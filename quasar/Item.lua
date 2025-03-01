--[[ item.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

---@class Item
---@field id integer
---@field count integer
---@field nbt string
local Item = {}




function Item:tostring()
  return string.format("[Item#%ix%i]", self.id, self.count)
end

function Item._new(id, count, nbt)
  local self = {
    id = id,
    count = count,
    nbt = nbt
  }
  setmetatable(self, { __index = Item, __tostring = Item.tostring })
  return self
end

return Item
