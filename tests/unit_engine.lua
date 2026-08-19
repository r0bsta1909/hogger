-- tests/unit_engine.lua â€” Stufe 1: Engine-Invarianten auf echten Sim-Laeufen
-- und gezielte Einzelpruefungen (Threat-Loeschung bei Tod, Heilungsdeckel).

local model = require("sim.model")
local engine = require("sim.engine")
local T = _G.T

-- Kompletter Kurzlauf jedes Agententyps: Ergebnisstruktur plausibel ----------
for _, agent in ipairs({ "unkoordiniert", "koordiniert", "turtle" }) do
  local r = engine.run_try({ n = 5, walk = 15, crits = true,
                             agent = agent, seed = 1, log = false })
  T.ok(r.duration > 0 and r.duration <= model.p("try_time_limit") + 1,
    "engine: Trydauer im Rahmen (" .. agent .. ")")
  T.ok(r.rest_hp_pct >= 0 and r.rest_hp_pct <= 1,
    "engine: Rest-HP-Anteil in [0,1] (" .. agent .. ")")
  T.ok(r.uptime >= 0 and r.uptime <= 1,
    "engine: Uptime in [0,1] (" .. agent .. ")")
  T.ok(r.c.eat_interrupted + r.c.eat_completed <= r.c.eat_channels,
    "engine: Fress-Buchhaltung konsistent (" .. agent .. ")")
end

-- Gezielte Invarianten auf einem manuell gebauten Mini-Zustand ---------------
local rngmod = require("sim.rng")
local function mini_run()
  local run = {
    cfg = { n = 5, walk = 15, crits = false, agent = "unkoordiniert",
            seed = 1, log = false },
    rng = rngmod.new(1), t = 100, events = {}, corpses = {}, adds = {},
    players = {},
    agent = { act = function() end },
    hogger = { hp = 600, max_hp = 600, next_auto = 0, slice_ready = 0,
               charge_ready = 0, eat_ready = 0, eating = nil, target = nil,
               slow_until = 0 },
    c = { deaths = 0, dmg_to_hogger = 0, dmg_to_players = 0, healing = 0,
          crit_kills = 0, eat_channels = 0, eat_interrupted = 0,
          eat_completed = 0, eat_healing = 0, charges = 0, add_deaths = 0 },
  }
  return run
end

local run = mini_run()
local p = { id = "p1", class = "warrior", is_leeroy = false, alive = true,
            hp = 80, max_hp = 80, resource = 0, cp = 0, d = 40, state = "combat",
            dead_until = 0, gcd_ready = 0, cast = nil, last_cast_t = -1000,
            next_auto = 0, raptor_ready = 0, threat = 50, bleed_until = 0,
            bleed_next = math.huge, shout_until = 0, seal_hits = 0,
            has_frost_armor = false, imp_alive = false, add_idx = nil,
            combat_time = 0, dmg_done = 0, heal_done = 0, deaths = 0, skill = 1 }
run.players[1] = p

-- Threat-Loeschung bei Tod (GDD 9.4)
engine.kill_player(run, p)
T.eq(p.threat, 0, "engine: Bedrohung wird beim Tod geloescht")
T.ok(not p.alive, "engine: Spieler ist nach kill_player tot")
T.eq(#run.corpses, 1, "engine: Tod hinterlaesst genau eine Leiche")
T.eq(run.corpses[1].d, 40, "engine: Leiche liegt an der Sterbeposition")

-- Kein Heilen ueber Max (Invariante aus GDD 17.7 Stufe 4, hier vorgezogen)
local run2 = mini_run()
local healer = { id = "p1", class = "priest", is_leeroy = false, alive = true,
                 hp = 50, max_hp = 50, resource = 100, cp = 0, d = 120,
                 state = "combat", dead_until = 0, gcd_ready = 0, cast = nil,
                 last_cast_t = -1000, next_auto = 0, raptor_ready = 0,
                 threat = 0, bleed_until = 0, bleed_next = math.huge,
                 shout_until = 0, seal_hits = 0, has_frost_armor = false,
                 imp_alive = false, add_idx = nil, combat_time = 0,
                 dmg_done = 0, heal_done = 0, deaths = 0, skill = 1 }
local hurt = { id = "p2", class = "warrior", is_leeroy = false, alive = true,
               hp = 78, max_hp = 80, resource = 0, cp = 0, d = 40,
               state = "combat", dead_until = 0, gcd_ready = 0, cast = nil,
               last_cast_t = -1000, next_auto = 0, raptor_ready = 0,
               threat = 0, bleed_until = 0, bleed_next = math.huge,
               shout_until = 0, seal_hits = 0, has_frost_armor = false,
               imp_alive = false, add_idx = nil, combat_time = 0,
               dmg_done = 0, heal_done = 0, deaths = 0, skill = 1 }
run2.players[1], run2.players[2] = healer, hurt
engine.heal_player(run2, healer, hurt, 20, "heal")
T.eq(hurt.hp, 80, "engine: Heilung deckelt bei Max-HP")
T.near(healer.threat, 2 * model.p("threat_per_heal"),
  "engine: Heil-Bedrohung nur fuer effektive Heilung")

-- Fress-Unterbrechung: Schwelle ueber verschiedene Spieler -------------------
local run3 = mini_run()
run3.hogger.hp = 300 -- unter 90 %
run3.hogger.eating = { phase = "channel", ends_at = run3.t + 8,
                       hitters = {}, hitter_count = 0, dmg_accum = 0 }
local a1 = { id = "a1", class = "hunter", is_leeroy = false, alive = true,
             hp = 65, max_hp = 65, resource = 100, cp = 0, d = 200,
             state = "combat", dead_until = 0, gcd_ready = 0, cast = nil,
             last_cast_t = -1000, next_auto = 0, raptor_ready = 0, threat = 0,
             bleed_until = 0, bleed_next = math.huge, shout_until = 0,
             seal_hits = 0, has_frost_armor = false, imp_alive = false,
             add_idx = nil, combat_time = 0, dmg_done = 0, heal_done = 0,
             deaths = 0, skill = 1 }
local a2 = { id = "a2", class = "hunter", is_leeroy = false, alive = true,
             hp = 65, max_hp = 65, resource = 100, cp = 0, d = 200,
             state = "combat", dead_until = 0, gcd_ready = 0, cast = nil,
             last_cast_t = -1000, next_auto = 0, raptor_ready = 0, threat = 0,
             bleed_until = 0, bleed_next = math.huge, shout_until = 0,
             seal_hits = 0, has_frost_armor = false, imp_alive = false,
             add_idx = nil, combat_time = 0, dmg_done = 0, heal_done = 0,
             deaths = 0, skill = 1 }
local a3 = { id = "a3", class = "hunter", is_leeroy = false, alive = true,
             hp = 65, max_hp = 65, resource = 100, cp = 0, d = 200,
             state = "combat", dead_until = 0, gcd_ready = 0, cast = nil,
             last_cast_t = -1000, next_auto = 0, raptor_ready = 0, threat = 0,
             bleed_until = 0, bleed_next = math.huge, shout_until = 0,
             seal_hits = 0, has_frost_armor = false, imp_alive = false,
             add_idx = nil, combat_time = 0, dmg_done = 0, heal_done = 0,
             deaths = 0, skill = 1 }
run3.players[1], run3.players[2], run3.players[3] = a1, a2, a3
-- Runde 12 (#140): Schaden unterbricht NICHT mehr — egal wie viele
-- verschiedene Spieler treffen. Nur der Schurken-Tritt beendet den Kanal.
engine.player_damage_hogger(run3, a1, 50, "autohit")
engine.player_damage_hogger(run3, a2, 50, "autohit")
engine.player_damage_hogger(run3, a3, 50, "autohit")
T.ok(run3.hogger.eating ~= nil,
  "engine: Schaden vieler Spieler unterbricht nicht mehr (#140)")
engine.interrupt_eat(run3, 1)
T.ok(run3.hogger.eating == nil, "engine: der Tritt beendet den Kanal")
T.eq(run3.c.eat_interrupted, 1, "engine: Unterbrechung gezaehlt")

-- Der koordinierte Agent tritt nur mit lebendem Schurken in Schlagweite,
-- bereitem Cooldown und genug Energie (Runde 12, #140)
do
  local agents = require("sim.agents")
  local kr = mini_run()
  kr.hogger.eating = { phase = "channel", ends_at = kr.t + 8 }
  local rogue = { id = "r1", class = "rogue", is_leeroy = false, alive = true,
                  hp = 65, max_hp = 65, resource = 100, cp = 0, d = 40,
                  state = "combat", dead_until = 0, gcd_ready = 0, cast = nil,
                  last_cast_t = -1000, next_auto = 0, raptor_ready = 0,
                  kick_ready = 0, threat = 0, bleed_until = 0,
                  bleed_next = math.huge, shout_until = 0, seal_hits = 0,
                  has_frost_armor = false, imp_alive = false, add_idx = nil,
                  combat_time = 0, dmg_done = 0, heal_done = 0, deaths = 0,
                  skill = 1 }
  kr.players[1] = rogue
  kr.agent = agents.make("koordiniert", kr)
  kr.agent.tick(kr) -- Reaktionszeit laeuft erst an
  T.ok(kr.hogger.eating ~= nil, "agent: vor der Reaktionszeit kein Tritt")
  kr.t = kr.t + 1.5
  kr.agent.tick(kr)
  T.ok(kr.hogger.eating == nil, "agent: Schurke in Schlagweite tritt")
  T.near(rogue.resource, 100 - model.p("rogue_kick_energy"),
    "agent: der Tritt kostet Energie")
  T.ok(rogue.kick_ready > kr.t, "agent: der Tritt geht auf Cooldown")

  -- ohne bereiten Tritt frisst Hogger weiter
  kr.hogger.eating = { phase = "channel", ends_at = kr.t + 8,
                       react_at = kr.t }
  kr.agent.tick(kr)
  T.ok(kr.hogger.eating ~= nil, "agent: Tritt auf Cooldown -> Kanal laeuft")

  -- toter Schurke tritt nicht
  rogue.kick_ready = 0
  rogue.alive = false
  kr.hogger.eating = { phase = "channel", ends_at = kr.t + 8,
                       react_at = kr.t }
  kr.agent.tick(kr)
  T.ok(kr.hogger.eating ~= nil, "agent: toter Schurke tritt nicht")
end

-- Kein-Kontakt-Abbruch (Runde 10, #124): dieselbe Regel wie im Spiel. Im
-- 1D-Modell greift sie praktisch nur beim totalen Wipe — die Todesstrafe
-- (24 s) liegt unter der Frist (30 s), der Nachschub schafft es also.
do
  local entry = model.params.hogger_no_contact_reset
  local orig = entry.wert

  -- Mit der GDD-Frist laeuft ein normaler Lauf ohne Abbruch durch.
  local ruhig = engine.run_try({ n = 10, walk = 15, crits = false,
                                 agent = "koordiniert", seed = 7, log = false })
  T.eq(ruhig.c.resets, 0, "engine: Frist von 30 s bricht einen normalen Lauf nicht ab")

  -- Mit einer absurd kurzen Frist muss die Regel greifen und den Lauf
  -- vorzeitig als Niederlage beenden — der Beweis, dass sie verdrahtet ist.
  entry.wert = 0.5
  local kurz = engine.run_try({ n = 10, walk = 15, crits = false,
                                agent = "unkoordiniert", seed = 7, log = false })
  entry.wert = orig
  T.eq(kurz.c.resets, 1, "engine: kurze Frist loest den Abbruch aus")
  T.ok(not kurz.win, "engine: der Abbruch wertet den Lauf als Niederlage")
  T.ok(kurz.duration < model.p("try_time_limit"),
    "engine: der Abbruch beendet den Lauf vorzeitig")
  T.eq(model.p("hogger_no_contact_reset"), orig,
    "engine: der Test stellt die Frist wieder her")
end

