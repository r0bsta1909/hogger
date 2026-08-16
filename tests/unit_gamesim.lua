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
do -- Rasse regelkonform ausgewuerfelt (GDD 5)
  local valid = false
  for _, r in ipairs(model.classes.warrior.races) do
    if r == p1.race then valid = true end
  end
  T.ok(valid, "step: Rasse gueltig fuer Klasse (" .. tostring(p1.race) .. ")")
end

-- M3: acht Klassen-Slots am Feld; Schurke, Verstohlenheit, Wichtel ----------
T.eq(#world.CLASSES, 8, "world: acht Klassenicon-Slots")
do
  local st = world.new(3)
  world.add_player(st, "sc")
  world.add_player(st, "hx")
  world.begin_try(st, {})
  local input_mod = require("game.gamesim.input")
  -- Schurke: Slot 4
  local rogue = st.players[1]
  local rx, ry = world.class_icon_pos(4)
  rogue.x, rogue.y = rx, ry
  -- Hexenmeister: Slot 7
  local lock = st.players[2]
  local lx, ly = world.class_icon_pos(7)
  lock.x, lock.y = lx, ly
  for _ = 1, math.ceil(2.2 / model.TICK_DT) do
    step.step(st, {})
  end
  T.eq(rogue.class, "rogue", "step: Slot 4 ist Schurke")
  T.eq(lock.class, "warlock", "step: Slot 7 ist Hexenmeister")
  T.eq(lock.resource, model.p("mana_max"), "step: Hexer startet mit vollem Mana")
  T.eq(rogue.resource, model.p("energy_max"), "step: Schurke startet mit voller Energie")
  T.ok(model.classes.warlock.races[1] ~= nil and lock.race ~= nil,
    "step: Hexer-Rasse gewuerfelt")
  -- Verstohlenheit: Slot 3 druecken -> an, nochmal -> aus (GDD 8.2)
  step.step(st, { [1] = { mask = input_mod.AB3 } })
  step.step(st, { [1] = { mask = 0 } })
  T.ok(rogue.stealth, "step: Verstohlenheit an")
  T.ok(not st.hogger.threat[1] or st.hogger.threat[1] == 0,
    "step: Hogger ignoriert Verstohlene")
  for _ = 1, math.ceil(model.p("gcd") / model.TICK_DT) + 1 do
    step.step(st, {})
  end
  step.step(st, { [1] = { mask = input_mod.AB3 } })
  step.step(st, { [1] = { mask = 0 } })
  T.ok(not rogue.stealth, "step: Verstohlenheit wieder aus")
  -- Wichtel beschwoeren: Slot 2 (3-s-Cast, GDD 8.2)
  step.step(st, { [2] = { mask = input_mod.AB2 } })
  T.ok(lock.cast ~= nil, "step: Wichtel-Beschwoerung castet")
  for _ = 1, math.ceil((model.p("warlock_imp_cast") + 0.2) / model.TICK_DT) do
    step.step(st, { [2] = { mask = 0 } })
  end
  T.ok(lock.imp_id ~= nil and st.npcs[lock.imp_id] ~= nil,
    "step: Wichtel existiert als NPC")
  T.eq(st.npcs[lock.imp_id].hp, model.p("imp_hp"), "step: Wichtel-HP nach 8.2")
  T.ok((st.hogger.threat[lock.imp_id] or 0) > 0,
    "step: Wichtel zieht kurz Aggro")
end

-- M3-2: Mob-Spawns folgen den GDD-7.2-Platzierungsregeln --------------------
for i, sp in ipairs(map.MOB_SPAWNS) do
  T.ok(map.dist_to_path(sp.x, sp.y) > 250,
    "map: Spawn " .. i .. " nicht auf der Friedhof-Huegel-Achse")
  T.ok(world.dist(sp.x, sp.y, map.hill.x, map.hill.y) > model.p("hogger_leash_radius"),
    "map: Spawn " .. i .. " ausserhalb der Leash-Zone")
  T.ok(sp.x > 0 and sp.x < map.WIDTH and sp.y > 0 and sp.y < map.HEIGHT,
    "map: Spawn " .. i .. " in Weltgrenzen")
  if sp.typ == "murloc" then
    T.ok(sp.y > map.RIVER_Y - 120, "map: Murloc " .. i .. " am Fluss")
  end
end

-- M3-2: Mob toeten -> XP + Loot; Aufheben -> Zaehler (GDD 7.3) --------------
do
  local st = world.new(9)
  world.add_player(st, "jaeger")
  world.begin_try(st, {})
  local mobs = 0
  for id = 100, 250 do
    if st.npcs[id] and st.npcs[id].slot then mobs = mobs + 1 end
  end
  T.eq(mobs, model.mob_slots(1), "step: aktive Mob-Slots nach Formel 7.2")

  local p = st.players[1]
  local ix, iy = world.class_icon_pos(1) -- Krieger
  p.x, p.y = ix, iy
  for _ = 1, math.ceil(2.2 / model.TICK_DT) do step.step(st, {}) end
  T.ok(p.alive, "step: Testspieler lebt")
  T.eq(st.npcs[st.mob_by_slot[1]].kind, "boar", "step: Slot 1 ist ein Wildschwein")
  -- Kill-Test am passiven Kobold (Slot 3) — das Wildschwein wuerde fliehen
  local kob_id = st.mob_by_slot[3]
  local kob = st.npcs[kob_id]
  T.ok(kob ~= nil and kob.kind == "kobold", "step: Slot 3 ist ein Kobold")
  p.x, p.y = kob.x + 20, kob.y
  world.set_target(st, 1, kob_id, {})
  local xp_before = p.xp
  local evs = {}
  for _ = 1, math.ceil(60 / model.TICK_DT) do
    local e = step.step(st, {})
    for _, x in ipairs(e) do evs[#evs + 1] = x end
    if not st.npcs[kob_id] then break end
  end
  T.ok(st.npcs[kob_id] == nil, "step: Kobold besiegt")
  T.eq(p.xp, xp_before + model.p("xp_per_mob"), "step: 1 XP pro Mob-Todesstoss")
  T.ok(st.mob_respawn[3] ~= nil, "step: Respawn-Timer laeuft (120 s)")
  local saw_kill, saw_xp = false, false
  for _, e in ipairs(evs) do
    if e.ev == "mob_kill" and e.dst == "kobold" then saw_kill = true end
    if e.ev == "xp_gain" then saw_xp = true end
  end
  T.ok(saw_kill and saw_xp, "step: mob_kill- und xp_gain-Events")
  -- Loot: der Killer steht auf der Leiche (Nahkampf 40 > Aufheben 30) und
  -- sammelt im Folgetick automatisch ein — Zaehler statt Inventar (GDD 7.3)
  step.step(st, {})
  local saw_pickup = false
  for _, e in ipairs(evs) do
    if e.ev == "loot_pickup" then saw_pickup = true end
  end
  local loot_left = false
  for id = 1, 60 do if st.loot[id] then loot_left = true end end
  T.ok(not loot_left, "step: Loot sofort eingesammelt")
  T.eq(p.kupfer, model.mobs.kobold.kupfer, "step: Kupfer nach festem Typwert (7.3)")
  T.eq(p.plunder, 1, "step: Plunder-Zaehler")
  T.ok(saw_pickup, "step: loot_pickup-Event")
end

-- M3-2: Gnoll-Welpen am Huegelfuss (floor(N/8), GDD 9.3) --------------------
do
  local st = world.new(11)
  for i = 1, 8 do world.add_player(st, "b" .. i) end
  world.begin_try(st, {})
  local adds = 0
  for id = 100, 250 do
    if st.npcs[id] and st.npcs[id].kind == "add" then adds = adds + 1 end
  end
  T.eq(adds, model.adds(8), "step: Add-Anzahl nach Formel")
end

-- M3-2: JSON-Roundtrip fuer session.json ------------------------------------
do
  local json = require("game.json")
  local data = { try_nr = 4711, chars = { rob = { xp = 42, kupfer = 7,
    plunder = 3, ding = false }, ["gast 2"] = { xp = 0 } }, liste = { 1, 2.5, "x" } }
  local enc = json.encode(data)
  local dec, err = json.decode(enc)
  T.ok(dec ~= nil, "json: dekodierbar (" .. tostring(err) .. ")")
  T.eq(dec.try_nr, 4711, "json: Zahl")
  T.eq(dec.chars.rob.xp, 42, "json: verschachtelt")
  T.eq(dec.chars["gast 2"].xp, 0, "json: Schluessel mit Leerzeichen")
  T.eq(dec.liste[2], 2.5, "json: Liste")
  T.eq(json.encode(dec), enc, "json: kanonisch (Encode stabil)")
  local bad = json.decode('{"a": [1, 2')
  T.ok(bad == nil, "json: kaputte Datei faellt sauber durch")
end

-- M3-3: Begehbarkeits-Grid + A* — Erreichbarkeits-Beweis (GDD 14/17.7) ------
do
  local grid = require("game.gamesim.grid")
  local g, f = map.graveyard(), map.field()
  local targets = {
    { f.x, f.y, "Wiederbelebungsfeld" },
    { map.hill.x, map.hill.y, "Hogger Hill" },
  }
  for i, sp in ipairs(map.MOB_SPAWNS) do
    targets[#targets + 1] = { sp.x, sp.y, "Mob-Spawn " .. i }
  end
  for _, t in ipairs(targets) do
    local path = grid.path(g.x, g.y, t[1], t[2])
    T.ok(path ~= nil and #path >= 1, "grid: Friedhof erreicht " .. t[3])
    if path then
      local last = path[#path]
      T.ok(world.dist(last.x, last.y, t[1], t[2]) < 1,
        "grid: Pfad endet exakt am Ziel (" .. t[3] .. ")")
    end
  end
  T.ok(grid.path(-100, -100, 50, 50) == nil, "grid: ausserhalb -> kein Pfad")
end

-- M3-3: Leeroys ewiger Loop (GDD 10) ----------------------------------------
do
  local st = world.new(77)
  world.add_leeroy(st)
  world.add_player(st, "b1")
  world.add_player(st, "b2")
  local evs = {}
  world.begin_try(st, evs)
  T.eq(st.n_scale, 2, "world: Leeroy zaehlt nie in die N-Skalierung")
  bot.run(st, 200 * 60, evs)
  local leeroy_revived, screamed, stuck, lines_said = false, false, 0, 0
  for _, e in ipairs(evs) do
    if e.ev == "revive" and e.src == st.leeroy_pid then leeroy_revived = true end
    if e.ev == "leeroy_line" and e.dst == 1 then screamed = true end
    if e.ev == "leeroy_line" then lines_said = lines_said + 1 end
    if e.ev == "leeroy_stuck" then stuck = stuck + 1 end
  end
  T.ok(leeroy_revived, "leeroy: belebt sich als Krieger wieder")
  T.ok(screamed, "leeroy: DER Schrei beim Anmarsch (Zeile 1)")
  T.eq(stuck, 0, "leeroy: kein leeroy_stuck (jedes Vorkommen = Bug-Report)")
  T.ok(lines_said >= 2, "leeroy: Announcer spricht (" .. lines_said .. " Zeilen)")
  local lp = st.players[st.leeroy_pid]
  T.ok(lp.class == "warrior" or lp.class == nil,
    "leeroy: immer Krieger (fluchbedingt)")
  T.ok(lp.race == "mensch" or lp.race == nil, "leeroy: immer Mensch")
end

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

-- Faehigkeits-Spezifikationen und Klassenkits duerfen nie auseinanderlaufen:
-- die UI liest den Namen ueber denselben Slot-Index aus model.classes
-- (eine Wahrheit, Issue #28)
for _, class_id in ipairs(model.CLASS_IDS) do
  local specs = step.ABILITIES[class_id]
  local defs = model.classes[class_id].abilities
  T.ok(specs ~= nil, "ABILITIES kennt " .. class_id)
  T.eq(#specs, #defs, "gleich viele Slots wie im Modell: " .. class_id)
  for i = 1, #defs do
    T.ok(defs[i].name_de ~= nil and #defs[i].name_de > 2,
      "Slot hat einen deutschen Namen: " .. class_id .. "/" .. i)
    T.ok(specs[i] ~= nil and specs[i].id ~= nil,
      "Slot hat eine Spezifikation: " .. class_id .. "/" .. i)
  end
end
T.ok(step.ICON_RADIUS > 0, "Draufstellen-Radius fuer die UI verfuegbar")

-- Frontbogen (GDD 8.1, Issue #32): das Ziel muss vor einem liegen ----------
do
  -- Winkelrechnung: 0 = Norden, im Uhrzeigersinn
  T.eq(input.facing_towards(0, 0, 0, -100), 0, "facing: Norden ist 0")
  T.eq(input.facing_towards(0, 0, 100, 0), 64, "facing: Osten ist ein Viertel")
  T.eq(input.facing_towards(0, 0, 0, 100), 128, "facing: Sueden ist die Haelfte")
  T.ok(input.facing_ok(0, 0, 0, 0, -100, 180), "facing: direkt voraus zaehlt")
  T.ok(not input.facing_ok(0, 0, 0, 0, 100, 180), "facing: genau hinten zaehlt nicht")
  T.ok(input.facing_ok(0, 0, 0, 100, 0, 180), "facing: 90 Grad liegt im 180er-Bogen")
  T.ok(not input.facing_ok(0, 0, 0, 100, 0, 90), "facing: 90 Grad faellt aus dem 90er-Bogen")
  T.ok(input.facing_ok(0, 0, 0, 0, 100, 360), "facing: 360 schaltet die Regel ab")

  -- Autohit: derselbe Aufbau, nur die Blickrichtung entscheidet
  local function uptime(facing)
    local st = world.new(7)
    world.add_player(st, "a")
    local q = st.players[1]
    world.begin_try(st, {})
    q.alive, q.ghost = true, false
    q.class, q.race = "warrior", "mensch"
    q.max_hp, q.hp = model.hp_for_class("warrior"), model.hp_for_class("warrior")
    q.x, q.y = st.hogger.x, st.hogger.y - 20 -- Hogger liegt genau suedlich
    local hp0 = st.hogger.hp
    for _ = 1, 300 do
      st.players[1].x, st.players[1].y = st.hogger.x, st.hogger.y - 20
      step.step(st, { [1] = { mask = 0, facing = facing } })
    end
    return hp0 - st.hogger.hp
  end
  T.ok(uptime(128) > 0, "facing: zum Ziel gedreht trifft der Autohit")
  T.eq(uptime(0), 0, "facing: weggedreht geht kein Angriff durch")

  -- Wegdrehen bricht einen laufenden Cast ab
  local st = world.new(9)
  world.add_player(st, "m")
  world.begin_try(st, {})
  local q = st.players[1]
  q.alive, q.ghost = true, false
  q.class, q.race = "mage", "mensch"
  q.max_hp, q.hp = model.hp_for_class("mage"), model.hp_for_class("mage")
  q.resource = model.p("mana_max")
  q.x, q.y = st.hogger.x, st.hogger.y - 60
  step.step(st, { [1] = { mask = input.AB1, facing = 128 } })
  T.ok(q.cast ~= nil, "facing: Cast startet mit Ziel im Blick")
  step.step(st, { [1] = { mask = 0, facing = 0 } })
  T.eq(q.cast, nil, "facing: Wegdrehen bricht den laufenden Cast ab")
end

-- Leeroy wartet mit dem ersten Anmarsch auf den ersten echten Spieler
-- (GDD 10.3, Issue #33): waehrend des Intros bleibt er stehen
do
  local leeroy = require("game.gamesim.leeroy")
  local st = world.new(3)
  world.add_leeroy(st)
  world.add_player(st, "mensch")
  world.begin_try(st, {})
  local lee = st.players[st.leeroy_pid]
  for _ = 1, 60 * 20 do -- 20 s: ohne die Regel waere er laengst unterwegs
    step.step(st, {})
  end
  T.eq(st.leeroy_started, false, "Leeroy: Try-Start-Bedingung noch offen")
  -- Er belebt sich am Feld wieder (das gehoert zum Loop), nimmt aber den
  -- Pfad zum Huegel nicht auf
  T.ok(lee.ai.phase ~= "march", "Leeroy: kein Anmarsch waehrend des Intros")
  T.ok(world.dist(lee.x, lee.y, map.hill.x, map.hill.y)
       > model.p("field_to_hill_dist") * 0.9,
    "Leeroy: bleibt hinter dem Wiederbelebungsfeld")
  -- Spieler belebt sich -> Leeroy darf los
  local q = st.players[2]
  q.alive, q.ghost, q.class = true, false, "warrior"
  T.ok(leeroy.may_march(st), "Leeroy: erster Wiederbelebter gibt ihn frei")
  for _ = 1, 60 * 10 do step.step(st, {}) end
  T.ok(world.dist(lee.x, lee.y, map.hill.x, map.hill.y)
       < model.p("field_to_hill_dist") * 0.9, "Leeroy: marschiert danach los")

  -- Notbremse: niemand belebt sich, trotzdem geht es irgendwann los
  local st2 = world.new(4)
  world.add_leeroy(st2)
  world.add_player(st2, "mensch")
  world.begin_try(st2, {})
  st2.time = model.p("leeroy_first_march_wait")
  T.ok(leeroy.may_march(st2), "Leeroy: Notbremse nach der Wartezeit")
end
