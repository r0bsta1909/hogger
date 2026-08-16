-- game/ui/victory.lua — Fluchbruch-Sequenz (GDD Kap. 11): Hoggers Icon
-- zerspringt, Loot-Fenster (Thunderfury-Gag + Zerfledderter Wams), der
-- Glitch laeuft rueckwaerts, kurz der echte Login-Screen ("Du kannst dich
-- jetzt ausloggen."), dann die finale Statistik-Tafel mit REVANCHE-Knopf.
-- Die Sim steht waehrenddessen (phase "won"), bis REVANCHE den naechsten
-- Abend-Durchlauf startet (Try-Zaehler bei 1).

local assets = require("game.assets")
local stats = require("game.ui.stats")

local V = {}
V.__index = V

local SHATTER_T = 2.2
local LOOT_MIN_T = 1.2
local UNGLITCH_T = 2.2
local LOGIN_T = 3.0

-- Loot-Texte (GDD-Wortlaut bzw. Vorschlag)
local THUNDERFURY =
  "Thunderfury, Gesegnete Klinge des Windsuchers"
local THUNDERFURY_SUB = "Dropchance: 0,0000 %. Nicht gedroppt."
local WAMS = "Zerfledderter Wams  (2 Kupfer)"

function V.new(board)
  local self = setmetatable({}, V)
  self.board = board
  self.state = "shatter" -- shatter | loot | unglitch | login | board
  self.t = 0
  self.panel = nil
  -- Scherben deterministisch (rein kosmetisch, kein RNG-Kanal)
  self.frags = {}
  for i = 1, 14 do
    local ang = i * (2 * math.pi / 14) + i * 0.7
    self.frags[i] = { ang = ang, speed = 130 + (i * 37) % 90,
                      spin = ((i % 5) - 2) * 3 }
  end
  return self
end

local function enter(self, state)
  self.state = state
  self.t = 0
end

function V:update(dt)
  self.t = self.t + dt
  if self.state == "shatter" and self.t >= SHATTER_T then
    enter(self, "loot")
  elseif self.state == "unglitch" and self.t >= UNGLITCH_T then
    enter(self, "login")
  elseif self.state == "login" and self.t >= LOGIN_T then
    enter(self, "board")
    self.panel = stats.new(self.board, { sticky = true, button = "REVANCHE" })
  end
  if self.panel then self.panel:update(dt) end
end

-- Rueckgabe "revanche", wenn der Knopf der finalen Tafel gedrueckt wurde
function V:mousepressed(mx, my)
  if self.state == "loot" and self.t >= LOOT_MIN_T then
    enter(self, "unglitch")
    return true
  elseif self.state == "board" and self.panel then
    if self.panel:mousepressed(mx, my) == "button" then return "revanche" end
    return true
  end
  return true -- Sequenz schluckt Klicks (die Welt steht ohnehin)
end

function V:keypressed(key)
  if key == "return" or key == "space" then
    local r = self:mousepressed(-1, -1)
    return r == true
  end
  return true
end

-- ---------------------------------------------------------------------------
local function draw_loot(self, w, h)
  local pw, ph = 480, 170
  local px, py = (w - pw) / 2, h / 2 - 120
  love.graphics.setColor(0.07, 0.07, 0.11, 0.96)
  love.graphics.rectangle("fill", px, py, pw, ph, 5, 5)
  love.graphics.setColor(0.78, 0.63, 0.28, 1)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", px, py, pw, ph, 5, 5)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.95, 0.85, 0.4, 1)
  love.graphics.print("Beute", px + 16, py + 10)
  -- Thunderfury: legendaeres Orange, der Gag ist die Dropchance (GDD 11)
  love.graphics.setColor(1.0, 0.5, 0.1, 1)
  love.graphics.printf(THUNDERFURY, px + 16, py + 38, pw - 32)
  love.graphics.setColor(0.75, 0.72, 0.62, 1)
  love.graphics.print(THUNDERFURY_SUB, px + 16, py + 58)
  -- Zerfledderter Wams: grau, aber immerhin gedroppt
  love.graphics.setColor(0.62, 0.62, 0.62, 1)
  love.graphics.print(WAMS, px + 16, py + 92)
  if self.board.wams then
    love.graphics.setColor(0.85, 0.75, 0.5, 1)
    love.graphics.print(self.board.wams, px + 16, py + 112)
  end
  love.graphics.setColor(0.6, 0.56, 0.45, 0.6 + 0.3 * math.sin(self.t * 3))
  love.graphics.print("(klicken)", px + pw - 76, py + ph - 22)
end

local function draw_unglitch(self, w, h)
  -- der Glitch laeuft rueckwaerts: die Minimap zerreisst (GDD 11)
  local k = math.min(1, self.t / UNGLITCH_T)
  local rnd = love.math.random
  local bands = 14
  local band_h = h / bands
  for i = 0, bands - 1 do
    if rnd() < k then
      local off = (rnd() - 0.5) * 160 * k
      love.graphics.setColor(0, 0, 0, 0.55 * k)
      love.graphics.rectangle("fill", off, i * band_h, w, band_h)
    end
  end
  love.graphics.setColor(0, 0, 0, 0.35)
  for y = 0, h, 3 do
    love.graphics.rectangle("fill", 0, y, w, 1)
  end
  love.graphics.setColor(1, 1, 1, 0.3 * k)
  for _ = 1, 260 do
    love.graphics.rectangle("fill", rnd() * w, rnd() * h, rnd() * 3 + 1, 1)
  end
  love.graphics.setColor(0, 0, 0, k * k)
  love.graphics.rectangle("fill", 0, 0, w, h)
end

local function draw_login(self, w, h)
  local img = assets.get("splash_login")
  local iw, ih = img:getDimensions()
  local scale = math.max(w / iw, h / ih)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, w / 2, h / 2, 0, scale, scale, iw / 2, ih / 2)
  local line = "Du kannst dich jetzt ausloggen."
  local font = love.graphics.getFont()
  love.graphics.setColor(0.92, 0.89, 0.78, math.min(1, self.t / 0.8))
  love.graphics.print(line, w / 2 - font:getWidth(line), h * 0.62, 0, 2, 2)
end

function V:draw(view, to_screen, w, h)
  if self.state == "shatter" then
    -- Hoggers Icon zerspringt (GDD 11): Scherben fliegen, Icon verblasst
    local hx, hy = to_screen(view.hogger.x, view.hogger.y)
    local k = self.t / SHATTER_T
    for _, f in ipairs(self.frags) do
      local d = f.speed * self.t
      local x, y = hx + math.cos(f.ang) * d, hy + math.sin(f.ang) * d
      love.graphics.push()
      love.graphics.translate(x, y)
      love.graphics.rotate(f.ang + self.t * f.spin)
      love.graphics.setColor(0.85, 0.25, 0.20, 1 - k)
      love.graphics.polygon("fill", 0, -8, 7, 6, -7, 6)
      love.graphics.pop()
    end
    love.graphics.setColor(1, 0.95, 0.7, (1 - k) * 0.35)
    love.graphics.circle("fill", hx, hy, 30 + k * 90)
  elseif self.state == "loot" then
    draw_loot(self, w, h)
  elseif self.state == "unglitch" then
    draw_unglitch(self, w, h)
  elseif self.state == "login" then
    draw_login(self, w, h)
  elseif self.state == "board" and self.panel then
    draw_login(self, w, h) -- die Tafel liegt ueber dem Login-Screen
    self.panel:draw()
  end
end

return V
