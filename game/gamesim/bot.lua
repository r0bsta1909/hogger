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
    local slot = ((pid - 1) % #world.CLASSES) + 1
    local ix, iy = world.class_icon_pos(slot)
    local face = input.facing_towards(p.x, p.y, ix, iy)
    if world.dist(p.x, p.y, ix, iy) <= 30 then
      return { mask = 0, facing = face }
    end
    return { mask = move_mask_towards(p.x, p.y, ix, iy, 8), facing = face }
  end

  -- lebend: auf Klassenreichweite an Hogger heran, dann Faehigkeiten.
  -- Caster stehen auf Zauberreichweite, solange Mana da ist; ohne Mana
  -- ruecken sie zum Stab-Vermoebeln in den Nahkampf auf (Issue #86)
  local h = state.hogger
  local attack = model.classes[p.class] and model.classes[p.class].attack or "melee"
  local range = model.p("melee_range")
  if attack == "shot" then range = model.p("autoshot_range") end
  local CASTER = { priest = true, mage = true, warlock = true, druid = true }
  if CASTER[p.class] and (p.resource or 0) >= 20 then
    range = model.p("cast_range")
  end

  local d = world.dist(p.x, p.y, h.x, h.y)
  local mask = 0
  if d > range * 0.9 then
    mask = move_mask_towards(p.x, p.y, h.x, h.y, 8)
  else
    local low_hp = p.hp < 0.5 * p.max_hp
    local cls = p.class
    -- Flanken: Bits nur in einzelnen Ticks setzen
    if cls == "warrior" or cls == "hunter" or cls == "mage"
       or cls == "warlock" or cls == "druid" or cls == "rogue" then
      if state.tick % 30 == 0 then mask = mask + input.AB1 end
    end
    if cls == "priest" then
      if low_hp and state.tick % 30 == 15 then mask = mask + input.AB2
      elseif state.tick % 30 == 0 then mask = mask + input.AB1 end
    end
    if cls == "paladin" then
      if low_hp and state.tick % 30 == 15 then mask = mask + input.AB1
      elseif state.tick % 30 == 0 then mask = mask + input.AB2 end
    end
    if cls == "rogue" and (p.cp or 0) >= 5 and state.tick % 30 == 15 then
      mask = mask + input.AB2
    end
    if cls == "warlock" and state.tick % 600 == 30 then
      mask = mask + input.AB2 -- Wichtel nachbeschwoeren (wirkt nur ohne Wichtel)
    end
    -- WoW-Spieler huepfen permanent (GDD 4.1)
    if state.tick % 90 == 45 then mask = mask + input.JUMP end
  end
  -- Blickrichtung immer aufs Ziel: seit der Frontbogen-Regel (GDD 8.1)
  -- trifft nur, wer sein Ziel ansieht
  return { mask = mask, facing = input.facing_towards(p.x, p.y, h.x, h.y) }
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
