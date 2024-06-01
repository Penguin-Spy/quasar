--[[ nbt.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]


local NBT = {}

local string_char = string.char
local string_byte = string.byte
local string_sub = string.sub
local string_pack = string.pack

---@param value any
---@return string
local function infer_type(value)
  -- detect if this value has already been encoded (string that starts with a byte 0-12)
  if type(value) == "string" and (string_byte(value) or 13) <= 12 then
    return value
  end
  if type(value) == "string" then
    return NBT.string(value)
  elseif type(value) == "boolean" then
    return NBT.byte(value and 1 or 0)
  elseif type(value) == "table" then
    if value[1] then  -- numeric keys, is list
      return NBT.list(value)
    else              -- string keys, is compound
      return NBT.compound(value)
    end
  else
    error("cannot infer NBT type of '" .. type(value) .. "'")
  end
end

---@param value integer
function NBT.byte(value)
  return '\1' .. string_char(value & 0xFF)
end
---@param value integer
function NBT.short(value)
  return '\2' .. string_pack(">i2", value)
end
---@param value integer
function NBT.int(value)
  return '\3' .. string_pack(">i4", value)
end
---@param value number
function NBT.float(value)
  return '\5' .. string_pack(">f", value)
end
---@param value number
function NBT.double(value)
  return '\6' .. string_pack(">d", value)
end
---@param value string
function NBT.string(value)
  return '\8' .. string_pack(">s2", value)
end

---@param items { [string]: any }
---@return string
function NBT.compound(items)
  local buf = "\10"
  for key, item in pairs(items) do
    if type(key) ~= "string" then error("invalid key type '" .. type(key) .. "' for compound") end
    local name = string_pack(">s2", key)
    item = infer_type(item)
    buf = buf .. string_sub(item, 1, 1) .. name .. string_sub(item, 2)
  end
  return buf .. '\0'
end

---@param items any[]
---@return string
function NBT.list(items)
  local buf = "\9"
  local list_type
  for _, item in ipairs(items) do
    item = infer_type(item)
    if not list_type then
      list_type = string_sub(item, 1, 1)
      buf = buf .. list_type .. string_pack(">i4", #items)
    elseif list_type ~= string_sub(item, 1, 1) then
      error("list of mismatched types!")
    end
    buf = buf .. string_sub(item, 2)
  end
  return buf
end

return NBT
