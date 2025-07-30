--[[ registry.lua © Penguin_Spy 2024-2025
  the registry stores all data that can be normally modified by datapacks,
  as well as the mappings between identifiers and network integer ids.

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.

  The Covered Software may not be used as training or other input data
  for LLMs, generative AI, or other forms of machine learning or neural
  networks.
]]

local SendBuffer = require "quasar.SendBuffer"
local util = require "quasar.util"

local packets = require "quasar.data.packets"
local REGISTRY_DATA_PACKET_ID <const> = packets.configuration.clientbound["registry_data"]
local UPDATE_TAGS_PACKET_ID <const> = packets.configuration.clientbound["update_tags"]

local Registry = {}

-- count number of keys in a table that isn't a sequence (i really wish this was a c function provided by lua)
local function count_table_entries(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

-- Converts the table form of a block to its block state string (properties sorted lexicographically). <br>
-- **This isn't particularly efficient**; block states should be referenced directly by string or network id whenever possible.
---@param name identifier
---@param properties table<string,string|integer|boolean> all properties must be specified
function Registry.get_block_state_with_properties(name, properties)
  local sorted_keys = {}
  for property in pairs(properties) do
    table.insert(sorted_keys, property)
  end
  table.sort(sorted_keys)
  local property_list = {}
  for _, key in ipairs(sorted_keys) do
    table.insert(property_list, key .. "=" .. properties[key])
  end
  return name .. "[" .. table.concat(property_list, ",") .. "]"
end

--[[
vanilla generated/reports:
  blocks.json:      all block states w/ properties; need to process to make the block state map
  commands.json:    not implemented yet, also we probably don't need it anyways (it's just vanilla commands)
  datapack.json:    maybe useful for automatically determining what should be read by generate_version_data.lua
  items.json:       default components, no ids
  packets.json:     not relevant for user code, used entirely by Connection
  registries.json:  all static registry maps

map:  identifier <-> id
  everything in registries.json
  block states
data: identifier -> data (or 'true' to use vanilla data)
  data pack data
tag:  identifier -> list of identifier
  data pack tags

-- order of operations:

on require:
  load static registry data and create maps for them
    freeze these maps right away
  load core datapack data and add to data
    create empty maps so other files can create local references
  load core datapack tags and add to tags

(user code modifies registry as necessary)

on finalize:
  freeze data maps, data & tags
  generate network representation of data & tags
  generate 2-way maps for data and add to maps (and freeze them)
]]

---@type table<identifier, table<identifier,integer> & table<integer,identifier>>
local maps = {}
---@type table<identifier, table<identifier, table|true>>
local datapack = {}
---@type table<identifier, table<identifier, identifier[]>>
local tags = require "quasar.data.core_datapack_tags"
---@type table<integer,{[1]:string,[2]:true?,[string]:string}> & table<identifier,integer>
local block_state_map = require "quasar.data.blocks"

-- Gets the registry map for the given category. <br>
-- A registry map is a 2-way map between an identifier and its integer network id. <br>
-- The map for types that are specified in the registry data tables will be **empty** until after
-- the registry is finalized.
---@param category identifier
---@return table<identifier,integer> & table<integer,identifier>
function Registry.get_map(category)
  return maps[category] or error(string.format("no registry map for category '%s'", category))
end

-- Gets the registry data table for the given category. <br>
-- The registry data table stores data for what datapacks can normally modify (biomes, armor trim, mob variants, etc.)
---@param category identifier
---@return table<identifier, table|true>
function Registry.get_data(category)
  return datapack[category] or error(string.format("no registry data table for category '%s'", category))
end

-- Gets the registry tags list for the given category. <br>
-- The registry tags list is a table of tag name to tag entries for the given type.
---@param category identifier
---@return table<identifier, identifier[]>
function Registry.get_tags(category)
  return tags[category] or error(string.format("no registry tags for category '%s'", category))
end

-- Gets the map for block states. <br>
-- Indexing with the block state integer network id retrieves the `block`. <br>
-- Indexing with a block's identifier (`minecraft:stone`) retrieves the network id of its default state. <br>
-- Indexing with a block state string (`minecraft:note_block[instrument=harp,note=0,powered=true]`, with properties in lexicographical order)
--  retrieves the network id of the specified state.
function Registry.get_block_state_map()
  return block_state_map
end

--= load initial registry contents =--

-- load static registry data and create maps for them
-- freeze these maps right away
for category, data in pairs(require "quasar.data.static_registries") do
  local map = {}
  for identifier, id in pairs(data) do  -- network ids are 0-based
    map[id-1] = identifier
    map[identifier] = id-1
  end
  maps[category] = util.freeze(map, string.format("cannot modify contents of the static registry map '%s'", category))
end

-- load block states & generate string -> id references
local block_state_string_mappings = {}
for id, block in pairs(block_state_map --[[@as table<integer,{[1]:string,[2]:true?}>]]) do
  util.freeze(block, "cannot modify block data retrieved from the block state map")
  local properties = {}
  for k, v in pairs(block) do
    if type(k) == "string" then
      properties[k] = v
    end
  end
  local name = Registry.get_block_state_with_properties(block[1], properties)
  block_state_string_mappings[name] = id
  if block[2] then -- if default, then set the mapping for the name without properties as well
    block_state_string_mappings[block[1]] = id
  end
end
-- can't modify the table while pairs-ing it
for k, v in pairs(block_state_string_mappings) do
  block_state_map[k] = v
end
util.freeze(block_state_map, "cannot modify contents of the block state map", "no entry in block state map")

-- load core datapack data and add to data
-- create empty maps so other files can create local references
for category, entries in pairs(require "quasar.data.core_datapack") do
  datapack[category] = {}
  for _, entry in pairs(entries) do
    datapack[category][entry] = true
  end
  maps[category] = {}
end

-- include server links in the pause screen additions tag by default
tags["minecraft:dialog"]["minecraft:pause_screen_additions"] = {"minecraft:server_links"}


--= functions for finalizing the registry contents =--

---@type boolean
local registry_finalized = false

-- a list of precomputed Registry Data packets
---@type string[]
local network_registry_packets = {}
-- the precomputed Update Tags packet
---@type string
local network_tags_packet

-- recursively flattens a tag's entries; prevents circular references
---@param tag_category string               the category of tag (entity, block, etc.)
---@param identifier string                 the identifier of this tag
---@param previous_tags table<string, true> a set of previously visited tags
local function flatten_tag(tag_category, identifier, previous_tags)
  if previous_tags[identifier] then
    local members = {} for k in pairs(previous_tags) do table.insert(members, k) end
    error(string.format("circular dependency in %s tag '%s', members: %s", tag_category, identifier, table.concat(members, ", ")))
  end
  previous_tags[identifier] = true

  local values = tags[tag_category][identifier]
  for i, value in ipairs(values) do -- ipairs will iterate values added at the end during the loop
    if value:sub(1,1) == "#" then
      local referenced_values = flatten_tag(tag_category, value:sub(2), previous_tags)
      table.remove(values, i) -- remove the "#tag" reference itself
      for j = 1, #referenced_values do
        table.insert(values, i + j - 1, referenced_values[j])
      end
    end
  end
  if not getmetatable(values) then
    util.freeze(values, string.format("cannot modify contents of the registry tag list entry '%s' (category '%s') after finalization", identifier, tag_category))
  end
  previous_tags[identifier] = nil -- allow duplicate entries (allowed to load, might break network?)
  return values
end

-- Finalizes the contents of the registry; all registry maps, data tables, and tags become read-only after this is called. <br>
-- Generates the network representations of data tables & tags, and therefore creates the maps for entries in the data tables. <br>
-- Must be called before `Registry.get_network_data()` and `Registry.get_network_tags()`.
-- Repeated calls to `finalize()` are ignored.
function Registry.finalize()
  -- ignore extra calls
  if registry_finalized then return end
  registry_finalized = true

  -- generate maps & packets for data table entries
  for category, entries in pairs(datapack) do
    -- generate the order of the entries
    local entry_map = {} ---@type table<integer, identifier>
    for identifier, entry in pairs(entries) do
      table.insert(entry_map, identifier)
      if type(entry) == "table" then
        util.freeze(entry, string.format("cannot modify contents of the registry data table entry '%s' (category '%s') after finalization", identifier, category))
      end
      -- tables within the entry are not frozen. just don't modify them :)
    end
    util.freeze(entries, string.format("cannot modify contents of the registry data table '%s' after finalization", category))

    -- fill out the double map for the entries
    local map = maps[category]
    for id, identifier in pairs(entry_map) do -- network ids are 0-based
      map[id-1] = identifier
      map[identifier] = id-1
    end
    util.freeze(map, string.format("cannot modify contents of the registry map '%s' after finalization", category))

    -- then generate the packet
    local buffer = SendBuffer():string(category):varint(#entry_map)
    for _, identifier in ipairs(entry_map) do
      local entry = entries[identifier]
      if type(entry) == "table" then
        -- TODO: encode non-default data as NBT
        error("cannot encode non-default registry data yet")
      elseif entry == true then
        buffer:string(identifier):boolean(false)  -- no data (assumes client has core/vanilla data already)
      else
        error(string.format("registry data table entries must be a table or 'true', but entry '%s' (category '%s') is of type '%s'", identifier, category, type(entry)))
      end
    end
    table.insert(network_registry_packets, buffer:concat_and_prepend_varint(REGISTRY_DATA_PACKET_ID))
  end

  -- flatten and freeze tags, and generate the update tags packet
  local buffer = SendBuffer():varint(count_table_entries(tags))
  for tag_category, entries in pairs(tags) do
    local map = maps[tag_category]
    buffer:string(tag_category):varint(count_table_entries(entries))

    for identifier, values in pairs(entries) do
      -- this intentionally modifies the tag tables
      flatten_tag(tag_category, identifier, {})

      buffer:string(identifier):varint(count_table_entries(values))
      for _, value in pairs(values) do
        buffer:varint(map[value])
      end
    end
    util.freeze(entries, string.format("cannot modify contents of the registry tag list '%s' after finalization", tag_category))
  end
  network_tags_packet = buffer:concat_and_prepend_varint(UPDATE_TAGS_PACKET_ID)
end

-- Returns the list of precomputed Registry Data packets
---@return string[]
function Registry.get_network_data()
  return registry_finalized and network_registry_packets or error("cannot get registry network data before the registry is finalized")
end

-- Returns the precomputed Update Tags packet
---@return string
function Registry.get_network_tags()
  return registry_finalized and network_tags_packet or error("cannot get registry network tags before the registry is finalized")
end

return Registry
