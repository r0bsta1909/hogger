-- tools/png_to_icon.lua — macht aus assets/icon_app.png die Plattform-Icons
-- fuer die Release-Pipeline (GDD 17.0): Windows .ico und macOS .icns.
-- Beide Formate duerfen PNG-Daten direkt einbetten (Windows ab Vista, macOS
-- ab 10.7), deshalb reicht reines Lua: Kopf schreiben, Bytes anhaengen.
-- Kein Bildwerkzeug in der Pipeline, keine zusaetzliche Abhaengigkeit.
--
--   lua tools/png_to_icon.lua assets/icon_app.png build/hogger.ico build/hogger.icns

local M = {}

local function u16le(n)
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function u32le(n)
  return string.char(n % 256, math.floor(n / 256) % 256,
    math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function u32be(n)
  return string.char(math.floor(n / 16777216) % 256,
    math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

local function be32(s, i)
  return s:byte(i) * 16777216 + s:byte(i + 1) * 65536
       + s:byte(i + 2) * 256 + s:byte(i + 3)
end

function M.read_png(path)
  local f = assert(io.open(path, "rb"), "PNG nicht lesbar: " .. path)
  local data = f:read("*a")
  f:close()
  assert(data:sub(1, 8) == "\137PNG\r\n\26\n", "keine PNG-Datei: " .. path)
  assert(data:sub(13, 16) == "IHDR", "IHDR fehlt: " .. path)
  return data, be32(data, 17), be32(data, 21)
end

-- Windows-Icon: ein Eintrag mit eingebettetem PNG (Breite/Hoehe 0 = 256)
function M.ico(png, w, h)
  local dim_w = (w >= 256) and 0 or w
  local dim_h = (h >= 256) and 0 or h
  local dir = u16le(0) .. u16le(1) .. u16le(1)
  local entry = string.char(dim_w, dim_h, 0, 0) .. u16le(1) .. u16le(32)
                .. u32le(#png) .. u32le(22)
  return dir .. entry .. png
end

-- macOS-Icon: ic08 = 256x256 PNG, ic09 = 512x512 PNG
function M.icns(png, w)
  local typ = (w >= 512) and "ic09" or "ic08"
  local entry = typ .. u32be(#png + 8) .. png
  return "icns" .. u32be(#entry + 8) .. entry
end

local function write(path, data)
  local f = assert(io.open(path, "wb"), "nicht schreibbar: " .. path)
  f:write(data)
  f:close()
end

-- Als Skript gestartet ist der erste Vararg das erste CLI-Argument, als
-- Modul der Modulname — daran unterscheiden wir beide Faelle
local first = ...
if first == (arg and arg[1]) then
  local src = arg[1] or "assets/icon_app.png"
  local ico = arg[2] or "build/hogger.ico"
  local icns = arg[3] or "build/hogger.icns"
  local png, w, h = M.read_png(src)
  assert(w == h, string.format("Icon muss quadratisch sein (%dx%d)", w, h))
  assert(w >= 256, "Icon braucht mindestens 256 px, hat " .. w)
  write(ico, M.ico(png, w, h))
  write(icns, M.icns(png, w))
  print(string.format("%s (%dx%d) -> %s, %s", src, w, h, ico, icns))
end

return M
