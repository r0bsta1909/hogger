-- sim/main.lua — CLI der Headless-Sim (GDD 17.2).
-- Einzelzelle: lua sim/main.lua --n 10 --runs 1000 --penalty 30 --crits on
--              [--agent koordiniert] [--seed 1]
-- Voller Sweep (Matrix aus GDD 17.2 Punkt 6):
--              lua sim/main.lua --sweep --runs 1000 [--out reports/x.md] [--date 2026-08-16]

package.path = "./?.lua;" .. package.path

local engine = require("sim.engine")
local report = require("sim.report")

-- ---------------------------------------------------------------------------
local model = require("sim.model")

local opts = { n = 10, runs = 100, penalty = 30, crits = "on",
               agent = "koordiniert", seed = 1, sweep = false,
               out = nil, date = "bericht", exp = {} }
local i = 1
while i <= #arg do
  local a = arg[i]
  if a == "--sweep" then opts.sweep = true
  elseif a == "--n" then i = i + 1; opts.n = tonumber(arg[i])
  elseif a == "--runs" then i = i + 1; opts.runs = tonumber(arg[i])
  elseif a == "--penalty" then i = i + 1; opts.penalty = tonumber(arg[i])
  elseif a == "--crits" then i = i + 1; opts.crits = arg[i]
  elseif a == "--agent" then i = i + 1; opts.agent = arg[i]
  elseif a == "--seed" then i = i + 1; opts.seed = tonumber(arg[i])
  elseif a == "--out" then i = i + 1; opts.out = arg[i]
  elseif a == "--date" then i = i + 1; opts.date = arg[i]
  elseif a == "--set" then
    -- Parameter-Experiment: --set hogger_hp_coeff=180 (Tuning-Protokoll 17.9)
    i = i + 1
    local key, val = arg[i]:match("^([%w_]+)=([%d%.%-]+)$")
    assert(key and model.params[key], "ungueltiges --set: " .. tostring(arg[i]))
    model.params[key].wert = tonumber(val)
    io.write("SET ", key, " = ", val, "\n")
  elseif a == "--exp" then
    -- Sim-Prototyp fuer Vorschlags-Issues (KEINE Designaenderung):
    -- cleave (Autohit trifft ceil(N/10) Ziele), chargescale (Charge-CD / (N/10))
    i = i + 1
    opts.exp[arg[i]] = true
    io.write("EXPERIMENT ", arg[i], "\n")
  else io.write("unbekannte Option: ", a, "\n"); os.exit(2) end
  i = i + 1
end

local function run_cell(agent, n, penalty, crits, runs, cell_seed)
  local results = {}
  for r = 1, runs do
    results[r] = engine.run_try({
      n = n, penalty = penalty, crits = crits, agent = agent,
      seed = cell_seed + r, log = false, exp = opts.exp,
    })
  end
  local s = report.summarize(results)
  s.diag = report.diagnostics(results, n)
  return s
end

local function pct(x) return string.format("%.1f%%", x * 100) end

-- ---------------------------------------------------------------------------
if not opts.sweep then
  local s = run_cell(opts.agent, opts.n, opts.penalty, opts.crits == "on",
                     opts.runs, opts.seed * 1000000)
  io.write(string.format(
    "Zelle: agent=%s N=%d penalty=%ds crits=%s runs=%d\n",
    opts.agent, opts.n, opts.penalty, opts.crits, s.runs))
  io.write(string.format("  Siegquote        %s\n", pct(s.win_rate)))
  io.write(string.format("  Median-Trylaenge %.1f min%s\n",
    (s.median_duration or 0) / 60,
    s.median_win_duration
      and string.format(" (Siege: %.1f min)", s.median_win_duration / 60) or ""))
  io.write(string.format("  Uptime           %s\n", pct(s.mean_uptime)))
  io.write(string.format("  Tode/Lauf        %.1f\n", s.mean_deaths))
  io.write(string.format("  Fress-Kanaele    %.2f/Lauf, unterbrochen %s\n",
    s.eat_channels / s.runs,
    pct(s.eat_interrupted / math.max(1, s.eat_channels))))
  io.write(string.format("  Charges          %.1f/Lauf\n", s.charges / s.runs))
  if s.diag then
    io.write(string.format("  Lebensdauer am Boss (Mittel) %.1f s (GDD-Modell: 5-15 s)\n",
      s.diag.mean_life))
    io.write(string.format("  DPS je lebendem Spieler      %.2f (GDD-Modell: ~3,5)\n",
      s.diag.dps_per_alive))
  end
  os.exit(0)
end

-- ---------------------------------------------------------------------------
-- Sweep: Matrix N x Todesstrafe x Krits x Agent (GDD 17.2 Punkt 6)
-- ---------------------------------------------------------------------------
local NS = { 5, 10, 20, 40 }
local PENALTIES = { 20, 25, 30, 35 }
local AGENTS = { "unkoordiniert", "koordiniert", "turtle" }

local cells = {}
local cell_index = 0
for _, agent in ipairs(AGENTS) do
  cells[agent] = {}
  for _, n in ipairs(NS) do
    cells[agent][n] = {}
    for _, penalty in ipairs(PENALTIES) do
      cells[agent][n][penalty] = {}
      for _, crits in ipairs({ true, false }) do
        cell_index = cell_index + 1
        local key = crits and "an" or "aus"
        local s = run_cell(agent, n, penalty, crits, opts.runs,
                           opts.seed * 1000000 + cell_index * 10000000)
        cells[agent][n][penalty][key] = s
        io.write(string.format("[%2d/96] %-13s N=%2d strafe=%2d krits=%-3s  sieg=%s\n",
          cell_index, agent, n, penalty, key, pct(s.win_rate)))
        io.flush()
      end
    end
  end
end

-- Todesstrafe fixieren: kleinstes Penalty, bei dem F1 UND F5 fuer alle N halten;
-- gibt es keins, das mit den wenigsten Verletzungen.
local best_penalty, best_score = nil, -1
for _, penalty in ipairs(PENALTIES) do
  local score = 0
  for _, n in ipairs(NS) do
    local s = cells["koordiniert"][n][penalty]["an"]
    if s.win_rate >= 0.60 and s.win_rate <= 0.90 then score = score + 1 end
    local md = s.median_win_duration
    if md and md >= 6 * 60 and md <= 13 * 60 then score = score + 1 end
  end
  if score > best_score then best_score, best_penalty = score, penalty end
end

local f = report.evaluate(cells, best_penalty, NS)

-- ---------------------------------------------------------------------------
-- Markdown-Bericht
-- ---------------------------------------------------------------------------
local out = {}
local function w(fmt, ...)
  if select("#", ...) == 0 then
    out[#out + 1] = fmt -- Rohzeile, kein Format (Zeilen koennen % enthalten)
  else
    out[#out + 1] = string.format(fmt, ...)
  end
end

w("# M1-Validierungsbericht — Headless-Sim (%s)\n", opts.date)
w("%d Laeufe je Zelle, Matrix: N x Todesstrafe x Krits x Agent (GDD 17.2).\n", opts.runs)
w("**Fixierte Todesstrafe: %d s** (kleinste Strafe mit maximaler F1+F5-Erfuellung).\n", best_penalty)

w("\n## F-Kriterien (GDD 13.3) bei Todesstrafe %d s\n", best_penalty)
w("| # | Kriterium | Ergebnis | Detail |")
w("|---|---|---|---|")
local names = {
  "F1 koordiniert gewinnt zuverlaessig (60-90 %)",
  "F2 unkoordiniert verliert meist (<= 35 %)",
  "F3 Fressen ist der Hebel (<= 10 % ohne Unterbrechung)",
  "F4 Krits entscheiden nichts (<= 5 pp)",
  "F5 Median-Siegtry 6-13 min",
  "F6 Skalierung fair (Spread <= 15 pp)",
}
for k = 1, 6 do
  w("| F%d | %s | %s | %s |", k, names[k], f[k].ok and "BESTANDEN" or "**VERLETZT**", f[k].detail)
end
w("| T | Turtle verliert per Zeitlimit (> 95 %%) | %s | %s |",
  f.turtle.ok and "BESTANDEN" or "**VERLETZT**", f.turtle.detail)

for _, agent in ipairs(AGENTS) do
  w("\n## Siegquoten %s (Krits an)\n", agent)
  local header = "| N \\ Strafe |"
  local sep = "|---|"
  for _, p in ipairs(PENALTIES) do
    header = header .. string.format(" %d s |", p)
    sep = sep .. "---|"
  end
  w(header); w(sep)
  for _, n in ipairs(NS) do
    local row = string.format("| %d |", n)
    for _, p in ipairs(PENALTIES) do
      row = row .. string.format(" %s |", pct(cells[agent][n][p]["an"].win_rate))
    end
    w(row)
  end
end

w("\n## Kennzahlen koordiniert (Krits an, Todesstrafe %d s)\n", best_penalty)
w("| N | Siegquote | Median-Siegtry | Uptime | Tode/Lauf | Fress-Kanaele | unterbrochen | Charges |")
w("|---|---|---|---|---|---|---|---|")
for _, n in ipairs(NS) do
  local s = cells["koordiniert"][n][best_penalty]["an"]
  w("| %d | %s | %s | %s | %.1f | %.2f | %s | %.1f |",
    n, pct(s.win_rate),
    s.median_win_duration and string.format("%.1f min", s.median_win_duration / 60) or "-",
    pct(s.mean_uptime), s.mean_deaths, s.eat_channels / s.runs,
    pct(s.eat_interrupted / math.max(1, s.eat_channels)), s.charges / s.runs)
end

w("\n## Klassenverteilung der Sieglaeufe (koordiniert, alle Zellen)\n")
local class_totals, total = {}, 0
for _, n in ipairs(NS) do
  for _, p in ipairs(PENALTIES) do
    for _, ck in ipairs({ "an", "aus" }) do
      for cl, k in pairs(cells["koordiniert"][n][p][ck].class_wins) do
        class_totals[cl] = (class_totals[cl] or 0) + k
        total = total + k
      end
    end
  end
end
local sorted = {}
for cl, k in pairs(class_totals) do sorted[#sorted + 1] = { cl, k } end
table.sort(sorted, function(a, b)
  if a[2] ~= b[2] then return a[2] > b[2] end
  return a[1] < b[1] -- Namens-Tiebreak: Berichtsausgabe plattformstabil
end)
w("| Klasse | Anteil |")
w("|---|---|")
for _, e in ipairs(sorted) do
  w("| %s | %s |", e[1], pct(e[2] / math.max(1, total)))
end

local text = table.concat(out, "\n") .. "\n"
io.write("\n" .. text)

if opts.out then
  local fh = assert(io.open(opts.out, "w"))
  fh:write(text)
  fh:close()
  io.write("Bericht geschrieben: ", opts.out, "\n")
end

local all_ok = f[1].ok and f[2].ok and f[3].ok and f[4].ok and f[5].ok and f[6].ok and f.turtle.ok
os.exit(all_ok and 0 or 1)
