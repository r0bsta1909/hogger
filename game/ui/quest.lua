-- game/ui/quest.lua — Das Questfenster des Echos (GDD Kap. 5).
-- Das Onboarding laeuft nicht mehr ueber Dialog-Panels, sondern so, wie ein
-- Spiel es einem Spieler beibringt, den es nie gefragt hat: Ein Questgeber
-- rennt heran und drueckt ihm die Quest auf. Annehmen kann man sie,
-- ablehnen nicht — der Knopf ist da, er ist nur grau (Referenz
-- docs/referenzen/quest text beispiel.jpg).
-- Statemachine ist love-frei (Unit-Test Stufe 1); love nur im draw-Teil.

local Q = {}
Q.__index = Q

-- ---------------------------------------------------------------------------
-- Texte (VORSCHLAG — Fiktion entscheidet Rob, CLAUDE.md).
-- Es spricht das ECHO, nicht der Raid-Leeroy: es sieht seinem eigenen
-- Koerper seit tausend Trys beim Sterben zu. %d = Try-Nummer.
-- ---------------------------------------------------------------------------
local TITLE = "Der Fluch des Leeroy Jenkins"
local GIVER = "Echo von Leeroy Jenkins"
local BODY = {
  "Da bist du ja. Nein, steh nicht auf. Du liegst nicht, du bist nur tot. "
    .. "Das legt sich.",
  "Ich bin Leeroy Jenkins. Genauer: das, was von ihm uebrig ist, waehrend er "
    .. "da vorne schon wieder losrennt. Siehst du ihn? Der Krieger, der gleich "
    .. "in den Gnoll chargt. Das bin auch ich. Ich sehe mir dabei zu. Seit "
    .. "Try %d. Ungefaehr. Ich habe aufgehoert zu zaehlen.",
  "Kurzfassung: Hexenmeister, Fluch, dieser Gnoll da hinten. Hogger. Solange "
    .. "der lebt, kommt hier keiner raus. Du uebrigens auch nicht.",
  "Mein alter Raid? Lauter Vollpfosten. Von jetzt auf gleich weg -- "
    .. "ausgeloggt, disconnected, wer weiss das schon.",
  "Ich erinnere mich an Drachenwelpen, einen Charge und einen Wipe. Und dann "
    .. "... das hier. Ist dir aufgefallen, wie FLACH hier alles ist? Frag nicht.",
}
local GOALS = {
  "Toetet Hogger.",
  "Sucht euch am Ende des Wegs eine Leiche aus und belebt euch wieder.",
  "Ablehnen ist keine Option. Das ist keine Redewendung.",
}
-- Easter Egg (Issue #64): die ganze Geschichte, wenn man das Echo als Geist
-- noch einmal anspricht. Null Spielwirkung, keine Belohnung, nur wer sucht.
-- VORSCHLAG — Fiktion entscheidet Rob.
local LORE_TITLE = "Was passiert ist"
local LORE = {
  { titel = "Der Raid", absaetze = {
    "Wir standen vor dem Raum. Sie haben gerechnet. Wahrscheinlichkeiten, Prozente, wer wen zieht. Zweiunddreissig Minuten lang.",
    "Ich war Huehnchen holen.",
  } },
  { titel = "Der Sturmangriff", absaetze = {
    "Dann bin ich rein. Mit meinem eigenen Namen im Mund, weil ich dachte, das macht es besser.",
    "Es machte es nicht besser. Es waren sehr viele Drachenwelpen. Es war ein sehr kurzer Kampf.",
  } },
  { titel = "Der Fluch", absaetze = {
    "Der Hexenmeister hat nicht geschrien. Das war das Schlimme. Er hat nur gesagt, ich soll das machen, was ich am besten kann: anrennen.",
    "Auf ewig. Als Stufe 1. Gegen etwas, das ich nie schaffe.",
  } },
  { titel = "Das Erwachen", absaetze = {
    "Danach: hier. Alles flach, alles Symbole, alles klein. Ein Gnoll auf einem Huegel, ein Pfad, ein Friedhof.",
    "Mein Raid war noch da. Eine Weile. Dann waren sie weg -- ausgeloggt, disconnected, wer weiss das schon. Keiner blieb.",
  } },
  { titel = "Die Teilung", absaetze = {
    "Irgendwann war ich zweimal. Der da vorne rennt, schreit meinen Namen und stirbt. Und ich stehe hier und sehe ihm dabei zu.",
    "Er hoert mich nicht. Ich habe es oft genug versucht.",
  } },
  { titel = "Warum ich dich frage", absaetze = {
    "Ich kann nicht aufhoeren. Aber ihr koennt anfangen. Deshalb der Zettel, das Ausrufezeichen, der ganze Zirkus.",
    "Der Knopf zum Ablehnen ist uebrigens echt. Er ist nur grau. So wie hier alles.",
  } },
}
Q.LORE, Q.LORE_TITLE = LORE, LORE_TITLE

local NAME_PROMPT = "Und wie sollen wir dich nennen?"
local NAME_TAKEN = "Den gibt's schon. Streng dich an."
local NAME_HINT = "2-12 Buchstaben"
Q.TITLE, Q.GIVER, Q.BODY, Q.GOALS = TITLE, GIVER, BODY, GOALS
Q.NAME_TAKEN, Q.NAME_PROMPT = NAME_TAKEN, NAME_PROMPT

-- Charge des Echos (Issues #61/#73): kurzes Ausholen an der Standposition,
-- dann schneller Anflug bis auf den eigenen Pfeil in der Bildschirmmitte.
-- Rein lokal — in der Welt bewegt sich das Echo nie.
local APPROACH_T = 1.1
local WINDUP = 0.32 -- Anteil der Zeit, in dem es nur ausholt

-- skip_approach: beim erneuten Anklicken chargt es nicht noch einmal
function Q.new(prefill, skip_approach)
  return setmetatable({
    state = skip_approach and "open" or "approach", -- approach | open | waiting | done
    mode = "quest",     -- quest | log (Questlog nach der Annahme, Taste L)
    t = 0,
    buffer = prefill or "",
    note = nil,
    submit = nil,       -- von main abgeholter Namenswunsch
    pending = nil,
    accepted = nil,     -- bestaetigter Name
    closed = false,     -- Fenster weggeklickt (Echo neu anklicken oeffnet es)
    hover = nil,
  }, Q)
end

-- Questlog (Taste L nach der Annahme): dieselbe Seite, ohne Namensfeld und
-- ohne Knoepfe — man kann nichts mehr entscheiden (GDD Kap. 5)
function Q.new_log()
  local q = Q.new()
  q.state = "open"
  q.mode = "log"
  return q
end

-- Easter Egg: das Echo erzaehlt (Issue #64). Blockiert nichts, man kann
-- jederzeit weggehen — es redet dann eben mit sich selbst.
function Q.new_lore()
  local q = Q.new()
  q.state = "open"
  q.mode = "lore"
  q.page = 1
  return q
end

function Q:lore_next()
  if self.mode ~= "lore" then return false end
  if self.page >= #LORE then
    self.closed = true
  else
    self.page = self.page + 1
  end
  return true
end

function Q:lore_prev()
  if self.mode ~= "lore" or self.page <= 1 then return false end
  self.page = self.page - 1
  return true
end

-- Solange das Fenster offen ist, gehen Tasten ins Fenster (Namensfeld).
-- Das Questlog blockiert nichts: es ist nur eine Anzeige.
function Q:blocking()
  return self.mode == "quest" and self.state ~= "done" and not self.closed
end

-- sichtbar (auch das Log, das nichts blockiert)
function Q:visible()
  return self.state ~= "done" and not self.closed
end

function Q:update(dt)
  self.t = self.t + dt
  if self.state == "approach" and self.t >= APPROACH_T then
    self.state = "open"
    self.t = 0
  end
end

-- Taste L: wegblenden und zurueckholen (Issue #62)
function Q:toggle()
  if self.state == "done" then return false end
  self.closed = not self.closed
  return true
end

-- Name: erster Buchstabe gross, Rest klein (GDD Kap. 5)
local function pretty(name)
  return name:sub(1, 1):upper() .. name:sub(2):lower()
end

function Q:can_accept()
  return self.mode == "quest" and self.state == "open" and #self.buffer >= 2
end

function Q:accept()
  if not self:can_accept() then return false end
  self.submit = pretty(self.buffer)
  self.pending = self.submit
  self.note = nil
  self.state = "waiting"
  return true
end

function Q:reopen()
  if self.state ~= "done" then self.closed = false end
end

function Q:textinput(t)
  if not self:blocking() then return false end
  if self.state == "open" and self.mode == "quest"
     and t:match("^%a$") and #self.buffer < 12 then
    self.buffer = self.buffer .. t
  end
  return true
end

function Q:keypressed(key)
  if self.mode == "lore" and self:visible() then
    if key == "escape" then self.closed = true
    elseif key == "return" or key == "space" or key == "kpenter" then
      self:lore_next()
    elseif key == "backspace" then self:lore_prev() end
    return true
  end
  if not self:blocking() then return false end
  if key == "backspace" then
    self.buffer = self.buffer:sub(1, -2)
  elseif key == "return" or key == "kpenter" then
    self:accept()
  elseif key == "escape" then
    self.closed = true -- der Knopf oben rechts, nur eben als Taste
  end
  return true
end

-- main holt den Namenswunsch genau einmal ab und fragt den Host
function Q:take_submit()
  local s = self.submit
  self.submit = nil
  return s
end

-- Host-Antwort auf den Namen: ok -> Quest annehmen; Kollision -> Feld offen
function Q:result(ok)
  if self.state ~= "waiting" then return end
  if ok then
    self.accepted = self.pending
    self.state = "done"
  else
    self.note = NAME_TAKEN
    self.state = "open"
  end
  self.pending = nil
end

-- ---------------------------------------------------------------------------
-- Zeichnen (Original-Vorbild: Pergament, Titelleiste mit Portrait,
-- Questziele, unten Annehmen/Ablehnen)
-- ---------------------------------------------------------------------------
local PARCH = { 0.85, 0.78, 0.60 }
local PARCH_DARK = { 0.20, 0.15, 0.09 }

local function button(x, y, w, h, label, enabled, hover)
  local a = enabled and 1 or 0.45
  love.graphics.setColor(0.16 * a + 0.05, 0.12 * a + 0.04, 0.07 * a + 0.03, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  love.graphics.setColor(0.55 * a, 0.44 * a, 0.20 * a, 1)
  love.graphics.setLineWidth(enabled and 2 or 1)
  love.graphics.rectangle("line", x, y, w, h, 3, 3)
  love.graphics.setLineWidth(1)
  local col = enabled and (hover and { 1, 0.95, 0.7 } or { 0.95, 0.85, 0.55 })
              or { 0.55, 0.52, 0.45 }
  love.graphics.setColor(col[1], col[2], col[3], 1)
  local font = love.graphics.getFont()
  love.graphics.print(label, x + w / 2 - font:getWidth(label) / 2,
    y + h / 2 - font:getHeight() / 2)
end

-- Rueckgabe: Rechtecke fuer die Klickpruefung
function Q:layout(w, h)
  local pw, ph = 620, 560
  local px, py = (w - pw) / 2, (h - ph) / 2
  return {
    x = px, y = py, w = pw, h = ph,
    close = { px + pw - 34, py + 8, 26, 26 },
    accept = { px + 20, py + ph - 46, 150, 32 },
    decline = { px + pw - 170, py + ph - 46, 150, 32 },
    name = { px + 24, py + ph - 92, 260, 26 },
  }
end

local function inside(r, mx, my)
  return mx >= r[1] and mx <= r[1] + r[3] and my >= r[2] and my <= r[2] + r[4]
end

function Q:mousepressed(mx, my, w, h)
  if not self:visible() or self.state == "approach" then return false end
  local L = self:layout(w, h)
  if self.mode == "log" then
    if inside(L.close, mx, my) then self.closed = true end
    return true
  end
  if self.mode == "lore" then
    if inside(L.close, mx, my) then self.closed = true
    elseif inside(L.accept, mx, my) then self:lore_prev()
    elseif inside(L.decline, mx, my) then self:lore_next() end
    return true
  end
  if inside(L.close, mx, my) then
    self.closed = true
    return true
  end
  if inside(L.accept, mx, my) then
    self:accept()
    return true
  end
  return true -- das Fenster schluckt Klicks (Ablehnen tut nichts)
end

function Q:mousemoved(mx, my, w, h)
  local L = self:layout(w, h)
  self.hover = inside(L.accept, mx, my) and "accept"
               or inside(L.decline, mx, my) and "decline"
               or inside(L.close, mx, my) and "close" or nil
end

-- Lokale Annaeherung (Issue #61): nur der betroffene Spieler sieht, wie das
-- Echo von seiner Standposition auf ihn zugleitet. In der Welt bewegt sich
-- dabei nichts — alle anderen sehen es unveraendert am Friedhof stehen.
function Q:draw_approach(view, w, h, to_screen)
  local assets = require("game.assets")
  local k = math.min(1, self.t / APPROACH_T)
  -- Ziel ist der eigene Pfeil: exakt die Bildschirmmitte (GDD 4.1)
  local tx, ty = w / 2, h / 2
  local fx, fy = tx, ty - h * 0.30
  if view and view.echo and to_screen then
    fx, fy = to_screen(view.echo.x, view.echo.y)
  end
  local x, y, run
  if k < WINDUP then
    -- Ausholen: es steht noch, zittert nur kurz
    local j = (k / WINDUP)
    local shake = (1 - j) * 3
    x = fx + math.sin(self.t * 40) * shake
    y = fy + math.cos(self.t * 37) * shake * 0.6
    run = 0
  else
    -- Ansturm: schnell los, am Ziel abbremsen
    run = (k - WINDUP) / (1 - WINDUP)
    local e = 1 - (1 - run) * (1 - run)
    x, y = fx + (tx - fx) * e, fy + (ty - fy) * e
  end
  local scale = 1.6 + 1.5 * run
  love.graphics.setColor(0, 0, 0, 0.45 * k)
  love.graphics.rectangle("fill", 0, 0, w, h)
  -- Staubfahne hinter dem Ansturm
  if run > 0 then
    for i = 1, 6 do
      local t2 = math.max(0, run - i * 0.05)
      local e2 = 1 - (1 - t2) * (1 - t2)
      love.graphics.setColor(0.75, 0.85, 1.0, 0.10 * (1 - i / 7))
      love.graphics.circle("fill", fx + (tx - fx) * e2, fy + (ty - fy) * e2,
        16 * scale * (1 - i / 9))
    end
  end
  love.graphics.setColor(0.75, 0.85, 1.0, 0.25)
  love.graphics.circle("fill", x, y, 22 * scale)
  assets.draw("icon_warrior", x, y, scale, 0.55 + 0.4 * k)
  local font = love.graphics.getFont()
  love.graphics.setColor(0.72, 0.86, 0.55, k)
  love.graphics.print(GIVER, x - font:getWidth(GIVER) / 2, y + 26 * scale)
end

function Q:draw(view, w, h, to_screen)
  if not self:visible() then return end
  if self.state == "approach" then
    self:draw_approach(view, w, h, to_screen)
    return
  end
  local assets = require("game.assets")
  local font = love.graphics.getFont()
  local L = self:layout(w, h)
  local px, py, pw, ph = L.x, L.y, L.w, L.h

  -- Rahmen und Pergament
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(0.10, 0.08, 0.06, 0.98)
  love.graphics.rectangle("fill", px - 6, py - 6, pw + 12, ph + 12, 6, 6)
  love.graphics.setColor(0.55, 0.44, 0.20, 1)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", px - 6, py - 6, pw + 12, ph + 12, 6, 6)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(PARCH[1], PARCH[2], PARCH[3], 1)
  love.graphics.rectangle("fill", px + 8, py + 44, pw - 16, ph - 108, 3, 3)

  -- Titelleiste: Portrait des Echos, Name, Schliessen-Kreuz
  love.graphics.setColor(0.16, 0.13, 0.09, 1)
  love.graphics.rectangle("fill", px, py, pw, 40, 4, 4)
  assets.draw("icon_warrior", px + 24, py + 20, 32 / assets.size("icon_warrior"), 0.7)
  love.graphics.setColor(0.72, 0.86, 0.55, 1) -- freundlicher NPC: gruen
  love.graphics.print(GIVER, px + 48, py + 12)
  if self.mode == "lore" then
    love.graphics.setColor(0.55, 0.52, 0.42, 1)
    love.graphics.print("(kein Questziel, nur Reden)", px + 250, py + 12)
  end
  love.graphics.setColor(0.75, 0.25, 0.2, 1)
  love.graphics.rectangle("line", L.close[1], L.close[2], L.close[3], L.close[4], 3, 3)
  love.graphics.setColor(0.9, 0.5, 0.45, 1)
  love.graphics.print("X", L.close[1] + 9, L.close[2] + 5)

  local tx, ty, tw = px + 26, py + 60, pw - 52

  if self.mode == "lore" then
    -- Easter Egg: Seite fuer Seite, sonst nichts (Issue #64)
    local page = LORE[self.page] or LORE[1]
    love.graphics.setColor(PARCH_DARK[1], PARCH_DARK[2], PARCH_DARK[3], 1)
    love.graphics.print(LORE_TITLE, tx, ty, 0, 1.5, 1.5)
    ty = ty + 40
    love.graphics.print(page.titel, tx, ty, 0, 1.2, 1.2)
    ty = ty + 30
    love.graphics.setColor(0.16, 0.12, 0.07, 1)
    for _, para in ipairs(page.absaetze) do
      local _, wrapped = font:getWrap(para, tw)
      love.graphics.printf(para, tx, ty, tw)
      ty = ty + #wrapped * font:getHeight() + 10
    end
    love.graphics.setColor(0.35, 0.30, 0.22, 1)
    local pg = string.format("Seite %d von %d", self.page, #LORE)
    love.graphics.print(pg, tx, py + ph - 128)
    button(L.accept[1], L.accept[2], L.accept[3], L.accept[4], "Zurueck",
      self.page > 1, self.hover == "accept")
    button(L.decline[1], L.decline[2], L.decline[3], L.decline[4],
      self.page < #LORE and "Weiter" or "Schliessen", true,
      self.hover == "decline")
    return
  end

  -- Questtitel und Fliesstext
  love.graphics.setColor(PARCH_DARK[1], PARCH_DARK[2], PARCH_DARK[3], 1)
  love.graphics.print(TITLE, tx, ty, 0, 1.5, 1.5)
  ty = ty + 34
  love.graphics.setColor(0.16, 0.12, 0.07, 1)
  for _, para in ipairs(BODY) do
    local text = para:find("%%d") and string.format(para, view and view.try_nr or 0)
                 or para
    local _, lines = font:getWrap(text, tw)
    love.graphics.printf(text, tx, ty, tw)
    ty = ty + #lines * font:getHeight() + 8
  end

  -- Questziele
  ty = ty + 4
  love.graphics.setColor(PARCH_DARK[1], PARCH_DARK[2], PARCH_DARK[3], 1)
  love.graphics.print("Questziele", tx, ty, 0, 1.2, 1.2)
  ty = ty + 24
  love.graphics.setColor(0.16, 0.12, 0.07, 1)
  for _, g in ipairs(GOALS) do
    love.graphics.printf("- " .. g, tx, ty, tw)
    ty = ty + font:getHeight() + 4
  end

  if self.mode == "log" then
    -- Questlog: nichts zu entscheiden, nur nachlesen (Taste L)
    love.graphics.setColor(0.35, 0.30, 0.22, 1)
    local hint = "Angenommen.  [L] schliesst das Questlog."
    love.graphics.print(hint, L.name[1], L.name[2] + 6)
    return
  end

  -- Namensfeld
  love.graphics.setColor(0.20, 0.16, 0.10, 1)
  love.graphics.print(NAME_PROMPT, L.name[1], L.name[2] - 20)
  love.graphics.setColor(0.10, 0.09, 0.07, 1)
  love.graphics.rectangle("fill", L.name[1], L.name[2], L.name[3], L.name[4], 3, 3)
  love.graphics.setColor(0.55, 0.44, 0.20, 1)
  love.graphics.rectangle("line", L.name[1], L.name[2], L.name[3], L.name[4], 3, 3)
  local shown = #self.buffer > 0 and pretty(self.buffer) or ""
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print(shown .. (self.state == "open"
      and ((math.floor(self.t * 2) % 2 == 0) and "_" or "") or " ..."),
    L.name[1] + 8, L.name[2] + 5)
  if self.note then
    love.graphics.setColor(0.75, 0.20, 0.15, 1)
    love.graphics.print(self.note, L.name[1] + L.name[3] + 12, L.name[2] + 5)
  else
    love.graphics.setColor(0.35, 0.30, 0.22, 1)
    love.graphics.print(NAME_HINT, L.name[1] + L.name[3] + 12, L.name[2] + 5)
  end

  -- Knoepfe: Annehmen wirkt, Ablehnen ist da und tut nichts (GDD Kap. 5)
  button(L.accept[1], L.accept[2], L.accept[3], L.accept[4], "Annehmen",
    self:can_accept(), self.hover == "accept")
  button(L.decline[1], L.decline[2], L.decline[3], L.decline[4], "Ablehnen",
    false, false)
end

return Q
