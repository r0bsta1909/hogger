-- tests/unit_gamerun.lua — Stufe 1: die Spielsimulation als Balancing-Sim
-- (sim/gamerun.lua, Runde 20). Reines Lua; laeuft mit vergiftetem love.

local T = _G.T
local gamerun = require("sim.gamerun")
local report = require("sim.report")
local model = require("sim.model")
local logreport = require("tools.logreport")

-- Ein kleiner Lauf: Ergebnisformat vollstaendig, Frist eingehalten,
-- Krit-Parameter danach wieder auf GDD-Stand
do
  local r = gamerun.run_try({ n = 3, seed = 4711, crits = false,
                              profile = "typisch", log = true })
  T.ok(type(r.win) == "boolean", "gamerun: win ist boolesch")
  T.ok(r.reason ~= nil, "gamerun: der Grund des Try-Endes steht im Ergebnis")
  T.ok(r.duration > 0 and r.duration <= model.p("try_time_limit") + 30,
    "gamerun: Dauer innerhalb der Frist plus Enrage")
  T.ok(r.c.deaths >= 0 and r.c.eat_channels >= r.c.eat_interrupted
       and r.c.eat_channels >= r.c.eat_completed,
    "gamerun: Fresszaehler konsistent")
  T.ok(r.uptime >= 0 and r.uptime <= 1, "gamerun: Uptime ist ein Anteil")
  T.ok(#r.lifetimes == r.c.deaths or r.win or r.reason ~= "timeout",
    "gamerun: jedes beendete Leben ist eine Lebensdauer")
  T.ok(r.log_hash ~= nil and #r.events > 10, "gamerun: Log-Hash und Ereignisse bei log=true")
  T.eq(model.p("crit_chance_player"), model.defaults.crit_chance_player,
    "gamerun: Krits-aus stellt die Spielerchance wieder her")
  T.eq(model.p("crit_chance_hogger"), model.defaults.crit_chance_hogger,
    "gamerun: Krits-aus stellt die Hoggerchance wieder her")
  local n = 0
  for _ in pairs(r.class_counts) do n = n + 1 end
  T.ok(n >= 1, "gamerun: Klassenverteilung der Bots gefuellt")

  -- Das Ergebnis passt unveraendert in sim/report.lua
  local s = report.summarize({ r, r })
  T.eq(s.runs, 2, "gamerun: report.summarize nimmt das Format an")
  T.ok(s.reasons[r.reason] == 2, "gamerun: Ausgaenge werden gezaehlt")
end

-- Kompakte Lebensdauer-Kennzahl: Mittel und Kurzleben-Anteil
do
  local c = report.compact_life({ 5, 15, 25 })
  T.eq(c.n, 3, "compact_life: zaehlt Leben")
  T.near(c.sum, 45, "compact_life: summiert Sekunden")
  T.eq(c.short, 1, "compact_life: zaehlt Leben unter 10 s")
  local s = report.summarize({
    { win = false, duration = 10, uptime = 0.5, class_counts = {},
      c = { deaths = 3, eat_channels = 0, eat_interrupted = 0, eat_completed = 0,
            charges = 0, crit_kills = 0, resets = 0, dmg_to_hogger = 0 },
      life = c },
  })
  T.near(s.mean_life, 15, "summarize: mittlere Lebensdauer")
  T.near(s.short_life_share, 1 / 3, "summarize: Anteil kurzer Leben")
end

-- Dieselbe Auswertung fuer Sim und Abend: analyse_events liest die
-- Ereignistabellen, analyse die JSONL-Zeilen — beide muessen dasselbe sehen
do
  local events = require("game.gamesim.events")
  local r = gamerun.run_try({ n = 3, seed = 99, crits = true,
                              profile = "typisch", log = true })
  local lines, i = {}, 0
  for k, e in ipairs(r.events) do lines[k] = events.to_jsonl(e) end
  local a = logreport.analyse(function() i = i + 1; return lines[i] end)
  local b = logreport.analyse_events(r.events)
  T.eq(a.n_try, b.n_try, "logreport: Zeilen und Tabellen sehen dieselben Trys")
  T.eq(a.sum.deaths, b.sum.deaths, "logreport: dieselben Tode")
  T.eq(#a.lifetimes, #b.lifetimes, "logreport: dieselben Lebensdauern")
  T.near(a.sum.eat_heal, b.sum.eat_heal, "logreport: dieselbe Fress-Heilung")
  T.eq(a.trys[1].reason, b.trys[1].reason, "logreport: derselbe Grund")
  T.eq(a.players_seen, 3, "logreport: Raidgroesse aus den Kennungen (ohne Leeroy)")
  local ls = logreport.life_stats(b.lifetimes)
  T.ok(ls == nil or (ls.mean > 0 and ls.short_share >= 0 and ls.short_share <= 1),
    "logreport: life_stats liefert Mittel und Anteil")
end

-- Profile sind bekannt; ein unbekanntes Profil faellt nicht still auf
-- "typisch" zurueck, sondern wird durchgereicht (bot.lua entscheidet)
do
  local seen = {}
  for _, p in ipairs(gamerun.PROFILES) do seen[p] = true end
  T.ok(seen.typisch and seen.kopflos and seen.turtle,
    "gamerun: die drei Profile aus GDD 17.2 sind bekannt")
end
