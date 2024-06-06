--[[ dimension.lua © Penguin_Spy 2024
  Handles a specific dimension on the server, comprised of blocks (in chunks) and entities.

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

local log = require "log"

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
  for k, v in pairs(self.players) do
    if v == player then
      self.players[k] = nil
      return
    end
  end
end

-- Creates a new Dimension. You should not call this function yourself, instead use `Server.create_dimension`!
---@see Server.create_dimension
---@param identifier identifier   The identifier for the dimension, e.g. `"minecraft:overworld"`<br>
---@return Dimension
function Dimension._new(identifier)
  ---@type Dimension
  local self = {
    identifier = identifier,
    chunk_data = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 },
    players = {}
  }
  setmetatable(self, { __index = Dimension })
  return self
end

return Dimension
