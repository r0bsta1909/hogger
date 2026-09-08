-- sim/gamerun.lua — die Spielsimulation als Balancing-Sim (Runde 20).
--
-- Bis Runde 19 beantwortete ein eigenes 1D-Modell (sim/engine.lua) die
-- Balancing-Fragen. Es mass einen Raid, den es im Spiel nicht gab: Dienst-
-- Schurke mit 0,5 s Tritt, 50 % Jaeger, 60 % Charge-Ausweichen. Rob-Entscheid
-- (2026-09-08): die echte Spielsimulation game/gamesim ist die einzige
-- Balancing-Wahrheit, gespielt von den Bots, gegen die auch Menschen gemessen
-- werden. Dieses Modul treibt sie headless in reinem LuaJIT — kein love.*,
-- kein Netz, kein Fenster — und liefert je Lauf dieselbe Zusammenfassung wie
-- engine.run_try, damit sim/report.lua unveraendert prueft.
--
-- Ein Lauf = ein Zustand bis zum ersten try_end (Sieg, Wipe, Kein-Kontakt
-- oder Enrage). Die Auswertung der Ereignisse macht tools/logreport.lua —
-- dieselbe Funktion, die einen gespielten Abend nachrechnet.

local model = require("sim.model")
local hashmod = require("sim.hash")
local rngmod = require("sim.rng")
local world = require("game.gamesim.world")
local step = require("game.gamesim.step")
local bot = require("game.gamesim.bot")
local events = require("game.gamesim.events")
local logreport = require("tools.logreport")

local G = {}

-- Bot-Profile (GDD 17.2, Runde 20): typisch = der Raid, gegen den balanciert
-- wird; kopflos = die F2/F3-Gegenprobe; turtle = das Anti-Stall-Gate.
G.PROFILES = { "typisch", "kopflos", "turtle" }
G.DEFAULT_PROFILE = "typisch"

local DT = model.TICK_DT

-- Ein Tick fuer alle Bots: Entscheidungen einsammeln, Tritt/Heilung/Ziel
-- wie der Host ueber die autoritativen step-Pfade, Freigabe fuer Tote,
-- dann der Schritt. Leeroys Eingabe injiziert step.step selbst.
function G.tick(state, evsink)
  local inputs = {}
  for _, p in ipairs(state.players) do
    if not p.is_leeroy then
      local dec = bot.decide(state, p.id)
      inputs[p.id] = dec
      if dec.kick then step.kick(state, p.id, evsink) end
      if dec.heal then step.heal_request(state, p.id, dec.heal, evsink) end
      if dec.target then world.set_target(state, p.id, dec.target, evsink) end
      if dec.engage then step.engage(state, p.id) end
      -- Bots druecken "Geist freilassen" sofort (wie host.lua) — nur wenn
      -- sie tot und noch kein Geist sind, sonst reine Kosten je Tick
      if not p.alive and not p.ghost then step.release_spirit(state, p.id) end
    end
  end
  local evs = step.step(state, inputs)
  for _, e in ipairs(evs) do evsink[#evsink + 1] = e end
  return evs
end

-- Krits aus: beide Chancen auf 0. crit_roll zieht auch bei 0 % einen Wert,
-- die Krit-Welten teilen sich also den Zufallsstrom (gepaarter Vergleich).
local function set_crits(on)
  for _, key in ipairs({ "crit_chance_player", "crit_chance_hogger" }) do
    model.params[key].wert = on and model.defaults[key] or 0
  end
end

-- cfg = { n, seed, crits (bool), profile, log (bool) }
-- Ergebnis im Format von engine.run_try (sim/report.lua) plus:
--   reason (win|wipe|no_contact|timeout), lifetimes (Sekunden je Leben),
--   class_changes, eat_heal, kick_latencies
function G.run_try(cfg)
  local profile = cfg.profile or G.DEFAULT_PROFILE
  local crits = cfg.crits ~= false
  set_crits(crits)
  -- Rasterpunkt "typisch ohne X" (bot.SKIP): nur fuer diesen Lauf
  bot.SKIP = cfg.skip or {}

  local state = world.new(cfg.seed)
  world.add_leeroy(state)
  for i = 1, cfg.n do
    world.add_player(state, "bot" .. i, { quest_done = true, profile = profile })
  end
  -- Streuungsmodell (GDD 17.2 Punkt 5b, Pflicht fuer alle Agenten): ein
  -- Gruppenfaktor je Lauf mal ein Skill-Faktor je Bot auf den verursachten
  -- Schaden. Ohne Streuung springen Siegquoten zwischen 0 und 100 %
  -- (Stufenfunktion, Skill-Lehre) und ein Band wie 60-90 % ist nicht
  -- messbar. Eigener RNG-Strom, der Spiel-Zufall bleibt unberuehrt.
  do
    local srng = rngmod.new(rngmod.mix(cfg.seed or 0, 1)) -- Nebenstrom 1: Streuung
    local gmin, gmax = model.p("sim_group_factor_min"), model.p("sim_group_factor_max")
    local smin, smax = model.p("sim_skill_min"), model.p("sim_skill_max")
    local group = gmin + (gmax - gmin) * srng:next()
    for _, p in ipairs(state.players) do
      if not p.is_leeroy then
        p.skill = group * (smin + (smax - smin) * srng:next())
      end
    end
  end
  local evs = {}
  world.begin_try(state, evs)
  local max_hp = state.hogger.max_hp

  -- Deckel: Frist + Enrage-Sequenz + Luft. Ein Lauf, der ihn erreicht, ist
  -- ein Fehler in der Sim, kein Ergebnis.
  local max_ticks = math.ceil((model.p("try_time_limit") + 30) / DT)
  local ended = false
  for _ = 1, max_ticks do
    local tick_evs = G.tick(state, evs)
    for _, e in ipairs(tick_evs) do
      if e.ev == "try_end" then ended = true end
    end
    if ended then break end
  end
  set_crits(true)
  bot.SKIP = {}
  assert(ended, "gamerun: kein try_end innerhalb der Frist (N=" .. cfg.n .. ")")

  local r = logreport.analyse_events(evs)
  local t = r.trys[1]
  assert(t and t.dauer, "gamerun: Auswertung ohne Try")

  -- Klassen der Spieler am Ende des Laufs (Leeroy ausgenommen)
  local class_counts = {}
  for _, p in ipairs(state.players) do
    if not p.is_leeroy and p.class then
      class_counts[p.class] = (class_counts[p.class] or 0) + 1
    end
  end

  -- Uptime: Anteil gelebter Sekunden an N x Trydauer. engine.lua zaehlte
  -- Kampfzeit; hier zaehlt Lebenszeit — auf dem Anmarsch ist man nicht im
  -- Kampf, aber auch nicht tot. Der Unterschied steht im Bericht.
  local alive_sum = 0
  for _, v in ipairs(t.lifetimes) do alive_sum = alive_sum + v end

  local result = {
    win = t.won == true,
    reason = t.reason,
    duration = t.dauer,
    rest_hp_pct = max_hp > 0 and math.max(0, t.rest_hp or 0) / max_hp or 0,
    uptime = alive_sum / math.max(1, cfg.n * math.max(t.dauer, DT)),
    c = {
      deaths = t.deaths,
      eat_channels = t.eat_start,
      eat_interrupted = t.eat_interrupt,
      eat_completed = t.eat_complete,
      charges = t.charges,
      crit_kills = t.crit_kills,
      resets = t.reset and 1 or 0,
      dmg_to_hogger = t.dmg_hogger,
    },
    eat_heal = t.eat_heal,
    class_counts = class_counts,
    class_changes = t.class_changes,
    lifetimes = t.lifetimes,
    kick_latencies = t.kick_latencies,
  }
  if cfg.log then
    local lines = {}
    for i, e in ipairs(evs) do lines[i] = events.to_jsonl(e) end
    result.log_hash = hashmod.djb2(table.concat(lines, "\n"))
    result.events = evs
  end
  return result
end

return G
