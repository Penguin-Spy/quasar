return function(msg, ...)
  io.write(string.format(msg .. "\n", ...))
end
