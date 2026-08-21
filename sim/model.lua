-- sim/model.lua — EINZIGE Quelle aller Spielzahlen und Formeln.
-- Quellen: GDD Kap. 6, 7, 8, 9, 10, 13, 17 (docs/gdd.md). Sim und Spiel importieren
-- dieselbe Datei; keine Zahl existiert doppelt (CLAUDE.md: eine Wahrheit pro Frage).
-- Reines Lua 5.1 / LuaJIT: kein love.*, kein os.*, kein math.random.

local M = {}

-- ---------------------------------------------------------------------------
-- Zeitbasis
-- ---------------------------------------------------------------------------
M.TICK_DT = 1 / 60   -- fixer Simulationsschritt des Spiels (GDD Kap. 14, Skill Par. 1)
M.SIM_TICK_DT = 0.1  -- Tickweite der Headless-Balancing-Sim (GDD 17.2)
-- Combopunkte des Schurken (GDD 8.2, Vanilla-Konstante, kein Stellhebel).
-- Stand bis Runde 14 als 5 in vier Dateien; jetzt eine Wahrheit, an der
-- auch die Anzeige haengt (#170).
M.CP_MAX = 5

-- Die Questbelohnung (Runde 18, GDD 5): kein Stellhebel, sondern Inhalt.
-- Steht hier, weil das Questfenster sie VERSPRICHT und der Fluchbruch sie
-- LIEFERT — zwei getippte Zahlen liefen frueher oder spaeter auseinander,
-- und ein Questfenster, das eine Belohnung nennt und nicht liefert, ist
-- ein Fehler, kein Gag. Was das dritte, legendaere Stueck ist, sagt das
-- Questfenster bewusst nicht (game/ui/victory.lua loest es auf).
M.QUEST_REWARD_KUPFER = 1
M.QUEST_REWARD_XP = 10

-- Umrechnung Pixel -> Meter fuer die Anzeige (Runde 14, #171). Die Welt
-- rechnet in Pixeln, der Spieler denkt in Metern wie im deutschen Original:
-- cast_range 200 px entspricht den 30 m des Vanilla-Zauberbereichs, also
-- 6,667 px je Meter. Damit werden Nahkampf 40 px = 6 m, Autoschuss 230 px
-- = 35 m, Heilen 250 px = 38 m — alles nahe an den Originalwerten.
M.PX_PER_METER = 200 / 30

function M.meters(px)
  return math.floor((px or 0) / M.PX_PER_METER + 0.5)
end

-- ---------------------------------------------------------------------------
-- M.params — ALLE Balancing-Werte als flache Tabelle {wert, min, max, schritt,
-- kapitel} (GDD 17.6). Das F10-Tuning-Panel generiert sich vollstaendig daraus.
-- min/max/schritt sind Panel-Stellbereiche (Werkzeug), wert ist die GDD-Wahrheit.
-- ---------------------------------------------------------------------------
local function p(wert, min, max, schritt, kapitel)
  return { wert = wert, min = min, max = max, schritt = schritt, kapitel = kapitel }
end

M.params = {
  -- Hogger (GDD 9.2 / 9.3)
  -- HP = quad x N^2 + slope x N - offset (mild quadratisch seit Runde 6,
  -- #96): der Sockel bildet den Kleingruppen-Overhead ab, der quad-Term
  -- ersetzt die gestrichene N-Skalierung der Todesstrafe
  hogger_hp_quad         = p(3.0, 0, 20, 0.5, "9.3"),
  -- slope 560 -> 620 in Runde 13 (#155-#159): die fuenf neuen Klassen-
  -- Faehigkeiten (Handauflegung, Schild, Totstellen, Wurzeln, Blutpakt)
  -- hoben koordinierte Siege auf 98/95/87 % — der Aufschlag holt F1
  -- zurueck ins Band (Grid + Endsweep in GDD 17.9)
  -- Runde 17: 620 -> 640, Ausgleich fuer die auf 16 min verlaengerte Frist
  -- (mehr Zeit = mehr Siege; der Hebel fuer F1 ist laut GDD 13.3 die HP-Kurve)
  hogger_hp_slope        = p(640, 100, 800, 10, "9.3"),
  -- Historie: Offset 950 -> 850 in Runde 5 (#86, Zauberstab-Aus); Runde 6
  -- (#96) fixer Respawn -> quad-Term neu, slope/offset nachkalibriert.
  -- F1-F6-Belege: Sweeps in GDD 17.9.
  hogger_hp_offset       = p(1600, 0, 3000, 50, "9.3"),
  hogger_autohit_dmg     = p(30, 10, 60, 1, "9.2"),
  hogger_cleave_divisor  = p(6, 2, 40, 1, "9.2"),   -- Cleave-Ziele = ceil(N / Divisor)
  hogger_autohit_interval= p(1.8, 1.0, 3.0, 0.1, "9.2"),
  hogger_speed           = p(155, 100, 250, 5, "9.2"),
  hogger_aggro_radius    = p(250, 100, 500, 10, "9.1"),
  -- Hoggers Revier (Runde 10, #124): KEIN Leash mehr — er verfolgt ueberall
  -- hin, solange er getroffen wird. Der Radius bemisst nur noch seine
  -- Charge-Reichweite (gemessen ab IHM, nicht ab dem Huegel), das Zonenbanner
  -- und die Sperrzone der Ambient-Mobs.
  hogger_zone_radius     = p(600, 300, 1200, 25, "9.2"),
  -- Kein-Kontakt-Reset (Runde 10, #124): erreicht Hogger so lange weder ein
  -- lebendes Ziel NOCH nimmt er Spielerschaden, trabt er heim, heilt voll und
  -- der Try gilt als abgebrochen. Kiten ist damit erlaubt, solange man ihn
  -- trifft. 30 s ist KEIN freier Wert: die Todesstrafe ist konstant 24 s
  -- (GDD 6), der Nachschub muss es nach einem Wipe zurueckschaffen koennen.
  -- Unter 25 s kippt die Regel zum "Wipe beendet den Try sofort".
  hogger_no_contact_reset= p(30, 5, 120, 1, "9.1"),
  hogger_slice_dmg       = p(15, 5, 30, 1, "9.2"),
  hogger_slice_bleed_dmg = p(5, 0, 15, 1, "9.2"),
  hogger_slice_bleed_interval = p(2.0, 0.5, 4.0, 0.5, "9.2"),
  hogger_slice_duration  = p(6, 2, 12, 1, "9.2"),
  hogger_slice_cd        = p(12, 4, 30, 1, "9.2"),
  hogger_charge_cd       = p(10, 5, 60, 1, "9.2"),
  hogger_charge_dmg      = p(25, 5, 60, 1, "9.2"),
  hogger_charge_knockback= p(120, 0, 300, 10, "9.2"),
  hogger_charge_windup   = p(0.8, 0.2, 2.0, 0.1, "9.2"),

  -- Fressen (GDD 9.2)
  eat_cd                 = p(20, 5, 60, 1, "9.2"),
  eat_corpse_radius      = p(200, 50, 500, 10, "9.2"),
  eat_hp_threshold       = p(0.90, 0.5, 1.0, 0.05, "9.2"),
  eat_drag_duration      = p(1.0, 0, 3.0, 0.1, "9.2"),
  eat_channel_duration   = p(8, 2, 20, 1, "9.2"),
  eat_heal_rate          = p(0.015, 0.005, 0.05, 0.001, "9.2"),  -- Anteil Max-HP pro s
  -- Fress-Unterbrechung seit Runde 12 (#140) NUR noch per Schurken-Tritt:
  -- die Spieleranzahl-Bedingung (max(3; ceil(N/6)+1) verschiedene Spieler)
  -- und die 5-%-Schadensschwelle sind ersatzlos gestrichen (Rob-Entscheid).

  -- Krits (GDD 13.2, je Seite getrennt stellbar)
  crit_chance_player     = p(0.05, 0, 0.5, 0.01, "13.2"),
  crit_chance_hogger     = p(0.05, 0, 0.5, 0.01, "13.2"),
  crit_mult_player       = p(2.0, 1.0, 4.0, 0.25, "13.2"),
  crit_mult_hogger       = p(2.0, 1.0, 4.0, 0.25, "13.2"),

  -- Spieler-Basis (GDD 8.1)
  move_speed_alive       = p(140, 80, 250, 5, "8.1"),
  move_speed_ghost       = p(210, 100, 350, 5, "8.1"),
  autohit_melee_dmg      = p(2, 1, 10, 1, "8.1"),
  autohit_interval       = p(2.0, 0.5, 4.0, 0.1, "8.1"),
  autoshot_dmg           = p(4, 1, 10, 1, "8.1"), -- 3 -> 4 in Runde 5 (#86, F1-Ausgleich)
  -- Reichweiten (Runde 5, Issue #80): Caster mussten viel zu nah heran,
  -- der Jaeger bekommt etwas mehr und bleibt die laengste Reichweite
  -- (Vanilla-Verhaeltnis 30:35 yd ~ 200:230 px). cast_range hiess bis
  -- Runde 5 wand_range — der Zauberstab ist weg (Issue #86), die
  -- Zauber-Reichweite aller Caster-Faehigkeiten bleibt.
  autoshot_range         = p(230, 100, 400, 10, "8.1"),
  cast_range             = p(200, 50, 300, 10, "8.1"),
  melee_range            = p(40, 20, 100, 5, "8.1"),  -- im GDD nicht beziffert, siehe frage-Issue
  -- Heil-Reichweite (Runde 7, #103): Zauber mit target="ally" auf ANDERE;
  -- Selbstheilung ist immer Reichweite 0. Die 1D-Sim prueft sie bewusst
  -- NICHT: der maximale 1D-Spielerabstand ist cast_range - melee_range
  -- = 160 px < 250 px, eine Pruefung koennte dort nie binden (toter Code
  -- mit Falsifikationsrisiko). Revisionsausloeser in GDD 17.9.
  heal_range             = p(250, 100, 400, 10, "8.1"),
  gcd                    = p(1.5, 0.5, 3.0, 0.1, "8.1"),
  -- Frontbogen fuer Angriffe (GDD 8.1, Playtest 2026-08-16): das Ziel muss
  -- vor einem liegen, Wegdrehen bricht laufende Zauber ab. 360 = Regel aus.
  facing_arc_deg         = p(180, 60, 360, 10, "8.1"),
  hp_plate               = p(80, 40, 160, 5, "8.1"),
  hp_leather             = p(65, 30, 130, 5, "8.1"),
  hp_cloth               = p(50, 25, 100, 5, "8.1"),
  mana_max               = p(100, 50, 300, 10, "8.1"),
  five_sec_rule_wait     = p(5, 1, 15, 0.5, "8.1"),
  mana_regen_rate        = p(10, 0, 40, 1, "8.1"),
  rage_max               = p(100, 50, 100, 10, "8.1"),
  rage_per_hit_taken     = p(5, 0, 20, 1, "8.1"),
  rage_per_hit_dealt     = p(3, 0, 20, 1, "8.1"),
  energy_max             = p(100, 50, 200, 10, "8.1"),
  energy_regen_rate      = p(10, 1, 40, 1, "8.1"),
  revive_channel         = p(2.0, 0, 5.0, 0.5, "5"),

  -- Bedrohung (GDD 9.4)
  threat_per_damage      = p(1.0, 0.1, 3.0, 0.05, "9.4"),
  threat_per_heal        = p(0.75, 0.1, 3.0, 0.05, "9.4"),

  -- Klassen-Faehigkeiten (GDD 8.2)
  warrior_heroic_dmg     = p(6, 1, 20, 1, "8.2"),
  warrior_heroic_rage    = p(15, 5, 50, 5, "8.2"),
  warrior_shout_bonus    = p(0.15, 0, 0.5, 0.05, "8.2"),
  warrior_shout_radius   = p(300, 100, 800, 25, "8.2"),  -- "im Umkreis", GDD unbeziffert
  warrior_shout_duration = p(15, 5, 60, 5, "8.2"),
  warrior_shout_rage     = p(10, 0, 50, 5, "8.2"),
  -- Spott (Runde 12, #141): einzige Klasse, die Aggro kurzfristig erzwingt
  -- — "um sich zu opfern" (Rob). 10 s Cooldown und 3 s Zwang wie im
  -- Vanilla-Original; Reichweite etwas ueber Nahkampf, damit der Krieger
  -- den Zug ansagen kann, bevor er drinsteht.
  warrior_taunt_cd       = p(10, 2, 60, 1, "8.2"),
  warrior_taunt_duration = p(3, 1, 10, 0.5, "8.2"),
  warrior_taunt_range    = p(100, 40, 300, 10, "8.2"),
  paladin_holylight_cast = p(2.5, 0.5, 5.0, 0.1, "8.2"),
  paladin_holylight_heal = p(25, 5, 60, 1, "8.2"),
  paladin_holylight_mana = p(35, 5, 100, 5, "8.2"),
  paladin_seal_hits      = p(3, 1, 10, 1, "8.2"),
  paladin_seal_bonus_dmg = p(3, 1, 10, 1, "8.2"),
  paladin_seal_mana      = p(10, 0, 50, 5, "8.2"),
  -- Handauflegung (Runde 13, #155): heilt VOLL, kostet ALLES Mana, einmal
  -- pro Leben — beides Regel statt Zahl, deshalb nur der Schalter
  paladin_loh_enabled    = p(1, 0, 1, 1, "8.2"),
  hunter_raptor_dmg      = p(7, 1, 20, 1, "8.2"),
  hunter_raptor_cd       = p(8, 2, 30, 1, "8.2"),
  -- Totstellen (Runde 13, #157): das Gegenstueck zum Spott — die einzige
  -- Klasse, die Aggro LOSWIRD. Rettet nur den Jaeger, nicht den Raid.
  hunter_feign_enabled   = p(1, 0, 1, 1, "8.2"),
  hunter_feign_cd        = p(30, 5, 120, 5, "8.2"),
  hunter_feign_duration  = p(2, 0.5, 6, 0.5, "8.2"),
  rogue_sinister_dmg     = p(5, 1, 20, 1, "8.2"),
  rogue_sinister_energy  = p(40, 10, 100, 5, "8.2"),
  rogue_evis_dmg_per_cp  = p(4, 1, 10, 1, "8.2"),
  rogue_evis_energy      = p(30, 10, 100, 5, "8.2"),
  -- Verstohlenheit (Runde 14, #169): abschaltbar wie die Faehigkeiten aus
  -- Runde 13; nutzbar nur ausserhalb des Kampfes, Aggro setzt sie NICHT
  -- zurueck (Rob-Entscheid)
  rogue_stealth_enabled  = p(1, 0, 1, 1, "8.2"),
  rogue_stealth_speed    = p(0.6, 0.3, 1.0, 0.05, "8.2"),
  -- Tritt (Runde 12, #140): der EINZIGE Fress-Unterbrecher. 10 s Cooldown
  -- ist Robs Vorgabe; 25 Energie ist der Vanilla-Kick-Preis.
  rogue_kick_energy      = p(25, 0, 100, 5, "8.2"),
  rogue_kick_cd          = p(10, 2, 60, 1, "8.2"),
  priest_smite_cast      = p(1.5, 0.5, 4.0, 0.1, "8.2"),
  priest_smite_dmg       = p(6, 1, 20, 1, "8.2"),
  priest_smite_mana      = p(15, 5, 60, 5, "8.2"),
  priest_heal_cast       = p(2.0, 0.5, 4.0, 0.1, "8.2"),
  priest_heal_amount     = p(20, 5, 60, 1, "8.2"),
  priest_heal_mana       = p(25, 5, 100, 5, "8.2"),
  -- Machtwort: Schild (Runde 13, #156): der einzige Schadens-VERHINDERER.
  -- Absorb 20 liegt bewusst UNTER einem Hogger-Autohit (30); Schwache
  -- Seele drosselt dasselbe Ziel.
  priest_pws_enabled     = p(1, 0, 1, 1, "8.2"),
  priest_pws_absorb      = p(20, 5, 60, 1, "8.2"),
  priest_pws_duration    = p(10, 3, 30, 1, "8.2"),
  priest_pws_weaksoul    = p(15, 5, 60, 1, "8.2"),
  priest_pws_mana        = p(30, 5, 100, 5, "8.2"),
  mage_fireball_cast     = p(2.5, 0.5, 5.0, 0.1, "8.2"),
  mage_fireball_dmg      = p(11, 1, 30, 1, "8.2"),
  mage_fireball_mana     = p(30, 5, 100, 5, "8.2"),
  mage_frostarmor_slow   = p(0.25, 0, 0.75, 0.05, "8.2"),
  mage_frostarmor_slow_duration = p(3, 1, 10, 0.5, "8.2"),
  warlock_bolt_cast      = p(2.0, 0.5, 5.0, 0.1, "8.2"),
  warlock_bolt_dmg       = p(8, 1, 30, 1, "8.2"),
  warlock_bolt_mana      = p(25, 5, 100, 5, "8.2"),
  warlock_imp_cast       = p(3.0, 0.5, 6.0, 0.5, "8.2"),
  warlock_imp_mana       = p(30, 5, 100, 5, "8.2"),
  -- Blutpakt (Runde 13, #159): der lebende Wichtel staerkt alle Spieler
  -- in seinem Umkreis um einen Anteil Maximal-HP (Robs Variante statt
  -- Gesundheitsstein). Kein Gratis-Heil: nur der Deckel steigt.
  warlock_pact_enabled   = p(1, 0, 1, 1, "8.2"),
  warlock_pact_hp_pct    = p(0.10, 0, 0.5, 0.01, "8.2"),
  warlock_pact_radius    = p(200, 50, 600, 10, "8.2"),
  imp_hp                 = p(15, 5, 50, 5, "8.2"),
  imp_dmg                = p(2, 1, 10, 1, "8.2"),
  imp_interval           = p(2.0, 0.5, 4.0, 0.5, "8.2"),
  druid_wrath_cast       = p(1.5, 0.5, 4.0, 0.1, "8.2"),
  druid_wrath_dmg        = p(6, 1, 20, 1, "8.2"),
  druid_wrath_mana       = p(20, 5, 100, 5, "8.2"),
  druid_touch_cast       = p(3.0, 0.5, 6.0, 0.1, "8.2"),
  druid_touch_heal       = p(30, 5, 80, 1, "8.2"),
  druid_touch_mana       = p(35, 5, 100, 5, "8.2"),
  -- Gnarlwurzeln (Runde 13, #158): Mob-/Add-Kontrolle. Hogger ist immun
  -- (Boss, klassisch), Schaden bricht die Wurzeln.
  druid_roots_enabled    = p(1, 0, 1, 1, "8.2"),
  druid_roots_duration   = p(5, 1, 15, 1, "8.2"),
  druid_roots_cd         = p(15, 5, 60, 1, "8.2"),
  druid_roots_mana       = p(10, 0, 50, 5, "8.2"),

  -- Loop / Todesstrafe (GDD 6, 7.1, 9.3)
  -- Rob-Entscheid Runde 6 (#96): der Respawn-Timer ist FEST — er skaliert
  -- nicht mehr mit N (factor 0). Die F6-Fairness liegt seitdem auf den
  -- N-Hebeln Cleave/Adds (17.9).
  respawn_base           = p(10, 0, 30, 1, "9.3"),
  respawn_factor         = p(0, 0, 1.0, 0.01, "9.3"),
  respawn_min            = p(10, 0, 30, 1, "9.3"),
  respawn_max            = p(30, 5, 60, 1, "9.3"),
  -- Runde 17 (Rob-Entscheid): 900 -> 960 s, und die Uhr zaehlt RUNTER
  -- (GDD 4.2). Anlass: bei einem Abend mit ~46 Spielern liefen zwei Trys in
  -- die Frist, waehrend der Raid bis zur letzten Sekunde zuschlug.
  -- WARUM NICHT MEHR: das Zeitlimit ist nicht nur eine Notbremse, es ist die
  -- eigentliche Schwierigkeit. Gemessen (Richtungstest, 100 Laeufe je Zelle):
  -- 20 min bei unveraenderter HP-Kurve -> Siegquote 99/97/100/100 % gegen ein
  -- Band von 60-90 %. Gegensteuern geht nur ueber Boss-HP, und dann waechst
  -- die Trylaenge mit: 20 min brauchen slope 760 und ergeben 15-16,5 min
  -- Median-Siegtry — F5 (6-13 min) waere gerissen. 16 min mit slope 640 ist
  -- der weiteste Punkt, an dem alle sieben Kriterien halten.
  try_time_limit         = p(960, 300, 1800, 60, "6"),
  -- Feldposition = Feinsteller der Todesstrafe (GDD 7.1); Laufweg-Anteil
  -- 14 s gesamt (M1-Sweep): Geisterlauf 8 s + Restanmarsch 6 s
  graveyard_to_field_dist= p(1680, 500, 6000, 50, "7.1"),
  field_to_hill_dist     = p(840, 300, 4000, 50, "7.1"),

  -- Ambient-Mobs (GDD 7.2 / 7.3)
  mob_slot_base          = p(4, 0, 12, 1, "7.2"),
  mob_slot_divisor       = p(5, 1, 20, 1, "7.2"),
  mob_respawn            = p(120, 30, 600, 10, "7.2"),
  boar_hp                = p(12, 5, 40, 1, "7.2"),
  boar_dmg               = p(4, 1, 15, 1, "7.2"),
  boar_flee_hp_pct       = p(0.25, 0, 0.9, 0.05, "7.2"),
  wolf_hp                = p(10, 5, 40, 1, "7.2"),
  wolf_dmg               = p(5, 1, 15, 1, "7.2"),
  wolf_aggro_radius      = p(80, 20, 300, 10, "7.2"),
  kobold_hp              = p(14, 5, 40, 1, "7.2"),
  kobold_dmg             = p(4, 1, 15, 1, "7.2"),
  murloc_hp              = p(12, 5, 40, 1, "7.2"),
  murloc_dmg             = p(5, 1, 15, 1, "7.2"),
  mob_attack_interval    = p(2.0, 0.5, 4.0, 0.5, "7.2"),
  -- Leerlauf-Patrouille (Runde 5, Issue #87): 0 = aus
  mob_patrol_radius      = p(60, 0, 200, 5, "7.2"),
  mob_patrol_speed       = p(45, 10, 140, 5, "7.2"),
  xp_per_mob             = p(1, 0, 5, 1, "7.3"),
  xp_level2              = p(400, 100, 1000, 50, "7.3"),

  -- Adds: Gnoll-Welpen (GDD 9.2 / 9.3)
  add_divisor            = p(8, 2, 20, 1, "9.3"),
  add_hp                 = p(20, 5, 60, 5, "9.2"),
  add_dmg                = p(10, 1, 30, 1, "9.2"),
  add_attack_interval    = p(2.0, 0.5, 4.0, 0.5, "9.2"),

  -- Leeroy (GDD 10)
  leeroy_announcer_throttle = p(10, 2, 60, 1, "10"),
  leeroy_threat_factor   = p(0.5, 0.1, 1.0, 0.05, "10"),
  leeroy_kragen_trys     = p(3, 1, 10, 1, "10"),
  leeroy_stuck_timeout   = p(5, 1, 15, 1, "10"),
  -- Try-Start-Bedingung (GDD 10.3): Leeroys allererster Anmarsch wartet auf
  -- die erste angenommene Quest auf dem Realm — sonst rennt er los, waehrend
  -- sein Echo noch redet (Playtest 2026-08-16). Notbremse, falls niemand
  -- annimmt:
  leeroy_first_march_wait = p(120, 10, 600, 10, "10.3"),
  -- Geist freilassen (GDD Kap. 11): Nachfrist, nach der die Freigabe von
  -- selbst passiert. Der Respawn-Timer selbst bleibt die Todesstrafe —
  -- freigeben kann man erst, wenn er abgelaufen ist (GDD Kap. 6).
  release_grace          = p(5, 0, 60, 1, "11"),

  -- Sim-Streuungsmodell (GDD 17.2 Punkt 5b, v2.6) — Agentenmodell, kein Spielverhalten
  sim_skill_min          = p(0.7, 0.3, 1.0, 0.05, "17.2"),
  sim_skill_max          = p(1.3, 1.0, 2.0, 0.05, "17.2"),
  sim_group_factor_min   = p(0.75, 0.5, 1.0, 0.05, "17.2"),
  sim_group_factor_max   = p(1.25, 1.0, 1.5, 0.05, "17.2"),

  -- UI (GDD 4.1 / 4.2)
  zoom_radius_1          = p(300, 150, 600, 25, "4.2"),
  zoom_radius_2          = p(450, 200, 900, 25, "4.2"),
  zoom_radius_3          = p(600, 300, 1200, 25, "4.2"),
  floating_text_max      = p(30, 10, 60, 5, "4.1"),
  floating_text_duration = p(1.5, 0.5, 4.0, 0.25, "4.1"),
  -- Bedrohungsbogen am Minimap-Rand (Runde 14, #174): eigener Anteil an der
  -- Spitzenbedrohung. Abschaltbar, weil er im 40-Mann-Zerg auch Unruhe
  -- stiften kann — das entscheidet der Playtest.
  ui_threat_meter        = p(1, 0, 1, 1, "4.2"),
  -- Runde 17: Nachlauf der Heil-Leiste. Wer voll geheilt wurde, bleibt so
  -- lange stehen — sonst klappt die Liste unter dem Cursor zusammen, genau
  -- in dem Moment, in dem der Heiler den naechsten anklicken will.
  healbar_grace          = p(3, 0, 10, 0.5, "4.3"),
}

-- GDD-Stand jedes Parameters, eingefroren beim Laden: das F10-Panel mutiert
-- M.params in-place, der CSV-Export (GDD 17.6, Issue #82) braucht die
-- Abweichung vom Default.
M.defaults = {}
for k, e in pairs(M.params) do M.defaults[k] = e.wert end

-- bequemer Wertzugriff: M.p("hogger_hp_coeff") -> 120
-- Die Fehlermeldung wird ERST im Fehlerfall gebaut: assert() haette den
-- String bei jedem der ~100 Aufrufe pro Entitaet und Tick zusammengesetzt
-- (Runde 14, #175 — gemessener Sim-Hotspot, Verhalten unveraendert).
function M.p(key)
  local entry = M.params[key]
  if entry == nil then
    error("unbekannter Parameter: " .. tostring(key), 2)
  end
  return entry.wert
end

-- ---------------------------------------------------------------------------
-- Klassen (GDD 8.2) — Bezeichner englisch, Anzeigenamen deutsch.
-- Faehigkeitswerte referenzieren M.params-Schluessel (eine Wahrheit).
-- ---------------------------------------------------------------------------
M.RACES = { "mensch", "zwerg", "nachtelf", "gnom" }

-- attack: "shot" = Jaeger-Autoschuss (die einzige kostenlose Fernkampf-
-- Autoattack, laeuft automatisch); "melee" = Nahkampf-Autohit, der seit
-- Runde 5 (Issue #86) ANGESCHALTET werden muss (Rechtsklick, Taste 4 oder
-- irgendein Faehigkeitsdruck) — den Zauberstab gibt es nicht mehr.
M.classes = {
  warrior = {
    name_de = "Krieger", races = { "mensch", "zwerg", "nachtelf", "gnom" },
    armor = "plate", resource = "rage", attack = "melee",
    abilities = {
      { id = "heroic_strike", art = "Schaden", name_de = "Heroischer Stoss", dmg = "warrior_heroic_dmg", cost = "warrior_heroic_rage" },
      { id = "battle_shout", art = "Verstaerkung", name_de = "Schlachtruf", buff_bonus = "warrior_shout_bonus",
        duration = "warrior_shout_duration", cost = "warrior_shout_rage" },
      { id = "taunt", art = "Aggro", name_de = "Spott", cd = "warrior_taunt_cd",
        duration = "warrior_taunt_duration" },
    },
  },
  paladin = {
    name_de = "Paladin", races = { "mensch", "zwerg" },
    armor = "plate", resource = "mana", attack = "melee",
    abilities = {
      { id = "holy_light", art = "Heilung", name_de = "Heiliges Licht", heal = "paladin_holylight_heal",
        cast = "paladin_holylight_cast", cost = "paladin_holylight_mana" },
      { id = "seal_of_righteousness", art = "Verstaerkung", name_de = "Siegel der Rechtschaffenheit", bonus_hits = "paladin_seal_hits",
        bonus_dmg = "paladin_seal_bonus_dmg", cost = "paladin_seal_mana" },
      { id = "lay_on_hands", art = "Notheilung", name_de = "Handauflegung", enabled = "paladin_loh_enabled" },
    },
  },
  hunter = {
    name_de = "Jaeger", races = { "zwerg", "nachtelf" },
    armor = "leather", resource = "mana", attack = "shot",
    abilities = {
      { id = "raptor_strike", art = "Schaden", name_de = "Raptorstoss", dmg = "hunter_raptor_dmg", cd = "hunter_raptor_cd" },
      { id = "feign_death", art = "Aggro-Reset", name_de = "Totstellen", cd = "hunter_feign_cd",
        duration = "hunter_feign_duration", enabled = "hunter_feign_enabled" },
    },
  },
  rogue = {
    name_de = "Schurke", races = { "mensch", "zwerg", "nachtelf", "gnom" },
    armor = "leather", resource = "energy", attack = "melee",
    abilities = {
      { id = "sinister_strike", art = "Schaden + Combopunkt", name_de = "Finsterer Stoss", dmg = "rogue_sinister_dmg", cost = "rogue_sinister_energy" },
      { id = "eviscerate", art = "Schaden, verbraucht Combopunkte", name_de = "Ausweiden", dmg_per_cp = "rogue_evis_dmg_per_cp", cost = "rogue_evis_energy" },
      { id = "stealth", art = "Tarnung", name_de = "Verstohlenheit", speed_factor = "rogue_stealth_speed",
        enabled = "rogue_stealth_enabled" },
      { id = "kick", art = "Unterbrechung", name_de = "Tritt", cost = "rogue_kick_energy", cd = "rogue_kick_cd" },
    },
  },
  priest = {
    name_de = "Priester", races = { "mensch", "zwerg", "nachtelf" },
    armor = "cloth", resource = "mana", attack = "melee",
    abilities = {
      { id = "smite", art = "Schaden", name_de = "Goettliche Pein", dmg = "priest_smite_dmg", cast = "priest_smite_cast", cost = "priest_smite_mana" },
      { id = "lesser_heal", art = "Heilung", name_de = "Geringes Heilen", heal = "priest_heal_amount", cast = "priest_heal_cast", cost = "priest_heal_mana" },
      { id = "power_word_shield", art = "Schild", name_de = "Machtwort: Schild", absorb = "priest_pws_absorb",
        duration = "priest_pws_duration", cost = "priest_pws_mana", enabled = "priest_pws_enabled" },
    },
  },
  mage = {
    name_de = "Magier", races = { "mensch", "gnom" },
    armor = "cloth", resource = "mana", attack = "melee",
    abilities = {
      { id = "fireball", art = "Schaden", name_de = "Feuerball", dmg = "mage_fireball_dmg", cast = "mage_fireball_cast", cost = "mage_fireball_mana" },
      { id = "frost_armor", art = "Verstaerkung + Verlangsamung", name_de = "Frostruestung", slow = "mage_frostarmor_slow", slow_duration = "mage_frostarmor_slow_duration" },
    },
  },
  warlock = {
    name_de = "Hexenmeister", races = { "mensch", "gnom" },
    armor = "cloth", resource = "mana", attack = "melee",
    abilities = {
      { id = "shadow_bolt", art = "Schaden", name_de = "Schattenblitz", dmg = "warlock_bolt_dmg", cast = "warlock_bolt_cast", cost = "warlock_bolt_mana" },
      { id = "summon_imp", art = "Beschwoerung", name_de = "Wichtel beschwoeren", cast = "warlock_imp_cast", cost = "warlock_imp_mana" },
    },
  },
  druid = {
    name_de = "Druide", races = { "nachtelf" },
    armor = "leather", resource = "mana", attack = "melee",
    abilities = {
      { id = "wrath", art = "Schaden", name_de = "Zorn", dmg = "druid_wrath_dmg", cast = "druid_wrath_cast", cost = "druid_wrath_mana" },
      { id = "healing_touch", art = "Heilung", name_de = "Heilende Beruehrung", heal = "druid_touch_heal", cast = "druid_touch_cast", cost = "druid_touch_mana" },
      { id = "entangling_roots", art = "Kontrolle", name_de = "Gnarlwurzeln", duration = "druid_roots_duration",
        cd = "druid_roots_cd", cost = "druid_roots_mana", enabled = "druid_roots_enabled" },
    },
  },
}

M.CLASS_IDS = { "warrior", "paladin", "hunter", "rogue", "priest", "mage", "warlock", "druid" }

function M.hp_for_class(class_id)
  local armor = M.classes[class_id].armor
  if armor == "plate" then return M.p("hp_plate") end
  if armor == "leather" then return M.p("hp_leather") end
  return M.p("hp_cloth")
end

-- Rassenwurf bei Wiederbelebung (GDD 5): 2/3 Mensch, wo erlaubt, Rest gleichverteilt.
-- rand01: Zahl in [0,1) aus dem Host-RNG (sim/rng.lua). Rein kosmetisch.
function M.roll_race(class_id, rand01)
  local races = M.classes[class_id].races
  local others = {}
  local has_human = false
  for _, r in ipairs(races) do
    if r == "mensch" then has_human = true else others[#others + 1] = r end
  end
  if has_human then
    if rand01 < 2 / 3 or #others == 0 then return "mensch" end
    local u = (rand01 - 2 / 3) * 3 -- Rest des Wurfs auf [0,1) strecken
    return others[1 + math.floor(u * #others)]
  end
  return races[1 + math.floor(rand01 * #races)]
end

-- ---------------------------------------------------------------------------
-- Skalierungsformeln (GDD 9.3) — die harten Testfaelle der Stufe 1
-- ---------------------------------------------------------------------------
local function clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

-- Untergrenze 120 x N: unterhalb der Design-Spanne (N < ~3, z. B. Host
-- wartet allein auf Mitspieler) wuerde die affine Formel degenerieren
-- (N=1: 430-950 -> 1 HP, Hogger stirbt an einem Schlag)
-- HP-Formel seit Runde 6 (#96) mild quadratisch: der feste Respawn-Timer
-- nahm der Schwierigkeit ihren superlinearen Anteil (Todesstrafe skalierte
-- mit N) — der quad-Term bringt ihn zurueck, sonst rollen grosse Raids per
-- Materialschlacht drueber (Sweep: N=20/40 bei 100 % Siegen).
function M.hogger_hp(n)
  return math.max(120 * n, math.floor(
    M.p("hogger_hp_quad") * n * n
    + M.p("hogger_hp_slope") * n - M.p("hogger_hp_offset") + 0.5))
end

function M.eat_heal_per_second(n)
  return M.hogger_hp(n) * M.p("eat_heal_rate")
end

function M.eat_heal_per_channel(n)
  return M.eat_heal_per_second(n) * M.p("eat_channel_duration")
end

-- Die Unterbrecher-Formel (max(3; ceil(N/6)+1) verschiedene Spieler) und
-- die Schadensschwelle sind seit Runde 12 (#140) GESTRICHEN: Unterbrechen
-- kann nur noch der Schurken-Tritt (rogue_kick_cd/energy, 8.2).

function M.adds(n)
  return math.floor(n / M.p("add_divisor"))
end

-- Rundumschlag: Gesamtzahl der Autohit-Ziele im Nahkampf (GDD 9.2/9.3, v2.6)
function M.cleave_targets(n)
  return math.ceil(n / M.p("hogger_cleave_divisor"))
end

-- Sekunden als m:ss. Steht hier, weil sie inzwischen an drei Stellen
-- gebraucht wird (Uhr am Ring, Questziel, Questtext) und eine zweite
-- Formatierung frueher oder spaeter anders rundet als die erste.
function M.mmss(sec)
  sec = math.max(0, sec or 0)
  return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

function M.respawn_timer(n)
  return clamp(M.p("respawn_base") + M.p("respawn_factor") * n,
               M.p("respawn_min"), M.p("respawn_max"))
end

function M.mob_slots(n)
  return M.p("mob_slot_base") + math.floor(n / M.p("mob_slot_divisor"))
end

-- theoretisches Maximum an Mob-Kills des ganzen Raids in einem Try (GDD 7.3:
-- Stufe 2 muss praktisch unerreichbar bleiben; Test haelt das < xp_level2)
function M.max_mob_kills_per_try(n)
  local respawns = math.floor(M.p("try_time_limit") / M.p("mob_respawn"))
  return M.mob_slots(n) * (1 + respawns)
end

-- Todesstrafe in Sekunden: Respawn-Timer + Geisterlauf + lebendiger Restanmarsch
-- (GDD 6/7.1; Zielkorridor 25-35 s, fixiert per M1-Sweep)
-- Laufweg-Anteil der Todesstrafe (Geisterweg + Anmarsch). N-unabhaengig und
-- seit Runde 6 (#96) per Rob-Entscheid fest — die Sim leitet ihren Standard
-- hier ab, statt eine zweite Zahl zu fuehren (Runde 14, #175).
function M.walk_time()
  return M.p("graveyard_to_field_dist") / M.p("move_speed_ghost")
       + M.p("field_to_hill_dist") / M.p("move_speed_alive")
end

function M.death_penalty(n)
  return M.respawn_timer(n) + M.walk_time()
end

-- ---------------------------------------------------------------------------
-- Krit-Regeln (GDD 13.2): 5 % x2 beide Seiten, auch Heilungen.
-- Ausgeschlossen: Charge, Slice, Fress-Heilung, DoT-Ticks, Adds.
-- ---------------------------------------------------------------------------
local CRIT_ALLOWED = {
  autohit = true, ability = true, heal = true, mob = true,
  charge = false, slice = false, dot = false, eat_heal = false, add = false,
}

function M.can_crit(kind)
  local allowed = CRIT_ALLOWED[kind]
  assert(allowed ~= nil, "unbekannte Schadensart: " .. tostring(kind))
  return allowed
end

-- ---------------------------------------------------------------------------
-- Bedrohung (GDD 9.4)
-- ---------------------------------------------------------------------------
function M.threat_for(amount, is_heal)
  if is_heal then return amount * M.p("threat_per_heal") end
  return amount * M.p("threat_per_damage")
end

-- ---------------------------------------------------------------------------
-- Mob-Tabelle (GDD 7.2) — Kupferwerte fest je Typ (GDD 7.3: 1-3, fester Wert)
-- ---------------------------------------------------------------------------
M.mobs = {
  boar   = { name_de = "Wildschwein",    hp = "boar_hp",   dmg = "boar_dmg",   kupfer = 1,
             passive = true, flee_hp_pct = "boar_flee_hp_pct" },
  wolf   = { name_de = "Junger Wolf",    hp = "wolf_hp",   dmg = "wolf_dmg",   kupfer = 2,
             passive = false, aggro_radius = "wolf_aggro_radius" },
  kobold = { name_de = "Kobold-Arbeiter", hp = "kobold_hp", dmg = "kobold_dmg", kupfer = 2,
             passive = true },
  murloc = { name_de = "Murloc",         hp = "murloc_hp", dmg = "murloc_dmg", kupfer = 3,
             passive = false, river_only = true },
}

return M
