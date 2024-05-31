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

function Buffer:read(length)
  local data = string_sub(self.data, 1, length)
  self.data = string_sub(self.data, length + 1)
  return data
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
  new = new
}
