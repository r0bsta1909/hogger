-- game/ui/stats.lua — Statistik-Tafel (GDD Kap. 11): nach jedem Try-Ende
-- und beim Sieg, WoW-Panel-Stil, ~10 s, wegklickbar; zweispaltig
-- Hogger/Schlachtzug inkl. Titel. Rendert eine fertig formatierte Tafel
-- (statboard.lua/Wire) — hier steht keine einzige Spielzahl.

local S = {}
S.__index = S

local SHOW_T = 10 -- ~10 s (GDD 11)

-- opts.sticky: bleibt stehen (finale Sieg-Tafel); opts.button: Beschriftung
-- eines Knopfs unten mittig (REVANCHE, GDD 11) — Klick liefert "button"
function S.new(board, opts)
  opts = opts or {}
  return setmetatable({ board = board, t = SHOW_T, visible = true,
                        sticky = opts.sticky, button = opts.button }, S)
end

function S:update(dt)
  if self.sticky then
    self.t = math.max(1, self.t) -- volle Deckkraft, kein Auto-Ausblenden
    return
  end
  self.t = self.t - dt
  if self.t <= 0 then self.visible = false end
end

local function panel_rect(w, h)
  local pw = math.min(760, w - 80)
  local ph = math.min(430, h - 120)
  return (w - pw) / 2, (h - ph) / 2, pw, ph
end

local function button_rect(w, h)
  local px, py, pw, ph = panel_rect(w, h)
  local bw, bh = 180, 36
  return px + (pw - bw) / 2, py + ph - bh - 14, bw, bh
end

-- Klick in die Tafel schliesst sie (wegklickbar, GDD 11); mit Knopf
-- (finale Sieg-Tafel) schliesst nur der Knopf — Rueckgabe "button"
function S:mousepressed(mx, my)
  if not self.visible then return false end
  local w, h = love.graphics.getDimensions()
  local px, py, pw, ph = panel_rect(w, h)
  if self.button then
    local bx, by, bw2, bh2 = button_rect(w, h)
    if mx >= bx and mx <= bx + bw2 and my >= by and my <= by + bh2 then
      return "button"
    end
    return mx >= px and mx <= px + pw and my >= py and my <= py + ph
  end
  if mx >= px and mx <= px + pw and my >= py and my <= py + ph then
    self.visible = false
    return true
  end
  return false
end

function S:keypressed(key)
  if not self.visible then return false end
  if key == "escape" and not self.sticky then
    self.visible = false
    return true
  end
  return false
end

function S:draw()
  if not self.visible then return end
  local b = self.board
  local w, h = love.graphics.getDimensions()
  local px, py, pw, ph = panel_rect(w, h)
  local a = math.min(1, self.t / 0.5)
  love.graphics.setColor(0.07, 0.07, 0.11, 0.95 * a)
  love.graphics.rectangle("fill", px, py, pw, ph, 6, 6)
  love.graphics.setColor(0.78, 0.63, 0.28, a)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", px, py, pw, ph, 6, 6)
  love.graphics.setLineWidth(1)

  local font = love.graphics.getFont()
  love.graphics.setColor(0.95, 0.85, 0.4, a)
  love.graphics.print(b.header, px + pw / 2 - font:getWidth(b.header), py + 12, 0, 2, 2)

  local col_w = pw / 2 - 32
  local lx, rx = px + 20, px + pw / 2 + 12
  local top = py + 52
  local line_h = font:getHeight() + 6

  local function column(x, caption, rows)
    love.graphics.setColor(0.9, 0.35, 0.3, a)
    love.graphics.print(caption, x, top)
    for i, r in ipairs(rows) do
      local y = top + 8 + i * line_h
      love.graphics.setColor(0.75, 0.72, 0.62, a)
      love.graphics.print(r[1], x, y)
      love.graphics.setColor(0.95, 0.92, 0.8, a)
      love.graphics.printf(r[2], x, y, col_w, "right")
    end
    return top + 8 + (#rows + 1) * line_h
  end

  local hy = column(lx, "Hogger", b.hogger)
  column(rx, "Schlachtzug", b.raid)

  -- Wipe-Pointe gross unter der Hogger-Spalte ("Er hatte noch 4 %.")
  if b.big then
    love.graphics.setColor(0.95, 0.55, 0.35, a)
    love.graphics.print(b.big, lx, hy + 8, 0, 1.6, 1.6)
  end

  -- Titelzeilen unten
  if #b.titles > 0 then
    local bottom_off = self.button and 60 or 18
    local ty = py + ph - bottom_off - #b.titles * line_h
    love.graphics.setColor(0.6, 0.56, 0.45, a)
    love.graphics.print("Titel des Trys", lx, ty - line_h)
    for i, t in ipairs(b.titles) do
      love.graphics.setColor(0.85, 0.75, 0.5, a)
      love.graphics.print(t, lx, ty + (i - 1) * line_h)
    end
  end

  -- REVANCHE-Knopf der finalen Tafel (GDD 11)
  if self.button then
    local bx, by, bw2, bh2 = button_rect(w, h)
    love.graphics.setColor(0.45, 0.12, 0.10, a)
    love.graphics.rectangle("fill", bx, by, bw2, bh2, 5, 5)
    love.graphics.setColor(0.95, 0.75, 0.3, a)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", bx, by, bw2, bh2, 5, 5)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.98, 0.92, 0.75, a)
    love.graphics.print(self.button,
      bx + bw2 / 2 - font:getWidth(self.button), by + 6, 0, 2, 2)
  end
end

return S
