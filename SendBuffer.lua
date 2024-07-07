--[[ SendBuffer.lua © Penguin_Spy 2024
  A buffer class specifically for writing packet data to be sent out.
  Writing data to it adds the binary strings to a table that is concatenated when the buffer is complete.
  This avoids repeated string concatenation `..` which is slow in large amounts.

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

local insert, concat = table.insert, table.concat
local string_pack, string_char = string.pack, string.char

---@class SendBuffer
local SendBuffer = {}

-- Encodes a value as a VarInt.
---@param value integer
function SendBuffer:write_varint(value)
  local data = ""
  repeat
    local byte = value & 0x7F
    if value > 0x7F then
      data = data .. string.char(byte | 0x80)
      value = value >> 7
    else
      data = data .. string.char(byte)
      break
    end
  until false
  insert(self, data)
end

-- Encodes a string.
---@param str string
function SendBuffer:write_string(str)
  self:write_varint(#str)
  insert(self, str)
end

-- Appends raw data to the buffer.
---@param data string
function SendBuffer:write_raw(data)
  insert(self, data)
end

-- Encodes a Byte.
---@param value integer
function SendBuffer:write_byte(value)
  insert(self, string_char(value))
end

-- Encodes a Short.
---@param value integer
function SendBuffer:write_short(value)
  insert(self, string_pack(">i2", value))
end

-- Encodes an Int.
---@param value integer
function SendBuffer:write_int(value)
  insert(self, string_pack(">i4", value))
end

-- Encodes a Long.
---@param value integer
function SendBuffer:write_long(value)
  insert(self, string_pack(">i8", value))
end

-- Encodes a Position.
---@param pos blockpos
function SendBuffer:write_position(pos)
  insert(self, string_pack(">I8", ((pos.x & 0x3FFFFFF) << 38) | ((pos.z & 0x3FFFFFF) << 12) | (pos.y & 0xFFF)))
end

-- Concatenates all data in this buffer and returns it as a string.
---@return string
function SendBuffer:concat()
  return concat(self)
end

local mt = { __index = SendBuffer }
-- Constructs a new SendBuffer
---@return SendBuffer
function SendBuffer.new()
  return setmetatable({}, mt)
end

return SendBuffer
