-- game/net/client.lua — Gast: sendet Inputs (60 Hz, 3-Tick-Redundanz),
-- empfaengt Voll-Snapshots; Rebase + Replay nur fuer die eigene Bewegung
-- (GDD Kap. 14: Client-Prediction nur Bewegung; Skill Par. 3).

local enet = require("enet")
local model = require("sim.model")
local map = require("game.data.map")
local input = require("game.gamesim.input")
local wire = require("game.net.wire")
local hostmod = require("game.net.host")

local C = {}
C.__index = C

local CH_RELIABLE = 0
local HISTORY_MAX = 120 -- Replay-Deckel (2 s)

function C.new(ip, name)
  local self = setmetatable({}, C)
  -- ephemerer Port statt ungebundenem Host (Skill Par. 4; ungebunden
  -- schlaegt der service()-Aufruf in LOEVEs lua-enet fehl)
  self.enet_host = enet.host_create("*:0", 1, 2)
  self.peer = self.enet_host:connect(ip .. ":" .. hostmod.PORT, 2)
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

function C:send_revanche()
  if self.connected then
    self.peer:send(wire.revanche(), CH_RELIABLE, "reliable")
  end
end

function C:send_rename(name)
  if self.connected then
    self.rename_result = nil
    self.peer:send(wire.rename(name), CH_RELIABLE, "reliable")
  end
end

function C:set_target(id)
  if self.connected then
    self.peer:send(wire.set_target(id), CH_RELIABLE, "reliable")
  end
end

function C:send_zoom(level)
  if self.connected then
    self.peer:send(wire.zoom(level), CH_RELIABLE, "reliable")
  end
end

function C:update(dt, local_input)
  local event = self.enet_host:service(0)
  while event do
    if event.type == "receive" then
      self:_handle(event.data)
    elseif event.type == "connect" then
      self.peer:timeout(0, 0, 5000)
      self.peer:send(wire.hello(self.name), CH_RELIABLE, "reliable")
    elseif event.type == "disconnect" then
      self.connected = false
      self.failed = "Vom Server getrennt."
    end
    event = self.enet_host:service(0)
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
      self.peer:send(wire.input(self.ctick, m0, m1, m2, local_input.facing),
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

  self.enet_host:flush()
end

function C:destroy()
  if self.peer then self.peer:disconnect_now() end
  if self.enet_host then self.enet_host:destroy() end
end

return C
