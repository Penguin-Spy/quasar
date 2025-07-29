--[[ ChunkProvider.lua © Penguin_Spy 2025
  functions for loading or generating chunks for a Dimension

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.

  The Covered Software may not be used as training or other input data
  for LLMs, generative AI, or other forms of machine learning or neural
  networks.
]]

local Chunk = require "quasar.Chunk"
local Anvil = require "quasar.Anvil"
local Registry = require "quasar.Registry"

local block_state_map = Registry.get_block_state_map()
local AIR_BLOCKSTATE = block_state_map["minecraft:air"]
local format, insert = string.format, table.insert

local ChunkProvider = {}

---@class ChunkProvider
--- loads the chunk
---@field load fun(self: ChunkProvider, x: integer, z: integer): Chunk|false
--- saves the chunk. only present on the region chunkprovider by default
---@field save fun(self: ChunkProvider, x: integer, z: integer, chunk: Chunk)?
--- used by `"load_all"` loading mode on the Dimension
---@field size {dx: integer, dz: integer}?


---@class (exact) ChunkProvider.region : ChunkProvider
---@field path string
---@field regions table<string, Anvil.Region>

---@param self ChunkProvider.region
---@param x integer
---@param z integer
---@return Chunk|false
local function region_provider_load(self, x, z)
  if math.abs(x) > 5 or math.abs(z) > 5 then return false end
  local region_x, region_z = x // 32, z // 32
  local region_name = format("%sr.%d.%d.mca", self.path, region_x, region_z)
  local region = self.regions[region_name]
  if not region then
    -- TODO: consider when to close the region (ever? if all chunks from it are loaded? if all chunks the dimension wants are loaded?)
    region = Anvil.open(region_name)
    self.regions[region_name] = region
  end

  return region:get_chunk(x, z)
end

---@class (exact) ChunkProvider.region_options
--- the path to the region files, "r.(x).(z).mca" is appended and loaded as an Anvil region file
---@field path string
--- NOT YET IMPLEMENTED:
--- optional, limits area of chunks to be loaded
----@field size {x: integer, z: integer}
--- optional, offset in the region files to load chunk from (i.e. loading 0,0 in the Dimension grabs 0,2 from the regions)
----@field size {x: integer, z: integer}
--- the behavior for saving chunks
----@field save_mode "immutable" | "save" | "ephemeral"
--- optional, only loads chunks and only those that have no data in the region files and are within the size/offset area
----@field generator ChunkProvider

--- A chunk provider that loads chunks from a directory of Anvil region files.
---@param options ChunkProvider.region_options
---@return ChunkProvider.region
function ChunkProvider.region(options)
  assert(options.path and type(options.path) == "string", "region files path is required!")

  return {
    regions = {},
    path = options.path,
    load = region_provider_load
  }
end


local function superflat_provider_load(self, chunk_x, chunk_z)
  return Chunk.new_from_data(self.sections)
end

---@class (exact) ChunkProvider.superflat_options
--- a list of block state and height pairs, in order from bottom to top of the chunk
---@field layers ([identifier, integer])[]
--- (unused) the biome for all chunks
----@field biome identifier
--- the number of subchunks in this chunk; must match the height of the dimension's type
---@field subchunk_height integer
--- unused
----@field size {x: integer, z: integer}

--- A chunk provider that generates a superflat world.
---@param options ChunkProvider.superflat_options
---@return ChunkProvider
function ChunkProvider.superflat(options)
  local sections, section_count = {}, 0

  local layer_index = 1
  -- blockstate network id, long of 16 palette indexes,
  local blockstate, blockstate_long, remaining_layer_height = nil, nil, 0

  -- paletted block states long data array, map of block state id -> palette index
  local block_states, palette_contents, palette_index = {}, {}, 0
  local remaining_section_height = 16

  while true do
    local need_update_blockstate_palette = false

    -- get next section if necessary
    if remaining_section_height <= 0 then
      local block_palette = {}
      for blockstate_id, index in pairs(palette_contents) do
        block_palette[index] = blockstate_id
      end
      insert(sections, {
        block_states = block_states,
        block_palette = block_palette
      })
      -- the only break condition; we've filled up all the sections we need to
      if #sections == options.subchunk_height then break end

      block_states, palette_contents, palette_index = {}, {}, 0
      remaining_section_height = 16
      need_update_blockstate_palette = true -- palette was cleared
    end

    -- get next (or first) layer if necessary
    if remaining_layer_height <= 0 then
      local layer = options.layers[layer_index]
      if layer then
        layer_index = layer_index + 1
        blockstate = block_state_map[layer[1]]
        remaining_layer_height = layer[2]
      else -- no more layers, fill with air
        blockstate = AIR_BLOCKSTATE
        remaining_layer_height = 16
      end

      need_update_blockstate_palette = true -- blockstate was changed
    end

    if need_update_blockstate_palette then
      -- add blockstate into palette (if not there)
      local blockstate_index = palette_contents[blockstate]
      if not blockstate_index then
        blockstate_index = palette_index
        palette_contents[blockstate] = palette_index
        palette_index = palette_index + 1
        assert(blockstate_index <= 15, "cannot use more than 4 bits for a palette index!?")
      end

      -- calculate new long of palette index
      blockstate_long = 0
      for i = 0, 15*4, 4 do
        blockstate_long = blockstate_long | (blockstate_index << i)
      end
    end

    local height = math.min(remaining_section_height, remaining_layer_height)

    -- insert longs into section blockstates
    for _ = 1, height do  -- y layers
      for _ = 1, 16 do    -- 16 z values
        insert(block_states, blockstate_long) -- each long is 16 x values
      end
    end

    remaining_layer_height = remaining_layer_height - height
    remaining_section_height = remaining_section_height - height
  end

  return {
    sections = sections,
    load = superflat_provider_load
  }
end


return ChunkProvider
