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
    local server_port = (self.buffer:byte() << 8) + self.buffer:byte()
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
    self:send(0x00,
      Buffer.encode_string(
        "{\"version\":{\"name\":\"1.20.4\",\"protocol\":765},\"players\":{\"max\":0,\"online\":2,\"sample\":[{\"name\":\"Penguin_Spy\",\"id\":\"dfbd911d-9775-495e-aac3-efe339db7efd\"}]},\"description\":{\"text\":\"woah haiii :3\"},\"enforcesSecureChat\":false,\"previewsChat\":false,\"preventsChatReports\":true}"))

    --
  elseif packet_id == 0x01 and self.state == STATE_STATUS then
    print("ping request with data " .. self.buffer:dump(8))
    self:send(0x01, self.buffer:read(8))
  else
    print(string.format("received unexpected packet id 0x%02X in state %s", packet_id, self.state))
    self:close()
  end
end

-- Receive loop
function Connection:loop()
  while true do
    local _, err, data = self.sock:receivepartial("*a")
    if err == "closed" then
      print("closed", self.sock)
      break
    elseif err == "timeout" then
      self.buffer:append(data)
      print(self.buffer:dump())
      repeat
        local length = self.buffer:try_read_varint()
        if length then
          print("read length", length)
          self:handle_packet()
        else
          print("not read length", length)
        end
      until not length
    else
      print("error", err)
    end
  end
end

function Connection:tostring()
  return "connection " .. tostring(self.sock)
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
