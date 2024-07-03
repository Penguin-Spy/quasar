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

-- when the creative inventory is used to set the item in a slot
---@param slot integer  the slot index
---@param item Item?    the item to put in the slot, or nil to clear the slot
function Player:on_set_slot(slot, item)
  self.inventory[slot] = item
end

-- Called when the player sends a chat message. <br>
-- Default behavior runs the `on_chat_message` handler of the Player's Dimension.
---@param message string
function Player:on_chat_message(message)
  self.dimension:on_chat_message(self, message)
end

-- Called when the player attempts to run a command (regardless of if it's a real or valid command). <br>
-- Default behavior runs the `on_command` handler of the Player's Dimension.
---@param command string  The full text of the command, not including the preceeding slash '/'
function Player:on_command(command)
  self.dimension:on_command(self, command)
end

-- Updates the block at the specified position for the player.
---@param position blockpos
---@param state integer     The block state ID to set at the position
function Player:set_block(position, state)
  self.connection:send_block(position, state)
end

-- Sends a chat message to the player
---@param type registry.chat_type  The chat type
---@param sender string   The name of the one sending the message
---@param content string  The content of the message
---@param target string?  Optional target of the message, used in some chat types
function Player:send_chat_message(type, sender, content, target)
  self.connection:send_chat_message(type, sender, content, target)
end

-- Sends a system message to the player
---@param message string
function Player:send_system_message(message)
  self.connection:send_system_message(message)
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
    connection = con
  }
  setmetatable(self, { __index = Player })
  return self
end

return Player
