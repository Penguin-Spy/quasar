local copas = require "copas"
local socket = require "socket"

local Buffer = require "buffer"

-- DEBUG this only exists on my computer
---@class dump function
---@field colorize function
local dump = require "lunacord.dump"

local address = "*"
local port = 25565
--[[local ssl_params = {
  wrap = {
    mode = "server",
    protocol = "any"
  }
}]]

local server_socket = assert(socket.bind(address, port))


-- Attempts to read a VarInt from the start of the buffer.
---@param buffer Buffer
---@return integer?
local function try_read_varint(buffer)
  local value = 0
  for i = 1, 3 do
    local b = buffer:byte()
    print("buffer", i, b)
    if not b then return end
    value = value + ((b & 0x7F) << (i - 1) * 7)
    print("value", value, not ((b & 0x80) == 0x80))
    if not ((b & 0x80) == 0x80) then
      return value
    end
  end
  error("too long or invalid VarInt")
end

local function try_read_string(buffer)
  local length = try_read_varint(buffer)
  if not length then return end
  return buffer:read(length)
end

-- Handles a single packet
---@param buffer Buffer
local function handle_packet(buffer)
  local packet_id = try_read_varint(buffer)
  if packet_id == 0x00 then
    print("handshake")
    local protocol_id = try_read_varint(buffer)
    local server_addr = try_read_string(buffer)
    local server_port = (buffer:byte() << 8) + buffer:byte()
    local next_state = try_read_varint(buffer)
    print("  from protocol " .. protocol_id
      .. " addr " .. server_addr
      .. " port " .. server_port
      .. " next state " .. next_state)
  end
end

local function connection_handler(sock)
  print("socket opened:", sock)
  local buffer = Buffer.new()
  while true do
    local _, err, data = sock:receivepartial("*a")
    --print("data:", dump.colorize(data), dump.colorize(err))
    if err == "closed" then
      print("closed", sock)
      break
    elseif err == "timeout" then
      buffer:append(data)
      print(buffer:dump())
      print("first", dump.colorize(buffer:peek_byte()))
      repeat
        local length
        length = try_read_varint(buffer)
        if length then
          print("read length", length, buffer)
          print("first2", dump.colorize(buffer:peek_byte()))
          handle_packet(buffer)
        else
          print("not read length", length)
        end
      until not length
    else
      print("error", dump.colorize(err))
    end
  end
end

copas.addserver(server_socket, copas.handler(connection_handler --[[, ssl_params]]), "my_TCP_server")

copas()

--return try_read_varint
