-- tools/check_assets.lua — Asset-Kontrakt-Validator (GDD 17.5 Punkt 5).
-- Prueft jede ECHTE Datei unter assets/ gegen das Manifest: PNG-Masse
-- (IHDR direkt aus dem Header gelesen, reines Lua), Audio-Container
-- (RIFF/OggS), Dateinamensregeln (klein, keine Umlaute/Leerzeichen,
-- GDD Kap. 14). Ein falsch geliefertes Final-Asset faellt im Test auf,
-- nicht auf der LAN. Laeuft in der Test-Suite und als CLI:
--   lua tools/check_assets.lua

local M = {}

local function read_bytes(path, n)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read(n)
  f:close()
  return data
end

local function be32(s, i)
  return s:byte(i) * 16777216 + s:byte(i + 1) * 65536
       + s:byte(i + 2) * 256 + s:byte(i + 3)
end

-- PNG: 8 Byte Signatur, dann Laenge(4) + "IHDR" + Breite(4) + Hoehe(4)
function M.png_size(path)
  local head = read_bytes(path, 26)
  if not head or #head < 26 then return nil, "Datei zu kurz" end
  if head:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil, "keine PNG-Signatur" end
  if head:sub(13, 16) ~= "IHDR" then return nil, "IHDR fehlt" end
  return be32(head, 17), be32(head, 21)
end

function M.audio_ok(path)
  local head = read_bytes(path, 4)
  if not head then return false, "nicht lesbar" end
  if head == "OggS" then return true end
  if head == "RIFF" then return true end
  if head:sub(1, 3) == "ID3" or head:byte(1) == 255 then return true end -- mp3
  return false, "unbekannter Audio-Container (erwartet ogg/wav/mp3)"
end

-- root: Repo-Wurzel (Standard "."); Rueckgabe: Fehlerliste, Anzahl Dateien
function M.check(manifest, root)
  root = root or "."
  local errors = {}
  local found = 0
  local ids = {}
  for id in pairs(manifest) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local spec = manifest[id]
    local name = spec.datei
    if not name then
      errors[#errors + 1] = id .. ": kein datei-Feld im Manifest"
    else
      -- Dateinamensregeln gelten immer (GDD Kap. 14, macOS/CI-Falle)
      if name ~= name:lower() then
        errors[#errors + 1] = id .. ": Dateiname nicht klein: " .. name
      end
      if name:find("[ %z\128-\255]") then
        errors[#errors + 1] = id .. ": Umlaut/Leerzeichen im Namen: " .. name
      end
      local path = root .. "/assets/" .. name
      -- Windows blendet bekannte Endungen aus: "icon_x.png" wird beim
      -- Speichern zu "icon_x.png.png" und die Datei bleibt unsichtbar
      local ext = name:match("%.(%w+)$")
      if ext then
        local dbl = io.open(path .. "." .. ext, "rb")
        if dbl then
          dbl:close()
          errors[#errors + 1] = id .. ": Datei liegt als " .. name .. "." .. ext
            .. " (Endung doppelt) — umbenennen nach " .. name
        end
      end
      local f = io.open(path, "rb")
      if f then
        f:close()
        found = found + 1
        if spec.art then
          local ok, err = M.audio_ok(path)
          if not ok then errors[#errors + 1] = id .. ": " .. err end
        else
          local w, h, err
          w, h = M.png_size(path)
          if not w then
            err = h
            errors[#errors + 1] = id .. ": " .. tostring(err)
          else
            local want_w = spec.breite or spec.groesse
            local want_h = spec.hoehe or spec.groesse
            if spec.groesse then
              -- Icons: quadratisch und mindestens Rastermasse; groessere
              -- Exporte werden beim Zeichnen normalisiert (17.5)
              if w ~= h then
                errors[#errors + 1] = string.format(
                  "%s: %dx%d ist nicht quadratisch (Icon-PNGs quadratisch "
                  .. "exportieren, Rand egal)", id, w, h)
              elseif w < want_w then
                errors[#errors + 1] = string.format(
                  "%s: %dx%d ist kleiner als das Raster %dx%d", id, w, h,
                  want_w, want_h)
              end
            elseif spec.masse == "mindestens" then
              -- bildschirmfuellend gezeichnete Flaechen (Splash) werden
              -- cover-skaliert; hier zaehlt nur genug Aufloesung (17.5)
              if w < want_w or h < want_h then
                errors[#errors + 1] = string.format(
                  "%s: Masse %dx%d, Manifest verlangt mindestens %dx%d",
                  id, w, h, want_w, want_h)
              end
            elseif w ~= want_w or h ~= want_h then
              errors[#errors + 1] = string.format(
                "%s: Masse %dx%d, Manifest verlangt %dx%d (17.5: exakt)",
                id, w, h, want_w, want_h)
            end
          end
        end
      end
    end
  end
  return errors, found
end

-- CLI: `lua tools/check_assets.lua` (als Modul required: nur Funktionen)
local modname = ...
if not modname then
  package.path = "./?.lua;" .. package.path
  local manifest = require("assets.manifest")
  local errors, found = M.check(manifest, ".")
  print(string.format("%d echte Asset-Dateien geprueft, %d Fehler",
    found, #errors))
  for _, e in ipairs(errors) do print("FEHLER  " .. e) end
  if #errors > 0 then os.exit(1) end
end

return M
