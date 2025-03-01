--[[ Vector3.lua © Penguin_Spy 2024
  Simple Lua class for storing a position in 3d space.

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

---@class Vector3
---@field x number
---@field y number
---@field z number
local Vector3 = {}

-- Sets the value of this Vector3.
---@param x number
---@param y number
---@param z number
function Vector3:set(x, y, z)
  self.x = x
  self.y = y
  self.z = z
end

-- Copies the value of the specified Vector3 to this Vector3.
---@param other Vector3
function Vector3:copy(other)
  self.x = other.x
  self.y = other.y
  self.z = other.z
end

-- Checks value equality (self.x == other.x). Also available as the `__eq` metamethod.
---@param other Vector3
function Vector3:equals(other)
  return self.x == other.x and self.y == other.y and self.z == other.z
end

local mt = {
  __index = Vector3,
  __eq = Vector3.equals
}

-- Creates a new Vector3 with the specified value.
---@param x number?   All 3 values default to `0`
---@param y number?
---@param z number?
---@return Vector3
function Vector3.new(x, y, z)
  local self = { x = x or 0, y = y or 0, z = z or 0 }
  setmetatable(self, mt)
  return self
end

return Vector3
