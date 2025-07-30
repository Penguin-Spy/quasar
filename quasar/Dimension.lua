--[[ dimension.lua © Penguin_Spy 2024-2025
  Handles a specific dimension on the server, comprised of blocks (in chunks) and entities.

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.

  The Covered Software may not be used as training or other input data
  for LLMs, generative AI, or other forms of machine learning or neural
  networks.
]]

local log = require "quasar.log"
local util = require "quasar.util"
local Vector3 = require "quasar.Vector3"
local Entity = require "quasar.Entity"
local Chunk = require 'quasar.Chunk'
local Registry = require 'quasar.Registry'

---@class Dimension
---@field timer table?  Copas timer for dimension ticking
---@field identifier identifier The unique namespaced identifier of this dimension
---@field type identifier       The identifier of this dimension's type
---@field chunks {[integer]: {[integer]: Chunk|false }}   An entry is false if there is no chunk there
---@field empty_chunk Chunk               A chunk usually comprised of entirely air, sent to the client for nonexistent chunks
---@field chunk_provider ChunkProvider    The provider for chunks for this Dimension
---@field view_distance integer Radius in chunks; the area where the client accepts chunks is a square with sides `2r+7`, and chunks are rendered in a `2r+1` square.
---@field players Player[]      All players currently in this Dimension
---@field entities Entity[]
---@field next_entity_id number Starts at 1
---@field spawnpoint Vector3    The position where newly added players will spawn in
---@field is_flat boolean       if the dimension is "flat", the skybox horizon is at -65 instead of 61. used for superflat worlds in vanilla.
---@field sea_level integer     unknown effect on the client, unused on the server
local Dimension = {}

-- Called when a player breaks a block
---@param player Player     the player who broke the block
---@param position blockpos a table with the fields x,y,z
function Dimension:on_break_block(player, position)
  self:set_block(position, "minecraft:air")
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
  self:set_block(pos, "minecraft:stone")
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

-- Called whenever a player in this Dimension moves to a different block position.
---@param player Player
function Dimension:on_player_changed_position(player)

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

local block_state_map = Registry.get_block_state_map()

-- Updates the block at the specified position for all players in this dimension.
---@param position blockpos
---@param block identifier
---@return boolean        # Whether the placement was successful
function Dimension:set_block(position, block)
  local chunk = self:get_chunk(position.x // 16, position.z // 16)
  if not chunk then return false end

  local state = block_state_map[block]

  chunk:set_block(position, state)
  for _, p in pairs(self.players) do
    p:set_block(position, state)
  end
  return true
end

-- Broadcasts a chat message to all players in the dimension
---@param chat_type identifier  The chat type
---@param sender string         The name of the one sending the message
---@param content string        The content of the message
---@param target string?        Optional target of the message, used in some chat types
function Dimension:broadcast_chat_message(chat_type, sender, content, target)
  for _, p in pairs(self.players) do
    p:send_chat_message(chat_type, sender, content, target)
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
---@param entity_type identifier
---@param position Vector3
---@return Entity
function Dimension:spawn_entity(entity_type, position)
  local entity = Entity._new(self.next_entity_id, entity_type, position)
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
---@param player Player?   the player to get the chunk for
---@return Chunk|false chunk
function Dimension:get_chunk(chunk_x, chunk_z, player)
  -- get the row of chunks, creating it if it doesn't exist
  local cx = self.chunks[chunk_x]
  if not cx then
    cx = {}
    self.chunks[chunk_x] = cx
  end

  -- get the chunk itself, loading it if it isn't loaded
  local chunk = cx[chunk_z]
  if chunk == nil then -- specifically check nil but not false
    -- if "no chunk" is returned, still save `false` to not call load() again unnecessarily
    chunk = self.chunk_provider:load(chunk_x, chunk_z)
    cx[chunk_z] = chunk
  end
  return chunk
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

  -- synchronize player position (do this first so the client doesn't default to (8.5,65,8.5) when chunks are sent)
  player.connection:synchronize_position()

  -- send chunks to the player
  local pos = player.position
  self:_on_player_changed_chunk(player, pos.x // 16, pos.z // 16, true)
  -- resync position in case the client fell into the void while loading chunks
  player.connection:synchronize_position()
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


local modf = math.modf
-- Called whenever a player in this Dimension moves. <br>
-- Note that this is called each time a movement packet is received, and not necessarily when the player's block position has changed. <br>
-- Default behavior handles chunk loading
---@param player Player
function Dimension:_on_player_moved(player)
  local pos, bpos = player.position, player.block_position
  local bx, by, bz = modf(pos.x), modf(pos.y), modf(pos.z)

  if bx ~= bpos.x or by ~= bpos.y or bz ~= bpos.z then
    bpos:set(bx, by, bz)
    self:on_player_changed_position(player)

    local cx, cy, cz = pos.x // 16, pos.y // 16, pos.z // 16
    local cpos = player.chunk_position
    if cx ~= cpos.x or cz ~= cpos.z then
      self:_on_player_changed_chunk(player, cx, cz)
    end
    cpos:set(cx, cy, cz)
  end
end

-- Handles sending chunks to the client; you generally don't need to change this.
---@param player Player
---@param cx integer The new chunk x
---@param cz integer The new chunk z
---@param load_all boolean? If true, all chunks in the view distance will be sent to the client (i.e. when first joining the dimension)
function Dimension:_on_player_changed_chunk(player, cx, cz, load_all)
  local cpos = player.chunk_position

  player.connection:send_set_center_chunk(cx, cz)
  local r = self.view_distance + 3  -- extra 3 chunks is from `2r+7`

  for x = cx - r, cx + r do
    for z = cz - r, cz + r do
      if (x < (cpos.x - r)) or (x > (cpos.x + r))
          or (z < (cpos.z - r)) or (z > (cpos.z + r)) or load_all then
        player.connection:send_chunk(x, z, self:get_chunk(x, z, player) or self.empty_chunk)
      end
    end
  end
end

---@class (exact) Dimension.options
--- the identifier for this dimension
---@field identifier identifier
--- the type of this dimension; defaults to `"minecraft:overworld"`
---@field type identifier?
--- the chunk provider for the dimension
---@field chunk_provider ChunkProvider
--- the default spawn location for players joining the dimension. defaults to `(1, 65, 1)`
---@field spawnpoint Vector3?
--- defaults to `false`, if the dimension is "flat", the skybox horizon is at -65 instead of 61. used for superflat worlds in vanilla.
---@field is_flat boolean?
--- defaults to `63`, the sea level of the dimension; unknown effect on the client, unused on the server
---@field sea_level integer?
--- (unused) loading behavior for chunks
----@field chunk_load_behavior "normal"|"load_all"|"stay_loaded"

-- Creates a new Dimension. You should not call this function yourself, instead use `Server.create_dimension`! <br>
---@see Server.create_dimension
---@param options Dimension.options
---@return Dimension
function Dimension._new(options)
  assert(options.identifier, "dimension identifier is required!")
  assert(options.chunk_provider, "dimension chunk provider is required!")

  local self = {
    identifier = options.identifier,
    type = options.type or "minecraft:overworld",
    chunks = {},
    chunk_provider = options.chunk_provider,
    view_distance = 4,
    players = {},
    entities = {},
    next_entity_id = 1,
    spawnpoint = options.spawnpoint or Vector3.new(1, 65, 1),
    is_flat = options.is_flat or false,
    sea_level = options.sea_level or 63
  }
  self.empty_chunk = Chunk.new_empty(24)
  setmetatable(self, { __index = Dimension })
  return self
end

return Dimension
