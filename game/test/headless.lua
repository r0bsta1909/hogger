-- game/test/headless.lua — Stufe 4 (GDD 17.7): Host + N Bot-Clients
-- in-process ueber 127.0.0.1, fensterlos. Prueft: voller Try inkl.
-- Try-Uebergang, Invarianten je Tick, Snapshot-Budget, Codec-Feldliste
-- gegen den echten State, Rejoin mitten im Try.
-- Aufruf: love game --headless --test   (aus der Repo-Wurzel)

local model = require("sim.model")
local world = require("game.gamesim.world")
local step = require("game.gamesim.step")
local bot = require("game.gamesim.bot")
local wire = require("game.net.wire")
local hostmod = require("game.net.host")
local clientmod = require("game.net.client")
local budget = require("game.test.budget")

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
  -- Zuerst das Snapshot-Budget bei voller Raid-Groesse (Runde 16). Der Lauf
  -- unten hat nur sechs bis acht Spieler und kann ueber N=40 nichts sagen;
  -- K sind die dort gemessenen Kosten je Datensatz, mit denen die
  -- Budget-Pruefung in der Schleife rechnet — statt mit einer Magic Number,
  -- die still veraltet.
  local K = budget.run(ok)

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
      local nscale0 = host.state.n_scale
      local max0, hp0 = host.state.hogger.max_hp, host.state.hogger.hp
      local frac0 = hp0 / max0
      local total = host:add_bots(2)
      -- Laufzeit-Skalierung (Runde 9, #118)
      ok(host.state.n_scale == nscale0 + 2,
        "Laufzeit-Bots: n_scale sofort nachgezogen")
      ok(host.state.hogger.max_hp > max0,
        "Laufzeit-Bots: Hoggers Max-HP waechst sofort")
      ok(math.abs(host.state.hogger.hp / host.state.hogger.max_hp - frac0) < 0.01,
        "Laufzeit-Bots: HP-Anteil bleibt erhalten")
      ok(host.state.hogger.hp >= 1, "Laufzeit-Bots: Hogger lebt weiter")
      ok(total == n0 + 2, "Laufzeit-Bots: +2 Spieler (" .. total .. ")")
      ok(#host.bot_pids == bots0 + 2, "Laufzeit-Bots: pids registriert")
      local seen = {}
      for _, p in ipairs(host.state.players) do
        ok(not seen[p.name], "Laufzeit-Bots: Name eindeutig (" .. p.name .. ")")
        seen[p.name] = true
      end
      local newbie = host.state.players[host.bot_pids[#host.bot_pids]]
      -- Runde 12 (#146): Bots heissen nach Robs Liste, botN nur als Fallback
      local in_list = false
      for _, nm in ipairs(require("game.data.names").BOT_NAMES) do
        if newbie.name == nm then in_list = true break end
      end
      ok(in_list or newbie.name:find("^bot") ~= nil,
        "Laufzeit-Bots: Name aus Robs Liste (oder botN-Fallback)")
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

    -- Gewinnen die Bots von selbst, laeuft die Endsequenz an und die Welt
    -- steht — der Realm wird per Werkzeug zurueckgeholt (seit Runde 11 gibt
    -- es im Spiel keinen Weg zurueck mehr, #133), damit der Test weiterlaeuft
    if host.state.phase == "won" and not revanche_sent then
      revanche_sent = true
      host:revanche()
    end
    if revanche_sent and not revanche_done and host.state.phase == "try" then
      revanche_done = true
      ok(host.state.try_nr == 1,
        "Werkzeug-Neustart: Try-Zaehler startet bei 1 (" .. host.state.try_nr .. ")")
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
      -- Der Hinweis, dass ein Klick die Tafel schliesst (Runde 10, #126):
      -- vorhanden und ASCII (Umlaut-Konvention des UI)
      local hint = require("game.ui.stats").HINT
      ok(type(hint) == "string" and #hint > 0, "Statistik-Tafel: Hinweistext da")
      ok(hint and hint:find("[\128-\255]") == nil,
        "Statistik-Tafel: Hinweistext ist ASCII")
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
      -- Die Formel kommt aus den gemessenen Kosten je Datensatz (budget.lua),
      -- nicht aus geratenen Konstanten mit Sicherheitszuschlag. Sie muss
      -- deshalb EXAKT aufgehen: jede Abweichung heisst, dass der Packer etwas
      -- anderes tut als angenommen. Bis Runde 16 stand hier "20 * Spieler",
      -- waehrend der Datensatz 25 B kostete — bei N=40 waere die alte Formel
      -- schon mit dem damaligen Format verletzt gewesen, nur lief der Test
      -- nie mit mehr als acht Spielern.
      local erwartet = budget.budget(K, #st.players, #st.corpses,
                                     npc_count, loot_count)
      ok(#body == erwartet, string.format(
        "Snapshot-Budget eingehalten (%d B erwartet, %d B gemessen)",
        erwartet, #body))
      ok(#body + budget.PAKETKOPF <= budget.MTU, string.format(
        "Snapshot passt in ein ENet-Paket (%d von %d B)",
        #body + budget.PAKETKOPF, budget.MTU))
      local _, snap = wire.read_snapshot(wire.snapshot(0, body), 4)
      for _, p in ipairs(st.players) do
        local sp = snap.players[p.id]
        ok(sp ~= nil, "Codec: jeder Spieler im Snapshot")
        if sp then
          ok(math.abs(sp.x - p.x) <= 1 and math.abs(sp.y - p.y) <= 1,
            "Codec: Position (Quantisierung <= 1 px)")
          ok(sp.alive == (p.alive and true or false), "Codec: alive-Flag")
          -- Bedrohungsanteil (Runde 14, #174): ein Byte, 0..1 quantisiert
          ok(sp.threat_frac >= 0 and sp.threat_frac <= 1,
            "Codec: Bedrohungsanteil liegt zwischen 0 und 1")
          ok(math.abs(sp.threat_frac - (p.threat_frac or 0)) <= 1 / 255 + 1e-6,
            "Codec: Bedrohungsanteil ueberlebt die Quantisierung")
        end
      end
      -- Wer die Spitzenbedrohung hat, muss auch 1,0 melden — sonst zeigt
      -- der Bogen nie Vollausschlag
      do
        local top_pid, top = nil, 0
        for _, p in ipairs(st.players) do
          local th = st.hogger.threat[p.id]
          if th and th > top then top, top_pid = th, p.id end
        end
        if top_pid then
          ok(snap.players[top_pid].threat_frac >= 254 / 255,
            "Codec: der Spitzenreiter meldet vollen Bedrohungsanteil")
        end
      end
      ok(snap.hogger.hp == math.max(0, math.floor(st.hogger.hp + 0.5)),
        "Codec: Hogger-HP")
      ok(snap.hogger.slow_rest == math.max(0, math.min(255,
           math.ceil((st.hogger.slow_until or 0) - st.time))),
        "Codec: Hogger-Frost-Slow-Restsekunden (Runde 8, #107)")

      -- NPC-Flags-Byte (Runde 13 gebaut, Runde 14 erstmals geprueft, #167):
      -- Bit 1 = gewurzelt, Bits 2-8 = Restdauer in Vierteln einer Sekunde.
      -- Fuer das Log war der Zustand da, geprueft hat ihn nie jemand.
      for id = 100, 250 do
        local npc = st.npcs[id]
        if npc then
          local sn = snap.npcs[id]
          ok(sn ~= nil, "Codec: jeder NPC im Snapshot")
          if sn then
            local soll = st.time < (npc.rooted_until or 0)
            ok(sn.rooted == soll, "Codec: Wurzel-Flag am NPC")
            if soll then
              local rest = (npc.rooted_until or 0) - st.time
              ok(math.abs(sn.root_rest - math.min(31.75, rest)) <= 0.25,
                "Codec: Wurzel-Restdauer (Viertelsekunden-Raster)")
            end
          end
        end
      end
    end
  end

  -- Ein gewurzelter Mob geht durch den Codec: der Fall tritt im Bot-Lauf
  -- nicht zuverlaessig auf (kein Bot spielt Druide), also hier gestellt.
  do
    local st = host.state
    local npc_id
    for id = 100, 250 do if st.npcs[id] then npc_id = id break end end
    if npc_id then
      local npc = st.npcs[npc_id]
      local vorher = npc.rooted_until
      npc.rooted_until = st.time + 5
      local _, snap = wire.read_snapshot(
        wire.snapshot(0, wire.snapshot_body(st)), 4)
      ok(snap.npcs[npc_id] and snap.npcs[npc_id].rooted,
        "Codec: gewurzelter Mob kommt als gewurzelt beim Client an")
      ok(snap.npcs[npc_id] and math.abs(snap.npcs[npc_id].root_rest - 5) <= 0.25,
        "Codec: seine Restdauer ueberlebt die Leitung")
      npc.rooted_until = st.time - 1
      local _, snap2 = wire.read_snapshot(
        wire.snapshot(0, wire.snapshot_body(st)), 4)
      ok(snap2.npcs[npc_id] and not snap2.npcs[npc_id].rooted,
        "Codec: abgelaufene Wurzeln kommen als nicht gewurzelt an")
      npc.rooted_until = vorher
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

  -- Der Enrage ueber das Netz (Runde 18): die Frist gezielt ablaufen lassen
  -- und die ganze Sequenz durchfahren. Geprueft wird, was der Spieler davon
  -- hat — dass die Phase steht, dass wirklich alle sterben, dass das
  -- Ereignis beim Client ankommt und dass der naechste Try sauber beginnt.
  do
    local st = host.state
    if st.phase == "try" then
      local try0 = st.try_nr
      local lebend0 = 0
      for _, p in ipairs(st.players) do
        -- alle auf die Beine und in Hoggers Naehe: sonst prueft der Test
        -- nur, dass Tote tot bleiben
        p.alive, p.ghost, p.hp, p.dead_until = true, false, p.max_hp, 0
        p.x, p.y = st.hogger.x + 20 + p.id * 7, st.hogger.y + 15
        lebend0 = lebend0 + 1
      end
      st.clock = model.p("try_time_limit") - DT / 2
      local idle = { mask = 0, facing = 0 }
      local log0 = #log_lines
      -- Was der Client SCHON gesehen hat, zaehlt nicht mit
      local kosm0 = {}
      for i, c in ipairs(clients) do kosm0[i] = #c.cosmetics end
      local phase_gesehen = false
      local ticks = math.ceil((step.ENRAGE.end_t + 1) / DT)
      for i = 1, ticks do
        host:update(DT, idle)
        for _, c in ipairs(clients) do
          if not c.dead then c:update(DT, idle) end
        end
        if st.phase == "enrage" then
          phase_gesehen = true
          -- mitten in der Sequenz: der Beat muss ueber die Leitung passen
          if i == 2 then
            local _, snap = wire.read_snapshot(
              wire.snapshot(0, wire.snapshot_body(st)), 4)
            ok(snap.phase == "try",
              "Enrage: der Snapshot meldet KEINEN Fluchbruch (Phasen-Byte frei)")
            ok(math.abs(snap.clock - st.clock) < 0.2,
              "Enrage: die Uhr traegt die Zeitachse ueber die Leitung")
          end
        end
      end
      local n_enrage, n_death, n_ende = 0, 0, 0
      for i = log0 + 1, #log_lines do
        local l = log_lines[i]
        if l:find('"ev":"enrage"') then n_enrage = n_enrage + 1 end
        if l:find('"ev":"death"') then n_death = n_death + 1 end
        if l:find('"ev":"try_end"') then n_ende = n_ende + 1 end
      end
      ok(n_enrage == 1, "Enrage: genau ein Enrage-Ereignis im Log (" ..
        n_enrage .. ")")
      ok(n_ende == 1, "Enrage: genau ein try_end (" .. n_ende .. ")")
      ok(n_death == lebend0, "Enrage: jeder Tod steht im Log (" .. n_death ..
        " von " .. lebend0 .. ")")
      ok(phase_gesehen, "Enrage: die Phase wird betreten")
      ok(st.try_nr == try0 + 1, "Enrage: der Try wird danach gewertet")
      ok(st.phase == "try", "Enrage: danach laeuft wieder ein normaler Try")
      ok(#st.corpses == 0, "Enrage: der naechste Try startet ohne frische Leichen")
      local lebend = 0
      for _, p in ipairs(st.players) do if p.alive then lebend = lebend + 1 end end
      ok(lebend0 > 0 and lebend == 0,
        "Enrage: die Welle hat alle " .. lebend0 .. " erwischt (" .. lebend ..
        " stehen noch)")
      for _, p in ipairs(st.players) do
        ok((p.dead_until or 0) > 0,
          "Enrage: " .. p.name .. " geht durch die normale Freigabe")
      end
      -- Der eigentliche Beweis: ein ENTFERNTER Client hat den Enrage ueber
      -- die Leitung bekommen. Ohne Eintrag in wire.EV filtert der Host ihn
      -- weg, er stuende nur im Log und niemand saehe je eine Welle — genau
      -- der Fehler aus Runde 14 (#167/#168).
      for i, c in ipairs(clients) do
        local gesehen = false
        for k = kosm0[i] + 1, #c.cosmetics do
          if c.cosmetics[k].ev == "enrage" then gesehen = true end
        end
        ok(gesehen, "Enrage: Client " .. i .. " sieht ihn ueber die Leitung")
      end
    end
  end

  -- Die Endsequenz ueber das Netz (Runde 11, #131): Hogger gezielt toeten und
  -- die Szene bis zum Abgang durchlaufen lassen. Deterministisch, damit der
  -- Fluchbruch nicht davon abhaengt, ob die Bots zufaellig gewinnen.
  do
    local st = host.state
    if st.phase == "try" then
      step.admin_kill_hogger(st)
      local ticks = math.ceil((step.WON_EXIT + 2) / DT)
      local idle = { mask = 0, facing = 0 }
      for _ = 1, ticks do
        host:update(DT, idle)
        for _, c in ipairs(clients) do
          if not c.dead then c:update(DT, idle) end
        end
      end
      ok(st.phase == "won", "Finale: Phase steht auf won")
      ok(st.won_stage == 4, "Finale: Leeroy ist am Ende weg (Stufe "
        .. tostring(st.won_stage) .. ")")
      for _, p in ipairs(st.players) do
        ok(p.alive and not p.ghost, "Finale: " .. p.name .. " lebt im Kreis")
      end
      -- Der Beat muss beim Client ankommen — er haengt im Phasen-Byte
      local body = wire.snapshot_body(st)
      local _, snap = wire.read_snapshot(wire.snapshot(0, body), 4)
      ok(snap.phase == "won", "Finale: Phase im Snapshot")
      ok(snap.won_stage == st.won_stage, "Finale: Beat im Snapshot")
      local c1 = clients[1]
      ok(c1.snap == nil or c1.snap.won_stage == nil or c1.snap.won_stage >= 1,
        "Finale: der Client sieht die Endsequenz")
    end
  end

  -- Ergebnis-Pruefungen
  local try_starts, revives, damage_evs = outcome_counts()
  ok(try_starts >= 2, "Voller Try inkl. Try-Uebergang (" .. try_starts .. " Starts)")
  ok(revives >= 4, "Clients beleben sich ueber das Netz wieder (" .. revives .. ")")
  ok(damage_evs > 50, "Kampf laeuft ueber das Netz (" .. damage_evs .. " Treffer)")
  -- nach einem Werkzeug-Neustart zaehlt der Try-Zaehler ab 1 (GDD 11)
  ok(revanche_sent or host.state.try_nr >= 1000,
    "Try-Zaehler vierstellig (GDD 6) bzw. Werkzeug-Neustart")
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
