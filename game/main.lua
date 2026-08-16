-- game/main.lua — LOEVE-Einstieg: Verdrahtung von Sim, Netz und Darstellung.
-- M2-Debug-Start (GDD 15): love game [--join IP] [--name X] [--bots K]
--                          [--seed N] | love game --headless --test
-- Fixer Zeitschritt lebt in host/client; hier nur Eingabe, Kosmetik, UI.

-- Repo-Wurzel in den Suchpfad: game/ importiert sim/model.lua unveraendert
do
  local src = love.filesystem.getSource()
  package.path = src .. "/../?.lua;" .. src .. "/?.lua;" .. package.path
end

local model = require("sim.model")
local input = require("game.gamesim.input")
local world = require("game.gamesim.world")
local wire -- erst nach --headless-Entscheidung laden (braucht love.data)

local app = {
  mode = "host", name = "spieler", join_ip = nil, seed = nil,
  bots = 0, headless = false, test = false,
  net = nil, render = nil, panel = nil, floating = nil,
  cooldown_view = { 0, 0, 0 }, cooldown_max = { 1, 1, 1 },
  last_try = 0,
}

local function parse_args(args)
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--join" then i = i + 1; app.join_ip = args[i]; app.mode = "client"
    elseif a == "--name" then i = i + 1; app.name = args[i]
    elseif a == "--seed" then i = i + 1; app.seed = tonumber(args[i])
    elseif a == "--bots" then i = i + 1; app.bots = tonumber(args[i]) or 0
    elseif a == "--headless" then app.headless = true
    elseif a == "--test" then app.test = true
    elseif a == "--shot" then i = i + 1; app.shot_at = tonumber(args[i]) or 3
    elseif a == "--auto" then app.auto = true -- Debug: eigener Spieler als Bot
    elseif a == "--panel" then app.open_panel = true -- Debug: F10 direkt offen
    end
    i = i + 1
  end
end

function love.load(args)
  parse_args(args or {})

  if app.headless and app.test then
    local exit = require("game.test.headless").run()
    love.event.quit(exit)
    return
  end

  wire = require("game.net.wire")
  app.render = require("game.render").new()
  app.floating = require("game.ui.floating").new()

  if app.mode == "host" then
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
    app.panel = require("game.ui.panel").new(function(key, value)
      return app.net:set_param(key, value)
    end)
    if app.open_panel then app.panel.visible = true end
  else
    local clientmod = require("game.net.client")
    app.net = clientmod.new(app.join_ip, app.name)
  end
end

local ABILITY_KEYS = { "1", "2" }

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
  if app.mode == "host" then
    local body = wire.snapshot_body(app.net.state)
    local _, snap = wire.read_snapshot(wire.snapshot(0, body), 4)
    snap.me = app.net.local_pid
    local me = snap.players[snap.me]
    snap.me_x, snap.me_y = me.x, me.y
    return snap
  end
  local snap = app.net.snap
  if not snap or not app.net.pid then return nil end
  snap.me = app.net.pid
  local me = snap.players[snap.me]
  if app.net.predicted then
    snap.me_x, snap.me_y = app.net.predicted.x, app.net.predicted.y
  elseif me then
    snap.me_x, snap.me_y = me.x, me.y
  end
  return snap
end

local function process_cosmetics(view)
  local list = app.net.cosmetics
  if not view then
    for i = #list, 1, -1 do list[i] = nil end
    return
  end
  local function entity_pos(idnum)
    if idnum == 0 or idnum == 255 or idnum == "hogger" or idnum == "host" then
      return view.hogger.x, view.hogger.y
    end
    local p = view.players[tonumber(idnum)]
    if p then return p.x, p.y end
    return view.hogger.x, view.hogger.y
  end
  for _, e in ipairs(list) do
    if e.ev == "damage" then
      local tx, ty = entity_pos(e.dst)
      local own = tonumber(e.src) == view.me or tonumber(e.dst) == view.me
      local color = e.crit and { 1, 0.85, 0.2 } or { 1, 1, 1 }
      local txt = tostring(math.floor((e.val or 0) + 0.5))
      app.floating:add(txt, tx, ty, color, (e.crit or own) and 2 or 1)
      if e.crit and tonumber(e.dst) == view.me then app.render:add_shake(10) end
    elseif e.ev == "heal" then
      local tx, ty = entity_pos(e.dst)
      app.floating:add("+" .. tostring(math.floor((e.val or 0) + 0.5)),
        tx, ty, { 0.3, 0.95, 0.3 }, tonumber(e.dst) == view.me and 2 or 1)
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
    end
  end
  for i = #list, 1, -1 do list[i] = nil end
end

function love.update(dt)
  if app.headless then return end
  local inp, angle = local_input_frame()
  app.facing_angle = angle
  if app.auto and app.mode == "host" then
    inp = require("game.gamesim.bot").decide(app.net.state, app.net.local_pid)
  end
  if app.panel and app.panel.visible then
    inp = { mask = 0, facing = inp.facing } -- Panel schluckt die Eingabe
  end
  app.net:update(dt, inp)

  -- lokale Cooldown-Anzeige (nur Optik; Wahrheit liegt beim Host)
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

  -- Debug: Screenshot nach N Sekunden, dann beenden (--shot N)
  if app.shot_at then
    app.shot_at = app.shot_at - dt
    if app.shot_at <= 0 then
      app.shot_at = nil
      love.graphics.captureScreenshot("debug-shot.png")
      app.quit_next = 2 -- zwei Frames warten, bis der Shot geschrieben ist
    end
  elseif app.quit_next then
    app.quit_next = app.quit_next - 1
    if app.quit_next <= 0 then love.event.quit(0) end
  end
end

function love.draw()
  if app.headless then return end
  if not app.view then
    love.graphics.setColor(0.9, 0.88, 0.8, 1)
    love.graphics.print(app.net and app.net.failed or "Verbinde ...", 40, 40)
    return
  end
  local cds = {}
  for i = 1, 3 do
    cds[i] = app.cooldown_max[i] > 0
      and app.cooldown_view[i] / app.cooldown_max[i] or 0
  end
  local to_screen = app.render:draw(app.view, {
    facing_angle = app.facing_angle,
    cooldowns = cds,
  })
  app.floating:draw(to_screen)
  if app.panel then app.panel:draw() end
end

function love.keypressed(key)
  if app.headless then return end
  if app.panel and app.panel:keypressed(key) then return end
  if key == "f10" and app.panel then
    app.panel:toggle()
  elseif key == "kp+" or key == "+" then
    app.render:set_zoom(app.render.zoom - 1) -- reinzoomen = kleinerer Radius
    if app.net.send_zoom then app.net:send_zoom(app.render.zoom) end
  elseif key == "kp-" or key == "-" then
    app.render:set_zoom(app.render.zoom + 1)
    if app.net.send_zoom then app.net:send_zoom(app.render.zoom) end
  elseif key == "1" or key == "2" or key == "3" then
    local slot = tonumber(key)
    -- lokale Cooldown-Optik: GCD bzw. Raptor-CD
    local me = app.view and app.view.players[app.view.me]
    local cd = model.p("gcd")
    if me and me.class == "hunter" and slot == 1 then
      cd = model.p("hunter_raptor_cd")
    end
    app.cooldown_view[slot] = cd
    app.cooldown_max[slot] = cd
  elseif key == "tab" then
    -- Ziel: Hogger (M2 hat genau einen Feind)
    if app.mode == "host" then app.net:set_local_target(world.HOGGER_ID)
    else app.net:set_target(world.HOGGER_ID) end
  end
end

function love.wheelmoved(_, dy)
  if app.headless or not app.render then return end
  if dy > 0 then app.render:set_zoom(app.render.zoom - 1)
  elseif dy < 0 then app.render:set_zoom(app.render.zoom + 1) end
  if app.net and app.net.send_zoom then app.net:send_zoom(app.render.zoom) end
end

function love.mousepressed(mx, my)
  if app.headless or not app.view then return end
  -- Klick-Zielwahl: naechstes Spieler-Icon, sonst Hogger (ADR-002)
  local w, h = love.graphics.getDimensions()
  local radius = h / 2 - 8
  local scale = radius / app.render:zoom_radius()
  local function to_screen(wx, wy)
    return w / 2 + (wx - app.view.me_x) * scale,
           h / 2 + (wy - app.view.me_y) * scale
  end
  local best, best_d = nil, 24
  for pid, p in pairs(app.view.players) do
    if pid ~= app.view.me then
      local x, y = to_screen(p.x, p.y)
      local d = math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
      if d < best_d then best, best_d = pid, d end
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

function love.quit()
  if app.net and app.net.destroy then app.net:destroy() end
end
