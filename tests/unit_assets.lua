-- tests/unit_assets.lua — Asset-Kontrakt (GDD 17.5) und Sound-Manifest
-- (GDD Kap. 12): jede Position der Sound-Liste hat eine ID, der Validator
-- prueft echte Dateien (PNG-Masse, Audio-Container, Dateinamensregeln).

local manifest = require("assets.manifest")
local check = require("tools.check_assets")

-- GDD-12-Liste: eine ID je Position, alle mit art + datei
local REQUIRED = {
  "snd_login_music", "snd_glitch_static",              -- 1
  "snd_ambience_elwynn", "snd_ghost_wind",             -- 2/3
  "snd_footsteps",                                     -- 4
  "snd_melee_hit",                                     -- 5
  "snd_cast_loop", "snd_impact_fire", "snd_impact_shadow",
  "snd_impact_holy", "snd_impact_frost",               -- 6
  "snd_wand", "snd_shot",                              -- 7
  "snd_shout", "snd_stealth", "snd_imp_summon",        -- 8
  "snd_crit",                                          -- 9
  "snd_hogger_growl", "snd_hogger_schmatzen",
  "snd_hogger_charge", "snd_hogger_death",             -- 10
  "snd_wolf_growl", "snd_murloc",                      -- 11
  "snd_player_death",                                  -- 12
  "snd_jump", "snd_land",                              -- 12b
  "snd_ding",                                          -- 13
  "snd_loot", "snd_ui_click",                          -- 14
  "snd_fanfare", "snd_wipe_sting",                     -- 15
  "snd_leeroy_scream",                                 -- 16
}
for _, id in ipairs(REQUIRED) do
  local spec = manifest[id]
  T.ok(spec ~= nil, "GDD-12-Slot vorhanden: " .. id)
  if spec then
    T.ok(spec.art ~= nil, id .. " hat eine Platzhalter-Art (17.5)")
    T.ok(spec.datei ~= nil, id .. " hat ein datei-Feld (17.5)")
  end
end

-- Musik/Ambience spielen Stille bis eine Datei liegt (17.5 Punkt 4)
T.eq(manifest.snd_login_music.art, "stille", "Login-Musik-Slot ist stille")
T.eq(manifest.snd_ambience_elwynn.art, "stille", "Ambience-Slot ist stille")
T.eq(manifest.snd_ghost_wind.art, "stille", "Geister-Wind-Slot ist stille")

-- Validator gegen das echte Repo: alles regelkonform
local errors = check.check(manifest, ".")
T.eq(#errors, 0, "check_assets im Repo: " .. table.concat(errors, " | "))

-- PNG-Parser liest IHDR korrekt (kuenstlicher Mini-Header)
local tmp = "tmp_check_assets_test.png"
local f = assert(io.open(tmp, "wb"))
f:write("\137PNG\r\n\26\n\0\0\0\13IHDR\0\0\0\32\0\0\0\48\8\6\0\0\0")
f:close()
local w, h = check.png_size(tmp)
T.eq(w, 32, "PNG-Breite aus IHDR")
T.eq(h, 48, "PNG-Hoehe aus IHDR")
os.remove(tmp)
T.ok(select(2, check.png_size("gibtsnicht.png")) ~= nil, "fehlende Datei = Fehler")

-- Audio-Container-Erkennung
local wav = "tmp_check_assets_test.wav"
f = assert(io.open(wav, "wb")); f:write("RIFF1234WAVE"); f:close()
T.ok(check.audio_ok(wav), "RIFF/WAV erkannt")
os.remove(wav)

-- Dateinamensregeln (GDD Kap. 14): klein, keine Umlaute/Leerzeichen
local errs = check.check({
  kaputt = { form = "kreis", groesse = 16, datei = "Bad Name.png" },
}, ".")
T.ok(#errs >= 2, "Grossbuchstabe und Leerzeichen werden beanstandet")
