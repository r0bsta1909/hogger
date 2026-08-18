-- game/ui/panel.lua — Live-Tuning-Panel (GDD 17.6, F10, Host-only).
-- Generiert sich VOLLSTAENDIG aus M.params — keine Variable wird je von
-- Hand ins UI gebaut. Aenderungen wirken live und broadcasten an Clients.
-- Seit Runde 6 (#97) zweistufig: Einstieg auf einer groben Kategorienliste
-- (Hogger, Spieler, Klassen, ...), Enter/Rechts oeffnet die Kategorie,
-- Backspace fuehrt zurueck. Die Zuordnung ist ABSCHLIESSEND — jeder
-- Parameter gehoert genau einer Kategorie an (tests/unit_panel.lua).
-- Gehaltene Pfeiltasten wiederholen (#81); der CSV-Export legt nur die
-- vom GDD-Stand abweichenden Werte in den Save-Ordner (#82).
-- Steuerlogik ist love-frei; love nur in update/draw/mousepressed.

local model = require("sim.model")
local docs = require("sim.param_docs")
local tooltip = require("game.ui.tooltip")

local P = {}
P.__index = P

-- Key-Repeat (Issue #81): erst kurze Verzoegerung, dann schnell
local REPEAT_DELAY = 0.35
local REPEAT_RATE = 0.045
local REPEAT_KEYS = { "down", "up", "pagedown", "pageup", "left", "right" }

-- Hover-Erklaerung (Runde 9, #119): wer eine Sekunde auf einer Zeile
-- verweilt, bekommt Beschreibung und Wirkungsrichtung
local HOVER_DELAY = 1.0
P.HOVER_DELAY = HOVER_DELAY

local CSV_FILE = "tuning.csv"
P.CSV_FILE = CSV_FILE

-- ---------------------------------------------------------------------------
-- Kategorien (Runde 6, #97): grob und intuitiv, KEINE Unterkategorien.
-- Zuordnung: erst Einzel-Ausnahmen (der Loop schneidet quer durch die
-- GDD-Kapitel), dann die Kapitel-Map. Ein Parameter ohne Treffer landet in
-- "sonstiges" — und unit_panel laesst die Suite rot werden, wenn das je
-- passiert: die Liste bleibt abschliessend.
-- ---------------------------------------------------------------------------
local KAT_ORDER = { "hogger", "spieler", "klassen", "mobs", "loop",
                    "krits", "leeroy", "ui", "sim", "sonstiges" }
local KAT_NAME = {
  hogger = "Hogger (Kampf, Fressen, Adds)",
  spieler = "Spieler (Basiswerte, Reichweiten)",
  klassen = "Klassen (Faehigkeiten)",
  mobs = "Mobs & Loot",
  loop = "Loop & Todesstrafe",
  krits = "Krits",
  leeroy = "Leeroy & Echo",
  ui = "UI & Kamera",
  sim = "Sim-Modell (nur Headless)",
  sonstiges = "Sonstiges",
}
P.KAT_ORDER, P.KAT_NAME = KAT_ORDER, KAT_NAME

-- Kategorie-Erklaerung fuer den Hover auf der Einstiegsebene (Runde 9)
local KAT_DESC = {
  hogger = "Alles am Boss: Schaden, Tempo, Fressen, Leash, Adds, HP-Formel.",
  spieler = "Was fuer jede Klasse gilt: Tempo, Reichweiten, HP, Ressourcen.",
  klassen = "Die Faehigkeiten der acht Klassen: Schaden, Kosten, Zauberzeit.",
  mobs = "Ambient-Mobs am Wegesrand plus Erfahrung und Plunder.",
  loop = "Der Rhythmus des Abends: Trylaenge, Todesstrafe, Laufwege.",
  krits = "Der einzige Zufall im Spiel: Kritchance und Multiplikator.",
  leeroy = "Der Raid-Leeroy und das Echo am Friedhof.",
  ui = "Kamera und Anzeige: Zoomstufen, Erfahrungsbalken.",
  sim = "Nur fuer die Headless-Sim: Agentenverhalten beim Balancing.",
  sonstiges = "Ohne Kategorie -- hier sollte nie etwas stehen.",
}
P.KAT_DESC = KAT_DESC

local KAT_BY_KEY = {
  try_time_limit = "loop", release_grace = "loop", revive_channel = "loop",
  graveyard_to_field_dist = "loop", field_to_hill_dist = "loop",
}
local KAT_BY_KAPITEL = {
  ["9.1"] = "hogger", ["9.2"] = "hogger", ["9.3"] = "hogger",
  ["8.1"] = "spieler", ["9.4"] = "spieler",
  ["8.2"] = "klassen",
  ["7.2"] = "mobs", ["7.3"] = "mobs",
  ["6"] = "loop", ["7.1"] = "loop", ["5"] = "loop", ["11"] = "loop",
  ["10"] = "leeroy", ["10.3"] = "leeroy",
  ["4.1"] = "ui", ["4.2"] = "ui",
  ["13.2"] = "krits",
  ["17.2"] = "sim",
}

function P.category_of(key, kapitel)
  if key:sub(1, 8) == "respawn_" then return "loop" end
  return KAT_BY_KEY[key] or KAT_BY_KAPITEL[kapitel] or "sonstiges"
end

function P.new(apply_fn)
  local self = setmetatable({}, P)
  self.visible = false
  self.apply = apply_fn  -- function(key, value) -> angewendeter Wert
  self.mode = "kats"     -- kats | params
  self.kat_cursor = 1
  self.cursors = {}      -- Merkposten je Kategorie
  self.scroll = 0
  self.held = nil        -- gehaltene Repeat-Taste
  self.held_t = 0
  self.note = nil        -- Ergebniszeile des letzten Exports
  self.note_t = 0
  -- alle Schluessel (fuer den CSV-Export) und je Kategorie sortiert
  self.keys = {}
  self.by_kat = {}
  for _, k in ipairs(KAT_ORDER) do self.by_kat[k] = {} end
  local tmp = {}
  for k, e in pairs(model.params) do
    tmp[#tmp + 1] = { key = k, kapitel = e.kapitel }
  end
  table.sort(tmp, function(a, b)
    if a.kapitel ~= b.kapitel then return a.kapitel < b.kapitel end
    return a.key < b.key
  end)
  for i, e in ipairs(tmp) do
    self.keys[i] = e.key
    local kat = P.category_of(e.key, e.kapitel)
    local list = self.by_kat[kat]
    list[#list + 1] = e.key
  end
  -- Kategorien in fester Reihenfolge, leere fallen weg
  self.kats = {}
  for _, k in ipairs(KAT_ORDER) do
    if #self.by_kat[k] > 0 then self.kats[#self.kats + 1] = k end
  end
  return self
end

function P:toggle()
  self.visible = not self.visible
  if self.visible then self.mode = "kats" end
end

function P:current_kat()
  return self.kats[self.kat_cursor]
end

function P:changed_in(kat)
  local n = 0
  for _, k in ipairs(self.by_kat[kat]) do
    if model.params[k].wert ~= model.defaults[k] then n = n + 1 end
  end
  return n
end

-- love-frei: eine Navigations- oder Wertaktion ausfuehren (Tastendruck
-- UND Wiederholung laufen hier durch)
function P:action(key, shift)
  if self.mode == "kats" then
    local n = #self.kats
    if key == "down" then self.kat_cursor = math.min(n, self.kat_cursor + 1)
    elseif key == "up" then self.kat_cursor = math.max(1, self.kat_cursor - 1)
    elseif key == "right" or key == "return" or key == "kpenter" then
      self.mode = "params"
      self.scroll = 0
    else
      return false
    end
    return true
  end
  local list = self.by_kat[self:current_kat()]
  local n = #list
  local cur = self.cursors[self:current_kat()] or 1
  if key == "down" then cur = math.min(n, cur + 1)
  elseif key == "up" then cur = math.max(1, cur - 1)
  elseif key == "pagedown" then cur = math.min(n, cur + 12)
  elseif key == "pageup" then cur = math.max(1, cur - 12)
  elseif key == "left" or key == "right" then
    local k = list[cur]
    local e = model.params[k]
    local delta = (key == "right") and e.schritt or -e.schritt
    if shift then delta = delta * 10 end
    self.apply(k, e.wert + delta)
  elseif key == "backspace" then
    self.mode = "kats"
    self.scroll = 0
    return true
  else
    return false
  end
  self.cursors[self:current_kat()] = cur
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

-- love-frei: CSV nur mit den Abweichungen vom GDD-Stand (Issue #82) —
-- ueber ALLE Kategorien hinweg.
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
-- mit der Mausposition (fuer die Hover-Uhr, Runde 9)
function P:update(dt, mx, my)
  if not self.visible then
    self:repeat_step(nil, 0)
    self:hover_step(nil, 0)
    return
  end
  if mx then
    local w, h = love.graphics.getDimensions()
    local line_h = love.graphics.getFont():getHeight() + 4
    self.hover_mx, self.hover_my = mx, my
    self.hover_show = self:hover_step(self:row_at(mx, my, w, h, line_h), dt)
  else
    self.hover_show = false
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

-- Welche Listenzeile liegt unter der Maus? Reine Arithmetik (love-frei,
-- getestet); line_h kommt vom Aufrufer, damit die Schriftgroesse nicht
-- hier hineinragt. Rueckgabe: Key bzw. Kategorie-Id, sonst nil.
function P:row_at(mx, my, w, h, line_h)
  local px, py, pw, ph = geom(w, h)
  if mx < px or mx > px + pw then return nil end
  local top = py + 32
  if my < top or my > py + ph - 40 then return nil end -- Titel/Fusszeile
  if self.mode == "kats" then
    local i = math.floor((my - top) / (line_h + 6)) + 1
    return self.kats[i]
  end
  local list = self.by_kat[self:current_kat()]
  local visible_rows = math.floor((ph - 40 - 22) / line_h)
  local row = math.floor((my - top) / line_h) + 1
  if row < 1 or row > visible_rows then return nil end
  return list[row + self.scroll]
end

-- Hover-Uhr (Muster repeat_step, love-frei): true, sobald faellig
function P:hover_step(key, dt)
  if key == nil or key ~= self.hover_key then
    self.hover_key = key
    self.hover_t = 0
    return false
  end
  self.hover_t = (self.hover_t or 0) + dt
  return self.hover_t >= HOVER_DELAY
end

-- Tooltip-Zeilen: Live-Wert oben (gold), dann Beschreibung, Wirkung,
-- Stellbereich. Zahlen kommen IMMER aus model.params, nie aus dem Text.
function P:tooltip_lines(key)
  if not key then return nil end
  local e = model.params[key]
  if not e then -- Kategorienebene
    local d = KAT_DESC[key]
    if not d then return nil end
    return { KAT_NAME[key] or key, d,
             string.format("%d Werte", #(self.by_kat[key] or {})) }
  end
  local d = docs[key] or { "(keine Beschreibung)", "" }
  return {
    string.format("%s = %g", key, e.wert),
    d[1], d[2],
    string.format("Kapitel %s   Bereich %g..%g   Schritt %g",
      e.kapitel, e.min, e.max, e.schritt),
  }
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
  local title = self.mode == "kats"
    and "TUNING (F10)  Enter oeffnet"
    or ("TUNING > " .. (KAT_NAME[self:current_kat()] or "?"))
  love.graphics.print(title, px + 12, py + 8)

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

  if self.mode == "kats" then
    -- Kategorienliste: Name, Parameterzahl, Zahl der Abweichungen
    for i, kat in ipairs(self.kats) do
      local y = top + (i - 1) * (line_h + 6)
      if i == self.kat_cursor then
        love.graphics.setColor(0.78, 0.63, 0.28, 0.25)
        love.graphics.rectangle("fill", px + 6, y - 2, pw - 12, line_h + 4)
      end
      love.graphics.setColor(0.92, 0.89, 0.80, 1)
      love.graphics.print(KAT_NAME[kat], px + 16, y)
      local changed = self:changed_in(kat)
      local info = string.format("%d Werte", #self.by_kat[kat])
      if changed > 0 then info = info .. string.format("   %d *", changed) end
      love.graphics.setColor(changed > 0 and 0.95 or 0.55,
        changed > 0 and 0.85 or 0.52, changed > 0 and 0.4 or 0.45, 1)
      love.graphics.printf(info, px + pw - 190, y, 178, "right")
    end
    love.graphics.setColor(0.45, 0.42, 0.35, 1)
    love.graphics.print("Hoch/Runter waehlen, Enter/Rechts oeffnen, E = CSV",
      px + 12, py + ph - 22)
  else
    local kat = self:current_kat()
    local list = self.by_kat[kat]
    local cursor = self.cursors[kat] or 1
    local list_h = ph - 40 - 22
    local visible_rows = math.floor(list_h / line_h)
    if cursor - self.scroll > visible_rows then
      self.scroll = cursor - visible_rows
    elseif cursor <= self.scroll then
      self.scroll = cursor - 1
    end
    for row = 1, visible_rows do
      local i = row + self.scroll
      local k = list[i]
      if not k then break end
      local e = model.params[k]
      local y = top + (row - 1) * line_h
      if i == cursor then
        love.graphics.setColor(0.78, 0.63, 0.28, 0.25)
        love.graphics.rectangle("fill", px + 6, y - 2, pw - 12, line_h)
      end
      love.graphics.setColor(0.55, 0.52, 0.45, 1)
      love.graphics.print(e.kapitel, px + 12, y)
      local changed = e.wert ~= model.defaults[k]
      if changed then love.graphics.setColor(0.95, 0.85, 0.4, 1)
      else love.graphics.setColor(0.92, 0.89, 0.80, 1) end
      love.graphics.print(k .. (changed and " *" or ""), px + 64, y)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.printf(string.format("%g", e.wert), px + pw - 130, y, 118, "right")
    end
    love.graphics.setColor(0.45, 0.42, 0.35, 1)
    love.graphics.print("links/rechts aendern (halten wiederholt), Shift = x10, Backspace zurueck",
      px + 12, py + ph - 22)
  end

  -- Ergebniszeile des Exports (voller Pfad zum Zurueckspielen an Claude)
  if self.note_t > 0 and self.note then
    love.graphics.setColor(0.55, 0.70, 0.40, math.min(1, self.note_t))
    love.graphics.print(self.note, px + 12, py + ph - 40)
  end

  -- Erklaerung nach einer Sekunde Verweilen (Runde 9, #119)
  if self.hover_show and self.hover_key then
    local lines = self:tooltip_lines(self.hover_key)
    if lines then
      tooltip.draw(lines, self.hover_mx, self.hover_my, w, h)
    end
  end
end

return P
