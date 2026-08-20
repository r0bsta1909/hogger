-- game/test/budget.lua — Stufe 4: Snapshot-Budget bei voller Raid-Groesse.
--
-- Warum es diese Datei gibt (Runde 16): die Budget-Pruefung in headless.lua
-- rechnete mit 20 Byte je Spieler, ADR-001 sogar mit 14 — der Datensatz kostet
-- laengst 25. Auffallen konnte das nicht: der Stufe-4-Lauf hat sechs bis acht
-- Spieler, dort deckt der Zuschlag von 96 B die Luecke. Bei 40 Spielern waere
-- die alte Formel schon mit dem HEUTIGEN Format verletzt gewesen.
--
-- Statt die Zahl zu korrigieren (und sie beim naechsten neuen Feld wieder zu
-- vergessen), MISST diese Datei die Kosten je Datensatz am echten Packer: ein
-- Datensatz mehr, Differenz der Rumpflaenge. Damit kann die Formel nicht mehr
-- veralten — wer ein Feld ergaenzt, sieht es sofort.
--
-- Warum Stufe 4 und nicht Stufe 1: wire.lua packt ueber love.data.pack, ist
-- also nicht love-frei, und LuaJIT kennt weder string.pack noch
-- string.packsize. Die Messung braucht ein laufendes LOEVE.

local model = require("sim.model")
local world = require("game.gamesim.world")
local wire = require("game.net.wire")

local M = {}

-- ENet-Standard-MTU. Darueber fragmentiert ENet das Paket. Fuer einen
-- "unsequenced" Snapshot ist genau das der Fall, den ADR-001 nicht vorgesehen
-- hat ("keine zwei Zeitbasen, keine Lueckenbehandlung").
M.MTU = 1400
-- Was ausser dem Rumpf noch ins Paket geht (wire.snapshot): 3 Byte Header
-- plus 4 Byte ackInputTick.
M.PAKETKOPF = 7
-- Harter Deckel des Leichen-Blocks im Format (wire.lua: min(255, #corpses))
M.LEICHEN_DECKEL = 255

-- Eine Welt ohne Beiwerk: nur der feste Teil plus die gewuenschten Spieler.
local function blank(n_players)
  local st = world.new(1234)
  for i = 1, n_players do
    world.add_player(st, "p" .. i, { quest_done = true })
  end
  world.begin_try(st)
  -- begin_try setzt Welpen und Mob-Slots; fuer die Differenzmessung stoert das
  st.npcs = {}
  st.corpses = {}
  st.loot = {}
  return st
end

local function body_len(st)
  return #wire.snapshot_body(st)
end

-- Kosten je Datensatz aus dem Packer ableiten (nicht behaupten).
function M.kosten()
  local leer = body_len(blank(0))

  local je_spieler = body_len(blank(1)) - leer

  local lst = blank(0)
  lst.corpses[1] = { x = 1500, y = 1000 }
  local je_leiche = body_len(lst) - leer

  local nst = blank(0)
  world.add_npc(nst, "imp", 1500, 1000, 15)
  local je_npc = body_len(nst) - leer

  local bst = blank(0)
  world.add_loot(bst, 1500, 1000, 5, 1)
  local je_beute = body_len(bst) - leer

  return { leer = leer, spieler = je_spieler, leiche = je_leiche,
           npc = je_npc, beute = je_beute }
end

-- Die Budget-Formel — vollstaendig aus den gemessenen Kosten gebildet.
-- Kein Zuschlag, keine Magic Number: wenn das nicht exakt aufgeht, ist der
-- Packer anders gebaut als hier angenommen, und das soll auffallen.
function M.budget(k, n_players, n_corpses, n_npcs, n_loot)
  return k.leer
       + k.spieler * n_players
       + k.leiche * math.min(M.LEICHEN_DECKEL, n_corpses)
       + k.npc * n_npcs
       + k.beute * n_loot
end

local function zaehle(st)
  local npcs, loot = 0, 0
  for id = 100, 250 do if st.npcs[id] then npcs = npcs + 1 end end
  for id = 1, 60 do if st.loot[id] then loot = loot + 1 end end
  return #st.players, #st.corpses, npcs, loot
end

-- Ein Szenario aufbauen und messen. corpses/loot werden gesetzt, NPCs stammen
-- aus begin_try (Welpen + Mob-Slots) plus optionalen Wichteln.
function M.szenario(n_players, n_corpses, n_loot, n_imps)
  local st = world.new(1234)
  for i = 1, n_players do
    world.add_player(st, "p" .. i, { quest_done = true })
  end
  world.begin_try(st)
  for i = 1, (n_imps or 0) do
    world.add_npc(st, "imp", 1500 + i, 1000, model.p("imp_hp"))
  end
  for i = 1, n_corpses do
    st.corpses[i] = { x = 1500 + (i % 40), y = 1000 + math.floor(i / 40) }
  end
  for i = 1, n_loot do
    world.add_loot(st, 1500 + i, 1050, 5, 1)
  end
  local body = wire.snapshot_body(st)
  local sp, co, np, lo = zaehle(st)
  return { bytes = #body, paket = #body + M.PAKETKOPF,
           spieler = sp, leichen = co, npcs = np, beute = lo, state = st }
end

function M.run(ok)
  print("== Stufe 4: Snapshot-Budget bei voller Raid-Groesse ==")

  local k = M.kosten()
  print(string.format(
    "   Kosten je Datensatz (gemessen): fest %d B | Spieler %d B | Leiche %d B"
    .. " | NPC %d B | Beute %d B",
    k.leer, k.spieler, k.leiche, k.npc, k.beute))

  -- 1) Kosten festnageln. Waechst ein Datensatz, faellt dieser Test und
  --    zwingt zu einer bewussten Entscheidung statt zu stillem Wachstum.
  ok(k.spieler == 25, "Budget: Spieler-Datensatz kostet 25 B (ist "
     .. k.spieler .. ")")
  ok(k.leiche == 4, "Budget: Leiche kostet 4 B (ist " .. k.leiche .. ")")
  ok(k.npc == 8, "Budget: NPC kostet 8 B (ist " .. k.npc .. ")")
  ok(k.beute == 5, "Budget: Bodenbeute kostet 5 B (ist " .. k.beute .. ")")

  -- 2) Die Formel muss die Wirklichkeit EXAKT treffen, nicht nur ungefaehr.
  local szenarien = {
    { name = "N=5, frischer Try",        n = 5,  leichen = 0,   beute = 0,  imps = 1 },
    { name = "N=40, frischer Try",       n = 40, leichen = 0,   beute = 0,  imps = 5 },
    { name = "N=40, Leichen am Deckel",  n = 40, leichen = 255, beute = 12, imps = 5 },
    { name = "N=40, alles am Anschlag",  n = 40, leichen = 400, beute = 60, imps = 20 },
  }

  local voll_frisch, voll_saturiert
  for _, s in ipairs(szenarien) do
    local r = M.szenario(s.n, s.leichen, s.beute, s.imps)
    local erwartet = M.budget(k, r.spieler, r.leichen, r.npcs, r.beute)
    ok(r.bytes == erwartet, string.format(
      "Budget-Formel trifft exakt (%s): %d B erwartet, %d B gemessen",
      s.name, erwartet, r.bytes))
    print(string.format(
      "   %-26s %4d Spieler-B + Rest = %5d B Rumpf, %5d B Paket  (MTU %d: %s)",
      s.name, k.spieler * r.spieler, r.bytes, r.paket, M.MTU,
      r.paket <= M.MTU and "passt"
        or ("UEBER um " .. (r.paket - M.MTU) .. " B")))
    if s.name == "N=40, frischer Try" then voll_frisch = r end
    if s.name == "N=40, Leichen am Deckel" then voll_saturiert = r end
  end

  -- 3) Der frische 40er-Try MUSS in ein Paket passen. Faellt das, ist der
  --    Snapshot bei jedem Tick fragmentiert und ADR-001 ist gebrochen.
  ok(voll_frisch and voll_frisch.paket <= M.MTU, string.format(
    "Budget: frischer 40er-Try passt in die MTU (%d von %d B)",
    voll_frisch and voll_frisch.paket or -1, M.MTU))

  -- 4) Der gesaettigte 40er-Try liegt heute UEBER der MTU. Das ist ein
  --    bekannter Zustand (Issue in Runde 16) und kein Test-Versagen — aber er
  --    wird hier festgenagelt, damit er nicht unbemerkt weiter waechst.
  --    Leichen verschwinden nur, wenn Hogger sie frisst (step.lua), sonst nie:
  --    255 Leichen sind 6,4 Tode je Spieler, also der Normalzustand eines
  --    40er-Trys nach wenigen Minuten, kein exotischer Sonderfall.
  local DECKEL_SATURIERT = 2400
  ok(voll_saturiert and voll_saturiert.paket <= DECKEL_SATURIERT, string.format(
    "Budget: gesaettigter 40er-Try bleibt unter %d B (ist %d B)",
    DECKEL_SATURIERT, voll_saturiert and voll_saturiert.paket or -1))
  if voll_saturiert and voll_saturiert.paket > M.MTU then
    print(string.format(
      "   WARNUNG: gesaettigter 40er-Try liegt %d B ueber der ENet-MTU —"
      .. " ENet fragmentiert dann jeden Snapshot (ADR-001-Revisionsausloeser)",
      voll_saturiert.paket - M.MTU))
  end

  -- 5) Der Leichen-Block ist der einzige unbegrenzt wachsende Teil. Belegen,
  --    dass der Deckel im Format wirklich greift — sonst waere das Paket bei
  --    einem langen 40er-Try beliebig gross.
  local ueber = M.szenario(40, 400, 0, 0)
  local am_deckel = M.szenario(40, M.LEICHEN_DECKEL, 0, 0)
  ok(ueber.bytes == am_deckel.bytes,
    "Budget: der Leichen-Block deckelt bei 255 (400 Leichen kosten nicht mehr)")

  return k
end

return M
