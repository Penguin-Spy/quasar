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

---@param value integer
---@return string
local function varint(value)
  local data = ""
  while true do
    local byte = value & 0x7F
    if value > 0x7F then
      data = data .. string_char(byte | 0x80)
      value = value >> 7
    else
      return data .. string_char(byte)
    end
  end
end

-- Encodes a value as a VarInt.
---@param value integer
function SendBuffer:varint(value)
  insert(self, varint(value))
  return self
end

-- Encodes a string.
---@param str string
function SendBuffer:string(str)
  insert(self, varint(#str))
  insert(self, str)
  return self
end

-- Appends raw data to the buffer.
---@param data string
function SendBuffer:raw(data)
  insert(self, data)
  return self
end

-- Encodes a Byte.
---@param value integer
function SendBuffer:byte(value)
  insert(self, string_char(value))
  return self
end

-- Encodes a boolean (a Byte of `0` or `1`).
---@param value boolean
function SendBuffer:boolean(value)
  insert(self, string_char(value and 1 or 0))
  return self
end

-- Encodes a Short.
---@param value integer
function SendBuffer:short(value)
  insert(self, string_pack(">i2", value))
  return self
end

-- Encodes an Int.
---@param value integer
function SendBuffer:int(value)
  insert(self, string_pack(">i4", value))
  return self
end

-- Encodes a Long.
---@param value integer
function SendBuffer:long(value)
  insert(self, string_pack(">i8", value))
  return self
end

-- Encodes a Position.
---@param pos blockpos
function SendBuffer:position(pos)
  insert(self, string_pack(">I8", ((pos.x & 0x3FFFFFF) << 38) | ((pos.z & 0x3FFFFFF) << 12) | (pos.y & 0xFFF)))
  return self
end

-- Appends the passed values packed according to the format string `fmt`. <br>
---@see string.pack
---@param fmt string
---@param ... string|number
function SendBuffer:pack(fmt, ...)
  insert(self, string_pack(fmt, ...))
  return self
end

-- Concatenates all data in this buffer and returns it as a string. <br>
-- Does not modify the buffer's contents.
---@return string
function SendBuffer:concat()
  return concat(self)
end

-- Concatenates all data in this buffer, prepends it with its length in bytes encoded as a VarInt, and returns it as a string. <br>
-- Does not modify the buffer's contents.
---@return string
function SendBuffer:concat_with_length()
  local data = concat(self)
  return varint(#data) .. data
end

-- Concatenates all data in this buffer, prepends it with a VarInt, and returns it as a string. <br>
-- Does not modify the buffer's contents.
---@param value integer
---@return string
function SendBuffer:concat_and_prepend_varint(value)
  local data = concat(self)
  return varint(value) .. data
end


local mt = { __index = SendBuffer }
-- Constructs a new SendBuffer. <br>
-- All methods return the buffer object so that they may be chained.
---@return SendBuffer
return function()
  return setmetatable({}, mt)
end
