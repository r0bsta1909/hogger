-- tests/unit_model.lua — Stufe 1: model.lua gegen die GDD-Tabellen.
-- GDD 9.3 sind die harten Testfaelle; dazu 8.1/8.2-Vollstaendigkeit,
-- Krit-Ausschluesse, Bedrohung, XP-Deckel, Parametertabellen-Struktur.

local M = require("sim.model")
local T = _G.T

-- GDD 9.3: Skalierungstabelle als harte Testfaelle -------------------------
local table93 = {
  --  N, HP,    Fressheilung, Unterbrecher, Cleave, Adds, Respawn (GDD 9.3, v2.6)
  -- HP = 430 x N - 950; Cleave = ceil(N/5); Respawn = clamp(8+0,52N; 10; 30)
  { 5,   1200,  144,  3, 1, 0, 10.6 },
  { 10,  3350,  402,  3, 2, 1, 13.2 },
  { 20,  7650,  918,  4, 4, 2, 18.4 },
  { 40, 16250, 1950,  6, 8, 5, 28.8 },
}
for _, row in ipairs(table93) do
  local n = row[1]
  T.eq(M.hogger_hp(n), row[2], "9.3 Hogger-HP N=" .. n)
  T.near(M.eat_heal_per_channel(n), row[3], "9.3 Fress-Heilung N=" .. n)
  T.eq(M.eat_interrupters(n), row[4], "9.3 Unterbrecher N=" .. n)
  T.eq(M.cleave_targets(n), row[5], "9.3 Cleave-Ziele N=" .. n)
  T.eq(M.adds(n), row[6], "9.3 Adds N=" .. n)
  T.near(M.respawn_timer(n), row[7], "9.3 Respawn N=" .. n)
end

-- GDD 9.3: HP-Untergrenze 120 x N unterhalb der Design-Spanne --------------
T.eq(M.hogger_hp(1), 120, "9.3 HP-Untergrenze N=1 (Solo-Wartelobby)")
T.eq(M.hogger_hp(2), 240, "9.3 HP-Untergrenze N=2")
T.eq(M.hogger_hp(4), 770, "9.3 affine Formel greift ab N=4")

-- GDD 7.2: Mob-Slots -------------------------------------------------------
T.eq(M.mob_slots(5), 5, "7.2 Mob-Slots N=5")
T.eq(M.mob_slots(40), 12, "7.2 Mob-Slots N=40")

-- GDD 9.2: Fress-Schadensschwelle 5 % Max-HP (v2.6) ------------------------
T.near(M.eat_dmg_threshold(10), 167.5, "9.2 Fress-Schadensschwelle N=10")
T.near(M.eat_dmg_threshold(40), 812.5, "9.2 Fress-Schadensschwelle N=40")

-- GDD 13.2: Krit-Ausschluesse ----------------------------------------------
T.ok(M.can_crit("autohit"), "13.2 Autohit kann kritten")
T.ok(M.can_crit("ability"), "13.2 Faehigkeit kann kritten")
T.ok(M.can_crit("heal"), "13.2 Heilung kann kritten")
T.ok(M.can_crit("mob"), "7.2 Mobs kritten mit Standard-5%")
T.ok(not M.can_crit("charge"), "13.2 Charge kann NICHT kritten")
T.ok(not M.can_crit("slice"), "13.2 Slice kann NICHT kritten")
T.ok(not M.can_crit("dot"), "13.2 DoT-Ticks koennen NICHT kritten")
T.ok(not M.can_crit("eat_heal"), "13.2 Fress-Heilung kann NICHT kritten")
T.ok(not M.can_crit("add"), "9.2 Adds kritten NICHT")
T.throws(function() M.can_crit("quatsch") end, "13.2 unbekannte Schadensart faellt auf")

-- GDD 9.4: Bedrohung -------------------------------------------------------
T.near(M.threat_for(10, false), 10, "9.4 1 Schaden = 1 Bedrohung")
T.near(M.threat_for(20, true), 15, "9.4 1 Heilung = 0,75 Bedrohung")

-- GDD 8.1: Basiswerte ------------------------------------------------------
T.eq(M.p("move_speed_alive"), 140, "8.1 Tempo lebend")
T.eq(M.p("move_speed_ghost"), 210, "8.1 Tempo Geist (150%)")
T.eq(M.p("autohit_melee_dmg"), 2, "8.1 Nahkampf-Autohit")
T.eq(M.p("autoshot_dmg"), 3, "8.1 Autoschuss")
T.eq(M.p("autoshot_range"), 200, "8.1 Autoschuss-Reichweite")
T.eq(M.p("wand_range"), 120, "8.1 Zauberstab-Reichweite")
T.eq(M.p("gcd"), 1.5, "8.1 GCD")
T.eq(M.p("crit_chance_player"), 0.05, "13.2 Kritchance Spieler")
T.eq(M.p("crit_mult_hogger"), 2.0, "13.2 Kritmultiplikator Hogger")
T.eq(M.p("mana_regen_rate"), 10, "8.1 Fuenf-Sekunden-Regel: 10 Mana/s")
T.eq(M.p("five_sec_rule_wait"), 5, "8.1 Fuenf-Sekunden-Regel: 5 s Wartezeit")

-- GDD 8.1: HP nach Ruestungsklasse ----------------------------------------
local expected_hp = {
  warrior = 80, paladin = 80,
  hunter = 65, rogue = 65, druid = 65,
  priest = 50, mage = 50, warlock = 50,
}
for class_id, hp in pairs(expected_hp) do
  T.eq(M.hp_for_class(class_id), hp, "8.1 HP " .. class_id)
end

-- GDD 8.2: 8 Klassen, gueltige Vanilla-Rassen-Kombinationen ----------------
T.eq(#M.CLASS_IDS, 8, "8.2 acht Klassen")
local expected_races = {
  warrior = { "mensch", "zwerg", "nachtelf", "gnom" },
  paladin = { "mensch", "zwerg" },
  hunter  = { "zwerg", "nachtelf" },
  rogue   = { "mensch", "zwerg", "nachtelf", "gnom" },
  priest  = { "mensch", "zwerg", "nachtelf" },
  mage    = { "mensch", "gnom" },
  warlock = { "mensch", "gnom" },
  druid   = { "nachtelf" },
}
for class_id, races in pairs(expected_races) do
  local c = M.classes[class_id]
  T.ok(c ~= nil, "8.2 Klasse existiert: " .. class_id)
  T.eq(#c.races, #races, "8.2 Rassenzahl " .. class_id)
  for i, r in ipairs(races) do
    T.eq(c.races[i], r, "8.2 Rasse " .. class_id .. "/" .. r)
  end
end

-- GDD 8.2: die Kits vollstaendig und in Reihenfolge (Issue #28 — die
-- Playtest-Frage "Jaeger hat nur RS?" wird hier maschinell beantwortet:
-- sein Autoschuss IST Faehigkeit 1 und laeuft automatisch, GDD 8.1)
local expected_kits = {
  warrior = { "Heroischer Stoss", "Schlachtruf" },
  paladin = { "Heiliges Licht", "Siegel der Rechtschaffenheit" },
  hunter  = { "Raptorstoss" },
  rogue   = { "Finsterer Stoss", "Ausweiden", "Verstohlenheit" },
  priest  = { "Goettliche Pein", "Geringes Heilen" },
  mage    = { "Feuerball", "Frostruestung" },
  warlock = { "Schattenblitz", "Wichtel beschwoeren" },
  druid   = { "Zorn", "Heilende Beruehrung" },
}
local expected_attack = {
  warrior = "melee", paladin = "melee", hunter = "shot", rogue = "melee",
  priest = "wand", mage = "wand", warlock = "wand", druid = "melee",
}
for class_id, kit in pairs(expected_kits) do
  local c = M.classes[class_id]
  T.eq(#c.abilities, #kit, "8.2 Anzahl Faehigkeiten " .. class_id)
  for i, name in ipairs(kit) do
    T.eq(c.abilities[i] and c.abilities[i].name_de, name,
      "8.2 Faehigkeit " .. class_id .. "/" .. i)
  end
  T.eq(c.attack, expected_attack[class_id], "8.1 Autoangriff " .. class_id)
end

-- GDD 5: Rassenwurf — Druide immer Nachtelf, Jaeger nie Mensch,
-- 2/3-Mensch-Regel, jeder Wurf liefert eine gueltige Rasse ------------------
for i = 0, 99 do
  local u = i / 100
  T.eq(M.roll_race("druid", u), "nachtelf", "5 Druide immer Nachtelf (u=" .. u .. ")")
  local hr = M.roll_race("hunter", u)
  T.ok(hr == "zwerg" or hr == "nachtelf", "5 Jaeger nur Zwerg/Nachtelf (u=" .. u .. ")")
end
T.eq(M.roll_race("warrior", 0.0), "mensch", "5 Krieger-Wurf unter 2/3 ist Mensch")
T.eq(M.roll_race("warrior", 0.66), "mensch", "5 Krieger-Wurf knapp unter 2/3 ist Mensch")
T.ok(M.roll_race("warrior", 0.67) ~= "mensch", "5 Krieger-Wurf ueber 2/3 ist kein Mensch")
for i = 0, 99 do
  local u = i / 100
  for _, class_id in ipairs(M.CLASS_IDS) do
    local r = M.roll_race(class_id, u)
    local valid = false
    for _, vr in ipairs(M.classes[class_id].races) do
      if vr == r then valid = true end
    end
    T.checks = T.checks + 1
    if not valid then
      T.failures[#T.failures + 1] = "5 ungueltige Rasse " .. tostring(r) .. " fuer " .. class_id
    end
  end
end

-- GDD 7.3: XP-Deckel — Stufe 2 in einem Try unerreichbar -------------------
for _, n in ipairs({ 5, 10, 20, 40 }) do
  local max_xp = M.max_mob_kills_per_try(n) * M.p("xp_per_mob")
  T.ok(max_xp < M.p("xp_level2"),
    string.format("7.3 XP-Deckel pro Try < 400 (N=%d: %d)", n, max_xp))
end
T.ok(M.max_mob_kills_per_try(40) <= 120, "7.3 Richtwert ~100 Mob-Kills pro Try haelt")

-- GDD 6: Todesstrafe im fixierten Korridor (M1: 24,6 s bei N=5 bis 42,8 s bei N=40)
T.near(M.death_penalty(5), 24.6, "6 Todesstrafe N=5")
T.near(M.death_penalty(40), 42.8, "6 Todesstrafe N=40")
for _, n in ipairs({ 5, 10, 20, 40 }) do
  local pen = M.death_penalty(n)
  T.ok(pen >= 24 and pen <= 45,
    string.format("6 Todesstrafe plausibel (N=%d: %.1f s)", n, pen))
end

-- GDD 17.6: Parametertabelle strukturell vollstaendig ----------------------
for key, entry in pairs(M.params) do
  T.ok(type(entry.wert) == "number" and type(entry.min) == "number"
    and type(entry.max) == "number" and type(entry.schritt) == "number"
    and type(entry.kapitel) == "string",
    "17.6 Parameterfelder vollstaendig: " .. key)
  T.ok(entry.min <= entry.wert and entry.wert <= entry.max,
    "17.6 wert in [min,max]: " .. key)
end
T.throws(function() M.p("gibt_es_nicht") end, "17.6 unbekannter Parameter faellt auf")

-- GDD 7.2: Mob-Tabelle mit Kupfer 1-3 --------------------------------------
for mob_id, mob in pairs(M.mobs) do
  T.ok(mob.kupfer >= 1 and mob.kupfer <= 3, "7.3 Kupfer 1-3: " .. mob_id)
  T.ok(type(M.p(mob.hp)) == "number", "7.2 Mob-HP-Parameter existiert: " .. mob_id)
  T.ok(type(M.p(mob.dmg)) == "number", "7.2 Mob-Schadens-Parameter existiert: " .. mob_id)
end
