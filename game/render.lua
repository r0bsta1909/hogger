-- game/render.lua — Die Minimap IST das Spiel (GDD Kap. 4).
-- Bildschirmfuellender Kreis, eigener Spieler = goldener Pfeil im Zentrum,
-- alle anderen Entitaeten als Icons; Render-Hierarchie nach GDD 4.1.
-- Konsumiert eine dekodierte Snapshot-Sicht (Host und Client identisch).

local model = require("sim.model")
local map = require("game.data.map")
local world = require("game.gamesim.world")
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
}
local ABILITIES = require("game.gamesim.step").ABILITIES
local UI_BG = { 0.09, 0.08, 0.07 }
local GRASS = { 0.30, 0.44, 0.22 }
local PATH = { 0.48, 0.40, 0.26 }

function R.new()
  local self = setmetatable({}, R)
  self.zoom = 2 -- Stufe 1..3 (GDD 4.2)
  self.banner_t = 0
  self.banner_text = nil
  self.shake = 0
  self.toasts = {} -- Loot-Toasts am Kreisrand (GDD 7.3)
  return self
end

function R:toast(text)
  table.insert(self.toasts, 1, { text = text, t = 4 })
  if #self.toasts > 5 then table.remove(self.toasts) end
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

function R:add_shake(amount)
  self.shake = math.max(self.shake, amount)
end

function R:update(dt)
  if self.banner_t > 0 then self.banner_t = self.banner_t - dt end
  if self.shake > 0 then self.shake = math.max(0, self.shake - dt * 30) end
  for i = #self.toasts, 1, -1 do
    self.toasts[i].t = self.toasts[i].t - dt
    if self.toasts[i].t <= 0 then table.remove(self.toasts, i) end
  end
end

-- Welt -> Bildschirm um (cx, cy) zentriert
function R:make_transform(cx, cy)
  local w, h = love.graphics.getDimensions()
  local radius = h / 2 - 8
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

-- view: dekodierter Snapshot + me/me_x/me_y; ui: { facing_angle, cooldowns }
function R:draw(view, ui)
  local w, h = love.graphics.getDimensions()
  love.graphics.setColor(UI_BG[1], UI_BG[2], UI_BG[3], 1)
  love.graphics.rectangle("fill", 0, 0, w, h)

  local me = view.players[view.me]
  local to_screen, scale, ox, oy, radius = self:make_transform(view.me_x, view.me_y)

  -- Kreis-Stencil: die Minimap
  love.graphics.stencil(function()
    love.graphics.circle("fill", ox, oy, radius)
  end, "replace", 1)
  love.graphics.setStencilTest("greater", 0)

  -- Boden
  love.graphics.setColor(GRASS[1], GRASS[2], GRASS[3], 1)
  love.graphics.rectangle("fill", 0, 0, w, h)
  -- Pfad Friedhof -> Huegel
  local g = map.graveyard()
  local gx, gy = to_screen(g.x, g.y)
  local hx2, hy2 = to_screen(map.hill.x, map.hill.y)
  love.graphics.setColor(PATH[1], PATH[2], PATH[3], 1)
  love.graphics.setLineWidth(26 * scale)
  love.graphics.line(gx, gy, hx2, hy2)
  love.graphics.setLineWidth(1)
  -- Huegel-Plateau
  love.graphics.setColor(0.36, 0.33, 0.24, 1)
  love.graphics.circle("fill", hx2, hy2, 150 * scale)

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

  -- Geister zuerst (gedimmt), dann Lebende (GDD 4.1)
  for pass = 1, 2 do
    for pid, p in pairs(view.players) do
      if pid ~= view.me then
        local is_ghost_pass = pass == 1
        if (p.ghost and is_ghost_pass) or (p.alive and not is_ghost_pass) then
          local x, y = to_screen(p.x, p.y)
          local icon = CLASS_ICON[p.class]
          local jump = p.jumping and 1.25 or 1
          local alpha = p.ghost and 0.35 or p.stealth and 0.4 or 1
          if icon then
            assets.draw(icon, x, y - (p.jumping and 4 or 0),
              scale * 1.8 * jump, alpha)
            if p.is_leeroy then -- markiertes Krieger-Icon (GDD 4.1)
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
            local maxhp = model.hp_for_class(p.class)
            hp_bar(x, y + 14, 16, p.hp / maxhp, 0.2, 0.8, 0.2)
          end
        end
      end
    end
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
      assets.draw("icon_" .. npc.kind, x, y, scale * 1.8)
      if npc.kind ~= "imp" then
        local maxhp = npc.kind == "add" and model.p("add_hp")
                      or model.p(npc.kind .. "_hp")
        hp_bar(x, y + 12, 10, npc.hp / maxhp, 0.85, 0.75, 0.2)
      end
    end
  end

  -- Hogger
  local hg = view.hogger
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
      assets.draw("icon_hogger", x, y, scale * 2)
      hp_bar(x, y + 20, 26, hg.hp / math.max(1, hg.max_hp), 0.85, 0.2, 0.15)
      -- Unterbrechungszaehler: Pflicht-UI waehrend des Fressens (GDD 9.2)
      if hg.eat and hg.eat.phase == "channel" then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(string.format("%d/%d", hg.eat.hitters, hg.eat.needed),
          x - 12, y - 34 * scale - 16)
        hp_bar(x, y + 26, 26, hg.eat.progress, 0.9, 0.8, 0.2)
      end
    end
  end

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

  love.graphics.setStencilTest()

  -- Totensicht: blaeulicher Entsaettigungsfilter als Zustand (GDD 4.1)
  if me and not me.alive then
    love.graphics.setColor(0.25, 0.35, 0.60, 0.45)
    love.graphics.rectangle("fill", 0, 0, w, h)
  end

  -- Ring
  love.graphics.setColor(0.78, 0.63, 0.28, 1)
  love.graphics.setLineWidth(4)
  love.graphics.circle("line", ox, oy, radius + 2)
  love.graphics.setLineWidth(1)

  -- Zonenbanner oben (GDD 4.1)
  do
    local zone = map.zone_at(view.me_x, view.me_y)
    love.graphics.setColor(0.95, 0.90, 0.70, 1)
    local font = love.graphics.getFont()
    love.graphics.print(zone, ox - font:getWidth(zone) / 2, oy - radius + 10)
  end

  -- Uhr (zaehlt pro Try hoch, GDD 4.2) + Try-Nr.
  do
    local mins = math.floor(view.clock / 60)
    local secs = math.floor(view.clock % 60)
    local txt = string.format("%d:%02d", mins, secs)
    love.graphics.setColor(0.95, 0.90, 0.70, 1)
    love.graphics.print(txt, ox + radius * 0.60, oy - radius * 0.66)
    love.graphics.setColor(0.6, 0.56, 0.45, 1)
    love.graphics.print("Try " .. view.try_nr, ox + radius * 0.60,
      oy - radius * 0.66 + 16)
  end

  -- ====== Ring-UI komplett (GDD 4.2/4.3) ======
  local names = view.names or {}
  local RES_COL = { mana = { 0.25, 0.45, 0.9 }, rage = { 0.9, 0.2, 0.2 },
                    energy = { 0.9, 0.85, 0.2 } }
  local RACE_K = { mensch = "M", zwerg = "Z", nachtelf = "N", gnom = "G" }

  -- Einheitenfenster nach Original-Vorbild: Portrait, Namensbalken,
  -- Stufen-Medaillon, HP/Ressource (GDD 4.3)
  local function unit_frame(x, y, u)
    love.graphics.setColor(0.07, 0.07, 0.09, 0.85)
    love.graphics.rectangle("fill", x, y, 214, 48, 3, 3)
    local px, py = x + 24, y + 24
    love.graphics.setColor(0.35, 0.30, 0.24, 1)
    love.graphics.circle("fill", px, py, 18)
    if u.elite then -- goldener Elite-Drachenrahmen (Platzhalter-Doppelring)
      love.graphics.setColor(0.95, 0.78, 0.2, 1)
      love.graphics.setLineWidth(3)
      love.graphics.circle("line", px, py, 21)
      love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(u.rk or "?", px - 5, py - 8)
    love.graphics.setColor(0.85, 0.72, 0.25, 1)
    love.graphics.circle("fill", px + 15, py + 13, 9)
    love.graphics.setColor(0, 0, 0, 1)
    local lv = tostring(u.level or 1)
    love.graphics.print(lv, px + 15 - #lv * 4, py + 6)
    love.graphics.setColor(u.name_col[1], u.name_col[2], u.name_col[3], 1)
    love.graphics.print(u.name or "?", x + 50, y + 4)
    love.graphics.setColor(0.85, 0.85, 0.8, 1)
    love.graphics.print(string.format("%d/%d", u.hp or 0, u.maxhp or 1), x + 50, y + 18)
    hp_bar(x + 128, y + 24, 80, (u.hp or 0) / math.max(1, u.maxhp or 1), 0.2, 0.8, 0.2)
    if u.res_frac then
      local c = u.res_col or RES_COL.mana
      hp_bar(x + 128, y + 34, 80, u.res_frac, c[1], c[2], c[3])
    end
  end

  -- Oben links: das eigene Einheitenfenster (GDD 4.3)
  if me and me.class then
    unit_frame(12, 10, {
      name = names[view.me] or "?", rk = RACE_K[me.race] or "?",
      level = 1, hp = me.hp, maxhp = model.hp_for_class(me.class),
      res_frac = (me.resource or 0) / 100,
      res_col = RES_COL[model.classes[me.class].resource],
      name_col = { 0.95, 0.92, 0.8 },
    })
    if me.class == "rogue" and (me.cp or 0) > 0 then
      love.graphics.setColor(0.95, 0.35, 0.35, 1)
      love.graphics.print("CP " .. me.cp, 232, 14)
    end
    love.graphics.setColor(0.6, 0.56, 0.45, 1)
    love.graphics.print(string.format("Kupfer %d   Plunder %d",
      me.kupfer or 0, me.plunder or 0), 14, 62)
  end

  -- Oben rechts: Zielfenster, Ziel des Ziels, Buff-Leiste (GDD 4.3)
  if me then
    local t = me.target
    local frame
    if t == 0 then
      frame = { name = "Hogger", rk = "H", level = 11, elite = true,
                hp = view.hogger.hp, maxhp = view.hogger.max_hp,
                name_col = { 0.9, 0.25, 0.2 } }
    elseif view.players[t] then
      local q = view.players[t]
      frame = { name = names[t] or "?", rk = RACE_K[q.race] or "?", level = 1,
                hp = q.hp, maxhp = q.class and model.hp_for_class(q.class) or 1,
                res_frac = (q.resource or 0) / 100,
                res_col = q.class and RES_COL[model.classes[q.class].resource],
                name_col = { 0.4, 0.9, 0.4 } }
    elseif view.npcs and view.npcs[t] then
      local npc = view.npcs[t]
      local hostile = npc.kind == "add" or npc.kind == "wolf" or npc.kind == "murloc"
      local mobdef = model.mobs[npc.kind]
      frame = { name = mobdef and mobdef.name_de
                  or (npc.kind == "add" and "Gnoll-Welpe" or "Wichtel"),
                rk = "-", level = 1, hp = npc.hp,
                maxhp = npc.kind == "add" and model.p("add_hp")
                        or (mobdef and model.p(npc.kind .. "_hp")) or 1,
                name_col = hostile and { 0.9, 0.25, 0.2 } or { 0.9, 0.8, 0.3 } }
    end
    if frame then
      unit_frame(w - 226, 10, frame)
      -- Ziel des Ziels: wen verpruegelt Hogger gerade? (GDD 4.3)
      if t == 0 and view.hogger.target and names[view.hogger.target] then
        love.graphics.setColor(0.07, 0.07, 0.09, 0.85)
        love.graphics.rectangle("fill", w - 226, 62, 214, 20, 3, 3)
        love.graphics.setColor(0.85, 0.8, 0.7, 1)
        love.graphics.print("> " .. names[view.hogger.target], w - 220, 64)
      end
    end
    -- Buff-Leiste: nur Buffs, die Level-1-Klassen haben (GDD 4.3)
    local buffs = {}
    if me.shout then buffs[#buffs + 1] = { "SR", me.shout_rest } end
    if me.seal then buffs[#buffs + 1] = { "SG" } end
    if me.frost_armor then buffs[#buffs + 1] = { "FR" } end
    if me.stealth then buffs[#buffs + 1] = { "VS" } end
    for i, b in ipairs(buffs) do
      local bx, by = w - 226 + (i - 1) * 34, 88
      love.graphics.setColor(0.2, 0.25, 0.4, 0.9)
      love.graphics.rectangle("fill", bx, by, 30, 30, 3, 3)
      love.graphics.setColor(0.9, 0.9, 0.95, 1)
      love.graphics.print(b[1], bx + 6, by + 2)
      if b[2] and b[2] > 0 then
        love.graphics.print(tostring(b[2]), bx + 8, by + 15)
      end
    end
  end

  -- XP-Bogen an der Innenkante, fuellt im Uhrzeigersinn (GDD 4.2)
  if me then
    local frac = math.min(1, (me.xp or 0) / model.p("xp_level2"))
    love.graphics.setColor(0.35, 0.30, 0.2, 0.6)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", ox, oy, radius - 8)
    if frac > 0 then
      love.graphics.setColor(0.75, 0.45, 0.85, 0.9)
      love.graphics.arc("line", "open", ox, oy, radius - 8,
        -math.pi / 2, -math.pi / 2 + frac * 2 * math.pi)
    end
    love.graphics.setLineWidth(1)
    -- Tooltip bei Hover (GDD 4.2)
    if ui.mouse then
      local md = math.sqrt((ui.mouse[1] - ox) ^ 2 + (ui.mouse[2] - oy) ^ 2)
      if md > radius - 16 and md < radius + 4 then
        local rest = math.max(0, model.p("xp_level2") - (me.xp or 0))
        love.graphics.setColor(0.07, 0.07, 0.09, 0.9)
        love.graphics.rectangle("fill", ui.mouse[1] + 10, ui.mouse[2] - 24, 214, 20)
        love.graphics.setColor(0.95, 0.92, 0.8, 1)
        love.graphics.print("Noch " .. rest .. " Erfahrung bis Stufe 2.",
          ui.mouse[1] + 14, ui.mouse[2] - 22)
      end
    end
  end

  -- Zoom-Knoepfe am Ring (klassische Position, GDD 4.2) + Stufenanzeige
  do
    local zx, zy = ox + radius * 0.86, oy + radius * 0.42
    for i, sym in ipairs({ "+", "-" }) do
      local by = zy + (i - 1) * 34
      love.graphics.setColor(0.15, 0.14, 0.11, 0.9)
      love.graphics.circle("fill", zx, by, 13)
      love.graphics.setColor(0.78, 0.63, 0.28, 1)
      love.graphics.circle("line", zx, by, 13)
      love.graphics.print(sym, zx - 4, by - 8)
    end
    love.graphics.setColor(0.6, 0.56, 0.45, 1)
    love.graphics.print("Zoom " .. self.zoom, zx - 24, zy + 60)
  end

  -- Faehigkeitenleiste unten mittig, aus den Faehigkeits-Spezifikationen
  -- generiert — nie mehr Buttons als die Klasse Faehigkeiten hat (GDD 4.2)
  if me and me.class then
    local buttons = {}
    for slot, spec in ipairs(ABILITIES[me.class] or {}) do
      buttons[slot] = { ABILITY_ICON[spec.id], tostring(slot) }
    end
    local bx = ox - (#buttons * 48) / 2 + 24
    for i, b in ipairs(buttons) do
      local x, y = bx + (i - 1) * 48, oy + radius - 34
      assets.draw(b[1], x, y, 1)
      local cd = ui.cooldowns and ui.cooldowns[i] or 0
      if cd > 0 then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", x - 20, y - 20 + 40 * (1 - cd), 40, 40 * cd)
      end
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.print(b[2], x - 18, y - 18)
    end
    -- Cast-/Wiederbelebungsbalken
    if me.casting or me.reviving then
      hp_bar(ox, oy + 40, 50, me.progress, 0.9, 0.8, 0.3)
    end
  end

  -- Loot-Toasts am linken Kreisrand (GDD 7.3)
  for i, t in ipairs(self.toasts) do
    love.graphics.setColor(0.95, 0.85, 0.35, math.min(1, t.t))
    love.graphics.print(t.text, ox - radius * 0.72, oy + radius * 0.45 + (i - 1) * 18)
  end

  -- Ansage-Banner (Try-Ende, Sieg)
  if self.banner_t > 0 and self.banner_text then
    love.graphics.setColor(1, 0.9, 0.5, math.min(1, self.banner_t))
    local font = love.graphics.getFont()
    love.graphics.print(self.banner_text,
      ox - font:getWidth(self.banner_text) / 2 * 2, oy - radius * 0.4, 0, 2, 2)
  end

  return to_screen
end

return R
