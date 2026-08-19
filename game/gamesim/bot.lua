-- game/gamesim/bot.lua — Bot-Eingabequelle (ADR-002: eine Quelle pro Spieler,
-- austauschbar). Reines Lua; liefert je Tick eine Bitmaske wie die Tastatur.
-- Nutzer: Stufe-3/4-Tests, Stresstest-Harness (M3), Debug.

local input = require("game.gamesim.input")
local world = require("game.gamesim.world")
local model = require("sim.model")
local map = require("game.data.map")

local M = {}

-- Heiler-Rolle (Runde 12, #143): Befund bestaetigt — Bots heilten nur sich
-- selbst. Jetzt entscheiden sich 2/3 der Heilerklassen-Bots (deterministisch
-- aus der pid, kein RNG-Kanal), aktiv Verbuendete mit <= 80 % HP in
-- Heil-Reichweite zu heilen; 1/3 bleibt reiner Schadensbot.
local HEALER = { paladin = true, priest = true, druid = true }
function M.healer_duty(p)
  return (HEALER[p.class or ""] or false) and p.id % 3 ~= 0
end

-- Bestes Heilziel: niedrigster HP-Anteil unter den lebenden Spielern mit
-- <= 80 % HP in Heil-Reichweite (sich selbst eingeschlossen); ipairs haelt
-- die Wahl deterministisch
function M.heal_target(state, p)
  local best, best_frac
  for _, q in ipairs(state.players) do
    if q.alive and (q.max_hp or 0) > 0 and q.hp <= 0.8 * q.max_hp
       and world.dist(p.x, p.y, q.x, q.y) <= model.p("heal_range") then
      local frac = q.hp / q.max_hp
      if best == nil or frac < best_frac then best, best_frac = q, frac end
    end
  end
  return best
end

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
  -- Heiler-Rolle (#143): Priester/Druide halten Zauber-Reichweite zum Boss
  -- auch ohne Mana (nie in den Cleave); der Paladin heilt aus dem Nahkampf —
  -- im Klumpen steht er ohnehin mitten in seinen Zielen (heal_range 250)
  local duty = M.healer_duty(p)
  if duty and (p.class == "priest" or p.class == "druid") then
    range = model.p("cast_range")
  end

  local d = world.dist(p.x, p.y, h.x, h.y)
  local mask = 0
  local kick = false
  local heal_pid = nil
  if d > range * 0.9 then
    mask = move_mask_towards(p.x, p.y, h.x, h.y, 8)
  else
    local low_hp = p.hp < 0.5 * p.max_hp
    local cls = p.class
    local needy = duty and M.heal_target(state, p) or nil
    -- Heiler-Rolle (#143): Heilwunsch nur im Stand (Bewegung braeche den
    -- Cast sofort wieder ab). Der Wurf geht ueber S.heal_request — derselbe
    -- Pfad wie die Heil-Leiste; GCD, Mana und Reichweite prueft der Host.
    -- Leicht entzerrt (alle 15 Ticks je Bot), damit 40 Bots nicht im
    -- Gleichtakt anfragen.
    if needy and state.tick % 15 == p.id % 15 then
      heal_pid = needy.id
    end
    -- Flanken: Bits nur in einzelnen Ticks setzen. Heiler im Dienst
    -- druecken KEINEN Schadens-Cast, solange jemand Heilung braucht.
    if cls == "warrior" or cls == "hunter" or cls == "mage"
       or cls == "warlock" or cls == "rogue" then
      if state.tick % 30 == 0 then mask = mask + input.AB1 end
    end
    if cls == "druid" and not needy then
      if state.tick % 30 == 0 then mask = mask + input.AB1 end
    end
    if cls == "priest" then
      if duty then
        if not needy and state.tick % 30 == 0 then mask = mask + input.AB1 end
      elseif low_hp and state.tick % 30 == 15 then mask = mask + input.AB2
      elseif state.tick % 30 == 0 then mask = mask + input.AB1 end
    end
    if cls == "paladin" then
      if not duty and low_hp and state.tick % 30 == 15 then
        mask = mask + input.AB1
      elseif state.tick % 30 == 0 then mask = mask + input.AB2 end
    end
    if cls == "rogue" and (p.cp or 0) >= 5 and state.tick % 30 == 15 then
      mask = mask + input.AB2
    end
    -- Schurken-Tritt (Runde 12, #140): frisst Hogger im Kanal und der Bot
    -- steht in Schlagweite, tritt er — CD/Energie prueft der S.kick-Pfad
    if cls == "rogue" and h.eating and h.eating.phase == "channel"
       and d <= model.p("melee_range") then
      kick = true
    end
    if cls == "warlock" and state.tick % 600 == 30 then
      mask = mask + input.AB2 -- Wichtel nachbeschwoeren (wirkt nur ohne Wichtel)
    end
    -- Bots springen NICHT (Runde 12, #142): Springen bricht seit dieser
    -- Runde Casts ab, und die Dauerhopserei stand den Caster-Bots im Weg.
    -- Huepfen bleibt den Menschen ueberlassen.
  end
  -- Blickrichtung immer aufs Ziel: seit der Frontbogen-Regel (GDD 8.1)
  -- trifft nur, wer sein Ziel ansieht. kick und heal liegen NEBEN der
  -- Maske: sie haben kein Bit, der Traeger (Host/Testrunner) ruft
  -- step.kick bzw. step.heal_request auf.
  return { mask = mask, facing = input.facing_towards(p.x, p.y, h.x, h.y),
           kick = kick, heal = heal_pid }
end

-- Bequemer Runner fuer Tests: laeuft n Ticks mit Bots, sammelt Events
function M.run(state, ticks, evsink)
  local step = require("game.gamesim.step")
  for _ = 1, ticks do
    local inputs = {}
    for _, p in ipairs(state.players) do
      local dec = M.decide(state, p.id)
      inputs[p.id] = dec
      -- Tritt/Heilung wie der Host: vor dem Tick, in Spieler-Reihenfolge
      if dec.kick then step.kick(state, p.id, evsink or {}) end
      if dec.heal then step.heal_request(state, p.id, dec.heal, evsink or {}) end
    end
    local evs = step.step(state, inputs)
    if evsink then
      for _, e in ipairs(evs) do evsink[#evsink + 1] = e end
    end
  end
end

return M
