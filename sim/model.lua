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
  -- HP = slope x N - offset (affin, v2.6): der Sockel bildet den
  -- Kleingruppen-Overhead ab; offset=0, slope=120 ergibt die alte Formel
  hogger_hp_slope        = p(430, 100, 800, 10, "9.3"),
  hogger_hp_offset       = p(950, 0, 3000, 50, "9.3"),
  hogger_autohit_dmg     = p(30, 10, 60, 1, "9.2"),
  hogger_cleave_divisor  = p(5, 2, 40, 1, "9.2"),   -- Cleave-Ziele = ceil(N / Divisor)
  hogger_autohit_interval= p(1.8, 1.0, 3.0, 0.1, "9.2"),
  hogger_speed           = p(155, 100, 250, 5, "9.2"),
  hogger_aggro_radius    = p(250, 100, 500, 10, "9.1"),
  hogger_leash_radius    = p(600, 300, 1200, 25, "9.2"),
  hogger_leash_hysteresis= p(2.0, 0, 5, 0.5, "9.1"),
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
  eat_interrupt_offset   = p(2, 0, 5, 1, "9.3"),                 -- ceil(N/10) + offset (v2.6)
  eat_dmg_threshold_pct  = p(0.05, 0.005, 0.15, 0.005, "9.2"),   -- Anteil Max-HP im Kanal (v2.6)

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
  autoshot_dmg           = p(3, 1, 10, 1, "8.1"),
  autoshot_range         = p(200, 100, 400, 10, "8.1"),
  wand_dmg               = p(2, 1, 10, 1, "8.1"),
  wand_range             = p(120, 50, 300, 10, "8.1"),
  melee_range            = p(40, 20, 100, 5, "8.1"),  -- im GDD nicht beziffert, siehe frage-Issue
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
  paladin_holylight_cast = p(2.5, 0.5, 5.0, 0.1, "8.2"),
  paladin_holylight_heal = p(25, 5, 60, 1, "8.2"),
  paladin_holylight_mana = p(35, 5, 100, 5, "8.2"),
  paladin_seal_hits      = p(3, 1, 10, 1, "8.2"),
  paladin_seal_bonus_dmg = p(3, 1, 10, 1, "8.2"),
  paladin_seal_mana      = p(10, 0, 50, 5, "8.2"),
  hunter_raptor_dmg      = p(7, 1, 20, 1, "8.2"),
  hunter_raptor_cd       = p(8, 2, 30, 1, "8.2"),
  rogue_sinister_dmg     = p(5, 1, 20, 1, "8.2"),
  rogue_sinister_energy  = p(40, 10, 100, 5, "8.2"),
  rogue_evis_dmg_per_cp  = p(4, 1, 10, 1, "8.2"),
  rogue_evis_energy      = p(30, 10, 100, 5, "8.2"),
  rogue_stealth_speed    = p(0.6, 0.3, 1.0, 0.05, "8.2"),
  priest_smite_cast      = p(1.5, 0.5, 4.0, 0.1, "8.2"),
  priest_smite_dmg       = p(6, 1, 20, 1, "8.2"),
  priest_smite_mana      = p(15, 5, 60, 5, "8.2"),
  priest_heal_cast       = p(2.0, 0.5, 4.0, 0.1, "8.2"),
  priest_heal_amount     = p(20, 5, 60, 1, "8.2"),
  priest_heal_mana       = p(25, 5, 100, 5, "8.2"),
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
  imp_hp                 = p(15, 5, 50, 5, "8.2"),
  imp_dmg                = p(2, 1, 10, 1, "8.2"),
  imp_interval           = p(2.0, 0.5, 4.0, 0.5, "8.2"),
  druid_wrath_cast       = p(1.5, 0.5, 4.0, 0.1, "8.2"),
  druid_wrath_dmg        = p(6, 1, 20, 1, "8.2"),
  druid_wrath_mana       = p(20, 5, 100, 5, "8.2"),
  druid_touch_cast       = p(3.0, 0.5, 6.0, 0.1, "8.2"),
  druid_touch_heal       = p(30, 5, 80, 1, "8.2"),
  druid_touch_mana       = p(35, 5, 100, 5, "8.2"),

  -- Loop / Todesstrafe (GDD 6, 7.1, 9.3)
  respawn_base           = p(8, 0, 30, 1, "9.3"),
  respawn_factor         = p(0.52, 0, 1.0, 0.01, "9.3"),
  respawn_min            = p(10, 0, 30, 1, "9.3"),
  respawn_max            = p(30, 5, 60, 1, "9.3"),
  try_time_limit         = p(900, 300, 1800, 60, "6"),
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
  -- Try-Start-Bedingung (GDD 10.3): Leeroys allererster Anmarsch wartet, bis
  -- sich der erste echte Spieler wiederbelebt hat — sonst rennt er mitten im
  -- Intro los, das er selbst haelt (Playtest 2026-08-16). Notbremse, falls
  -- niemand auf ein Klassenicon tritt:
  leeroy_first_march_wait = p(120, 10, 600, 10, "10.3"),

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
}

-- bequemer Wertzugriff: M.p("hogger_hp_coeff") -> 120
function M.p(key)
  local entry = M.params[key]
  assert(entry ~= nil, "unbekannter Parameter: " .. tostring(key))
  return entry.wert
end

-- ---------------------------------------------------------------------------
-- Klassen (GDD 8.2) — Bezeichner englisch, Anzeigenamen deutsch.
-- Faehigkeitswerte referenzieren M.params-Schluessel (eine Wahrheit).
-- ---------------------------------------------------------------------------
M.RACES = { "mensch", "zwerg", "nachtelf", "gnom" }

M.classes = {
  warrior = {
    name_de = "Krieger", races = { "mensch", "zwerg", "nachtelf", "gnom" },
    armor = "plate", resource = "rage", attack = "melee",
    abilities = {
      { id = "heroic_strike", name_de = "Heroischer Stoss", dmg = "warrior_heroic_dmg", cost = "warrior_heroic_rage" },
      { id = "battle_shout", name_de = "Schlachtruf", buff_bonus = "warrior_shout_bonus",
        duration = "warrior_shout_duration", cost = "warrior_shout_rage" },
    },
  },
  paladin = {
    name_de = "Paladin", races = { "mensch", "zwerg" },
    armor = "plate", resource = "mana", attack = "melee",
    abilities = {
      { id = "holy_light", name_de = "Heiliges Licht", heal = "paladin_holylight_heal",
        cast = "paladin_holylight_cast", cost = "paladin_holylight_mana" },
      { id = "seal_of_righteousness", name_de = "Siegel der Rechtschaffenheit", bonus_hits = "paladin_seal_hits",
        bonus_dmg = "paladin_seal_bonus_dmg", cost = "paladin_seal_mana" },
    },
  },
  hunter = {
    name_de = "Jaeger", races = { "zwerg", "nachtelf" },
    armor = "leather", resource = "mana", attack = "shot",
    abilities = {
      { id = "raptor_strike", name_de = "Raptorstoss", dmg = "hunter_raptor_dmg", cd = "hunter_raptor_cd" },
    },
  },
  rogue = {
    name_de = "Schurke", races = { "mensch", "zwerg", "nachtelf", "gnom" },
    armor = "leather", resource = "energy", attack = "melee",
    abilities = {
      { id = "sinister_strike", name_de = "Finsterer Stoss", dmg = "rogue_sinister_dmg", cost = "rogue_sinister_energy" },
      { id = "eviscerate", name_de = "Ausweiden", dmg_per_cp = "rogue_evis_dmg_per_cp", cost = "rogue_evis_energy" },
      { id = "stealth", name_de = "Verstohlenheit", speed_factor = "rogue_stealth_speed" },
    },
  },
  priest = {
    name_de = "Priester", races = { "mensch", "zwerg", "nachtelf" },
    armor = "cloth", resource = "mana", attack = "wand",
    abilities = {
      { id = "smite", name_de = "Goettliche Pein", dmg = "priest_smite_dmg", cast = "priest_smite_cast", cost = "priest_smite_mana" },
      { id = "lesser_heal", name_de = "Geringes Heilen", heal = "priest_heal_amount", cast = "priest_heal_cast", cost = "priest_heal_mana" },
    },
  },
  mage = {
    name_de = "Magier", races = { "mensch", "gnom" },
    armor = "cloth", resource = "mana", attack = "wand",
    abilities = {
      { id = "fireball", name_de = "Feuerball", dmg = "mage_fireball_dmg", cast = "mage_fireball_cast", cost = "mage_fireball_mana" },
      { id = "frost_armor", name_de = "Frostruestung", slow = "mage_frostarmor_slow", slow_duration = "mage_frostarmor_slow_duration" },
    },
  },
  warlock = {
    name_de = "Hexenmeister", races = { "mensch", "gnom" },
    armor = "cloth", resource = "mana", attack = "wand",
    abilities = {
      { id = "shadow_bolt", name_de = "Schattenblitz", dmg = "warlock_bolt_dmg", cast = "warlock_bolt_cast", cost = "warlock_bolt_mana" },
      { id = "summon_imp", name_de = "Wichtel beschwoeren", cast = "warlock_imp_cast", cost = "warlock_imp_mana" },
    },
  },
  druid = {
    name_de = "Druide", races = { "nachtelf" },
    armor = "leather", resource = "mana", attack = "melee",
    abilities = {
      { id = "wrath", name_de = "Zorn", dmg = "druid_wrath_dmg", cast = "druid_wrath_cast", cost = "druid_wrath_mana" },
      { id = "healing_touch", name_de = "Heilende Beruehrung", heal = "druid_touch_heal", cast = "druid_touch_cast", cost = "druid_touch_mana" },
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
function M.hogger_hp(n)
  return math.max(120 * n,
    M.p("hogger_hp_slope") * n - M.p("hogger_hp_offset"))
end

function M.eat_heal_per_second(n)
  return M.hogger_hp(n) * M.p("eat_heal_rate")
end

function M.eat_heal_per_channel(n)
  return M.eat_heal_per_second(n) * M.p("eat_channel_duration")
end

function M.eat_interrupters(n)
  return math.ceil(n / 10) + M.p("eat_interrupt_offset")
end

function M.eat_dmg_threshold(n)
  return M.hogger_hp(n) * M.p("eat_dmg_threshold_pct")
end

function M.adds(n)
  return math.floor(n / M.p("add_divisor"))
end

-- Rundumschlag: Gesamtzahl der Autohit-Ziele im Nahkampf (GDD 9.2/9.3, v2.6)
function M.cleave_targets(n)
  return math.ceil(n / M.p("hogger_cleave_divisor"))
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
function M.death_penalty(n)
  return M.respawn_timer(n)
    + M.p("graveyard_to_field_dist") / M.p("move_speed_ghost")
    + M.p("field_to_hill_dist") / M.p("move_speed_alive")
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
