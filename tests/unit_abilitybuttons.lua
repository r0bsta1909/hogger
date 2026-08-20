-- tests/unit_abilitybuttons.lua — Stufe 1: die Faehigkeitsbuttons am Ring
-- sind seit Runde 14 (#172) anklickbar. Die Sitzplatz-Rechnung lag vorher
-- inline im Zeichencode; jetzt ist sie love-frei und wird von Zeichnen UND
-- Klicken benutzt — genau deshalb ist sie hier pruefbar.

local render = require("game.render")
local model = require("sim.model")
local T = _G.T

local L = render.layout(1280, 800, true)

-- Sitzplaetze: so viele wie die Klasse Faehigkeiten hat --------------------
do
  local warrior = render.ability_slots(L, "warrior")
  T.eq(#warrior, 3, "buttons: der Krieger hat drei Faehigkeiten")
  local rogue = render.ability_slots(L, "rogue")
  T.eq(#rogue, 4, "buttons: der Schurke hat vier (Tritt als Slot 4)")
  local hunter = render.ability_slots(L, "hunter")
  T.eq(#hunter, 2, "buttons: der Jaeger hat zwei")

  -- Slot 1 liegt links von Slot 2 (Tastenreihenfolge, GDD 4.2)
  T.ok(rogue[1].x < rogue[2].x, "buttons: Slot 1 links von Slot 2")
  T.ok(rogue[2].x < rogue[3].x, "buttons: ... und weiter aufsteigend")
  T.eq(rogue[1].slot, 1, "buttons: der erste Sitzplatz traegt Slot 1")
  T.eq(rogue[4].slot, 4, "buttons: der letzte traegt Slot 4")

  -- alle auf der Ringbahn, unten mittig
  for _, e in ipairs(rogue) do
    local d = math.sqrt((e.x - L.ox) ^ 2 + (e.y - L.oy) ^ 2)
    T.ok(math.abs(d - L.ring_r) < 0.01, "buttons: sitzt auf der Ringbahn")
    T.ok(e.y > L.oy, "buttons: sitzt in der unteren Haelfte")
  end
end

-- Treffer und Danebengriff -------------------------------------------------
do
  local slots = render.ability_slots(L, "rogue")
  local e = slots[2]
  T.eq((render.ability_button_at(L, "rogue", e.x, e.y)), e.slot,
    "klick: die Mitte trifft")
  T.eq((render.ability_button_at(L, "rogue", e.x + render.BUTTON_R - 2, e.y)),
    e.slot, "klick: knapp innerhalb trifft noch")
  T.eq((render.ability_button_at(L, "rogue", e.x, e.y - render.BUTTON_R - 6)),
    nil, "klick: knapp ausserhalb trifft nicht")
  T.eq((render.ability_button_at(L, "rogue", L.ox, L.oy)), nil,
    "klick: die Kartenmitte ist kein Button")
  T.eq((render.ability_button_at(L, nil, e.x, e.y)), nil,
    "klick: ohne Klasse kein Treffer")
end

-- Per F10 abgeschaltete Faehigkeiten haben keinen Sitzplatz ----------------
do
  local vorher = #render.ability_slots(L, "rogue")
  model.params.rogue_stealth_enabled.wert = 0
  local slots = render.ability_slots(L, "rogue")
  T.eq(#slots, vorher - 1, "buttons: abgeschaltet = ein Sitzplatz weniger")
  for _, e in ipairs(slots) do
    T.ok(e.slot ~= 3, "buttons: die Verstohlenheit ist raus")
  end
  -- ... und ihr alter Platz laesst sich nicht mehr anklicken: die uebrigen
  -- Buttons ruecken zusammen, die Tastennummern bleiben aber am Slot
  T.eq(slots[#slots].slot, 4, "buttons: der Tritt behaelt seine Nummer 4")
  model.params.rogue_stealth_enabled.wert = 1
end

-- Das Layout darf die Buttons nicht aus dem Bild schieben ------------------
do
  for _, size in ipairs({ { 1280, 800 }, { 1024, 768 }, { 800, 600 } }) do
    local LL = render.layout(size[1], size[2], true)
    for _, e in ipairs(render.ability_slots(LL, "rogue")) do
      T.ok(e.x - render.BUTTON_R >= 0 and e.x + render.BUTTON_R <= size[1],
        "buttons: bleiben bei " .. size[1] .. "x" .. size[2] .. " im Bild (x)")
      T.ok(e.y + render.BUTTON_R <= size[2],
        "buttons: bleiben bei " .. size[1] .. "x" .. size[2] .. " im Bild (y)")
    end
  end
end
