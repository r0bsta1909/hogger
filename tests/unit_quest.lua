-- tests/unit_quest.lua — Questfenster des Echos (GDD Kap. 5, Issue #51).
-- Deckt die Statemachine ab: tippen, annehmen, Namenskollision haelt das
-- Fenster offen, Ablehnen gibt es nicht. Love-frei (Zeichnen liegt separat).

local quest = require("game.ui.quest")

local q = quest.new()
T.eq(q.state, "approach", "das Echo chargt zuerst heran (lokale Sequenz)")
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

-- Kein Ausweg mehr (Issue #83): weder Escape noch X noch Taste L schliessen
-- die Quest — angenommen wird, und der Name ist Pflicht.
do
  local w = quest.new("Rob")
  w:update(2.0)
  T.eq(w.buffer, "Rob", "Vorbelegung mit dem gemerkten Namen")
  w:keypressed("escape")
  T.ok(w:blocking(), "Escape schliesst die Quest nicht mehr (#83)")
  T.eq(w:toggle(), false, "Taste L blendet die Quest nicht mehr weg")
  local L = w:layout(1280, 720)
  w:mousepressed(L.close[1] + 5, L.close[2] + 5, 1280, 720)
  T.ok(w:blocking(), "Klick auf die alte X-Position prallt ab")
  T.ok(w:visible(), "das Fenster bleibt sichtbar, bis angenommen wird")
end

-- Der Text gehoert dem ECHO, nicht dem Raid-Leeroy (Issue #52). Seit Runde 11
-- (#132) heisst es "Leeroy Leeroy Jenkins Jenkins" — dass es nur der Rest von
-- Leeroy ist, sagt seitdem der Questtext selbst statt der Name.
local names = require("game.data.names")
T.eq(quest.GIVER, names.ECHO, "Questgeber traegt den Namen aus einer Wahrheit")
T.ok(names.ECHO ~= names.LEEROY, "Echo und Raid-Leeroy sind zwei Figuren")
T.ok(names.ECHO:find("[\128-\255]") == nil, "Name ist ASCII (Spielcode-Konvention)")
T.ok(#names.LEEROY_LEFT > 0 and names.LEEROY_LEFT:find("[\128-\255]") == nil,
  "Systemnachricht der Endsequenz ist da und ASCII")

-- Mit der Verschmelzung heilt der Name (GDD 11): aus dem doppelten wird
-- wieder der eine, und genau der verlaesst dann das Spiel.
T.eq(names.echo_name(0), names.ECHO, "waehrend des Trys der doppelte Name")
T.eq(names.echo_name(1), names.ECHO, "versammelt: noch doppelt")
T.eq(names.echo_name(2), names.ECHO, "waehrend der Verschmelzung noch doppelt")
T.eq(names.echo_name(3), names.WHOLE, "verschmolzen: wieder einer")
T.eq(names.echo_name(4), names.WHOLE, "beim Abgang: wieder einer")
T.eq(names.WHOLE, "Leeroy Jenkins", "der ganze Name ist der aus der Legende")
T.ok(names.LEEROY_LEFT:find(names.WHOLE, 1, true) == 1,
  "die Systemnachricht meldet genau diesen Namen")

-- Bot-Namen (Runde 12, #146): Robs Liste, deterministisch zugelost
do
  T.eq(#names.BOT_NAMES, 42, "botnamen: Robs Liste ist komplett (42)")
  local seen = {}
  for _, nm in ipairs(names.BOT_NAMES) do
    T.ok(not seen[nm], "botnamen: kein Duplikat (" .. nm .. ")")
    seen[nm] = true
    T.ok(nm:find("[\128-\255]") == nil, "botnamen: ASCII (" .. nm .. ")")
  end
  local a = names.bot_names_for_seed(7)
  local b = names.bot_names_for_seed(7)
  local c = names.bot_names_for_seed(8)
  T.eq(#a, 42, "botnamen: Zulosung verliert keinen Namen")
  local same_ab, same_ac = true, true
  local in_a = {}
  for i = 1, #a do
    if a[i] ~= b[i] then same_ab = false end
    if a[i] ~= c[i] then same_ac = false end
    in_a[a[i]] = true
  end
  T.ok(same_ab, "botnamen: gleicher Seed -> gleiche Reihenfolge")
  T.ok(not same_ac, "botnamen: anderer Seed -> andere Reihenfolge")
  for _, nm in ipairs(names.BOT_NAMES) do
    T.ok(in_a[nm], "botnamen: Zulosung ist eine Permutation (" .. nm .. ")")
  end
end
-- Der Test fesselte bis Runde 18 die woertliche Wendung "uebrig ist". Der
-- neue Wortlaut (Rob, 2026-08-21) sagt dasselbe anders. Gefesselt wird
-- deshalb, WOFUER der Test da war: dass das Echo im Questtext seine eigene
-- Natur erklaert — der Name allein sagt es nicht (GDD 10.1).
do
  local body = table.concat(quest.BODY, " ")
  T.ok(body:find("Echo") ~= nil,
    "der Questtext klaert auf, dass er nur das Echo ist")
  -- Er darf sie auch nicht NUR behaupten: irgendwo muss stehen, dass da
  -- noch ein zweiter, koerperlicher Leeroy herumrennt (GDD 10.2)
  T.ok(body:find("Koerper") ~= nil or body:find("Huelle") ~= nil,
    "der Questtext nennt die zweite, koerperliche Haelfte")
end
T.ok(#quest.BODY >= 3, "Questtext hat die Intro-Informationen")
T.ok(#quest.GOALS >= 2, "Questziele sind benannt")
local goals = table.concat(quest.GOALS, " ")
T.ok(goals:find("Hogger") ~= nil, "Questziel nennt Hogger")
-- Das Onboarding darf beim Umschreiben nicht verlorengehen: diese Zeile
-- ist die EINZIGE Anweisung, die einem frischen Geist sagt, wofuer die
-- acht Klassenicons am Wiederbelebungsfeld da sind (GDD 5.5).
T.ok(goals:find("Leiche") ~= nil and goals:find("belebt") ~= nil,
  "Questziel erklaert die Wiederbelebung am Klassenicon")

-- ---------------------------------------------------------------------------
-- Alle Anzeigetexte ASCII (Spielcode-Konvention, CLAUDE.md). Bis Runde 18
-- galt die Pruefung nur fuer names.lua — Umlaute in quest.lua waeren gruen
-- durchgerutscht und haetten trotzdem die Konvention gebrochen.
-- ---------------------------------------------------------------------------
do
  local function ascii(s, wo)
    T.ok(type(s) == "string" and s:find("[\128-\255]") == nil,
      "ASCII: " .. wo .. " (" .. tostring(s):sub(1, 40) .. ")")
  end
  ascii(quest.TITLE, "Questtitel")
  for i, s in ipairs(quest.BODY) do ascii(s, "Body " .. i) end
  for i, s in ipairs(quest.GOALS) do ascii(s, "Ziel " .. i) end
  for i, s in ipairs(quest.REWARDS) do ascii(s, "Belohnung " .. i) end
  ascii(quest.TIME_GOAL, "Zeitziel")
  ascii(quest.REWARD_LEAD, "Belohnungs-Einleitung")
  ascii(quest.REWARD_NOTE, "Belohnungs-Fussnote")
  for i, seite in ipairs(quest.LORE) do
    ascii(seite.titel, "Lore-Titel " .. i)
    for k, s in ipairs(seite.absaetze) do ascii(s, "Lore " .. i .. "." .. k) end
  end
end

-- ---------------------------------------------------------------------------
-- Die Frist im Questtext kommt aus dem Parameter, nie als feste Zahl. Wer
-- im F10-Panel dreht, muss sie hier sofort lesen (GDD 4.2 fuer die Uhr am
-- Ring — dieselbe Zusage gilt fuers Questfenster).
-- ---------------------------------------------------------------------------
do
  local model = require("sim.model")
  local alt = model.params.try_time_limit.wert
  local body = table.concat(quest.BODY, " ")
  T.ok(body:find("{ZEIT}") ~= nil, "die Frist steht als Platzhalter im Text")
  T.ok(body:find("%d%d? Minuten") == nil and body:find("16:00") == nil,
    "keine festgetippte Frist im Questtext")

  model.params.try_time_limit.wert = 960
  T.ok(quest.fill("Frist {ZEIT}"):find("16:00") ~= nil,
    "Platzhalter zeigt 16:00 bei 960 s")
  model.params.try_time_limit.wert = 600
  T.ok(quest.fill("Frist {ZEIT}"):find("10:00") ~= nil,
    "... und 10:00, sobald der Parameter auf 600 steht")
  -- {REST} zaehlt mit der Try-Uhr herunter (Timed Quest wie im Original)
  T.eq(quest.fill("{REST}", { clock = 0 }), "10:00", "Restzeit beim Try-Start")
  T.eq(quest.fill("{REST}", { clock = 599 }), "0:01", "Restzeit kurz vor Ablauf")
  T.eq(quest.fill("{REST}", { clock = 900 }), "0:00",
    "Restzeit laeuft nicht ins Negative")
  model.params.try_time_limit.wert = alt
end

-- ---------------------------------------------------------------------------
-- Der Ueberlauf-Test, den es nie gab (Runde 18). Das Questfenster hat weder
-- setScissor noch Hoehenpruefung noch Scrolling: ein zu langer Text laeuft
-- ueber das Namensfeld hinaus aus dem Pergament heraus. Bis Runde 18 haette
-- das WEDER Stufe 1 NOCH der Zeichentest gemerkt — nur ein Auge im Spiel.
-- Hier mit einer bewusst KONSERVATIVEN Schaetzung (schmale Zeichen); die
-- Messung mit der echten Schrift steht im Zeichentest (Stufe 4b).
-- ---------------------------------------------------------------------------
do
  local FH = 15          -- love.graphics.getFont():getHeight() der Standardschrift
  local PX_PER_CHAR = 6.9 -- Vera Sans 12 misst im Mittel ~6,4; hier mit Reserve
  local function wrap(text, breite)
    return math.max(1, math.ceil(#text * PX_PER_CHAR / breite))
  end
  local w = quest.new({ try_nr = 4711 })
  local L = w:layout(1280, 800)
  local tw = quest.text_width(L)
  local unten = quest.walk(quest.blocks({ try_nr = 4711, clock = 0 }),
    quest.content_top(L), tw, wrap, FH)
  T.ok(unten <= quest.content_bottom(L),
    "Questtext passt ins Pergament (" .. math.floor(unten) .. " px, Platz bis "
    .. math.floor(quest.content_bottom(L)) .. " px)")

  -- Und die Pruefung muss beissen: ein Absatz mehr soll sie kippen
  local viele = quest.blocks({ try_nr = 4711, clock = 0 })
  viele[#viele + 1] = { kind = "para", text = string.rep("Fuellwort ", 60) }
  T.ok(quest.walk(viele, quest.content_top(L), tw, wrap, FH)
       > quest.content_bottom(L),
    "... und ein Absatz zu viel faellt auf")

  -- Das Fenster selbst muss in die Fensterhoehe passen (conf.lua: 800)
  T.ok(quest.PANEL_H + 16 <= 800, "Questfenster passt in die Fensterhoehe")
  T.ok(L.y >= 8, "Questfenster waechst nicht oben aus dem Bild")
end

-- Taste L: wegblenden und zurueckholen gilt nur noch fuers Questlog
-- (Issue #62, eingeschraenkt durch #83 — siehe Log-Block unten)

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

-- Easter Egg: das Echo erzaehlt (Issue #64). Blaettern, schliessen, und
-- keinerlei Spielwirkung — es gibt nichts anzunehmen.
do
  local lore = quest.new_lore()
  T.eq(lore.mode, "lore", "Lore-Modus")
  T.eq(lore.page, 1, "beginnt auf Seite 1")
  T.eq(lore:blocking(), false, "das Echo redet, es sperrt nichts")
  T.eq(lore:can_accept(), false, "hier gibt es nichts anzunehmen")
  T.eq(lore:lore_prev(), false, "vor Seite 1 gibt es nichts")
  for i = 2, #quest.LORE do
    lore:lore_next()
    T.eq(lore.page, i, "blaettert auf Seite " .. i)
  end
  lore:lore_next()
  T.eq(lore:visible(), false, "nach der letzten Seite ist Schluss")
  T.ok(#quest.LORE >= 5, "die Geschichte hat mehrere Seiten")
  for i, page in ipairs(quest.LORE) do
    T.ok(page.titel and #page.titel > 2, "Seite " .. i .. " hat einen Titel")
    T.ok(page.absaetze and #page.absaetze >= 1, "Seite " .. i .. " hat Text")
  end
end

-- Der Charge laeuft nur beim ersten Aufploppen; erneutes Anklicken oeffnet
-- direkt (Issue #73)
do
  local direkt = quest.new(nil, true)
  T.eq(direkt.state, "open", "erneutes Anklicken chargt nicht noch einmal")
  local erst = quest.new()
  T.eq(erst.state, "approach", "beim ersten Mal chargt es")
  erst:update(0.2)
  T.eq(erst.state, "approach", "und braucht dafuer einen Moment")
  erst:update(1.2)
  T.eq(erst.state, "open", "danach steht das Fenster")
end

-- Der Sound des Charges ist NICHT der Schrei (GDD 12 Nr. 16/17, Issue #73)
do
  local manifest = require("assets.manifest")
  T.ok(manifest.snd_echo_charge ~= nil, "eigener Sound-Slot fuer den Charge")
  T.ok(manifest.snd_echo_charge.datei:find("echo") ~= nil,
    "und er heisst nach dem Echo, nicht nach Leeroy")
end
