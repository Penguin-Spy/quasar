--[[ log.lua © Penguin_Spy 2024-2025

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.

  The Covered Software may not be used as training or other input data
  for LLMs, generative AI, or other forms of machine learning or neural
  networks.
]]

local insert, format, indent = table.insert, string.format, "  "

local function sort(a, b)
  if type(a) == type(b) then return a < b
  else return type(a) == "number" end -- sort numbers b4 strings
end

---@return string
local function dump(t, level)
  if type(t) == "table" then
    local out = {"{"}
    local sorted_keys = {}
    for k in pairs(t) do insert(sorted_keys, k) end
    table.sort(sorted_keys, sort)
    local index = 1
    for _, key in ipairs(sorted_keys) do
      if key == index then -- print sequential indexes as list items (without [key]=...)
        insert(out, format("%s%s,", indent:rep(level), dump(t[key], level+1)))
        index = index + 1
      else
        insert(out, format("%s[%q]=%s,", indent:rep(level), key, dump(t[key], level+1)))
      end
    end
    insert(out, indent:rep(level-1) .. "}")
    return table.concat(out, "\n")
  else
    return format("%q", t)
  end
end

return function(msg, ...)
  if type(msg) == "string" then
    io.write(format(msg .. "\n", ...))
  else
    io.write(dump(msg, 1) .. "\n")
  end
end
