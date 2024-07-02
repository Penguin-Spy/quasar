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

---@class Dimension
---@field identifier identifier
---@field chunk_data table
---@field players Player[]      All players currently in this Dimension
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


-- Updates the block at the specified position for all players in this dimension.
---@param position blockpos
---@param state integer     The block state ID to set at the position
function Dimension:set_block(position, state)
  for _, p in pairs(self.players) do
    p:set_block(position, state)
  end
end


-- Gets the raw chunk data for the chunk at the specified position.
---@param chunk_x integer
---@param chunk_z integer
---@param player Player   the player to get the chunk data for
---@return table data     A list of block types, from the lowest to highest subchunk.
function Dimension:get_chunk(chunk_x, chunk_z, player)
  return self.chunk_data
end

-- Adds the player to this Dimension. The player will receive packets for changes happening in this dimension.<br>
-- Note that this will not inform the client that they have changed dimensions!<br>
-- You likely want to use `Player:change_dimension` instead.
---@param player Player
function Dimension:add_player(player)
  table.insert(self.players, player)
end

-- Removes the player from this Dimension. The player will no longer receive packets for changes happening in this dimension.<br>
-- Note that this will not inform the client that they have changed dimensions!<br>
-- You likely want to use `Player:change_dimension` instead.
---@param player Player
function Dimension:remove_player(player)
  util.remove_value(self.players, player)
end

-- Creates a new Dimension. You should not call this function yourself, instead use `Server.create_dimension`!
---@see Server.create_dimension
---@param identifier identifier   The identifier for the dimension, e.g. `"minecraft:overworld"`<br>
---@return Dimension
function Dimension._new(identifier)
  ---@type Dimension
  local self = {
    identifier = identifier,
    chunk_data = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 0, 0, 0, 0, 0, 0, 0, 0 },
    players = {}
  }
  setmetatable(self, { __index = Dimension })
  return self
end

return Dimension
