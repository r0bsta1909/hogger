-- game/test/drawtest.lua — Stufe 4b: der Renderer wird tatsaechlich AUSGEFUEHRT.
-- Aufruf: love game --drawtest   (braucht ein Fenster, laeuft also nicht unter
-- --headless; dort ist das Grafikmodul abgeschaltet.)
--
-- Warum es diesen Test gibt (Runde 15, #187): In Runde 14 hat ein Refactoring
-- eine lokale Variable entfernt, die zwanzig Zeilen weiter unten noch benutzt
-- wurde. Der Fehler lag im Zweig "lebender Spieler mit Klasse" — also in JEDEM
-- Spielmoment nach einer Wiederbelebung. Trotzdem war alles gruen: Stufe 1 und
-- 3 sind love-frei und rufen den Renderer nie auf, Stufe 4 laeuft ohne
-- Grafikmodul, und die Screenshot-Gegenproben erwischten den Bot-Spieler
-- zufaellig immer als Geist oder Leiche. Ein Fehler, den kein Test finden
-- kann, ist nur eine Frage der Zeit — dieser Test fuehrt den Zeichencode fuer
-- jede Klasse und jeden Zustand einmal aus und faellt bei jedem Lua-Fehler.
--
-- Die Sichten kommen NICHT von Hand, sondern durch den echten Codec
-- (wire.snapshot_body -> read_snapshot): so prueft der Test nebenbei, dass
-- Renderer und Wire-Format dieselben Felder meinen.

local model = require("sim.model")
local world = require("game.gamesim.world")
local step = require("game.gamesim.step")
local wire = require("game.net.wire")

local T = {}

local fehler, geprueft = {}, 0

local function versuch(label, fn)
  geprueft = geprueft + 1
  local ok, err = pcall(fn)
  if not ok then
    fehler[#fehler + 1] = label .. ": " .. tostring(err)
    print("FEHLER  " .. label .. ": " .. tostring(err))
  end
end

-- Welt mit allen acht Klassen, lebendig, am Boss ---------------------------
local function baue_welt()
  local st = world.new(4242)
  for i, class in ipairs(model.CLASS_IDS) do
    world.add_player(st, "test" .. i, { quest_done = true })
  end
  world.begin_try(st, {})
  for i, class in ipairs(model.CLASS_IDS) do
    local p = st.players[i]
    p.alive, p.ghost, p.dead_until = true, false, 0
    p.class, p.race = class, model.classes[class].races[1]
    p.max_hp = model.hp_for_class(class)
    p.hp = p.max_hp * (0.3 + 0.1 * i)
    p.resource = 60
    p.x = st.hogger.x + 30 + i * 12
    p.y = st.hogger.y + (i % 3) * 15
    p.xp = 120
    p.kupfer, p.plunder = 37, 2
    p.cp = (i % (model.CP_MAX + 1))
    p.target = world.HOGGER_ID
    st.hogger.threat[p.id] = i * 10
  end
  -- Umgebung: Mobs (einer gewurzelt), Wichtel, Leiche, Beute
  local wolf = world.add_npc(st, "wolf", st.hogger.x + 120, st.hogger.y, 10)
  wolf.spawn_x, wolf.spawn_y = wolf.x, wolf.y
  wolf.rooted_until = st.time + 4
  local add = world.add_npc(st, "add", st.hogger.x - 90, st.hogger.y + 40, 12)
  add.spawn_x, add.spawn_y = add.x, add.y
  local imp = world.add_npc(st, "imp", st.hogger.x + 60, st.hogger.y - 40, 5)
  imp.spawn_x, imp.spawn_y = imp.x, imp.y
  imp.owner = st.players[7].id
  st.corpses[#st.corpses + 1] = { x = st.hogger.x + 20, y = st.hogger.y + 20,
                                  pid = st.players[1].id, t = st.time }
  if st.loot then
    -- t = Verfallszeit; ohne sie stolpert der Beute-Tick (step.lua)
    st.loot[1] = { id = 1, x = st.hogger.x - 40, y = st.hogger.y + 60,
                   t = 30, kupfer = 7 }
  end
  st.hogger.state = "combat"
  st.hogger.engaged = true
  st.hogger.target = st.players[1].id
  return st
end

-- Achtung: read_snapshot(data, OFFSET) — die 4 ueberspringt den 3-Byte-Kopf.
-- Der zweite Parameter ist NICHT die Spieler-ID (die setzen wir unten selbst).
local function sicht(st, pid)
  local body = wire.snapshot_body(st)
  local _, snap = wire.read_snapshot(wire.snapshot(0, body), 4)
  snap.me = pid
  local me = snap.players[pid]
  snap.me_x, snap.me_y = me and me.x or 0, me and me.y or 0
  snap.names = {}
  for id in pairs(snap.players) do snap.names[id] = "Spieler" .. id end
  return snap
end

-- ---------------------------------------------------------------------------
function T.run()
  print("== Stufe 4b: Zeichentest (Renderer wird ausgefuehrt) ==")
  local render = require("game.render").new()
  render.docked = true
  local w, h = love.graphics.getDimensions()
  local st = baue_welt()

  -- Mausposition wandert ueber alles, was einen Tooltip hat
  local L = render.layout(w, h, true)
  local maus_orte = {
    { "keine Maus", nil },
    { "ueber der Karte", { L.ox, L.oy } },
    { "ueber der XP-Leiste", { L.ox, L.oy - L.radius + 8 } },
    { "ueber dem Bedrohungsbogen", { L.ox, L.oy + L.radius - 14 } },
    { "ueber der Combopunkt-Leiste", { L.frames.cp.x + 4, L.frames.cp.y + 8 } },
    { "ueber den eigenen Auren", { L.frames.buffs_self.x + 14, L.frames.buffs_self.y + 14 } },
    { "ueber den Ziel-Auren", { L.frames.buffs.x + 14, L.frames.buffs.y + 14 } },
    { "ueber der Heil-Leiste", { L.frames.healbar.x + 20, L.frames.healbar.y + 30 } },
    { "ueber dem Zoom-Plus", { L.zoom.plus.x, L.zoom.plus.y } },
    { "ueber dem Zoom-Minus", { L.zoom.minus.x, L.zoom.minus.y } },
  }

  for klasse_i, class in ipairs(model.CLASS_IDS) do
    local pid = klasse_i
    local view = sicht(st, pid)

    for _, ort in ipairs(maus_orte) do
      versuch(class .. " / " .. ort[1], function()
        render:draw(view, { facing_angle = 0.5, cooldowns = { 0.3, 0, 0.8, 0.1 },
                            mouse = ort[2] })
      end)
    end

    -- jeder Faehigkeitsbutton einmal unter der Maus: der Tooltip-Bau ist
    -- der Zweig, der die meisten Modellwerte anfasst
    for _, e in ipairs(render.ability_slots(L, class)) do
      versuch(class .. " / Tooltip Slot " .. e.slot, function()
        render:draw(view, { facing_angle = 0, cooldowns = { 0, 0, 0, 0 },
                            mouse = { e.x, e.y } })
      end)
    end

    versuch(class .. " / Raid-Overview", function()
      render:draw_raid_overview(view, w, h)
    end)
  end

  -- Zustaende, die im Zeichencode eigene Zweige haben ----------------------
  local zustaende = {
    { "Geist", function(p) p.alive, p.ghost = false, true end },
    { "tot (Leiche)", function(p) p.alive, p.ghost, p.dead_until = false, false, 8 end },
    { "verstohlen", function(p) p.stealth = true end },
    { "totgestellt", function(p) p.feign_until = 99 end },
    { "geschildet", function(p) p.shield_hp, p.shield_until = 20, 99 end },
    { "Schwache Seele", function(p) p.weak_soul_until = 99 end },
    { "Blutpakt", function(p) p.pact = true end },
    { "blutend", function(p) p.bleed_until = 99 end },
    { "Handauflegung verbraucht", function(p) p.loh_used = true end },
    { "im Cast", function(p) p.cast = { id = "fireball", t_left = 1, total = 2, slot = 1 } end },
    { "springt", function(p) p.jump_until = 99 end },
    { "Schlachtruf", function(p) p.shout_until = 99 end },
    { "voller Bedrohung", function(p) end, threat = true },
  }
  for _, z in ipairs(zustaende) do
    local frisch = baue_welt()
    local p = frisch.players[4] -- Schurke: hat alle vier Slots
    z[2](p)
    if z.threat then
      for id in pairs(frisch.hogger.threat) do frisch.hogger.threat[id] = 1 end
      frisch.hogger.threat[p.id] = 999
    end
    step.step(frisch, {}) -- Flags/Bedrohungsanteil einmal frisch rechnen
    local view = sicht(frisch, p.id)
    versuch("Zustand: " .. z[1], function()
      render:draw(view, { facing_angle = 1.2, cooldowns = { 0, 0.5, 0, 0 },
                          mouse = { L.ox + 40, L.oy + 40 } })
    end)
  end

  -- Hogger-Zustaende
  local hogger_zustaende = {
    { "frisst", function(s) s.hogger.eating = { phase = "channel", t_left = 5,
        corpse = 1, total = 8 }; s.hogger.state = "eating" end },
    { "chargt", function(s) s.hogger.charge = { target = 1, t_left = 0.5,
        total = 0.8 } end },
    { "tot", function(s) s.hogger.hp = 0 end },
    { "trabt heim", function(s) s.hogger.state = "reset" end },
    { "verlangsamt", function(s) s.hogger.slow_until = 99 end },
    { "gespottet", function(s) s.hogger.taunt = { pid = 1, until_t = 99 } end },
  }
  for _, hz in ipairs(hogger_zustaende) do
    local frisch = baue_welt()
    hz[2](frisch)
    local view = sicht(frisch, 4)
    versuch("Hogger: " .. hz[1], function()
      render:draw(view, { facing_angle = 0, cooldowns = { 0, 0, 0, 0 },
                          mouse = { L.ox, L.oy } })
    end)
  end

  -- Ansage-Banner und Sprechblase (Runde 15, #189)
  do
    local frisch = baue_welt()
    local view = sicht(frisch, 4)
    local texte = {
      "HOGGER FRISST!",
      "Echo: Der Geistheiler? Der funktioniert nicht mehr. Frag nicht.",
      string.rep("sehr langer text ", 12),
      "",
    }
    for _, txt in ipairs(texte) do
      render:announce(txt, 3)
      versuch("Banner: " .. (#txt > 0 and txt:sub(1, 24) or "(leer)"), function()
        render:draw(view, { facing_angle = 0, cooldowns = { 0, 0, 0, 0 } })
      end)
    end
    render:bubble("LEEEEROOOY JENKINS!", 3, "leeroy")
    versuch("Sprechblase am Raid-Leeroy", function()
      render:draw(view, { facing_angle = 0, cooldowns = { 0, 0, 0, 0 } })
    end)
    render:bubble("Ein Monolog des Echos, laenger als eine Zeile.", 3)
    versuch("Sprechblase am Echo", function()
      render:draw(view, { facing_angle = 0, cooldowns = { 0, 0, 0, 0 } })
    end)
    render.banner_t, render.bubble_t = 0, 0
  end

  -- Zoomstufen und Fenstergroessen
  for zoom = 1, 3 do
    local frisch = baue_welt()
    local view = sicht(frisch, 4)
    render.zoom = zoom
    versuch("Zoomstufe " .. zoom, function()
      render:draw(view, { facing_angle = 0, cooldowns = { 0, 0, 0, 0 } })
    end)
  end
  render.zoom = 1
  for _, dock in ipairs({ true, false }) do
    render.docked = dock
    local frisch = baue_welt()
    local view = sicht(frisch, 4)
    versuch("HUD " .. (dock and "angedockt" or "in den Ecken"), function()
      render:draw(view, { facing_angle = 0, cooldowns = { 0, 0, 0, 0 },
                          mouse = { 40, 40 } })
    end)
  end
  render.docked = true

  -- F10-Schalter aus: die Buttons verschwinden, der Rest muss stehen
  do
    local schalter = { "rogue_stealth_enabled", "paladin_loh_enabled",
                       "priest_pws_enabled", "hunter_feign_enabled",
                       "druid_roots_enabled", "warlock_pact_enabled",
                       "ui_threat_meter" }
    for _, key in ipairs(schalter) do model.params[key].wert = 0 end
    for i, class in ipairs(model.CLASS_IDS) do
      local frisch = baue_welt()
      local view = sicht(frisch, i)
      versuch("alle F10-Schalter aus / " .. class, function()
        render:draw(view, { facing_angle = 0, cooldowns = { 0, 0, 0, 0 },
                            mouse = { L.ox, L.oy + L.ring_r } })
      end)
    end
    for _, key in ipairs(schalter) do model.params[key].wert = 1 end
  end

  local bericht = string.format("%d Zeichenlaeufe, %d Fehler", geprueft, #fehler)
  print(bericht)
  -- Auch als Datei: unter Windows kommt stdout aus einem LOEVE-Fenster nicht
  -- zuverlaessig beim Aufrufer an (Speicherordner, GDD 17.3-Nachbarschaft)
  local nl = string.char(10)
  love.filesystem.write("drawtest.txt",
    bericht .. nl .. table.concat(fehler, nl))
  return (#fehler == 0) and 0 or 1
end

return T
