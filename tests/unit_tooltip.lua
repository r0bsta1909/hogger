-- tests/unit_tooltip.lua — Stufe 1: Faehigkeits-Tooltips (Runde 14, #171).
-- "Reichweite 40 px" sagte niemandem etwas, und was die Faehigkeit TUT,
-- stand gar nicht drin — obwohl alle Zahlen in der Kit-Tabelle gebunden
-- sind. Hier wird beides festgenagelt.

local render = require("game.render")
local model = require("sim.model")
local step = require("game.gamesim.step")
local T = _G.T

local function lines_for(class, slot)
  local spec = step.ABILITIES[class][slot]
  local def = model.classes[class].abilities[slot]
  return render.ability_tooltip(class, spec, def, slot), spec, def
end

local function joined(l) return table.concat(l, "\n") end

-- Meter statt Pixel ---------------------------------------------------------
do
  T.eq(model.meters(model.p("cast_range")), 30,
    "meter: 200 px Zauberreichweite sind die 30 Meter des Originals")
  T.eq(model.meters(model.p("melee_range")), 6, "meter: Nahkampf 40 px = 6 m")
  T.eq(model.meters(model.p("autoshot_range")), 35, "meter: Autoschuss = 35 m")
  T.eq(model.meters(model.p("heal_range")), 38, "meter: Heilen = 38 m")
  T.eq(model.meters(0), 0, "meter: null bleibt null")

  -- Und die Anzeige haengt am Modell, nicht an einer zweiten Zahl
  local alt = model.params.cast_range.wert
  model.params.cast_range.wert = 300
  local l = lines_for("druid", 3)
  T.ok(joined(l):find("Reichweite: 45 Meter"),
    "meter: dreht man den Parameter, zieht der Tooltip mit")
  model.params.cast_range.wert = alt
end

-- Kategorie und Wirkung -----------------------------------------------------
do
  local l = lines_for("rogue", 1) -- Finsterer Stoss
  T.eq(l[1], "Finsterer Stoss", "tooltip: Name zuerst")
  T.eq(l[2], "Schaden + Combopunkt", "tooltip: Kategorie in Zeile 2")
  T.ok(joined(l):find("5 Schaden"), "tooltip: die gebundene Zahl steht da")
  T.ok(joined(l):find("40 Energie"), "tooltip: Kosten mit Ressourcennamen")
  T.ok(joined(l):find("Sofort"), "tooltip: ohne Zauberzeit heisst es Sofort")
  T.ok(joined(l):find("Taste 1"), "tooltip: Tastenkuerzel zuletzt")

  local ev = lines_for("rogue", 2) -- Ausweiden
  T.ok(joined(ev):find("je Combopunkt"), "tooltip: Ausweiden rechnet je Punkt")
  T.ok(joined(ev):find("bis " .. model.p("rogue_evis_dmg_per_cp") * model.CP_MAX),
    "tooltip: ... und nennt das Maximum")

  local heal = lines_for("priest", 2) -- Geringes Heilen
  T.eq(heal[2], "Heilung", "tooltip: Heilzauber ist als Heilung ausgewiesen")
  T.ok(joined(heal):find("Heilt %d"), "tooltip: Heilwert steht da")
  T.ok(joined(heal):find("Zauberzeit"), "tooltip: Zauberzeit statt Sofort")
  T.ok(joined(heal):find("Verbuendeter in 38 Metern"),
    "tooltip: Ally-Zauber nennt die Heil-Reichweite in Metern")

  local pws = lines_for("priest", 3) -- Machtwort: Schild
  T.eq(pws[2], "Schild", "tooltip: Schild ist als Schild ausgewiesen")
  T.ok(joined(pws):find("Absorbiert " .. model.p("priest_pws_absorb")),
    "tooltip: Absorptionswert steht da")

  local kick = lines_for("rogue", 4) -- Tritt
  T.eq(kick[2], "Unterbrechung", "tooltip: der Tritt ist eine Unterbrechung")
  T.ok(joined(kick):find("Abklingzeit"), "tooltip: Cooldown steht da")

  local loh = lines_for("paladin", 3) -- Handauflegung
  T.eq(loh[2], "Notheilung", "tooltip: Handauflegung ist Notheilung")
  T.ok(joined(loh):find("einmal pro Leben"),
    "tooltip: die Einmal-Regel steht im Klartext")

  local feign = lines_for("hunter", 2) -- Totstellen
  T.eq(feign[2], "Aggro-Reset", "tooltip: Totstellen ist ein Aggro-Reset")

  local taunt = lines_for("warrior", 3) -- Spott
  T.eq(taunt[2], "Aggro", "tooltip: Spott zieht Aggro")

  local stealth = lines_for("rogue", 3)
  T.eq(stealth[2], "Tarnung", "tooltip: Verstohlenheit ist Tarnung")
  T.ok(joined(stealth):find("60 %% Tempo"), "tooltip: Tempoanteil steht da")
end

-- Vollstaendigkeit: JEDE Faehigkeit hat eine Kategorie ----------------------
do
  local n = 0
  for _, class in ipairs(model.CLASS_IDS) do
    for slot, def in ipairs(model.classes[class].abilities) do
      T.ok(type(def.art) == "string" and #def.art > 0,
        "art: " .. class .. " Slot " .. slot .. " (" .. tostring(def.id) .. ") hat eine Kategorie")
      T.ok(def.art == nil or #def.art <= 34,
        "art: " .. tostring(def.id) .. " passt in eine Tooltip-Zeile")
      n = n + 1
    end
  end
  T.eq(n, 22, "art: alle 22 Faehigkeiten der acht Klassen sind erfasst")
end

-- Abgeschaltete Faehigkeiten haben trotzdem einen sauberen Tooltip ----------
do
  model.params.druid_roots_enabled.wert = 0
  local l = lines_for("druid", 3)
  T.eq(l[1], "Gnarlwurzeln", "tooltip: auch abgeschaltet bleibt der Name")
  model.params.druid_roots_enabled.wert = 1
end
