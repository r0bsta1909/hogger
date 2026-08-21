-- game/ui/victory.lua — der Auftakt des Fluchbruchs (GDD Kap. 11):
-- Hoggers Icon zerspringt, danach kurz das Loot-Fenster (Thunderfury-Gag +
-- Zerfledderter Wams). Mehr macht dieses Overlay nicht: Verschmelzung,
-- Monolog und Abgang spielen seit Runde 11 (#132) IN DER WELT und werden
-- von der Sim getaktet (won_stage im Snapshot), damit alle Rechner dieselben
-- Beats sehen. Rueckwaerts-Glitch, Login-Splash und die Knoepfe REVANCHE /
-- Ausloggen sind ersatzlos entfallen — nach dem Fluchbruch gibt es keinen
-- Weg zurueck ins Spiel.

local V = {}
V.__index = V

local SHATTER_T = 2.2
local LOOT_T = 6.5 -- zeitgesteuert: ein Klickzwang liesse die Runde driften
                   -- (Runde 18: 5,0 -> 6,5 s, das Fenster hat eine Zeile mehr)

-- Loot-Texte (GDD-Wortlaut bzw. Vorschlag)
local THUNDERFURY =
  "Thunderfury, Gesegnete Klinge des Windsuchers"
local THUNDERFURY_SUB = "Dropchance: 0,0000 %. Nicht gedroppt."
local WAMS = "Zerfledderter Wams  (2 Kupfer)"
-- Die Aufloesung (Runde 18): im Questfenster stand nur "???  (legendaer)".
-- Hier faellt die Pointe, und der Questtitel "Wenigstens haben wir..."
-- vervollstaendigt sich von selbst. Wortlaut: Rob, 2026-08-21.
local HUHN = "Kaltes, angebissenes Huehnchen"
local HUHN_SUB = "\"Schmeckt nach Reue und Wipe\""
V.HUHN, V.HUHN_SUB = HUHN, HUHN_SUB

function V.new(board)
  local self = setmetatable({}, V)
  self.board = board
  self.state = "shatter" -- shatter | loot | done
  self.t = 0
  -- Scherben deterministisch (rein kosmetisch, kein RNG-Kanal)
  self.frags = {}
  for i = 1, 14 do
    local ang = i * (2 * math.pi / 14) + i * 0.7
    self.frags[i] = { ang = ang, speed = 130 + (i * 37) % 90,
                      spin = ((i % 5) - 2) * 3 }
  end
  return self
end

function V:update(dt)
  self.t = self.t + dt
  if self.state == "shatter" and self.t >= SHATTER_T then
    self.state, self.t = "loot", 0
  elseif self.state == "loot" and self.t >= LOOT_T then
    self.state, self.t = "done", 0
  end
end

-- true, solange das Overlay noch etwas zu sagen hat
function V:active()
  return self.state ~= "done"
end

function V:mousepressed()
  if self.state == "loot" then self.state, self.t = "done", 0 end
  return true -- die Sequenz schluckt Klicks (die Welt steht ohnehin)
end

function V:keypressed(key)
  if key == "return" or key == "space" then self:mousepressed() end
  return true
end

-- ---------------------------------------------------------------------------
local function draw_loot(self, w, h)
  -- Runde 18: 170 -> 236 px, das Huehnchen braucht seine eigenen Zeilen
  local pw, ph = 480, 236
  local px, py = (w - pw) / 2, h / 2 - 150
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
  -- Die Questbelohnung: die legendaere Zeile, die im Questfenster nur
  -- "???" hiess. Legendaeres Orange wie Thunderfury — der Witz ist, dass
  -- sie es tatsaechlich ernst meint.
  love.graphics.setColor(0.38, 0.33, 0.24, 1)
  love.graphics.line(px + 16, py + 142, px + pw - 16, py + 142)
  love.graphics.setColor(0.75, 0.72, 0.62, 1)
  love.graphics.print("Questbelohnung: Wenigstens haben wir...",
    px + 16, py + 152)
  love.graphics.setColor(1.0, 0.5, 0.1, 1)
  love.graphics.print(HUHN, px + 16, py + 178)
  love.graphics.setColor(0.62, 0.60, 0.52, 1)
  love.graphics.print(HUHN_SUB, px + 16, py + 198)
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
  end
end

return V
