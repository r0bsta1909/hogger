-- game/test/headless.lua — Stufe 4 (GDD 17.7): Host + N Bot-Clients
-- in-process ueber 127.0.0.1, fensterlos. Prueft: voller Try inkl.
-- Try-Uebergang, Invarianten je Tick, Snapshot-Budget, Codec-Feldliste
-- gegen den echten State, Rejoin mitten im Try.
-- Aufruf: love game --headless --test   (aus der Repo-Wurzel)

local model = require("sim.model")
local world = require("game.gamesim.world")
local bot = require("game.gamesim.bot")
local wire = require("game.net.wire")
local hostmod = require("game.net.host")
local clientmod = require("game.net.client")

local T = {}
local checks, failures = 0, {}

local function ok(cond, label)
  checks = checks + 1
  if not cond then
    failures[#failures + 1] = label
    print("FEHLER  " .. label)
  end
end

-- Bot-Sicht aus dem Client-Snapshot (Bots fahren den echten Netzpfad)
local function snap_to_botstate(snap, pid)
  local players = {}
  for id, p in pairs(snap.players) do
    players[id] = {
      id = id, alive = p.alive, ghost = p.ghost, class = p.class,
      x = p.x, y = p.y, hp = p.hp,
      max_hp = p.class and model.hp_for_class(p.class) or 1,
    }
  end
  return { players = players, hogger = snap.hogger, tick = snap.tick }
end

function T.run()
  print("== Stufe 4: Host + 4 Bot-Clients (Loopback) ==")
  model.params.try_time_limit.wert = 90 -- Try-Uebergang schnell erzwingen

  local log_lines = {}
  local host = hostmod.new({
    name = "hostbot", seed = 4242, bots = 0, session = false,
    log = function(line) log_lines[#log_lines + 1] = line end,
  })

  local clients = {}
  for i = 1, 4 do
    clients[i] = clientmod.new("127.0.0.1", "botc" .. i)
  end

  local DT = model.TICK_DT
  -- adaptiv: mindestens 150 s; auf langsamen CI-Runnern verbinden die
  -- Bot-Clients spaeter, dann laeuft der Test bis 420 s weiter, statt an
  -- einer festen Frist zu flaken (macOS-Runner, 2026-08-16)
  local min_seconds, max_seconds = 150, 420
  local rejoined = false
  local old_pid_of_c2 = nil
  local max_body = 0
  local function outcome_counts()
    local try_starts, revives, damage_evs = 0, 0, 0
    for _, line in ipairs(log_lines) do
      if line:find('"ev":"try_start"') then try_starts = try_starts + 1 end
      if line:find('"ev":"revive"') then revives = revives + 1 end
      if line:find('"ev":"damage"') then damage_evs = damage_evs + 1 end
    end
    return try_starts, revives, damage_evs
  end

  local iter = 0
  while true do
    iter = iter + 1
    if iter > math.floor(max_seconds / DT) then break end
    if iter > math.floor(min_seconds / DT)
       and iter % math.floor(5 / DT) == 1 then
      local ts, rv, dm = outcome_counts()
      if ts >= 2 and rv >= 4 and dm > 50 then break end
    end
    -- Host: eigener Spieler laeuft als Bot
    local host_inp = bot.decide(host.state, host.local_pid)
    host:update(DT, host_inp)

    for ci, c in ipairs(clients) do
      if not c.dead then
        local inp = { mask = 0, facing = 0 }
        if c.snap and c.pid then
          inp = bot.decide(snap_to_botstate(c.snap, c.pid), c.pid)
        end
        c:update(DT, inp)
      end
    end

    -- Rejoin mitten im Try (GDD 17.7): Client 2 trennen und neu verbinden
    if iter == math.floor(45 / DT) then
      old_pid_of_c2 = clients[2].pid
      clients[2]:destroy()
      clients[2].dead = true
    end
    if iter == math.floor(48 / DT) then
      clients[2] = clientmod.new("127.0.0.1", "botc2")
    end
    if iter == math.floor(60 / DT) and not rejoined then
      rejoined = true
      ok(clients[2].connected, "Rejoin: Client 2 wieder verbunden")
      ok(clients[2].pid == old_pid_of_c2,
        "Rejoin: Charakter haengt am Namen (gleiche PID)")
    end

    -- Invarianten je Tick (GDD 17.7 Stufe 4)
    local st = host.state
    for _, p in ipairs(st.players) do
      ok(p.hp <= p.max_hp + 1e-9, "Invariante: kein Heilen ueber Max")
      ok(p.hp >= 0 or not p.alive, "Invariante: keine negativen HP lebend")
      ok(not (p.alive and p.ghost), "Invariante: nie lebend UND Geist")
      if not p.alive then
        ok((st.hogger.threat[p.id] or 0) == 0,
          "Invariante: kein Ziel gleichzeitig tot und am Boss")
      end
      if checks > 500000 then break end
    end

    -- Snapshot-Budget + Codec-Feldliste alle 5 s
    if iter % math.floor(5 / DT) == 0 then
      local body = wire.snapshot_body(st)
      max_body = math.max(max_body, #body)
      local npc_count, loot_count = 0, 0
      for id = 100, 250 do if st.npcs[id] then npc_count = npc_count + 1 end end
      for id = 1, 60 do if st.loot[id] then loot_count = loot_count + 1 end end
      ok(#body <= 64 + 20 * #st.players + 4 * #st.corpses
              + 8 * npc_count + 6 * loot_count + 32,
        "Snapshot-Budget eingehalten (" .. #body .. " B)")
      local _, snap = wire.read_snapshot(wire.snapshot(0, body), 4)
      for _, p in ipairs(st.players) do
        local sp = snap.players[p.id]
        ok(sp ~= nil, "Codec: jeder Spieler im Snapshot")
        if sp then
          ok(math.abs(sp.x - p.x) <= 1 and math.abs(sp.y - p.y) <= 1,
            "Codec: Position (Quantisierung <= 1 px)")
          ok(sp.alive == (p.alive and true or false), "Codec: alive-Flag")
        end
      end
      ok(snap.hogger.hp == math.max(0, math.floor(st.hogger.hp + 0.5)),
        "Codec: Hogger-HP")
    end
  end

  -- Ergebnis-Pruefungen
  local try_starts, revives, damage_evs = outcome_counts()
  ok(try_starts >= 2, "Voller Try inkl. Try-Uebergang (" .. try_starts .. " Starts)")
  ok(revives >= 4, "Clients beleben sich ueber das Netz wieder (" .. revives .. ")")
  ok(damage_evs > 50, "Kampf laeuft ueber das Netz (" .. damage_evs .. " Treffer)")
  ok(host.state.try_nr >= 1000, "Try-Zaehler vierstellig (GDD 6)")
  -- Leeroy vollendet seinen Loop ohne leeroy_stuck (GDD 17.7 Stufe 4)
  local leeroy_revive, leeroy_stuck = false, false
  for _, line in ipairs(log_lines) do
    if line:find('"ev":"revive","src":"' .. host.state.leeroy_pid .. '"') then
      leeroy_revive = true
    end
    if line:find('"ev":"leeroy_stuck"') then leeroy_stuck = true end
  end
  ok(leeroy_revive, "Leeroy vollendet seinen Loop (Wiederbelebung im Log)")
  ok(not leeroy_stuck, "kein leeroy_stuck-Event")

  for _, c in ipairs(clients) do c:destroy() end
  host:destroy()

  print(string.format("%d Pruefungen, %d Fehler, Snapshot max %d B",
    checks, #failures, max_body))
  return (#failures == 0) and 0 or 1
end

return T
