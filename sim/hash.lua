-- sim/hash.lua — djb2 ueber Strings.
-- Der EINE Hash des Projekts (Skill Par. 2: Hash in der Sim rechnen, nie love.data.hash;
-- nie zwei Hashes ueber dieselbe Sache). Reines Lua 5.1, alle Zwischenwerte < 2^53.

local M = {}

function M.djb2(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 2147483648
  end
  return h
end

return M
