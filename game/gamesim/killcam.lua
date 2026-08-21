-- game/gamesim/killcam.lua — Killcam-Zeilen (GDD Kap. 11): 2 s nach dem
-- eigenen Tod, sarkastischer RECOUNT-9000-Ton, Pool ~30, kontextsensitiv.
-- Reines Lua: der Todesursachen-Kontrakt (CAUSE) wird von der Sim in das
-- death-Event geschrieben (val), die Zeilenwahl laeuft client-seitig und
-- deterministisch (Rotation ueber den eigenen Todeszaehler, kein RNG).
-- Alle Zeilen sind VORSCHLAG — Fiktion entscheidet Rob (CLAUDE.md).

local K = {}

-- Todesursache im death-Event (val); Sim-Seite: step.lua
K.CAUSE = {
  autohit = 1, charge = 2, slice = 3, dot = 4,
  boar = 5, wolf = 6, kobold = 7, murloc = 8, add = 9,
  enrage = 10, -- Runde 18: die Schockwelle am Ende der Frist (GDD 6/9.1)
}

-- Zeilengruppen je Ursache
local GROUPS = {
  [1] = { -- Hogger-Autohit / Allgemein
    "Todesursache: Optimismus.",
    "Todesursache: Nahkampf. Mit Stoffhose.",
    "Du hast tapfer im Weg gestanden.",
    "Hogger 1, Statistik 0.",
    "Der Boden dankt fuer die Spende.",
    "Range-Check: nicht bestanden.",
    "Immerhin: schnell.",
  },
  [2] = { -- Rushing Charge
    "Charge gesehen. Charge gegessen.",
    "Die blinkende Linie war keine Deko.",
    "Weitester Spieler. Groesster Fehler.",
    "Flugstunde: kostenlos. Landung: toedlich.",
  },
  [3] = { -- Vicious Slice
    "Vicious Slice. Der Name war Programm.",
    "Angeschnitten und abgelaufen.",
  },
  [4] = { -- Blutung
    "Verblutet. In Zeitlupe.",
    "Die letzten fuenf HP waren geliehen.",
  },
  [5] = { -- Wildschwein
    "Von einem Wildschwein getoetet. Einem WILDSCHWEIN.",
    "Das Schwein war Stufe 1. Du auch. Es war besser.",
  },
  [6] = { -- Junger Wolf
    "Ein junger Wolf. Nicht mal ein alter.",
    "Alle zergen Hogger. Dich frass ein Wolf.",
  },
  [7] = { -- Kobold
    "Du hast die Kerze genommen. Irgendwie.",
  },
  [8] = { -- Murloc
    "Mrglglglgl. Das hiess: du bist tot.",
    "Der Fisch hat gewonnen.",
  },
  [9] = { -- Gnoll-Welpe
    "Ein Welpe. Niemand hat es gesehen. Ausser allen.",
  },
  [10] = { -- Enrage: Hogger wurde langweilig (Runde 18)
    "Hogger wurde langweilig. Du warst der Beweis.",
    "Er hatte Besseres vor. Zum Beispiel das.",
    "Todesursache: Ungeduld. Nicht deine.",
    "Ihr wart zu langsam. Alle. Gleichzeitig.",
  },
}

local CRIT_LINES = { -- Krit-Tod (der "WAS?!"-Moment, GDD 9.2)
  "Kritisch zerschmettert. Volle Wucht. Respekt.",
  "RNG sagt: nein.",
  "Das war der 5-Prozent-Moment.",
}
local HEALED_LINES = { -- kurz zuvor geheilt (GDD-Beispielzeile)
  "Der Priester hat dich geheilt. Deshalb bist du tot.",
  "Frisch geheilt ins Grab. Effizient.",
}
local SERIAL_LINE = "... zum wiederholten Male. RECOUNT zaehlt mit: viele."

-- fuer den Pool-Test (~30 Zeilen)
function K.count()
  local n = #CRIT_LINES + #HEALED_LINES + 1
  for _, g in pairs(GROUPS) do n = n + #g end
  return n
end

-- cause: CAUSE-Wert aus dem death-Event; crit: crit-Flag des Events;
-- deaths: eigener Todeszaehler (Rotation); healed: in den letzten ~4 s
-- geheilt worden. Rueckgabe: eine Zeile, immer.
function K.pick(cause, crit, deaths, healed)
  deaths = deaths or 0
  if crit then
    return CRIT_LINES[1 + deaths % #CRIT_LINES]
  end
  if healed and (cause or 0) <= 4 then
    return HEALED_LINES[1 + deaths % #HEALED_LINES]
  end
  if deaths > 0 and deaths % 7 == 0 then
    return SERIAL_LINE
  end
  local group = GROUPS[cause] or GROUPS[1]
  return group[1 + deaths % #group]
end

return K
