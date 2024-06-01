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

---@type Connection[]
local connections = {}

local server_socket

-- Listens for connections on the specified address and port.
---@param address string  The address to listen on, or `"*"` to listen on any address
---@param port integer    The port to listen on, usually `25565`
function Server.listen(address, port)
  server_socket = assert(socket.bind(address, port))

  local function connection_handler(sock)
    local con = Connection.new(sock)
    table.insert(connections, con)
    con:loop()
    -- remove connection from table when it closes
    for i, c in pairs(connections) do
      if c == con then
        connections[i] = nil
      end
    end
  end

  copas.addserver(server_socket, copas.handler(connection_handler --[[, ssl_params]]), "endstone_server")
  Server.run()
end

function Server.run()
  local success, msg
  repeat
    ---@type boolean, string
    success, msg = pcall(copas.step)
    if not success then
      if msg:sub(-12) == "interrupted!" then
        -- caught Ctrl+C or other quit signal
        print("Caught quit signal, closing server and disconnecting all clients")
      else
        -- encountered an actual error
        print(debug.traceback(msg))
      end

      -- close the server socket
      copas.removeserver(server_socket)
      -- close every Connection
      local n = 0
      for _, con in pairs(connections) do
        con:close()
        n = n + 1
      end
      print("Closed server and " .. n .. " clients")
    end
  until copas.finished()
  return success, msg
end

return Server
