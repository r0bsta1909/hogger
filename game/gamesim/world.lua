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
    npcs = {},          -- Wichtel, Mobs, Adds; id -> npc
    next_npc_id = M.NPC_ID_BASE,
    loot = {},          -- Bodenbeute; id -> { x, y, kupfer, item_idx, t }
    next_loot_id = 1,
    mob_by_slot = {},   -- Spawn-Slot -> npc-id
    mob_respawn = {},   -- Spawn-Slot -> Restzeit bis Respawn (GDD 7.2: 120 s)
    hogger = nil,
    -- Leeroys allererster Anmarsch wartet auf den ersten wiederbelebten
    -- Spieler (GDD 10.3, Issue #33); danach laeuft er jeden Try normal los
    leeroy_started = false,
    rng = nil,
    stats = nil,        -- je Try, gesetzt in begin_try (GDD 11)
  }
  return state
end

function M.add_npc(state, kind, x, y, hp, owner)
  local id = state.next_npc_id
  local tries = 0
  while state.npcs[id] and tries < 150 do
    id = (id >= 250) and M.NPC_ID_BASE or id + 1
    tries = tries + 1
  end
  state.next_npc_id = (id >= 250) and M.NPC_ID_BASE or id + 1
  state.npcs[id] = { id = id, kind = kind, x = x, y = y, hp = hp,
                     max_hp = hp, owner = owner, next_auto = 0 }
  return state.npcs[id]
end

-- Ambient-Mob in einem Spawn-Slot erzeugen (GDD 7.2)
function M.spawn_mob(state, slot)
  local sp = map.MOB_SPAWNS[slot]
  if not sp then return end
  local hp = model.p(sp.typ .. "_hp")
  local npc = M.add_npc(state, sp.typ, sp.x, sp.y, hp)
  npc.slot = slot
  npc.spawn_x, npc.spawn_y = sp.x, sp.y
  npc.state = "idle"
  npc.target_pid = nil
  state.mob_by_slot[slot] = npc.id
  return npc
end

-- aktive Slots sicherstellen (Slot-Formel 7.2); Respawn-Timer tickt in step
function M.ensure_mob_slots(state)
  local active = model.mob_slots(math.max(1, state.n_scale))
  for slot = 1, math.min(active, #map.MOB_SPAWNS) do
    local id = state.mob_by_slot[slot]
    if not (id and state.npcs[id]) and not state.mob_respawn[slot] then
      M.spawn_mob(state, slot)
    end
  end
end

function M.add_loot(state, x, y, kupfer, item_idx)
  local id = state.next_loot_id
  local tries = 0
  while state.loot[id] and tries < 60 do
    id = (id >= 60) and 1 or id + 1
    tries = tries + 1
  end
  state.next_loot_id = (id >= 60) and 1 or id + 1
  state.loot[id] = { id = id, x = x, y = y, kupfer = kupfer,
                     item_idx = item_idx, t = 60 }
  return state.loot[id]
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
    xp = 0, kupfer = 0, plunder = 0, ding_done = false, -- GDD 7.3
  }
  return id
end

-- Leeroy Jenkins: Spieler-Entitaet mit KI-Eingabequelle (GDD 10);
-- zaehlt nie in die N-Skalierung, Bedrohung halbiert
function M.add_leeroy(state)
  local id = M.add_player(state, "Leeroy")
  state.players[id].is_leeroy = true
  state.leeroy_pid = id
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
  -- N = verbundene, wiederbelebbare Spieler; Leeroy zaehlt nie mit (GDD 6/10)
  local n = 0
  for _, p in ipairs(state.players) do
    if not p.is_leeroy and not p.disconnected then n = n + 1 end
  end
  state.n_scale = math.max(1, n)
  state.corpses = {}
  -- Statistik-Tafel (GDD 11): Zaehler je Try, gefuellt in step.lua
  state.stats = {
    hogger = { dmg = 0, kills = 0, crit_kills = 0, eaten = 0, healed = 0,
               interrupts = 0, charges = 0 },
    players = {},        -- pid -> { dmg, deaths, ghost_t, eaten, heal_aggro,
                         --          interrupts, mob_kills }
    first_death = nil,   -- pid des ersten Todes im Try
    boar_victim = nil,   -- Name: "Von einem Wildschwein getoetet" (GDD 7.2)
  }
  local try_seed = state.seed + state.try_nr * 1000
  state.rng = rngmod.new(try_seed)
  reset_hogger(state)
  for _, p in ipairs(state.players) do
    p.jumps = 0
  end
  -- Gnoll-Welpen: floor(N/8) am Huegelfuss, kein Respawn im Try (GDD 9.2)
  for id = M.NPC_ID_BASE, 250 do
    local npc = state.npcs[id]
    if npc and npc.kind == "add" then state.npcs[id] = nil end
  end
  local addpos = map.add_positions(model.adds(math.max(1, state.n_scale)))
  for _, pos in ipairs(addpos) do
    local npc = M.add_npc(state, "add", pos.x, pos.y, model.p("add_hp"))
    npc.state = "idle"
    npc.spawn_x, npc.spawn_y = pos.x, pos.y
  end
  -- Ambient-Mobs bestehen ueber Trys fort; fehlende Slots auffuellen
  M.ensure_mob_slots(state)
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
  if target_id ~= M.HOGGER_ID and not state.players[target_id]
     and not state.npcs[target_id] then return end
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
