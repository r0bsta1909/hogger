-- game/ui/floating.lua — Floating Combat Text mit Budget (GDD 4.1):
-- maximal ~30 gleichzeitig, eigene Ereignisse und Krits priorisiert,
-- Rest still verworfen; Objekt-Pool gegen GC-Druck.

local model = require("sim.model")

local F = {}
F.__index = F

function F.new()
  return setmetatable({ items = {}, pool = {} }, F)
end

-- prio: 2 = eigen/Krit, 1 = normal
function F:add(text, wx, wy, color, prio)
  local budget = model.p("floating_text_max")
  if #self.items >= budget then
    -- niederprioren Eintrag verdraengen, sonst still verwerfen
    local victim
    for i, it in ipairs(self.items) do
      if it.prio < (prio or 1) then victim = i break end
    end
    if not victim then return end
    table.remove(self.items, victim)
  end
  local it = table.remove(self.pool) or {}
  it.text, it.wx, it.wy, it.color, it.prio = text, wx, wy, color, prio or 1
  it.t = model.p("floating_text_duration")
  it.total = it.t
  self.items[#self.items + 1] = it
end

function F:update(dt)
  for i = #self.items, 1, -1 do
    local it = self.items[i]
    it.t = it.t - dt
    it.wy = it.wy - 28 * dt
    if it.t <= 0 then
      self.pool[#self.pool + 1] = it
      table.remove(self.items, i)
    end
  end
end

-- to_screen: Funktion Weltkoord -> Bildschirm
function F:draw(to_screen)
  local font = love.graphics.getFont()
  for _, it in ipairs(self.items) do
    local x, y = to_screen(it.wx, it.wy)
    local a = math.min(1, it.t / (it.total * 0.4))
    local scale = it.prio >= 2 and 1.5 or 1
    love.graphics.setColor(it.color[1], it.color[2], it.color[3], a)
    local tw = font:getWidth(it.text) * scale
    love.graphics.print(it.text, x - tw / 2, y - 24, 0, scale, scale)
  end
end

return F
