-- game/ui/tooltip.lua — Tooltip im Original-Stil (GDD 4.2/4.3): erste Zeile
-- gold (der Name), Rest hell, dunkle Fuellung mit Goldrahmen, geklemmt an
-- die Bildschirmkanten. EINE Wahrheit fuer alle Tooltips — der Renderer
-- (Faehigkeiten, Buffs, Zoom) und das F10-Panel benutzen dieselbe Routine.

local T = {}

function T.draw(lines, mx, my, w, h)
  local font = love.graphics.getFont()
  local tw = 0
  for _, l in ipairs(lines) do tw = math.max(tw, font:getWidth(l)) end
  local th = #lines * 16 + 8
  local tx = math.min(w - tw - 20, math.max(8, mx - tw / 2))
  local ty = math.max(8, my - th - 16)
  love.graphics.setColor(0.05, 0.05, 0.07, 0.94)
  love.graphics.rectangle("fill", tx, ty, tw + 12, th, 3, 3)
  love.graphics.setColor(0.45, 0.40, 0.28, 1)
  love.graphics.rectangle("line", tx, ty, tw + 12, th, 3, 3)
  for i, l in ipairs(lines) do
    love.graphics.setColor(i == 1 and 1 or 0.8, i == 1 and 0.85 or 0.78,
      i == 1 and 0.4 or 0.66, 1)
    love.graphics.print(l, tx + 6, ty + 4 + (i - 1) * 16)
  end
end

return T
