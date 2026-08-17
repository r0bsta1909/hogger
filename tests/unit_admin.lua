-- tests/unit_admin.lua — Admin-Werkzeuge im F12-Overlay (GDD 4.4,
-- Issues #35/#36). Sie sind Werkzeug, kein Spielinhalt — trotzdem muessen
-- sie tun, was draufsteht, sonst kostet das auf der LAN Nerven.

local model = require("sim.model")
local world = require("game.gamesim.world")
local step = require("game.gamesim.step")
local debugui = require("game.ui.debug")

-- Hogger sofort toeten loest den regulaeren Sieg-Pfad aus (#35)
do
  local st = world.new(11)
  world.add_leeroy(st)
  world.add_player(st, "rob", { quest_done = true })
  world.begin_try(st, {})
  T.ok(st.hogger.hp > 0, "Admin: Hogger lebt zu Beginn")
  T.eq(step.admin_kill_hogger(st), true, "Admin: Kill greift im laufenden Try")
  local evs = step.step(st, {})
  local won, board = nil, nil
  for _, e in ipairs(evs) do
    if e.ev == "try_end" then won, board = e.val, e.board end
  end
  T.eq(won, 1, "Admin: try_end meldet den Sieg")
  T.ok(board ~= nil and board.header:find("^SIEG") ~= nil,
    "Admin: Statistik-Tafel kommt als Sieg-Tafel")
  T.eq(st.phase, "won", "Admin: Fluchbruch-Phase laeuft")
  T.eq(step.admin_kill_hogger(st), false, "Admin: zweiter Kill prallt ab")
  -- danach ist REVANCHE moeglich (GDD 11) — die Kette bleibt testbar
  T.eq(step.revanche(st, {}), true, "Admin: REVANCHE nach dem Kill moeglich")
end

-- Tastenbelegung des Overlays: geschlossen schluckt es nichts
do
  local d = debugui.new()
  T.eq(d:keypressed("k"), false, "Overlay geschlossen: K geht ins Spiel")
  d:toggle()
  T.eq(d:keypressed("k"), "kill", "Overlay: K toetet Hogger")
  T.eq(d:keypressed("r"), "intro", "Overlay: R spielt das Intro erneut")
  T.eq(d:keypressed("z"), "realm", "Overlay: Z startet den Realm neu")
  T.eq(d:keypressed("t"), "teleport", "Overlay: T teleportiert vor Hogger")
  T.eq(d:keypressed("h"), "host", "Overlay: H erzwingt den Host")
  T.eq(d:keypressed("n"), "wipe", "Overlay: N loescht die Session")
  T.eq(d:keypressed("q"), true, "Overlay: fremde Tasten werden geschluckt")
  d:keypressed("escape")
  T.eq(d.visible, false, "Overlay: Escape schliesst")
end

-- Teleport vor Hogger (Runde 6, Issue #100): sofort lebendig als Klasse
-- der Rotation, kurz AUSSERHALB der Aggro-Range, Quest implizit angenommen
do
  local world2 = require("game.gamesim.world")
  local st = world2.new(13)
  world2.add_player(st, "rob", {}) -- Quest noch NICHT angenommen
  world2.begin_try(st, {})
  local p = st.players[1]
  T.eq(p.alive, false, "Teleport: Spieler startet tot am Friedhof")
  T.eq(step.admin_teleport(st, 1), true, "Teleport: greift")
  T.ok(p.alive and not p.ghost, "Teleport: sofort lebendig")
  T.ok(p.class ~= nil and model.classes[p.class] ~= nil,
    "Teleport: gueltige Klasse (" .. tostring(p.class) .. ")")
  T.eq(p.hp, model.hp_for_class(p.class), "Teleport: volle HP")
  T.eq(p.quest, 2, "Teleport: Quest gilt als angenommen (Bewegung frei)")
  local d = world2.dist(p.x, p.y, st.hogger.x, st.hogger.y)
  T.ok(d > model.p("hogger_aggro_radius"),
    string.format("Teleport: ausserhalb der Aggro-Range (%.0f px)", d))
  T.ok(d < model.p("hogger_aggro_radius") + 120,
    "Teleport: aber nicht weit weg davon")
  T.eq(step.admin_teleport(st, 99), false, "Teleport: unbekannte pid prallt ab")
  st.hogger.hp = 0
  T.eq(step.admin_teleport(st, 1), false, "Teleport: ohne lebenden Hogger sinnlos")
end
