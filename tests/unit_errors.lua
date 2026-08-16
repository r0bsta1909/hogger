-- tests/unit_errors.lua — Fehlermeldungen beim Faehigkeitsversuch (#56).
-- Der Host verwirft stumm; diese Regeln sagen dem Spieler warum. Sie
-- muessen mit der Sim uebereinstimmen (Ressource, Reichweite, Frontbogen).

local errors = require("game.ui.errors")
local model = require("sim.model")
local step = require("game.gamesim.step")
local world = require("game.gamesim.world")

local hogger = { x = 1000, y = 1000, hp = 500, state = "combat" }
local function ctx(x, y, facing, cd)
  return { x = x, y = y, facing = facing, cooldown = cd or 0,
           hogger = hogger, npcs = {} }
end

local warrior_heroic = step.ABILITIES.warrior[1]  -- Heroischer Stoss, Nahkampf
local mage_fireball = step.ABILITIES.mage[1]      -- Feuerball, Zauberreichweite
local rogue_evis = step.ABILITIES.rogue[2]        -- Ausweiden, braucht CP
local warrior_shout = step.ABILITIES.warrior[2]   -- Schlachtruf, auf sich selbst

local me = { class = "warrior", resource = 100, target = world.HOGGER_ID }
-- direkt am Ziel und hingedreht: kein Fehler
T.eq(errors.check(me, warrior_heroic, ctx(1000, 970, 128)), nil,
  "kein Fehler bei Reichweite und Blick")
-- zu weit weg
T.eq(errors.check(me, warrior_heroic, ctx(1000, 500, 128)), errors.TOO_FAR,
  "zu weit entfernt wird gemeldet")
-- weggedreht
T.eq(errors.check(me, warrior_heroic, ctx(1000, 970, 0)), errors.WRONG_WAY,
  "weggedreht wird gemeldet")
-- Cooldown laeuft
T.eq(errors.check(me, warrior_heroic, ctx(1000, 970, 128, 3)), errors.NOT_READY,
  "laufender Cooldown wird gemeldet")
-- kein Ziel (Hogger geleasht)
do
  local reset = { x = 1000, y = 1000, hp = 500, state = "reset" }
  local c = ctx(1000, 970, 128); c.hogger = reset
  T.eq(errors.check(me, warrior_heroic, c), errors.NO_TARGET,
    "ohne gueltiges Ziel wird das gemeldet")
end
-- Ressource fehlt (Wut)
do
  local leer = { class = "warrior", resource = 0, target = world.HOGGER_ID }
  local msg = errors.check(leer, warrior_heroic, ctx(1000, 970, 128))
  T.ok(msg and msg:find("Wut") ~= nil, "fehlende Wut wird beim Namen genannt")
end
-- Caster: Manamangel und Zauberreichweite
do
  local mage = { class = "mage", resource = 5, target = world.HOGGER_ID }
  local msg = errors.check(mage, mage_fireball, ctx(1000, 950, 128))
  T.ok(msg and msg:find("Mana") ~= nil, "fehlendes Mana wird gemeldet")
  local voll = { class = "mage", resource = 100, target = world.HOGGER_ID }
  T.eq(errors.check(voll, mage_fireball, ctx(1000, 950, 128)), nil,
    "Zauberreichweite ist groesser als Nahkampf")
  T.eq(errors.check(voll, mage_fireball, ctx(1000, 700, 128)), errors.TOO_FAR,
    "aber nicht unbegrenzt")
end
-- Combopunkte
do
  local rogue = { class = "rogue", resource = 100, cp = 0, target = world.HOGGER_ID }
  T.eq(errors.check(rogue, rogue_evis, ctx(1000, 970, 128)), errors.NO_CP,
    "Ausweiden ohne Combopunkte wird gemeldet")
end
-- Selbstbuffs brauchen weder Ziel noch Blickrichtung
do
  local w = { class = "warrior", resource = 100, target = world.HOGGER_ID }
  T.eq(errors.check(w, warrior_shout, ctx(0, 0, 0)), nil,
    "Schlachtruf geht immer (wirkt auf einen selbst)")
end
