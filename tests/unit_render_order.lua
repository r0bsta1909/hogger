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
