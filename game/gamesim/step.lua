-- game/gamesim/step.lua — DER Spielschritt: step(state, inputs) -> events.
-- Einzige Stelle, die Spielzustand aendert (ADR-002, Skill Par. 2).
-- Reines Lua, fixer Schritt 1/60 s; alle Zahlen aus sim/model.lua.
-- inputs: pid -> { mask = 0..255, facing = 0..255 }

local model = require("sim.model")
local input = require("game.gamesim.input")
local world = require("game.gamesim.world")
local map = require("game.data.map")
local events = require("game.gamesim.events")

local S = {}
local DT = model.TICK_DT
local ICON_RADIUS = 60      -- Draufstellen-Radius der Klassenicons (GDD 5)
-- Leeroys letzte Zeilen nach dem Fluchbruch (GDD 11): Zeit -> Zeilen-ID
local WON_LINES = { { 1.0, 31 }, { 4.5, 32 }, { 9.0, 33 } }

-- ---------------------------------------------------------------------------
-- Kampfhelfer
-- ---------------------------------------------------------------------------
local function crit_roll(state, side, kind)
  if not model.can_crit(kind) then return false end
  local chance = (side == "player") and model.p("crit_chance_player")
                                     or model.p("crit_chance_hogger")
  return state.rng:roll(chance)
end

local CAUSE = require("game.gamesim.killcam").CAUSE

-- Statistik-Tafel (GDD 11): Zaehler je Try; Spieler-Eintrag lazy angelegt
local function stat_p(state, pid)
  local s = state.stats
  if not s then return nil end
  local e = s.players[pid]
  if not e then
    e = { dmg = 0, deaths = 0, ghost_t = 0, eaten = 0, heal_aggro = 0,
          interrupts = 0, mob_kills = 0 }
    s.players[pid] = e
  end
  return e
end

-- Unterbrechung fuer die Statistik verbuchen (Hogger + beteiligte Spieler);
-- reine Zaehler, Reihenfolge der hitters-Menge ist ergebnisneutral
local function note_interrupt(state, eating)
  local s = state.stats
  if not s then return end
  s.hogger.interrupts = s.hogger.interrupts + 1
  for pid in pairs(eating.hitters) do
    local sp = stat_p(state, pid)
    sp.interrupts = sp.interrupts + 1
  end
end

-- cause: Todesursache fuer die Killcam (killcam.CAUSE, GDD Kap. 11)
local function kill_player(state, p, ev, was_crit, cause)
  p.alive = false
  p.ghost = false
  p.hp = 0
  p.cast = nil
  p.revive = nil
  p.stealth = false
  p.cp = 0
  p.seal_hits = 0
  p.frost_armor = false
  if p.imp_id and state.npcs[p.imp_id] then -- Wichtel stirbt mit dem Meister
    state.hogger.threat[p.imp_id] = nil
    state.npcs[p.imp_id] = nil
  end
  p.imp_id = nil
  p.deaths = p.deaths + 1
  p.dead_until = model.respawn_timer(math.max(1, state.n_scale))
  state.hogger.threat[p.id] = nil -- Bedrohung wird beim Tod geloescht (GDD 9.4)
  -- owner: "Am haeufigsten gefressen worden" braucht den Leichen-Besitzer
  state.corpses[#state.corpses + 1] = { x = p.x, y = p.y, owner = p.id }
  local s = state.stats
  if s then
    local sp = stat_p(state, p.id)
    sp.deaths = sp.deaths + 1
    if not s.first_death then s.first_death = p.id end
    if cause and cause <= 4 then -- Hogger-Ursachen (Autohit/Charge/Slice/DoT)
      s.hogger.kills = s.hogger.kills + 1
      if was_crit then s.hogger.crit_kills = s.hogger.crit_kills + 1 end
    end
    if cause == CAUSE.boar then s.boar_victim = p.name end
    if state.time - (p.last_heal_t or -1000) < 5 then
      sp.heal_aggro = sp.heal_aggro + 1 -- Heal-Aggro-Tod (GDD 11 / 9.4)
    end
  end
  events.push(ev, state.tick, "death", p.id, nil, cause, was_crit or nil)
  if was_crit then
    events.push(ev, state.tick, "crit_kill", "hogger", p.id, nil, true)
  end
end

local function hogger_damage_player(state, p, amount, kind, ev)
  if not p.alive then return end
  local crit = crit_roll(state, "hogger", kind)
  if crit then amount = amount * model.p("crit_mult_hogger") end
  p.hp = p.hp - amount
  if state.stats then
    state.stats.hogger.dmg = state.stats.hogger.dmg + amount
  end
  if kind == "autohit" and p.class == "warrior" then
    p.resource = math.min(model.p("rage_max"), p.resource + model.p("rage_per_hit_taken"))
  end
  -- Frostruestung: Treffer auf den Magier verlangsamt Hogger (GDD 8.2)
  if p.frost_armor and kind == "autohit" then
    state.hogger.slow_until = state.time + model.p("mage_frostarmor_slow_duration")
  end
  events.push(ev, state.tick, "damage", "hogger", p.id, amount, crit)
  if p.hp <= 0 then kill_player(state, p, ev, crit, CAUSE[kind]) end
end

local function player_damage_hogger(state, p, amount, kind, ev)
  local h = state.hogger
  if h.hp <= 0 or h.state == "reset" then return end
  local crit = crit_roll(state, "player", kind)
  if crit then amount = amount * model.p("crit_mult_player") end
  if p.shout_until > state.time then
    amount = amount * (1 + model.p("warrior_shout_bonus"))
  end
  h.hp = h.hp - amount
  p.dmg_done = p.dmg_done + amount
  local sp = stat_p(state, p.id)
  if sp then sp.dmg = sp.dmg + amount end
  local tf = p.is_leeroy and model.p("leeroy_threat_factor") or 1 -- GDD 10.3
  h.threat[p.id] = (h.threat[p.id] or 0) + model.threat_for(amount, false) * tf
  if h.state == "idle" then h.state = "combat" end
  -- Fress-Unterbrechung (GDD 9.2): verschiedene Spieler ODER Schadensschwelle
  if h.eating and h.eating.phase == "channel" then
    local e = h.eating
    if not e.hitters[p.id] then
      e.hitters[p.id] = true
      e.hitter_count = e.hitter_count + 1
    end
    e.dmg_accum = e.dmg_accum + amount
    if e.hitter_count >= model.eat_interrupters(state.n_scale)
       or e.dmg_accum >= model.eat_dmg_threshold(state.n_scale) then
      h.eating = nil
      h.eat_cd = model.p("eat_cd")
      note_interrupt(state, e)
      events.push(ev, state.tick, "eat_interrupt", "hogger", nil, e.hitter_count, nil)
    end
  end
  events.push(ev, state.tick, "damage", p.id, "hogger", amount, crit)
  if kind == "autohit" and p.class == "warrior" then
    p.resource = math.min(model.p("rage_max"), p.resource + model.p("rage_per_hit_dealt"))
  end
end

local function heal_player(state, src, dst, amount, ev)
  if not dst.alive then return end
  local crit = crit_roll(state, "player", "heal")
  if crit then amount = amount * model.p("crit_mult_player") end
  local effective = math.min(amount, dst.max_hp - dst.hp)
  dst.hp = dst.hp + effective
  src.heal_done = src.heal_done + effective
  src.last_heal_t = state.time -- fuer den Heal-Aggro-Kommentar (GDD 10.4)
  local h = state.hogger
  if h.state == "combat" or h.state == "eating" then
    h.threat[src.id] = (h.threat[src.id] or 0) + model.threat_for(effective, true)
  end
  events.push(ev, state.tick, "heal", src.id, dst.id, effective, crit)
end

-- ---------------------------------------------------------------------------
-- Feind-Aufloesung: Ziel ist Hogger ODER ein feindlicher NPC (Mob/Add)
-- ---------------------------------------------------------------------------
local MOB_TYPES = { boar = true, wolf = true, kobold = true, murloc = true }
local loot_pool = require("game.gamesim.loot")

local function current_enemy(state, p)
  if p.target == world.HOGGER_ID then
    local h = state.hogger
    if h.hp > 0 and h.state ~= "reset" then return h, "hogger" end
    return nil
  end
  local npc = state.npcs[p.target]
  if npc and npc.kind ~= "imp" then return npc, "npc" end
  return nil
end

local function give_xp(state, p, ev)
  p.xp = p.xp + model.p("xp_per_mob")
  events.push(ev, state.tick, "xp_gain", p.id, nil, model.p("xp_per_mob"), nil)
  if not p.ding_done and p.xp >= model.p("xp_level2") then
    p.ding_done = true -- DING: mechanischer Effekt exakt null (GDD 7.3)
    events.push(ev, state.tick, "ding", p.id, nil, p.xp, nil)
  end
end

local function mob_died(state, npc, killer, ev)
  if npc.kind == "add" then
    events.push(ev, state.tick, "add_death", npc.id, nil, nil, nil)
  elseif MOB_TYPES[npc.kind] then
    events.push(ev, state.tick, "mob_kill", killer.id, npc.kind, nil, nil)
    local sp = stat_p(state, killer.id)
    if sp then sp.mob_kills = sp.mob_kills + 1 end
    give_xp(state, killer, ev)
    -- Loot-Roll: sanktionierter Zufall (GDD 13.2), fester Kupferwert je Typ
    local item_idx = state.rng:range(1, #loot_pool)
    world.add_loot(state, npc.x, npc.y, model.mobs[npc.kind].kupfer, item_idx)
    if npc.slot then
      state.mob_by_slot[npc.slot] = nil
      state.mob_respawn[npc.slot] = model.p("mob_respawn")
    end
  end
  state.hogger.threat[npc.id] = nil
  state.npcs[npc.id] = nil
end

-- ---------------------------------------------------------------------------
-- Faehigkeiten (GDD 8.2) als Daten: je Klasse bis zu 3 Slots (Tasten 1-3)
-- ---------------------------------------------------------------------------
local function enemy_in_range(state, p, range)
  local enemy = current_enemy(state, p)
  return enemy ~= nil and world.dist(p.x, p.y, enemy.x, enemy.y) <= range
end

local function player_damage_npc(state, p, npc, amount, kind, ev)
  local crit = false
  if kind == "autohit" or kind == "ability" then
    crit = crit_roll(state, "player", MOB_TYPES[npc.kind] and "mob" or "add")
  end
  if crit then amount = amount * model.p("crit_mult_player") end
  npc.hp = npc.hp - amount
  p.dmg_done = p.dmg_done + amount
  local sp = stat_p(state, p.id)
  if sp then sp.dmg = sp.dmg + amount end
  if p.stealth then p.stealth = false end
  if MOB_TYPES[npc.kind] and npc.state ~= "flee" then
    npc.state = "combat"
    npc.target_pid = p.id
  elseif npc.kind == "add" then
    npc.state = "combat"
    npc.target_pid = npc.target_pid or p.id
  end
  events.push(ev, state.tick, "damage", p.id, npc.id, amount, crit)
  if npc.hp <= 0 then mob_died(state, npc, p, ev) end
end

-- Schaden auf das aktuelle Ziel des Spielers (Hogger oder NPC)
local function player_damage_enemy(state, p, amount, kind, ev)
  local enemy, etype = current_enemy(state, p)
  if not enemy then return end
  if etype == "hogger" then
    player_damage_hogger(state, p, amount, kind, ev)
  else
    player_damage_npc(state, p, enemy, amount, kind, ev)
  end
end

local function set_stealth(state, p, on)
  p.stealth = on
end

local function dmg_fx(param)
  return function(state, p, _, ev)
    player_damage_enemy(state, p, model.p(param), "ability", ev)
  end
end

local function heal_fx(param)
  return function(state, p, target, ev)
    heal_player(state, p, target or p, model.p(param), ev)
  end
end

-- spec: cost (Param-Schluessel, Klassenressource), cast (Castzeit-Param),
-- range (Param) + target "enemy"|"ally"|"self", cd_field/cd (Cooldown),
-- requires_cp, effect(state, p, target, ev)
local ABILITIES = {
  warrior = {
    { id = "heroic", cost = "warrior_heroic_rage", range = "melee_range",
      target = "enemy", effect = dmg_fx("warrior_heroic_dmg") },
    { id = "shout", cost = "warrior_shout_rage", target = "self",
      effect = function(state, p)
        local r = model.p("warrior_shout_radius")
        for _, q in ipairs(state.players) do
          if q.alive and world.dist(p.x, p.y, q.x, q.y) <= r then
            q.shout_until = state.time + model.p("warrior_shout_duration")
          end
        end
      end },
  },
  paladin = {
    { id = "holylight", cost = "paladin_holylight_mana",
      cast = "paladin_holylight_cast", target = "ally",
      effect = heal_fx("paladin_holylight_heal") },
    { id = "seal", cost = "paladin_seal_mana", target = "self",
      effect = function(_, p) p.seal_hits = model.p("paladin_seal_hits") end },
  },
  hunter = {
    { id = "raptor", cd_field = "raptor_cd", cd = "hunter_raptor_cd",
      range = "melee_range", target = "enemy",
      effect = dmg_fx("hunter_raptor_dmg") },
  },
  rogue = {
    { id = "sinister", cost = "rogue_sinister_energy", range = "melee_range",
      target = "enemy",
      effect = function(state, p, _, ev)
        player_damage_enemy(state, p, model.p("rogue_sinister_dmg"), "ability", ev)
        p.cp = math.min(5, p.cp + 1)
      end },
    { id = "evis", cost = "rogue_evis_energy", range = "melee_range",
      target = "enemy", requires_cp = true,
      effect = function(state, p, _, ev)
        player_damage_enemy(state, p,
          model.p("rogue_evis_dmg_per_cp") * p.cp, "ability", ev)
        p.cp = 0
      end },
    { id = "stealth", target = "self",
      effect = function(state, p) set_stealth(state, p, not p.stealth) end },
  },
  priest = {
    { id = "smite", cost = "priest_smite_mana", cast = "priest_smite_cast",
      range = "wand_range", target = "enemy", effect = dmg_fx("priest_smite_dmg") },
    { id = "heal", cost = "priest_heal_mana", cast = "priest_heal_cast",
      target = "ally", effect = heal_fx("priest_heal_amount") },
  },
  mage = {
    { id = "fireball", cost = "mage_fireball_mana", cast = "mage_fireball_cast",
      range = "wand_range", target = "enemy", effect = dmg_fx("mage_fireball_dmg") },
    { id = "frostarmor", target = "self",
      effect = function(_, p) p.frost_armor = true end },
  },
  warlock = {
    { id = "bolt", cost = "warlock_bolt_mana", cast = "warlock_bolt_cast",
      range = "wand_range", target = "enemy", effect = dmg_fx("warlock_bolt_dmg") },
    { id = "imp", cost = "warlock_imp_mana", cast = "warlock_imp_cast",
      target = "self",
      effect = function(state, p)
        if p.imp_id and state.npcs[p.imp_id] then return end
        local npc = world.add_npc(state, "imp", p.x + 20, p.y + 20,
          model.p("imp_hp"), p.id)
        p.imp_id = npc.id
        -- "zieht kurz Aggro" (GDD 8.2): kleiner Startimpuls auf der Threat-Liste
        state.hogger.threat[npc.id] = 5
      end },
  },
  druid = {
    { id = "wrath", cost = "druid_wrath_mana", cast = "druid_wrath_cast",
      range = "wand_range", target = "enemy", effect = dmg_fx("druid_wrath_dmg") },
    { id = "touch", cost = "druid_touch_mana", cast = "druid_touch_cast",
      target = "ally", effect = heal_fx("druid_touch_heal") },
  },
}
S.ABILITIES = ABILITIES -- fuer Renderer (Buttons) und Bots

local function is_mana_class(p)
  return model.classes[p.class].resource == "mana"
end

local function spend(state, p, cost)
  p.resource = p.resource - cost
  if cost > 0 and is_mana_class(p) then
    p.last_cast_t = state.time -- Fuenf-Sekunden-Regel (GDD 8.1)
  end
end

local function ally_target(state, p)
  local t = state.players[p.target]
  if t and t.alive then return t end
  return p
end

local function try_ability(state, p, slot, ev)
  if p.gcd > 0 or p.cast then return end
  local spec = ABILITIES[p.class] and ABILITIES[p.class][slot]
  if not spec then return end
  if spec.cd_field and p[spec.cd_field] > 0 then return end
  if spec.requires_cp and p.cp < 1 then return end
  local cost = spec.cost and model.p(spec.cost) or 0
  if p.resource < cost then return end
  if spec.target == "enemy" and spec.range
     and not enemy_in_range(state, p, model.p(spec.range)) then return end
  if p.stealth and spec.id ~= "stealth" then
    set_stealth(state, p, false) -- bricht beim Angriff (GDD 8.2)
  end
  if spec.cast then
    p.cast = { slot = slot, t_left = model.p(spec.cast),
               total = model.p(spec.cast),
               target = spec.target == "ally" and ally_target(state, p).id or nil }
    p.gcd = model.p("gcd")
    return
  end
  spend(state, p, cost)
  if spec.cd_field then p[spec.cd_field] = model.p(spec.cd) end
  spec.effect(state, p, spec.target == "ally" and ally_target(state, p) or nil, ev)
  p.gcd = model.p("gcd")
end

local function finish_cast(state, p, ev)
  local c = p.cast
  p.cast = nil
  local spec = ABILITIES[p.class] and ABILITIES[p.class][c.slot]
  if not spec then return end
  local cost = spec.cost and model.p(spec.cost) or 0
  if p.resource < cost then return end
  if spec.target == "enemy" and spec.range
     and not enemy_in_range(state, p, model.p(spec.range)) then return end
  local target
  if spec.target == "ally" then
    target = c.target and state.players[c.target] or nil
    if not (target and target.alive) then target = p end
  end
  spend(state, p, cost)
  spec.effect(state, p, target, ev)
end

-- ---------------------------------------------------------------------------
-- Spieler-Tick
-- ---------------------------------------------------------------------------
local function player_tick(state, p, inp, ev)
  local mask = (inp and input.valid(inp.mask)) and inp.mask or 0
  if inp and inp.facing then p.facing = inp.facing % 256 end

  -- tot: auf Respawn warten, dann als Geist am Friedhof erscheinen
  if not p.alive and not p.ghost then
    p.dead_until = p.dead_until - DT
    if p.dead_until <= 0 then
      local g = map.graveyard()
      p.ghost = true
      p.x, p.y = g.x, g.y
      events.push(ev, state.tick, "spawn", p.id, nil, nil, nil)
    end
    p.prev_mask = mask
    return
  end

  local dx, dy = input.move_vec(mask)
  local moving = dx ~= 0 or dy ~= 0

  -- Springen: reines Feel-Feature (GDD 4.1), Host zaehlt
  if input.pressed(mask, p.prev_mask, input.JUMP) and p.jump_t <= 0 then
    p.jump_t = 0.4
    p.jumps = p.jumps + 1
  end
  if p.jump_t > 0 then p.jump_t = p.jump_t - DT end

  if p.ghost then
    local spg = stat_p(state, p.id) -- "Meiste Zeit als Geist" (GDD 11)
    if spg then spg.ghost_t = spg.ghost_t + DT end
    local speed = model.p("move_speed_ghost")
    p.x, p.y = map.clamp(p.x + dx * speed * DT, p.y + dy * speed * DT)
    -- Wiederbelebung: auf Klassenicon stehen, 2-s-Channel (GDD 5)
    if moving then p.revive = nil end
    if not p.revive then
      for slot = 1, #world.CLASSES do
        local ix, iy = world.class_icon_pos(slot)
        if world.dist(p.x, p.y, ix, iy) <= ICON_RADIUS then
          p.revive = { slot = slot, t_left = model.p("revive_channel") }
          break
        end
      end
    else
      p.revive.t_left = p.revive.t_left - DT
      if p.revive.t_left <= 0 then
        local class = world.CLASSES[p.revive.slot]
        if p.class ~= class then
          events.push(ev, state.tick, "class_change", p.id, class, nil, nil)
        end
        p.class = class
        -- Rasse je Wiederbelebung regelkonform ausgewuerfelt (GDD 5), kosmetisch;
        -- Leeroy ist fluchbedingt immer Mensch-Krieger (GDD 10.3)
        p.race = p.is_leeroy and "mensch" or model.roll_race(class, state.rng:next())
        local race_idx = 1
        for i, r in ipairs(model.RACES) do
          if r == p.race then race_idx = i end
        end
        p.max_hp = model.hp_for_class(class)
        p.hp = p.max_hp
        local res = model.classes[class].resource
        p.resource = (res == "rage") and 0
                     or (res == "energy") and model.p("energy_max")
                     or model.p("mana_max")
        p.cp = 0
        p.stealth = false
        p.seal_hits = 0
        p.frost_armor = false
        p.alive = true
        p.ghost = false
        p.revive = nil
        p.last_cast_t = -1000
        p.next_auto = 0
        p.shout_until = 0
        p.bleed_t = 0
        events.push(ev, state.tick, "revive", p.id, class, race_idx, nil)
      end
    end
    p.prev_mask = mask
    return
  end

  -- lebend --------------------------------------------------------------
  local speed = model.p("move_speed_alive")
  if p.stealth then speed = speed * model.p("rogue_stealth_speed") end
  if moving then
    p.x, p.y = map.clamp(p.x + dx * speed * DT, p.y + dy * speed * DT)
    if p.cast then p.cast = nil end -- Bewegung bricht den Cast
  end

  -- Blutung (Vicious Slice, kein Krit)
  if p.bleed_t > 0 then
    p.bleed_t = p.bleed_t - DT
    p.bleed_next = p.bleed_next - DT
    if p.bleed_next <= 0 then
      p.bleed_next = p.bleed_next + model.p("hogger_slice_bleed_interval")
      hogger_damage_player(state, p, model.p("hogger_slice_bleed_dmg"), "dot", ev)
      if not p.alive then p.prev_mask = mask return end
    end
  end

  -- Ressourcen (GDD 8.1): Mana mit Fuenf-Sekunden-Regel, Energie 10/s
  local res_type = model.classes[p.class].resource
  if res_type == "mana" then
    if state.time - p.last_cast_t >= model.p("five_sec_rule_wait") then
      p.resource = math.min(model.p("mana_max"),
        p.resource + model.p("mana_regen_rate") * DT)
    end
  elseif res_type == "energy" then
    p.resource = math.min(model.p("energy_max"),
      p.resource + model.p("energy_regen_rate") * DT)
  end

  if p.gcd > 0 then p.gcd = p.gcd - DT end
  if p.raptor_cd > 0 then p.raptor_cd = p.raptor_cd - DT end

  -- Cast abschliessen
  if p.cast then
    p.cast.t_left = p.cast.t_left - DT
    if p.cast.t_left <= 0 then finish_cast(state, p, ev) end
  end

  -- Faehigkeiten per Flanke (ADR-002)
  if input.pressed(mask, p.prev_mask, input.AB1) then try_ability(state, p, 1, ev) end
  if input.pressed(mask, p.prev_mask, input.AB2) then try_ability(state, p, 2, ev) end
  if input.pressed(mask, p.prev_mask, input.AB3) then try_ability(state, p, 3, ev) end

  -- Autohit / Autoschuss / Zauberstab (GDD 8.1); nicht aus Verstohlenheit
  p.next_auto = p.next_auto - DT
  if p.next_auto <= 0 and not p.cast and not p.stealth then
    local attack = model.classes[p.class].attack
    local range, dmg
    if attack == "shot" then
      range, dmg = model.p("autoshot_range"), model.p("autoshot_dmg")
    elseif attack == "wand" then
      range, dmg = model.p("wand_range"), model.p("wand_dmg")
    else
      range, dmg = model.p("melee_range"), model.p("autohit_melee_dmg")
      if p.seal_hits > 0 then -- Siegel der Rechtschaffenheit (GDD 8.2)
        dmg = dmg + model.p("paladin_seal_bonus_dmg")
      end
    end
    if enemy_in_range(state, p, range) then
      p.next_auto = model.p("autohit_interval")
      if attack ~= "shot" and attack ~= "wand" and p.seal_hits > 0 then
        p.seal_hits = p.seal_hits - 1
      end
      player_damage_enemy(state, p, dmg, "autohit", ev)
    end
  end

  p.prev_mask = mask
end

-- ---------------------------------------------------------------------------
-- NPC-Tick (M3: Wichtel; spaeter Mobs/Adds)
-- ---------------------------------------------------------------------------
local function remove_npc(state, npc)
  state.hogger.threat[npc.id] = nil
  local owner = state.players[npc.owner or 0]
  if owner and owner.imp_id == npc.id then owner.imp_id = nil end
  state.npcs[npc.id] = nil
end

-- Mob/Add greift einen Spieler an; Mobs kritten mit Standard-5 % (GDD 7.2),
-- Adds nie (GDD 9.2)
local function npc_damage_player(state, npc, p, ev)
  local dmg = MOB_TYPES[npc.kind] and model.p(npc.kind .. "_dmg")
                                    or model.p("add_dmg")
  local kind = MOB_TYPES[npc.kind] and "mob" or "add"
  local crit = crit_roll(state, "hogger", kind)
  if crit then dmg = dmg * model.p("crit_mult_hogger") end
  p.hp = p.hp - dmg
  events.push(ev, state.tick, "damage", npc.id, p.id, dmg, crit)
  if p.hp <= 0 then
    kill_player(state, p, ev, crit, CAUSE[npc.kind])
    if MOB_TYPES[npc.kind] then
      -- die Pflicht-Anekdote (GDD 7.2)
      events.push(ev, state.tick, "mob_death_by", p.id, npc.kind, nil, nil)
    end
  end
end

local function mob_tick(state, npc, ev)
  local typ = npc.kind
  local speed = model.p("move_speed_alive")
  local function move_towards(tx, ty)
    local d = world.dist(npc.x, npc.y, tx, ty)
    if d < 2 then return end
    local step_len = math.min(speed * DT, d)
    npc.x = npc.x + (tx - npc.x) / d * step_len
    npc.y = npc.y + (ty - npc.y) / d * step_len
  end

  -- Leash an den Spawn (GDD 7.2)
  if npc.state ~= "leash"
     and world.dist(npc.x, npc.y, npc.spawn_x, npc.spawn_y) > 450 then
    npc.state = "leash"
    npc.target_pid = nil
    npc.hp = npc.max_hp
  end

  if npc.state == "leash" then
    move_towards(npc.spawn_x, npc.spawn_y)
    if world.dist(npc.x, npc.y, npc.spawn_x, npc.spawn_y) < 8 then
      npc.state = "idle"
      npc.hp = npc.max_hp
    end
    return
  end

  -- Wildschwein flieht bei 25 % HP (GDD 7.2)
  if typ == "boar" and npc.state == "combat"
     and npc.hp <= model.p("boar_flee_hp_pct") * npc.max_hp then
    npc.state = "flee"
  end
  if npc.state == "flee" then
    local from = state.players[npc.target_pid]
    if from then
      local dx, dy = npc.x - from.x, npc.y - from.y
      local d = math.max(1, math.sqrt(dx * dx + dy * dy))
      npc.x = npc.x + dx / d * speed * DT
      npc.y = npc.y + dy / d * speed * DT
      npc.x, npc.y = map.clamp(npc.x, npc.y)
    end
    return -- bis der Leash greift
  end

  if npc.state == "idle" then
    -- aggressive Typen: Wolf/Murloc ab Naehe (GDD 7.2)
    if typ == "wolf" or typ == "murloc" then
      for _, p in ipairs(state.players) do
        if p.alive and not p.stealth
           and world.dist(p.x, p.y, npc.x, npc.y) <= model.p("wolf_aggro_radius") then
          npc.state = "combat"
          npc.target_pid = p.id
          break
        end
      end
    end
    return
  end

  -- Kampf
  local target = state.players[npc.target_pid]
  if not (target and target.alive) then
    npc.state = "leash"
    return
  end
  local d = world.dist(npc.x, npc.y, target.x, target.y)
  if d > model.p("melee_range") then
    move_towards(target.x, target.y)
    return
  end
  npc.next_auto = npc.next_auto - DT
  if npc.next_auto <= 0 then
    npc.next_auto = model.p("mob_attack_interval")
    npc_damage_player(state, npc, target, ev)
  end
end

local function add_tick(state, npc, ev)
  if npc.state == "idle" then
    for _, p in ipairs(state.players) do
      if p.alive and not p.stealth
         and world.dist(p.x, p.y, npc.x, npc.y) <= 150 then
        npc.state = "combat"
        npc.target_pid = p.id
        break
      end
    end
    return
  end
  local target = state.players[npc.target_pid]
  if not (target and target.alive) then
    npc.state = "idle"
    npc.target_pid = nil
    return
  end
  if world.dist(npc.x, npc.y, npc.spawn_x, npc.spawn_y) > 400 then
    npc.state = "idle" -- Welpen bleiben am Huegelfuss (GDD 9.2)
    npc.target_pid = nil
    return
  end
  local d = world.dist(npc.x, npc.y, target.x, target.y)
  if d > model.p("melee_range") then
    local step_len = math.min(model.p("move_speed_alive") * DT, d)
    npc.x = npc.x + (target.x - npc.x) / d * step_len
    npc.y = npc.y + (target.y - npc.y) / d * step_len
    return
  end
  npc.next_auto = npc.next_auto - DT
  if npc.next_auto <= 0 then
    npc.next_auto = model.p("add_attack_interval")
    npc_damage_player(state, npc, target, ev)
  end
end

local function npc_tick(state, npc, ev)
  if MOB_TYPES[npc.kind] then return mob_tick(state, npc, ev) end
  if npc.kind == "add" then return add_tick(state, npc, ev) end
  if npc.kind ~= "imp" then return end
  local owner = state.players[npc.owner]
  if not owner or not owner.alive then
    remove_npc(state, npc)
    return
  end
  -- folgt dem Meister
  local d = world.dist(npc.x, npc.y, owner.x, owner.y)
  if d > 80 then
    local step_len = math.min(model.p("move_speed_alive") * DT, d)
    npc.x = npc.x + (owner.x - npc.x) / d * step_len
    npc.y = npc.y + (owner.y - npc.y) / d * step_len
  end
  -- Feuerblitz (GDD 8.2)
  npc.next_auto = npc.next_auto - DT
  local h = state.hogger
  if npc.next_auto <= 0 and h.hp > 0 and h.state ~= "reset"
     and world.dist(npc.x, npc.y, h.x, h.y) <= model.p("wand_range") then
    npc.next_auto = model.p("imp_interval")
    local dmg = model.p("imp_dmg")
    h.hp = h.hp - dmg
    local sp = stat_p(state, owner.id) -- Wichtel-Schaden zaehlt dem Meister
    if sp then sp.dmg = sp.dmg + dmg end
    h.threat[npc.id] = (h.threat[npc.id] or 0) + dmg
    if h.state == "idle" then h.state = "combat" end
    -- Fress-Schwelle: Schaden zaehlt, der Wichtel ist aber kein
    -- "verschiedener Spieler" (GDD 9.2)
    if h.eating and h.eating.phase == "channel" then
      local e = h.eating
      e.dmg_accum = e.dmg_accum + dmg
      if e.dmg_accum >= model.eat_dmg_threshold(state.n_scale) then
        h.eating = nil
        h.eat_cd = model.p("eat_cd")
        note_interrupt(state, e)
        events.push(ev, state.tick, "eat_interrupt", "hogger", nil, e.hitter_count, nil)
      end
    end
    events.push(ev, state.tick, "damage", npc.id, "hogger", dmg, nil)
  end
end

-- deterministische NPC-Reihenfolge: numerische IDs, nie pairs()
local function each_npc(state, fn)
  for id = world.NPC_ID_BASE, 250 do
    local npc = state.npcs[id]
    if npc then fn(npc) end
  end
end

-- ---------------------------------------------------------------------------
-- Hogger-Tick (GDD 9, v2.6 inkl. Cleave)
-- ---------------------------------------------------------------------------
-- Ziel: hoechste Bedrohung im Nahkampf, sonst hoechste gesamt (GDD 9.4);
-- Verstohlene ignoriert er (GDD 8.2); Wichtel sind gueltige Ziele
local function pick_hogger_target(state)
  local h = state.hogger
  local melee_r = model.p("melee_range")
  local best_melee, bm_threat, best_any, ba_threat = nil, -1, nil, -1
  local function consider(e)
    local th = h.threat[e.id]
    if th and th > 0 then
      local d = world.dist(e.x, e.y, h.x, h.y)
      if d <= melee_r and th > bm_threat then best_melee, bm_threat = e, th end
      if th > ba_threat then best_any, ba_threat = e, th end
    end
  end
  for _, p in ipairs(state.players) do
    if p.alive and not p.stealth then consider(p) end
  end
  each_npc(state, consider)
  return best_melee or best_any, best_melee ~= nil
end

local function hogger_damage_npc(state, npc, amount, ev)
  npc.hp = npc.hp - amount
  events.push(ev, state.tick, "damage", "hogger", npc.id, amount, nil)
  if npc.hp <= 0 then
    events.push(ev, state.tick, "add_death", npc.id, nil, nil, nil)
    remove_npc(state, npc)
  end
end

local function hogger_move_towards(state, tx, ty, speed)
  local h = state.hogger
  local d = world.dist(h.x, h.y, tx, ty)
  if d < 1 then return end
  local step = math.min(speed * DT, d)
  local nx = h.x + (tx - h.x) / d * step
  local ny = h.y + (ty - h.y) / d * step
  if not map.in_graveyard(nx, ny) then -- unantastbare Zone (GDD 7.1)
    h.x, h.y = nx, ny
  end
end

local function hogger_try_eat(state, ev)
  local h = state.hogger
  if h.eating or h.eat_cd > 0 then return false end
  if h.hp >= model.p("eat_hp_threshold") * h.max_hp then return false end
  local radius = model.p("eat_corpse_radius")
  for i, c in ipairs(state.corpses) do
    if world.dist(c.x, c.y, h.x, h.y) <= radius then
      h.eating = { phase = "drag", t_left = model.p("eat_drag_duration"),
                   corpse = i, hitters = {}, hitter_count = 0, dmg_accum = 0,
                   heal_tick = 1 }
      events.push(ev, state.tick, "eat_start", "hogger", nil, nil, nil)
      events.push(ev, state.tick, "eat_drag", "hogger", nil, nil, nil)
      return true
    end
  end
  return false
end

local function hogger_reset(state)
  local h = state.hogger
  h.state = "reset"
  h.hp = h.max_hp -- Full Heal beim Leash-Reset (GDD 9.1)
  h.threat = {}
  h.eating = nil
  h.charge = nil
  h.out_of_leash_t = 0
end

local function hogger_tick(state, ev)
  local h = state.hogger
  if h.hp <= 0 then return end

  if h.eat_cd > 0 then h.eat_cd = h.eat_cd - DT end
  if h.slice_cd > 0 then h.slice_cd = h.slice_cd - DT end
  if h.charge_cd > 0 then h.charge_cd = h.charge_cd - DT end
  h.next_auto = h.next_auto - DT

  -- Rueckweg nach Leash-Reset
  if h.state == "reset" then
    hogger_move_towards(state, map.hill.x, map.hill.y, model.p("hogger_speed"))
    if world.dist(h.x, h.y, map.hill.x, map.hill.y) < 10 then
      h.state = "idle"
    end
    return
  end

  -- Fressen
  if h.eating then
    local e = h.eating
    local c = state.corpses[e.corpse]
    if not c then
      h.eating = nil
    elseif e.phase == "drag" then
      -- Leiche heranziehen (schliesst Safe-Death-Exploit, GDD 9.2)
      c.x = h.x + (c.x - h.x) * (1 - DT / math.max(DT, e.t_left))
      c.y = h.y + (c.y - h.y) * (1 - DT / math.max(DT, e.t_left))
      e.t_left = e.t_left - DT
      if e.t_left <= 0 then
        e.phase = "channel"
        e.t_left = model.p("eat_channel_duration")
      end
      return
    else
      local before = h.hp
      h.hp = math.min(h.max_hp, h.hp + model.eat_heal_per_second(state.n_scale) * DT)
      if state.stats then
        state.stats.hogger.healed = state.stats.hogger.healed + (h.hp - before)
      end
      e.t_left = e.t_left - DT
      -- eat_tick je voller Sekunde Kanal (GDD 17.3)
      if model.p("eat_channel_duration") - e.t_left >= e.heal_tick then
        e.heal_tick = e.heal_tick + 1
        events.push(ev, state.tick, "eat_tick", "hogger", nil,
                    model.eat_heal_per_second(state.n_scale), nil)
      end
      if e.t_left <= 0 then
        if state.stats then
          state.stats.hogger.eaten = state.stats.hogger.eaten + 1
          if c.owner then -- "Am haeufigsten gefressen worden" (GDD 11)
            local sp = stat_p(state, c.owner)
            sp.eaten = sp.eaten + 1
          end
        end
        table.remove(state.corpses, e.corpse)
        h.eating = nil
        h.eat_cd = model.p("eat_cd")
        events.push(ev, state.tick, "eat_complete", "hogger", nil, nil, nil)
      end
      return
    end
  end

  -- Charge-Anlauf laeuft (Leash-Pruefung waehrenddessen ausgesetzt, GDD 9.1)
  if h.charge then
    h.charge.t_left = h.charge.t_left - DT
    local target = state.players[h.charge.target]
    if not target or not target.alive then
      h.charge = nil
    elseif h.charge.t_left <= 0 then
      local ox, oy = h.x, h.y
      h.x, h.y = target.x, target.y
      -- Knockback: vom Anlaufvektor weg (GDD 9.2), kein Krit
      local d = math.max(1, world.dist(ox, oy, target.x, target.y))
      local kx = (target.x - ox) / d * model.p("hogger_charge_knockback")
      local ky = (target.y - oy) / d * model.p("hogger_charge_knockback")
      target.x, target.y = map.clamp(target.x + kx, target.y + ky)
      if target.cast then target.cast = nil end
      if state.stats then
        state.stats.hogger.charges = state.stats.hogger.charges + 1
      end
      events.push(ev, state.tick, "charge", "hogger", target.id, nil, nil)
      hogger_damage_player(state, target, model.p("hogger_charge_dmg"), "charge", ev)
      h.charge = nil
      h.next_auto = math.max(h.next_auto, 0.5)
    end
    return
  end

  -- IDLE: Huegel-Patrouille, Aggro bei 250 px (GDD 9.1)
  if h.state == "idle" then
    local wp = map.patrol[h.patrol_i]
    hogger_move_towards(state, wp.x, wp.y, model.p("hogger_speed") * 0.5)
    if world.dist(h.x, h.y, wp.x, wp.y) < 12 then
      h.patrol_i = (h.patrol_i % #map.patrol) + 1
    end
    for _, p in ipairs(state.players) do
      if p.alive and world.dist(p.x, p.y, h.x, h.y) <= model.p("hogger_aggro_radius") then
        h.state = "combat"
        h.threat[p.id] = math.max(h.threat[p.id] or 0, 0.1)
        break
      end
    end
    if h.state == "idle" then
      hogger_try_eat(state, ev)
      return
    end
  end

  -- KAMPF ----------------------------------------------------------------
  -- Leash (Hysterese 2 s; GDD 9.1)
  if world.dist(h.x, h.y, map.hill.x, map.hill.y) > model.p("hogger_leash_radius") then
    h.out_of_leash_t = h.out_of_leash_t + DT
    if h.out_of_leash_t >= model.p("hogger_leash_hysteresis") then
      hogger_reset(state)
      return
    end
  else
    h.out_of_leash_t = 0
  end

  local target, in_melee = pick_hogger_target(state)
  if not target then
    if not hogger_try_eat(state, ev) then
      h.state = "idle"
    end
    return
  end

  -- Charge: weitestes Ziel mit Bedrohung innerhalb des Leash-Radius (GDD 9.2)
  if h.charge_cd <= 0 then
    local far, far_d = nil, 0
    for _, p in ipairs(state.players) do
      local th = h.threat[p.id]
      if p.alive and not p.stealth and th and th > 0
         and world.dist(p.x, p.y, map.hill.x, map.hill.y) <= model.p("hogger_leash_radius") then
        local d = world.dist(p.x, p.y, h.x, h.y)
        if d > far_d then far, far_d = p, d end
      end
    end
    if far then
      h.charge_cd = model.p("hogger_charge_cd")
      h.charge = { target = far.id, t_left = model.p("hogger_charge_windup") }
      return
    end
  end

  -- Verfolgen / Zuschlagen
  local d = world.dist(target.x, target.y, h.x, h.y)
  if d > model.p("melee_range") then
    local speed = model.p("hogger_speed")
    if h.slow_until > state.time then
      speed = speed * (1 - model.p("mage_frostarmor_slow"))
    end
    hogger_move_towards(state, target.x, target.y, speed)
    hogger_try_eat(state, ev)
    return
  end

  -- Vicious Slice (GDD 9.2) — nur auf Spieler, kein Krit
  if h.slice_cd <= 0 and not target.kind then
    h.slice_cd = model.p("hogger_slice_cd")
    hogger_damage_player(state, target, model.p("hogger_slice_dmg"), "slice", ev)
    if target.alive then
      target.bleed_t = model.p("hogger_slice_duration")
      target.bleed_next = model.p("hogger_slice_bleed_interval")
    end
    return
  end

  -- Autohit + Rundumschlag (v2.6)
  if h.next_auto <= 0 then
    h.next_auto = model.p("hogger_autohit_interval")
    if target.kind then
      hogger_damage_npc(state, target, model.p("hogger_autohit_dmg"), ev)
    else
      hogger_damage_player(state, target, model.p("hogger_autohit_dmg"), "autohit", ev)
    end
    local extra = model.cleave_targets(math.max(1, state.n_scale)) - 1
    if extra > 0 then
      -- deterministische Reihenfolge: nach Bedrohung, dann ID
      local cands = {}
      for _, q in ipairs(state.players) do
        if q.alive and not q.stealth and q ~= target
           and (h.threat[q.id] or 0) > 0
           and world.dist(q.x, q.y, h.x, h.y) <= model.p("melee_range") then
          cands[#cands + 1] = q
        end
      end
      each_npc(state, function(npc)
        if npc ~= target and (h.threat[npc.id] or 0) > 0
           and world.dist(npc.x, npc.y, h.x, h.y) <= model.p("melee_range") then
          cands[#cands + 1] = npc
        end
      end)
      table.sort(cands, function(a, b)
        local ta, tb = h.threat[a.id] or 0, h.threat[b.id] or 0
        if ta ~= tb then return ta > tb end
        return a.id < b.id
      end)
      for i = 1, math.min(extra, #cands) do
        if cands[i].kind then
          hogger_damage_npc(state, cands[i], model.p("hogger_autohit_dmg"), ev)
        else
          hogger_damage_player(state, cands[i], model.p("hogger_autohit_dmg"), "autohit", ev)
        end
      end
    end
  end

  hogger_try_eat(state, ev)
end

-- ---------------------------------------------------------------------------
-- Try-Struktur (GDD 6)
-- ---------------------------------------------------------------------------
local function end_try(state, ev, won)
  local e = events.push(ev, state.tick, "try_end", "host",
    string.format("%.17g", math.max(0, state.hogger.hp)), won and 1 or 0, nil)
  local jumps = {}
  for _, p in ipairs(state.players) do
    jumps[#jumps + 1] = { p.id, p.jumps }
  end
  e.jumps = jumps
  -- Statistik-Tafel (GDD 11): VOR begin_try bauen (das setzt die Zaehler
  -- zurueck); haengt als e.board am Event, wird nicht ins JSONL serialisiert
  if state.stats then
    local board = require("game.gamesim.statboard").build(state, won)
    for _, t in ipairs(board.title_awards) do
      state.players[t.pid].titel = t.title -- persistiert via session.json
    end
    if won then
      -- Zerfledderter Wams: 2 Kupfer, Zufalls-Roll — folgenloser RNG,
      -- ausdruecklich erlaubt (GDD 11/13.2); Leeroy wuerfelt nicht (Fluch)
      local cands = {}
      for _, p in ipairs(state.players) do
        if not p.is_leeroy and not p.disconnected then cands[#cands + 1] = p end
      end
      if #cands > 0 then
        local winner = cands[state.rng:range(1, #cands)]
        local roll = state.rng:range(1, 100)
        winner.kupfer = winner.kupfer + 2
        events.push(ev, state.tick, "loot_pickup", winner.id, 0, 2, nil)
        board.wams = winner.name .. " gewinnt den Wurf (" .. roll .. ")"
      end
    end
    e.board = board
  end
end

-- Neustart nach dem Fluchbruch: alle als Geist an den Friedhof
local function restart_all(state, ev)
  world.begin_try(state, ev)
  for _, p in ipairs(state.players) do
    p.alive = false
    p.ghost = true
    local g = map.graveyard()
    p.x, p.y = g.x, g.y
  end
end

-- REVANCHE (GDD 11): startet den naechsten Abend-Durchlauf, Try-Zaehler
-- bei 1 — der Fluch ist gebrochen, ab jetzt zergt man freiwillig
function S.revanche(state, ev)
  if state.phase ~= "won" then return false end
  state.phase = "try"
  state.try_nr = 0
  restart_all(state, ev)
  return true
end

-- ---------------------------------------------------------------------------
function S.step(state, inputs)
  local ev = {}
  state.tick = state.tick + 1
  state.time = state.tick * DT

  if state.phase == "won" then
    -- Fluchbruch (GDD 11): die Welt haelt an, bis REVANCHE gedrueckt wird;
    -- Leeroys letzte Zeilen kommen zeitversetzt
    local before = state.won_t
    state.won_t = state.won_t + DT
    for _, l in ipairs(WON_LINES) do
      if before < l[1] and state.won_t >= l[1] then
        events.push(ev, state.tick, "leeroy_line", "leeroy", l[2], nil, nil)
      end
    end
    return ev
  end

  state.clock = state.clock + DT

  -- Leeroys Eingabequelle ist Teil der Sim (GDD 10, ADR-002)
  if state.leeroy_pid then
    inputs[state.leeroy_pid] = require("game.gamesim.leeroy").decide(state, ev)
  end

  for _, p in ipairs(state.players) do
    player_tick(state, p, inputs[p.id], ev)
  end
  each_npc(state, function(npc) npc_tick(state, npc, ev) end)
  hogger_tick(state, ev)

  -- Mob-Respawn: 120 s am festen Punkt (GDD 7.2)
  local active_slots = model.mob_slots(math.max(1, state.n_scale))
  for slot = 1, #map.MOB_SPAWNS do
    local t = state.mob_respawn[slot]
    if t then
      t = t - DT
      if t <= 0 then
        state.mob_respawn[slot] = nil
        if slot <= active_slots then world.spawn_mob(state, slot) end
      else
        state.mob_respawn[slot] = t
      end
    end
  end

  -- Bodenbeute: Verfall + Aufheben, sofort Zaehler statt Inventar (GDD 7.3)
  for id = 1, 60 do
    local l = state.loot[id]
    if l then
      l.t = l.t - DT
      if l.t <= 0 then
        state.loot[id] = nil
      else
        for _, p in ipairs(state.players) do
          if p.alive and world.dist(p.x, p.y, l.x, l.y) <= 30 then
            p.kupfer = p.kupfer + l.kupfer
            p.plunder = p.plunder + 1
            events.push(ev, state.tick, "loot_pickup", p.id, l.item_idx, l.kupfer, nil)
            state.loot[id] = nil
            break
          end
        end
      end
    end
  end

  if state.hogger.hp <= 0 then
    end_try(state, ev, true)
    state.phase = "won"
    state.won_t = 0
  elseif state.clock >= model.p("try_time_limit") then
    end_try(state, ev, false)
    world.begin_try(state, ev)
  end

  -- Leeroy kommentiert die Ereignisse dieses Ticks (GDD 10.4)
  require("game.gamesim.announcer").process(state, ev)

  return ev
end

return S
