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

-- Rand-Saeulen (Runde 21, Robs Skizze): reicht der Rand, stehen die Tafeln
-- NEBEN dem Kreis, und der ganze Stapel darunter laeuft am Kreis vorbei ---
do
  local L = render.layout(1280, 800, true)
  T.ok(L.saeulen, "layout saeulen: bei 1280x800 reicht der Rand")
  T.eq(L.frames.unit.x, 262 - 12 - 214, "layout saeulen: Einheitenfenster links neben dem Kreis")
  T.eq(L.frames.target.x, 1018 + 12, "layout saeulen: Zielfenster rechts neben dem Kreis")
  T.eq(L.frames.unit.y, 22 + 26, "layout saeulen: Tafeln oben, unter der Ringoberkante")
  T.eq(L.frames.target.y, L.frames.unit.y, "layout saeulen: beide Tafeln auf einer Hoehe")
  -- nichts liegt im Kreis: die linke Spalte endet vor dem linken Kreisrand,
  -- die rechte beginnt hinter dem rechten
  T.ok(L.frames.unit.x + render.FRAME_W <= L.ox - L.radius,
    "layout saeulen: linke Spalte komplett ausserhalb des Kreises")
  T.ok(L.frames.healbar.x + L.frames.healbar.w <= L.ox - L.radius,
    "layout saeulen: Heil-Leiste ausserhalb des Kreises")
  T.ok(L.frames.target.x >= L.ox + L.radius,
    "layout saeulen: rechte Spalte komplett ausserhalb des Kreises")
  T.ok(L.frames.target.x + render.FRAME_W <= 1280,
    "layout saeulen: Zielfenster im Bild")
  T.ok(L.frames.unit.x >= 0, "layout saeulen: Einheitenfenster im Bild")
  -- Ableitungen wandern mit
  T.eq(L.frames.healbar.x, L.frames.unit.x, "layout saeulen: Heil-Leiste folgt dem Fenster")
  T.eq(L.frames.healbar.y, L.frames.unit.y + 132, "layout saeulen: Heil-Leiste y-Offset (M13)")
  T.eq(L.frames.buffs_self.y, L.frames.unit.y + 60, "layout saeulen: eigene Auren y-Offset")
  T.eq(L.frames.money.y, L.frames.unit.y + 94, "layout saeulen: Kupferzeile y-Offset (M13)")
  T.eq(L.frames.buffs.x, L.frames.target.x, "layout saeulen: Buffs folgen dem Zielfenster")
  T.eq(L.frames.buffs.y, L.frames.target.y + 86, "layout saeulen: Buffs y-Offset")
  T.eq(L.frames.tot.y, L.frames.target.y + 60, "layout saeulen: Ziel des Ziels y-Offset")
  T.eq(L.frames.cp.x, L.frames.unit.x + 52, "layout saeulen: CP-Leiste folgt der Tafel")
  T.eq(L.frames.cp.y, L.frames.unit.y - render.CP_STRIP_H, "layout saeulen: CP-Leiste sitzt darueber")
  T.ok(L.frames.cp.y + render.CP_STRIP_H <= L.frames.unit.y,
    "layout saeulen: die Leiste ueberlappt das Einheitenfenster nicht")
  T.eq(render.CP_MAX, require("sim.model").CP_MAX,
    "layout: die Anzeige kennt genauso viele Combopunkte wie die Simulation")
  -- Ring-Moeblierung ist von docked unabhaengig
  local U = render.layout(1280, 800, false)
  T.eq(L.radius, U.radius, "layout saeulen: radius unveraendert")
  T.eq(L.clock.cy, U.clock.cy, "layout saeulen: Uhr unveraendert")
  -- 1920x1080 ebenso
  local G = render.layout(1920, 1080, true)
  T.ok(G.saeulen and G.frames.target.x >= G.ox + G.radius
       and G.frames.unit.x + render.FRAME_W <= G.ox - G.radius,
    "layout saeulen: 1920x1080 beide Spalten ausserhalb")
end

-- Dock-Variante (tangential an 10-/2-Uhr) bleibt der Rueckfall, wenn der
-- Rand nicht reicht (4:3-Fenster) ----------------------------------------
do
  local L = render.layout(1024, 768, true)
  T.ok(not L.saeulen, "layout dock: bei 1024x768 reicht der Rand nicht")
  local radius = 768 / 2 - 22
  local p2x = 512 + radius * 0.866
  T.eq(L.frames.target.x, math.min(1024 - 226, math.floor(p2x - 8)),
    "layout dock: Zielfenster tangential an 2 Uhr")
  T.eq(L.frames.unit.y, math.max(10, math.floor(384 - radius * 0.5 - 56 + 8)),
    "layout dock: Einheitenfenster tangential an 10 Uhr")
  T.eq(L.frames.healbar.y, L.frames.unit.y + 132, "layout dock: Heil-Leiste y-Offset (M13)")
end

-- Icon-Balken (Runde 21): am Icon-Rand, skaliert mit dem Zoom -----------------
do
  local dy1, hw1, hh1 = render.bar_geom(16 * 1.8 * 1.43, 1.43) -- Zoom 1
  local dy3, hw3, hh3 = render.bar_geom(16 * 1.8 * 0.71, 0.71) -- Zoom 3
  T.ok(dy1 > 16 * 1.8 * 1.43, "bar: der Balken haengt UNTER dem Icon-Rand (Zoom 1)")
  T.ok(dy3 > 16 * 1.8 * 0.71, "bar: der Balken haengt UNTER dem Icon-Rand (Zoom 3)")
  T.ok(hw1 > hw3, "bar: auf Zoom 1 breiter als auf Zoom 3")
  T.ok(hw1 * 2 <= 16 * 1.8 * 1.43 * 2, "bar: nie breiter als das Icon")
  T.ok(hh1 >= 3 and hh1 <= 6 and hh3 >= 3 and hh3 <= 6, "bar: Hoehe 3-6 px")
  T.ok(hh1 > hh3, "bar: auf Zoom 1 hoeher als auf Zoom 3")
  local dyh, hwh = render.bar_geom(48 * 0.95, 0.95)
  T.ok(dyh > 48 * 0.95 and hwh > hw1 * 0.5, "bar: Hoggers Balken unter seinem Ring, breiter als ein Spieler-Balken")
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

-- ---------------------------------------------------------------------------
-- Die Uhr zaehlt RUNTER (GDD 4.2, Runde 17). Vorher zeigte sie die
-- verstrichene Zeit — sie nannte die Frist also nie, und das Try-Ende kam
-- fuer den Spieler aus dem Nichts. Rob stand neben einem lebenden Hogger,
-- als die Uhr ablief, und hielt es fuer einen Reset.
-- ---------------------------------------------------------------------------
do
  local model = require("sim.model")
  local L = model.p("try_time_limit")

  T.eq(render.clock_text(0, L), "16:00", "uhr: beim Start steht die volle Frist")
  T.eq(render.clock_text(60, L), "15:00", "uhr: nach einer Minute eine weniger")
  T.eq(render.clock_text(L - 1, L), "0:01", "uhr: die letzte Sekunde")
  T.eq(render.clock_text(L, L), "0:00", "uhr: bei Ablauf steht null")
  T.eq(render.clock_text(L + 50, L), "0:00",
    "uhr: laeuft nicht ins Negative, falls der Tick spaeter ankommt")

  -- Die eigentliche Zusage: sie zaehlt herunter, nicht herauf
  local function rest(t)
    local m, s = render.clock_text(t, L):match("(%d+):(%d+)")
    return tonumber(m) * 60 + tonumber(s)
  end
  T.ok(rest(0) > rest(100) and rest(100) > rest(600),
    "uhr: die Anzeige wird kleiner, nicht groesser")
  T.eq(rest(0), L, "uhr: sie zeigt die Frist, nicht die verstrichene Zeit")

  -- Sie haengt am Parameter, nicht an einer festen Zahl: wer im F10-Panel
  -- dreht, sieht die neue Frist sofort
  T.eq(render.clock_text(0, 600), "10:00", "uhr: folgt dem eingestellten Wert")
end
