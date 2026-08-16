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
  world.add_player(st, "rob")
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
  T.eq(d:keypressed("h"), "host", "Overlay: H erzwingt den Host")
  T.eq(d:keypressed("n"), "wipe", "Overlay: N loescht die Session")
  T.eq(d:keypressed("q"), true, "Overlay: fremde Tasten werden geschluckt")
  d:keypressed("escape")
  T.eq(d.visible, false, "Overlay: Escape schliesst")
end
