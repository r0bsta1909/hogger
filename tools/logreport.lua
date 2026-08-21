-- tools/logreport.lua — Auswertung eines Host-Logs (GDD 17.3) als reines
-- Lua-Modul: parse -> analyse -> render. Runde 14, #175.
--
-- Warum ein Modul und kein Skript: so kann der Test die Zahlen pruefen,
-- ohne Dateien anzufassen — und er speist die Zeilen durch DENSELBEN
-- Serialisierer, den der Host benutzt (game/gamesim/events.to_jsonl).
-- Laeuft das Schema auseinander, wird der Test rot statt der Auswertung.

local M = {}

M.TICK = 1 / 60 -- Host-Tickrate (GDD 14): Ticks -> Sekunden

M.CAUSE_DE = {
  [1] = "Hogger-Nahkampf", [2] = "Charge", [3] = "Vicious Slice",
  [4] = "Blutung", [5] = "Wildschwein", [6] = "Wolf", [7] = "Kobold",
  [8] = "Murloc", [9] = "Gnoll-Welpe",
}
M.CLASS_DE = {
  warrior = "Krieger", paladin = "Paladin", hunter = "Jaeger",
  rogue = "Schurke", priest = "Priester", mage = "Magier",
  warlock = "Hexenmeister", druid = "Druide",
}

-- ---------------------------------------------------------------------------
-- Zeile -> Ereignis. Das Format schreiben wir selbst, deshalb genuegen
-- Muster; ein JSON-Parser waere hier Ballast.
-- ---------------------------------------------------------------------------
function M.parse(line)
  local ev = line:match('"ev":"([^"]*)"')
  if not ev then return nil end
  return {
    t = tonumber(line:match('"t":(-?[%d%.eE+-]+)')) or 0,
    ev = ev,
    src = line:match('"src":"([^"]*)"'),
    dst = line:match('"dst":"([^"]*)"'),
    val = tonumber(line:match('"val":(-?[%d%.eE+-]+)')),
    crit = line:match('"crit":(%a+)') == "true",
    art = line:match('"art":"([^"]*)"'),
    -- Grund des Try-Endes (Runde 17, GDD 17.3). Aeltere Logs haben das Feld
    -- nicht — dann bleibt es nil und wir raten hoechstens, sichtbar.
    reason = line:match('"reason":"([^"]*)"'),
  }
end

-- Ausgang eines Trys in Klartext. Zweiter Rueckgabewert sagt, ob der Grund
-- im Log STAND oder nur erschlossen wurde. Ein Bericht, der "Zeit abgelaufen"
-- behauptet, wo er es nur vermutet, ist schlimmer als "unbekannt".
M.REASON_DE = {
  win        = "Sieg",
  wipe       = "Abbruch: alle tot",
  no_contact = "Abbruch: niemand am Boss",
  -- Runde 18: die Frist endet mit dem Enrage. Der Grund im Log heisst
  -- weiter "timeout" (die Uhr ist die Ursache), der Bericht nennt beides.
  timeout    = "Enrage (Frist abgelaufen)",
}

function M.outcome(t, params)
  if t.won then return "Sieg", false end
  if t.reason then return M.REASON_DE[t.reason] or t.reason, false end
  -- Altlog ohne Grund: der Reset trug seine Ursache schon immer mit sich
  if t.reset then
    return M.REASON_DE[t.reset] or ("Abbruch: " .. tostring(t.reset)), false
  end
  -- Kein Reset-Ereignis und kein Grund: dann war es das Zeitlimit — aber das
  -- ist ein Schluss aus der Dauer, kein Protokolleintrag.
  -- Bewusst NICHT REASON_DE: ein Log ohne reason-Feld stammt aus einer
  -- Version vor Runde 17, und dort lief die Frist wirklich still ab. Einen
  -- Enrage zu behaupten, den es damals nicht gab, waere eine Erfindung.
  local limit = params and params.try_time_limit
  if limit and t.dauer and t.dauer >= limit - 2 then
    return "Zeit abgelaufen", true
  end
  return "Ende unbekannt (altes Log)", false
end

local function new_try(nr, n, tick)
  return {
    nr = nr, n = n, t0 = tick, deaths = 0, causes = {},
    dmg_hogger = 0, dmg_mobs = 0, dmg_taken = 0, heal = 0,
    eat_interrupt = 0, eat_complete = 0, complete_with_rogue = 0,
    charges = 0, crit_kills = 0, heal_aggro = 0,
    interrupts_by = {}, dmg_by = {}, deaths_by = {}, last_heal_t = {},
  }
end

-- iter: Iterator ueber Zeilen (z. B. datei:lines() oder ipairs-Wrapper)
function M.analyse(iter)
  local trys, cur = {}, nil
  local class_of, alive = {}, {}
  local params, seed = {}, nil
  local lines_total, lines_bad = 0, 0

  for line in iter do
    lines_total = lines_total + 1
    local e = M.parse(line)
    if not e then
      lines_bad = lines_bad + 1
    elseif e.ev == "try_start" then
      if cur then trys[#trys + 1] = cur end
      cur = new_try(tonumber(e.dst) or (#trys + 1), e.val, e.t)
    elseif e.ev == "param_change" and e.dst then
      if e.dst == "seed" then seed = e.val else params[e.dst] = e.val end
    elseif cur then
      if e.ev == "revive" then
        class_of[e.src] = e.dst or class_of[e.src]
        alive[e.src] = true
      elseif e.ev == "class_change" then
        class_of[e.src] = e.dst or class_of[e.src]
      elseif e.ev == "spawn" then
        alive[e.src] = true
      elseif e.ev == "death" then
        alive[e.src] = false
        cur.deaths = cur.deaths + 1
        local c = M.CAUSE_DE[e.val or 0] or "unbekannt"
        cur.causes[c] = (cur.causes[c] or 0) + 1
        cur.deaths_by[e.src] = (cur.deaths_by[e.src] or 0) + 1
        local lh = cur.last_heal_t[e.src]
        if lh and (e.t - lh) * M.TICK < 5 then
          cur.heal_aggro = cur.heal_aggro + 1
        end
      elseif e.ev == "damage" then
        local v = e.val or 0
        if e.dst == "hogger" then
          cur.dmg_hogger = cur.dmg_hogger + v
          cur.dmg_by[e.src] = (cur.dmg_by[e.src] or 0) + v
        elseif e.src == "hogger" or e.art == "mob" or e.art == "add" then
          cur.dmg_taken = cur.dmg_taken + v
        else
          cur.dmg_mobs = cur.dmg_mobs + v
          cur.dmg_by[e.src] = (cur.dmg_by[e.src] or 0) + v
        end
      elseif e.ev == "heal" then
        cur.heal = cur.heal + (e.val or 0)
        if e.dst then cur.last_heal_t[e.dst] = e.t end
      elseif e.ev == "eat_interrupt" then
        cur.eat_interrupt = cur.eat_interrupt + 1
        if e.dst then
          cur.interrupts_by[e.dst] = (cur.interrupts_by[e.dst] or 0) + 1
        end
      elseif e.ev == "eat_complete" then
        cur.eat_complete = cur.eat_complete + 1
        -- Die offene Frage aus Runde 12: lebte ein Schurke, als das
        -- Fressen durchging? Dann wurde der Tritt nicht gespielt.
        for pid, cls in pairs(class_of) do
          if cls == "rogue" and alive[pid] then
            cur.complete_with_rogue = cur.complete_with_rogue + 1
            break
          end
        end
      elseif e.ev == "charge" then
        cur.charges = cur.charges + 1
      elseif e.ev == "crit_kill" then
        cur.crit_kills = cur.crit_kills + 1
      elseif e.ev == "hogger_reset" then
        cur.reset = e.dst
        cur.rest_hp = e.val
      elseif e.ev == "try_end" then
        cur.won = (e.val or 0) >= 1
        cur.reason = e.reason
        cur.rest_hp = cur.rest_hp or tonumber(e.dst)
        cur.dauer = (e.t - cur.t0) * M.TICK
        trys[#trys + 1] = cur
        cur = nil
      end
    end
  end
  if cur then cur.dauer = 0; trys[#trys + 1] = cur end

  -- Summen
  local sum = { deaths = 0, eat_interrupt = 0, eat_complete = 0,
                complete_with_rogue = 0, dmg_hogger = 0, dmg_mobs = 0,
                charges = 0, heal_aggro = 0, crit_kills = 0 }
  local causes, dmg_by, int_by, deaths_by = {}, {}, {}, {}
  local wins, aborts, total_time, win_durations = 0, 0, 0, {}
  for _, t in ipairs(trys) do
    if t.won then wins = wins + 1; win_durations[#win_durations + 1] = t.dauer or 0 end
    if t.reset then aborts = aborts + 1 end
    total_time = total_time + (t.dauer or 0)
    for k in pairs(sum) do sum[k] = sum[k] + (t[k] or 0) end
    for c, k in pairs(t.causes) do causes[c] = (causes[c] or 0) + k end
    for p, v in pairs(t.dmg_by) do dmg_by[p] = (dmg_by[p] or 0) + v end
    for p, v in pairs(t.interrupts_by) do int_by[p] = (int_by[p] or 0) + v end
    for p, v in pairs(t.deaths_by) do deaths_by[p] = (deaths_by[p] or 0) + v end
  end

  return {
    trys = trys, sum = sum, causes = causes, dmg_by = dmg_by,
    interrupts_by = int_by, deaths_by = deaths_by, class_of = class_of,
    params = params, seed = seed, wins = wins, aborts = aborts,
    total_time = total_time, win_durations = win_durations,
    lines_total = lines_total, lines_bad = lines_bad,
    n_try = #trys, raid_n = trys[1] and trys[1].n or 0,
  }
end

function M.median(list)
  if #list == 0 then return nil end
  local s = {}
  for i, v in ipairs(list) do s[i] = v end
  table.sort(s)
  local m = math.floor(#s / 2)
  if #s % 2 == 1 then return s[m + 1] end
  return (s[m] + s[m + 1]) / 2
end

-- Die Hinweise sind der eigentliche Zweck: welcher Regler, in welche
-- Richtung. Sie folgen den Stellhebeln aus GDD 13.3.
function M.hints(r)
  local out = {}
  local n = math.max(1, r.n_try)
  local quote = r.wins / n
  local md = M.median(r.win_durations)
  local eat_total = r.sum.eat_interrupt + r.sum.eat_complete
  local dmg_all = r.sum.dmg_hogger + r.sum.dmg_mobs
  if r.n_try >= 3 and quote > 0.90 then
    out[#out + 1] = "Die Siegquote liegt ueber dem Band: hogger_hp_slope hoch (mehr Boss-HP)."
  elseif r.n_try >= 3 and quote < 0.60 then
    -- Seit Runde 17 steht der Grund im Log; die Tabelle "Trys nach Ursache"
    -- beantwortet die Frage, statt sie zu stellen.
    out[#out + 1] = "Die Siegquote liegt unter dem Band: hogger_hp_slope runter — siehe zuerst 'Trys nach Ursache'."
  end
  if md and md > 13 * 60 then
    out[#out + 1] = "Die Siegtrys dauern zu lang: hogger_hp_slope runter."
  elseif md and md < 6 * 60 then
    out[#out + 1] = "Die Siegtrys gehen zu schnell: hogger_hp_slope hoch."
  end
  if eat_total > 0 and r.sum.eat_interrupt / eat_total < 0.5 then
    out[#out + 1] = "Das Fressen wird selten unterbrochen — fehlen Schurken, oder kommt der Tritt nicht an? (rogue_kick_cd, rogue_kick_energy)"
  end
  if r.sum.eat_complete > 0
     and r.sum.complete_with_rogue / r.sum.eat_complete > 0.5 then
    out[#out + 1] = "Meist lebte ein Schurke, als das Fressen durchging: die Unterbrecher-Rolle wird nicht gespielt. Das ist eine Ansage-Frage, kein Zahlenproblem."
  end
  if dmg_all > 0 and r.sum.dmg_mobs / dmg_all > 0.10 then
    out[#out + 1] = "Mehr als ein Zehntel des Schadens ging an Mobs statt an Hogger: die Ambient-Mobs lenken zu stark ab."
  end
  return out
end

-- ---------------------------------------------------------------------------
function M.render(r, quelle, defaults)
  local out = {}
  local function w(fmt, ...)
    out[#out + 1] = select("#", ...) == 0 and fmt or string.format(fmt, ...)
  end
  local function pct(x) return string.format("%.1f %%", x * 100) end
  local function mins(s) return string.format("%.1f min", (s or 0) / 60) end

  w("# Abend-Auswertung — %s\n", quelle or "Log")
  w("%d Zeilen gelesen%s, %d Trys, Raidgroesse %s, Seed %s.\n",
    r.lines_total, r.lines_bad > 0 and (" (" .. r.lines_bad .. " unlesbar)") or "",
    r.n_try, tostring(r.raid_n), tostring(r.seed))
  if r.n_try == 0 then
    w("\nKein vollstaendiger Try im Log — nichts zu rechnen.\n")
    return table.concat(out, "\n") .. "\n"
  end

  local md = M.median(r.win_durations)
  local eat_total = r.sum.eat_interrupt + r.sum.eat_complete
  local dmg_all = r.sum.dmg_hogger + r.sum.dmg_mobs

  w("\n## Der Abend auf einen Blick\n")
  w("| Frage | Ergebnis | Zielband (GDD) |")
  w("|---|---|---|")
  w("| Siegquote | %s (%d von %d) | 60-90 %% bei koordiniertem Spiel (F1) |",
    pct(r.wins / r.n_try), r.wins, r.n_try)
  w("| Median-Siegtry | %s | 6-13 min (F5) |", md and mins(md) or "kein Sieg")
  w("| Fressen unterbrochen | %s (%d von %d Kanaelen) | moeglichst hoch (F3) |",
    eat_total > 0 and pct(r.sum.eat_interrupt / eat_total) or "-",
    r.sum.eat_interrupt, eat_total)
  w("| Durchgegangen, obwohl ein Schurke lebte | %d von %d | die offene Frage aus Runde 12 |",
    r.sum.complete_with_rogue, r.sum.eat_complete)
  w("| Ablenkung: Schaden an Mobs statt Hogger | %s | unter 10 %% (GDD 13.4) |",
    dmg_all > 0 and pct(r.sum.dmg_mobs / dmg_all) or "-")
  w("| Tode je Try | %.1f | Wipes sind gewollt, Dauersterben nicht |",
    r.sum.deaths / r.n_try)
  w("| davon kurz nach einer Heilung | %d | Heilung zieht Aggro (GDD 9.4) |",
    r.sum.heal_aggro)
  w("| Charges je Try | %.1f | |", r.sum.charges / r.n_try)
  w("| Toedliche Krits | %d | |", r.sum.crit_kills)
  if r.total_time > 0 and r.raid_n and r.raid_n > 0 then
    w("| Schaden an Hogger je Sekunde und Spieler | %.2f | Modellannahme ~3,5 (GDD 13.1) |",
      r.sum.dmg_hogger / r.total_time / r.raid_n)
  end

  -- Trys nach Ursache (Runde 17): die Frage "an der Zeit oder am Wipe
  -- gescheitert?" war bis dahin aus dem Log nicht zu beantworten.
  do
    local nach = {}
    local order = {}
    for _, t in ipairs(r.trys) do
      local text, geraten = M.outcome(t, r.params)
      local key = text .. (geraten and " (aus der Dauer geschlossen)" or "")
      if not nach[key] then nach[key] = 0; order[#order + 1] = key end
      nach[key] = nach[key] + 1
    end
    table.sort(order) -- deterministisch, nicht in pairs-Reihenfolge
    w("\n## Trys nach Ursache\n")
    w("| Ausgang | Anzahl |")
    w("|---|---|")
    for _, key in ipairs(order) do w("| %s | %d |", key, nach[key]) end
  end

  w("\n## Try fuer Try\n")
  w("| Try | Dauer | Ausgang | Hogger-Rest | Tode | Fressen (unterbrochen) | Charges |")
  w("|---|---|---|---|---|---|---|")
  for _, t in ipairs(r.trys) do
    local text, geraten = M.outcome(t, r.params)
    local ausgang = t.won and "**SIEG**"
      or (text .. (geraten and " (aus der Dauer geschlossen)" or ""))
    local et = t.eat_interrupt + t.eat_complete
    w("| %s | %s | %s | %s | %d | %d (%s) | %d |",
      tostring(t.nr), mins(t.dauer), ausgang,
      t.rest_hp and string.format("%.0f", t.rest_hp) or "-",
      t.deaths, et, et > 0 and pct(t.eat_interrupt / et) or "-", t.charges)
  end

  local function top(map, titel, kopf, fmt)
    local list = {}
    for pid, v in pairs(map) do list[#list + 1] = { pid, v } end
    if #list == 0 then return end
    table.sort(list, function(a, b)
      if a[2] ~= b[2] then return a[2] > b[2] end
      return tostring(a[1]) < tostring(b[1])
    end)
    w("\n## %s\n", titel)
    w("| Spieler | Klasse | %s |", kopf)
    w("|---|---|---|")
    for i = 1, math.min(#list, 12) do
      local pid = list[i][1]
      w("| %s | %s | " .. fmt .. " |", tostring(pid),
        M.CLASS_DE[r.class_of[pid] or ""] or "?", list[i][2])
    end
  end
  top(r.dmg_by, "Schaden je Spieler", "Schaden", "%.0f")
  top(r.interrupts_by, "Unterbrechungen je Spieler (der Tritt)", "Tritte", "%d")
  top(r.deaths_by, "Tode je Spieler", "Tode", "%d")

  if next(r.causes) then
    local list = {}
    for c, k in pairs(r.causes) do list[#list + 1] = { c, k } end
    table.sort(list, function(a, b)
      if a[2] ~= b[2] then return a[2] > b[2] end
      return a[1] < b[1]
    end)
    w("\n## Woran gestorben wurde\n")
    w("| Ursache | Tode | Anteil |")
    w("|---|---|---|")
    for _, e in ipairs(list) do
      w("| %s | %d | %s |", e[1], e[2], pct(e[2] / math.max(1, r.sum.deaths)))
    end
  end

  if defaults then
    local diff = {}
    for k, v in pairs(r.params) do
      local d = defaults[k]
      if d and math.abs(d - v) > 1e-9 then diff[#diff + 1] = { k, d, v } end
    end
    table.sort(diff, function(a, b) return a[1] < b[1] end)
    w("\n## Parameterstand des Abends\n")
    if #diff == 0 then
      w("Alle geloggten Parameter standen auf GDD-Stand.\n")
    else
      w("**%d Parameter wichen vom GDD-Stand ab** — die Zahlen oben gelten fuer DIESE Welt:\n",
        #diff)
      w("| Parameter | GDD | an diesem Abend |")
      w("|---|---|---|")
      for _, e in ipairs(diff) do
        w("| %s | %s | %s |", e[1], tostring(e[2]), tostring(e[3]))
      end
    end
  end

  w("\n## Was das heisst\n")
  local hints = M.hints(r)
  if #hints == 0 then
    w("Der Abend liegt in allen gemessenen Baendern. Nichts zu drehen.\n")
  else
    for _, h in ipairs(hints) do w("- %s", h) end
    w("\nWelcher Regler was tut, steht in `docs/balancing-fuer-rob.md`.\n")
  end
  return table.concat(out, "\n") .. "\n"
end

return M
