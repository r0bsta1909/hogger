-- tests/run_all.lua — der EINE Testbefehl (CLAUDE.md): lua tests/run_all.lua
-- Optionen: --stage unit | determinism | all (Standard: all)
-- Stufe 4 (headless LOEVE) laeuft separat: love . --headless --test (aus game/)

package.path = "./?.lua;" .. package.path

-- ---------------------------------------------------------------------------
-- love-Vergiftung (CLAUDE.md / Skill Par. 8): die Sim ist beweisbar love-frei.
-- Jeder Zugriff auf love.*, os.time/clock oder math.random unter den Tests
-- laesst die Suite rot werden — maschinell, nicht per Disziplin.
-- ---------------------------------------------------------------------------
local function poison(name)
  return function() error("VERBOTEN in der Sim: " .. name, 2) end
end
_G.love = setmetatable({}, { __index = function(_, k) error("VERBOTEN in der Sim: love." .. tostring(k), 2) end })
os.time = poison("os.time")
os.clock = poison("os.clock")
math.random = poison("math.random")
math.randomseed = poison("math.randomseed")

-- ---------------------------------------------------------------------------
-- Mini-Testrahmen
-- ---------------------------------------------------------------------------
local T = { checks = 0, failures = {} }

function T.ok(cond, label)
  T.checks = T.checks + 1
  if not cond then
    T.failures[#T.failures + 1] = label
    io.write("FEHLER  ", label, "\n")
  end
end

function T.eq(got, expected, label)
  T.ok(got == expected, string.format("%s (erwartet %s, erhalten %s)",
    label, tostring(expected), tostring(got)))
end

function T.near(got, expected, label)
  local eps = math.max(1e-9, math.abs(expected) * 1e-9)
  T.ok(math.abs(got - expected) <= eps, string.format("%s (erwartet %s, erhalten %s)",
    label, tostring(expected), tostring(got)))
end

function T.throws(fn, label)
  local okc = pcall(fn)
  T.ok(not okc, label .. " (haette einen Fehler werfen muessen)")
end

_G.T = T

-- ---------------------------------------------------------------------------
-- Stufen
-- ---------------------------------------------------------------------------
local stage = "all"
for i = 1, #arg do
  if arg[i] == "--stage" then stage = arg[i + 1] end
end

local stages = {
  unit = { "tests.unit_model", "tests.unit_rng", "tests.unit_engine",
           "tests.unit_gamesim", "tests.unit_quest", "tests.unit_killcam",
           "tests.unit_statboard", "tests.unit_assets", "tests.unit_netguard",
           "tests.unit_fx", "tests.unit_admin",
           "tests.unit_release", "tests.unit_errors", "tests.unit_report",
           "tests.unit_panel", "tests.unit_raid" },
  determinism = { "tests.determinism" },
}

local to_run = {}
if stage == "all" then
  for _, name in ipairs(stages.unit) do to_run[#to_run + 1] = name end
  for _, name in ipairs(stages.determinism) do to_run[#to_run + 1] = name end
elseif stages[stage] then
  for _, name in ipairs(stages[stage]) do to_run[#to_run + 1] = name end
else
  io.write("unbekannte Stufe: ", tostring(stage), "\n")
  os.exit(2)
end

for _, name in ipairs(to_run) do
  io.write("== ", name, "\n")
  require(name)
end

io.write(string.format("\n%d Pruefungen, %d Fehler\n", T.checks, #T.failures))
if #T.failures > 0 then os.exit(1) end
