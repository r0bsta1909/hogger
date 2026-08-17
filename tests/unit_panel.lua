-- tests/unit_panel.lua — F10-Tuning-Panel (GDD 17.6, Issues #81/#82):
-- Navigation/Clamping, Key-Repeat-Uhr und der CSV-Export der Abweichungen.
-- Love-frei: getestet werden action/repeat_step/csv, nie draw/update.

local model = require("sim.model")
local panelmod = require("game.ui.panel")

-- apply wie im Host (game/net/host.lua): clampen und in-place setzen
local function apply(key, value)
  local e = model.params[key]
  value = math.max(e.min, math.min(e.max, value))
  e.wert = value
  return value
end

local p = panelmod.new(apply)

-- Schluesselliste: vollstaendig aus M.params, sortiert nach Kapitel/Name
do
  local n = 0
  for _ in pairs(model.params) do n = n + 1 end
  T.eq(#p.keys, n, "Panel kennt jeden Parameter (GDD 17.6)")
  for i = 2, #p.keys do
    local a, b = model.params[p.keys[i - 1]], model.params[p.keys[i]]
    T.ok(a.kapitel < b.kapitel
      or (a.kapitel == b.kapitel and p.keys[i - 1] < p.keys[i]),
      "Sortierung Kapitel/Name stabil bei " .. p.keys[i])
  end
end

-- Defaults: beim Laden eingefroren, deckungsgleich mit den Startwerten
do
  local n = 0
  for k, e in pairs(model.params) do
    n = n + 1
    T.ok(model.defaults[k] ~= nil, "Default vorhanden fuer " .. k)
  end
  local m = 0
  for _ in pairs(model.defaults) do m = m + 1 end
  T.eq(m, n, "keine Geister-Defaults")
end

-- Navigation clampt an beiden Enden
p:action("up")
T.eq(p.cursor, 1, "up am Anfang bleibt bei 1")
p:action("pageup")
T.eq(p.cursor, 1, "pageup am Anfang bleibt bei 1")
for _ = 1, #p.keys + 20 do p:action("down") end
T.eq(p.cursor, #p.keys, "down clampt am Ende")
p:action("pagedown")
T.eq(p.cursor, #p.keys, "pagedown clampt am Ende")
T.eq(p:action("x"), false, "fremde Tasten gehen durch")

-- Wertaenderung: Schritt, Shift x10, Clamp an min/max (via apply)
p.cursor = 1
local k1 = p.keys[1]
local e1 = model.params[k1]
local orig = e1.wert
p:action("right")
T.near(e1.wert, math.min(e1.max, orig + e1.schritt), "rechts = +schritt")
p:action("left")
T.near(e1.wert, orig, "links = -schritt")
p:action("left", true)
T.ok(e1.wert >= e1.min, "Shift x10 haelt min ein")
apply(k1, orig)

-- Key-Repeat-Uhr (Issue #81): Verzoegerung, dann schnelle Wiederholung
do
  local q = panelmod.new(apply)
  T.eq(q:repeat_step("down", 0.1), 0, "Tastenwechsel: noch keine Wiederholung")
  T.eq(q:repeat_step("down", 0.2), 0, "unter der Verzoegerung passiert nichts")
  local fires = q:repeat_step("down", 0.3) -- gehalten: 0.5 s gesamt
  T.ok(fires >= 2, "nach der Verzoegerung feuert es mehrfach (" .. fires .. ")")
  local burst = q:repeat_step("down", 1.0)
  T.ok(burst >= 20, "eine Sekunde halten scrollt schnell (" .. burst .. ")")
  T.eq(q:repeat_step("up", 0.5), 0, "Tastenwechsel setzt die Uhr zurueck")
  T.eq(q:repeat_step(nil, 0.5), 0, "losgelassen feuert nichts")
  T.eq(q:repeat_step("up", 0.1), 0, "und die Uhr beginnt wieder vorn")
end

-- CSV-Export (Issue #82): NUR die Abweichungen vom GDD-Stand
do
  local csv, n = p:csv()
  T.eq(n, 0, "unveraendert: null Zeilen")
  T.eq(csv, "param;gdd_wert;wert\n", "nur die Kopfzeile")

  local ka, kb = p.keys[1], p.keys[2]
  local ea, eb = model.params[ka], model.params[kb]
  local oa, ob = ea.wert, eb.wert
  apply(ka, oa + ea.schritt)
  apply(kb, ob + eb.schritt)
  csv, n = p:csv()
  T.eq(n, 2, "zwei geaenderte Werte, zwei Zeilen")
  T.ok(csv:find(ka .. ";", 1, true) ~= nil, "geaenderter Parameter steht drin")
  T.ok(csv:find(string.format("%s;%g;%g", kb, model.defaults[kb], eb.wert),
    1, true) ~= nil, "Zeile ist param;gdd_wert;wert")

  -- zurueckgedreht faellt die Zeile wieder raus
  apply(ka, oa)
  csv, n = p:csv()
  T.eq(n, 1, "zurueckgedreht: Zeile verschwindet")
  T.ok(csv:find(ka, 1, true) == nil, "der zurueckgedrehte Parameter fehlt")
  apply(kb, ob)
  local _, n2 = p:csv()
  T.eq(n2, 0, "alles zurueck: wieder leer")
end
