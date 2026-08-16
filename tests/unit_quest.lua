-- tests/unit_quest.lua — Questfenster des Echos (GDD Kap. 5, Issue #51).
-- Deckt die Statemachine ab: tippen, annehmen, Namenskollision haelt das
-- Fenster offen, Ablehnen gibt es nicht. Love-frei (Zeichnen liegt separat).

local quest = require("game.ui.quest")

local q = quest.new()
T.eq(q.state, "approach", "das Echo naehert sich zuerst (lokale Sequenz)")
T.ok(q:blocking(), "Questfenster blockiert die Eingaben")
q:textinput("x")
T.eq(q.buffer, "", "waehrend der Annaeherung tippt man noch nicht")
q:update(2.0)
T.eq(q.state, "open", "danach steht das Fenster offen")
T.eq(q:can_accept(), false, "Annehmen ist ohne Namen gesperrt")
T.eq(q:accept(), false, "Annehmen ohne Namen prallt ab")

q:textinput("7"); q:textinput("!"); q:textinput(".")
T.eq(q.buffer, "", "Ziffern und Zeichen werden verworfen (nur Buchstaben)")
q:textinput("r")
T.eq(q:can_accept(), false, "ein Buchstabe reicht nicht (min. 2)")
for c in ("obbertdererste"):gmatch(".") do q:textinput(c) end
T.eq(#q.buffer, 12, "Deckel bei 12 Buchstaben")
T.eq(q:can_accept(), true, "mit gueltigem Namen ist Annehmen frei")
q:keypressed("backspace")
T.eq(#q.buffer, 11, "Backspace loescht")

T.eq(q:accept(), true, "Annehmen greift")
T.eq(q.state, "waiting", "wartet auf die Realm-Antwort")
T.eq(q:take_submit(), "Robbertdere", "erster Buchstabe automatisch gross")
T.eq(q:take_submit(), nil, "Namenswunsch nur einmal abholbar")

q:result(false)
T.eq(q.state, "open", "Kollision: das Fenster bleibt offen (GDD 5)")
T.eq(q.note, quest.NAME_TAKEN, "Kollisions-Zeile gesetzt")
T.ok(q:blocking(), "Questfenster blockiert weiterhin")

q:accept()
q:result(true)
T.eq(q.state, "done", "angenommener Name schliesst das Fenster")
T.eq(q.accepted, "Robbertdere", "bestaetigter Name gemerkt")
T.eq(q:blocking(), false, "danach gehen Eingaben wieder ins Spiel")

-- Wegklicken und wieder oeffnen (das Echo bleibt anklickbar)
do
  local w = quest.new("Rob")
  w:update(2.0)
  T.eq(w.buffer, "Rob", "Vorbelegung mit dem gemerkten Namen")
  w:keypressed("escape")
  T.eq(w:blocking(), false, "weggeklickt schluckt keine Tasten mehr")
  w:reopen()
  T.ok(w:blocking(), "Echo anklicken oeffnet es wieder")
end

-- Der Text gehoert dem ECHO, nicht dem Raid-Leeroy (Issue #52)
T.ok(quest.GIVER:find("Echo") ~= nil, "Questgeber ist das Echo")
T.ok(#quest.BODY >= 4, "Questtext hat die Intro-Informationen")
T.ok(#quest.GOALS >= 2, "Questziele sind benannt")
local goals = table.concat(quest.GOALS, " ")
T.ok(goals:find("Hogger") ~= nil, "Questziel nennt Hogger")

-- Taste L: wegblenden und zurueckholen (Issue #62)
do
  local w = quest.new()
  w:update(2.0)
  T.eq(w:toggle(), true, "L blendet weg")
  T.eq(w:visible(), false, "weggeblendet ist unsichtbar")
  T.eq(w:blocking(), false, "und schluckt keine Tasten")
  w:toggle()
  T.ok(w:visible(), "L holt es zurueck")
end

-- Questlog nach der Annahme: nur Anzeige, blockiert nichts (Issue #62)
do
  local log = quest.new_log()
  T.eq(log.mode, "log", "Log-Modus")
  T.eq(log.state, "open", "Log braucht keine Annaeherung")
  T.ok(log:visible(), "Log ist sichtbar")
  T.eq(log:blocking(), false, "Log sperrt die Eingaben nicht")
  T.eq(log:can_accept(), false, "im Log gibt es nichts anzunehmen")
  log:toggle()
  T.eq(log:visible(), false, "L schliesst das Log wieder")
end
