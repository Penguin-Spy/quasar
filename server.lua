local copas = require "copas"
local socket = require "socket"
local Connection = require "connection"

local Server = {}

--[[local ssl_params = {
  wrap = {
    mode = "server",
    protocol = "any"
  }
}]]

-- Listens for connections on the specified address and port.
---@param address string  The address to listen on, or `"*"` to listen on any address
---@param port integer    The port to listen on, usually `25565`
function Server.listen(address, port)
  local server_socket = assert(socket.bind(address, port))

  local function connection_handler(sock)
    print("socket opened:", sock)
    local con = Connection.new(sock)
    con:loop()
  end

  copas.addserver(server_socket, copas.handler(connection_handler --[[, ssl_params]]), "endstone_server")
  copas()
end

return Server
