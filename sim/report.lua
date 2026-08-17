-- sim/report.lua — Aggregation der Sim-Laeufe und F1-F6-Bewertung (GDD 13.3).

local R = {}

local function median(list)
  if #list == 0 then return nil end
  local s = {}
  for i, v in ipairs(list) do s[i] = v end
  table.sort(s)
  local m = math.floor(#s / 2)
  if #s % 2 == 1 then return s[m + 1] end
  return (s[m] + s[m + 1]) / 2
end
R.median = median

-- Laufliste einer Zelle -> Kennzahlen
function R.summarize(results)
  local s = {
    runs = #results, wins = 0,
    durations = {}, win_durations = {},
    uptime_sum = 0, deaths_sum = 0,
    eat_channels = 0, eat_interrupted = 0, eat_completed = 0,
    charges = 0, crit_kills = 0,
    wins_without_interrupt = 0, runs_without_interrupt = 0,
    class_wins = {},
  }
  for _, r in ipairs(results) do
    if r.win then
      s.wins = s.wins + 1
      s.win_durations[#s.win_durations + 1] = r.duration
      for cl, k in pairs(r.class_counts) do
        s.class_wins[cl] = (s.class_wins[cl] or 0) + k
      end
    end
    s.durations[#s.durations + 1] = r.duration
    s.uptime_sum = s.uptime_sum + r.uptime
    s.deaths_sum = s.deaths_sum + r.c.deaths
    s.eat_channels = s.eat_channels + r.c.eat_channels
    s.eat_interrupted = s.eat_interrupted + r.c.eat_interrupted
    s.eat_completed = s.eat_completed + r.c.eat_completed
    s.charges = s.charges + r.c.charges
    s.crit_kills = s.crit_kills + r.c.crit_kills
    if r.c.eat_interrupted == 0 then
      s.runs_without_interrupt = s.runs_without_interrupt + 1
      if r.win then s.wins_without_interrupt = s.wins_without_interrupt + 1 end
    end
  end
  s.win_rate = s.wins / math.max(1, s.runs)
  s.median_duration = median(s.durations)
  s.median_win_duration = median(s.win_durations)
  s.mean_uptime = s.uptime_sum / math.max(1, s.runs)
  s.mean_deaths = s.deaths_sum / math.max(1, s.runs)
  return s
end

-- Diagnose gegen das Attritionsmodell (GDD 13.1): mittlere Lebensdauer am
-- Boss und DPS je lebendem Spieler, aus den Zaehlern eines Laufs abgeleitet.
function R.diagnostics(results, n)
  local life_sum, dps_sum, k = 0, 0, 0
  for _, r in ipairs(results) do
    local alive_seconds = r.uptime * n * r.duration
    if r.c.deaths > 0 and alive_seconds > 0 then
      life_sum = life_sum + alive_seconds / r.c.deaths
      dps_sum = dps_sum + r.c.dmg_to_hogger / alive_seconds
      k = k + 1
    end
  end
  if k == 0 then return nil end
  return { mean_life = life_sum / k, dps_per_alive = dps_sum / k }
end

-- F1-F6 (GDD 13.3) bei fixierter Todesstrafe.
-- cells: cells[agent][n][penalty][crits_key] = summary  (crits_key "an"/"aus")
function R.evaluate(cells, penalty, ns)
  local f = {}
  local function cell(agent, n, crits_key)
    return cells[agent] and cells[agent][n] and cells[agent][n][penalty]
           and cells[agent][n][penalty][crits_key]
  end

  -- F1: koordiniert gewinnt zuverlaessig (60-90 % bei jedem N)
  local f1_ok, f1_detail = true, {}
  for _, n in ipairs(ns) do
    local s = cell("koordiniert", n, "an")
    local wr = s and s.win_rate or 0
    f1_detail[#f1_detail + 1] = string.format("N=%d: %.1f%%", n, wr * 100)
    if wr < 0.60 or wr > 0.90 then f1_ok = false end
  end
  f[1] = { ok = f1_ok, detail = table.concat(f1_detail, " · ") }

  -- F2: unkoordiniert verliert meist (<= 35 %)
  local f2_ok, f2_detail = true, {}
  for _, n in ipairs(ns) do
    local s = cell("unkoordiniert", n, "an")
    local wr = s and s.win_rate or 0
    f2_detail[#f2_detail + 1] = string.format("N=%d: %.1f%%", n, wr * 100)
    if wr > 0.35 then f2_ok = false end
  end
  f[2] = { ok = f2_ok, detail = table.concat(f2_detail, " · ") }

  -- F3: Fressen ist der Hebel — unkoordinierte Siege ohne Unterbrechung
  -- bei N >= 10 duerfen 10 % (der Laeufe ohne Unterbrechung) nicht uebersteigen
  local f3_ok, f3_detail = true, {}
  for _, n in ipairs(ns) do
    if n >= 10 then
      local s = cell("unkoordiniert", n, "an")
      local base = s and s.runs_without_interrupt or 0
      local rate = (base > 0) and (s.wins_without_interrupt / base) or 0
      f3_detail[#f3_detail + 1] = string.format("N=%d: %.1f%% (Basis %d)",
        n, rate * 100, base)
      if rate > 0.10 then f3_ok = false end
    end
  end
  f[3] = { ok = f3_ok, detail = table.concat(f3_detail, " · ") }

  -- F4: Krits entscheiden nichts — Delta an/aus <= 5 pp IM MITTEL ueber
  -- alle Zellen (GDD 13.3, Rob-Entscheid Issue #6). Einzelzellen duerfen
  -- streuen, solange beide Krit-Welten der Koordinierten im F1-Band
  -- bleiben. Der alte Checker pruefte je Zelle und war strenger als das GDD.
  local f4_ok, f4_detail = true, {}
  local delta_sum, delta_cells = 0, 0
  for _, agent in ipairs({ "koordiniert", "unkoordiniert" }) do
    for _, n in ipairs(ns) do
      local a = cell(agent, n, "an")
      local b = cell(agent, n, "aus")
      if a and b then
        local delta = math.abs(a.win_rate - b.win_rate)
        delta_sum = delta_sum + delta
        delta_cells = delta_cells + 1
        f4_detail[#f4_detail + 1] = string.format("%s N=%d: %.1f pp",
          agent:sub(1, 2), n, delta * 100)
        if agent == "koordiniert" then
          if a.win_rate < 0.60 or a.win_rate > 0.90
             or b.win_rate < 0.60 or b.win_rate > 0.90 then
            f4_ok = false
          end
        end
      end
    end
  end
  local f4_mean = delta_cells > 0 and delta_sum / delta_cells or 0
  if f4_mean > 0.05 then f4_ok = false end
  table.insert(f4_detail, 1, string.format("Mittel %.1f pp", f4_mean * 100))
  f[4] = { ok = f4_ok, detail = table.concat(f4_detail, " · ") }

  -- F5: Median-Siegtry im Fenster 6-13 min (koordiniert)
  local f5_ok, f5_detail = true, {}
  for _, n in ipairs(ns) do
    local s = cell("koordiniert", n, "an")
    local md = s and s.median_win_duration
    if md then
      f5_detail[#f5_detail + 1] = string.format("N=%d: %.1f min", n, md / 60)
      if md < 6 * 60 or md > 13 * 60 then f5_ok = false end
    else
      f5_detail[#f5_detail + 1] = string.format("N=%d: keine Siege", n)
      f5_ok = false
    end
  end
  f[5] = { ok = f5_ok, detail = table.concat(f5_detail, " · ") }

  -- F6: Skalierung fair — Spread zwischen kleinstem und groesstem N
  -- <= 15 pp (GDD 13.3: "zwischen N=5 und N=40"). Der alte Checker nahm
  -- max-min ueber ALLE N und war strenger als das GDD; die volle Spanne
  -- bleibt als Zusatzinfo im Detail stehen.
  local lo, hi = 1, 0
  for _, n in ipairs(ns) do
    local s = cell("koordiniert", n, "an")
    local wr = s and s.win_rate or 0
    if wr < lo then lo = wr end
    if wr > hi then hi = wr end
  end
  local s_first = cell("koordiniert", ns[1], "an")
  local s_last = cell("koordiniert", ns[#ns], "an")
  local spread = math.abs((s_first and s_first.win_rate or 0)
                          - (s_last and s_last.win_rate or 0))
  f[6] = { ok = spread <= 0.15,
           detail = string.format(
             "Spread N=%d<->N=%d %.1f pp (alle N: %.1f-%.1f %%)",
             ns[1], ns[#ns], spread * 100, lo * 100, hi * 100) }

  -- Turtle-Gate (GDD 17.2 Punkt 4): > 95 % Zeitlimit-Niederlagen in jeder Zelle
  local turtle_ok, turtle_detail = true, {}
  for _, n in ipairs(ns) do
    for _, ck in ipairs({ "an", "aus" }) do
      local s = cell("turtle", n, ck)
      if s then
        local loss_rate = 1 - s.win_rate
        if loss_rate <= 0.95 then turtle_ok = false end
        turtle_detail[#turtle_detail + 1] = string.format(
          "N=%d/%s: %.1f%% Niederlagen, %.1f Tode/Lauf", n, ck,
          loss_rate * 100, s.mean_deaths)
      end
    end
  end
  f.turtle = { ok = turtle_ok, detail = table.concat(turtle_detail, " · ") }

  return f
end

return R
