-- tests/unit_gamemenu.lua — Stufe 1: das Spielmenue nach dem Fluchbruch
-- (GDD Kap. 11, #133). Geometrie und Zustand sind love-frei; draw bleibt
-- ungetestet wie bei ui/release.lua.

local menu = require("game.ui.gamemenu")
local T = _G.T

-- Genau ein scharfer Eintrag: das ist die ganze Aussage des Menues
local scharf = 0
for _, e in ipairs(menu.ENTRIES) do
  if e.enabled then
    scharf = scharf + 1
    T.eq(e.id, "quit", "nur 'Spiel verlassen' ist scharf")
  end
  T.ok(#e.label > 0, "jeder Eintrag hat eine Beschriftung: " .. e.id)
  T.ok(e.label:find("[\128-\255]") == nil,
    "Beschriftung ist ASCII (Spielcode-Konvention): " .. e.id)
end
T.eq(scharf, 1, "genau ein Eintrag ist anklickbar")
T.ok(#menu.ENTRIES >= 3, "das Menue sieht aus wie das Original (mehrere Zeilen)")

-- Layout: schmal, mittig, Zeilen ueberlappen nicht und liegen im Panel
do
  local w, h = 1280, 800
  local l = menu.layout(w, h)
  local px, py, pw, ph = l.panel[1], l.panel[2], l.panel[3], l.panel[4]
  T.ok(pw <= 320, "schmales Panel (" .. pw .. " px)")
  T.near(px + pw / 2, w / 2, "horizontal zentriert")
  T.near(py + ph / 2, h / 2, "vertikal zentriert")
  T.eq(#l.rows, #menu.ENTRIES, "je Eintrag eine Zeile")
  local prev_bottom = py
  for i, r in ipairs(l.rows) do
    T.ok(r.rect[1] >= px and r.rect[1] + r.rect[3] <= px + pw,
      "Zeile " .. i .. " liegt im Panel (x)")
    T.ok(r.rect[2] >= prev_bottom, "Zeile " .. i .. " ueberlappt die vorige nicht")
    prev_bottom = r.rect[2] + r.rect[4]
  end
  T.ok(prev_bottom <= py + ph, "alle Zeilen passen ins Panel")
end

-- Klick: nur der scharfe Eintrag liefert eine Aktion
do
  local w, h = 1280, 800
  local l = menu.layout(w, h)
  local function mitte(r) return r.rect[1] + r.rect[3] / 2, r.rect[2] + r.rect[4] / 2 end
  for _, r in ipairs(l.rows) do
    local mx, my = mitte(r)
    local got = menu.click(w, h, mx, my)
    if r.enabled then
      T.eq(got, "quit", "Klick auf 'Spiel verlassen' beendet")
    else
      T.eq(got, nil, "Klick auf '" .. r.label .. "' tut nichts")
    end
  end
  T.eq(menu.click(w, h, 5, 5), nil, "Klick neben das Menue tut nichts")
end

-- Verfuegbarkeit: NUR nach dem Fluchbruch (GDD 11)
T.ok(not menu.available(nil), "ohne Sicht kein Menue")
T.ok(not menu.available({ won_stage = 0 }), "waehrend des Trys kein Menue")
T.ok(menu.available({ won_stage = 1 }), "ab dem Fluchbruch gibt es das Menue")
T.ok(menu.available({ won_stage = 4 }), "auch nach Leeroys Abgang")

-- Kleine Fenster: das Panel darf nicht aus dem Bild rutschen
do
  local l = menu.layout(640, 480)
  T.ok(l.panel[1] >= 0 and l.panel[2] >= 0, "Panel bleibt im Bild")
end
