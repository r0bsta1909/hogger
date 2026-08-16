-- game/ui/intro.lua — Leeroy-Intro (GDD Kap. 5): lokales Onboarding zum
-- individuellen Spielstart. Eingaben gesperrt, Leeroys Icon naehert sich,
-- Dialog-Panels weiterklickbar, Namenseingabe (2-12 Buchstaben, erster
-- automatisch gross), Kollision: "Den gibt's schon. Streng dich an."
-- Danach "Such dir eine Leiche aus." -> Eingaben frei.
-- Statemachine ist love-frei (Unit-Test Stufe 1); love nur im draw-Teil.

local I = {}
I.__index = I

local APPROACH_T = 2.0

-- Dialogtexte (VORSCHLAG — Fiktion entscheidet Rob, CLAUDE.md);
-- %d = Try-Nummer in Seite 3
local PAGES = {
  "Ah. Frischfleisch. Ich bin Leeroy. Leeroy Jenkins. Ja, genau DER.",
  "Kurzfassung: Hexenmeister, Fluch, dieser Gnoll da hinten. Hogger. "
    .. "Solange der lebt, komme ich hier nicht raus. Du uebrigens auch nicht.",
  "Wir sind bei Try Nummer %d. Ungefaehr. Ich habe aufgehoert zu zaehlen.",
  "Mein alter Raid? Lauter Vollpfosten. Von jetzt auf gleich weg -- "
    .. "ausgeloggt, disconnected, wer weiss das schon.",
  "Ich erinnere mich an Drachenwelpen, einen Charge und einen Wipe. "
    .. "Und dann ... das hier. Ist dir aufgefallen, wie FLACH hier alles ist? Frag nicht.",
}
local NAME_PROMPT = "Und du bist? Na los, jeder hier braucht einen Namen."
local NAME_TAKEN = "Den gibt's schon. Streng dich an."
local FINAL_PAGE = "%s also. Gut. Such dir eine Leiche aus. Da vorne, am Ende des Wegs."
I.PAGES, I.NAME_TAKEN = PAGES, NAME_TAKEN -- fuer Tests/Review

function I.new()
  return setmetatable({
    state = "approach", -- approach | page | name | waiting | final | done
    t = 0, page = 1,
    buffer = "", note = nil,
    submit = nil,       -- von main abgeholter Namenswunsch
    pending = nil,      -- Wunsch, auf den die Host-Antwort aussteht
    accepted = nil,     -- bestaetigter Name (fuer die Schlusszeile)
  }, I)
end

-- Eingaben gesperrt, solange das Intro laeuft (GDD 5, Punkt 1)
function I:blocking()
  return self.state ~= "done"
end

function I:update(dt)
  self.t = self.t + dt
  if self.state == "approach" and self.t >= APPROACH_T then
    self.state = "page"
    self.t = 0
  end
end

-- Klick: naechstes Panel (GDD 5: "weiterklickbar")
function I:mousepressed()
  if self.state == "page" then
    if self.page < #PAGES then
      self.page = self.page + 1
    else
      self.state = "name"
    end
  elseif self.state == "final" then
    self.state = "done"
  end
end

-- Name: erster Buchstabe automatisch gross, Rest klein (GDD 5)
local function pretty(name)
  return name:sub(1, 1):upper() .. name:sub(2):lower()
end

function I:keypressed(key)
  if self.state == "name" then
    if key == "backspace" then
      self.buffer = self.buffer:sub(1, -2)
      return true
    elseif key == "return" and #self.buffer >= 2 then
      self.submit = pretty(self.buffer)
      self.pending = self.submit
      self.note = nil
      self.state = "waiting"
      return true
    end
    return true -- Feld schluckt alles (Eingaben sind ohnehin gesperrt)
  end
  if key == "return" or key == "space" then
    self:mousepressed()
    return true
  end
  return self:blocking()
end

function I:textinput(t)
  if self.state ~= "name" then return self:blocking() end
  if t:match("^%a$") and #self.buffer < 12 then
    self.buffer = self.buffer .. t
  end
  return true
end

-- main holt den Namenswunsch genau einmal ab und fragt den Host
function I:take_submit()
  local s = self.submit
  self.submit = nil
  return s
end

-- Host-Antwort: ok -> Schlusszeile; Kollision -> Feld bleibt offen (GDD 5)
function I:result(ok)
  if self.state ~= "waiting" then return end
  if ok then
    self.accepted = self.pending
    self.state = "final"
  else
    self.note = NAME_TAKEN
    self.state = "name"
  end
  self.pending = nil
end

-- ---------------------------------------------------------------------------
-- Zeichnen (WoW-Panel-Stil unten mittig; Leeroys Icon naehert sich)
-- ---------------------------------------------------------------------------
local function panel(px, py, pw, ph)
  love.graphics.setColor(0.08, 0.08, 0.12, 0.95)
  love.graphics.rectangle("fill", px, py, pw, ph, 5, 5)
  love.graphics.setColor(0.78, 0.63, 0.28, 1)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", px, py, pw, ph, 5, 5)
  love.graphics.setLineWidth(1)
end

function I:draw(view, w, h)
  if self.state == "done" then return end
  local assets = require("game.assets")

  -- Leeroys Icon gleitet heran und bleibt am Panel stehen (GDD 5, Punkt 1)
  local target_x, icon_y = w / 2 - 250, h - 190
  local from_x = -40
  local k = self.state == "approach" and math.min(1, self.t / APPROACH_T) or 1
  local ix = from_x + (target_x - from_x) * (k * k * (3 - 2 * k))
  assets.draw("icon_warrior", ix, icon_y, 2.2)
  love.graphics.setColor(0.95, 0.78, 0.2, 1)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", ix, icon_y, 38)
  love.graphics.setLineWidth(1)
  love.graphics.print("Leeroy", ix - 20, icon_y + 42)
  if self.state == "approach" then return end

  local pw, ph = 560, 110
  local px, py = (w - pw) / 2, h - 150
  panel(px, py, pw, ph)
  local font = love.graphics.getFont()

  local function say(text)
    love.graphics.setColor(0.95, 0.92, 0.8, 1)
    love.graphics.printf("Leeroy: " .. text, px + 16, py + 14, pw - 32)
  end

  if self.state == "page" then
    say(string.format(PAGES[self.page], view and view.try_nr or 0))
    love.graphics.setColor(0.6, 0.56, 0.45, 0.6 + 0.3 * math.sin(self.t * 3))
    love.graphics.print("(klicken)", px + pw - 76, py + ph - 22)
  elseif self.state == "name" or self.state == "waiting" then
    say(NAME_PROMPT)
    local shown = #self.buffer > 0 and pretty(self.buffer) or ""
    love.graphics.setColor(0.12, 0.12, 0.18, 1)
    love.graphics.rectangle("fill", px + 16, py + ph - 38, 220, 24, 3, 3)
    love.graphics.setColor(0.78, 0.63, 0.28, 1)
    love.graphics.rectangle("line", px + 16, py + ph - 38, 220, 24, 3, 3)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(shown .. (self.state == "name" and "_" or " ..."),
      px + 22, py + ph - 34)
    if self.note then
      love.graphics.setColor(0.95, 0.45, 0.35, 1)
      love.graphics.print(self.note, px + 248, py + ph - 34)
    else
      love.graphics.setColor(0.6, 0.56, 0.45, 1)
      love.graphics.print("2-12 Buchstaben, Enter", px + 248, py + ph - 34)
    end
  elseif self.state == "final" then
    say(string.format(FINAL_PAGE, self.accepted or "?"))
    love.graphics.setColor(0.6, 0.56, 0.45, 0.6 + 0.3 * math.sin(self.t * 3))
    love.graphics.print("(klicken)", px + pw - 76, py + ph - 22)
  end
end

return I
