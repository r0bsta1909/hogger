-- tests/unit_statboard.lua — Statistik-Tafel (GDD Kap. 11): zweispaltiger
-- Aufbau, Maxima mit deterministischem Gleichstand, Titelvergabe,
-- Wipe-Pointe ("Er hatte noch 4 %.").

local world = require("game.gamesim.world")
local statboard = require("game.gamesim.statboard")

local state = world.new(42)
world.add_leeroy(state)
local a = world.add_player(state, "Anna")
local b = world.add_player(state, "Bert")
world.begin_try(state, {})

local s = state.stats
s.players[a] = { dmg = 120, deaths = 3, ghost_t = 40.7, eaten = 2,
                 heal_aggro = 1, interrupts = 4, mob_kills = 0 }
s.players[b] = { dmg = 200, deaths = 1, ghost_t = 10, eaten = 0,
                 heal_aggro = 0, interrupts = 1, mob_kills = 3 }
s.hogger = { dmg = 999.4, kills = 4, crit_kills = 1, eaten = 2,
             healed = 300.6, interrupts = 5, charges = 7 }
s.first_death = a
s.boar_victim = "Bert"
state.players[b].kupfer = 9
state.players[a].jumps = 33
state.players[b].ding_done = true
state.hogger.hp = state.hogger.max_hp * 0.04

local function row(rows, label)
  for _, r in ipairs(rows) do
    if r[1] == label then return r[2] end
  end
  return nil
end

local board = statboard.build(state, false)
T.ok(board.header:find("Wipe") ~= nil, "Wipe im Titel")
T.eq(#board.hogger, 8, "acht Hogger-Zeilen (GDD 11)")
T.eq(row(board.hogger, "Gesamtschaden"), "999", "Hogger-Schaden gerundet")
T.eq(row(board.hogger, "davon kritisch zerschmettert"), "1", "Krit-Kills")
T.eq(row(board.hogger, "Geheilte HP"), "301", "Fress-Heilung gerundet")
T.eq(row(board.hogger, "Rest-HP"), "4 %", "Rest-HP in Prozent")
T.eq(board.big, "Er hatte noch 4 %.", "Wipe-Pointe gross (GDD 11)")

T.eq(row(board.raid, "Meister Schaden"), "Bert - 200", "Meister Schaden")
T.eq(row(board.raid, "Am haeufigsten gestorben"), "Anna - 3x", "Tode")
T.eq(row(board.raid, "Meiste Zeit als Geist"), "Anna - 40 s", "Geisterzeit")
T.eq(row(board.raid, "Am haeufigsten gefressen worden"), "Anna - 2x", "gefressen")
T.eq(row(board.raid, "Reichster Spieler"), "Bert - 9 Kupfer", "Kupfer")
T.eq(row(board.raid, "Erster Tod des Trys"), "Anna", "erster Tod ohne Anhang")
T.eq(row(board.raid, "Von einem Wildschwein getoetet"), "Bert", "Wildschwein-Zeile")
T.eq(row(board.raid, "Meiste Spruenge"), "Anna - 33", "Sprung-Zaehler (GDD 4.1)")

local titles = table.concat(board.titles, "; ")
T.ok(titles:find("Anna, der Gefressene") ~= nil, "Titel: der Gefressene")
T.ok(titles:find("Anna, die Geisterstimme") ~= nil, "Titel: die Geisterstimme")
T.ok(titles:find("Anna, der Unvorsichtige") ~= nil, "Titel: der Unvorsichtige")
T.ok(titles:find("Anna, der Zappelphilipp") ~= nil, "Titel: der Zappelphilipp")
T.ok(titles:find("Bert, der Zweite") ~= nil, "Titel: der Zweite (DING, GDD 7.3)")

-- Sieg: keine Wipe-Pointe, Rest-HP "0 (tot)"
local win = statboard.build(state, true)
T.ok(win.header:find("SIEG") ~= nil, "SIEG im Titel")
T.eq(row(win.hogger, "Rest-HP"), "0 (tot)", "Rest-HP beim Sieg")
T.eq(win.big, nil, "keine Wipe-Pointe beim Sieg")

-- neuer Try: Try-Zaehler bleiben weg, Abend-Werte (Kupfer, DING) bleiben
world.begin_try(state, {})
local fresh = statboard.build(state, false)
T.eq(#fresh.raid, 1, "nur die Abend-Zeile Reichster Spieler bleibt")
T.eq(row(fresh.raid, "Reichster Spieler"), "Bert - 9 Kupfer",
  "Kupfer persistiert ueber Trys (GDD 7.3)")
T.eq(#fresh.titles, 1, "nur der persistente DING-Titel bleibt")
T.ok(fresh.titles[1]:find("der Zweite") ~= nil, "der Zweite haengt am Abend")

-- REVANCHE (GDD 11): nur aus der Siegphase, Try-Zaehler bei 1
local step = require("game.gamesim.step")
state.phase = "won"
state.try_nr = 4711
local rev_ev = {}
T.ok(step.revanche(state, rev_ev), "REVANCHE aus der Siegphase")
T.eq(state.phase, "try", "REVANCHE startet den naechsten Durchlauf")
T.eq(state.try_nr, 1, "Try-Zaehler startet bei 1")
T.ok(state.players[a].ghost and not state.players[a].alive,
  "alle starten als Geist am Friedhof")
local found_start = false
for _, e in ipairs(rev_ev) do
  if e.ev == "try_start" then found_start = true end
end
T.ok(found_start, "try_start nach REVANCHE geloggt")
T.ok(not step.revanche(state, {}), "REVANCHE ausserhalb der Siegphase wirkungslos")
