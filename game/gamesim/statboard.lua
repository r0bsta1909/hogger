-- game/gamesim/statboard.lua — Statistik-Tafel (GDD Kap. 11): zweispaltig
-- Hogger/Schlachtzug inkl. Titel und Sprung-Zaehler. Reines Lua; wird von
-- der Sim am Try-Ende gebaut (bevor begin_try die Zaehler zuruecksetzt)
-- und haengt als e.board am try_end-Event (nicht im JSONL serialisiert).

local model = require("sim.model")

local B = {}

-- Maximum ueber die Spieler; deterministisch (ipairs, Gleichstand: kleinere ID)
local function max_stat(state, field)
  local best, best_v = nil, 0
  for _, p in ipairs(state.players) do
    local e = state.stats.players[p.id]
    local v = e and e[field] or 0
    if v > best_v then best, best_v = p, v end
  end
  return best, best_v
end

local function max_player_field(state, field)
  local best, best_v = nil, 0
  for _, p in ipairs(state.players) do
    local v = p[field] or 0
    if v > best_v then best, best_v = p, v end
  end
  return best, best_v
end

-- Kopfzeile je Ausgang. Bis Runde 16 stand hier
--   won and "SIEG" or (cause and "Abbruch" or "Wipe")
-- und das war fuer zwei von drei Verlustfaellen schlicht falsch herum: ein
-- abgelaufenes Zeitlimit (cause == nil) hiess "Wipe", ein echter Raid-Wipe
-- hiess "Abbruch". Rob las "Wipe", waehrend sein Raid lebte und zuschlug.
local HEADER = {
  win        = "SIEG",
  wipe       = "Wipe",
  no_contact = "Abbruch: kein Kontakt",
  -- Runde 18: die Frist laeuft nicht mehr still ab, Hogger wird langweilig
  -- und raeumt auf. Der Grund im Log bleibt technisch "timeout" — die Uhr
  -- ist die Ursache, der Enrage ist, was man davon sieht.
  timeout    = "Enrage",
}

function B.build(state, won, reason)
  local s = state.stats
  local h = s.hogger
  local hogger = {}
  local function hrow(label, value)
    hogger[#hogger + 1] = { label, tostring(value) }
  end
  hrow("Gesamtschaden", math.floor(h.dmg + 0.5))
  hrow("Spieler getoetet", h.kills)
  hrow("davon kritisch zerschmettert", h.crit_kills)
  hrow("Leichen gefressen", h.eaten)
  hrow("Geheilte HP", math.floor(h.healed + 0.5))
  hrow("Unterbrechungen kassiert", h.interrupts)
  hrow("Charges", h.charges)

  -- Rest-HP: beim Wipe gross inszeniert ("Er hatte noch 4 %.", GDD 11).
  -- Bei einem Abbruch (Runde 10, #124) steht der Grund davor — Rob soll nicht
  -- raten muessen, warum der Try auf einmal vorbei war.
  -- Rueckfall auf reset_cause, solange ein Aufrufer den Grund nicht mitgibt
  local cause = reason or state.hogger.reset_cause or (won and "win" or nil)
  local big = nil
  if won then
    hrow("Rest-HP", "0 (tot)")
  else
    local pct = state.hogger.max_hp > 0
      and math.max(0, state.hogger.hp) / state.hogger.max_hp * 100 or 0
    local shown = pct >= 1 and string.format("%d", math.floor(pct + 0.5))
                            or string.format("%.1f", pct)
    hrow("Rest-HP", shown .. " %")
    local rest = "Er hatte noch " .. shown .. " %."
    -- Zwei Zeilen: die Pointe wird in 1,6-facher Groesse gezeichnet, einzeilig
    -- liefe der Grundtext in schmalen Fenstern aus dem Panel (Runde 10, #126)
    if cause == "no_contact" then
      big = string.format("Er hat %d s lang niemanden erreicht.\n%s",
        math.floor(model.p("hogger_no_contact_reset") + 0.5), rest)
    elseif cause == "wipe" then
      big = string.format("Der Raid lag %d s lang.\n%s",
        math.floor(model.p("hogger_no_contact_reset") + 0.5), rest)
    elseif cause == "timeout" then
      big = "Hogger wurde langweilig.\n" .. rest
    else
      big = rest
    end
  end

  local raid = {}
  local function rrow(label, p, valtext)
    if p then
      local v = (valtext ~= "" ) and (p.name .. " - " .. valtext) or p.name
      raid[#raid + 1] = { label, v }
    end
  end
  local top_dmg, v_dmg = max_stat(state, "dmg")
  rrow("Meister Schaden", top_dmg, tostring(math.floor(v_dmg + 0.5)))
  local top_deaths, v_deaths = max_stat(state, "deaths")
  rrow("Am haeufigsten gestorben", top_deaths, tostring(v_deaths) .. "x")
  local top_ghost, v_ghost = max_stat(state, "ghost_t")
  rrow("Meiste Zeit als Geist", top_ghost, string.format("%d s", v_ghost))
  local top_eaten, v_eaten = max_stat(state, "eaten")
  rrow("Am haeufigsten gefressen worden", top_eaten, tostring(v_eaten) .. "x")
  local top_ha, v_ha = max_stat(state, "heal_aggro")
  rrow("Heal-Aggro-Tode", top_ha, tostring(v_ha))
  local top_int, v_int = max_stat(state, "interrupts")
  rrow("Meiste Unterbrechungen", top_int, tostring(v_int))
  local top_mob, v_mob = max_stat(state, "mob_kills")
  rrow("Meiste Mob-Kills", top_mob, tostring(v_mob))
  local top_kupfer, v_kupfer = max_player_field(state, "kupfer")
  rrow("Reichster Spieler", top_kupfer, tostring(v_kupfer) .. " Kupfer")
  local first = s.first_death and state.players[s.first_death]
  rrow("Erster Tod des Trys", first, "")
  if s.boar_victim then
    raid[#raid + 1] = { "Von einem Wildschwein getoetet", s.boar_victim }
  end
  local top_jump, v_jump = max_player_field(state, "jumps")
  rrow("Meiste Spruenge", top_jump, tostring(v_jump))

  -- Statistik-Titel (GDD 11); "der Zappelphilipp" fuer den Sprung-Meister
  local title_awards = {}
  local function award(p, title)
    if p then title_awards[#title_awards + 1] = { pid = p.id, title = title } end
  end
  award(top_eaten, "der Gefressene")
  award(top_ghost, "die Geisterstimme")
  award(first, "der Unvorsichtige")
  award(top_jump, "der Zappelphilipp")
  for _, p in ipairs(state.players) do
    if p.ding_done then award(p, "der Zweite") break end
  end
  local titles = {}
  for _, t in ipairs(title_awards) do
    titles[#titles + 1] = state.players[t.pid].name .. ", " .. t.title
  end

  return {
    header = (HEADER[cause] or (won and "SIEG" or "Try vorbei"))
             .. " - Try " .. tostring(state.try_nr),
    hogger = hogger, raid = raid,
    titles = titles, title_awards = title_awards, big = big,
  }
end

return B
