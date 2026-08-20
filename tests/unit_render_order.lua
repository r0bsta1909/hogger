-- tests/unit_render_order.lua — deterministische Zeichenreihenfolge
-- (Runde 7): sorted_pids ersetzt pairs() ueber view.players, damit die
-- Ueberdeckung im Nahkampf-Klumpen und der Klick-Gleichstand stabil sind.

local render = require("game.render")

do
  local pids = render.sorted_pids({ [7] = {}, [2] = {}, [40] = {} })
  T.eq(#pids, 3, "order: alle pids kommen zurueck")
  T.eq(pids[1], 2, "order: kleinste pid zuerst")
  T.eq(pids[2], 7, "order: mittlere pid")
  T.eq(pids[3], 40, "order: groesste pid zuletzt")
end

do
  local pids = render.sorted_pids({})
  T.eq(#pids, 0, "order: leere Spielertabelle ergibt leere Liste")
end

-- Stabil ueber wiederholte Aufrufe (pairs-Reihenfolge darf nie durchschlagen)
do
  local players = { [3] = {}, [1] = {}, [12] = {}, [8] = {} }
  local a = render.sorted_pids(players)
  local b = render.sorted_pids(players)
  for i = 1, #a do
    T.eq(a[i], b[i], "order: Reihenfolge identisch bei Wiederholung #" .. i)
  end
end

-- ---------------------------------------------------------------------------
-- Gnarlwurzeln waren unsichtbar (Runde 14, #167): der Ring wurde mit
-- Radius 14 gezeichnet und danach vom Mob-Icon zugedeckt — Platzhalter-Icons
-- sind deckende Scheiben. Zwei Invarianten halten das jetzt fest.
-- ---------------------------------------------------------------------------
do
  local manifest = require("assets.manifest")
  local MOBS = { "add", "boar", "wolf", "kobold", "murloc" }

  -- Wie assets.draw zeichnet: Kantenlaenge = groesse * 1.8 * scale,
  -- Halbausdehnung also groesse * 0.9. Der Ring muss darueber liegen.
  local groesster = 0
  for _, kind in ipairs(MOBS) do
    local m = manifest["icon_" .. kind]
    T.ok(m ~= nil, "wurzeln: Manifest kennt icon_" .. kind)
    groesster = math.max(groesster, (m.groesse or 0) * 0.9)
  end
  T.ok(render.ROOT_RING_R > groesster,
    string.format("wurzeln: Ringradius %.1f liegt ausserhalb des groessten Mob-Icons (%.1f)",
      render.ROOT_RING_R, groesster))

  -- Und er muss NACH dem Icon gezeichnet werden. Das ist der eigentliche
  -- Fehler gewesen und in der Zeichenreihenfolge sonst unsichtbar.
  local src = assert(io.open("game/render.lua")):read("*a")
  local block = src:match("if view%.npcs then(.-)\n  end")
  T.ok(block ~= nil, "wurzeln: NPC-Zeichenblock im Renderer gefunden")
  if block then
    local icon_at = block:find('assets%.draw%("icon_" %.%. npc%.kind')
    local ring_at = block:find("npc%.rooted")
    T.ok(icon_at and ring_at and icon_at < ring_at,
      "wurzeln: der Wurzelring wird NACH dem Mob-Icon gezeichnet")
  end
end

-- Das root-Ereignis muss im Netz-Wortschatz stehen, sonst verwirft der Host
-- es in seiner Whitelist und kein Client sieht je einen Fliesstext (#167).
do
  local wire_src = assert(io.open("game/net/wire.lua")):read("*a")
  local ev_block = wire_src:match("W%.EV = {(.-)}")
  T.ok(ev_block and ev_block:find("root%s*=%s*%d"),
    "wurzeln: root steht in wire.EV (Ereignis-Whitelist des Hosts)")
  T.ok(ev_block and ev_block:find("taunt%s*=%s*19"),
    "wurzeln: die bestehenden Ereignisnummern bleiben unangetastet")
end

-- ---------------------------------------------------------------------------
-- Die Heil-Leiste muss NACH den Innenrand-Boegen gezeichnet werden
-- (Runde 15, #196): XP-Bogen (r-8) und Bedrohungsbogen (r-14) laufen genau
-- durch ihre Flaeche. Eine deckende Plakette hilft nichts, wenn die Boegen
-- danach darueber gezogen werden.
-- ---------------------------------------------------------------------------
do
  local src = assert(io.open("game/render.lua")):read("*a")
  local healbar = src:find("self:draw_healbar%(view, L%.frames%.healbar%)")
  local xp = src:find("%-%- XP%-Bogen an der Innenkante")
  local threat = src:find("%-%- Bedrohungsbogen an der Innenkante")
  T.ok(healbar and xp and threat, "order: alle drei Bloecke gefunden")
  if healbar and xp and threat then
    T.ok(healbar > xp, "order: Heil-Leiste wird nach dem XP-Bogen gezeichnet")
    T.ok(healbar > threat,
      "order: Heil-Leiste wird nach dem Bedrohungsbogen gezeichnet")
  end
end
