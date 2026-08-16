-- tests/unit_netguard.lua — ENet-Fehlerpolitik (Issue #23).
-- Beweist maschinell: ein transienter Socket-Fehler (macOS-Firewall,
-- kurz wegfallende Schnittstelle) kann das Spiel nicht mehr beenden, und
-- ein dauerhafter Fehler endet als sauberer Verbindungsverlust.

local netguard = require("game.net.netguard")

local function boom() error("Error during service") end
local function fine(v) return v end

-- 1) Fehler werden geschluckt, nicht geworfen
do
  local g = netguard.new(2.0)
  g:frame(1 / 60)
  local ok = g:call(boom)
  T.eq(ok, false, "fehlerhafter Aufruf meldet false statt zu werfen")
  T.eq(g.dead, false, "ein einzelner Fehler toetet die Verbindung nicht")
  T.eq(g.errors, 1, "Fehler wird gezaehlt")
  T.ok(g.last_error:find("Error during service") ~= nil, "Meldung gemerkt")
end

-- 2) Ergebnisse werden durchgereicht
do
  local g = netguard.new()
  g:frame(0.016)
  local ok, a, b = g:call(function() return 7, 8 end)
  T.eq(ok, true, "erfolgreicher Aufruf meldet true")
  T.eq(a, 7, "erstes Ergebnis durchgereicht")
  T.eq(b, 8, "zweites Ergebnis durchgereicht")
  T.eq(g:call(fine, nil), true, "nil-Ergebnis ist kein Fehler")
end

-- 3) Pro Frame zaehlt hoechstens ein Fehler (die Service-Schleife ruft oft)
do
  local g = netguard.new(2.0)
  g:frame(0.5)
  for _ = 1, 100 do g:call(boom) end
  T.eq(g.errors, 1, "die Schleife im selben Frame zaehlt einmal")
  T.near(g.err_t, 0.5, "Fehlerzeit waechst um genau einen Frame")
end

-- 4) Erholung: ein erfolgreicher Aufruf setzt die Uhr zurueck
--    (macOS: sobald der Nutzer die Firewall-Nachfrage bestaetigt)
do
  local g = netguard.new(2.0)
  for _ = 1, 100 do
    g:frame(1 / 60)
    g:call(boom)
    g:frame(1 / 60)
    g:call(fine, 1)
  end
  T.eq(g.dead, false, "abwechselnd Fehler und Erfolg toetet die Verbindung nie")
  T.eq(g.errors, 100, "Fehler bleiben fuer die Diagnose gezaehlt")
end

-- 5) Dauerfehler: nach der Toleranz gilt die Verbindung als tot
do
  local g = netguard.new(2.0)
  local frames = 0
  while not g.dead and frames < 10000 do
    g:frame(1 / 60)
    g:call(boom)
    frames = frames + 1
  end
  T.eq(g.dead, true, "Dauerfehler endet als Verbindungsverlust")
  -- 120 Frames = 2 s; die Summe kleiner Fliesskommaschritte darf einen
  -- Frame spaeter kippen
  T.ok(frames == 120 or frames == 121, "rund 2 s Toleranz bei 60 Hz")
  T.eq(g:call(fine, 1), false, "tote Verbindung fuehrt nichts mehr aus")
  T.ok(g:note():find("Netzfehler") ~= nil, "Diagnosezeile fuers F12-Overlay")
end

-- 6) Frame ohne dt (Ereignisse ausserhalb der Update-Schleife) toetet nie
do
  local g = netguard.new(2.0)
  for _ = 1, 1000 do g:call(boom) end
  T.eq(g.dead, false, "Sendefehler ohne Frame-Takt toeten nicht")
end
