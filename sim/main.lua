-- sim/main.lua — CLI der Headless-Sim (GDD 17.2).
-- Einzelzelle: lua sim/main.lua --n 10 --runs 1000 --crits on
--              [--walk 14] [--agent koordiniert] [--seed 1]
-- --walk ist der Laufweg-Anteil der Todesstrafe (Geist + Wiederbelebungskanal
-- + Anmarsch, 16 s); ohne Angabe kommt er aus model.walk_time(). Die
-- Gesamtstrafe ist respawn_timer(N) + Laufweg (GDD 9.3 + 7.1).
--
-- RICHTUNGSTEST (Standard-Gate seit Runde 14, ADR 004):
--              lua sim/main.lua --quick --jobs 10 [--out reports/x.md]
--   24 Zellen bei festem Laufweg, deckt F1-F6 und das Turtle-Gate ab.
-- VOLLE MATRIX (nur vor Releases oder auf Ansage):
--              lua sim/main.lua --sweep --runs 1000 --jobs 10 [--out ...]
--   96 Zellen; die zusaetzlichen 72 variieren nur den Laufweg, der seit
--   Runde 6 (#96) fest ist — sie liefern die Belegmatrizen, kein Kriterium.
--
-- --jobs N verteilt die Zellen auf N Kindprozesse (io.popen, plattformgleich)
-- und fuegt deren Ergebnisse zusammen. --part k/n ist der Kindmodus: er
-- rechnet nur jede n-te Zelle und schreibt eine Lua-Tabelle nach stdout.
-- Der Zellen-Seed haengt am Zellindex, nicht an der Reihenfolge der
-- Abarbeitung — parallel und seriell liefern bitgleiche Ergebnisse.

package.path = "./?.lua;" .. package.path

local engine = require("sim.engine")
local gamerun = require("sim.gamerun")
local report = require("sim.report")
local model = require("sim.model")

-- Informationszeilen gehen nach stderr, sobald wir Kindprozess sind:
-- stdout gehoert dann allein der Ergebnistabelle.
local function note(s)
  io.stderr:write(s)
  io.stderr:flush()
end

-- --engine spiel|1d (Runde 20): "spiel" treibt die echte Spielsimulation
-- (sim/gamerun.lua, Bots als Referenz-Raid), "1d" das alte Modell
-- (sim/engine.lua). Standard bis zur Ausmusterung der 1D-Sim: 1d.
local opts = { n = 10, runs = 100, walk = nil, crits = "on",
               agent = nil, seed = 1, mode = "cell", engine = "1d",
               out = nil, date = "bericht", jobs = 1, part = nil, parts = nil }
local raw = {}
local i = 1
while i <= #arg do
  local a = arg[i]
  if a == "--sweep" then opts.mode = "sweep"; raw[#raw + 1] = a
  elseif a == "--quick" then opts.mode = "quick"; raw[#raw + 1] = a
  elseif a == "--engine" then i = i + 1; opts.engine = arg[i]; raw[#raw + 1] = "--engine"; raw[#raw + 1] = arg[i]
  elseif a == "--smoke" then
    -- Rauchtest fuer Zwischenschritte: eine typische Zelle, wenige Laeufe
    opts.mode = "cell"; opts.engine = "spiel"; opts.n = 10; opts.runs = 20
    opts.agent = "typisch"
  elseif a == "--n" then i = i + 1; opts.n = tonumber(arg[i]); raw[#raw + 1] = "--n"; raw[#raw + 1] = arg[i]
  elseif a == "--runs" then i = i + 1; opts.runs = tonumber(arg[i]); raw[#raw + 1] = "--runs"; raw[#raw + 1] = arg[i]
  elseif a == "--walk" or a == "--penalty" then
    i = i + 1; opts.walk = tonumber(arg[i]); raw[#raw + 1] = "--walk"; raw[#raw + 1] = arg[i]
  elseif a == "--crits" then i = i + 1; opts.crits = arg[i]; raw[#raw + 1] = "--crits"; raw[#raw + 1] = arg[i]
  elseif a == "--agent" then i = i + 1; opts.agent = arg[i]; raw[#raw + 1] = "--agent"; raw[#raw + 1] = arg[i]
  elseif a == "--seed" then i = i + 1; opts.seed = tonumber(arg[i]); raw[#raw + 1] = "--seed"; raw[#raw + 1] = arg[i]
  elseif a == "--out" then i = i + 1; opts.out = arg[i] -- NICHT an Kinder weiterreichen
  elseif a == "--date" then i = i + 1; opts.date = arg[i]; raw[#raw + 1] = "--date"; raw[#raw + 1] = arg[i]
  elseif a == "--jobs" then i = i + 1; opts.jobs = math.max(1, tonumber(arg[i]) or 1)
  elseif a == "--part" then
    i = i + 1
    local k, n = tostring(arg[i]):match("^(%d+)/(%d+)$")
    if not k then io.write("--part erwartet k/n, bekam: ", tostring(arg[i]), "\n"); os.exit(2) end
    opts.part, opts.parts = tonumber(k), tonumber(n)
  elseif a == "--set" then
    -- Parameter-Experiment: --set hogger_hp_coeff=180 (Tuning-Protokoll 17.9)
    i = i + 1
    local key, val = arg[i]:match("^([%w_]+)=([%d%.%-]+)$")
    assert(key and model.params[key], "ungueltiges --set: " .. tostring(arg[i]))
    model.params[key].wert = tonumber(val)
    note("SET " .. key .. " = " .. val .. "\n")
    raw[#raw + 1] = "--set"; raw[#raw + 1] = arg[i]
  else io.write("unbekannte Option: ", a, "\n"); os.exit(2) end
  i = i + 1
end

-- Laufweg-Standard aus dem Modell (Runde 14): frueher stand hier die 15,
-- waehrend die Wahrheit im Modell 14 war — Spot-Checks liefen daneben.
opts.walk = opts.walk or model.walk_time()

assert(opts.engine == "1d" or opts.engine == "spiel",
  "--engine erwartet 1d oder spiel, bekam: " .. tostring(opts.engine))
local SPIEL = opts.engine == "spiel"
local NAMES = SPIEL and report.NAMES_SPIEL or report.NAMES_1D
opts.agent = opts.agent or NAMES.good

-- Ein Lauf. Die Spielsim liefert Listen (Lebensdauern, Tritt-Latenzen);
-- die werden hier zu Kennzahlen verdichtet, damit ein Kindprozess keine
-- Hunderte Zahlen je Lauf serialisieren muss.
local function run_one(agent, n, walk, crits, seed)
  if SPIEL then
    local r = gamerun.run_try({ n = n, crits = crits, profile = agent,
                                seed = seed, log = false })
    r.life = report.compact_life(r.lifetimes)
    r.kick = report.compact_list(r.kick_latencies)
    r.lifetimes, r.kick_latencies = nil, nil
    return r
  end
  return engine.run_try({ n = n, walk = walk, crits = crits, agent = agent,
                          seed = seed, log = false })
end

local function summarize_cell(results, n)
  local s = report.summarize(results)
  s.diag = report.diagnostics(results, n)
  return s
end

local function run_cell(agent, n, walk, crits, runs, cell_seed)
  local results = {}
  for r = 1, runs do
    results[r] = run_one(agent, n, walk, crits, cell_seed + r)
  end
  return summarize_cell(results, n)
end

local function pct(x) return string.format("%.1f%%", x * 100) end

-- ---------------------------------------------------------------------------
if opts.mode == "cell" then
  local s = run_cell(opts.agent, opts.n, opts.walk, opts.crits == "on",
                     opts.runs, opts.seed * 1000000)
  io.write(string.format(
    "Zelle [%s]: agent=%s N=%d laufweg=%ds (Gesamtstrafe %.0fs) crits=%s runs=%d\n",
    SPIEL and "Spielsim" or "1D-Sim",
    opts.agent, opts.n, opts.walk,
    model.respawn_timer(opts.n) + opts.walk, opts.crits, s.runs))
  io.write(string.format("  Siegquote        %s (+/- %.1f pp)\n",
    pct(s.win_rate), report.ci95(s.win_rate, s.runs) * 100))
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
  io.write(string.format("  Abbrueche        %d von %d Laeufen (Kein-Kontakt)\n",
    s.resets, s.runs))
  if s.mean_life then
    io.write(string.format("  Lebensdauer      Mittel %.1f s, %s der Leben unter %d s\n",
      s.mean_life, pct(s.short_life_share), report.SHORT_LIFE))
    io.write(string.format("  Fress-Heilung    %.0f je Lauf gegen %.0f Raidschaden\n",
      s.eat_heal / s.runs, s.dmg_sum / s.runs))
  end
  if s.mean_kick_latency then
    io.write(string.format("  Tritt-Latenz     %.1f s (Mittel, nur getretene Kanaele)\n",
      s.mean_kick_latency))
  end
  local reasons = {}
  for k, v in pairs(s.reasons) do reasons[#reasons + 1] = k .. "=" .. v end
  table.sort(reasons)
  if #reasons > 0 then io.write("  Ausgaenge        " .. table.concat(reasons, " ") .. "\n") end
  if s.diag then
    io.write(string.format("  Lebensdauer am Boss (Mittel) %.1f s (GDD-Modell: 5-15 s)\n",
      s.diag.mean_life))
    io.write(string.format("  DPS je lebendem Spieler      %.2f (GDD-Modell: ~3,5)\n",
      s.diag.dps_per_alive))
  end
  os.exit(0)
end

-- ---------------------------------------------------------------------------
-- Zellenliste: EINE Reihenfolge fuer beide Matrix-Modi. Der Richtungstest ist
-- die Teilmenge mit festem Laufweg und behaelt die Zellindizes der vollen
-- Matrix — damit sind die Seeds identisch und beide Laeufe vergleichbar.
-- ---------------------------------------------------------------------------
local NS = { 5, 10, 20, 40 }
-- Runde 20: Laufweg-Achse 10/14/18/22 -> 12/16/20/24, weil model.walk_time()
-- jetzt den 2-s-Wiederbelebungskanal mitrechnet (16 s statt 14). Die
-- Zellindizes und damit die Seeds bleiben; die Welten sind trotzdem andere
-- als vor Runde 20 — Vergleiche mit aelteren Berichten nur mit Vorbehalt.
local QUICK_WALK = 16 -- = model.walk_time(), per Test festgenagelt
-- Die Spielsim hat keine Laufweg-Achse: der Weg ist echte Geometrie
-- (game/data/map.lua). Ihre Matrix ist N x Krits x Profil.
local WALKS = SPIEL and { QUICK_WALK } or { 12, 16, 20, 24 }
local AGENTS = SPIEL and { "kopflos", "typisch", "turtle" }
                     or { "unkoordiniert", "koordiniert", "turtle" }

local all_cells, cells_for_run = {}, {}
do
  local idx = 0
  for _, agent in ipairs(AGENTS) do
    for _, n in ipairs(NS) do
      for _, walk in ipairs(WALKS) do
        for _, crits in ipairs({ true, false }) do
          idx = idx + 1
          all_cells[idx] = { idx = idx, agent = agent, n = n,
                             walk = walk, crits = crits }
        end
      end
    end
  end
  for _, c in ipairs(all_cells) do
    if opts.mode == "sweep" or c.walk == QUICK_WALK then
      cells_for_run[#cells_for_run + 1] = c
    end
  end
end

local function cell_seed(c) return opts.seed * 1000000 + c.idx * 10000000 end

local function compute(subset, progress)
  local out = {}
  for k, c in ipairs(subset) do
    local s = run_cell(c.agent, c.n, c.walk, c.crits, opts.runs, cell_seed(c))
    out[c.idx] = s
    if progress then progress(k, #subset, c, s) end
  end
  return out
end

-- Kindmodus (Runde 20): Sharding nach LAUFINDEX statt Zellindex. Kind k
-- rechnet in JEDER Zelle die Laeufe r mit (r-1) % parts == k-1. Vorher bekam
-- jedes Kind ganze Zellen, und eine N=40-Zelle kostet das Achtfache einer
-- N=5-Zelle — alle warteten auf ein Kind. Der Seed haengt an (Zelle, r),
-- seriell und parallel bleiben bitgleich.
local function compute_part(part, parts, progress)
  local out = {}
  for k, c in ipairs(cells_for_run) do
    local mine = {}
    for r = 1, opts.runs do
      if (r - 1) % parts == part - 1 then
        mine[r] = run_one(c.agent, c.n, c.walk, c.crits, cell_seed(c) + r)
      end
    end
    out[c.idx] = mine
    if progress then progress(k, #cells_for_run, c, mine) end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Kindmodus: nur jede n-te Zelle rechnen, Ergebnis als Lua-Tabelle nach stdout
-- ---------------------------------------------------------------------------
local function serialize(v)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "0/0" end
    return string.format("%.17g", v)
  elseif t == "string" then return string.format("%q", v)
  elseif t == "boolean" then return tostring(v)
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = { "{" }
    for _, k in ipairs(keys) do
      local kk = type(k) == "number" and ("[" .. k .. "]")
                 or ("[" .. string.format("%q", k) .. "]")
      parts[#parts + 1] = kk .. "=" .. serialize(v[k]) .. ","
    end
    parts[#parts + 1] = "}"
    return table.concat(parts)
  end
  error("nicht serialisierbar: " .. t)
end

if opts.part then
  local t0 = os.clock()
  local res = compute_part(opts.part, opts.parts, function(k, total, c, mine)
    local wins, runs = 0, 0
    for _, r in pairs(mine) do runs = runs + 1; if r.win then wins = wins + 1 end end
    note(string.format("  [Teil %d] %d/%d  %-13s N=%2d krits=%-3s  %d/%d Siege  (%.0f s)\n",
      opts.part, k, total, c.agent, c.n, c.crits and "an" or "aus",
      wins, runs, os.clock() - t0))
  end)
  io.write("return ", serialize(res), "\n")
  os.exit(0)
end

-- ---------------------------------------------------------------------------
-- Elternmodus: entweder selbst rechnen oder auf Kindprozesse verteilen
-- ---------------------------------------------------------------------------
local function interpreter()
  local k = 0
  while arg[k - 1] ~= nil do k = k - 1 end
  return arg[k] or "lua"
end

local function quoted(s)
  if s:find("[ \t]") then return '"' .. s .. '"' end
  return s
end

local function child_command(k, jobs)
  local parts = { quoted(interpreter()), quoted(arg[0] or "sim/main.lua") }
  for _, a in ipairs(raw) do parts[#parts + 1] = quoted(a) end
  parts[#parts + 1] = "--part"
  parts[#parts + 1] = k .. "/" .. jobs
  local cmd = table.concat(parts, " ")
  -- cmd.exe frisst die aeusseren Anfuehrungszeichen, wenn der Befehl mit
  -- einem Zitat beginnt — eine zusaetzliche Klammer haelt ihn zusammen.
  if package.config:sub(1, 1) == "\\" and cmd:sub(1, 1) == '"' then
    cmd = '"' .. cmd .. '"'
  end
  return cmd
end

local loadchunk = loadstring or load
local merged

if opts.jobs > 1 then
  local jobs = math.min(opts.jobs, #cells_for_run)
  io.write(string.format("%d Zellen auf %d Prozesse verteilt ...\n",
    #cells_for_run, jobs))
  io.flush()
  local handles = {}
  for k = 1, jobs do
    handles[k] = assert(io.popen(child_command(k, jobs), "r"),
                        "Kindprozess liess sich nicht starten")
  end
  -- Laeufe je Zelle aus allen Kindern zusammenfuehren, dann verdichten
  local raw_by_cell = {}
  for k = 1, jobs do
    local text = handles[k]:read("*a") or ""
    handles[k]:close()
    local chunk = loadchunk(text, "=teil" .. k)
    if not chunk then
      io.write("Teil ", k, " lieferte keine Tabelle:\n", text:sub(1, 500), "\n")
      os.exit(3)
    end
    for idx, runs in pairs(chunk()) do
      raw_by_cell[idx] = raw_by_cell[idx] or {}
      for r, res in pairs(runs) do raw_by_cell[idx][r] = res end
    end
  end
  merged = {}
  for _, c in ipairs(cells_for_run) do
    local list = raw_by_cell[c.idx]
    if list then
      local ordered = {}
      for r = 1, opts.runs do
        if not list[r] then
          io.write("Zelle ", c.idx, ": Lauf ", r, " fehlt — Lauf abgebrochen.\n")
          os.exit(3)
        end
        ordered[r] = list[r]
      end
      merged[c.idx] = summarize_cell(ordered, c.n)
    end
  end
else
  merged = compute(cells_for_run, function(k, total, c, s)
    io.write(string.format("[%2d/%d] %-13s N=%2d laufweg=%2d krits=%-3s  sieg=%s\n",
      k, total, c.agent, c.n, c.walk, c.crits and "an" or "aus", pct(s.win_rate)))
    io.flush()
  end)
end

-- Fehlende Zellen sind ein harter Fehler: lieber kein Bericht als ein
-- Bericht mit Loechern, den jemand fuer vollstaendig haelt.
for _, c in ipairs(cells_for_run) do
  if not merged[c.idx] then
    io.write("Zelle ", c.idx, " fehlt im Ergebnis — Lauf abgebrochen.\n")
    os.exit(3)
  end
end

-- verschachtelte Sicht fuer report.evaluate und die Belegmatrizen
local cells = {}
for _, c in ipairs(cells_for_run) do
  cells[c.agent] = cells[c.agent] or {}
  cells[c.agent][c.n] = cells[c.agent][c.n] or {}
  cells[c.agent][c.n][c.walk] = cells[c.agent][c.n][c.walk] or {}
  cells[c.agent][c.n][c.walk][c.crits and "an" or "aus"] = merged[c.idx]
end

local best_walk = QUICK_WALK
if opts.mode == "sweep" then
  -- Laufweg fixieren: kleinster Wert, bei dem F1 UND F5 fuer alle N halten;
  -- gibt es keinen, der mit den wenigsten Verletzungen. (Historische
  -- Absicherung — der Wert ist seit Runde 6 per Rob-Entscheid fest.)
  local best_score = -1
  for _, walk in ipairs(WALKS) do
    local score = 0
    for _, n in ipairs(NS) do
      local s = cells["koordiniert"][n][walk]["an"]
      if s.win_rate >= 0.60 and s.win_rate <= 0.90 then score = score + 1 end
      local md = s.median_win_duration
      if md and md >= 6 * 60 and md <= 13 * 60 then score = score + 1 end
    end
    if score > best_score then best_score, best_walk = score, walk end
  end
end

local f = report.evaluate(cells, best_walk, NS, NAMES)

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

local function pctci(s)
  return string.format("%s +/-%.1f", pct(s.win_rate),
    report.ci95(s.win_rate, s.runs) * 100)
end

if SPIEL then
  w("# Richtungstest — Spielsimulation (%s)\n", opts.date)
  w("%d Laeufe je Zelle, %d Zellen: N x Krits x Bot-Profil (typisch = der Raid, gegen den balanciert wird; kopflos = Gegenprobe; turtle = Anti-Stall-Gate). Die Spielsim game/gamesim laeuft headless in reinem LuaJIT (sim/gamerun.lua, Runde 20); der Laufweg ist echte Kartengeometrie, kein Parameter.\n",
    opts.runs, #cells_for_run)
elseif opts.mode == "quick" then
  w("# Richtungstest — Headless-Sim (%s)\n", opts.date)
  w("%d Laeufe je Zelle, %d Zellen: N x Krits x Agent bei festem Laufweg %d s (= model.walk_time(), seit Runde 6 per Rob-Entscheid fest, #96). Deckt F1-F6 und das Turtle-Gate ab; die volle Matrix variiert zusaetzlich den Laufweg und liefert nur Belegmatrizen.\n",
    opts.runs, #cells_for_run, best_walk)
else
  w("# M1-Validierungsbericht — Headless-Sim (%s)\n", opts.date)
  w("%d Laeufe je Zelle, Matrix: N x Laufweg x Krits x Agent (GDD 17.2).\n", opts.runs)
  w("**Fixierter Laufweg: %d s** (kleinster Wert mit maximaler F1+F5-Erfuellung).\n", best_walk)
end
w("Gesamt-Todesstrafe = Respawn-Timer(N) + Laufweg: N=5 -> %.0f s, N=40 -> %.0f s.\n",
  model.respawn_timer(5) + best_walk, model.respawn_timer(40) + best_walk)
w("Alle Siegquoten mit 95-%%-Vertrauensbereich (+/- pp); bei %d Laeufen sind das rund %.1f pp bei einer Quote um 75 %%.\n",
  opts.runs, report.ci95(0.75, opts.runs) * 100)

w("\n## F-Kriterien (GDD 13.3) bei Laufweg %d s\n", best_walk)
w("| # | Kriterium | Ergebnis | Detail |")
w("|---|---|---|---|")
local names = {
  "F1 " .. NAMES.good .. " gewinnt zuverlaessig (60-90 %)",
  "F2 " .. NAMES.bad .. " verliert meist (<= 35 %)",
  "F3 Fressen ist der Hebel (<= 10 % ohne Unterbrechung)",
  "F4 Krits entscheiden nichts (<= 5 pp)",
  "F5 Median-Siegtry 6-13 min",
  "F6 Skalierung fair (Spread <= 15 pp)",
  string.format("F7 Sterben ist Teil, nicht alles (Lebensdauer >= %d s, <= %.0f %% unter %d s)",
    report.F7_MIN_LIFE, report.F7_MAX_SHORT * 100, report.SHORT_LIFE),
}
for k = 1, 7 do
  w("| F%d | %s | %s | %s |", k, names[k], f[k].ok and "BESTANDEN" or "**VERLETZT**", f[k].detail)
end
w("| T | Turtle verliert per Zeitlimit (> 95 %%) | %s | %s |",
  f.turtle.ok and "BESTANDEN" or "**VERLETZT**", f.turtle.detail)

local walks_shown = (opts.mode == "sweep") and WALKS or { best_walk }
for _, agent in ipairs(AGENTS) do
  w("\n## Siegquoten %s (Krits an)\n", agent)
  local header = "| N \\ Laufweg |"
  local sep = "|---|"
  for _, wv in ipairs(walks_shown) do
    header = header .. string.format(" %d s |", wv)
    sep = sep .. "---|"
  end
  w(header); w(sep)
  for _, n in ipairs(NS) do
    local row = string.format("| %d |", n)
    for _, wv in ipairs(walks_shown) do
      row = row .. string.format(" %s |", pctci(cells[agent][n][wv]["an"]))
    end
    w(row)
  end
end

w("\n## Kennzahlen %s (Krits an, Laufweg %d s)\n", NAMES.good, best_walk)
w("| N | Siegquote | Median-Siegtry | Uptime | Tode/Lauf | Fress-Kanaele | unterbrochen | Charges |")
w("|---|---|---|---|---|---|---|---|")
for _, n in ipairs(NS) do
  local s = cells[NAMES.good][n][best_walk]["an"]
  w("| %d | %s | %s | %s | %.1f | %.2f | %s | %.1f |",
    n, pctci(s),
    s.median_win_duration and string.format("%.1f min", s.median_win_duration / 60) or "-",
    pct(s.mean_uptime), s.mean_deaths, s.eat_channels / s.runs,
    pct(s.eat_interrupted / math.max(1, s.eat_channels)), s.charges / s.runs)
end

if SPIEL then
  w("\n## Sterben und Fressen %s (Krits an)\n", NAMES.good)
  w("| N | Lebensdauer (Mittel) | Leben < %d s | Tritt-Latenz | Fress-Heilung/Lauf | Raidschaden/Lauf | Klassenwechsel/Lauf | Ausgaenge |", report.SHORT_LIFE)
  w("|---|---|---|---|---|---|---|---|")
  for _, n in ipairs(NS) do
    local s = cells[NAMES.good][n][best_walk]["an"]
    local reasons = {}
    for k, v in pairs(s.reasons) do reasons[#reasons + 1] = k .. " " .. v end
    table.sort(reasons)
    w("| %d | %s | %s | %s | %.0f | %.0f | %.1f | %s |",
      n, s.mean_life and string.format("%.1f s", s.mean_life) or "-",
      s.short_life_share and pct(s.short_life_share) or "-",
      s.mean_kick_latency and string.format("%.1f s", s.mean_kick_latency) or "-",
      s.eat_heal / s.runs, s.dmg_sum / s.runs, s.class_changes / s.runs,
      table.concat(reasons, ", "))
  end
end

w("\n## Klassenverteilung der Sieglaeufe (%s, alle Zellen)\n", NAMES.good)
local class_totals, total = {}, 0
for _, n in ipairs(NS) do
  for _, wv in ipairs(walks_shown) do
    for _, ck in ipairs({ "an", "aus" }) do
      for cl, k in pairs(cells[NAMES.good][n][wv][ck].class_wins) do
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

local all_ok = f[1].ok and f[2].ok and f[3].ok and f[4].ok and f[5].ok and f[6].ok
               and f[7].ok and f.turtle.ok
os.exit(all_ok and 0 or 1)
