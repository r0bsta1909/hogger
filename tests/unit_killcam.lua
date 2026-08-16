-- tests/unit_killcam.lua — Killcam-Zeilen (GDD Kap. 11): Pool ~30,
-- kontextsensitiv, deterministische Rotation ohne RNG.

local killcam = require("game.gamesim.killcam")

T.ok(killcam.count() >= 28, "Pool umfasst ~30 Zeilen (" .. killcam.count() .. ")")

-- jede Todesursache liefert immer eine Zeile (alle Zaehlerstaende)
for cause = 1, 9 do
  for deaths = 0, 20 do
    local line = killcam.pick(cause, false, deaths, false)
    T.ok(type(line) == "string" and #line > 0,
      "Zeile fuer Ursache " .. cause .. ", Tod " .. deaths)
  end
end
T.ok(#killcam.pick(nil, nil, 0, nil) > 0, "unbekannte Ursache faellt auf Allgemein zurueck")

-- Kontext: Krit schlaegt alles, Heilung nur bei Hogger-Ursachen
T.ok(killcam.pick(2, true, 0, false):find("5%-Prozent")
     or killcam.pick(2, true, 0, false):find("zerschmettert")
     or killcam.pick(2, true, 0, false):find("RNG"),
  "Krit-Tod bekommt eine Krit-Zeile")
T.eq(killcam.pick(1, false, 0, true),
     "Der Priester hat dich geheilt. Deshalb bist du tot.",
  "frisch geheilt: die GDD-Beispielzeile")
T.ok(killcam.pick(5, false, 0, true):find("WILDSCHWEIN") ~= nil,
  "Mob-Tod ignoriert den Heilungs-Kontext (Wildschwein-Zeile)")

-- deterministische Rotation: gleicher Kontext -> gleiche Zeile,
-- naechster Tod -> andere Zeile (Gruppen > 1)
T.eq(killcam.pick(2, false, 1, false), killcam.pick(2, false, 1, false),
  "deterministisch bei gleichem Kontext")
T.ok(killcam.pick(2, false, 1, false) ~= killcam.pick(2, false, 2, false),
  "Rotation ueber den Todeszaehler")

-- Serientod (jeder 7.) bekommt die Zaehl-Zeile
T.ok(killcam.pick(1, false, 7, false):find("RECOUNT zaehlt") ~= nil,
  "Serientod-Zeile beim 7. Tod")
