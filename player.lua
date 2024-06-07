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
---@field selected_slot integer  0-8
---@field position table
---@field connection Connection
---@field dimension Dimension
local Player = {}

--
---@param slot integer 0-8
function Player:on_select_hotbar_slot(slot)
  self.selected_slot = slot
end

-- Updates the block at the specified position for the player.
---@param position blockpos
---@param state integer     The block state ID to set at the position
function Player:set_block(position, state)
  self.connection:send_block(position, state)
end

-- when the creative inventory is used to set the item in a slot
---@param slot integer  the slot index
---@param item Item?    the item to put in the slot, or nil to clear the slot
function Player:on_set_slot(slot, item)
  self.inventory[slot] = item
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
    selected_slot = 0,
    position = {},
    connection = con
  }
  setmetatable(self, { __index = Player })
  return self
end

return Player
