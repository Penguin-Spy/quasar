--[[ Anvil.lua © Penguin_Spy 2025
  handles loading & saving Anvil chunk files (https://minecraft.wiki/w/Region_file_format)

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.

  The Covered Software may not be used as training or other input data
  for LLMs, generative AI, or other forms of machine learning or neural
  networks.
]]

local zlib = require "quasar.zlib"
local NBT  = require "quasar.NBT"
local Chunk = require "quasar.Chunk"
local Registry = require "quasar.Registry"

local unpack = string.unpack
local block_state_map = Registry.get_block_state_map()

local Anvil = {}

---@class Anvil.Region
---@field chunk_offsets integer[]
---@field file file
local Region = {}

function Region:get_chunk(x, z)
  local offset = self.chunk_offsets[((x % 32) + (z % 32) * 32) + 1]
  if offset == 0 then return false end

  self.file:seek("set", offset)
  local length = unpack(">I4", self.file:read(4))
  local compression = unpack(">I1", self.file:read(1))
  if compression ~= 2 then
    error(string.format("cannot read non-zlib compressed chunk at (%i, %i) type: %i", x, z, compression))
  end

  local data = zlib.decompress(self.file:read(length-1))
  local nbt = NBT.parse(data, 1, false)
  if nbt["Status"] ~= "minecraft:full" then
    print(string.format("cannot read chunk at (%i, %i) with incomplete generation: '%s'", x, z, nbt["Status"]))
    return false
  end

  local sections = {}
  for i, section_data in ipairs(nbt["sections"]) do
    local block_palette = {}
    for j, entry in pairs(section_data["block_states"]["palette"]) do
      local name = entry["Properties"] and Registry.get_block_state_with_properties(entry["Name"], entry["Properties"])
          or entry["Name"]
      local id = block_state_map[name]
      block_palette[j-1] = id
    end
    sections[i] = {block_states = section_data["block_states"]["data"], block_palette = block_palette}
  end

  return Chunk.new_from_data(sections)
end

-- Opens a file as a region file
---@return Anvil.Region
function Anvil.open(filename)
  local f = assert(io.open(filename, "rb"))
  local chunk_offsets = {}
  for i = 1, 1024 do
    chunk_offsets[i] = unpack(">I3", f:read(3)) * 0x1000
    ---@diagnostic disable-next-line: discard-returns
    f:read(1) -- discard the sector count value
  end
  return setmetatable({file = f, chunk_offsets = chunk_offsets}, {__index = Region})
end

return Anvil
