-- game/gamesim/bot.lua — Bot-Eingabequelle (ADR-002: eine Quelle pro Spieler,
-- austauschbar). Reines Lua; liefert je Tick eine Bitmaske wie die Tastatur.
-- Nutzer: Stufe-3/4-Tests, Stresstest-Harness (M3), Debug.

local input = require("game.gamesim.input")
local world = require("game.gamesim.world")
local model = require("sim.model")
local map = require("game.data.map")

local M = {}

local function move_mask_towards(px, py, tx, ty, slack)
  local mask = 0
  local dx, dy = tx - px, ty - py
  if math.abs(dx) > slack then
    mask = mask + (dx > 0 and input.RIGHT or input.LEFT)
  end
  if math.abs(dy) > slack then
    mask = mask + (dy > 0 and input.DOWN or input.UP)
  end
  return mask
end

-- decide(state, pid) -> { mask, facing }
function M.decide(state, pid)
  local p = state.players[pid]
  if not p then return { mask = 0, facing = 0 } end

  -- tot: nichts zu tun
  if not p.alive and not p.ghost then return { mask = 0, facing = 0 } end

  if p.ghost then
    -- zum zugeteilten Klassenicon laufen und stehenbleiben (Channel)
    local slot = ((pid - 1) % #world.CLASSES_M2) + 1
    local ix, iy = world.class_icon_pos(slot)
    if world.dist(p.x, p.y, ix, iy) <= 30 then
      return { mask = 0, facing = 0 }
    end
    return { mask = move_mask_towards(p.x, p.y, ix, iy, 8), facing = 0 }
  end

  -- lebend: auf Klassenreichweite an Hogger heran, dann Faehigkeiten
  local h = state.hogger
  local range = model.p("melee_range")
  if p.class == "hunter" then range = model.p("autoshot_range") end
  if p.class == "priest" then range = model.p("wand_range") end

  local d = world.dist(p.x, p.y, h.x, h.y)
  local mask = 0
  if d > range * 0.9 then
    mask = move_mask_towards(p.x, p.y, h.x, h.y, 8)
  else
    -- Faehigkeit 1 als Flanke: Bit nur jeden 30. Tick setzen
    if state.tick % 30 == 0 then mask = mask + input.AB1 end
    -- Priester: Selbstheilung unter 50 % (Faehigkeit 2)
    if p.class == "priest" and p.hp < 0.5 * p.max_hp
       and state.tick % 30 == 15 then
      mask = mask + input.AB2
    end
    -- WoW-Spieler huepfen permanent (GDD 4.1)
    if state.tick % 90 == 45 then mask = mask + input.JUMP end
  end
  return { mask = mask, facing = (pid * 37) % 256 }
end

-- Bequemer Runner fuer Tests: laeuft n Ticks mit Bots, sammelt Events
function M.run(state, ticks, evsink)
  local step = require("game.gamesim.step")
  for _ = 1, ticks do
    local inputs = {}
    for _, p in ipairs(state.players) do
      inputs[p.id] = M.decide(state, p.id)
    end
    local evs = step.step(state, inputs)
    if evsink then
      for _, e in ipairs(evs) do evsink[#evsink + 1] = e end
    end
  end
end

return M
