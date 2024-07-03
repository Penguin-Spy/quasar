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

  if pos.y >= 192 then
    self:set_block(pos, 0)
  else
    self:set_block(pos, 13)
  end
end


local the_nether = Server.create_dimension("minecraft:the_nether")
function the_nether:get_chunk(chunk_x, chunk_z)
  return { chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, chunk_x, 0, 0, 0, 0, 0, 0, 0, 0 }
end

---@param player Player
---@param command string
function the_nether:on_command(player, command)
  if command == "hatsune miku" then
    player:send_system_message("hatsune miku moment")
  else
    player:send_system_message('what no')
  end
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
