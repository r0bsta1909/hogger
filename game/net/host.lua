-- game/net/host.lua — autoritativer Host (ADR-001): Sim 60 Hz, Voll-Snapshots,
-- Body einmal gepackt + ackInputTick je Peer, flush am Frame-Ende (Skill Par. 4).

local enet = require("enet")
local model = require("sim.model")
local world = require("game.gamesim.world")
local step = require("game.gamesim.step")
local wire = require("game.net.wire")
local events = require("game.gamesim.events")

local H = {}
H.__index = H

H.PORT = 44777
local CH_RELIABLE, CH_UNRELIABLE = 0, 1

-- Netz-Ereignisfeed: nur, was Clients zeichnen/hoeren (Rest ist Log-Sache)
local NET_EVS = {}
for name in pairs(wire.EV) do NET_EVS[name] = true end

function H.new(opts)
  local self = setmetatable({}, H)
  self.host = enet.host_create("*:" .. H.PORT, 48, 2) -- 40 Spieler + Reserve
  assert(self.host, "ENet-Port " .. H.PORT .. " nicht bindbar")
  self.state = world.new(opts.seed)
  -- session.json: einzige rundenuebergreifende Persistenz (GDD 17.3)
  self.use_session = opts.session ~= false
  self.session = self.use_session and require("game.session").load() or nil
  -- Try-Zaehler: allererster Host-Start beginnt vierstellig (GDD 6)
  local try_base = (self.session and self.session.try_nr)
                   or (1000 + (opts.seed or 0) % 9000)
  self.state.try_nr = try_base - 1
  self.clients = {}      -- peer -> { pid, queue = {ctick->mask}, next_ctick,
                          --           last_mask, ack, facing }
  self.by_pid = {}
  self.log = opts.log     -- function(jsonl_line) oder nil
  world.add_leeroy(self.state) -- pid 1: der verfluchte Raid-Lead (GDD 10)
  self.local_pid = world.add_player(self.state, opts.name)
  self:_restore_char(self.local_pid)
  self.cosmetics = {}     -- Ereignisse fuer die eigene Darstellung
  -- Debug-Bots (Solo-Test): eigene Eingabequelle je Bot (ADR-002)
  self.bot_pids = {}
  for i = 1, (opts.bots or 0) do
    self.bot_pids[#self.bot_pids + 1] = world.add_player(self.state, "bot" .. i)
  end
  local ev = {}
  world.begin_try(self.state, ev)
  self:_after_step(ev)
  self.accumulator = 0
  return self
end

-- XP/Kupfer/Plunder haengen am Charakternamen (GDD 7.3 / Kap. 5)
function H:_restore_char(pid)
  local p = self.state.players[pid]
  if not (p and self.session and self.session.chars) then return end
  local saved = self.session.chars[p.name]
  if saved then
    p.xp = saved.xp or 0
    p.kupfer = saved.kupfer or 0
    p.plunder = saved.plunder or 0
    p.ding_done = saved.ding or false
    p.titel = saved.titel -- Statistik-Titel (GDD 11 / 17.3)
  end
end

function H:_save_session()
  if not self.use_session then return end
  local chars = (self.session and self.session.chars) or {}
  for _, p in ipairs(self.state.players) do
    -- provisorische Intro-Namen ("gastNNNN") nicht persistieren (Kap. 5)
    if not p.name:find("^gast%d") then
      chars[p.name] = { xp = p.xp, kupfer = p.kupfer, plunder = p.plunder,
                       ding = p.ding_done or false, titel = p.titel }
    end
  end
  self.session = { try_nr = self.state.try_nr, chars = chars }
  require("game.session").save(self.session)
end

function H:_log_events(evlist)
  if not self.log then return end
  for _, e in ipairs(evlist) do
    self.log(events.to_jsonl(e))
  end
end

function H:_after_step(evlist)
  self:_log_events(evlist)
  local net = {}
  for _, e in ipairs(evlist) do
    if NET_EVS[e.ev] then net[#net + 1] = e end
    self.cosmetics[#self.cosmetics + 1] = e
    if e.ev == "try_end" then
      self:_save_session()
      -- Statistik-Tafel (GDD 11): an alle, lokal anzeigen
      if e.board then
        self.stats_board = e.board
        if next(self.clients) then
          self.host:broadcast(wire.stats(e.board), CH_RELIABLE, "reliable")
        end
      end
    end
  end
  if #net > 0 and next(self.clients) then
    self.host:broadcast(wire.events(net), CH_RELIABLE, "reliable")
  end
end

function H:_handle(peer, data)
  local msg, off = wire.read_header(data)
  if not msg then return end
  local c = self.clients[peer]
  if msg == wire.MSG.HELLO then
    local name = wire.read_hello(data, off)
    -- Rejoin: Charakter haengt am Namen (GDD Kap. 14); Rejoin-Flag steuert
    -- das Intro auf dem Client (Kap. 5: "Ah. Wieder da.")
    local pid, rejoin
    for _, p in ipairs(self.state.players) do
      if p.name == name and p.disconnected then
        pid = p.id
        p.disconnected = nil
        rejoin = true
        break
      end
    end
    if not pid then
      -- Namenskollision: Anhaengen statt Ablehnen (Skill Par. 5)
      for _, p in ipairs(self.state.players) do
        if p.name == name and not p.disconnected then
          name = name .. " 2"
        end
      end
      rejoin = self.session and self.session.chars
               and self.session.chars[name] ~= nil or false
      pid = world.add_player(self.state, name)
      self:_restore_char(pid)
    end
    self.clients[peer] = { pid = pid, queue = {}, last_mask = 0,
                           ack = 0, next_ctick = nil, facing = 0 }
    self.by_pid[pid] = self.clients[peer]
    peer:send(wire.welcome(pid, rejoin, model.params), CH_RELIABLE, "reliable")
    self.host:broadcast(wire.roster(self.state.players), CH_RELIABLE, "reliable")
  elseif c and msg == wire.MSG.RENAME then
    -- Namenswunsch aus dem Intro (Kap. 5); Kollision -> "Den gibt's schon."
    local wish = wire.read_rename(data, off)
    local ok = self:rename(c.pid, wish)
    peer:send(wire.rename_result(ok), CH_RELIABLE, "reliable")
  elseif c and msg == wire.MSG.INPUT then
    local ctick, m0, m1, m2 = wire.read_input(data, off)
    local _, _, _, _, facing = wire.read_input(data, off)
    c.facing = facing
    -- Redundanz: Masken der letzten 3 Ticks fuellen Luecken (Skill Par. 3)
    if ctick > c.ack then
      c.queue[ctick] = m0
      if ctick - 1 > c.ack then c.queue[ctick - 1] = c.queue[ctick - 1] or m1 end
      if ctick - 2 > c.ack then c.queue[ctick - 2] = c.queue[ctick - 2] or m2 end
      c.next_ctick = c.next_ctick or math.max(c.ack + 1, ctick - 2)
    end
  elseif c and msg == wire.MSG.SET_TARGET then
    local target = wire.read_set_target(data, off)
    local ev = {}
    world.set_target(self.state, c.pid, target, ev)
    self:_log_events(ev)
  elseif c and msg == wire.MSG.ZOOM then
    local level = wire.read_zoom(data, off)
    if self.log then
      self.log(events.to_jsonl({ t = self.state.tick, ev = "zoom_change",
                                 src = c.pid, val = level }))
    end
  end
end

function H:_client_input(c)
  -- naechste Maske in Client-Tick-Reihenfolge; fehlt sie: letzte wiederholen
  -- (Repeat-Last, Skill Par. 3); ack steht dann still
  if c.next_ctick and c.queue[c.next_ctick] then
    c.last_mask = c.queue[c.next_ctick]
    c.queue[c.next_ctick] = nil
    c.ack = c.next_ctick
    c.next_ctick = c.next_ctick + 1
  end
  return { mask = c.last_mask, facing = c.facing }
end

function H:set_param(key, value)
  local entry = model.params[key]
  if not entry then return end
  value = math.max(entry.min, math.min(entry.max, value))
  entry.wert = value
  if next(self.clients) then
    self.host:broadcast(wire.param_set(key, value), CH_RELIABLE, "reliable")
  end
  if self.log then
    self.log(events.to_jsonl({ t = self.state.tick, ev = "param_change",
                               src = self.local_pid, dst = key, val = value }))
  end
  return value
end

-- Umbenennung nach dem Intro (Kap. 5): jeder vorhandene Charaktername
-- (verbunden ODER getrennt) kollidiert — getrennte gehoeren ihren Spielern
-- und kommen ueber den Rejoin-Pfad zurueck. Erfolg: umbenennen, Session-
-- Stand des Namens uebernehmen, Roster an alle.
function H:rename(pid, wish)
  local p = self.state.players[pid]
  if not p or #wish < 2 or #wish > 12 or wish:find("[^%a]") then return false end
  for _, q in ipairs(self.state.players) do
    if q.id ~= pid and q.name:lower() == wish:lower() then return false end
  end
  p.name = wish
  self:_restore_char(pid)
  if next(self.clients) then
    self.host:broadcast(wire.roster(self.state.players), CH_RELIABLE, "reliable")
  end
  return true
end

function H:set_local_target(target_id)
  local ev = {}
  world.set_target(self.state, self.local_pid, target_id, ev)
  self:_log_events(ev)
end

-- local_input: { mask, facing } vom Tastatur-Layer
function H:update(dt, local_input)
  -- ENet-Schleife pro Frame vollstaendig leeren (Skill Par. 4)
  local event = self.host:service(0)
  while event do
    if event.type == "receive" then
      self:_handle(event.peer, event.data)
    elseif event.type == "connect" then
      event.peer:timeout(0, 0, 5000) -- 5-s-Timeout statt 30 s (Skill Par. 4)
    elseif event.type == "disconnect" then
      local c = self.clients[event.peer]
      if c then
        local p = self.state.players[c.pid]
        if p then p.disconnected = true end
        self.by_pid[c.pid] = nil
        self.clients[event.peer] = nil
      end
    end
    event = self.host:service(0)
  end

  -- fixer Schritt mit gedeckeltem Akkumulator (Skill Par. 1)
  self.accumulator = math.min(self.accumulator + dt, 0.25)
  local stepped = false
  while self.accumulator >= model.TICK_DT do
    self.accumulator = self.accumulator - model.TICK_DT
    local inputs = { [self.local_pid] = local_input }
    for _, c in pairs(self.clients) do
      inputs[c.pid] = self:_client_input(c)
    end
    if #self.bot_pids > 0 then
      local bot = require("game.gamesim.bot")
      for _, pid in ipairs(self.bot_pids) do
        inputs[pid] = bot.decide(self.state, pid)
      end
    end
    local ev = step.step(self.state, inputs)
    self:_after_step(ev)
    stepped = true
  end

  -- Snapshot: Body EINMAL packen, je Peer nur der ack-Kopf (ADR-001)
  if stepped and next(self.clients) then
    local body = wire.snapshot_body(self.state)
    for peer, c in pairs(self.clients) do
      peer:send(wire.snapshot(c.ack, body), CH_UNRELIABLE, "unsequenced")
    end
  end

  self.host:flush() -- am Frame-Ende, nach allen Ticks (Skill Par. 4, [gemessen])
end

function H:destroy()
  self:_save_session()
  if self.host then self.host:destroy() end
end

return H
