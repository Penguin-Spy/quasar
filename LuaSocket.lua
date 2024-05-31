---@meta

---@class LuaSocket
socket = {}

---@alias LuaSocket.error
---| "timeout"  The receive timed out
---| "closed"   The socket is closed
---| nil        No error occured

--
---@param pattern string
---@return nil, LuaSocket.error err  `nil` if no error, else the error that occured
---@return string               data  The data received
function socket:receivepartial(pattern) end

--
---@param data string
---@return integer|nil      i   The number of bytes sent
---@return LuaSocket.error  err `nil` if no error, else the error that occured
function socket:send(data) end

function socket:close() end
