-- tests/unit_intro.lua — Leeroy-Intro-Statemachine (GDD Kap. 5).
-- Deckt die Stufe-4-Anforderung "Intro-Statemachine blockiert Eingaben
-- korrekt" als reinen Unit-Test ab: Annaeherung -> Dialogseiten ->
-- Namenseingabe (2-12 Buchstaben, erster gross, Kollision haelt das Feld
-- offen) -> Schlusszeile -> frei. Love-frei (Zeichnen liegt separat).

local intro = require("game.ui.intro")

local it = intro.new()
T.ok(it:blocking(), "Intro blockiert ab Start")
it:update(1.0)
T.eq(it.state, "approach", "Annaeherung laeuft")
it:mousepressed()
T.eq(it.state, "approach", "Klick waehrend der Annaeherung wirkungslos")
it:update(1.5)
T.eq(it.state, "page", "Dialog beginnt nach der Annaeherung")

for _ = 1, #intro.PAGES - 1 do it:mousepressed() end
T.eq(it.state, "page", "letzte Dialogseite noch offen")
T.ok(it:blocking(), "Intro blockiert waehrend der Dialogseiten")
it:mousepressed()
T.eq(it.state, "name", "Namenseingabe nach der letzten Seite")

it:textinput("7"); it:textinput("!"); it:textinput(".")
T.eq(it.buffer, "", "Ziffern und Zeichen werden verworfen (nur Buchstaben)")
it:textinput("r")
it:keypressed("return")
T.eq(it.state, "name", "ein Buchstabe reicht nicht (min. 2)")
for c in ("obbertdererste"):gmatch(".") do it:textinput(c) end
T.eq(#it.buffer, 12, "Deckel bei 12 Buchstaben")
it:keypressed("return")
T.eq(it.state, "waiting", "wartet auf die Realm-Antwort")
T.eq(it:take_submit(), "Robbertderer", "erster Buchstabe automatisch gross")
T.eq(it:take_submit(), nil, "Namenswunsch nur einmal abholbar")

it:result(false)
T.eq(it.state, "name", "Kollision: das Feld bleibt offen (GDD 5)")
T.eq(it.note, intro.NAME_TAKEN, "Kollisions-Zeile gesetzt")
T.ok(it:blocking(), "Intro blockiert weiterhin")

for _ = 1, 12 do it:keypressed("backspace") end
T.eq(it.buffer, "", "Backspace leert das Feld")
for c in ("Erwin"):gmatch(".") do it:textinput(c) end
it:keypressed("return")
it:result(true)
T.eq(it.state, "final", "Annahme: Schlusszeile")
T.eq(it.accepted, "Erwin", "bestaetigter Name gemerkt")
T.ok(it:blocking(), "blockiert bis zur Schlusszeile")
it:mousepressed()
T.eq(it.state, "done", "Intro beendet")
T.ok(not it:blocking(), "Eingaben frei nach dem Intro")
