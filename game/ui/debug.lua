-- game/ui/debug.lua — F12-Debug-Overlay (GDD Kap. 3/14): manuelle IP,
-- Host erzwingen, Neuer Abend (session.json loeschen), Log-Pfad.
-- Kein normaler Spieler sieht das je; die Fiktion kennt kein Menue.

local D = {}
D.__index = D

function D.new()
  return setmetatable({ visible = false, ip_input = "", note = nil }, D)
end

function D:toggle() self.visible = not self.visible end

-- Rueckgabe: "host" | {join=ip} | "wipe" | "kill" | "intro" | "realm"
--            | {volume=d} | true (geschluckt) | false
function D:keypressed(key)
  if not self.visible then return false end
  if key == "f12" or key == "escape" then
    self.visible = false
  elseif key == "h" then
    return "host"
  elseif key == "n" then
    return "wipe"
  elseif key == "k" then
    return "kill"   -- Hogger sofort toeten (Issue #35)
  elseif key == "r" then
    return "intro"  -- Boot + Quest des Echos noch einmal (Issue #36)
  elseif key == "z" then
    return "realm"  -- kompletter Neustart des Realms (Issue #36)
  elseif key == "t" then
    return "teleport" -- sofort als Zufallsklasse vor Hogger (Issue #100)
  elseif key == "d" then
    return "dock"   -- HUD-Andock-Vorschau umschalten (M12)
  elseif key == "+" or key == "kp+" then
    return { volume = 0.1 } -- Lautstaerke lebt hier (GDD 4.4)
  elseif key == "-" or key == "kp-" then
    return { volume = -0.1 }
  elseif key == "backspace" then
    self.ip_input = self.ip_input:sub(1, -2)
  elseif key == "return" and #self.ip_input >= 7 then
    local ip = self.ip_input
    self.ip_input = ""
    return { join = ip }
  end
  return true
end

function D:textinput(t)
  if not self.visible then return false end
  if t:match("^[%d%.]$") and #self.ip_input < 15 then
    self.ip_input = self.ip_input .. t
  end
  return true
end

function D:draw(info)
  if not self.visible then return end
  local w = love.graphics.getWidth()
  local pw, ph = 500, 344
  local px, py = 24, 60
  love.graphics.setColor(0.05, 0.06, 0.09, 0.94)
  love.graphics.rectangle("fill", px, py, pw, ph, 4, 4)
  love.graphics.setColor(0.5, 0.7, 0.5, 1)
  love.graphics.rectangle("line", px, py, pw, ph, 4, 4)
  local lines = {
    "DEBUG (F12)",
    "Modus: " .. (info.mode or "?") .. "   eigene IP: " .. (info.own_ip or "?"),
    "Lobbys gefunden: " .. (info.lobbies or 0),
    "Logs: " .. (info.log_dir or "?"),
    "",
    "[H] Host erzwingen    [N] Neuer Abend (session.json loeschen)",
    "[K] Hogger sofort toeten (Host)   [R] Quest des Echos noch einmal",
    "[Z] Neuer Realm (frischer Abend, Quest, Leeroy wartet wieder)",
    "[T] Teleport vor Hogger als Zufallsklasse (Host, Testhilfe)",
    "[D] HUD am Ring andocken (Vorschau): "
      .. (info.docked and "AN" or "aus"),
    "[+/-] Lautstaerke: " .. string.format("%d %%", (info.volume or 0) * 100),
    info.net or "Netz: keine Fehler",
    "IP eintippen + Enter verbindet: " .. self.ip_input .. "_",
    info.note or "",
  }
  for i, line in ipairs(lines) do
    love.graphics.setColor(0.85, 0.9, 0.85, 1)
    love.graphics.print(line, px + 12, py + 8 + (i - 1) * 22)
  end
end

return D
