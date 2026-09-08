-- tests/unit_bot.lua — Stufe 1: das Bot-Gehirn (game/gamesim/bot.lua, Runde 20).
-- Die Bots sind der Referenz-Raid, gegen den balanciert wird — was sie
-- koennen und was nicht, ist damit Balancing-Wahrheit und gehoert getestet.

local T = _G.T
local bot = require("game.gamesim.bot")
local world = require("game.gamesim.world")
local input = require("game.gamesim.input")
local model = require("sim.model")
local map = require("game.data.map")

local function has(mask, bit) return mask % (bit * 2) >= bit end

-- Welt mit n lebenden Bots einer Klasse nahe Hogger
local function arena(n, class, profile, seed)
  local st = world.new(seed or 3)
  world.add_leeroy(st)
  for i = 1, n do
    world.add_player(st, "b" .. i, { quest_done = true, profile = profile or "typisch" })
  end
  world.begin_try(st, {})
  local h = st.hogger
  h.state = "combat"; h.engaged = true
  for _, p in ipairs(st.players) do
    if not p.is_leeroy then
      p.alive, p.ghost, p.class = true, false, class
      p.max_hp = model.hp_for_class(class); p.hp = p.max_hp
      p.resource = 100
      p.x, p.y = h.x + 30, h.y
    end
  end
  return st, h
end

-- Reaktionszeit deterministisch aus Seed und pid, im menschlichen Fenster
do
  local a = bot.new_brain(42, 5, "typisch")
  local b = bot.new_brain(42, 5, "typisch")
  local c = bot.new_brain(42, 6, "typisch")
  T.near(a.react, b.react, "brain: gleicher Seed+pid -> gleiche Reaktionszeit")
  T.ok(a.react ~= c.react, "brain: andere pid -> andere Reaktionszeit")
  T.ok(a.react >= 1.0 and a.react <= 2.0, "brain: Reaktionszeit 1-2 s")
  T.eq(bot.DEFAULT_PROFILE, "typisch", "brain: Standardprofil ist der typische Raid")
end

-- Kein Nachlaufen waehrend eines Casts: Bewegung braeche ihn
do
  local st, h = arena(1, "mage")
  local p = st.players[2]
  p.x = h.x + model.p("cast_range") + 200 -- weit ausserhalb
  p.cast = { slot = 1, t_left = 1, total = 2 }
  local dec = bot.decide(st, p.id)
  T.eq(dec.mask % 16, 0, "typisch: waehrend des Casts keine Bewegung")
  p.cast = nil
  p.brain.cached = nil
  dec = bot.decide(st, p.id)
  T.ok(dec.mask % 16 > 0, "typisch: ohne Cast laeuft der Magier heran")
end

-- Reichweite halten: wer drinsteht, laeuft nicht weiter auf Hogger zu
do
  local st, h = arena(1, "hunter")
  local p = st.players[2]
  p.x = h.x + model.p("autoshot_range") * 0.8
  local dec = bot.decide(st, p.id)
  T.eq(dec.mask % 16, 0, "typisch: Jaeger in Reichweite bleibt stehen")
  T.ok(dec.engage == true, "typisch: Jaeger schaltet den Autoschuss an (Rechtsklick)")
end

-- Tritt: erst nach der Reaktionszeit, und nur in Schlagweite
do
  local st, h = arena(2, "rogue", "typisch", 11)
  local p = st.players[2]
  h.eating = { phase = "channel", t_left = 6 }
  st.time = 100
  local dec = bot.decide(st, p.id)
  T.ok(not dec.kick, "typisch: kein Tritt im ersten Moment des Kanals")
  st.time = 100 + p.brain.react + 0.05
  st.tick = st.tick + 10; p.brain.cached = nil
  dec = bot.decide(st, p.id)
  T.ok(dec.kick == true, "typisch: Tritt nach der Reaktionszeit")
  -- ausser Schlagweite: kein Tritt, aber der Kicker laeuft hin
  p.x = h.x + 200
  st.tick = st.tick + 10; p.brain.cached = nil
  dec = bot.decide(st, p.id)
  T.ok(not dec.kick, "typisch: ausser Schlagweite kein Tritt")
  T.ok(dec.mask % 16 > 0, "typisch: der Kicker laeuft zum Fressen hin")
  h.eating = nil
  st.tick = st.tick + 10; p.brain.cached = nil
  bot.decide(st, p.id)
  T.eq(p.brain.eat_seen_t, nil, "typisch: Kanal vorbei, Gedaechtnis geloescht")
end

-- Der Kicker (kleinste pid unter den lebenden Schurken) haelt Energie zurueck
do
  local st, h = arena(2, "rogue", "typisch", 11)
  local kicker, other = st.players[2], st.players[3]
  kicker.resource, other.resource = 50, 50
  st.tick = 100
  local d1 = bot.decide(st, kicker.id)
  local d2 = bot.decide(st, other.id)
  T.ok(not has(d1.mask, input.AB1), "typisch: Kicker spart bei 50 Energie fuer den Tritt")
  T.ok(has(d2.mask, input.AB1), "typisch: der zweite Schurke schlaegt normal zu")
  kicker.resource = 100
  st.tick = st.tick + 30; kicker.brain.cached = nil
  d1 = bot.decide(st, kicker.id)
  T.ok(has(d1.mask, input.AB1), "typisch: mit voller Energie schlaegt auch der Kicker")
end

-- Faehigkeits-Bits sind Flanken: hoechstens alle 0,5 s, dazwischen nicht
do
  local st = arena(1, "warrior")
  local p = st.players[2]
  p.resource = 100; p.shout_until = 1e9 -- Schlachtruf steht
  st.tick = 300
  local d = bot.decide(st, p.id)
  T.ok(has(d.mask, input.AB1), "typisch: Krieger drueckt Heroischen Stoss")
  st.tick = 303; d = bot.decide(st, p.id)
  T.ok(not has(d.mask, input.AB1), "typisch: kurz danach kein zweiter Druck")
  st.tick = 330; d = bot.decide(st, p.id)
  T.ok(has(d.mask, input.AB1), "typisch: nach 0,5 s wieder")
end

-- Krieger ohne Schlachtruf ruft zuerst
do
  local st = arena(1, "warrior")
  local p = st.players[2]
  p.resource = 100; p.shout_until = 0
  st.tick = 300
  local d = bot.decide(st, p.id)
  T.ok(has(d.mask, input.AB2), "typisch: Krieger ohne Buff ruft den Schlachtruf")
end

-- Magier legt beim ersten Zug die Frostruestung an
do
  local st = arena(1, "mage")
  local p = st.players[2]
  p.x = st.hogger.x + 100
  st.tick = 300
  local d = bot.decide(st, p.id)
  T.ok(has(d.mask, input.AB2), "typisch: Magier ohne Frostruestung legt sie an")
  p.frost_armor = true
  st.tick = 330; p.brain.cached = nil
  d = bot.decide(st, p.id)
  T.ok(has(d.mask, input.AB1), "typisch: mit Frostruestung kommt der Feuerball")
end

-- Bedarfsgesteuerte Klassenwahl: fehlt der Schurke, wird einer
do
  local st = world.new(5)
  world.add_leeroy(st)
  for i = 1, 10 do world.add_player(st, "g" .. i, { quest_done = true, profile = "typisch" }) end
  world.begin_try(st, {})
  -- alle lebend als Jaeger, nur pid 2 ist Geist
  for _, p in ipairs(st.players) do
    if not p.is_leeroy then p.alive, p.ghost, p.class = true, false, "hunter" end
  end
  local g = st.players[2]
  g.alive, g.ghost = false, true
  T.eq(bot.choose_class(st, g), "rogue", "bedarf: ohne Schurken wird der Geist Schurke")
  -- zwei Schurken da, keine Heiler: der naechste wird Heiler
  st.players[3].class, st.players[4].class = "rogue", "rogue"
  local cls = bot.choose_class(st, g)
  T.ok(cls == "priest" or cls == "paladin" or cls == "druid",
    "bedarf: mit Schurken, aber ohne Heiler wird der Geist Heiler (" .. tostring(cls) .. ")")
  -- alles gedeckt: der Geist bleibt, was er war
  st.players[5].class, st.players[6].class = "priest", "druid"
  g.class = "warrior"
  T.eq(bot.choose_class(st, g), "warrior", "bedarf: alles gedeckt -> Klasse behalten")
  local t = bot.role_targets(40)
  T.ok(t.rogue == 4 and t.healer == 7 and t.ranged == 14, "bedarf: Rollenziele bei N=40")
  local t5 = bot.role_targets(5)
  T.ok(t5.rogue == 2 and t5.healer == 2 and t5.ranged == 2, "bedarf: bei N=5 zwei Schurken, zwei Heiler")
end

-- Zwei Geister ziehen in pid-Reihenfolge: nicht beide dieselbe Luecke
do
  local st = world.new(5)
  world.add_leeroy(st)
  for i = 1, 6 do world.add_player(st, "g" .. i, { quest_done = true, profile = "typisch" }) end
  world.begin_try(st, {})
  for _, p in ipairs(st.players) do
    if not p.is_leeroy then p.alive, p.ghost, p.class = true, false, "warrior" end
  end
  local a, b = st.players[2], st.players[3]
  a.alive, a.ghost, b.alive, b.ghost = false, true, false, true
  local ca = bot.choose_class(st, a)
  local cb = bot.choose_class(st, b)
  T.ok(ca ~= cb or ca == "rogue" and bot.role_targets(6).rogue >= 2,
    "bedarf: zwei Geister fuellen verschiedene Luecken (" .. ca .. "/" .. cb .. ")")
  -- Die Wahl wird je Geisterlauf gemerkt: erst der Icon-Lauf, kein Pendeln
  local d = bot.decide(st, a.id)
  local chosen = a.brain.ghost_choice
  T.ok(chosen ~= nil, "bedarf: Geist merkt sich seine Wahl")
  st.players[4].class = chosen -- jemand anders wird dasselbe
  st.tick = st.tick + 10; a.brain.cached = nil
  bot.decide(st, a.id)
  T.eq(a.brain.ghost_choice, chosen, "bedarf: die Wahl bleibt trotz veraenderter Lage")
  T.ok(d.mask % 16 > 0, "bedarf: der Geist laeuft zum Icon")
end

-- kopflos: Klasse fest, kein Gedaechtnis, Tritt sofort
do
  local st, h = arena(1, "rogue", "kopflos")
  local p = st.players[2]
  h.eating = { phase = "channel", t_left = 6 }
  local d = bot.decide(st, p.id)
  T.ok(not d.kick, "kopflos: ignoriert das Fressen (unkoordinierter Raid, GDD 17.2)")
  T.eq(p.brain and p.brain.profile, "kopflos", "kopflos: Profil am Gehirn")
  p.alive, p.ghost, p.class = false, true, nil
  d = bot.decide(st, p.id)
  local ix = world.class_icon_pos(((p.id - 1) % #world.CLASSES) + 1)
  T.ok(ix ~= nil and d.facing ~= nil, "kopflos: Geist laeuft zum festen Icon")
end

-- turtle: nur Heilerklassen, kein Angriff, kein Anschalten
do
  local st = world.new(9)
  world.add_leeroy(st)
  for i = 1, 3 do world.add_player(st, "t" .. i, { quest_done = true, profile = "turtle" }) end
  world.begin_try(st, {})
  for _, p in ipairs(st.players) do
    if not p.is_leeroy then
      local d = bot.decide(st, p.id)
      local cls = p.brain.ghost_choice
      T.ok(cls == "priest" or cls == "paladin" or cls == "druid",
        "turtle: waehlt eine Heilerklasse (" .. tostring(cls) .. ")")
    end
  end
  local p = st.players[2]
  p.alive, p.ghost, p.class = true, false, "priest"
  p.max_hp, p.hp, p.resource = 50, 50, 100
  p.x, p.y = st.hogger.x + 100, st.hogger.y
  st.tick = 300; p.brain.cached = nil
  local d = bot.decide(st, p.id)
  T.ok(not has(d.mask, input.AB1) and not has(d.mask, input.AB2) and not has(d.mask, input.AB3),
    "turtle: drueckt keine Faehigkeit")
  T.ok(not d.engage, "turtle: schaltet keinen Autoangriff an")
end

-- Ein Mob, der mich angreift, wird Ziel
do
  local st, h = arena(1, "warrior")
  local p = st.players[2]
  local npc = world.add_npc(st, "wolf", p.x + 20, p.y, 10)
  npc.state = "combat"; npc.target_pid = p.id
  st.tick = 300
  local d = bot.decide(st, p.id)
  T.eq(d.target, npc.id, "typisch: der angreifende Wolf wird Ziel")
end

-- Ohne Seed im Zustand (Snapshot-Sicht der Stufe-4-Clients): kopflos,
-- aber ohne Fehler
do
  local st = arena(1, "hunter")
  local p = st.players[2]
  local view = { players = { [p.id] = p }, hogger = st.hogger, tick = st.tick }
  p.brain = nil
  local d = bot.decide(view, p.id)
  T.ok(type(d.mask) == "number", "snapshot-sicht: Bot entscheidet ohne Gehirn")
end

-- Rasterpunkte "typisch ohne X" (Runde 21, Player-Agency-Analyse): bot.SKIP
-- ist ein reines Sim-Werkzeug — im Spiel leer — und muss genau die eine
-- Faehigkeit/Entscheidung abschalten, nichts sonst.
do
  T.eq(next(bot.SKIP), nil, "SKIP: im Spiel leer")
  -- ohne Tritt tritt der Kicker nie, auch nach der Reaktionszeit
  local st, h = arena(2, "rogue")
  local p = st.players[2]
  h.eating = { phase = "channel", t_left = 8, corpse = 1, heal_tick = 0 }
  bot.SKIP = { kick = true }
  local kicked = false
  for _ = 1, 60 * 3 do
    st.tick = st.tick + 1; st.time = st.tick * model.TICK_DT
    local dec = bot.decide(st, p.id)
    if dec.kick then kicked = true end
  end
  T.ok(not kicked, "SKIP.kick: der Kicker tritt nie")
  bot.SKIP = {}
  p.brain = nil
  for _ = 1, 60 * 3 do
    st.tick = st.tick + 1; st.time = st.tick * model.TICK_DT
    local dec = bot.decide(st, p.id)
    if dec.kick then kicked = true end
  end
  T.ok(kicked, "SKIP leer: der Kicker tritt nach seiner Reaktionszeit")
  h.eating = nil

  -- ohne Bedarfswahl nimmt der Geist die feste Klasse pid mod 8
  local st2 = arena(3, "mage")
  local g = st2.players[3]
  g.alive, g.ghost, g.class = false, true, "mage"
  g.brain = nil
  bot.SKIP = { needclass = true }
  bot.decide(st2, g.id)
  T.eq(g.brain.ghost_choice, world.CLASSES[((g.id - 1) % #world.CLASSES) + 1],
       "SKIP.needclass: Klasse fest pid mod 8")
  bot.SKIP = {}
  g.brain = nil
  bot.decide(st2, g.id)
  T.eq(g.brain.ghost_choice, "rogue", "SKIP leer: ohne Schurken waehlt der Geist Schurke")

  -- jeder Schluessel aus SKIP_KEYS ist bekannt und laeuft ohne Fehler durch
  for _, key in ipairs(bot.SKIP_KEYS) do
    bot.SKIP = { [key] = true }
    local st3 = arena(1, "warrior")
    local ok = pcall(bot.decide, st3, st3.players[2].id)
    T.ok(ok, "SKIP." .. key .. ": Entscheidung laeuft")
  end
  bot.SKIP = {}
end
