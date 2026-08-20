-- game/gamesim/announcer.lua — Leeroy als Announcer (GDD 10.4): ersetzt den
-- gestrichenen Chat vollstaendig. Liest die Ereignisse des Ticks und haengt
-- gedrosselte leeroy_line-Events an (max. 1 Kommentar je Drossel-Fenster).
-- Zeilenwahl ueber den Host-RNG: rein kosmetisch, deterministisch je Seed.

local model = require("sim.model")
local events = require("game.gamesim.events")

local A = {}

-- Muss zu step.ALLY_SLOT passen (dort aus ABILITIES abgeleitet; der
-- Require-Zyklus step->announcer verhindert die Ableitung hier).
-- Konsistenz sichert tests/unit_gamesim.lua.
local HEALERS = { priest = true, paladin = true, druid = true }
A.HEALERS = HEALERS
local MILESTONES = { 0.75, 0.5, 0.25, 0.10 }
local MILESTONE_LINE = { 7, 8, 9, 10 }

local function say(state, ev, line_id)
  events.push(ev, state.tick, "leeroy_line", "leeroy", line_id, nil, nil)
  state.ann.last_line_t = state.time
end

local function pick(state, from, to)
  return state.rng:range(from, to)
end

function A.process(state, ev)
  if not state.ann then
    state.ann = { last_line_t = -100, last_alarm_t = -100,
                  last_charge_pid = nil, last_charge_t = -100,
                  milestones = {}, try_had_interrupt = false,
                  trys_without_interrupt = 0, kragen_pending = false }
  end
  local ann = state.ann
  local throttle = model.p("leeroy_announcer_throttle")
  local gate_open = state.time - ann.last_line_t >= throttle

  local count = #ev -- nur die Original-Events dieses Ticks betrachten
  for i = 1, count do
    local e = ev[i]
    if e.ev == "try_start" then
      ann.milestones = {}
      ann.try_had_interrupt = false
      if ann.kragen_pending then
        ann.kragen_pending = false
        say(state, ev, 25) -- der Kragen platzt (Sicherheitsnetz, GDD 10.4)
      end
    elseif e.ev == "eat_start" then
      -- Fress-Alarm: eigener, kuerzerer Takt — das ist Pflicht-Kommunikation
      if state.time - ann.last_alarm_t >= 6 then
        ann.last_alarm_t = state.time
        say(state, ev, pick(state, 2, 6))
      end
    elseif e.ev == "eat_interrupt" then
      ann.try_had_interrupt = true
    elseif e.ev == "charge" then
      ann.last_charge_pid = e.dst
      ann.last_charge_t = state.time
    elseif e.ev == "ding" then
      say(state, ev, 29)
    elseif e.ev == "try_end" then
      if (e.val or 0) == 0 then
        if ann.try_had_interrupt then
          ann.trys_without_interrupt = 0
        else
          ann.trys_without_interrupt = ann.trys_without_interrupt + 1
          if ann.trys_without_interrupt >= model.p("leeroy_kragen_trys") then
            ann.kragen_pending = true
            ann.trys_without_interrupt = 0
          end
        end
        -- Zeilenwahl nach Ursache (Runde 17). Vorher lief JEDER verlorene
        -- Try ueber die Wipe-Zeilen — auch ein abgelaufenes Zeitlimit mit
        -- lebendem, pruegelndem Raid.
        -- DETERMINISMUS: jeder Zweig zieht GENAU EINEN Wert aus dem RNG.
        -- Ein Zweig ohne pick() wuerde den Krit- und Loot-Strom des ganzen
        -- Abends gegenueber heute verschieben.
        local from, to = 21, 24 -- echter Wipe
        if e.reason == "no_contact" then
          from, to = 36, 37
        elseif e.reason == "timeout" then
          from, to = 38, 39
        end
        say(state, ev, pick(state, from, to))
      end
    elseif e.ev == "mob_death_by" and gate_open then
      gate_open = false
      say(state, ev, e.dst == "boar" and 18 or 14)
    elseif e.ev == "death" and gate_open then
      -- Spielertode: stichprobenartig, kontextsensitiv (GDD 10.4)
      local p = state.players[e.src]
      if p and not p.is_leeroy then
        gate_open = false
        local line
        if ann.last_charge_pid == e.src
           and state.time - ann.last_charge_t < 3 then
          line = 12
        elseif p.class and HEALERS[p.class]
               and state.time - (p.last_heal_t or -100) < 5 then
          line = 15
        elseif p.deaths >= 5 then
          line = 16
        else
          line = ({ 11, 17, 20 })[pick(state, 1, 3)]
        end
        say(state, ev, line)
      end
    elseif e.ev == "crit_kill" and gate_open then
      gate_open = false
      say(state, ev, 13)
    end
  end

  -- HP-Meilensteine 75/50/25/10 (GDD 10.4): eskalierende Euphorie
  local h = state.hogger
  if h.hp > 0 and h.max_hp > 0 then
    local frac = h.hp / h.max_hp
    for i, m in ipairs(MILESTONES) do
      if frac <= m and not ann.milestones[i] then
        ann.milestones[i] = true
        say(state, ev, MILESTONE_LINE[i])
      end
    end
  end
end

return A
