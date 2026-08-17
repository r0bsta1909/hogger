-- tests/unit_raid.lua — Raid-Overview (Runde 6, Issue #95): love-freie
-- Zeilenaufbereitung. Sortierung Lebende/Geister/Tote, HP-Prozent,
-- Restsekunden der Toten, Leeroy-Markierung.

local render = require("game.render")

local view = {
  me = 1,
  names = { [1] = "Rob", [2] = "Leeroy", [3] = "Zora", [4] = "Anna" },
  players = {
    [1] = { alive = true, ghost = false, class = "warrior", hp = 40 },
    [2] = { alive = false, ghost = false, class = "warrior",
            is_leeroy = true, dead_rest = 12 },
    [3] = { alive = false, ghost = true, class = "mage" },
    [4] = { alive = true, ghost = false, class = "priest", hp = 50 },
  },
}

local rows, alive_n, ghost_n, dead_n = render.raid_rows(view)
T.eq(#rows, 4, "raid: alle Spieler tauchen auf")
T.eq(alive_n, 2, "raid: zwei Lebende gezaehlt")
T.eq(ghost_n, 1, "raid: ein Geist gezaehlt")
T.eq(dead_n, 1, "raid: ein Toter gezaehlt")

T.eq(rows[1].name, "Anna", "raid: Lebende zuerst, alphabetisch")
T.eq(rows[2].name, "Rob", "raid: zweiter Lebender")
T.eq(rows[3].status, "geist", "raid: Geister nach den Lebenden")
T.eq(rows[4].status, "tot", "raid: Tote zuletzt")

T.eq(rows[1].detail, 100, "raid: Priester mit 50/50 HP = 100 %")
T.eq(rows[2].detail, 50, "raid: Krieger mit 40/80 HP = 50 %")
T.eq(rows[4].detail, 12, "raid: Tote zeigen Restsekunden bis zur Freigabe")
T.ok(rows[4].leeroy, "raid: Leeroy ist markiert")

-- Spieler ohne Klasse (vor der ersten Wiederbelebung): kein HP-Prozent
do
  local v = { names = {}, players = { [7] = { alive = false, ghost = true } } }
  local r = render.raid_rows(v)
  T.eq(r[1].name, "#7", "raid: ohne Roster-Namen faellt die Id ein")
  T.eq(r[1].class, nil, "raid: keine Klasse vor der Wiederbelebung")
end
