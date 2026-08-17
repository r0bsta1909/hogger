-- game/net/client.lua — Gast: sendet Inputs (60 Hz, 3-Tick-Redundanz),
-- empfaengt Voll-Snapshots; Rebase + Replay nur fuer die eigene Bewegung
-- (GDD Kap. 14: Client-Prediction nur Bewegung; Skill Par. 3).

local enet = require("enet")
local model = require("sim.model")
local map = require("game.data.map")
local input = require("game.gamesim.input")
local wire = require("game.net.wire")
local hostmod = require("game.net.host")
local netguard = require("game.net.netguard")

local C = {}
C.__index = C

local CH_RELIABLE = 0
local HISTORY_MAX = 120 -- Replay-Deckel (2 s)

function C.new(ip, name)
  local self = setmetatable({}, C)
  self.guard = netguard.new()
  -- ephemerer Port statt ungebundenem Host (Skill Par. 4; ungebunden
  -- schlaegt der service()-Aufruf in LOEVEs lua-enet fehl); scheitert schon
  -- das Anlegen (macOS-Firewall, belegter Port), ist das kein Absturz,
  -- sondern ein Verbindungsfehler (Issue #23)
  local ok, host_or_err = pcall(enet.host_create, "*:0", 1, 2)
  self.enet_host = ok and host_or_err or nil
  if self.enet_host then
    local okc, peer_or_err = pcall(self.enet_host.connect, self.enet_host,
      ip .. ":" .. hostmod.PORT, 2)
    self.peer = okc and peer_or_err or nil
    if not okc then self.net_error = tostring(peer_or_err) end
  else
    self.net_error = tostring(host_or_err)
  end
  if not self.peer then self.failed = "Vom Server getrennt." end
  self.name = name
  self.pid = nil
  self.snap = nil
  self.ack = 0
  self.ctick = 0
  self.history = {}      -- ctick -> mask (fuer Redundanz + Replay)
  self.cosmetics = {}    -- Ereignisse fuer Darstellung
  self.names = {}        -- pid -> Charaktername (Roster)
  self.predicted = nil   -- { x, y } eigene Position nach Rebase+Replay
  self.accumulator = 0
  self.connected = false
  self.failed = nil
  return self
end

function C:_rebase()
  -- Snapshot anwenden, eigene Masken seit ackInputTick wieder vorspielen
  -- (eine Zeitbasis, Skill Par. 3); Deckel gegen Ausreisser
  local me = self.snap and self.pid and self.snap.players[self.pid]
  if not me then self.predicted = nil return end
  local x, y = me.x, me.y
  local speed = me.alive and model.p("move_speed_alive")
                or me.ghost and model.p("move_speed_ghost") or 0
  local from = math.max(self.ack + 1, self.ctick - HISTORY_MAX)
  for t = from, self.ctick do
    local mask = self.history[t]
    if mask and speed > 0 then
      local dx, dy = input.move_vec(mask)
      x, y = map.clamp(x + dx * speed * model.TICK_DT,
                       y + dy * speed * model.TICK_DT)
    end
  end
  self.predicted = { x = x, y = y }
end

function C:_handle(data)
  local msg, off = wire.read_header(data)
  if not msg then return end
  if msg == wire.MSG.WELCOME then
    local pid, rejoin, kv = wire.read_welcome(data, off)
    self.pid = pid
    self.rejoin = rejoin -- Kap. 5: Rejoin -> kein Intro, nur "Ah. Wieder da."
    self.connected = true
    for k, v in pairs(kv) do
      if model.params[k] then model.params[k].wert = v end
    end
  elseif msg == wire.MSG.RENAME_RESULT then
    self.rename_result = wire.read_rename_result(data, off) -- Intro holt ab
  elseif msg == wire.MSG.STATS then
    self.stats_board = wire.read_stats(data, off) -- main zeigt die Tafel
  elseif msg == wire.MSG.SNAPSHOT then
    local ack, snap = wire.read_snapshot(data, off)
    -- unsequenced Kanal: veraltete Snapshots verwerfen
    if not self.snap or snap.tick >= self.snap.tick then
      self.snap = snap
      self.ack = ack
      -- Verlauf unterhalb des Acks aufraeumen
      for t in pairs(self.history) do
        if t <= ack - 3 then self.history[t] = nil end
      end
      self:_rebase()
    end
  elseif msg == wire.MSG.EVENTS then
    local list = wire.read_events(data, off)
    for _, e in ipairs(list) do
      self.cosmetics[#self.cosmetics + 1] = e
    end
  elseif msg == wire.MSG.PARAM_SET then
    local k, v = wire.read_param_set(data, off)
    if model.params[k] then model.params[k].wert = v end
  elseif msg == wire.MSG.ROSTER then
    self.names = wire.read_roster(data, off)
  end
end

-- jeder Sendeweg geht durch den Guard: ein Socket-Fehler ist ein
-- Verbindungsproblem, kein Programmabbruch (Issue #23)
function C:_send(data, channel, mode)
  if not (self.connected and self.peer) then return false end
  return self.guard:call(self.peer.send, self.peer, data, channel, mode)
end

function C:release_spirit()
  self:_send(wire.release_spirit(), CH_RELIABLE, "reliable")
end

function C:accept_quest()
  self:_send(wire.quest_accept(), CH_RELIABLE, "reliable")
end

function C:send_revanche()
  self:_send(wire.revanche(), CH_RELIABLE, "reliable")
end

-- Nahkampf anschalten (Issue #86): Rechtsklick oder Taste 4
function C:send_engage()
  self:_send(wire.engage(), CH_RELIABLE, "reliable")
end

function C:send_rename(name)
  if self.connected then self.rename_result = nil end
  self:_send(wire.rename(name), CH_RELIABLE, "reliable")
end

function C:set_target(id)
  self:_send(wire.set_target(id), CH_RELIABLE, "reliable")
end

function C:send_zoom(level)
  self:_send(wire.zoom(level), CH_RELIABLE, "reliable")
end

function C:update(dt, local_input)
  if not self.enet_host then return end
  self.guard:frame(dt)
  -- ENet-Schleife: bricht beim ersten Socket-Fehler ab statt zu drehen
  local ok, event = self.guard:call(self.enet_host.service, self.enet_host, 0)
  while ok and event do
    if event.type == "receive" then
      self:_handle(event.data)
    elseif event.type == "connect" then
      self.guard:call(self.peer.timeout, self.peer, 0, 0, 5000)
      self.connected = true -- fuer den Sendeweg; WELCOME bestaetigt danach
      self:_send(wire.hello(self.name), CH_RELIABLE, "reliable")
    elseif event.type == "disconnect" then
      self.connected = false
      self.failed = "Vom Server getrennt."
    end
    ok, event = self.guard:call(self.enet_host.service, self.enet_host, 0)
  end

  if self.connected then
    -- Input im 60-Hz-Takt, Masken der letzten 3 Ticks (Skill Par. 3)
    self.accumulator = math.min(self.accumulator + dt, 0.25)
    while self.accumulator >= model.TICK_DT do
      self.accumulator = self.accumulator - model.TICK_DT
      self.ctick = self.ctick + 1
      self.history[self.ctick] = local_input.mask
      local m0 = local_input.mask
      local m1 = self.history[self.ctick - 1] or m0
      local m2 = self.history[self.ctick - 2] or m1
      self:_send(wire.input(self.ctick, m0, m1, m2, local_input.facing),
        1, "unsequenced")
      -- lokale Vorhersage sofort weiterfuehren (eine Zeitbasis)
      if self.predicted then
        local me = self.snap and self.snap.players[self.pid]
        local speed = me and (me.alive and model.p("move_speed_alive")
                     or me.ghost and model.p("move_speed_ghost")) or 0
        if speed > 0 then
          local dx, dy = input.move_vec(local_input.mask)
          self.predicted.x, self.predicted.y = map.clamp(
            self.predicted.x + dx * speed * model.TICK_DT,
            self.predicted.y + dy * speed * model.TICK_DT)
        end
      end
    end
  end

  self.guard:call(self.enet_host.flush, self.enet_host)

  -- anhaltender Netzfehler = Verbindungsverlust; main.lua zeigt daraufhin den
  -- Disconnect-Dialog und sucht neu (GDD Kap. 3) statt abzustuerzen
  if self.guard.dead and not self.failed then
    self.connected = false
    self.failed = "Vom Server getrennt."
    self.net_error = self.guard.last_error
  end
end

function C:destroy()
  if self.peer then pcall(self.peer.disconnect_now, self.peer) end
  if self.enet_host then pcall(self.enet_host.destroy, self.enet_host) end
end

return C
