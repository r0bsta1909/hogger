-- game/ui/panel.lua — Live-Tuning-Panel (GDD 17.6, F10, Host-only).
-- Generiert sich VOLLSTAENDIG aus M.params — keine Variable wird je von
-- Hand ins UI gebaut. Aenderungen wirken live und broadcasten an Clients.

local model = require("sim.model")

local P = {}
P.__index = P

function P.new(apply_fn)
  local self = setmetatable({}, P)
  self.visible = false
  self.apply = apply_fn  -- function(key, value) -> angewendeter Wert
  self.cursor = 1
  self.scroll = 0
  self.keys = {}
  local tmp = {}
  for k, e in pairs(model.params) do
    tmp[#tmp + 1] = { key = k, kapitel = e.kapitel }
  end
  table.sort(tmp, function(a, b)
    if a.kapitel ~= b.kapitel then return a.kapitel < b.kapitel end
    return a.key < b.key
  end)
  for i, e in ipairs(tmp) do self.keys[i] = e.key end
  return self
end

function P:toggle() self.visible = not self.visible end

function P:keypressed(key)
  if not self.visible then return false end
  local n = #self.keys
  if key == "down" then self.cursor = math.min(n, self.cursor + 1)
  elseif key == "up" then self.cursor = math.max(1, self.cursor - 1)
  elseif key == "pagedown" then self.cursor = math.min(n, self.cursor + 12)
  elseif key == "pageup" then self.cursor = math.max(1, self.cursor - 12)
  elseif key == "left" or key == "right" then
    local k = self.keys[self.cursor]
    local e = model.params[k]
    local delta = (key == "right") and e.schritt or -e.schritt
    if love.keyboard.isDown("lshift", "rshift") then delta = delta * 10 end
    self.apply(k, e.wert + delta)
  elseif key == "escape" or key == "f10" then
    self.visible = false
  else
    return false
  end
  return true
end

function P:draw()
  if not self.visible then return end
  local w, h = love.graphics.getDimensions()
  local pw, ph = 560, h - 120
  local px, py = w - pw - 24, 60
  love.graphics.setColor(0.06, 0.07, 0.10, 0.92)
  love.graphics.rectangle("fill", px, py, pw, ph, 4, 4)
  love.graphics.setColor(0.78, 0.63, 0.28, 1)
  love.graphics.rectangle("line", px, py, pw, ph, 4, 4)
  love.graphics.print("TUNING (F10)  links/rechts aendern, Shift = x10", px + 12, py + 8)

  local font = love.graphics.getFont()
  local line_h = font:getHeight() + 4
  local visible_rows = math.floor((ph - 40) / line_h)
  if self.cursor - self.scroll > visible_rows then
    self.scroll = self.cursor - visible_rows
  elseif self.cursor <= self.scroll then
    self.scroll = self.cursor - 1
  end

  local last_kapitel
  for row = 1, visible_rows do
    local i = row + self.scroll
    local k = self.keys[i]
    if not k then break end
    local e = model.params[k]
    local y = py + 32 + (row - 1) * line_h
    if i == self.cursor then
      love.graphics.setColor(0.78, 0.63, 0.28, 0.25)
      love.graphics.rectangle("fill", px + 6, y - 2, pw - 12, line_h)
    end
    love.graphics.setColor(0.55, 0.52, 0.45, 1)
    love.graphics.print(e.kapitel, px + 12, y)
    love.graphics.setColor(0.92, 0.89, 0.80, 1)
    love.graphics.print(k, px + 64, y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(string.format("%g", e.wert), px + pw - 130, y, 118, "right")
    last_kapitel = e.kapitel
  end
end

return P
