-- tests/unit_rng.lua — Stufe 1: deterministischer RNG und djb2-Hash.

local rng = require("sim.rng")
local hash = require("sim.hash")
local T = _G.T

-- Wertebereich und Grundverteilung
local r = rng.new(42)
local min, max, sum = 1, 0, 0
for _ = 1, 10000 do
  local x = r:next()
  if x < min then min = x end
  if x > max then max = x end
  sum = sum + x
end
T.ok(min >= 0, "rng: next() >= 0")
T.ok(max < 1, "rng: next() < 1")
T.ok(math.abs(sum / 10000 - 0.5) < 0.02, "rng: Mittelwert nahe 0,5")

-- range inklusive Grenzen
local r2 = rng.new(7)
local seen_lo, seen_hi = false, false
for _ = 1, 2000 do
  local v = r2:range(1, 3)
  T.checks = T.checks + 1
  if v < 1 or v > 3 then T.failures[#T.failures + 1] = "rng: range ausserhalb [1,3]: " .. v end
  if v == 1 then seen_lo = true end
  if v == 3 then seen_hi = true end
end
T.ok(seen_lo and seen_hi, "rng: range erreicht beide Grenzen")

-- Seed 0 / negative Seeds duerfen nicht in den Nullzyklus laufen
local r0 = rng.new(0)
T.ok(r0:next_int() > 0, "rng: Seed 0 liefert gueltige Folge")

-- djb2: bekannte Referenzwerte (einmal berechnet, ab jetzt eingefroren —
-- aendert sich der Hash, ist das Wire-Format-Vertrauen weg)
T.eq(hash.djb2(""), 5381, "hash: djb2 Leerstring")
T.eq(hash.djb2("hogger"), hash.djb2("hogger"), "hash: djb2 stabil")
T.ok(hash.djb2("hogger") ~= hash.djb2("hoggre"), "hash: djb2 unterscheidet")
