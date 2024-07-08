--[[ ReceiveBuffer.lua © Penguin_Spy 2024
  A buffer class specifically for reading packet data received from the client.

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

local string_byte = string.byte
local string_sub = string.sub
local string_unpack = string.unpack

---@class ReceiveBuffer
local ReceiveBuffer = {}

-- Appends the data to the end of the buffer.
---@param data string
function ReceiveBuffer:append(data)
  self.data = self.data .. data
end

-- Splits off and returns the first byte of the buffer.
---@return integer
function ReceiveBuffer:byte()
  local data = string_byte(self.data)
  self.data = string_sub(self.data, 2)
  return data
end

-- Returns the first byte of the buffer without modifying it.
---@return integer
function ReceiveBuffer:peek_byte()
  return string_byte(self.data)
end

-- Debugging function; returns the data in the buffer as a hex string.
---@param length integer?   How many bytes to display. If not given, the whole buffer is returned.
---@return string
function ReceiveBuffer:dump(length)
  local data = length and string_sub(self.data, 1, length) or self.data
  return (data:gsub(".", function(char) return string.format("%02X", char:byte()) end))
end

-- Splits off and returns a sequence of bytes from the start of the buffer.
---@param length integer  How many bytes to return.
---@return string
function ReceiveBuffer:read(length)
  local data = string_sub(self.data, 1, length)
  self.data = string_sub(self.data, length + 1)
  return data
end

-- Sets the position of the "end boundary".<br>
-- A subsequent call to `ReceiveBuffer:read_to_end()` will return all remaining data up to the end boundary.<br>
---@see ReceiveBuffer.read_to_end
---@param length integer
function ReceiveBuffer:set_end(length)
  -- (END - OLD) + new = n
  self.end_boundary = length - #self.data
end

-- Reads all data up to the "end boundary".<br>
-- The calculation will be incorrect if any data is appended to the buffer between the two calls.<br>
---@see ReceiveBuffer.set_end
function ReceiveBuffer:read_to_end()
  -- (end - old) + NEW = n
  return self:read(self.end_boundary + #self.data)
end

-- Attempts to read a VarInt from the start of the buffer.
---@return integer?
function ReceiveBuffer:try_read_varint()
  local value = 0
  for i = 0, 5 * 7, 7 do
    local b = self:byte()
    if not b then return end
    value = value + ((b & 0x7F) << i)
    if (b & 0x80) ~= 0x80 then
      return value
    end
  end
  error("too long or invalid VarInt")
end

-- Reads a VarInt from the start of the buffer.
---@return integer
function ReceiveBuffer:varint()
  local value = self:try_read_varint()
  if not value then error("reached end of buffer while reading VarInt") end
  return value
end

-- Reads a String from the start of the buffer.
---@return string
function ReceiveBuffer:string()
  local length = self:try_read_varint()
  if not length then error("reached end of buffer while reading String") end
  return self:read(length)
end

-- Reads a boolean from the buffer.
---@return boolean
function ReceiveBuffer:boolean()
  return self:byte() ~= 0
end

-- Reads a Short from the start of the buffer.
---@return integer
function ReceiveBuffer:short()
  local hi, lo = string_byte(self.data, 1, 2)
  self.data = string_sub(self.data, 3)
  return (hi << 8) + lo
end

-- Reads an Int from the start of the buffer.
---@return integer
function ReceiveBuffer:int()
  local hi, gh, lo, w = string_byte(self.data, 1, 4)
  self.data = string_sub(self.data, 5)
  return (hi << 24) + (gh << 16) + (lo << 8) + w
end

-- Reads a Float from the start of the buffer.
---@return number
function ReceiveBuffer:float()
  return (string_unpack(">f", self:read(4)))
end

-- Reads a Double from the start of the buffer.
---@return number
function ReceiveBuffer:double()
  return (string_unpack(">d", self:read(8)))
end

-- Reads a Long from the start of the buffer.
---@return integer
function ReceiveBuffer:long()
  return (string_unpack(">i8", self:read(8)))
end

-- Reads a Position from the start of the buffer.
---@return blockpos
function ReceiveBuffer:position()
  local data = string_unpack(">I8", self:read(8))
  local x = data >> 38
  local y = data << 52 >> 52
  local z = data << 26 >> 38
  if x >= 1 << 25 then x = x - (1 << 26) end
  if y >= 1 << 11 then y = y - (1 << 12) end
  if z >= 1 << 25 then z = z - (1 << 26) end
  return { x = x, y = y, z = z }
end

local mt = { __index = ReceiveBuffer }

-- Constructs a new ReceiveBuffer
---@return ReceiveBuffer
return function()
  return setmetatable({ data = "" }, mt)
end
