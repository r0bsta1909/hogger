-- tests/unit_picktarget.lua — Stufe 1: Karten-Klickziel (Runde 13, #154).
-- render.pick_target ist love-frei: der Rechtsklick ist der Angriffsklick
-- und bevorzugt Feinde (Hogger gewinnt in seinem Icon-Radius 48 x scale),
-- der Linksklick waehlt wie seit Runde 7 das naechste Zentrum in 24 px.

local R = require("game.render")
local world = require("game.gamesim.world")
local T = _G.T

local function ident(x, y) return x, y end
local SCALE1 = 1.26 -- Zoomstufe 1 am Standardfenster (378 / 300)

local function mkview(opts)
  return {
    me = 99,
    players = (opts and opts.players) or {},
    npcs = (opts and opts.npcs) or {},
    hogger = (opts and opts.hogger)
             or { x = 500, y = 500, hp = 1000, state = "combat" },
  }
end

-- Der Kernfall (#154): Spieler liegt DIREKT unterm Cursor, 30 px neben
-- Hoggers Zentrum — der Rechtsklick trifft trotzdem den Gnoll (Icon-Radius
-- ~60 px), der Linksklick am selben Punkt weiter den Spieler (Heiler!)
do
  local v = mkview({ players = { [1] = { x = 500, y = 530 } } })
  local id, enemy = R.pick_target(v, 500, 530, ident, SCALE1, true)
  T.eq(id, world.HOGGER_ID, "pick: Rechtsklick im Klumpen trifft Hogger")
  T.ok(enemy, "pick: Hogger ist Feind (engaged)")
  local id2, enemy2 = R.pick_target(v, 500, 530, ident, SCALE1, false)
  T.eq(id2, 1, "pick: Linksklick am selben Punkt waehlt den Spieler")
  T.ok(not enemy2, "pick: Spieler ist kein Feind")
end

-- Ausserhalb des Ring-Radius faellt der Rechtsklick auf die normale Wahl
do
  local v = mkview({ players = { [1] = { x = 600, y = 500 } } })
  local id, enemy = R.pick_target(v, 600, 500, ident, SCALE1, true)
  T.eq(id, 1, "pick: Rechtsklick fern von Hogger nimmt den Spieler")
  T.ok(not enemy, "pick: ... engaged dann aber nicht")
end

-- Mobs gewinnen den Rechtsklick vor Spielern (im normalen 24-px-Radius);
-- der Linksklick-Gleichstand gehoert weiter dem Spieler (Runde 7)
do
  local v = mkview({
    players = { [1] = { x = 600, y = 500 } },
    npcs = { [120] = { kind = "wolf", x = 610, y = 500 } },
  })
  local id, enemy = R.pick_target(v, 605, 500, ident, SCALE1, true)
  T.eq(id, 120, "pick: Rechtsklick nimmt den Mob vor dem Spieler")
  T.ok(enemy, "pick: Mob ist Feind")
  local id2 = (R.pick_target(v, 605, 500, ident, SCALE1, false))
  T.eq(id2, 1, "pick: Linksklick-Gleichstand gehoert dem Spieler")
end

-- Ein toter oder resettender Hogger ist NIE Klickziel (vorher klickbar)
do
  local v = mkview({ hogger = { x = 500, y = 500, hp = 0, state = "combat" } })
  local id = (R.pick_target(v, 500, 500, ident, SCALE1, true))
  T.eq(id, nil, "pick: toter Hogger ist kein Rechtsklick-Ziel")
  local v2 = mkview({ hogger = { x = 500, y = 500, hp = 100, state = "reset" } })
  local id2 = (R.pick_target(v2, 500, 500, ident, SCALE1, true))
  T.eq(id2, nil, "pick: resettender Hogger ist kein Ziel")
  local id3 = (R.pick_target(v2, 500, 500, ident, SCALE1, false))
  T.eq(id3, nil, "pick: ... auch nicht per Linksklick")
end

-- Der eigene Spieler und Wichtel sind keine Klickziele
do
  local v = mkview({ players = { [99] = { x = 600, y = 500 } },
                     npcs = { [110] = { kind = "imp", x = 602, y = 500 } } })
  local id = (R.pick_target(v, 600, 500, ident, SCALE1, false))
  T.eq(id, nil, "pick: eigener Pfeil und Wichtel sind keine Klickziele")
end

-- Der Ring-Radius skaliert mit dem Zoom (48 x scale)
do
  local s3 = 0.63 -- Zoomstufe 3
  local v = mkview({})
  local out = (R.pick_target(v, 500 + 48 * s3 + 2, 500, ident, s3, true))
  T.eq(out, nil, "pick: knapp ausserhalb des Rings (Zoom 3) kein Treffer")
  local hit = (R.pick_target(v, 500 + 48 * s3 - 2, 500, ident, s3, true))
  T.eq(hit, world.HOGGER_ID, "pick: knapp innerhalb des Rings trifft")
end
