-- game/ui/release.lua — "Geist freilassen" (GDD Kap. 11, Referenz
-- docs/referenzen/geist freilassen.png). Wer getoetet wird, liegt erst
-- einmal da: Ueberschrift mit Restzeit, darunter der rote Knopf. Erst mit
-- Ablauf des Respawn-Timers wird er scharf — die Wartezeit IST die
-- Todesstrafe (GDD Kap. 6) und darf nicht wegklickbar sein.
-- Layout und Zustand sind love-frei (Unit-Test Stufe 1).

local R = {}

R.WIDTH, R.HEIGHT = 340, 74

-- Panel oben mittig; Rueckgabe: Panel- und Knopf-Rechteck
function R.layout(w, h)
  local pw, ph = R.WIDTH, R.HEIGHT
  local px, py = math.floor((w - pw) / 2), math.floor(h * 0.12)
  return {
    panel = { px, py, pw, ph },
    button = { px + 90, py + 36, pw - 180, 28 },
  }
end

function R.hit(rect, mx, my)
  return mx >= rect[1] and mx <= rect[1] + rect[3]
     and my >= rect[2] and my <= rect[2] + rect[4]
end

-- Ueberschrift wie im Original: erst der Countdown, dann die Aufforderung
function R.headline(rest)
  rest = math.max(0, math.floor((rest or 0) + 0.5))
  if rest > 0 then
    return string.format("%d Sekunden bis zur Freigabe", rest)
  end
  return "Bereit zur Freigabe"
end

function R.ready(rest)
  return (rest or 0) <= 0
end

-- me: eigener Spieler aus der Sicht; sichtbar nur zwischen Tod und Freigabe
function R.visible(me)
  return me ~= nil and not me.alive and not me.ghost
end

function R.draw(me, w, h, hover)
  if not R.visible(me) then return end
  local L = R.layout(w, h)
  local p, b = L.panel, L.button
  local rest = me.dead_rest or 0
  local ready = R.ready(rest)
  local font = love.graphics.getFont()

  love.graphics.setColor(0.04, 0.04, 0.05, 0.92)
  love.graphics.rectangle("fill", p[1], p[2], p[3], p[4], 4, 4)
  love.graphics.setColor(0.42, 0.36, 0.24, 1)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", p[1], p[2], p[3], p[4], 4, 4)
  love.graphics.setLineWidth(1)

  local head = R.headline(rest)
  love.graphics.setColor(0.92, 0.90, 0.84, 1)
  love.graphics.print(head, p[1] + p[3] / 2 - font:getWidth(head) / 2, p[2] + 12)

  -- Knopf: scharf erst nach Ablauf des Timers
  local a = ready and 1 or 0.4
  love.graphics.setColor(0.16 * a + 0.04, 0.05 * a + 0.03, 0.04 * a + 0.03, 1)
  love.graphics.rectangle("fill", b[1], b[2], b[3], b[4], 3, 3)
  love.graphics.setColor(0.75 * a, 0.20 * a, 0.16 * a, 1)
  love.graphics.setLineWidth(ready and 2 or 1)
  love.graphics.rectangle("line", b[1], b[2], b[3], b[4], 3, 3)
  love.graphics.setLineWidth(1)
  local label = "Geist freilassen"
  love.graphics.setColor(ready and (hover and 1 or 0.95) or 0.55,
    ready and (hover and 0.85 or 0.75) or 0.5,
    ready and (hover and 0.75 or 0.65) or 0.48, 1)
  love.graphics.print(label, b[1] + b[3] / 2 - font:getWidth(label) / 2,
    b[2] + b[4] / 2 - font:getHeight() / 2)
end

return R
