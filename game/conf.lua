-- game/conf.lua — LOEVE 11.5 gepinnt, ungenutzte Module abgeschaltet
-- (GDD Kap. 14 / Skill Par. 7). --headless (Stufe-4-Tests) laeuft fensterlos.

function love.conf(t)
  t.version = "11.5"
  t.identity = "hogger"
  t.console = false

  local headless = false
  for _, a in ipairs(arg or {}) do
    if a == "--headless" then headless = true end
  end

  if headless then
    t.window = nil
    t.modules.window = false
    t.modules.graphics = false
  else
    t.window.title = "World of Warcraft" -- die Fiktion beginnt beim Fenstertitel
    t.window.width = 1280
    t.window.height = 800
    t.window.resizable = true
    t.window.vsync = 1
  end

  t.modules.physics = false
  t.modules.video = false
  t.modules.touch = false
  t.modules.joystick = false
  t.modules.thread = false
  t.modules.audio = true   -- Sounds ab M4; Modul bleibt an (Blips folgen)
  t.modules.sound = true
end
