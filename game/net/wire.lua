-- game/net/wire.lua — Wire-Format (Skill Par. 4, ADR-001/002).
-- Little-Endian, explizit dimensionierte Typen via love.data.pack.
-- 3-Byte-Header: protoVersion, msgType, flags. Reserviertes flags-Feld wird
-- beim Empfang NICHT geprueft (spaeter erweitern ohne Versionssprung).

local love = love
local W = {}

W.PROTO = 1

W.MSG = {
  HELLO = 1, WELCOME = 2, INPUT = 3, SNAPSHOT = 4, EVENTS = 5,
  SET_TARGET = 6, PARAM_SET = 7, ZOOM = 8, ROSTER = 9,
  -- 13 war REVANCHE (bis Runde 11): den Knopf gibt es nicht mehr, nach dem
  -- Fluchbruch fuehrt kein Weg zurueck ins Spiel. Die Nummer bleibt frei,
  -- damit alte Aufzeichnungen nicht stillschweigend umgedeutet werden.
  RENAME = 10, RENAME_RESULT = 11, STATS = 12,
  QUEST_ACCEPT = 14, RELEASE_SPIRIT = 15, ENGAGE = 16,
  HEAL_REQUEST = 17,
  KICK = 18, -- Schurken-Tritt (Runde 12, #140): der einzige Unterbrecher
}

-- Ereignistypen fuers Netz (Kosmetik-Feed; das JSONL-Log bleibt Host-Sache)
W.EV = {
  damage = 1, heal = 2, death = 3, charge = 4,
  eat_start = 5, eat_drag = 6, eat_tick = 7, eat_interrupt = 8,
  eat_complete = 9, crit_kill = 10, try_start = 11, try_end = 12,
  revive = 13, loot_pickup = 14, mob_kill = 15, mob_death_by = 16, ding = 17,
  leeroy_line = 18, taunt = 19,
}
W.EV_NAMES = {}
for name, id in pairs(W.EV) do W.EV_NAMES[id] = name end

local CLASS_NAMES = { "warrior", "paladin", "hunter", "rogue",
                      "priest", "mage", "warlock", "druid" }
local CLASS_IDX = {}
for i, name in ipairs(CLASS_NAMES) do CLASS_IDX[name] = i end
W.CLASS_IDX, W.CLASS_NAMES = CLASS_IDX, CLASS_NAMES

-- Schadensarten (GDD 17.3, Feld "art"): Index = Wire-ID, 0 = unbestimmt.
-- Sie steuert Geschoss-/Schlag-Darstellung und Trefferklang (GDD 4.1/12).
W.DMG_ARTS = { "autohit", "ability", "dot", "charge", "slice", "mob", "add" }
local ART_IDX = {}
for i, name in ipairs(W.DMG_ARTS) do ART_IDX[name] = i end

W.NPC_KINDS = { "imp", "add", "boar", "wolf", "kobold", "murloc" } -- Index = Wire-ID
local NPC_KIND_IDX = {}
for i, name in ipairs(W.NPC_KINDS) do NPC_KIND_IDX[name] = i end

local function pack(fmt, ...)
  return love.data.pack("string", fmt, ...)
end

local function header(msg_type)
  return pack("<BBB", W.PROTO, msg_type, 0)
end

function W.read_header(data)
  if #data < 3 then return nil end
  local proto, msg_type = love.data.unpack("<BB", data)
  if proto ~= W.PROTO then return nil, "protoVersion " .. proto end
  return msg_type, 4 -- Offset des Nutzlast-Beginns
end

-- Zahlenfelder begradigen: IEEE-754 kennt +/-0 (Skill Par. 4, [gemessen])
local function z(x) return x + 0.0 end

-- HELLO -----------------------------------------------------------------
function W.hello(name)
  return header(W.MSG.HELLO) .. pack("<s1", name:sub(1, 12))
end
function W.read_hello(data, off)
  return love.data.unpack("<s1", data, off)
end

-- WELCOME: pid + Rejoin-Flag (Kap. 5: kein Intro beim Rejoin) +
-- selbstbeschreibender Parametersatz (Skill Par. 4)
function W.welcome(pid, rejoin, params)
  local keys = {}
  for k in pairs(params) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = { header(W.MSG.WELCOME),
                  pack("<BBI2", pid, rejoin and 1 or 0, #keys) }
  for _, k in ipairs(keys) do
    parts[#parts + 1] = pack("<s1d", k, z(params[k].wert))
  end
  return table.concat(parts)
end
function W.read_welcome(data, off)
  local pid, rejoin, count
  pid, rejoin, count, off = love.data.unpack("<BBI2", data, off)
  local kv = {}
  for _ = 1, count do
    local k, v
    k, v, off = love.data.unpack("<s1d", data, off)
    kv[k] = v
  end
  return pid, rejoin == 1, kv
end

-- RENAME: Namenswunsch aus dem Intro (Kap. 5); Antwort ok/Kollision
function W.rename(name)
  return header(W.MSG.RENAME) .. pack("<s1", name:sub(1, 12))
end
function W.read_rename(data, off)
  return love.data.unpack("<s1", data, off)
end

function W.rename_result(ok)
  return header(W.MSG.RENAME_RESULT) .. pack("<B", ok and 1 or 0)
end
function W.read_rename_result(data, off)
  local ok = love.data.unpack("<B", data, off)
  return ok == 1
end

-- INPUT: Client-Tick + Masken der letzten 3 Ticks + Blickrichtung ---------
function W.input(ctick, m0, m1, m2, facing)
  return header(W.MSG.INPUT) .. pack("<I4BBBB", ctick, m0, m1, m2, facing)
end
function W.read_input(data, off)
  return love.data.unpack("<I4BBBB", data, off)
end

-- SET_TARGET / ZOOM / PARAM_SET ------------------------------------------
function W.set_target(id)
  return header(W.MSG.SET_TARGET) .. pack("<B", id)
end
function W.read_set_target(data, off)
  return love.data.unpack("<B", data, off)
end

function W.zoom(level)
  return header(W.MSG.ZOOM) .. pack("<B", level)
end
function W.read_zoom(data, off)
  return love.data.unpack("<B", data, off)
end

-- Namens-Roster (Einheiten-/Zielfenster): selten, reliable, bei jedem Join
function W.roster(players)
  local parts = { header(W.MSG.ROSTER), pack("<B", #players) }
  for _, p in ipairs(players) do
    parts[#parts + 1] = pack("<Bs1", p.id, (p.name or "?"):sub(1, 12))
  end
  return table.concat(parts)
end
function W.read_roster(data, off)
  local count
  count, off = love.data.unpack("<B", data, off)
  local names = {}
  for _ = 1, count do
    local pid, name
    pid, name, off = love.data.unpack("<Bs1", data, off)
    names[pid] = name
  end
  return names
end

function W.param_set(key, value)
  return header(W.MSG.PARAM_SET) .. pack("<s1d", key, z(value))
end
function W.read_param_set(data, off)
  return love.data.unpack("<s1d", data, off)
end

-- STATS: fertig formatierte Statistik-Tafel am Try-Ende (GDD 11) ----------
-- Zeilen als Strings — der Client rendert nur; ein Format, eine Wahrheit
local function pack_rows(rows)
  local parts = { pack("<B", #rows) }
  for _, r in ipairs(rows) do
    parts[#parts + 1] = pack("<s1s1", r[1]:sub(1, 250), r[2]:sub(1, 250))
  end
  return table.concat(parts)
end
local function read_rows(data, off)
  local count
  count, off = love.data.unpack("<B", data, off)
  local rows = {}
  for _ = 1, count do
    local a, b
    a, b, off = love.data.unpack("<s1s1", data, off)
    rows[#rows + 1] = { a, b }
  end
  return rows, off
end

-- Nahkampf anschalten (Issue #86): Client -> Host, kein Payload
function W.engage()
  return header(W.MSG.ENGAGE)
end

-- Schurken-Tritt (Runde 12, #140): Client -> Host, kein Payload — der Host
-- validiert autoritativ ueber denselben try_ability-Pfad (step.S.kick)
function W.kick()
  return header(W.MSG.KICK)
end

-- Klick-Heilung aus der Heil-Leiste (Runde 7, #103): Ziel-Spieler-ID,
-- reliable. Der Host validiert autoritativ (Heilerklasse, Ziel lebt,
-- heal_range, GCD/Ressource) und startet den Cast mit explizitem Ziel —
-- p.target bleibt unberuehrt (GDD 14, Muster SET_TARGET/ENGAGE, ADR-002).
function W.heal_request(pid)
  return header(W.MSG.HEAL_REQUEST) .. pack("<B", pid)
end
function W.read_heal_request(data, off)
  return love.data.unpack("<B", data, off)
end

function W.stats(board)
  local parts = { header(W.MSG.STATS),
                  pack("<s1s1s1", board.header:sub(1, 250),
                       (board.big or ""):sub(1, 250),
                       (board.wams or ""):sub(1, 250)),
                  pack_rows(board.hogger), pack_rows(board.raid) }
  parts[#parts + 1] = pack("<B", #board.titles)
  for _, t in ipairs(board.titles) do
    parts[#parts + 1] = pack("<s1", t:sub(1, 250))
  end
  return table.concat(parts)
end
function W.read_stats(data, off)
  local board = {}
  local big, wams
  board.header, big, wams, off = love.data.unpack("<s1s1s1", data, off)
  board.big = big ~= "" and big or nil
  board.wams = wams ~= "" and wams or nil
  board.hogger, off = read_rows(data, off)
  board.raid, off = read_rows(data, off)
  local count
  count, off = love.data.unpack("<B", data, off)
  board.titles = {}
  for _ = 1, count do
    local t
    t, off = love.data.unpack("<s1", data, off)
    board.titles[#board.titles + 1] = t
  end
  return board
end

-- EVENTS: kompakter Kosmetik-Feed ----------------------------------------
-- e.src/dst: Spieler-IDs als Zahl; "hogger"/"host" -> 0; nil -> 255
local function ent(v)
  if v == nil then return 255 end
  if type(v) == "number" then return v end
  return 0
end

function W.events(list)
  local parts = { header(W.MSG.EVENTS), pack("<I2", #list) }
  for _, e in ipairs(list) do
    -- letztes Byte: Bit 0 = Krit, Bits 1-4 = Schadensart (kostet nichts extra)
    local flags = (e.crit and 1 or 0) + 2 * (ART_IDX[e.art] or 0)
    parts[#parts + 1] = pack("<BBBfB", W.EV[e.ev], ent(e.src), ent(e.dst),
      z(tonumber(e.val) or 0), flags)
  end
  return table.concat(parts)
end
function W.read_events(data, off)
  local count
  count, off = love.data.unpack("<I2", data, off)
  local list = {}
  for _ = 1, count do
    local t, src, dst, val, flags
    t, src, dst, val, flags, off = love.data.unpack("<BBBfB", data, off)
    list[#list + 1] = { ev = W.EV_NAMES[t], src = src, dst = dst, val = val,
                        crit = flags % 2 == 1,
                        art = W.DMG_ARTS[math.floor(flags / 2) % 16] }
  end
  return list
end

-- QUEST_ACCEPT: der Spieler nimmt die Quest des Echos an (GDD Kap. 5)
function W.quest_accept()
  return header(W.MSG.QUEST_ACCEPT)
end

-- RELEASE_SPIRIT: "Geist freilassen" (GDD Kap. 11)
function W.release_spirit()
  return header(W.MSG.RELEASE_SPIRIT)
end

-- SNAPSHOT ----------------------------------------------------------------
-- Feldliste ist gegen den echten State erhoben; der Stufe-4-Test erzwingt sie.
local function q16(x) -- Position quantisiert auf ganze logische px
  x = math.floor(x + 0.5)
  if x < 0 then x = 0 elseif x > 65535 then x = 65535 end
  return x
end
local function q8(frac)
  local v = math.floor((frac or 0) * 255 + 0.5)
  if v < 0 then v = 0 elseif v > 255 then v = 255 end
  return v
end

local PFLAG = { alive = 1, ghost = 2, casting = 4, jumping = 8, reviving = 16,
                leeroy = 32, bleeding = 64 }
W.PFLAG = PFLAG

local model = require("sim.model")

function W.snapshot_body(state)
  local h = state.hogger
  local parts = {}
  -- Das Phasen-Byte traegt seit Runde 11 (#131) auch den Beat der
  -- Endsequenz: 0 = Try laeuft, 1..4 = Fluchbruch (versammelt, Verschmelzung,
  -- Monolog, Leeroy weg). Kein zusaetzliches Byte noetig — der Snapshot
  -- waechst dadurch nicht, und ausser der Phase liest niemand dieses Feld.
  parts[#parts + 1] = pack("<I4I2I2BB",
    state.tick, math.floor(state.clock * 10), state.try_nr,
    state.phase == "won" and math.max(1, state.won_stage or 1) or 0,
    state.n_scale)
  -- Hogger
  local hstate = ({ idle = 0, combat = 1, eating = 2, reset = 3 })[h.state] or 0
  -- eathit/eatneed sind seit Runde 12 (#140) tote Bytes (der Zaehler fiel
  -- mit der Spieleranzahl-Unterbrechung); sie bleiben als 0 im Format, kein
  -- PROTO-Bump (bewusste Politik seit Runde 8)
  local eatphase, eathit, eatneed, eatprog = 0, 0, 0, 0
  if h.eating then
    eatphase = h.eating.phase == "drag" and 1 or 2
    local total = (eatphase == 1) and model.p("eat_drag_duration")
                                    or model.p("eat_channel_duration")
    eatprog = q8(1 - h.eating.t_left / total)
  end
  local ctarget, cprog = 255, 0
  if h.charge then
    ctarget = h.charge.target
    cprog = q8(1 - h.charge.t_left / model.p("hogger_charge_windup"))
  end
  -- Ziel des Ziels (GDD 4.3): hoechste Bedrohung als Anzeige-Naeherung
  local htarget = 255
  do
    local best = -1
    for _, p in ipairs(state.players) do
      local th = h.threat and h.threat[p.id]
      if p.alive and th and th > best then best, htarget = th, p.id end
    end
  end
  -- slow_rest (Runde 8, #107): Restsekunden des Magier-Frost-Slows an
  -- Hogger (step.lua slow_until), aufgerundet, 0 = kein Slow
  local slow_rest = math.max(0, math.min(255,
    math.ceil((h.slow_until or 0) - state.time)))
  parts[#parts + 1] = pack("<I2I2I4I4BBBBBBBBB",
    q16(h.x), q16(h.y), math.max(0, math.floor(h.hp + 0.5)),
    math.floor(h.max_hp + 0.5), hstate, eatphase, eathit, eatneed, eatprog,
    ctarget, cprog, htarget, slow_rest)
  -- Das Echo von Leeroy Jenkins (GDD 10.1): Standposition. Es bewegt sich
  -- nicht — die Annaeherung ist lokale Darstellung (Issue #61)
  do
    local e = state.echo or { x = 0, y = 0 }
    parts[#parts + 1] = pack("<I2I2", q16(e.x), q16(e.y))
  end
  -- Leichen
  parts[#parts + 1] = pack("<B", math.min(255, #state.corpses))
  for i = 1, math.min(255, #state.corpses) do
    local c = state.corpses[i]
    parts[#parts + 1] = pack("<I2I2", q16(c.x), q16(c.y))
  end
  -- Spieler
  parts[#parts + 1] = pack("<B", #state.players)
  for _, p in ipairs(state.players) do
    local flags = 0
    if p.alive then flags = flags + PFLAG.alive end
    if p.ghost then flags = flags + PFLAG.ghost end
    if p.cast then flags = flags + PFLAG.casting end
    if p.jump_t and p.jump_t > 0 then flags = flags + PFLAG.jumping end
    if p.revive then flags = flags + PFLAG.reviving end
    if p.is_leeroy then flags = flags + PFLAG.leeroy end
    if (p.bleed_t or 0) > 0 then flags = flags + PFLAG.bleeding end
    -- Buffs/Zustaende fuer die Buff-Leiste (GDD 4.3)
    local flags2 = 0
    if p.stealth then flags2 = flags2 + 1 end
    if (p.shout_until or 0) > state.time then flags2 = flags2 + 2 end
    if (p.seal_hits or 0) > 0 then flags2 = flags2 + 4 end
    if p.frost_armor then flags2 = flags2 + 8 end
    -- Bits 5/6: laufender Cast-Slot (1..3) — der Castbalken kann die
    -- Faehigkeit damit beim Namen nennen (GDD 4.2)
    if p.cast and p.cast.slot then flags2 = flags2 + 16 * (p.cast.slot % 4) end
    -- Bits 7/8: Quest-Zustand (0 offen, 1 aufgedrueckt, 2 angenommen)
    flags2 = flags2 + 64 * ((p.quest or 2) % 4)
    local prog = 0
    if p.cast and p.cast.total then
      prog = q8(1 - p.cast.t_left / p.cast.total)
    elseif p.revive then
      prog = q8(1 - p.revive.t_left / model.p("revive_channel"))
    elseif not p.alive and not p.ghost then
      -- tot: dasselbe Byte traegt die Restsekunden bis zur Freigabe
      -- (GDD Kap. 11) — es ist in diesem Zustand sonst unbenutzt
      prog = math.max(0, math.min(255, math.ceil(p.dead_until or 0)))
    end
    local race_idx = 0
    for i, r in ipairs(model.RACES) do
      if r == p.race then race_idx = i end
    end
    local shout_rest = math.max(0, math.min(255,
      math.floor((p.shout_until or 0) - state.time + 0.5)))
    -- flags3 (Runde 13): Schild/Handauflegung/Totstellen/Blutpakt —
    -- Snapshot-Erweiterung ohne PROTO-Bump ist bewusste Politik (Runde 8)
    local flags3 = 0
    if (p.shield_hp or 0) > 0 and state.time < (p.shield_until or 0) then
      flags3 = flags3 + 1
    end
    if p.loh_used then flags3 = flags3 + 2 end
    if state.time < (p.feign_until or 0) then flags3 = flags3 + 4 end
    if p.pact then flags3 = flags3 + 8 end
    if state.time < (p.weak_soul_until or 0) then flags3 = flags3 + 16 end
    parts[#parts + 1] = pack("<BBBBBBI2I2I2BBBBBI2I2I2B",
      p.id, flags, CLASS_IDX[p.class] or 0, race_idx, flags2, p.cp or 0,
      q16(p.x), q16(p.y), math.max(0, math.floor(p.hp + 0.5)),
      q8((p.resource or 0) / 100), p.facing or 0,
      p.target or 255, prog, shout_rest,
      math.min(65535, p.xp or 0), math.min(65535, p.kupfer or 0),
      math.min(65535, p.plunder or 0), flags3)
  end
  -- NPCs (Wichtel; ab M3-2 Mobs/Adds)
  local npc_ids = {}
  for id = 100, 250 do
    if state.npcs and state.npcs[id] then npc_ids[#npc_ids + 1] = id end
  end
  parts[#parts + 1] = pack("<B", #npc_ids)
  for _, id in ipairs(npc_ids) do
    local npc = state.npcs[id]
    parts[#parts + 1] = pack("<BBI2I2B", id, NPC_KIND_IDX[npc.kind] or 0,
      q16(npc.x), q16(npc.y), math.max(0, math.min(255, math.floor(npc.hp + 0.5))))
  end
  -- Bodenbeute
  local loot_ids = {}
  for id = 1, 60 do
    if state.loot and state.loot[id] then loot_ids[#loot_ids + 1] = id end
  end
  parts[#parts + 1] = pack("<B", #loot_ids)
  for _, id in ipairs(loot_ids) do
    local l = state.loot[id]
    parts[#parts + 1] = pack("<BI2I2", id, q16(l.x), q16(l.y))
  end
  return table.concat(parts)
end

-- Kopf je Client: ackInputTick (ADR-001: Body einmal packen, Kopf je Peer)
function W.snapshot(ack, body)
  return header(W.MSG.SNAPSHOT) .. pack("<I4", ack) .. body
end

function W.read_snapshot(data, off)
  local s = {}
  local ack
  ack, off = love.data.unpack("<I4", data, off)
  local clock10, phase
  s.tick, clock10, s.try_nr, phase, s.n_scale, off =
    love.data.unpack("<I4I2I2BB", data, off)
  s.clock = clock10 / 10
  s.phase = phase >= 1 and "won" or "try"
  s.won_stage = phase -- 0 keine, 1 versammelt, 2 Verschmelzung, 3 Monolog, 4 weg
  local hx, hy, hhp, hmax, hstate, eatphase, eathit, eatneed, eatprog,
        ctarget, cprog, htarget, hslow
  hx, hy, hhp, hmax, hstate, eatphase, eathit, eatneed, eatprog, ctarget,
    cprog, htarget, hslow, off =
    love.data.unpack("<I2I2I4I4BBBBBBBBB", data, off)
  s.hogger = {
    x = hx, y = hy, hp = hhp, max_hp = hmax,
    state = ({ [0] = "idle", "combat", "eating", "reset" })[hstate],
    eat = eatphase > 0 and { phase = eatphase == 1 and "drag" or "channel",
                             hitters = eathit, needed = eatneed,
                             progress = eatprog / 255 } or nil,
    charge = ctarget ~= 255 and { target = ctarget, progress = cprog / 255 } or nil,
    target = htarget ~= 255 and htarget or nil,
    slow_rest = hslow, -- Runde 8 (#107): Frost-Slow-Restsekunden
  }
  do
    local ex, ey
    ex, ey, off = love.data.unpack("<I2I2", data, off)
    s.echo = { x = ex, y = ey }
  end
  local ccount
  ccount, off = love.data.unpack("<B", data, off)
  s.corpses = {}
  for i = 1, ccount do
    local cx, cy
    cx, cy, off = love.data.unpack("<I2I2", data, off)
    s.corpses[i] = { x = cx, y = cy }
  end
  local pcount
  pcount, off = love.data.unpack("<B", data, off)
  s.players = {}
  for _ = 1, pcount do
    local pid, flags, cls, race, flags2, cp, px, py, php, pres, pfacing, ptarget, pprog, pshout, pxp, pku, ppl, flags3
    pid, flags, cls, race, flags2, cp, px, py, php, pres, pfacing, ptarget, pprog, pshout, pxp, pku, ppl, flags3, off =
      love.data.unpack("<BBBBBBI2I2I2BBBBBI2I2I2B", data, off)
    s.players[pid] = {
      id = pid,
      alive = flags % 2 >= 1,
      ghost = flags % 4 >= 2,
      casting = flags % 8 >= 4,
      jumping = flags % 16 >= 8,
      reviving = flags % 32 >= 16,
      is_leeroy = flags % 64 >= 32,
      bleeding = flags % 128 >= 64, -- Hoggers Vicious Slice (GDD 9.2)
      class = CLASS_NAMES[cls],
      race = model.RACES[race],
      stealth = flags2 % 2 >= 1,
      shout = flags2 % 4 >= 2,
      seal = flags2 % 8 >= 4,
      frost_armor = flags2 % 16 >= 8,
      cast_slot = math.floor(flags2 / 16) % 4, -- 0 = kein Cast
      quest = math.floor(flags2 / 64) % 4,
      -- flags3 (Runde 13): neue Klassen-Faehigkeiten
      shielded = flags3 % 2 >= 1,        -- Machtwort: Schild (#156)
      loh_used = flags3 % 4 >= 2,        -- Handauflegung verbraucht (#155)
      feigning = flags3 % 8 >= 4,        -- Totstellen (#157)
      pact = flags3 % 16 >= 8,           -- Blutpakt-Aura (#159)
      weak_soul = flags3 % 32 >= 16,     -- Schwache Seele (#156)
      cp = cp,
      x = px, y = py, hp = php, resource = pres / 255 * 100,
      facing = pfacing, target = ptarget, progress = pprog / 255,
      dead_rest = pprog, -- nur sinnvoll, solange tot und noch kein Geist
      shout_rest = pshout, xp = pxp, kupfer = pku, plunder = ppl,
    }
  end
  local ncount
  ncount, off = love.data.unpack("<B", data, off)
  s.npcs = {}
  for _ = 1, ncount do
    local nid, nkind, nx, ny, nhp
    nid, nkind, nx, ny, nhp, off = love.data.unpack("<BBI2I2B", data, off)
    s.npcs[nid] = { id = nid, kind = W.NPC_KINDS[nkind], x = nx, y = ny, hp = nhp }
  end
  local lcount
  lcount, off = love.data.unpack("<B", data, off)
  s.loot = {}
  for _ = 1, lcount do
    local lid, lx, ly
    lid, lx, ly, off = love.data.unpack("<BI2I2", data, off)
    s.loot[lid] = { id = lid, x = lx, y = ly }
  end
  return ack, s
end

return W
