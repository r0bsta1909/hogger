-- tests/unit_layout.lua — M12: die eine Layout-Wahrheit der Minimap-
-- Moeblierung (R.layout). Renderer und Maus-Hit-Tests rechnen mit denselben
-- Zahlen; hier wird die Arithmetik love-frei bewiesen: Bestandszahlen der
-- Ecken-Variante, Dock-Anker, Klemmung, Plaketten-Kollisionsfreiheit.

local render = require("game.render")

-- Grundwerte 1280x800 -------------------------------------------------------
do
  local L = render.layout(1280, 800, false)
  T.eq(L.ox, 640, "layout: ox = w/2")
  T.eq(L.oy, 400, "layout: oy = h/2")
  T.eq(L.radius, 378, "layout: radius = h/2 - 22")
  T.near(L.ring_r, 378 * 0.87, "layout: ring_r = 0.87 radius")
  T.eq(L.banner.cx, 640, "layout: Banner mittig")
  T.eq(L.banner.cy, 22, "layout: Banner auf der Ringoberkante")
  T.eq(L.clock.cx, 640, "layout: Uhr mittig")
  T.eq(L.clock.cy, 778, "layout: Uhr auf der Ringunterkante")
  T.eq(L.npip.x, 640, "layout: N-Pip mittig")
  T.eq(L.npip.y, 22 + 26, "layout: N-Pip unter dem Banner")
  -- Zoom-Knoepfe sitzen seit Runde 15 (#189) auf DERSELBEN Ringbahn:
  -- vorher stand der zweite 34 px unter dem ersten, also einer im Kreis
  -- und einer auf dem Goldring.
  T.eq(L.zoom.r, 14, "layout: Zoom-Radius = Hit-Radius")
  local function bahn(b)
    return math.sqrt((b.x - 640) ^ 2 + (b.y - 400) ^ 2)
  end
  T.near(bahn(L.zoom.plus), 378, "layout: Plus sitzt auf der Ringbahn")
  T.near(bahn(L.zoom.minus), 378, "layout: Minus sitzt auf derselben Bahn")
  T.ok(L.zoom.minus.y > L.zoom.plus.y, "layout: Minus liegt unter Plus")
  do -- Knoepfe duerfen sich nicht ueberlappen
    local dx = L.zoom.minus.x - L.zoom.plus.x
    local dy = L.zoom.minus.y - L.zoom.plus.y
    T.ok(math.sqrt(dx * dx + dy * dy) > 2 * L.zoom.r,
      "layout: Plus und Minus ueberlappen sich nicht")
  end
  -- Trefferpruefung und Zeichnung teilen sich eine Rechnung
  T.eq(render.zoom_button_at(L, L.zoom.plus.x, L.zoom.plus.y), "plus",
    "zoom: Klick auf Plus trifft Plus")
  T.eq(render.zoom_button_at(L, L.zoom.minus.x, L.zoom.minus.y), "minus",
    "zoom: Klick auf Minus trifft Minus")
  T.eq(render.zoom_button_at(L, 640, 400), nil,
    "zoom: die Kartenmitte ist kein Zoom-Knopf")
  T.eq(render.zoom_button_at(L, L.zoom.plus.x, L.zoom.plus.y - L.zoom.r - 6), nil,
    "zoom: knapp daneben trifft nicht")
end

-- Ecken-Variante reproduziert die Bestandszahlen ----------------------------
do
  local L = render.layout(1280, 800, false)
  T.eq(L.frames.unit.x, 12, "layout: Einheitenfenster x (Bestand)")
  T.eq(L.frames.unit.y, 10, "layout: Einheitenfenster y (Bestand)")
  T.eq(L.frames.target.x, 1054, "layout: Zielfenster x = w-226 (Bestand)")
  T.eq(L.frames.target.y, 10, "layout: Zielfenster y (Bestand)")
  -- Combopunkt-Leiste (Runde 14, #170): ueber der Tafel statt rechts
  -- daneben auf dem Goldring. Undockt sitzt die Tafel bei y=10, die Leiste
  -- wuerde also negativ werden — die Klemme haelt sie im Bild.
  T.eq(L.frames.cp.x, 64, "layout: CP-Leiste x = unit.x + 52")
  T.eq(L.frames.cp.y, 2, "layout: CP-Leiste y geklemmt (undockt)")
  T.ok(L.frames.cp.y >= 0, "layout: CP-Leiste laeuft nie oben aus dem Bild")
  T.ok(L.frames.cp.x + (render.CP_MAX - 1) * render.CP_PITCH + render.CP_R
       < L.frames.unit.x + render.FRAME_W,
    "layout: die Leiste bleibt ueber der Tafel, nicht daneben")
  T.eq(L.frames.buffs_self.x, 12, "layout: eigene Auren x unter der Tafel (M13)")
  T.eq(L.frames.buffs_self.y, 70, "layout: eigene Auren y = unit+60 (M13)")
  T.eq(L.frames.money.x, 14, "layout: Kupfer/Plunder x (Bestand)")
  T.eq(L.frames.money.y, 104, "layout: Kupfer/Plunder y (M13: +34 fuer Auren)")
  T.eq(L.frames.hint.x, 14, "layout: STRG-Hinweis x (Bestand)")
  T.eq(L.frames.hint.y, 122, "layout: STRG-Hinweis y (M13: +34 fuer Auren)")
  T.eq(L.frames.tot.y, 70, "layout: Ziel-des-Ziels y (Bestand)")
  T.eq(L.frames.buffs.y, 96, "layout: Buff-Leiste y (Bestand)")
  -- Verheiratung mit der Heil-Leisten-Konstante: dieselben Zahlen
  T.eq(L.frames.healbar.x, render.HEALBAR.x, "layout: Healbar x == R.HEALBAR")
  T.eq(L.frames.healbar.y, render.HEALBAR.y, "layout: Healbar y == R.HEALBAR")
  T.eq(L.frames.healbar.w, render.HEALBAR.w, "layout: Healbar w uebernommen")
  T.eq(L.frames.healbar.row_h, render.HEALBAR.row_h,
    "layout: Healbar row_h uebernommen")
end

-- Dock-Variante: tangential an 10-/2-Uhr, Ableitungen wandern mit -----------
do
  local L = render.layout(1280, 800, true)
  T.eq(L.frames.unit.x, 106, "layout dock: Einheitenfenster x")
  T.eq(L.frames.unit.y, 163, "layout dock: Einheitenfenster y")
  T.eq(L.frames.target.x, 959, "layout dock: Zielfenster x")
  T.eq(L.frames.target.y, 163, "layout dock: Zielfenster y")
  T.eq(L.frames.healbar.x, 106, "layout dock: Heil-Leiste folgt dem Fenster")
  T.eq(L.frames.healbar.y, 163 + 132, "layout dock: Heil-Leiste y-Offset (M13)")
  T.eq(L.frames.buffs_self.x, 106, "layout dock: eigene Auren folgen")
  T.eq(L.frames.buffs_self.y, 163 + 60, "layout dock: eigene Auren y-Offset")
  T.eq(L.frames.money.y, 163 + 94, "layout dock: Kupferzeile y-Offset (M13)")
  T.eq(L.frames.buffs.x, 959, "layout dock: Buffs folgen dem Zielfenster")
  T.eq(L.frames.buffs.y, 163 + 86, "layout dock: Buffs y-Offset")
  T.eq(L.frames.money.x, 106 + 2, "layout dock: Kupferzeile folgt")
  -- Combopunkt-Leiste im Standard-HUD: ueber der Tafel, mit Luft zum Rand
  T.eq(L.frames.cp.x, 106 + 52, "layout dock: CP-Leiste folgt der Tafel")
  T.eq(L.frames.cp.y, 163 - render.CP_STRIP_H, "layout dock: CP-Leiste sitzt darueber")
  T.ok(L.frames.cp.y + render.CP_STRIP_H <= L.frames.unit.y,
    "layout dock: die Leiste ueberlappt das Einheitenfenster nicht")
  T.eq(render.CP_MAX, require("sim.model").CP_MAX,
    "layout: die Anzeige kennt genauso viele Combopunkte wie die Simulation")
  -- Ring-Moeblierung ist von docked unabhaengig
  local U = render.layout(1280, 800, false)
  T.eq(L.radius, U.radius, "layout dock: radius unveraendert")
  T.eq(L.clock.cy, U.clock.cy, "layout dock: Uhr unveraendert")
end

-- Klemmung bei schmalen Fenstern --------------------------------------------
do
  local L = render.layout(700, 800, true)
  T.eq(L.frames.unit.x, 12, "layout dock: Klemmung links greift")
  T.eq(L.frames.target.x, 700 - 226, "layout dock: Klemmung rechts greift")
  local L2 = render.layout(500, 800, true)
  T.eq(L2.frames.unit.x, 12, "layout dock: Klemmung links (sehr schmal)")
  T.eq(L2.frames.target.x, 500 - 226, "layout dock: Klemmung rechts (sehr schmal)")
end

-- Plaketten kollidieren nicht mit den Faehigkeits-Buttons -------------------
-- Button-Unterkante: oy + ring_r + BR(23); Uhr-Oberkante: clock.cy - h/2
for _, hh in ipairs({ 720, 800, 1080 }) do
  local L = render.layout(1280, hh, false)
  local button_bottom = L.oy + L.ring_r + 23
  local clock_top = L.clock.cy - L.clock.h / 2
  T.ok(clock_top - button_bottom >= 2,
    "layout: Uhr-Plakette frei von den Buttons bei h=" .. hh
    .. " (Gap " .. string.format("%.1f", clock_top - button_bottom) .. ")")
  T.ok(L.clock.cy + L.clock.h / 2 <= hh - 4,
    "layout: Uhr-Plakette im Bild bei h=" .. hh)
  T.ok(L.banner.cy - L.banner.h / 2 >= 4,
    "layout: Zonenbanner im Bild bei h=" .. hh)
end

-- Heil-Leiste laeuft nie unten aus dem Fenster (M13-Klemme): die Rechnung
-- enthaelt die "+K weitere"-Zeile, die draw_healbar zusaetzlich zeichnet
for _, hh in ipairs({ 720, 800, 1080 }) do
  for _, docked in ipairs({ false, true }) do
    local L = render.layout(1280, hh, docked)
    local HB = L.frames.healbar
    local bottom = HB.y + HB.header_h + (HB.max_rows + 1) * HB.row_h + 8
    T.ok(bottom <= hh, "layout: Heil-Leisten-Unterkante im Bild bei h=" .. hh
      .. (docked and " (dock, " or " (ecken, ") .. HB.max_rows .. " Zeilen)")
    T.ok(HB.max_rows >= 4, "layout: Heil-Leisten-Untergrenze bei h=" .. hh)
  end
end

-- healbar_row_at mit explizitem Layout (Dock-Pfad) --------------------------
do
  local hb = { x = 200, y = 300, w = 190, header_h = 18, row_h = 18 }
  T.eq(render.healbar_row_at(3, 210, 319, hb), 1,
    "layout: healbar_row_at folgt dem uebergebenen Layout")
  T.eq(render.healbar_row_at(3, 210, 305, hb), nil,
    "layout: Kopfzeile trifft nichts (verschoben)")
  T.eq(render.healbar_row_at(3, 150, 319, hb), nil,
    "layout: links daneben trifft nichts (verschoben)")
  -- ohne 4. Argument: Bestandsverhalten an R.HEALBAR
  local HB = render.HEALBAR
  T.eq(render.healbar_row_at(3, HB.x + 10, HB.y + HB.header_h + 1), 1,
    "layout: healbar_row_at-Default bleibt R.HEALBAR")
end

-- Hogger-Tracker edge_pos (Runde 8, #108) -----------------------------------
do
  local L = render.layout(1280, 800, false)
  T.eq(render.edge_pos(0, 0, 100, 0, 200, L), nil,
    "tracker: innerhalb des Zoom-Radius kein Indikator")
  T.eq(render.edge_pos(0, 0, 200, 0, 200, L), nil,
    "tracker: exakt am Uebergang noch kein Indikator (<=)")
  local ex, ey = render.edge_pos(0, 0, 201, 0, 200, L)
  T.ok(ex ~= nil, "tracker: ausserhalb erscheint der Indikator")
  T.near(math.sqrt((ex - L.ox) ^ 2 + (ey - L.oy) ^ 2), L.radius - 18,
    "tracker: Punkt liegt auf dem Innenrand (radius - 18)")
  T.ok(ex > L.ox, "tracker: oestliches Ziel zeigt nach rechts")
  T.near(ey, L.oy, "tracker: rein oestliches Ziel bleibt auf der Mittellinie")
  local nx, ny = render.edge_pos(500, 500, 500, -300, 200, L)
  T.ok(ny < L.oy, "tracker: noerdliches Ziel zeigt nach oben")
  T.near(nx, L.ox, "tracker: rein noerdliches Ziel bleibt mittig")
end

-- cellhash: deterministisch und streuend ------------------------------------
do
  T.eq(render.cellhash(7, 13), render.cellhash(7, 13),
    "layout: cellhash deterministisch")
  T.ok(render.cellhash(7, 13) ~= render.cellhash(8, 13),
    "layout: cellhash streut ueber Nachbarzellen (x)")
  T.ok(render.cellhash(7, 13) ~= render.cellhash(7, 14),
    "layout: cellhash streut ueber Nachbarzellen (y)")
  T.ok(render.cellhash(-5, -9) >= 0, "layout: cellhash nie negativ")
end

-- ---------------------------------------------------------------------------
-- Ansage-Banner (Runde 15, #188): eine lange Echo-Zeile lief in doppelter
-- Groesse quer durch das Zielfenster und aus dem Bild. Kurze Rufe sollen
-- gross bleiben, ganze Saetze umbrechen — und beides IM Kartenkreis.
-- ---------------------------------------------------------------------------
do
  local W, H, RADIUS = 1280, 800, 378

  local kurz = render.banner_style("HOGGER FRISST!", W, RADIUS, false)
  T.eq(kurz.scale, 2, "banner: kurze Rufe bleiben gross")
  T.ok(kurz.kurz, "banner: ... und gelten als Ruf")

  local lang = render.banner_style(
    "Echo: Der Geistheiler? Der funktioniert nicht mehr. Frag nicht.",
    W, RADIUS, false)
  T.eq(lang.scale, 1, "banner: ganze Saetze werden normal gross gesetzt")
  T.ok(not lang.kurz, "banner: ... und gelten nicht als Ruf")

  -- Die gezeichnete Breite ist wrap * scale und muss in den Kreis passen
  for _, st in ipairs({ kurz, lang }) do
    local px_breit = st.wrap * st.scale
    T.ok(px_breit <= 2 * RADIUS,
      "banner: die Textbreite bleibt im Kartenkreis (" .. px_breit .. ")")
    T.ok(px_breit <= W * 0.55,
      "banner: ... und unter der halben Fensterbreite")
  end

  -- Es darf nicht in die HUD-Tafeln laufen: linker Rand des Banners liegt
  -- rechts vom Einheitenfenster, rechter Rand links vom Zielfenster
  do
    local L = render.layout(W, H, true)
    for _, st in ipairs({ kurz, lang }) do
      local halb = st.wrap * st.scale / 2
      T.ok(L.ox - halb > L.frames.unit.x + render.FRAME_W,
        "banner: bleibt rechts vom Einheitenfenster")
      T.ok(L.ox + halb < L.frames.target.x,
        "banner: bleibt links vom Zielfenster")
    end
  end

  -- Nach dem Fluchbruch rutscht es unter die Mitte (Sprechblase hat oben Platz)
  local sieg = render.banner_style("HOGGER IST TOT!", W, RADIUS, true)
  T.ok(sieg.dy > 0, "banner: nach dem Sieg unterhalb der Mitte")
  T.ok(kurz.dy < 0, "banner: im Try oberhalb der Mitte")
  T.ok(math.abs(kurz.dy) < RADIUS, "banner: bleibt innerhalb des Kreises")

  -- Auch ein extrem langer Satz veraendert die Breite nicht mehr
  local sehr_lang = render.banner_style(string.rep("wort ", 40), W, RADIUS, false)
  T.eq(sehr_lang.wrap * sehr_lang.scale, lang.wrap * lang.scale,
    "banner: die Breite haengt nicht an der Textlaenge")
end
