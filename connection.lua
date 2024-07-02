--[[ connection.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]


local Buffer = require "buffer"
local log = require "log"
local registry = require "registry"
local NBT = require "nbt"
local Player = require "player"
local Item = require "item"

---@class Connection
---@field sock LuaSocket
---@field buffer Buffer
---@field state state
---@field server Server
local Connection = {}

---@alias state
---| 0 # handshake
---| 1 # status
---| 2 # login
---| 3 # login, waiting for client to acknowledge
---| 4 # configuration
---| 5 # play
local STATE_HANDSHAKE = 0
local STATE_STATUS = 1
local STATE_LOGIN = 2
local STATE_LOGIN_WAIT_ACK = 3
local STATE_CONFIGURATION = 4
local STATE_PLAY = 5

-- Sends a packet to the client.
---@param packet_id integer
---@param data string
function Connection:send(packet_id, data)
  data = Buffer.encode_varint(packet_id) .. data
  data = Buffer.encode_varint(#data) .. data
  log("send: %s", data:gsub(".", function(char) return string.format("%02X", char:byte()) end))
  self.sock:send(data)
end

-- Immediatley closes this connection; does not send any information to the client.
function Connection:close()
  self.sock:close()
  -- clear any data we might still have so the loop() doesn't try to read more packets
  self.buffer.data = ""
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

  self:send(0x27, packet)
end

-- Sends a Block Update packet to the client.
---@param pos blockpos
---@param state integer   The block state ID to set at the position
function Connection:send_block(pos, state)
  self:send(0x09, Buffer.encode_position(pos) .. Buffer.encode_varint(state))
end

-- Handles a single packet
function Connection:handle_packet()
  local packet_id = self.buffer:read_varint()
  if packet_id == 0x00 and self.state == STATE_HANDSHAKE then
    -- Begin connection (corresponds to "Connecting to the server..." on the client connection screen
    local protocol_id = self.buffer:read_varint()
    local server_addr = self.buffer:read_string()
    local server_port = self.buffer:read_short()
    local next_state = self.buffer:read_varint()
    log("handshake from protocol %i to %s:%i, next state: %i", protocol_id, server_addr, server_port, next_state)
    if next_state == 1 then
      self.state = STATE_STATUS
    elseif next_state == 2 then
      self.state = STATE_LOGIN
    else  -- can't accept transfer logins (yet?)
      self:close()
    end

    --
  elseif packet_id == 0x00 and self.state == STATE_STATUS then
    log("status request")
    self:send(0x00, Buffer.encode_string(
      "{\"version\":{\"name\":\"1.21\",\"protocol\":767},\"players\":{\"max\":0,\"online\":2,\"sample\":[{\"name\":\"Penguin_Spy\",\"id\":\"dfbd911d-9775-495e-aac3-efe339db7efd\"}]},\"description\":{\"text\":\"woah haiii :3\"},\"enforcesSecureChat\":false,\"previewsChat\":false}"
    ))

    --
  elseif packet_id == 0x01 and self.state == STATE_STATUS then
    log("ping request with data %s", self.buffer:dump(8))
    self:send(0x01, self.buffer:read(8))

    --
  elseif packet_id == 0x00 and self.state == STATE_LOGIN then
    local username = self.buffer:read_string()
    local uuid_str = self.buffer:dump(16)
    local uuid = self.buffer:read(16)
    log("login start: '%s' (%s)", username, uuid_str)
    -- TODO: encryption & compression

    local accept, message = self.server.on_login(username)
    if not accept then
      self:send(0x00, Buffer.encode_string('{"text":"' .. tostring(message) .. '"}'))
      self:close()
      return
    end

    self.player = Player._new(username, uuid_str, self)

    -- Send login success (corresponds to "Joining world..." on the client connection screen)
    self:send(0x02, uuid .. Buffer.encode_string(username) .. Buffer.encode_varint(0) .. '\1')  -- last byte is strict error handling
    self.state = STATE_LOGIN_WAIT_ACK

    --
  elseif packet_id == 0x03 and self.state == STATE_LOGIN_WAIT_ACK then
    log("login ack'd")
    -- send server brand
    self:send(0x01, Buffer.encode_string("minecraft:brand") .. Buffer.encode_string("quasar"))
    -- super cool extra data in the new "protocol error report"
    self:send(0x0F, Buffer.encode_varint(1) .. Buffer.encode_string("quasar server") .. Buffer.encode_string("https://github.com/Penguin-Spy/quasar"))
    -- bug report link (just testing this, it seems neat. should make this available to ppl using the library)
    self:send(0x10, Buffer.encode_varint(1) .. '\1' .. Buffer.encode_varint(0) .. Buffer.encode_string("https://github.com/Penguin-Spy/quasar/issues"))
    -- send feature flags packet (enable vanilla features (not required for registry sync/client to connect, but probably important))
    self:send(0x0C, Buffer.encode_varint(1) .. Buffer.encode_string("minecraft:vanilla"))
    -- start datapack negotiation (official server declares the "minecraft:core" datapack with version "1.21")
    self:send(0x0E, Buffer.encode_varint(1) .. Buffer.encode_string("minecraft") .. Buffer.encode_string("core") .. Buffer.encode_string("1.21"))
    self.state = STATE_CONFIGURATION

    --
  elseif packet_id == 0x07 and self.state == STATE_CONFIGURATION then
    local client_known_pack_count = self.buffer:read_varint()
    log("serverbound known packs (known on the client): %i", client_known_pack_count)
    for i = 1, client_known_pack_count do
      local pack_namespace = self.buffer:read_string()
      local pack_id = self.buffer:read_string()
      local pack_version = self.buffer:read_string()
      log("  client knows pack %s:%s of version %s", pack_namespace, pack_id, pack_version)
    end

    -- send registry data
    self:send(0x07, registry["worldgen/biome"])
    self:send(0x07, registry.chat_type)
    self:send(0x07, registry.trim_pattern)
    self:send(0x07, registry.trim_material)
    self:send(0x07, registry.wolf_variant)
    self:send(0x07, registry.painting_variant)
    self:send(0x07, registry.dimension_type)
    self:send(0x07, registry.damage_type)
    self:send(0x07, registry.banner_pattern)
    self:send(0x07, registry.enchantment)
    self:send(0x07, registry.jukebox_song)

    self:send(0x03, "")  -- then tell client we're finished with configuration, u can ack when you're done sending stuff

    --
  elseif packet_id == 0x00 and self.state == STATE_CONFIGURATION then
    self.buffer:read_to_end()
    log("client information (configuration)")

    --
  elseif packet_id == 0x02 and self.state == STATE_CONFIGURATION then
    local channel = self.buffer:read_string()
    local data = self.buffer:read_to_end()
    log("plugin message (configuration) on channel '%s' with data: '%s'", channel, data)

    --
  elseif packet_id == 0x03 and self.state == STATE_CONFIGURATION then
    log("configuration finish ack")

    local player = self.player
    -- allow setup of player event handlers & loading inventory, dimension, etc.
    local accept, message = self.server.on_join(player)
    if not accept then
      self:send(0x1D, NBT.compound{ text = tostring(message) })
      self:close()
      return
    end

    -- add the player to the default dimension if the on_join handler didn't add them to any
    if not player.dimension then
      player.dimension = self.server.get_default_dimension()
    end
    local dim = player.dimension
    dim:add_player(player)

    -- send login (Corresponds to "Loading terrain..." on the client connection screen)
    self:send(0x2B, Buffer.encode_int(0) .. '\0'  -- entity id, is hardcore
      .. Buffer.encode_varint(1)                  -- dimensions (appears to be ignored?)
      .. Buffer.encode_string("minecraft:the_end")
      .. Buffer.encode_varint(0)                  -- "max players" (unused)
      .. Buffer.encode_varint(10)                 -- view dist
      .. Buffer.encode_varint(5)                  -- sim dist
      .. '\0\1\0'                                 -- reduced debug, respawn screen, limited crafting
      .. Buffer.encode_varint(0)                  -- starting dim type (registry id)
      .. Buffer.encode_string(dim.identifier)     -- starting dim name
      .. Buffer.encode_long(0)                    -- hashed seeed
      .. '\1\255\0\0\0'                           -- game mode (creative), prev game mode (-1 undefined), is debug, is flat, has death location
      .. Buffer.encode_varint(0)                  -- portal cooldown (unknown use)
      .. '\0'                                     -- enforces secure chat
    )

    -- synchronize player position (do this first so the client doesn't default to (8.5,65,8.5) when chunks are sent)
    self:send(0x40, string.pack(">dddffb", 0, 194, 0, 0, 0, 0) .. Buffer.encode_varint(3))

    self:send(0x22, "\13\0\0\0\0")  -- game event 13 (start waiting for chunks), float param of always 0

    -- send chunks (this closes the connection screen and shows the player in the world)
    for x = -4, 4 do
      for z = -4, 4 do
        self:send_chunk(x, z, dim:get_chunk(x, z, player))
      end
    end

    self.state = STATE_PLAY

    --
  elseif packet_id == 0x00 and self.state == STATE_PLAY then
    log("confirm teleport id: " .. self.buffer:read_varint())

    --
  elseif packet_id == 0x0A and self.state == STATE_PLAY then
    self.buffer:read_to_end()
    log("client information (play)")

    --
  elseif packet_id == 0x12 and self.state == STATE_PLAY then
    local channel = self.buffer:read_string()
    local data = self.buffer:read_to_end()
    log("plugin message (play) on channel '%s' with data: '%s'", channel, data)

    --
  elseif packet_id == 0x1A and self.state == STATE_PLAY then
    self.buffer:read_to_end()
    log("set player position")

    --
  elseif packet_id == 0x1B and self.state == STATE_PLAY then
    self.buffer:read_to_end()
    log("set player position and rotation")

    --
  elseif packet_id == 0x1C and self.state == STATE_PLAY then
    self.buffer:read_to_end()
    log("set player rotation")

    --
  elseif packet_id == 0x1D and self.state == STATE_PLAY then
    log("player on ground: %q", self.buffer:byte() ~= 0)

    --
  elseif packet_id == 0x23 and self.state == STATE_PLAY then
    local abilities = self.buffer:byte()
    log("player abilities: %02X", abilities)

    --
  elseif packet_id == 0x25 and self.state == STATE_PLAY then
    local entity_id = self.buffer:read_varint()
    local action = self.buffer:read_varint()
    local horse_jump_boost = self.buffer:read_varint()
    log("player command: %i %i %i", entity_id, action, horse_jump_boost)

    --
  elseif packet_id == 0x2F and self.state == STATE_PLAY then
    local slot = self.buffer:read_short()
    log("select slot %i", slot)
    self.player:on_select_hotbar_slot(slot)

    --
  elseif packet_id == 0x32 and self.state == STATE_PLAY then
    local slot = self.buffer:read_short()

    local item_count = self.buffer:read_varint()
    if item_count > 0 then
      local item_id = self.buffer:read_varint()
      local components_to_add_count = self.buffer:read_varint()
      local components_to_remove_count = self.buffer:read_varint()
      log("set slot %i to item #%i x%i (+%i,-%i)", slot, item_id, item_count, components_to_add_count, components_to_remove_count)
      -- TODO: read component data, construct actual item object
      self.player:on_set_slot(slot, nil)
    else
      log("set slot %i to item of 0 count", slot)
      self.player:on_set_slot(slot, nil)
    end

    --
  elseif packet_id == 0x0F and self.state == STATE_PLAY then
    log("close screen %i", self.buffer:byte())

    --
  elseif packet_id == 0x2C and self.state == STATE_PLAY then
    local action, tab_id = self.buffer:read_varint()
    if action == 0 then
      tab_id = self.buffer:read_string()
    end
    log("seen advancements: action %i, tab %s", action, tab_id or "n/a")

    --
  elseif packet_id == 0x24 and self.state == STATE_PLAY then
    local action = self.buffer:read_varint()
    local pos = self.buffer:read_position()
    local face = self.buffer:byte()
    local seq = self.buffer:read_varint()
    log("player action: action %i, pos (%i,%i,%i), face %i, seq %i", action, pos.x, pos.y, pos.z, face, seq)

    self.player.dimension:on_break_block(self.player, pos)
    -- acknowledge the block breaking so the client shows the block state the server says instead of its predicted state
    self:send(0x05, Buffer.encode_varint(seq))

    --
  elseif packet_id == 0x36 and self.state == STATE_PLAY then
    log("swing arm %i", self.buffer:read_varint())

    --
  elseif packet_id == 0x38 and self.state == STATE_PLAY then
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
    self:send(0x05, Buffer.encode_varint(seq))

    --
  elseif packet_id == 0x39 and self.state == STATE_PLAY then
    local hand = self.buffer:read_varint()
    local seq = self.buffer:read_varint()
    local yaw = self.buffer:read_float()
    local pitch = self.buffer:read_float()
    local slot = hand == 1 and 45 or self.player.selected_slot + 36
    log("use item of hand %i (slot %i) facing %f,%f", hand, slot, yaw, pitch)
    self.player.dimension:on_use_item(self.player, slot, yaw, pitch)
    -- acknowledge the item use
    self:send(0x05, Buffer.encode_varint(seq))

    --
  else
    log("received unexpected packet id 0x%02X in state %s", packet_id, self.state)
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
  self.sock:send("\xFF\x00\031\x00\xA7\x001\x00\x00\x001\x002\x007\x00\x00\x001\x00.\x002\x000\x00.\x004\x00\x00\x00w\x00o\x00a\x00h\x00 \x00h\x00a\x00i\x00i\x00i\x00 \x00:\x003\x00\x00\x000\x00\x00\x000")
  self:close()
end

-- Receive loop
function Connection:loop()
  log("open '%s'", self)
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
          self:handle_packet()
        else
        end
      until not length
    else
      log("close '%s' - %s", self, err)
      if self.player then              -- if this connection was in the game
        -- TODO: any dimensionless player cleanup
        if self.player.dimension then  -- if this player was in a dimension
          self.player.dimension:remove_player(self.player)
        end
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
  local self = {
    sock = sock,
    buffer = Buffer.new(),
    state = STATE_HANDSHAKE,
    server = server
  }
  setmetatable(self, mt)
  return self
end

return {
  new = new
}
