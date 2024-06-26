--[[ main.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

-- we redefine fields to set the event handlers
---@diagnostic disable: duplicate-set-field

local Server = require "server"
local log = require "log"

local overworld = Server.create_dimension("minecraft:overworld")
function overworld:on_break_block(player, pos)
  log("player '%s' broke a block at (%i, %i, %i)", player.username, pos.x, pos.y, pos.z)

  --self.chunk_data[16] = 13
  self:set_block(pos, 13)
end


local the_nether = Server.create_dimension("minecraft:the_nether")
function the_nether:get_chunk(chunk_x, chunk_z)
  return { chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x }
end

Server.set_default_dimension(overworld)

function Server.on_login(username, uuid)
  --"Failed to connect to the server"
  --return false, "nope"
  return true
end

function Server.on_join(player)
  -- "connection lost"
  --return false, "nope 2"
  player.dimension = the_nether
  return true
end

Server.listen("*", 25565)
