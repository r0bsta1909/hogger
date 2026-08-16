-- game/session.lua — session.json (GDD 17.3): XP/Kupfer/Plunder je
-- Charaktername, Try-Zaehler, Titel. Einzige rundenuebergreifende Persistenz.
-- Atomar nach Skill Par. 6: tmp schreiben -> .bak loeschen -> json -> bak ->
-- tmp -> json. love.filesystem kann nicht umbenennen -> os.rename mit
-- absoluten Pfaden; os.rename ueberschreibt unter Windows nicht, deshalb
-- exakt diese Reihenfolge (fuer die strengere Plattform geschrieben).

local json = require("game.json")

local S = {}
local FILE = "session.json"

local function abs(name)
  return love.filesystem.getSaveDirectory() .. "/" .. name
end

function S.load()
  local raw = love.filesystem.read(FILE)
  if raw then
    local data, err = json.decode(raw)
    if data then return data end
    print("session.json defekt (" .. tostring(err) .. "), versuche .bak")
  end
  raw = love.filesystem.read(FILE .. ".bak")
  if raw then
    local data = json.decode(raw)
    if data then return data end
  end
  return nil
end

function S.save(data)
  local ok, encoded = pcall(json.encode, data)
  if not ok then return false end
  love.filesystem.write(FILE .. ".tmp", encoded .. "\n")
  os.remove(abs(FILE .. ".bak"))
  os.rename(abs(FILE), abs(FILE .. ".bak"))
  os.rename(abs(FILE .. ".tmp"), abs(FILE))
  return true
end

function S.wipe() -- "Neuer Abend" (Debug-Overlay)
  os.remove(abs(FILE))
  os.remove(abs(FILE .. ".bak"))
  os.remove(abs(FILE .. ".tmp"))
end

return S
