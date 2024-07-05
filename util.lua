--[[ util.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

local json = require 'lunajson'

local util = {}

-- Attempts to remove the specified value from the table. Returns true if the value was found and removed.
---@generic V
---@param t table<any, V>
---@param value V
---@return boolean
function util.remove_value(t, value)
  for k, v in pairs(t) do
    if v == value then
      t[k] = nil
      return true
    end
  end
  return false
end

-- Generates a new UUIDv4 in binary form (16-byte string).
---@return uuid
function util.new_UUID()
  return string.char(
    math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255),
    math.random(0, 255), math.random(0, 255),
    0x40 | math.random(0, 0x0F), math.random(0, 255),
    0x80 | math.random(0, 0x3F), math.random(0, 255),
    math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255)
  )
end

-- Converts a UUID in binary form to a human-readable string.
---@param uuid uuid
---@return string
function util.UUID_to_string(uuid)
  local out = ""
  for i = 1, 16 do
    out = out .. string.format("%02X", uuid:byte(i))
    if i == 4 or i == 6 or i == 8 or i == 10 then
      out = out .. "-"
    end
  end
  return out
end

-- Loads the contents of a JSON file as a Lua table.
---@param path string
---@return table
function util.read_json(path)
  local f, err = io.open(path, "r")
  if not f then
    error(("failed to open %s - %s"):format(path, err))
  end
  local data = f:read("a")
  f:close()
  return json.decode(data)
end

-- Splits a string into a list by the seperator.
---@param input string
---@param seperator string
---@return string[]
function util.split(input, seperator)
  local output = {}
  for v in input:gmatch("([^" .. seperator .. "]+)") do
    table.insert(output, v)
  end
  return output
end

return util
