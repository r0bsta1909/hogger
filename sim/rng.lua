-- sim/rng.lua — deterministischer Zufall (Lehmer / Park-Miller, Modulus 2^31-1).
-- Einzige erlaubte Zufallsquelle der Simulation und des Spiels (GDD 13.2):
-- 5-%-Krit und Loot-Roll, nur auf dem Host, Seed pro Try geloggt.
-- Reines Lua 5.1: 16807 * state < 2^45, exakt in Doubles darstellbar.

local RNG = {}
RNG.__index = RNG

local M = {}

local MOD = 2147483647 -- 2^31 - 1

function M.new(seed)
  seed = math.floor(seed) % MOD
  if seed <= 0 then seed = seed + (MOD - 1) end
  return setmetatable({ state = seed }, RNG)
end

-- naechster Rohwert, 1 .. 2^31-2
function RNG:next_int()
  self.state = (self.state * 16807) % MOD
  return self.state
end

-- gleichverteilt in [0, 1)
function RNG:next()
  return (self:next_int() - 1) / (MOD - 1)
end

-- true mit Wahrscheinlichkeit p
function RNG:roll(p)
  return self:next() < p
end

-- Ganzzahl in [lo, hi] (inklusive)
function RNG:range(lo, hi)
  return lo + self:next_int() % (hi - lo + 1)
end

return M
