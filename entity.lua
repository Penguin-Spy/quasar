--[[ entity.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

local util = require "util"
local registry = require "registry"
local Vector3 = require "Vector3"

---@class Entity
---@field id number
---@field uuid uuid
---@field type registry.entity_type
---@field position Vector3
---@field pitch number    Degrees from 90 to -90, -90 is looking straight up
---@field yaw number      Degrees from 0-359, 0 is +Z, counterclockwise
---@field last_sync_pos Vector3
---@field last_sync_pitch number
---@field last_sync_yaw number
local Entity = {}


-- Internal method.
---@see Dimension.spawn_entity
---@param id number
---@param entity_type registry.entity_type
---@param pos Vector3
---@param uuid uuid?
---@return Entity
function Entity._new(id, entity_type, pos, uuid)
  if type(registry.entity_types[entity_type]) ~= "number" then
    error("invalid entity type '" .. tostring(entity_type) .. "'")
  end
  ---@type Entity
  local self = {
    id = id,
    uuid = uuid or util.new_UUID(),
    type = entity_type,
    position = Vector3.new(pos.x, pos.y, pos.z),
    pitch = 0,
    yaw = 0,
    last_sync_pos = Vector3.new(pos.x, pos.y, pos.z),
    last_sync_pitch = 0,
    last_sync_yaw = 0
  }
  setmetatable(self, { __index = Entity })
  return self
end

return Entity
