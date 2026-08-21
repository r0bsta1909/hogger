-- game/ui/quest.lua — Das Questfenster des Echos (GDD Kap. 5).
-- Das Onboarding laeuft nicht mehr ueber Dialog-Panels, sondern so, wie ein
-- Spiel es einem Spieler beibringt, den es nie gefragt hat: Ein Questgeber
-- rennt heran und drueckt ihm die Quest auf. Annehmen kann man sie,
-- ablehnen nicht — der Knopf ist da, er ist nur grau (Referenz
-- docs/referenzen/quest text beispiel.jpg).
-- Statemachine ist love-frei (Unit-Test Stufe 1); love nur im draw-Teil.

local model = require("sim.model")

local Q = {}
Q.__index = Q

-- ---------------------------------------------------------------------------
-- Texte (VORSCHLAG — Fiktion entscheidet Rob, CLAUDE.md).
-- Es spricht das ECHO, nicht der Raid-Leeroy: es sieht seinem eigenen
-- Koerper seit tausend Trys beim Sterben zu. %d = Try-Nummer.
-- ---------------------------------------------------------------------------
-- Wortlaut: Rob, 2026-08-21. Der Titel ist der Aufbau einer Pointe, die
-- erst beim Fluchbruch faellt — er verraet die Belohnung nicht.
-- Beachte: in der Titelleiste steht weiter "Leeroy Leeroy Jenkins Jenkins"
-- (GIVER aus names.lua), waehrend er sich hier als "Leeroy Jenkins"
-- vorstellt. Die Diskrepanz sieht der Spieler selbst; erklaert wird sie
-- nie, und beim Fluchbruch heilt sie sichtbar (GDD 10.1/11).
local TITLE = "Wenigstens haben wir..."
local GIVER = require("game.data.names").ECHO
local BODY = {
  "NA ENDLICH!! Nach all der Zeit! Verzeiht meine Aufregung, aber Ihr seid "
    .. "die erste echte Person, die hier seit Ewigkeiten auftaucht. Mein Name "
    .. "ist Leeroy Jenkins - ja, genau der. Aber tatsaechlich bin ich nur das "
    .. "Echo meiner physischen Huelle...",
  -- "der Paladin da drueben" statt "rennt da vorne": beim allerersten
  -- Spieler des Abends ist der Raid-Leeroy noch gar nicht losgerannt, er
  -- steht als Geist neben dem Echo am Friedhof (GDD 10.2). Die Formulierung
  -- stimmt vorher wie nachher.
  "Wir haben keine Zeit zu verlieren! Der Hexenmeister-Fluch hat diese "
    .. "Realitaet in eine zweidimensionale Ebene kollabieren lassen. Mein "
    .. "physischer Koerper - der Paladin da drueben - rennt gleich wieder "
    .. "voellig unkontrolliert und ohne Verstand in sein Verderben. Und als "
    .. "waere das nicht genug: Hogger langweilt sich schnell! Kriegen wir das "
    .. "Biest nicht in {ZEIT} klein, verliert er die Geduld - und dann macht "
    .. "er kurzen Prozess. Mit allen. Auf einmal. Ich habe es oft genug "
    .. "gesehen.",
  -- "stehen wir alle bei seiner Leiche" statt "eile ich zu seiner Leiche":
  -- beim Fluchbruch werden ALLE Spieler zu Hoggers Leiche teleportiert, und
  -- das Echo steht schon in der Mitte des Kreises. Seine einzige Bewegung
  -- ueberhaupt ist die Verschmelzung mit seinem eigenen Koerper (GDD 11).
  "Folgt dem Pfad, schliesst Euch den anderen Abenteurern an und bringt "
    .. "diesen verfluchten Gnoll zur Strecke, bevor die Zeit ablaeuft! Sobald "
    .. "er liegt, stehen wir alle bei seiner Leiche - und ich ueberreiche "
    .. "Euch Eure legendaere Belohnung. Eilt euch!",
}
local GOALS = {
  "Toetet Hogger, bevor ihm langweilig wird.  (0/1)",
  -- Diese Zeile ist die EINZIGE Anweisung, die einem frischen Geist sagt,
  -- wofuer die acht Klassenicons am Wiederbelebungsfeld da sind (GDD 5.5).
  -- Ohne sie steht ein Neuer davor und weiss nichts.
  "Sucht euch am Ende des Wegs eine Leiche aus und belebt euch wieder.",
  "Ablehnen ist keine Option. Das ist keine Redewendung.",
}
-- Timed Quest wie im Original. {REST} zaehlt mit der Try-Uhr herunter und
-- kommt aus derselben Quelle wie die Uhr am Ring — nie eine feste Zahl.
local TIME_GOAL = "Verbleibende Zeit: {REST}"
-- Die legendaere Belohnung bleibt im Questfenster UNGENANNT (Rob-Entscheid):
-- die Aufloesung gehoert dem Fluchbruch, und der Questtitel vervollstaendigt
-- sich dort von selbst.
local REWARD_LEAD = "Ihr erhaltet:"
local REWARDS = { "1 Kupfer", "10 Erfahrungspunkte", "???  (legendaer)" }
local REWARD_NOTE = "Vertraut mir. Es ist legendaer."
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
Q.TIME_GOAL, Q.REWARDS, Q.REWARD_LEAD = TIME_GOAL, REWARDS, REWARD_LEAD
Q.REWARD_NOTE = REWARD_NOTE
Q.NAME_TAKEN, Q.NAME_PROMPT = NAME_TAKEN, NAME_PROMPT

-- ---------------------------------------------------------------------------
-- Platzhalter: {ZEIT} = die Frist, {REST} = was davon noch laeuft, {TRY} =
-- die Try-Nummer. Beide Zeiten kommen aus model.p("try_time_limit") und aus
-- der Try-Uhr — NIE als feste Zeichenkette im Text. Wer im F10-Panel dreht,
-- liest im Questfenster sofort die neue Zahl (dieselbe Zusage wie fuer die
-- Uhr am Ring, GDD 4.2).
-- ---------------------------------------------------------------------------
function Q.fill(text, view)
  local limit = model.p("try_time_limit")
  local rest = limit - ((view and view.clock) or 0)
  return (text:gsub("{ZEIT}", model.mmss(limit))
              :gsub("{REST}", model.mmss(rest))
              :gsub("{TRY}", tostring((view and view.try_nr) or 0)))
end

-- ---------------------------------------------------------------------------
-- Der Inhalt als Liste von Bloecken. EINE Wahrheit fuer das Zeichnen UND
-- fuer die Hoehenpruefung: bis Runde 18 lief die Hoehe nur implizit durch
-- draw(), und das Fenster hat weder setScissor noch Hoehenpruefung noch
-- Scrolling — ein zu langer Text lief ungebremst ueber das Namensfeld aus
-- dem Pergament heraus, ohne dass irgendein Test es gemerkt haette.
-- kind: "h1" Titel · "h2" Abschnitt · "para" Fliesstext · "item" Zeile ·
--       "note" Kleingedrucktes
-- ---------------------------------------------------------------------------
function Q.blocks(view)
  local b = { { kind = "h1", text = TITLE } }
  for _, para in ipairs(BODY) do
    b[#b + 1] = { kind = "para", text = Q.fill(para, view) }
  end
  b[#b + 1] = { kind = "h2", text = "Questziele" }
  for _, g in ipairs(GOALS) do
    b[#b + 1] = { kind = "item", text = "- " .. g }
  end
  b[#b + 1] = { kind = "item", text = Q.fill(TIME_GOAL, view) }
  b[#b + 1] = { kind = "h2", text = "Belohnungen" }
  b[#b + 1] = { kind = "item", text = REWARD_LEAD }
  for _, r in ipairs(REWARDS) do
    b[#b + 1] = { kind = "item", text = "  " .. r }
  end
  b[#b + 1] = { kind = "note", text = REWARD_NOTE }
  return b
end

-- Laeuft die Bloecke ab und ruft emit(blk, y) fuer jeden; Rueckgabe ist die
-- y-Position NACH dem letzten Block. draw() zeichnet in emit, der Test
-- zaehlt nur mit — so kann die geprueffte Hoehe nicht von der gezeichneten
-- abweichen. wrap(text, breite) -> Zeilenzahl, fh = Zeilenhoehe.
function Q.walk(blocks, y, tw, wrap, fh, emit)
  for _, blk in ipairs(blocks) do
    if blk.kind == "h2" then y = y + 4 end
    if emit then emit(blk, y) end
    if blk.kind == "h1" then
      y = y + 34
    elseif blk.kind == "h2" then
      y = y + 24
    else
      y = y + wrap(blk.text, tw) * fh + (blk.kind == "para" and 8 or 4)
    end
  end
  return y
end

-- Anflug des Echos (Issues #61/#73; Runde 12 #138: KEINE Charge mehr —
-- Leeroy ist Paladin, und ein Paladin chargt nicht): das Echo gleitet ohne
-- Ausholen und ohne Staubfahne bis auf den eigenen Pfeil in der
-- Bildschirmmitte. Rein lokal — in der Welt bewegt sich das Echo nie.
local APPROACH_T = 1.1

-- skip_approach: beim erneuten Anklicken fliegt es nicht noch einmal an
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

-- Taste L: wegblenden und zurueckholen (Issue #62). Gilt nur noch fuer
-- Questlog und Lore — die Quest selbst laesst sich nicht mehr wegdruecken,
-- bevor sie angenommen ist (Issue #83).
function Q:toggle()
  if self.mode == "quest" then return false end
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
  end
  -- Escape schliesst hier nichts mehr: angenommen wird, und der Name
  -- ist Pflicht (Issue #83). Ablehnen bleibt grau.
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
-- Runde 18: 560 -> 660. Der neue Questtext samt Zielen und Belohnungsblock
-- braucht rund 90 px mehr, als das alte Fenster hergab. Gedeckelt an den
-- oberen Bildschirmrand, damit das Fenster bei kleinen Aufloesungen nicht
-- nach oben aus dem Bild waechst (Q.PANEL_H, Q.content_top/bottom pruefen
-- den Rest maschinell, siehe tests/unit_quest.lua).
Q.PANEL_W, Q.PANEL_H = 620, 660
function Q:layout(w, h)
  local pw, ph = Q.PANEL_W, Q.PANEL_H
  local px, py = (w - pw) / 2, math.max(8, (h - ph) / 2)
  return {
    x = px, y = py, w = pw, h = ph,
    close = { px + pw - 34, py + 8, 26, 26 },
    accept = { px + 20, py + ph - 46, 150, 32 },
    decline = { px + pw - 170, py + ph - 46, 150, 32 },
    name = { px + 24, py + ph - 92, 260, 26 },
  }
end

-- Wo der Inhalt beginnt und wo er spaetestens enden muss. Die Untergrenze
-- ist die Oberkante der Namensfrage (name.y - 20) — laeuft der Text
-- darueber hinaus, steht er im Namensfeld.
Q.CONTENT_TOP = 60
function Q.content_top(L) return L.y + Q.CONTENT_TOP end
function Q.content_bottom(L) return L.name[2] - 22 end
function Q.text_width(L) return L.w - 52 end

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
  -- kein X im Quest-Modus (Issue #83): erst annehmen, dann weiterspielen
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
  -- Gleiten mit Ease-out: geisterhaft, ohne Ausholen, ohne Staub (#138)
  local run = k
  local e = 1 - (1 - run) * (1 - run)
  local x, y = fx + (tx - fx) * e, fy + (ty - fy) * e
  local scale = 1.6 + 1.5 * run
  love.graphics.setColor(0, 0, 0, 0.45 * k)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(0.75, 0.85, 1.0, 0.25)
  love.graphics.circle("fill", x, y, 22 * scale)
  assets.draw("icon_paladin", x, y, scale, 0.55 + 0.4 * k)
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
  assets.draw("icon_paladin", px + 24, py + 20, 32 / assets.size("icon_paladin"), 0.7)
  love.graphics.setColor(0.72, 0.86, 0.55, 1) -- freundlicher NPC: gruen
  love.graphics.print(GIVER, px + 48, py + 12)
  if self.mode == "lore" then
    love.graphics.setColor(0.55, 0.52, 0.42, 1)
    love.graphics.print("(kein Questziel, nur Reden)", px + 250, py + 12)
  end
  if self.mode ~= "quest" then
    -- Schliessen-Kreuz nur da, wo es nichts zu entscheiden gibt (Issue #83)
    love.graphics.setColor(0.75, 0.25, 0.2, 1)
    love.graphics.rectangle("line", L.close[1], L.close[2], L.close[3], L.close[4], 3, 3)
    love.graphics.setColor(0.9, 0.5, 0.45, 1)
    love.graphics.print("X", L.close[1] + 9, L.close[2] + 5)
  end

  local tx, ty, tw = px + 26, Q.content_top(L), Q.text_width(L)
  -- Zeilenzahl aus der echten Schrift; dieselbe Funktion bekommt der
  -- Ueberlauf-Test in den Fingern (Stufe 4b), damit gemessen wird, was
  -- wirklich gezeichnet wird
  local function wrap_lines(text, width)
    local _, l = font:getWrap(text, width)
    return #l
  end

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

  -- Titel, Fliesstext, Ziele, Belohnungen — gezeichnet aus DERSELBEN
  -- Blockliste, die der Ueberlauf-Test misst (Q.walk, Runde 18)
  Q.walk(Q.blocks(view), ty, tw, wrap_lines, font:getHeight(),
    function(blk, y)
      if blk.kind == "h1" then
        love.graphics.setColor(PARCH_DARK[1], PARCH_DARK[2], PARCH_DARK[3], 1)
        love.graphics.print(blk.text, tx, y, 0, 1.5, 1.5)
      elseif blk.kind == "h2" then
        love.graphics.setColor(PARCH_DARK[1], PARCH_DARK[2], PARCH_DARK[3], 1)
        love.graphics.print(blk.text, tx, y, 0, 1.2, 1.2)
      elseif blk.kind == "note" then
        love.graphics.setColor(0.42, 0.35, 0.24, 1)
        love.graphics.printf(blk.text, tx, y, tw)
      else
        love.graphics.setColor(0.16, 0.12, 0.07, 1)
        love.graphics.printf(blk.text, tx, y, tw)
      end
    end)

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
