--[[ chunk.lua © Penguin_Spy 2024
  Represents a single chunk (a 16x16xheight column of blocks).
  Stores block data as a list of Longs (lua integers) as its a decent middleground
  between memory efficiency and quick reading/writing of blocks.

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

local SendBuffer = require 'SendBuffer'

---@class Chunk.subchunk
---@field block_count integer
---@field bits_per_entry integer
---@field palette integer[]
---@field data integer[]

---@class Chunk
---@field subchunks Chunk.subchunk[]
local Chunk = {}



---@param pos blockpos    The absolute position in the world (this method converts to the position in the chunk internally)
---@param state integer   The block state ID to set at the position
function Chunk:set_block(pos, state)
  local subchunk = self.subchunks[(pos.y // 16) + 5]                      -- todo: adjust for bottom of world not always being at y=0
  local yz, x = ((pos.y % 16) * 16) + (pos.z % 16) + 1, (pos.x % 16) * 4  -- the +1 of yz is because Lua list indexes start at 1
  subchunk.data[yz] = subchunk.data[yz] & ~(0xf << x) | (state << x)
end


-- Returns this chunk's raw data ready for sending over the network.
---@return string
function Chunk:get_data()
  -- have to have our own buffer so that the packet sending function can get the length of the data :/
  local buffer = SendBuffer()
  for _, subchunk in pairs(self.subchunks) do
    buffer:short(16 * 16 * 16)            -- block count

    buffer:byte(subchunk.bits_per_entry)  -- block palette bits per entry
    buffer:varint(#subchunk.palette)      -- # of palette entries
    for _, palette_entry in pairs(subchunk.palette) do
      buffer:varint(palette_entry)
    end

    buffer:varint(#subchunk.data)  -- size of data array
    for _, data_entry in pairs(subchunk.data) do
      buffer:long(data_entry)
    end

    buffer:byte(0)    -- biome palette type 0 (single valued)
    buffer:varint(0)  -- single value: 0
    buffer:varint(0)  -- size of data array (0 for single valued)
  end
  return buffer:concat_with_length()
end

-- Internal method
---@param height integer  Number of subchunks in this chunk
---@return Chunk
local function new(height)
  ---@type Chunk.subchunk[]
  local subchunks = {}
  for i = 1, height do
    local data = {}
    for j = 1, 16 * 16 do  -- array of 256 Longs (data_size_as_longs)
      if i <= 8 then
        -- each Long is a line of 16 blocks along the X axis
        data[j] = ((j % 16) > 1) and 0x0111111111111110 or 0x2000000000000002
      else
        data[j] = 0
      end
    end
    table.insert(subchunks, {
      block_count = 0,
      bits_per_entry = 4,            --always 4 for now
      palette = { 0, 1, 2, 3, 4, 5, 6, 7, 15, 16, 17, 18, 19, 20, 21, 22 },
      data_size_as_longs = 16 * 16,  -- compute from bits_per_entry
      data = data
    })
  end
  ---@type Chunk
  local self = {
    subchunks = subchunks
  }
  setmetatable(self, { __index = Chunk })
  return self
end

-- Precomputes and creates a chunk object that is entirely air.
---@return Chunk
local function new_empty(height)
  local buffer = SendBuffer()
  for _ = 1, height do
    -- array of chunk section
    buffer:short(0)         -- block count
        :byte(0):varint(0)  -- block palette type 0, (single valued), single value: 0 (air)
        :varint(0)          -- size of data array (0 for single valued)
        :byte(0):varint(0)  -- biome palette type 0 (single valued), single value: 0  (whatever the 1st biome in the registry is)
        :varint(0)          -- size of data array (0 for single valued)
  end
  local data = buffer:concat_with_length()
  return {
    get_data = function() return data end
  }
end

return {
  new = new,
  new_empty = new_empty
}
