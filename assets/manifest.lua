-- assets/manifest.lua — Asset-Kontrakt (GDD 17.5): logische IDs, nie Pfade im
-- Spielcode. Platzhalter werden zur Laufzeit aus diesem Manifest generiert
-- (einfarbige Formen mit Kuerzel, exakt finale Masse); liegt eine echte Datei
-- unter `datei`, wird sie geladen und von tools/check_assets.lua gegen die
-- Masse geprueft. Finale Assets muessen exakt die Manifest-Masse liefern.
-- Reines Lua (auch headless ladbar).

return {
  -- Klassenicons (32 px Raster)
  icon_warrior  = { form = "kreis",  groesse = 32, farbe = { 0.78, 0.61, 0.43 }, kuerzel = "KR", datei = "icon_warrior.png" },
  icon_hunter   = { form = "kreis",  groesse = 32, farbe = { 0.67, 0.83, 0.45 }, kuerzel = "JG", datei = "icon_hunter.png" },
  icon_priest   = { form = "kreis",  groesse = 32, farbe = { 1.00, 1.00, 1.00 }, kuerzel = "PR", datei = "icon_priest.png" },

  -- Begehbare Klassen-Bodenicons am Wiederbelebungsfeld (48 px, GDD 5)
  floor_warrior = { form = "ring",   groesse = 48, farbe = { 0.78, 0.61, 0.43 }, kuerzel = "KR", datei = "floor_warrior.png" },
  floor_hunter  = { form = "ring",   groesse = 48, farbe = { 0.67, 0.83, 0.45 }, kuerzel = "JG", datei = "floor_hunter.png" },
  floor_priest  = { form = "ring",   groesse = 48, farbe = { 1.00, 1.00, 1.00 }, kuerzel = "PR", datei = "floor_priest.png" },

  -- Hogger (groesser, GDD 4.1) und Welt
  icon_hogger   = { form = "kreis",  groesse = 48, farbe = { 0.85, 0.25, 0.20 }, kuerzel = "HO", datei = "icon_hogger.png" },
  icon_corpse   = { form = "raute",  groesse = 24, farbe = { 0.85, 0.85, 0.80 }, kuerzel = "X",  datei = "icon_corpse.png" },
  icon_deco_skull = { form = "raute", groesse = 16, farbe = { 0.65, 0.65, 0.60 }, kuerzel = "x", datei = "icon_deco_skull.png" },
  icon_tree     = { form = "kreis",  groesse = 28, farbe = { 0.22, 0.45, 0.20 }, kuerzel = "",   datei = "icon_tree.png" },

  -- Faehigkeiten-Buttons (Ring unten, 40 px, GDD 4.2)
  ab_heroic     = { form = "quadrat", groesse = 40, farbe = { 0.80, 0.35, 0.25 }, kuerzel = "HS", datei = "ab_heroic.png" },
  ab_shout      = { form = "quadrat", groesse = 40, farbe = { 0.90, 0.60, 0.25 }, kuerzel = "SR", datei = "ab_shout.png" },
  ab_raptor     = { form = "quadrat", groesse = 40, farbe = { 0.45, 0.70, 0.30 }, kuerzel = "RS", datei = "ab_raptor.png" },
  ab_smite      = { form = "quadrat", groesse = 40, farbe = { 0.95, 0.90, 0.60 }, kuerzel = "GP", datei = "ab_smite.png" },
  ab_heal       = { form = "quadrat", groesse = 40, farbe = { 0.55, 0.85, 0.55 }, kuerzel = "GH", datei = "ab_heal.png" },
}
