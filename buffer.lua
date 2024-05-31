local string_byte = string.byte
local string_sub = string.sub

---@class Buffer
local Buffer = {}

-- Appends the data to the end of the buffer.
---@param data string
function Buffer:append(data)
  self.data = self.data .. data
end

-- Splits off and returns the first byte of the buffer.
---@return integer
function Buffer:byte()
  local data = string_byte(self.data, 1)
  self.data = string_sub(self.data, 2)
  return data
end

-- Returns the first byte of the buffer without modifying it.
---@return integer
function Buffer:peek_byte()
  return string_byte(self.data, 1)
end

-- Debugging function; returns the data in the buffer as a hex string.
---@param length integer?   How many bytes to display. If not given, the whole buffer is returned.
---@return string
function Buffer:dump(length)
  local data = length and string_sub(self.data, 1, length) or self.data
  return (data:gsub(".", function(char) return string.format("%02X", char:byte()) end))
end

---@param length integer  How many bytes to return.
---@return string
function Buffer:read(length)
  local data = string_sub(self.data, 1, length)
  self.data = string_sub(self.data, length + 1)
  return data
end

-- Attempts to read a VarInt from the start of the buffer.
---@return integer?
function Buffer:try_read_varint()
  local value = 0
  for i = 0, 3 * 7, 7 do
    local b = self:byte()
    if not b then return end
    value = value + ((b & 0x7F) << i)
    if (b & 0x80) ~= 0x80 then
      return value
    end
  end
  error("too long or invalid VarInt")
end

-- Attempts to read a String from the start of the buffer.
---@return string?
function Buffer:try_read_string()
  local length = self:try_read_varint()
  if not length then return end
  return self:read(length)
end

-- Static method that encodes a value as a VarInt.
---@param value integer
---@return string
local function encode_varint(value)
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
  return data
end

-- Static method that encodes a string.
---@param str string
---@return string
local function encode_string(str)
  return encode_varint(#str) .. str
end

-- Constructs a new Buffer
---@return Buffer
local function new()
  ---@type Buffer
  local self = { data = "" }
  setmetatable(self, { __index = Buffer })
  return self
end

return {
  new = new,
  encode_varint = encode_varint,
  encode_string = encode_string
}
