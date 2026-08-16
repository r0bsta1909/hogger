-- game/gamesim/world.lua — Aufbau und Verwaltung des Spielzustands (ADR-002).
-- Reines Lua: kein love.*, kein os.*, kein math.random. Einzige Zahlenquelle
-- ist sim/model.lua; Zufall nur ueber den Host-RNG (Seed je Try geloggt).

local model = require("sim.model")
local rngmod = require("sim.rng")
local map = require("game.data.map")
local events = require("game.gamesim.events")

local M = {}

M.HOGGER_ID = 0
-- M3: alle acht Vanilla-Allianz-Klassen (GDD 8.2); Reihenfolge = Icon-Slots
M.CLASSES = { "warrior", "paladin", "hunter", "rogue",
              "priest", "mage", "warlock", "druid" }
M.CLASSES_M2 = M.CLASSES -- Altname (Tests/Renderer M2)

-- NPC-IDs beginnen bei 100 (Spieler 1..40, Hogger 0); u8-Adressraum im Wire
M.NPC_ID_BASE = 100

-- Positionen der begehbaren Klassenicons am Wiederbelebungsfeld
function M.class_icon_pos(slot)
  local f = map.field()
  local angle = (slot - 1) * (2 * math.pi / #M.CLASSES) + 0.5
  return f.x + 140 * math.cos(angle), f.y + 140 * math.sin(angle)
end

function M.new(seed)
  local state = {
    seed = seed,
    tick = 0,
    time = 0,           -- monotone Spielzeit (Buffs/Casts; laeuft ueber Trys weiter)
    clock = 0,          -- Try-Uhr in Sekunden (zaehlt hoch, GDD 4.2)
    try_nr = 0,
    phase = "try",      -- "try" | "won"
    won_t = 0,
    n_scale = 0,        -- N beim Try-Start (GDD 6)
    players = {},       -- Array; Index == Spieler-ID (1..40)
    corpses = {},       -- { x, y, drag = nil|{t_left} }
    npcs = {},          -- Wichtel (M3-1), spaeter Mobs/Adds; id -> npc
    next_npc_id = M.NPC_ID_BASE,
    hogger = nil,
    rng = nil,
  }
  return state
end

function M.add_npc(state, kind, x, y, hp, owner)
  local id = state.next_npc_id
  state.next_npc_id = state.next_npc_id + 1
  if state.next_npc_id > 250 then state.next_npc_id = M.NPC_ID_BASE end
  state.npcs[id] = { id = id, kind = kind, x = x, y = y, hp = hp,
                     max_hp = hp, owner = owner, next_auto = 0 }
  return state.npcs[id]
end

function M.add_player(state, name)
  local id = #state.players + 1
  local g = map.graveyard()
  state.players[id] = {
    id = id, name = name or ("spieler" .. id),
    class = nil,             -- erst mit erster Wiederbelebung (GDD 5)
    race = nil,              -- je Wiederbelebung ausgewuerfelt (GDD 5), kosmetisch
    alive = false, ghost = true,
    x = g.x + (id % 5) * 24 - 48, y = g.y + math.floor(id / 5) * 24,
    hp = 0, max_hp = 0, resource = 0, cp = 0,
    facing = 0,
    target = M.HOGGER_ID,
    threat = 0,
    cast = nil,              -- { slot, t_left, total, target }
    gcd = 0, next_auto = 0, raptor_cd = 0,
    last_cast_t = -1000,
    bleed_t = 0, bleed_next = 0,
    shout_until = 0, seal_hits = 0,
    stealth = false, frost_armor = false,
    imp_id = nil,
    dead_until = 0,          -- Respawn-Wartezeit (tot, noch kein Geist)
    revive = nil,            -- { slot, t_left } waehrend des Channels
    prev_mask = 0,
    jump_t = 0, jumps = 0,
    dmg_done = 0, heal_done = 0, deaths = 0,
  }
  return id
end

local function reset_hogger(state)
  state.hogger = {
    id = M.HOGGER_ID,
    x = map.hill.x, y = map.hill.y,
    hp = model.hogger_hp(math.max(1, state.n_scale)),
    max_hp = model.hogger_hp(math.max(1, state.n_scale)),
    state = "idle",         -- idle | combat | eating | reset
    patrol_i = 1,
    threat = {},            -- pid -> Bedrohung
    next_auto = 0, slice_cd = 0, charge_cd = model.p("hogger_charge_cd"),
    eat_cd = 0,
    eating = nil,           -- { phase = "drag"|"channel", t_left, corpse,
                            --   hitters = {}, hitter_count, dmg_accum }
    charge = nil,           -- { target, t_left } (Anlauf/Telegraph)
    slow_until = 0,
    out_of_leash_t = 0,
    bleed_targets = nil,
  }
end

-- Try-Start: N zaehlen, Hogger zuruecksetzen, Seed ableiten, Parameter loggen
function M.begin_try(state, evlist)
  state.try_nr = state.try_nr + 1
  state.clock = 0
  state.phase = "try"
  state.n_scale = #state.players
  state.corpses = {}
  local try_seed = state.seed + state.try_nr * 1000
  state.rng = rngmod.new(try_seed)
  reset_hogger(state)
  for _, p in ipairs(state.players) do
    p.jumps = 0
  end
  if evlist then
    events.push(evlist, state.tick, "try_start", "host", tostring(state.try_nr),
                state.n_scale, nil)
    -- kompletter Parametersatz + Seed (GDD 17.3)
    events.push(evlist, state.tick, "param_change", "init", "seed", try_seed, nil)
    local keys = {}
    for k in pairs(model.params) do keys[#keys + 1] = k end
    table.sort(keys) -- deterministische Reihenfolge (pairs() waere eine Suende)
    for _, k in ipairs(keys) do
      events.push(evlist, state.tick, "param_change", "init", k, model.p(k), nil)
    end
  end
end

-- Zielwahl (reliable Nachricht, ADR-002); loggt target_switch (GDD 13.4)
function M.set_target(state, pid, target_id, evlist)
  local p = state.players[pid]
  if not p then return end
  if target_id ~= M.HOGGER_ID and not state.players[target_id] then return end
  if p.target ~= target_id then
    p.target = target_id
    if evlist then
      events.push(evlist, state.tick, "target_switch", pid, target_id, nil, nil)
    end
  end
end

function M.dist(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return math.sqrt(dx * dx + dy * dy)
end

return M
