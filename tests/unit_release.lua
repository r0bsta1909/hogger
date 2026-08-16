-- tests/unit_release.lua — Panel "Geist freilassen" (GDD Kap. 11, Issue #54).
-- Nur Layout und Zustand; das Zeichnen liegt separat.

local rel = require("game.ui.release")

T.eq(rel.visible(nil), false, "Panel: ohne Spieler unsichtbar")
T.eq(rel.visible({ alive = true, ghost = false }), false, "Panel: lebend unsichtbar")
T.eq(rel.visible({ alive = false, ghost = true }), false, "Panel: als Geist unsichtbar")
T.eq(rel.visible({ alive = false, ghost = false }), true, "Panel: tot sichtbar")

T.eq(rel.headline(6), "6 Sekunden bis zur Freigabe", "Ueberschrift zaehlt herunter")
T.eq(rel.headline(0), "Bereit zur Freigabe", "Ueberschrift bei 0")
T.eq(rel.ready(3), false, "Knopf bleibt stumpf, solange die Strafe laeuft")
T.eq(rel.ready(0), true, "Knopf wird scharf bei 0")

local L = rel.layout(1280, 800)
T.ok(L.panel[1] > 0 and L.panel[1] + L.panel[3] < 1280, "Panel liegt im Bild")
T.ok(L.button[2] > L.panel[2], "Knopf sitzt unter der Ueberschrift")
T.ok(rel.hit(L.button, L.button[1] + 5, L.button[2] + 5), "Treffer im Knopf")
T.ok(not rel.hit(L.button, L.button[1] - 20, L.button[2] + 5), "kein Treffer daneben")
