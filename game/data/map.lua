-- game/data/map.lua — Kartendaten (GDD 7.1), als Datendatei (Vorhalt Modus 2).
-- Reines Lua. Ankerpunkte des Pfads werden aus model.lua abgeleitet:
-- Feld- und Friedhofsposition folgen den Panel-Parametern (Feldposition ist
-- Balancing-Hebel) — eine Wahrheit, kein Drift zwischen Karte und Modell.

local model = require("sim.model")

local M = {}

-- Logische Weltgroesse: Konstante (Skill Par. 1); ~3x2 Bildschirmradien
-- bei mittlerem Zoom (450 px)
M.WIDTH = 3000
M.HEIGHT = 2000

-- Hogger Hill (Suedwesten) und Pfadrichtung zum Friedhof (Nordosten)
M.hill = { x = 420, y = 1650 }
local dir = { x = 2180, y = -1330 } -- Richtung Friedhof, wird normalisiert
local len = math.sqrt(dir.x * dir.x + dir.y * dir.y)
M.path_dir = { x = dir.x / len, y = dir.y / len }

local function along_path(dist)
  return { x = M.hill.x + M.path_dir.x * dist,
           y = M.hill.y + M.path_dir.y * dist }
end

-- Wiederbelebungsfeld: am Ende des Pfads, Abstand zum Huegel aus model.lua
function M.field()
  return along_path(model.p("field_to_hill_dist"))
end

-- Friedhof: Feld + Geisterlauf-Distanz aus model.lua
function M.graveyard()
  return along_path(model.p("field_to_hill_dist") + model.p("graveyard_to_field_dist"))
end

-- Huegel-Patrouille (IDLE-Wegpunkte, GDD 9.1)
M.patrol = {
  { x = M.hill.x - 120, y = M.hill.y - 60 },
  { x = M.hill.x + 140, y = M.hill.y + 80 },
}

-- Unterzonen fuer das Zonenbanner (GDD 4.1); Reihenfolge = Pruefreihenfolge
function M.zone_at(x, y)
  local g = M.graveyard()
  local f = M.field()
  local function d2(px, py, qx, qy)
    local dx, dy = px - qx, py - qy
    return dx * dx + dy * dy
  end
  if d2(x, y, g.x, g.y) < 400 * 400 then return "Friedhof von Elwynn" end
  if d2(x, y, f.x, f.y) < 300 * 300 then return "Wiederbelebungsfeld" end
  if d2(x, y, M.hill.x, M.hill.y) < (model.p("hogger_leash_radius")) ^ 2 then
    return "Hogger Hill"
  end
  return "Der Elwynn-Pfad"
end

-- Friedhof ist unantastbar: Hogger betritt ihn nie (GDD 7.1)
function M.in_graveyard(x, y)
  local g = M.graveyard()
  local dx, dy = x - g.x, y - g.y
  return dx * dx + dy * dy < 400 * 400
end

function M.clamp(x, y)
  if x < 0 then x = 0 elseif x > M.WIDTH then x = M.WIDTH end
  if y < 0 then y = 0 elseif y > M.HEIGHT then y = M.HEIGHT end
  return x, y
end

return M
