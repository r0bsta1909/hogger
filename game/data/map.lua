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

-- Friedhof von Elwynn (GDD 7.1): unantastbare Zone mit Radius 400. Der
-- Geistheiler ist funktionslose Szenerie (Kap. 7.1), die Grabsteine machen
-- aus der Wiese ueberhaupt erst einen Friedhof (Playtest 2026-08-16).
M.GRAVEYARD_RADIUS = 400

-- quer zur Pfadrichtung (fuer Anordnungen am Friedhof)
local function perp()
  return -M.path_dir.y, M.path_dir.x
end

-- Der Geistheiler steht abseits der Spawnpunkte, Richtung Zaun
function M.spirit_healer()
  local g = M.graveyard()
  local px, py = perp()
  return { x = g.x + px * 150 - M.path_dir.x * 60,
           y = g.y + py * 150 - M.path_dir.y * 60 }
end

-- Standposition des Echos von Leeroy Jenkins (GDD 7.1/10.1): am Friedhof,
-- dem Geistheiler gegenueber, mit Blick auf den Pfad Richtung Huegel — es
-- sieht seinen eigenen Koerper jeden Try losrennen
function M.echo_home()
  local g = M.graveyard()
  local px, py = perp()
  return { x = g.x - px * 150 - M.path_dir.x * 60,
           y = g.y - py * 150 - M.path_dir.y * 60 }
end

-- Grabsteine in zwei Reihen laengs des Pfads, plus ein paar schiefe
function M.gravestones()
  local g = M.graveyard()
  local px, py = perp()
  local list = {}
  local function add(along, side)
    list[#list + 1] = { x = g.x + M.path_dir.x * along + px * side,
                        y = g.y + M.path_dir.y * along + py * side }
  end
  for i = -2, 2 do
    add(i * 90 + 40, -170)
    add(i * 90 - 10, -260)
  end
  add(200, 60); add(250, -60); add(-190, 120); add(-230, -120)
  return list
end

-- Huegel-Patrouille (IDLE-Wegpunkte, GDD 9.1)
M.patrol = {
  { x = M.hill.x - 120, y = M.hill.y - 60 },
  { x = M.hill.x + 140, y = M.hill.y + 80 },
}

-- Fluss-Linie am Suedrand (GDD 7.1); Murlocs spawnen nur hier
M.RIVER_Y = 1900

-- Mob-Spawn-Punkte (GDD 7.2): weit verstreut, ausserhalb der Leash-Zone,
-- nie auf der Friedhof-Huegel-Achse; Reihenfolge = Slot-Aktivierung
-- (model.mob_slots(N) aktiviert die ersten k). Ein Unit-Test erzwingt
-- die Platzierungsregeln.
M.MOB_SPAWNS = {
  { x = 300,  y = 900,  typ = "boar" },
  { x = 700,  y = 600,  typ = "wolf" },
  { x = 900,  y = 1000, typ = "kobold" },
  { x = 1200, y = 300,  typ = "boar" },
  { x = 1400, y = 1900, typ = "murloc" },
  { x = 1050, y = 1850, typ = "wolf" },
  { x = 1500, y = 1600, typ = "boar" },
  { x = 1800, y = 150,  typ = "kobold" },
  { x = 2000, y = 1400, typ = "wolf" },
  { x = 2400, y = 1000, typ = "boar" },
  { x = 2600, y = 1500, typ = "kobold" },
  { x = 2200, y = 1880, typ = "murloc" },
}

-- Abstand eines Punkts zur Friedhof-Huegel-Achse (fuer den Platzierungstest)
function M.dist_to_path(x, y)
  local vx, vy = x - M.hill.x, y - M.hill.y
  return math.abs(vx * M.path_dir.y - vy * M.path_dir.x)
end

-- Add-Positionen am Huegelfuss (GDD 9.2), Richtung Pfad
function M.add_positions(count)
  local list = {}
  for i = 1, count do
    local side = (i % 2 == 0) and 1 or -1
    local dist = 220 + (math.ceil(i / 2) - 1) * 60
    local px = M.hill.x + M.path_dir.x * dist - M.path_dir.y * side * 80
    local py = M.hill.y + M.path_dir.y * dist + M.path_dir.x * side * 80
    list[i] = { x = px, y = py }
  end
  return list
end

-- Deko-Schaedel (GDD Kap. 2: ~10-12, um Huegel und letztes Wegstueck)
function M.deco_skulls()
  local list = {}
  local function add(dist, side)
    local px = M.hill.x + M.path_dir.x * dist - M.path_dir.y * side
    local py = M.hill.y + M.path_dir.y * dist + M.path_dir.x * side
    list[#list + 1] = { x = px, y = py }
  end
  add(60, 90); add(120, -110); add(200, 40); add(90, -60); add(260, -30)
  add(420, 70); add(520, -90); add(640, 50); add(760, -40); add(880, 80)
  add(150, 160); add(300, -150)
  return list
end

-- Baum-Icons als Sichtblocker-Andeutung entlang des Pfads (GDD 7.1)
function M.trees()
  local list = {}
  local function add(dist, side)
    local px = M.hill.x + M.path_dir.x * dist - M.path_dir.y * side
    local py = M.hill.y + M.path_dir.y * dist + M.path_dir.x * side
    list[#list + 1] = { x = px, y = py }
  end
  add(1100, 220); add(1350, -260); add(1600, 240); add(1850, -220)
  add(2100, 260); add(1250, 300); add(1750, -300)
  return list
end

-- Unterzonen fuer das Zonenbanner (GDD 4.1); Reihenfolge = Pruefreihenfolge
function M.zone_at(x, y)
  local g = M.graveyard()
  local f = M.field()
  local function d2(px, py, qx, qy)
    local dx, dy = px - qx, py - qy
    return dx * dx + dy * dy
  end
  if d2(x, y, g.x, g.y) < M.GRAVEYARD_RADIUS ^ 2 then
    return "Friedhof von Elwynn"
  end
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
  return dx * dx + dy * dy < M.GRAVEYARD_RADIUS ^ 2
end

function M.clamp(x, y)
  if x < 0 then x = 0 elseif x > M.WIDTH then x = M.WIDTH end
  if y < 0 then y = 0 elseif y > M.HEIGHT then y = M.HEIGHT end
  return x, y
end

return M
