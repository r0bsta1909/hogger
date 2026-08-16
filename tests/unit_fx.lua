-- tests/unit_fx.lua — Kampf-Effekte (GDD 4.1, Issue #30): welche Form und
-- welche Farbe ein Treffer erzeugt, haengt an Klasse und Schadensart ("art",
-- GDD 17.3). Reine Zustandslogik, kein Zeichnen — deshalb love-frei pruefbar.

local render = require("game.render")

local function fx1(class, attack, art)
  local r = render.new()
  r:add_attack_fx(class, attack, art, 0, 0, 100, 0)
  return r.fx and r.fx[1]
end

-- Caster: Zauber in Schulfarbe, Autoangriff als fahler Stab-Blitz
local fb = fx1("mage", "wand", "ability")
T.eq(fb.form, "bolt", "Feuerball ist ein Geschoss")
T.eq(fb.col[1], 1.00, "Feuerball brennt orange")
local sb = fx1("warlock", "wand", "ability")
T.ok(sb.col[3] > sb.col[2], "Schattenblitz ist violett")
local wand = fx1("priest", "wand", "autohit")
T.eq(wand.form, "bolt", "Zauberstab ist ein kleines Geschoss")
T.ok(wand.col[3] > wand.col[1], "Zauberstab bleibt fahlblau, nicht heilig")

-- Jaeger: Autoschuss ist ein Pfeil, Raptorstoss ein Nahkampfbogen (GDD 8.2)
T.eq(fx1("hunter", "shot", "autohit").form, "arrow", "Autoschuss fliegt")
T.eq(fx1("hunter", "shot", "ability").form, "slash", "Raptorstoss ist Nahkampf")

-- Nahkaempfer und Gegner
T.eq(fx1("warrior", "melee", "ability").form, "slash", "Heroischer Stoss schlaegt")
local claw = fx1(nil, nil, "autohit")
T.eq(claw.form, "slash", "Hogger schlaegt")
T.ok(claw.col[1] > 0.9 and claw.col[2] < 0.5, "Gegnerschlag ist rot")
T.eq(fx1(nil, nil, "charge").form, "charge", "Charge hat eine eigene Wucht")

-- Blutung hat keine Quelle und darf nichts zeichnen
T.eq(fx1("warrior", "melee", "dot"), nil, "Blutung erzeugt kein Geschoss")

-- Budget wie beim Floating Text (GDD 4.1): nichts laeuft ueber
do
  local r = render.new()
  for _ = 1, 200 do r:add_attack_fx("mage", "wand", "ability", 0, 0, 10, 10) end
  T.ok(#r.fx <= 61, "Effekt-Budget gedeckelt (" .. #r.fx .. ")")
end

-- Alterung: Effekte verschwinden von selbst, der Trefferrand klingt ab
do
  local r = render.new()
  r:add_attack_fx("mage", "wand", "ability", 0, 0, 10, 10)
  r:add_heal_fx(5, 5)
  r:add_hurt_flash(1.0)
  for _ = 1, 60 do r:update(1 / 60) end
  T.eq(#r.fx, 0, "Effekte laufen nach einer Sekunde aus")
  T.eq(r.hurt, 0, "Trefferrand klingt ab")
end
