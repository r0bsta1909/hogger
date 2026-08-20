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
              [5] = "Heiler", [6] = "Otto", [7] = "Uwe" },
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
      -- Leeroy in Reichweite und verwundet: normal drin
      -- (bis Runde 17 stand er hier auf vollen 80 HP — seit die Liste nur
      -- noch Verwundete zeigt, waere er damit gar nicht mehr erschienen und
      -- der Test haette die falsche Sache geprueft)
      [6] = { alive = true, class = "warrior", is_leeroy = true, hp = 60,
              x = 1000, y = 1100 },
      -- Unverletzt in Reichweite: seit Runde 17 NICHT in der Liste — er
      -- braucht keine Heilung und belegt sonst den Platz eines Sterbenden
      [7] = { alive = true, class = "warrior", hp = 80, x = 1030, y = 1000 },
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
    T.ok(r.is_self or r.name ~= "Uwe",
      "healbar: ein Unverletzter belegt keinen Platz (" .. r.name .. ")")
  end
  -- Man selbst steht drin, auch unverletzt: Anker der Liste, und man muss
  -- sich selbst anklicken koennen
  T.eq(rows[1].hp_pct, 100, "healbar: selbst erscheint auch mit vollen HP")
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

-- Ueberhang: max_rows deckelt, der Rest wird gezaehlt.
--
-- Der Test stand bis Runde 17 mit 29 UNVERLETZTEN Verbuendeten da und hat
-- damit nie den Ueberhang gemessen, sondern nur den Deckel. Die eigentliche
-- Zusage ist eine andere: bei Platzmangel ueberleben die am schwersten
-- Verwundeten die Auswahl — angezeigt wird trotzdem alphabetisch. Vorher
-- schnitt der Deckel nach dem ALPHABET ab, ein sterbender "Zoe" war also
-- unsichtbar, waehrend ein unverletzter "Anna" seinen Platz belegte.
do
  local v = { me = 1, me_x = 0, me_y = 0, names = {}, players = {
    [1] = { alive = true, class = "priest", hp = 50, x = 0, y = 0 } } }
  -- pid 2..30: je hoeher die pid, desto GESUENDER (pid 2 = 4 HP von 80,
  -- pid 30 = 60 HP von 80). Die Namen laufen genau andersherum, damit
  -- Auswahl und Anzeige sich nicht zufaellig decken.
  for pid = 2, 30 do
    v.players[pid] = { alive = true, class = "warrior", hp = 2 * pid,
                       x = 10 + pid, y = 0 }
    v.names[pid] = string.format("spieler%02d", 32 - pid)
  end
  local rows, more_n = render.heal_rows(v, RANGE, 24)
  T.eq(#rows, 24, "healbar: Deckel bei max_rows Zeilen")
  T.eq(more_n, 6, "healbar: Ueberhang gezaehlt (29 Verwundete, 23 Plaetze)")
  T.ok(rows[1].is_self, "healbar: selbst behaelt Zeile 1")

  -- Gezeigt werden die 23 Schwaechsten, also die pids 2..24
  local gezeigt = {}
  for i = 2, #rows do gezeigt[rows[i].pid] = true end
  for pid = 2, 24 do
    T.ok(gezeigt[pid], "healbar: Schwerverletzter pid " .. pid .. " ist sichtbar")
  end
  for pid = 25, 30 do
    T.ok(not gezeigt[pid],
      "healbar: der Gesuendere pid " .. pid .. " weicht ihm")
  end

  -- ... und sie stehen trotzdem alphabetisch, nicht nach HP
  local sortiert = true
  for i = 3, #rows do
    if rows[i - 1].name:lower() > rows[i].name:lower() then sortiert = false end
  end
  T.ok(sortiert, "healbar: angezeigt wird alphabetisch, nicht nach HP")
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
-- Gnadenfrist (Runde 17): wer voll geheilt wurde, bleibt kurz stehen. Ohne
-- das klappt die Liste genau in dem Moment zusammen, in dem der Heiler den
-- naechsten anklicken will — die Zeilen darunter ruecken auf, und der Klick
-- landet auf dem Falschen.
-- ---------------------------------------------------------------------------
do
  local GRACE = model.p("healbar_grace")
  local function view_mit(hp)
    return { me = 1, me_x = 0, me_y = 0, names = { [1] = "Heiler", [2] = "Anna" },
             players = {
               [1] = { alive = true, class = "priest", hp = 50, x = 0, y = 0 },
               [2] = { alive = true, class = "warrior", hp = hp, x = 10, y = 0 },
             } }
  end
  local memo = {}
  local rows = render.heal_rows(view_mit(40), RANGE, 24, 0, memo)
  T.eq(#rows, 2, "gnadenfrist: der Verwundete steht drin")

  -- voll geheilt, kurz danach: bleibt stehen
  rows = render.heal_rows(view_mit(80), RANGE, 24, GRACE - 0.1, memo)
  T.eq(#rows, 2, "gnadenfrist: direkt nach der Heilung bleibt die Zeile")

  -- nach Ablauf: raus
  rows = render.heal_rows(view_mit(80), RANGE, 24, GRACE + 0.1, memo)
  T.eq(#rows, 1, "gnadenfrist: nach Ablauf verschwindet er")
  T.eq(next(memo), nil, "gnadenfrist: die Merk-Tabelle raeumt sich auf")

  -- Wer NIE verwundet war, kommt auch nicht ueber die Gnadenfrist herein
  local memo2 = {}
  local nur_gesund = render.heal_rows(view_mit(80), RANGE, 24, 0, memo2)
  T.eq(#nur_gesund, 1, "gnadenfrist: ein nie Verwundeter erscheint nicht")
  T.eq(next(memo2), nil, "gnadenfrist: ... und wird nicht gemerkt")

  -- Ohne Merk-Tabelle verhaelt sich alles wie ohne Nachlauf
  local ohne = render.heal_rows(view_mit(80), RANGE, 24)
  T.eq(#ohne, 1, "gnadenfrist: ohne Merk-Tabelle kein Nachlauf")
end

-- ---------------------------------------------------------------------------
-- Determinismus: die AUSWAHL darf nicht an der Einfuegereihenfolge haengen.
-- LuaJITs table.sort ist instabil; ohne pid als Endanschlag haengt das
-- Ergebnis an der pairs-Reihenfolge und ist zwischen zwei Laeufen anders.
-- ---------------------------------------------------------------------------
do
  local function bau(reihenfolge)
    local v = { me = 1, me_x = 0, me_y = 0, names = {}, players = {
      [1] = { alive = true, class = "priest", hp = 50, x = 0, y = 0 } } }
    for _, pid in ipairs(reihenfolge) do
      -- ALLE gleich schwer verletzt: nur der pid-Endanschlag kann noch
      -- entscheiden, wer den letzten Platz bekommt
      v.players[pid] = { alive = true, class = "warrior", hp = 40, x = 10, y = 0 }
      v.names[pid] = "gleich"
    end
    local rows = render.heal_rows(v, RANGE, 5)
    local pids = {}
    for i = 2, #rows do pids[#pids + 1] = rows[i].pid end
    return table.concat(pids, ",")
  end
  local vorwaerts = bau({ 2, 3, 4, 5, 6, 7, 8 })
  local rueckwaerts = bau({ 8, 7, 6, 5, 4, 3, 2 })
  T.eq(rueckwaerts, vorwaerts,
    "auswahl: umgekehrte Einfuegereihenfolge liefert dieselben Zeilen")
  T.eq(vorwaerts, "2,3,4,5",
    "auswahl: bei Gleichstand entscheidet die pid, nicht der Zufall")
end

-- ---------------------------------------------------------------------------
-- Der Ueberhang zaehlt nur Verwundete: "+X weitere verwundet" darf nicht
-- Kerngesunde mitzaehlen, sonst sucht der Heiler jemanden, den es nicht gibt.
-- ---------------------------------------------------------------------------
do
  local v = { me = 1, me_x = 0, me_y = 0, names = {}, players = {
    [1] = { alive = true, class = "priest", hp = 50, x = 0, y = 0 } } }
  for pid = 2, 20 do -- 5 verwundet, 14 kerngesund
    v.players[pid] = { alive = true, class = "warrior",
                       hp = (pid <= 6) and 20 or 80, x = 10, y = 0 }
  end
  local rows, more_n = render.heal_rows(v, RANGE, 4)
  T.eq(#rows, 4, "ueberhang: drei Verwundete plus man selbst passen")
  T.eq(more_n, 2, "ueberhang: nur die restlichen VERWUNDETEN werden gezaehlt")
end

-- Die Kritisch-Schwelle hat einen Namen und ist dieselbe wie die Balkenfarbe
T.eq(render.HEALBAR_LOW_PCT, 35, "healbar: Kritisch-Schwelle als Konstante")

-- ---------------------------------------------------------------------------
-- Host und Client muessen sich ueber die Maximal-HP einig sein. Bis Runde 17
-- kostete eine Abweichung nur eine falsche Balkenfarbe — jetzt entscheidet
-- dieselbe Zahl, WER ueberhaupt in der Liste steht.
-- ---------------------------------------------------------------------------
do
  local step_mod = require("game.gamesim.step")
  for _, class in ipairs({ "warrior", "paladin", "hunter", "rogue",
                           "priest", "mage", "warlock", "druid" }) do
    for _, pact in ipairs({ false, true }) do
      local host = step_mod.effective_max_hp(
        { max_hp = model.hp_for_class(class), pact = pact })
      local client = render.client_max_hp({ class = class, pact = pact })
      T.near(client, host, string.format(
        "max-hp: Client und Host einig (%s, Blutpakt %s)",
        class, tostring(pact)))
    end
  end
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
