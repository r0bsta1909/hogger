-- game/test/stress.lua — Stufe 5: 40-Client-Stresstest (GDD 17.4).
-- Headless-Client-Harness: 40 echte ENet-Verbindungen ueber Loopback,
-- 10 Minuten Simulationszeit, Zufallsbewegung + Faehigkeits-Spam.
-- Gemessen wird NUR die Host-Update-Dauer je Tick (Sim + Packen + ENet);
-- Gates: p95 < 16,6 ms, Upstream, GC-Auffaelligkeiten.
-- Aufruf: love game --headless --stress   (lokal, nicht in der CI —
-- CI-Runner sagen nichts ueber den LAN-Host, GDD 17.0)

local model = require("sim.model")
local input = require("game.gamesim.input")
local hostmod = require("game.net.host")
local clientmod = require("game.net.client")

local T = {}

local N_CLIENTS = 40
local SIM_MINUTES = 10

-- deterministische "Zufalls"-Maske je Client und Tick
local function chaos_mask(pid, tick)
  local h = (pid * 2654435761 + tick * 40503) % 2147483648
  local mask = h % 16 -- Bewegungsbits
  if tick % 23 == pid % 23 then mask = mask + input.JUMP end
  if tick % 31 == pid % 31 then mask = mask + input.AB1 end
  if tick % 47 == pid % 47 then mask = mask + input.AB2 end
  if tick % 61 == pid % 61 then mask = mask + input.AB3 end
  return mask
end

function T.run()
  print(string.format("== Stufe 5: Stresstest %d Clients, %d min Simulationszeit ==",
    N_CLIENTS, SIM_MINUTES))

  local host = hostmod.new({ name = "stresshost", seed = 9999, bots = 0,
                             session = false, log = nil })
  local clients = {}
  for i = 1, N_CLIENTS do
    clients[i] = clientmod.new("127.0.0.1", "s" .. i)
  end

  local DT = model.TICK_DT
  local ticks = SIM_MINUTES * 60 * 60
  local durations = {}
  local wall_start = love.timer.getTime()
  local gc_before = collectgarbage("count")

  for iter = 1, ticks do
    local inp = { mask = chaos_mask(0, iter), facing = iter % 256 }

    local t0 = love.timer.getTime()
    host:update(DT, inp)
    local t1 = love.timer.getTime()
    durations[#durations + 1] = (t1 - t0) * 1000

    for ci, c in ipairs(clients) do
      c:update(DT, { mask = chaos_mask(ci, iter), facing = (ci * 7) % 256 })
    end

    if iter % (60 * 60) == 0 then
      print(string.format("  Minute %d/%d ...", iter / 3600, SIM_MINUTES))
    end
  end

  local wall = love.timer.getTime() - wall_start
  local sent = host.host:total_sent_data()

  table.sort(durations)
  local function pct(p)
    return durations[math.max(1, math.floor(#durations * p))]
  end
  local sum = 0
  for _, d in ipairs(durations) do sum = sum + d end
  local mean = sum / #durations
  local p95, p99, worst = pct(0.95), pct(0.99), durations[#durations]
  -- Upstream je Simulationssekunde (Bytes gesamt / Sim-Sekunden)
  local upstream_mbit = sent * 8 / (SIM_MINUTES * 60) / 1e6
  local gc_after = collectgarbage("count")

  local connected = 0
  for _, c in ipairs(clients) do
    if c.connected then connected = connected + 1 end
  end

  print(string.format("Clients verbunden: %d/%d", connected, N_CLIENTS))
  print(string.format("Host-Tickdauer: Mittel %.3f ms · p95 %.3f ms · p99 %.3f ms · max %.3f ms",
    mean, p95, p99, worst))
  print(string.format("Host-Upstream: %.2f Mbit/s (%.1f MB gesamt)",
    upstream_mbit, sent / 1e6))
  print(string.format("Lua-Heap: %.1f -> %.1f MB · Wallzeit %.0f s fuer %d min Sim",
    gc_before / 1024, gc_after / 1024, wall, SIM_MINUTES))

  local ok = connected == N_CLIENTS and p95 < 16.6
  print(ok and "GATE BESTANDEN: Host haelt 60 Hz bei 40 Verbindungen"
            or "GATE VERLETZT")

  for _, c in ipairs(clients) do c:destroy() end
  host:destroy()
  return ok and 0 or 1
end

return T
