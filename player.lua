--[[ player.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

---@class Player
---@field username string
---@field uuid uuid
---@field inventory table<integer, table>
---@field position table
---@field connection Connection
---@field dimension Dimension
local Player = {}

--
---@param slot integer 1-9
function Player:select_hotbar_slot(slot)
  -- nothing
end

-- Updates the block at the specified position for the player.
---@param position blockpos
---@param state integer     The block state ID to set at the position
function Player:set_block(position, state)
  self.connection:send_block(position, state)
end

-- dont' use this
---@param username string
---@param uuid string       The player's UUID in binary form.
---@param con Connection
---@return Player
function Player._new(username, uuid, con)
  local self = {
    username = username,
    uuid = uuid,
    inventory = {},
    position = {},
    connection = con
  }
  setmetatable(self, { __index = Player })
  return self
end

return Player
