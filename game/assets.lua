-- game/assets.lua — Zugriff NUR ueber logische IDs (GDD 17.5).
-- Liegt eine echte Datei am Manifest-Pfad, wird sie geladen; sonst wird der
-- Platzhalter zur Laufzeit aus dem Manifest generiert (Form + Farbe + Kuerzel,
-- exakt finale Masse) — M2/M3 sind damit voll spielbar.

local A = {}
local manifest = require("assets.manifest")
local cache = {}

local function make_placeholder(spec)
  local s = spec.groesse
  local cw, ch = spec.breite or s, spec.hoehe or s
  local canvas = love.graphics.newCanvas(cw, ch)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  local r, g, b = spec.farbe[1], spec.farbe[2], spec.farbe[3]
  love.graphics.setColor(r, g, b, 1)
  if spec.form == "splash" then
    -- dunkle Flaeche mit Logo-Schriftzug mittig (Boot-Sequenz, GDD Kap. 3)
    love.graphics.rectangle("fill", 0, 0, cw, ch)
    love.graphics.setColor(0.85, 0.72, 0.3, 1)
    local font = love.graphics.getFont()
    local tw = font:getWidth(spec.kuerzel)
    love.graphics.print(spec.kuerzel, cw / 2 - tw, ch / 3, 0, 2, 2)
    love.graphics.pop()
    return canvas
  end
  local half = s / 2
  if spec.form == "kreis" then
    love.graphics.circle("fill", half, half, half - 1)
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.circle("line", half, half, half - 1)
  elseif spec.form == "ring" then
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", half, half, half - 2)
  elseif spec.form == "quadrat" then
    love.graphics.rectangle("fill", 1, 1, s - 2, s - 2, 3, 3)
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("line", 1, 1, s - 2, s - 2, 3, 3)
  elseif spec.form == "raute" then
    love.graphics.polygon("fill", half, 1, s - 1, half, half, s - 1, 1, half)
  end
  if spec.kuerzel and spec.kuerzel ~= "" then
    love.graphics.setColor(0, 0, 0, 0.85)
    local font = love.graphics.getFont()
    local tw = font:getWidth(spec.kuerzel)
    love.graphics.print(spec.kuerzel, half - tw / 2, half - font:getHeight() / 2)
  end
  love.graphics.pop()
  return canvas
end

function A.get(id)
  if cache[id] then return cache[id] end
  local spec = manifest[id]
  assert(spec, "unbekannte Asset-ID: " .. tostring(id))
  local drawable
  if spec.datei and love.filesystem.getInfo
     and love.filesystem.getInfo("assets/" .. spec.datei) then
    drawable = love.graphics.newImage("assets/" .. spec.datei)
  else
    drawable = make_placeholder(spec)
  end
  cache[id] = drawable
  return drawable
end

function A.size(id)
  return manifest[id].groesse
end

-- Icon zentriert an Weltbildschirmposition zeichnen
function A.draw(id, x, y, scale, alpha)
  local img = A.get(id)
  local s = manifest[id].groesse
  love.graphics.setColor(1, 1, 1, alpha or 1)
  love.graphics.draw(img, x, y, 0, scale or 1, scale or 1, s / 2, s / 2)
end

return A
