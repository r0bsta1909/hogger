-- tests/unit_panel.lua — F10-Tuning-Panel (GDD 17.6, Issues #81/#82/#97):
-- Kategorien (abschliessend!), zweistufige Navigation, Key-Repeat-Uhr und
-- der CSV-Export der Abweichungen. Love-frei: getestet werden
-- action/repeat_step/csv/category_of, nie draw/update.

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

-- Schluesselliste: vollstaendig aus M.params (fuer den CSV-Export)
do
  local n = 0
  for _ in pairs(model.params) do n = n + 1 end
  T.eq(#p.keys, n, "Panel kennt jeden Parameter (GDD 17.6)")
end

-- Kategorien (Runde 6, #97): ABSCHLIESSEND — kein Parameter faellt nach
-- "sonstiges", jeder gehoert genau einer Kategorie an, die Summe stimmt
do
  T.eq(#p.by_kat.sonstiges, 0,
    "Kategorien abschliessend: nichts landet in Sonstiges")
  local sum = 0
  for _, kat in ipairs(panelmod.KAT_ORDER) do
    sum = sum + #p.by_kat[kat]
    T.ok(panelmod.KAT_NAME[kat] ~= nil, "Kategorie hat einen Namen: " .. kat)
  end
  T.eq(sum, #p.keys, "jeder Parameter genau einmal kategorisiert")
  for _, kat in ipairs(p.kats) do
    T.ok(#p.by_kat[kat] > 0, "gelistete Kategorie ist nicht leer: " .. kat)
  end
  -- Stichproben der Zuordnung
  T.eq(panelmod.category_of("respawn_base", "9.3"), "loop",
    "Respawn gehoert zum Loop, nicht zu Hogger")
  T.eq(panelmod.category_of("hogger_hp_slope", "9.3"), "hogger",
    "Hogger-HP gehoert zu Hogger")
  T.eq(panelmod.category_of("mage_fireball_dmg", "8.2"), "klassen",
    "Feuerball gehoert zu Klassen")
  T.eq(panelmod.category_of("mob_patrol_radius", "7.2"), "mobs",
    "Patrouille gehoert zu Mobs")
  T.eq(panelmod.category_of("voellig_neu", "99.9"), "sonstiges",
    "Unbekanntes faellt nach Sonstiges (und macht diese Suite rot)")
end

-- Navigation (Runde 6, #97): Kategorienliste -> Parameter -> zurueck
do
  T.eq(p.mode, "kats", "Einstieg auf der Kategorienliste")
  p:action("up")
  T.eq(p.kat_cursor, 1, "up am Anfang bleibt bei 1")
  for _ = 1, #p.kats + 5 do p:action("down") end
  T.eq(p.kat_cursor, #p.kats, "down clampt am Ende der Kategorien")
  p.kat_cursor = 1
  T.ok(p:action("return"), "Enter oeffnet die Kategorie")
  T.eq(p.mode, "params", "danach steht man in den Parametern")
  local list = p.by_kat[p:current_kat()]
  for _ = 1, #list + 20 do p:action("down") end
  T.eq(p.cursors[p:current_kat()], #list, "Cursor clampt am Listenende")
  T.ok(p:action("backspace"), "Backspace fuehrt zurueck")
  T.eq(p.mode, "kats", "wieder auf der Kategorienliste")
  T.ok(p:action("right"), "Rechts oeffnet ebenfalls")
  T.eq(p.cursors[p:current_kat()], #list,
    "der Cursor der Kategorie ist gemerkt")
  T.eq(p:action("x"), false, "fremde Tasten gehen durch")
  p:action("backspace")
end

-- Wertaenderung: Schritt, Shift x10, Clamp an min/max (via apply)
do
  p.kat_cursor = 1
  p:action("return")
  local kat = p:current_kat()
  p.cursors[kat] = 1
  local k1 = p.by_kat[kat][1]
  local e1 = model.params[k1]
  local orig = e1.wert
  p:action("right")
  T.near(e1.wert, math.min(e1.max, orig + e1.schritt), "rechts = +schritt")
  p:action("left")
  T.near(e1.wert, orig, "links = -schritt")
  p:action("left", true)
  T.ok(e1.wert >= e1.min, "Shift x10 haelt min ein")
  apply(k1, orig)
  p:action("backspace")
end

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

-- CSV-Export (Issue #82): NUR die Abweichungen, ueber alle Kategorien
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

  -- die Kategorienliste zaehlt die Abweichungen mit
  local total = 0
  for _, kat in ipairs(p.kats) do total = total + p:changed_in(kat) end
  T.eq(total, 2, "Abweichungs-Zaehler der Kategorien stimmt")

  apply(ka, oa)
  apply(kb, ob)
  local _, n2 = p:csv()
  T.eq(n2, 0, "alles zurueck: wieder leer")
end
