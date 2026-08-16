-- tests/determinism.lua — Stufe 3: gleicher Seed -> gleicher Hash.
-- M0-Stand: beweist die Determinismus-Kette RNG -> Wurffolge -> djb2.
-- Ab M1 kommt der volle Sim-Vergleich dazu (zwei Laeufe, identischer Log-Hash).

local rng = require("sim.rng")
local hash = require("sim.hash")
local T = _G.T

local function draw_sequence(seed)
  local r = rng.new(seed)
  local parts = {}
  for i = 1, 50000 do
    parts[i] = string.format("%.17g", r:next())
  end
  return hash.djb2(table.concat(parts, ";"))
end

local h1 = draw_sequence(12345)
local h2 = draw_sequence(12345)
T.eq(h1, h2, "Determinismus: gleicher Seed -> gleicher Hash")

local h3 = draw_sequence(54321)
T.ok(h1 ~= h3, "Determinismus: anderer Seed -> anderer Hash")

-- Rassenwurf ist eine reine Funktion desselben Wurfs
local model = require("sim.model")
local r = rng.new(99)
local seq1, seq2 = {}, {}
local r2 = rng.new(99)
for i = 1, 1000 do
  seq1[i] = model.roll_race("warrior", r:next())
  seq2[i] = model.roll_race("warrior", r2:next())
end
T.eq(table.concat(seq1, ","), table.concat(seq2, ","),
  "Determinismus: Rassenwurf reproduzierbar")
