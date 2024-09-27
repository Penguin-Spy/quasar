--[[ server.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

local copas = require "copas"
local copas_timer = require "copas.timer"
local socket = require "socket"
local Connection = require "connection"
local Dimension = require "dimension"
local util = require "util"
local log = require "log"

---@alias identifier string                                     A Minecraft identifier, in the form of `"namespace:thing"`
---@alias uuid       string                                     A UUID in binary form.
---@alias blockpos   {x: integer, y: integer, z: integer}       A block position in the world
---@alias text_component (string|{text:string,color:string?})   A text component. May be either a string containing plain text or a Lua table representing a text component.

local identifier_pattern = "^[%l%d_%-]+:[%l%d_%-]+$"

---@class Server
---@field address string  The IP address the server is listening for connections on. `0.0.0.0` means any address.
---@field port integer    The port the server is listening for connections on.
local Server = {}

---@type table<identifier, Dimension>
local dimensions = {}
---@type Dimension
local default_dimension = nil

-- Creates a new Dimension.
---@param identifier identifier   The identifier for the dimension, e.g. `"minecraft:overworld"`
---@param options nil             Options for the dimension (none currently)
---@return Dimension
function Server.create_dimension(identifier, options)
  if type(identifier) ~= "string" or not string.match(identifier, identifier_pattern) then
    error("'" .. tostring(identifier) .. "' is not a valid identifier!")
  elseif dimensions[identifier] then
    error("A dimension with the identifier '" .. identifier .. "' already exists!")
  end
  local dim = Dimension._new(identifier)
  dimensions[identifier] = dim
  dim.timer = copas_timer.new{
    name      = "quasar_dimension[" .. identifier .. "]",
    recurring = true,
    delay     = 0.05,  -- 20 ticks per second
    callback  = function() dim:tick() end
  }
  return dim
end

function Server.remove_dimension(identifier)
  error("remove_dimension not implemented")
end

-- Gets an existing Dimension.
---@param identifier identifier   The ID of the dimension.
---@return Dimension
function Server.get_dimension(identifier)
  return dimensions[identifier]
end

-- Sets an existing dimension to be the default dimension for players to enter when joining the server.
---@param dimension Dimension
function Server.set_default_dimension(dimension)
  default_dimension = dimension
end

-- Gets the default Dimension for the Server.
---@return Dimension
function Server.get_default_dimension()
  return default_dimension
end

---@type table<uuid, Player>
local players = {}

-- Called at the beginning of the connection ~~right after the player has been authenticated~~.
---@param username string   The username sent by the client
---@param uuid uuid?        Always `nil` - authentication is not implemented yet
---@return boolean?         accept  A falsy return value will disconnect the player immediately
---@return text_component?  message The message to display to the player when disconnected. The client will show this with a title of "Failed to connect to the server"
function Server.on_login(username, uuid)
  -- for now we just always accept the player
  return true
end

-- Called at the end of the configuration stage, once the player object is available.<br>
-- This function can be used to load data for the player (such as their inventory) or specify the dimension they should join in.
---@param player Player
---@return boolean?         accept  A falsy return value will disconnect the player
---@return text_component?  message The message to display to the player when disconnected. The client will show this with a title of "Connection lost"
function Server.on_join(player)
  return true
end


---@type Connection[]
local connections = {}

local server_socket

-- Listens for connections on the specified address and port. <br>
-- This does not start the copas loop, it only binds to the socket & adds the server thread; see `Server.run()`
---@param address string  The address to listen on, or `"*"` to listen on any address
---@param port integer    The port to listen on, usually `25565`, may be `0` to listen on an ephemeral port
function Server.listen(address, port)
  -- make sure a default dimension exists
  if not default_dimension then
    error("At least one dimension must be created and set as the default dimension before starting the server!")
  end

  server_socket = assert(socket.bind(address, port))

  local function connection_handler(sock)
    local con = Connection.new(sock, Server)
    table.insert(connections, con)
    con:loop()
    -- remove connection from table when it closes
    util.remove_value(connections, con)
  end

  copas.addserver(server_socket, copas.handler(connection_handler), nil, "quasar_server")

  local listen_address, listen_port, listen_family = server_socket:getsockname()
  log("Listening for connections to %s:%i (%s)", listen_address, listen_port, listen_family)
  Server.address = listen_address
  Server.port = listen_port
end

-- Cleanly closes the server and all active connections.
function Server.close()
  copas.removeserver(server_socket)

  local n_clients, n_dimensions = 0, 0
  for _, con in pairs(connections) do
    con:disconnect{ translate = "multiplayer.disconnect.server_shutdown" }
    n_clients = n_clients + 1
  end
  for _, dim in pairs(dimensions) do
    dim.timer:cancel()
    n_dimensions = n_dimensions + 1
  end

  log("Closed server, %i clients, and %i dimensions", n_clients, n_dimensions)
end

-- A convenience function that runs the copas loop and catches Ctrl+C to call `Server.close()`
function Server.run()
  repeat
    local success, msg = pcall(copas.step)
    if not success then  ---@cast msg -nil,-boolean,+string
      if msg:sub(-12) == "interrupted!" then
        -- caught Ctrl+C or other quit signal
        print("Caught quit signal, closing server and disconnecting all clients")
      else
        -- encountered an actual error
        print(debug.traceback(msg))
      end
      Server.close()
      return
    end
  until copas.finished()
end

return Server
