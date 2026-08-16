-- game/ui/dialog.lua — authentischer WoW-Disconnect-Dialog (GDD Kap. 3):
-- "Vom Server getrennt." mit OK-Button; danach zurueck zum Glitch-Schwarz
-- und automatischer Reconnect. Fehlerbehandlung als Fiktion recycelt.

local D = {}
D.__index = D

function D.new(text)
  return setmetatable({ text = text or "Vom Server getrennt.", visible = true }, D)
end

local function button_rect(w, h)
  local bw, bh = 110, 30
  return (w - bw) / 2, h / 2 + 26, bw, bh
end

-- true = OK gedrueckt (Dialog schliessen, Reconnect starten)
function D:keypressed(key)
  if key == "return" or key == "escape" or key == "space" then
    self.visible = false
    return true
  end
  return false
end

function D:mousepressed(mx, my)
  local w, h = love.graphics.getDimensions()
  local bx, by, bw, bh = button_rect(w, h)
  if mx >= bx and mx <= bx + bw and my >= by and my <= by + bh then
    self.visible = false
    return true
  end
  return false
end

function D:draw()
  local w, h = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", 0, 0, w, h)
  local pw, ph = 360, 120
  local px, py = (w - pw) / 2, h / 2 - 60
  love.graphics.setColor(0.08, 0.08, 0.12, 0.97)
  love.graphics.rectangle("fill", px, py, pw, ph, 5, 5)
  love.graphics.setColor(0.78, 0.63, 0.28, 1)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", px, py, pw, ph, 5, 5)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.95, 0.92, 0.8, 1)
  local font = love.graphics.getFont()
  love.graphics.print(self.text, w / 2 - font:getWidth(self.text) / 2, py + 26)
  local bx, by, bw, bh = button_rect(w, h)
  love.graphics.setColor(0.16, 0.14, 0.10, 1)
  love.graphics.rectangle("fill", bx, by, bw, bh, 4, 4)
  love.graphics.setColor(0.78, 0.63, 0.28, 1)
  love.graphics.rectangle("line", bx, by, bw, bh, 4, 4)
  love.graphics.setColor(0.95, 0.92, 0.8, 1)
  love.graphics.print("Okay", bx + bw / 2 - font:getWidth("Okay") / 2, by + 7)
end

return D
