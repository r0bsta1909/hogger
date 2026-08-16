-- game/net/netguard.lua — ENet-Aufrufe duerfen das Spiel nie toeten.
-- lua-enet wirft harte Lua-Fehler, sobald der UDP-Socket einen Fehler meldet
-- ("Error during service"): auf macOS reicht dafuer eine blockende Firewall
-- oder eine kurz wegfallende Schnittstelle. Ein einzelner transienter
-- Socket-Fehler beendete bisher den gesamten Prozess (Issue #23).
--
-- Politik: Fehler werden geschluckt und gezaehlt. Erst wenn die Verbindung
-- `tolerance` Sekunden am Stueck nur noch Fehler liefert, gilt sie als tot —
-- dann uebernimmt die Fiktion (WoW-Disconnect-Dialog, GDD Kap. 3) statt eines
-- Absturzes. Ein erfolgreicher Aufruf setzt die Uhr zurueck.
--
-- Reines Lua (kein love, kein enet) — damit maschinell testbar.

local G = {}
G.__index = G

-- tolerance: Sekunden ununterbrochener Fehler bis "tot" (Standard 2 s)
function G.new(tolerance)
  return setmetatable({
    tolerance = tolerance or 2.0,
    err_t = 0,          -- Fehlerzeit am Stueck
    errors = 0,         -- Fehler gesamt (Diagnose im F12-Overlay)
    last_error = nil,   -- letzte Fehlermeldung (Diagnose)
    dead = false,
    dt = 0,
    frame_failed = false,
  }, G)
end

-- Neuer Frame: dt merken; pro Frame zaehlt hoechstens ein Fehler
function G:frame(dt)
  self.dt = dt or 0
  self.frame_failed = false
end

-- Geschuetzter Aufruf. Rueckgabe: ok, ergebnis1, ergebnis2
function G:call(fn, ...)
  if self.dead then return false end
  local ok, a, b = pcall(fn, ...)
  if ok then
    if not self.frame_failed then self.err_t = 0 end
    return true, a, b
  end
  if not self.frame_failed then
    self.frame_failed = true
    self.errors = self.errors + 1
    self.last_error = tostring(a)
    self.err_t = self.err_t + self.dt
    if self.err_t >= self.tolerance then self.dead = true end
  end
  return false
end

-- Kurzfassung fuer das Debug-Overlay
function G:note()
  if self.errors == 0 then return nil end
  return string.format("Netzfehler: %d (%s)", self.errors,
    tostring(self.last_error):sub(1, 60))
end

return G
