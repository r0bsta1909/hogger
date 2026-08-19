-- game/ui/errors.lua — Warum geht die Faehigkeit nicht durch? (Issue #56)
-- Der Host verwirft einen unmoeglichen Versuch stumm; der Client sagt dem
-- Spieler hier, woran es lag — im Ton des Originals, als kurz aufblinkende
-- rote Zeile. Dieselben Regeln wie in der Sim (Ressource, Reichweite,
-- Frontbogen), nur lokal fuer die Anzeige. Reines Lua, testbar.

local model = require("sim.model")
local input = require("game.gamesim.input")
local world = require("game.gamesim.world")

local E = {}

E.RES_NAME = { mana = "Mana", rage = "Wut", energy = "Energie" }
E.NO_TARGET = "Du hast kein Ziel."
E.TOO_FAR = "Zu weit entfernt."
E.WRONG_WAY = "Ziel ist nicht vor dir."
E.NOT_READY = "Das ist noch nicht bereit."
E.NO_CP = "Keine Combopunkte."
E.NOT_EATING = "Hogger frisst gerade nicht."
E.ONCE_PER_LIFE = "Das geht nur einmal pro Leben."

-- me: eigener Spieler aus der Sicht; spec: Faehigkeits-Spezifikation;
-- ctx: { x, y, facing, cooldown, hogger = {x,y,hp,state}, npcs = {},
--        players = {}, ally_target = {x,y,alive,is_self} }
-- players (Snapshot-Spieler) speist den Tastendruck-Pfad fuer Ally-Zauber;
-- ally_target setzt nur der Heil-Leisten-Pfad explizit (Runde 7, #103).
function E.check(me, spec, ctx)
  if not (me and spec and ctx) then return nil end
  if (ctx.cooldown or 0) > 0 then return E.NOT_READY end
  -- Handauflegung (Runde 13, #155): einmal pro Leben — me.loh_used kommt
  -- als Snapshot-Flag (flags3)
  if spec.id == "loh" and me.loh_used then return E.ONCE_PER_LIFE end
  local cls = model.classes[me.class]
  local cost = spec.cost and model.p(spec.cost) or 0
  if cost > 0 and (me.resource or 0) + 0.5 < cost then
    return "Nicht genug " .. (E.RES_NAME[cls and cls.resource] or "Ressource") .. "."
  end
  if spec.requires_cp and (me.cp or 0) < 1 then return E.NO_CP end
  if spec.target == "ally" then
    -- Heil-Reichweite (Runde 7): nur fuer lebende SPIELER-Ziele ausser
    -- einem selbst; Hogger/Mob im Ziel heisst Selbstheilung — immer ok.
    local a = ctx.ally_target
    if not a and ctx.players then
      local t = ctx.players[me.target]
      if t then a = { x = t.x, y = t.y, alive = t.alive, is_self = false } end
    end
    if a and a.alive and not a.is_self
       and world.dist(ctx.x, ctx.y, a.x, a.y) > model.p("heal_range") then
      return E.TOO_FAR
    end
    return nil
  end
  if spec.target ~= "enemy" then return nil end

  local t = me.target
  local tx, ty
  local h = ctx.hogger
  if t == world.HOGGER_ID and h and (h.hp or 0) > 0 and h.state ~= "reset" then
    tx, ty = h.x, h.y
  elseif ctx.npcs and ctx.npcs[t] then
    tx, ty = ctx.npcs[t].x, ctx.npcs[t].y
  end
  if not tx then return E.NO_TARGET end
  if spec.range and world.dist(ctx.x, ctx.y, tx, ty) > model.p(spec.range) then
    return E.TOO_FAR
  end
  if not input.facing_ok(ctx.facing, ctx.x, ctx.y, tx, ty,
                         model.p("facing_arc_deg")) then
    return E.WRONG_WAY
  end
  -- Tritt (Runde 12, #140): nur waehrend Hoggers Fresskanal sinnvoll —
  -- der Host wuerde ihn sonst verwerfen (spec.ready), ohne den Cooldown
  -- anzufassen; hier steht der Grund
  if spec.id == "kick" then
    local eat = h and h.eat
    if t ~= world.HOGGER_ID
       or not (eat and eat.phase == "channel") then
      return E.NOT_EATING
    end
  end
  return nil
end

return E
