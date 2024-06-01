local Buffer = require "buffer"

---@class Connection
---@field sock LuaSocket
---@field buffer Buffer
---@field state state
local Connection = {}

---@alias state
---| 0 # handshake
---| 1 # status
---| 2 # login
local STATE_HANDSHAKE = 0
local STATE_STATUS = 1
local STATE_LOGIN = 2

-- Sends a packet to the client.
---@param packet_id integer
---@param data string
function Connection:send(packet_id, data)
  data = Buffer.encode_varint(packet_id) .. data
  data = Buffer.encode_varint(#data) .. data
  self.sock:send(data)
end

-- Immediatley closes this connection; does not send any information to the client.
function Connection:close()
  self.sock:close()
  -- clear any data we might still have so the loop() doesn't try to read more packets
  self.buffer.data = ""
end

-- Handles a single packet
function Connection:handle_packet()
  local packet_id = self.buffer:try_read_varint()
  if packet_id == 0x00 and self.state == STATE_HANDSHAKE then
    print("handshake")
    local protocol_id = self.buffer:try_read_varint()
    local server_addr = self.buffer:try_read_string()
    local server_port = self.buffer:try_read_short()
    local next_state = self.buffer:try_read_varint()
    print("  from protocol " .. protocol_id
      .. " addr " .. server_addr
      .. " port " .. server_port
      .. " next state " .. next_state)
    if next_state == 1 then
      self.state = STATE_STATUS
    elseif next_state == 2 then
      self.state = STATE_LOGIN
    end

    --
  elseif packet_id == 0x00 and self.state == STATE_STATUS then
    print("status request")
    self:send(0x00, Buffer.encode_string(
      "{\"version\":{\"name\":\"1.20.4\",\"protocol\":765},\"players\":{\"max\":0,\"online\":2,\"sample\":[{\"name\":\"Penguin_Spy\",\"id\":\"dfbd911d-9775-495e-aac3-efe339db7efd\"}]},\"description\":{\"text\":\"woah haiii :3\"},\"enforcesSecureChat\":false,\"previewsChat\":false,\"preventsChatReports\":true}"
    ))

    --
  elseif packet_id == 0x01 and self.state == STATE_STATUS then
    print("ping request with data " .. self.buffer:dump(8))
    self:send(0x01, self.buffer:read(8))
  else
    print(string.format("received unexpected packet id 0x%02X in state %s", packet_id, self.state))
    self:close()
  end
end

function Connection:handle_legacy_ping()
  self.buffer:read(27)                              -- discard irrelevant stuff
  local protocol_id = self.buffer:byte()
  local str_len = self.buffer:try_read_short() * 2  -- UTF-16BE
  local server_addr = self.buffer:read(str_len)
  local server_port = self.buffer:try_read_int()
  print("legacy ping from protocol " .. protocol_id .. " addr " .. server_addr .. " port " .. server_port)
  self.sock:send("\xFF\x00\031\x00\xA7\x001\x00\x00\x001\x002\x007\x00\x00\x001\x00.\x002\x000\x00.\x004\x00\x00\x00w\x00o\x00a\x00h\x00 \x00h\x00a\x00i\x00i\x00i\x00 \x00:\x003\x00\x00\x000\x00\x00\x000")
  self:close()
end

-- Receive loop
function Connection:loop()
  print("started connection " .. tostring(self))
  while true do
    local _, err, data = self.sock:receivepartial("*a")
    if err == "timeout" then
      self.buffer:append(data)
      print(self.buffer:dump())
      repeat
        local length = self.buffer:try_read_varint()
        if length == 254 and self.buffer:peek_byte() == 0xFA then
          self:handle_legacy_ping()
        elseif length then
          self:handle_packet()
        else
        end
      until not length
    else
      print("socket '" .. tostring(self) .. "' receive error: " .. tostring(err))
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
---@return Connection
local function new(sock)
  local self = {
    sock = sock,
    buffer = Buffer.new(),
    state = STATE_HANDSHAKE
  }
  setmetatable(self, mt)
  return self
end

return {
  new = new
}
