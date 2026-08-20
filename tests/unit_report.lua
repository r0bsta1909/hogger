-- tests/unit_report.lua — F-Kriterien-Bewertung (GDD 13.3). Festgezurrt
-- nach Runde 5: F4 prueft das MITTEL der Krit-Deltas (Rob-Entscheid
-- Issue #6) plus beide Krit-Welten im F1-Band; F6 prueft den Spread
-- zwischen kleinstem und groesstem N — nicht max-min ueber alle N.

local report = require("sim.report")

local PEN = 14
local NS = { 5, 10, 20, 40 }

-- Fixture-Bauer: wins = { [n] = { an, aus } } fuer koordiniert;
-- unkoordiniert bekommt ueberall 1 % (Deltas ~0)
local function make_cells(wins)
  local cells = { koordiniert = {}, unkoordiniert = {} }
  for _, n in ipairs(NS) do
    local w = wins[n]
    cells.koordiniert[n] = { [PEN] = {
      an = { win_rate = w[1], median_win_duration = 10 * 60 },
      aus = { win_rate = w[2], median_win_duration = 10 * 60 },
    } }
    cells.unkoordiniert[n] = { [PEN] = {
      an = { win_rate = 0.01, runs_without_interrupt = 100,
             wins_without_interrupt = 0 },
      aus = { win_rate = 0.012 },
    } }
  end
  return cells
end

-- Der Runde-5-Fall: Einzelzellen-Deltas bis 5,6 pp, Mittel klar unter 5,
-- beide Krit-Welten im Band; N=20 ist der Sweet Spot (89,8 %), aber der
-- F6-Spread N=5<->N=40 betraegt nur 3,8 pp
do
  local f = report.evaluate(make_cells({
    [5] = { 0.667, 0.616 }, [10] = { 0.831, 0.802 },
    [20] = { 0.898, 0.865 }, [40] = { 0.705, 0.649 },
  }), PEN, NS)
  T.ok(f[1].ok, "F1: alle N im Band 60-90 %")
  T.ok(f[4].ok, "F4: Mittel der Deltas zaehlt, Einzelzellen duerfen streuen")
  T.ok(f[4].detail:find("Mittel") ~= nil, "F4: Mittel steht im Detail")
  T.ok(f[6].ok, "F6: Spread N=5<->N=40 zaehlt, nicht max-min aller N")
  T.ok(f[6].detail:find("alle N") ~= nil, "F6: volle Spanne bleibt sichtbar")
end

-- F4 faellt, wenn das MITTEL ueber 5 pp liegt ...
do
  local f = report.evaluate(make_cells({
    [5] = { 0.88, 0.62 }, [10] = { 0.88, 0.62 },
    [20] = { 0.88, 0.62 }, [40] = { 0.88, 0.75 },
  }), PEN, NS)
  T.ok(not f[4].ok, "F4: Mittel > 5 pp falsifiziert")
end

-- ... oder wenn die Krits-aus-Welt aus dem F1-Band faellt
do
  local f = report.evaluate(make_cells({
    [5] = { 0.65, 0.62 }, [10] = { 0.80, 0.78 },
    [20] = { 0.85, 0.83 }, [40] = { 0.62, 0.57 },
  }), PEN, NS)
  T.ok(not f[4].ok, "F4: Krits-aus-Welt unter 60 % falsifiziert")
end

-- F6 faellt bei echtem N=5<->N=40-Spread ueber 15 pp
do
  local f = report.evaluate(make_cells({
    [5] = { 0.88, 0.86 }, [10] = { 0.80, 0.79 },
    [20] = { 0.75, 0.74 }, [40] = { 0.62, 0.61 },
  }), PEN, NS)
  T.ok(not f[6].ok, "F6: 26 pp zwischen N=5 und N=40 falsifiziert")
end

-- ---------------------------------------------------------------------------
-- Vertrauensbereich (Runde 14, #175): jede Siegquote im Bericht traegt ihn
-- mit sich, damit niemand Rauschen fuer ein Ergebnis haelt.
-- ---------------------------------------------------------------------------
do
  local model = require("sim.model")

  T.eq(report.ci95(0.5, 0), 0, "ci95: ohne Laeufe kein Bereich")
  T.near(report.ci95(0.5, 100), 1.96 * 0.05, "ci95: 100 Laeufe bei 50 % = +/-9,8 pp")
  T.ok(report.ci95(0.75, 300) > report.ci95(0.75, 1000),
    "ci95: mehr Laeufe = engerer Bereich")
  T.ok(report.ci95(0.75, 300) < 0.05,
    "ci95: 300 Laeufe reichen fuer eine Aussage im 60-90-%-Band")
  T.eq(report.ci95(0, 500), 0, "ci95: eine 0-%-Zelle streut nicht")
  T.eq(report.ci95(1, 500), 0, "ci95: eine 100-%-Zelle streut nicht")

  -- Der Richtungstest faehrt einen festen Laufweg. Diese Zahl steht in
  -- sim/main.lua als QUICK_WALK und MUSS die Modellwahrheit sein — laeuft
  -- sie auseinander, misst der Standardtest eine andere Welt als das Spiel.
  T.eq(model.walk_time(), 14, "walk_time: Laufweganteil der Todesstrafe ist 14 s")
  T.near(model.death_penalty(5), model.respawn_timer(5) + model.walk_time(),
    "walk_time: Todesstrafe = Respawn-Timer + Laufweg")
  local src = assert(io.open("sim/main.lua")):read("*a")
  local quick = tonumber(src:match("QUICK_WALK%s*=%s*(%d+)"))
  T.eq(quick, model.walk_time(),
    "Richtungstest: QUICK_WALK haengt am Modell, nicht an einer Handzahl")
end
