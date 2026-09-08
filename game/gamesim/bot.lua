-- game/gamesim/bot.lua — Bot-Eingabequelle (ADR-002: eine Quelle pro Spieler,
-- austauschbar). Reines Lua; liefert je Tick eine Bitmaske wie die Tastatur.
-- Nutzer: Balancing-Sim (sim/gamerun.lua), Stufe-3/4-Tests, Debug-Bots.
--
-- Runde 20: die Bots sind der Referenz-Raid, gegen den balanciert wird
-- (GDD 17.2, Rob-Entscheid). Drei Profile:
--   typisch  — ein typischer LAN-Raid: haelt Reichweite statt nachzulaufen,
--              bricht keine eigenen Casts, nutzt alle drei Faehigkeiten
--              sinnvoll, ein Schurke haelt Energie fuer den Tritt zurueck,
--              Tritt mit 1-2 s Reaktion, Klasse nach Bedarf beim Wiederbeleben
--   kopflos  — der Bot bis Runde 19: Klasse fest, nur Faehigkeit 1/2,
--              laeuft nach und bricht Casts, tritt sofort (F2/F3-Gegenprobe)
--   turtle   — nur Heilerklassen, nur Heilung, kein Schaden (Anti-Stall-Gate)
-- Alles deterministisch: jeder Bot hat einen eigenen RNG-Strom aus Seed und
-- pid (der Spiel-Zufall state.rng bleibt unberuehrt), Iteration nur ipairs
-- bzw. feste ID-Bereiche. Die Charge weicht niemand aus: Hogger springt auf
-- die Zielposition, Ausweichen ist im Spiel nicht moeglich (GDD 9.2).

local input = require("game.gamesim.input")
local world = require("game.gamesim.world")
local model = require("sim.model")
local rngmod = require("sim.rng")

local M = {}

M.PROFILES = { "typisch", "kopflos", "turtle" }
M.DEFAULT_PROFILE = "typisch"

-- Entscheidungsraster (Runde 20): ein Mensch entscheidet nicht 60-mal je
-- Sekunde. Alle DECIDE_EVERY Ticks wird gerechnet, dazwischen wiederholt
-- der Bot seine Maske ohne die Faehigkeits-Bits (die sind Flanken).
M.DECIDE_EVERY = 3

local HEALER = { paladin = true, priest = true, druid = true }
local CASTER = { priest = true, mage = true, warlock = true, druid = true }
local RANGED = { hunter = true, mage = true, warlock = true, priest = true, druid = true }
local CLOTH = { priest = true, mage = true, warlock = true }

-- Heiler-Rolle (Runde 12, #143): 2/3 der Heilerklassen-Bots heilen aktiv
-- Verbuendete (deterministisch aus der pid, kein RNG-Kanal); 1/3 bleibt
-- reiner Schadensbot. Gilt fuer typisch und kopflos; turtle heilt immer.
function M.healer_duty(p)
  if p.profile == "turtle" then return HEALER[p.class or ""] or false end
  return (HEALER[p.class or ""] or false) and p.id % 3 ~= 0
end

-- Bestes Heilziel: niedrigster HP-Anteil unter den lebenden Spielern mit
-- <= frac HP in Heil-Reichweite (sich selbst eingeschlossen); ipairs haelt
-- die Wahl deterministisch
function M.heal_target(state, p, frac)
  frac = frac or 0.8
  local best, best_frac
  for _, q in ipairs(state.players) do
    if q.alive and (q.max_hp or 0) > 0 and q.hp <= frac * q.max_hp
       and world.dist(p.x, p.y, q.x, q.y) <= model.p("heal_range") then
      local f = q.hp / q.max_hp
      if best == nil or f < best_frac then best, best_frac = q, f end
    end
  end
  return best
end

local function move_mask_towards(px, py, tx, ty, slack)
  local mask = 0
  local dx, dy = tx - px, ty - py
  if math.abs(dx) > slack then
    mask = mask + (dx > 0 and input.RIGHT or input.LEFT)
  end
  if math.abs(dy) > slack then
    mask = mask + (dy > 0 and input.DOWN or input.UP)
  end
  return mask
end

-- ---------------------------------------------------------------------------
-- Gehirn: Gedaechtnis und eigener Zufallsstrom je Bot
-- ---------------------------------------------------------------------------
function M.new_brain(seed, pid, profile)
  local rng = rngmod.new((seed or 0) * 131 + pid * 7 + 1)
  return {
    profile = profile or M.DEFAULT_PROFILE,
    rng = rng,
    react = 1.0 + rng:next(),  -- Reaktionszeit 1-2 s (typischer Mensch)
    eat_seen_t = nil,          -- wann dieser Bot den Fresskanal bemerkt hat
    last_tick = -1,
    cached = nil,
  }
end

-- Das Gehirn haengt am Spieler (p.brain); ohne Seed im Zustand (Snapshot-
-- Sicht der Stufe-4-Clients) gibt es keines — dann spielt der Bot kopflos.
local function brain_of(state, p)
  if p.brain then return p.brain end
  if not state.seed then return nil end
  p.brain = M.new_brain(state.seed, p.id, p.profile or M.DEFAULT_PROFILE)
  return p.brain
end

-- Hoggers aktuelles Ziel: im Snapshot ein Feld, im Zustand die hoechste
-- Bedrohung unter den Lebenden (dieselbe Naeherung wie wire.lua)
local function hogger_target_pid(state)
  local h = state.hogger
  if h.target then return h.target end
  if not h.threat then return nil end
  local best, bid = 0, nil
  for _, q in ipairs(state.players) do
    local th = h.threat[q.id]
    if q.alive and th and th > best then best, bid = th, q.id end
  end
  return bid
end

local function eating_channel(h)
  local e = h.eating or h.eat
  return e ~= nil and e.phase == "channel"
end

local function casting(p)
  return p.cast ~= nil or p.casting == true
end

-- NPC, der diesen Spieler angreift und nahe genug ist, um sich zu wehren
local function attacker_npc(state, p, within)
  if not state.npcs then return nil end
  for id = world.NPC_ID_BASE, 250 do
    local npc = state.npcs[id]
    if npc and npc.target_pid == p.id and (npc.hp or 1) > 0
       and world.dist(p.x, p.y, npc.x, npc.y) <= within then
      return npc
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Bedarfsgesteuerte Klassenwahl (Runde 20, Rob-Entscheid): der Raid braucht
-- Schurken fuer den Tritt, Heiler und Fernkampf. Wer als Geist am Feld
-- ankommt, nimmt die Rolle, die am staerksten fehlt — sonst bleibt er, was
-- er war. Alle Geister entscheiden gleichzeitig; damit nicht alle dieselbe
-- Luecke fuellen, wird in pid-Reihenfolge "gezogen": jeder rechnet die
-- Wahl aller kleineren pids mit, als haetten sie schon gewaehlt.
-- ---------------------------------------------------------------------------
local ROLE_CLASSES = {
  rogue  = { "rogue" },
  healer = { "priest", "paladin", "druid" },
  ranged = { "hunter", "mage", "warlock" },
}

function M.role_targets(n)
  return {
    rogue  = math.max(2, math.ceil(n / 10)),
    healer = math.max(2, math.ceil(n / 6)),
    ranged = math.ceil(n / 3),
  }
end

local function role_of(class)
  if class == "rogue" then return "rogue" end
  if HEALER[class] then return "healer" end
  if RANGED[class] then return "ranged" end
  return nil
end

-- Klasse, die ein Bot bei dieser Rollenzaehlung waehlen wuerde.
-- counts: {rogue=, healer=, ranged=}, targets: role_targets(N)
local function pick_for_need(counts, targets, current, pid)
  local best, best_gap = nil, 0
  for _, role in ipairs({ "rogue", "healer", "ranged" }) do
    local gap = (targets[role] - counts[role]) / targets[role]
    if gap > best_gap then best, best_gap = role, gap end
  end
  if not best then
    return current or world.CLASSES[((pid - 1) % #world.CLASSES) + 1]
  end
  -- Bin ich schon in der fehlenden Rolle? Dann bleiben.
  if current and role_of(current) == best then return current end
  local list = ROLE_CLASSES[best]
  return list[((pid - 1) % #list) + 1]
end

function M.choose_class(state, p)
  local n, counts = 0, { rogue = 0, healer = 0, ranged = 0 }
  local undecided = {}
  for _, q in ipairs(state.players) do
    if not q.is_leeroy then
      n = n + 1
      local cls = q.class
      if q.revive and q.revive.slot then cls = world.CLASSES[q.revive.slot] end
      -- Geister ohne festen Weg (typisch) waehlen gleich mit; wer schon
      -- lebt oder im Kanal steht, zaehlt mit seiner Klasse
      local chosen = q.brain and q.brain.ghost_choice
      if q.ghost and not q.revive and chosen and q.id ~= p.id then
        -- Geist, der sich schon entschieden hat: zaehlt mit seiner Wahl
        local r = role_of(chosen)
        if r then counts[r] = counts[r] + 1 end
      elseif q.ghost and not q.revive and q.id <= p.id
             and (q.profile or M.DEFAULT_PROFILE) == "typisch" then
        undecided[#undecided + 1] = q
      else
        local r = role_of(cls)
        if r then counts[r] = counts[r] + 1 end
      end
    end
  end
  local targets = M.role_targets(math.max(1, n))
  local choice
  for _, q in ipairs(undecided) do -- pid-Reihenfolge (ipairs ueber players)
    local cls = pick_for_need(counts, targets, q.class, q.id)
    local r = role_of(cls)
    if r then counts[r] = counts[r] + 1 end
    if q.id == p.id then choice = cls end
  end
  return choice or p.class or world.CLASSES[((p.id - 1) % #world.CLASSES) + 1]
end

local function slot_of_class(cls)
  for i, c in ipairs(world.CLASSES) do
    if c == cls then return i end
  end
  return 1
end

-- ---------------------------------------------------------------------------
-- Profil "kopflos": der Bot bis Runde 19, unveraendert (F2/F3-Gegenprobe)
-- ---------------------------------------------------------------------------
local function decide_kopflos(state, p)
  local pid = p.id
  if p.ghost then
    local slot = ((pid - 1) % #world.CLASSES) + 1
    local ix, iy = world.class_icon_pos(slot)
    local face = input.facing_towards(p.x, p.y, ix, iy)
    if world.dist(p.x, p.y, ix, iy) <= 30 then
      return { mask = 0, facing = face }
    end
    return { mask = move_mask_towards(p.x, p.y, ix, iy, 8), facing = face }
  end

  local h = state.hogger
  local attack = model.classes[p.class] and model.classes[p.class].attack or "melee"
  local range = model.p("melee_range")
  if attack == "shot" then range = model.p("autoshot_range") end
  if CASTER[p.class] and (p.resource or 0) >= 20 then
    range = model.p("cast_range")
  end
  local duty = M.healer_duty(p)
  if duty and (p.class == "priest" or p.class == "druid") then
    range = model.p("cast_range")
  end

  local d = world.dist(p.x, p.y, h.x, h.y)
  local mask = 0
  local kick = false
  local heal_pid = nil
  if d > range * 0.9 then
    mask = move_mask_towards(p.x, p.y, h.x, h.y, 8)
  else
    local low_hp = p.hp < 0.5 * p.max_hp
    local cls = p.class
    local needy = duty and M.heal_target(state, p) or nil
    if needy and state.tick % 15 == p.id % 15 then
      heal_pid = needy.id
    end
    if cls == "warrior" or cls == "hunter" or cls == "mage"
       or cls == "warlock" or cls == "rogue" then
      if state.tick % 30 == 0 then mask = mask + input.AB1 end
    end
    if cls == "druid" and not needy then
      if state.tick % 30 == 0 then mask = mask + input.AB1 end
    end
    if cls == "priest" then
      if duty then
        if not needy and state.tick % 30 == 0 then mask = mask + input.AB1 end
      elseif low_hp and state.tick % 30 == 15 then mask = mask + input.AB2
      elseif state.tick % 30 == 0 then mask = mask + input.AB1 end
    end
    if cls == "paladin" then
      if not duty and low_hp and state.tick % 30 == 15 then
        mask = mask + input.AB1
      elseif state.tick % 30 == 0 then mask = mask + input.AB2 end
    end
    if cls == "rogue" and (p.cp or 0) >= model.CP_MAX and state.tick % 30 == 15 then
      mask = mask + input.AB2
    end
    if cls == "rogue" and eating_channel(h) and d <= model.p("melee_range") then
      kick = true
    end
    if cls == "warlock" and state.tick % 600 == 30 then
      mask = mask + input.AB2
    end
  end
  return { mask = mask, facing = input.facing_towards(p.x, p.y, h.x, h.y),
           kick = kick, heal = heal_pid }
end

-- ---------------------------------------------------------------------------
-- Profil "typisch" (und "turtle" als Sonderfall: nur heilen)
-- ---------------------------------------------------------------------------
-- Der Kicker ist der lebende Schurke mit der kleinsten pid: er haelt
-- Energie fuer den Tritt zurueck und bleibt am Boss. Andere Schurken
-- spielen normal und treten, wenn sie zufaellig in Reichweite stehen.
local function is_kicker(state, p)
  if p.class ~= "rogue" then return false end
  for _, q in ipairs(state.players) do
    if q.alive and q.class == "rogue" and not q.is_leeroy then
      return q.id == p.id
    end
  end
  return false
end

local function decide_typisch(state, p, brain)
  local pid = p.id
  local turtle = brain.profile == "turtle"
  local now = state.time or (state.tick * model.TICK_DT)

  -- Geist: Klasse nach Bedarf, dann zum Icon. Die Wahl wird EINMAL je
  -- Geisterlauf getroffen und gemerkt — sonst wechselt sie mit jeder
  -- Wiederbelebung eines anderen und der Geist pendelt zwischen den Icons.
  if p.ghost then
    local cls = brain.ghost_choice
    if not cls then
      if turtle then
        local list = ROLE_CLASSES.healer
        cls = list[((pid - 1) % #list) + 1]
      else
        cls = M.choose_class(state, p)
      end
      brain.ghost_choice = cls
    end
    local slot = slot_of_class(cls)
    local ix, iy = world.class_icon_pos(slot)
    local face = input.facing_towards(p.x, p.y, ix, iy)
    if world.dist(p.x, p.y, ix, iy) <= 30 then
      return { mask = 0, facing = face }
    end
    return { mask = move_mask_towards(p.x, p.y, ix, iy, 8), facing = face }
  end

  brain.ghost_choice = nil -- lebend: die naechste Wahl faellt neu

  -- liegend (Totstellen): nichts tun, sonst steht man auf
  if now < (p.feign_until or 0) or p.feigning then
    return { mask = 0, facing = p.facing or 0 }
  end

  local h = state.hogger
  local cls = p.class
  local duty = M.healer_duty(p)
  local melee_r = model.p("melee_range")

  -- Gegner: ein Mob/Welpe, der mich angreift und nah ist, wird Ziel —
  -- sonst Hogger. (Vorher zielten Bots nur auf Hogger und liessen sich von
  -- drei Welpen dauerhaft anknabbern.)
  local target_id = world.HOGGER_ID
  local ex, ey = h.x, h.y
  local npc = (not turtle) and attacker_npc(state, p, model.p("cast_range")) or nil
  if npc then target_id, ex, ey = npc.id, npc.x, npc.y end
  local set_target = (p.target ~= target_id) and target_id or nil

  -- Wunschreichweite: Nahkaempfer 40 px, Jaeger Autoschuss, Caster Zauber-
  -- reichweite — auch OOM (Magier/Hexer ruecken OOM zum Stab-Vermoebeln auf,
  -- GDD 17.9; Priester/Druide bleiben draussen, sie heilen)
  local attack = model.classes[cls] and model.classes[cls].attack or "melee"
  local range = melee_r
  if attack == "shot" then range = model.p("autoshot_range")
  elseif CASTER[cls] then
    range = model.p("cast_range")
    if (cls == "mage" or cls == "warlock") and (p.resource or 0) < 20 then
      range = melee_r
    end
  end
  if turtle then range = model.p("cast_range") end
  if npc and range > melee_r and world.dist(p.x, p.y, ex, ey) <= range then
    -- Fernkaempfer schiesst den Mob; Nahkaempfer geht ran
  end

  local d = world.dist(p.x, p.y, ex, ey)
  local mask = 0
  local kick, heal_pid = false, nil

  -- Reichweite halten: heran, sobald das Ziel ausser Reichweite ist, bis
  -- man mit etwas Luft drinsteht (0,9 x Reichweite) — und NIE waehrend
  -- eines eigenen Casts (Bewegung bricht ihn; der Bot bis Runde 19 lief
  -- jedem Schritt Hoggers hinterher und toetete so seine 2-s-Zauber)
  local hold = casting(p)
  if d > range and not hold then
    mask = move_mask_towards(p.x, p.y, ex, ey, 8)
  elseif d > range * 0.9 and not hold and mask == 0 and (brain.approaching or false) then
    mask = move_mask_towards(p.x, p.y, ex, ey, 8)
  end
  brain.approaching = mask ~= 0 and d > range * 0.9
  local in_range = d <= range
  -- Faehigkeiten hoechstens alle 0,5 s (ein Mensch hämmert nicht 60x je
  -- Sekunde); die Frist haengt am Gehirn, nicht am Tick-Modulo — das
  -- Entscheidungsraster (alle 3 Ticks) traf ein Modulo sonst nie
  local on_tick = state.tick >= (brain.next_ab or 0)
  local half_tick = on_tick

  -- Heilung anderer: Heiler im Dienst heilen, sobald jemand Heilung braucht
  if duty then
    local needy = M.heal_target(state, p, turtle and 0.85 or 0.8)
    if needy and not hold and state.tick % 15 == pid % 15 then
      heal_pid = needy.id
    end
    if turtle then
      return { mask = mask, facing = input.facing_towards(p.x, p.y, ex, ey),
               heal = heal_pid, target = set_target }
    end
    if heal_pid then
      -- Heilen geht vor Schaden; Maske ohne Faehigkeits-Bits
      return { mask = mask, facing = input.facing_towards(p.x, p.y, ex, ey),
               heal = heal_pid, target = set_target }
    end
  end

  local low_hp = p.hp < 0.5 * p.max_hp
  local h_target = hogger_target_pid(state)
  local i_am_target = h_target == pid

  if in_range and not hold then
    if cls == "warrior" then
      -- Schlachtruf, wenn er fehlt; Spott, wenn Hogger einen Stoffträger
      -- prügelt; sonst Heroischer Stoss
      local shouting = (p.shout_until or 0) > now or p.shout
      local tp = h_target and state.players[h_target]
      if not shouting and on_tick then mask = mask + input.AB2
      elseif tp and tp.id ~= pid and CLOTH[tp.class or ""] and (p.taunt_cd or 0) <= 0
             and d <= model.p("warrior_taunt_range") and half_tick then
        mask = mask + input.AB3
      elseif on_tick then mask = mask + input.AB1 end
    elseif cls == "paladin" then
      -- Handauflegung auf den, der gleich stirbt (einmal pro Leben)
      local dying = (not p.loh_used) and M.heal_target(state, p, 0.2) or nil
      if dying and half_tick then
        heal_pid = nil
        -- Slot 3 zielt ueber p.target/Selbst-Fallback: auf sich selbst,
        -- wenn man selbst der Sterbende ist, sonst Heiliges Licht als
        -- Klick-Heilung (LoH auf andere braucht ein explizites Ziel, das
        -- nur die Heil-Leiste liefert)
        if dying.id == pid then mask = mask + input.AB3
        else heal_pid = dying.id end
      elseif not duty and low_hp and half_tick then mask = mask + input.AB1
      elseif on_tick then mask = mask + input.AB2 end
    elseif cls == "hunter" then
      -- Totstellen, wenn Hogger mich fuehrt und es eng wird
      if i_am_target and p.hp < 0.4 * p.max_hp and (p.feign_cd or 0) <= 0 and on_tick then
        mask = mask + input.AB2
      elseif d <= melee_r and on_tick then mask = mask + input.AB1 end
    elseif cls == "rogue" then
      local kicker = is_kicker(state, p)
      local reserve = kicker and (model.p("rogue_kick_energy") + model.p("rogue_sinister_energy"))
                             or 0
      if (p.cp or 0) >= model.CP_MAX and half_tick and (p.resource or 0) >= reserve + 30 then
        mask = mask + input.AB2
      elseif on_tick and (p.resource or 0) >= reserve then
        mask = mask + input.AB1
      end
    elseif cls == "priest" then
      -- Schild auf sich selbst, wenn Hogger mich fuehrt (Slot 3 zielt ueber
      -- Selbst-Fallback); sonst Pein
      if (i_am_target or low_hp) and not p.shielded and (p.shield_hp or 0) <= 0
         and now >= (p.weak_soul_until or 0) and half_tick then
        mask = mask + input.AB3
      elseif on_tick then mask = mask + input.AB1 end
    elseif cls == "mage" then
      if not p.frost_armor and half_tick then mask = mask + input.AB2
      elseif on_tick then mask = mask + input.AB1 end
    elseif cls == "warlock" then
      local has_imp = p.imp_id and state.npcs and state.npcs[p.imp_id] ~= nil
      if not has_imp and half_tick then mask = mask + input.AB2
      elseif on_tick then mask = mask + input.AB1 end
    elseif cls == "druid" then
      -- Wurzeln auf den Mob, der mich angreift; sonst Zorn
      if npc and (p.roots_cd or 0) <= 0 and now >= (npc.rooted_until or 0) and half_tick then
        mask = mask + input.AB3
      elseif on_tick then mask = mask + input.AB1 end
    end
  end

  -- Tritt (Runde 20): 1-2 s nach Kanalbeginn, nur in Schlagweite von
  -- Hogger; Energie/Cooldown prueft der S.kick-Pfad
  if cls == "rogue" then
    if eating_channel(h) then
      brain.eat_seen_t = brain.eat_seen_t or now
      local dh = world.dist(p.x, p.y, h.x, h.y)
      if now - brain.eat_seen_t >= brain.react and dh <= melee_r then
        kick = true
      end
      -- Der Kicker laeuft zum Fressen hin, wenn er nicht drinsteht
      if is_kicker(state, p) and dh > melee_r and not hold then
        mask = move_mask_towards(p.x, p.y, h.x, h.y, 8)
        ex, ey = h.x, h.y
      end
    else
      brain.eat_seen_t = nil
    end
  end

  if mask >= input.AB1 then brain.next_ab = state.tick + 30 end
  -- Autoangriff anschalten wie per Rechtsklick (GDD 8.1): sobald das Ziel
  -- in Reichweite steht. Ein Jaeger drueckt sonst nie etwas (Raptorstoss
  -- braucht Nahkampf) und schiesst deshalb nie.
  local engage = in_range and not p.attack_on and not duty and not turtle
  return { mask = mask, facing = input.facing_towards(p.x, p.y, ex, ey),
           kick = kick, heal = heal_pid, target = set_target,
           engage = engage or nil }
end

-- decide(state, pid[, brain]) -> { mask, facing, kick?, heal?, target? }
-- kick/heal/target liegen NEBEN der Maske: sie haben kein Bit, der Traeger
-- (Host/Runner) ruft step.kick, step.heal_request bzw. world.set_target.
function M.decide(state, pid, brain)
  local p = state.players[pid]
  if not p then return { mask = 0, facing = 0 } end
  if not p.alive and not p.ghost then return { mask = 0, facing = 0 } end

  brain = brain or brain_of(state, p)
  if not brain or brain.profile == "kopflos" then
    return decide_kopflos(state, p)
  end

  -- Entscheidungsraster: dazwischen die letzte Maske ohne Flanken-Bits
  local every = M.DECIDE_EVERY
  if brain.cached and state.tick - brain.last_tick < every then
    local c = brain.cached
    return { mask = c.mask_hold, facing = c.facing }
  end
  local dec = decide_typisch(state, p, brain)
  local hold = dec.mask
  for _, bit in ipairs({ input.AB1, input.AB2, input.AB3 }) do
    if hold % (bit * 2) >= bit then hold = hold - bit end
  end
  dec.mask_hold = hold
  brain.cached = dec
  brain.last_tick = state.tick
  return dec
end

-- Bequemer Runner fuer Tests: laeuft n Ticks mit Bots, sammelt Events
function M.run(state, ticks, evsink)
  local step = require("game.gamesim.step")
  for _ = 1, ticks do
    local inputs = {}
    for _, p in ipairs(state.players) do
      if not p.is_leeroy then
        local dec = M.decide(state, p.id)
        inputs[p.id] = dec
        -- Tritt/Heilung/Ziel wie der Host: vor dem Tick, in Spieler-Reihenfolge
        if dec.kick then step.kick(state, p.id, evsink or {}) end
        if dec.heal then step.heal_request(state, p.id, dec.heal, evsink or {}) end
        if dec.target then world.set_target(state, p.id, dec.target, evsink) end
        if dec.engage then step.engage(state, p.id) end
      end
    end
    local evs = step.step(state, inputs)
    if evsink then
      for _, e in ipairs(evs) do evsink[#evsink + 1] = e end
    end
  end
end

return M
