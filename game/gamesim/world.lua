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

-- i-ter von n Punkten auf einem Ring um (cx, cy). Ab RING_MAX Punkten je Ring
-- kommt ein weiterer Ring dazu, sonst kleben bei grossen Gruppen die Icons.
-- Der "lockere" Versatz ist deterministisch aus dem Index gerechnet — kein
-- RNG-Kanal (Zufalls-Regel GDD 14), damit die Sim reproduzierbar bleibt.
-- Ohne jitter (Standard) liegen die Punkte exakt auf dem Ring.
-- RING_STEP bleibt klein: der aeusserste Ring muss auch bei N=40 innerhalb
-- des engsten Zoom-Radius (zoom_radius_1, 300 px) liegen, sonst sieht ein
-- Spieler am Rand die Mitte des Kreises nicht mehr.
local RING_MAX, RING_STEP = 12, 45
function M.ring_pos(cx, cy, i, n, radius, jitter, phase)
  local ring = math.floor((i - 1) / RING_MAX)
  local first = ring * RING_MAX + 1
  local count = math.min(RING_MAX, n - first + 1)
  local r = radius + ring * RING_STEP
  local angle = (i - first) * (2 * math.pi / math.max(1, count)) + (phase or 0)
  if jitter and jitter > 0 then
    -- zwei teilerfremde Multiplikatoren: Winkel und Radius zappeln
    -- unterschiedlich, das Muster wirkt gewachsen statt gerastert
    angle = angle + ((i * 37) % 23 / 23 - 0.5) * (2 * math.pi / math.max(1, count)) * 0.5
    r = r + ((i * 53) % 17 / 17 - 0.5) * 2 * jitter
  end
  return cx + r * math.cos(angle), cy + r * math.sin(angle)
end

-- Positionen der begehbaren Klassenicons am Wiederbelebungsfeld
function M.class_icon_pos(slot)
  local f = map.field()
  return M.ring_pos(f.x, f.y, slot, #M.CLASSES, 140, 0, 0.5)
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
    won_stage = 0,      -- Endsequenz-Beat fuer den Client (GDD 11, #131)
    merge_from = nil,   -- Startpunkt von Leeroys Koerper fuer die Verschmelzung
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
    -- Das Echo von Leeroy Jenkins (GDD 10.1): Questgeber am Friedhof.
    -- state: idle | charge | deliver | return
    echo = nil,
    -- Leeroys allererster Anmarsch wartet auf die erste angenommene Quest
    -- (GDD 10.3, Issues #33/#53); danach laeuft er jeden Try normal los
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

-- opts.quest_done: Bots, Debug-Laeufe und Rejoins bekommen keine Quest
-- aufgedrueckt (GDD Kap. 5, Punkt 4)
function M.add_player(state, name, opts)
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
    taunt_cd = 0, kick_cd = 0, -- Spott/Tritt (Runde 12, #140/#141)
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
    -- Quest des Echos (GDD Kap. 5): 0 = offen, 1 = aufgedrueckt, 2 = angenommen.
    -- Unter 2 kann sich der Spieler nur um die eigene Achse drehen.
    quest = (opts and opts.quest_done) and 2 or 0,
  }
  return id
end

-- Quest angenommen: ab jetzt darf sich der Spieler bewegen, und der
-- Raid-Leeroy nimmt seinen Pfad auf (GDD 10.3)
function M.accept_quest(state, pid)
  local p = state.players[pid]
  if not p or p.quest ~= 1 then return false end
  p.quest = 2
  return true
end

-- Leeroy Jenkins: Spieler-Entitaet mit KI-Eingabequelle (GDD 10);
-- zaehlt nie in die N-Skalierung, Bedrohung halbiert
function M.add_leeroy(state)
  local id = M.add_player(state, "Leeroy", { quest_done = true })
  state.players[id].is_leeroy = true
  state.leeroy_pid = id
  return id
end

-- Das Echo steht am Friedhof und wartet auf Neuankoemmlinge (GDD 10.1)
function M.reset_echo(state)
  local home = map.echo_home()
  state.echo = { x = home.x, y = home.y, state = "idle", target = nil, t = 0 }
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
    eating = nil,           -- { phase = "drag"|"channel", t_left, corpse }
                            -- (Unterbrechung nur per Tritt, Runde 12 #140)
    charge = nil,           -- { target, t_left } (Anlauf/Telegraph)
    taunt = nil,            -- { pid, until_t } — Spott-Zwang (Runde 12, #141)
    slow_until = 0,
    engaged = false,        -- Try angefangen? (Runde 10, #124)
    no_contact_t = 0,       -- Kein-Kontakt-Uhr (Runde 9, #117)
    reset_cause = nil,      -- "no_contact" | "wipe", solange der Try endet
    bleed_targets = nil,
  }
end

-- N = verbundene, wiederbelebbare Spieler; Leeroy zaehlt nie mit (GDD 6/10).
-- Eine Wahrheit fuer begin_try und die Laufzeit-Skalierung (Runde 9, #118).
function M.count_n(state)
  local n = 0
  for _, p in ipairs(state.players) do
    if not p.is_leeroy and not p.disconnected then n = n + 1 end
  end
  return math.max(1, n)
end

-- Laufzeit-Skalierung (Runde 9, #118): NUR fuer die F12-Debug-Bots. Echte
-- Joins zaehlen weiter erst ab dem naechsten Try (GDD 6). Hoggers HP-ANTEIL
-- bleibt erhalten, Adds werden nur aufgestockt (erschlagene Welpen kommen
-- nicht zurueck, GDD 9.2). Cleave, Unterbrecher, Fressrate und Mob-Slots
-- folgen automatisch ueber n_scale.
function M.rescale(state, evlist)
  local h = state.hogger
  -- Nach dem Sieg oder bei totem Hogger nichts tun: ein hp-Update wuerde
  -- ihn wiederbeleben und den Fluchbruch zerstoeren.
  if state.phase ~= "try" or not h or h.hp <= 0 then return false end
  local n = M.count_n(state)
  if n == state.n_scale then return false end
  state.n_scale = n
  local frac = h.max_hp > 0 and (h.hp / h.max_hp) or 1
  h.max_hp = model.hogger_hp(n)
  h.hp = math.max(1, math.floor(frac * h.max_hp + 0.5))
  -- Adds nur aufstocken, nie loeschen
  local want = model.adds(n)
  local have = state.adds_spawned or 0
  if want > have then
    local addpos = map.add_positions(want)
    for i = have + 1, want do
      local pos = addpos[i]
      local npc = M.add_npc(state, "add", pos.x, pos.y, model.p("add_hp"))
      npc.state = "idle"
      npc.spawn_x, npc.spawn_y = pos.x, pos.y
    end
    state.adds_spawned = want
  end
  M.ensure_mob_slots(state)
  if evlist then
    -- wie der Try-Seed als param_change geloggt: das Log muss erklaeren,
    -- warum Hoggers Max-HP mitten im Try springt
    events.push(evlist, state.tick, "param_change", "host", "n_scale", n, nil)
  end
  return true
end

-- Try-Start: N zaehlen, Hogger zuruecksetzen, Seed ableiten, Parameter loggen
function M.begin_try(state, evlist)
  state.try_nr = state.try_nr + 1
  state.clock = 0
  state.phase = "try"
  state.n_scale = M.count_n(state)
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
  if not state.echo then M.reset_echo(state) end
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
  state.adds_spawned = #addpos -- Basis fuer M.rescale (Runde 9, #118)
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
