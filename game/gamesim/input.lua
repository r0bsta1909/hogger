-- game/gamesim/input.lua — 1-Byte-Input-Bitmaske (ADR-002, Skill Par. 1).
-- Zustaende, keine Impulse; Flankenerkennung passiert in der Sim.
-- Reines Lua 5.1 (bit-Arithmetik ueber Modulo, kein bitops-Modul noetig).

local M = {}

M.LEFT = 1
M.RIGHT = 2
M.UP = 4
M.DOWN = 8
M.JUMP = 16
M.AB1 = 32
M.AB2 = 64
M.AB3 = 128

function M.has(mask, bit)
  return mask % (bit * 2) >= bit
end

-- Bewegungsvektor aus der Maske, normalisiert (Diagonale nicht schneller)
function M.move_vec(mask)
  local dx, dy = 0, 0
  if M.has(mask, M.LEFT) then dx = dx - 1 end
  if M.has(mask, M.RIGHT) then dx = dx + 1 end
  if M.has(mask, M.UP) then dy = dy - 1 end
  if M.has(mask, M.DOWN) then dy = dy + 1 end
  if dx ~= 0 and dy ~= 0 then
    local inv = 1 / math.sqrt(2)
    dx, dy = dx * inv, dy * inv
  end
  return dx, dy
end

-- Flanke: Bit ist jetzt gesetzt, war es im Vortick nicht
function M.pressed(mask, prev_mask, bit)
  return M.has(mask, bit) and not M.has(prev_mask, bit)
end

function M.valid(mask)
  return type(mask) == "number" and mask >= 0 and mask <= 255
         and mask == math.floor(mask)
end

return M
