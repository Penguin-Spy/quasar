--[[ util.lua © Penguin_Spy 2024

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.
  This Source Code Form is "Incompatible With Secondary Licenses", as
  defined by the Mozilla Public License, v. 2.0.
]]

local util = {}


function util.remove_value(t, value)
  for k, v in pairs(t) do
    if v == value then
      t[k] = nil
      return true
    end
  end
  return false
end


return util
