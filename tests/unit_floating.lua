-- tests/unit_floating.lua — Stufe 1: der Floating Combat Text (game/ui/floating.lua)
-- ohne love: Budget, Prioritaeten und die Signatur der eigenen Wirkung
-- (Runde 21: Umriss, Aufspringen, fremde Zahlen klein).

local T = _G.T
local F = require("game.ui.floating")
local model = require("sim.model")

local f = F.new()
local own = f:add("11", 0, 0, { 1, 1, 1 }, 2, { own = true, big = true })
local auto = f:add("2", 0, 0, { 1, 1, 1 }, 2, { own = true })
local other = f:add("6", 0, 0, { 0.7, 0.7, 0.7 }, 1)
local hit_me = f:add("20", 0, 0, { 1, 0.3, 0.3 }, 2)
local crit = f:add("22!", 0, 0, { 1, 0.85, 0.2 }, 3, { own = true, big = true })
local crit_other = f:add("22!", 0, 0, { 1, 0.85, 0.2 }, 3)
local heal = f:add("+25", 0, 0, { 0.55, 1, 0.55 }, 2, { own = true, heal = true })

T.ok(own.own and own.big, "floating: eigene Faehigkeit traegt die Signatur")
T.ok(not other.own, "floating: fremde Zahl ohne Signatur")
T.near(F.scale_of(own), F.SCALE_OWN_BIG, "floating: eigene Faehigkeit springt gross auf")
f:update(F.POP_T)
T.near(F.scale_of(own), F.SCALE_OWN_REST, "floating: ... und landet auf der Ruhegroesse")
T.near(F.scale_of(auto), F.SCALE_OWN_AUTO, "floating: eigener Autohit kleiner als die Faehigkeit")
T.ok(F.scale_of(auto) < F.scale_of(own), "floating: bewusste Taste sticht heraus")
T.near(F.scale_of(other), F.SCALE_OTHER, "floating: fremde Zahl klein")
T.ok(F.scale_of(other) < F.scale_of(auto), "floating: fremd kleiner als eigener Autohit")
T.near(F.scale_of(hit_me), 1.5, "floating: erlittener Schaden wie bisher 1,5-fach")
T.near(F.scale_of(crit), F.SCALE_CRIT_OWN, "floating: eigener Krit am groessten")
T.ok(F.scale_of(crit) > F.scale_of(own), "floating: eigener Krit groesser als eigene Faehigkeit")
T.near(F.scale_of(crit_other), 2.0, "floating: fremder/erlittener Krit bleibt 2,0")
T.near(F.scale_of(heal), F.SCALE_OWN_HEAL, "floating: eigene Heilung bleibt bei 1,5 (der gruene Ring reicht)")
T.ok(F.scale_of(heal) <= F.scale_of(auto), "floating: Heilung nicht groesser als eigener Autohit-Schaden")
T.ok(F.SCALE_OWN_BIG >= 2.5 and F.SCALE_OWN_REST >= 1.8, "floating: eigener Schaden deutlich groesser (Rob, v0.21.1)")

-- Budget: fremde Zahlen werden von eigenen verdraengt, nie umgekehrt
local g = F.new()
for _ = 1, model.p("floating_text_max") do g:add("1", 0, 0, { 1, 1, 1 }, 1) end
local n0 = #g.items
local mine = g:add("9", 0, 0, { 1, 1, 1 }, 2, { own = true, big = true })
T.ok(mine ~= nil and #g.items == n0, "floating: eigene Zahl verdraengt eine fremde im vollen Budget")
local dropped = g:add("1", 0, 0, { 1, 1, 1 }, 1)
T.eq(dropped, nil, "floating: fremde Zahl wird im vollen Budget still verworfen")

-- Ablauf: nach der Dauer ist alles weg
g:update(model.p("floating_text_duration") + 0.01)
T.eq(#g.items, 0, "floating: nach der Dauer geleert")
