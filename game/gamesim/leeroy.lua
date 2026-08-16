-- game/gamesim/leeroy.lua — Leeroy Jenkins, KI-Verhaltensmodell (GDD 10.3).
-- Er ist eine Spieler-Entitaet mit eigener Eingabequelle (ADR-002): die KI
-- liefert je Tick eine Bitmaske wie Tastatur oder Bot. Er weicht nichts aus —
-- Leeroy ist tapfer, nicht klug. Sein Sterben als meist Erster ist emergent.
-- Zustaende: WARTEN -> ANMARSCH (mit Schrei) -> KAMPF -> TOT/GEIST ->
-- WIEDERBELEBUNG (immer Mensch-Krieger) -> ANMARSCH ... bis der Fluch bricht.

local model = require("sim.model")
local input = require("game.gamesim.input")
local world = require("game.gamesim.world")
local map = require("game.data.map")
local grid = require("game.gamesim.grid")
local events = require("game.gamesim.events")

local L = {}
local DT = model.TICK_DT

local function mask_towards(px, py, tx, ty, slack)
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

local function allies_near(state, p, radius)
  local k = 0
  for _, q in ipairs(state.players) do
    if q.alive and q ~= p and world.dist(p.x, p.y, q.x, q.y) <= radius then
      k = k + 1
    end
  end
  return k
end

-- Try-Start-Bedingung (GDD 10.3): Leeroy nimmt seinen Pfad erst auf, wenn
-- der erste Spieler auf dem Realm die Quest seines Echos angenommen hat
-- (Issues #33/#53). Losrennen, waehrend das Echo noch redet, zerreisst die
-- Szene. Danach gilt fuer alle weiteren Trys wieder die normale Wartezeit.
function L.may_march(state)
  if state.leeroy_started then return true end
  for _, q in ipairs(state.players) do
    if not q.is_leeroy and (q.quest or 0) >= 2 then
      state.leeroy_started = true
      return true
    end
  end
  -- Notbremse: niemand belebt sich (alle im Menue, alle weg)
  if state.time >= model.p("leeroy_first_march_wait") then
    state.leeroy_started = true
    return true
  end
  return false
end

function L.decide(state, ev)
  local p = state.players[state.leeroy_pid]
  if not p then return { mask = 0, facing = 0 } end
  local ai = p.ai
  if not ai then
    ai = { phase = "wait", wait_t = 2, path = nil, wp = 1,
           try_seen = state.try_nr, screamed_try = 0,
           last_x = p.x, last_y = p.y, progress_t = 0 }
    p.ai = ai
  end

  -- neuer Try: sammeln, dann neuer Anmarsch (Try-Starter, GDD 10.2)
  if ai.try_seen ~= state.try_nr then
    ai.try_seen = state.try_nr
    if p.alive then
      ai.phase = "wait"
      ai.wait_t = 2
      ai.path = nil
    end
  end

  -- tot: warten (player_tick verwaltet den Respawn)
  if not p.alive and not p.ghost then
    ai.path = nil
    ai.phase = "wait"
    ai.wait_t = 1
    return { mask = 0, facing = p.facing }
  end

  local mask = 0

  if p.ghost then
    -- Geisterlauf zum Krieger-Icon (immer Krieger, fluchbedingt; GDD 10.3)
    local ix, iy = world.class_icon_pos(1)
    if world.dist(p.x, p.y, ix, iy) > 20 then
      mask = mask_towards(p.x, p.y, ix, iy, 8)
    end
  elseif ai.phase == "wait" then
    ai.wait_t = ai.wait_t - DT
    if ai.wait_t <= 0 and L.may_march(state) then
      ai.phase = "march"
      ai.path = grid.path(p.x, p.y,
        map.hill.x + map.path_dir.x * 80, map.hill.y + map.path_dir.y * 80)
      ai.wp = 1
      if ai.screamed_try ~= state.try_nr then
        ai.screamed_try = state.try_nr
        -- DER Schrei: kartenweites Startsignal (GDD 10.2), Zeile 1
        events.push(ev, state.tick, "leeroy_line", "leeroy", 1, nil, nil)
      end
    end
  elseif ai.phase == "march" then
    local h = state.hogger
    if h.hp > 0 and h.state ~= "reset"
       and world.dist(p.x, p.y, h.x, h.y) <= model.p("hogger_aggro_radius") then
      ai.phase = "fight"
    elseif ai.path and ai.path[ai.wp] then
      local wp = ai.path[ai.wp]
      if world.dist(p.x, p.y, wp.x, wp.y) < 24 then
        ai.wp = ai.wp + 1
      else
        mask = mask_towards(p.x, p.y, wp.x, wp.y, 6)
      end
    else
      ai.phase = "fight"
    end
  elseif ai.phase == "fight" then
    local h = state.hogger
    if h.hp <= 0 or h.state == "reset" then
      ai.phase = "wait"
      ai.wait_t = 3
    else
      local d = world.dist(p.x, p.y, h.x, h.y)
      if d > model.p("melee_range") * 0.9 then
        mask = mask_towards(p.x, p.y, h.x, h.y, 6)
      else
        -- Krieger-Kit (GDD 10.3): Heroischer Stoss bei Wut, Schlachtruf
        -- bei >= 3 Verbuendeten im Umkreis — sein einziger Gruppenbeitrag
        if state.tick % 90 == 30 and allies_near(state, p, model.p("warrior_shout_radius")) >= 3
           and p.resource >= model.p("warrior_shout_rage") then
          mask = mask + input.AB2
        elseif state.tick % 30 == 0 then
          mask = mask + input.AB1
        end
      end
    end
  end

  -- Anti-Stuck-Failsafe (GDD 10.3): 5 s ohne messbaren Fortschritt beim
  -- Laufen -> Versatz entlang des Pfads + leeroy_stuck (jedes Vorkommen
  -- ist ein Pathfinding-Bug-Report)
  local moving = mask % 16 > 0
  if moving then
    ai.progress_t = ai.progress_t + DT
    if ai.progress_t >= model.p("leeroy_stuck_timeout") then
      if world.dist(p.x, p.y, ai.last_x, ai.last_y) < 10 then
        p.x, p.y = map.clamp(p.x + map.path_dir.x * -100,
                             p.y + map.path_dir.y * -100)
        events.push(ev, state.tick, "leeroy_stuck", "leeroy", nil, nil, nil)
        ai.path = nil
        ai.phase = p.ghost and ai.phase or "wait"
        ai.wait_t = 1
      end
      ai.last_x, ai.last_y = p.x, p.y
      ai.progress_t = 0
    end
  else
    ai.last_x, ai.last_y = p.x, p.y
    ai.progress_t = 0
  end

  local h = state.hogger
  local facing = input.facing_towards(p.x, p.y, h.x, h.y)
  return { mask = mask, facing = facing }
end

return L
