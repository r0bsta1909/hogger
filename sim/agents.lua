-- sim/agents.lua — Verhaltensmodelle der Headless-Sim (GDD 17.2).
-- "unkoordiniert": laeuft zum Boss, drueckt Faehigkeiten bei Verfuegbarkeit,
--   ignoriert Fressen/Charge, wechselt nie die Klasse.
-- "koordiniert": zusaetzlich Fress-Fokus (80 % je Kanal), Charge-Ausweichen
--   60 %, Konvergenz ab Minute 3 zur Zielkomposition.
-- "turtle": Heil-Maximierer als Anti-Stall-Beweis (GDD 17.2 Punkt 4).
-- Leeroy wird von der Engine als zusaetzlicher Paladin gefuehrt (Runde 12,
-- #138) und spielt immer unkoordiniert (Engine markiert ihn mit is_leeroy).

local model = require("sim.model")

local A = {}

-- ---------------------------------------------------------------------------
-- Gemeinsame Bausteine
-- ---------------------------------------------------------------------------
local function lowest_ally(run, below_pct, exclude_self, self_p)
  local best, best_pct = nil, below_pct
  for _, q in ipairs(run.players) do
    if q.alive and not (exclude_self and q == self_p) then
      local pct = q.hp / q.max_hp
      if pct < best_pct then best, best_pct = q, pct end
    end
  end
  return best
end

local function allies_alive(run)
  local k = 0
  for _, q in ipairs(run.players) do
    if q.alive then k = k + 1 end
  end
  return k
end

-- Klassenlogik "Faehigkeiten bei Verfuegbarkeit"; heal_others steuert, ob
-- Heiler auch Verbuendete heilen (koordiniert) oder nur sich selbst.
local function act_class(run, p, heal_others)
  local E = require("sim.engine")
  local class = p.class
  local hp_pct = p.hp / p.max_hp

  if class == "warrior" then
    if p.shout_until <= run.t and allies_alive(run) >= 3
       and p.resource >= model.p("warrior_shout_rage") then
      if E.cast_ability(run, p, "battle_shout") then return end
    end
    E.cast_ability(run, p, "heroic_strike")
  elseif class == "paladin" then
    local target = heal_others and lowest_ally(run, 0.7, false, p)
                   or (hp_pct < 0.5 and p or nil)
    if target and E.cast_ability(run, p, "holy_light", target) then return end
    if p.seal_hits == 0 then E.cast_ability(run, p, "seal_of_righteousness") end
  elseif class == "hunter" then
    if p.d <= model.p("melee_range") then E.cast_ability(run, p, "raptor_strike") end
  elseif class == "rogue" then
    if p.cp >= 5 then
      if E.cast_ability(run, p, "eviscerate") then return end
    end
    E.cast_ability(run, p, "sinister_strike")
  elseif class == "priest" then
    local target = heal_others and lowest_ally(run, 0.7, false, p)
                   or (hp_pct < 0.5 and p or nil)
    if target and E.cast_ability(run, p, "lesser_heal", target) then return end
    E.cast_ability(run, p, "smite")
  elseif class == "mage" then
    E.cast_ability(run, p, "fireball")
  elseif class == "warlock" then
    if not p.imp_alive then
      if E.cast_ability(run, p, "summon_imp") then return end
    end
    E.cast_ability(run, p, "shadow_bolt")
  elseif class == "druid" then
    local target = heal_others and lowest_ally(run, 0.7, false, p)
                   or (hp_pct < 0.5 and p or nil)
    if target and E.cast_ability(run, p, "healing_touch", target) then return end
    E.cast_ability(run, p, "wrath")
  end
end

local function uniform_class(run)
  return model.CLASS_IDS[run.rng:range(1, #model.CLASS_IDS)]
end

-- ---------------------------------------------------------------------------
-- Agenten
-- ---------------------------------------------------------------------------
function A.make(name, run)
  if name == "unkoordiniert" then
    return {
      initial_class = function(r) return uniform_class(r) end,
      act = function(r, p) act_class(r, p, false) end,
    }
  end

  if name == "koordiniert" then
    local agent = {}
    agent.initial_class = function(r) return uniform_class(r) end

    -- Zielkomposition (GDD 17.2): 50 % Jaeger; Heiler und Schurken skalieren
    -- mit N (max(2, N/8) bzw. max(2, N/10)) — die Startannahme "2/2" liess
    -- kleine Raids proportional mehr Support-Overhead tragen (F6-Schieflage)
    agent.choose_class = function(r, p)
      if p.is_leeroy or r.t < 180 then return nil end
      local want = {
        hunter = math.floor(0.5 * r.cfg.n + 0.5),
        priest = math.max(2, math.floor(r.cfg.n / 8 + 0.5)),
        rogue = math.max(2, math.floor(r.cfg.n / 10 + 0.5)),
      }
      local have = { hunter = 0, priest = 0, rogue = 0 }
      for i = 1, r.cfg.n do
        local cl = r.players[i].class
        if have[cl] and r.players[i] ~= p then have[cl] = have[cl] + 1 end
      end
      for _, role in ipairs({ "rogue", "priest", "hunter" }) do
        if have[role] < want[role] then return role end
      end
      local mixed = { "warrior", "paladin", "mage", "warlock", "druid" }
      return mixed[r.rng:range(1, #mixed)]
    end

    -- Fress-Fokus: 80 % Unterbrechungs-Erfolg je Kanal, frueh im Kanal
    agent.tick = function(r)
      local h = r.hogger
      local e = h.eating
      if e and e.phase == "channel" then
        if e.coord_roll == nil then
          e.coord_roll = r.rng:roll(0.8)
          e.coord_at = r.t + 1.5
        end
        if e.coord_roll and r.t >= e.coord_at then
          local E = require("sim.engine")
          E.interrupt_eat(r, model.eat_interrupters(r.cfg.n))
        end
      end
    end

    agent.avoid_charge = function(r, p)
      return r.rng:roll(0.6)
    end

    agent.act = function(r, p) act_class(r, p, true) end
    return agent
  end

  if name == "turtle" then
    -- Anti-Stall-Beweis: alle Heilerklassen, minimaler Schaden, optimale
    -- Fuenf-Sekunden-Regel (heilen nur, wenn noetig; nie angreifen).
    local HEALERS = { "priest", "paladin", "druid" }
    local agent = {}
    agent.initial_class = function(r, i) return HEALERS[1 + (i % #HEALERS)] end
    agent.desired_range = function(r, p)
      if p.is_leeroy then return nil end -- Leeroy kaempft normal im Nahkampf
      return model.p("cast_range")
    end
    agent.no_auto = function(r, p) return not p.is_leeroy end
    agent.act = function(r, p)
      if p.is_leeroy then return act_class(r, p, false) end
      local E = require("sim.engine")
      local target = lowest_ally(r, 0.85, false, p)
      if not target then return end -- Cast-Pause: Mana regeneriert (FSR)
      if p.class == "priest" then
        E.cast_ability(r, p, "lesser_heal", target)
      elseif p.class == "paladin" then
        E.cast_ability(r, p, "holy_light", target)
      elseif p.class == "druid" then
        E.cast_ability(r, p, "healing_touch", target)
      end
    end
    return agent
  end

  error("unbekannter Agent: " .. tostring(name))
end

return A
