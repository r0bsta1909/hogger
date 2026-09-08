-- game/ui/floating.lua — Floating Combat Text mit Budget (GDD 4.1):
-- maximal ~30 gleichzeitig, eigene Ereignisse und Krits priorisiert,
-- Rest still verworfen; Objekt-Pool gegen GC-Druck.
--
-- Runde 21 (Rob: "ich verstehe nicht, welcher Schaden von mir ist"): die
-- EIGENE Wirkung hat eine Signatur — dunkler Umriss und ein Aufspringen
-- beim Erscheinen (Faehigkeiten gross, Autohits kleiner); fremde Zahlen
-- sind klein und blass. Was an einem selbst passiert, bleibt wie bisher.

local model = require("sim.model")

local F = {}
F.__index = F

-- Signatur-Groessen (Faktor auf die Schrift)
F.SCALE_OWN_BIG   = 1.9   -- eigene Faehigkeit / eigene Heilung: springt auf ...
F.SCALE_OWN_REST  = 1.35  -- ... und landet hier; eigener Autohit startet hier
F.SCALE_OWN_AUTO  = 1.2
F.SCALE_OTHER     = 0.85  -- fremde Zahlen
F.ALPHA_OTHER     = 0.55
F.POP_T           = 0.15  -- Dauer des Aufspringens in Sekunden

function F.new()
  return setmetatable({ items = {}, pool = {} }, F)
end

-- prio: 3 = eigener/erlittener Krit, 2 = eigen, 1 = normal
-- opts (optional): own = eigene Wirkung (Umriss + Aufspringen),
--                  big = eigene Faehigkeit/Heilung (sonst Autohit)
function F:add(text, wx, wy, color, prio, opts)
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
  it.own = opts and opts.own or false
  it.big = opts and opts.big or false
  it.t = model.p("floating_text_duration")
  it.total = it.t
  self.items[#self.items + 1] = it
  return it
end

-- Groesse eines Eintrags zu einem Zeitpunkt (love-frei, getestet):
-- eigene Faehigkeiten springen von SCALE_OWN_BIG auf SCALE_OWN_REST,
-- Krits bleiben gross, fremde Zahlen klein.
function F.scale_of(it)
  if it.prio >= 3 then return 2.0 end
  if it.own then
    if it.big then
      local age = it.total - it.t
      local k = math.min(1, age / F.POP_T)
      return F.SCALE_OWN_BIG + (F.SCALE_OWN_REST - F.SCALE_OWN_BIG) * k
    end
    return F.SCALE_OWN_AUTO
  end
  if it.prio >= 2 then return 1.5 end -- an mir selbst (erlitten/geheilt)
  return F.SCALE_OTHER
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
    local scale = F.scale_of(it)
    if not it.own and it.prio < 2 then a = a * F.ALPHA_OTHER end
    local tw = font:getWidth(it.text) * scale
    local px, py = x - tw / 2, y - 24
    if it.own then
      -- dunkler Umriss: vier Versatz-Kopien, damit die eigene Zahl auch
      -- auf hellem Icon-Gulasch steht
      love.graphics.setColor(0.05, 0.04, 0.03, a)
      for _, o in ipairs({ { 1.5, 0 }, { -1.5, 0 }, { 0, 1.5 }, { 0, -1.5 } }) do
        love.graphics.print(it.text, px + o[1], py + o[2], 0, scale, scale)
      end
    end
    love.graphics.setColor(it.color[1], it.color[2], it.color[3], a)
    love.graphics.print(it.text, px, py, 0, scale, scale)
  end
end

return F
