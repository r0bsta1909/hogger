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
    skip_quest = true, -- der Host laeuft hier als Bot, ohne Questfenster
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
  local revanche_sent, revanche_done = false, false
  local addbot_pid, addbot_x = nil, nil -- Laufzeit-Bots (Runde 8, #109)
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
        -- Quest des Echos annehmen, sobald sie aufgedrueckt wurde (GDD 5):
        -- ohne Annahme bleibt der Spieler stehen (Issue #50)
        local me = c.snap and c.pid and c.snap.players[c.pid]
        if me and (me.quest or 2) == 1 and not c.quest_sent then
          c.quest_sent = true
          c:accept_quest()
        end
        -- "Geist freilassen" ueber das Netz, sobald der Timer durch ist
        -- (GDD Kap. 11, Issue #54)
        if me and not me.alive and not me.ghost and (me.dead_rest or 1) <= 0 then
          c:release_spirit()
          c.released_once = true
        end
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
      ok(clients[2].rejoin == true,
        "Rejoin: WELCOME-Flag gesetzt (kein Intro, GDD 5)")
    end

    -- Quest des Echos (GDD Kap. 5 / Issue #50): aufgedrueckt und angenommen
    if iter == math.floor(40 / DT) then
      local pid1 = clients[1].pid
      ok(host.state.players[pid1] and host.state.players[pid1].quest == 2,
        "Quest: Client 1 hat die Quest des Echos angenommen")
      ok(host.state.leeroy_started == true,
        "Quest: die erste Annahme startet den Raid-Leeroy (GDD 10.3)")
      ok(clients[1].snap and clients[1].snap.echo ~= nil,
        "Quest: das Echo steht im Snapshot")
    end

    -- Laufzeit-Bots (Runde 8, #109): joinen mitten im Try wie Nachzuegler
    if iter == math.floor(50 / DT) then
      local n0 = #host.state.players
      local bots0 = #host.bot_pids
      local total = host:add_bots(2)
      ok(total == n0 + 2, "Laufzeit-Bots: +2 Spieler (" .. total .. ")")
      ok(#host.bot_pids == bots0 + 2, "Laufzeit-Bots: pids registriert")
      local seen = {}
      for _, p in ipairs(host.state.players) do
        ok(not seen[p.name], "Laufzeit-Bots: Name eindeutig (" .. p.name .. ")")
        seen[p.name] = true
      end
      local newbie = host.state.players[host.bot_pids[#host.bot_pids]]
      ok(newbie.name:find("^bot") ~= nil, "Laufzeit-Bots: bot-Praefix")
      ok(newbie.ghost and not newbie.alive,
        "Laufzeit-Bots: Spawn als Geist am Friedhof (wie ein echter Join)")
      addbot_pid = host.bot_pids[#host.bot_pids]
      addbot_x = newbie.x
    end
    if iter == math.floor(60 / DT) and addbot_pid then
      local b = host.state.players[addbot_pid]
      ok(b.x ~= addbot_x or b.alive,
        "Laufzeit-Bots: der neue Bot bewegt sich oder lebt schon")
      ok(clients[1].snap and clients[1].snap.players[addbot_pid] ~= nil,
        "Laufzeit-Bots: Bot erreicht die Clients im Snapshot")
      ok(clients[1].names[addbot_pid] ~= nil,
        "Laufzeit-Bots: Roster-Broadcast mit Bot-Namen angekommen")
    end

    -- Geist freilassen (GDD Kap. 11): kein Client wird ohne Klick zum Geist,
    -- bevor der Respawn-Timer durch ist
    for _, c in ipairs(clients) do
      local me = c.snap and c.pid and c.snap.players[c.pid]
      if me and me.ghost then
        ok(c.released_once == true or c.rejoin ~= nil,
          "Freigabe: Geist gibt es erst nach dem Klick")
      end
    end

    -- Rename-Pfad des Intros (GDD 5): Annahme, Kollision, Roster-Broadcast
    if iter == math.floor(70 / DT) then
      clients[1]:send_rename("Erwin")
    end
    if iter == math.floor(73 / DT) then
      clients[4]:send_rename("erwin") -- Kollision (case-insensitiv)
    end
    if iter == math.floor(76 / DT) then
      ok(clients[1].rename_result == true, "Rename: Wunschname angenommen")
      ok(clients[4].rename_result == false, "Rename: Kollision abgelehnt")
      local pid1 = clients[1].pid
      ok(host.state.players[pid1].name == "Erwin",
        "Rename: Host-Zustand aktualisiert")
      ok(clients[3].names[pid1] == "Erwin",
        "Rename: Roster-Broadcast bei allen angekommen")
    end

    -- Fluchbruch (GDD 11): ein Sieg haelt die Welt an, bis REVANCHE
    -- gedrueckt wird — hier drueckt Client 1 ueber das Netz
    if host.state.phase == "won" and not revanche_sent then
      revanche_sent = true
      clients[1]:send_revanche()
    end
    if revanche_sent and not revanche_done and host.state.phase == "try" then
      revanche_done = true
      ok(host.state.try_nr == 1,
        "REVANCHE: Try-Zaehler startet bei 1 (" .. host.state.try_nr .. ")")
    end

    -- Statistik-Tafel (GDD 11): nach dem ersten Try-Ende (90 s) bei allen
    if iter == math.floor(95 / DT) then
      ok(clients[1].stats_board ~= nil, "Statistik-Tafel beim Client angekommen")
      if clients[1].stats_board then
        ok(#clients[1].stats_board.hogger == 8,
          "Statistik-Tafel: acht Hogger-Zeilen")
        -- Bots koennen den ersten Try auch gewinnen: Wipe hat die grosse
        -- Rest-HP-Pointe, ein Sieg nicht (GDD 11)
        ok(clients[1].stats_board.big ~= nil
           or clients[1].stats_board.header:find("SIEG") ~= nil,
          "Statistik-Tafel: Wipe-Pointe oder Siegkopf")
      end
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
      ok(snap.hogger.slow_rest == math.max(0, math.min(255,
           math.ceil((st.hogger.slow_until or 0) - st.time))),
        "Codec: Hogger-Frost-Slow-Restsekunden (Runde 8, #107)")
    end
  end

  -- Wire-Roundtrip HEAL_REQUEST (Runde 7, #103): reines Lua kann
  -- love.data.pack nicht, darum liegt der Codec-Test hier in Stufe 4
  do
    local data = wire.heal_request(7)
    ok(#data == 4, "Wire: HEAL_REQUEST ist 4 Bytes")
    local msg_type, off = wire.read_header(data)
    ok(msg_type == wire.MSG.HEAL_REQUEST, "Wire: HEAL_REQUEST-Header")
    ok(wire.read_heal_request(data, off) == 7, "Wire: Ziel-pid im Roundtrip")
  end

  -- Ergebnis-Pruefungen
  local try_starts, revives, damage_evs = outcome_counts()
  ok(try_starts >= 2, "Voller Try inkl. Try-Uebergang (" .. try_starts .. " Starts)")
  ok(revives >= 4, "Clients beleben sich ueber das Netz wieder (" .. revives .. ")")
  ok(damage_evs > 50, "Kampf laeuft ueber das Netz (" .. damage_evs .. " Treffer)")
  -- nach einer REVANCHE zaehlt der Try-Zaehler regulaer ab 1 (GDD 11)
  ok(revanche_sent or host.state.try_nr >= 1000,
    "Try-Zaehler vierstellig (GDD 6) bzw. REVANCHE-Neustart")
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
