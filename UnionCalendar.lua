-- Guild Union - Calendario de la unión (la sección Calendar de la lista de miembros) [+ARCHITECTURE.md]
-- Fase 1: solo la ventana, sin red. Con el estilo compartido (DJStyle.lua): fondos lisos casi negros con borde de
-- tooltip gris, títulos y rayas doradas, tarjetas con sombra arriba y brillo dorado.
-- Pestañas Eventos (tarjetas) y Calendario (el mes); la ficha de cada evento son sus raids.
local _, HU = ...
local L = HU.L

local CARD_H, CARD_GAP = 100, 8    -- Eventos: tarjetas de 2 en 2 (2 filas a la vista)
local GROUPS, PER_GROUP = 8, 5
local MAX_RAIDS = 20
local RAID_ROW = 10         -- pestañas de raid por fila (dos filas: 20)
local DETAIL_H = 480        -- alto de la ventana del evento con una fila de pestañas
local BENCH_N = 12          -- filas del banquillo a la vista (con barra, el resto)
local DAY_N, DAY_H = 5, 44  -- eventos del día a la vista en Calendario (con barra, el resto) y su alto
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
local ROLE_TC = { TANK = { 0, 19, 22, 41 }, HEALER = { 20, 39, 1, 20 }, DAMAGER = { 20, 39, 22, 41 } }
local function RoleIcon(role, size)
    local c = ROLE_TC[role]
    if not c then return "" end
    size = size or 14
    return string.format("|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:%d:%d:0:0:64:64:%d:%d:%d:%d|t", size, size, c[1], c[2], c[3], c[4])
end
local KIND = {}
for _, k in ipairs(KINDS) do KIND[k[1]] = k end
local DAYS = { "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo" }
local DAYS_SHORT = { "L", "M", "X", "J", "V", "S", "D" }
local DAYS_ABBR = { "lun", "mar", "mié", "jue", "vie", "sáb", "dom" }
local MONTHS = { "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
    "noviembre", "diciembre" }

-- (en la sesión: fase 1, sin red)
local events = {}           -- { id, title, kind, t, who, tag, desc, minLevel, icon, signups = { [nombre] = "yes" }, roles = { [nombre] = rol }, raids, test }
local lastRole              -- el último rol con el que me apunté (sin el menú del juego, y al crear un evento, voy con él)
local view = "list"         -- "list" (Eventos) o "month" (Calendario)
local selected              -- el evento cuya ficha está abierta (id)
local month, year           -- el mes que se ve en Calendario
local pickedDay             -- el día elegido en Calendario ("aaaa-mm-dd")
local raidPick = 1          -- la raid que se ve
local testClass = {}        -- [nombre] = clase (modo prueba)
local invites = {}          -- [nombre] = { s = "wait"|"ok"|"no", t } (lo que pasó al invitarlos)
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
-- (próximos primero; los ya pasados, fuera de la lista: siguen en el calendario)
local function Upcoming()
    local out, now = {}, time() - 3 * 3600
    for _, e in ipairs(events) do if e.t >= now then out[#out + 1] = e end end
    table.sort(out, function(a, b) return a.t < b.t end)
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
-- «Colocar en raids»: los del banquillo, primero tanques, luego sanadores y luego daño
local function PlaceBench(e)
    local order = { TANK = 1, HEALER = 2, DAMAGER = 3 }
    local free = Unassigned(e)
    table.sort(free, function(a, b)
        local ra, rb = order[RoleOf(e, a) or "DAMAGER"] or 3, order[RoleOf(e, b) or "DAMAGER"] or 3
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    local placed = 0
    for _, n in ipairs(free) do if AutoPlace(e, n) then placed = placed + 1 end end
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
HU:On("GROUP_ROSTER_UPDATE", function()
    for n, st in pairs(invites) do if st.s ~= "ok" and InGroup(n) then Mark(n, "ok") end end
    if ui and ui:IsShown() and selected then Paint() end
end)

local function InviteRaid(r)
    local inv = C_PartyInfo and C_PartyInfo.InviteUnit
    if not inv then return end
    if IsInGroup() and not IsInRaid() and C_PartyInfo.ConvertToRaid then pcall(C_PartyInfo.ConvertToRaid) end
    local n, left = 0, 0
    local room = IsInRaid() and 40 or 4
    for _, name in ipairs(Members(r)) do
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

-- Apuntarse (con un rol) o desapuntarse; al apuntarse se entra en una raid con sitio
local function SetSignup(e, name, role)
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
local function OpenDetail(id)
    local other = selected ~= id
    selected = id
    if other then raidPick = 1; ScrollTop(ui.detail.benchScroll) end
    Paint()
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
    -- (pestañas de raid en filas de 10, bajo la descripción; «+ Añadir» va en el hueco siguiente. Con dos filas,
    -- la ventana crece 26 y todo lo de debajo baja 26, y lo mismo con lo que ocupa la descripción: así no se sale
    -- ni se monta)
    local canAdd = manage and #e.raids < MAX_RAIDS
    local used = #e.raids + (canAdd and 1 or 0)
    local shift = d.descH + (used > RAID_ROW and 26 or 0)
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
            d.SmallFont(b)
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
    if cur then
        d.invite:Label(string.format(L("Invitar a todos (%d)"), #Members(cur)))
        d.leaderBar.roles:SetText(RoleCounts(e, Members(cur)))
        d.leaderBar.text:SetText(L("Líder de la raid") .. ":  " .. (cur.leader and (CROWN .. ColorName(cur.leader, classes, RoleOf(e, cur.leader)) .. " " .. Status(cur.leader))
            or ("|cffa0a4ad" .. L("nadie (clic derecho en alguien: «Hacer líder»)") .. "|r")))
    end
    local free = Unassigned(e)
    local levels = LevelMap()
    d.benchHead:SetText(L("Sin raid") .. "  |cffa0a4ad(" .. #free .. ")|r")
    -- (con más de los que caben, la barra: las filas se estrechan para dejarle sitio)
    FauxScrollFrame_Update(d.benchScroll, #free, BENCH_N, 18)
    local off = FauxScrollFrame_GetOffset(d.benchScroll)
    local w = #free > BENCH_N and 122 or 142
    for i, b in ipairs(d.bench) do
        local n = free[off + i]
        b.name = n
        b:SetWidth(w)
        b.fill:SetAlpha(1)
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
        raidPick = #e.raids
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
    -- (las raids: una pestaña por raid y «+ Añadir raid»)
    d.raidTabs = {}
    -- (10 por fila de 65 + 3: 677 de ancho, cabe en los 704 del panel; letra pequeña en todos sus estados,
    -- para que no cambie de tamaño al pasar el ratón)
    function d.TabPoint(b, i)
        local col, row = (i - 1) % RAID_ROW, math.floor((i - 1) / RAID_ROW)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", cf, "TOPLEFT", 12 + col * 68, -34 - d.descH - row * 26)
    end
    function d.SmallFont(b)
        b:SetNormalFontObject(b.picked and "GameFontHighlightSmall" or "GameFontNormalSmall")
        b:SetHighlightFontObject("GameFontHighlightSmall")
        b:SetDisabledFontObject("GameFontDisableSmall")
    end
    for i = 1, MAX_RAIDS do
        local b = DJButton(cf, "", 65, 24)
        d.TabPoint(b, i)
        b.idx = i
        b:SetScript("OnClick", function() raidPick = i; Paint() end)
        b:Hide()
        d.raidTabs[i] = b
    end
    d.addRaid = DJButton(cf, "+ " .. L("Añadir"), 65, 24)
    d.SmallFont(d.addRaid)
    d.addRaid:SetScript("OnClick", function(s) AskLeader(s) end)
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
        btn.text:SetText(""); if btn.fill then btn.fill:SetAlpha(0) end; if btn.status then btn.status:SetText("") end
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
        b:SetHighlightTexture(ROW_HL, "ADD")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.text:SetPoint("LEFT", 5, 0); b.text:SetPoint("RIGHT", -18, 0); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
        b.status = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        b.status:SetPoint("RIGHT", -3, 0)
        b:RegisterForClicks("RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnClick", function(s) if s.name then NameMenu(s, s.name) end end)
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
    local bsf = CreateFrame("ScrollFrame", "GuildUnionCalendarBenchScroll", bench, "FauxScrollFrameTemplate")
    bsf:SetPoint("TOPLEFT", 7, -28); bsf:SetSize(122, BENCH_N * 18)
    bsf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, 18, PaintDetail) end)
    d.benchScroll = bsf
    d.bench = {}
    for i = 1, BENCH_N do
        local b = Slot(bench, 142)
        b:SetPoint("TOPLEFT", 7, -28 - (i - 1) * 18)
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
    -- (debajo de los grupos: Invitar a todos, Quitar raid y Convertir en banda; Apuntarme, abajo a la derecha)
    d.invite = DJButton(cf, "", 170, 24)
    d.invite:SetPoint("TOPLEFT", d.groups[5], "BOTTOMLEFT", 0, -10)
    d.invite:SetScript("OnClick", function()
        local e = selected and Find(selected)
        local r = e and e.raids[raidPick]
        if r then InviteRaid(r) end
    end)
    d.delRaid = DJButton(cf, L("Quitar raid"), 110, 24)
    d.delRaid:SetPoint("LEFT", d.invite, "RIGHT", 6, 0)
    d.convert = DJButton(cf, L("Convertir en banda"), 150, 24)
    d.convert:SetPoint("LEFT", d.delRaid, "RIGHT", 6, 0)
    d.convert:SetScript("OnClick", function()
        if C_PartyInfo and C_PartyInfo.ConvertToRaid then pcall(C_PartyInfo.ConvertToRaid) end
    end)
    d.delRaid:SetScript("OnClick", function()
        local e = selected and Find(selected)
        if e and e.raids[raidPick] then table.remove(e.raids, raidPick); raidPick = math.max(1, raidPick - 1); Paint() end
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
    d:HookScript("OnHide", function() pk:Hide() end)
    d.picker = pk

    d.join = DJButton(d, L("Apuntarme"), 140, 24)
    d.join:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -18, 14)
    d.join:SetScript("OnClick", function(s) local e = selected and Find(selected); if e then SignUp(e, s) end end)
    return d
end

---------------------------------------------------------------------------
-- Eventos: tarjetas de 2 en 2, como las de las mazmorras del Dungeon Journal
---------------------------------------------------------------------------
local function PaintCards()
    local list = Upcoming()
    local rows = math.ceil(#list / 2)
    FauxScrollFrame_Update(ui.scroll, rows, 2, CARD_H + CARD_GAP)
    -- (con barra, la zona de las tarjetas deja su hueco a la derecha dentro del panel: el panel sigue centrado)
    local inset = rows > 2 and 30 or 8
    if ui.cardArea.inset ~= inset then
        ui.cardArea.inset = inset
        ui.cardArea:SetPoint("BOTTOMRIGHT", ui.list, "BOTTOMRIGHT", -inset, 8)
    end
    local off = FauxScrollFrame_GetOffset(ui.scroll) * 2
    for i, card in ipairs(ui.cards) do
        local e = list[off + i]
        card.id = e and e.id
        if e then
            local r, g, b = KindRGB(e.kind)
            card.wash:SetColorTexture(r, g, b, 0.10)
            card.icon:SetTexture(EventIcon(e))
            card.title:SetText(e.title)
            card.kind:SetText(KindText(e.kind) .. "  |cffe6e6ea" .. date("%H:%M", e.t) .. "|r"
                .. (e.minLevel and ("  |cffa0a4ad" .. string.format(L("Nv. %d+"), e.minLevel) .. "|r") or ""))
            card.num:SetText(tonumber(date("%d", e.t)))
            card.date:SetText(L(DAYS[WeekDay(e.t)]) .. "\n" .. L(MONTHS[tonumber(date("%m", e.t))]))
            card.who:SetText("|cffa0a4ad" .. L("por") .. "|r " .. WhoText(e))
            card.going:SetText((e.signups[Me()] == "yes" and "|TInterface\\RaidFrame\\ReadyCheck-Ready:18:18|t " or "")
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
    for k, b in pairs(ui.viewBtns) do b:Pick(k == view) end
    ui.list:SetShown(view == "list")
    ui.month:SetShown(view == "month")
    ui.side:SetShown(view == "month")
    if view == "list" then PaintCards() else PaintMonth(); PaintDay() end
    ui.new:SetEnabled(HU:CanMakeEvents() or ui.testOn == true)
    ui.side.new:SetShown(view == "month" and pickedDay ~= nil)
    ui.side.new:SetEnabled(ui.new:IsEnabled())
    PaintDetail()
end

---------------------------------------------------------------------------
-- Nuevo evento: título, tipo, imagen, día, hora, nivel mínimo y descripción
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
    d.desc:SetMultiLine(true); d.desc:SetAutoFocus(false); d.desc:SetMaxLetters(240)
    d.desc:SetFontObject(ChatFontNormal); d.desc:SetTextInsets(6, 6, 6, 6)
    d.desc:SetPoint("TOPLEFT", 2, -2); d.desc:SetPoint("BOTTOMRIGHT", -2, 2)
    d.desc:SetScript("OnEscapePressed", d.desc.ClearFocus)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() d.desc:SetFocus() end)

    local ok = DJButton(d, L("Crear"), 120, 24); ok:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 18, 14)
    local no = DJButton(d, L("Cancelar"), 120, 24); no:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -18, 14)
    no:SetScript("OnClick", function() d:Hide() end)
    ok:SetScript("OnClick", function()
        local t = HU.Trim(d.title:GetText() or "")
        if t == "" then return HU:Print(L("Pon un título al evento.")) end
        local when = time({ year = d.y, month = d.m, day = d.dd, hour = d.hh, min = d.mi })
        if when < time() then return HU:Print(L("Elige un día y una hora que no hayan pasado.")) end
        local minLv = tonumber(d.minLv:GetText() or "")
        -- (quien lo crea va, con su rol: como al apuntarse)
        events[#events + 1] = { id = NewId(), title = t, kind = d.kind or "other", t = when, who = Me(), tag = HU.myTag,
            desc = HU.Trim(d.desc:GetText() or ""), signups = { [Me()] = "yes" }, roles = { [Me()] = MyRole() }, raids = {},
            minLevel = (minLv and minLv > 1) and minLv or nil, icon = d.icon }
        d:Hide()
        Paint()
    end)
    function d.Open(dayT)
        local t = dayT or time()
        d.title:SetText(""); d.desc:SetText(""); d.minLv:SetText("")
        local td = date("*t", t)
        d.y, d.m, d.dd, d.hh, d.mi = td.year, td.month, td.day, 20, 0
        d.PaintWhen()
        d.kind = "raid"; d.PaintKinds()
        d.icon, d.iconCustom = KindIcon(d.kind), false; d.PaintIcons()
        d:Show(); d.title:SetFocus()
    end
    return d
end

---------------------------------------------------------------------------
-- Modo prueba: eventos de mentira (de mi hermandad y de otra), con gente apuntada y una raid hecha
---------------------------------------------------------------------------
-- (quitar lo de prueba: sus eventos, invitaciones, clases y niveles; la ficha abierta, solo si era de prueba)
local function ClearTest()
    for k = #events, 1, -1 do if events[k].test then table.remove(events, k) end end
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
        events[#events + 1] = { id = NewId() .. #events, title = title, kind = kind, t = t, who = who, tag = tag, desc = desc,
            signups = su or {}, raids = {}, test = true }
        return events[#events]
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
    Paint()
end

-- (crear eventos apagado: quién los crea según la configuración del calendario, calMake; con «Todos» siempre se
-- puede, así que no hay aviso)
local function NoMakeText()
    local who = HU:UnionCfg().calMake or "officers"
    return (who == "gm" and L("Solo el maestro crea eventos.")) or (who == "officers" and L("Solo los oficiales crean eventos.")) or nil
end
-- («+ Nuevo evento» del día, al pasar el ratón: solo el aviso, si está apagado)
local function NoMakeTip(s)
    if s:IsEnabled() then return end
    local text = NoMakeText()
    if not text then return end
    GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:SetText(text); GameTooltip:Show()
end
-- (el «+» de arriba, al pasar el ratón: su nombre y, si está apagado, el aviso debajo)
local function NewTip(s)
    GameTooltip:SetOwner(s, "ANCHOR_TOP"); GameTooltip:SetText(L("Nuevo evento"))
    local why = not s:IsEnabled() and NoMakeText()
    if why then GameTooltip:AddLine(why, 1, 1, 1, true) end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Montar la sección (UnionRoster.lua la pone en la pestaña Calendar)
---------------------------------------------------------------------------
function HU:BuildCalendar(host)
    ui = host
    local now = date("*t")
    month, year = now.month, now.year

    -- Arriba, el modo prueba (a la derecha); debajo, el «+» de nuevo evento (a la izquierda, ver más abajo) y
    -- Eventos · Calendario (en el centro)
    ui.viewBtns = {}
    local prev
    for _, t in ipairs({ { "list", L("Eventos") }, { "month", L("Calendario") } }) do
        local b = DJButton(host, t[2], 120, 24)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPRIGHT", host, "TOP", -2, -30) end
        b:SetScript("OnClick", function() view = t[1]; PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB); Paint() end)
        ui.viewBtns[t[1]] = b
        prev = b
    end
    local test = DJButton(host, L("Modo prueba"), 104, 24)
    test:SetPoint("TOPRIGHT", host, "TOPRIGHT", -26, -2)
    -- (el modo prueba se enciende y se apaga: apagado, se quita lo de prueba)
    test:SetScript("OnClick", function(b)
        if ui.testOn then ClearTest(); ui.testOn = nil else AddTest(); ui.testOn = true end
        b:Pick(ui.testOn == true)
        Paint()
    end)
    -- (el panel de la sección: color «content», borde y pergamino)
    local body = CreateFrame("Frame", nil, host, "BackdropTemplate")
    body:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -58); body:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)
    Panel(body, T.content, T.border, 14, 4)
    Parchment(body, 0.18)

    -- Eventos: tarjetas de 2 en 2
    local list = CreateFrame("Frame", nil, body, "BackdropTemplate")
    list:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -8); list:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 8)
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
    for i = 1, 4 do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local c = CreateFrame("Button", nil, list, "BackdropTemplate")
        c:SetHeight(CARD_H)
        if col == 0 then
            c:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -row * (CARD_H + CARD_GAP))
            c:SetPoint("RIGHT", area, "CENTER", -CARD_GAP / 2, 0)
        else
            c:SetPoint("TOPLEFT", area, "TOP", CARD_GAP / 2, -row * (CARD_H + CARD_GAP))
            c:SetPoint("RIGHT", area, "RIGHT", 0, 0)
        end
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
        topShade:SetPoint("TOPLEFT", 4, -4); topShade:SetPoint("TOPRIGHT", -4, -4); topShade:SetHeight(42)
        topShade:SetColorTexture(0, 0, 0, 0.42)
        local glow = c:CreateTexture(nil, "ARTWORK")
        glow:SetPoint("TOPLEFT", 4, -4); glow:SetPoint("TOPRIGHT", -4, -4); glow:SetHeight(1)
        glow:SetColorTexture(1.0, 0.84, 0.25, 0.30)
        local hl = c:CreateTexture(nil, "HIGHLIGHT")
        hl:SetPoint("TOPLEFT", 4, -4); hl:SetPoint("BOTTOMRIGHT", -4, 4); hl:SetColorTexture(1, 0.82, 0.18, 0.08)
        -- (icono redondo del tipo, título dorado con sombra y tipo · hora)
        c.icon = RoundIcon(c, 30)
        c.icon:SetPoint("TOPLEFT", 12, -9)
        c.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        C(c.title, { 1.00, 0.88, 0.24 }); c.title:SetShadowColor(0, 0, 0, 1); c.title:SetShadowOffset(1, -1)
        c.title:SetPoint("TOPLEFT", 54, -9); c.title:SetJustifyH("LEFT"); c.title:SetWordWrap(false)
        c.kind = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.kind:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -3)
        -- (arriba a la derecha: cuántos van)
        c.going = C(c:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), { 0.92, 0.92, 0.95 })
        c.going:SetPoint("TOPRIGHT", -10, -10)
        c.roles = C(c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), { 0.90, 0.90, 0.93 })
        c.roles:SetPoint("TOPRIGHT", c.going, "BOTTOMRIGHT", 0, -4)
        c.title:SetPoint("RIGHT", c.going, "LEFT", -8, 0)
        -- (abajo a la izquierda: el día grande, día de la semana y mes, y quién lo pone)
        c.num = c:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        C(c.num, T.title); Big(c.num, 26)
        c.num:SetPoint("BOTTOMLEFT", 12, 26)
        c.date = C(c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), { 0.90, 0.90, 0.93 })
        c.date:SetPoint("LEFT", c.num, "RIGHT", 6, 0); c.date:SetJustifyH("LEFT"); c.date:SetSpacing(1)
        c.who = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.who:SetPoint("BOTTOMLEFT", 12, 9); c.who:SetJustifyH("LEFT"); c.who:SetWordWrap(false)
        -- (abajo a la derecha: Apuntarme y Más información)
        c.info = DJButton(c, L("Más información"), 116, 22)
        c.info:SetPoint("BOTTOMRIGHT", -8, 8)
        c.info:SetScript("OnClick", function() if c.id then OpenDetail(c.id) end end)
        c.join = DJButton(c, L("Apuntarme"), 96, 22)
        c.join:SetPoint("BOTTOMRIGHT", c.info, "TOPRIGHT", 0, 4)
        c.join:SetScript("OnClick", function(s) local e = c.id and Find(c.id); if e then SignUp(e, s) end end)
        c.who:SetPoint("RIGHT", c.info, "LEFT", -6, 0)
        -- (al pasar el ratón, borde dorado)
        c:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(T.hover[1], T.hover[2], T.hover[3], 1) end)
        c:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(0.34, 0.34, 0.34, 1) end)
        c:SetScript("OnClick", function(s) if s.id then OpenDetail(s.id) end end)
        ui.cards[i] = c
    end
    -- (la rueda del ratón mueve la barra de una fila de tarjetas en una fila)
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
    side:SetPoint("TOPRIGHT", -10, -10); side:SetPoint("BOTTOMRIGHT", -10, 10); side:SetWidth(220)
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
        b:SetScript("OnClick", function(s) OpenDetail(s.id) end)
        b:Hide()
        side.dayBtns[i] = b
    end
    -- (abajo del panel del día: nuevo evento ese día)
    side.new = DJButton(side, "+ " .. L("Nuevo evento"), 180, 24)
    side.new:SetPoint("BOTTOM", 0, 8)
    side.new:SetScript("OnClick", function()
        if not pickedDay then return end
        local y, m, dd = pickedDay:match("(%d+)-(%d+)-(%d+)")
        ui.newDlg.Open(time({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 }))
    end)
    side.new:SetScript("OnEnter", NoMakeTip)
    side.new:SetScript("OnLeave", function() GameTooltip:Hide() end)
    side.new:SetMotionScriptsWhileDisabled(true)

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

    -- Debajo, a la izquierda: «+», nuevo evento (quien puede crearlos, HU:CanMakeEvents, o con el modo prueba); en
    -- Calendario, para el día elegido
    -- (el verde claro de DJ.Plus, como el de Comercio; apagado, gris)
    local new = DJ.Plus(host, 26)
    new:SetPoint("TOPLEFT", host, "TOPLEFT", 14, -30)
    new:SetScript("OnClick", function()
        local t
        if view == "month" and pickedDay then
            local y, m, dd = pickedDay:match("(%d+)-(%d+)-(%d+)")
            t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 })
        end
        ui.newDlg.Open(t)
    end)
    new:SetScript("OnEnter", NewTip)
    new:SetScript("OnLeave", function() GameTooltip:Hide() end)
    new:SetMotionScriptsWhileDisabled(true)
    ui.new = new

    host:HookScript("OnShow", Paint)
    host:HookScript("OnHide", function() selected = nil; ui.detail:Hide() end)
    Paint()
end

-- (si cambia quién crea eventos, el «+» de arriba y el «+ Nuevo evento» del día se ponen al día)
HU:Listen("CHANGED", function(what) if what == "unionCfg" then Paint() end end)

HU:Module("UnionCalendar", { "BlizzTab", "Config", "Core", "ListWindow", "UnionConfig" })
