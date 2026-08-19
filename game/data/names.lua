-- game/data/names.lua — Namen, die an mehr als einer Stelle auftauchen.
-- Eine Wahrheit: der Questgeber stand vorher als unabhaengige Kopie in
-- render.lua UND in ui/quest.lua. Strings sind ASCII-transliteriert wie
-- ueberall im Spielcode (Umlaute nur in docs/).

local N = {}

-- Der NPC am Friedhof (GDD 10.1). Der Name ist der Witz: der Fluch hat ihn
-- geteilt, und was uebrig blieb, heisst doppelt. Dass er nur das Echo ist,
-- erklaert er selbst im Questtext.
N.ECHO = "Leeroy Leeroy Jenkins Jenkins"

-- Der Raid-Leeroy, der Koerper da vorne (GDD 10.2)
N.LEEROY = "Leeroy"

-- Nach der Verschmelzung (GDD 11): der Fluch hatte ihn geteilt, jetzt ist er
-- wieder einer. Der doppelte Name war die Wunde — hier heilt sie.
N.WHOLE = "Leeroy Jenkins"

-- Wie die Figur am Friedhof gerade heisst. won_stage: 0 = Try laeuft,
-- 1 versammelt, 2 Verschmelzung laeuft, 3 verschmolzen, 4 weg.
-- Love-frei, damit der Wechsel testbar ist.
function N.echo_name(won_stage)
  return (won_stage or 0) >= 3 and N.WHOLE or N.ECHO
end

-- Die Systemnachricht am Ende der Endsequenz (GDD 11): sie steht bewusst im
-- Wortlaut des Originals — genau so meldet WoW einen Abgang.
N.LEEROY_LEFT = "Leeroy Jenkins hat das Spiel verlassen."

-- Bot-Namen (Runde 12, #146): Robs Liste — WoW-Groessen von Reckful bis
-- Red Shirt Guy. Reihenfolge hier = Robs Reihenfolge; zugelost wird per
-- bot_names_for_seed. Erweiterung nur hier.
N.BOT_NAMES = {
  "Reckful", "Vurtne", "Drakedog", "Laintime", "Neilyo", "Hydramist",
  "Cdew", "Venruki", "Pikaboo", "Snutz", "Whaazz", "Raiku",
  "Chas", "Chanimal", "Jahmilli", "Mes", "Absterge", "Kungen",
  "Sco", "Scripe", "Gingi", "Naowh", "Fragnance", "Rogerbrown",
  "Justwait", "Zaelia", "Mione", "Rextroy", "Doubleagent", "Swifty",
  "Asmongold", "Sodapoppin", "Athene", "Angwe", "Bajheera", "Esfand",
  "Towelliee", "Preach", "Nobbel87", "Barney", "Red Shirt Guy", "Payo",
}

-- Zufaellig zugeloste Reihenfolge der Bot-Namen — deterministisch aus dem
-- Realm-Seed (eigener RNG-Strom; der Try-RNG des Hosts bleibt unberuehrt,
-- Zufallsregel GDD 13.2/14). Fisher-Yates ueber eine Kopie der Liste.
function N.bot_names_for_seed(seed)
  local rng = require("sim.rng").new((seed or 0) * 2 + 999331)
  local pool = {}
  for i, nm in ipairs(N.BOT_NAMES) do pool[i] = nm end
  for i = #pool, 2, -1 do
    local j = rng:range(1, i)
    pool[i], pool[j] = pool[j], pool[i]
  end
  return pool
end

return N
