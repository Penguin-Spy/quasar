--[[ NBT.lua © Penguin_Spy 2024

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
local string_unpack = string.unpack

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


local parse_payload

-- parses the payload of a TAG_Compound
---@param data string     the raw data
---@param offset integer  where to start reading the payload from
---@return table payload, integer offset
local function parse_compound_payload(data, offset)
  local compound = {}
  local tag, name, payload
  while true do
    tag, offset = string_unpack(">I1", data, offset)
    if tag == 0 then break end -- TAG_End has no name or payload
    name, offset = string_unpack(">s2", data, offset)
    payload, offset = parse_payload(tag, data, offset)
    compound[name] = payload
  end
  return compound, offset
end

-- parses the payload of a TAG_List, TAG_Int_Array, or TAG_Long_Array
---@param tag integer     the type of tags in the list
---@param data string     the raw data
---@param offset integer  where to start reading the payload from
---@return table payload, integer offset
local function parse_list_payload(tag, data, offset)
  local list, length = {}, nil
  length, offset = string_unpack(">i4", data, offset)
  for i = 1, length do
    list[i], offset = parse_payload(tag, data, offset)
  end
  return list, offset
end

-- parses the payload of an NBT tag
---@param tag integer the NBT tag type
---@param data string     the raw data
---@param offset integer  where to start reading the payload from
---@return any payload, integer offset
function parse_payload(tag, data, offset)
  if tag == 1 then
    return string_unpack(">i1", data, offset)
  elseif tag == 2 then
    return string_unpack(">i2", data, offset)
  elseif tag == 3 then
    return string_unpack(">i4", data, offset)
  elseif tag == 4 then
    return string_unpack(">i8", data, offset)
  elseif tag == 5 then
    return string_unpack(">f", data, offset)
  elseif tag == 6 then
    return string_unpack(">d", data, offset)
  elseif tag == 8 then
    return string_unpack(">s2", data, offset)
  elseif tag == 9 then
    local list_tag = string_byte(data, offset)
    return parse_list_payload(list_tag, data, offset + 1)
  elseif tag == 10 then
    return parse_compound_payload(data, offset)
  elseif tag == 11 then
    return parse_list_payload(3, data, offset)
  elseif tag == 12 then
    return parse_list_payload(4, data, offset)
  else
    error(string.format("unknown NBT tag type: %i at offset %i", tag, offset))
  end
end

-- parses an uncompressed NBT compound
---@param data string       the raw data
---@param offset integer    where to start reading
---@param skip_name boolean true if there is no name for the root compound
---@return table compound   the parsed NBT data
---@return integer offset   the index of the first unread byte of `data`
function NBT.parse(data, offset, skip_name)
  assert(string_byte(data, offset) == 10, "NBT data must start with a TAG_Compound")
  local name_length = skip_name and 0 or (2 + string_unpack(">I2", data, offset + 1))
  return parse_compound_payload(data, offset + 1 + name_length)
end

return NBT
