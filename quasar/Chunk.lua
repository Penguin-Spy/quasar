--[[ chunk.lua © Penguin_Spy 2024-2025
  Represents a single chunk (a 16x16xheight column of blocks).
  Stores block data as a list of Longs (lua integers) as its a decent middleground
  between memory efficiency and quick reading/writing of blocks.

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
local Registry = require "quasar.Registry"
local util = require "quasar.util"

local biome_registry_map = Registry.get_map("minecraft:worldgen/biome")

---@class Chunk.subchunk
---@field block_count integer
---@field bits_per_entry integer
---@field palette {[integer]:integer}           Map from palette index (0-based index) to block state
---@field palette_contents {[integer]:integer}  Map from block state to palette index
---@field data integer[]

---@class Chunk
---@field subchunks Chunk.subchunk[]
local Chunk = {}


-- increases the bits_per_entry by 1 and reshuffles data to fit
local function expand_subchunk_palette(subchunk)
  -- TODO: correctly resize from single value (bpe=0) subchunks too
  local old_bits_per_entry = subchunk.bits_per_entry
  local old_entries_per_long = 64 // old_bits_per_entry
  local old_data = subchunk.data

  local new_bits_per_entry = old_bits_per_entry + 1
  local new_entries_per_long = 64 // new_bits_per_entry
  local new_data = {}

  local old_mask = ((1 << old_bits_per_entry)-1)
  for entry = 0, 4095 do
    local old_long_index = (entry // old_entries_per_long) + 1
    local old_long_offset = (entry % old_entries_per_long) * old_bits_per_entry
    local new_long_index = (entry // new_entries_per_long) + 1
    local new_long_offset = (entry % new_entries_per_long) * new_bits_per_entry

    local palette_entry = old_data[old_long_index] & (old_mask << old_long_offset)

    new_data[new_long_index] = (new_data[new_long_index] or 0) | (palette_entry << new_long_offset)
  end

  subchunk.data = new_data
  subchunk.bits_per_entry = new_bits_per_entry
end


---@param pos blockpos    The absolute position in the world (this method converts to the position in the chunk internally)
---@param state integer   The block state ID to set at the position
function Chunk:set_block(pos, state)
  -- TODO: adjust for bottom of world not always being at y=0
  local subchunk = self.subchunks[(pos.y // 16) + 5] ---@cast subchunk -nil

  -- ensure the state is in the palette
  if not subchunk.palette_contents[state] then
    -- add to palette
    table.insert(subchunk.palette, state)
    subchunk.palette_contents[state] = #subchunk.palette
    -- expand if necessary
    if #subchunk.palette + 1 > 1<<subchunk.bits_per_entry then
      expand_subchunk_palette(subchunk)
    end
  end

  local palette_entry = subchunk.palette_contents[state]

  local entries_per_long = 64 // subchunk.bits_per_entry
  local entry = (pos.x%16) + (pos.z%16)*16 + (pos.y%16)*256                 -- index of the entry for this block position
  local long_index = (entry // entries_per_long) + 1                        -- index of the long for the entry (+1 for Lua indexing)
  local long_offset = (entry % entries_per_long) * subchunk.bits_per_entry  -- offset of bits into the long

  subchunk.data[long_index] = subchunk.data[long_index]
    & ~(((1 << subchunk.bits_per_entry)-1) << long_offset)
    | (palette_entry << long_offset)
end


-- Returns this chunk's raw data ready for sending over the network.
---@return string
function Chunk:get_data()
  -- have to have our own buffer so that the packet sending function can get the length of the data :/
  local buffer = SendBuffer()
  for _, subchunk in pairs(self.subchunks) do
    buffer:short(16 * 16 * 16)            -- block count

    buffer:byte(subchunk.bits_per_entry)  -- block palette bits per entry
    if subchunk.bits_per_entry > 0 then
      buffer:varint(#subchunk.palette + 1)      -- # of palette entries
      for i = 0, #subchunk.palette do
        buffer:varint(subchunk.palette[i])
      end

      for _, data_entry in pairs(subchunk.data) do
        buffer:long(data_entry)
      end

    else -- single valued
      buffer:varint(subchunk.palette[0])
    end

    buffer:byte(0)    -- biome palette type 0 (single valued)
    buffer:varint(biome_registry_map["minecraft:plains"])  -- single value: the id of minecraft:plains
  end
  return buffer:concat_with_length()
end

-- creates a chunk from a list of chunk sections (subchunks)<br>
-- the number of chunk sections determines the height of this chunk; subchunks are ordered from bottom to top
---@param sections {block_states:integer[], block_palette:{[integer]:integer}}[] block_states is 1-based (list of longs), block_palette is 0-based
---@return Chunk
local function new_from_data(sections)
  ---@type Chunk.subchunk[]
  local subchunks = {}
  for i = 1, #sections do
    local section = sections[i]
    local palette_length, bpe = #section.block_palette + 1, nil
    if palette_length == 1 then
      bpe = 0 -- single valued
    else
      bpe = math.max(math.ceil(math.log(palette_length, 2)), 4)
      if bpe > 8 then
        error("too large bits per entry: " .. tostring(bpe))
      end
    end
    ---@type Chunk.subchunk
    local subchunk = {
      block_count = 0,
      bits_per_entry = bpe,
      -- copy palette & data to give each chunk a unique table
      palette = util.copy(section.block_palette),
      palette_contents = {},
      -- block_states is nil when the section is a single value
      data = section.block_states and util.copy(section.block_states)
    }
    for index, state in pairs(subchunk.palette) do
      subchunk.palette_contents[state] = index
    end
    table.insert(subchunks, subchunk)
  end
  return setmetatable({
    subchunks = subchunks
  }, { __index = Chunk })
end

-- Precomputes and creates a chunk object that is entirely air.
---@return Chunk
local function new_empty(height)
  local buffer = SendBuffer()
  for _ = 1, height do
    -- array of chunk section
    buffer:short(0)         -- block count
        :byte(0):varint(0)  -- block palette type 0, (single valued), single value: 0 (air)
        :byte(0):varint(0)  -- biome palette type 0 (single valued), single value: 0  (whatever the 1st biome in the registry is)
  end
  local data = buffer:concat_with_length()
  return {
    get_data = function() return data end
  } --[[@as Chunk]]
end

return {
  new_from_data = new_from_data,
  new_empty = new_empty
}
