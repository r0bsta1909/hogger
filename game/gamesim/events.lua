-- game/gamesim/events.lua — Ereignisse im 17.3-Schema, plus JSONL-Serialisierung.
-- Reines Lua; dieselbe Serialisierung speist Log-Datei UND Determinismus-Hash.

local M = {}

-- {"t":..,"ev":"..","src":"..","dst":..,"val":..,"crit":..[,"art":".."]}
-- art = Schadensart bei damage-Ereignissen (GDD 17.3): autohit, ability,
-- dot, charge, slice, mob, add — sie steuert Darstellung und Sound.
function M.to_jsonl(e)
  local parts = {
    '"t":' .. tostring(e.t),
    '"ev":"' .. e.ev .. '"',
    '"src":"' .. tostring(e.src) .. '"',
    '"dst":' .. (e.dst ~= nil and ('"' .. tostring(e.dst) .. '"') or "null"),
    '"val":' .. (e.val ~= nil and string.format("%.17g", e.val) or "null"),
    '"crit":' .. (e.crit ~= nil and tostring(e.crit) or "null"),
  }
  if e.art then parts[#parts + 1] = '"art":"' .. tostring(e.art) .. '"' end
  -- Zusatzfelder (nur try_end: Sprungzaehler laut GDD 17.3)
  if e.jumps then
    local js = {}
    for i = 1, #e.jumps do
      js[i] = '"' .. tostring(e.jumps[i][1]) .. '":' .. tostring(e.jumps[i][2])
    end
    parts[#parts + 1] = '"jumps":{' .. table.concat(js, ",") .. "}"
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function M.push(list, tick, ev, src, dst, val, crit, art)
  list[#list + 1] = { t = tick, ev = ev, src = src, dst = dst, val = val,
                      crit = crit, art = art }
  return list[#list]
end

return M
