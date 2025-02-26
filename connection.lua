--[[ connection.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.

  The Covered Software may not be used as training or other input data
  for LLMs, generative AI, or other forms of machine learning or neural
  networks.
]]

local json = require 'lunajson'
local copas_timer = require 'copas.timer'
local http = require 'copas.http'

local ReceiveBuffer = require "ReceiveBuffer"
local SendBuffer = require 'SendBuffer'
local log = require "log"
local util = require "util"
local Registry = require "registry"
local NBT = require "nbt"
local Player = require "player"
local Item = require "item"

---@class Server
local Server
-- only require "openssl.cipher",  "openssl.digest", and "openssl.bignum" if the server has encryption enabled
local cipher, digest, bn

local server_version <const>, server_protocol <const> = "1.21.4", 769

---@class openssl.cipher
---@field update fun(self:openssl.cipher, data:string):string, string?

---@class Connection
---@field sock LuaSocket
---@field buffer ReceiveBuffer
---@field state state
---@field player Player
---@field encrypted boolean               whether this connection is encrypted
---@field verify_token string?            4 byte random value to ensure encryption initalized correctly
---@field encryption_username string?     temporary, only for connecting to the session server<br>use Player.username instead!
---@field send_cipher openssl.cipher?     the encryption cipher for sending data
---@field receive_cipher openssl.cipher?  the encryption cipher for receiving data
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
---| 3 # login, waiting for encryption response
---| 4 # end login, waiting for client to acknowledge
---| 5 # configuration
---| 6 # end configuration, waiting for client to acknowledge
---| 7 # play
---| 8 # closed
local STATE_HANDSHAKE <const> = 0
local STATE_STATUS <const> = 1
local STATE_LOGIN <const> = 2
local STATE_LOGIN_WAIT_ENCRYPT <const> = 3
local STATE_LOGIN_WAIT_ACK <const> = 4
local STATE_CONFIGURATION <const> = 5
local STATE_CONFIGURATION_WAIT_ACK <const> = 6
local STATE_PLAY <const> = 7
local STATE_CLOSED <const> = 8

---@type {[state]:{[string]:integer}}, {[state]:{[string]:integer}}
local clientbound_packet_id, serverbound_packet_id = {}, {}
do
  local packets = util.read_json("data/packets.json")
  ---@return {[string]: integer}
  local function flatten(t)
    local t2 = {}
    for k, v in pairs(t) do
      t2[k:gsub("minecraft:", "")] = v.protocol_id
    end
    return t2
  end

  serverbound_packet_id[STATE_HANDSHAKE] = flatten(packets.handshake.serverbound)

  serverbound_packet_id[STATE_STATUS] = flatten(packets.status.serverbound)
  clientbound_packet_id[STATE_STATUS] = flatten(packets.status.clientbound)

  serverbound_packet_id[STATE_LOGIN] = flatten(packets.login.serverbound)
  serverbound_packet_id[STATE_LOGIN_WAIT_ENCRYPT] = serverbound_packet_id[STATE_LOGIN]
  serverbound_packet_id[STATE_LOGIN_WAIT_ACK] = serverbound_packet_id[STATE_LOGIN]
  clientbound_packet_id[STATE_LOGIN] = flatten(packets.login.clientbound)
  clientbound_packet_id[STATE_LOGIN_WAIT_ENCRYPT] = clientbound_packet_id[STATE_LOGIN]
  clientbound_packet_id[STATE_LOGIN_WAIT_ACK] = clientbound_packet_id[STATE_LOGIN]

  serverbound_packet_id[STATE_CONFIGURATION] = flatten(packets.configuration.serverbound)
  serverbound_packet_id[STATE_CONFIGURATION_WAIT_ACK] = serverbound_packet_id[STATE_CONFIGURATION]
  clientbound_packet_id[STATE_CONFIGURATION] = flatten(packets.configuration.clientbound)
  clientbound_packet_id[STATE_CONFIGURATION_WAIT_ACK] = clientbound_packet_id[STATE_CONFIGURATION]

  serverbound_packet_id[STATE_PLAY] = flatten(packets.play.serverbound)
  clientbound_packet_id[STATE_PLAY] = flatten(packets.play.clientbound)
end

---@type {[state]:{[integer]:fun(self:Connection)}}
local packet_handlers = {}
---@param state state
---@param packet_name string
---@param handler fun(self:Connection)
local function handle(state, packet_name, handler)
  packet_handlers[state] = packet_handlers[state] or {}
  packet_handlers[state][serverbound_packet_id[state][packet_name]] = handler
end


--= Connection methods =--

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

-- Sends a raw packet to the client (i.e. an already `concat`ed buffer).
---@param self Connection
---@param data string       The packet's data, including the packet id.
local function send_raw(self, data)
  local packet, err = SendBuffer():varint(#data):raw(data):concat()
  if self.encrypted then
    packet, err = self.send_cipher:update(packet)
    if packet == "" then
      return  -- "The returned string may be empty if no blocks can be flushed."
    elseif not packet then
      error(err)
    end
  end
  self.sock:send(packet)
end

-- Sends a packet to the client.
---@param packet_name string    The resource name of the packet; the protocol id is determined based on the state of this connection
---@param buffer SendBuffer   The buffer's contents are not modified
function Connection:send(packet_name, buffer)
  send_raw(self, buffer:concat_and_prepend_varint(clientbound_packet_id[self.state][packet_name]))
end

-- Sends a packet to all other connections that are "listening" to this connection (sending movement/pose actions to other players). <br>
-- This avoids re-encoding the body of the packet for each player (and having to write this for loop all over the place).
---@param packet_name string
---@param buffer SendBuffer   The buffer's contents are not modified
function Connection:send_to_all_listeners(packet_name, buffer)
  local data = buffer:concat_and_prepend_varint(clientbound_packet_id[self.state][packet_name])
  for _, con in pairs(self.listening_connections) do
    send_raw(con, data)
  end
end

-- Immediately closes this connection; does not send any information to the client.
function Connection:close()
  self.sock:close()
  self:set_state(STATE_CLOSED)
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
  if self.state == STATE_LOGIN or self.state == STATE_LOGIN_WAIT_ENCRYPT then
    self:send("login_disconnect", SendBuffer():string(json.encode(message)))
  elseif self.state == STATE_PLAY then
    self:send("disconnect", SendBuffer():raw(NBT.compound(message)))
  end
  self:close()
end

-- Checks if the client has responded to the previous keep alive message. <br>
-- If it has, sends the next keep alive message with a new ID. <br>
-- If it hasn't, disconnects the client using the `"disconnect.timeout"` translation key.
function Connection:keepalive()
  if not self.keepalive_received then
    log("disconnecting %s because it timed out", self)
    self:disconnect{ translate = "disconnect.timeout" }
    return
  end
  self.keepalive_id = math.random(math.mininteger, math.maxinteger)  -- lua integers are the same range as a Long
  self:send("keep_alive", SendBuffer():long(self.keepalive_id))
end

-- Sends a full "Chunk Data and Update Light" packet to the client.
---@param chunk_x integer
---@param chunk_z integer
---@param chunk Chunk      The chunk data
function Connection:send_chunk(chunk_x, chunk_z, chunk)
  local buffer = SendBuffer()
  local chunk_data = chunk:get_data()

  buffer:int(chunk_x)
  buffer:int(chunk_z)
  buffer:raw(NBT.compound{})  -- empty heightmaps

  buffer:raw(chunk_data)      -- chunk data (includes size)

  buffer:varint(0)            -- # of block entites
  buffer:varint(0)            -- sky light mask (BitSet of length 0)
  buffer:varint(0)            -- block light mask (BitSet of length 0)
  buffer:varint(0)            -- empty sky light mask (BitSet of length 0)
  buffer:varint(0)            -- empty sky light mask (BitSet of length 0)
  buffer:varint(0)            -- sky light array count (empty array)
  buffer:varint(0)            -- block light array count (empty array)

  self:send("level_chunk_with_light", buffer)
end

-- Sends a Block Update packet to the client.
---@param pos blockpos
---@param state integer   The block state ID to set at the position
function Connection:send_block(pos, state)
  self:send("block_update", SendBuffer():position(pos):varint(state))
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
  local buffer = SendBuffer():raw(NBT.string(content)):varint(1):raw(NBT.string(sender))
  if target then
    buffer:boolean(true):raw(NBT.string(target))
  else
    buffer:boolean(false)  -- has target name
  end
  self:send("disguised_chat", buffer)
end

-- Sends a system message to the client.
---@param message string
function Connection:send_system_message(message)
  self:send("system_chat", SendBuffer():raw(NBT.string(message)):boolean(false))  -- false is not overlay/actionbar
end

-- Informs the client that the specified other players exist
---@param players Player[]
function Connection:add_players(players)
  -- player info: 0x01 Add Player | 0x08 Update Listed, # of players in the array
  local buffer = SendBuffer():byte(0x09):varint(#players)
  for _, player in pairs(players) do
    -- uuid, username
    buffer:raw(player.uuid):string(player.username)
    -- properties
    if player.skin.texture then
      buffer:varint(1):string("textures"):string(player.skin.texture)
      if player.skin.texture_signature then
        buffer:boolean(true):string(player.skin.texture_signature)
      else
        buffer:boolean(false)
      end
    else
      buffer:varint(0)
    end
    -- is listed
    buffer:boolean(true)

    -- player entity metadata (the player's own entity id is always 0)
    self:send("set_entity_data", SendBuffer():varint(player == self.player and 0 or player.id)
      -- sneaking causes the nametag to become fainter and hidden behind walls, sprinting causes the running particles to appear
      :byte(0):varint(0):byte((player.sneaking and 0x02 or 0) | (player.sprinting and 0x08 or 0))
      -- sets the sneaking/standing pose
      :byte(6):varint(21):varint(player.sneaking and 5 or 0)
      -- skin layers
      :byte(17):varint(0):byte(player.skin.layers)
      -- main hand
      :byte(18):varint(0):byte(player.skin.hand)
      :byte(0xff))

    -- start listening to the player's connection (unless it's ourselves)
    if player ~= self.player then
      player.connection:add_listener(self)
    end
  end
  self:send("player_info_update", buffer)
end

-- Informs the client that the specified entity spawned
---@param entity Entity
function Connection:add_entity(entity)
  local type_id = Registry.entity_types[entity.type]
  local yaw, pitch = send_facing(entity.yaw, entity.pitch)
  self:send("add_entity", SendBuffer():varint(entity.id):raw(entity.uuid):varint(type_id)
    :pack(">dddBBB", entity.position.x, entity.position.y, entity.position.z, pitch, yaw, yaw)  -- xyz, pitch yaw head_yaw
    :varint(0)                                                                                  -- "data" (depends on entity type)
    :pack(">i2i2i2", 0, 0, 0)                                                                   -- velocity (as shorts)
  )
end

-- Informs the client of the new position of the entity
---@param entity Entity
function Connection:send_move_entity(entity)
  local yaw, pitch = send_facing(entity.yaw, entity.pitch)
  self:send("teleport_entity", SendBuffer():varint(entity.id):pack(">dddBBB",
    entity.position.x, entity.position.y, entity.position.z, yaw, pitch, 1  -- 1 is on ground
  ))
  self:send("rotate_head", SendBuffer():varint(entity.id):byte(yaw))
end

-- Informs the client that the specified other players no longer exist
---@param players Player[]
function Connection:remove_players(players)
  local buffer = SendBuffer():varint(#players)
  for _, player in pairs(players) do
    buffer:raw(player.uuid)
    -- stop listening to the player's connection
    player.connection:remove_listener(self)
  end
  self:send("player_info_remove", buffer)
end

-- Informs the client that the specified entities no longer exist
---@param entities Entity[]
function Connection:remove_entities(entities)
  local buffer = SendBuffer():varint(#entities)
  for _, entity in pairs(entities) do
    buffer:varint(entity.id)
  end
  self:send("remove_entities", buffer)
end

-- Synchronizes the Player's position with the client. Handles the "Teleport ID" stuff with the accept teleport packet.
function Connection:synchronize_position()
  self.current_teleport_id = self.current_teleport_id + 1
  self.current_teleport_acknowledged = false
  local pos = self.player.position
  local yaw, pitch = self.player.yaw, self.player.pitch  -- as floats, not 1/256ths of rotation
  self:send("player_position", SendBuffer()
    :varint(self.current_teleport_id)
    :pack(">ddddddffI4", pos.x, pos.y, pos.z, 0, 0, 0, yaw, pitch, 0) -- xyz, xyz velocity, yaw/pitch, flags (all absolute)
  )
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

-- Respawns the player, used both when they are dead to respawn them, as well as when changing dimensions (`player.dimension` must be changed before calling this function).
---@param data_kept integer           Bit mask. 0x01: Keep attributes, 0x02: Keep metadata (includes potion effects).
---@param changing_dimension boolean  true if changing the dimension the player is in; must be set for the loading screen to close correctly
function Connection:respawn(data_kept, changing_dimension)
  local dim = self.player.dimension
  self:send("respawn", SendBuffer()
    :varint(Registry.dimension_type[dim.type])                       -- starting dim type (registry id)
    :string(dim.identifier)                                          -- starting dim name
    :long(0)                                                         -- hashed seeed
    :byte(1):byte(255):boolean(false):boolean(false):boolean(false)  -- game mode (creative), prev game mode (-1 undefined), is debug, is flat, has death location
    :varint(0)                                                       -- portal cooldown (unknown use)
    :varint(63)                                                      -- sea level
    :byte(data_kept)                                                 -- normal respawns keep no data, dimension changes keep all, end portal only keeps attributes
  )
  if changing_dimension then                                         -- must be sent before chunks for the new dimension
    self:send("game_event", SendBuffer():byte(13):int(0))
  end
end

-- Sets the center chunk around which loaded chunks can be sent, and chunks outside get unloaded. <br>
-- The area where the client accepts chunks is a square with sides `2r+7`, and chunks are rendered in a `2r+1` square, <br>
-- where `r` is the server render distance.
---@param x integer Chunk x
---@param z integer Chunk z
function Connection:send_set_center_chunk(x, z)
  self:send("set_chunk_cache_center", SendBuffer():varint(x):varint(z))
end

-- Sets the state of the Connection
---@param state state
function Connection:set_state(state)
  self.handle_packet = packet_handlers[state]
  self.state = state
end


--= handshake state packet handlers =--

handle(STATE_HANDSHAKE, "intention", function (self)
  -- Begin connection (corresponds to "Connecting to the server..." on the client connection screen)
  local protocol_id = self.buffer:varint()
  local server_addr = self.buffer:string()
  local server_port = self.buffer:short()
  local next_state = self.buffer:varint()
  log("handshake from protocol %i to %s:%i, next state: %i", protocol_id, server_addr, server_port, next_state)
  if next_state == 1 then
    self:set_state(STATE_STATUS)
  elseif next_state == 2 then
    self:set_state(STATE_LOGIN)
    if protocol_id ~= server_protocol then
     self:disconnect{ translate = "multiplayer.disconnect.outdated_client", with = { server_version } }
    end
  else  -- can't accept transfer logins (yet?)
    self:set_state(STATE_LOGIN)
    self:disconnect{ translate = "multiplayer.disconnect.transfers_disabled" }
  end
end)


--= status state packet handlers =--

local status_response = json.encode{
  version = { name = server_version, protocol = server_protocol },
  players = { max = 0, online = 2 },
  description = { text = "woah haiii :3" },
  enforcesSecureChat = false,
  previewsChat = false
}

handle(STATE_STATUS, "status_request", function (self)
  log("status request")
  self:send("status_response", SendBuffer():string(status_response))
end)

handle(STATE_STATUS, "ping_request", function (self)
  log("ping request with data %s", self.buffer:dump(8))
  self:send("pong_response", SendBuffer():raw(self.buffer:read(8)))
end)


--= login state packet handlers =--

-- completes the login process
---@param self Connection
---@param username string
---@param uuid uuid
---@param skin? {texture: string, texture_signature: string?}
local function finish_login(self, username, uuid, skin)
  local accept, message = Server.on_login(username, self.encrypted and uuid or nil)
  if not accept then
    self:disconnect(message or "Login refused")
    return
  end

  self.player = Player._new(username, uuid, self, skin)

  log("login finish: '%s' (%s), %q", username, util.UUID_to_string(uuid), skin ~= nil)
  -- Send login success (corresponds to "Joining world..." on the client connection screen)
  -- it appears that sending the player's skin (texture) property in the login packet has no effect
  -- and it must be sent in the player list info update for the player's own info instead
  self:send("login_finished", SendBuffer():raw(uuid):string(username):varint(0))
  self:set_state(STATE_LOGIN_WAIT_ACK)
end

-- calculates minecraft's non-standard sha1 hex digest string
local function hexdigest(hash)
  if string.byte(hash) > 0x7F then
    -- convert to a bignum in 2's compliment
    -- cannot use bignum.fromBinary() because we need to flip the bytes first, as we can't do bitwise operations on a bignum
    local n = bn.new()
    for i = 1, 20 do
      n = (n << 8) + (0xFF - string.byte(hash, i))  -- flip bytes
    end
    n = n + 1                                       -- and add 1
    hash = n:toHex():lower()                        -- then print as a hexadecimal string
    -- remove leading '0's and prepend the negative sign
    hash = "-" .. (string.gsub(hash, "^0+", "", 1))
  else
    -- convert to hexadecimal string
    hash = (string.gsub(hash, ".", function(char) return string.format("%02x", string.byte(char)) end))
    -- remove leading '0's ()
    hash = (string.gsub(hash, "^0+", "", 1))
  end
  return hash
end

-- only valid to receive BEFORE we've sent the game_profile packet
handle(STATE_LOGIN, "hello", function (self)
  local username = self.buffer:string()
  local uuid = self.buffer:read(16)
  log("login start: '%s' (client sent %s)", username, util.UUID_to_string(uuid))
  -- TODO: compression

  if Server.properties.online_mode then
    local public_key_encoded = Server.public_key_encoded
    self.verify_token = string.char(math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255))
    -- encryption request (corresponds to "Logging in..." and "Encrypting..." on the client connection screen)
    self:send("hello", SendBuffer()
      :string("")                                           -- Server ID (always an empty string)
      :varint(#public_key_encoded):raw(public_key_encoded)  -- Public Key
      :varint(4):raw(self.verify_token)                     -- random Verify Token (always 4 bytes)
      :boolean(true)                                        -- should authenticate
    )
    self:set_state(STATE_LOGIN_WAIT_ENCRYPT)
    self.encryption_username = username  -- save username for contacting the session server
    return                    -- delay login until after encryption
  end

  -- TODO: in offline mode, generate a UUIDv2 based on the username like the offical server does
  finish_login(self, username, util.new_UUID())
end)

-- only valid to receive AFTER we've sent the encryption request packet
handle(STATE_LOGIN_WAIT_ENCRYPT, "key", function (self)
  log("encryption response")
  local shared_secret_encrypted = self.buffer:read(self.buffer:varint())  -- read varint, then byte array
  local verify_token_encrypted = self.buffer:read(self.buffer:varint())
  local shared_secret_clear = Server.key:decrypt(shared_secret_encrypted)
  local verify_token_clear = Server.key:decrypt(verify_token_encrypted)

  if verify_token_clear ~= self.verify_token then
    log("verify token mismatch")
    self:disconnect("Encryption error")  -- message won't ever be seen, the client expects the connection to be encrypted by now
  end

  -- initalize & enable encryption
  self.send_cipher = cipher.new("AES-128-CFB8"):encrypt(shared_secret_clear, shared_secret_clear)
  self.receive_cipher = cipher.new("AES-128-CFB8"):decrypt(shared_secret_clear, shared_secret_clear)
  self.encrypted = true

  -- calculate minecraft's non-standard sha1 hex digest string
  local hash = hexdigest(digest.new("sha1"):update(shared_secret_clear):final(Server.public_key_encoded))

  -- session server returns 204 no content if the hash is invalid or the player isn't logged in
  -- or 200 OK and the UUID & skin blob
  local res, status = http.request("https://sessionserver.mojang.com/session/minecraft/hasJoined?username=" .. self.encryption_username .. "&serverId=" .. hash)
  if not res or status ~= 200 then
    if status == 204 then  -- not authenticated
      self:disconnect("Authentication failed")
    else                   -- request failure or non-ok status code
      self:disconnect{ translate = "disconnect.loginFailedInfo.serversUnavailable" }
    end
    return
  end
  local data = json.decode(res)
  self.encryption_username = nil

  -- read the session server response to get the player's cannonical username, uuid, & skin data
  local auth_uuid = util.string_to_UUID(data.id)
  local auth_username = data.name        -- the session server request parameter is case-insensitive, use the response to prevent clients from changing the capitalization of their name
  local skin
  for _, v in pairs(data.properties) do  -- i'm not sure when properties would ever have anything else, but just in case
    if v.name == "textures" then
      skin = { texture = v.value, texture_signature = v.signature }
    end
  end

  finish_login(self, auth_username, auth_uuid, skin)
end)

-- only valid to receive AFTER we've sent the game_profile packet
handle(STATE_LOGIN_WAIT_ACK, "login_acknowledged", function (self)
  log("login ack'd")
  self:set_state(STATE_CONFIGURATION)
  -- send server brand
  self:send("custom_payload", SendBuffer():string("minecraft:brand"):string("quasar"))
  -- super cool extra data in the new "protocol error report"
  self:send("custom_report_details", SendBuffer():varint(1):string("quasar server"):string("https://github.com/Penguin-Spy/quasar"))
  -- bug report link (just testing this, it seems neat. should make this available to ppl using the library)
  self:send("server_links", SendBuffer():varint(1):byte(1):varint(0):string("https://github.com/Penguin-Spy/quasar/issues"))
  -- send feature flags packet (enable vanilla features (not required for registry sync/client to connect, but probably important))
  self:send("update_enabled_features", SendBuffer():varint(1):string("minecraft:vanilla"))
  -- start datapack negotiation (official server declares the "minecraft:core" datapack with the server version)
  self:send("select_known_packs", SendBuffer():varint(1):string("minecraft"):string("core"):string(server_version))
end)


--= configuration state packet handlers =--

-- only valid to receive BEFORE we've sent the finish_configuration packet
handle(STATE_CONFIGURATION, "select_known_packs", function (self)
  local client_known_pack_count = self.buffer:varint()
  log("serverbound known packs (known on the client): %i", client_known_pack_count)
  -- validate that the client does actually know about minecraft:core with the correct version
  local client_known_packs = {}
  for i = 1, client_known_pack_count do
    local pack_namespace = self.buffer:string()
    local pack_id = self.buffer:string()
    local pack_version = self.buffer:string()
    log("  client knows pack %s:%s of version %s", pack_namespace, pack_id, pack_version)
    client_known_packs[pack_namespace .. ":" .. pack_id] = pack_version
  end
  if client_known_packs["minecraft:core"] ~= server_version then
    self:disconnect{ translate = "multiplayer.disconnect.outdated_client", with = { server_version } }
  end

  -- send registry data
  local regs = Registry.network_data
  self:send("registry_data", regs["worldgen/biome"])
  self:send("registry_data", regs.chat_type)
  self:send("registry_data", regs.trim_pattern)
  self:send("registry_data", regs.trim_material)
  self:send("registry_data", regs.wolf_variant)
  self:send("registry_data", regs.painting_variant)
  self:send("registry_data", regs.dimension_type)
  self:send("registry_data", regs.damage_type)
  self:send("registry_data", regs.banner_pattern)
  self:send("registry_data", regs.enchantment)
  self:send("registry_data", regs.jukebox_song)

  self:send("finish_configuration", SendBuffer())  -- then tell client we're finished with configuration, u can ack when you're done sending stuff
  self:set_state(STATE_CONFIGURATION_WAIT_ACK)
end)

handle(STATE_CONFIGURATION, "client_information", function (self)
  local locale, view_distance, chat_mode, chat_colors = self.buffer:string(), self.buffer:byte(), self.buffer:varint(), self.buffer:boolean()
  local skin_layers, main_hand = self.buffer:byte(), self.buffer:varint()
  self.buffer:read_to_end()
  log("client information (configuration): %s, %i, %i, %q, %02x, %i", locale, view_distance, chat_mode, chat_colors, skin_layers, main_hand)
  self.player.skin.layers = skin_layers & 0x7F       -- mask off unused bit
  self.player.skin.hand = main_hand == 0 and 0 or 1  -- ensure it's only 0 or 1 (default 1; right hand)
end)

handle(STATE_CONFIGURATION, "custom_payload", function (self)
  local channel = self.buffer:string()
  local data = self.buffer:read_to_end()
  log("plugin message (configuration) on channel '%s' with data: '%s'", channel, data)
end)

-- only valid to receive AFTER we've sent the finish_configuration packet
handle(STATE_CONFIGURATION_WAIT_ACK, "finish_configuration", function (self)
  log("configuration finish ack")
  self:set_state(STATE_PLAY)

  local player = self.player
  -- allow setup of player event handlers & loading inventory, dimension, etc.
  local accept, message = Server.on_join(player)
  if not accept then
    self:disconnect(message or "Join refused")
    return
  end

  -- add the player to the default dimension if the on_join handler didn't add them to any
  if not player.dimension then
    player.dimension = Server.get_default_dimension()
  end
  local dim = player.dimension

  -- send login (Corresponds to "Loading terrain..." on the client connection screen)
  self:send("login", SendBuffer()
    :int(0):boolean(false)                                           -- entity id, is hardcore
    :varint(0)                                                       -- dimensions (appears to be ignored?)
    :varint(0)                                                       -- "max players" (unused)
    :varint(dim.view_distance):varint(5)                             -- view dist, sim dist
    :boolean(false):boolean(true):boolean(false)                     -- reduced debug, respawn screen, limited crafting
    :varint(Registry.dimension_type[dim.type])                       -- starting dim type (registry id)
    :string(dim.identifier)                                          -- starting dim name
    :long(0)                                                         -- hashed seeed
    :byte(1):byte(255):boolean(false):boolean(false):boolean(false)  -- game mode (creative), prev game mode (-1 undefined), is debug, is flat, has death location
    :varint(0)                                                       -- portal cooldown (unknown use)
    :varint(63)                                                      -- sea level
    :boolean(true)                                                   -- enforces secure chat (causes giant warning toast to show up if false, seemingly no other effects?)
  )

  -- game event 13 (start waiting for chunks), float param of always 0 (4 bytes)
  self:send("game_event", SendBuffer():byte(13):int(0))

  -- spawns player in dimension and loads chunks & entities
  -- sending chunks closes the connection screen and shows the player in the world
  dim:_add_player(player)

  -- this does stuff with flight (flying + flight disabled + 0 fly speed -> locks player in place)
  -- invulnerable (unknown effect), flying, allow flying (allow toggling flight), creative mode/instant break (unknown effect), fly speed, fov modifier
  --self:send(PLAY_clientbound.player_abilities, string.pack(">bff", 0x01 | 0x02 | 0x04 | 0x08, 0.05, 0.1))

  self.keepalive_timer = copas_timer.new{
    name      = "quasar_connection_keepalive[" .. player.username .. "]",
    recurring = true,
    delay     = 15,
    callback  = function() self:keepalive() end
  }
  self:keepalive()  -- start the keepalive cycle
end)


--= play state packet handlers =--

handle(STATE_PLAY, "keep_alive", function (self)
  local keepalive_id = self.buffer:long()
  if keepalive_id == self.keepalive_id then
    self.keepalive_received = true
  else
    log("ignoring incorrect keepalive id %i", keepalive_id)
  end
end)

handle(STATE_PLAY, "accept_teleportation", function (self)
  local teleport_id = self.buffer:varint()
  if teleport_id == self.current_teleport_id then
    log("confirm teleport #%i", teleport_id)
    self.current_teleport_acknowledged = true
  else
    log("ignoring incorrect confirm teleport #%i", teleport_id)
  end
end)

handle(STATE_PLAY, "chat", function (self)
  local message = self.buffer:string()
  local timestamp = self.buffer:dump(8); self.buffer:read(8)
  local salt = self.buffer:dump(8); self.buffer:read(8)  -- discard what we just dumped
  local has_signature = self.buffer:boolean()
  self.buffer:read_to_end()
  log("chat msg from '%s' at %s salt %s signed %q: %s", self.player.username, timestamp, salt, has_signature, message)

  if #message > 256 then
    error("received too long chat message")
  end

  self.player:on_chat_message(message)
end)

handle(STATE_PLAY, "chat_command", function (self)
  local command = self.buffer:string()
  if #command > 32767 then
    error("received too long command")
  end
  log("chat command from '%s': %s", self.player.username, command)
  self.player:on_command(command)
end)

handle(STATE_PLAY, "client_command", function (self)
  self.buffer:varint() -- 0 = perform respawn, 1 = view stats. ignore both for now
end)

handle(STATE_PLAY, "client_tick_end", function (self)
  -- ignore (no data)
end)

handle(STATE_PLAY, "client_information", function (self)
  local locale, view_distance, chat_mode, chat_colors = self.buffer:string(), self.buffer:byte(), self.buffer:varint(), self.buffer:boolean()
  local skin_layers, main_hand = self.buffer:byte(), self.buffer:varint()
  self.buffer:read_to_end()
  log("client information (play): %s, %i, %i, %q, %02x, %i", locale, view_distance, chat_mode, chat_colors, skin_layers, main_hand)

  local skin = self.player.skin
  if skin_layers ~= skin.layers or main_hand ~= skin.hand then
    log("updating skin layers")
    skin.layers = skin_layers & 0x7F       -- mask off unused bit
    skin.hand = main_hand == 0 and 0 or 1  -- ensure it's only 0 or 1 (default 1; right hand)
    -- send the packet to all listeners & ourselves
    self:send_to_all_listeners("set_entity_data", SendBuffer():varint(self.player.id)
      -- skin layers
      :byte(17):varint(0):byte(skin.layers)
      -- main hand
      :byte(18):varint(0):byte(skin.hand)
      :byte(0xff))
    self:send("set_entity_data", SendBuffer():varint(0)  -- client's player entity is 0
      -- skin layers
      :byte(17):varint(0):byte(skin.layers)
      -- main hand
      :byte(18):varint(0):byte(skin.hand)
      :byte(0xff))
  end
end)

handle(STATE_PLAY, "custom_payload", function (self)
  local channel = self.buffer:string()
  local data = self.buffer:read_to_end()
  log("plugin message (play) on channel '%s' with data: '%s'", channel, data)
end)

handle(STATE_PLAY, "debug_sample_subscription", function (self)
  log("debug sample subscription %i", self.buffer:varint())
  local bytes = math.floor(collectgarbage("count") * 1e3)
  self:send("debug_sample", SendBuffer()
    -- 50ms total, 20ms tick, 5ms tasks, 25ms idle
    --:varint(4):long(50e6):long(20e6):long(5e6):long(25e6)
    :varint(4):long(50e6):long(bytes):long(0):long(50e6 - bytes)
    :varint(0))
end)

handle(STATE_PLAY, "chat_session_update", function (self)
  local uuid = self.buffer:read(16)
  log("player session update '%s'", util.UUID_to_string(uuid))
  self.buffer:read_to_end()
end)

handle(STATE_PLAY, "move_player_pos", function (self)
  if not self.current_teleport_acknowledged then
    self.buffer:read_to_end()
    return
  end
  local player = self.player
  player.position:set(self.buffer:double(), self.buffer:double(), self.buffer:double())
  local status = self.buffer:byte()
  player.on_ground = (status & 0x1) == 1
  player.against_wall = (status & 0x2) == 1
  for _, con in pairs(self.listening_connections) do
    con:send_move_entity(player)
  end
  player.dimension:_on_player_moved(player)
end)

handle(STATE_PLAY, "move_player_pos_rot", function (self)
  if not self.current_teleport_acknowledged then
    self.buffer:read_to_end()
    return
  end
  local player = self.player
  player.position:set(self.buffer:double(), self.buffer:double(), self.buffer:double())
  player.yaw, player.pitch = receive_facing(self.buffer:float(), self.buffer:float())
  local status = self.buffer:byte()
  player.on_ground = (status & 0x1) == 1
  player.against_wall = (status & 0x2) == 1
  for _, con in pairs(self.listening_connections) do
    con:send_move_entity(player)
  end
  player.dimension:_on_player_moved(player)
end)

handle(STATE_PLAY, "move_player_rot", function (self)
  if not self.current_teleport_acknowledged then
    self.buffer:read_to_end()
    return
  end
  local player = self.player
  player.yaw, player.pitch = receive_facing(self.buffer:float(), self.buffer:float())
  local status = self.buffer:byte()
  player.on_ground = (status & 0x1) == 1
  player.against_wall = (status & 0x2) == 1
  for _, con in pairs(self.listening_connections) do
    con:send_move_entity(player)
  end
end)

handle(STATE_PLAY, "move_player_status_only", function (self)
  local status, player = self.buffer:byte(), self.player
  player.on_ground = (status & 0x1) == 1
  player.against_wall = (status & 0x2) == 1
end)

handle(STATE_PLAY, "pick_item_from_block", function (self)
  local pos = self.buffer:position()
  log("pick block (%d,%d,%d) %q", pos.x, pos.y, pos.z, self.buffer:boolean())
end)

handle(STATE_PLAY, "pick_item_from_entity", function (self)
  log("pick block on entity %d %q", self.buffer:varint(), self.buffer:boolean())
end)

handle(STATE_PLAY, "ping_request", function (self)
  self:send("pong_response", SendBuffer():long(self.buffer:long()))
end)

handle(STATE_PLAY, "player_abilities", function (self)
  local abilities = self.buffer:byte()
  log("player abilities: %02X", abilities)
end)

handle(STATE_PLAY, "player_command", function (self)
  self.buffer:varint()       -- always the player's entity ID
  local action = self.buffer:varint()
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
  self:send_to_all_listeners("set_entity_data", SendBuffer():varint(self.player.id)
    -- sneaking causes the nametag to become fainter and hidden behind walls, sprinting causes the running particles to appear
    :byte(0):varint(0):byte((self.player.sneaking and 0x02 or 0) | (self.player.sprinting and 0x08 or 0))
    -- sets the sneaking/standing pose
    :byte(6):varint(21):varint(self.player.sneaking and 5 or 0)
    :byte(0xff))
end)

handle(STATE_PLAY, "player_input", function (self)
  -- TODO: an event for when input changes?
  self.player.input = self.buffer:byte()
end)

handle(STATE_PLAY, "player_loaded", function (self)
  log("player's chunk loaded")
end)

handle(STATE_PLAY, "set_carried_item", function (self)
  local slot = self.buffer:short()
  log("select slot %i", slot)
  self.player:on_select_hotbar_slot(slot)
end)

handle(STATE_PLAY, "set_creative_mode_slot", function (self)
  local slot = self.buffer:short()

  local item_count = self.buffer:varint()
  if item_count > 0 then
    local item_id = self.buffer:varint()
    local components_to_add_count = self.buffer:varint()
    local components_to_remove_count = self.buffer:varint()
    log("set slot %i to item #%i x%i (+%i,-%i)", slot, item_id, item_count, components_to_add_count, components_to_remove_count)
    -- TODO: read component data, construct actual item object
    self.buffer:read_to_end()
    self.player:on_set_slot(slot, nil)
  else
    log("set slot %i to item of 0 count", slot)
    self.player:on_set_slot(slot, nil)
  end
end)

handle(STATE_PLAY, "container_close", function (self)
  log("close screen %i", self.buffer:byte())
end)

handle(STATE_PLAY, "seen_advancements", function (self)
  local action, tab_id = self.buffer:varint()
  if action == 0 then
    tab_id = self.buffer:string()
  end
  log("seen advancements: action %i, tab %s", action, tab_id or "n/a")
end)

handle(STATE_PLAY, "player_action", function (self)
  local action = self.buffer:varint()
  local pos = self.buffer:position()
  local face = self.buffer:byte()
  local seq = self.buffer:varint()
  log("player action: action %i, pos (%i,%i,%i), face %i, seq %i", action, pos.x, pos.y, pos.z, face, seq)

  self.player.dimension:on_break_block(self.player, pos)
  -- acknowledge the block breaking so the client shows the block state the server says instead of its predicted state
  self:send("block_changed_ack", SendBuffer():varint(seq))
end)

handle(STATE_PLAY, "swing", function (self)
  local arm_animation = self.buffer:varint() == 0 and 0 or 3  -- arm 0 is animation 0, arm 1 (offhand) is animation 3
  self:send_to_all_listeners("animate", SendBuffer():varint(self.player.id):byte(arm_animation))
end)

handle(STATE_PLAY, "use_item_on", function (self)
  local hand = self.buffer:varint()
  local pos = self.buffer:position()
  local face = self.buffer:byte()
  local cursor_x = self.buffer:float()
  local cursor_y = self.buffer:float()
  local cursor_z = self.buffer:float()
  local inside_block = self.buffer:boolean()
  local world_border_hit = self.buffer:boolean()
  local seq = self.buffer:varint()

  local slot = hand == 1 and 45 or self.player.selected_slot + 36
  log("use item of hand %i (slot %i) on block (%i,%i,%i) face %i at (%f,%f,%f) in block: %q, hit world border: %q",
    hand, slot, pos.x, pos.y, pos.z, face, cursor_x, cursor_y, cursor_z, inside_block, world_border_hit)
  self.player.dimension:on_use_item_on_block(self.player, slot, pos, face, { x = cursor_x, y = cursor_y, z = cursor_z }, inside_block)
  -- acknowledge the item use
  self:send("block_changed_ack", SendBuffer():varint(seq))
end)

handle(STATE_PLAY, "use_item", function (self)
  local hand = self.buffer:varint()
  local seq = self.buffer:varint()
  local yaw = self.buffer:float()
  local pitch = self.buffer:float()
  local slot = hand == 1 and 45 or self.player.selected_slot + 36
  log("use item of hand %i (slot %i) facing %f,%f", hand, slot, yaw, pitch)
  self.player.dimension:on_use_item(self.player, slot, yaw, pitch)
  -- acknowledge the item use
  self:send("block_changed_ack", SendBuffer():varint(seq))
end)


--= socket interaction =--

function Connection:handle_legacy_ping()
  self.buffer:read(29)                     -- discard irrelevant stuff
  local protocol_id = self.buffer:byte()
  local str_len = self.buffer:short() * 2  -- UTF-16BE
  local server_addr = self.buffer:read(str_len)
  local server_port = self.buffer:int()
  log("legacy ping from protocol %i addr %s port %i", protocol_id, server_addr, server_port)
  self.sock:send("\xFF\x00\029\x00\xA7\x001\x00\x00\x001\x002\x007\x00\x00\x001\x00.\x002\x001\x00\x00\x00w\x00o\x00a\x00h\x00 \x00h\x00a\x00i\x00i\x00i\x00 \x00:\x003\x00\x00\x000\x00\x00\x000")
  self:close()
end

-- Receive loop
function Connection:loop()
  log("open '%s'", self)
  self:set_state(STATE_HANDSHAKE)

  -- read at least 1 byte to see if this is a legacy ping
  local _, err, data = self.sock:receivepartial("*a")
  if string.byte(data) == 0xFE then
    self.buffer:append(data)
    self:handle_legacy_ping()
    return
  end

  repeat  -- socket receive loop
    if self.encrypted then
      data, err = self.receive_cipher:update(data)
      if data == "" then
        goto no_data_yet  -- "The returned string may be empty if no blocks can be flushed."
      elseif not data then
        goto exit         -- err is set to whatever the openssl error was
      end
    end
    self.buffer:append(data)

    while true do  -- packet handle loop
      local length, bytes = self.buffer:try_peek_varint()
      if not length then break end
      if length > #self.buffer.data - bytes then break end  -- haven't received the full packet yet

      self.buffer:read(bytes)                               -- remove the data of the varint from the buffer
      self.buffer:set_end(length)

      local packet_id = self.buffer:varint()
      local func = self.handle_packet[packet_id]
      if not func then
        err = string.format("received unexpected packet id 0x%02X in state %i", packet_id, self.state)
        goto exit
      end

      -- handle the packet
      local success, packet_err = xpcall(func, debug.traceback, self)
      if not success then
        err = packet_err
        goto exit
      end
    end

    ::no_data_yet::

    _, err, data = self.sock:receivepartial("*a")
  until err ~= "timeout"
  ::exit::

  log("close '%s' - %s", self, err)
  self:destroy(true)
end

-- Destroy this connection, cleaning up all data (such as the player's presence in a Dimension). <br>
-- This is the `__gc` metamethod (finalizer), and is also called when the `Connection:loop()` ends.
---@param clean boolean?  `true` if called at the end of Connection:loop(), `nil` if called as the finalizer.
function Connection:destroy(clean)
  if self.state == STATE_CLOSED then return end  -- this connection was already closed

  -- if this connection was in the game
  if self.player then
    -- TODO: any dimensionless player cleanup
    if self.player.dimension then  -- if this player was in a dimension
      self.player.dimension:_remove_player(self.player)
    end
  end
  if self.keepalive_timer then
    self.keepalive_timer:cancel()
  end
  -- if the socket wasn't closed, this was a Lua error while handling the packet
  if self.state ~= STATE_CLOSED then
    if not clean then log("destroying connection from __gc") end
    self:disconnect("Internal server error")  -- do this last in case it fails (copas will close the socket if so)
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
  __tostring = Connection.tostring,
  __gc = Connection.destroy
}

-- Constructs a new Connection on the given socket.
---@param sock LuaSocket
---@return Connection
local function new(sock)
  local self = {
    sock = sock,
    buffer = ReceiveBuffer(),
    state = STATE_HANDSHAKE,
    current_teleport_id = 0,
    current_teleport_acknowledged = true,
    keepalive_received = true,
    listening_connections = {}
  }
  setmetatable(self, mt)
  return self
end

-- Sets up local references to the server & requires openssl modules if necessary.
---@param the_server Server a reference to the Server (can't require bc circular dependency)
local function initalize(the_server)
  Server = the_server
  if Server.properties.online_mode then
    cipher = require "openssl.cipher"
    digest = require "openssl.digest"
    bn = require "openssl.bignum"
  end
end

return {
  new = new,
  initalize = initalize
}
