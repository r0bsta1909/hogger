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

  -- Programm-Icon (Fenster, wow.exe, hogger.app; GDD 17.0). Eigene
  -- Zeichnung, kein fremdes Bildmaterial — Rob kann die Datei jederzeit
  -- durch eine andere 256er-PNG ersetzen, Pipeline und Fenster ziehen nach.
  icon_app      = { form = "kreis",  groesse = 256, farbe = { 0.55, 0.18, 0.14 }, kuerzel = "H", datei = "icon_app.png" },

  -- Boot-Sequenz (GDD Kap. 3): Vanilla-Splash; Platzhalter = dunkle Flaeche
  -- mit Logo-Schriftzug, finale Datei muss exakt breite x hoehe liefern
  -- masse = "mindestens": der Splash wird vollstaendig gezeigt (contain,
  -- schwarzer Rand), exakte Masse waeren hier Willkuer; Rest bleibt exakt
  splash_login  = { form = "splash", breite = 1024, hoehe = 768, masse = "mindestens", farbe = { 0.05, 0.08, 0.18 }, kuerzel = "World of Warcraft", datei = "splash_login.png" },

  -- Hogger (groesser, GDD 4.1) und Welt
  icon_hogger   = { form = "kreis",  groesse = 48, farbe = { 0.85, 0.25, 0.20 }, kuerzel = "HO", datei = "icon_hogger.png" },
  icon_corpse   = { form = "raute",  groesse = 24, farbe = { 0.85, 0.85, 0.80 }, kuerzel = "X",  datei = "icon_corpse.png" },
  icon_deco_skull = { form = "raute", groesse = 16, farbe = { 0.65, 0.65, 0.60 }, kuerzel = "x", datei = "icon_deco_skull.png" },
  icon_tree     = { form = "kreis",  groesse = 28, farbe = { 0.22, 0.45, 0.20 }, kuerzel = "",   datei = "icon_tree.png" },
  -- Friedhof von Elwynn (GDD 7.1 / 4.1): Grabsteine und der Geistheiler
  -- (Engel-Icon, funktionslose Szenerie)
  icon_gravestone = { form = "quadrat", groesse = 22, farbe = { 0.62, 0.62, 0.58 }, kuerzel = "+", datei = "icon_gravestone.png" },
  icon_spirit_healer = { form = "kreis", groesse = 36, farbe = { 0.80, 0.90, 1.00 }, kuerzel = "GH", datei = "icon_spirit_healer.png" },

  -- Faehigkeiten-Buttons (Ring unten, 40 px, GDD 4.2)
  ab_heroic     = { form = "quadrat", groesse = 40, farbe = { 0.80, 0.35, 0.25 }, kuerzel = "HS", datei = "ab_heroic.png" },
  ab_shout      = { form = "quadrat", groesse = 40, farbe = { 0.90, 0.60, 0.25 }, kuerzel = "SR", datei = "ab_shout.png" },
  ab_taunt      = { form = "quadrat", groesse = 40, farbe = { 0.78, 0.61, 0.43 }, kuerzel = "SP", datei = "ab_taunt.png" },
  ab_kick       = { form = "quadrat", groesse = 40, farbe = { 1.00, 0.96, 0.41 }, kuerzel = "TR", datei = "ab_kick.png" },
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
  -- Standard-Aktion Nahkampf, jede Klasse (Runde 5, Issue #86)

  -- =========================================================================
  -- Sounds — vollstaendige Liste aus GDD Kap. 12, eine ID je Position.
  -- art "blip" = Sinus-Platzhalter (freq/dauer), "rauschen" = Static,
  -- "stille" = Musik-/Ambience-Slot spielt Stille bis eine Datei liegt.
  -- Finale Dateien (ogg/wav) einfach unter `datei` ablegen (17.5).
  -- =========================================================================
  -- 1: Boot-Sequenz
  snd_login_music     = { art = "stille", loop = false, datei = "snd_login_music.ogg" },
  snd_glitch_static   = { art = "rauschen", dauer = 1.4, datei = "snd_glitch_static.ogg" },
  -- 2/3: Grundteppich + Totensicht
  snd_ambience_elwynn = { art = "stille", loop = true, gain = 0.55, datei = "snd_ambience_elwynn.ogg" },
  -- ohne_geisterfilter: der Geisterwind IST die Welt des Geistes und darf
  -- nicht von der Totensicht-Daempfung mitgenommen werden (Issue #55)
  snd_ghost_wind      = { art = "stille", loop = true, gain = 1.0, ohne_geisterfilter = true, datei = "snd_ghost_wind.ogg" },
  -- 4: Schritte (Geister sind lautlos)
  snd_footsteps       = { art = "blip", freq = 90, dauer = 0.25, loop = true, gain = 0.25, datei = "snd_footsteps.ogg" },
  -- 5: Nahkampf
  snd_melee_hit       = { art = "blip", freq = 220, dauer = 0.08, datei = "snd_melee_hit.ogg" },
  -- 6: Caster
  snd_cast_loop       = { art = "blip", freq = 520, dauer = 0.4, loop = true, gain = 0.25, datei = "snd_cast_loop.ogg" },
  snd_impact_fire     = { art = "blip", freq = 330, dauer = 0.12, datei = "snd_impact_fire.ogg" },
  snd_impact_shadow   = { art = "blip", freq = 180, dauer = 0.14, datei = "snd_impact_shadow.ogg" },
  snd_impact_holy     = { art = "blip", freq = 660, dauer = 0.12, datei = "snd_impact_holy.ogg" },
  snd_impact_frost    = { art = "blip", freq = 440, dauer = 0.12, datei = "snd_impact_frost.ogg" },
  -- 7: Jaeger-Autoschuss (der Zauberstab-Slot fiel mit Issue #86 weg)
  snd_shot            = { art = "blip", freq = 500, dauer = 0.07, datei = "snd_shot.ogg" },
  -- 8: Klassen-Signaturen
  snd_shout           = { art = "blip", freq = 250, dauer = 0.3, datei = "snd_shout.ogg" },
  snd_stealth         = { art = "blip", freq = 150, dauer = 0.2, gain = 0.6, datei = "snd_stealth.ogg" },
  snd_imp_summon      = { art = "blip", freq = 400, dauer = 0.35, datei = "snd_imp_summon.ogg" },
  -- 9: Krit-Punch (beide Seiten)
  snd_crit            = { art = "blip", freq = 110, dauer = 0.18, gain = 1.4, datei = "snd_crit.ogg" },
  -- 10: Hogger-Lesbarkeit
  snd_hogger_growl    = { art = "blip", freq = 80, dauer = 0.5, datei = "snd_hogger_growl.ogg" },
  snd_hogger_schmatzen= { art = "blip", freq = 65, dauer = 0.6, loop = true, gain = 1.2, datei = "snd_hogger_schmatzen.ogg" },
  snd_hogger_charge   = { art = "blip", freq = 130, dauer = 0.4, gain = 1.2, datei = "snd_hogger_charge.ogg" },
  snd_hogger_death    = { art = "blip", freq = 70, dauer = 1.2, gain = 1.4, datei = "snd_hogger_death.ogg" },
  -- 11: Mob-Aggro (der Murloc-Schrei ist gesetzt — teuerster Einzelgag)
  snd_wolf_growl      = { art = "blip", freq = 120, dauer = 0.3, datei = "snd_wolf_growl.ogg" },
  snd_murloc          = { art = "blip", freq = 800, dauer = 0.6, gain = 1.2, datei = "snd_murloc.ogg" },
  -- 12/12b: Spieler-Feedback
  snd_player_death    = { art = "blip", freq = 160, dauer = 0.35, datei = "snd_player_death.ogg" },
  snd_jump            = { art = "blip", freq = 300, dauer = 0.08, gain = 0.5, datei = "snd_jump.ogg" },
  snd_land            = { art = "blip", freq = 140, dauer = 0.07, gain = 0.5, datei = "snd_land.ogg" },
  -- 13/14: DING und Plunder
  snd_ding            = { art = "blip", freq = 880, dauer = 0.7, gain = 1.2, datei = "snd_ding.ogg" },
  snd_loot            = { art = "blip", freq = 950, dauer = 0.1, datei = "snd_loot.ogg" },
  snd_ui_click        = { art = "blip", freq = 600, dauer = 0.04, gain = 0.5, datei = "snd_ui_click.ogg" },
  -- 15: Try-Enden (Wipe-Sting: kurz, Moll — lachen, nicht trauern)
  snd_fanfare         = { art = "blip", freq = 523, dauer = 1.5, gain = 1.2, datei = "snd_fanfare.ogg" },
  snd_wipe_sting      = { art = "blip", freq = 233, dauer = 0.9, datei = "snd_wipe_sting.ogg" },
  -- 16: DER Schrei — einzige Voice-Line, Eigenproduktion (Rob/TTS/Suno)
  snd_leeroy_scream   = { art = "blip", freq = 350, dauer = 1.0, gain = 1.4, datei = "snd_leeroy_scream.ogg" },
  -- 17: Charge des Echos bei der Questuebergabe (Ruestungsrasseln/Ansturm).
  -- Ausdruecklich NICHT der Schrei — der gehoert dem Raid-Leeroy (GDD 10.2)
  snd_echo_charge     = { art = "blip", freq = 180, dauer = 0.5, gain = 0.9, datei = "snd_echo_charge.ogg" },
}
