-- game/gamesim/grid.lua — Begehbarkeits-Grid + A* (GDD Kap. 14).
-- 32-px-Zellen aus der Kartendatei; deterministisch (feste Nachbar-
-- Reihenfolge, keine pairs()-Iteration). Pfadglaettung per String-Pulling.
-- Nutzer: Leeroy (Anmarsch/Geisterlauf) und der Mob-Leash an den Spawn.
-- Die Karte hat derzeit keine blockierende Geometrie — das Grid ist die
-- Infrastruktur, die bei kuenftigen Hindernissen (Modus 2) sofort traegt;
-- der Erreichbarkeits-Test (Stufe 1) haelt die Zusage maschinell.

local map = require("game.data.map")

local G = {}
G.CELL = 32
G.COLS = math.ceil(map.WIDTH / G.CELL)
G.ROWS = math.ceil(map.HEIGHT / G.CELL)

function G.walkable(cx, cy)
  return cx >= 1 and cx <= G.COLS and cy >= 1 and cy <= G.ROWS
end

function G.to_cell(x, y)
  return math.floor(x / G.CELL) + 1, math.floor(y / G.CELL) + 1
end

function G.to_world(cx, cy)
  return (cx - 0.5) * G.CELL, (cy - 0.5) * G.CELL
end

-- feste Nachbar-Reihenfolge (Determinismus-Pflicht, GDD 14)
local NEIGHBORS = {
  { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 },
  { 1, 1, 1.4142 }, { 1, -1, 1.4142 }, { -1, 1, 1.4142 }, { -1, -1, 1.4142 },
}

local function key(cx, cy)
  return cy * (G.COLS + 1) + cx
end

-- Sichtlinie zwischen zwei Zellen frei? (fuers String-Pulling)
local function line_clear(ax, ay, bx, by)
  local steps = math.max(math.abs(bx - ax), math.abs(by - ay))
  for i = 1, steps do
    local t = i / steps
    local cx = math.floor(ax + (bx - ax) * t + 0.5)
    local cy = math.floor(ay + (by - ay) * t + 0.5)
    if not G.walkable(cx, cy) then return false end
  end
  return true
end

-- A* von Weltposition zu Weltposition -> Liste von Welt-Wegpunkten
-- (geglaettet); nil, wenn unerreichbar
function G.path(x1, y1, x2, y2)
  local sx, sy = G.to_cell(x1, y1)
  local tx, ty = G.to_cell(x2, y2)
  if not G.walkable(sx, sy) or not G.walkable(tx, ty) then return nil end
  if sx == tx and sy == ty then return { { x = x2, y = y2 } } end

  local open = { { cx = sx, cy = sy, g = 0 } }
  local came, gscore, closed = {}, {}, {}
  gscore[key(sx, sy)] = 0

  local function heuristic(cx, cy)
    local dx, dy = math.abs(cx - tx), math.abs(cy - ty)
    return math.max(dx, dy) + 0.4142 * math.min(dx, dy)
  end

  local iterations = 0
  while #open > 0 do
    iterations = iterations + 1
    if iterations > G.COLS * G.ROWS then return nil end
    -- kleinstes f herausnehmen (lineare Suche: Grid ist winzig, GDD 14)
    local best_i, best_f = 1, math.huge
    for i, n in ipairs(open) do
      local f = n.g + heuristic(n.cx, n.cy)
      if f < best_f then best_i, best_f = i, f end
    end
    local cur = table.remove(open, best_i)
    local ck = key(cur.cx, cur.cy)
    if not closed[ck] then
      closed[ck] = true
      if cur.cx == tx and cur.cy == ty then
        -- Pfad rekonstruieren (Zellen)
        local cells = { { cur.cx, cur.cy } }
        local k = ck
        while came[k] do
          local c = came[k]
          table.insert(cells, 1, { c[1], c[2] })
          k = key(c[1], c[2])
        end
        -- String-Pulling: unnoetige Zwischenpunkte entfernen
        local pulled = { cells[1] }
        local anchor = 1
        for i = 3, #cells do
          if not line_clear(cells[anchor][1], cells[anchor][2],
                            cells[i][1], cells[i][2]) then
            pulled[#pulled + 1] = cells[i - 1]
            anchor = i - 1
          end
        end
        pulled[#pulled + 1] = cells[#cells]
        local out = {}
        for i = 2, #pulled do -- Startzelle auslassen
          local wx, wy = G.to_world(pulled[i][1], pulled[i][2])
          out[#out + 1] = { x = wx, y = wy }
        end
        if #out == 0 then out[1] = { x = x2, y = y2 } end
        out[#out] = { x = x2, y = y2 } -- exakte Zielposition
        return out
      end
      for _, nb in ipairs(NEIGHBORS) do
        local nx, ny = cur.cx + nb[1], cur.cy + nb[2]
        if G.walkable(nx, ny) and not closed[key(nx, ny)] then
          local ng = cur.g + nb[3]
          local nk = key(nx, ny)
          if gscore[nk] == nil or ng < gscore[nk] then
            gscore[nk] = ng
            came[nk] = { cur.cx, cur.cy }
            open[#open + 1] = { cx = nx, cy = ny, g = ng }
          end
        end
      end
    end
  end
  return nil
end

return G
