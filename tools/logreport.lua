-- tools/logreport.lua — Auswertung eines Host-Logs (GDD 17.3) als reines
-- Lua-Modul: parse -> analyse -> render. Runde 14, #175.
--
-- Warum ein Modul und kein Skript: so kann der Test die Zahlen pruefen,
-- ohne Dateien anzufassen — und er speist die Zeilen durch DENSELBEN
-- Serialisierer, den der Host benutzt (game/gamesim/events.to_jsonl).
-- Laeuft das Schema auseinander, wird der Test rot statt der Auswertung.

local M = {}

M.TICK = 1 / 60 -- Host-Tickrate (GDD 14): Ticks -> Sekunden
-- F7-Zielwerte (Runde 20) — dieselben wie in sim/report.lua, ohne den
-- Umweg ueber ein require: der Leser bleibt ein Werkzeug ohne Sim-Abhaengigkeit
M.SHORT_LIFE = 10
M.F7_MIN_LIFE = 30
M.F7_MAX_SHORT = 0.20

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
    eat_start = 0, eat_heal = 0, eat_seek = 0,
    eat_interrupt = 0, eat_complete = 0, complete_with_rogue = 0,
    charges = 0, charges_dodged = 0, crit_kills = 0, heal_aggro = 0, class_changes = 0,
    -- Runde 24: Rundumschlaege, Getroffene, wer beim Telegraph im Ring stand
    -- (Ausweichquote am Ring) und wen es je Spieler traf
    shocks = 0, shock_hits = 0, shock_in_ring = 0, shock_hit_by = {},
    interrupts_by = {}, dmg_by = {}, deaths_by = {}, last_heal_t = {},
    -- Runde 20: Lebensdauer je Leben (Wiederbelebung -> Tod, Sekunden) —
    -- die Messgroesse hinter F7 ("wiederbeleben, um sofort zu sterben")
    lifetimes = {},
    -- Tritt-Latenz je Kanal (Kanalbeginn -> Tritt, Sekunden); ein
    -- durchgegangener Kanal steht hier nicht, er zaehlt in eat_complete
    kick_latencies = {},
  }
end

-- iter: Iterator ueber Zeilen (z. B. datei:lines() oder ipairs-Wrapper).
-- Zeile -> parse -> analyse_events; die Sim (sim/gamerun.lua) speist ihre
-- Ereignistabellen direkt ein, damit ein gespielter Abend und ein Sim-Lauf
-- durch DIESELBE Auswertung gehen (Runde 20, eine Wahrheit pro Frage).
function M.analyse(iter)
  local bad = 0
  local function next_event()
    for line in iter do
      local e = M.parse(line)
      if e then return e end
      bad = bad + 1
    end
    return nil
  end
  local r = M.analyse_events(next_event)
  r.lines_total = r.lines_total + bad
  r.lines_bad = bad
  return r
end

-- next_event: Funktion, die je Aufruf das naechste Ereignis (Tabelle im
-- 17.3-Schema) oder nil liefert. Alternativ eine Liste von Ereignissen.
function M.analyse_events(next_event)
  if type(next_event) == "table" then
    local list, i = next_event, 0
    next_event = function() i = i + 1; return list[i] end
  end
  local trys, cur = {}, nil
  local class_of, alive, alive_since = {}, {}, {}
  local players_seen = {}
  local params, seed = {}, nil
  local lines_total = 0

  for e in next_event do
    lines_total = lines_total + 1
    -- Kennungen kommen aus dem Log als Text; die Sim liefert Zahlen
    local src = e.src ~= nil and tostring(e.src) or nil
    local dst = e.dst ~= nil and tostring(e.dst) or nil
    if e.ev == "try_start" then
      if cur then trys[#trys + 1] = cur end
      cur = new_try(tonumber(dst) or (#trys + 1), e.val, e.t)
    elseif e.ev == "param_change" and dst then
      if dst == "seed" then seed = e.val else params[dst] = e.val end
    elseif cur then
      if e.ev == "revive" then
        if src == "1" then cur.leeroy_lives = (cur.leeroy_lives or 0) + 1 end
        class_of[src] = dst or class_of[src]
        alive[src] = true
        alive_since[src] = e.t
        players_seen[src] = true
      elseif e.ev == "class_change" then
        if class_of[src] and class_of[src] ~= dst then
          cur.class_changes = cur.class_changes + 1
        end
        class_of[src] = dst or class_of[src]
      elseif e.ev == "spawn" then
        alive[src] = true
        players_seen[src] = true
      elseif e.ev == "death" then
        alive[src] = false
        players_seen[src] = true
        if alive_since[src] then
          cur.lifetimes[#cur.lifetimes + 1] = (e.t - alive_since[src]) * M.TICK
          alive_since[src] = nil
        end
        cur.deaths = cur.deaths + 1
        local c = M.CAUSE_DE[e.val or 0] or "unbekannt"
        cur.causes[c] = (cur.causes[c] or 0) + 1
        cur.deaths_by[src] = (cur.deaths_by[src] or 0) + 1
        local lh = cur.last_heal_t[src]
        if lh and (e.t - lh) * M.TICK < 5 then
          cur.heal_aggro = cur.heal_aggro + 1
        end
      elseif e.ev == "damage" then
        local v = e.val or 0
        if dst == "hogger" then
          cur.dmg_hogger = cur.dmg_hogger + v
          cur.dmg_by[src] = (cur.dmg_by[src] or 0) + v
        elseif src == "hogger" or e.art == "mob" or e.art == "add" then
          cur.dmg_taken = cur.dmg_taken + v
        else
          cur.dmg_mobs = cur.dmg_mobs + v
          cur.dmg_by[src] = (cur.dmg_by[src] or 0) + v
        end
      elseif e.ev == "heal" then
        cur.heal = cur.heal + (e.val or 0)
        if dst then cur.last_heal_t[dst] = e.t end
        -- Leeroys Handauflegung (Runde 23): art = loh, Leeroy ist Spieler 1
        if e.art == "loh" and src == "1" then
          cur.leeroy_loh = (cur.leeroy_loh or 0) + 1
        end
      elseif e.ev == "eat_seek" then
        -- Heisshunger (Runde 23): Fressen ohne Leiche in Reichweite — er
        -- laeuft erst hin. Viele Laeufe heissen: der Raid stirbt weit weg
        -- oder kitet ihn von den Leichen.
        cur.eat_seek = cur.eat_seek + 1
      elseif e.ev == "eat_start" then
        cur.eat_start = cur.eat_start + 1
        cur.eat_t0 = e.t
      elseif e.ev == "eat_tick" then
        -- Hoggers Fress-Heilung: das, was der Raid zurueckholen muss
        cur.eat_heal = cur.eat_heal + (e.val or 0)
      elseif e.ev == "eat_interrupt" then
        cur.eat_interrupt = cur.eat_interrupt + 1
        if cur.eat_t0 then
          cur.kick_latencies[#cur.kick_latencies + 1] = (e.t - cur.eat_t0) * M.TICK
          cur.eat_t0 = nil
        end
        if dst then
          cur.interrupts_by[dst] = (cur.interrupts_by[dst] or 0) + 1
        end
      elseif e.ev == "eat_complete" then
        cur.eat_complete = cur.eat_complete + 1
        cur.eat_t0 = nil
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
        -- Runde 21: val = 0 heisst verfehlt (ausgewichen), sonst getroffen
        if tonumber(e.val) == 0 then cur.charges_dodged = cur.charges_dodged + 1 end
      elseif e.ev == "shockwave" then
        -- Runde 24, vier Zeilenformen (GDD 17.3): ohne dst Telegraph (val -1)
        -- bzw. Summe (val = Getroffene); mit dst je Spieler im Ring beim
        -- Telegraph (val -1) bzw. je Getroffenem (val = Abstand)
        local v = tonumber(e.val) or 0
        if dst == nil then
          if v < 0 then cur.shocks = cur.shocks + 1
          else cur.shock_hits = cur.shock_hits + v end
        elseif v < 0 then
          cur.shock_in_ring = cur.shock_in_ring + 1
        else
          cur.shock_hit_by[dst] = (cur.shock_hit_by[dst] or 0) + 1
        end
      elseif e.ev == "crit_kill" then
        cur.crit_kills = cur.crit_kills + 1
      elseif e.ev == "hogger_reset" then
        cur.reset = dst
        cur.rest_hp = e.val
      elseif e.ev == "try_end" then
        cur.won = (e.val or 0) >= 1
        cur.reason = e.reason
        cur.rest_hp = cur.rest_hp or tonumber(dst)
        cur.dauer = (e.t - cur.t0) * M.TICK
        -- Wer beim Try-Ende noch lebt, hat sein Leben nicht "beendet": es
        -- zaehlt trotzdem, sonst waeren die Ueberlebenden unsichtbar und
        -- die mittlere Lebensdauer ein Kurz-Leben-Mass.
        for pid, t0 in pairs(alive_since) do
          cur.lifetimes[#cur.lifetimes + 1] = (e.t - t0) * M.TICK
          alive_since[pid] = nil
        end
        trys[#trys + 1] = cur
        cur = nil
      end
    end
  end
  if cur then cur.dauer = 0; trys[#trys + 1] = cur end

  -- Summen
  local sum = { deaths = 0, eat_start = 0, eat_heal = 0, eat_seek = 0,
                leeroy_loh = 0, leeroy_lives = 0,
                eat_interrupt = 0, eat_complete = 0,
                complete_with_rogue = 0, dmg_hogger = 0, dmg_mobs = 0,
                charges = 0, charges_dodged = 0, heal_aggro = 0, crit_kills = 0,
                shocks = 0, shock_hits = 0, shock_in_ring = 0,
                class_changes = 0 }
  local lifetimes, kick_latencies = {}, {}
  local causes, dmg_by, int_by, deaths_by, shock_by = {}, {}, {}, {}, {}
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
    for p, v in pairs(t.shock_hit_by) do shock_by[p] = (shock_by[p] or 0) + v end
    for _, v in ipairs(t.lifetimes) do lifetimes[#lifetimes + 1] = v end
    for _, v in ipairs(t.kick_latencies) do kick_latencies[#kick_latencies + 1] = v end
  end

  -- Raidgroesse: try_start.val ist die Skalierung beim Try-Start — bei
  -- #215-Logs stand dort eine 1, obwohl dreissig Leute spielten. Wer
  -- wirklich gespielt hat, zaehlt man an den Kennungen ab (Runde 20).
  -- Leeroy ist immer Spieler 1: host.lua und sim/gamerun.lua rufen
  -- world.add_leeroy vor dem ersten add_player. Er zaehlt nie in N (GDD 6).
  local seen = 0
  for pid in pairs(players_seen) do
    if pid ~= "1" then seen = seen + 1 end
  end

  return {
    trys = trys, sum = sum, causes = causes, dmg_by = dmg_by,
    interrupts_by = int_by, deaths_by = deaths_by, shock_hit_by = shock_by,
    class_of = class_of,
    params = params, seed = seed, wins = wins, aborts = aborts,
    total_time = total_time, win_durations = win_durations,
    lifetimes = lifetimes, kick_latencies = kick_latencies,
    lines_total = lines_total, lines_bad = 0,
    n_try = #trys, raid_n = trys[1] and trys[1].n or 0,
    players_seen = seen,
  }
end

-- Lebensdauer-Kennzahlen (Runde 20, F7): Mittel und Anteil der Leben unter
-- `short` Sekunden. Ohne Leben: nil — nicht 0, sonst liest jemand "alle
-- sterben sofort", wo niemand gestorben ist.
function M.life_stats(lifetimes, short)
  short = short or 10
  local n = #lifetimes
  if n == 0 then return nil end
  local sum, shorts = 0, 0
  for _, v in ipairs(lifetimes) do
    sum = sum + v
    if v < short then shorts = shorts + 1 end
  end
  return { mean = sum / n, short_share = shorts / n, count = n,
           median = M.median(lifetimes) }
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
  if r.sum.shocks >= 5 and r.sum.shock_in_ring > 0
     and 1 - r.sum.shock_hits / r.sum.shock_in_ring < 0.2 then
    out[#out + 1] = "Kaum jemand tritt aus dem roten Ring: hogger_shock_windup hoch (mehr Zeit zum Austreten)."
  end
  if eat_total > 0 and r.sum.eat_interrupt / eat_total < 0.5 then
    out[#out + 1] = "Das Fressen wird selten unterbrochen — fehlen Schurken, oder kommt der Tritt nicht an? (rogue_kick_cd, rogue_kick_energy)"
  end
  if r.sum.eat_complete > 0
     and r.sum.complete_with_rogue / r.sum.eat_complete > 0.5 then
    out[#out + 1] = "Meist lebte ein Schurke, als das Fressen durchging: die Unterbrecher-Rolle wird nicht gespielt. Das ist eine Ansage-Frage, kein Zahlenproblem."
  end
  if r.sum.eat_start > 0 and r.sum.eat_seek / r.sum.eat_start > 0.5 then
    out[#out + 1] = "Mehr als die Haelfte der Mahlzeiten begann mit einem Hunger-Lauf: der Raid stirbt weit weg von Hogger oder zieht ihn von den Leichen weg (eat_seek_radius, eat_seek_timeout)."
  end
  if dmg_all > 0 and r.sum.dmg_mobs / dmg_all > 0.10 then
    out[#out + 1] = "Mehr als ein Zehntel des Schadens ging an Mobs statt an Hogger: die Ambient-Mobs lenken zu stark ab."
  end
  -- Runde 20: Fressen und Sterben
  if r.sum.dmg_hogger > 0 and r.sum.eat_heal / r.sum.dmg_hogger > 0.5 then
    out[#out + 1] = string.format(
      "Das Fressen holt %.0f %% des Raidschadens zurueck: eat_heal_rate runter oder eat_channel_duration runter — mit menschlicher Tritt-Latenz kommt der Tritt nie frueh genug, um das allein zu loesen.",
      r.sum.eat_heal / r.sum.dmg_hogger * 100)
  end
  local ls = M.life_stats(r.lifetimes, M.SHORT_LIFE)
  if ls and (ls.mean < M.F7_MIN_LIFE or ls.short_share > M.F7_MAX_SHORT) then
    out[#out + 1] = string.format(
      "Man lebt im Mittel %.0f s und %.0f %% der Leben enden unter %d s (F7: >= %d s, <= %.0f %%): hogger_cleave_divisor hoch oder hogger_autohit_dmg runter — das Sterben soll Teil sein, nicht alles.",
      ls.mean, ls.short_share * 100, M.SHORT_LIFE, M.F7_MIN_LIFE, M.F7_MAX_SHORT * 100)
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
    r.n_try, tostring(r.raid_n) .. " (" .. tostring(r.players_seen or 0) .. " Spieler gesehen)",
    tostring(r.seed))
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
  w("| Hunger-Laeufe (keine Leiche in Reichweite, er lief hin) | %d | Runde 23: viele heisst, der Raid stirbt weit weg oder kitet |",
    r.sum.eat_seek)
  if r.sum.leeroy_lives > 0 then
    w("| Leeroys Handauflegung | %d in %d Leben | Runde 23: er drueckt sie unter %s HP mit Reaktionszeit — manchmal zu spaet |",
      r.sum.leeroy_loh, r.sum.leeroy_lives,
      r.params.leeroy_loh_hp_pct and string.format("%.0f %%", r.params.leeroy_loh_hp_pct * 100) or "der Schwelle")
  end
  w("| Ablenkung: Schaden an Mobs statt Hogger | %s | unter 10 %% (GDD 13.4) |",
    dmg_all > 0 and pct(r.sum.dmg_mobs / dmg_all) or "-")
  w("| Tode je Try | %.1f | Wipes sind gewollt, Dauersterben nicht |",
    r.sum.deaths / r.n_try)
  w("| davon kurz nach einer Heilung | %d | Heilung zieht Aggro (GDD 9.4) |",
    r.sum.heal_aggro)
  w("| Charges je Try | %.1f | davon ausgewichen: %s (Runde 21: die Ziellinie im Anlauf verlassen) |",
    r.sum.charges / r.n_try,
    r.sum.charges > 0 and pct(r.sum.charges_dodged / r.sum.charges) or "-")
  -- Runde 24: der Rundumschlag — Getroffene je Stoss und die Ausweichquote am
  -- Ring (wer beim Telegraph drinstand und beim Stoss nicht mehr). Alte Logs
  -- ohne Ring-Zeilen zeigen "-".
  w("| Rundumschlaege je Try | %.1f | Getroffene je Stoss: %s, am Ring ausgewichen: %s (Runde 24) |",
    r.sum.shocks / r.n_try,
    r.sum.shocks > 0 and string.format("%.1f", r.sum.shock_hits / r.sum.shocks) or "-",
    r.sum.shock_in_ring > 0
      and pct(math.max(0, 1 - r.sum.shock_hits / r.sum.shock_in_ring)) or "-")
  w("| Toedliche Krits | %d | |", r.sum.crit_kills)
  -- Runde 20 (F7): wie lange lebt man nach der Wiederbelebung, und wie oft
  -- stirbt man gleich wieder? Dazu, was das Fressen zurueckholt.
  local ls = M.life_stats(r.lifetimes, M.SHORT_LIFE)
  if ls then
    w("| Lebensdauer nach der Wiederbelebung (Mittel) | %.1f s | >= %d s (F7) |",
      ls.mean, M.F7_MIN_LIFE)
    w("| Leben unter %d s | %s | <= %.0f %% (F7) |", M.SHORT_LIFE,
      pct(ls.short_share), M.F7_MAX_SHORT * 100)
  end
  if r.sum.dmg_hogger > 0 then
    w("| Fress-Heilung gegen Raidschaden | %.0f gegen %.0f (%s zurueckgeholt) | Fressen ist der Hebel (F3) |",
      r.sum.eat_heal, r.sum.dmg_hogger, pct(r.sum.eat_heal / r.sum.dmg_hogger))
  end
  if #r.kick_latencies > 0 then
    local ksum = 0
    for _, v in ipairs(r.kick_latencies) do ksum = ksum + v end
    w("| Tritt-Latenz (Mittel, nur getretene Kanaele) | %.1f s | je kuerzer, desto weniger heilt er |",
      ksum / #r.kick_latencies)
  end
  -- Raidgroesse: die groessere der beiden Wahrheiten (try_start.val stand bei
  -- #215-Logs auf 1, waehrend dreissig Leute spielten)
  local raid_n = math.max(r.raid_n or 0, r.players_seen or 0)
  if r.total_time > 0 and raid_n > 0 then
    w("| Schaden an Hogger je Sekunde und Spieler | %.2f | Modellannahme ~3,5 (GDD 13.1) |",
      r.sum.dmg_hogger / r.total_time / raid_n)
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
  top(r.shock_hit_by, "Vom Rundumschlag getroffen je Spieler", "Treffer", "%d")

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
