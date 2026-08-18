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

-- Runde 9 (#119): jeder Parameter ist erklaert ------------------------------
local docs = require("sim.param_docs")

do -- Vollstaendigkeit: das ist der eigentliche Zweck des Tests
  for k in pairs(model.params) do
    local d = docs[k]
    T.ok(type(d) == "table" and type(d[1]) == "string" and #d[1] > 0
         and type(d[2]) == "string" and #d[2] > 0,
      "Panel erklaert jeden Parameter (GDD 17.6): " .. k)
  end
  for k in pairs(docs) do
    T.ok(model.params[k] ~= nil,
      "Beschreibung ohne Parameter (Waise): " .. k)
  end
end

do -- Textqualitaet: ASCII, Form, Laenge, KEINE Zahlen
  for k, d in pairs(docs) do
    if type(d) == "table" and d[1] and d[2] then
      for i = 1, 2 do
        local ascii = true
        for pos = 1, #d[i] do
          local b = d[i]:byte(pos)
          if b < 32 or b > 126 then ascii = false break end
        end
        T.ok(ascii, "Beschreibung ist ASCII (" .. k .. ", Feld " .. i .. ")")
        T.ok(d[i]:find("%d") == nil,
          "keine Zahlen im Text -- der Tooltip zeigt den Live-Wert (" .. k .. ")")
      end
      T.ok(d[1]:sub(-1) == ".", "Beschreibung endet auf einem Punkt: " .. k)
      T.ok(d[2]:sub(1, 9) == "hoeher = ",
        "Wirkungsrichtung beginnt mit 'hoeher = ': " .. k)
      T.ok(#d[1] <= 80, "Beschreibung passt in den Tooltip: " .. k)
      T.ok(#d[2] <= 60, "Wirkungsrichtung passt in den Tooltip: " .. k)
    end
  end
end

do -- Kategorien haben ebenfalls eine Erklaerung
  for _, kat in ipairs(panelmod.KAT_ORDER) do
    local d = panelmod.KAT_DESC[kat]
    T.ok(type(d) == "string" and #d > 0 and d:sub(-1) == ".",
      "Kategorie erklaert: " .. kat)
  end
end

do -- Hover-Uhr (love-frei, Muster repeat_step)
  local q = panelmod.new(apply)
  T.eq(q:hover_step("gcd", 0.5), false,
    "Hover: der erste Frame auf einer Zeile startet die Uhr bei null")
  T.eq(q:hover_step("gcd", 0.5), false, "Hover: unter der Schwelle kein Tooltip")
  T.eq(q:hover_step("gcd", 0.4), false, "Hover: knapp darunter immer noch nicht")
  T.eq(q:hover_step("gcd", 0.2), true, "Hover: ab einer Sekunde faellig")
  T.eq(q:hover_step("melee_range", 0.2), false, "Hover: Zeilenwechsel setzt zurueck")
  T.eq(q:hover_step(nil, 5), false, "Hover: neben der Liste kein Tooltip")
  T.eq(q.hover_t, 0, "Hover: Uhr steht wieder auf null")
end

do -- Tooltip-Zeilen: Live-Wert und Stellbereich kommen aus model.params
  local q = panelmod.new(apply)
  local lines = q:tooltip_lines("gcd")
  T.eq(#lines, 4, "Tooltip: vier Zeilen")
  T.ok(lines[1]:find("gcd") ~= nil, "Tooltip: Kopfzeile nennt den Parameter")
  T.ok(lines[1]:find(string.format("%g", model.params.gcd.wert), 1, true) ~= nil,
    "Tooltip: Kopfzeile zeigt den LIVE-Wert")
  T.eq(lines[2], docs.gcd[1], "Tooltip: Beschreibung")
  T.eq(lines[3], docs.gcd[2], "Tooltip: Wirkungsrichtung")
  T.ok(lines[4]:find("Kapitel") ~= nil and lines[4]:find("Bereich") ~= nil,
    "Tooltip: Kapitel und Stellbereich")
  local o = model.params.gcd.wert
  apply("gcd", o + model.params.gcd.schritt)
  local l2 = q:tooltip_lines("gcd")
  T.ok(l2[1] ~= lines[1], "Tooltip: der Wert in der Kopfzeile zieht nach")
  apply("gcd", o)
  T.ok(q:tooltip_lines("hogger") ~= nil, "Tooltip: auch Kategorien erklaeren sich")
  T.eq(q:tooltip_lines(nil), nil, "Tooltip: ohne Zeile kein Text")
end

do -- row_at: Geometrie der Listenzeilen (love-frei, line_h vom Aufrufer)
  local q = panelmod.new(apply)
  local W, H, LH = 1280, 800, 18
  local pw, ph = 560, H - 120
  local px, py = W - pw - 24, 60
  local top = py + 32
  T.eq(q:row_at(px + 20, py + 10, W, H, LH), nil,
    "row_at: die Titelzeile trifft nichts")
  T.eq(q:row_at(px - 5, top + 2, W, H, LH), nil,
    "row_at: links neben dem Panel trifft nichts")
  T.eq(q:row_at(px + 20, py + ph - 10, W, H, LH), nil,
    "row_at: die Fusszeile trifft nichts")
  T.eq(q:row_at(px + 20, top + 2, W, H, LH), q.kats[1],
    "row_at: erste Kategorie auf der Einstiegsebene")
  q:action("return")
  local list = q.by_kat[q:current_kat()]
  T.eq(q:row_at(px + 20, top + 2, W, H, LH), list[1],
    "row_at: erste Parameterzeile")
  T.eq(q:row_at(px + 20, top + LH + 2, W, H, LH), list[2],
    "row_at: zweite Parameterzeile")
  q.scroll = 3
  T.eq(q:row_at(px + 20, top + 2, W, H, LH), list[4],
    "row_at: Scroll-Offset wird beruecksichtigt")
end
