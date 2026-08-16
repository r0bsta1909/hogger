-- game/net/discovery.lua — Zero-Config-Discovery (GDD Kap. 3/14, Skill Par. 5).
-- UDP-Broadcast mit socket.udp4 (udp() waere IPv6 und scheitert still an
-- 255.255.255.255, [gemessen]). Rundrufziele: 255.255.255.255 UND eigenes
-- /24-Subnetz UND 127.0.0.1. Der Suchende bindet den Discovery-Port NICHT
-- fest (Host+Client auf einem Rechner!), deshalb Unicast-Antwort auf PROBE.
-- Textprotokoll mit Magic; Fremdpakete werden still verworfen.

local socket = require("socket")

local D = {}
D.PORT = 44778
local MAGIC = "HOGR1"

-- eigene LAN-IP ermitteln (Verbindungs-Trick, sendet nichts)
function D.own_ip()
  local u = socket.udp4()
  if not u then return nil end
  u:settimeout(0)
  local ok = u:setpeername("192.168.255.255", 1)
  local ip
  if ok then ip = u:getsockname() end
  u:close()
  if ip == "0.0.0.0" then return nil end
  return ip
end

local function broadcast_targets()
  local targets = { "255.255.255.255", "127.0.0.1" }
  local ip = D.own_ip()
  if ip then
    local subnet = ip:match("^(%d+%.%d+%.%d+)%.")
    if subnet then targets[#targets + 1] = subnet .. ".255" end
  end
  return targets
end

-- ---------------------------------------------------------------------------
-- Host-Bake: ANNOUNCE je 1 s, Unicast-Antwort auf PROBE; erkennt aeltere
-- Lobbys (Degradierung bei Gleichzeitstart, GDD Kap. 3)
-- ---------------------------------------------------------------------------
local Host = {}
Host.__index = Host

function D.new_host(lobby_id, start_time, game_port)
  local self = setmetatable({}, Host)
  self.sock = socket.udp4()
  self.sock:setoption("reuseaddr", true)
  self.sock:setoption("broadcast", true)
  self.sock:settimeout(0)
  local ok = self.sock:setsockname("*", D.PORT)
  if not ok then
    -- Port belegt (zweiter Host auf dem Rechner): nur senden, nicht lauschen
    self.sock:setsockname("*", 0)
  end
  self.lobby_id = lobby_id
  self.start_time = start_time
  self.game_port = game_port
  self.targets = broadcast_targets()
  self.announce_t = 0
  self.degrade_to = nil -- { ip, port } einer aelteren Lobby
  return self
end

function Host:announce_msg()
  return string.format("%s A %s %.3f %d", MAGIC, self.lobby_id,
    self.start_time, self.game_port)
end

function Host:update(dt)
  self.announce_t = self.announce_t - dt
  if self.announce_t <= 0 then
    self.announce_t = 1
    for _, ip in ipairs(self.targets) do
      self.sock:sendto(self:announce_msg(), ip, D.PORT)
    end
  end
  while true do
    local data, from_ip, from_port = self.sock:receivefrom()
    if not data then break end
    local kind = data:match("^" .. MAGIC .. " (%a)")
    if kind == "P" then
      self.sock:sendto(self:announce_msg(), from_ip, from_port)
    elseif kind == "A" then
      local lid, st = data:match("^" .. MAGIC .. " A (%S+) (%S+)")
      st = tonumber(st)
      if lid and st and lid ~= self.lobby_id then
        -- aelterer Beacon gewinnt; Gleichstand: kleinere Lobby-ID
        if st < self.start_time
           or (st == self.start_time and lid < self.lobby_id) then
          local port = tonumber(data:match("(%d+)%s*$"))
          self.degrade_to = { ip = from_ip, port = port or 0 }
        end
      end
    end
  end
end

function Host:close()
  self.sock:close()
end

-- ---------------------------------------------------------------------------
-- Suche: PROBE je 2 s ueber fluechtigen Port, Announces mithoeren, wenn der
-- Discovery-Port frei ist; Lobby-Dedup ueber die ID, 127.0.0.1 bevorzugt
-- ---------------------------------------------------------------------------
local Search = {}
Search.__index = Search

function D.new_search()
  local self = setmetatable({}, Search)
  self.sock = socket.udp4()
  self.sock:setoption("broadcast", true)
  self.sock:settimeout(0)
  self.sock:setsockname("*", 0)
  self.listen = socket.udp4()
  self.listen:setoption("reuseaddr", true)
  self.listen:settimeout(0)
  if not self.listen:setsockname("*", D.PORT) then
    self.listen:close()
    self.listen = nil -- Bind darf scheitern (Host laeuft lokal)
  end
  self.targets = broadcast_targets()
  self.probe_t = 0
  self.lobbies = {} -- id -> { ip, port, start_time, last_seen }
  self.clock = 0
  return self
end

local function search_handle(self, data, from_ip)
  local lid, st, port = data:match("^" .. MAGIC .. " A (%S+) (%S+) (%d+)")
  if not lid then return end
  local entry = self.lobbies[lid]
  if not entry then
    entry = { ip = from_ip, port = tonumber(port),
              start_time = tonumber(st), last_seen = self.clock }
    self.lobbies[lid] = entry
  else
    entry.last_seen = self.clock
    if from_ip == "127.0.0.1" then entry.ip = from_ip end -- lokal bevorzugen
  end
end

function Search:update(dt)
  self.clock = self.clock + dt
  self.probe_t = self.probe_t - dt
  if self.probe_t <= 0 then
    self.probe_t = 2
    for _, ip in ipairs(self.targets) do
      self.sock:sendto(MAGIC .. " P", ip, D.PORT)
    end
  end
  while true do
    local data, from_ip = self.sock:receivefrom()
    if not data then break end
    search_handle(self, data, from_ip)
  end
  if self.listen then
    while true do
      local data, from_ip = self.listen:receivefrom()
      if not data then break end
      search_handle(self, data, from_ip)
    end
  end
  for id, e in pairs(self.lobbies) do
    if self.clock - e.last_seen > 5 then self.lobbies[id] = nil end
  end
end

-- aelteste Lobby (Gleichstand: kleinste ID)
function Search:best()
  local best, best_id
  for id, e in pairs(self.lobbies) do
    if not best or e.start_time < best.start_time
       or (e.start_time == best.start_time and id < best_id) then
      best, best_id = e, id
    end
  end
  return best
end

function Search:close()
  self.sock:close()
  if self.listen then self.listen:close() end
end

return D
