-- tests/unit_gamesim.lua — Stufe 1: Spielsimulation (game/gamesim) headless.
-- Laeuft unter vergiftetem love-Global: beweist die love-Freiheit von ADR-002.

local model = require("sim.model")
local map = require("game.data.map")
local input = require("game.gamesim.input")
local world = require("game.gamesim.world")
local step = require("game.gamesim.step")
local bot = require("game.gamesim.bot")
local T = _G.T

-- Karte: Distanzen folgen model.lua (eine Wahrheit) -------------------------
local f, g = map.field(), map.graveyard()
T.near(world.dist(f.x, f.y, map.hill.x, map.hill.y),
  model.p("field_to_hill_dist"), "map: Feld-Huegel-Distanz = Modellparameter")
T.near(world.dist(g.x, g.y, f.x, f.y),
  model.p("graveyard_to_field_dist"), "map: Friedhof-Feld-Distanz = Modellparameter")
T.ok(g.x > 0 and g.x < map.WIDTH and g.y > 0 and g.y < map.HEIGHT,
  "map: Friedhof innerhalb der Weltgrenzen")
T.eq(map.zone_at(map.hill.x, map.hill.y), "Hogger Hill", "map: Zone Huegel")
T.eq(map.zone_at(g.x, g.y), "Friedhof von Elwynn", "map: Zone Friedhof")
T.ok(map.in_graveyard(g.x, g.y), "map: Friedhofszone erkannt")

-- Input-Bitmaske ------------------------------------------------------------
T.ok(input.has(input.LEFT + input.JUMP, input.JUMP), "input: has erkennt Bit")
T.ok(not input.has(input.LEFT, input.JUMP), "input: has lehnt fehlendes Bit ab")
local dx, dy = input.move_vec(input.RIGHT + input.DOWN)
T.near(math.sqrt(dx * dx + dy * dy), 1, "input: Diagonale normalisiert")
T.ok(input.pressed(input.AB1, 0, input.AB1), "input: Flanke erkannt")
T.ok(not input.pressed(input.AB1, input.AB1, input.AB1), "input: Halten ist keine Flanke")
T.ok(input.valid(255) and input.valid(0), "input: 0..255 gueltig")
T.ok(not input.valid(256) and not input.valid(-1) and not input.valid(1.5),
  "input: ausserhalb 0..255 ungueltig")

-- Weltaufbau und Try-Start --------------------------------------------------
local state = world.new(1)
for i = 1, 5 do world.add_player(state, "bot" .. i) end
local ev0 = {}
world.begin_try(state, ev0)
T.eq(state.n_scale, 5, "world: N beim Try-Start")
T.eq(state.hogger.hp, model.hogger_hp(5), "world: Hogger-HP nach 9.3-Formel")
T.eq(state.try_nr, 1, "world: Try-Zaehler")
T.eq(ev0[1].ev, "try_start", "world: try_start-Event")
local seed_logged = false
for _, e in ipairs(ev0) do
  if e.ev == "param_change" and e.dst == "seed" then seed_logged = true end
end
T.ok(seed_logged, "world: Seed je Try geloggt (GDD 13.2)")

-- Wiederbelebungs-Ablauf: Geist auf Icon -> Channel -> lebend ---------------
local p1 = state.players[1]
local ix, iy = world.class_icon_pos(1)
p1.x, p1.y = ix, iy
local ticks_needed = math.ceil((model.p("revive_channel") + 0.1) / model.TICK_DT)
for _ = 1, ticks_needed do
  step.step(state, { [1] = { mask = 0, facing = 0 } })
end
T.ok(p1.alive, "step: Wiederbelebung nach Channel")
T.eq(p1.class, "warrior", "step: Klasse vom Icon-Slot")
T.eq(p1.hp, model.p("hp_plate"), "step: HP nach Ruestungsklasse")

-- Bot-Volllauf: Invarianten ueber 90 Simulationssekunden --------------------
local state2 = world.new(7)
for i = 1, 5 do world.add_player(state2, "bot" .. i) end
world.begin_try(state2, {})
local evs = {}
bot.run(state2, 90 * 60, evs)
local saw_damage, saw_death, saw_revive = false, false, false
for _, e in ipairs(evs) do
  if e.ev == "damage" then saw_damage = true end
  if e.ev == "death" then saw_death = true end
  if e.ev == "revive" then saw_revive = true end
end
T.ok(saw_revive, "step: Bots beleben sich wieder")
T.ok(saw_damage, "step: Kampf findet statt")
T.ok(saw_death, "step: Hogger toetet")
T.ok(state2.hogger.hp <= state2.hogger.max_hp, "step: Hogger-HP nie ueber Max")
for _, p in ipairs(state2.players) do
  T.ok(p.hp <= p.max_hp + 1e-9, "step: Spieler-HP nie ueber Max (" .. p.id .. ")")
  T.ok(p.x >= 0 and p.x <= map.WIDTH and p.y >= 0 and p.y <= map.HEIGHT,
    "step: Position in Weltgrenzen (" .. p.id .. ")")
  T.ok(not (p.alive and p.ghost), "step: nie gleichzeitig lebend und Geist (" .. p.id .. ")")
  if not p.alive then
    T.ok((state2.hogger.threat[p.id] or 0) == 0,
      "step: Bedrohung Toter geloescht (" .. p.id .. ")")
  end
end
T.ok(state2.players[1].jumps > 0, "step: Sprungzaehler zaehlt (GDD 4.1)")
