--[[ connection.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

local json = require 'lunajson'
local copas_timer = require 'copas.timer'

local Buffer = require "buffer"
local log = require "log"
local util = require "util"
local registry = require "registry"
local NBT = require "nbt"
local Player = require "player"
local Item = require "item"

local HANDSHAKE_serverbound
local STATUS_serverbound
local STATUS_clientbound
local LOGIN_serverbound
local LOGIN_clientbound
local CONFIGURATION_serverbound
local CONFIGURATION_clientbound
local PLAY_serverbound
local PLAY_clientbound
do
  local packets = util.read_json("packets.json")

  local function flatten(t)
    local t2 = {}
    for k, v in pairs(t) do
      t2[k:gsub("minecraft:", "")] = v.protocol_id
    end
    return t2
  end

  ---@type table<string, integer>
  HANDSHAKE_serverbound = flatten(packets.handshake.serverbound)
  ---@type table<string, integer>
  STATUS_serverbound = flatten(packets.status.serverbound)
  ---@type table<string, integer>
  STATUS_clientbound = flatten(packets.status.clientbound)
  ---@type table<string, integer>
  LOGIN_serverbound = flatten(packets.login.serverbound)
  ---@type table<string, integer>
  LOGIN_clientbound = flatten(packets.login.clientbound)
  ---@type table<string, integer>
  CONFIGURATION_serverbound = flatten(packets.configuration.serverbound)
  ---@type table<string, integer>
  CONFIGURATION_clientbound = flatten(packets.configuration.clientbound)
  ---@type table<string, integer>
  PLAY_serverbound = flatten(packets.play.serverbound)
  ---@type table<string, integer>
  PLAY_clientbound = flatten(packets.play.clientbound)
end

---@class Connection
---@field sock LuaSocket
---@field buffer Buffer
---@field state state
---@field server Server
---@field current_teleport_id integer
---@field current_teleport_acknowledged boolean
---@field keepalive_timer table?
---@field keepalive_id number?
---@field keepalive_received boolean
---@field listening_connections Connection[]
local Connection = {}

---@alias state
---| 0 # handshake
---| 1 # status
---| 2 # login
---| 3 # end login, waiting for client to acknowledge
---| 4 # configuration
---| 5 # end configuration, waiting for client to acknowledge
---| 6 # play
local STATE_HANDSHAKE = 0
local STATE_STATUS = 1
local STATE_LOGIN = 2
local STATE_LOGIN_WAIT_ACK = 3
local STATE_CONFIGURATION = 4
local STATE_CONFIGURATION_WAIT_ACK = 5
local STATE_PLAY = 6


-- Converts the angles sent by the client to the ranges used on the server.
---@param yaw number
---@param pitch number
---@return number yaw, number pitch
local function receive_facing(yaw, pitch)
  if yaw < 0 then
    yaw = math.fmod(yaw, 360) + 360
  else
    yaw = math.fmod(yaw, 360)
  end
  if pitch > 90 then
    pitch = 90
  elseif pitch < -90 then
    pitch = -90
  end
  return yaw, pitch
end

-- Converts the angles used on the server to the correct format for sending to the client.
---@param yaw number
---@param pitch number
---@return integer yaw, integer pitch
local function send_facing(yaw, pitch)
  yaw = math.floor(yaw * (255 / 360))
  if pitch < 0 then
    pitch = math.floor((pitch + 360) * (255 / 360))
  else
    pitch = math.floor(pitch * (255 / 360))
  end
  return yaw, pitch
end


-- Sends a packet to the client.
---@param packet_id integer
---@param data string
function Connection:send(packet_id, data)
  data = Buffer.encode_varint(packet_id) .. data
  data = Buffer.encode_varint(#data) .. data
  log("send: %s", data:gsub(".", function(char) return string.format("%02X", char:byte()) end))
  self.sock:send(data)
end

-- Immediately closes this connection; does not send any information to the client.
function Connection:close()
  self.sock:close()
  -- clear any data we might still have so the loop() doesn't try to read more packets
  self.buffer.data = ""
  -- cancel the keepalive timer if it exists
  if self.keepalive_timer then
    self.keepalive_timer:cancel()
  end
end

-- Disconnects the client with a message. The message will only be sent in the login & play stages, but the connection will always be closed.
---@param message text_component   A table containing a text component: `{ text = "reason" }`
function Connection:disconnect(message)
  if type(message) ~= "table" then
    message = { text = tostring(message) }
  end
  if self.state == STATE_LOGIN then
    self:send(LOGIN_clientbound.login_disconnect, Buffer.encode_string(json.encode(message)))
  elseif self.state == STATE_PLAY then
    self:send(PLAY_clientbound.disconnect, NBT.compound(message))
  end
  self:close()
end

-- Checks if the client has responded to the previous keep alive message. <br>
-- If it has, sends the next keep alive message with a new ID. <br>
-- If it hasn't, disconnects the client using the `"disconnect.timeout"` translation key.
function Connection:keepalive()
  if not self.keepalive_received then
    self:disconnect{ translate = "disconnect.timeout" }
    return
  end
  self.keepalive_id = math.random(math.mininteger, math.maxinteger)  -- lua integers are the same range as a Long
  self:send(PLAY_clientbound.keep_alive, Buffer.encode_long(self.keepalive_id))
end

-- Sends a packet to all other connections that are "listening" to this connection (sending movement/pose actions to other players). <br>
-- This avoids re-encoding the body of the packet for each player (and having to write this for loop all over the place).
---@param packet_id integer
---@param data string
function Connection:send_to_all_listeners(packet_id, data)
  for _, con in pairs(self.listening_connections) do
    con:send(packet_id, data)
  end
end

-- Sends a full "Chunk Data and Update Light" packet to the client.
---@param chunk_x integer
---@param chunk_z integer
---@param data table      The chunk data
function Connection:send_chunk(chunk_x, chunk_z, data)
  local chunk_data = ""

  for i = 1, 24 do
    chunk_data = chunk_data .. Buffer.encode_short(16 * 16 * 16)  -- block count
        .. '\0' .. Buffer.encode_varint(data[i])                  -- block palette - type 0, single valued
        .. Buffer.encode_varint(0)                                -- size of data array (0 for single valued)
        .. '\0' .. Buffer.encode_varint(0)                        -- biome palette - type 0, single valued: 0
        .. Buffer.encode_varint(0)                                -- size of data array (0 for single valued)
  end

  local packet = Buffer.encode_int(chunk_x) .. Buffer.encode_int(chunk_z)
      .. NBT.compound{}                     -- empty heightmaps
      .. Buffer.encode_varint(#chunk_data)  -- chunk data size
      .. chunk_data                         -- chunk data
      .. Buffer.encode_varint(0)            -- # of block entites
      .. Buffer.encode_varint(0)            -- sky light mask (BitSet of length 0)
      .. Buffer.encode_varint(0)            -- block light mask (BitSet of length 0)
      .. Buffer.encode_varint(0)            -- empty sky light mask (BitSet of length 0)
      .. Buffer.encode_varint(0)            -- empty sky light mask (BitSet of length 0)
      .. Buffer.encode_varint(0)            -- sky light array count (empty array)
      .. Buffer.encode_varint(0)            -- block light array count (empty array)

  self:send(PLAY_clientbound.level_chunk_with_light, packet)
end

-- Sends a Block Update packet to the client.
---@param pos blockpos
---@param state integer   The block state ID to set at the position
function Connection:send_block(pos, state)
  self:send(PLAY_clientbound.block_update, Buffer.encode_position(pos) .. Buffer.encode_varint(state))
end

-- Sends a chat message to the client.
---@param type registry.chat_type  The chat type
---@param sender string   The name of the one sending the message
---@param content string  The content of the message
---@param target string?  Optional target of the message, used in some chat types
function Connection:send_chat_message(type, sender, content, target)
  log("sending chat message of type %q from %q with target %q and content %q", type, sender, target, content)
  --TODO: resolving of registry types for chat_type.
  -- also chat type here appears to be indexed starting at 1? instead of 0 like other registries
  local packet = NBT.string(content) .. Buffer.encode_varint(1) .. NBT.string(sender)
  if target then
    packet = packet .. '\1' .. NBT.string(target)
  else
    packet = packet .. '\0'
  end
  self:send(PLAY_clientbound.disguised_chat, packet)
end

-- Sends a system message to the client.
---@param message string
function Connection:send_system_message(message)
  self:send(PLAY_clientbound.system_chat, NBT.string(message) .. '\0')  -- 0 is not overlay/actionbar
end

-- Informs the client that the specified other players exist
---@param players Player[]
function Connection:add_players(players)
  -- 0x01 Add Player | 0x08 Update Listed, # of players in the array
  local players_data = '\x09' .. Buffer.encode_varint(#players)
  for _, player in pairs(players) do
    -- uuid, username, 0 properties, is listed
    players_data = players_data .. player.uuid .. Buffer.encode_string(player.username) .. Buffer.encode_varint(0) .. '\1'
    -- start listening to the player's connection
    player.connection:add_listener(self)
  end
  self:send(PLAY_clientbound.player_info_update, players_data)
end

-- Informs the client that the specified entity spawned
---@param entity Entity
function Connection:add_entity(entity)
  local type_id = registry.entity_types[entity.type]
  local yaw, pitch = send_facing(entity.yaw, entity.pitch)
  self:send(PLAY_clientbound.add_entity, Buffer.encode_varint(entity.id) .. entity.uuid .. Buffer.encode_varint(type_id)
    .. string.pack(">dddBBB", entity.position.x, entity.position.y, entity.position.z, pitch, yaw, yaw)  -- xyz, pitch yaw head_yaw
    .. Buffer.encode_varint(0)                                                                           -- "data" (depends on entity type)
    .. string.pack(">i2i2i2", 0, 0, 0)
  )
end

-- Informs the client of the new position of the entity
---@param entity Entity
function Connection:send_move_entity(entity)
  local yaw, pitch = send_facing(entity.yaw, entity.pitch)
  self:send(PLAY_clientbound.teleport_entity, Buffer.encode_varint(entity.id) .. string.pack(">dddBBB",
    entity.position.x, entity.position.y, entity.position.z, yaw, pitch, 1  -- 1 is on ground
  ))
  self:send(PLAY_clientbound.rotate_head, Buffer.encode_varint(entity.id) .. string.char(yaw))
end

-- Informs the client that the specified other players no longer exist
---@param players Player[]
function Connection:remove_players(players)
  local players_data = Buffer.encode_varint(#players)
  for _, player in pairs(players) do
    players_data = players_data .. player.uuid
    -- stop listening to the player's connection
    player.connection:remove_listener(self)
  end
  self:send(PLAY_clientbound.player_info_remove, players_data)
end

-- Informs the client that the specified entities no longer exist
---@param entities Entity[]
function Connection:remove_entities(entities)
  local entities_data = Buffer.encode_varint(#entities)
  for _, entity in pairs(entities) do
    entities_data = entities_data .. Buffer.encode_varint(entity.id)
  end
  self:send(PLAY_clientbound.remove_entities, entities_data)
end

-- Synchronizes the Player's position with the client. Handles the "Teleport ID" stuff with the accept teleport packet.
function Connection:synchronize_position()
  self.current_teleport_id = self.current_teleport_id + 1
  self.current_teleport_acknowledged = false
  local pos = self.player.position
  local yaw, pitch = self.player.yaw, self.player.pitch  -- as floats, not 1/256ths of rotation
  self:send(PLAY_clientbound.player_position, string.pack(">dddffb", pos.x, pos.y, pos.z, yaw, pitch, 0) .. Buffer.encode_varint(self.current_teleport_id))
end

-- Indicates that the specified connection is listening to this connection's movement/pose actions.
---@param con Connection
function Connection:add_listener(con)
  table.insert(self.listening_connections, con)
end

-- Indicates that the specified connection is no longerlistening to this connection's movement/pose actions.
---@param con Connection
function Connection:remove_listener(con)
  util.remove_value(self.listening_connections, con)
end

-- Sets the state of the Connection & sets the proper packet handling function
---@param state state
function Connection:set_state(state)
  if state == STATE_HANDSHAKE then
    self.handle_packet = Connection.handle_packet_handshake
  elseif state == STATE_STATUS then
    self.handle_packet = Connection.handle_packet_status
  elseif state == STATE_LOGIN or state == STATE_LOGIN_WAIT_ACK then
    self.handle_packet = Connection.handle_packet_login
  elseif state == STATE_CONFIGURATION or state == STATE_CONFIGURATION_WAIT_ACK then
    self.handle_packet = Connection.handle_packet_configuration
  elseif state == STATE_PLAY then
    self.handle_packet = Connection.handle_packet_play
  else
    error("unknown state %i", state)
  end
  self.state = state
end

-- Handles a single packet in the handshake state
---@param packet_id integer
function Connection:handle_packet_handshake(packet_id)
  if packet_id == HANDSHAKE_serverbound.intention then
    -- Begin connection (corresponds to "Connecting to the server..." on the client connection screen
    local protocol_id = self.buffer:read_varint()
    local server_addr = self.buffer:read_string()
    local server_port = self.buffer:read_short()
    local next_state = self.buffer:read_varint()
    log("handshake from protocol %i to %s:%i, next state: %i", protocol_id, server_addr, server_port, next_state)
    if next_state == 1 then
      self:set_state(STATE_STATUS)
    elseif next_state == 2 then
      self:set_state(STATE_LOGIN)
    else  -- can't accept transfer logins (yet?)
      self:set_state(STATE_LOGIN)
      self:disconnect{ translate = "multiplayer.disconnect.transfers_disabled" }
    end
  else
    log("received unexpected packet id 0x%02X in handshake state (%i)", packet_id, self.state)
    self:close()
  end
end

local status_response = Buffer.encode_string(
  json.encode{
    version = { name = "1.21", protocol = 767 },
    players = { max = 0, online = 2,
      sample = {
        { name = "Penguin_Spy", id = "dfbd911d-9775-495e-aac3-efe339db7efd" }
      }
    },
    description = { text = "woah haiii :3" },
    enforcesSecureChat = false,
    previewsChat = false
  }
)
-- Handles a single packet in the status state
---@param packet_id integer
function Connection:handle_packet_status(packet_id)
  if packet_id == STATUS_serverbound.status_request then
    log("status request")
    self:send(STATUS_clientbound.status_response, status_response)

    --
  elseif packet_id == STATUS_serverbound.ping_request then
    log("ping request with data %s", self.buffer:dump(8))
    self:send(STATUS_clientbound.pong_response, self.buffer:read(8))

    --
  else
    log("received unexpected packet id 0x%02X in status state (%i)", packet_id, self.state)
    self:close()
  end
end


-- Handles a single packet in the login state
---@param packet_id integer
function Connection:handle_packet_login(packet_id)
  -- only valid to receive BEFORE we've sent the game_profile packet
  if packet_id == LOGIN_serverbound.hello and self.state == STATE_LOGIN then
    local username = self.buffer:read_string()
    local uuid_str = self.buffer:dump(16)
    self.buffer:read_to_end()  -- discard client-sent UUID
    local uuid = util.new_UUID()
    log("login start: '%s' (client sent %s, joining as %s)", username, uuid_str, util.UUID_to_string(uuid))
    -- TODO: encryption & compression

    local accept, message = self.server.on_login(username)
    if not accept then
      self:disconnect(message or "Login refused")
      return
    end

    self.player = Player._new(username, uuid, self)

    -- Send login success (corresponds to "Joining world..." on the client connection screen)
    self:send(LOGIN_clientbound.game_profile, uuid .. Buffer.encode_string(username) .. Buffer.encode_varint(0) .. '\1')  -- last byte is strict error handling
    self:set_state(STATE_LOGIN_WAIT_ACK)

    -- only valid to receive AFTER we've sent the game_profile packet
  elseif packet_id == LOGIN_serverbound.login_acknowledged and self.state == STATE_LOGIN_WAIT_ACK then
    log("login ack'd")
    self:set_state(STATE_CONFIGURATION)
    -- send server brand
    self:send(CONFIGURATION_clientbound.custom_payload, Buffer.encode_string("minecraft:brand") .. Buffer.encode_string("quasar"))
    -- super cool extra data in the new "protocol error report"
    self:send(CONFIGURATION_clientbound.custom_report_details, Buffer.encode_varint(1) .. Buffer.encode_string("quasar server") .. Buffer.encode_string("https://github.com/Penguin-Spy/quasar"))
    -- bug report link (just testing this, it seems neat. should make this available to ppl using the library)
    self:send(CONFIGURATION_clientbound.server_links, Buffer.encode_varint(1) .. '\1' .. Buffer.encode_varint(0) .. Buffer.encode_string("https://github.com/Penguin-Spy/quasar/issues"))
    -- send feature flags packet (enable vanilla features (not required for registry sync/client to connect, but probably important))
    self:send(CONFIGURATION_clientbound.update_enabled_features, Buffer.encode_varint(1) .. Buffer.encode_string("minecraft:vanilla"))
    -- start datapack negotiation (official server declares the "minecraft:core" datapack with version "1.21")
    self:send(CONFIGURATION_clientbound.select_known_packs, Buffer.encode_varint(1) .. Buffer.encode_string("minecraft") .. Buffer.encode_string("core") .. Buffer.encode_string("1.21"))

    --
  else
    log("received unexpected packet id 0x%02X in login state (%i)", packet_id, self.state)
    self:close()
  end
end

-- Handles a single packet in the configuration state
---@param packet_id integer
function Connection:handle_packet_configuration(packet_id)
  -- only valid to receive BEFORE we've sent the finish_configuration packet
  if packet_id == CONFIGURATION_serverbound.select_known_packs and self.state == STATE_CONFIGURATION then
    local client_known_pack_count = self.buffer:read_varint()
    log("serverbound known packs (known on the client): %i", client_known_pack_count)
    -- TODO: validate that the client does actually know about minecraft:core with version 1.21
    for i = 1, client_known_pack_count do
      local pack_namespace = self.buffer:read_string()
      local pack_id = self.buffer:read_string()
      local pack_version = self.buffer:read_string()
      log("  client knows pack %s:%s of version %s", pack_namespace, pack_id, pack_version)
    end

    -- send registry data
    local regs = registry.network_data
    self:send(CONFIGURATION_clientbound.registry_data, regs["worldgen/biome"])
    self:send(CONFIGURATION_clientbound.registry_data, regs.chat_type)
    self:send(CONFIGURATION_clientbound.registry_data, regs.trim_pattern)
    self:send(CONFIGURATION_clientbound.registry_data, regs.trim_material)
    self:send(CONFIGURATION_clientbound.registry_data, regs.wolf_variant)
    self:send(CONFIGURATION_clientbound.registry_data, regs.painting_variant)
    self:send(CONFIGURATION_clientbound.registry_data, regs.dimension_type)
    self:send(CONFIGURATION_clientbound.registry_data, regs.damage_type)
    self:send(CONFIGURATION_clientbound.registry_data, regs.banner_pattern)
    self:send(CONFIGURATION_clientbound.registry_data, regs.enchantment)
    self:send(CONFIGURATION_clientbound.registry_data, regs.jukebox_song)

    self:send(CONFIGURATION_clientbound.finish_configuration, "")  -- then tell client we're finished with configuration, u can ack when you're done sending stuff
    self:set_state(STATE_CONFIGURATION_WAIT_ACK)

    --
  elseif packet_id == CONFIGURATION_serverbound.client_information then
    self.buffer:read_to_end()
    log("client information (configuration)")

    --
  elseif packet_id == CONFIGURATION_serverbound.custom_payload then
    local channel = self.buffer:read_string()
    local data = self.buffer:read_to_end()
    log("plugin message (configuration) on channel '%s' with data: '%s'", channel, data)

    -- only valid to receive AFTER we've sent the finish_configuration packet
  elseif packet_id == CONFIGURATION_serverbound.finish_configuration and self.state == STATE_CONFIGURATION_WAIT_ACK then
    log("configuration finish ack")
    self:set_state(STATE_PLAY)

    local player = self.player
    -- allow setup of player event handlers & loading inventory, dimension, etc.
    local accept, message = self.server.on_join(player)
    if not accept then
      self:disconnect(message or "Join refused")
      self:close()
      return
    end

    -- add the player to the default dimension if the on_join handler didn't add them to any
    if not player.dimension then
      player.dimension = self.server.get_default_dimension()
    end
    local dim = player.dimension

    -- send login (Corresponds to "Loading terrain..." on the client connection screen)
    self:send(PLAY_clientbound.login, Buffer.encode_int(0) .. '\0'  -- entity id, is hardcore
      .. Buffer.encode_varint(0)                                    -- dimensions (appears to be ignored?)
      .. Buffer.encode_varint(0)                                    -- "max players" (unused)
      .. Buffer.encode_varint(10)                                   -- view dist
      .. Buffer.encode_varint(5)                                    -- sim dist
      .. '\0\1\0'                                                   -- reduced debug, respawn screen, limited crafting
      .. Buffer.encode_varint(0)                                    -- starting dim type (registry id)
      .. Buffer.encode_string(dim.identifier)                       -- starting dim name
      .. Buffer.encode_long(0)                                      -- hashed seeed
      .. '\1\255\0\0\0'                                             -- game mode (creative), prev game mode (-1 undefined), is debug, is flat, has death location
      .. Buffer.encode_varint(0)                                    -- portal cooldown (unknown use)
      .. '\1'                                                       -- enforces secure chat (causes giant warning toast to show up if false, seemingly no other effects?)
    )
    -- spawns player in dimension and loads entities
    dim:_add_player(player)

    -- synchronize player position (do this first so the client doesn't default to (8.5,65,8.5) when chunks are sent)
    self:synchronize_position()
    -- this does stuff with flight (flying + flight disabled + 0 fly speed -> locks player in place)
    -- invulnerable (unknown effect), flying, allow flying (allow toggling flight), creative mode/instant break (unknown effect), fly speed, fov modifier
    --self:send(PLAY_clientbound.player_abilities, string.pack(">bff", 0x01 | 0x02 | 0x04 | 0x08, 0.05, 0.1))

    self:send(PLAY_clientbound.game_event, "\13\0\0\0\0")  -- game event 13 (start waiting for chunks), float param of always 0

    -- send chunks (this closes the connection screen and shows the player in the world)
    for x = -4, 4 do
      for z = -4, 4 do
        self:send_chunk(x, z, dim:get_chunk(x, z, player))
      end
    end

    self.keepalive_timer = copas_timer.new{
      name      = "quasar_connection_keepalive[" .. player.username .. "]",
      recurring = true,
      delay     = 15,
      callback  = function() self:keepalive() end
    }
    self:keepalive()  -- start the keepalive cycle
  else
    log("received unexpected packet id 0x%02X in configuration state (%i)", packet_id, self.state)
    self:close()
  end
end

-- Handles a single packet in the play state
---@param packet_id integer
function Connection:handle_packet_play(packet_id)
  if packet_id == PLAY_serverbound.keep_alive then
    local keepalive_id = self.buffer:read_long()
    if keepalive_id == self.keepalive_id then
      self.keepalive_received = true
    else
      log("ignoring incorrect keepalive id %i", keepalive_id)
    end
    --
  elseif packet_id == PLAY_serverbound.accept_teleportation then
    local teleport_id = self.buffer:read_varint()
    if teleport_id == self.current_teleport_id then
      log("confirm teleport #%i", teleport_id)
      self.current_teleport_acknowledged = true
    else
      log("ignoring incorrect confirm teleport #%i", teleport_id)
    end

    --
  elseif packet_id == PLAY_serverbound.chat then
    local message = self.buffer:read_string()
    local timestamp = self.buffer:dump(8)
    local salt = self.buffer:dump(8)
    self.buffer:read(16)  -- discard what we just dumped
    local has_signature = self.buffer:byte()
    self.buffer:read_to_end()
    log("chat msg from '%s' at %s salt %s signed %q: %s", self.player.username, timestamp, salt, has_signature, message)

    if #message > 256 then
      error("received too long chat message")
    end

    self.player:on_chat_message(message)

    --
  elseif packet_id == PLAY_serverbound.chat_command then
    local command = self.buffer:read_string()
    if #command > 32767 then
      error("received too long command")
    end
    log("chat command from '%s': %s", self.player.username, command)
    self.player:on_command(command)

    --
  elseif packet_id == PLAY_serverbound.client_information then
    self.buffer:read_to_end()
    log("client information (play)")

    --
  elseif packet_id == PLAY_serverbound.custom_payload then
    local channel = self.buffer:read_string()
    local data = self.buffer:read_to_end()
    log("plugin message (play) on channel '%s' with data: '%s'", channel, data)

    --
  elseif packet_id == PLAY_serverbound.move_player_pos then
    self.player.position:set(self.buffer:read_double(), self.buffer:read_double(), self.buffer:read_double())
    self.player.on_ground = self.buffer:byte() ~= 0
    for _, con in pairs(self.listening_connections) do
      con:send_move_entity(self.player)
    end

    --
  elseif packet_id == PLAY_serverbound.move_player_pos_rot then
    self.player.position:set(self.buffer:read_double(), self.buffer:read_double(), self.buffer:read_double())
    self.player.yaw, self.player.pitch = receive_facing(self.buffer:read_float(), self.buffer:read_float())
    self.player.on_ground = self.buffer:byte() ~= 0
    for _, con in pairs(self.listening_connections) do
      con:send_move_entity(self.player)
    end

    --
  elseif packet_id == PLAY_serverbound.move_player_rot then
    self.player.yaw, self.player.pitch = receive_facing(self.buffer:read_float(), self.buffer:read_float())
    self.player.on_ground = self.buffer:byte() ~= 0
    for _, con in pairs(self.listening_connections) do
      con:send_move_entity(self.player)
    end

    --
  elseif packet_id == PLAY_serverbound.move_player_status_only then
    log("player on ground: %q", self.buffer:byte() ~= 0)

    --
  elseif packet_id == PLAY_serverbound.player_abilities then
    local abilities = self.buffer:byte()
    log("player abilities: %02X", abilities)

    --
  elseif packet_id == PLAY_serverbound.player_command then
    self.buffer:read_varint()  -- always the player's entity ID
    local action = self.buffer:read_varint()
    self.buffer:read_to_end()  -- VarInt horse jump strength, or 0 if not jumping
    if action == 0 then
      self.player.sneaking = true
    elseif action == 1 then
      self.player.sneaking = false
    elseif action == 3 then
      self.player.sprinting = true
    elseif action == 4 then
      self.player.sprinting = false
    end
    self:send_to_all_listeners(PLAY_clientbound.set_entity_data, Buffer.encode_varint(self.player.id)
      -- sneaking causes the nametag to become fainter and hidden behind walls, sprinting causes the running particles to appear
      .. '\0' .. Buffer.encode_varint(0) .. string.char((self.player.sneaking and 0x02 or 0) | (self.player.sprinting and 0x08 or 0))
      -- sets the sneaking/standing pose
      .. '\6' .. Buffer.encode_varint(21) .. Buffer.encode_varint(self.player.sneaking and 5 or 0)
      .. '\xff')

    --
  elseif packet_id == PLAY_serverbound.set_carried_item then
    local slot = self.buffer:read_short()
    log("select slot %i", slot)
    self.player:on_select_hotbar_slot(slot)

    --
  elseif packet_id == PLAY_serverbound.set_creative_mode_slot then
    local slot = self.buffer:read_short()

    local item_count = self.buffer:read_varint()
    if item_count > 0 then
      local item_id = self.buffer:read_varint()
      local components_to_add_count = self.buffer:read_varint()
      local components_to_remove_count = self.buffer:read_varint()
      log("set slot %i to item #%i x%i (+%i,-%i)", slot, item_id, item_count, components_to_add_count, components_to_remove_count)
      -- TODO: read component data, construct actual item object
      self.buffer:read_to_end()
      self.player:on_set_slot(slot, nil)
    else
      log("set slot %i to item of 0 count", slot)
      self.player:on_set_slot(slot, nil)
    end

    --
  elseif packet_id == PLAY_serverbound.container_close then
    log("close screen %i", self.buffer:byte())

    --
  elseif packet_id == PLAY_serverbound.seen_advancements then
    local action, tab_id = self.buffer:read_varint()
    if action == 0 then
      tab_id = self.buffer:read_string()
    end
    log("seen advancements: action %i, tab %s", action, tab_id or "n/a")

    --
  elseif packet_id == PLAY_serverbound.player_action then
    local action = self.buffer:read_varint()
    local pos = self.buffer:read_position()
    local face = self.buffer:byte()
    local seq = self.buffer:read_varint()
    log("player action: action %i, pos (%i,%i,%i), face %i, seq %i", action, pos.x, pos.y, pos.z, face, seq)

    self.player.dimension:on_break_block(self.player, pos)
    -- acknowledge the block breaking so the client shows the block state the server says instead of its predicted state
    self:send(PLAY_clientbound.block_changed_ack, Buffer.encode_varint(seq))

    --
  elseif packet_id == PLAY_serverbound.swing then
    local arm_animation = self.buffer:read_varint() == 0 and '\0' or '\3'  -- arm 0 is animation 0, arm 1 (offhand) is animation 3
    self:send_to_all_listeners(PLAY_clientbound.animate, Buffer.encode_varint(self.player.id) .. arm_animation)

    --
  elseif packet_id == PLAY_serverbound.use_item_on then
    local hand = self.buffer:read_varint()
    local pos = self.buffer:read_position()
    local face = self.buffer:byte()
    local cursor_x = self.buffer:read_float()
    local cursor_y = self.buffer:read_float()
    local cursor_z = self.buffer:read_float()
    local inside_block = self.buffer:byte() == 1
    local seq = self.buffer:read_varint()

    local slot = hand == 1 and 45 or self.player.selected_slot + 36
    log("use item of hand %i (slot %i) on block (%i,%i,%i) face %i at (%f,%f,%f) in block: %q", hand, slot, pos.x, pos.y, pos.z, face, cursor_x, cursor_y, cursor_z, inside_block)
    self.player.dimension:on_use_item_on_block(self.player, slot, pos, face, { x = cursor_x, y = cursor_y, z = cursor_z }, inside_block)
    -- acknowledge the item use
    self:send(PLAY_clientbound.block_changed_ack, Buffer.encode_varint(seq))

    --
  elseif packet_id == PLAY_serverbound.use_item then
    local hand = self.buffer:read_varint()
    local seq = self.buffer:read_varint()
    local yaw = self.buffer:read_float()
    local pitch = self.buffer:read_float()
    local slot = hand == 1 and 45 or self.player.selected_slot + 36
    log("use item of hand %i (slot %i) facing %f,%f", hand, slot, yaw, pitch)
    self.player.dimension:on_use_item(self.player, slot, yaw, pitch)
    -- acknowledge the item use
    self:send(PLAY_clientbound.block_changed_ack, Buffer.encode_varint(seq))

    --
  else
    log("received unexpected packet id 0x%02X in play state (%s)", packet_id, self.state)
    self:close()
  end
end

function Connection:handle_legacy_ping()
  self.buffer:read(27)                          -- discard irrelevant stuff
  local protocol_id = self.buffer:byte()
  local str_len = self.buffer:read_short() * 2  -- UTF-16BE
  local server_addr = self.buffer:read(str_len)
  local server_port = self.buffer:read_int()
  log("legacy ping from protocol %i addr %s port %i", protocol_id, server_addr, server_port)
  self.sock:send("\xFF\x00\029\x00\xA7\x001\x00\x00\x001\x002\x007\x00\x00\x001\x00.\x002\x001\x00\x00\x00w\x00o\x00a\x00h\x00 \x00h\x00a\x00i\x00i\x00i\x00 \x00:\x003\x00\x00\x000\x00\x00\x000")
  self:close()
end

-- Receive loop
function Connection:loop()
  log("open '%s'", self)
  self:set_state(STATE_HANDSHAKE)
  while true do
    local _, err, data = self.sock:receivepartial("*a")
    if err == "timeout" then
      self.buffer:append(data)
      log("receive %s", self.buffer:dump())
      repeat
        local length = self.buffer:try_read_varint()
        if length == 254 and self.buffer:peek_byte() == 0xFA then
          self:handle_legacy_ping()
        elseif length then
          self.buffer:set_end(length)
          self:handle_packet(self.buffer:read_varint())
        else
        end
      until not length
    else
      log("close '%s' - %s", self, err)
      if self.player then              -- if this connection was in the game
        -- TODO: any dimensionless player cleanup
        if self.player.dimension then  -- if this player was in a dimension
          self.player.dimension:_remove_player(self.player)
        end
      end
      if self.keepalive_timer then
        self.keepalive_timer:cancel()
      end
      break
    end
  end
end

function Connection:tostring()
  local ip, port, family = self.sock:getpeername()
  if ip then
    return "Connection " .. ip .. ":" .. port .. " (" .. family .. ")"
  else
    return "Connection " .. tostring(self.sock)
  end
end

local mt = {
  __index = Connection,
  __tostring = Connection.tostring
}

-- Constructs a new Connection on the give socket
---@param sock LuaSocket
---@param server Server  a reference to the Server (can't require bc circular dependency)
---@return Connection
local function new(sock, server)
  ---@type Connection
  local self = {
    sock = sock,
    buffer = Buffer.new(),
    state = STATE_HANDSHAKE,
    server = server,
    current_teleport_id = 0,
    current_teleport_acknowledged = true,
    keepalive_received = true,
    listening_connections = {}
  }
  setmetatable(self, mt)
  return self
end

return {
  new = new
}
