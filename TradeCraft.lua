-- Guild Union - Comercio: los objetos (lo que el juego sabe de ellos y si son BOE), los fabricables y quién de la unión los
-- hace, y ¿puedo hacerlo? (mis profesiones y mis recetas). Comparte lo suyo por HU.TradeInternal (Trade.lua) [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L

-- (las recetas de cada profesión, leídas al abrir su ventana: ver ReadRecipes)
HU:Saved({ char = { "tradeRecipes" } })

local T = HU.TradeInternal
local Plain, Status = T.Plain, T.Status

local BIND_EQUIP = (Enum and Enum.ItemBind and Enum.ItemBind.OnEquip) or 2

---------------------------------------------------------------------------
-- Objetos: lo que el juego sabe de ellos (C_Item; en Forever no hay GetItemInfo suelto) y si son BOE [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local function Pack(...) return { n = select("#", ...), ... } end
local function Num(v) return (type(v) == "number" and not HU.Secret(v)) and v or nil end
-- (de un objeto (número, nombre o enlace): { name, link, q (calidad), il (nivel de objeto), rl (nivel requerido: el que
-- pide para usarlo; 0, ninguno), cls (clase), bind (ligado) }; nil si el juego aún no lo tiene)
local function ItemInfo(item)
    local get = C_Item and C_Item.GetItemInfo
    if type(get) ~= "function" then return nil end
    local res = Pack(pcall(get, item))
    local name, link = res[2], res[3]
    if not (res[1] and type(name) == "string" and type(link) == "string") or HU.Secret(name) or HU.Secret(link) then return nil end
    return { name = name, link = link, q = Num(res[4]), il = Num(res[5]), rl = Num(res[6]), cls = Num(res[13]),
        bind = Num(res[15]) }
end

-- Fabricables (CraftItems.lua): el juego da su nombre y enlace en tu idioma; se piden poco a poco (30 cada
-- medio segundo) desde que se monta la sección (al cargar la ventana de hermandad del juego), y los que tarda se
-- reintentan dos vueltas más. De paso se guardan su calidad, sus niveles y su clase, para Buscar [+ARCHITECTURE.md]
local craft = {}            -- [objeto] (o ["s" .. hechizo]) = { key = nombre en minúsculas, link, skill, lv, q, il, rl, cls, bind }
T.craft = craft
T.findDirty = true          -- Buscar: la lista de objetos que encajan, por rehacer (cambia un filtro o llegan objetos)
-- (los encantamientos son hechizos, no objetos: el juego da su nombre y su enlace al momento, sin pedirlos)
local function LoadCraftSpells()
    local S = C_Spell
    if type(HU.CRAFT_SPELLS) ~= "table" or not (S and S.GetSpellName and S.GetSpellLink) then return end
    for skill, list in pairs(HU.CRAFT_SPELLS) do
        for i = 1, #list - 1, 2 do
            local id = list[i]
            local okN, name = pcall(S.GetSpellName, id)
            local okL, link = pcall(S.GetSpellLink, id)
            if okN and okL and type(name) == "string" and type(link) == "string" and not HU.Secret(name)
                and not HU.Secret(link) then
                craft["s" .. id] = { key = HU.Fold(name), link = link, skill = skill, lv = list[i + 1] }
                T.findDirty = true
            end
        end
    end
end
local function LoadCraftNames()
    if T.craftLoader or type(HU.CRAFT_ITEMS) ~= "table" then return end
    LoadCraftSpells()
    local queue, info = {}, {}
    for skill, list in pairs(HU.CRAFT_ITEMS) do
        for i = 1, #list - 1, 2 do
            if not info[list[i]] then queue[#queue + 1] = list[i] end
            info[list[i]] = { skill = skill, lv = list[i + 1] }
        end
    end
    local pos, pass, missing = 1, 1, {}
    T.craftLoader = HU:Every(0.5, "Comercio: nombres", function()
        for _ = 1, 30 do
            local id = queue[pos]
            if not id then
                -- (una vuelta entera: con Buscar a la vista, se pinta lo que ha llegado; al acabar, sin las flechas de
                -- «cargando» (`done`))
                local last = pass >= 3 or #missing == 0
                if last then T.craftLoader:Cancel(); T.craftLoader.done = true end
                if T.ui and T.view == "find" and T.ui:IsVisible() then T.Paint() end
                if last then return end
                queue, missing, pos, pass = missing, {}, 1, pass + 1
                return
            end
            pos = pos + 1
            local it = ItemInfo(id)
            if it then
                craft[id] = { key = HU.Fold(it.name), link = it.link, skill = info[id].skill, lv = info[id].lv, q = it.q,
                    il = it.il, rl = it.rl, cls = it.cls, bind = it.bind }
                T.findDirty = true
            else
                missing[#missing + 1] = id
            end
        end
    end, { pauseInCombat = true })
end

-- (el número del objeto que pide un anuncio: su enlace o, lo escrito a mano, el nombre exacto de un fabricable; un
-- hechizo o un encantamiento no es un objeto)
local function ItemIdOf(item)
    if type(item) ~= "string" or HU.Secret(item) then return nil end
    local id = item:match("|Hitem:(%d+)")
    if id then return tonumber(id) end
    if item:find("|H", 1, true) then return nil end
    local name = HU.Fold(Plain(item)):gsub("^%s*%[", ""):gsub("%]%s*$", "")
    for k, c in pairs(craft) do if type(k) == "number" and c.key == name then return k end end
    return nil
end
-- ¿Es BOE (se liga al equipar, de verde a legendario)? true o false, y el número del objeto. nil si el juego aún no lo
-- conoce: se le pide y avisa al llegar (ITEM_DATA_LOAD_RESULT). Lo que no es un objeto, no [+ARCHITECTURE.md]
local function BoeOf(item)
    local id = ItemIdOf(item)
    if not id then return false end
    local it = ItemInfo(id)
    if not it then
        local ask = C_Item and C_Item.RequestLoadItemDataByID
        if type(ask) == "function" then pcall(ask, id) end
        return nil, id
    end
    local q = it.q or 0
    return it.bind == BIND_EQUIP and q >= 2 and q <= 5, id
end

---------------------------------------------------------------------------
-- Quién lo hace: los de toda la unión con su línea de oficios y los de mi hermandad con lo que da la comunidad
---------------------------------------------------------------------------
-- (las profesiones y el nivel que hacen falta para algo que encaje con q, por su nombre, y lo que encaja ([clave] = true).
-- Solo cuenta lo que mejor encaja: con «bolsa», lo que lleva esa palabra entera y no «Bolsas» ni «Embolsar», si lo hay.
-- Jorge, 24/11: «más al grano»)
local function CraftNeeds(q)
    local needs, keys, best = {}, {}, nil
    for k, c in pairs(craft) do
        local r = HU.TextRank(c.key, q)
        if r then
            local tier = (r <= 2 and 1) or (r <= 4 and 2) or 3
            if not best or tier < best then best, needs, keys = tier, {}, {} end
            if tier == best then
                keys[k] = true
                if needs[c.skill] == nil or c.lv < needs[c.skill] then needs[c.skill] = c.lv end
            end
        end
    end
    if not best then return nil, nil end
    return needs, keys
end

-- (los de mi hermandad con sus profesiones de la comunidad, { name, tag, prof, icon, id, online, rank } por profesión; se
-- leen una vez por repintado)
local clubRows
local function ClubRows()
    if clubRows then return clubRows end
    clubRows = {}
    local cid = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local ok, ids = false, nil
    if cid and not HU.Secret(cid) then ok, ids = pcall(C_Club.GetClubMembers, cid) end
    for _, id in ipairs((ok and type(ids) == "table") and ids or {}) do
        local ok2, info = pcall(C_Club.GetMemberInfo, cid, id)
        local n = ok2 and info and info.name
        if type(n) == "string" and not HU.Secret(n) then
            local off = Enum and Enum.ClubMemberPresence and info.presence == Enum.ClubMemberPresence.Offline
            local full = HU:FullName(n) or n
            for _, p in ipairs(HU:ClubProfessions(info)) do
                clubRows[#clubRows + 1] = { name = full, tag = HU.myTag, prof = p.name, icon = p.icon, id = p.id,
                    online = not off, rank = p.rank }
            end
        end
    end
    return clubRows
end
local function ClubRow(m) return { name = m.name, tag = m.tag, prof = m.prof, icon = m.icon, online = m.online, rank = m.rank } end

-- Cuántos de mi hermandad tienen cada profesión principal, de lo que da el juego (sin addon): { { name, icon, id, n }, de
-- más a menos; id, su número }. Para las estadísticas (GuildStats.lua). Se lee fresco porque se abre aparte de Comercio [+ARCHITECTURE.md]
function HU:GuildProfessionCounts()
    clubRows = nil
    local by = {}
    for _, r in ipairs(ClubRows()) do
        if type(r.prof) == "string" and r.prof ~= "" then
            local e = by[r.prof] or { name = r.prof, icon = r.icon, id = r.id, n = 0 }
            e.n, by[r.prof] = e.n + 1, e
        end
    end
    local out = {}
    for _, e in pairs(by) do out[#out + 1] = e end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    return out
end
-- (¿tiene ya línea de oficios de esa profesión? Entonces vale lo que dice su línea, también si seguro que no sabe la
-- receta: no sale otra vez con lo que da el juego)
local function HasLine(name, skill)
    for _, p in ipairs(HU:UnionProfessionsOf(name) or {}) do if p.id == skill then return true end end
    return false
end

-- «Quién lo hace»: los de toda la unión con su línea de oficios (Packs/Professions.lua: nivel de verdad y si saben la
-- receta, también desconectados) y los de mi hermandad que no la tienen, con lo que da el juego [+ARCHITECTURE.md]
local function SearchMembers(q)
    q = q:lower()
    local out, have = {}, {}
    local needs, keys = CraftNeeds(q)
    for _, r in ipairs(HU:UnionCrafters(q, keys, needs)) do
        r.online = Status(r.name)
        out[#out + 1] = r
        have[(HU:Key(r.name) or r.name) .. "|" .. r.skill] = true
    end
    for _, m in ipairs(ClubRows()) do
        -- (solo al buscar por nombre de profesión: ahí sí quieres a todos los que la tienen. Al buscar un objeto, de
        -- mi hermandad no se sabe las recetas, así que no se añaden: solo sale quien lo confirma. Jorge, 25/11)
        if not have[m.name:lower() .. "|" .. tostring(m.id)] and not HasLine(m.name, m.id) and HU.TextRank(m.prof, q) then
            out[#out + 1] = ClubRow(m)
        end
    end
    -- (primero quien sabe la receta; luego los de nivel sabido, de más a menos; los demás, detrás)
    table.sort(out, function(a, b)
        if (a.knows == true) ~= (b.knows == true) then return a.knows == true end
        local ra, rb = a.rank or -1, b.rank or -1
        if ra ~= rb then return ra > rb end
        return a.name < b.name
    end)
    return out
end

-- (el nombre de cada profesión de CraftItems.lua, para decir cuál te falta)
local PROF_NAMES = { [129] = "Primeros auxilios", [164] = "Herrería", [165] = "Peletería", [171] = "Alquimia",
    [185] = "Cocina", [186] = "Minería", [197] = "Sastrería", [202] = "Ingeniería", [333] = "Encantamiento" }

-- (los fabricables por su número: [objeto] o ["s" .. hechizo] = { { id, spell, skill, lv }, ... }, uno por profesión
-- que lo hace y en orden de profesión; se monta la primera vez que hace falta)
local craftIndex
local function CraftIndex()
    if craftIndex then return craftIndex end
    craftIndex = {}
    for _, src in ipairs({ { HU.CRAFT_ITEMS, false }, { HU.CRAFT_SPELLS, true } }) do
        for skill, list in pairs(type(src[1]) == "table" and src[1] or {}) do
            for i = 1, #list - 1, 2 do
                local k = src[2] and ("s" .. list[i]) or list[i]
                craftIndex[k] = craftIndex[k] or {}
                table.insert(craftIndex[k], { id = list[i], spell = src[2], skill = skill, lv = list[i + 1] })
            end
        end
    end
    for _, e in pairs(craftIndex) do table.sort(e, function(a, b) return a.skill < b.skill end) end
    return craftIndex
end

-- Quién lo hace un fabricable (su clave): los de la unión con su línea de oficios que lo saben o tienen el nivel, y los de
-- mi hermandad sin línea que tienen la profesión; conectados primero, luego quien sabe la receta y por nivel
local crafters = {}         -- [clave] = quién lo hace (se vacía en cada repintado)
local function CraftersOf(key)
    if crafters[key] then return crafters[key] end
    local needs = {}
    for _, t in ipairs(CraftIndex()[key] or {}) do
        if needs[t.skill] == nil or t.lv < needs[t.skill] then needs[t.skill] = t.lv end
    end
    local out = {}
    for _, r in ipairs(HU:UnionCrafters(nil, { [key] = true }, needs)) do
        r.online = Status(r.name)
        out[#out + 1] = r
    end
    -- (de mi hermandad por la lista del juego no se sabe qué recetas tienen, solo la profesión: por eso ya no se
    -- añaden aquí. Solo sale quien lo confirma con su línea de oficios. Jorge, 25/11)
    table.sort(out, function(a, b)
        if (a.online == true) ~= (b.online == true) then return a.online == true end
        if (a.knows == true) ~= (b.knows == true) then return a.knows == true end
        local ra, rb = a.rank or -1, b.rank or -1
        if ra ~= rb then return ra > rb end
        return a.name < b.name
    end)
    crafters[key] = out
    return out
end
-- (cada repintado vuelve a leer a los de mi hermandad y quién lo hace cada objeto: Paint, TradeView.lua)
local function ResetCrafters() clubRows, crafters = nil, {} end
-- (el icono de una profesión, el del juego, si lo da: se recuerda)
local profIcons = {}
local function ProfLabel(skill)
    if profIcons[skill] == nil then
        local f = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture
        local ok, tex = false, nil
        if type(f) == "function" then ok, tex = pcall(f, skill) end
        profIcons[skill] = (ok and tex and not HU.Secret(tex)) and tex or false
    end
    local icon = profIcons[skill]
    return (icon and ("|T" .. icon .. ":14:14|t ") or "") .. L(PROF_NAMES[skill] or "?")
end

---------------------------------------------------------------------------
-- ¿Puedo hacerlo? Mis profesiones (el juego las da siempre) y mis recetas (solo con la ventana de la profesión abierta:
-- se guardan al abrirla) [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- (lo que pide una solicitud, entre los fabricables: su lista de CraftIndex, o nil si no se reconoce. Un enlace de
-- objeto o de encantamiento, por su número; lo escrito a mano, por el nombre exacto que da el juego)
local function CraftTargets(item)
    if type(item) ~= "string" or HU.Secret(item) then return nil end
    local idx = CraftIndex()
    local id = item:match("|Hitem:(%d+)")
    if id then return idx[tonumber(id)] end
    id = item:match("|Hspell:(%d+)") or item:match("|Henchant:(%d+)")
    if id then return idx["s" .. id] end
    local name = HU.Fold(Plain(item)):gsub("^%s*%[", ""):gsub("%]%s*$", "")
    for k, c in pairs(craft) do if c.key == name then return idx[k] end end
    return nil
end

-- (mis profesiones: [número] = nivel; false si el juego no las da: entonces no se puede comprobar)
local function MyProfessions()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return false end
    local res = Pack(pcall(GetProfessions))
    if not res[1] then return false end
    local out, byName = {}, {}
    for i = 2, res.n do
        if type(res[i]) == "number" then
            -- (nombre, icono, nivel, máximo, hechizos, desplazamiento, número de profesión…)
            local ok, name, _, rank, _, _, _, skill = pcall(GetProfessionInfo, res[i])
            if ok and type(skill) == "number" and not HU.Secret(skill) then
                out[skill] = (type(rank) == "number" and not HU.Secret(rank)) and rank or 0
                if type(name) == "string" and not HU.Secret(name) then byName[name:lower()] = out[skill] end
            end
        end
    end
    return out, byName
end

-- Las profesiones de alguien de mi hermandad, de su ficha en la comunidad (C_Club.GetMemberInfo): { id, name, icon,
-- guid, rank }. En Forever la comunidad da siempre nivel 1 (Jorge, 24/11: su Herboristería 195 y su Minería 111 salían a
-- 1): el mío sale de mi personaje, como en Comercio; el de los demás no se sabe y queda sin nivel (nil). Lo usan la
-- columna de profesiones y la ficha (UnionRoster.lua) y «Quién lo hace», por HU:ClubProfessions (Trade.lua) [+ARCHITECTURE.md]
local function ClubProfessions(info)
    local out = {}
    if type(info) ~= "table" then return out end
    local mine, mineByName
    if info.isSelf == true then mine, mineByName = MyProfessions() end
    for _, k in ipairs({ "1", "2" }) do
        local pid, pn, pr = info["profession" .. k .. "ID"], info["profession" .. k .. "Name"], info["profession" .. k .. "Rank"]
        if type(pn) == "string" and pn ~= "" and not HU.Secret(pn) then
            local icon
            if type(pid) == "number" and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture then
                local okI, tex = pcall(C_TradeSkillUI.GetTradeSkillTexture, pid)
                if okI and tex and not HU.Secret(tex) then icon = tex end
            end
            local rank = (type(pr) == "number" and not HU.Secret(pr) and pr > 1) and pr or nil
            if mine then rank = (type(pid) == "number" and mine[pid]) or mineByName[pn:lower()] or rank end
            out[#out + 1] = { id = pid, name = pn, icon = icon, guid = info.guid, rank = rank }
        end
    end
    return out
end

-- Si puedo hacer lo que pide `item` (un enlace o lo escrito): ok y, si no, el porqué. Lo que no se reconoce, o sin poder
-- leer mis profesiones, sí: no se puede comprobar. `profs`: las de MyProfessions (HU:CanCraft, Trade.lua) [+ARCHITECTURE.md]
local function CraftCheck(item, profs)
    local targets = CraftTargets(item)
    if not (targets and profs) then return true end
    local saved = (HU.db and HU.db.tradeRecipes) or {}
    local why
    for _, t in ipairs(targets) do
        local rank = profs[t.skill]
        if rank then
            local rec = saved[t.skill]
            local known = type(rec) == "table" and rec[t.spell and "spells" or "items"]
            if type(known) == "table" and known[t.id] then return true end
            if rank < t.lv then why = why or string.format(L("Te falta nivel (%d)"), t.lv)
            elseif type(rec) == "table" and rec.full then why = why or L("No tienes la receta")
            else return true end
        end
    end
    return false, why or string.format(L("Te falta %s"), L(PROF_NAMES[targets[1].skill] or "?"))
end

-- Recetas: al abrir la ventana de una profesión mía, las aprendidas (su número, que es el del hechizo, y el objeto que
-- crean) se guardan por personaje en `tradeRecipes[profesión]`. Con un filtro puesto en esa ventana la lista no viene
-- entera: se suman a las de antes y no cuenta como leída entera (`full`) [+ARCHITECTURE.md]
local RECIPE_FILTERS = { "GetOnlyShowMakeableRecipes", "GetOnlyShowSkillUpRecipes", "GetOnlyShowFirstCraftRecipes",
    "AreAnyInventorySlotsFiltered", "AnyRecipeCategoriesFiltered" }
-- (una función de C_TradeSkillUI, si el juego la tiene; nil si no o si falla)
local function TS(fn, ...)
    local f = C_TradeSkillUI and C_TradeSkillUI[fn]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, ...)
    if ok and not HU.Secret(v) then return v end
    return nil
end
local function Unfiltered()
    for _, fn in ipairs(RECIPE_FILTERS) do if TS(fn) then return false end end
    local text = TS("GetRecipeItemNameFilter")
    return TS("GetShowLearned") ~= false and not (type(text) == "string" and text ~= "")
end
local readQueued
local function ReadRecipes()
    readQueued = nil
    local db = HU.db
    if not db or TS("IsTradeSkillReady") == false or TS("IsDataSourceChanging") then return end
    -- (la de otro (enlazada o de la hermandad) o la de un PNJ no es la mía)
    if TS("IsTradeSkillLinked") or TS("IsTradeSkillGuild") or TS("IsTradeSkillGuildMember") or TS("IsNPCCrafting") then return end
    local info = TS("GetChildProfessionInfo")
    if type(info) ~= "table" or not info.professionID or info.professionID == 0 then info = TS("GetBaseProfessionInfo") end
    local skill = type(info) == "table" and (info.parentProfessionID or info.professionID)
    if type(skill) ~= "number" or skill == 0 then return end
    local ids, full = TS("GetAllRecipeIDs"), true
    if type(ids) ~= "table" then ids, full = TS("GetFilteredRecipeIDs"), Unfiltered() end
    if type(ids) ~= "table" then return end
    local items, spells = {}, {}
    for _, id in ipairs(ids) do
        local r = TS("GetRecipeInfo", id)
        if type(r) == "table" and r.learned == true then
            spells[id] = true
            local s = TS("GetRecipeSchematic", id, false)
            if type(s) == "table" and type(s.outputItemID) == "number" then items[s.outputItemID] = true end
        end
    end
    -- (ninguna aprendida: la ventana aún no las ha dado; no se pisa lo guardado)
    if next(spells) == nil then return end
    db.tradeRecipes = db.tradeRecipes or {}
    local old = db.tradeRecipes[skill]
    if not full and type(old) == "table" then
        for k in pairs(old.items or {}) do items[k] = true end
        for k in pairs(old.spells or {}) do spells[k] = true end
        full = old.full
    end
    db.tradeRecipes[skill] = { t = time(), full = full or nil, items = items, spells = spells }
    if T.ui and T.ui:IsShown() then T.Paint() end
end
-- (la ventana avisa varias veces seguidas al abrirse y con cada cambio: se lee una vez, un momento después)
local function QueueRead()
    if readQueued then return end
    readQueued = true
    HU.After(0.3, ReadRecipes)
end
HU:On("TRADE_SKILL_SHOW", QueueRead)
HU:On("TRADE_SKILL_LIST_UPDATE", QueueRead)

T.ItemInfo, T.LoadCraftNames, T.BoeOf, T.SearchMembers, T.CraftIndex, T.CraftersOf = ItemInfo, LoadCraftNames, BoeOf, SearchMembers, CraftIndex, CraftersOf
T.ResetCrafters, T.ProfLabel, T.CraftTargets, T.MyProfessions = ResetCrafters, ProfLabel, CraftTargets, MyProfessions
T.ClubProfessions, T.CraftCheck, T.PROF_NAMES = ClubProfessions, CraftCheck, PROF_NAMES

HU:Module("TradeCraft", { "Core", "Packs/Professions", "Trade" })
