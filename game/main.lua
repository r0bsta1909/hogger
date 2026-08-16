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
local wire, discovery

local app = {
  mode = "discover", name = "spieler", join_ip = nil, seed = nil,
  bots = 0, headless = false, test = false,
  net = nil, search = nil, beacon = nil,
  render = nil, panel = nil, floating = nil, debug = nil,
  boot = nil, dialog = nil, auto_hosted = false, uptime = 0,
  cooldown_view = { 0, 0, 0 }, cooldown_max = { 1, 1, 1 },
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
    elseif a == "--stress" then app.stress = true
    elseif a == "--shot" then i = i + 1; app.shot_at = tonumber(args[i]) or 3
    elseif a == "--auto" then app.auto = true
    elseif a == "--panel" then app.open_panel = true
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

local function teardown_net()
  if app.net and app.net.destroy then app.net:destroy() end
  app.net = nil
  if app.beacon then app.beacon:close(); app.beacon = nil end
  app.view = nil
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
  wire = require("game.net.wire")
  discovery = require("game.net.discovery")
  app.render = require("game.render").new()
  app.floating = require("game.ui.floating").new()
  app.debug = require("game.ui.debug").new()
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
      app.need_intro = not app.auto -- Debug-Autolaeufe starten ohne Intro
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
  local w, h = love.graphics.getDimensions()
  local mx, my = love.mouse.getPosition()
  local angle = math.atan2(my - h / 2, mx - w / 2) + math.pi / 2
  local facing = math.floor((angle % (2 * math.pi)) / (2 * math.pi) * 256) % 256
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
      local own = tonumber(e.src) == view.me or tonumber(e.dst) == view.me
      local color = e.crit and { 1, 0.85, 0.2 } or { 1, 1, 1 }
      -- Krit-Inszenierung (GDD 11): gross und gelb, Screenshake beide Seiten
      app.floating:add(tostring(math.floor((e.val or 0) + 0.5)), tx, ty,
        color, e.crit and 3 or (own and 2 or 1))
      if e.crit and tonumber(e.dst) == view.me then app.render:add_shake(12)
      elseif e.crit and tonumber(e.src) == view.me then app.render:add_shake(6) end
    elseif e.ev == "heal" then
      local tx, ty = entity_pos(e.dst)
      app.floating:add("+" .. tostring(math.floor((e.val or 0) + 0.5)),
        tx, ty, { 0.3, 0.95, 0.3 }, tonumber(e.dst) == view.me and 2 or 1)
      if tonumber(e.dst) == view.me then app.last_healed_t = app.uptime end
    elseif e.ev == "death" and tonumber(e.src) == view.me then
      -- Killcam-Zeile (GDD 11): kontextsensitiv, deterministische Rotation
      app.my_deaths = (app.my_deaths or 0) + 1
      local healed = app.last_healed_t ~= nil
                     and (app.uptime - app.last_healed_t) < 4
      app.render:show_killcam(require("game.gamesim.killcam").pick(
        tonumber(e.val), e.crit, app.my_deaths, healed))
    elseif e.ev == "crit_kill" and tonumber(e.dst) == view.me then
      app.render:add_shake(18) -- der "WAS?!"-Moment (GDD 9.2)
    elseif e.ev == "eat_start" then
      app.render:announce("HOGGER FRISST!", 2.5)
    elseif e.ev == "eat_complete" then
      app.render:announce("Hogger hat gefressen ...", 2.5)
    elseif e.ev == "try_end" then
      if (e.val or 0) >= 1 then
        app.render:announce("HOGGER IST TOT!", 8)
      else
        app.render:announce("Wipe. Naechster Try.", 4)
      end
    elseif e.ev == "try_start" then
      app.render:announce("Try " .. tostring(e.dst or ""), 2.5)
    elseif e.ev == "loot_pickup" and tonumber(e.src) == view.me then
      local pool = require("game.gamesim.loot")
      local item = pool[tonumber(e.dst) or 0] or "Plunder"
      app.render:toast(item .. "  (+" .. tostring(math.floor(e.val or 0)) .. " Kupfer)")
    elseif e.ev == "ding" then
      -- DING-Inszenierung (GDD 7.3): goldener Ring + Ansage; Leeroys
      -- Kommentar (Zeile 29) folgt als eigenes leeroy_line-Event
      app.render:announce("DING!", 6)
      local dp = view.players[tonumber(e.src)]
      if dp then app.render:add_ding(dp.x, dp.y) end
    elseif e.ev == "leeroy_line" then
      local lines = require("game.gamesim.lines")
      local text = lines[tonumber(e.dst) or 0]
      if text then app.render:announce("Leeroy: " .. text, 4) end
    end
  end
  for i = #list, 1, -1 do list[i] = nil end
end

function love.update(dt)
  if app.headless then return end

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
     or (app.intro and app.intro:blocking()) then
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
  elseif app.mode == "client" and app.net.failed then
    -- authentischer WoW-Disconnect-Dialog, danach Glitch-Schwarz und
    -- automatischer Reconnect (GDD Kap. 3)
    teardown_net()
    app.dialog = require("game.ui.dialog").new("Vom Server getrennt.")
    app.mode = "disconnected"
    return
  end

  for i = 1, 3 do
    if app.cooldown_view[i] > 0 then
      app.cooldown_view[i] = math.max(0, app.cooldown_view[i] - dt)
    end
  end

  local view = build_view()
  process_cosmetics(view)
  app.view = view
  app.floating:update(dt)
  app.render:update(dt)

  -- Statistik-Tafel am Try-Ende (GDD 11): Host baut, alle zeigen
  if app.net and app.net.stats_board then
    app.stats = require("game.ui.stats").new(app.net.stats_board)
    app.net.stats_board = nil
  end
  if app.stats then
    app.stats:update(dt)
    if not app.stats.visible then app.stats = nil end
  end

  -- Leeroy-Intro (GDD Kap. 5): startet nach der Aufblende (Boot fertig);
  -- Rejoin bekommt statt des Intros nur "Ah. Wieder da." (GDD 5, Punkt 4)
  if view and (not app.boot or not app.boot:active()) then
    if app.need_intro and not app.intro then
      app.need_intro = nil
      app.intro = require("game.ui.intro").new()
    elseif app.rejoin_known and not app.rejoin_greeted then
      app.rejoin_greeted = true
      local known = (app.mode == "host" and app.net.session
                     and app.net.session.chars
                     and app.net.session.chars[app.name] ~= nil)
                    or (app.mode == "client" and app.net.rejoin)
      if known then app.render:announce('Leeroy: "Ah. Wieder da."', 4) end
    end
  end
  if app.intro then
    app.intro:update(dt)
    local wish = app.intro:take_submit()
    if wish then
      if app.mode == "host" then
        app.intro:result(app.net:rename(app.net.local_pid, wish))
      else
        app.net:send_rename(wish)
      end
    end
    if app.mode == "client" and app.net.rename_result ~= nil then
      app.intro:result(app.net.rename_result)
      app.net.rename_result = nil
    end
    if app.intro.accepted and app.name ~= app.intro.accepted then
      -- bestaetigter Name: merken (Rejoin) und Charakter daran haengen
      app.name = app.intro.accepted
      love.filesystem.write("charname.dat",
        os.date("%Y-%m-%d") .. "\n" .. app.name)
    end
    if not app.intro:blocking() then app.intro = nil end
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
    for i = 1, 3 do
      cds[i] = app.cooldown_max[i] > 0
        and app.cooldown_view[i] / app.cooldown_max[i] or 0
    end
    local to_screen = app.render:draw(app.view, {
      facing_angle = app.facing_angle,
      cooldowns = cds,
      mouse = { love.mouse.getPosition() },
    })
    app.floating:draw(to_screen)
    if app.intro then app.intro:draw(app.view, bw, bh) end
    if app.stats then app.stats:draw() end
    if app.panel then app.panel:draw() end
  end
  if app.boot and app.boot:active() and not app.boot:covers_screen() then
    app.boot:draw_overlay(bw, bh) -- langsame Aufblende in die Totensicht
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
  })
end

function love.keypressed(key)
  if app.headless then return end
  if app.dialog and app.dialog.visible then
    if app.dialog:keypressed(key) then
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
  elseif type(action) == "table" and action.join then
    teardown_net()
    if app.search then app.search:close(); app.search = nil end
    start_client(action.join)
    return
  elseif action == true then
    return
  end
  if key == "f12" then app.debug:toggle() return end
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
  if app.intro and app.intro:blocking() then
    app.intro:keypressed(key) -- Intro schluckt alles (Eingaben gesperrt)
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
    local slot = tonumber(key)
    local me = app.view and app.view.players[app.view.me]
    local cd = model.p("gcd")
    if me and me.class == "hunter" and slot == 1 then
      cd = model.p("hunter_raptor_cd")
    end
    app.cooldown_view[slot] = cd
    app.cooldown_max[slot] = cd
  elseif key == "tab" then
    if app.mode == "host" then app.net:set_local_target(world.HOGGER_ID)
    else app.net:set_target(world.HOGGER_ID) end
  end
end

function love.textinput(t)
  if app.debug and app.debug:textinput(t) then return end
  if app.boot and app.boot:active() and app.boot:textinput(t) then return end
  if app.intro and app.intro:blocking() then app.intro:textinput(t) end
end

function love.mousepressed(mx, my)
  if app.headless then return end
  if app.dialog and app.dialog.visible then
    if app.dialog:mousepressed(mx, my) then
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
  if app.intro and app.intro:blocking() then
    app.intro:mousepressed() -- Dialog-Panels weiterklicken (GDD 5)
    return
  end
  if app.stats and app.stats:mousepressed(mx, my) then return end
  if not app.view then return end
  local w, h = love.graphics.getDimensions()
  local radius = h / 2 - 8
  local scale = radius / app.render:zoom_radius()
  local function to_screen(wx, wy)
    return w / 2 + (wx - app.view.me_x) * scale,
           h / 2 + (wy - app.view.me_y) * scale
  end
  -- Zoom-Knoepfe am Ring (GDD 4.2)
  local zx, zy = w / 2 + radius * 0.86, h / 2 + radius * 0.42
  if math.abs(mx - zx) < 14 and math.abs(my - zy) < 14 then
    app.render:set_zoom(app.render.zoom - 1) return
  end
  if math.abs(mx - zx) < 14 and math.abs(my - (zy + 34)) < 14 then
    app.render:set_zoom(app.render.zoom + 1) return
  end
  local best, best_d = nil, 24
  for pid, p in pairs(app.view.players) do
    if pid ~= app.view.me then
      local x, y = to_screen(p.x, p.y)
      local d = math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
      if d < best_d then best, best_d = pid, d end
    end
  end
  for nid, npc in pairs(app.view.npcs or {}) do
    if npc.kind ~= "imp" then
      local x, y = to_screen(npc.x, npc.y)
      local d = math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
      if d < best_d then best, best_d = nid, d end
    end
  end
  do
    local x, y = to_screen(app.view.hogger.x, app.view.hogger.y)
    local d = math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
    if d < best_d then best, best_d = world.HOGGER_ID, d end
  end
  if best then
    if app.mode == "host" then app.net:set_local_target(best)
    else app.net:set_target(best) end
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
