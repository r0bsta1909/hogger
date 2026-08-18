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

return N
