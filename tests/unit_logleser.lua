-- tests/unit_logleser.lua — Stufe 1: Abend-Auswertung aus dem Host-Log
-- (Runde 14, #175). Der Test baut Ereignisse, serialisiert sie mit DEM
-- Serialisierer des Hosts (game/gamesim/events.to_jsonl) und laesst den
-- Leser rechnen. Laeuft das 17.3-Schema auseinander, wird dieser Test rot
-- statt einer Auswertung, die stillschweigend Nullen liefert.

local events = require("game.gamesim.events")
local logreport = require("tools.logreport")
local T = _G.T

local TPS = 60 -- Ticks je Sekunde (GDD 14)

-- Baut eine Zeilenliste und gibt einen Iterator darueber zurueck
local function lines_of(list)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = events.to_jsonl(e) end
  local i = 0
  return function()
    i = i + 1
    return out[i]
  end, out
end

local function ev(t, name, src, dst, val, crit, art)
  return { t = t, ev = name, src = src, dst = dst, val = val,
           crit = crit, art = art }
end

-- ---------------------------------------------------------------------------
-- Ein Abend mit zwei Trys: einer gewonnen, einer als Wipe abgebrochen
-- ---------------------------------------------------------------------------
do
  local L = {}
  local function add(...) L[#L + 1] = ev(...) end

  -- Try 1: Sieg nach 8 Minuten
  add(0, "try_start", "host", "1", 10)
  add(0, "param_change", "init", "seed", 4242)
  -- Der GDD-Stand wird aus dem Modell gelesen, nicht hingeschrieben: eine
  -- feste 620 haette diesen Test bei der naechsten Eichung rot gemacht,
  -- ohne dass am Leser etwas kaputt gewesen waere (Runde 17).
  add(0, "param_change", "host", "hogger_hp_slope",
      require("sim.model").defaults.hogger_hp_slope)
  add(0, "revive", "1", "rogue", 0)
  add(0, "revive", "2", "priest", 0)
  add(0, "revive", "3", "warrior", 0)
  add(60, "damage", "1", "hogger", 10, false, "ability")
  add(60, "damage", "3", "hogger", 30, true, "autohit")
  add(70, "damage", "1", "12", 5, false, "ability")     -- Schaden an einem Mob
  add(90, "heal", "2", "3", 20, false)
  add(120, "eat_interrupt", "hogger", "1", 1)           -- der Tritt kam
  add(150, "eat_complete", "hogger", nil, nil)          -- Schurke lebte: gezaehlt
  add(180, "charge", "hogger", "3", nil)
  add(200, "death", "3", nil, 2, nil)                   -- Charge
  add(220, "death", "2", nil, 1, nil)                   -- Nahkampf, kurz nach Heilung? nein
  add(8 * 60 * TPS, "try_end", "host", "0", 1)

  -- Try 2: Wipe-Abbruch
  add(8 * 60 * TPS + 1, "try_start", "host", "2", 10)
  add(8 * 60 * TPS + 60, "damage", "1", "hogger", 40, false, "ability")
  add(8 * 60 * TPS + 90, "eat_complete", "hogger", nil, nil)
  add(8 * 60 * TPS + 100, "death", "1", nil, 6, nil)    -- Wolf
  add(8 * 60 * TPS + 120, "hogger_reset", "hogger", "wipe", 900)
  add(12 * 60 * TPS, "try_end", "host", "900", 0)

  local iter = lines_of(L)
  local r = logreport.analyse(iter)

  T.eq(r.n_try, 2, "logleser: zwei Trys erkannt")
  T.eq(r.wins, 1, "logleser: ein Sieg")
  T.eq(r.raid_n, 10, "logleser: Raidgroesse aus try_start")
  T.eq(r.seed, 4242, "logleser: Seed aus dem Parametersatz")
  T.eq(r.trys[1].won, true, "logleser: Try 1 gewonnen")
  T.near(r.trys[1].dauer, 8 * 60, "logleser: Trydauer aus Ticks in Sekunden")
  T.eq(r.trys[2].reset, "wipe", "logleser: Abbruchursache mitgelesen")
  T.eq(r.trys[2].rest_hp, 900, "logleser: Rest-HP beim Abbruch")

  T.eq(r.sum.deaths, 3, "logleser: drei Tode")
  T.eq(r.causes["Charge"], 1, "logleser: Todesursache Charge benannt")
  T.eq(r.causes["Wolf"], 1, "logleser: Todesursache Wolf benannt")
  T.eq(r.sum.dmg_hogger, 80, "logleser: Schaden an Hogger summiert")
  T.eq(r.sum.dmg_mobs, 5, "logleser: Schaden an Mobs getrennt gezaehlt")
  T.eq(r.sum.eat_interrupt, 1, "logleser: eine Unterbrechung")
  T.eq(r.sum.eat_complete, 2, "logleser: zwei durchgegangene Kanaele")
  T.eq(r.interrupts_by["1"], 1, "logleser: der Tritt haengt am Schurken")
  T.eq(r.dmg_by["3"], 30, "logleser: Schaden je Spieler")
  T.eq(r.deaths_by["3"], 1, "logleser: Tode je Spieler")
  T.eq(r.class_of["1"], "rogue", "logleser: Klasse aus dem revive-Ereignis")
  T.eq(r.sum.charges, 1, "logleser: Charges gezaehlt")
  T.eq(r.sum.heal_aggro, 1,
    "logleser: Tod kurz nach einer Heilung zaehlt als Heal-Aggro")
  T.eq(r.lines_bad, 0, "logleser: keine unlesbare Zeile im eigenen Format")

  -- Die Runde-12-Frage: beide Kanaele gingen durch, waehrend der Schurke
  -- lebte — genau das soll der Bericht sichtbar machen.
  T.eq(r.sum.complete_with_rogue, 2,
    "logleser: durchgegangenes Fressen trotz lebendem Schurken erkannt")

  local hints = logreport.hints(r)
  local found_rogue, found_mobs = false, false
  for _, h in ipairs(hints) do
    if h:find("Unterbrecher%-Rolle") then found_rogue = true end
    if h:find("Mobs") then found_mobs = true end
  end
  T.ok(found_rogue, "logleser: Hinweis auf die nicht gespielte Tritt-Rolle")
  T.ok(not found_mobs,
    "logleser: 6 %% Mob-Schaden loesen den Ablenkungs-Hinweis NICHT aus")

  local model = require("sim.model")
  local text = logreport.render(r, "test.jsonl", model.defaults)
  T.ok(text:find("Abend%-Auswertung"), "logleser: Bericht hat eine Ueberschrift")
  T.ok(text:find("SIEG"), "logleser: der Sieg steht in der Try-Tabelle")
  T.ok(text:find("Abbruch: alle tot"), "logleser: der Wipe-Abbruch wird benannt")
  T.ok(text:find("Alle geloggten Parameter standen auf GDD%-Stand"),
    "logleser: unveraenderte Parameter werden als solche gemeldet")
end

-- ---------------------------------------------------------------------------
-- Ein Abend auf verstellten Werten muss das sagen — sonst vergleicht man
-- Zahlen aus zwei verschiedenen Welten (Runde 14).
-- ---------------------------------------------------------------------------
do
  local model = require("sim.model")
  local L = {
    ev(0, "try_start", "host", "1", 5),
    ev(0, "param_change", "init", "seed", 1),
    ev(0, "param_change", "host", "hogger_hp_slope",
       model.defaults.hogger_hp_slope + 100),
    ev(60 * 60, "try_end", "host", "0", 1),
  }
  local r = logreport.analyse((lines_of(L)))
  local text = logreport.render(r, "verstellt.jsonl", model.defaults)
  T.ok(text:find("1 Parameter wichen vom GDD%-Stand ab"),
    "logleser: verstellter Parameter wird ausgewiesen")
  T.ok(text:find("hogger_hp_slope"),
    "logleser: der verstellte Parameter steht namentlich da")
end

-- ---------------------------------------------------------------------------
-- Robustheit: Muell im Log darf nicht die Auswertung kippen
-- ---------------------------------------------------------------------------
do
  local out = { '{"kaputt":1}', "", "kein json",
                events.to_jsonl(ev(0, "try_start", "host", "7", 20)),
                events.to_jsonl(ev(600, "try_end", "host", "0", 1)) }
  local i = 0
  local r = logreport.analyse(function() i = i + 1; return out[i] end)
  T.eq(r.lines_bad, 3, "logleser: unlesbare Zeilen werden gezaehlt")
  T.eq(r.n_try, 1, "logleser: der gueltige Try wird trotzdem ausgewertet")
  T.eq(r.wins, 1, "logleser: ... und als Sieg gewertet")
end

-- ---------------------------------------------------------------------------
-- Der Grund des Try-Endes (Runde 17). Bis dahin endete ein abgelaufenes
-- Zeitlimit ereignislos und war im Log von einem Wipe nicht zu unterscheiden
-- — genau daran scheiterte die Auswertung von Robs Abend.
-- ---------------------------------------------------------------------------
do
  local model = require("sim.model")
  local function ende(t, rest, won, reason)
    return { t = t, ev = "try_end", src = "host", dst = tostring(rest),
             val = won and 1 or 0, reason = reason }
  end
  local L = {
    ev(0, "param_change", "init", "try_time_limit", 900),
    ev(0, "try_start", "host", "1", 10),
    ende(60 * TPS, 0, true, "win"),
    ev(60 * TPS + 1, "try_start", "host", "2", 10),
    ev(60 * TPS + 60, "hogger_reset", "hogger", "no_contact", 500),
    ende(120 * TPS, 500, false, "no_contact"),
    ev(120 * TPS + 1, "try_start", "host", "3", 10),
    ende(1020 * TPS, 800, false, "timeout"),
  }
  local r = logreport.analyse((lines_of(L)))
  T.eq(r.n_try, 3, "logleser: drei Trys")
  T.eq(r.trys[3].reason, "timeout", "logleser: reason wird aus dem Log gelesen")

  local text, geraten = logreport.outcome(r.trys[3], r.params)
  T.eq(text, "Zeit abgelaufen", "logleser: Zeitlimit wird benannt")
  T.eq(geraten, false, "logleser: der Grund stand im Log, er wurde nicht geraten")

  local t2 = logreport.outcome(r.trys[2], r.params)
  T.eq(t2, "Abbruch: niemand am Boss", "logleser: Kein-Kontakt wird benannt")

  local out = logreport.render(r, "gruende.jsonl", model.defaults)
  T.ok(out:find("Trys nach Ursache"), "logleser: Bericht gruppiert nach Ursache")
  T.ok(out:find("Zeit abgelaufen"), "logleser: das Zeitlimit steht im Bericht")
  T.ok(out:find("aus der Dauer geschlossen") == nil,
    "logleser: nichts wird geraten, wenn der Grund im Log steht")
end

-- Altlogs (Robs 30.248 Zeilen) haben das Feld nicht. Der Leser darf daraus
-- schliessen — aber er muss es dazusagen. Ein Bericht, der "Zeit abgelaufen"
-- behauptet, wo er es nur vermutet, ist schlimmer als "unbekannt".
do
  local model = require("sim.model")
  local L = {
    ev(0, "param_change", "init", "try_time_limit", 900),
    ev(0, "try_start", "host", "1", 10),
    ev(900 * TPS, "try_end", "host", "800", 0),      -- exakt an der Frist
    ev(900 * TPS + 1, "try_start", "host", "2", 10),
    ev(910 * TPS, "try_end", "host", "700", 0),      -- viel zu kurz
  }
  local r = logreport.analyse((lines_of(L)))

  local t1, geraten1 = logreport.outcome(r.trys[1], r.params)
  T.eq(t1, "Zeit abgelaufen", "altlog: aus der Dauer auf das Zeitlimit geschlossen")
  T.eq(geraten1, true, "altlog: der Schluss ist als Schluss gekennzeichnet")

  local t2, geraten2 = logreport.outcome(r.trys[2], r.params)
  T.eq(t2, "Ende unbekannt (altes Log)", "altlog: ohne Anhaltspunkt wird nichts erfunden")
  T.eq(geraten2, false, "altlog: 'unbekannt' ist kein Schluss, sondern ein Eingestaendnis")

  local out = logreport.render(r, "alt.jsonl", model.defaults)
  T.ok(out:find("aus der Dauer geschlossen"),
    "altlog: der Bericht macht den Schluss sichtbar")
  T.ok(out:find("Ende unbekannt"),
    "altlog: der unklare Try wird als unklar ausgewiesen")
end

-- ---------------------------------------------------------------------------
-- Ein Log ohne abgeschlossenen Try darf keinen Bericht erfinden
-- ---------------------------------------------------------------------------
do
  local i = 0
  local r = logreport.analyse(function() i = i + 1; return nil end)
  T.eq(r.n_try, 0, "logleser: leeres Log ergibt null Trys")
  local text = logreport.render(r, "leer.jsonl", nil)
  T.ok(text:find("nichts zu rechnen"), "logleser: leeres Log sagt das klar")
end
