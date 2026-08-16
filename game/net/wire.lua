-- game/net/wire.lua — Wire-Format (Skill Par. 4, ADR-001/002).
-- Little-Endian, explizit dimensionierte Typen via love.data.pack.
-- 3-Byte-Header: protoVersion, msgType, flags. Reserviertes flags-Feld wird
-- beim Empfang NICHT geprueft (spaeter erweitern ohne Versionssprung).

local love = love
local W = {}

W.PROTO = 1

W.MSG = {
  HELLO = 1, WELCOME = 2, INPUT = 3, SNAPSHOT = 4, EVENTS = 5,
  SET_TARGET = 6, PARAM_SET = 7, ZOOM = 8,
}

-- Ereignistypen fuers Netz (Kosmetik-Feed; das JSONL-Log bleibt Host-Sache)
W.EV = {
  damage = 1, heal = 2, death = 3, charge = 4,
  eat_start = 5, eat_drag = 6, eat_tick = 7, eat_interrupt = 8,
  eat_complete = 9, crit_kill = 10, try_start = 11, try_end = 12,
  revive = 13,
}
W.EV_NAMES = {}
for name, id in pairs(W.EV) do W.EV_NAMES[id] = name end

local CLASS_NAMES = { "warrior", "paladin", "hunter", "rogue",
                      "priest", "mage", "warlock", "druid" }
local CLASS_IDX = {}
for i, name in ipairs(CLASS_NAMES) do CLASS_IDX[name] = i end
W.CLASS_IDX, W.CLASS_NAMES = CLASS_IDX, CLASS_NAMES

W.NPC_KINDS = { "imp" } -- Index = Wire-ID
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

-- WELCOME: pid + selbstbeschreibender Parametersatz (Skill Par. 4)
function W.welcome(pid, params)
  local keys = {}
  for k in pairs(params) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = { header(W.MSG.WELCOME), pack("<BI2", pid, #keys) }
  for _, k in ipairs(keys) do
    parts[#parts + 1] = pack("<s1d", k, z(params[k].wert))
  end
  return table.concat(parts)
end
function W.read_welcome(data, off)
  local pid, count
  pid, count, off = love.data.unpack("<BI2", data, off)
  local kv = {}
  for _ = 1, count do
    local k, v
    k, v, off = love.data.unpack("<s1d", data, off)
    kv[k] = v
  end
  return pid, kv
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

function W.param_set(key, value)
  return header(W.MSG.PARAM_SET) .. pack("<s1d", key, z(value))
end
function W.read_param_set(data, off)
  return love.data.unpack("<s1d", data, off)
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
    parts[#parts + 1] = pack("<BBBfB", W.EV[e.ev], ent(e.src), ent(e.dst),
      z(tonumber(e.val) or 0), e.crit and 1 or 0)
  end
  return table.concat(parts)
end
function W.read_events(data, off)
  local count
  count, off = love.data.unpack("<I2", data, off)
  local list = {}
  for _ = 1, count do
    local t, src, dst, val, crit
    t, src, dst, val, crit, off = love.data.unpack("<BBBfB", data, off)
    list[#list + 1] = { ev = W.EV_NAMES[t], src = src, dst = dst,
                        val = val, crit = crit == 1 }
  end
  return list
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

local PFLAG = { alive = 1, ghost = 2, casting = 4, jumping = 8, reviving = 16 }
W.PFLAG = PFLAG

local model = require("sim.model")

function W.snapshot_body(state)
  local h = state.hogger
  local parts = {}
  parts[#parts + 1] = pack("<I4I2I2BB",
    state.tick, math.floor(state.clock * 10), state.try_nr,
    state.phase == "won" and 1 or 0, state.n_scale)
  -- Hogger
  local hstate = ({ idle = 0, combat = 1, eating = 2, reset = 3 })[h.state] or 0
  local eatphase, eathit, eatneed, eatprog = 0, 0, 0, 0
  if h.eating then
    eatphase = h.eating.phase == "drag" and 1 or 2
    eathit = h.eating.hitter_count
    eatneed = model.eat_interrupters(math.max(1, state.n_scale))
    local total = (eatphase == 1) and model.p("eat_drag_duration")
                                    or model.p("eat_channel_duration")
    eatprog = q8(1 - h.eating.t_left / total)
  end
  local ctarget, cprog = 255, 0
  if h.charge then
    ctarget = h.charge.target
    cprog = q8(1 - h.charge.t_left / model.p("hogger_charge_windup"))
  end
  parts[#parts + 1] = pack("<I2I2I4I4BBBBBBB",
    q16(h.x), q16(h.y), math.max(0, math.floor(h.hp + 0.5)),
    math.floor(h.max_hp + 0.5), hstate, eatphase, eathit, eatneed, eatprog,
    ctarget, cprog)
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
    -- Buffs/Zustaende fuer die Buff-Leiste (GDD 4.3)
    local flags2 = 0
    if p.stealth then flags2 = flags2 + 1 end
    if (p.shout_until or 0) > state.time then flags2 = flags2 + 2 end
    if (p.seal_hits or 0) > 0 then flags2 = flags2 + 4 end
    if p.frost_armor then flags2 = flags2 + 8 end
    local prog = 0
    if p.cast and p.cast.total then
      prog = q8(1 - p.cast.t_left / p.cast.total)
    elseif p.revive then
      prog = q8(1 - p.revive.t_left / model.p("revive_channel"))
    end
    local race_idx = 0
    for i, r in ipairs(model.RACES) do
      if r == p.race then race_idx = i end
    end
    parts[#parts + 1] = pack("<BBBBBBI2I2I2BBBB",
      p.id, flags, CLASS_IDX[p.class] or 0, race_idx, flags2, p.cp or 0,
      q16(p.x), q16(p.y), math.max(0, math.floor(p.hp + 0.5)),
      q8((p.resource or 0) / 100), p.facing or 0,
      p.target or 255, prog)
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
  s.phase = phase == 1 and "won" or "try"
  local hx, hy, hhp, hmax, hstate, eatphase, eathit, eatneed, eatprog, ctarget, cprog
  hx, hy, hhp, hmax, hstate, eatphase, eathit, eatneed, eatprog, ctarget, cprog, off =
    love.data.unpack("<I2I2I4I4BBBBBBB", data, off)
  s.hogger = {
    x = hx, y = hy, hp = hhp, max_hp = hmax,
    state = ({ [0] = "idle", "combat", "eating", "reset" })[hstate],
    eat = eatphase > 0 and { phase = eatphase == 1 and "drag" or "channel",
                             hitters = eathit, needed = eatneed,
                             progress = eatprog / 255 } or nil,
    charge = ctarget ~= 255 and { target = ctarget, progress = cprog / 255 } or nil,
  }
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
    local pid, flags, cls, race, flags2, cp, px, py, php, pres, pfacing, ptarget, pprog
    pid, flags, cls, race, flags2, cp, px, py, php, pres, pfacing, ptarget, pprog, off =
      love.data.unpack("<BBBBBBI2I2I2BBBB", data, off)
    s.players[pid] = {
      id = pid,
      alive = flags % 2 >= 1,
      ghost = flags % 4 >= 2,
      casting = flags % 8 >= 4,
      jumping = flags % 16 >= 8,
      reviving = flags % 32 >= 16,
      class = CLASS_NAMES[cls],
      race = model.RACES[race],
      stealth = flags2 % 2 >= 1,
      shout = flags2 % 4 >= 2,
      seal = flags2 % 8 >= 4,
      frost_armor = flags2 % 16 >= 8,
      cp = cp,
      x = px, y = py, hp = php, resource = pres / 255 * 100,
      facing = pfacing, target = ptarget, progress = pprog / 255,
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
  return ack, s
end

return W
