-- game/ui/gamemenu.lua — das klassische WoW-Spielmenue (GDD Kap. 11).
-- Es gibt NUR nach dem Fluchbruch: der Abend ist vorbei, das Spiel wartet auf
-- harten Input. Genau ein Eintrag ist scharf ("Spiel verlassen"), die anderen
-- stehen grau da, weil sie im Original auch da stehen — das Menue ist Kulisse
-- mit einer Funktion. ESC oeffnet und schliesst es.
-- Layout und Zustand sind love-frei (Unit-Test Stufe 1), nur draw braucht love.

local M = {}

M.WIDTH = 220
M.ROW_H, M.ROW_GAP, M.PAD = 30, 8, 16

-- Reihenfolge wie im Original; nur der letzte Eintrag tut etwas.
M.ENTRIES = {
  { id = "options",  label = "Spieloptionen",     enabled = false },
  { id = "keys",     label = "Tastaturbelegung",  enabled = false },
  { id = "macros",   label = "Makros",            enabled = false },
  { id = "logout",   label = "Ausloggen",         enabled = false },
  { id = "quit",     label = "Spiel verlassen",   enabled = true },
}

function M.height()
  return M.PAD * 2 + #M.ENTRIES * M.ROW_H + (#M.ENTRIES - 1) * M.ROW_GAP
end

-- Schmales, mittiges Panel; Rueckgabe: Panel-Rechteck und je Eintrag eines
function M.layout(w, h)
  local pw, ph = M.WIDTH, M.height()
  local px, py = math.floor((w - pw) / 2), math.floor((h - ph) / 2)
  local rows = {}
  for i, e in ipairs(M.ENTRIES) do
    rows[i] = {
      id = e.id, label = e.label, enabled = e.enabled,
      rect = { px + M.PAD, py + M.PAD + (i - 1) * (M.ROW_H + M.ROW_GAP),
               pw - 2 * M.PAD, M.ROW_H },
    }
  end
  return { panel = { px, py, pw, ph }, rows = rows }
end

function M.hit(rect, mx, my)
  return mx >= rect[1] and mx <= rect[1] + rect[3]
     and my >= rect[2] and my <= rect[2] + rect[4]
end

-- id des getroffenen SCHARFEN Eintrags, sonst nil. Ein Klick auf einen grauen
-- Eintrag tut nichts — er schliesst das Menue auch nicht.
function M.click(w, h, mx, my)
  local l = M.layout(w, h)
  for _, r in ipairs(l.rows) do
    if r.enabled and M.hit(r.rect, mx, my) then return r.id end
  end
  return nil
end

-- Nur nach dem Fluchbruch (won_stage > 0 im Snapshot)
function M.available(view)
  return view ~= nil and (view.won_stage or 0) > 0
end

function M.draw(w, h, mx, my)
  local l = M.layout(w, h)
  local px, py, pw, ph = l.panel[1], l.panel[2], l.panel[3], l.panel[4]
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(0.07, 0.07, 0.11, 0.97)
  love.graphics.rectangle("fill", px, py, pw, ph, 5, 5)
  love.graphics.setColor(0.78, 0.63, 0.28, 1)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", px, py, pw, ph, 5, 5)
  love.graphics.setLineWidth(1)
  local font = love.graphics.getFont()
  for _, r in ipairs(l.rows) do
    local x, y, bw, bh = r.rect[1], r.rect[2], r.rect[3], r.rect[4]
    local hover = r.enabled and M.hit(r.rect, mx or -1, my or -1)
    local a = r.enabled and 1 or 0.35
    love.graphics.setColor(hover and 0.24 or 0.16, 0.14, 0.10, a)
    love.graphics.rectangle("fill", x, y, bw, bh, 4, 4)
    love.graphics.setColor(0.78, 0.63, 0.28, a)
    love.graphics.rectangle("line", x, y, bw, bh, 4, 4)
    love.graphics.setColor(0.98, 0.92, 0.75, a)
    love.graphics.print(r.label,
      x + bw / 2 - font:getWidth(r.label) / 2, y + bh / 2 - font:getHeight() / 2)
  end
end

return M
