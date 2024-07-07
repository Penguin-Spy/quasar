--[[ dimension.lua © Penguin_Spy 2024
  Handles a specific dimension on the server, comprised of blocks (in chunks) and entities.

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

local log = require "log"
local util = require "util"
local Vector3 = require "Vector3"
local Entity = require "entity"
local Chunk = require 'chunk'

---@class Dimension
---@field timer table?  Copas timer for dimension ticking
---@field identifier identifier
---@field chunks Chunk[][]
---@field players Player[]      All players currently in this Dimension
---@field entities Entity[]
---@field next_entity_id number Starts at 1
---@field spawnpoint Vector3   The position where newly added players will spawn in
local Dimension = {}

-- Called when a player breaks a block
---@param player Player     the player who broke the block
---@param position blockpos a table with the fields x,y,z
function Dimension:on_break_block(player, position)
  self:set_block(position, 0)
end

-- Called when the player uses an item while not looking at a block.
---@param player Player
---@param slot integer  the slot containing the item used (45 for offhand, else 36-44 for hotbar)
---@param yaw number    the player's head yaw when using the item
---@param pitch number  the player's head pitch when using the item
function Dimension:on_use_item(player, slot, yaw, pitch)
  log("'%s' used the item in slot #%i: %s", player.username, slot, player.inventory[slot])
end


-- Called when the player "uses" an item against a block (usually placing a block, but is sent for all items).
---@param player Player the player who used the item
---@param slot integer  the slot containing the item used (45 for offhand, else 36-44 for hotbar)
---@param pos blockpos  the position of the block the item was used against
---@param face integer  the face of the block the item was used against
---@param cursor {x: number, y: number, z:number} values range from `0.0` to `1.0` indicating where on the block face the item was used
---@param inside_block boolean  whether the client reports its head being inside a block when using the item
function Dimension:on_use_item_on_block(player, slot, pos, face, cursor, inside_block)
  log("'%s' used the item in slot #%i: %s on the block at (%i, %i, %i)'s face %i, cursor pos (%f, %f, %f), inside block: %q",
    player.username, slot, player.inventory[slot], pos.x, pos.y, pos.z, face, cursor.x, cursor.y, cursor.z, inside_block)
  -- offset the position based on the face
  if face == 0 then
    pos.y = pos.y - 1
  elseif face == 1 then
    pos.y = pos.y + 1
  elseif face == 2 then
    pos.z = pos.z - 1
  elseif face == 3 then
    pos.z = pos.z + 1
  elseif face == 4 then
    pos.x = pos.x - 1
  else  --if face == 5 then
    pos.x = pos.x + 1
  end
  self:set_block(pos, 1)
end

-- Called when a player sends a chat message. <br>
-- Default behavior broadcasts the message to all players in the dimension. <br>
-- Only called if the Player's `on_chat_message` handler hasn't been set (or explicitly calls it's default behavior).
---@param player Player   The player who sent the message
---@param message string  The message sent
function Dimension:on_chat_message(player, message)
  self:broadcast_chat_message("minecraft:chat", player.username, message)
end

-- Called when the player attempts to run a command (regardless of if it's a real or valid command)
---@param player Player   The player who ran the command
---@param command string  The full text of the command, not including the preceeding slash '/'
function Dimension:on_command(player, command)
  player:send_system_message("unknown command")
end

-- Called when a player joins this Dimension. Useful for updating position & inventory.
---@param player Player
function Dimension:on_player_joined(player)
  player.position:copy(self.spawnpoint)
end

-- Ran 20 times per second. Handles updating the position of entites.
function Dimension:tick()
  -- TODO: shouldn't sync player positions here (but players are currently part of the entities list)
  --[[for _, e in pairs(self.entities) do
    if e.position ~= e.last_sync_pos or e.pitch ~= e.last_sync_pitch or e.yaw ~= e.last_sync_yaw then
      --local dx, dy, dz = e.position.x - e.last_sync_pos.x, e.position.y - e.last_sync_pos.y, e.position.z - e.last_sync_pos.z
      --if math.abs(dx) >
      log("syncing pos of %q", e.id)
      for _, p in pairs(self.players) do
        p:move_entity(e)
      end
      e.last_sync_pos:copy(e.position)
      e.last_sync_pitch = e.pitch
      e.last_sync_yaw = e.yaw
    end
  end]]
end


-- Updates the block at the specified position for all players in this dimension.
---@param position blockpos
---@param state integer     The block state ID to set at the position
function Dimension:set_block(position, state)
  for _, p in pairs(self.players) do
    p:set_block(position, state)
  end
  local chunk = self.chunks[position.x // 16][position.z // 16]
  chunk:set_block(position, state)
end

-- Broadcasts a chat message to all players in the dimension
---@param type registry.chat_type  The chat type
---@param sender string   The name of the one sending the message
---@param content string  The content of the message
---@param target string?  Optional target of the message, used in some chat types
function Dimension:broadcast_chat_message(type, sender, content, target)
  for _, p in pairs(self.players) do
    p:send_chat_message(type, sender, content, target)
  end
end

-- Broadcasts a system message to all players in the dimension
---@param message string
function Dimension:broadcast_system_message(message)
  for _, p in pairs(self.players) do
    p:send_system_message(message)
  end
end

-- Spawns a new entity into this dimension.
---@param type registry.entity_type
---@param position Vector3
---@return Entity
function Dimension:spawn_entity(type, position)
  local entity = Entity._new(self.next_entity_id, type, position)
  self.next_entity_id = self.next_entity_id + 1
  self.entities[entity.id] = entity
  for _, p in pairs(self.players) do
    p:add_entity(entity)
  end
  return entity
end

-- Gets the chunk at the specified chunk coordinates.
---@param chunk_x integer
---@param chunk_z integer
---@param player Player   the player to get the chunk for
---@return Chunk chunk
function Dimension:get_chunk(chunk_x, chunk_z, player)
  return self.chunks[chunk_x][chunk_z]
end

-- Spawns the player into the dimension, adding their player entity & raising `on_player_join`.
---@param player Player
function Dimension:_add_player(player)
  -- inform this player of all other players, then add it to the list
  player:add_players(self.players)
  table.insert(self.players, player)

  -- inform the player of all existing entities
  for _, e in pairs(self.entities) do
    player:add_entity(e)
  end
  -- then add the player as an entity in this Dimension
  player.id = self.next_entity_id
  self.next_entity_id = self.next_entity_id + 1
  self.entities[player.id] = player

  -- update stuff like the player's position
  self:on_player_joined(player)

  -- inform all other players of this player & its entity
  for _, other_player in pairs(self.players) do
    other_player:add_players{ player }  -- informs the player about its own player data
    if other_player ~= player then
      other_player:add_entity(player)
    end
  end
end

-- Removes the player from this Dimension, despawning their player entity.
---@param player Player
function Dimension:_remove_player(player)
  util.remove_value(self.players, player)
  self.entities[player.id] = nil
  for _, other_player in pairs(self.players) do
    other_player:remove_players{ player }
    other_player:remove_entities{ player }
  end
  player.id = nil
end

-- Creates a new Dimension. You should not call this function yourself, instead use `Server.create_dimension`!
---@see Server.create_dimension
---@param identifier identifier   The identifier for the dimension, e.g. `"minecraft:overworld"`<br>
---@return Dimension
function Dimension._new(identifier)
  ---@type Dimension
  local self = {
    identifier = identifier,
    chunks = {},
    players = {},
    entities = {},
    next_entity_id = 1,
    spawnpoint = Vector3.new(0, 66, 0)
  }
  for x = -4, 4 do
    self.chunks[x] = {}
    for z = -4, 4 do
      self.chunks[x][z] = Chunk._new(24)
    end
  end
  setmetatable(self, { __index = Dimension })
  return self
end

return Dimension
