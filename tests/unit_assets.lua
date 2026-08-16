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

-- Masse-Regeln: exakt fuer Icons, "mindestens" nur fuer cover-skalierte
-- Flaechen (Splash) — sonst waere jede Aufloesung ein Fehler
T.eq(manifest.splash_login.masse, "mindestens", "Splash darf groesser sein")
for id, spec in pairs(manifest) do
  if not spec.art and id ~= "splash_login" then
    T.eq(spec.masse, nil, id .. " haelt die exakte Manifest-Masse (17.5)")
  end
end

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

-- Icon-Kontrakt v2.7 (17.5): quadratisch, mindestens Rastermasse; groessere
-- Exporte werden beim Zeichnen normalisiert. Der Validator muss beides
-- erkennen — sonst faellt ein schiefes Final-Asset erst auf der LAN auf.
-- (Testdateien liegen kurz in assets/ und heissen tmp_*, damit kein
-- Verzeichnis angelegt werden muss.)
do
  local function be32(n)
    return string.char(math.floor(n / 16777216) % 256,
      math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
  end
  local function png(name, w, h)
    local f = assert(io.open("assets/" .. name, "wb"))
    local sig = string.char(137, 80, 78, 71, 13, 10, 26, 10)
    f:write(sig .. string.char(0, 0, 0, 13) .. "IHDR" .. be32(w)
            .. be32(h) .. string.char(8, 6, 0, 0, 0))
    f:close()
  end
  local mani = {
    tmp_gut    = { form = "kreis", groesse = 32, farbe = { 1, 1, 1 }, datei = "tmp_gut.png" },
    tmp_schief = { form = "kreis", groesse = 32, farbe = { 1, 1, 1 }, datei = "tmp_schief.png" },
    tmp_klein  = { form = "kreis", groesse = 32, farbe = { 1, 1, 1 }, datei = "tmp_klein.png" },
  }
  png("tmp_gut.png", 500, 500)
  png("tmp_schief.png", 696, 225)
  png("tmp_klein.png", 16, 16)
  png("tmp_gut.png.png", 500, 500) -- Windows-Falle: Endung doppelt
  local errs = check.check(mani, ".")
  local joined = table.concat(errs, " | ")
  T.eq(#errs, 3, "Validator: drei Befunde (" .. joined .. ")")
  T.ok(joined:find("nicht quadratisch") ~= nil, "Validator: schiefes Icon faellt auf")
  T.ok(joined:find("kleiner als das Raster") ~= nil, "Validator: zu kleines Icon faellt auf")
  T.ok(joined:find("Endung doppelt") ~= nil, "Validator: doppelte Endung faellt auf")
  for _, n in ipairs({ "tmp_gut.png", "tmp_schief.png", "tmp_klein.png",
                       "tmp_gut.png.png" }) do
    os.remove("assets/" .. n)
  end
end

-- Programm-Icon (Issue #37): aus einer PNG werden die Plattform-Icons.
-- Beide Formate betten PNG-Daten ein — die Koepfe muessen exakt stimmen,
-- sonst zeigt Windows still das Standardsymbol.
do
  local icon = require("tools.png_to_icon")
  local png, w, h = icon.read_png("assets/icon_app.png")
  T.eq(w, h, "Programm-Icon ist quadratisch")
  T.ok(w >= 256, "Programm-Icon mindestens 256 px (" .. w .. ")")

  local ico = icon.ico(png, w, h)
  T.eq(ico:sub(1, 6), string.char(0, 0, 1, 0, 1, 0), "ICO-Kopf: ein Icon-Eintrag")
  T.eq(ico:byte(7), 0, "ICO: Breite 0 steht fuer 256")
  T.eq(ico:byte(13), 32, "ICO: 32 Bit Farbtiefe")
  T.eq(ico:byte(19), 22, "ICO: Nutzdaten beginnen bei Offset 22")
  T.eq(ico:sub(23, 26), "\137PNG", "ICO: eingebettete PNG-Daten")
  T.eq(#ico, 22 + #png, "ICO: Groesse = Kopf + PNG")

  local icns = icon.icns(png, w)
  T.eq(icns:sub(1, 4), "icns", "ICNS-Magie")
  T.eq(icns:sub(9, 12), "ic08", "ICNS: 256er-Slot")
  T.eq(#icns, #png + 16, "ICNS: Groesse = zwei Koepfe + PNG")
  local total = icns:byte(5) * 16777216 + icns:byte(6) * 65536
                + icns:byte(7) * 256 + icns:byte(8)
  T.eq(total, #icns, "ICNS: Groessenfeld stimmt")
end
