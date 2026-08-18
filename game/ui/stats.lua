-- game/ui/stats.lua — Statistik-Tafel (GDD Kap. 11): nach jedem Try-Ende
-- und beim Sieg, WoW-Panel-Stil, ~10 s, wegklickbar; zweispaltig
-- Hogger/Schlachtzug inkl. Titel. Rendert eine fertig formatierte Tafel
-- (statboard.lua/Wire) — hier steht keine einzige Spielzahl.

local S = {}
S.__index = S

local SHOW_T = 10 -- ~10 s (GDD 11)

-- Hinweis auf der Tafel (Runde 10, #126). ASCII-Konvention wie ueberall im UI.
S.HINT = "Klick zum Schliessen"

-- opts.hold: kein Auto-Ausblenden, aber wegklickbar — die Tafel am Ende der
-- Endsequenz (Runde 11, #132) ist das letzte Bild und soll auf den Leser
-- warten. Die frueheren Knoepfe (REVANCHE / Ausloggen) und der sticky-Modus
-- sind mit der neuen Endsequenz entfallen (#133): nach dem Fluchbruch fuehrt
-- kein Weg zurueck ins Spiel, das Menue liegt jetzt auf ESC.
function S.new(board, opts)
  opts = opts or {}
  return setmetatable({ board = board, t = SHOW_T, visible = true,
                        hold = opts.hold }, S)
end

function S:update(dt)
  if self.hold then
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

-- Klick in die Tafel schliesst sie (wegklickbar, GDD 11); mit Knoepfen
-- (finale Sieg-Tafel) wirken nur die Knoepfe — Rueckgabe deren id
function S:mousepressed(mx, my)
  if not self.visible then return false end
  local w, h = love.graphics.getDimensions()
  local px, py, pw, ph = panel_rect(w, h)
  if mx >= px and mx <= px + pw and my >= py and my <= py + ph then
    self.visible = false
    return true
  end
  return false
end

function S:keypressed(key)
  if not self.visible then return false end
  if key == "escape" then
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
    local bottom_off = 18
    local ty = py + ph - bottom_off - #b.titles * line_h
    love.graphics.setColor(0.6, 0.56, 0.45, a)
    love.graphics.print("Titel des Trys", lx, ty - line_h)
    for i, t in ipairs(b.titles) do
      love.graphics.setColor(0.85, 0.75, 0.5, a)
      love.graphics.print(t, lx, ty + (i - 1) * line_h)
    end
  end

  -- Hinweis unten rechts (Runde 10, #126): dass ein Klick die Tafel
  -- schliesst, stand nirgends. Muster wie ui/victory.lua und ui/boot.lua,
  -- zusaetzlich mit dem Ausblend-Alpha multipliziert — sonst bliebe der
  -- Hinweis beim Ausfaden stehen.
  love.graphics.setColor(0.6, 0.56, 0.45,
    a * (0.6 + 0.3 * math.sin(self.t * 3)))
  love.graphics.print(S.HINT,
    px + pw - font:getWidth(S.HINT) - 14, py + ph - 22)
end

return S
