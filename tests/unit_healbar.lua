-- tests/unit_healbar.lua — Heil-Leiste (Runde 7, #103): love-freier
-- Zeilen-Builder (Reichweiten-Filter, Selbst-zuerst, stabile alphabetische
-- Sortierung, Geister/Tote raus, Ueberhang) und der reine Arithmetik-Hit-Test.

local render = require("game.render")
local model = require("sim.model")

local RANGE = 250

local function mkview()
  return {
    me = 5, me_x = 1000, me_y = 1000,
    names = { [1] = "Anna", [2] = "Bert", [3] = "Zora", [4] = "Karl",
              [5] = "Heiler", [6] = "Otto" },
    players = {
      [5] = { alive = true, class = "priest", hp = 50, x = 1000, y = 1000 },
      -- 249 px: drin
      [1] = { alive = true, class = "warrior", hp = 40, x = 1249, y = 1000 },
      -- 251 px: draussen
      [2] = { alive = true, class = "warrior", hp = 40, x = 1251, y = 1000 },
      -- Geist in Reichweite: unheilbar, raus
      [3] = { alive = false, ghost = true, class = "mage", x = 1010, y = 1000 },
      -- Toter in Reichweite: raus
      [4] = { alive = false, ghost = false, class = "rogue", x = 1020, y = 1000 },
      -- Leeroy in Reichweite: normal drin
      [6] = { alive = true, class = "warrior", is_leeroy = true, hp = 80,
              x = 1000, y = 1100 },
    },
  }
end

do
  local rows, more_n = render.heal_rows(mkview(), RANGE)
  T.eq(#rows, 3, "healbar: selbst + zwei Verbuendete in Reichweite")
  T.eq(more_n, 0, "healbar: kein Ueberhang")
  T.ok(rows[1].is_self, "healbar: selbst immer Zeile 1")
  T.eq(rows[1].name, "Heiler", "healbar: eigener Name in Zeile 1")
  T.eq(rows[1].hp_pct, 100, "healbar: Priester 50/50 = 100 %")
  T.eq(rows[2].name, "Anna", "healbar: 249 px ist in Reichweite, alphabetisch zuerst")
  T.eq(rows[2].hp_pct, 50, "healbar: Krieger 40/80 = 50 %")
  T.eq(rows[3].name, "Otto", "healbar: Leeroy erscheint normal")
  for _, r in ipairs(rows) do
    T.ok(r.name ~= "Bert", "healbar: 251 px ist ausser Reichweite (" .. r.name .. ")")
    T.ok(r.name ~= "Zora", "healbar: Geist nie in der Liste (" .. r.name .. ")")
    T.ok(r.name ~= "Karl", "healbar: Toter nie in der Liste (" .. r.name .. ")")
  end
end

-- Stabile Sortierung: HP-Aenderungen duerfen die Reihenfolge nicht kippen
do
  local v = mkview()
  local a = render.heal_rows(v, RANGE)
  v.players[1].hp = 5
  v.players[6].hp = 79
  local b = render.heal_rows(v, RANGE)
  for i = 1, #a do
    T.eq(b[i].pid, a[i].pid, "healbar: Reihenfolge stabil unter HP-Aenderung #" .. i)
  end
end

-- Toter Betrachter: leere Liste (die Leiste verschwindet)
do
  local v = mkview()
  v.players[5].alive = false
  local rows = render.heal_rows(v, RANGE)
  T.eq(#rows, 0, "healbar: toter Heiler sieht keine Liste")
end

-- Ueberhang: max_rows deckelt, der Rest wird gezaehlt
do
  local v = { me = 1, me_x = 0, me_y = 0, names = {}, players = {
    [1] = { alive = true, class = "priest", hp = 50, x = 0, y = 0 } } }
  for pid = 2, 30 do
    v.players[pid] = { alive = true, class = "warrior", hp = 80,
                       x = 10 + pid, y = 0 }
  end
  local rows, more_n = render.heal_rows(v, RANGE, 24)
  T.eq(#rows, 24, "healbar: Deckel bei max_rows Zeilen")
  T.eq(more_n, 6, "healbar: Ueberhang gezaehlt (30 - 24)")
end

-- Ohne Roster-Namen faellt die pid ein
do
  local v = { me = 1, me_x = 0, me_y = 0, players = {
    [1] = { alive = true, class = "priest", hp = 50, x = 0, y = 0 } } }
  local rows = render.heal_rows(v, RANGE)
  T.eq(rows[1].name, "#1", "healbar: ohne Roster-Namen faellt die pid ein")
end

-- Hit-Test: reine Arithmetik gegen die Layout-Konstanten
do
  local HB = render.HEALBAR
  T.eq(render.healbar_row_at(3, HB.x + 10, HB.y + 4), nil,
    "healbar: Kopfzeile trifft keine Zeile")
  T.eq(render.healbar_row_at(3, HB.x + 10, HB.y + HB.header_h + 1), 1,
    "healbar: erste Zeile getroffen")
  T.eq(render.healbar_row_at(3, HB.x + 10,
    HB.y + HB.header_h + 2 * HB.row_h + 1), 3,
    "healbar: letzte Zeile getroffen")
  T.eq(render.healbar_row_at(3, HB.x + 10,
    HB.y + HB.header_h + 3 * HB.row_h + 1), nil,
    "healbar: unterhalb der letzten Zeile trifft nichts")
  T.eq(render.healbar_row_at(3, HB.x - 2, HB.y + HB.header_h + 1), nil,
    "healbar: links neben der Leiste trifft nichts")
  T.eq(render.healbar_row_at(3, HB.x + HB.w + 2, HB.y + HB.header_h + 1), nil,
    "healbar: rechts neben der Leiste trifft nichts")
end

-- Der Parameter existiert und die Leiste nutzt denselben Wert wie die Sim
T.eq(model.p("heal_range"), 250, "healbar: heal_range-Parameter = 250")

-- ---------------------------------------------------------------------------
-- Eine Wahrheit statt zweier (Runde 17). Die Plakettenhoehe stand bis dahin
-- zweimal da — im Zeichner und noch einmal von Hand im Klickpfad. Und der
-- Klickpfad baute die Liste ein ZWEITES Mal auf, mit frischeren Daten als das
-- Bild: geklickt wurde also eine Liste, die so nie auf dem Schirm stand.
-- ---------------------------------------------------------------------------
do
  local HB = render.HEALBAR

  -- Die Hoehenformel
  T.eq(render.healbar_height(3, 0, HB), HB.header_h + 3 * HB.row_h + 8,
    "healbar: Hoehe ohne Restzeile")
  T.eq(render.healbar_height(3, 6, HB), HB.header_h + 4 * HB.row_h + 8,
    "healbar: die Restzeile zaehlt als eine Zeile mit")
  T.eq(render.healbar_height(24, 16, HB), render.healbar_height(24, 1, HB),
    "healbar: wie GROSS der Ueberhang ist, aendert die Hoehe nicht")

  -- healbar_hit liefert die ZEILE, nicht den Index
  local rows = { { pid = 11 }, { pid = 22 }, { pid = 33 } }
  local mitte_x = HB.x + 10
  local zeile2_y = HB.y + HB.header_h + HB.row_h + 1

  local row, drauf = render.healbar_hit(rows, 0, mitte_x, zeile2_y, HB)
  T.ok(type(row) == "table", "healbar: Treffer ist die Zeile, kein Index")
  T.eq(row and row.pid, 22, "healbar: die richtige Zeile")
  T.eq(drauf, true, "healbar: der Klick lag auf der Leiste")

  -- Kopfzeile: auf der Leiste, aber keine Zeile — der Klick darf trotzdem
  -- nicht auf die Karte durchfallen
  local kopf_row, kopf_drauf = render.healbar_hit(rows, 0, mitte_x, HB.y + 4, HB)
  T.eq(kopf_row, nil, "healbar: die Kopfzeile ist keine Zeile")
  T.eq(kopf_drauf, true, "healbar: ... liegt aber auf der Leiste")

  -- Neben der Leiste: gar nichts, der Klick gehoert der Karte
  local _, daneben = render.healbar_hit(rows, 0, HB.x - 5, zeile2_y, HB)
  T.ok(not daneben, "healbar: links daneben gehoert der Klick der Karte")
  local _, drunter = render.healbar_hit(rows, 0, mitte_x,
    HB.y + render.healbar_height(#rows, 0, HB) + 5, HB)
  T.ok(not drunter, "healbar: unterhalb der Plakette ebenso")

  -- Die Restzeile ist Teil der Flaeche, aber keine anklickbare Zeile
  local rest_y = HB.y + HB.header_h + #rows * HB.row_h + 1
  local rest_row, rest_drauf = render.healbar_hit(rows, 6, mitte_x, rest_y, HB)
  T.eq(rest_row, nil, "healbar: die Restzeile waehlt niemanden aus")
  T.eq(rest_drauf, true, "healbar: ... schluckt den Klick aber")

  -- Leere Liste: kein Treffer, keine Flaeche
  local _, leer = render.healbar_hit({}, 0, mitte_x, zeile2_y, HB)
  T.ok(not leer, "healbar: ohne Zeilen gibt es keine Klickflaeche")
end

-- ---------------------------------------------------------------------------
-- Der gemerkte Frame darf einen Tod nicht ueberleben: sonst klickt man auf
-- eine Leiste, die gar nicht mehr gezeichnet wird.
-- ---------------------------------------------------------------------------
do
  local self_ = { heal_cache = nil }
  local hv = render.heal_view(self_, mkview(), render.HEALBAR)
  T.ok(hv ~= nil and #hv.rows == 3, "healbar: heal_view baut die Liste")
  T.ok(self_.heal_cache == hv, "healbar: ... und merkt sie sich fuer den Klick")

  local tot = mkview()
  tot.players[tot.me].alive = false
  T.eq(render.heal_view(self_, tot, render.HEALBAR), nil,
    "healbar: als Toter gibt es keine Leiste")
  T.eq(self_.heal_cache, nil,
    "healbar: der gemerkte Frame wird dabei geloescht (sonst klickt man ins Leere)")

  -- Keine Heilerklasse: dasselbe
  self_.heal_cache = { rows = { {} } }
  local krieger = mkview()
  krieger.players[krieger.me].class = "warrior"
  T.eq(render.heal_view(self_, krieger, render.HEALBAR), nil,
    "healbar: ohne Heilzauber keine Leiste")
  T.eq(self_.heal_cache, nil, "healbar: auch dann wird der Frame geloescht")
end
