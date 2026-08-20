-- sim/engine.lua — Headless-Balancing-Sim (GDD 17.2).
-- Reines Lua 5.1: kein love.*, kein os.*, kein math.random (Tests vergiften das).
-- Raeumliches Modell: 1D-Distanz zum Boss, Reichweiten als Schwellen, kein Pathing.
-- Dokumentierte Vereinfachungen: siehe reports/ (M1-Validierungsbericht).

local model = require("sim.model")
local rngmod = require("sim.rng")
local hashmod = require("sim.hash")

local E = {}

local HUGE = math.huge

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------
-- Wunschabstand zum Boss. Seit Runde 5 (Issue #86) gibt es keinen
-- Zauberstab mehr: Caster stehen auf Zauberreichweite, solange das Mana
-- fuer ihren Angriffszauber reicht, und ruecken OOM zum Stab-Vermoebeln
-- in den Nahkampf auf (mit Mana ziehen sie sich wieder zurueck). Die
-- Sim-Agenten schalten ihren Autohit per Definition an (im Spiel:
-- Rechtsklick/Taste 4). Erster Modellversuch "alle Caster dauerhaft im
-- Nahkampf" ist falsifiziert: Hoggers Cleave frisst bei grossen N die
-- Heiler, N=40 fiel von ~74 % auf 4 % Siege (17.9).
-- Stab-Phase (#86) nur fuer die reinen Schadens-Caster: OOM -> rein und
-- PRUEGELN, bis der Pool sich ueber die Fuenf-Sekunden-Regel erholt hat
-- (waehrenddessen kein Cast, sonst greift die FSR nie); erst mit halbem
-- Pool wieder raus. Modell-Iterationen (17.9): alle Caster dauerhaft im
-- Nahkampf -> N=40 bei 4 % (Cleave frisst die Heiler); Pendeln nach jedem
-- Zauber -> 23 %; Stab-Phase auch fuer Priester -> Heiler-Ausfall, 22 %.
-- Priester bleiben deshalb auf Zauberreichweite (Heil-Mana ist wertvoller
-- als 1 DPS Stab), der Druide steht im Modell wie eh und je im Nahkampf.
local CASTER_NUKE_COST = {
  mage = "mage_fireball_mana", warlock = "warlock_bolt_mana",
}
local function desired_range(p)
  local attack = model.classes[p.class].attack
  if attack == "shot" then return model.p("autoshot_range") end
  if p.class == "priest" then return model.p("cast_range") end
  local nuke = CASTER_NUKE_COST[p.class]
  if not nuke then return model.p("melee_range") end
  if p.want_melee then
    if p.resource >= 0.5 * model.p("mana_max") then p.want_melee = false end
  elseif p.resource < model.p(nuke) then
    p.want_melee = true
  end
  return p.want_melee and model.p("melee_range") or model.p("cast_range")
end
E.desired_range = desired_range

local function log_ev(run, t, ev, src, dst, val, crit)
  if not run.cfg.log then return end
  run.events[#run.events + 1] = string.format(
    '{"t":%d,"ev":"%s","src":"%s","dst":%s,"val":%s,"crit":%s}',
    math.floor(t * 10 + 0.5), ev, tostring(src),
    dst and ('"' .. tostring(dst) .. '"') or "null",
    val and string.format("%.17g", val) or "null",
    crit == nil and "null" or tostring(crit))
end
E.log_ev = log_ev

-- ---------------------------------------------------------------------------
-- Spieler anlegen
-- ---------------------------------------------------------------------------
local function make_player(run, id, class, is_leeroy)
  local p = {
    id = id, class = class, is_leeroy = is_leeroy or false, skill = 1,
    alive = false, hp = 0, max_hp = model.hp_for_class(class),
    resource = 0, cp = 0,
    d = HUGE, state = "dead", dead_until = 0,
    gcd_ready = 0, cast = nil, last_cast_t = -1000,
    next_auto = 0, raptor_ready = 0, kick_ready = 0, loh_used = false,
    shield_hp = 0, shield_until = 0, weak_soul_until = 0, feign_ready = 0,
    pact = false,
    threat = 0,
    bleed_until = 0, bleed_next = HUGE,
    shout_until = 0, seal_hits = 0, has_frost_armor = false,
    imp_alive = false,
    add_idx = nil,          -- gebundenes Add (1v1 beim Anmarsch)
    combat_time = 0,
    dmg_done = 0, heal_done = 0, deaths = 0,
  }
  return p
end

local function resource_max(p)
  local r = model.classes[p.class].resource
  if r == "mana" then return model.p("mana_max") end
  if r == "energy" then return model.p("energy_max") end
  return model.p("rage_max")
end

local function spawn_player(run, p, at_range)
  -- Klassenwechsel bei Wiederbelebung (GDD 5; koordinierte Konvergenz 17.2)
  if run.agent.choose_class then
    local cl = run.agent.choose_class(run, p)
    if cl and cl ~= p.class then
      log_ev(run, run.t, "class_change", p.id, cl, nil, nil)
      p.class = cl
      p.max_hp = model.hp_for_class(cl)
    end
  end
  p.alive = true
  p.state = "combat"
  p.hp = p.max_hp
  local r = model.classes[p.class].resource
  p.resource = (r == "rage") and 0 or resource_max(p)
  p.cp = 0
  p.d = at_range
        or (run.agent.desired_range and run.agent.desired_range(run, p))
        or desired_range(p)
  p.cast = nil
  p.gcd_ready = run.t
  p.next_auto = run.t + 0.5
  p.bleed_until = 0
  p.bleed_next = HUGE
  p.seal_hits = 0
  p.has_frost_armor = (p.class == "mage")
  p.imp_alive = false
  p.want_melee = false -- Stab-Phase (#86) endet mit dem Tod
  p.loh_used = false -- Handauflegung: einmal PRO LEBEN (Runde 13, #155)
  p.shield_hp = 0 -- Machtwort haftet nicht am neuen Leben (Runde 13, #156)
  p.weak_soul_until = 0
  p.add_idx = nil
  -- Adds fangen fruehe Ankommende ab (1v1), solange welche leben
  for ai = 1, #run.adds do
    if run.adds[ai].hp > 0 and run.adds[ai].engaged_by == nil then
      run.adds[ai].engaged_by = p.id
      p.add_idx = ai
      break
    end
  end
  log_ev(run, run.t, "revive", p.id, p.class, 0, nil)
end
E.spawn_player = spawn_player

-- ---------------------------------------------------------------------------
-- Schaden & Heilung
-- ---------------------------------------------------------------------------
local function crit_roll(run, side, kind)
  if not run.cfg.crits then return false end
  if not model.can_crit(kind) then return false end
  local chance = (side == "player") and model.p("crit_chance_player")
                                     or model.p("crit_chance_hogger")
  return run.rng:roll(chance)
end

function E.player_damage_hogger(run, p, amount, kind)
  local h = run.hogger
  if h.hp <= 0 then return end
  -- Streuungsmodell (GDD 17.2 Punkt 5b): Skill-Faktor wirkt auf verursachten Schaden
  amount = amount * p.skill
  local crit = crit_roll(run, "player", kind)
  if crit then amount = amount * model.p("crit_mult_player") end
  if p.shout_until > run.t then amount = amount * (1 + model.p("warrior_shout_bonus")) end
  h.hp = h.hp - amount
  p.dmg_done = p.dmg_done + amount
  -- Kein-Kontakt-Uhr (Runde 10, #124): jeder Treffer haelt Hogger im Kampf
  run.engaged = true
  run.no_contact_t = 0
  local tf = p.is_leeroy and model.p("leeroy_threat_factor") or 1
  p.threat = p.threat + model.threat_for(amount, false) * tf
  run.c.dmg_to_hogger = run.c.dmg_to_hogger + amount
  -- Schaden unterbricht das Fressen NICHT mehr (Runde 12, #140): nur der
  -- Schurken-Tritt — den modelliert der koordinierte Agent (agents.lua)
  log_ev(run, run.t, "damage", p.id, "hogger", amount, crit)
  -- Wut fuer ausgeteilte Autohits
  if model.classes[p.class].resource == "rage" and kind == "autohit" then
    p.resource = math.min(resource_max(p), p.resource + model.p("rage_per_hit_dealt"))
  end
end

function E.kill_player(run, p)
  p.alive = false
  p.state = "dead"
  p.hp = 0
  p.threat = 0  -- Bedrohung wird beim Tod geloescht (GDD 9.4)
  p.cast = nil
  p.deaths = p.deaths + 1
  p.imp_alive = false
  if p.add_idx and run.adds[p.add_idx] then run.adds[p.add_idx].engaged_by = nil end
  p.add_idx = nil
  -- Todesstrafe = N-skalierender Respawn-Timer (GDD 9.3) + Laufweg (Geist + Anmarsch)
  p.dead_until = run.t + model.respawn_timer(run.cfg.n) + run.cfg.walk
  -- Leiche als Fress-Ressource an der Sterbeposition
  run.corpses[#run.corpses + 1] = { d = p.d }
  run.c.deaths = run.c.deaths + 1
  if run.hogger.target == p then run.hogger.target = nil end
  log_ev(run, run.t, "death", p.id, nil, nil, nil)
end

function E.hogger_damage_player(run, p, amount, kind)
  if not p.alive then return end
  local crit = crit_roll(run, "hogger", kind)
  if crit then
    amount = amount * model.p("crit_mult_hogger")
    run.c.crit_kills = run.c.crit_kills + (amount >= p.hp and 1 or 0)
  end
  -- Machtwort: Schild (Runde 13, #156): der Schild frisst zuerst
  if (p.shield_hp or 0) > 0 and run.t < (p.shield_until or 0) then
    local a = math.min(amount, p.shield_hp)
    p.shield_hp = p.shield_hp - a
    amount = amount - a
  end
  p.hp = p.hp - amount
  run.c.dmg_to_players = run.c.dmg_to_players + amount
  -- Wut nur je erlittenem AUTOHIT (GDD 8.1), nicht fuer Charge/Slice/DoT
  if kind == "autohit" and model.classes[p.class].resource == "rage" then
    p.resource = math.min(resource_max(p), p.resource + model.p("rage_per_hit_taken"))
  end
  -- Frostruestung: Treffer auf den Magier verlangsamt Hogger (GDD 8.2)
  if p.has_frost_armor then
    run.hogger.slow_until = run.t + model.p("mage_frostarmor_slow_duration")
  end
  log_ev(run, run.t, "damage", "hogger", p.id, amount, crit)
  if p.hp <= 0 then E.kill_player(run, p) end
end

-- Effektive Maximal-HP (Runde 13, #159): der Blutpakt hebt den Deckel,
-- solange der Spieler in der Wichtel-Aura steht — dieselbe Formel wie
-- step.effective_max_hp
local function eff_max(p)
  if p.pact then
    return p.max_hp * (1 + model.p("warlock_pact_hp_pct"))
  end
  return p.max_hp
end
E.eff_max = eff_max

function E.heal_player(run, src, dst, amount, kind)
  if not dst.alive then return end
  local crit = crit_roll(run, "player", kind or "heal")
  if crit then amount = amount * model.p("crit_mult_player") end
  local effective = math.min(amount, eff_max(dst) - dst.hp)
  dst.hp = dst.hp + effective
  src.heal_done = src.heal_done + effective
  local tf = src.is_leeroy and model.p("leeroy_threat_factor") or 1
  src.threat = src.threat + model.threat_for(effective, true) * tf
  run.c.healing = run.c.healing + effective
  log_ev(run, run.t, "heal", src.id, dst.id, effective, crit)
end

-- ---------------------------------------------------------------------------
-- Faehigkeiten: Kosten/GCD/Casts. Agenten rufen nur cast_ability.
-- ---------------------------------------------------------------------------
local function res_cost(p, cost)
  if p.resource < cost then return false end
  p.resource = p.resource - cost
  return true
end

local INSTANT = {
  heroic_strike = function(run, p)
    if not res_cost(p, model.p("warrior_heroic_rage")) then return false end
    E.player_damage_hogger(run, p, model.p("warrior_heroic_dmg"), "ability")
    return true
  end,
  battle_shout = function(run, p)
    if not res_cost(p, model.p("warrior_shout_rage")) then return false end
    for _, q in ipairs(run.players) do
      if q.alive then q.shout_until = run.t + model.p("warrior_shout_duration") end
    end
    return true
  end,
  seal_of_righteousness = function(run, p)
    if not res_cost(p, model.p("paladin_seal_mana")) then return false end
    p.seal_hits = model.p("paladin_seal_hits")
    p.last_cast_t = run.t
    return true
  end,
  -- Handauflegung (Runde 13, #155): heilt das Ziel VOLL, kostet ALLES
  -- Mana, einmal pro Leben — dieselben Regeln wie in step.lua
  lay_on_hands = function(run, p, target)
    if model.p("paladin_loh_enabled") < 1 or p.loh_used then return false end
    local t = target or p
    E.heal_player(run, p, t, eff_max(t), "heal") -- voll = inkl. Blutpakt
    p.resource = 0
    p.loh_used = true
    return true
  end,
  -- Machtwort: Schild (Runde 13, #156): dieselben Regeln wie in step.lua
  power_word_shield = function(run, p, target)
    if model.p("priest_pws_enabled") < 1 then return false end
    local t = target or p
    if run.t < (t.weak_soul_until or 0) then return false end
    if not res_cost(p, model.p("priest_pws_mana")) then return false end
    p.last_cast_t = run.t
    t.shield_hp = model.p("priest_pws_absorb")
    t.shield_until = run.t + model.p("priest_pws_duration")
    t.weak_soul_until = run.t + model.p("priest_pws_weaksoul")
    return true
  end,
  raptor_strike = function(run, p)
    if run.t < p.raptor_ready then return false end
    p.raptor_ready = run.t + model.p("hunter_raptor_cd")
    E.player_damage_hogger(run, p, model.p("hunter_raptor_dmg"), "ability")
    return true
  end,
  -- Totstellen (Runde 13, #157): loescht die eigene Bedrohung; die
  -- Liegezeit kostet den naechsten Autoschuss
  feign_death = function(run, p)
    if model.p("hunter_feign_enabled") < 1 then return false end
    if run.t < (p.feign_ready or 0) then return false end
    p.feign_ready = run.t + model.p("hunter_feign_cd")
    p.threat = 0
    if run.hogger.target == p then run.hogger.target = nil end
    p.next_auto = math.max(p.next_auto,
      run.t + model.p("hunter_feign_duration"))
    return true
  end,
  sinister_strike = function(run, p)
    if not res_cost(p, model.p("rogue_sinister_energy")) then return false end
    E.player_damage_hogger(run, p, model.p("rogue_sinister_dmg"), "ability")
    p.cp = math.min(5, p.cp + 1)
    return true
  end,
  eviscerate = function(run, p)
    if p.cp < 1 then return false end
    if not res_cost(p, model.p("rogue_evis_energy")) then return false end
    E.player_damage_hogger(run, p, model.p("rogue_evis_dmg_per_cp") * p.cp, "ability")
    p.cp = 0
    return true
  end,
}

-- Casts: {dauer, mana, wirkung(run, p, ziel)}
local CASTS = {
  holy_light = { cast = "paladin_holylight_cast", mana = "paladin_holylight_mana",
    effect = function(run, p, target)
      E.heal_player(run, p, target or p, model.p("paladin_holylight_heal"), "heal")
    end },
  smite = { cast = "priest_smite_cast", mana = "priest_smite_mana",
    effect = function(run, p) E.player_damage_hogger(run, p, model.p("priest_smite_dmg"), "ability") end },
  lesser_heal = { cast = "priest_heal_cast", mana = "priest_heal_mana",
    effect = function(run, p, target)
      E.heal_player(run, p, target or p, model.p("priest_heal_amount"), "heal")
    end },
  fireball = { cast = "mage_fireball_cast", mana = "mage_fireball_mana",
    effect = function(run, p) E.player_damage_hogger(run, p, model.p("mage_fireball_dmg"), "ability") end },
  shadow_bolt = { cast = "warlock_bolt_cast", mana = "warlock_bolt_mana",
    effect = function(run, p) E.player_damage_hogger(run, p, model.p("warlock_bolt_dmg"), "ability") end },
  summon_imp = { cast = "warlock_imp_cast", mana = "warlock_imp_mana",
    effect = function(run, p)
      p.imp_alive = true
      p.imp_next = run.t + model.p("imp_interval")
    end },
  wrath = { cast = "druid_wrath_cast", mana = "druid_wrath_mana",
    effect = function(run, p) E.player_damage_hogger(run, p, model.p("druid_wrath_dmg"), "ability") end },
  healing_touch = { cast = "druid_touch_cast", mana = "druid_touch_mana",
    effect = function(run, p, target)
      E.heal_player(run, p, target or p, model.p("druid_touch_heal"), "heal")
    end },
}
E.CASTS = CASTS

-- true, wenn die Faehigkeit gestartet wurde
function E.cast_ability(run, p, id, target)
  if run.t < p.gcd_ready or p.cast then return false end
  local inst = INSTANT[id]
  if inst then
    if inst(run, p, target) then
      p.gcd_ready = run.t + model.p("gcd")
      return true
    end
    return false
  end
  local c = CASTS[id]
  assert(c, "unbekannte Faehigkeit: " .. tostring(id))
  if p.resource < model.p(c.mana) then return false end
  p.cast = { id = id, ends_at = run.t + model.p(c.cast), target = target }
  p.gcd_ready = run.t + model.p("gcd")
  return true
end

-- ---------------------------------------------------------------------------
-- Fressen
-- ---------------------------------------------------------------------------
function E.interrupt_eat(run, involved)
  local h = run.hogger
  if not h.eating then return end
  h.eating = nil
  h.eat_ready = run.t + model.p("eat_cd")
  run.c.eat_interrupted = run.c.eat_interrupted + 1
  log_ev(run, run.t, "eat_interrupt", "hogger", nil, involved, nil)
end

local function hogger_try_eat(run)
  local h = run.hogger
  if h.eating or run.t < h.eat_ready then return false end
  if h.hp >= model.p("eat_hp_threshold") * h.max_hp then return false end
  local radius = model.p("eat_corpse_radius")
  for i = 1, #run.corpses do
    if run.corpses[i].d <= radius then
      table.remove(run.corpses, i)
      -- hitters/dmg_accum sind weg (Runde 12, #140): nur der Tritt
      -- unterbricht, der Kanal braucht keine Buchhaltung
      h.eating = { phase = "drag", ends_at = run.t + model.p("eat_drag_duration") }
      run.c.eat_channels = run.c.eat_channels + 1
      log_ev(run, run.t, "eat_start", "hogger", nil, nil, nil)
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Hogger-Tick
-- ---------------------------------------------------------------------------
-- Hogger bewegt sich auf der 1D-Achse: alle Relativdistanzen (Spieler UND
-- Leichen) verschieben sich um den Schritt — so landet er nach einem Charge
-- mitten in der Fernkampf-Reihe, genau wie im echten Spiel.
local function hogger_relocate(run, step)
  for _, q in ipairs(run.players) do
    if q.alive then q.d = math.abs(q.d - step) end
  end
  for _, c in ipairs(run.corpses) do
    c.d = math.abs(c.d - step)
  end
end

local function pick_hogger_target(run)
  local h = run.hogger
  local best_melee, best_melee_threat = nil, 0
  local best_any, best_any_threat = nil, 0
  local melee_r = model.p("melee_range")
  for _, p in ipairs(run.players) do
    if p.alive and p.threat > 0 then
      if p.d <= melee_r and p.threat > best_melee_threat then
        best_melee, best_melee_threat = p, p.threat
      end
      if p.threat > best_any_threat then
        best_any, best_any_threat = p, p.threat
      end
    end
  end
  h.target = best_melee or best_any
  return h.target, best_melee ~= nil
end

local function hogger_tick(run, dt)
  local h = run.hogger
  if h.hp <= 0 then return end

  -- Fress-Zustandsmaschine
  if h.eating then
    local e = h.eating
    if e.phase == "drag" and run.t >= e.ends_at then
      e.phase = "channel"
      e.ends_at = run.t + model.p("eat_channel_duration")
      log_ev(run, run.t, "eat_tick", "hogger", nil, 0, nil)
    elseif e.phase == "channel" then
      local heal = model.eat_heal_per_second(run.cfg.n) * dt
      h.hp = math.min(h.max_hp, h.hp + heal)
      run.c.eat_healing = run.c.eat_healing + heal
      if run.t >= e.ends_at then
        h.eating = nil
        h.eat_ready = run.t + model.p("eat_cd")
        run.c.eat_completed = run.c.eat_completed + 1
        log_ev(run, run.t, "eat_complete", "hogger", nil, nil, nil)
      end
    end
    return -- waehrend Schleppen/Fressen keine Angriffe
  end

  local target, in_melee = pick_hogger_target(run)
  if not target then
    hogger_try_eat(run)
    return
  end

  -- Charge: weitestes Ziel mit Bedrohung in Hoggers Revier (GDD 9.2);
  -- p.d ist die Distanz zu Hogger — genau so misst das Spiel seit Runde 10
  local charge_cd = model.p("hogger_charge_cd")
  if run.t >= h.charge_ready then
    local far, far_d = nil, 0
    for _, p in ipairs(run.players) do
      if p.alive and p.threat > 0 and p.d <= model.p("hogger_zone_radius") and p.d > far_d then
        far, far_d = p, p.d
      end
    end
    if far then
      h.charge_ready = run.t + charge_cd
      run.c.charges = run.c.charges + 1
      local avoided = run.agent.avoid_charge and run.agent.avoid_charge(run, far)
      if far.cast then far.cast = nil end
      -- Hogger stuermt ZUM Ziel und bleibt dort — die bisherige Front ist
      -- jetzt fern, die Fernkaempfer um ihn herum sind die neue Nahzone.
      local travel = far.d
      hogger_relocate(run, travel)
      far.d = model.p("hogger_charge_knockback")
      if not avoided then
        E.hogger_damage_player(run, far, model.p("hogger_charge_dmg"), "charge")
      end
      h.next_auto = math.max(h.next_auto, run.t + model.p("hogger_charge_windup"))
      log_ev(run, run.t, "charge", "hogger", far.id, nil, nil)
      return
    end
  end

  -- Fressen hat Prioritaet vor dem Verfolgen, nicht vor dem Nahkampf
  if not in_melee then
    if hogger_try_eat(run) then return end
    -- Ziel verfolgen: Hogger bewegt sich, alle Distanzen verschieben sich
    local speed = model.p("hogger_speed")
    if h.slow_until > run.t then speed = speed * (1 - model.p("mage_frostarmor_slow")) end
    local step = math.min(speed * dt, math.max(0, target.d - model.p("melee_range")))
    hogger_relocate(run, step)
    return
  end

  -- Vicious Slice (GDD 9.2), kein Krit
  if run.t >= h.slice_ready then
    h.slice_ready = run.t + model.p("hogger_slice_cd")
    E.hogger_damage_player(run, target, model.p("hogger_slice_dmg"), "slice")
    if target.alive then
      target.bleed_until = run.t + model.p("hogger_slice_duration")
      target.bleed_next = run.t + model.p("hogger_slice_bleed_interval")
    end
    return
  end

  -- Autohit
  if run.t >= h.next_auto then
    h.next_auto = run.t + model.p("hogger_autohit_interval")
    E.hogger_damage_player(run, target, model.p("hogger_autohit_dmg"), "autohit")
    -- Rundumschlag (GDD 9.2, v2.6): der Autohit trifft zusaetzlich bis zu
    -- ceil(N/Divisor)-1 weitere Ziele mit Bedrohung im Nahkampf.
    local extra = model.cleave_targets(run.cfg.n) - 1
    if extra > 0 then
      local melee_r = model.p("melee_range")
      for _, q in ipairs(run.players) do
        if extra <= 0 then break end
        if q.alive and q ~= target and q.threat > 0 and q.d <= melee_r then
          E.hogger_damage_player(run, q, model.p("hogger_autohit_dmg"), "autohit")
          extra = extra - 1
        end
      end
    end
  end

  hogger_try_eat(run)
end

-- ---------------------------------------------------------------------------
-- Spieler-Tick (Mechanik; Entscheidungen liegen in agents.lua)
-- ---------------------------------------------------------------------------
local function player_tick(run, p, dt)
  if not p.alive then
    if p.state == "dead" and run.t >= p.dead_until then
      spawn_player(run, p)
    end
    return
  end

  p.combat_time = p.combat_time + dt

  -- Blutung (DoT, kein Krit)
  if p.bleed_until > run.t and run.t >= p.bleed_next then
    p.bleed_next = p.bleed_next + model.p("hogger_slice_bleed_interval")
    E.hogger_damage_player(run, p, model.p("hogger_slice_bleed_dmg"), "dot")
    if not p.alive then return end
  end

  -- Ressourcen-Regeneration
  local res = model.classes[p.class].resource
  if res == "mana" then
    if run.t - p.last_cast_t >= model.p("five_sec_rule_wait") then
      p.resource = math.min(resource_max(p), p.resource + model.p("mana_regen_rate") * dt)
    end
  elseif res == "energy" then
    p.resource = math.min(resource_max(p), p.resource + model.p("energy_regen_rate") * dt)
  end

  -- Add-Duell blockiert Boss-Beitrag (1v1 beim Anmarsch)
  if p.add_idx then
    local add = run.adds[p.add_idx]
    if not add or add.hp <= 0 then
      if add then add.engaged_by = nil end
      p.add_idx = nil
    else
      if run.t >= p.next_auto then
        p.next_auto = run.t + model.p("autohit_interval")
        local dmg = (model.classes[p.class].attack == "shot")
          and model.p("autoshot_dmg") or model.p("autohit_melee_dmg")
        add.hp = add.hp - dmg
        if add.hp <= 0 then
          add.engaged_by = nil
          p.add_idx = nil
          run.c.add_deaths = run.c.add_deaths + 1
          log_ev(run, run.t, "add_death", p.id, nil, nil, nil)
        end
      end
      if run.t >= add.next_auto then
        add.next_auto = run.t + model.p("add_attack_interval")
        p.hp = p.hp - model.p("add_dmg")
        if p.hp <= 0 then E.kill_player(run, p) end
      end
      return
    end
  end

  -- Bewegung auf Wunschreichweite (Agent darf abweichen, z. B. Turtle)
  local want = run.agent.desired_range and run.agent.desired_range(run, p)
               or desired_range(p)
  if p.d > want then
    p.d = math.max(want, p.d - model.p("move_speed_alive") * dt)
    if p.d > want then return end -- noch unterwegs
  elseif p.d < want - 1 and CASTER_NUKE_COST[p.class] then
    -- NUR die OOM-Caster-Pendelei (#86): wieder Mana -> zurueck auf
    -- Zauberreichweite. Alle anderen bleiben stehen, wo sie sind —
    -- insbesondere Jaeger schiessen aus jeder Distanz <= Wunschabstand
    -- weiter, statt nach jeder Hogger-Bewegung nachzuruecken.
    p.d = math.min(want, p.d + model.p("move_speed_alive") * dt)
    if p.d < want then return end -- noch unterwegs
  end

  -- Cast abschliessen
  if p.cast and run.t >= p.cast.ends_at then
    local c = CASTS[p.cast.id]
    local target = p.cast.target
    p.cast = nil
    if res_cost(p, model.p(c.mana)) then
      p.last_cast_t = run.t
      c.effect(run, p, target)
      if not p.alive then return end
    end
  end

  -- Agent entscheidet (Faehigkeiten, Heilziele) — nicht in der Stab-Phase:
  -- dort wird gepruegelt und regeneriert (FSR), nicht gecastet (#86)
  if not p.want_melee then
    run.agent.act(run, p)
    if not p.alive then return end
  end

  -- Autohit / Autoschuss (Agent darf unterdruecken, z. B. Turtle). Die
  -- Sim-Agenten schalten ihre Autoattack per Definition an (im Spiel seit
  -- Runde 12, #145: Rechtsklick — auch fuer den Autoschuss). Der Jaeger
  -- schiesst hier BEWUSST weiter aus jeder Distanz, obwohl das Spiel in
  -- Nahkampf-Reichweite auf den 2-Schaden-Autohit wechselt: der Schuss aus
  -- der Nahzone ist der Proxy fuer "tritt in 0,3 s heraus und schiesst
  -- weiter" (140 px/s gegen 20 px Weg). Beide 1D-Alternativen wurden
  -- gemessen und verworfen (17.9): dauerhaft steckenbleiben halbiert die
  -- Jaeger-DPS (F1 N=40 auf 59 %), echtes Heraustreten zerruettet die
  -- Relokations-Geometrie (F1 auf 94-100 %, F2 auf 39 %).
  if not p.cast and run.t >= p.next_auto
     and not (run.agent.no_auto and run.agent.no_auto(run, p)) then
    local attack = model.classes[p.class].attack
    if attack == "shot" then
      p.next_auto = run.t + model.p("autohit_interval")
      E.player_damage_hogger(run, p, model.p("autoshot_dmg"), "autohit")
    elseif p.d <= model.p("melee_range") then
      -- Nahkampf nur im Nahkampf: ein Caster auf Zauberreichweite
      -- schlaegt nicht aus 200 px zu (seit #86 gibt es keinen Stab mehr)
      p.next_auto = run.t + model.p("autohit_interval")
      local dmg = model.p("autohit_melee_dmg")
      if p.seal_hits > 0 then
        dmg = dmg + model.p("paladin_seal_bonus_dmg")
        p.seal_hits = p.seal_hits - 1
      end
      E.player_damage_hogger(run, p, dmg, "autohit")
    end
  end

  -- Wichtel-Beitrag (GDD 8.2: 2 Schaden / 2 s solange er lebt)
  if p.imp_alive and run.t >= (p.imp_next or 0) then
    p.imp_next = run.t + model.p("imp_interval")
    E.player_damage_hogger(run, p, model.p("imp_dmg"), "ability")
  end
end

-- ---------------------------------------------------------------------------
-- Lauf
-- ---------------------------------------------------------------------------
-- cfg: { n, walk (Laufweg-Anteil der Todesstrafe in s; Gesamtstrafe =
--        respawn_timer(n) + walk), crits, agent = "unkoordiniert" |
--        "koordiniert" | "turtle", seed, log=false }
function E.run_try(cfg)
  local agents = require("sim.agents")
  local run = {
    cfg = cfg,
    rng = rngmod.new(cfg.seed),
    t = 0,
    events = {},
    corpses = {},
    players = {},
    adds = {},
    c = { deaths = 0, dmg_to_hogger = 0, dmg_to_players = 0, healing = 0,
          crit_kills = 0, eat_channels = 0, eat_interrupted = 0,
          eat_completed = 0, eat_healing = 0, charges = 0, add_deaths = 0,
          resets = 0 },
  }
  run.agent = agents.make(cfg.agent, run)

  run.hogger = {
    hp = model.hogger_hp(cfg.n), max_hp = model.hogger_hp(cfg.n),
    next_auto = 0, slice_ready = 0,
    charge_ready = model.p("hogger_charge_cd"),
    eat_ready = 0, eating = nil, target = nil, slow_until = 0,
  }

  for i = 1, model.adds(cfg.n) do
    run.adds[i] = { hp = model.p("add_hp"), engaged_by = nil, next_auto = 0 }
  end

  for i = 1, cfg.n do
    local class = run.agent.initial_class(run, i)
    run.players[i] = make_player(run, "p" .. i, class, false)
  end
  -- Leeroy: zusaetzlicher Paladin (Runde 12, #138), immer unkoordiniert,
  -- zaehlt nicht in N (GDD 17.2)
  run.players[cfg.n + 1] = make_player(run, "leeroy", "paladin", true)

  -- Streuungsmodell (GDD 17.2 Punkt 5b): Gruppenfaktor je Lauf x Skill je Agent
  local gmin, gmax = model.p("sim_group_factor_min"), model.p("sim_group_factor_max")
  local smin, smax = model.p("sim_skill_min"), model.p("sim_skill_max")
  local group_factor = gmin + (gmax - gmin) * run.rng:next()
  for _, p in ipairs(run.players) do
    p.skill = group_factor * (smin + (smax - smin) * run.rng:next())
  end

  log_ev(run, 0, "try_start", "sim", tostring(cfg.seed), cfg.n, nil)

  -- Try-Start: gestaffelter Anmarsch (Leeroy voran, GDD 10)
  for i, p in ipairs(run.players) do
    p.state = "dead"
    p.dead_until = p.is_leeroy and 0 or (10 + (i % 5) * 0.8)
  end

  local dt = model.SIM_TICK_DT
  local limit = model.p("try_time_limit")
  local melee_r = model.p("melee_range")
  local frist = model.p("hogger_no_contact_reset")
  run.engaged, run.no_contact_t = false, 0
  -- EIN Puffer fuer die Wichtel-Distanzen statt einer neuen Tabelle je Tick
  -- (Runde 14, #175 — bis zu 9000 Allokationen pro Lauf, Verhalten gleich)
  local imp_ds, imp_n, pact_any = {}, 0, false
  while run.t < limit do
    run.t = run.t + dt
    -- Blutpakt (Runde 13, #159) im 1D-Modell: der Wichtel steht beim
    -- Besitzer, die Aura gilt fuer |d - d_besitzer| <= Radius. Beim
    -- Verlassen (oder Abschalten) klemmt der Deckel die Bonus-HP.
    do
      imp_n = 0
      if model.p("warlock_pact_enabled") >= 1 then
        for _, o in ipairs(run.players) do
          if o.alive and o.imp_alive then
            imp_n = imp_n + 1
            imp_ds[imp_n] = o.d
          end
        end
      end
      -- Lebt kein Wichtel und traegt niemand die Aura, ist die ganze
      -- Schleife ein Leerlauf — dann uebersprungen (Runde 14, #175)
      if imp_n > 0 or pact_any then
        local pr = model.p("warlock_pact_radius")
        pact_any = false
        for _, q in ipairs(run.players) do
          local inside = false
          if q.alive then
            for i = 1, imp_n do
              if math.abs(q.d - imp_ds[i]) <= pr then
                inside = true
                break
              end
            end
          end
          if q.pact and not inside and q.alive then
            q.hp = math.min(q.hp, q.max_hp)
          end
          q.pact = inside
          if inside then pact_any = true end
        end
      end
    end
    if run.agent.tick then run.agent.tick(run) end
    for _, p in ipairs(run.players) do
      player_tick(run, p, dt)
    end
    hogger_tick(run, dt)
    if run.hogger.hp <= 0 then break end
    -- Kein-Kontakt-Uhr (Runde 10, #124) — dieselbe Regel wie im Spiel: ab dem
    -- ersten Treffer laeuft sie und wird von jedem Treffer sowie von jedem
    -- lebenden Spieler in Schlagweite auf 0 gestellt. Laeuft sie ab, trabt
    -- Hogger heim und heilt voll: der Try ist verloren. Im 1D-Modell trifft
    -- das praktisch nur den totalen Wipe (Todesstrafe 24 s gegen Frist 30 s).
    if run.engaged then
      local contact = false
      for _, p in ipairs(run.players) do
        if p.alive and p.d <= melee_r then contact = true break end
      end
      if contact then
        run.no_contact_t = 0
      else
        run.no_contact_t = run.no_contact_t + dt
        if run.no_contact_t >= frist then
          run.c.resets = run.c.resets + 1
          break
        end
      end
    end
  end

  local win = run.hogger.hp <= 0
  log_ev(run, run.t, "try_end", "sim", string.format("%.17g", math.max(0, run.hogger.hp)),
         win and 1 or 0, nil)

  -- Uptime: Anteil Kampfzeit lebender Spieler an N x Trydauer (GDD 13.1)
  local combat_sum = 0
  for i = 1, cfg.n do combat_sum = combat_sum + run.players[i].combat_time end

  local class_counts = {}
  for i = 1, cfg.n do
    local cl = run.players[i].class
    class_counts[cl] = (class_counts[cl] or 0) + 1
  end

  return {
    win = win,
    duration = run.t,
    rest_hp_pct = math.max(0, run.hogger.hp) / run.hogger.max_hp,
    uptime = combat_sum / (cfg.n * run.t),
    c = run.c,
    class_counts = class_counts,
    log_hash = cfg.log and hashmod.djb2(table.concat(run.events, "\n")) or nil,
    events = cfg.log and run.events or nil,
  }
end

return E
