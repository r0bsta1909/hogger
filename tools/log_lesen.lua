-- tools/log_lesen.lua — rechnet einen echten Spielabend nach (Runde 14, #175).
--
--   lua tools/log_lesen.lua <pfad/session-20260820-201500.jsonl> [--out bericht.md]
--
-- Das Host-Log (GDD 17.3) liegt unter:
--   Windows  %APPDATA%\LOVE\hogger\logs\
--   macOS    ~/Library/Application Support/LOVE/hogger/logs/
-- Es ist die einzige Datei, die einen gespielten Abend nachrechenbar macht —
-- session.json enthaelt nur XP, Kupfer, Plunder und den Try-Zaehler.
--
-- Die Rechenarbeit steckt in tools/logreport.lua (dort auch der Test).

package.path = "./?.lua;" .. package.path

local logreport = require("tools.logreport")

local path, outfile
do
  local i = 1
  while i <= #arg do
    if arg[i] == "--out" then i = i + 1; outfile = arg[i]
    else path = arg[i] end
    i = i + 1
  end
end

if not path then
  io.write("Aufruf: lua tools/log_lesen.lua <session-*.jsonl> [--out bericht.md]\n")
  os.exit(2)
end

local fh, err = io.open(path, "r")
if not fh then
  io.write("Log nicht lesbar: ", tostring(err), "\n")
  os.exit(2)
end

local r = logreport.analyse(fh:lines())
fh:close()

-- Parameterabweichungen nur, wenn das Modell greifbar ist (aus dem Repo
-- heraus immer; als kopierte Einzeldatei faellt der Abschnitt weg).
local defaults
do
  local ok, model = pcall(require, "sim.model")
  if ok then defaults = model.defaults end
end

local text = logreport.render(r, path:match("[^/\\]+$") or path, defaults)
io.write(text)

if outfile then
  local f = assert(io.open(outfile, "w"))
  f:write(text)
  f:close()
  io.write("\nBericht geschrieben: ", outfile, "\n")
end
