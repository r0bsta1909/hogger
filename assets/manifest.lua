-- assets/manifest.lua — Asset-Kontrakt (GDD 17.5): logische IDs, nie Pfade im
-- Spielcode. Platzhalter werden zur Laufzeit aus diesem Manifest generiert
-- (einfarbige Formen mit Kuerzel, exakt finale Masse); liegt eine echte Datei
-- unter `datei`, wird sie geladen und von tools/check_assets.lua gegen die
-- Masse geprueft. Finale Assets muessen exakt die Manifest-Masse liefern.
-- Reines Lua (auch headless ladbar).

return {
  -- Klassenicons (32 px Raster, WoW-Klassenfarben)
  icon_warrior  = { form = "kreis",  groesse = 32, farbe = { 0.78, 0.61, 0.43 }, kuerzel = "KR", datei = "icon_warrior.png" },
  icon_paladin  = { form = "kreis",  groesse = 32, farbe = { 0.96, 0.55, 0.73 }, kuerzel = "PA", datei = "icon_paladin.png" },
  icon_hunter   = { form = "kreis",  groesse = 32, farbe = { 0.67, 0.83, 0.45 }, kuerzel = "JG", datei = "icon_hunter.png" },
  icon_rogue    = { form = "kreis",  groesse = 32, farbe = { 1.00, 0.96, 0.41 }, kuerzel = "SC", datei = "icon_rogue.png" },
  icon_priest   = { form = "kreis",  groesse = 32, farbe = { 1.00, 1.00, 1.00 }, kuerzel = "PR", datei = "icon_priest.png" },
  icon_mage     = { form = "kreis",  groesse = 32, farbe = { 0.41, 0.80, 0.94 }, kuerzel = "MA", datei = "icon_mage.png" },
  icon_warlock  = { form = "kreis",  groesse = 32, farbe = { 0.58, 0.51, 0.79 }, kuerzel = "HX", datei = "icon_warlock.png" },
  icon_druid    = { form = "kreis",  groesse = 32, farbe = { 1.00, 0.49, 0.04 }, kuerzel = "DR", datei = "icon_druid.png" },

  -- Begehbare Klassen-Bodenicons am Wiederbelebungsfeld (48 px, GDD 5)
  floor_warrior = { form = "ring",   groesse = 48, farbe = { 0.78, 0.61, 0.43 }, kuerzel = "KR", datei = "floor_warrior.png" },
  floor_paladin = { form = "ring",   groesse = 48, farbe = { 0.96, 0.55, 0.73 }, kuerzel = "PA", datei = "floor_paladin.png" },
  floor_hunter  = { form = "ring",   groesse = 48, farbe = { 0.67, 0.83, 0.45 }, kuerzel = "JG", datei = "floor_hunter.png" },
  floor_rogue   = { form = "ring",   groesse = 48, farbe = { 1.00, 0.96, 0.41 }, kuerzel = "SC", datei = "floor_rogue.png" },
  floor_priest  = { form = "ring",   groesse = 48, farbe = { 1.00, 1.00, 1.00 }, kuerzel = "PR", datei = "floor_priest.png" },
  floor_mage    = { form = "ring",   groesse = 48, farbe = { 0.41, 0.80, 0.94 }, kuerzel = "MA", datei = "floor_mage.png" },
  floor_warlock = { form = "ring",   groesse = 48, farbe = { 0.58, 0.51, 0.79 }, kuerzel = "HX", datei = "floor_warlock.png" },
  floor_druid   = { form = "ring",   groesse = 48, farbe = { 1.00, 0.49, 0.04 }, kuerzel = "DR", datei = "floor_druid.png" },

  -- NPCs
  icon_imp      = { form = "raute",  groesse = 20, farbe = { 0.75, 0.35, 0.85 }, kuerzel = "w",  datei = "icon_imp.png" },
  icon_add      = { form = "kreis",  groesse = 24, farbe = { 0.80, 0.45, 0.30 }, kuerzel = "g",  datei = "icon_add.png" },
  icon_boar     = { form = "kreis",  groesse = 22, farbe = { 0.60, 0.45, 0.35 }, kuerzel = "eb", datei = "icon_boar.png" },
  icon_wolf     = { form = "kreis",  groesse = 22, farbe = { 0.50, 0.50, 0.55 }, kuerzel = "wo", datei = "icon_wolf.png" },
  icon_kobold   = { form = "kreis",  groesse = 22, farbe = { 0.70, 0.60, 0.30 }, kuerzel = "ko", datei = "icon_kobold.png" },
  icon_murloc   = { form = "kreis",  groesse = 22, farbe = { 0.35, 0.70, 0.55 }, kuerzel = "mu", datei = "icon_murloc.png" },
  icon_loot     = { form = "raute",  groesse = 16, farbe = { 0.95, 0.85, 0.35 }, kuerzel = "",   datei = "icon_loot.png" },

  -- Boot-Sequenz (GDD Kap. 3): Vanilla-Splash; Platzhalter = dunkle Flaeche
  -- mit Logo-Schriftzug, finale Datei muss exakt breite x hoehe liefern
  splash_login  = { form = "splash", breite = 1024, hoehe = 768, farbe = { 0.05, 0.08, 0.18 }, kuerzel = "World of Warcraft", datei = "splash_login.png" },

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
  ab_holylight  = { form = "quadrat", groesse = 40, farbe = { 1.00, 0.95, 0.55 }, kuerzel = "HL", datei = "ab_holylight.png" },
  ab_seal       = { form = "quadrat", groesse = 40, farbe = { 0.95, 0.75, 0.35 }, kuerzel = "SG", datei = "ab_seal.png" },
  ab_sinister   = { form = "quadrat", groesse = 40, farbe = { 0.85, 0.80, 0.35 }, kuerzel = "FS", datei = "ab_sinister.png" },
  ab_evis       = { form = "quadrat", groesse = 40, farbe = { 0.80, 0.30, 0.30 }, kuerzel = "AW", datei = "ab_evis.png" },
  ab_stealth    = { form = "quadrat", groesse = 40, farbe = { 0.45, 0.45, 0.60 }, kuerzel = "VS", datei = "ab_stealth.png" },
  ab_fireball   = { form = "quadrat", groesse = 40, farbe = { 0.95, 0.45, 0.20 }, kuerzel = "FB", datei = "ab_fireball.png" },
  ab_frostarmor = { form = "quadrat", groesse = 40, farbe = { 0.55, 0.75, 0.95 }, kuerzel = "FR", datei = "ab_frostarmor.png" },
  ab_bolt       = { form = "quadrat", groesse = 40, farbe = { 0.55, 0.40, 0.75 }, kuerzel = "SB", datei = "ab_bolt.png" },
  ab_imp        = { form = "quadrat", groesse = 40, farbe = { 0.75, 0.35, 0.85 }, kuerzel = "WI", datei = "ab_imp.png" },
  ab_wrath      = { form = "quadrat", groesse = 40, farbe = { 0.95, 0.60, 0.25 }, kuerzel = "ZO", datei = "ab_wrath.png" },
  ab_touch      = { form = "quadrat", groesse = 40, farbe = { 0.45, 0.85, 0.45 }, kuerzel = "HB", datei = "ab_touch.png" },
}
