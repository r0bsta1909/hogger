-- game/audio.lua — Sound ueber logische IDs (GDD Kap. 12 / 17.5).
-- Liegt eine echte Datei am Manifest-Pfad, wird sie gespielt; sonst der
-- generierte Platzhalter: "blip" = Sinus mit Huellkurve, "rauschen" =
-- weisses Rauschen (Glitch-Static), "stille" = Musik-/Ambience-Slot, der
-- Stille spielt, bis eine Datei liegt (17.5 Punkt 4).
-- Master-Lautstaerke liegt im Debug-Overlay (F12, GDD 4.4) und persistiert.

local A = {}
local manifest = require("assets.manifest")

local templates = {}  -- id -> Source-Vorlage (oder false = Stille)
local loops = {}      -- id -> laufende Loop-Source
local pending = {}    -- { t, id, vol } verzoegerte Abspielung
local master = 0.8
local ghost_mod = 1.0 -- Totensicht: Welt-Sounds gedaempft (Tiefpass-Naeherung)

local VOL_FILE = "volume.dat"

function A.load()
  local raw = love.filesystem.read(VOL_FILE)
  local v = tonumber(raw)
  if v then master = math.max(0, math.min(1, v)) end
end

local RATE = 22050

local function gen_blip(freq, dur, gain)
  local n = math.floor(RATE * dur)
  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  for i = 0, n - 1 do
    local env = 1 - i / n
    sd:setSample(i, math.sin(2 * math.pi * freq * i / RATE) * env * env * gain)
  end
  return sd
end

local function gen_noise(dur, gain)
  local n = math.floor(RATE * dur)
  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  for i = 0, n - 1 do
    sd:setSample(i, (love.math.random() * 2 - 1) * gain)
  end
  return sd
end

local function get_template(id)
  local t = templates[id]
  if t ~= nil then return t end
  local spec = manifest[id]
  assert(spec and spec.art, "unbekannte Sound-ID: " .. tostring(id))
  if spec.datei and love.filesystem.getInfo("assets/" .. spec.datei) then
    t = love.audio.newSource("assets/" .. spec.datei,
                             spec.loop and "stream" or "static")
  elseif spec.art == "stille" then
    t = false -- Slot spielt Stille bis eine Datei liegt (17.5)
  elseif spec.art == "rauschen" then
    t = love.audio.newSource(gen_noise(spec.dauer or 1.0, 0.25), "static")
  else -- "blip"
    t = love.audio.newSource(
      gen_blip(spec.freq or 440, spec.dauer or 0.1, 0.5), "static")
  end
  if t and spec.loop then t:setLooping(true) end
  templates[id] = t
  return t
end

-- kartenweit: ignoriert die Totensicht-Daempfung nicht — nur die Distanz
-- ist Sache des Aufrufers (vol vorberechnen)
function A.play(id, vol)
  local t = get_template(id)
  if not t then return end
  local spec = manifest[id]
  local c = t:clone()
  c:setVolume((vol or 1) * (spec.gain or 1) * master * ghost_mod)
  love.audio.play(c)
end

function A.play_later(delay, id, vol)
  pending[#pending + 1] = { t = delay, id = id, vol = vol }
end

function A.loop_start(id, vol)
  if loops[id] ~= nil then return end
  local t = get_template(id)
  if not t then loops[id] = false return end
  local spec = manifest[id]
  local c = t:clone()
  c:setLooping(true)
  local entry = { src = c, base = (vol or 1) * (spec.gain or 1) }
  c:setVolume(entry.base * master * ghost_mod)
  love.audio.play(c)
  loops[id] = entry
end

function A.loop_stop(id)
  local e = loops[id]
  if e and e.src then e.src:stop() end
  loops[id] = nil
end

local function refresh_loops()
  for _, e in pairs(loops) do
    if e and e.src then e.src:setVolume(e.base * master * ghost_mod) end
  end
end

function A.update(dt)
  for i = #pending, 1, -1 do
    local p = pending[i]
    p.t = p.t - dt
    if p.t <= 0 then
      table.remove(pending, i)
      A.play(p.id, p.vol)
    end
  end
end

-- Totensicht (GDD 12, Nr. 3): Tiefpass-Naeherung als Daempfung der Welt
function A.set_ghost(on)
  local mod = on and 0.4 or 1.0
  if mod == ghost_mod then return end
  ghost_mod = mod
  refresh_loops()
end

function A.master()
  return master
end

function A.set_master(v)
  master = math.max(0, math.min(1, v))
  love.filesystem.write(VOL_FILE, tostring(master))
  refresh_loops()
  return master
end

-- Distanz-Lautstaerke: 1 nah, 0 ab horizon px (kartenweite Sounds: vol 1)
function A.falloff(dist, horizon)
  return math.max(0, 1 - dist / (horizon or 700))
end

return A
