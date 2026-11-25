-- Guild Union - Eventos de la unión (la sección Eventos de la lista de miembros; hasta el 25/11, Calendario) [+ARCHITECTURE.md]
-- Los eventos y quién va viajan como propuestas (Packs/Events.lua, conjunto EV); las raids se quedan en el PC de quien
-- organiza. Con el estilo compartido (DJStyle.lua): fondos lisos casi negros con borde de tooltip gris, títulos y rayas
-- doradas, tarjetas con sombra arriba y brillo dorado.
-- Pestañas Eventos (tarjetas) y Calendario (el mes); la ficha de cada evento son sus raids. Clic derecho en uno mío:
-- editarlo o eliminarlo.
local _, HU = ...
local L = HU.L

-- (las raids de los eventos que organizo, en este PC: calRaids[id] = { raid, …, t = hora del evento }. calEvents: los
-- eventos de la copia 324, que pasan a la red al entrar: ver Migrate)
HU:Saved({ account = { calEvents = {}, calRaids = {} } })

-- (Eventos: una tarjeta por línea, a todo lo ancho, y 4 a la vista; la rueda baja de una en una. Jorge, 24/11)
local CARD_H, CARD_GAP, CARD_N = 62, 6, 4
local GROUPS, PER_GROUP = 8, 5
local MAX_RAIDS = 20
-- (las pestañas de raid de la ficha: botones rojos de 92 x 24 con la letra de siempre, 7 por fila; con 20, tres filas)
local RAID_ROW, TAB_W, TAB_H, TAB_ROW_H = 7, 92, 24, 28
local DETAIL_H = 480        -- alto de la ventana del evento con una fila de pestañas
local BENCH_N = 12          -- filas del banquillo a la vista (con barra, el resto)
local DAY_N, DAY_H = 5, 44  -- eventos del día a la vista en Calendario (con barra, el resto) y su alto
-- (abajo, «+ Nuevo evento» (24 de alto, a 6 del borde del panel): las tarjetas, el mes y el panel del día acaban BOTTOM_H
-- por encima del borde de abajo del panel, para que el botón no tape nada) [+ARCHITECTURE.md]
local BOTTOM_H = 34
local DESC_LINES, DESC_LINE_H = 4, 13 -- la descripción en la ficha: como mucho 4 líneas (de 13 px, letra pequeña)
local MINE, OTHERS = "|cff4da6ff", "|cffffd100"
local DJ = HU.DJ
local T = DJ.T
local WHITE, TIP_BORDER, ROW_HL = DJ.WHITE, DJ.TIP_BORDER, DJ.ROW_HL
local Panel, Parchment, Line, DJButton, RoundIcon, DJWindow, Big, C =
    DJ.Panel, DJ.Parchment, DJ.Line, DJ.Button, DJ.RoundIcon, DJ.Window, DJ.Big, DJ.C
local CROWN = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:14:14|t "
local ST_WAIT = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14:14|t"
local ST_OK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
local ST_NO = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t"
local KINDS = {
    { "raid", "Banda", "ff8040", "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
    { "dungeon", "Mazmorra", "4da6ff", "Interface\\Icons\\INV_Misc_Key_03" },
    { "pvp", "JcJ", "ff4040", "Interface\\Icons\\INV_BannerPVP_02" },
    { "social", "Social", "40ff40", "Interface\\Icons\\INV_Drink_05" },
    { "other", "Otro", "b0b0b0", "Interface\\Icons\\INV_Misc_QuestionMark" },
}
-- (los roles, con el icono redondo del buscador de grupo del juego)
local ROLES = { "TANK", "HEALER", "DAMAGER" }
local ROLE_NAME = { TANK = "Tanque", HEALER = "Sanador", DAMAGER = "Daño" }
local ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_TC = { TANK = { 0, 19, 22, 41 }, HEALER = { 20, 39, 1, 20 }, DAMAGER = { 20, 39, 22, 41 } }
local function RoleIcon(role, size)
    local c = ROLE_TC[role]
    if not c then return "" end
    size = size or 14
    return string.format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t", ROLE_TEX, size, size, c[1], c[2], c[3], c[4])
end
local KIND = {}
for _, k in ipairs(KINDS) do KIND[k[1]] = k end
local DAYS = { "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo" }
local DAYS_SHORT = { "L", "M", "X", "J", "V", "S", "D" }
local DAYS_ABBR = { "lun", "mar", "mié", "jue", "vie", "sáb", "dom" }
local MONTHS = { "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
    "noviembre", "diciembre" }

-- (lo que se ve: los eventos de la red, que rehace Rebuild, y los del modo prueba, aparte y solo en este PC)
local events = {}           -- { id, title, kind, t, who, tag, desc, minLevel, icon, signups = { [nombre] = "yes" }, roles = { [nombre] = rol }, raids, test }
local testEvents = {}
local dirty = true          -- ha llegado algo de la red: se rehace antes de pintar
local paintSoon             -- (lo que llega seguido se pinta una sola vez)
local open                  -- la sección se ve (entre su OnShow y su OnHide: también se esconde al cerrar la ventana)
local lastRole              -- el último rol con el que me apunté (sin el menú del juego, y al crear un evento, voy con él)
local view = "list"         -- "list" (Eventos) o "month" (Calendario)
local selected              -- el evento cuya ficha está abierta (id)
local month, year           -- el mes que se ve en Calendario
local pickedDay             -- el día elegido en Calendario ("aaaa-mm-dd")
local raidPick = 1          -- la raid que se ve
local benchRole             -- el banquillo, solo de ese rol ("TANK", "HEALER", "DAMAGER"); nil, todos
local testClass = {}        -- [nombre] = clase (modo prueba)
local invites = {}          -- [nombre] = { s = "wait"|"ok"|"no", t } (lo que pasó al invitarlos)
local picks = {}            -- [nombre] = true: los elegidos con Ctrl / Mayús en la ficha, para invitar solo a esos
local lastPick              -- el último elegido (Mayús elige desde él)
local dragName
local ui

local function Me() return HU:Me() or "?" end
local function NewId() return string.format("%x%x", math.random(0, 0xffff), time() % 0xffff) end
local function DayKey(t) return date("%Y-%m-%d", t) end
-- (día de la semana, con el lunes primero: 1 = lunes … 7 = domingo)
local function WeekDay(t) return (tonumber(date("%w", t)) + 6) % 7 + 1 end
local function KindText(k)
    local d = KIND[k] or KIND.other
    return "|cff" .. d[3] .. L(d[2]) .. "|r"
end
local function KindIcon(k) return (KIND[k] or KIND.other)[4] end
-- (las imágenes para elegir al crear un evento: iconos de vanilla)
local EVENT_ICONS = {
    "INV_Misc_Head_Dragon_01", "INV_Misc_Head_Dragon_Black", "Spell_Fire_Incinerate", "INV_Hammer_Unique_Sulfuras",
    "Spell_Shadow_RaiseDead", "Spell_Shadow_ShadowBolt", "INV_Sword_39", "Ability_Warrior_DefensiveStance",
    "INV_BannerPVP_01", "INV_BannerPVP_02", "Ability_Mount_RidingHorse", "INV_Misc_Key_03",
    "INV_Drink_05", "INV_Misc_Food_15", "INV_Fishingpole_02", "INV_Misc_Gift_01",
    "Spell_Nature_Polymorph", "Spell_Holy_PrayerOfHealing", "Spell_Frost_FrostBolt02", "Spell_Nature_Lightning",
    "Ability_Rogue_Eviscerate", "Ability_Hunter_Pet_Wolf", "INV_Misc_Bag_10", "INV_Misc_Coin_01",
    "INV_Misc_Book_09", "INV_Misc_Map_01", "Spell_Holy_HolyBolt", "INV_Shield_06",
    "INV_Helmet_08", "Spell_Nature_HealingTouch", "Spell_Arcane_TeleportStormWind", "INV_Misc_Herb_07",
    "Spell_Holy_SealOfMight", "Spell_Holy_DivineIntervention", "Spell_Shadow_DeathCoil", "Spell_Shadow_SoulGem",
    "Spell_Fire_FlameBolt", "Spell_Fire_Fireball02", "Spell_Frost_FrostNova", "Spell_Nature_StarFall",
    "Spell_Nature_Regeneration", "Ability_Warrior_Charge", "Ability_Warrior_BattleShout", "Ability_Druid_CatForm",
    "Ability_Racial_BearForm", "Ability_Hunter_SniperShot", "Ability_Stealth", "Ability_Rogue_Sprint",
    "INV_Sword_04", "INV_Axe_09", "INV_Mace_01", "INV_Staff_13",
    "INV_Weapon_Bow_07", "INV_Chest_Plate06", "INV_Misc_Bone_HumanSkull_01", "INV_Misc_Gem_Pearl_02",
    "INV_Potion_54", "INV_Scroll_03", "INV_Misc_Note_01", "INV_Torch_Lit",
    "Spell_Holy_Resurrection", "Spell_Arcane_TeleportOrgrimmar", "INV_Misc_Ribbon_01", "INV_Misc_Bomb_04",
}
local function EventIcon(e) return e.icon or KindIcon(e.kind) end
local function KindRGB(k)
    local h = (KIND[k] or KIND.other)[3]
    return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
local function LongDay(t)
    local d = date("*t", t)
    return string.format(L("%s %d de %s"), L(DAYS[WeekDay(t)]), d.day, L(MONTHS[d.month]))
end
local function Find(id) for _, e in ipairs(events) do if e.id == id then return e end end end
local function Count(e)
    local n = 0
    for _, v in pairs(e.signups) do if v == "yes" then n = n + 1 end end
    return n
end
local function WhoText(e)
    local tag = e.tag and (" |cff" .. HU:GuildColorHex(e.tag) .. "<" .. e.tag .. ">|r") or ""
    return (e.who == Me() and MINE or OTHERS) .. HU:Short(e.who) .. "|r" .. tag
end
-- (un evento no tiene hora de fin: acaba LASTS (3 h) después de su hora. En Eventos, por fecha, hasta CARDS_AFTER (2 días)
-- después de acabar; luego solo en el mes, hasta que caduca su línea en la red (Packs/Events.lua)) [+ARCHITECTURE.md]
local LASTS, CARDS_AFTER = 3 * 3600, 2 * 86400
-- (por fecha, y arriba los que su creador fijó para todos (Jorge, 25/11: «por orden de fecha, pudiendo fijar si se
-- quiere», «para todos»: `pinned`, Packs/Events.lua) [+ARCHITECTURE.md]
local function Upcoming()
    local out, now = {}, time()
    for _, e in ipairs(events) do if now < e.t + LASTS + CARDS_AFTER then out[#out + 1] = e end end
    table.sort(out, function(a, b)
        if (a.pinned == true) ~= (b.pinned == true) then return a.pinned == true end
        if a.t ~= b.t then return a.t < b.t end
        return tostring(a.id) < tostring(b.id)
    end)
    return out
end
local function OnDay(key)
    local out = {}
    for _, e in ipairs(events) do if DayKey(e.t) == key then out[#out + 1] = e end end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end
-- (organiza el evento —crear raids, mover gente, colocar, elegir líder—: quien lo creó o el líder de alguna de
-- sus raids) [+ARCHITECTURE.md]
local function CanManage(e)
    if e.who == Me() then return true end
    for _, r in ipairs(e.raids or {}) do if r.leader == Me() then return true end end
    return false
end
-- (la clase de alguien, para su color: mi hermandad, las listas de las otras o el modo prueba)
local function ClassMap()
    local map = {}
    for k, v in pairs(testClass) do map[k:lower()] = v end
    for _, m in ipairs(HU.rosterList or {}) do
        if type(m.name) == "string" and m.class then map[m.name:lower()] = m.class end
    end
    for _, rr in pairs(HU.remoteRoster or {}) do
        for _, m in ipairs(rr.members or {}) do
            if type(m.name) == "string" and m.class and not map[m.name:lower()] then map[m.name:lower()] = m.class end
        end
    end
    return map
end
local testLevel = {}         -- [nombre] = nivel (modo prueba)
local function LevelMap()
    local map = {}
    for k, v in pairs(testLevel) do map[k:lower()] = v end
    for _, m in ipairs(HU.rosterList or {}) do
        if type(m.name) == "string" and type(m.level) == "number" then map[m.name:lower()] = m.level end
    end
    for _, rr in pairs(HU.remoteRoster or {}) do
        for _, m in ipairs(rr.members or {}) do
            if type(m.name) == "string" and type(m.level) == "number" and not map[m.name:lower()] then map[m.name:lower()] = m.level end
        end
    end
    return map
end
local function ColorName(name, classes, role)
    local c = classes[(HU:FullName(name) or name):lower()] or classes[name:lower()]
    c = c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c]
    local hex = c and string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "ffffff"
    return (role and (RoleIcon(role, 13) .. " ") or "") .. "|cff" .. hex .. HU:Short(name) .. "|r"
end
local function RoleOf(e, name) return e.roles and e.roles[name] end
-- (qué roles puede hacer cada clase en Forever, que es vanilla: tanque guerrero, druida y paladín; sanador sacerdote,
-- druida, paladín y chamán; daño, todas)
local CAN_ROLE = {
    TANK = { WARRIOR = true, DRUID = true, PALADIN = true },
    HEALER = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true },
}
local function CanRole(class, role)
    if role == "DAMAGER" or not class then return true end
    return CAN_ROLE[role] and CAN_ROLE[role][class] == true
end
-- (mi rol sin el menú, al crear un evento: el último con el que me apunté o, si no, el primero que hace mi clase)
local function MyRole()
    if lastRole then return lastRole end
    local _, myClass = UnitClass("player")
    for _, role in ipairs(ROLES) do if CanRole(myClass, role) then return role end end
end
-- (cuántos de cada rol: «[T] 2  [H] 5  [D] 12»)
local function RoleCounts(e, names)
    local n = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for _, name in ipairs(names) do local r = RoleOf(e, name); if r then n[r] = n[r] + 1 end end
    return RoleIcon("TANK") .. " " .. n.TANK .. "   " .. RoleIcon("HEALER") .. " " .. n.HEALER .. "   " .. RoleIcon("DAMAGER") .. " " .. n.DAMAGER
end

local Paint

---------------------------------------------------------------------------
-- Raids: { name, leader, groups = { {nombres} x8 } }. El líder va siempre el primero del grupo 1 [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local function Members(r)
    local out = {}
    for g = 1, GROUPS do for _, n in ipairs(r.groups[g]) do out[#out + 1] = n end end
    return out
end
local function FindPos(r, name)
    for g = 1, GROUPS do for i, n in ipairs(r.groups[g]) do if n == name then return g, i end end end
end
local function InAnyRaid(e, name)
    for _, r in ipairs(e.raids or {}) do if FindPos(r, name) then return r end end
end
local function Unassigned(e)
    local out = {}
    for n, v in pairs(e.signups) do if v == "yes" and not InAnyRaid(e, n) then out[#out + 1] = n end end
    table.sort(out)
    return out
end
-- (el banquillo que se ve: con un rol elegido arriba, solo los de ese rol; y, aparte, todos los que no tienen raid)
local function BenchShown(e)
    local free = Unassigned(e)
    if not benchRole then return free, free end
    local shown = {}
    for _, n in ipairs(free) do if RoleOf(e, n) == benchRole then shown[#shown + 1] = n end end
    return shown, free
end
-- (lo que se ve en la ficha, en orden: el banquillo de arriba abajo y luego la raid, grupo a grupo. Mayús elige un tramo)
local function PickOrder(shown, r)
    local out = {}
    for _, n in ipairs(shown) do out[#out + 1] = n end
    for _, n in ipairs(Members(r)) do out[#out + 1] = n end
    return out
end
-- A quién invita el botón de la raid: los elegidos con Ctrl / Mayús; sin elegidos, los de la raid, o solo los del rol del
-- filtro del banquillo (Jorge, 25/11: «invitará solo a los tankes o healers o lo que tengas filtrado») [+ARCHITECTURE.md]
local function InviteTargets(e, r)
    local out = {}
    for _, n in ipairs(PickOrder((BenchShown(e)), r)) do if picks[n] then out[#out + 1] = n end end
    if #out > 0 then return out, "picked" end
    for _, n in ipairs(Members(r)) do if not benchRole or RoleOf(e, n) == benchRole then out[#out + 1] = n end end
    return out, benchRole
end
local function TakeOut(r, name)
    local g, i = FindPos(r, name)
    if g then table.remove(r.groups[g], i) end
    if r.leader == name then r.leader = nil end
end
-- (la raid que lleva alguien: el líder no se mueve de su hueco ni de su raid, solo cambia con SetLeader)
local function LeadsAny(e, name)
    for _, r in ipairs(e.raids or {}) do if r.leader == name then return r end end
end
-- Poner a alguien en un grupo (y un hueco): si el hueco tiene a otro, se cambian (si viene del banquillo, el otro
-- sale al banquillo); si el grupo está lleno, no. El hueco 1 del grupo 1 es del líder
local function Place(e, r, name, tg, ti)
    if LeadsAny(e, name) then return end
    if r.leader and tg == 1 and ti == 1 then ti = 2 end
    for _, o in ipairs(e.raids) do if o ~= r then TakeOut(o, name) end end
    local sg, si = FindPos(r, name)
    local other = r.groups[tg][ti]
    if other == name then return end
    if other then
        if other == r.leader then return end
        if sg then r.groups[sg][si] = other end
        r.groups[tg][ti] = name
        return
    end
    if #r.groups[tg] >= PER_GROUP and sg ~= tg then return HU:Print(L("Ese grupo está lleno.")) end
    if sg then table.remove(r.groups[sg], si) end
    table.insert(r.groups[tg], name)
end
local function AddToRaid(e, r, name)
    for g = 1, GROUPS do
        if #r.groups[g] < PER_GROUP then Place(e, r, name, g, #r.groups[g] + 1); return end
    end
    HU:Print(L("La raid está llena (40)."))
end
-- (el líder, el primero del grupo 1: si no cabe, el último del grupo 1 baja a otro grupo)
local function SetLeader(e, r, name)
    for _, o in ipairs(e.raids) do if o ~= r then TakeOut(o, name) end end
    TakeOut(r, name)
    local g1 = r.groups[1]
    if #g1 >= PER_GROUP then
        local out = table.remove(g1)
        r.leader = name
        table.insert(g1, 1, name)
        AddToRaid(e, r, out)
        return
    end
    table.insert(g1, 1, name)
    r.leader = name
end
-- La raid para alguien: entre las que tienen sitio, la que menos tiene de su rol (y luego, la más vacía)
local function BestRaid(e, name)
    local role, best, bestKey = RoleOf(e, name), nil, nil
    for _, r in ipairs(e.raids or {}) do
        local m = Members(r)
        if #m < GROUPS * PER_GROUP then
            local same = 0
            for _, n in ipairs(m) do if RoleOf(e, n) == role then same = same + 1 end end
            local key = same * 100 + #m
            if not bestKey or key < bestKey then best, bestKey = r, key end
        end
    end
    return best
end
local function AutoPlace(e, name)
    if InAnyRaid(e, name) then return true end
    local r = BestRaid(e, name)
    if r then AddToRaid(e, r, name); return true end
    return false
end
-- (la primera raid con sitio, en su orden)
local function FirstRaid(e)
    for _, r in ipairs(e.raids or {}) do
        if #Members(r) < GROUPS * PER_GROUP then return r end
    end
end
-- «Colocar en raids»: los del banquillo, primero tanques, luego sanadores y luego daño, llenando las raids en orden: la 1
-- hasta llenarla, luego la 2 y así hasta la última (Jorge, 24/11; antes repartía como al apuntarse, BestRaid)
local function PlaceBench(e)
    local order = { TANK = 1, HEALER = 2, DAMAGER = 3 }
    local free = Unassigned(e)
    table.sort(free, function(a, b)
        local ra, rb = order[RoleOf(e, a) or "DAMAGER"] or 3, order[RoleOf(e, b) or "DAMAGER"] or 3
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    local placed = 0
    for _, n in ipairs(free) do
        local r = FirstRaid(e)
        if not r then break end
        AddToRaid(e, r, n)
        placed = placed + 1
    end
    HU:Print(string.format(L("Colocados %d en raids; %d se quedan sin raid."), placed, #free - placed))
end
-- (se llama «Raid N», con el número siguiente al más alto: al quitar una del medio no se repite)
local function NewRaid(e, leader)
    local top = 0
    for _, o in ipairs(e.raids) do top = math.max(top, tonumber(o.name:match("(%d+)$")) or 0) end
    local r = { name = L("Raid") .. " " .. (top + 1), groups = {} }
    for g = 1, GROUPS do r.groups[g] = {} end
    table.insert(e.raids, r)
    if leader then SetLeader(e, r, leader) end
    return r
end

---------------------------------------------------------------------------
-- Lo que se ve: lo de la red (HU:PackedEvents) y los de prueba. Se rehace al llegar algo o al abrir [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- (¿tengo enteros los paquetes de las otras hermandades? Un trozo que se está pidiendo no quiere decir que se hayan ido)
local function Whole()
    for _, tag in ipairs(HU:OtherTags()) do
        local got, total = HU:PackProgress(tag, "EV")
        if got and got < total then return false end
    end
    return true
end
-- (quien ya no va sale de las raids de ese evento)
local function Prune(e)
    for _, r in ipairs(e.raids) do
        for _, n in ipairs(Members(r)) do if e.signups[n] ~= "yes" then TakeOut(r, n) end end
    end
end
local function Rebuild()
    dirty = false
    local list, byId = {}, {}
    local evs, signs = HU:PackedEvents()
    -- (si dos creadores usan la misma clave, vale el primero que la propuso)
    table.sort(evs, function(a, b)
        if a.pt ~= b.pt then return a.pt < b.pt end
        if a.who ~= b.who then return a.who < b.who end
        return a.id < b.id
    end)
    for _, e in ipairs(evs) do
        if not byId[e.id] then byId[e.id] = e; list[#list + 1] = e end
    end
    -- (las raids, con su tabla guardada: lo que se mueve se guarda solo. Las de los míos, guardadas desde el principio)
    local saved, me = HU.db.calRaids, Me()
    for _, e in ipairs(list) do
        e.signups, e.roles = {}, {}
        local raids = saved[e.id]
        if not raids and e.who == me then raids = {}; saved[e.id] = raids end
        if raids then raids.t = e.t end
        e.raids = raids or {}
    end
    for _, s in ipairs(signs) do
        local e = byId[s.id]
        if e then e.signups[s.who], e.roles[s.who] = "yes", s.role end
    end
    -- (quien ya no va sale de mis raids)
    if Whole() then for _, e in ipairs(list) do Prune(e) end end
    for _, e in ipairs(testEvents) do list[#list + 1] = e end
    events = list
end

---------------------------------------------------------------------------
-- Invitar a todos los de la raid, y lo que pasa con cada uno: reloj (invitado), tic (dentro), X (no acepta,
-- rechaza o no se le encuentra) [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- (un texto del juego como «%s declines your group invitation.» pasado a patrón de búsqueda)
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local s = fmt:gsub("%%s", "@S@"):gsub("%%d", "@D@")
    s = s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    s = s:gsub("@S@", "(.+)"):gsub("@D@", "%%d+")
    return "^" .. s .. "$"
end
local NO_PATTERNS = {}
for _, k in ipairs({ "ERR_DECLINE_GROUP_S", "ERR_ALREADY_IN_GROUP_S", "ERR_BAD_PLAYER_NAME_S", "ERR_INVITE_PLAYER_BUSY_S" }) do
    local p = Pattern(_G[k])
    if p then NO_PATTERNS[#NO_PATTERNS + 1] = p end
end
local function InGroup(name)
    local short = HU:Short(name)
    return UnitInRaid(short) or UnitInParty(short)
end
local function Mark(name, s)
    invites[name] = { s = s, t = time() }
    if ui and ui:IsShown() then Paint() end
end
HU:On("CHAT_MSG_SYSTEM", function(msg)
    if type(msg) ~= "string" or HU.Secret(msg) or not next(invites) then return end
    for _, p in ipairs(NO_PATTERNS) do
        local who = msg:match(p)
        if who then
            who = who:gsub("^'", ""):gsub("'$", "")
            for n, st in pairs(invites) do
                if st.s == "wait" and HU:Short(n):lower() == HU:Short(who):lower() then Mark(n, "no") end
            end
            return
        end
    end
end)

---------------------------------------------------------------------------
-- La banda de verdad, montada como la raid de la que invité: quien entra va a su grupo de la pestaña (Jorge, 25/11:
-- «lo va cambiando en el juego para que quede montado igual según vayan entrando»). Solo líder o ayudante, fuera de
-- combate, una pasada por cambio de banda y sin pelearse con nadie [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local PLAN_TTL, ARRANGE_GAP, ARRANGE_MAX = 4 * 3600, 1, 4
-- (plan: { id, name, who, untilT, placed = { [nombre] = grupo } }, la raid de la que invité; en un evento de verdad va
-- guardado con sus raids, calRaids[id].plan, y sigue tras /reload. soon: hay una pasada en camino; later: espera a
-- salir de combate; off: el juego no deja que el addon mueva a la gente, y no se intenta más hasta /reload)
local arrange = {}
-- (mover de grupo; el bloqueo del juego se espera, como en Channel.lua: no se guarda como error)
local function Move(fn, x, y)
    HU.expectBlock = "raid"
    pcall(fn, x, y)
    HU.expectBlock = nil
end
for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    HU:On(ev, function() if HU.expectBlock == "raid" then arrange.off = true end end)
end
local function PlanRaid()
    local p = arrange.plan
    if not p then return nil end
    if time() >= p.untilT then arrange.plan = nil; return nil end
    local e = Find(p.id)
    for _, r in ipairs((e and e.raids) or HU.db.calRaids[p.id] or {}) do if r.name == p.name then return r end end
end
-- (lleva a m a su grupo del plan: si cabe, allí (SetRaidSubgroup); si está lleno, se cambia (SwapRaidSubgroup) con
-- alguien del plan que tampoco va ahí y no se ha colocado, mejor si va justo al grupo de m. 1 si lo ha movido)
local function Bring(m, list, count, placed)
    if count[m.w] < PER_GROUP then
        Move(SetRaidSubgroup, m.i, m.w)
        count[m.g] = count[m.g] - 1
        count[m.w] = count[m.w] + 1
        m.g = m.w
        return 1
    end
    local o
    for _, x in ipairs(list) do
        if x.g == m.w and x.w ~= m.w and placed[x.k] ~= x.w and (not o or x.w == m.g) then o = x end
    end
    if not o then return 0 end
    Move(SwapRaidSubgroup, m.i, o.i)
    o.g, m.g = m.g, m.w
    return 1
end
-- Una pasada: quien está en el plan y no en su grupo va a él (Bring). A quien no está en el plan no se le toca, y quien
-- ya estuvo en su sitio y alguien movió luego se queda donde lo pusieron [+ARCHITECTURE.md]
local function Arrange()
    local r = PlanRaid()
    if not (r and IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))) then return end
    if InCombatLockdown() then arrange.later = true; return end
    local info = GetRaidRosterInfo
    if not (info and SetRaidSubgroup and SwapRaidSubgroup) then return end
    -- (el plan, por nombre; a quien el juego da sin apellido, por su nombre si en el plan no se repite)
    local want, first = {}, {}
    for g = 1, GROUPS do
        for _, n in ipairs(r.groups[g]) do
            local k = n:lower()
            local f = k:match("^[^%-]+")
            want[k], first[f] = g, first[f] == nil and k or false
        end
    end
    local placed, list, count, here = arrange.plan.placed, {}, {}, {}
    for g = 1, GROUPS do count[g] = 0 end
    for i = 1, GetNumGroupMembers() do
        local name, _, g = info(i)
        if count[g] then
            count[g] = count[g] + 1
            local k = type(name) == "string" and not HU.Secret(name) and name:lower()
            if k and not k:find("-", 1, true) then k = first[k] or k end
            if k then here[k] = true end
            if k and want[k] then
                if want[k] == g then placed[k] = g end
                list[#list + 1] = { i = i, k = k, g = g, w = want[k] }
            end
        end
    end
    -- (quien ha salido de la banda, al volver se coloca otra vez)
    for k in pairs(placed) do if not here[k] then placed[k] = nil end end
    -- (como mucho ARRANGE_MAX por pasada; ya en su sitio o colocado antes, no se mueve)
    local moves = 0
    for _, m in ipairs(list) do
        if moves < ARRANGE_MAX and not arrange.off and m.g ~= m.w and placed[m.k] ~= m.w then moves = moves + Bring(m, list, count, placed) end
    end
    -- (bloqueado: un aviso, una vez; luego ya no se pide ninguna pasada)
    if arrange.off then HU:Print(L("El juego no deja que el addon cambie a la gente de grupo en la banda: colócala a mano.")) end
end
-- (lo que llega seguido, una pasada: la primera señal la pide para dentro de ARRANGE_GAP s y las demás esperan a esa)
local function ArrangeSoon()
    if arrange.soon or arrange.off or not arrange.plan then return end
    arrange.soon = true
    HU.After(ARRANGE_GAP, function() arrange.soon = nil; Arrange() end)
end
-- (la raid de la que invito pasa a ser el plan durante PLAN_TTL; si ya lo era, solo se alarga)
local function SetPlan(e, r)
    local me, p = Me(), arrange.plan
    if not (p and p.id == e.id and p.name == r.name) then
        p = { id = e.id, name = r.name, who = me, placed = {} }
        for _, raids in pairs(HU.db.calRaids) do
            if type(raids) == "table" and type(raids.plan) == "table" and raids.plan.who == me then raids.plan = nil end
        end
        if not e.test and HU.db.calRaids[e.id] then HU.db.calRaids[e.id].plan = p end
        arrange.plan = p
    end
    p.untilT = time() + PLAN_TTL
    ArrangeSoon()
end
HU:On("PLAYER_REGEN_ENABLED", function() if arrange.later then arrange.later = nil; ArrangeSoon() end end)

HU:On("GROUP_ROSTER_UPDATE", function()
    for n, st in pairs(invites) do if st.s ~= "ok" and InGroup(n) then Mark(n, "ok") end end
    if ui and ui:IsShown() and selected then Paint() end
    ArrangeSoon()
end)

-- (invita a `names`, los de la raid r que dice el botón, y r pasa a ser el plan de la banda)
local function InviteRaid(e, r, names)
    local inv = C_PartyInfo and C_PartyInfo.InviteUnit
    if not inv then return end
    if IsInGroup() and not IsInRaid() and C_PartyInfo.ConvertToRaid then pcall(C_PartyInfo.ConvertToRaid) end
    local n, left = 0, 0
    local room = IsInRaid() and 40 or 4
    for _, name in ipairs(names) do
        if name ~= Me() then
            if InGroup(name) then
                invites[name] = { s = "ok", t = time() }
            elseif n < room then
                pcall(inv, HU:FullName(name) or name)
                invites[name] = { s = "wait", t = time() }
                n = n + 1
            else
                left = left + 1
            end
        end
    end
    -- (a los 90 s, quien no haya entrado: X)
    HU.After(90, function()
        for name, st in pairs(invites) do
            if st.s == "wait" and time() - st.t >= 85 and not InGroup(name) then Mark(name, "no") end
        end
    end)
    SetPlan(e, r)
    if left > 0 then
        HU:Print(string.format(L("Invitados %d. Cuando acepten, pulsa otra vez para invitar a los %d que faltan."), n, left))
    else
        HU:Print(string.format(L("Invitados %d a %s."), n, r.name))
    end
    Paint()
end
local function Status(name)
    local st = invites[name]
    if not st then return "" end
    return st.s == "ok" and ST_OK or st.s == "no" and ST_NO or ST_WAIT
end

-- Apuntarse (con un rol) o desapuntarse; al apuntarse se entra en una raid con sitio. Yo, en uno de verdad: primero a la
-- red (s<id>) y luego lo de mis raids
local function SetSignup(e, name, role)
    if not e.test and name == Me() then
        if not HU:ProposeSignup(e.id, role) then return end
        Rebuild()
        e = Find(e.id) or e
    end
    e.roles = e.roles or {}
    if role then
        e.signups[name], e.roles[name] = "yes", role
        AutoPlace(e, name)
    else
        e.signups[name], e.roles[name] = nil, nil
        for _, r in ipairs(e.raids or {}) do TakeOut(r, name) end
    end
end
-- (el botón: si ya voy, me quita; si no, pregunta el rol)
local function SignUp(e, owner)
    if e.signups[Me()] == "yes" then
        ui.confirm(L("¿Seguro que quieres salir del evento?"), function() SetSignup(e, Me(), nil); Paint() end)
        return
    end
    local myLv = UnitLevel and UnitLevel("player")
    if e.minLevel and type(myLv) == "number" and myLv < e.minLevel then
        return HU:Print(string.format(L("Este evento pide nivel %d o más."), e.minLevel))
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then SetSignup(e, Me(), lastRole or "DAMAGER"); Paint(); return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L("¿Con qué rol vas?"))
        local _, myClass = UnitClass("player")
        for _, role in ipairs(ROLES) do
            if CanRole(myClass, role) then
                root:CreateButton(RoleIcon(role, 16) .. "  " .. L(ROLE_NAME[role]), function()
                    lastRole = role
                    SetSignup(e, Me(), role)
                    Paint()
                end)
            end
        end
        root:CreateButton(L("Cancelar"), function() end)
    end)
end
-- (una lista con barra, otra vez arriba)
local function ScrollTop(sf)
    FauxScrollFrame_SetOffset(sf, 0)
    local bar = sf.ScrollBar or _G[sf:GetName() .. "ScrollBar"]
    if bar then bar:SetValue(0) end
end
-- (la raid que se ve en la ficha; lo elegido con Ctrl / Mayús se vacía)
local function PickRaid(i) raidPick, picks, lastPick = i, {}, nil end
local function OpenDetail(id)
    local other = selected ~= id
    selected = id
    if other then PickRaid(1); benchRole = nil; ScrollTop(ui.detail.benchScroll) end
    Paint()
end

---------------------------------------------------------------------------
-- Clic derecho en un evento mío, en su tarjeta o en su fila del día: editarlo o eliminarlo. En los de otros, nada [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- (eliminar: uno de verdad, su línea vacía a la red (Packs/Events.lua); uno de prueba, solo aquí. Fuera sus raids y su ficha)
local function DeleteEvent(id)
    local e = Find(id)
    if not (e and e.who == Me()) then return end
    if e.test then
        for k = #testEvents, 1, -1 do if testEvents[k].id == id then table.remove(testEvents, k) end end
    elseif not HU:ProposeEventDelete(id) then
        return HU:Print(L("No se ha podido eliminar el evento."))
    elseif e.pinned then
        -- (fuera también su fijado, para que no quede en la red)
        HU:ProposeEventPin(id, false)
    end
    HU.db.calRaids[id] = nil
    if selected == id then selected = nil end
    Rebuild()
    Paint()
end
-- (clic derecho en un evento mío: fijarlo arriba de Eventos para todos (o quitarlo), editarlo o eliminarlo. Uno de
-- prueba se fija solo aquí)
local function EventMenu(owner, id)
    local e = id and Find(id)
    if not (e and e.who == Me() and MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(e.title)
        root:CreateButton(e.pinned and L("Quitar de arriba") or L("Fijar arriba para todos"), function()
            local x = Find(id)
            if not x then return end
            if x.test then
                x.pinned = (not x.pinned) or nil
                Paint()
            elseif not HU:ProposeEventPin(id, not x.pinned) then
                HU:Print(L("No se ha podido guardar el evento."))
            end
        end)
        root:CreateButton(L("Editar evento"), function() local x = Find(id); if x then ui.newDlg.Open(nil, x) end end)
        root:CreateButton(L("Eliminar"), function()
            ui.confirm(L("¿Seguro que quieres eliminar el evento?"), function() DeleteEvent(id) end)
        end)
        root:CreateButton(L("Cancelar"), function() end)
    end)
end

---------------------------------------------------------------------------
-- La ficha del evento: sus raids (líder, banquillo, 8 grupos de 5)
---------------------------------------------------------------------------
local function PaintDetail()
    local d = ui.detail
    local e = selected and Find(selected)
    if not e then d:Hide(); return end
    e.raids = e.raids or {}
    d.titleText:SetText(e.title)
    d.icon:SetTexture(EventIcon(e))
    d.sub:SetText(KindText(e.kind) .. "   |cffe6e6ea" .. LongDay(e.t) .. ", " .. date("%H:%M", e.t) .. "|r   |cffa0a4ad"
        .. L("por") .. "|r " .. WhoText(e) .. "   |cff40ff40" .. Count(e) .. "|r |cffe6e6ea" .. L("van") .. "|r"
        .. (e.minLevel and ("   |cffa0a4ad" .. string.format(L("Nv. %d+"), e.minLevel) .. "|r") or ""))
    d.roles:SetText(RoleCounts(e, (function() local t = {} for n, v in pairs(e.signups) do if v == "yes" then t[#t + 1] = n end end return t end)()))
    -- (la descripción, debajo de esa línea: lo que ocupa baja la raya y todo lo de debajo; sin descripción, nada)
    local desc = e.desc or ""
    d.desc:SetText(desc)
    local h = desc ~= "" and math.min(d.desc:GetStringHeight(), DESC_LINES * DESC_LINE_H) or 0
    d.descH = h > 0 and (math.ceil(h) + 4) or 0
    d.desc:SetShown(d.descH > 0)
    d.rule:SetPoint("TOPLEFT", 10, -28 - d.descH); d.rule:SetPoint("TOPRIGHT", -10, -28 - d.descH)
    local classes = ClassMap()
    local manage = CanManage(e)
    local mine = e.signups[Me()] == "yes"
    d.join:Label(mine and ("|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t |cff40ff40" .. L("Apuntado") .. "|r") or L("Apuntarme"))
    d.join:Pick(mine)

    if raidPick > #e.raids then raidPick = #e.raids end
    if raidPick < 1 and #e.raids > 0 then raidPick = 1 end
    -- (pestañas de raid en filas de 7, bajo la descripción; «+ Añadir» va en el hueco siguiente. Con cada fila de más,
    -- la ventana crece 28 y todo lo de debajo baja 28, y lo mismo con lo que ocupa la descripción: así no se sale
    -- ni se monta)
    local canAdd = manage and #e.raids < MAX_RAIDS
    local used = #e.raids + (canAdd and 1 or 0)
    local shift = d.descH + (math.max(1, math.ceil(used / RAID_ROW)) - 1) * TAB_ROW_H
    d:SetHeight(DETAIL_H + shift)
    d.leaderBar:SetPoint("TOPLEFT", 176, -64 - shift)
    d.benchF:SetPoint("TOPLEFT", 12, -64 - shift)
    d.groupsF:SetPoint("TOPLEFT", 176, -100 - shift)
    d.noRaid:SetPoint("TOPLEFT", 186, -110 - shift)
    for k, b in ipairs(d.raidTabs) do
        local r = e.raids[k]
        if r then
            d.TabPoint(b, k)
            b:Label(r.name .. " (" .. #Members(r) .. ")")
            b:Pick(k == raidPick)
            b:Show()
        else
            b:Hide()
        end
    end
    if canAdd then d.TabPoint(d.addRaid, #e.raids + 1) end
    d.addRaid:SetShown(canAdd)
    local cur = e.raids[raidPick]
    d.noRaid:SetShown(cur == nil)
    d.groupsF:SetShown(cur ~= nil)
    d.leaderBar:SetShown(cur ~= nil)
    -- (Invitar a todos: solo el líder de esa raid; Quitar raid: quien creó el evento o el líder de esa raid)
    d.invite:SetShown(cur ~= nil and cur.leader == Me())
    d.delRaid:SetShown(cur ~= nil and (e.who == Me() or cur.leader == Me()))
    -- (convertir mi grupo en banda: solo el líder de esta raid, si está en grupo, no en banda, y lo lleva él)
    local amLeader = cur ~= nil and cur.leader == Me()
    local inRaid, inGroup = IsInRaid(), IsInGroup()
    d.convert:SetShown(amLeader)
    d.convert:SetEnabled(inGroup and not inRaid and UnitIsGroupLeader("player") and true or false)
    -- (con un rol elegido arriba del banquillo, solo los de ese rol; en la cabecera, cuántos de cuántos)
    local shown, free = BenchShown(e)
    -- (lo elegido con Ctrl / Mayús, solo de lo que se ve; quien no lleva esta raid no invita, y no elige)
    if amLeader then
        local seen = {}
        for _, n in ipairs(PickOrder(shown, cur)) do seen[n] = true end
        for n in pairs(picks) do if not seen[n] then picks[n] = nil end end
    else
        wipe(picks); lastPick = nil
    end
    if cur then
        local names, how = InviteTargets(e, cur)
        d.invite:Label(string.format((how == "picked" and L("Invitar seleccionados (%d)")) or (how == "TANK" and L("Invitar tanques (%d)"))
            or (how == "HEALER" and L("Invitar sanadores (%d)")) or (how == "DAMAGER" and L("Invitar daño (%d)"))
            or L("Invitar a todos (%d)"), #names))
        d.leaderBar.roles:SetText(RoleCounts(e, Members(cur)))
        d.leaderBar.text:SetText(L("Líder de la raid") .. ":  " .. (cur.leader and (CROWN .. ColorName(cur.leader, classes, RoleOf(e, cur.leader)) .. " " .. Status(cur.leader))
            or ("|cffa0a4ad" .. L("nadie (clic derecho en alguien: «Hacer líder»)") .. "|r")))
    end
    local levels = LevelMap()
    for _, b in ipairs(d.roleBtns) do b:Pick(b.role == benchRole) end
    d.benchHead:SetText(L("Sin raid") .. "  |cffa0a4ad(" .. (benchRole and (#shown .. "/") or "") .. #free .. ")|r")
    -- (con más de los que caben, la barra: las filas se estrechan para dejarle sitio)
    FauxScrollFrame_Update(d.benchScroll, #shown, BENCH_N, 18)
    local off = FauxScrollFrame_GetOffset(d.benchScroll)
    local w = #shown > BENCH_N and 122 or 142
    for i, b in ipairs(d.bench) do
        local n = shown[off + i]
        b.name = n
        b:SetWidth(w)
        b.fill:SetAlpha(1)
        b.pick:SetShown(n ~= nil and picks[n] == true)
        if n then
            local lv = levels[(HU:FullName(n) or n):lower()] or levels[n:lower()]
            b.text:SetText((lv and ("|cffa0a4ad" .. lv .. "|r ") or "") .. ColorName(n, classes, RoleOf(e, n)))
            b:Show()
        else
            b:Hide()
        end
    end
    d.place:SetShown(manage and #free > 0 and #e.raids > 0)
    d.place:Label(string.format(L("Colocar en raids (%d)"), #free))
    for gi, grp in ipairs(d.groups) do
        local list = cur and cur.groups[gi] or {}
        grp.label:SetText(string.format(L("Grupo %d"), gi) .. "  |cffa0a4ad" .. #list .. "/" .. PER_GROUP .. "|r")
        for si, slot in ipairs(grp.slots) do
            local n = list[si]
            slot.name = n
            slot.fill:SetShown(n ~= nil); slot.fill:SetAlpha(1)
            slot.pick:SetShown(n ~= nil and picks[n] == true)
            if n then
                slot.text:SetText((cur.leader == n and CROWN or "") .. ColorName(n, classes, RoleOf(e, n)))
                slot.status:SetText(Status(n))
            else
                slot.text:SetText("|cff5a5d66" .. (EMPTY or L("Vacío")) .. "|r")
                slot.status:SetText("")
            end
        end
    end
    -- (al líder de la raid, si no está en banda, el aviso en rojo en vez de la ayuda de arrastrar)
    if amLeader and not inRaid then
        d.hint:SetText("|cffff5050" .. (inGroup and L("Estás en grupo, no en banda: pulsa «Convertir en banda» antes de «Invitar a todos».")
            or L("No estás en banda: invita a alguien, pulsa «Convertir en banda» y luego «Invitar a todos».")) .. "|r")
    else
        d.hint:SetText(manage and L("Arrastra los nombres a otro grupo, a otra raid (su pestaña) o al banquillo. Clic derecho: más opciones.") or "")
    end
    d:Show()
    -- (lo que se cambia aquí, con la banda montándose, también se lleva a la banda)
    ArrangeSoon()
end

-- Clic derecho en un nombre: hacer líder, pasar a otra raid, sacar (al líder, nada de eso: no se mueve), susurrar
-- e invitar
local function NameMenu(owner, name)
    local e = selected and Find(selected)
    if not (e and name and MenuUtil and MenuUtil.CreateContextMenu) then return end
    local manage = CanManage(e)
    local cur = e.raids[raidPick]
    local isLeader = cur and cur.leader == name
    local inCur = cur and FindPos(cur, name) and not isLeader
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(HU:Short(name))
        if manage then
            if cur and not isLeader then
                root:CreateButton(L("Hacer líder de la raid"), function() SetLeader(e, cur, name); Paint() end)
            end
            local others = {}
            for _, r in ipairs(e.raids) do if not FindPos(r, name) then others[#others + 1] = r end end
            if #others > 0 and not isLeader then
                local sub = root:CreateButton(L("Mover a"))
                for _, r in ipairs(others) do
                    sub:CreateButton(r.name .. "  |cffa0a4ad(" .. #Members(r) .. ")|r", function() AddToRaid(e, r, name); Paint() end)
                end
            end
            if inCur then
                root:CreateButton(L("Sacar de la raid"), function() TakeOut(cur, name); Paint() end)
            end
        end
        root:CreateButton(L("Susurrar"), function() HU.WhisperTo(name) end)
        -- (invitar al grupo, uno a uno; desde el clic del menú, que el juego lo deja)
        root:CreateButton(L("Invitar al grupo"), function()
            local fn = C_PartyInfo and C_PartyInfo.InviteUnit
            if fn then pcall(fn, HU:FullName(name) or name) end
        end)
        root:CreateButton(L("Cancelar"), function() end)
    end)
end

-- Clic izquierdo en un nombre, quien lleva la raid: con Ctrl suma o quita a esa persona de lo elegido; con Mayús, el
-- tramo desde el último elegido (como «Mis encargos» de Comercio); solo, vacía lo elegido (sin elegidos, nada: lo de
-- siempre). Con elegidos, el botón de la raid invita solo a esos [+ARCHITECTURE.md]
local function PickName(name)
    local e = selected and Find(selected)
    local cur = e and e.raids[raidPick]
    if not (cur and cur.leader == Me()) then return end
    if IsControlKeyDown() then
        picks[name] = (not picks[name]) or nil
        lastPick = name
    elseif IsShiftKeyDown() then
        local order, a, b = PickOrder((BenchShown(e)), cur), nil, nil
        for k, n in ipairs(order) do
            if n == lastPick then a = k end
            if n == name then b = k end
        end
        if b then for k = math.min(a or b, b), math.max(a or b, b) do picks[order[k]] = true end end
        lastPick = name
    else
        picks, lastPick = {}, nil
    end
    PaintDetail()
end

-- «+ Añadir raid»: primero, quién la lleva (los que van), en la ventanita con buscador
local function AskLeader(owner)
    local e = selected and Find(selected)
    if not e then return end
    local names = {}
    for n, v in pairs(e.signups) do if v == "yes" then names[#names + 1] = n end end
    table.sort(names, function(a, b)
        local ra, rb = InAnyRaid(e, a) and 1 or 0, InAnyRaid(e, b) and 1 or 0
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    local classes = ClassMap()
    local entries = {}
    for _, n in ipairs(names) do
        local where = InAnyRaid(e, n)
        entries[#entries + 1] = { value = n, key = HU:Short(n):lower(),
            text = ColorName(n, classes, RoleOf(e, n)) .. (where and ("  |cff808080(" .. where.name .. ")|r") or "") }
    end
    ui.detail.picker.Open(owner, L("¿Quién lleva la nueva raid?"), entries, function(n)
        NewRaid(e, n)
        PickRaid(#e.raids)
        Paint()
    end)
end

local function BuildDetail(host)
    local d = DJWindow("GuildUnionCalendarDetail", host, 740, DETAIL_H, function() selected = nil; Paint() end)
    local cf = d.content
    -- (arriba a la izquierda, la imagen del evento, redonda)
    d.icon = RoundIcon(d, 30)
    d.icon:SetPoint("TOPLEFT", d, "TOPLEFT", 22, -12)
    d.sub = cf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.sub:SetPoint("TOPLEFT", 12, -10); d.sub:SetPoint("RIGHT", cf, "RIGHT", -12, 0)
    d.sub:SetJustifyH("LEFT"); d.sub:SetWordWrap(false)
    d.roles = C(cf:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), T.text)
    d.roles:SetPoint("TOPRIGHT", -12, -10)
    d.sub:SetPoint("RIGHT", d.roles, "LEFT", -10, 0)
    -- (la descripción, en varias líneas a todo lo ancho: 704 del panel menos los márgenes)
    d.desc = C(cf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.text)
    d.desc:SetPoint("TOPLEFT", 12, -28); d.desc:SetWidth(680)
    d.desc:SetJustifyH("LEFT"); d.desc:SetWordWrap(true); d.desc:SetMaxLines(DESC_LINES)
    d.descH = 0
    d.rule = Line(cf, 0.45); d.rule:SetPoint("TOPLEFT", 10, -28); d.rule:SetPoint("TOPRIGHT", -10, -28)
    -- (las raids: una pestaña por raid y «+ Añadir raid». Botones rojos del juego con su letra de siempre, que se lea
    -- «Raid 20 (40)» (Jorge, 24/11: «mejorar los botones de Raid 1, Raid 2…»); la elegida, negra (DJ.PickRed). 7 por fila
    -- de 92 + 4: 668 de ancho, cabe en los 704 del panel)
    d.raidTabs = {}
    function d.TabPoint(b, i)
        local col, row = (i - 1) % RAID_ROW, math.floor((i - 1) / RAID_ROW)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", cf, "TOPLEFT", 12 + col * (TAB_W + 4), -34 - d.descH - row * TAB_ROW_H)
    end
    for i = 1, MAX_RAIDS do
        local b = DJButton(cf, "", TAB_W, TAB_H)
        d.TabPoint(b, i)
        b.idx = i
        b:SetScript("OnClick", function() PickRaid(i); Paint() end)
        b:Hide()
        d.raidTabs[i] = b
    end
    -- (abre «¿Quién lleva la nueva raid?»; abierta, otro clic la cierra. Jorge, 25/11)
    d.addRaid = DJButton(cf, "+ " .. L("Añadir"), TAB_W, TAB_H)
    d.addRaid:SetScript("OnClick", function(s) if d.picker:IsShown() then d.picker:Hide() else AskLeader(s) end end)
    -- (el líder, siempre arriba de los grupos: franja de cabecera)
    local lb = CreateFrame("Frame", nil, cf, "BackdropTemplate")
    lb:SetPoint("TOPLEFT", 176, -64); lb:SetPoint("RIGHT", cf, "RIGHT", -12, 0); lb:SetHeight(28)
    Panel(lb, T.header, T.border, 10, 2)
    Parchment(lb, 0.16)
    lb.text = C(lb:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.title)
    Big(lb.text, 14)
    lb.text:SetPoint("LEFT", 10, 0)
    lb.roles = C(lb:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), T.text)
    lb.roles:SetPoint("RIGHT", -10, 0)
    d.leaderBar = lb
    d.noRaid = C(cf:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), T.muted)
    d.noRaid:SetPoint("TOPLEFT", 186, -110)
    d.noRaid:SetText(L("Todavía no hay raids. Quien organiza las crea con «+ Añadir raid»."))

    -- (arrastrar: un rótulo sigue al ratón y, al soltar, va al hueco, al grupo, a la pestaña de otra raid, a la barra
    -- del líder o al banquillo de debajo. Al líder no se le arrastra: se cambia con «Hacer líder de la raid»)
    local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ghost:SetSize(120, 22); ghost:SetFrameStrata("TOOLTIP")
    Panel(ghost, T.rowSel, T.title, 10, 2)
    ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ghost.text:SetPoint("CENTER")
    ghost:Hide()
    ghost:SetScript("OnUpdate", function(s)
        local x, y = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale()
        s:ClearAllPoints(); s:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc + 50, y / sc - 12)
    end)
    local function DragStart(btn)
        local e = selected and Find(selected)
        if not (btn.name and e and CanManage(e) and e.raids[raidPick]) then return end
        if LeadsAny(e, btn.name) then
            return HU:Print(L("El líder no se mueve: para cambiarlo, clic derecho en otro y «Hacer líder de la raid»."))
        end
        dragName = btn.name
        ghost.text:SetText(btn.text:GetText()); ghost:Show()
        btn.text:SetText(""); btn.fill:SetAlpha(0); btn.pick:Hide(); btn.status:SetText("")
    end
    local function DragStop()
        ghost:Hide()
        local name = dragName
        dragName = nil
        local e = selected and Find(selected)
        local r = e and e.raids[raidPick]
        if not (name and r) then Paint(); return end
        if d.leaderBar:IsMouseOver() then SetLeader(e, r, name); Paint(); return end
        for _, tab in ipairs(d.raidTabs) do
            local to = tab.idx and e.raids[tab.idx]
            if tab:IsShown() and tab:IsMouseOver() and to then
                if to ~= r then AddToRaid(e, to, name) end
                Paint(); return
            end
        end
        for gi, grp in ipairs(d.groups) do
            for si, slot in ipairs(grp.slots) do
                if slot:IsMouseOver() then Place(e, r, name, gi, si); Paint(); return end
            end
            if grp:IsMouseOver() then Place(e, r, name, gi, #r.groups[gi] + 1); Paint(); return end
        end
        if d.benchF:IsMouseOver() then TakeOut(r, name) end
        Paint()
    end
    local function Slot(parent, w)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(w, 17)
        b.fill = b:CreateTexture(nil, "BACKGROUND")
        b.fill:SetAllPoints(); b.fill:SetColorTexture(T.rowSel[1], T.rowSel[2], T.rowSel[3], 0.55)
        -- (elegido con Ctrl / Mayús: un fondo azul por encima, como las filas elegidas de Comercio)
        b.pick = b:CreateTexture(nil, "BORDER")
        b.pick:SetAllPoints(); b.pick:SetColorTexture(0.25, 0.55, 1, 0.35); b.pick:Hide()
        b:SetHighlightTexture(ROW_HL, "ADD")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.text:SetPoint("LEFT", 5, 0); b.text:SetPoint("RIGHT", -18, 0); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
        b.status = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.status:SetPoint("RIGHT", -3, 0)
        -- (clic derecho, el menú; el izquierdo, elegir con Ctrl / Mayús; arrastrar con el izquierdo, como siempre)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnClick", function(s, button)
            if not s.name then return end
            if button == "LeftButton" then PickName(s.name) else NameMenu(s, s.name) end
        end)
        b:SetScript("OnDragStart", DragStart)
        b:SetScript("OnDragStop", DragStop)
        return b
    end
    -- (izquierda: el banquillo, panel lateral; 12 a la vista y, si hay más, la barra a su derecha)
    local bench = CreateFrame("Frame", nil, cf, "BackdropTemplate")
    bench:SetPoint("TOPLEFT", 12, -64); bench:SetPoint("BOTTOMLEFT", 12, 10); bench:SetWidth(156)
    Panel(bench, T.panel, T.border, 12, 3)
    Parchment(bench, 0.13)
    d.benchF = bench
    d.benchHead = C(bench:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.title)
    d.benchHead:SetPoint("TOPLEFT", 9, -8)
    local bl = Line(bench, 0.45); bl:SetPoint("TOPLEFT", 6, -24); bl:SetPoint("TOPRIGHT", -6, -24)
    -- (debajo de la raya, el filtro por rol: Todos, tanque, sanador y daño; el elegido, negro. Jorge, 24/11. De 22 de alto,
    -- como los demás botones rojos, y el icono de 14 aparte, centrado: en el texto de uno de 18 se salía del botón. Jorge,
    -- 25/11: «el icono sobresale del botón») [+ARCHITECTURE.md]
    d.roleBtns = {}
    local x = 7
    for _, it in ipairs({ { false, 44 }, { "TANK", 28 }, { "HEALER", 28 }, { "DAMAGER", 28 } }) do
        local b = DJButton(bench, it[1] and "" or L("Todos"), it[2], 22)
        b:SetPoint("TOPLEFT", x, -28)
        x = x + it[2] + 4
        b.role = it[1] or nil
        b:SetScript("OnClick", function(s) benchRole = s.role; ScrollTop(d.benchScroll); PaintDetail() end)
        if b.role then
            local c = ROLE_TC[b.role]
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(14, 14); b.icon:SetPoint("CENTER", 0, 0)
            b.icon:SetTexture(ROLE_TEX); b.icon:SetTexCoord(c[1] / 64, c[2] / 64, c[3] / 64, c[4] / 64)
            b:SetScript("OnEnter", function(s)
                GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:SetText(L(ROLE_NAME[s.role])); GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        d.roleBtns[#d.roleBtns + 1] = b
    end
    -- (las filas, 4 por debajo de los botones: las 12 siguen cabiendo encima de «Colocar en raids»)
    local bsf = CreateFrame("ScrollFrame", "GuildUnionCalendarBenchScroll", bench, "FauxScrollFrameTemplate")
    bsf:SetPoint("TOPLEFT", 7, -54); bsf:SetSize(122, BENCH_N * 18)
    bsf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, 18, PaintDetail) end)
    d.benchScroll = bsf
    d.bench = {}
    for i = 1, BENCH_N do
        local b = Slot(bench, 142)
        b:SetPoint("TOPLEFT", 7, -54 - (i - 1) * 18)
        b.fill:SetColorTexture(T.row[1], T.row[2], T.row[3], 0.7)
        b.text:SetPoint("RIGHT", -3, 0) -- (en el banquillo no hay marca de invitación: el nombre, a todo lo ancho)
        d.bench[i] = b
    end
    d.place = DJButton(bench, "", 140, 22)
    d.place:SetPoint("BOTTOM", 0, 8)
    d.place:SetScript("OnClick", function() local e = selected and Find(selected); if e then PlaceBench(e); Paint() end end)
    -- (derecha: los 8 grupos de 5, cada uno un panel)
    local gf = CreateFrame("Frame", nil, cf)
    gf:SetPoint("TOPLEFT", 176, -100); gf:SetPoint("BOTTOMRIGHT", -12, 26)
    d.groupsF = gf
    local gw = 132
    local gh = 6 + PER_GROUP * 18
    d.groups = {}
    for gi = 1, GROUPS do
        local col, row = (gi - 1) % 4, math.floor((gi - 1) / 4)
        local grp = CreateFrame("Frame", nil, gf, "BackdropTemplate")
        grp:SetSize(gw - 6, gh)
        grp:SetPoint("TOPLEFT", gf, "TOPLEFT", col * gw, -14 - row * (gh + 22))
        Panel(grp, T.row, T.border, 10, 2)
        grp.label = C(grp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), T.title)
        grp.label:SetPoint("BOTTOMLEFT", grp, "TOPLEFT", 3, 2)
        grp.slots = {}
        for si = 1, PER_GROUP do
            local s = Slot(grp, gw - 14)
            s:SetPoint("TOPLEFT", 4, -3 - (si - 1) * 18)
            grp.slots[si] = s
        end
        d.groups[gi] = grp
    end
    d.hint = C(cf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    d.hint:SetPoint("BOTTOMLEFT", 178, 8)
    -- (debajo de los grupos: Invitar a todos (o a los de un rol, o a los elegidos: 190 de ancho, que quepa «Invitar
    -- seleccionados (40)»), Quitar raid y Convertir en banda; Apuntarme, abajo a la derecha)
    d.invite = DJButton(cf, "", 190, 24)
    d.invite:SetPoint("TOPLEFT", d.groups[5], "BOTTOMLEFT", 0, -10)
    d.invite:SetScript("OnClick", function()
        local e = selected and Find(selected)
        local r = e and e.raids[raidPick]
        if r then InviteRaid(e, r, (InviteTargets(e, r))) end
    end)
    d.invite:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(L("Ctrl+clic o Mayús+clic en los nombres: invitar solo a esos."), nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    d.invite:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.delRaid = DJButton(cf, L("Quitar raid"), 110, 24)
    d.delRaid:SetPoint("LEFT", d.invite, "RIGHT", 6, 0)
    d.convert = DJButton(cf, L("Convertir en banda"), 150, 24)
    d.convert:SetPoint("LEFT", d.delRaid, "RIGHT", 6, 0)
    d.convert:SetScript("OnClick", function()
        if C_PartyInfo and C_PartyInfo.ConvertToRaid then pcall(C_PartyInfo.ConvertToRaid) end
    end)
    d.delRaid:SetScript("OnClick", function()
        local e = selected and Find(selected)
        if e and e.raids[raidPick] then table.remove(e.raids, raidPick); PickRaid(math.max(1, raidPick - 1)); Paint() end
    end)
    -- Ventanita para elegir a alguien de una lista larga: título, buscador, filas con barra y Cancelar
    local pk = CreateFrame("Frame", "GuildUnionCalendarPicker", d, "BackdropTemplate")
    pk:SetSize(240, 326); pk:SetFrameStrata("FULLSCREEN_DIALOG"); pk:EnableMouse(true)
    Panel(pk, T.frame, T.border, 12, 3)
    pk:Hide()
    pk.title = C(pk:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.title)
    pk.title:SetPoint("TOPLEFT", 10, -9); pk.title:SetPoint("RIGHT", pk, "RIGHT", -10, 0); pk.title:SetJustifyH("LEFT")
    pk.search = CreateFrame("EditBox", "GuildUnionCalendarPickerSearch", pk, "SearchBoxTemplate")
    pk.search:SetSize(216, 20); pk.search:SetPoint("TOPLEFT", 14, -28)
    local PK_ROWS = 12
    local sf = CreateFrame("ScrollFrame", "GuildUnionCalendarPickerScroll", pk, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -54); sf:SetSize(204, PK_ROWS * 18)
    pk.rows = {}
    for i = 1, PK_ROWS do
        local b = CreateFrame("Button", nil, pk)
        b:SetSize(204, 18); b:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * 18)
        b:SetHighlightTexture(ROW_HL, "ADD")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.text:SetPoint("LEFT", 6, 0); b.text:SetPoint("RIGHT", -4, 0); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
        b:SetScript("OnClick", function(s) if s.value and pk.onPick then local f = pk.onPick; pk:Hide(); f(s.value) end end)
        pk.rows[i] = b
    end
    pk.empty = C(pk:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    pk.empty:SetPoint("TOP", sf, "TOP", 0, -20); pk.empty:SetText(L("Nadie encaja."))
    function pk.Refresh()
        local q = (pk.search:GetText() or ""):lower()
        local list = {}
        for _, en in ipairs(pk.entries or {}) do
            if q == "" or en.key:find(q, 1, true) then list[#list + 1] = en end
        end
        FauxScrollFrame_Update(sf, #list, PK_ROWS, 18)
        local off = FauxScrollFrame_GetOffset(sf)
        for i, b in ipairs(pk.rows) do
            local en = list[off + i]
            b.value = en and en.value
            if en then b.text:SetText(en.text); b:Show() else b:Hide() end
        end
        pk.empty:SetShown(#list == 0)
    end
    sf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, 18, pk.Refresh) end)
    pk.search:HookScript("OnTextChanged", function() FauxScrollFrame_SetOffset(sf, 0); pk.Refresh() end)
    local cancel = DJButton(pk, L("Cancelar"), 120, 22)
    cancel:SetPoint("BOTTOM", 0, 10)
    cancel:SetScript("OnClick", function() pk:Hide() end)
    function pk.Open(owner, title, entries, onPick)
        pk.title:SetText(title); pk.entries, pk.onPick = entries, onPick
        pk:ClearAllPoints(); pk:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
        pk.search:SetText(""); FauxScrollFrame_SetOffset(sf, 0)
        pk:Show(); pk.Refresh(); pk.search:SetFocus()
    end
    -- (pinchar fuera la cierra: una capa invisible de toda la pantalla, por debajo de ella, como en la ventana de nuevo
    -- evento. Otro clic en «+ Añadir» cae en la capa y también la cierra. Jorge, 25/11)
    local catcher = CreateFrame("Button", nil, d)
    catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("FULLSCREEN_DIALOG"); catcher:SetFrameLevel(1)
    catcher:RegisterForClicks("AnyDown"); catcher:Hide()
    catcher:SetScript("OnClick", function() pk:Hide() end)
    pk:SetFrameLevel(20)
    pk:HookScript("OnShow", function() catcher:Show() end)
    pk:HookScript("OnHide", function() catcher:Hide() end)
    pk.catcher = catcher
    d:HookScript("OnHide", function() pk:Hide() end)
    d.picker = pk

    d.join = DJButton(d, L("Apuntarme"), 140, 24)
    d.join:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -18, 14)
    d.join:SetScript("OnClick", function(s) local e = selected and Find(selected); if e then SignUp(e, s) end end)
    return d
end

---------------------------------------------------------------------------
-- Eventos: una tarjeta por línea, a todo lo ancho, como las de las mazmorras del Dungeon Journal [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local function PaintCards()
    local list = Upcoming()
    FauxScrollFrame_Update(ui.scroll, #list, CARD_N, CARD_H + CARD_GAP)
    -- (con barra, la zona de las tarjetas deja su hueco a la derecha dentro del panel: el panel sigue centrado)
    local inset = #list > CARD_N and 30 or 8
    if ui.cardArea.inset ~= inset then
        ui.cardArea.inset = inset
        ui.cardArea:SetPoint("BOTTOMRIGHT", ui.list, "BOTTOMRIGHT", -inset, 8)
    end
    local off = FauxScrollFrame_GetOffset(ui.scroll)
    for i, card in ipairs(ui.cards) do
        local e = list[off + i]
        card.id = e and e.id
        if e then
            local r, g, b = KindRGB(e.kind)
            card.wash:SetColorTexture(r, g, b, 0.10)
            card.icon:SetTexture(EventIcon(e))
            -- (fijado: con la estrella delante)
            card.title:SetText((e.pinned and "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14:14|t " or "") .. e.title)
            card.kind:SetText(KindText(e.kind) .. "  |cffe6e6ea" .. date("%H:%M", e.t) .. "|r"
                .. (e.minLevel and ("  |cffa0a4ad" .. string.format(L("Nv. %d+"), e.minLevel) .. "|r") or ""))
            card.num:SetText(tonumber(date("%d", e.t)))
            card.date:SetText(L(DAYS[WeekDay(e.t)]) .. "\n" .. L(MONTHS[tonumber(date("%m", e.t))]))
            card.who:SetText("|cffa0a4ad" .. L("por") .. "|r " .. WhoText(e))
            card.going:SetText((e.signups[Me()] == "yes" and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t " or "")
                .. Count(e) .. " " .. L("van"))
            local goingNames = {}
            for n, v in pairs(e.signups) do if v == "yes" then goingNames[#goingNames + 1] = n end end
            card.roles:SetText(RoleCounts(e, goingNames))
            local mine = e.signups[Me()] == "yes"
            card.join:Label(mine and ("|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t |cff40ff40" .. L("Apuntado") .. "|r") or L("Apuntarme"))
            card.join:Pick(mine)
            card:Show()
        else
            card:Hide()
        end
    end
    ui.empty:SetShown(#list == 0)
end

---------------------------------------------------------------------------
-- Calendario: el mes en casillas de panel; a la derecha, los eventos del día elegido
---------------------------------------------------------------------------
local function PaintMonth()
    local g = ui.grid
    local first = time({ year = year, month = month, day = 1, hour = 12 })
    local lead = WeekDay(first) - 1
    local nextM = time({ year = month == 12 and year + 1 or year, month = month % 12 + 1, day = 1, hour = 12 })
    local days = tonumber(date("%d", nextM - 86400))
    ui.monthTitle:SetText((L(MONTHS[month]):gsub("^%l", string.upper)) .. " " .. year)
    local w, h = g:GetWidth(), g:GetHeight()
    if type(w) ~= "number" or w <= 0 then w = 360 end
    if type(h) ~= "number" or h <= 0 then h = 220 end
    local weeks = math.ceil((lead + days) / 7)
    local cw, ch = math.floor(w / 7), math.floor((h - 18) / weeks)
    for i, l in ipairs(g.dayNames) do
        l:ClearAllPoints(); l:SetPoint("TOPLEFT", g, "TOPLEFT", (i - 1) * cw, -2); l:SetWidth(cw)
    end
    local today = DayKey(time())
    local byDay = {}
    for _, e in ipairs(events) do
        local k = DayKey(e.t)
        byDay[k] = byDay[k] or {}
        table.insert(byDay[k], e)
    end
    for i, cell in ipairs(g.cells) do
        local col, rowN = (i - 1) % 7, math.floor((i - 1) / 7)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", g, "TOPLEFT", col * cw, -18 - rowN * ch)
        cell:SetSize(cw - 2, ch - 2)
        local d = i - lead
        if d >= 1 and d <= days and i <= weeks * 7 then
            local key = string.format("%04d-%02d-%02d", year, month, d)
            cell.key = key
            cell.num:SetText(d)
            local list = byDay[key] or {}
            table.sort(list, function(a, b) return a.t < b.t end)
            -- (cuántos eventos tiene el día: «+N evento(s)» debajo del número; el color del primero, un
            -- cuadradito arriba a la derecha)
            cell.ev:SetText(#list == 0 and "" or ("|cffffd100+" .. #list .. " " .. (#list == 1 and L("evento") or L("eventos")) .. "|r"))
            if #list > 0 then cell.mark:SetColorTexture(KindRGB(list[1].kind)); cell.mark:Show() else cell.mark:Hide() end
            local bg = key == pickedDay and T.rowSel or T.row
            local bd = key == today and T.title or T.border
            cell:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            cell:SetBackdropBorderColor(bd[1], bd[2], bd[3], 1)
            cell:Show()
        else
            cell.key = nil
            cell:Hide()
        end
    end
end

local function PaintDay()
    local s = ui.side
    for _, b in ipairs(s.dayBtns) do b:Hide() end
    local list = pickedDay and OnDay(pickedDay) or {}
    -- (con más de 5, la barra: las filas se estrechan para dejarle sitio)
    FauxScrollFrame_Update(s.scroll, #list, DAY_N, DAY_H)
    local inset = #list > DAY_N and 30 or 6
    if s.inset ~= inset then
        s.inset = inset
        for _, b in ipairs(s.dayBtns) do b:SetPoint("RIGHT", s, "RIGHT", -inset, 0) end
    end
    if not pickedDay then
        s.title:SetText(L("Calendario"))
        s.info:SetText(L("Elige un día para ver sus eventos."))
        return
    end
    local y, m, d = pickedDay:match("(%d+)-(%d+)-(%d+)")
    local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    s.title:SetText(LongDay(t))
    s.info:SetText(#list == 0 and L("No hay eventos este día.") or "")
    local off = FauxScrollFrame_GetOffset(s.scroll)
    for i, b in ipairs(s.dayBtns) do
        local ev = list[off + i]
        if ev then
            b.id = ev.id
            b.icon:SetTexture(EventIcon(ev))
            b.text:SetText(ev.title)
            b.sub:SetText(date("%H:%M", ev.t) .. "  " .. KindText(ev.kind) .. "  |cff40ff40" .. Count(ev) .. "|r " .. L("van"))
            b:Show()
        end
    end
end

function Paint()
    if not (ui and ui:IsShown()) then return end
    if dirty then Rebuild() end
    for k, b in pairs(ui.viewBtns) do b:Pick(k == view) end
    ui.list:SetShown(view == "list")
    ui.month:SetShown(view == "month")
    ui.side:SetShown(view == "month")
    if view == "list" then PaintCards() else PaintMonth(); PaintDay() end
    ui.new:SetEnabled(HU:CanMakeEvents() or ui.testOn == true)
    PaintDetail()
end

---------------------------------------------------------------------------
-- Nuevo evento: título, tipo, imagen, día, hora, nivel mínimo y descripción. La misma ventana edita uno mío
-- (d.Open(nil, evento)): «Editar evento», todo puesto y «Guardar» [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local function BuildNewDialog(host)
    local d = DJWindow("GuildUnionCalendarNew", host, 380, 420)
    d.titleText:SetText(L("Nuevo evento"))
    local cf = d.content
    local function Label(text, x, y)
        local l = C(cf:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.title)
        l:SetPoint("TOPLEFT", x, y); l:SetText(text)
        return l
    end
    Label(L("Título:"), 12, -12)
    d.title = HU.NewEditBox(cf, 310); d.title:SetPoint("TOPLEFT", 18, -28); d.title:SetMaxLetters(40)
    Label(L("Tipo:"), 12, -58)
    d.kindBtns = {}
    local prev
    for _, k in ipairs({ KIND.raid, KIND.pvp, KIND.social }) do
        local b = DJButton(cf, L(k[2]), 100, 22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT", 10, -74) end
        b:SetScript("OnClick", function()
            d.kind = k[1]; d.PaintKinds()
            if not d.iconCustom then d.icon = KindIcon(d.kind); d.PaintIcons() end
        end)
        d.kindBtns[k[1]] = b
        prev = b
    end
    function d.PaintKinds() for key, b in pairs(d.kindBtns) do b:Pick(d.kind == key) end end
    Label(L("Imagen:"), 12, -104)
    -- (la elegida, en grande; al lado, el botón que abre la rejilla. Siempre hay una: la del tipo, si no se elige)
    local pv = CreateFrame("Button", nil, cf)
    pv:SetSize(36, 36); pv:SetPoint("TOPLEFT", 12, -120)
    pv:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    pv.tex = pv:CreateTexture(nil, "ARTWORK"); pv.tex:SetAllPoints()
    d.iconPrev = pv
    local choose = DJButton(cf, L("Elegir imagen"), 150, 24)
    choose:SetPoint("LEFT", pv, "RIGHT", 10, 0)
    -- (la rejilla: 8 x 4 a la vista y barra para ver el resto)
    local G_COLS, G_ROWS = 8, 4
    local grid = CreateFrame("Frame", nil, d, "BackdropTemplate")
    grid:SetSize(G_COLS * 40 + 14 + 22, G_ROWS * 40 + 14); grid:SetFrameStrata("FULLSCREEN_DIALOG"); grid:EnableMouse(true)
    grid:SetPoint("TOPLEFT", pv, "BOTTOMLEFT", 0, -4)
    Panel(grid, T.frame, T.border, 12, 3)
    grid:Hide()
    local gsf = CreateFrame("ScrollFrame", "GuildUnionCalendarIconScroll", grid, "FauxScrollFrameTemplate")
    gsf:SetPoint("TOPLEFT", 7, -7); gsf:SetSize(G_COLS * 40, G_ROWS * 40)
    d.iconBtns = {}
    for k = 1, G_COLS * G_ROWS do
        local b = CreateFrame("Button", nil, grid)
        b:SetSize(36, 36)
        b:SetPoint("TOPLEFT", gsf, "TOPLEFT", ((k - 1) % G_COLS) * 40, -math.floor((k - 1) / G_COLS) * 40)
        b.tex = b:CreateTexture(nil, "ARTWORK"); b.tex:SetAllPoints()
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.sel = b:CreateTexture(nil, "OVERLAY")
        b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight"); b.sel:SetBlendMode("ADD"); b.sel:SetAllPoints(); b.sel:Hide()
        b:SetScript("OnClick", function(sf2)
            if not sf2.path then return end
            d.icon, d.iconCustom = sf2.path, true; grid:Hide(); d.PaintIcons()
        end)
        d.iconBtns[k] = b
    end
    function grid.Paint()
        FauxScrollFrame_Update(gsf, math.ceil(#EVENT_ICONS / G_COLS), G_ROWS, 40)
        local off = FauxScrollFrame_GetOffset(gsf) * G_COLS
        for k, b in ipairs(d.iconBtns) do
            local name = EVENT_ICONS[off + k]
            b.path = name and ("Interface\\Icons\\" .. name)
            if name then b.tex:SetTexture(b.path); b.sel:SetShown(b.path == d.icon); b:Show() else b:Hide() end
        end
    end
    gsf:SetScript("OnVerticalScroll", function(sb, offset) FauxScrollFrame_OnVerticalScroll(sb, offset, 40, grid.Paint) end)
    -- (pinchar fuera de una ventanita la cierra: una capa invisible que cubre la pantalla, debajo de ellas)
    local catcher = CreateFrame("Button", nil, d)
    catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("FULLSCREEN_DIALOG"); catcher:SetFrameLevel(1)
    catcher:RegisterForClicks("AnyDown"); catcher:Hide()
    catcher:SetScript("OnClick", function() d.ClosePopups() end)
    local function Watch(p)
        p:SetFrameLevel(20)
        p:HookScript("OnShow", function() catcher:Show() end)
        p:HookScript("OnHide", function()
            for _, q in ipairs(d.popups) do if q:IsShown() then return end end
            catcher:Hide()
        end)
    end
    d.WatchPopup = Watch
    -- (las ventanitas de la ventana: abrir una cierra las otras)
    d.popups = { grid }
    Watch(grid)
    function d.ClosePopups(keep) for _, p in ipairs(d.popups) do if p ~= keep then p:Hide() end end end
    local function Toggle()
        d.ClosePopups(grid)
        if grid:IsShown() then grid:Hide() else grid:Show(); grid.Paint() end
    end
    choose:SetScript("OnClick", Toggle)
    pv:SetScript("OnClick", Toggle)
    d:HookScript("OnHide", function() grid:Hide() end)
    function d.PaintIcons()
        pv.tex:SetTexture(d.icon)
        if grid:IsShown() then grid.Paint() end
    end
    Label(L("Día:"), 12, -166)
    d.dayBtn = DJButton(cf, "", 104, 22); d.dayBtn:SetPoint("TOPLEFT", 12, -182)
    Label(L("Hora:"), 126, -166)
    d.hourBtn = DJButton(cf, "", 80, 22); d.hourBtn:SetPoint("TOPLEFT", 126, -182)
    -- (lo elegido: año, mes, día, hora y minuto)
    function d.PaintWhen()
        local t = time({ year = d.y, month = d.m, day = d.dd, hour = 12 })
        d.dayBtn:Label(L(DAYS_ABBR[WeekDay(t)]) .. " " .. date("%d/%m", t))
        d.hourBtn:Label(string.format("%02d:%02d", d.hh, d.mi))
    end
    -- Calendario pequeño para el día: < mes >, L M X J V S D y los días (hoy con borde dorado; el elegido, oscuro)
    local dp = CreateFrame("Frame", nil, d, "BackdropTemplate")
    dp:SetSize(7 * 28 + 14, 30 + 16 + 6 * 22 + 10); dp:SetFrameStrata("FULLSCREEN_DIALOG"); dp:EnableMouse(true)
    dp:SetPoint("TOPLEFT", d.dayBtn, "BOTTOMLEFT", 0, -4)
    Panel(dp, T.frame, T.border, 12, 3)
    dp:Hide()
    table.insert(d.popups, dp); d.WatchPopup(dp)
    dp.title = C(dp:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.title)
    dp.title:SetPoint("TOP", 0, -10)
    local function MonthArrow(dir, point, x)
        local b = DJButton(dp, dir < 0 and "<" or ">", 24, 20)
        b:SetPoint(point, x, -6)
        b:SetScript("OnClick", function()
            dp.m = dp.m + dir
            if dp.m < 1 then dp.m, dp.y = 12, dp.y - 1 elseif dp.m > 12 then dp.m, dp.y = 1, dp.y + 1 end
            dp.Paint()
        end)
    end
    MonthArrow(-1, "TOPLEFT", 7)
    MonthArrow(1, "TOPRIGHT", -7)
    for k = 1, 7 do
        local l = C(dp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), T.muted)
        l:SetPoint("TOPLEFT", 7 + (k - 1) * 28, -32); l:SetWidth(26); l:SetJustifyH("CENTER"); l:SetText(L(DAYS_SHORT[k]))
    end
    dp.cells = {}
    for k = 1, 42 do
        local b = DJButton(dp, "", 26, 20)
        b:SetPoint("TOPLEFT", 7 + ((k - 1) % 7) * 28, -46 - math.floor((k - 1) / 7) * 22)
        b:SetScript("OnClick", function(sf)
            d.y, d.m, d.dd = dp.y, dp.m, sf.day
            dp:Hide(); d.PaintWhen()
        end)
        dp.cells[k] = b
    end
    function dp.Paint()
        dp.title:SetText((L(MONTHS[dp.m]):gsub("^%l", string.upper)) .. " " .. dp.y)
        local first = time({ year = dp.y, month = dp.m, day = 1, hour = 12 })
        local lead = WeekDay(first) - 1
        local nextM = time({ year = dp.m == 12 and dp.y + 1 or dp.y, month = dp.m % 12 + 1, day = 1, hour = 12 })
        local days = tonumber(date("%d", nextM - 86400))
        local now = date("*t")
        for k, b in ipairs(dp.cells) do
            local day = k - lead
            if day >= 1 and day <= days then
                b.day = day
                local isToday = now.year == dp.y and now.month == dp.m and now.day == day
                b:Label(isToday and ("|cffffd100" .. day .. "|r") or tostring(day))
                b:Pick(d.y == dp.y and d.m == dp.m and d.dd == day)
                b:Show()
            else
                b:Hide()
            end
        end
    end
    d.dayBtn:SetScript("OnClick", function()
        if dp:IsShown() then dp:Hide() return end
        d.ClosePopups(dp)
        dp.y, dp.m = d.y, d.m
        dp.Paint(); dp:Show()
    end)
    -- Lista de horas (de 15 en 15), con barra y la elegida marcada; se abre por la elegida
    local TP_ROWS, TIMES = 8, {}
    for h = 0, 23 do for m = 0, 45, 15 do TIMES[#TIMES + 1] = { h, m } end end
    local tp = CreateFrame("Frame", nil, d, "BackdropTemplate")
    tp:SetSize(110, TP_ROWS * 20 + 14); tp:SetFrameStrata("FULLSCREEN_DIALOG"); tp:EnableMouse(true)
    tp:SetPoint("TOPLEFT", d.hourBtn, "BOTTOMLEFT", 0, -4)
    Panel(tp, T.frame, T.border, 12, 3)
    tp:Hide()
    table.insert(d.popups, tp); d.WatchPopup(tp)
    local tsf = CreateFrame("ScrollFrame", "GuildUnionCalendarTimeScroll", tp, "FauxScrollFrameTemplate")
    tsf:SetPoint("TOPLEFT", 7, -7); tsf:SetSize(72, TP_ROWS * 20)
    tp.rows = {}
    for k = 1, TP_ROWS do
        local b = CreateFrame("Button", nil, tp)
        b:SetSize(72, 20); b:SetPoint("TOPLEFT", tsf, "TOPLEFT", 0, -(k - 1) * 20)
        b:SetHighlightTexture(ROW_HL, "ADD")
        b.sel = b:CreateTexture(nil, "BACKGROUND"); b.sel:SetAllPoints()
        b.sel:SetColorTexture(T.rowSel[1], T.rowSel[2], T.rowSel[3], 0.9)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.text:SetPoint("CENTER")
        b:SetScript("OnClick", function(sf2) d.hh, d.mi = sf2.h, sf2.m; tp:Hide(); d.PaintWhen() end)
        tp.rows[k] = b
    end
    function tp.Paint()
        FauxScrollFrame_Update(tsf, #TIMES, TP_ROWS, 20)
        local off = FauxScrollFrame_GetOffset(tsf)
        for k, b in ipairs(tp.rows) do
            local t = TIMES[off + k]
            b.h, b.m = t[1], t[2]
            local on = t[1] == d.hh and t[2] == d.mi
            b.sel:SetShown(on)
            b.text:SetText((on and "|cffffd100" or "") .. string.format("%02d:%02d", t[1], t[2]) .. (on and "|r" or ""))
        end
    end
    tsf:SetScript("OnVerticalScroll", function(sb, offset) FauxScrollFrame_OnVerticalScroll(sb, offset, 20, tp.Paint) end)
    d.hourBtn:SetScript("OnClick", function()
        if tp:IsShown() then tp:Hide() return end
        d.ClosePopups(tp)
        -- (se abre con la elegida a la vista)
        local idx = d.hh * 4 + math.floor(d.mi / 15) + 1
        local off = math.max(0, math.min(#TIMES - TP_ROWS, idx - 3))
        FauxScrollFrame_SetOffset(tsf, off)
        local bar = tsf.ScrollBar or _G[tsf:GetName() .. "ScrollBar"]
        if bar then bar:SetValue(off * 20) end
        tp:Show(); tp.Paint()
    end)
    d:HookScript("OnHide", function() d.ClosePopups() end)
    Label(L("Nivel mínimo:"), 216, -166)
    d.minLv = HU.NewEditBox(cf, 50); d.minLv:SetPoint("TOPLEFT", 222, -182); d.minLv:SetMaxLetters(2); d.minLv:SetNumeric(true)
    d.minLv:SetJustifyH("CENTER")
    Label(L("Descripción:"), 12, -212)
    -- (la descripción, en una caja de varias líneas)
    local box = CreateFrame("Frame", nil, cf, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 12, -228); box:SetSize(326, 84)
    Panel(box, T.row, T.border, 10, 2)
    d.desc = CreateFrame("EditBox", nil, box)
    d.desc:SetMultiLine(true); d.desc:SetAutoFocus(false); d.desc:SetMaxLetters(90)
    d.desc:SetFontObject(ChatFontNormal); d.desc:SetTextInsets(6, 6, 6, 6)
    d.desc:SetPoint("TOPLEFT", 2, -2); d.desc:SetPoint("BOTTOMRIGHT", -2, 2)
    d.desc:SetScript("OnEscapePressed", d.desc.ClearFocus)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() d.desc:SetFocus() end)

    local ok = DJButton(d, L("Crear"), 120, 24); ok:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 18, 14)
    d.ok = ok
    local no = DJButton(d, L("Cancelar"), 120, 24); no:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -18, 14)
    no:SetScript("OnClick", function() d:Hide() end)
    ok:SetScript("OnClick", function()
        local t = HU.Trim(d.title:GetText() or "")
        if t == "" then return HU:Print(L("Pon un título al evento.")) end
        -- (al editar, el de antes, con lo último que ha llegado; si ya no está, no hay nada que guardar)
        if dirty then Rebuild() end
        local old = d.editing and Find(d.editing)
        if d.editing and not old then return HU:Print(L("No se ha podido guardar el evento.")) end
        local when = time({ year = d.y, month = d.m, day = d.dd, hour = d.hh, min = d.mi })
        -- (al editar, el día y la hora de antes valen aunque ya hayan pasado)
        local same = old and date("%Y%m%d%H%M", when) == date("%Y%m%d%H%M", old.t)
        if same then when = old.t end
        if when < time() and not same then return HU:Print(L("Elige un día y una hora que no hayan pasado.")) end
        local minLv = tonumber(d.minLv:GetText() or "")
        local e = { id = old and old.id or NewId(), title = t, kind = d.kind or "other", t = when, who = Me(), tag = HU.myTag,
            desc = HU.Trim(d.desc:GetText() or ""), minLevel = (minLv and minLv > 1) and minLv or nil, icon = d.icon }
        -- (a la red, y quien lo crea va, con su rol: como al apuntarse. En el modo prueba sin permiso para crear, solo en este
        -- PC, como los de prueba. Editar uno de prueba, aquí; uno de verdad, el mismo id otra vez a la red: lo apuntado va
        -- aparte (s<id>) y sigue)
        if old and old.test then
            old.title, old.kind, old.t, old.desc, old.minLevel, old.icon = e.title, e.kind, e.t, e.desc, e.minLevel, e.icon
        elseif old then
            if not HU:ProposeEvent(old.id, e) then return HU:Print(L("No se ha podido guardar el evento.")) end
            Rebuild()
        elseif ui.testOn and not HU:CanMakeEvents() then
            e.test, e.signups, e.roles, e.raids = true, { [Me()] = "yes" }, { [Me()] = MyRole() }, {}
            testEvents[#testEvents + 1] = e
            dirty = true
        elseif HU:ProposeEvent(e.id, e) then
            HU:ProposeSignup(e.id, MyRole())
            Rebuild()
        else
            return HU:Print(L("No se ha podido crear el evento."))
        end
        d:Hide()
        Paint()
    end)
    -- (sin evento, uno nuevo para ese día (o para hoy) a las 20:00; con uno mío, para editarlo: todo como está)
    function d.Open(dayT, e)
        d.editing = e and e.id or nil
        d.titleText:SetText(e and L("Editar evento") or L("Nuevo evento"))
        d.ok:Label(e and L("Guardar") or L("Crear"))
        d.title:SetText(e and e.title or ""); d.desc:SetText(e and e.desc or "")
        d.minLv:SetText(e and e.minLevel and tostring(e.minLevel) or "")
        local td = date("*t", e and e.t or dayT or time())
        d.y, d.m, d.dd = td.year, td.month, td.day
        d.hh, d.mi = e and td.hour or 20, e and td.min or 0
        d.PaintWhen()
        d.kind = e and e.kind or "raid"; d.PaintKinds()
        d.icon = e and EventIcon(e) or KindIcon(d.kind)
        d.iconCustom = d.icon ~= KindIcon(d.kind); d.PaintIcons()
        d:Show(); d.title:SetFocus()
    end
    return d
end

---------------------------------------------------------------------------
-- Modo prueba: eventos de mentira (de mi hermandad y de otra), con gente apuntada y una raid hecha
---------------------------------------------------------------------------
-- (quitar lo de prueba: sus eventos, invitaciones, clases y niveles; la ficha abierta, solo si era de prueba)
local function ClearTest()
    testEvents = {}
    Rebuild()
    if selected and not Find(selected) then selected = nil end
    for n in pairs(invites) do if n:find("%-Prueba$") then invites[n] = nil end end
    for n in pairs(testClass) do testClass[n] = nil end
    for n in pairs(testLevel) do testLevel[n] = nil end
end

local function AddTest()
    ClearTest()
    local base = date("*t")
    local other = HU:OtherTags()[1] or "OTRA"
    local function At(days, h, m)
        return time({ year = base.year, month = base.month, day = base.day + days, hour = h, min = m or 0 })
    end
    local function E(title, kind, t, who, tag, desc, su)
        testEvents[#testEvents + 1] = { id = NewId() .. #testEvents, title = title, kind = kind, t = t, who = who, tag = tag,
            desc = desc, signups = su or {}, raids = {}, test = true }
        return testEvents[#testEvents]
    end
    local CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "HUNTER", "WARLOCK", "DRUID", "PALADIN", "SHAMAN" }
    local mc = { ["Jandra-Prueba"] = "yes", ["Pepe-Prueba"] = "yes", ["Bea-Prueba"] = "yes", [Me()] = "yes" }
    local NAMES = { "Arwen", "Borin", "Celes", "Dax", "Elian", "Fyra", "Gorm", "Hela", "Ivo", "Jun", "Kael", "Lune",
        "Mora", "Nix", "Orla", "Pim", "Quin", "Rhea", "Sol", "Tamsin" }
    for i, n in ipairs(NAMES) do
        local full = n .. "-Prueba"
        mc[full] = "yes"
        testClass[full] = CLASSES[(i - 1) % #CLASSES + 1]
        testLevel[full] = 52 + (i * 7) % 9
    end
    testClass["Jandra-Prueba"], testClass["Pepe-Prueba"], testClass["Bea-Prueba"] = "PRIEST", "WARRIOR", "DRUID"
    local ROLE_BY = { WARRIOR = "TANK", PRIEST = "HEALER", DRUID = "HEALER", PALADIN = "HEALER", SHAMAN = "HEALER" }
    local first = E(L("Núcleo de Magma"), "raid", At(0, 21), "Jandra-Prueba", HU.myTag, L("Raid de la unión. Traed resistencias al fuego."), {})
    first.roles = {}
    first.minLevel = 55
    local r1 = NewRaid(first, Me())
    first.signups[Me()], first.roles[Me()] = "yes", "DAMAGER"
    -- (los primeros 12 entran solos en la raid 1; el resto, al banquillo: la raid 1 es de 12 para que se vea)
    local i = 0
    for n in pairs(mc) do
        if n ~= Me() then
            i = i + 1
            first.signups[n] = "yes"
            first.roles[n] = ROLE_BY[testClass[n] or ""] or "DAMAGER"
            if i <= 12 then AutoPlace(first, n) end
        end
    end
    r1.name = L("Raid") .. " 1"
    -- (cómo se ven las marcas al invitar: uno dentro, uno esperando, uno que no aceptó)
    invites["Jandra-Prueba"] = { s = "ok", t = time() }
    invites["Arwen-Prueba"] = { s = "wait", t = time() }
    invites["Borin-Prueba"] = { s = "no", t = time() }
    E(L("Profundidades de Roca Negra"), "dungeon", At(1, 19, 30), "Pepe-Prueba", HU.myTag, L("Grupo para la llave."),
        { ["Pepe-Prueba"] = "yes" })
    E(L("Garganta Grito de Guerra"), "pvp", At(2, 22), "Lyra-Prueba", other, "", { ["Lyra-Prueba"] = "yes" })
    E(L("Pesca en Tuercespina"), "social", At(5, 18), Me(), HU.myTag, L("Concurso de pesca, premio para el primero."),
        { [Me()] = "yes" })
    E(L("Guarida de Onyxia"), "raid", At(8, 21), "Bea-Prueba", other, L("Para los que tengáis la misión."), { ["Bea-Prueba"] = "yes" }).minLevel = 60
    ui.testOn = true
    dirty = true
    Paint()
end

-- Lo guardado, en la cuenta: los eventos y quién va, en la red (Packs/Events.lua, tras /reload siguen); aquí, las raids de
-- los míos (calRaids) y lo que queda de la copia 324 (calEvents), lo que vive un evento en la red (HU.EVENT_LIVES, 30 días
-- desde su hora): mientras se ve en el mes, su ficha sigue con sus raids. Lo de prueba no se guarda [+ARCHITECTURE.md]
local function Tidy()
    local old = time() - HU.EVENT_LIVES
    local kept = HU.db.calEvents
    for k = #kept, 1, -1 do
        local e = kept[k]
        if type(e) ~= "table" or e.test or type(e.t) ~= "number" or e.t < old or type(e.signups) ~= "table" then table.remove(kept, k) end
    end
    -- (las raids de eventos viejos o sin hora, fuera; y el plan de la banda, solo mientras vale)
    for id, raids in pairs(HU.db.calRaids) do
        local p = type(raids) == "table" and raids.plan
        if type(raids) ~= "table" or type(raids.t) ~= "number" or raids.t < old then HU.db.calRaids[id] = nil
        elseif p and not (type(p) == "table" and type(p.placed) == "table" and type(p.untilT) == "number" and p.untilT > time()) then raids.plan = nil end
    end
end
-- (copia 324: los eventos solo se guardaban aquí. Con la comunidad leída, los míos pasan a la red, con mi apuntado y sus
-- raids, y salen de calEvents; los de otro personaje de la cuenta se quedan para cuando entre él) [+ARCHITECTURE.md]
local function Migrate()
    local kept, me = HU.db.calEvents, HU:Me()
    if not (HU.myTag and me and #kept > 0) then return end
    for k = #kept, 1, -1 do
        local e = kept[k]
        if type(e) == "table" and e.who == me and not e.test and type(e.t) == "number" and type(e.signups) == "table" then
            table.remove(kept, k)
            if e.t >= time() - HU.EVENT_LIVES and HU:ProposeEvent(e.id, e) then
                if e.signups[me] == "yes" then HU:ProposeSignup(e.id, type(e.roles) == "table" and e.roles[me] or MyRole()) end
                if type(e.raids) == "table" and #e.raids > 0 then e.raids.t = e.t; HU.db.calRaids[e.id] = e.raids end
            end
        end
    end
end
-- (lo que falta de la red: lo de mi hermandad que me perdí estando fuera y lo de las otras. Al abrir y cada minuto mientras
-- se ve)
local function Need()
    HU:PackNeed(HU.myTag, "EV")
    for _, tag in ipairs(HU:OtherTags()) do HU:PackNeed(tag, "EV") end
end
HU:OnStart(function()
    Tidy()
    -- (el plan de la banda que dejé guardado, si es mío y aún vale: tras /reload, la banda se sigue montando)
    for id, raids in pairs(HU.db.calRaids) do
        if raids.plan and raids.plan.who == Me() then raids.plan.id, arrange.plan = id, raids.plan end
    end
    HU:Every(60, "calendario-pedir", function() if open then Need() end end)
end)
HU:On("PLAYER_LOGOUT", Tidy)

-- («+ Nuevo evento» apagado, al pasar el ratón: quién los crea según la configuración del calendario, calMake; con
-- «Todos» siempre se puede, así que no sale. Encendido, nada: su nombre ya se lee)
local function NoMakeTip(s)
    if s:IsEnabled() then return end
    local who = HU:UnionCfg().calMake or "officers"
    local text = (who == "gm" and L("Solo el maestro crea eventos.")) or (who == "officers" and L("Solo los oficiales crean eventos."))
    if not text then return end
    GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:SetText(text); GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Montar la sección (UnionRoster.lua la pone en la pestaña Eventos)
---------------------------------------------------------------------------
function HU:BuildCalendar(host)
    ui = host
    local now = date("*t")
    month, year = now.month, now.year

    -- Arriba, en el centro, los botones rojos Eventos · Calendario, como los de Comercio (DJ.Switch; Jorge, 24/11), y a su
    -- derecha el modo prueba; abajo, en el centro, «+ Nuevo evento» (ver más abajo) [+ARCHITECTURE.md]
    local sw = DJ.Switch(host, { { "list", L("Eventos") }, { "month", L("Calendario") } })
    sw:SetPoint("TOP", host, "TOP", 0, -4)
    ui.switch = sw
    ui.viewBtns = sw.btns
    for k, b in pairs(sw.btns) do
        b:SetScript("OnClick", function() view = k; PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB); Paint() end)
    end
    -- (el modo prueba, a la altura del interruptor, en el hueco de su derecha; se enciende y se apaga: apagado, se quita
    -- lo de prueba)
    local test = DJButton(host, L("Modo prueba"), 104, 24)
    test:SetPoint("TOPRIGHT", host, "TOPRIGHT", -8, -4 - (DJ.SWITCH.h - 24) / 2)
    test:SetScript("OnClick", function(b)
        if ui.testOn then ClearTest(); ui.testOn = nil else AddTest(); ui.testOn = true end
        b:Pick(ui.testOn == true)
        Paint()
    end)
    -- (el panel de la sección, 6 por debajo del interruptor: color «content», borde y pergamino)
    local body = CreateFrame("Frame", nil, host, "BackdropTemplate")
    body:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -4 - DJ.SWITCH.h - 6); body:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)
    Panel(body, T.content, T.border, 14, 4)
    Parchment(body, 0.18)

    -- Eventos: una tarjeta por línea
    local list = CreateFrame("Frame", nil, body, "BackdropTemplate")
    list:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -8); list:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, BOTTOM_H)
    ui.list = list
    -- (el panel de las tarjetas, centrado; dentro, la zona de las tarjetas y, a su derecha, la barra)
    Panel(list, T.panel, T.border, 12, 3)
    local area = CreateFrame("Frame", nil, list)
    area:SetPoint("TOPLEFT", 8, -8); area:SetPoint("BOTTOMRIGHT", -8, 8)
    ui.cardArea = area
    local sf = CreateFrame("ScrollFrame", "GuildUnionCalendarScroll", list, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", area, "TOPLEFT"); sf:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
    sf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, CARD_H + CARD_GAP, Paint) end)
    ui.scroll = sf
    ui.cards = {}
    for i = 1, CARD_N do
        local c = CreateFrame("Button", nil, list, "BackdropTemplate")
        c:SetHeight(CARD_H)
        c:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(i - 1) * (CARD_H + CARD_GAP))
        c:SetPoint("RIGHT", area, "RIGHT", 0, 0)
        c:SetBackdrop({ bgFile = WHITE, edgeFile = TIP_BORDER, tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        c:SetBackdropColor(0.02, 0.02, 0.02, 0.45)
        c:SetBackdropBorderColor(0.34, 0.34, 0.34, 1)
        -- (capas: el fondo de fila, un tinte del color del tipo, sombra arriba y una raya de brillo dorado)
        local art = c:CreateTexture(nil, "BACKGROUND", nil, 1)
        art:SetPoint("TOPLEFT", 4, -4); art:SetPoint("BOTTOMRIGHT", -4, 4)
        art:SetColorTexture(T.row[1], T.row[2], T.row[3], 1)
        c.wash = c:CreateTexture(nil, "BACKGROUND", nil, 2)
        c.wash:SetPoint("TOPLEFT", 4, -4); c.wash:SetPoint("BOTTOMRIGHT", -4, 4)
        local topShade = c:CreateTexture(nil, "BACKGROUND", nil, 3)
        topShade:SetPoint("TOPLEFT", 4, -4); topShade:SetPoint("TOPRIGHT", -4, -4); topShade:SetHeight(24)
        topShade:SetColorTexture(0, 0, 0, 0.42)
        local glow = c:CreateTexture(nil, "ARTWORK")
        glow:SetPoint("TOPLEFT", 4, -4); glow:SetPoint("TOPRIGHT", -4, -4); glow:SetHeight(1)
        glow:SetColorTexture(1.0, 0.84, 0.25, 0.30)
        local hl = c:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 4, -4); hl:SetPoint("BOTTOMRIGHT", -4, 4); hl:SetColorTexture(1, 0.82, 0.18, 0.08)
        -- (a lo ancho, de izquierda a derecha: el día grande con el día de la semana y el mes; una raya dorada que lo
        -- separa del resto; la imagen redonda; en tres líneas, el título dorado, quién lo pone y tipo · hora · nivel, y a su
        -- derecha los roles y cuántos van; y a la derecha del todo, Apuntarme encima de Más información. Jorge, 25/11:
        -- «primero la fecha… luego una pequeña separación… el nombre, by… debajo del nombre y debajo la hora»)
        c.num = c:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        C(c.num, T.title); Big(c.num, 26)
        c.num:SetPoint("LEFT", 12, 1)
        c.date = C(c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), { 0.90, 0.90, 0.93 })
        c.date:SetPoint("LEFT", c.num, "RIGHT", 6, 0); c.date:SetJustifyH("LEFT"); c.date:SetSpacing(1)
        c.sep = Line(c, 0.45)
        c.sep:SetWidth(1); c.sep:SetHeight(CARD_H - 20)
        c.sep:SetPoint("LEFT", c, "LEFT", 120, 0)
        c.icon = RoundIcon(c, 30)
        c.icon:SetPoint("LEFT", c, "LEFT", 130, 0)
        c.join = DJButton(c, L("Apuntarme"), 112, 22)
        c.join:SetPoint("TOPRIGHT", -8, -7)
        c.join:SetScript("OnClick", function(s) local e = c.id and Find(c.id); if e then SignUp(e, s) end end)
        c.info = DJButton(c, L("Más información"), 112, 22)
        c.info:SetPoint("BOTTOMRIGHT", -8, 7)
        c.info:SetScript("OnClick", function() if c.id then OpenDetail(c.id) end end)
        c.roles = C(c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), { 0.90, 0.90, 0.93 })
        c.roles:SetPoint("TOPRIGHT", -132, -27)
        c.going = C(c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), { 0.92, 0.92, 0.95 })
        c.going:SetPoint("TOPRIGHT", -132, -43)
        -- (el título, hasta los botones; quién lo pone, hasta los roles, y tipo · hora · nivel, hasta cuántos van)
        c.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        C(c.title, { 1.00, 0.88, 0.24 }); c.title:SetShadowColor(0, 0, 0, 1); c.title:SetShadowOffset(1, -1)
        c.title:SetPoint("TOPLEFT", 168, -8); c.title:SetPoint("TOPRIGHT", -132, -8)
        c.title:SetJustifyH("LEFT"); c.title:SetWordWrap(false)
        c.who = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.who:SetPoint("TOPLEFT", 168, -29); c.who:SetPoint("TOPRIGHT", -250, -29)
        c.who:SetJustifyH("LEFT"); c.who:SetWordWrap(false)
        c.kind = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.kind:SetPoint("TOPLEFT", 168, -43); c.kind:SetPoint("TOPRIGHT", -210, -43)
        c.kind:SetJustifyH("LEFT"); c.kind:SetWordWrap(false)
        -- (al pasar el ratón, borde dorado)
        c:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(T.hover[1], T.hover[2], T.hover[3], 1) end)
        c:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(0.34, 0.34, 0.34, 1) end)
        -- (clic: la ficha; clic derecho, en uno mío: editar o eliminar)
        c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        c:SetScript("OnClick", function(s, button)
            if button == "RightButton" then return EventMenu(s, s.id) end
            if s.id then OpenDetail(s.id) end
        end)
        ui.cards[i] = c
    end
    -- (la rueda del ratón mueve la barra de una tarjeta en una: poco a poco, y la barra con ella. Jorge, 24/11: antes
    -- bajaba una fila de dos, «de golpe»; el juego no pasa de los extremos de la barra)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(s, delta)
        local bar = s.ScrollBar or _G[s:GetName() .. "ScrollBar"]
        if bar then bar:SetValue(bar:GetValue() - delta * (CARD_H + CARD_GAP)) end
    end)
    ui.empty = C(list:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), T.muted)
    ui.empty:SetPoint("TOP", list, "TOP", 0, -60); ui.empty:SetWidth(400)
    ui.empty:SetText(L("No hay eventos próximos."))

    -- Calendario: a la derecha, los eventos del día elegido (panel lateral)
    local side = CreateFrame("Frame", nil, body, "BackdropTemplate")
    side:SetPoint("TOPRIGHT", -10, -10); side:SetPoint("BOTTOMRIGHT", -10, BOTTOM_H); side:SetWidth(220)
    Panel(side, T.panel, T.border, 12, 3)
    Parchment(side, 0.13)
    ui.side = side
    side.title = C(side:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), T.title)
    side.title:SetPoint("TOPLEFT", 10, -10); side.title:SetPoint("RIGHT", side, "RIGHT", -8, 0)
    side.title:SetJustifyH("LEFT"); side.title:SetWordWrap(false)
    local sl = Line(side, 0.45); sl:SetPoint("TOPLEFT", 8, -32); sl:SetPoint("TOPRIGHT", -8, -32)
    side.info = C(side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    side.info:SetPoint("TOPLEFT", 10, -40); side.info:SetPoint("RIGHT", side, "RIGHT", -8, 0)
    side.info:SetJustifyH("LEFT")
    -- (5 a la vista y, si hay más, la barra a su derecha)
    local dsf = CreateFrame("ScrollFrame", "GuildUnionCalendarDayScroll", side, "FauxScrollFrameTemplate")
    dsf:SetPoint("TOPLEFT", 6, -40); dsf:SetSize(184, DAY_N * DAY_H)
    dsf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, DAY_H, PaintDay) end)
    side.scroll = dsf
    side.dayBtns = {}
    for i = 1, DAY_N do
        local b = CreateFrame("Button", nil, side, "BackdropTemplate")
        b:SetHeight(40)
        b:SetPoint("TOPLEFT", side, "TOPLEFT", 6, -40 - (i - 1) * DAY_H); b:SetPoint("RIGHT", side, "RIGHT", -6, 0)
        Panel(b, T.row, T.border, 10, 2)
        b:SetHighlightTexture(ROW_HL, "ADD")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(30, 30); b.icon:SetPoint("LEFT", 5, 0); b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.text = C(b:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.title)
        b.text:SetPoint("TOPLEFT", 42, -6); b.text:SetPoint("RIGHT", -4, 0); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
        b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.sub:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -3); b.sub:SetPoint("RIGHT", -4, 0); b.sub:SetJustifyH("LEFT")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(s, button)
            if button == "RightButton" then return EventMenu(s, s.id) end
            OpenDetail(s.id)
        end)
        b:Hide()
        side.dayBtns[i] = b
    end

    -- Calendario: el mes
    local mframe = CreateFrame("Frame", nil, body)
    mframe:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -10); mframe:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -8, 0)
    ui.month = mframe
    local mh = CreateFrame("Frame", nil, mframe, "BackdropTemplate")
    mh:SetPoint("TOPLEFT", 30, 0); mh:SetPoint("TOPRIGHT", -30, 0); mh:SetHeight(24)
    Panel(mh, T.header, T.border, 10, 2)
    ui.monthTitle = C(mh:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), T.title)
    ui.monthTitle:SetPoint("CENTER", 0, 0)
    local function Arrow(dir, point)
        local b = CreateFrame("Button", nil, mframe)
        b:SetSize(26, 26)
        local name = dir < 0 and "Prev" or "Next"
        b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "Page-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "Page-Down")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetPoint(point, mframe, point, 0, 1)
        b:SetScript("OnClick", function()
            month = month + dir
            if month < 1 then month, year = 12, year - 1 elseif month > 12 then month, year = 1, year + 1 end
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            Paint()
        end)
    end
    Arrow(-1, "TOPLEFT")
    Arrow(1, "TOPRIGHT")
    local grid = CreateFrame("Frame", nil, mframe)
    grid:SetPoint("TOPLEFT", mframe, "TOPLEFT", 0, -28); grid:SetPoint("BOTTOMRIGHT")
    ui.grid = grid
    grid.dayNames = {}
    for i = 1, 7 do
        local l = C(grid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), T.title)
        l:SetText(L(DAYS_SHORT[i])); l:SetJustifyH("CENTER")
        grid.dayNames[i] = l
    end
    grid.cells = {}
    for i = 1, 42 do
        local c = CreateFrame("Button", nil, grid, "BackdropTemplate")
        Panel(c, T.row, T.border, 8, 2)
        c:SetHighlightTexture(ROW_HL, "ADD")
        c.num = C(c:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.title)
        c.num:SetPoint("TOPLEFT", 5, -4)
        c.ev = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.ev:SetPoint("TOPLEFT", 4, -16); c.ev:SetPoint("RIGHT", -2, 0); c.ev:SetHeight(11)
        c.mark = c:CreateTexture(nil, "OVERLAY")
        c.mark:SetSize(6, 6); c.mark:SetPoint("TOPRIGHT", -4, -4); c.mark:Hide()
        c.ev:SetJustifyH("LEFT"); c.ev:SetJustifyV("TOP"); c.ev:SetWordWrap(false)
        Big(c.ev, 9)
        c:SetScript("OnClick", function(s)
            local other = pickedDay ~= s.key
            pickedDay = s.key
            if other then ScrollTop(ui.side.scroll) end
            Paint()
        end)
        grid.cells[i] = c
    end
    grid:SetScript("OnSizeChanged", function() if ui:IsShown() and view == "month" then Paint() end end)

    -- La ficha del evento y la ventana de nuevo evento
    ui.detail = BuildDetail(host)
    ui.newDlg = BuildNewDialog(host)
    -- (preguntar antes de algo: texto y Sí / No)
    local cfm = CreateFrame("Frame", "GuildUnionCalendarConfirm", host, "BackdropTemplate")
    cfm:SetSize(300, 110); cfm:SetPoint("CENTER", host, "CENTER", 0, 20)
    cfm:SetFrameStrata("FULLSCREEN_DIALOG"); cfm:SetToplevel(true); cfm:EnableMouse(true)
    Panel(cfm, T.frame, T.border, 12, 3)
    cfm:Hide()
    cfm.text = C(cfm:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), T.text)
    cfm.text:SetPoint("TOP", 0, -22); cfm.text:SetWidth(270)
    local yes = DJButton(cfm, L("Sí"), 110, 24); yes:SetPoint("BOTTOMRIGHT", cfm, "BOTTOM", -6, 14)
    local no = DJButton(cfm, L("No"), 110, 24); no:SetPoint("BOTTOMLEFT", cfm, "BOTTOM", 6, 14)
    no:SetScript("OnClick", function() cfm:Hide() end)
    yes:SetScript("OnClick", function() local f = cfm.onYes; cfm:Hide(); if f then f() end end)
    function ui.confirm(text, onYes)
        cfm.text:SetText(text); cfm.onYes = onYes
        cfm:Show()
    end

    -- Abajo, en el centro, en las dos vistas: «+ Nuevo evento», como hasta la copia 304 (teñido de verde, letra blanca).
    -- Quien puede crearlos (HU:CanMakeEvents) o con el modo prueba; en Calendario, para el día elegido [+ARCHITECTURE.md]
    local new = DJButton(body, "+ " .. L("Nuevo evento"), 200, 24)
    new:SetPoint("BOTTOM", body, "BOTTOM", 0, 6)
    for _, k in ipairs({ "Left", "Middle", "Right" }) do if new[k] then new[k]:SetVertexColor(0.45, 1, 0.45) end end
    new:SetNormalFontObject("GameFontHighlight")
    new:SetScript("OnClick", function()
        local t
        if view == "month" and pickedDay then
            local y, m, dd = pickedDay:match("(%d+)-(%d+)-(%d+)")
            t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 })
        end
        ui.newDlg.Open(t)
    end)
    new:SetScript("OnEnter", NoMakeTip)
    new:SetScript("OnLeave", function() GameTooltip:Hide() end)
    new:SetMotionScriptsWhileDisabled(true)
    ui.new = new

    -- (al abrir, se pide lo que falte y se rehace)
    host:HookScript("OnShow", function() open = true; Need(); dirty = true; Paint() end)
    host:HookScript("OnHide", function() open = false; selected = nil; ui.detail:Hide() end)
    Paint()
end

-- (si cambia quién crea eventos, «+ Nuevo evento» se pone al día; con la comunidad leída, lo de la copia 324 pasa a la red;
-- y lo que llega de la red se rehace al pintar: si se ve, enseguida, y lo que llega seguido, de una vez)
HU:Listen("CHANGED", function(what)
    if what == "unionCfg" then
        Paint()
    elseif what == "config" then
        Migrate()
    elseif what == "calendar" then
        dirty = true
        if open and not paintSoon then
            paintSoon = true
            HU.After(0.3, function() paintSoon = false; if dirty then Paint() end end)
        end
    end
end)

HU:Module("UnionCalendar", { "BlizzTab", "Config", "Core", "ListWindow", "Net/Packs", "Packs/Events", "UnionConfig" })
