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
local Registry = require("quasar.Registry")

local block_state_map = Registry.get_block_state_map()
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


---@class (exact) ChunkProvider.superflat_options
--- a list of block state and height pairs, in order from bottom to top of the chunk
---@field layers ([identifier, integer])[]
--- the biome for all chunks
---@field biome identifier
--- the number of subchunks in this chunk; must match the height of the dimension's type
---@field subchunk_height integer
--- unused
----@field size {x: integer, z: integer}

--- test
---@param options ChunkProvider.superflat_options
---@return ChunkProvider
function ChunkProvider.superflat(options)
  error("superflat generator not implemented")
  -- create subchunks from bottom up
  --[=[local sections, current_height = {}, 0
  for _, layer in pairs(options.layers) do
    local state, height = block_state_map[layer[1]], layer[2]
    -- local row =
  end]=]

  -- create list of block states for each individual layer
  --[[local layers = {}
  for _, layer in pairs(options.layers) do
    for _ = 1, layer[2] do
      table.insert(layers, layer[1])
    end
  end]]

end


return ChunkProvider
