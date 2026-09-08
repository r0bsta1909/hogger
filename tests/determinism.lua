-- tests/determinism.lua — Stufe 3: gleicher Seed -> gleicher Hash.
-- M0-Stand: beweist die Determinismus-Kette RNG -> Wurffolge -> djb2.
-- Seit Runde 20 (ADR 006) haengt der volle Sim-Vergleich an der Spielsim
-- (sim/gamerun.lua), nicht mehr an einem eigenen 1D-Modell.

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

-- Spielsimulation (gamesim): zwei Bot-Laeufe, gleicher Seed -> gleicher Hash
local gworld = require("game.gamesim.world")
local gbot = require("game.gamesim.bot")
local gevents = require("game.gamesim.events")
local function gamesim_hash(seed, ticks)
  local state = gworld.new(seed)
  for i = 1, 5 do gworld.add_player(state, "bot" .. i, { quest_done = true }) end
  local evs = {}
  gworld.begin_try(state, evs)
  gbot.run(state, ticks, evs)
  local lines = {}
  for i, e in ipairs(evs) do lines[i] = gevents.to_jsonl(e) end
  return hash.djb2(table.concat(lines, "\n"))
end
local g1 = gamesim_hash(42, 120 * 60)
local g2 = gamesim_hash(42, 120 * 60)
T.eq(g1, g2, "Determinismus: gamesim reproduzierbar (Seed 42, 120 s)")
local g3 = gamesim_hash(43, 120 * 60)
T.ok(g1 ~= g3, "Determinismus: gamesim anderer Seed -> anderer Lauf")

-- Spielsim als Balancing-Sim (sim/gamerun.lua, Runde 20): ein ganzer Lauf
-- bis zum Try-Ende, gleicher Seed -> gleicher Hash. Seit Runde 20 haengt
-- der Balancing-Nachweis an dieser Kette, nicht mehr an sim/engine.lua.
local gamerun = require("sim.gamerun")
do
  local a = gamerun.run_try({ n = 5, seed = 4711, crits = true, profile = "typisch", log = true })
  local b = gamerun.run_try({ n = 5, seed = 4711, crits = true, profile = "typisch", log = true })
  T.eq(a.log_hash, b.log_hash, "Determinismus: gamerun reproduzierbar (N=5, Seed 4711)")
  T.eq(a.duration, b.duration, "Determinismus: gamerun gleiche Dauer")
  local c = gamerun.run_try({ n = 5, seed = 4712, crits = true, profile = "typisch", log = true })
  T.ok(a.log_hash ~= c.log_hash, "Determinismus: gamerun anderer Seed -> anderer Lauf")
  -- Krits aus zieht denselben Zufallsstrom (crit_roll wuerfelt auch bei 0 %):
  -- die Krit-Welten sind gepaart, und der Lauf bleibt reproduzierbar
  local d = gamerun.run_try({ n = 5, seed = 4711, crits = false, profile = "typisch", log = true })
  local e = gamerun.run_try({ n = 5, seed = 4711, crits = false, profile = "typisch", log = true })
  T.eq(d.log_hash, e.log_hash, "Determinismus: gamerun ohne Krits reproduzierbar")
end

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
