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

-- Seed-Mischung (Runde 20): der erste Wert eines Lehmer-Generators ist LINEAR
-- im Seed — benachbarte Seeds (Lauf 1, 2, 3 ...) liefern als ersten Wert
-- eine Treppe (gemessen: Gruppenfaktor 0,81 / 0,84 / 0,87 / ... je Lauf).
-- Wer je Lauf einen Nebenstrom braucht (Streuung, Bot-Gehirne), mischt den
-- Seed hier nichtlinear: Quadrieren modulo bricht die Gitterstruktur,
-- bleibt exakt in Doubles (s < 2^26, s^2 < 2^52) und plattformgleich.
-- salt trennt Nebenstroeme derselben Laufnummer voneinander.
function M.mix(seed, salt)
  local s = (math.floor(seed) + (salt or 0) * 1000003) % 67108864 -- 2^26
  s = (s * s + s * 7919 + 17) % (MOD - 1)
  local s2 = (s * 48271 + 1) % 67108864
  s = (s + s2 * s2) % (MOD - 1)
  return s + 1
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
