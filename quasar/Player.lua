--[[ player.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.

  The Covered Software may not be used as training or other input data
  for LLMs, generative AI, or other forms of machine learning or neural
  networks.
]]

local Vector3 = require "quasar.Vector3"

---@class Player : Entity
---@field username string
---@field uuid uuid
---@field skin {texture: string?, texture_signature: string?, layers: integer, hand: 0|1}
---@field inventory table<integer, Item>
---@field selected_slot integer  0-8
---@field connection Connection
---@field dimension Dimension
---@field on_ground boolean     True if the client thinks it's on the ground
---@field against_wall boolean  True if the client thinks it's pushed against a wall
---@field sneaking boolean      True if the client intends to be sneaking
---@field sprinting boolean     True if the client intends to be sprinting
---@field input number          The player's current input, see https://minecraft.wiki/w/Java_Edition_protocol#Player_Input
---@field block_position Vector3
---@field chunk_position Vector3
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
---@param chat_type identifier  The chat type
---@param sender string         The name of the one sending the message
---@param content string        The content of the message
---@param target string?        Optional target of the message, used in some chat types
function Player:send_chat_message(chat_type, sender, content, target)
  self.connection:send_chat_message(chat_type, sender, content, target)
end

-- Sends a system message to the player
---@param message string
function Player:send_system_message(message)
  self.connection:send_system_message(message)
end

-- Informs this player that the specified other players exist
---@param players Player[]
function Player:add_players(players)
  self.connection:add_players(players)
end

-- Informs this player that the specified entity spawned
---@param entity Entity
function Player:add_entity(entity)
  self.connection:add_entity(entity)
end

-- Informs this player of the new position of the entity
---@param entity Entity
function Player:move_entity(entity)
  self.connection:send_move_entity(entity)
end

-- Informs this player that the specified other players no longer exist
---@param players Player[]
function Player:remove_players(players)
  self.connection:remove_players(players)
end

-- Informs this player that the specified entities no longer exist
---@param entities Entity[]
function Player:remove_entities(entities)
  self.connection:remove_entities(entities)
end

-- Transfers the player to the specified dimension
---@param new_dimension Dimension
function Player:transfer_dimension(new_dimension)
  self.dimension:_remove_player(self)
  self.dimension = new_dimension
  self.connection:respawn(3, true)
  self.dimension:_add_player(self)
end

-- Internal method
---@param username string
---@param uuid uuid         The player's UUID in binary form.
---@param con Connection
---@param skin? {texture: string, texture_signature: string?}
---@return Player
function Player._new(username, uuid, con, skin)
  local self = {
    type = "minecraft:player",  -- for Entity
    position = Vector3.new(),
    pitch = 0,
    yaw = 0,
    last_sync_pos = Vector3.new(),
    last_sync_pitch = 0,
    last_sync_yaw = 0,
    username = username,
    uuid = uuid,
    skin = { layers = 0, hand = 1, texture = skin and skin.texture, texture_signature = skin and skin.texture_signature },
    inventory = {},
    selected_slot = 0,
    connection = con,
    on_ground = false,
    against_wall = false,
    sneaking = false,
    sprinting = false,
    input = 0,
    block_position = Vector3.new(),
    chunk_position = Vector3.new()
  }
  setmetatable(self, { __index = Player })
  return self
end

return Player
