-- tests/unit_uiorder.lua — Klick- und Tastenreihenfolge der Overlays
-- (Runde 19). Sie MUSS die Umkehrung der Zeichenreihenfolge sein: was oben
-- liegt, wird zuerst gefragt.
--
-- Warum es diesen Test gibt: bis Runde 18 lief es genau andersherum. Die
-- Statistik-Tafel wurde NACH dem Questfenster gezeichnet (lag also sichtbar
-- davor), aber VOR ihr gefragt — und der Quest-Block returnte bedingungslos,
-- ohne den Rueckgabewert anzusehen. Beim Spielstart erscheint die Wipe-Tafel
-- ueber dem noch offenen Questfenster; in der Ueberlappung (beide mittig,
-- 620x660 gegen 760x430) kam kein Klick mehr an. Rob konnte sie nur in zwei
-- rund 70 px schmalen Streifen links und rechts wegklicken — bzw. gar nicht,
-- solange das Fenster blockierte, und hielt das Auto-Ausblenden nach 10 s
-- fuer seinen Klickerfolg.
--
-- Warum als QUELLTEXT-Test: Stufe 1 laeuft mit vergiftetem love-Global, ein
-- echter Klick ist dort nicht ausloesbar. Dasselbe Muster benutzt
-- tests/unit_render_order.lua fuer dieselbe Fehlerklasse ("der Wurzelring
-- wird NACH dem Mob-Icon gezeichnet").

local src = assert(io.open("game/main.lua")):read("*a")

-- Den Rumpf einer love-Rueckruffunktion herausschneiden (bis zur naechsten
-- Funktion auf Spaltenebene 0)
local function funktion(name)
  local block = src:match("\nfunction love%." .. name .. "%b()(.-)\nend\n\nfunction ")
  return block or src:match("\nfunction love%." .. name .. "%b()(.-)\nend\n")
end

local zeichnen = funktion("draw")
local klicken = funktion("mousepressed")
local tasten = funktion("keypressed")
T.ok(zeichnen and #zeichnen > 0, "uiorder: love.draw gefunden")
T.ok(klicken and #klicken > 0, "uiorder: love.mousepressed gefunden")
T.ok(tasten and #tasten > 0, "uiorder: love.keypressed gefunden")

-- Die drei Overlays, um die es geht. Muster so gewaehlt, dass sie genau
-- einmal je Block vorkommen.
local OVERLAYS = {
  { name = "Questfenster", zeichnen = "app%.quest:draw",
    klicken = "app%.quest:visible", tasten = "app%.quest:blocking" },
  { name = "Statistik-Tafel", zeichnen = "app%.stats:draw",
    klicken = "app%.stats:mousepressed", tasten = "app%.stats:keypressed" },
  { name = "Beutefenster", zeichnen = "app%.victory:draw",
    klicken = "app%.victory:mousepressed", tasten = "app%.victory:keypressed" },
}

local function stelle(block, muster, was, name)
  local at = block:find(muster)
  T.ok(at ~= nil, "uiorder: " .. name .. " kommt in " .. was .. " vor")
  return at or 0
end

local z, k, t = {}, {}, {}
for _, o in ipairs(OVERLAYS) do
  z[o.name] = stelle(zeichnen, o.zeichnen, "love.draw", o.name)
  k[o.name] = stelle(klicken, o.klicken, "love.mousepressed", o.name)
  t[o.name] = stelle(tasten, o.tasten, "love.keypressed", o.name)
end

-- ---------------------------------------------------------------------------
-- Die eigentliche Zusage: gerechnet, nicht hingeschrieben. Wer eine neue
-- Ueberlagerung einschiebt, muss beide Stellen anfassen, sonst wird das hier
-- rot — auch fuer Overlays, die es heute noch gar nicht gibt.
-- ---------------------------------------------------------------------------
for _, a in ipairs(OVERLAYS) do
  for _, b in ipairs(OVERLAYS) do
    if a.name < b.name then
      local oben = (z[a.name] > z[b.name]) and a.name or b.name
      local unten = (oben == a.name) and b.name or a.name
      T.ok(k[oben] < k[unten], string.format(
        "uiorder: %s liegt ueber %s und wird beim Klick zuerst gefragt",
        oben, unten))
      T.ok(t[oben] < t[unten], string.format(
        "uiorder: %s liegt ueber %s und wird bei den Tasten zuerst gefragt",
        oben, unten))
    end
  end
end

-- ---------------------------------------------------------------------------
-- Und dieselbe Aussage noch einmal in Klartext, damit im Fehlerfall dasteht,
-- worum es geht — die Rechnung oben nennt Robs Fall nicht beim Namen.
-- ---------------------------------------------------------------------------
T.ok(z["Statistik-Tafel"] > z["Questfenster"],
  "uiorder: die Tafel wird NACH dem Questfenster gezeichnet, liegt also davor")
T.ok(k["Statistik-Tafel"] < k["Questfenster"],
  "uiorder: ... und wird deshalb beim Klick VOR dem Questfenster gefragt")
T.ok(t["Statistik-Tafel"] < t["Questfenster"],
  "uiorder: ESC erreicht die Tafel, bevor das Questfenster alle Tasten schluckt")

-- Die Tafel kennt ESC ueberhaupt (sonst waere die Reihenfolge folgenlos)
do
  local stats = require("game.ui.stats")
  local zu = { visible = true }
  T.eq(stats.keypressed(zu, "escape"), true, "uiorder: ESC schliesst die Tafel")
  T.eq(zu.visible, false, "uiorder: ... und sie ist danach wirklich weg")
  T.eq(stats.keypressed({ visible = true }, "space"), false,
    "uiorder: andere Tasten laesst die Tafel durch")
  T.eq(stats.keypressed({ visible = false }, "escape"), false,
    "uiorder: eine unsichtbare Tafel verbraucht kein ESC")
end
