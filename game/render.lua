-- game/render.lua — Die Minimap IST das Spiel (GDD Kap. 4).
-- Bildschirmfuellender Kreis, eigener Spieler = goldener Pfeil im Zentrum,
-- alle anderen Entitaeten als Icons; Render-Hierarchie nach GDD 4.1.
-- Konsumiert eine dekodierte Snapshot-Sicht (Host und Client identisch).

local model = require("sim.model")
local map = require("game.data.map")
local names = require("game.data.names")
local world = require("game.gamesim.world")
local input = require("game.gamesim.input")
local assets = require("game.assets")

local R = {}
R.__index = R

local CLASS_ICON, FLOOR_ICON = {}, {}
for slot, class in ipairs(world.CLASSES) do
  CLASS_ICON[class] = "icon_" .. class
  FLOOR_ICON[slot] = "floor_" .. class
end
local ABILITY_ICON = {
  heroic = "ab_heroic", shout = "ab_shout", raptor = "ab_raptor",
  sinister = "ab_sinister", evis = "ab_evis", stealth = "ab_stealth",
  smite = "ab_smite", heal = "ab_heal", holylight = "ab_holylight",
  seal = "ab_seal", fireball = "ab_fireball", frostarmor = "ab_frostarmor",
  bolt = "ab_bolt", imp = "ab_imp", wrath = "ab_wrath", touch = "ab_touch",
  taunt = "ab_taunt", kick = "ab_kick", -- Spott/Tritt (Runde 12, #140/#141)
  loh = "ab_loh", -- Handauflegung (Runde 13, #155)
  pws = "ab_pws", -- Machtwort: Schild (Runde 13, #156)
  feign = "ab_feign", -- Totstellen (Runde 13, #157)
  roots = "ab_roots", -- Gnarlwurzeln (Runde 13, #158)
}
local ABILITIES = require("game.gamesim.step").ABILITIES
local ABILITIES_ENABLED = require("game.gamesim.step").ability_enabled
local ICON_RADIUS = require("game.gamesim.step").ICON_RADIUS
-- Heilerklassen, abgeleitet aus den Faehigkeiten (Runde 7, eine Wahrheit)
local ALLY_SLOT = require("game.gamesim.step").ALLY_SLOT
local UI_BG = { 0.09, 0.08, 0.07 }
local GRASS = { 0.30, 0.44, 0.22 }
local PATH = { 0.48, 0.40, 0.26 }
-- Klassenfarben (Vanilla) fuer Portraitrahmen und Namensbalken (GDD 4.3)
local CLASS_COL = {
  warrior = { 0.78, 0.61, 0.43 }, paladin = { 0.96, 0.55, 0.73 },
  hunter  = { 0.67, 0.83, 0.45 }, rogue   = { 1.00, 0.96, 0.41 },
  priest  = { 1.00, 1.00, 1.00 }, mage    = { 0.41, 0.80, 0.94 },
  warlock = { 0.58, 0.51, 0.79 }, druid   = { 1.00, 0.49, 0.04 },
}
-- Autoangriff je Klasse in Worten (GDD 8.1) — beim Jaeger IST der Autoschuss
-- die erste "Faehigkeit", er hat deshalb nur einen Button (GDD 8.2).
-- Seit Runde 12 (#145) gibt es keinen Nahkampf-Button mehr: Rechtsklick
-- aufs Ziel schaltet jede Autoattack an, der Jaeger wechselt automatisch.
local AUTO_DE = {
  melee = "Rechtsklick auf Ziel = Autoattack",
  shot = "Rechtsklick auf Ziel = Autoattack (nah: Nahkampf, fern: Schuss)",
}
local RES_DE = { mana = "Mana", rage = "Wut", energy = "Energie" }

-- Effektive Maximal-HP eines Snapshot-Spielers (Runde 13, #159): der
-- Blutpakt hebt den Deckel um warlock_pact_hp_pct — der Client rechnet
-- dieselbe Formel wie step.effective_max_hp aus dem flags3-Bit und den
-- synchronen Params (WELCOME/PARAM_SET), eine Wahrheit, kein Extra-Byte.
local function client_max_hp(p)
  local base = p.class and model.hp_for_class(p.class) or 0
  if p.pact then base = base * (1 + model.p("warlock_pact_hp_pct")) end
  return base
end

-- Buffs und Debuffs mit Tooltip (GDD 4.3/8.2/9.2, Issue #65). Die Zahlen
-- kommen aus model.lua, damit Anzeige und Wirkung nie auseinanderlaufen.
local AURA = {
  shout = { kuerzel = "SR", name = "Schlachtruf", debuff = false,
    text = function()
      return { string.format("+%d %% Schaden fuer Verbuendete im Umkreis",
                 model.p("warrior_shout_bonus") * 100),
               string.format("Haelt %d s, stapelt nicht",
                 model.p("warrior_shout_duration")) }
    end },
  seal = { kuerzel = "SG", name = "Siegel der Rechtschaffenheit", debuff = false,
    text = function()
      return { string.format("Die naechsten %d Autohits verursachen",
                 model.p("paladin_seal_hits")),
               string.format("+%d Heiligschaden",
                 model.p("paladin_seal_bonus_dmg")) }
    end },
  frost = { kuerzel = "FR", name = "Frostruestung", debuff = false,
    text = function()
      return { string.format("Trifft Hogger dich, ist er %d s",
                 model.p("mage_frostarmor_slow_duration")),
               string.format("um %d %% verlangsamt",
                 model.p("mage_frostarmor_slow") * 100) }
    end },
  stealth = { kuerzel = "VS", name = "Verstohlenheit", debuff = false,
    text = function()
      return { string.format("Unsichtbar, %d %% Tempo",
                 model.p("rogue_stealth_speed") * 100),
               "Hogger ignoriert dich",
               "Bricht beim Angriff" }
    end },
  pws = { kuerzel = "MS", name = "Machtwort: Schild", debuff = false,
    text = function()
      return { string.format("Absorbiert die naechsten %d Schaden",
                 model.p("priest_pws_absorb")),
               string.format("Haelt %d s", model.p("priest_pws_duration")) }
    end },
  pact = { kuerzel = "BP", name = "Blutpakt", debuff = false,
    text = function()
      return { string.format("+%d %% Maximal-HP, solange du im",
                 model.p("warlock_pact_hp_pct") * 100),
               "Umkreis eines lebenden Wichtels stehst" }
    end },
  weak_soul = { kuerzel = "SS", name = "Schwache Seele", debuff = true,
    text = function()
      return { "Kann kein neues Machtwort: Schild",
               string.format("erhalten (%d s je Ziel)",
                 model.p("priest_pws_weaksoul")) }
    end },
  bleed = { kuerzel = "BL", name = "Blutung", debuff = true,
    text = function()
      return { string.format("%d Schaden alle %.1f s",
                 model.p("hogger_slice_bleed_dmg"),
                 model.p("hogger_slice_bleed_interval")),
               "Vicious Slice von Hogger",
               "Kein Krit, keine Heilung dagegen" }
    end },
  -- Hoggers Frost-Slow (Runde 8, #107): existierte in der Sim, war aber
  -- unsichtbar — jetzt als Debuff an seiner Zieltafel (Magier-Kit ablesbar)
  slow = { kuerzel = "VL", name = "Verlangsamt", debuff = true,
    text = function()
      return { string.format("Hogger ist um %d %% verlangsamt",
                 model.p("mage_frostarmor_slow") * 100),
               string.format("Frostruestung, haelt %d s je Treffer",
                 model.p("mage_frostarmor_slow_duration")) }
    end },
}

function R.new()
  local self = setmetatable({}, R)
  self.zoom = 2 -- Stufe 1..3 (GDD 4.2)
  self.banner_t = 0
  self.banner_text = nil
  self.shake = 0
  self.toasts = {} -- Loot-Toasts am Kreisrand (GDD 7.3)
  self.killcam_t = 0     -- Killcam-Zeile, 2 s (GDD 11)
  self.killcam_text = nil
  self.effects = {}      -- DING-Ringe u. ae. (Weltkoordinaten)
  return self
end

function R:show_killcam(text)
  self.killcam_text = text
  self.killcam_t = 2.0 -- GDD 11: 2 s
end

-- DING-Inszenierung: goldener Ring am Icon (GDD 7.3)
function R:add_ding(wx, wy)
  self.effects[#self.effects + 1] = { x = wx, y = wy, t = 1.5, total = 1.5 }
end

-- ---------------------------------------------------------------------------
-- Kampf-Effekte (GDD 4.1): Symbole, keine Sprites. Ein Treffer erzeugt eine
-- kurze Spur von der Quelle zum Ziel plus einen Einschlag — damit ist
-- sichtbar, WER gerade WAS macht, nicht nur dass eine Zahl auftaucht (#30).
-- Schule/Form ergeben sich aus Klasse und Schadensart ("art", GDD 17.3).
-- ---------------------------------------------------------------------------
local SCHOOL = {
  mage    = { 1.00, 0.55, 0.15 },  -- Feuer
  warlock = { 0.62, 0.35, 0.95 },  -- Schatten
  priest  = { 1.00, 0.95, 0.70 },  -- Heilig
  druid   = { 0.55, 0.90, 0.35 },  -- Natur
}
local MELEE_COL = { 0.95, 0.95, 0.90 }
local ENEMY_COL = { 0.95, 0.35, 0.25 }

-- src_class = Klasse des Angreifers (nil bei Hogger/Mobs), art aus dem Event
function R:add_attack_fx(src_class, attack, art, sx, sy, tx, ty)
  if art == "dot" then return end -- Blutung hat kein Geschoss
  local form, col
  if not src_class then
    form = (art == "charge") and "charge" or "slash"
    col = ENEMY_COL
  elseif attack == "shot" and art ~= "ability" then
    form, col = "arrow", { 0.85, 0.85, 0.75 }
  elseif art == "ability" and SCHOOL[src_class] then
    -- Zauber als Geschoss in Schulfarbe; den Zauberstab gibt es seit
    -- Runde 5 nicht mehr (Issue #86), Caster-Autohits sind weisse Slashes
    form, col = "bolt", SCHOOL[src_class]
  else
    form, col = "slash", MELEE_COL
  end
  self.fx = self.fx or {}
  if #self.fx > 60 then return end -- Budget wie beim Floating Text (4.1)
  self.fx[#self.fx + 1] = { form = form, col = col, t = 0.22, total = 0.22,
                            sx = sx, sy = sy, tx = tx, ty = ty }
end

function R:add_heal_fx(tx, ty)
  self.fx = self.fx or {}
  if #self.fx > 60 then return end
  self.fx[#self.fx + 1] = { form = "heal", col = { 0.35, 0.95, 0.45 },
                            t = 0.5, total = 0.5, sx = tx, sy = ty,
                            tx = tx, ty = ty }
end

-- Fehlermeldung im Original-Ton (Issue #56): rot, kurz, blinkt einmal auf
-- und ist wieder weg. Ersetzt den Dauertext zur Blickrichtung.
function R:error(text)
  if self.err_text == text and (self.err_t or 0) > 1.4 then return end
  self.err_text = text
  self.err_t = 2.0
end

-- kurzer roter Rand, wenn man selbst getroffen wird (Issue #31)
function R:add_hurt_flash(strength)
  self.hurt = math.max(self.hurt or 0, strength or 0.5)
end

function R:toast(text)
  table.insert(self.toasts, 1, { text = text, t = 4 })
  if #self.toasts > 5 then table.remove(self.toasts) end
end

-- Deterministische Zeichenreihenfolge der Spieler (Runde 7): pairs() ueber
-- view.players ist Hash-Reihenfolge — im Nahkampf-Klumpen flackerte damit,
-- wer wen ueberdeckt, und der Klick-Gleichstand war zufaellig. pid-sortiert
-- zeichnet die hoehere pid stabil ueber die niedrigere.
function R.sorted_pids(players)
  local pids = {}
  for pid in pairs(players) do pids[#pids + 1] = pid end
  table.sort(pids)
  return pids
end

-- Karten-Klickziel (Runde 13, #154) — love-frei, EINE Wahrheit fuer
-- main.lua und die Stufe-1-Tests. Linksklick: naechstes Zentrum im festen
-- 24-px-Radius, Spieler vor NPC vor Hogger (wie seit Runde 7 — Heiler
-- brauchen ihre Klickziele). Rechtsklick ist der ANGRIFFSKLICK und
-- bevorzugt Feinde: Hogger gewinnt jeden Rechtsklick innerhalb seines
-- Icon-Radius (Manifest-Groesse 48 x scale — sein 121-px-Icon ist breiter
-- als der ganze Nahkampfkreis, mit dem 24-px-Test lag fast immer ein
-- Spielerzentrum naeher am Cursor), Mobs innerhalb der ueblichen 24 px;
-- erst wenn kein Feind trifft, faellt er auf die Linksklick-Wahl zurueck.
-- Ein toter oder resetteter Hogger ist nie Ziel (war vorher klickbar).
-- Rueckgabe: ziel_id oder nil, ist_feind.
function R.pick_target(view, mx, my, to_screen, scale, right_click)
  local function dist_to(wx, wy)
    local x, y = to_screen(wx, wy)
    return math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
  end
  local hg = view.hogger
  local hogger_ok = hg and (hg.hp or 0) > 0 and hg.state ~= "reset"
  if right_click then
    if hogger_ok and dist_to(hg.x, hg.y) <= 48 * scale then
      return world.HOGGER_ID, true
    end
    local best, best_d = nil, 24
    for nid, npc in pairs(view.npcs or {}) do
      if npc.kind ~= "imp" then
        local d = dist_to(npc.x, npc.y)
        if d < best_d then best, best_d = nid, d end
      end
    end
    if best then return best, true end
  end
  local best, best_d, best_enemy = nil, 24, false
  -- pid-sortiert statt pairs(): der Gleichstands-Fall (exakt gleiche
  -- Distanz) ist damit auf jedem Rechner derselbe (Runde 7)
  for _, pid in ipairs(R.sorted_pids(view.players)) do
    if pid ~= view.me then
      local p = view.players[pid]
      local d = dist_to(p.x, p.y)
      if d < best_d then best, best_d, best_enemy = pid, d, false end
    end
  end
  for nid, npc in pairs(view.npcs or {}) do
    if npc.kind ~= "imp" then
      local d = dist_to(npc.x, npc.y)
      if d < best_d then best, best_d, best_enemy = nid, d, true end
    end
  end
  if hogger_ok then
    local d = dist_to(hg.x, hg.y)
    if d < best_d then best, best_d, best_enemy = world.HOGGER_ID, d, true end
  end
  return best, best_enemy
end

-- Raid-Overview (Runde 6, Issue #95): love-freie Zeilenaufbereitung —
-- wer ist dabei, welche Klasse, lebend/Geist/tot. Sortierung: Lebende,
-- dann Geister, dann Tote; innerhalb alphabetisch.
function R.raid_rows(view)
  local rows = {}
  local names = view.names or {}
  local alive_n, ghost_n, dead_n = 0, 0, 0
  for pid, p in pairs(view.players) do
    local status, detail
    if p.alive then
      status = "lebend"
      alive_n = alive_n + 1
      local maxhp = client_max_hp(p)
      detail = maxhp > 0
        and math.floor((p.hp or 0) / maxhp * 100 + 0.5) or nil
    elseif p.ghost then
      status = "geist"
      ghost_n = ghost_n + 1
    else
      status = "tot"
      dead_n = dead_n + 1
      detail = p.dead_rest -- Restsekunden bis zur Freigabe (GDD 11)
    end
    rows[#rows + 1] = { pid = pid, name = names[pid] or ("#" .. pid),
                        class = p.class, leeroy = p.is_leeroy,
                        status = status, detail = detail }
  end
  local ORD = { lebend = 1, geist = 2, tot = 3 }
  table.sort(rows, function(a, b)
    if ORD[a.status] ~= ORD[b.status] then return ORD[a.status] < ORD[b.status] end
    return a.name:lower() < b.name:lower()
  end)
  return rows, alive_n, ghost_n, dead_n
end

-- Das Overlay selbst: sichtbar, solange STRG gehalten wird (main fragt die
-- Taste ab). Reine Anzeige — es blockiert keinerlei Eingaben.
function R:draw_raid_overview(view, w, h)
  local rows, alive_n, ghost_n, dead_n = R.raid_rows(view)
  if #rows == 0 then return end
  local PER_COL, ROW_H, COL_W = 14, 20, 236
  local cols = math.max(1, math.ceil(#rows / PER_COL))
  local pw = cols * COL_W + 24
  local ph = 66 + math.min(#rows, PER_COL) * ROW_H + 12
  local px0 = (w - pw) / 2
  local py0 = math.max(36, (h - ph) / 2)
  love.graphics.setColor(0.07, 0.07, 0.11, 0.93)
  love.graphics.rectangle("fill", px0, py0, pw, ph, 6, 6)
  love.graphics.setColor(0.78, 0.63, 0.28, 1)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", px0, py0, pw, ph, 6, 6)
  love.graphics.setLineWidth(1)
  local font = love.graphics.getFont()
  love.graphics.setColor(0.95, 0.85, 0.4, 1)
  love.graphics.print("Schlachtzug", px0 + 12, py0 + 8, 0, 1.4, 1.4)
  -- Zusammenfassung in eigener Zeile — kollidiert so nie mit dem Titel
  local summary = string.format("%d lebend   %d Geister   %d tot",
    alive_n, ghost_n, dead_n)
  love.graphics.setColor(0.75, 0.72, 0.62, 1)
  love.graphics.print(summary, px0 + 12, py0 + 32)
  for i, r in ipairs(rows) do
    local col = math.floor((i - 1) / PER_COL)
    local x = px0 + 12 + col * COL_W
    local y = py0 + 58 + ((i - 1) % PER_COL) * ROW_H
    -- Klassenicon (oder grauer Kreis vor der ersten Wiederbelebung)
    if r.class and CLASS_ICON[r.class] then
      local icon = CLASS_ICON[r.class]
      assets.draw(icon, x + 8, y + 8, 16 / assets.size(icon),
        r.status == "lebend" and 1 or 0.45)
    else
      love.graphics.setColor(0.35, 0.35, 0.35, 0.8)
      love.graphics.circle("fill", x + 8, y + 8, 7)
    end
    -- Name: Klassenfarbe lebend, gedimmt sonst; Leeroy in Gold
    local col_name = r.leeroy and { 0.95, 0.78, 0.2 }
      or (r.class and CLASS_COL[r.class]) or { 0.8, 0.8, 0.75 }
    local dim = (r.status == "lebend") and 1 or 0.55
    love.graphics.setColor(col_name[1] * dim, col_name[2] * dim, col_name[3] * dim, 1)
    love.graphics.print(r.name, x + 20, y)
    -- Status rechtsbuendig: HP-Prozent / Geist / tot (Restsekunden)
    local txt, tc
    if r.status == "lebend" then
      txt = (r.detail or 0) .. "%"
      tc = (r.detail or 0) <= 35 and { 0.9, 0.35, 0.3 } or { 0.55, 0.8, 0.55 }
    elseif r.status == "geist" then
      txt, tc = "Geist", { 0.55, 0.65, 0.9 }
    else
      txt = (r.detail and r.detail > 0) and ("tot " .. r.detail .. "s") or "tot"
      tc = { 0.6, 0.56, 0.45 }
    end
    love.graphics.setColor(tc[1], tc[2], tc[3], 1)
    love.graphics.print(txt, x + COL_W - 16 - font:getWidth(txt), y)
  end
end

-- Heil-Leiste (Runde 7, #103, GDD 4.3): AutoHeal-Stil — nur fuer
-- Heilerklassen sichtbar, zeigt sich selbst plus alle lebenden Verbuendeten
-- in Heil-Reichweite; Rechtsklick auf eine Zeile heilt diesen Spieler
-- (HEAL_REQUEST), Linksklick waehlt ihn als Ziel. Layout/Builder/Hit-Test
-- sind love-frei (Muster raid_rows).
R.HEALBAR = { x = 12, y = 142, w = 190, header_h = 18, row_h = 18,
              max_rows = 24 }

-- Zeilen: selbst IMMER zuerst, danach alphabetisch nach Namen — STABIL,
-- eine HP-Sortierung liesse die Zeilen unter dem Cursor springen (genau
-- der Fehler, den die Leiste behebt). Geister/Tote sind unheilbar: raus.
function R.heal_rows(view, heal_range, max_rows)
  local rows, more_n = {}, 0
  local names = view.names or {}
  local me = view.players[view.me]
  if not (me and me.alive) then return rows, 0 end
  local function pct(p)
    local maxhp = client_max_hp(p)
    return maxhp > 0 and math.floor((p.hp or 0) / maxhp * 100 + 0.5) or 0
  end
  rows[1] = { pid = view.me, name = names[view.me] or ("#" .. tostring(view.me)),
              class = me.class, hp_pct = pct(me), is_self = true }
  local others = {}
  for pid, p in pairs(view.players) do
    if pid ~= view.me and p.alive
       and world.dist(view.me_x or 0, view.me_y or 0, p.x, p.y) <= heal_range then
      others[#others + 1] = { pid = pid,
                              name = names[pid] or ("#" .. tostring(pid)),
                              class = p.class, hp_pct = pct(p), is_self = false }
    end
  end
  table.sort(others, function(a, b)
    local al, bl = a.name:lower(), b.name:lower()
    if al ~= bl then return al < bl end
    return a.pid < b.pid -- Namensgleichstand: pid entscheidet, stabil
  end)
  max_rows = max_rows or R.HEALBAR.max_rows
  for _, r in ipairs(others) do
    if #rows < max_rows then rows[#rows + 1] = r else more_n = more_n + 1 end
  end
  return rows, more_n
end

-- Reine Arithmetik: welche Zeile liegt unter (mx, my)? nil = keine.
-- hb: optionales Layout (Dock-Variante, M12); Default = R.HEALBAR.
function R.healbar_row_at(n_rows, mx, my, hb)
  local HB = hb or R.HEALBAR
  if mx < HB.x or mx > HB.x + HB.w then return nil end
  local i = math.floor((my - (HB.y + HB.header_h)) / HB.row_h) + 1
  if i >= 1 and i <= n_rows then return i end
  return nil
end

-- M12: eine Layout-Wahrheit fuer die gesamte Minimap-Moeblierung — Renderer
-- (R:draw) und Maus-Hit-Tests (main.lua) rechnen mit DENSELBEN Zahlen.
-- Love-frei (reine Arithmetik, Stufe-1-getestet in tests/unit_layout.lua).
-- Alle Koordinaten sind UNgeshakt: die Moeblierung steht fest, nur der
-- Weltinhalt (make_transform) wackelt beim Screenshake.
-- docked (Runde 7, Vorschau hinter Flag): Einheiten-/Zielfenster tangential
-- an 10-/2-Uhr an den Ring statt in die Ecken; alles Abgeleitete (CP,
-- Kupfer, Hinweis, Heil-Leiste, Ziel-des-Ziels, Buffs) wandert mit.
R.FRAME_W, R.FRAME_H = 214, 56

function R.layout(w, h, docked)
  local ox, oy = w / 2, h / 2
  local radius = h / 2 - 22 -- war -8; Platz fuer Plaketten AUF dem Ring (M12)
  local unit, target
  if docked then
    local p10x, p10y = ox - radius * 0.866, oy - radius * 0.5
    local p2x = ox + radius * 0.866
    unit = { x = math.max(12, math.floor(p10x - R.FRAME_W + 8)),
             y = math.max(10, math.floor(p10y - R.FRAME_H + 8)) }
    target = { x = math.min(w - 226, math.floor(p2x - 8)), y = unit.y }
  else
    unit = { x = 12, y = 10 }
    target = { x = w - 226, y = 10 }
  end
  local HB = R.HEALBAR
  -- Eigene Auren sitzen seit M13 UNTER der eigenen Tafel (Runde 8, #107) —
  -- Kupfer/Hinweis/Heil-Leiste ruecken dafuer 34 px nach unten.
  local healbar_y = unit.y + 132
  -- Klemme: die Heil-Leiste (plus "+K weitere"-Zeile) darf nie unten aus dem
  -- Fenster laufen (Dock bei h=720 waere sonst 733 px tief)
  local max_rows = math.max(4, math.min(HB.max_rows,
    math.floor((h - healbar_y - HB.header_h - 8) / HB.row_h) - 1))
  return {
    ox = ox, oy = oy, radius = radius,
    ring_r = radius * 0.87, -- Bahn der Faehigkeits-Buttons
    banner = { cx = ox, cy = oy - radius, h = 26, pad = 14, min_w = 140 },
    npip = { x = ox, y = oy - radius + 26, r = 9 },
    clock = { cx = ox, cy = oy + radius, w = 96, h = 34 },
    zoom = { x = ox + radius * 0.86, y = oy + radius * 0.42,
             r = 14, spacing = 34 },
    frames = {
      unit = unit,
      target = target,
      cp = { x = unit.x + 220, y = unit.y + 4 },
      buffs_self = { x = unit.x, y = unit.y + 60 },
      money = { x = unit.x + 2, y = unit.y + 94 },
      hint = { x = unit.x + 2, y = unit.y + 112 },
      healbar = { x = unit.x, y = healbar_y, w = HB.w,
                  header_h = HB.header_h, row_h = HB.row_h,
                  max_rows = max_rows },
      tot = { x = target.x, y = target.y + 60 },
      buffs = { x = target.x, y = target.y + 86 },
    },
  }
end

-- Hogger-Tracker (Runde 8, #108): liegt ein Ziel ausserhalb des sichtbaren
-- Kreises (Weltdistanz > Zoom-Radius), liefert edge_pos den Punkt am
-- Innenrand des Rings in seiner Richtung — sonst nil. Reine Arithmetik,
-- love-frei, Stufe-1-getestet.
function R.edge_pos(me_x, me_y, tx, ty, zr, L)
  if world.dist(me_x, me_y, tx, ty) <= zr then return nil end
  local ang = math.atan2(ty - me_y, tx - me_x)
  return L.ox + math.cos(ang) * (L.radius - 18),
         L.oy + math.sin(ang) * (L.radius - 18)
end

-- Deterministischer Zellen-Hash fuer Aussen-Mottle und Gras-Flecken (M12):
-- reine Integer-Arithmetik, KEIN math.random — frame-stabil, love-frei.
function R.cellhash(x, y)
  -- Zwischenwerte bleiben unter 2^53 (exakte Double-Arithmetik)
  local n = (x * 374761 + y * 668265) % 2147483647
  return (n * 48271) % 2147483647
end

function R:draw_healbar(view, hb)
  local me = view.players[view.me]
  if not (me and me.alive and me.class and ALLY_SLOT[me.class]) then return end
  local HB = hb or R.HEALBAR
  -- max_rows aus dem Layout (M13-Klemme gegen die Fensterhoehe)
  local rows, more_n = R.heal_rows(view, model.p("heal_range"), HB.max_rows)
  if #rows == 0 then return end
  local extra = more_n > 0 and 1 or 0
  local ph = HB.header_h + (#rows + extra) * HB.row_h + 8
  love.graphics.setColor(0.07, 0.07, 0.11, 0.85)
  love.graphics.rectangle("fill", HB.x, HB.y, HB.w, ph, 5, 5)
  love.graphics.setColor(0.78, 0.63, 0.28, 0.9)
  love.graphics.rectangle("line", HB.x, HB.y, HB.w, ph, 5, 5)
  love.graphics.setColor(0.95, 0.85, 0.4, 1)
  love.graphics.print("Heilziele  (Rechtsklick heilt)", HB.x + 8, HB.y + 3)
  local font = love.graphics.getFont()
  for i, r in ipairs(rows) do
    local y = HB.y + HB.header_h + (i - 1) * HB.row_h + 1
    if r.class and CLASS_ICON[r.class] then
      local icon = CLASS_ICON[r.class]
      assets.draw(icon, HB.x + 12, y + 8, 14 / assets.size(icon))
    end
    local col = (r.class and CLASS_COL[r.class]) or { 0.8, 0.8, 0.75 }
    love.graphics.setColor(col[1], col[2], col[3], 1)
    love.graphics.print(r.is_self and (r.name .. " (du)") or r.name,
      HB.x + 22, y)
    local txt = (r.hp_pct or 0) .. "%"
    if (r.hp_pct or 0) <= 35 then love.graphics.setColor(0.9, 0.35, 0.3, 1)
    else love.graphics.setColor(0.55, 0.8, 0.55, 1) end
    love.graphics.print(txt, HB.x + HB.w - 8 - font:getWidth(txt), y)
  end
  if more_n > 0 then
    love.graphics.setColor(0.6, 0.56, 0.45, 1)
    love.graphics.print("+" .. more_n .. " weitere in Reichweite",
      HB.x + 22, HB.y + HB.header_h + #rows * HB.row_h + 1)
  end
end

function R:zoom_radius()
  return model.p("zoom_radius_" .. self.zoom)
end

function R:set_zoom(level)
  self.zoom = math.max(1, math.min(3, level))
end

function R:announce(text, dur)
  self.banner_text = text
  self.banner_t = dur or 3
end

-- Sprechblase am Icon des Echos (Endsequenz, GDD 11 / #132). Der Monolog
-- laeuft zusaetzlich als Einblendung — Rob will beides.
R.BUBBLE_WRAP = 260 -- Textbreite; darunter wird der laengste Satz vierzeilig
R.BUBBLE_PAD = 10
-- anchor: nil = Echo (Monolog der Endsequenz), "leeroy" = der rennende
-- Raid-Leeroy (DER Schrei, Runde 12 #144 — er schreit, nicht das Echo)
function R:bubble(text, dur, anchor)
  self.bubble_text = text
  self.bubble_t = dur or 3
  self.bubble_anchor = anchor
end

function R:add_shake(amount)
  self.shake = math.max(self.shake, amount)
end

function R:update(dt)
  if self.banner_t > 0 then self.banner_t = self.banner_t - dt end
  if (self.bubble_t or 0) > 0 then self.bubble_t = self.bubble_t - dt end
  if self.killcam_t > 0 then self.killcam_t = self.killcam_t - dt end
  if self.shake > 0 then self.shake = math.max(0, self.shake - dt * 30) end
  for i = #self.toasts, 1, -1 do
    self.toasts[i].t = self.toasts[i].t - dt
    if self.toasts[i].t <= 0 then table.remove(self.toasts, i) end
  end
  for i = #self.effects, 1, -1 do
    self.effects[i].t = self.effects[i].t - dt
    if self.effects[i].t <= 0 then table.remove(self.effects, i) end
  end
  if self.fx then
    for i = #self.fx, 1, -1 do
      self.fx[i].t = self.fx[i].t - dt
      if self.fx[i].t <= 0 then table.remove(self.fx, i) end
    end
  end
  if self.hurt and self.hurt > 0 then
    self.hurt = math.max(0, self.hurt - dt * 2.2)
  end
  if (self.err_t or 0) > 0 then self.err_t = self.err_t - dt end
end

-- Geschosse, Schlagboegen, Einschlaege (GDD 4.1) — zwischen Entitaeten und
-- Floating Text gezeichnet
function R:draw_fx(to_screen, scale)
  if not self.fx then return end
  for _, f in ipairs(self.fx) do
    local k = 1 - f.t / f.total          -- 0 = Start, 1 = Ende
    local c = f.col
    local sx, sy = to_screen(f.sx, f.sy)
    local tx, ty = to_screen(f.tx, f.ty)
    if f.form == "bolt" or f.form == "arrow" then
      -- Flugphase in der ersten Haelfte, danach Einschlag am Ziel
      local fly = math.min(1, k * 2)
      local x, y = sx + (tx - sx) * fly, sy + (ty - sy) * fly
      love.graphics.setColor(c[1], c[2], c[3], 1)
      if f.form == "arrow" then
        local dx, dy = tx - sx, ty - sy
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        local ux, uy = dx / len * 14, dy / len * 14
        love.graphics.setLineWidth(2)
        love.graphics.line(x - ux, y - uy, x, y)
        love.graphics.setLineWidth(1)
      else
        love.graphics.circle("fill", x, y, 5)
        love.graphics.setColor(c[1], c[2], c[3], 0.35)
        love.graphics.circle("fill", x, y, 9)
      end
      if k > 0.5 then
        love.graphics.setColor(c[1], c[2], c[3], (1 - k) * 2)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", tx, ty, 8 + (k - 0.5) * 40)
        love.graphics.setLineWidth(1)
      end
    elseif f.form == "slash" or f.form == "charge" then
      -- kurzer Schlagbogen quer zur Angriffsrichtung am Ziel
      local a = math.atan2(ty - sy, tx - sx)
      local r = (f.form == "charge") and 26 or 18
      love.graphics.setColor(c[1], c[2], c[3], 1 - k)
      love.graphics.setLineWidth(f.form == "charge" and 4 or 3)
      love.graphics.arc("line", "open", tx, ty, r + k * 6,
        a - 2.2, a - 0.9)
      love.graphics.arc("line", "open", tx, ty, r + k * 6,
        a + 0.9, a + 2.2)
      love.graphics.setLineWidth(1)
    elseif f.form == "heal" then
      love.graphics.setColor(c[1], c[2], c[3], 1 - k)
      love.graphics.setLineWidth(2)
      love.graphics.circle("line", tx, ty - k * 18, 10 * (1 - k * 0.5))
      love.graphics.setLineWidth(1)
    end
  end
end

-- Welt -> Bildschirm um (cx, cy) zentriert
function R:make_transform(cx, cy)
  local w, h = love.graphics.getDimensions()
  local radius = h / 2 - 22 -- EINE Wahrheit mit R.layout (M12)
  local scale = radius / self:zoom_radius()
  local ox, oy = w / 2, h / 2
  if self.shake > 0 then
    ox = ox + (love.math.random() - 0.5) * self.shake
    oy = oy + (love.math.random() - 0.5) * self.shake
  end
  return function(wx, wy)
    return ox + (wx - cx) * scale, oy + (wy - cy) * scale
  end, scale, ox, oy, radius
end

local function hp_bar(x, y, w2, frac, r, g, b)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x - w2, y, w2 * 2, 4)
  love.graphics.setColor(r, g, b, 1)
  love.graphics.rectangle("fill", x - w2, y, w2 * 2 * math.max(0, math.min(1, frac)), 4)
end

-- Tooltip im Original-Stil (GDD 4.2/4.3): erste Zeile gold (Name), Rest
-- hell. Eine Wahrheit fuer Renderer und F10-Panel (Runde 9, #119).
local draw_tooltip = require("game.ui.tooltip").draw

-- Plakette im Original-Minimap-Stil (M12, GDD 4.1/4.2): dunkle Fuellung,
-- Goldrahmen, helle Innenlinie — fuer Zonenbanner und Uhr
local function plaque(x, y, pw, ph)
  love.graphics.setColor(0.07, 0.06, 0.05, 0.95)
  love.graphics.rectangle("fill", x, y, pw, ph, 4, 4)
  love.graphics.setColor(0.78, 0.63, 0.28, 1)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, pw, ph, 4, 4)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.95, 0.85, 0.55, 0.5)
  love.graphics.rectangle("line", x + 2, y + 2, pw - 4, ph - 4, 3, 3)
end

-- Auren-Kacheln (GDD 4.3, Runde 8 #107): aura_list baut die Liste aus einem
-- beliebigen Snapshot-Spielereintrag (die Flags stehen fuer JEDEN Spieler im
-- Snapshot, nicht nur fuer me); draw_auras zeichnet sie an einen Anker und
-- liefert ggf. den Hover-Tooltip zurueck.
local function aura_list(p)
  local auras = {}
  if p.shout then auras[#auras + 1] = { AURA.shout, p.shout_rest } end
  if p.seal then auras[#auras + 1] = { AURA.seal } end
  if p.frost_armor then auras[#auras + 1] = { AURA.frost } end
  if p.stealth then auras[#auras + 1] = { AURA.stealth } end
  if p.shielded then auras[#auras + 1] = { AURA.pws } end
  if p.pact then auras[#auras + 1] = { AURA.pact } end
  if p.weak_soul and not p.shielded then
    auras[#auras + 1] = { AURA.weak_soul } -- erst sichtbar, wenn der Schild weg ist
  end
  if p.bleeding then auras[#auras + 1] = { AURA.bleed } end
  return auras
end

local function draw_auras(auras, ax, ay, ui)
  local tip = nil
  for i, a in ipairs(auras) do
    local def, rest = a[1], a[2]
    local bx, by = ax + (i - 1) * 34, ay
    if def.debuff then
      love.graphics.setColor(0.32, 0.10, 0.10, 0.95)
    else
      love.graphics.setColor(0.2, 0.25, 0.4, 0.9)
    end
    love.graphics.rectangle("fill", bx, by, 30, 30, 3, 3)
    love.graphics.setColor(def.debuff and 0.85 or 0.45,
      def.debuff and 0.25 or 0.42, def.debuff and 0.2 or 0.6, 1)
    love.graphics.rectangle("line", bx, by, 30, 30, 3, 3)
    love.graphics.setColor(0.9, 0.9, 0.95, 1)
    love.graphics.print(def.kuerzel, bx + 6, by + 2)
    if rest and rest > 0 then
      love.graphics.print(tostring(rest), bx + 8, by + 15)
    end
    if ui.mouse and ui.mouse[1] >= bx and ui.mouse[1] <= bx + 30
       and ui.mouse[2] >= by and ui.mouse[2] <= by + 30 then
      local lines = { def.name }
      for _, l in ipairs(def.text()) do lines[#lines + 1] = l end
      if rest and rest > 0 then
        lines[#lines + 1] = string.format("Noch %d s", rest)
      end
      tip = { lines = lines }
    end
  end
  return tip
end

-- Balken der Eckfenster: links oben verankert, Beschriftung liegt IM Balken
-- (Original-Vorbild spieleranzeige_und_ziel.png) — nie mehr quer durch die
-- Zahlen wie zuvor (Issue #25)
local function ui_bar(x, y, w, h, frac, col, text)
  love.graphics.setColor(0.02, 0.02, 0.02, 0.9)
  love.graphics.rectangle("fill", x - 1, y - 1, w + 2, h + 2, 2, 2)
  love.graphics.setColor(0.12, 0.12, 0.12, 1)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(col[1], col[2], col[3], 1)
  love.graphics.rectangle("fill", x, y, w * math.max(0, math.min(1, frac or 0)), h)
  if text then
    local font = love.graphics.getFont()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(text, x + w / 2 - font:getWidth(text) / 2,
      y + h / 2 - font:getHeight() / 2)
  end
end

-- view: dekodierter Snapshot + me/me_x/me_y; ui: { facing_angle, cooldowns }
function R:draw(view, ui)
  local w, h = love.graphics.getDimensions()
  -- Die Layout-Wahrheit fuer die gesamte Moeblierung (M12): UNgeshakt,
  -- identisch zu den Hit-Tests in main.lua
  local L = R.layout(w, h, self.docked)
  love.graphics.setColor(UI_BG[1], UI_BG[2], UI_BG[3], 1)
  love.graphics.rectangle("fill", 0, 0, w, h)

  -- Aussenbereich: dunkles Mottle statt Flat (M12) — statisches 64-px-Raster,
  -- deterministisch aus cellhash, Zellen innerhalb des Kreises uebersprungen.
  -- Bewusst simple Direkt-Calls (~200 Kreise); falls je messbar: in einen
  -- Canvas backen (Rebuild bei Groessenwechsel).
  do
    local cell = 64
    for gx0 = 0, math.ceil(w / cell) do
      for gy0 = 0, math.ceil(h / cell) do
        local cx = gx0 * cell + cell / 2
        local cy = gy0 * cell + cell / 2
        local dx, dy = cx - L.ox, cy - L.oy
        if dx * dx + dy * dy > (L.radius + 40) ^ 2 then
          local hsh = R.cellhash(gx0, gy0)
          local jx = (hsh % 33) - 16
          local jy = (math.floor(hsh / 33) % 33) - 16
          love.graphics.setColor(0, 0, 0, 0.05 + (hsh % 8) * 0.01)
          love.graphics.circle("fill", cx + jx, cy + jy, 22 + hsh % 12)
        end
      end
    end
  end

  local me = view.players[view.me]
  local to_screen, scale, ox, oy, radius = self:make_transform(view.me_x, view.me_y)

  -- Kreis-Stencil: die Minimap — auf UNgeshakten L-Koordinaten, damit die
  -- Kartenkante beim Screenshake nicht unter dem festen Ring hervorblitzt
  love.graphics.stencil(function()
    love.graphics.circle("fill", L.ox, L.oy, L.radius)
  end, "replace", 1)
  love.graphics.setStencilTest("greater", 0)

  -- Boden
  love.graphics.setColor(GRASS[1], GRASS[2], GRASS[3], 1)
  love.graphics.rectangle("fill", 0, 0, w, h)
  -- Gras-Textur (M12): deterministische Farbflecken auf einem 90-px-
  -- WELTraster — scrollt und zoomt mit, flackert nie (cellhash statt random)
  do
    local cell = 90
    local zr = self:zoom_radius()
    local x0 = math.floor((view.me_x - zr) / cell)
    local x1 = math.ceil((view.me_x + zr) / cell)
    local y0 = math.floor((view.me_y - zr) / cell)
    local y1 = math.ceil((view.me_y + zr) / cell)
    for cx0 = x0, x1 do
      for cy0 = y0, y1 do
        local hsh = R.cellhash(cx0, cy0)
        if hsh % 7 < 3 then
          local jx = (hsh % 41) - 20
          local jy = (math.floor(hsh / 41) % 41) - 20
          local px, py = to_screen(cx0 * cell + jx, cy0 * cell + jy)
          local d = (hsh % 2 == 0) and 0.025 or -0.03
          love.graphics.setColor(GRASS[1] + d, GRASS[2] + d, GRASS[3] + d,
            0.4 + (hsh % 3) * 0.05)
          love.graphics.circle("fill", px, py, (30 + hsh % 18) * scale)
        end
      end
    end
  end
  -- Pfad Friedhof -> Huegel: drei Paesse = weiche Kanten (M12)
  local g = map.graveyard()
  local gx, gy = to_screen(g.x, g.y)
  local hx2, hy2 = to_screen(map.hill.x, map.hill.y)
  love.graphics.setColor((GRASS[1] + PATH[1]) / 2, (GRASS[2] + PATH[2]) / 2,
    (GRASS[3] + PATH[3]) / 2, 0.55)
  love.graphics.setLineWidth(34 * scale)
  love.graphics.line(gx, gy, hx2, hy2)
  love.graphics.setColor(PATH[1], PATH[2], PATH[3], 1)
  love.graphics.setLineWidth(26 * scale)
  love.graphics.line(gx, gy, hx2, hy2)
  love.graphics.setColor(PATH[1] + 0.05, PATH[2] + 0.04, PATH[3] + 0.03, 0.6)
  love.graphics.setLineWidth(12 * scale)
  love.graphics.line(gx, gy, hx2, hy2)
  love.graphics.setLineWidth(1)
  -- Huegel-Plateau mit weichem Rand (M12)
  love.graphics.setColor(0.36, 0.33, 0.24, 0.35)
  love.graphics.circle("fill", hx2, hy2, 158 * scale)
  love.graphics.setColor(0.36, 0.33, 0.24, 1)
  love.graphics.circle("fill", hx2, hy2, 150 * scale)

  -- Friedhof von Elwynn (GDD 7.1): Erdfleck, Zaunpfosten rund um die
  -- unantastbare Zone, Grabsteine, Geistheiler — vorher war hier Wiese
  do
    local r = map.GRAVEYARD_RADIUS * scale
    love.graphics.setColor(0.26, 0.29, 0.22, 1)
    love.graphics.circle("fill", gx, gy, r)
    love.graphics.setColor(0.22, 0.19, 0.15, 0.95)
    local posts = 28
    local pw = math.max(1.5, 3 * scale)
    for i = 0, posts - 1 do
      local a = i * (2 * math.pi / posts)
      local x1, y1 = gx + math.cos(a) * r, gy + math.sin(a) * r
      love.graphics.setLineWidth(pw)
      love.graphics.line(x1, y1, gx + math.cos(a) * (r - 14 * scale),
        gy + math.sin(a) * (r - 14 * scale))
      -- Querlatte zum naechsten Pfosten
      local a2 = (i + 1) * (2 * math.pi / posts)
      love.graphics.setLineWidth(math.max(1, 1.5 * scale))
      love.graphics.line(x1, y1 - 6 * scale,
        gx + math.cos(a2) * r, gy + math.sin(a2) * r - 6 * scale)
    end
    love.graphics.setLineWidth(1)
    for _, s in ipairs(map.gravestones()) do
      local x, y = to_screen(s.x, s.y)
      assets.draw("icon_gravestone", x, y, scale * 1.6)
    end
    local sh = map.spirit_healer()
    local shx, shy = to_screen(sh.x, sh.y)
    -- leichtes Pulsieren: Engel-Icon, funktionslose Szenerie (GDD 7.1)
    local puls = 0.75 + 0.25 * math.sin(love.timer.getTime() * 1.5)
    love.graphics.setColor(0.7, 0.85, 1.0, 0.25 * puls)
    love.graphics.circle("fill", shx, shy, 26 * scale)
    assets.draw("icon_spirit_healer", shx, shy, scale * 1.6, 0.9)
  end

  -- Baeume, Deko-Schaedel (unterste Ebenen der Hierarchie, GDD 4.1)
  for _, t in ipairs(map.trees()) do
    local x, y = to_screen(t.x, t.y)
    assets.draw("icon_tree", x, y, scale * 2.2)
  end
  for _, s in ipairs(map.deco_skulls()) do
    local x, y = to_screen(s.x, s.y)
    assets.draw("icon_deco_skull", x, y, scale * 1.6, 0.8)
  end

  -- mechanische Leichen
  for _, c in ipairs(view.corpses) do
    local x, y = to_screen(c.x, c.y)
    assets.draw("icon_corpse", x, y, scale * 2)
  end

  -- Klassen-Bodenicons: nur im Geist-Zustand sichtbar (GDD 4.1)
  if me and me.ghost then
    for slot = 1, #world.CLASSES do
      local ix, iy = world.class_icon_pos(slot)
      local x, y = to_screen(ix, iy)
      assets.draw(FLOOR_ICON[slot], x, y, scale * 2.5)
    end
  end

  -- Das Echo von Leeroy Jenkins (GDD 10.1): blasses Paladin-Icon, gruener
  -- Name, goldenes Ausrufezeichen solange es eine Quest zu vergeben hat
  -- (Referenz questgeber-ausrufezeichen.jpg)
  -- nur Geister sehen es (Issue #63), wie die Klassen-Bodenicons (GDD 4.1).
  -- Ausnahme seit Runde 11 (#132): in der Endsequenz sehen es ALLE — es ist
  -- seine eigene Schlussszene, und nach dem Teleport lebt jeder. Ab Stufe 4
  -- ist es weg (die verschmolzene Figur hat sich ausgeloggt).
  local won = view.won_stage or 0
  if view.echo and me and (me.ghost or (won > 0 and won < 4)) then
    local ex, ey = to_screen(view.echo.x, view.echo.y)
    local me_quest = me and (me.quest or 2) or 2
    local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 3)
    love.graphics.setColor(0.75, 0.85, 1.0, 0.18 * pulse)
    love.graphics.circle("fill", ex, ey, 26 * scale)
    assets.draw("icon_paladin", ex, ey, scale * 1.9, 0.55)
    love.graphics.setColor(0.72, 0.86, 0.55, 0.95) -- freundlicher NPC: gruen
    local font = love.graphics.getFont()
    -- Mit der Verschmelzung heilt der Name: aus dem doppelten wird wieder
    -- der eine (GDD 11) — die Wunde, die der Fluch geschlagen hat, schliesst
    -- sich vor den Augen der Runde.
    local nm = names.echo_name(won)
    love.graphics.print(nm, ex - font:getWidth(nm) / 2, ey + 18 * scale)
    if me_quest < 2 then
      -- das Ausrufezeichen: goldener Balken plus Punkt, leicht schwebend
      local bob = math.sin(love.timer.getTime() * 2.5) * 3
      local y0 = ey - 34 * scale + bob
      love.graphics.setColor(0.98, 0.80, 0.15, 1)
      love.graphics.rectangle("fill", ex - 3, y0 - 20, 6, 15, 2, 2)
      love.graphics.circle("fill", ex, y0 - 1, 3.4)
      love.graphics.setColor(0.35, 0.25, 0.05, 0.9)
      love.graphics.rectangle("line", ex - 3, y0 - 20, 6, 15, 2, 2)
    end
  end

  -- Hoggers Icon UNTER den Spielern (Runde 7): das 113-px-Icon verdeckte
  -- sonst den Nahkampf-Klumpen; Balken, Fresskanal-Text, Charge-Telegraph
  -- und seit Runde 13 (#154) der Boss-Ring bleiben weiter oben (GDD 4.1)
  local hg = view.hogger
  if hg.state ~= "reset" then
    local x, y = to_screen(hg.x, hg.y)
    -- Nach dem Fluchbruch bleibt er als erloschenes Icon liegen (#132):
    -- der Kreis, in dem alle stehen, braucht seine Mitte
    assets.draw("icon_hogger", x, y, scale * 2, (hg.hp or 0) > 0 and 1 or 0.4)
  end

  -- Geister zuerst (gedimmt), dann Lebende (GDD 4.1)
  local draw_pids = R.sorted_pids(view.players)
  for pass = 1, 2 do
    for _, pid in ipairs(draw_pids) do
      local p = view.players[pid]
      -- Ab der Verschmelzung ist Leeroys Koerper im Echo aufgegangen (#132):
      -- zwei Icons uebereinander wuerden die Pointe zerstoeren
      local merged = p.is_leeroy and won >= 3
      if pid ~= view.me and not merged then
        local is_ghost_pass = pass == 1
        if (p.ghost and is_ghost_pass) or (p.alive and not is_ghost_pass) then
          local x, y = to_screen(p.x, p.y)
          local icon = CLASS_ICON[p.class]
          local jump = p.jumping and 1.25 or 1
          local alpha = p.ghost and 0.35 or p.stealth and 0.4 or 1
          if icon then
            if p.feigning then
              -- Totstellen (Runde 13, #157): das Icon liegt flach auf der
              -- Seite und ist blass — "liegt einfach da"
              love.graphics.push()
              love.graphics.translate(x, y)
              love.graphics.rotate(math.pi / 2)
              love.graphics.translate(-x, -y)
              assets.draw(icon, x, y, scale * 1.8, 0.55)
              love.graphics.pop()
            else
              assets.draw(icon, x, y - (p.jumping and 4 or 0),
                scale * 1.8 * jump, alpha)
            end
            if p.is_leeroy then -- markiertes Paladin-Icon (GDD 4.1)
              love.graphics.setColor(0.95, 0.78, 0.2, alpha)
              love.graphics.setLineWidth(2)
              love.graphics.circle("line", x, y, 34 * scale)
              love.graphics.setLineWidth(1)
              love.graphics.print("Leeroy", x - 20, y + 16)
            end
          else
            love.graphics.setColor(0.7, 0.8, 1.0, 0.35)
            love.graphics.circle("fill", x, y, 8 * scale * 1.8)
          end
          if p.alive and p.class then
            hp_bar(x, y + 14, 16, p.hp / client_max_hp(p), 0.2, 0.8, 0.2)
          end
        end
      end
    end
  end

  -- Boss-Ring (Runde 13, #154): Hoggers Icon liegt seit Runde 7 UNTER den
  -- Spielern — der goldene Umriss liegt OBEN und haelt Position und
  -- Ausdehnung im Klumpen immer lesbar, ohne einen Nahkaempfer zu
  -- verdecken. Sein Radius (Manifest 48 x scale) ist zugleich die
  -- Rechtsklick-Flaeche (R.pick_target). Im Fresskanal pulsiert er im
  -- Takt des "Schurke: TRITT!"-Texts; nach dem Fluchbruch bleibt er
  -- gedimmt als Mitte des Schlusskreises liegen.
  if hg.state ~= "reset" then
    local x, y = to_screen(hg.x, hg.y)
    local a = (hg.hp or 0) > 0 and 0.9 or 0.35
    if hg.eat and hg.eat.phase == "channel" then
      a = 0.55 + 0.4 * math.sin(love.timer.getTime() * 6)
    end
    love.graphics.setColor(0.78, 0.63, 0.28, a)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", x, y, 48 * scale)
    love.graphics.setLineWidth(1)
  end

  -- Fluss-Linie am Suedrand (GDD 7.1)
  do
    local _, ry = to_screen(0, map.RIVER_Y)
    love.graphics.setColor(0.25, 0.45, 0.65, 0.8)
    love.graphics.setLineWidth(10 * scale)
    love.graphics.line(0, ry, w, ry)
    love.graphics.setLineWidth(1)
  end

  -- Bodenbeute
  if view.loot then
    for _, l in pairs(view.loot) do
      local x, y = to_screen(l.x, l.y)
      assets.draw("icon_loot", x, y, scale * 1.6)
    end
  end

  -- NPCs: Wichtel, Gnoll-Welpen, Ambient-Mobs (mit Mini-HP-Balken)
  if view.npcs then
    for _, npc in pairs(view.npcs) do
      local x, y = to_screen(npc.x, npc.y)
      if npc.kind == "imp" and model.p("warlock_pact_enabled") >= 1 then
        -- Blutpakt-Aura (Runde 13, #159): dezenter Schein um den Wichtel
        love.graphics.setColor(0.75, 0.35, 0.85, 0.06)
        love.graphics.circle("fill", x, y,
          model.p("warlock_pact_radius") * scale)
      end
      if npc.rooted then
        -- Gnarlwurzeln (Runde 13, #158): gruener Wurzelgriff um den Mob
        love.graphics.setColor(0.35, 0.75, 0.25, 0.8)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", x, y, 14 * scale)
        love.graphics.setLineWidth(1)
      end
      assets.draw("icon_" .. npc.kind, x, y, scale * 1.8)
      if npc.kind ~= "imp" then
        local maxhp = npc.kind == "add" and model.p("add_hp")
                      or model.p(npc.kind .. "_hp")
        hp_bar(x, y + 12, 10, npc.hp / maxhp, 0.85, 0.75, 0.2)
      end
    end
  end

  -- Hoggers Balken, Fresszaehler und Charge-Telegraph — bewusst NACH den
  -- Spielern, damit sie im Klumpen sichtbar bleiben; das Icon selbst liegt
  -- seit Runde 7 unter den Spielern (GDD 4.1)
  do
    local x, y = to_screen(hg.x, hg.y)
    -- Charge-Telegraph: blinkende Ziellinie (GDD 9.2)
    if hg.charge and view.players[hg.charge.target] then
      local t = view.players[hg.charge.target]
      local tx, ty = to_screen(t.x, t.y)
      local blink = (math.floor(love.timer.getTime() * 8) % 2 == 0) and 0.9 or 0.4
      love.graphics.setColor(1, 0.3, 0.2, blink)
      love.graphics.setLineWidth(3)
      love.graphics.line(x, y, tx, ty)
      love.graphics.setLineWidth(1)
    end
    if hg.state ~= "reset" then
      hp_bar(x, y + 20, 26, hg.hp / math.max(1, hg.max_hp), 0.85, 0.2, 0.15)
      -- Fresskanal: Pflicht-UI (GDD 9.2). Der alte Spieler-Zaehler ("2/4")
      -- fiel mit Runde 12 (#140) — unterbrechen kann nur noch der
      -- Schurken-Tritt, also sagt die Zeile genau das
      if hg.eat and hg.eat.phase == "channel" then
        love.graphics.setColor(1, 1, 1, 1)
        local hint = "Schurke: TRITT!"
        local font = love.graphics.getFont()
        love.graphics.print(hint, x - font:getWidth(hint) / 2,
          y - 34 * scale - 16)
        hp_bar(x, y + 26, 26, hg.eat.progress, 0.9, 0.8, 0.2)
      end
    end
  end

  -- DING-Inszenierung: goldene, sich weitende Ringe (GDD 7.3)
  for _, e in ipairs(self.effects) do
    local x, y = to_screen(e.x, e.y)
    local k = 1 - e.t / e.total
    love.graphics.setColor(1, 0.85, 0.25, 1 - k)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", x, y, 10 + k * 60)
    love.graphics.setLineWidth(1)
  end

  -- Geschosse und Schlaege (GDD 4.1, Issue #30)
  self:draw_fx(to_screen, scale)

  -- Eigener Pfeil exakt im Zentrum (GDD 4.1)
  do
    local a = ui.facing_angle or 0
    local size = 13
    love.graphics.push()
    love.graphics.translate(ox, oy - ((me and me.jumping) and 5 or 0))
    love.graphics.rotate(a)
    if me and (me.ghost or not me.alive) then
      love.graphics.setColor(0.55, 0.65, 0.95, 0.9) -- blass-blaeulich als Geist
    else
      love.graphics.setColor(0.95, 0.78, 0.2, 1)    -- golden
    end
    love.graphics.polygon("fill", 0, -size, size * 0.6, size, 0, size * 0.45,
      -size * 0.6, size)
    love.graphics.pop()
  end

  -- Vignette an der Innenkante (M12): sanfter Uebergang zum Ring
  for i, va in ipairs({ 0.14, 0.08, 0.04 }) do
    love.graphics.setColor(0, 0, 0, va)
    love.graphics.setLineWidth(8)
    love.graphics.circle("line", L.ox, L.oy, L.radius - 3 - (i - 1) * 7)
    love.graphics.setLineWidth(1)
  end

  love.graphics.setStencilTest()

  -- Totensicht: blaeulicher Entsaettigungsfilter als Zustand (GDD 4.1)
  if me and not me.alive then
    love.graphics.setColor(0.25, 0.35, 0.60, 0.45)
    love.graphics.rectangle("fill", 0, 0, w, h)
  end

  -- eigener Treffer: kurzer roter Rand — erlittener Schaden ist etwas
  -- anderes als ausgeteilter (Issue #31)
  if (self.hurt or 0) > 0 then
    local a = math.min(0.5, self.hurt * 0.5)
    for i = 1, 5 do
      love.graphics.setColor(0.8, 0.1, 0.08, a * (1 - i / 6))
      love.graphics.setLineWidth(10)
      love.graphics.circle("line", L.ox, L.oy, L.radius - i * 9)
      love.graphics.setLineWidth(1)
    end
  end

  -- Ornament-Goldring statt duenner Linie (M12, Original-Vorbild):
  -- Sitz-Schatten aussen, Bronzeband, Gold-Hauptring, Kanten, Nieten
  do
    local cx, cy, r = L.ox, L.oy, L.radius
    love.graphics.setColor(0, 0, 0, 0.22)
    love.graphics.setLineWidth(20)
    love.graphics.circle("line", cx, cy, r + 16)
    love.graphics.setColor(0, 0, 0, 0.12)
    love.graphics.setLineWidth(18)
    love.graphics.circle("line", cx, cy, r + 34)
    love.graphics.setColor(0, 0, 0, 0.06)
    love.graphics.circle("line", cx, cy, r + 52)
    love.graphics.setColor(0.20, 0.15, 0.09, 1)
    love.graphics.setLineWidth(10)
    love.graphics.circle("line", cx, cy, r + 9)
    love.graphics.setColor(0.78, 0.63, 0.28, 1)
    love.graphics.setLineWidth(5)
    love.graphics.circle("line", cx, cy, r + 3)
    love.graphics.setColor(0.93, 0.82, 0.50, 0.9)
    love.graphics.setLineWidth(1.5)
    love.graphics.circle("line", cx, cy, r)
    love.graphics.setColor(0.55, 0.42, 0.18, 1)
    love.graphics.circle("line", cx, cy, r + 14)
    love.graphics.setLineWidth(1)
    -- Nieten im 45-Grad-Raster; 12 und 6 Uhr ausgelassen (dort Plaketten)
    for k = 0, 7 do
      if k ~= 2 and k ~= 6 then -- k=6: 12 Uhr, k=2: 6 Uhr (y waechst abwaerts)
        local a2 = k * math.pi / 4
        love.graphics.setColor(0.93, 0.82, 0.50, 1)
        love.graphics.circle("fill", cx + math.cos(a2) * (r + 3),
          cy + math.sin(a2) * (r + 3), 3.5)
      end
    end
  end

  -- Hogger-Tracker (Runde 8, #108): dezentes Medaillon am Innenrand des
  -- Rings in Hoggers Richtung, solange er ausserhalb des sichtbaren
  -- Kreises liegt und lebt — auch wenn er weit draussen kaempft. Kein Blinken.
  if view.hogger and (view.hogger.hp or 0) > 0 then
    local ex, ey = R.edge_pos(view.me_x, view.me_y,
      view.hogger.x, view.hogger.y, self:zoom_radius(), L)
    if ex then
      love.graphics.setColor(0.07, 0.07, 0.09, 0.9)
      love.graphics.circle("fill", ex, ey, 14)
      love.graphics.setColor(0.78, 0.63, 0.28, 0.9)
      love.graphics.setLineWidth(1.5)
      love.graphics.circle("line", ex, ey, 14)
      love.graphics.setLineWidth(1)
      assets.draw("icon_hogger", ex, ey, 22 / assets.size("icon_hogger"), 0.9)
    end
  end

  -- Zonenbanner als Plakette AUF dem Ring (M12, GDD 4.1, Original-Vorbild)
  do
    local zone = map.zone_at(view.me_x, view.me_y)
    local font = love.graphics.getFont()
    local bw = math.max(L.banner.min_w, font:getWidth(zone) + 2 * L.banner.pad)
    local bx = L.banner.cx - bw / 2
    local by = L.banner.cy - L.banner.h / 2
    plaque(bx, by, bw, L.banner.h)
    -- goldene Endknaeufe auf Ringhoehe
    love.graphics.setColor(0.78, 0.63, 0.28, 1)
    love.graphics.circle("fill", bx, L.banner.cy, 4)
    love.graphics.circle("fill", bx + bw, L.banner.cy, 4)
    love.graphics.setColor(0.95, 0.90, 0.70, 1)
    love.graphics.print(zone, L.banner.cx - font:getWidth(zone) / 2, by + 6)
  end

  -- Uhr-Plakette unten Mitte — die originale Minimap-Position (GDD 4.2)
  do
    local mins = math.floor(view.clock / 60)
    local secs = math.floor(view.clock % 60)
    local txt = string.format("%d:%02d", mins, secs)
    local try_txt = "Try " .. view.try_nr
    local font = love.graphics.getFont()
    local pw = math.max(L.clock.w, font:getWidth(try_txt) + 16)
    local px = L.clock.cx - pw / 2
    local py = L.clock.cy - L.clock.h / 2
    plaque(px, py, pw, L.clock.h)
    love.graphics.setColor(0.95, 0.90, 0.70, 1)
    love.graphics.print(txt, L.clock.cx - font:getWidth(txt) / 2, py + 3)
    love.graphics.setColor(0.6, 0.56, 0.45, 1)
    love.graphics.print(try_txt, L.clock.cx - font:getWidth(try_txt) / 2,
      py + 18)
  end

  -- ====== Ring-UI komplett (GDD 4.2/4.3) ======
  local names = view.names or {}
  local RES_COL = { mana = { 0.25, 0.45, 0.9 }, rage = { 0.9, 0.2, 0.2 },
                    energy = { 0.9, 0.85, 0.2 } }
  local RACE_K = { mensch = "M", zwerg = "Z", nachtelf = "N", gnom = "G" }

  -- Einheitenfenster nach Original-Vorbild (Referenz spieleranzeige_und_ziel):
  -- rundes Portrait, Namensbalken, Stufen-Medaillon, HP-Balken mit Zahlen
  -- IM Balken, Ressourcenbalken darunter (GDD 4.3)
  local function unit_frame(x, y, u)
    local FW, FH = 214, 56
    love.graphics.setColor(0.07, 0.07, 0.09, 0.88)
    love.graphics.rectangle("fill", x, y, FW, FH, 3, 3)
    love.graphics.setColor(0.30, 0.26, 0.18, 1)
    love.graphics.rectangle("line", x, y, FW, FH, 3, 3)
    -- Portrait: das Klassen-/Einheitenicon selbst — die Bildsprache des
    -- Spiels beantwortet "wer bin ich" ohne einen Buchstaben (Issue #24)
    local px, py = x + 26, y + 26
    love.graphics.setColor(0.16, 0.15, 0.13, 1)
    love.graphics.circle("fill", px, py, 19)
    if u.icon then
      assets.draw(u.icon, px, py, 32 / assets.size(u.icon))
    else
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.print(u.rk or "?", px - 5, py - 8)
    end
    local ring = u.elite and { 0.95, 0.78, 0.2 } or u.ring_col or { 0.45, 0.40, 0.30 }
    love.graphics.setColor(ring[1], ring[2], ring[3], 1)
    love.graphics.setLineWidth(u.elite and 3 or 2)
    love.graphics.circle("line", px, py, 20)
    love.graphics.setLineWidth(1)
    -- Rassenkuerzel als kleines Abzeichen, Stufen-Medaillon wie im Original
    if u.rk and u.icon then
      love.graphics.setColor(0.12, 0.12, 0.14, 0.95)
      love.graphics.circle("fill", px - 14, py + 15, 8)
      love.graphics.setColor(0.8, 0.8, 0.75, 1)
      love.graphics.print(u.rk, px - 18, py + 7)
    end
    love.graphics.setColor(0.85, 0.72, 0.25, 1)
    love.graphics.circle("fill", px + 15, py + 15, 9)
    love.graphics.setColor(0, 0, 0, 1)
    local lv = tostring(u.level or 1)
    love.graphics.print(lv, px + 15 - #lv * 4, py + 8)
    -- Namensbalken (Fraktionsfarbe) mit Zusatz rechts (Klasse bzw. Art)
    local bx, bw = x + 52, FW - 62
    love.graphics.setColor(0.05, 0.05, 0.06, 0.95)
    love.graphics.rectangle("fill", bx, y + 5, bw, 15, 2, 2)
    love.graphics.setColor(u.name_col[1], u.name_col[2], u.name_col[3], 1)
    love.graphics.print(u.name or "?", bx + 4, y + 5)
    if u.sub then
      local font = love.graphics.getFont()
      love.graphics.setColor(0.75, 0.72, 0.62, 1)
      love.graphics.print(u.sub, bx + bw - 4 - font:getWidth(u.sub), y + 5)
    end
    ui_bar(bx, y + 23, bw, 13, (u.hp or 0) / math.max(1, u.maxhp or 1),
      { 0.15, 0.72, 0.18 },
      string.format("%d/%d", math.max(0, u.hp or 0), u.maxhp or 1))
    if u.res_frac then
      local c = u.res_col or RES_COL.mana
      ui_bar(bx, y + 39, bw, 10, u.res_frac, c,
        u.res_txt and string.format("%s %d", u.res_txt,
          math.floor(u.res_frac * 100 + 0.5)) or nil)
    end
  end

  local aura_tip = nil

  -- Oben links: das eigene Einheitenfenster (GDD 4.3). Es zeigt die eigene
  -- Klasse dauerhaft — Icon, Klassenfarbe und Klassenname (Issue #24)
  if me then
    local cls = me.class and model.classes[me.class]
    local FU = L.frames.unit
    unit_frame(FU.x, FU.y, {
      name = names[view.me] or "?", rk = RACE_K[me.race],
      icon = me.class and CLASS_ICON[me.class] or nil,
      ring_col = me.class and CLASS_COL[me.class] or nil,
      sub = cls and cls.name_de or (me.alive and "?" or "Geist"),
      level = 1, hp = me.hp or 0,
      maxhp = client_max_hp(me),
      res_frac = cls and (me.resource or 0) / 100 or nil,
      res_col = cls and RES_COL[cls.resource],
      res_txt = cls and RES_DE[cls.resource],
      name_col = { 0.95, 0.92, 0.8 },
    })
    if me.class == "rogue" and (me.cp or 0) > 0 then
      love.graphics.setColor(0.95, 0.35, 0.35, 1)
      love.graphics.print("CP " .. me.cp, L.frames.cp.x, L.frames.cp.y)
    end
    love.graphics.setColor(0.6, 0.56, 0.45, 1)
    love.graphics.print(string.format("Kupfer %d   Plunder %d",
      me.kupfer or 0, me.plunder or 0), L.frames.money.x, L.frames.money.y)
    -- Eigene Auren direkt unter der eigenen Tafel (Runde 8, #107) —
    -- vorher hingen sie faelschlich unter dem Zielfenster
    aura_tip = draw_auras(aura_list(me), L.frames.buffs_self.x,
      L.frames.buffs_self.y, ui) or aura_tip
    -- Hinweis auf das Raid-Overview (Runde 6, Issue #95)
    love.graphics.setColor(0.45, 0.42, 0.35, 1)
    love.graphics.print("STRG fuer Raid-Overview",
      L.frames.hint.x, L.frames.hint.y)
  end

  -- Heil-Leiste der Heilerklassen (Runde 7, #103, GDD 4.3)
  self:draw_healbar(view, L.frames.healbar)

  -- Oben rechts: Zielfenster, Ziel des Ziels, Ziel-Auren (GDD 4.3)
  if me then
    local t = me.target
    local frame
    if t == 0 then
      frame = { name = "Hogger", rk = "H", level = 11, elite = true,
                icon = "icon_hogger", sub = "Gnoll",
                hp = view.hogger.hp, maxhp = view.hogger.max_hp,
                name_col = { 0.9, 0.25, 0.2 } }
    elseif view.players[t] then
      local q = view.players[t]
      local qc = q.class and model.classes[q.class]
      frame = { name = names[t] or "?", rk = RACE_K[q.race], level = 1,
                icon = q.class and CLASS_ICON[q.class] or nil,
                ring_col = q.class and CLASS_COL[q.class] or nil,
                sub = qc and qc.name_de or "Geist",
                hp = q.hp, maxhp = math.max(1, client_max_hp(q)),
                res_frac = qc and (q.resource or 0) / 100 or nil,
                res_col = qc and RES_COL[qc.resource],
                res_txt = qc and RES_DE[qc.resource],
                name_col = { 0.4, 0.9, 0.4 } }
    elseif view.npcs and view.npcs[t] then
      local npc = view.npcs[t]
      local hostile = npc.kind == "add" or npc.kind == "wolf" or npc.kind == "murloc"
      local mobdef = model.mobs[npc.kind]
      frame = { name = mobdef and mobdef.name_de
                  or (npc.kind == "add" and "Gnoll-Welpe" or "Wichtel"),
                icon = "icon_" .. npc.kind,
                rk = nil, level = 1, hp = npc.hp,
                maxhp = npc.kind == "add" and model.p("add_hp")
                        or (mobdef and model.p(npc.kind .. "_hp")) or 1,
                name_col = hostile and { 0.9, 0.25, 0.2 } or { 0.9, 0.8, 0.3 } }
    end
    if frame then
      local FT = L.frames.target
      unit_frame(FT.x, FT.y, frame)
      -- Ziel des Ziels: wen verpruegelt Hogger gerade? (GDD 4.3)
      if t == 0 and view.hogger.target and names[view.hogger.target] then
        love.graphics.setColor(0.07, 0.07, 0.09, 0.85)
        love.graphics.rectangle("fill", L.frames.tot.x, L.frames.tot.y,
          214, 20, 3, 3)
        love.graphics.setColor(0.85, 0.8, 0.7, 1)
        love.graphics.print("> " .. names[view.hogger.target],
          L.frames.tot.x + 6, L.frames.tot.y + 2)
      end
      -- Ziel-Auren unter der Zieltafel (Runde 8, #107): die Auren des
      -- ZIELS, nicht mehr die eigenen. Hogger zeigt hier seinen
      -- Frost-Slow (Magier-Frostruestung); NPCs haben keine Auren.
      local tauras = {}
      if t == 0 then
        if (view.hogger.slow_rest or 0) > 0 then
          tauras[1] = { AURA.slow, view.hogger.slow_rest }
        end
      elseif view.players[t] then
        tauras = aura_list(view.players[t])
      end
      aura_tip = draw_auras(tauras, L.frames.buffs.x, L.frames.buffs.y, ui)
        or aura_tip
    end
  end

  -- XP-Bogen an der Innenkante, fuellt im Uhrzeigersinn (GDD 4.2)
  if me then
    local frac = math.min(1, (me.xp or 0) / model.p("xp_level2"))
    love.graphics.setColor(0.35, 0.30, 0.2, 0.6)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", L.ox, L.oy, L.radius - 8)
    if frac > 0 then
      love.graphics.setColor(0.75, 0.45, 0.85, 0.9)
      love.graphics.arc("line", "open", L.ox, L.oy, L.radius - 8,
        -math.pi / 2, -math.pi / 2 + frac * 2 * math.pi)
    end
    love.graphics.setLineWidth(1)
    -- Tooltip bei Hover (GDD 4.2)
    if ui.mouse then
      local md = math.sqrt((ui.mouse[1] - L.ox) ^ 2 + (ui.mouse[2] - L.oy) ^ 2)
      if md > L.radius - 16 and md < L.radius + 4 then
        local rest = math.max(0, model.p("xp_level2") - (me.xp or 0))
        love.graphics.setColor(0.07, 0.07, 0.09, 0.9)
        love.graphics.rectangle("fill", ui.mouse[1] + 10, ui.mouse[2] - 24, 214, 20)
        love.graphics.setColor(0.95, 0.92, 0.8, 1)
        love.graphics.print("Noch " .. rest .. " Erfahrung bis Stufe 2.",
          ui.mouse[1] + 14, ui.mouse[2] - 22)
      end
    end
  end

  -- N-Pip: Norden ist fixiert (GDD 4.1) — als Kompass-Knopf unter dem
  -- Zonenbanner, bewusst NACH dem XP-Bogen gezeichnet (M12)
  do
    local NP = L.npip
    love.graphics.setColor(0.15, 0.14, 0.11, 1)
    love.graphics.circle("fill", NP.x, NP.y, NP.r)
    love.graphics.setColor(0.78, 0.63, 0.28, 1)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", NP.x, NP.y, NP.r)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.95, 0.90, 0.70, 1)
    love.graphics.print("N", NP.x - 4, NP.y - 8)
  end

  -- Zoom-Knoepfe am Ring (klassische Position, GDD 4.2): plastisch im
  -- Original-Stil (M12); Stufe als drei Punkte + Hover-Tooltip statt Text
  do
    local Z = L.zoom
    local zoom_hover = false
    for i, sym in ipairs({ "+", "-" }) do
      local by = Z.y + (i - 1) * Z.spacing
      love.graphics.setColor(0, 0, 0, 0.5)
      love.graphics.circle("fill", Z.x + 1, by + 2, Z.r + 1)
      love.graphics.setColor(0.15, 0.14, 0.11, 1)
      love.graphics.circle("fill", Z.x, by, Z.r)
      love.graphics.setColor(0.78, 0.63, 0.28, 1)
      love.graphics.setLineWidth(2)
      love.graphics.circle("line", Z.x, by, Z.r)
      love.graphics.setLineWidth(1)
      love.graphics.setColor(0.95, 0.85, 0.55, 0.6)
      love.graphics.setLineWidth(1.5)
      love.graphics.arc("line", "open", Z.x, by, Z.r - 3,
        math.rad(-140), math.rad(-40))
      love.graphics.setLineWidth(1)
      love.graphics.setColor(0.95, 0.90, 0.70, 1)
      love.graphics.print(sym, Z.x - 4, by - 8)
      if ui.mouse then
        local d = math.sqrt((ui.mouse[1] - Z.x) ^ 2 + (ui.mouse[2] - by) ^ 2)
        if d <= Z.r + 2 then zoom_hover = true end
      end
    end
    -- drei Stufen-Punkte: gefuellt bis zur aktuellen Zoomstufe
    for s = 1, 3 do
      local px = Z.x + (s - 2) * 9
      local py = Z.y + Z.spacing + 22
      if s <= self.zoom then
        love.graphics.setColor(0.78, 0.63, 0.28, 1)
      else
        love.graphics.setColor(0.25, 0.22, 0.16, 1)
      end
      love.graphics.circle("fill", px, py, 2.5)
    end
    if zoom_hover and ui.mouse then
      draw_tooltip({ "Zoom", "Stufe " .. self.zoom .. " von 3",
        "Mausrad oder + / -" }, ui.mouse[1], ui.mouse[2], w, h)
    end
  end

  -- Faehigkeiten als runde Add-on-Buttons am unteren Ring, mit Cooldown-Sweep
  -- und Tastenkuerzel (GDD 4.2, Referenz minimap.webp). Nie mehr Buttons als
  -- die Klasse Faehigkeiten hat — und keine, solange man tot ist (Issue #29)
  local hover_tip = nil
  if me and me.class and me.alive then
    local specs = ABILITIES[me.class] or {}
    local defs = model.classes[me.class].abilities or {}
    -- Klassen-Slots 1..4. Den frueheren Nahkampf-Button gibt es nicht mehr
    -- (Runde 12, #145): Rechtsklick aufs Ziel genuegt, die Hinweiszeile
    -- unterm Ring sagt es. Per F10 abgeschaltete Faehigkeiten (Runde 13)
    -- verschwinden aus der Leiste — die Tastennummer bleibt am Slot.
    local slots = {}
    for i, spec in ipairs(specs) do
      if ABILITIES_ENABLED(spec) then
        slots[#slots + 1] = { spec = spec, def = defs[i], slot = i }
      end
    end
    local n = #slots
    local BR = 23                       -- Buttonradius
    local ring_r = L.ring_r             -- Bahn knapp innerhalb des Rings
    local dtheta = (BR * 2 + 10) / ring_r
    for k, entry in ipairs(slots) do
      -- Slot 1 links, aufsteigend nach rechts (Tastenreihenfolge)
      local a = math.pi / 2 - (k - (n + 1) / 2) * dtheta
      local x, y = L.ox + math.cos(a) * ring_r, L.oy + math.sin(a) * ring_r
      love.graphics.setColor(0.10, 0.09, 0.07, 0.95)
      love.graphics.circle("fill", x, y, BR)
      local icon = ABILITY_ICON[entry.spec.id]
      if icon then assets.draw(icon, x, y, (BR * 1.7) / assets.size(icon)) end
      -- Cooldown-Sweep im Uhrzeigersinn (Original-Verhalten)
      local cd = entry.slot and ui.cooldowns and ui.cooldowns[entry.slot] or 0
      if cd > 0 then
        love.graphics.setColor(0, 0, 0, 0.62)
        love.graphics.arc("fill", "pie", x, y, BR, -math.pi / 2,
          -math.pi / 2 + cd * 2 * math.pi)
      end
      -- laufender Cast hebt seinen Button hervor
      local active = entry.slot ~= nil and (me.cast_slot or 0) == entry.slot
      love.graphics.setColor(active and 1 or 0.78, active and 0.9 or 0.63,
        active and 0.4 or 0.28, 1)
      love.graphics.setLineWidth(active and 3 or 2)
      love.graphics.circle("line", x, y, BR)
      love.graphics.setLineWidth(1)
      love.graphics.setColor(0.95, 0.92, 0.8, 1)
      love.graphics.print(tostring(entry.slot), x + BR - 10, y + BR - 16)
      -- Tooltip: der Grund, warum "RS" niemanden mehr ratlos laesst (#28)
      if ui.mouse then
        local d = math.sqrt((ui.mouse[1] - x) ^ 2 + (ui.mouse[2] - y) ^ 2)
        if d <= BR then hover_tip = entry end
      end
    end
    -- Autoangriff der Klasse in Worten: der Jaeger hat genau deshalb nur
    -- einen Button (GDD 8.1/8.2)
    local auto = AUTO_DE[model.classes[me.class].attack]
    if auto then
      local font = love.graphics.getFont()
      love.graphics.setColor(0.62, 0.58, 0.46, 1)
      love.graphics.print(auto, L.ox - font:getWidth(auto) / 2,
        L.oy + ring_r - BR - 22)
    end
  end

  -- Fehlermeldung (Issue #56): kurz, rot, blinkt einmal auf
  if (self.err_t or 0) > 0 and self.err_text then
    local font = love.graphics.getFont()
    local a = math.min(1, self.err_t / 0.6)
      * (0.75 + 0.25 * math.sin(love.timer.getTime() * 12))
    love.graphics.setColor(0.95, 0.28, 0.22, a)
    love.graphics.print(self.err_text,
      L.ox - font:getWidth(self.err_text) / 2 * 1.2, L.oy + L.radius * 0.62,
      0, 1.2, 1.2)
  end

  -- Cast- und Wiederbelebungsbalken: unabhaengig von der Klasse, denn beim
  -- allerersten Wiederbeleben hat man noch keine (Issue #26)
  if me and (me.casting or me.reviving) then
    local label
    if me.reviving then
      -- Ziel-Klasse aus dem Bodenicon ableiten, auf dem der Geist steht
      local best, bd = nil, ICON_RADIUS
      for slot = 1, #world.CLASSES do
        local ix, iy = world.class_icon_pos(slot)
        local d = world.dist(view.me_x, view.me_y, ix, iy)
        if d <= bd then best, bd = slot, d end
      end
      local cls = best and model.classes[world.CLASSES[best]]
      label = "Wiederbelebung" .. (cls and ": " .. cls.name_de or "")
    else
      local def = me.class and model.classes[me.class].abilities[me.cast_slot or 0]
      label = def and def.name_de or "Zauber"
    end
    local bw2, bx2, by2 = 260, L.ox - 130, L.oy + L.radius * 0.34
    ui_bar(bx2, by2, bw2, 18, me.progress, { 0.85, 0.72, 0.28 }, label)
  end

  -- Faehigkeits-Tooltip ueber dem Button (Original-Stil, GDD 4.2)
  if hover_tip then
    local spec, def = hover_tip.spec, hover_tip.def
    local font = love.graphics.getFont()
    local lines = { def and def.name_de or spec.id }
    local cls = model.classes[me.class]
    if spec.cost then
      lines[#lines + 1] = string.format("%d %s", model.p(spec.cost),
        RES_DE[cls.resource] or "")
    end
    lines[#lines + 1] = spec.cast
      and string.format("%.1f s Zauberzeit", model.p(spec.cast))
      or "Sofort"
    if spec.cd then
      lines[#lines + 1] = string.format("%d s Abklingzeit", model.p(spec.cd))
    end
    if spec.range then
      lines[#lines + 1] = string.format("Reichweite %d px", model.p(spec.range))
    elseif spec.target == "ally" then
      lines[#lines + 1] = "Ziel: Verbuendeter (sonst selbst)"
    elseif spec.target == "self" then
      lines[#lines + 1] = "Wirkt auf einen selbst"
    end
    if spec.requires_cp then lines[#lines + 1] = "Braucht Combopunkte" end
    lines[#lines + 1] = "Taste " .. hover_tip.slot
    draw_tooltip(lines, ui.mouse[1], ui.mouse[2], w, h)
  end

  -- Buff-/Debuff-Tooltip zuletzt, damit er ueber allem liegt (#65)
  if aura_tip and ui.mouse then
    draw_tooltip(aura_tip.lines, ui.mouse[1], ui.mouse[2], w, h)
  end

  -- Loot-Toasts am linken Kreisrand (GDD 7.3)
  for i, t in ipairs(self.toasts) do
    love.graphics.setColor(0.95, 0.85, 0.35, math.min(1, t.t))
    love.graphics.print(t.text, L.ox - L.radius * 0.72,
      L.oy + L.radius * 0.45 + (i - 1) * 18)
  end

  -- Ansage-Banner (Try-Ende, Sieg). In der Endsequenz rutscht es nach unten:
  -- oben steht dann die Sprechblase an der verschmolzenen Figur, und beide
  -- uebereinander waren im Test unlesbar (#132).
  if self.banner_t > 0 and self.banner_text then
    love.graphics.setColor(1, 0.9, 0.5, math.min(1, self.banner_t))
    local font = love.graphics.getFont()
    local by = won > 0 and (L.oy + L.radius * 0.72) or (L.oy - L.radius * 0.4)
    love.graphics.print(self.banner_text,
      L.ox - font:getWidth(self.banner_text) / 2 * 2, by, 0, 2, 2)
  end

  -- Sprechblase am Icon des Echos (Endsequenz, GDD 11 / #132) ODER am
  -- rennenden Raid-Leeroy (DER Schrei, Runde 12 #144): der Monolog gehoert
  -- zur verschmolzenen Figur, der Schrei der Figur, die gerade losrennt.
  local anchor_x, anchor_y
  if self.bubble_anchor == "leeroy" then
    for _, p in pairs(view.players) do
      if p.is_leeroy then anchor_x, anchor_y = p.x, p.y break end
    end
  elseif view.echo then
    anchor_x, anchor_y = view.echo.x, view.echo.y
  end
  if (self.bubble_t or 0) > 0 and self.bubble_text and anchor_x then
    local bx, by = to_screen(anchor_x, anchor_y)
    local font = love.graphics.getFont()
    local wrap = R.BUBBLE_WRAP
    local _, lines = font:getWrap(self.bubble_text, wrap)
    local th = #lines * font:getHeight()
    local bw = wrap + 2 * R.BUBBLE_PAD
    local bh = th + 2 * R.BUBBLE_PAD
    local px, py = bx - bw / 2, by - 46 - bh
    local a = math.min(1, self.bubble_t * 2)
    love.graphics.setColor(0.07, 0.07, 0.11, 0.94 * a)
    love.graphics.rectangle("fill", px, py, bw, bh, 6, 6)
    love.graphics.polygon("fill", bx - 7, py + bh, bx + 7, py + bh, bx, py + bh + 12)
    love.graphics.setColor(0.78, 0.63, 0.28, a)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", px, py, bw, bh, 6, 6)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.95, 0.92, 0.8, a)
    love.graphics.printf(self.bubble_text, px + R.BUBBLE_PAD, py + R.BUBBLE_PAD,
      wrap, "center")
  end

  -- Systemnachricht (Endsequenz, GDD 11 / #132): gelb, mittig, OHNE Ablauf —
  -- sie ist das letzte Wort des Abends und bleibt stehen.
  if self.sysmsg then
    local font = love.graphics.getFont()
    love.graphics.setColor(1, 0.82, 0.2, 1)
    love.graphics.print(self.sysmsg,
      L.ox - font:getWidth(self.sysmsg) / 2 * 1.4, L.oy - 12, 0, 1.4, 1.4)
  end

  -- Killcam-Zeile: 2 s, RECOUNT-9000-Ton (GDD 11)
  if self.killcam_t > 0 and self.killcam_text then
    local a = math.min(1, self.killcam_t / 0.5)
    local band_y = L.oy + L.radius * 0.52
    love.graphics.setColor(0, 0, 0, 0.75 * a)
    love.graphics.rectangle("fill", 0, band_y - 24, w, 58)
    love.graphics.setColor(0.9, 0.3, 0.25, a)
    love.graphics.print("RECOUNT-9000 // Todesursachen-Analyse",
      L.ox - 120, band_y - 18)
    love.graphics.setColor(0.95, 0.92, 0.8, a)
    local font = love.graphics.getFont()
    love.graphics.print(self.killcam_text,
      L.ox - font:getWidth(self.killcam_text) / 2 * 1.4, band_y + 2, 0, 1.4, 1.4)
  end

  return to_screen
end

return R
