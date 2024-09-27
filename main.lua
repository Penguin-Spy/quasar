--[[ main.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

-- we redefine fields to set the event handlers
---@diagnostic disable: duplicate-set-field

local Server = require "Server"
local log = require "log"
local util = require "util"

local overworld = Server.create_dimension("minecraft:overworld")
function overworld:on_break_block(player, pos)
  log("player '%s' broke a block at (%i, %i, %i)", player.username, pos.x, pos.y, pos.z)

  if pos.y >= 192 then
    self:set_block(pos, 0)
  else
    self:set_block(pos, 13)
  end
end

function overworld:on_command(player, command)
  local c = util.split(command, " ")
  if c[1] == "transfer" then
    if c[2] == "nether" then
      player:transfer_dimension(Server.get_dimension("minecraft:the_nether"))
    else
      player:send_system_message("unknown dimension")
    end
  else
    player:send_system_message("unknown command")
  end
end


local the_nether = Server.create_dimension("minecraft:the_nether")
the_nether.spawnpoint:set(1.5, 66, 8.5)

-- show letters in the ground for testing chunk loading
-- s for spawn
local spawn_chunk_data = the_nether:get_chunk(0, 0).subchunks[8].data
spawn_chunk_data[250] = 0x0111111000011110
spawn_chunk_data[249] = 0x0111110111111110
spawn_chunk_data[248] = 0x0111111000111110
spawn_chunk_data[247] = 0x0111111111011110
spawn_chunk_data[246] = 0x0111110000111110

-- f for far
local far_chunk_data = the_nether:get_chunk(-3, 0).subchunks[8].data
far_chunk_data[252] = 0x0111111100111110
far_chunk_data[251] = 0x0111111011111110
far_chunk_data[250] = 0x0111110000111110
far_chunk_data[249] = 0x0111111011111110
far_chunk_data[248] = 0x0111111011111110
far_chunk_data[247] = 0x0111111011111110
far_chunk_data[246] = 0x0111111011111110
---- b for bonus (official edge chunks)
local bonus_chunk_data = the_nether:get_chunk(-4, 0).subchunks[8].data
bonus_chunk_data[252] = 0x0111110111111110
bonus_chunk_data[251] = 0x0111110111111110
bonus_chunk_data[250] = 0x0111110100111110
bonus_chunk_data[249] = 0x0111110011011110
bonus_chunk_data[248] = 0x0111110111011110
bonus_chunk_data[247] = 0x0111110111011110
bonus_chunk_data[246] = 0x0111110000111110

-- line of increading block id
the_nether:get_chunk(-1, 0).subchunks[8].data[245] = 0x0222222222222220
the_nether:get_chunk(-2, 0).subchunks[8].data[245] = 0x0333333333333330
far_chunk_data[245] = 0x0444444444444440
bonus_chunk_data[245] = 0x0555555555555550
the_nether:get_chunk(-5, 0).subchunks[8].data[245] = 0x0666666666666660
the_nether:get_chunk(-6, 0).subchunks[8].data[245] = 0x0777777777777770
the_nether:get_chunk(-7, 0).subchunks[8].data[245] = 0x0888888888888880
the_nether:get_chunk(-8, 0).subchunks[8].data[245] = 0x0999999999999990
the_nether:get_chunk(-9, 0).subchunks[8].data[245] = 0x0AAAAAAAAAAAAAA0
the_nether:get_chunk(-10, 0).subchunks[8].data[245] = 0x0BBBBBBBBBBBBBB0

---@param player Player
---@param command string
function the_nether:on_command(player, command)
  local c = util.split(command, " ")
  if command == "hatsune miku" then
    player:send_system_message("hatsune miku moment")
  elseif c[1] == "summon" then
    local pos
    if c[3] then
      pos = { x = tonumber(c[3]), y = tonumber(c[4]), z = tonumber(c[5]) }
    else
      pos = { x = 8.5, y = 194, z = 8.5 }
    end
    self:spawn_entity(c[2], pos)
    player:send_system_message("summoned " .. c[2])
  elseif c[1] == "tp" then
    local x, y, z = tonumber(c[2]), tonumber(c[3]), tonumber(c[4])
    if x and y and z then
      player.position:set(x, y, z)
      player.connection:synchronize_position()
    else
      player:send_system_message("syntax error")
    end
  elseif c[1] == "transfer" then
    if c[2] == "overworld" then
      player:transfer_dimension(Server.get_dimension("minecraft:overworld"))
    else
      player:send_system_message("unknown dimension")
    end
  elseif c[1] == "disconnect" then
    player.connection:disconnect("bye")
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
Server.run()
