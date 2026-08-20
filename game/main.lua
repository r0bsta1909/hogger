-- game/main.lua — LOEVE-Einstieg: Discovery-Wahl, Verdrahtung von Sim, Netz
-- und Darstellung. Der erste Spieler, der startet, IST der Realm (GDD Kap. 3):
--   love game                  -> Discovery: joinen oder selbst Host werden
--   love game --join <ip>      -> manuelle IP (Pflichtfeature, Skill Par. 5)
--   love game --host           -> Host erzwingen
--   love game --headless --test-> Stufe-4-Integrationstest
-- Debug: --bots K, --auto, --shot N, --panel, --seed N, --name X; F12-Overlay.

do
  local src = love.filesystem.getSource()
  package.path = src .. "/../?.lua;" .. src .. "/?.lua;" .. package.path
end

local socket = require("socket")
local model = require("sim.model")
local input = require("game.gamesim.input")
local world = require("game.gamesim.world")
local audio = require("game.audio")
local gamemenu = require("game.ui.gamemenu")
local wire, discovery

local app = {
  mode = "discover", name = "spieler", join_ip = nil, seed = nil,
  bots = 0, headless = false, test = false,
  net = nil, search = nil, beacon = nil,
  render = nil, panel = nil, floating = nil, debug = nil,
  boot = nil, dialog = nil, auto_hosted = false, uptime = 0,
  cooldown_view = { 0, 0, 0, 0 }, cooldown_max = { 1, 1, 1, 1 }, -- Slot 4: Tritt (#140)
  discover_t = 0,
}

local function parse_args(args)
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--join" then i = i + 1; app.join_ip = args[i]; app.mode = "client"
    elseif a == "--host" then app.mode = "host"
    elseif a == "--name" then i = i + 1; app.name = args[i]; app.name_given = true
    elseif a == "--seed" then i = i + 1; app.seed = tonumber(args[i])
    elseif a == "--bots" then i = i + 1; app.bots = tonumber(args[i]) or 0; app.mode = "host"
    elseif a == "--headless" then app.headless = true
    elseif a == "--test" then app.test = true
    elseif a == "--drawtest" then app.drawtest = true
    elseif a == "--stress" then app.stress = true
    elseif a == "--shot" then i = i + 1; app.shot_at = tonumber(args[i]) or 3
    elseif a == "--auto" then app.auto = true
    elseif a == "--panel" then app.open_panel = true
    elseif a == "--dock" then app.dock = true -- HUD-Andock-Vorschau (M12)
    end
    i = i + 1
  end
end

local function start_search()
  app.mode = "discover"
  app.discover_t = 0
  if app.search then app.search:close() end
  app.search = discovery.new_search()
end

local function start_host()
  app.mode = "host"
  if app.search then app.search:close(); app.search = nil end
  local hostmod = require("game.net.host")
  love.filesystem.createDirectory("logs")
  local logname = "logs/session-" .. os.date("%Y%m%d-%H%M%S") .. ".jsonl"
  app.net = hostmod.new({
    name = app.name,
    seed = app.seed or os.time(),
    bots = app.bots,
    -- Debug-Laeufe (--auto/--name) und der Rejoin am selben Abend
    -- ueberspringen die Quest (GDD Kap. 5, Punkt 4)
    skip_quest = app.auto or app.name_given or app.rejoin_known or false,
    log = function(line)
      love.filesystem.append(logname, line .. "\n")
    end,
  })
  -- Bake laeuft waehrend des Matches weiter (Skill Par. 5)
  local lobby_id = string.format("%s-%d", app.name, os.time() % 100000)
  app.beacon = discovery.new_host(lobby_id, socket.gettime(), hostmod.PORT)
  app.panel = require("game.ui.panel").new(function(key, value)
    return app.net:set_param(key, value)
  end)
  if app.open_panel then app.panel.visible = true end
end

local function start_client(ip)
  app.mode = "client"
  if app.search then app.search:close(); app.search = nil end
  if app.beacon then app.beacon:close(); app.beacon = nil end
  local clientmod = require("game.net.client")
  app.net = clientmod.new(ip, app.name)
  app.panel = nil
end

-- Admin (GDD 4.4, Issue #36): das Onboarding noch einmal ansehen, ohne das
-- Spiel zu verlassen. Der gemerkte Charaktername faellt weg, Boot-Sequenz
-- und Leeroy-Intro laufen erneut; die Verbindung bleibt bestehen.
local function replay_intro()
  love.filesystem.remove("charname.dat")
  app.name = "gast" .. tostring(math.floor(socket.gettime() * 1000) % 10000)
  app.name_given = false
  app.rejoin_known, app.rejoin_greeted = nil, nil
  app.quest = nil
  if app.mode == "host" and app.net and app.net.reset_quest then
    app.net:reset_quest() -- das Echo kommt noch einmal
  end
  app.stats, app.victory = nil, nil
  app.boot = require("game.ui.boot").new()
  app.debug.visible = false
  app.debug.note = "Intro laeuft noch einmal."
end

local function teardown_net()
  if app.net and app.net.destroy then app.net:destroy() end
  app.net = nil
  if app.beacon then app.beacon:close(); app.beacon = nil end
  app.view = nil
end

-- Admin (Issue #36): kompletter Neustart — frischer Realm mit Try 1,
-- Boot-Sequenz, Intro und wieder wartendem Leeroy. Der alte Realm endet
-- dabei; verbundene Gaeste laufen ueber den Disconnect-Dialog automatisch
-- wieder herein (GDD Kap. 3).
local function restart_realm()
  teardown_net()
  if app.search then app.search:close(); app.search = nil end
  require("game.session").wipe() -- Try-Zaehler und Charaktere zuruecksetzen
  replay_intro()
  start_host()
  app.auto_hosted = true
  app.debug.note = "Realm neu gestartet."
end

function love.load(args)
  parse_args(args or {})
  if app.headless and app.test then
    local exit = require("game.test.headless").run()
    love.event.quit(exit)
    return
  end
  if app.headless and app.stress then
    local exit = require("game.test.stress").run()
    love.event.quit(exit)
    return
  end
  -- Zeichentest (Stufe 4b, Runde 15 #187): braucht das Grafikmodul, aber
  -- weder Netz noch Welt — er baut sich seine Sichten selbst. love.draw
  -- fuehrt ihn im ersten Frame aus und beendet das Programm.
  if app.drawtest then
    require("game.audio").load()
    return
  end
  wire = require("game.net.wire")
  discovery = require("game.net.discovery")
  app.render = require("game.render").new()
  -- HUD am Ring ist seit M13 STANDARD (Rob-Freigabe der M12-Vorschau);
  -- F12 [D] ist der Debug-Rueckweg in die Ecken-Variante
  app.render.docked = true
  app.floating = require("game.ui.floating").new()
  app.debug = require("game.ui.debug").new()
  audio.load()
  -- Fenster- und Taskleisten-Icon (Issue #37); dieselbe Datei wird in der
  -- Release-Pipeline zu .ico und .icns
  if love.window and love.window.setIcon then
    local data = require("game.assets").image_data("icon_app")
    if data then pcall(love.window.setIcon, data) end
  end
  -- Sieg-Reset (Runde 8, #110): endete die letzte Session siegreich (und
  -- ohne REVANCHE), ist dieser Start ein Erststart — voller Boot samt
  -- Warteschlangen-Gag, neuer Name, volle Quest, frischer Try-Zaehler.
  -- MUSS vor boot.new() laufen: das schreibt sofort boot_seen.dat.
  if love.filesystem.getInfo("sieg.dat") then
    love.filesystem.remove("sieg.dat")
    love.filesystem.remove("charname.dat")
    love.filesystem.remove("boot_seen.dat")
    love.filesystem.remove("boot_queue.dat")
    require("game.session").wipe()
  end

  -- Boot-Sequenz (GDD Kap. 3) im Normalstart; Debug-Laeufe starten direkt
  if not app.auto then
    app.boot = require("game.ui.boot").new()
  end

  -- Name & Intro (GDD Kap. 5): ohne --name laeuft das Intro; der bestaetigte
  -- Name haengt pro Abend am Rechner (charname.dat) -> Rejoin ohne Intro
  if not app.name_given then
    local saved = love.filesystem.read("charname.dat")
    local today = os.date("%Y-%m-%d")
    local d, n = (saved or ""):match("^(%S+)\n(%a+)")
    if d == today and n then
      app.name = n
      app.rejoin_known = true
    else
      app.name = "gast" .. tostring(math.floor(socket.gettime() * 1000) % 10000)
      app.fresh_char = true -- neuer Charakter: das Echo bringt die Quest
    end
  end

  if app.mode == "host" then start_host()
  elseif app.mode == "client" then start_client(app.join_ip)
  else start_search() end
end

local function local_input_frame()
  local mask = 0
  local kb = love.keyboard
  if kb.isDown("a", "left") then mask = mask + input.LEFT end
  if kb.isDown("d", "right") then mask = mask + input.RIGHT end
  if kb.isDown("w", "up") then mask = mask + input.UP end
  if kb.isDown("s", "down") then mask = mask + input.DOWN end
  if kb.isDown("space") then mask = mask + input.JUMP end
  if kb.isDown("1") then mask = mask + input.AB1 end
  if kb.isDown("2") then mask = mask + input.AB2 end
  if kb.isDown("3") then mask = mask + input.AB3 end
  -- Klick auf einen Faehigkeitsbutton (Runde 14, #172): genau EIN Tick mit
  -- gesetztem Bit, denn der Host wertet Flanken. Danach ist der Riegel weg.
  local click = app.click_ab
  if click then
    app.click_ab = nil
    local bit = (click == 1 and input.AB1)
             or (click == 2 and input.AB2)
             or (click == 3 and input.AB3)
    if bit and mask % (bit * 2) < bit then mask = mask + bit end
  end
  local w, h = love.graphics.getDimensions()
  local mx, my = love.mouse.getPosition()
  local angle = math.atan2(my - h / 2, mx - w / 2) + math.pi / 2
  local facing = input.facing_from_angle(angle)
  return { mask = mask, facing = facing }, angle
end

-- Sicht fuer den Renderer: Host dekodiert seinen eigenen Snapshot durch
-- denselben Codec wie die Clients — ein Lesepfad, staendig geprueft
local function build_view()
  if app.mode == "host" and app.net then
    local body = wire.snapshot_body(app.net.state)
    local _, snap = wire.read_snapshot(wire.snapshot(0, body), 4)
    snap.me = app.net.local_pid
    local me = snap.players[snap.me]
    snap.me_x, snap.me_y = me.x, me.y
    snap.names = {}
    for _, p in ipairs(app.net.state.players) do snap.names[p.id] = p.name end
    return snap
  end
  if app.mode ~= "client" or not app.net then return nil end
  local snap = app.net.snap
  if not snap or not app.net.pid then return nil end
  snap.me = app.net.pid
  local me = snap.players[snap.me]
  if app.net.predicted then
    snap.me_x, snap.me_y = app.net.predicted.x, app.net.predicted.y
  elseif me then
    snap.me_x, snap.me_y = me.x, me.y
  end
  snap.names = app.net.names
  return snap
end

local function process_cosmetics(view)
  local list = app.net and app.net.cosmetics or nil
  if not list then return end
  if not view then
    for i = #list, 1, -1 do list[i] = nil end
    return
  end
  local function entity_pos(idnum)
    local n = tonumber(idnum)
    if n and view.players[n] then return view.players[n].x, view.players[n].y end
    if n and view.npcs and view.npcs[n] then return view.npcs[n].x, view.npcs[n].y end
    return view.hogger.x, view.hogger.y
  end
  for _, e in ipairs(list) do
    if e.ev == "damage" then
      local tx, ty = entity_pos(e.dst)
      local sx, sy = entity_pos(e.src)
      local incoming = tonumber(e.dst) == view.me
      local outgoing = tonumber(e.src) == view.me
      -- Schadensrichtung ist ablesbar (GDD 4.1, Issue #31): eigener Schaden
      -- weiss, erlittener rot, fremder gedaempft; Krits gold bzw. glutrot
      local color, prio
      if e.crit then
        color = incoming and { 1, 0.45, 0.15 } or { 1, 0.85, 0.2 }
        prio = (incoming or outgoing) and 3 or 2
      elseif incoming then
        color, prio = { 1, 0.35, 0.30 }, 2
      elseif outgoing then
        color, prio = { 1, 1, 1 }, 2
      else
        color, prio = { 0.72, 0.72, 0.66 }, 1
      end
      app.floating:add(tostring(math.floor((e.val or 0) + 0.5))
        .. (e.crit and "!" or ""), tx, ty, color, prio)
      -- Geschoss/Schlag zwischen Quelle und Ziel (Issue #30)
      local src_p = view.players[tonumber(e.src)]
      app.render:add_attack_fx(src_p and src_p.class,
        src_p and src_p.class and model.classes[src_p.class].attack or nil,
        e.art, sx, sy, tx, ty)
      if incoming then app.render:add_hurt_flash(e.crit and 1.0 or 0.45) end
      -- Krit-Inszenierung (GDD 11): gross und gelb, Screenshake beide Seiten
      if e.crit and incoming then app.render:add_shake(12)
      elseif e.crit and outgoing then app.render:add_shake(6) end
      -- Treffer-Sounds (GDD 12 Nr. 5-7, 9, 11), gedrosselt + Distanz
      local vol = audio.falloff(world.dist(tx, ty, view.me_x, view.me_y))
      if e.crit then
        audio.play("snd_crit", math.max(0.6, vol)) -- Krit-Punch, beide Seiten
      elseif vol > 0.05 and app.uptime - (app.last_hit_snd or 0) > 0.08 then
        app.last_hit_snd = app.uptime
        local src_id = tonumber(e.src)
        local src_npc = view.npcs and view.npcs[src_id]
        local id = "snd_melee_hit"
        if src_p and src_p.class then
          -- Zauber klingen nach ihrer Schule (Schadensart aus dem Ereignis,
          -- GDD 17.3); Autoangriffe: Autoschuss oder Nahkampf — den
          -- Zauberstab gibt es seit Runde 5 nicht mehr (Issue #86)
          if e.art == "ability" then
            id = ({ mage = "snd_impact_fire", warlock = "snd_impact_shadow",
                    priest = "snd_impact_holy", druid = "snd_impact_fire" })
                 [src_p.class] or "snd_melee_hit"
          elseif model.classes[src_p.class].attack == "shot" then
            id = "snd_shot"
          end
        elseif src_npc and (src_npc.kind == "wolf" or src_npc.kind == "murloc") then
          -- Mob-Aggro-Naeherung: erster Biss bringt den Schrei (Nr. 11)
          local st = app.sndstate
          if st and app.uptime - (st.growl[src_id] or -10) > 8 then
            st.growl[src_id] = app.uptime
            audio.play(src_npc.kind == "wolf" and "snd_wolf_growl" or "snd_murloc",
              math.max(0.4, vol))
          end
        end
        audio.play(id, vol)
      end
    elseif e.ev == "heal" then
      local tx, ty = entity_pos(e.dst)
      app.floating:add("+" .. tostring(math.floor((e.val or 0) + 0.5)),
        tx, ty, { 0.3, 0.95, 0.3 }, tonumber(e.dst) == view.me and 2 or 1)
      app.render:add_heal_fx(tx, ty)
      if tonumber(e.dst) == view.me then app.last_healed_t = app.uptime end
    elseif e.ev == "death" then
      local dp = view.players[tonumber(e.src)]
      if dp then -- Todeslaut (GDD 12 Nr. 12)
        audio.play("snd_player_death",
          audio.falloff(world.dist(dp.x, dp.y, view.me_x, view.me_y)))
      end
      if tonumber(e.src) == view.me then
        -- Killcam-Zeile (GDD 11): kontextsensitiv, deterministische Rotation
        app.my_deaths = (app.my_deaths or 0) + 1
        local healed = app.last_healed_t ~= nil
                       and (app.uptime - app.last_healed_t) < 4
        app.render:show_killcam(require("game.gamesim.killcam").pick(
          tonumber(e.val), e.crit, app.my_deaths, healed))
      end
    elseif e.ev == "crit_kill" and tonumber(e.dst) == view.me then
      app.render:add_shake(18) -- der "WAS?!"-Moment (GDD 9.2)
    elseif e.ev == "charge" then
      audio.play("snd_hogger_charge") -- Boss-Lesbarkeit (GDD 12 Nr. 10)
    elseif e.ev == "eat_start" then
      app.render:announce("HOGGER FRISST!", 2.5)
    elseif e.ev == "eat_interrupt" then
      -- der Tritt hat gesessen (Runde 12, #140): kurzes, lautes Feedback
      app.render:announce("UNTERBROCHEN!", 2)
    elseif e.ev == "taunt" then
      local tx, ty = entity_pos(e.dst)
      app.floating:add("Spott!", tx, ty, { 1, 0.75, 0.3 }, 2)
    elseif e.ev == "root" then
      -- Gnarlwurzeln (Runde 14, #167): der Druide muss SEHEN, dass sie
      -- sassen — vorher gab es dafuer kein einziges Signal
      local tx, ty = entity_pos(e.dst)
      app.floating:add("Verwurzelt!", tx, ty, { 0.45, 0.9, 0.35 }, 2)
      audio.play("snd_impact_frost")
    elseif e.ev == "feign" then
      -- Totstellen (Runde 14, #168): der Jaeger sieht jetzt, dass er liegt
      local tx, ty = entity_pos(e.src)
      app.floating:add("Totgestellt!", tx, ty, { 0.75, 0.75, 0.7 }, 2)
    elseif e.ev == "shield" then
      -- Machtwort: Schild (Runde 13, #156) — das Ereignis kam nie an
      local tx, ty = entity_pos(e.src)
      app.floating:add("Schild!", tx, ty, { 0.8, 0.85, 1 }, 2)
    elseif e.ev == "eat_complete" then
      app.render:announce("Hogger hat gefressen ...", 2.5)
    elseif e.ev == "try_end" then
      if (e.val or 0) >= 1 then
        app.render:announce("HOGGER IST TOT!", 8)
        audio.play("snd_hogger_death")           -- GDD 12 Nr. 10
        audio.play_later(1.2, "snd_fanfare")     -- Nr. 15: Sieg-Fanfare
      else
        app.render:announce("Wipe. Naechster Try.", 4)
        audio.play("snd_wipe_sting")             -- Nr. 15: kurz, Moll
      end
    elseif e.ev == "try_start" then
      app.render:announce("Try " .. tostring(e.dst or ""), 2.5)
    elseif e.ev == "loot_pickup" and tonumber(e.src) == view.me then
      local pool = require("game.gamesim.loot")
      local item = pool[tonumber(e.dst) or 0] or "Plunder"
      app.render:toast(item .. "  (+" .. tostring(math.floor(e.val or 0)) .. " Kupfer)")
      audio.play("snd_loot") -- Muenzklimpern (GDD 12 Nr. 14)
    elseif e.ev == "ding" then
      -- DING-Inszenierung (GDD 7.3): goldener Ring + Ansage; Leeroys
      -- Kommentar (Zeile 29) folgt als eigenes leeroy_line-Event
      app.render:announce("DING!", 6)
      audio.play("snd_ding") -- Original-Levelup-Moment (GDD 7.3 / 12 Nr. 13)
      local dp = view.players[tonumber(e.src)]
      if dp then app.render:add_ding(dp.x, dp.y) end
    elseif e.ev == "leeroy_line" then
      -- Zeilen gehoeren dem ECHO (GDD 10.1): es sieht zu und kommentiert.
      -- Einzige Ausnahme ist DER Schrei — der gehoert dem Raid-Leeroy,
      -- der gerade losrennt (GDD 10.2, Issue #52)
      local lines = require("game.gamesim.lines")
      local lid = tonumber(e.dst) or 0
      local text = lines[lid]
      if text then
        if lid == 1 then
          -- DER Schrei gehoert der Figur, nicht dem Banner (Runde 12, #144):
          -- Sprechblase am rennenden Leeroy — die Raidansagen gehoeren
          -- ausschliesslich dem Echo
          app.render:bubble(text, 3, "leeroy")
        else
          app.render:announce("Echo: " .. text, 4)
          -- Der letzte Monolog haengt zusaetzlich als Sprechblase an der
          -- verschmolzenen Figur (Endsequenz, GDD 11 / #132). 3,5 s statt der
          -- 3 s Zeilenabstand: die letzte Blase steht damit bis zum Abgang und
          -- wird von ihm abgeschnitten, statt vorher still zu verpuffen.
          if lid >= 31 then app.render:bubble(text, 3.5) end
        end
      end
      if lid == 1 then
        audio.play("snd_leeroy_scream") -- kartenweit: DAS Startsignal (Nr. 16)
      end
    end
  end
  for i = #list, 1, -1 do list[i] = nil end
end

function love.update(dt)
  if app.headless or app.drawtest then return end

  app.uptime = app.uptime + dt
  if app.boot and app.boot:active() then
    app.boot:update(dt)
    -- IP-Fallback als getarnte Konsole nach 5 s ohne gefundenen Realm
    -- (GDD Kap. 3: verwaltete Switches blockieren gelegentlich Broadcasts)
    app.boot.ip_visible = app.auto_hosted and app.uptime > 5
  end

  if app.mode == "disconnected" then return end -- wartet auf den OK-Klick

  if app.mode == "discover" then
    app.search:update(dt)
    app.discover_t = app.discover_t + dt
    local best = app.search:best()
    if best and app.discover_t > 0.5 then
      start_client(best.ip)
      app.auto_hosted = false
    elseif app.discover_t > 3 then
      -- kein Realm gefunden: diese Instanz IST der Realm (GDD Kap. 3)
      start_host()
      app.auto_hosted = true
    end
    return
  end

  local inp, angle = local_input_frame()
  app.facing_angle = angle
  if app.auto and app.mode == "host" then
    inp = require("game.gamesim.bot").decide(app.net.state, app.net.local_pid)
  end
  if (app.panel and app.panel.visible) or app.debug.visible
     or (app.boot and app.boot:active() and app.boot:covers_screen())
     or (app.quest and app.quest:blocking()) then
    inp = { mask = 0, facing = inp.facing }
  end

  app.net:update(dt, inp)

  if app.mode == "host" and app.beacon then
    app.beacon:update(dt)
    if app.beacon.degrade_to then
      -- juengerer Host degradiert sich zum Client (GDD Kap. 3)
      local ip = app.beacon.degrade_to.ip
      teardown_net()
      start_client(ip)
      return
    end
  end
  if app.net and app.net.failed then
    -- authentischer WoW-Disconnect-Dialog, danach Glitch-Schwarz und
    -- automatischer Reconnect (GDD Kap. 3). Auch der Host landet hier, wenn
    -- sein Socket dauerhaft Fehler liefert (Issue #23) — nie ein Absturz.
    app.debug.note = app.net.net_error
      and ("Netz: " .. tostring(app.net.net_error):sub(1, 70)) or app.debug.note
    local msg = app.net.failed
    teardown_net()
    app.dialog = require("game.ui.dialog").new(msg, { quit = app.won_seen })
    app.mode = "disconnected"
    return
  end

  for i = 1, 4 do
    if app.cooldown_view[i] > 0 then
      app.cooldown_view[i] = math.max(0, app.cooldown_view[i] - dt)
    end
  end

  local view = build_view()
  process_cosmetics(view)
  app.view = view

  -- Endet ein Cast, faellt die lokale Cooldown-Anzeige des Slots (Runde 10,
  -- #125). Der lokale Timer ist nur eine Schaetzung der GCD; nach einem
  -- Abbruch hat der Host sie genullt und der naechste Versuch ist sofort
  -- erlaubt — die Schaetzung haette ihn mit "Das ist noch nicht bereit."
  -- blockiert (bei der Klick-Heilung sogar wirklich: die Anfrage ging gar
  -- nicht erst raus). Auch bei regulaerer Vollendung richtig, weil jede
  -- Castzeit laenger ist als die GCD (Test in tests/unit_gamesim.lua).
  local me_now = view and view.players[view.me]
  local casting_now = (me_now ~= nil and me_now.casting) or false
  if casting_now then
    app.casting_slot = me_now.cast_slot
  elseif app.was_casting and app.casting_slot and app.casting_slot > 0 then
    app.cooldown_view[app.casting_slot] = 0
  end
  app.was_casting = casting_now
  app.floating:update(dt)
  app.render:update(dt)

  -- ====== Sound aus dem Weltzustand (GDD Kap. 12) ======
  audio.update(dt)
  if view then
    local st = app.sndstate
    if not st then
      st = { jump = {}, imps = {}, growl = {}, hogger_state = nil,
             stealth = nil, shout = false, frost = false, eating = false }
      app.sndstate = st
    end
    local function dist_vol(x, y)
      return audio.falloff(world.dist(x, y, view.me_x, view.me_y))
    end
    local me = view.players[view.me]
    audio.set_ghost(me ~= nil and not me.alive) -- Tiefpass-Naeherung (Nr. 3)
    -- Grundteppich: Elwynn-Tag lebend, Geister-Wind ERST als Geist (Nr. 2/3).
    -- Wer tot daliegt und auf die Freigabe wartet, hoert die gedaempfte
    -- Welt — der Wind gehoert zum Friedhof (GDD Kap. 11, Issue #55)
    if me and me.alive then
      audio.loop_start("snd_ambience_elwynn")
      audio.loop_stop("snd_ghost_wind")
    elseif me and me.ghost then
      audio.loop_start("snd_ghost_wind")
      audio.loop_stop("snd_ambience_elwynn")
    else
      audio.loop_stop("snd_ghost_wind")
      audio.loop_stop("snd_ambience_elwynn")
    end
    -- Schritte nur lebend — Geister sind lautlos (Nr. 4)
    if me and me.alive and inp.mask % 16 > 0 then
      audio.loop_start("snd_footsteps")
    else
      audio.loop_stop("snd_footsteps")
    end
    -- Zauber-Cast-Loop (Nr. 6)
    if me and me.casting then
      audio.loop_start("snd_cast_loop")
    else
      audio.loop_stop("snd_cast_loop")
    end
    -- eigener Sprung + Landung (Nr. 12b)
    local jumping = input.has(inp.mask, input.JUMP)
    if jumping and not st.me_jump then
      audio.play("snd_jump")
      audio.play_later(0.35, "snd_land")
    end
    st.me_jump = jumping
    -- Spruenge der anderen (Jump-Flag im Snapshot, GDD 4.1)
    for pid, p in pairs(view.players) do
      if pid ~= view.me then
        if p.jumping and not st.jump[pid] then
          local v = dist_vol(p.x, p.y)
          if v > 0.05 then
            audio.play("snd_jump", v * 0.6)
            audio.play_later(0.35, "snd_land", v * 0.6)
          end
        end
        st.jump[pid] = p.jumping
      end
    end
    -- Klassen-Signaturen am eigenen Zustand (Nr. 8 + Frost-Buff Nr. 6)
    if me then
      if st.stealth ~= nil and me.stealth ~= st.stealth then
        audio.play("snd_stealth")
      end
      st.stealth = me.stealth
      if me.shout and not st.shout then audio.play("snd_shout") end
      st.shout = me.shout
      if me.frost_armor and not st.frost then audio.play("snd_impact_frost") end
      st.frost = me.frost_armor
    end
    -- Hogger-Lesbarkeit (Nr. 10): Growl bei Aggro, Schmatzen kartenweit
    local hs = view.hogger.state
    if hs == "combat" and st.hogger_state == "idle" then
      audio.play("snd_hogger_growl")
    end
    st.hogger_state = hs
    local eating = view.hogger.eat ~= nil
    if eating and not st.eating then
      audio.loop_start("snd_hogger_schmatzen") -- IST die Fress-Telegraphie
    elseif not eating and st.eating then
      audio.loop_stop("snd_hogger_schmatzen")
    end
    st.eating = eating
    -- Wichtel-Beschwoerung: neues Imp-Icon (Nr. 8)
    for nid, npc in pairs(view.npcs or {}) do
      if npc.kind == "imp" and not st.imps[nid] then
        st.imps[nid] = true
        audio.play("snd_imp_summon", dist_vol(npc.x, npc.y))
      end
    end
    for nid in pairs(st.imps) do
      if not (view.npcs and view.npcs[nid] and view.npcs[nid].kind == "imp") then
        st.imps[nid] = nil
      end
    end
  end

  -- Statistik-Tafel am Try-Ende (GDD 11): Host baut, alle zeigen;
  -- ein SIEG startet stattdessen die Fluchbruch-Sequenz
  if app.net and app.net.stats_board then
    local board = app.net.stats_board
    app.net.stats_board = nil
    if board.header:find("^SIEG") then
      app.victory = require("game.ui.victory").new(board)
      app.stats = nil
      -- Die Tafel kommt erst ganz am Ende, nach Leeroys Abgang (#132)
      app.end_board = board
      -- Sieg-Marker (Runde 8, #110): endet der Abend siegreich, ist der
      -- naechste Start ein Erststart (Auswertung in love.load).
      love.filesystem.write("sieg.dat", "1")
    else
      app.stats = require("game.ui.stats").new(board)
    end
  end
  if app.stats then
    app.stats:update(dt)
    if not app.stats.visible then app.stats = nil end
  end
  -- Key-Repeat (Issue #81) + Hover-Uhr fuer die Parameter-Erklaerung (#119)
  if app.panel then app.panel:update(dt, love.mouse.getPosition()) end
  if app.victory then
    app.victory:update(dt)
    if not app.victory:active() then app.victory = nil end
    -- Der Fluch ist zurueck (Debug-REVANCHE, #110): Sequenz sofort abraeumen
    if app.view and app.view.phase == "try" then
      love.filesystem.remove("sieg.dat")
      app.victory, app.sysmsg_done, app.endboard = nil, nil, nil
      app.render.sysmsg = nil
    end
  end

  -- Die Endsequenz taktet die Sim (Runde 11, #132): won_stage 4 heisst
  -- "Leeroy ist ausgeloggt". Danach die Systemnachricht, kurz darauf die
  -- Statistik-Tafel als letztes Bild — sie bleibt bis zum Klick stehen.
  -- Wer den Fluchbruch gesehen hat, beendet bei einer Trennung das Spiel
  -- statt neu zu suchen (#133): geht der Host, ist der Abend vorbei.
  if view and (view.won_stage or 0) > 0 then app.won_seen = true end
  if view and (view.won_stage or 0) >= 4 then
    if not app.sysmsg_done then
      app.sysmsg_done = 0
      app.render.sysmsg = require("game.data.names").LEEROY_LEFT
      app.render.bubble_t = 0 -- die Blase bricht mitten im Satz ab
    end
    app.sysmsg_done = app.sysmsg_done + dt
    if app.sysmsg_done >= 1.7 and not app.endboard and app.end_board then
      app.endboard = true
      app.stats = require("game.ui.stats").new(app.end_board, { hold = true })
    end
  end

  -- Questfenster des Echos (GDD Kap. 5): das Echo drueckt die Quest auf,
  -- der Snapshot sagt wann (quest == 1). Rejoin bekommt keine Quest, nur
  -- "Ah. Wieder da." (GDD 5, Punkt 4)
  local me_now = view and view.players[view.me]
  if view and (not app.boot or not app.boot:active()) then
    if me_now and (me_now.quest or 2) == 1 and not app.quest then
      app.quest = require("game.ui.quest").new(app.name_given and app.name or nil)
      -- Anflug des Echos (GDD 12 Nr. 17; seit #138 keine Charge mehr, der
      -- Whoosh bleibt) — nicht der Schrei, der gehoert dem Raid-Leeroy
      audio.play("snd_echo_charge")
    elseif app.rejoin_known and not app.rejoin_greeted then
      app.rejoin_greeted = true
      local known = (app.mode == "host" and app.net.session
                     and app.net.session.chars
                     and app.net.session.chars[app.name] ~= nil)
                    or (app.mode == "client" and app.net.rejoin)
      if known then app.render:announce('Echo: "Ah. Wieder da."', 4) end
    end
  end
  if app.quest then
    app.quest:update(dt)
    local wish = app.quest:take_submit()
    if wish then
      if app.mode == "host" then
        app.quest:result(app.net:rename(app.net.local_pid, wish))
      else
        app.net:send_rename(wish)
      end
    end
    if app.mode == "client" and app.net.rename_result ~= nil then
      app.quest:result(app.net.rename_result)
      app.net.rename_result = nil
    end
    if app.quest.accepted and app.name ~= app.quest.accepted then
      -- bestaetigter Name: merken (Rejoin) und Charakter daran haengen
      app.name = app.quest.accepted
      love.filesystem.write("charname.dat",
        os.date("%Y-%m-%d") .. "\n" .. app.name)
    end
    if app.quest.state == "done" and not app.quest.sent then
      -- Name steht: Quest annehmen; der Host gibt danach die Bewegung frei
      app.quest.sent = true
      app.net:accept_quest()
      audio.play("snd_ui_click")
    end
    if me_now and (me_now.quest or 2) >= 2 and app.quest.mode == "quest" then
      app.quest = nil -- angenommen; ab jetzt holt Taste L das Questlog
    end
  end

  if app.shot_at then
    app.shot_at = app.shot_at - dt
    if app.shot_at <= 0 then
      app.shot_at = nil
      love.graphics.captureScreenshot("debug-shot.png")
      app.quit_next = 2
    end
  elseif app.quit_next then
    app.quit_next = app.quit_next - 1
    if app.quit_next <= 0 then love.event.quit(0) end
  end
end

function love.draw()
  if app.drawtest then
    if not app.drawtest_fertig then
      app.drawtest_fertig = true
      -- Ergebnis zusaetzlich in den Speicherordner: unter Windows kommt
      -- stdout aus einem LOEVE-Fenster nicht zuverlaessig beim Aufrufer an,
      -- und ein Ladefehler wuerde sonst nur die blaue Fehlerseite zeigen.
      local ok, res = pcall(function()
        return require("game.test.drawtest").run()
      end)
      -- Der Test schreibt seinen Bericht selbst; hier faengt nur ein
      -- Ladefehler auf, der sonst als blaue Fehlerseite haengen bliebe.
      if not ok then
        love.filesystem.write("drawtest.txt", "LADEFEHLER " .. tostring(res))
      end
      if not ok then print("Zeichentest brach ab: " .. tostring(res)) end
      love.event.quit(ok and res or 1)
    end
    return
  end
  if app.headless then return end
  local bw, bh = love.graphics.getDimensions()
  if app.boot and app.boot:active() and app.boot:covers_screen() then
    -- Boot-Sequenz verdeckt die Spielsicht komplett (GDD Kap. 3)
    app.boot:draw(bw, bh)
  elseif app.mode == "disconnected" then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, bw, bh)
  elseif app.mode == "discover" or not app.view then
    love.graphics.setColor(0.9, 0.88, 0.8, 1)
    local msg = app.mode == "discover"
      and "Realm wird gesucht ..." or (app.net and app.net.failed or "Verbinde ...")
    love.graphics.print(msg, 40, 40)
    love.graphics.setColor(0.5, 0.48, 0.4, 1)
    love.graphics.print("F12: Debug (manuelle IP, Host erzwingen)", 40, 62)
  else
    local cds = {}
    for i = 1, 4 do -- Slot 4: Schurken-Tritt (Runde 12, #140)
      cds[i] = app.cooldown_max[i] > 0
        and app.cooldown_view[i] / app.cooldown_max[i] or 0
    end
    -- Reichweiten-Rueckmeldung am Button (Runde 14, #171): dieselbe
    -- Pruefung wie die Fehlerzeile, nur ohne Tastendruck — steht das Ziel
    -- zu weit weg, faerbt sich der Button rot statt still zu versagen.
    local oor = {}
    do
      local step_mod = require("game.gamesim.step")
      local errors = require("game.ui.errors")
      local me = app.view.players[app.view.me]
      local specs = me and me.class and step_mod.ABILITIES[me.class]
      if specs and me.alive then
        for i, spec in ipairs(specs) do
          if spec.range and step_mod.ability_enabled(spec) then
            oor[i] = errors.check(me, spec, {
              x = me.x, y = me.y, facing = me.facing, cooldown = 0,
              hogger = app.view.hogger, npcs = app.view.npcs,
              players = app.view.players,
            }) == errors.TOO_FAR
          end
        end
      end
    end
    local to_screen = app.render:draw(app.view, {
      facing_angle = app.facing_angle,
      cooldowns = cds,
      out_of_range = oor,
      mouse = { love.mouse.getPosition() },
    })
    app.floating:draw(to_screen)
    if app.quest then app.quest:draw(app.view, bw, bh, to_screen) end
    -- "Geist freilassen" zwischen Tod und Friedhof (GDD Kap. 11)
    do
      local rel = require("game.ui.release")
      local me = app.view.players[app.view.me]
      local mx, my = love.mouse.getPosition()
      rel.draw(me, bw, bh, rel.hit(rel.layout(bw, bh).button, mx, my))
    end
    if app.stats then app.stats:draw() end
    if app.victory then app.victory:draw(app.view, to_screen, bw, bh) end
    -- Raid-Overview, solange die linke STRG-Taste gehalten wird (Runde 6,
    -- Issue #95): reines Overlay, blockiert keine Eingaben
    if love.keyboard.isDown("lctrl") then
      app.render:draw_raid_overview(app.view, bw, bh)
    end
    if app.panel then app.panel:draw() end
  end
  if app.boot and app.boot:active() and not app.boot:covers_screen() then
    app.boot:draw_overlay(bw, bh) -- langsame Aufblende in die Totensicht
  end
  -- Spielmenue ueber allem, aber unter dem Trennungs-Dialog (#133)
  if app.menu then
    local gmx, gmy = love.mouse.getPosition()
    gamemenu.draw(bw, bh, gmx, gmy)
  end
  if app.dialog and app.dialog.visible then app.dialog:draw() end
  local lobbies = 0
  if app.search then
    for _ in pairs(app.search.lobbies) do lobbies = lobbies + 1 end
  end
  app.debug:draw({
    mode = app.mode,
    own_ip = discovery and discovery.own_ip() or "?",
    lobbies = lobbies,
    log_dir = love.filesystem.getSaveDirectory(),
    volume = audio.master(),
    net = app.net and app.net.guard and app.net.guard:note(),
    docked = app.render and app.render.docked,
  })
end

-- Eine Wahrheit fuer Tastendruck UND Buttonklick (Runde 14, #172).
-- Vorher lag die Logik zweimal in love.keypressed; die Buttons am Ring
-- waren reine Grafik. via_click setzt den Ein-Tick-Riegel, damit der
-- Klick dieselbe Flanke erzeugt wie eine gedrueckte Taste — die Maske
-- wird pro Simulationstick gepollt, ein Klick ist aber ein Ereignis.
local function trigger_ability(slot, via_click)
  local me = app.view and app.view.players[app.view.me]
  local step_mod = require("game.gamesim.step")
  local specs = me and me.alive and me.class and step_mod.ABILITIES[me.class]
  local spec = specs and specs[slot]
  -- per F10 abgeschaltet (Runde 13): Taste und Klick tun nichts
  if spec and not step_mod.ability_enabled(spec) then spec = nil end
  if not spec then return false end
  -- Fehlerzeile im Original-Ton (Issue #56): der Host verwirft den Versuch
  -- stumm, also sagt der Client hier, warum nichts passiert
  local err = require("game.ui.errors").check(me, spec, {
    x = app.view.me_x, y = app.view.me_y,
    facing = input.facing_from_angle(app.facing_angle or 0),
    cooldown = app.cooldown_view[slot] or 0,
    hogger = app.view.hogger, npcs = app.view.npcs,
    players = app.view.players, -- Heil-Reichweite (Runde 7, #103)
  })
  if err then
    app.render:error(err)
    return true
  end
  if slot == 4 then
    -- Schurken-Tritt (Runde 12, #140): kein Masken-Bit, eigene Wire-Msg
    if app.mode == "host" then app.net:kick()
    elseif app.net.send_kick then app.net:send_kick() end
    local cd = model.p(spec.cd)
    app.cooldown_view[4], app.cooldown_max[4] = cd, cd
  else
    if via_click then app.click_ab = slot end
    local cd = spec.cd and model.p(spec.cd) or model.p("gcd")
    app.cooldown_view[slot], app.cooldown_max[slot] = cd, cd
  end
  return true
end

function love.keypressed(key)
  if app.headless then return end
  if app.dialog and app.dialog.visible then
    if app.dialog:keypressed(key) then
      if app.dialog.quit then love.event.quit(0) return end -- nach dem Sieg
      -- OK: Glitch-Schwarz + automatischer Reconnect (GDD Kap. 3)
      app.dialog = nil
      start_search()
      if app.boot then app.boot:reenter() end
    end
    return
  end
  local action = app.debug:keypressed(key)
  if action == "host" then
    teardown_net()
    if app.search then app.search:close(); app.search = nil end
    start_host()
    return
  elseif action == "wipe" then
    require("game.session").wipe()
    app.debug.note = "session.json geloescht (wirkt beim naechsten Host-Start)"
    return
  elseif action == "dock" then
    -- HUD-Dock (M12/M13): live umschaltbar; Standard ist AN
    app.render.docked = not app.render.docked
    app.debug.note = app.render.docked
      and "HUD am Ring angedockt (Standard)" or "HUD in den Ecken (Debug)"
    return
  elseif type(action) == "table" and action.bots then
    -- Laufzeit-Bots (Runde 8, #109): joinen wie echte Nachzuegler
    if app.mode == "host" and app.net and app.net.add_bots then
      local total = app.net:add_bots(action.bots)
      app.debug.note = string.format("+%d Bots (jetzt %d Spieler)",
        action.bots, total)
    else
      app.debug.note = "Nur der Host kann Bots hinzufuegen."
    end
    return
  elseif action == "kill" then
    -- Hogger sofort toeten: Fluchbruch allein testbar (Issue #35)
    if app.mode == "host" and app.net and app.net.kill_hogger then
      app.debug.note = app.net:kill_hogger()
        and "Hogger getoetet — Fluchbruch laeuft"
        or "Hogger ist schon tot (oder der Try laeuft nicht)"
    else
      app.debug.note = "Nur der Host kann Hogger toeten."
    end
    return
  elseif action == "teleport" then
    -- Test-Teleport (Runde 6, #100): sofort als Zufallsklasse vor Hogger
    if app.mode == "host" and app.net and app.net.teleport_self then
      app.debug.note = app.net:teleport_self()
        and "Teleportiert — Hogger wartet."
        or "Teleport ging nicht (Hogger tot oder kein Spieler)."
    else
      app.debug.note = "Nur der Host kann sich teleportieren."
    end
    return
  elseif action == "revanche" then
    -- Testhilfe (Runde 11, #133): im Spiel gibt es nach dem Fluchbruch
    -- keinen Weg zurueck; hier schon, sonst braeuchte jeder Durchlauf der
    -- Endsequenz einen Anwendungsneustart.
    if app.mode == "host" and app.net and app.net.revanche then
      app.debug.note = app.net:revanche()
        and "Realm zurueck im Try — der Fluch ist wieder da"
        or "Geht nur nach dem Fluchbruch."
    else
      app.debug.note = "Nur der Host kann das."
    end
    return
  elseif action == "intro" then
    replay_intro()
    return
  elseif action == "realm" then
    restart_realm()
    return
  elseif type(action) == "table" and action.join then
    teardown_net()
    if app.search then app.search:close(); app.search = nil end
    start_client(action.join)
    return
  elseif type(action) == "table" and action.volume then
    -- Lautstaerke lebt im Debug-Overlay (GDD 4.4)
    audio.set_master(audio.master() + action.volume)
    audio.play("snd_ui_click")
    return
  elseif action == true then
    return
  end
  -- Spielmenue (GDD 11, #133): es gibt NUR nach dem Fluchbruch. Der Abend
  -- ist vorbei, das Spiel wartet auf harten Input — ESC oeffnet und
  -- schliesst, ALT+F4 beendet ohne Umweg (love.quit raeumt das Netz ab).
  if key == "escape" and gamemenu.available(app.view) then
    app.menu = not app.menu
    audio.play("snd_ui_click")
    return
  end
  if app.menu then return end -- offen schluckt es alles andere

  if key == "f12" then app.debug:toggle() return end
  -- Questlog wie im Original (Issue #62): wegblenden, zurueckholen, und
  -- nach der Annahme die Quest nachlesen
  if key == "l" and not (app.boot and app.boot:active()) then
    if app.quest then
      app.quest:toggle()
    elseif app.view then
      local me = app.view.players[app.view.me]
      if me and (me.quest or 0) >= 2 then
        app.quest = require("game.ui.quest").new_log()
      end
    end
    return
  end
  if app.boot and app.boot:active() then
    -- getarnte IP-Konsole im Glitch-Bild (GDD Kap. 3)
    local boot_action = app.boot:keypressed(key)
    if type(boot_action) == "table" and boot_action.join then
      teardown_net()
      if app.search then app.search:close(); app.search = nil end
      start_client(boot_action.join)
      app.auto_hosted = false
      return
    elseif boot_action then
      return
    end
  end
  if app.quest and app.quest:blocking() then
    app.quest:keypressed(key) -- das Questfenster schluckt alles
    return
  end
  if app.quest and app.quest.mode == "log" and key == "escape" then
    app.quest = nil
    return
  end
  if app.victory then
    app.victory:keypressed(key) -- Sequenz schluckt Tasten (Welt steht)
    return
  end
  if app.stats and app.stats:keypressed(key) then return end
  if app.mode == "discover" then return end
  if app.panel and app.panel:keypressed(key) then return end
  if key == "f10" and app.panel then
    app.panel:toggle()
  elseif key == "kp+" or key == "+" then
    app.render:set_zoom(app.render.zoom - 1)
    if app.net.send_zoom then app.net:send_zoom(app.render.zoom) end
  elseif key == "kp-" or key == "-" then
    app.render:set_zoom(app.render.zoom + 1)
    if app.net.send_zoom then app.net:send_zoom(app.render.zoom) end
  elseif key == "1" or key == "2" or key == "3" then
    trigger_ability(tonumber(key), false)
  elseif key == "4" then
    trigger_ability(4, false)
  elseif key == "tab" then
    if app.mode == "host" then app.net:set_local_target(world.HOGGER_ID)
    else app.net:set_target(world.HOGGER_ID) end
  end
end

function love.textinput(t)
  if app.debug and app.debug:textinput(t) then return end
  if app.boot and app.boot:active() and app.boot:textinput(t) then return end
  if app.quest and app.quest:blocking() then app.quest:textinput(t) end
end

function love.mousepressed(mx, my, button)
  if app.headless then return end
  -- Spielmenue nach dem Fluchbruch (GDD 11, #133): nur "Spiel verlassen" ist
  -- scharf, ein Klick daneben tut nichts (auch nicht schliessen — dafuer ESC)
  if app.menu then
    local w, h = love.graphics.getDimensions()
    if gamemenu.click(w, h, mx, my) == "quit" then
      audio.play("snd_ui_click")
      love.event.quit(0) -- love.quit raeumt Netz und Session ab
    end
    return
  end
  -- Tuning-Panel zuerst: Export-Knopf, und Klicks im Panel setzen kein Ziel
  if app.panel and app.panel:mousepressed(mx, my) then return end
  if app.dialog and app.dialog.visible then
    if app.dialog:mousepressed(mx, my) then
      if app.dialog.quit then love.event.quit(0) return end -- nach dem Sieg
      app.dialog = nil
      start_search()
      if app.boot then app.boot:reenter() end
    end
    return
  end
  if app.boot and app.boot:active() and app.boot:covers_screen() then
    app.boot:mousepressed() -- ab dem zweiten Start ueberspringbar (GDD 3)
    return
  end
  if app.quest and app.quest:visible() then
    local w2, h2 = love.graphics.getDimensions()
    local L = app.quest:layout(w2, h2)
    if app.quest:blocking()
       or (mx >= L.x and mx <= L.x + L.w and my >= L.y and my <= L.y + L.h) then
      app.quest:mousepressed(mx, my, w2, h2)
      return
    end
  end
  if app.victory then
    -- Der Auftakt schluckt Klicks; ein Klick ins Loot-Fenster ueberspringt es
    app.victory:mousepressed(mx, my)
    return
  end
  if app.stats and app.stats:mousepressed(mx, my) then return end
  if not app.view then return end

  -- Faehigkeitsbuttons am Ring (Runde 14, #172): Linksklick loest sie aus,
  -- exakt wie die zugehoerige Taste. Vor dem Kartenklick, damit ein Klick
  -- auf einen Button nicht auch noch ein Ziel dahinter waehlt.
  if button == 1 then
    local me = app.view.players[app.view.me]
    if me and me.alive and me.class then
      local bw2, bh2 = love.graphics.getDimensions()
      local L = app.render.layout(bw2, bh2, app.render.docked)
      local slot = app.render.ability_button_at(L, me.class, mx, my)
      if slot then
        trigger_ability(slot, true)
        audio.play("snd_ui_click")
        return
      end
    end
  end

  -- Heil-Leiste (Runde 7, #103, GDD 4.3): Rechtsklick auf eine Zeile heilt
  -- diesen Spieler (HEAL_REQUEST, p.target bleibt unberuehrt), Linksklick
  -- waehlt ihn als Ziel. Klicks im Leistenrechteck erreichen nie die Karte.
  local w, h = love.graphics.getDimensions()
  -- EINE Layout-Wahrheit mit dem Renderer (M12): Hit-Tests rechnen mit
  -- denselben, UNgeshakten Zahlen wie die Zeichnung
  local L = app.render.layout(w, h, app.render.docked)
  do
    local step_mod = require("game.gamesim.step")
    local me = app.view.players[app.view.me]
    local slot = me and me.alive and me.class and step_mod.ALLY_SLOT[me.class]
    if slot then
      local HB = L.frames.healbar
      local rows, more_n = app.render.heal_rows(app.view,
        model.p("heal_range"), HB.max_rows)
      local ph = HB.header_h + (#rows + ((more_n > 0) and 1 or 0)) * HB.row_h + 8
      if #rows > 0 and mx >= HB.x and mx <= HB.x + HB.w
         and my >= HB.y and my <= HB.y + ph then
        local i = app.render.healbar_row_at(#rows, mx, my, HB)
        local row = i and rows[i]
        if row and button == 2 then
          -- Fehlerzeile vorab (Issue #56): der Host verwirft stumm, der
          -- Client sagt, warum nichts passiert (GCD/Mana; Reichweite ist
          -- durch die Listen-Mitgliedschaft praktisch garantiert)
          local spec = step_mod.ABILITIES[me.class][slot]
          local t = app.view.players[row.pid]
          local err = require("game.ui.errors").check(me, spec, {
            x = app.view.me_x, y = app.view.me_y,
            cooldown = app.cooldown_view[slot] or 0,
            ally_target = t and { x = t.x, y = t.y, alive = t.alive,
                                  is_self = row.is_self },
          })
          if err then
            app.render:error(err)
          else
            if app.mode == "host" then app.net:heal_request(row.pid)
            else app.net:send_heal(row.pid) end
            local cd = spec.cd and model.p(spec.cd) or model.p("gcd")
            app.cooldown_view[slot] = cd
            app.cooldown_max[slot] = cd
            audio.play("snd_ui_click")
          end
        elseif row then
          if app.mode == "host" then app.net:set_local_target(row.pid)
          else app.net:set_target(row.pid) end
          audio.play("snd_ui_click")
        end
        return
      end
    end
  end

  local radius = L.radius
  local scale = radius / app.render:zoom_radius()
  local function to_screen(wx, wy)
    return w / 2 + (wx - app.view.me_x) * scale,
           h / 2 + (wy - app.view.me_y) * scale
  end
  -- Zoom-Knoepfe am Ring (GDD 4.2); UI-Klick-Sound (GDD 12 Nr. 14).
  -- Trefferpruefung seit Runde 15 (#189) in render.zoom_button_at — dieselbe
  -- Rechnung wie das Zeichnen, damit Knopf und Klickflaeche zusammenbleiben.
  do
    local knopf = app.render.zoom_button_at(L, mx, my)
    if knopf then
      audio.play("snd_ui_click")
      -- Plus = naeher heran = kleinere Zoomstufe
      app.render:set_zoom(app.render.zoom + (knopf == "plus" and -1 or 1))
      return
    end
  end
  -- "Geist freilassen" (GDD Kap. 11): der Knopf greift erst, wenn der
  -- Respawn-Timer abgelaufen ist
  do
    local rel = require("game.ui.release")
    local me = app.view.players[app.view.me]
    if rel.visible(me) then
      local L = rel.layout(love.graphics.getDimensions())
      if rel.hit(L.button, mx, my) then
        if rel.ready(me.dead_rest) then
          app.net:release_spirit()
          audio.play("snd_ui_click")
        end
        return
      end
    end
  end

  -- Das Echo anklicken (nur als Geist, Issue #63): vor der Annahme holt es
  -- das Questfenster zurueck, danach erzaehlt es die ganze Geschichte —
  -- Easter Egg ohne jede Spielwirkung (Issue #64)
  do
    local me = app.view.players[app.view.me]
    if app.view.echo and me and me.ghost then
      local ex, ey = to_screen(app.view.echo.x, app.view.echo.y)
      if math.sqrt((ex - mx) ^ 2 + (ey - my) ^ 2) < 28 then
        local quest = require("game.ui.quest")
        if (me.quest or 2) == 1 then
          -- erneutes Anklicken chargt nicht noch einmal
          if app.quest then app.quest:reopen()
          else app.quest = quest.new(nil, true) end
        else
          app.quest = quest.new_lore()
        end
        audio.play("snd_ui_click")
        return
      end
    end
  end

  -- Geistheiler anklicken: funktionslose Szenerie mit genau einer Reaktion
  -- (GDD 7.1) — Leeroy-Zeile 26, rein lokal, kein Spielzustand
  do
    local sh = require("game.data.map").spirit_healer()
    local x, y = to_screen(sh.x, sh.y)
    if math.sqrt((x - mx) ^ 2 + (y - my) ^ 2) < 26 then
      local lines = require("game.gamesim.lines")
      app.render:announce("Echo: " .. lines[26], 4)
      audio.play("snd_ui_click")
      return
    end
  end

  -- Karten-Klickziel (Runde 13, #154): eine love-freie Wahrheit in
  -- render.pick_target — der Rechtsklick ist der Angriffsklick und
  -- bevorzugt Feinde (Hogger gewinnt in seinem Icon-Radius), der
  -- Linksklick waehlt wie seit Runde 7 das naechste Zentrum
  local best, best_enemy = app.render.pick_target(app.view, mx, my,
    to_screen, scale, button == 2)
  if best then
    if app.mode == "host" then app.net:set_local_target(best)
    else app.net:set_target(best) end
    -- Rechtsklick auf Hogger oder Mob schaltet die Autoattack an (Issue #86;
    -- seit Runde 12 #145 der einzige Weg neben dem Faehigkeitsdruck)
    if button == 2 and best_enemy then
      if app.mode == "host" then app.net:engage()
      elseif app.net.send_engage then app.net:send_engage() end
    end
  end
end

function love.wheelmoved(_, dy)
  if app.headless or not app.render or app.mode == "discover" then return end
  if dy > 0 then app.render:set_zoom(app.render.zoom - 1)
  elseif dy < 0 then app.render:set_zoom(app.render.zoom + 1) end
  if app.net and app.net.send_zoom then app.net:send_zoom(app.render.zoom) end
end

function love.quit()
  teardown_net()
  if app.search then app.search:close() end
end
