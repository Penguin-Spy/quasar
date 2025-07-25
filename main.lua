--[[ main.lua © Penguin_Spy 2024-2025

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.

  The Covered Software may not be used as training or other input data
  for LLMs, generative AI, or other forms of machine learning or neural
  networks.
]]

-- we redefine fields to set the event handlers
---@diagnostic disable: duplicate-set-field

local Server = require "quasar.Server"
local log = require "quasar.log"
local util = require "quasar.util"
local ChunkProvider = require "quasar.ChunkProvider"

local overworld = Server.create_dimension{
  identifier = "minecraft:overworld",
  chunk_provider = ChunkProvider.region{ path = "world/" }
}

function overworld:on_break_block(player, pos)
  log("player '%s' broke a block at (%i, %i, %i)", player.username, pos.x, pos.y, pos.z)

  if pos.y >= 192 then
    self:set_block(pos, "minecraft:air")
  else
    self:set_block(pos, "minecraft:podzol")
  end
end

function overworld:on_command(player, command)
  local c = util.split(command, " ")
  if c[1] == "transfer" then
    local dimension = Server.get_dimension(c[2])
    if dimension then
      player:transfer_dimension(dimension)
    else
      player:send_system_message("unknown dimension")
    end
  else
    player:send_system_message("unknown command")
  end
end


local the_nether = Server.create_dimension{
  identifier = "minecraft:the_nether",
  chunk_provider = --[[ChunkProvider.superflat{
    layers = {
      ["minecraft:bedrock"] = 1,
      ["minecraft:dirt"] = 2,
      ["minecraft:grass_block"] = 1,
    },
    biome = "minecraft:plains",
    subchunk_height = 24,
  }]]
  ChunkProvider.region{ path = "world/" }
}
the_nether.spawnpoint:set(1.5, 128, 8.5)

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
  elseif c[1] == "setblock" then
    local x, y, z = tonumber(c[2]), tonumber(c[3]), tonumber(c[4])
    if x and y and z and type(c[5]) == "string" then
      player.dimension:set_block({x=x,y=y,z=z}, c[5])
    else
      player:send_system_message("syntax error")
    end
  elseif c[1] == "transfer" then
    local dimension = Server.get_dimension(c[2])
    if dimension then
      player:transfer_dimension(dimension)
    else
      player:send_system_message("unknown dimension")
    end
  elseif c[1] == "disconnect" then
    player.connection:disconnect("bye")
  --[[elseif c[1] == "lua" then
    local env = setmetatable({
      player = player,
      Server = Server,
      print = function (...) player:send_system_message(table.concat(table.pack(...), " ")) end
    }, {__index=_ENV})
    local f, err = load(command:sub(5), "/lua[" .. player.username .. "]", "t", env)
    if not f then
      return player:send_system_message(err or "unknown load error")
    end
    local success, err = pcall(f)
    if not success then
      player:send_system_message(err or "unknown run error")
    end]]
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
