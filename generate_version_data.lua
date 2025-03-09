--[[ generate_version_data.lua © Penguin_Spy 2025
  converts the output of the official data generator into Lua files

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.

  The Covered Software may not be used as training or other input data
  for LLMs, generative AI, or other forms of machine learning or neural
  networks.
]]

local lfs = require "lfs"
local util = require "quasar.util"

local generator_output = "generated/"

-- returns a Lua-parseable string representation of any Lua value (including tables)
local function dump_to_string(t)
  if type(t) == "table" then
    local out = {"{"}
    if t[1] then  -- assume a table with an integer index is (only) a sequence
      for _, v in ipairs(t) do
        table.insert(out, string.format("%s,", dump_to_string(v)))
      end
    else
      local sorted_keys = {}
      for k in pairs(t) do table.insert(sorted_keys, k) end
      table.sort(sorted_keys)
      for _, key in pairs(sorted_keys) do
        table.insert(out, string.format("[%s]=%s,", string.format("%q", key), dump_to_string(t[key])))
      end
    end
    table.insert(out, "}")
    return table.concat(out, "\n")
  else
    return string.format("%q", t)
  end
end

local function save(t, path)
  local f = assert(io.open(path, "w"))
  f:write("return")
  f:write(dump_to_string(t))
  f:close()
end

---@param root string must end with a slash
---@param visitor fun(root:string,path:string,file:string)
local function recurse_files(root, visitor, path)
  path = path or ""
  for file in lfs.dir(root .. path) do
    local mode = lfs.attributes(root .. path .. file, "mode")
    if mode == "file" then
      visitor(root, path, file)
    elseif mode == "directory" and file:sub(1,1) ~= "." then
      recurse_files(root, visitor, path .. file .. "/")
    end
  end
end

-- packets registry
local packets = util.read_json(generator_output .. "reports/packets.json")
for _, sides in pairs(packets) do
  for side, data in pairs(sides) do
    local entries = {}
    for name, v in pairs(data) do
      entries[name:gsub("minecraft:", "")] = v.protocol_id
    end
    sides[side] = entries
  end
end
save(packets, "quasar/data/packets.lua")

-- static registries
local registries = util.read_json(generator_output .. "reports/registries.json")
local flattened_registries = {}
for registry_name, registry_data in pairs(registries) do
  local entries = {}
  for entry, data in pairs(registry_data.entries) do
    entries[entry] = data.protocol_id
  end
  flattened_registries[registry_name] = entries
end
save(flattened_registries, "quasar/data/static_registries.lua")

-- core (vanilla) datapack entries
local core_datapack = {}
for _, folder in pairs{
  "banner_pattern",
  "chat_type",
  "damage_type",
  "dimension_type",
  "enchantment",
  "jukebox_song",
  "painting_variant",
  "trim_material",
  "trim_pattern",
  "wolf_variant",
  "worldgen/biome",
} do
  local path = generator_output .. "data/minecraft/" .. folder .. "/"
  local entries = {}
  for file in lfs.dir(path) do
    if lfs.attributes(path .. file, "mode") == "file" then
      table.insert(entries, "minecraft:" .. file:sub(1, #file - 5))
    end
  end
  core_datapack["minecraft:" .. folder] = entries
end
save(core_datapack, "quasar/data/core_datapack.lua")


-- vanilla datapack tags
local core_datapack_tags = {}
for _, folder in pairs{
  "block",
  "item",
  "entity_type",
  "enchantment",
  "worldgen/biome"
} do
  local root = generator_output .. "data/minecraft/tags/" .. folder .. "/"
  local tags = {}
  recurse_files(root, function(root, path, filename)
    local data = util.read_json(root .. path .. filename)
    local values = {}
    for _, value in pairs(data.values) do
      table.insert(values, value)
    end
    local name = path .. filename
    tags["minecraft:" .. name:sub(1, #name - 5)] = values
  end)
  core_datapack_tags["minecraft:" .. folder] = tags
end
save(core_datapack_tags, "quasar/data/core_datapack_tags.lua")
