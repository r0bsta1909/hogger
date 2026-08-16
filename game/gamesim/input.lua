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

-- ---------------------------------------------------------------------------
-- Blickrichtung: 1 Byte, 0 = Norden, im Uhrzeigersinn (GDD 4.1). Maus,
-- Bot, Leeroy und die Sim rechnen ueber DIESE Funktionen — eine Wahrheit,
-- sonst zielt jede Quelle ein bisschen anders.
-- ---------------------------------------------------------------------------
function M.facing_from_angle(angle)
  return math.floor((angle % (2 * math.pi)) / (2 * math.pi) * 256) % 256
end

function M.facing_towards(px, py, tx, ty)
  return M.facing_from_angle(math.atan2(ty - py, tx - px) + math.pi / 2)
end

-- Liegt (tx, ty) im Frontbogen? arc_deg = voller Oeffnungswinkel;
-- >= 360 schaltet die Regel ab (Tuning-Panel, GDD 8.1)
function M.facing_ok(facing, px, py, tx, ty, arc_deg)
  if not arc_deg or arc_deg >= 360 then return true end
  local want = M.facing_towards(px, py, tx, ty)
  local d = ((facing or 0) - want + 128) % 256 - 128
  return math.abs(d) <= arc_deg * 256 / 360 / 2
end

return M
