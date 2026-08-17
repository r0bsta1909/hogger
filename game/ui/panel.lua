-- game/ui/panel.lua — Live-Tuning-Panel (GDD 17.6, F10, Host-only).
-- Generiert sich VOLLSTAENDIG aus M.params — keine Variable wird je von
-- Hand ins UI gebaut. Aenderungen wirken live und broadcasten an Clients.
-- Gehaltene Pfeiltasten wiederholen (Issue #81); der CSV-Export legt nur
-- die vom GDD-Stand abweichenden Werte in den Save-Ordner (Issue #82).
-- Steuerlogik ist love-frei (tests/unit_panel.lua); love nur in
-- update/draw/mousepressed-Randschicht.

local model = require("sim.model")

local P = {}
P.__index = P

-- Key-Repeat (Issue #81): erst kurze Verzoegerung, dann schnell
local REPEAT_DELAY = 0.35
local REPEAT_RATE = 0.045
local REPEAT_KEYS = { "down", "up", "pagedown", "pageup", "left", "right" }

local CSV_FILE = "tuning.csv"
P.CSV_FILE = CSV_FILE

function P.new(apply_fn)
  local self = setmetatable({}, P)
  self.visible = false
  self.apply = apply_fn  -- function(key, value) -> angewendeter Wert
  self.cursor = 1
  self.scroll = 0
  self.held = nil        -- gehaltene Repeat-Taste
  self.held_t = 0
  self.note = nil        -- Ergebniszeile des letzten Exports
  self.note_t = 0
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

-- love-frei: eine Navigations- oder Wertaktion ausfuehren (Tastendruck
-- UND Wiederholung laufen hier durch)
function P:action(key, shift)
  local n = #self.keys
  if key == "down" then self.cursor = math.min(n, self.cursor + 1)
  elseif key == "up" then self.cursor = math.max(1, self.cursor - 1)
  elseif key == "pagedown" then self.cursor = math.min(n, self.cursor + 12)
  elseif key == "pageup" then self.cursor = math.max(1, self.cursor - 12)
  elseif key == "left" or key == "right" then
    local k = self.keys[self.cursor]
    local e = model.params[k]
    local delta = (key == "right") and e.schritt or -e.schritt
    if shift then delta = delta * 10 end
    self.apply(k, e.wert + delta)
  else
    return false
  end
  return true
end

-- love-frei: Repeat-Uhr. held = gerade gehaltene Taste (oder nil);
-- Rueckgabe = Anzahl faelliger Wiederholungen in diesem Frame.
function P:repeat_step(held, dt)
  if held ~= self.held then
    self.held, self.held_t = held, 0
    return 0
  end
  if not held then return 0 end
  self.held_t = self.held_t + dt
  local fires = 0
  while self.held_t >= REPEAT_DELAY + REPEAT_RATE do
    self.held_t = self.held_t - REPEAT_RATE
    fires = fires + 1
  end
  return fires
end

-- love-frei: CSV nur mit den Abweichungen vom GDD-Stand (Issue #82).
-- Rueckgabe: Inhalt, Anzahl geaenderter Parameter.
function P:csv()
  local out = { "param;gdd_wert;wert" }
  for _, k in ipairs(self.keys) do
    local e = model.params[k]
    if e.wert ~= model.defaults[k] then
      out[#out + 1] = string.format("%s;%g;%g", k, model.defaults[k], e.wert)
    end
  end
  return table.concat(out, "\n") .. "\n", #out - 1
end

function P:keypressed(key)
  if not self.visible then return false end
  if key == "escape" or key == "f10" then
    self.visible = false
    return true
  end
  if key == "e" then
    self:export()
    return true
  end
  local shift = love.keyboard.isDown("lshift", "rshift")
  if self:action(key, shift) then return true end
  return false
end

-- Wiederholung fuer gehaltene Tasten (Issue #81): main ruft das pro Frame
function P:update(dt)
  if not self.visible then
    self:repeat_step(nil, 0)
    return
  end
  local held
  for _, k in ipairs(REPEAT_KEYS) do
    if love.keyboard.isDown(k) then held = k break end
  end
  local shift = love.keyboard.isDown("lshift", "rshift")
  for _ = 1, self:repeat_step(held, dt) do self:action(held, shift) end
  if self.note_t > 0 then self.note_t = self.note_t - dt end
end

-- CSV in den Save-Ordner schreiben (love.filesystem, CLAUDE.md) und den
-- vollen Pfad anzeigen — die Datei ist der Rueckkanal ins Tuning-Protokoll.
function P:export()
  local csv, n = self:csv()
  love.filesystem.write(CSV_FILE, csv)
  local path = love.filesystem.getSaveDirectory() .. "/" .. CSV_FILE
  if n == 0 then
    self.note = "Keine Abweichung vom GDD-Stand -- " .. path
  else
    self.note = string.format("%d Wert(e) -> %s", n, path)
  end
  self.note_t = 10
end

-- Panel- und Knopfgeometrie (auch fuer die Klickpruefung)
local function geom(w, h)
  local pw, ph = 560, h - 120
  return w - pw - 24, 60, pw, ph
end

local function export_rect(w, h)
  local px, py, pw = geom(w, h)
  return px + pw - 168, py + 6, 156, 20
end

local function inside(mx, my, x, y, rw, rh)
  return mx >= x and mx <= x + rw and my >= y and my <= y + rh
end

-- Klick auf den Export-Knopf; alle anderen Klicks im Panel werden
-- geschluckt, damit sie nicht in der Welt ein Ziel setzen
function P:mousepressed(mx, my)
  if not self.visible then return false end
  local w, h = love.graphics.getDimensions()
  if inside(mx, my, export_rect(w, h)) then
    self:export()
    return true
  end
  local px, py, pw, ph = geom(w, h)
  return inside(mx, my, px, py, pw, ph)
end

function P:draw()
  if not self.visible then return end
  local w, h = love.graphics.getDimensions()
  local px, py, pw, ph = geom(w, h)
  love.graphics.setColor(0.06, 0.07, 0.10, 0.92)
  love.graphics.rectangle("fill", px, py, pw, ph, 4, 4)
  love.graphics.setColor(0.78, 0.63, 0.28, 1)
  love.graphics.rectangle("line", px, py, pw, ph, 4, 4)
  love.graphics.print("TUNING (F10)  links/rechts aendern (halten wiederholt), Shift = x10",
    px + 12, py + 8)

  -- Export-Knopf oben rechts (Issue #82)
  local bx, by, bw, bh = export_rect(w, h)
  love.graphics.setColor(0.16, 0.20, 0.14, 1)
  love.graphics.rectangle("fill", bx, by, bw, bh, 3, 3)
  love.graphics.setColor(0.55, 0.70, 0.40, 1)
  love.graphics.rectangle("line", bx, by, bw, bh, 3, 3)
  love.graphics.print("[E] CSV-Export", bx + 10, by + 3)

  local font = love.graphics.getFont()
  local line_h = font:getHeight() + 4
  local top = py + 32
  local list_h = ph - 40 - (self.note_t > 0 and 22 or 0)
  local visible_rows = math.floor(list_h / line_h)
  if self.cursor - self.scroll > visible_rows then
    self.scroll = self.cursor - visible_rows
  elseif self.cursor <= self.scroll then
    self.scroll = self.cursor - 1
  end

  for row = 1, visible_rows do
    local i = row + self.scroll
    local k = self.keys[i]
    if not k then break end
    local e = model.params[k]
    local y = top + (row - 1) * line_h
    if i == self.cursor then
      love.graphics.setColor(0.78, 0.63, 0.28, 0.25)
      love.graphics.rectangle("fill", px + 6, y - 2, pw - 12, line_h)
    end
    love.graphics.setColor(0.55, 0.52, 0.45, 1)
    love.graphics.print(e.kapitel, px + 12, y)
    -- geaenderte Werte heben sich ab: gelber Schluessel, Stern
    local changed = e.wert ~= model.defaults[k]
    if changed then love.graphics.setColor(0.95, 0.85, 0.4, 1)
    else love.graphics.setColor(0.92, 0.89, 0.80, 1) end
    love.graphics.print(k .. (changed and " *" or ""), px + 64, y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(string.format("%g", e.wert), px + pw - 130, y, 118, "right")
  end

  -- Ergebniszeile des Exports (voller Pfad zum Zurueckspielen an Claude)
  if self.note_t > 0 and self.note then
    love.graphics.setColor(0.55, 0.70, 0.40, math.min(1, self.note_t))
    love.graphics.print(self.note, px + 12, py + ph - 22)
  end
end

return P
