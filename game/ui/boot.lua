-- game/ui/boot.lua — Boot-Sequenz "Der falsche Client" (GDD Kap. 3).
-- Ablauf: Vanilla-Splash (+ Login-Musik-Anriss ab Sound-PR) -> optional
-- Warteschlangen-Gag (1x pro Client pro Abend) -> Glitch (Scanlines,
-- Versatz, Static) -> Schwarz -> langsame Aufblende in die Totensicht.
-- Waehrend Schritt 1-3 laeuft die Discovery unsichtbar dahinter; schlaegt
-- sie fehl, erscheint im Glitch-Bild die als Fehlerkonsole getarnte Zeile
-- "Realm nicht gefunden — IP:" (der Fallback bleibt in der Fiktion).
-- Ab dem zweiten Start pro Rechner per Klick ueberspringbar bis Glitch-Ende.
-- Gesamtdauer <= 20 s; reine Praesentation, kein Spielzustand.

local assets = require("game.assets")

local B = {}
B.__index = B

local SEEN_FILE = "boot_seen.dat"
local QUEUE_FILE = "boot_queue.dat"

-- Phasen und Dauern (Praesentations-Timing, kein Balancing)
local SPLASH_T = 6.0
local QUEUE_T = 1.5
local GLITCH_T = 1.6
local BLACK_T = 2.5
local FADE_T = 4.0

-- Lade-Zeilen der Fiktion (Vorschlagstexte); die Firewall-Zeile ist der
-- getarnte Pflicht-Hinweis fuer Windows (GDD Kap. 14, Cross-Platform)
local LOAD_LINES = {
  "Verbindung zum Realm wird hergestellt ...",
  "Authentifiziere ...",
  "Charakterliste wird abgerufen ...",
}
local FIREWALL_LINE =
  "Hinweis: Windows fragt gleich nach Netzwerk-Freigabe -- 'Privates Netzwerk' erlauben."

function B.new()
  local self = setmetatable({}, B)
  self.t = 0
  self.phase = "splash" -- splash | queue | glitch | black | fade | done
  self.skippable = love.filesystem.getInfo(SEEN_FILE) ~= nil
  love.filesystem.write(SEEN_FILE, "1")
  -- Warteschlangen-Gag: einmal pro Client pro Abend (GDD Kap. 3, Schritt 2)
  local today = os.date("%Y-%m-%d")
  self.show_queue = love.filesystem.read(QUEUE_FILE) ~= today
  if self.show_queue then love.filesystem.write(QUEUE_FILE, today) end
  self.ip_visible = false  -- getarnte Konsole (setzt main nach 5 s Discovery)
  self.ip_input = ""
  self.is_windows = love.system and love.system.getOS() == "Windows"
  return self
end

function B:active()
  return self.phase ~= "done"
end

-- solange true, ist die Spielsicht komplett verdeckt
function B:covers_screen()
  return self.phase == "splash" or self.phase == "queue"
      or self.phase == "glitch" or self.phase == "black"
end

local function enter(self, phase)
  self.phase = phase
  self.t = 0
end

function B:update(dt)
  self.t = self.t + dt
  if self.phase == "splash" and self.t >= SPLASH_T then
    enter(self, self.show_queue and "queue" or "glitch")
  elseif self.phase == "queue" and self.t >= QUEUE_T then
    enter(self, "glitch")
  elseif self.phase == "glitch" and self.t >= GLITCH_T then
    enter(self, "black")
  elseif self.phase == "black" and self.t >= BLACK_T then
    enter(self, "fade")
  elseif self.phase == "fade" and self.t >= FADE_T then
    enter(self, "done")
  end
end

-- Klick: ab dem zweiten Start ueberspringbar bis zum Glitch-Ende (GDD 3)
function B:mousepressed()
  if not self.skippable then return end
  if self.phase == "splash" or self.phase == "queue" or self.phase == "glitch" then
    enter(self, "black")
    self.t = BLACK_T - 0.4 -- kurzes Schwarz, dann Aufblende
  end
end

-- Wiedereintritt nach Disconnect: zurueck zum Glitch-Schwarz (GDD Kap. 3)
function B:reenter()
  enter(self, "black")
  self.t = BLACK_T - 1.0
end

-- IP-Fallback-Konsole: Eingabe wie im Debug-Overlay, Enter -> {join=ip}
function B:keypressed(key)
  if not self.ip_visible then return nil end
  if key == "backspace" then
    self.ip_input = self.ip_input:sub(1, -2)
    return true
  elseif key == "return" and #self.ip_input >= 7 then
    local ip = self.ip_input
    self.ip_input = ""
    return { join = ip }
  end
  return nil
end

function B:textinput(t)
  if not self.ip_visible then return false end
  if t:match("^[%d%.]$") and #self.ip_input < 15 then
    self.ip_input = self.ip_input .. t
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Zeichnen
-- ---------------------------------------------------------------------------
local function draw_console_line(self, w, h)
  if not self.ip_visible then return end
  love.graphics.setColor(0.55, 0.6, 0.55, 0.85)
  love.graphics.print("ERR_REALM_LIST: Realm nicht gefunden -- IP: "
    .. self.ip_input .. "_", 24, h - 40)
end

local function draw_splash(self, w, h)
  -- Splash-Asset (Platzhalter oder finale Datei) bildschirmfuellend
  local img = assets.get("splash_login")
  local iw, ih = img:getDimensions()
  local scale = math.max(w / iw, h / ih)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, w / 2, h / 2, 0, scale, scale, iw / 2, ih / 2)
  -- Lade-Zeilen unten links, Konsolen-Stil
  local li = math.min(#LOAD_LINES, 1 + math.floor(self.t / 1.6))
  local y = h - 96
  for i = 1, li do
    love.graphics.setColor(0.8, 0.78, 0.6, 0.9)
    love.graphics.print(LOAD_LINES[i], 24, y)
    y = y + 18
  end
  if self.is_windows then
    love.graphics.setColor(0.6, 0.58, 0.45, 0.9)
    love.graphics.print(FIREWALL_LINE, 24, h - 24)
  end
  if self.skippable then
    love.graphics.setColor(0.5, 0.48, 0.4, 0.5 + 0.3 * math.sin(self.t * 3))
    love.graphics.print("Klick zum Ueberspringen", w - 190, h - 24)
  end
end

local function draw_queue(self, w, h)
  love.graphics.setColor(0.04, 0.05, 0.10, 1)
  love.graphics.rectangle("fill", 0, 0, w, h)
  local panel_w, panel_h = 460, 90
  local px, py = (w - panel_w) / 2, (h - panel_h) / 2
  love.graphics.setColor(0.10, 0.11, 0.16, 1)
  love.graphics.rectangle("fill", px, py, panel_w, panel_h, 4, 4)
  love.graphics.setColor(0.78, 0.63, 0.28, 1)
  love.graphics.rectangle("line", px, py, panel_w, panel_h, 4, 4)
  love.graphics.setColor(0.92, 0.89, 0.78, 1)
  love.graphics.print("Position in der Warteschlange: 1", px + 24, py + 22)
  love.graphics.print("Geschaetzte Wartezeit: 4 Stunden", px + 24, py + 46)
end

local function draw_glitch(self, w, h)
  -- Bild zerreisst: horizontale Versatz-Baender + Scanlines + Static
  local img = assets.get("splash_login")
  local iw, ih = img:getDimensions()
  local scale = math.max(w / iw, h / ih)
  local rnd = love.math.random
  local bands = 14
  local band_h = h / bands
  local violence = math.min(1, self.t / (GLITCH_T * 0.6)) -- eskaliert
  for i = 0, bands - 1 do
    local off = (rnd() - 0.5) * 120 * violence
    love.graphics.setScissor(0, i * band_h, w, band_h)
    love.graphics.setColor(1, 1 - violence * rnd() * 0.5, 1 - violence * rnd() * 0.5, 1)
    love.graphics.draw(img, w / 2 + off, h / 2, 0, scale, scale, iw / 2, ih / 2)
    love.graphics.setScissor()
  end
  -- Scanlines
  love.graphics.setColor(0, 0, 0, 0.35)
  for y = 0, h, 3 do
    love.graphics.rectangle("fill", 0, y, w, 1)
  end
  -- Static-Rauschen
  love.graphics.setColor(1, 1, 1, 0.25 * violence)
  for _ = 1, 220 do
    love.graphics.rectangle("fill", rnd() * w, rnd() * h, rnd() * 3 + 1, 1)
  end
  -- Bild frisst sich schwarz
  love.graphics.setColor(0, 0, 0, violence * violence * 0.8)
  love.graphics.rectangle("fill", 0, 0, w, h)
end

-- Vollbild-Phasen (Spielsicht verdeckt)
function B:draw(w, h)
  if self.phase == "splash" then
    draw_splash(self, w, h)
  elseif self.phase == "queue" then
    draw_queue(self, w, h)
  elseif self.phase == "glitch" then
    draw_glitch(self, w, h)
    draw_console_line(self, w, h)
  elseif self.phase == "black" then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    draw_console_line(self, w, h)
  end
end

-- Overlay ueber der Spielsicht (langsame Aufblende in die Totensicht)
function B:draw_overlay(w, h)
  if self.phase ~= "fade" then return end
  local a = 1 - math.min(1, self.t / FADE_T)
  love.graphics.setColor(0, 0, 0, a)
  love.graphics.rectangle("fill", 0, 0, w, h)
  draw_console_line(self, w, h)
end

return B
