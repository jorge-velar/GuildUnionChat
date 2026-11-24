-- Guild Union - Comercio (la sección Trade de la lista de miembros) [+ARCHITECTURE.md]
-- Fase 1 (copias 211-214): solo la ventana, sin red. Lo que se pide o se escribe se queda en tu sesión, y
-- HU:TradeTest (solo por código: las pruebas) la rellena de solicitudes y chats de mentira. Diseño:
-- Obsidian/Addons/GuildUnion - Comercio (diseño).md
local _, HU = ...
local L = HU.L

-- (las recetas de cada profesión, leídas al abrir su ventana, y la casilla «Solo lo que puedo hacer»)
HU:Saved({ char = { "tradeRecipes", "tradeOnlyCraft" } })

-- (filas y títulos de 24, con 4 de margen a cada lado del texto: Jorge, 24/11, «muy apelotonado». Caben en la sección
-- con la ventana del juego a su alto de siempre: comercio_spec)
local ROW_H, ROWS = 24, 9
local HDR_H, CELL_PAD = 24, 4
-- (arriba, dos filas: los botones Tablón · Mis encargos (DJ.Switch) y, en ROW2_Y, el buscador y la casilla; las
-- listas van de BODY_Y a BOTTOM_H por encima del borde de abajo, donde va «+ Nueva solicitud» (24 de alto, a 8 del
-- borde), para que no tape nada) [+ARCHITECTURE.md]
local ROW2_Y, ROW2_H = -36, 28   -- (más pegada a los botones: Jorge, 24/11, «sube un poco más»)
local BODY_Y, BOTTOM_H = -74, 36   -- (la lista, 6 por debajo del buscador: Jorge, 24/11, «un poco menos» de gris)
local SEARCH_W = 200
local SEARCH_ROWS = 3       -- al buscar: filas de cada mitad (publicadas arriba, quién lo hace abajo)
local MAX_OPEN = 5          -- solicitudes abiertas por persona
local MINE, OTHERS = "|cff4da6ff", "|cffffd100"
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local CHAT_W = 200
local DOT_ON = "|TInterface\\FriendsFrame\\StatusIcon-Online:10:10|t"
local DOT_OFF = "|TInterface\\FriendsFrame\\StatusIcon-Offline:10:10|t"
local testOnline = { ["Pepe-Prueba"] = true, ["Bea-Prueba"] = true, ["Lyra-Prueba"] = false, ["Jandra-Prueba"] = false }
local ACT_W = 84            -- la última columna: el botón (Aceptar / Cancelar) o quién la aceptó
local COIN_ICON = { "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon" }
local GOLD = { 1, 0.82, 0.2 }

-- Botones con el estilo del Dungeon Journal (DJStyle.lua): rojos, y negros los elegidos
local DJ = HU.DJ
local function Flat(parent, text, w, h) return DJ.Button(parent, text, w, h) end

-- Columnas: en el Tablón, con materiales; en Mis encargos (más estrecha, con el chat al lado), sin ellos
local COLS = {
    pub = { { "who", "Quién", 100 }, { "item", "Receta / objeto", 170 }, { "qty", "Cant.", 40 }, { "mats", "Mats", 44 }, { "tip", "Propina", 66 }, { "state", "Estado", 0 },
        { "act", "Acción", ACT_W + 6 } },
    priv = { { "who", "Con quién", 86 }, { "item", "Receta / objeto", 120 }, { "qty", "Cant.", 36 }, { "tip", "Propina", 56 }, { "state", "Estado", 0 } },
    search = { { "who", "Quién", 110 }, { "guild", "Hermandad", 80 }, { "prof", "Profesión", 130 }, { "lvl", "Nivel", 0 } },
}

-- (en la sesión: fase 1, sin red)
local reqs = {}             -- { id, who, item, mats, tip, state = "open"|"taken"|"done"|"gone", taker, pub, to, t, test }
local chats = {}            -- [persona] = { líneas }: uno por persona
local unread = {}           -- [persona] = sus líneas sin leer (llegadas con su chat fuera de la pantalla)
local chatKey
local view = "pub"          -- "pub": el Tablón; "priv": Mis encargos
local sortKey, sortDesc     -- nil: lo más nuevo arriba; si no, por esa columna (clic en su título), si la vista la tiene
local PUB_KEEP = 600        -- una aceptada sigue 10 min en el Tablón
local selected
local picks = {}            -- Mis encargos: las elegidas con Ctrl / Mayús (para eliminar varias)
local lastPick              -- la última elegida (para Mayús)
local ui
local Paint

local function Me() return HU:Me() or "?" end
local function IsMine(r) return r.who == Me() end
-- (id: huella del nombre de quien la pide, la hora, un contador de la sesión y algo de azar, en 16 cifras: con la red,
-- distinto en toda la unión aunque dos pidan en el mismo segundo o el azar se repita)
local idSeq = 0
local function NewId()
    idSeq = (idSeq + 1) % 256
    return string.format("%s%06x%02x%04x", HU.Hash(Me()):sub(1, 4), time() % 0x1000000, idSeq, math.random(0, 0xffff))
end
-- (en una privada, la otra persona: a quién se la pido o quién la hace, o quién me la pide)
local function Other(r) if IsMine(r) then return r.taker or r.to end return r.who end
local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")) end
-- (cobre -> «2 [oro] 50 [plata]», con los iconos)
local function Coins(c)
    local g, sv, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out = {}
    for i, v in ipairs({ g, sv, cu }) do
        if v > 0 then out[#out + 1] = v .. "|T" .. COIN_ICON[i] .. ":12:12|t" end
    end
    return #out > 0 and table.concat(out, " ") or ("0|T" .. COIN_ICON[3] .. ":12:12|t")
end
-- (quién está conectado: mi hermandad, las listas de las otras y los que tienen GuildUnion; se rehace en
-- cada repintado) [+ARCHITECTURE.md]
local onlineMap = {}
local function BuildOnline()
    onlineMap = {}
    for k, v in pairs(testOnline) do onlineMap[k:lower()] = v end
    for _, e in ipairs(HU.rosterList or {}) do
        if type(e.name) == "string" then onlineMap[e.name:lower()] = e.online and true or false end
    end
    for _, rr in pairs(HU.remoteRoster or {}) do
        for _, m in ipairs(rr.members or {}) do
            if type(m.name) == "string" and onlineMap[m.name:lower()] == nil then onlineMap[m.name:lower()] = m.online ~= false end
        end
    end
    local now = GetTime()
    for _, pr in pairs(HU.remote or {}) do
        if type(pr.name) == "string" and type(pr.last) == "number" and now - pr.last < 300 then onlineMap[pr.name:lower()] = true end
    end
end
local function Dot(name)
    if name == HU:Me() then return DOT_ON end
    local full = type(name) == "string" and (HU:FullName(name) or name) or ""
    return onlineMap[full:lower()] and DOT_ON or DOT_OFF
end
local function Searching() return ui and HU.Trim(ui.search:GetText() or "") ~= "" end
local function Query()
    local t = Plain(HU.Trim(ui.search:GetText() or ""))
    return (t:gsub("^%[", ""):gsub("%]$", "")):lower()
end
-- (¿me toca a mí? la pedí yo, me la piden a mí o la hago yo)
local function Involved(r) return IsMine(r) or r.to == Me() or r.taker == Me() end

---------------------------------------------------------------------------
-- Sin leer: las líneas de otro que llegan con su chat fuera de la pantalla [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- (¿se ve ahora el chat con esa persona? la sección a la vista, en Mis encargos sin buscar y con su chat puesto)
local function ChatOnScreen(key)
    return ui ~= nil and key ~= nil and key == chatKey and view == "priv" and ui:IsVisible() and not Searching()
        and not HU:UnionCfg().tradeOff
end
-- Cuántas líneas hay sin leer, entre todos los chats (UnionRoster.lua hace brillar la pestaña de Comercio)
function HU:TradeUnread()
    local n = 0
    for _, c in pairs(unread) do n = n + c end
    return n
end
-- (la pestaña Mis encargos, con el número: «Mis encargos (2)»)
local function PaintUnread()
    local b = ui and ui.viewBtns and ui.viewBtns.priv
    if not b then return end
    local n = HU:TradeUnread()
    b:Label(n > 0 and string.format(L("Mis encargos (%d)"), n) or L("Mis encargos"))
end
local function MarkRead(key)
    if not (key and unread[key]) then return end
    unread[key] = nil
    PaintUnread()
    HU:Changed("tradeUnread")
end
-- (detrás del nombre en Mis encargos: cuántas suyas hay sin leer)
local function UnreadMark(key)
    local n = key and unread[key]
    return n and (" |cff40ff40(" .. n .. ")|r") or ""
end

---------------------------------------------------------------------------
-- Chat (derecha, solo en Mis encargos): el de la persona del comercio que eliges. Solo se ve aquí
---------------------------------------------------------------------------
local function ChatLine(key, who, text)
    chats[key] = chats[key] or {}
    local line = (who == Me() and MINE or OTHERS) .. HU:Short(who) .. "|r: " .. text
    local l = chats[key]
    l[#l + 1] = line
    if #l > 200 then table.remove(l, 1) end
    if key == chatKey and ui then ui.msgs:AddMessage(line) end
    -- (de otro y con su chat fuera de la pantalla: sin leer; nunca más de las que guarda el chat)
    if who ~= Me() and not ChatOnScreen(key) then
        unread[key] = math.min(#l, (unread[key] or 0) + 1)
        PaintUnread()
        HU:Changed("tradeUnread")
    end
end
-- Una línea en el chat con `key`: hoy, las mías y las del modo prueba; con la red, también las que lleguen
function HU:TradeChatLine(key, who, text) ChatLine(key, who, text) end

local function OpenChat(key)
    chatKey = key
    if not ui then return end
    ui.msgs:Clear()
    if ui.chatInput then
        if key then ui.chatInput:Enable() else ui.chatInput:SetText(""); ui.chatInput:ClearFocus(); ui.chatInput:Disable() end
        ui.chatHint:SetShown(not key)
    end
    ui.chatTitle:SetText(key and (OTHERS .. HU:Short(key) .. "|r " .. Dot(key)) or ("|cff808080" .. L("Elige un comercio para hablar") .. "|r"))
    for _, line in ipairs(key and chats[key] or {}) do ui.msgs:AddMessage(line) end
    if ChatOnScreen(key) then MarkRead(key) end
end

---------------------------------------------------------------------------
-- Buscar: arriba, las publicadas que encajan (por quién la pide, el objeto o quién la aceptó); abajo, quién lo
-- hace: los de mi hermandad con una profesión que encaja o con la de un fabricable que encaja (las da el juego).
-- Las otras hermandades, con la red
---------------------------------------------------------------------------
-- Fabricables (CraftItems.lua): el juego da su nombre y enlace en tu idioma; se piden poco a poco (30 cada
-- medio segundo) desde que se monta la sección (al cargar la ventana de hermandad del juego), y los que tarda se
-- reintentan dos vueltas más [+ARCHITECTURE.md]
local craft = {}            -- [objeto] (o ["s" .. hechizo]) = { key = nombre en minúsculas, link, skill, lv }
local craftLoader
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
            end
        end
    end
end
local function LoadCraftNames()
    if craftLoader or type(HU.CRAFT_ITEMS) ~= "table" then return end
    LoadCraftSpells()
    local queue, info = {}, {}
    for skill, list in pairs(HU.CRAFT_ITEMS) do
        for i = 1, #list - 1, 2 do
            if not info[list[i]] then queue[#queue + 1] = list[i] end
            info[list[i]] = { skill = skill, lv = list[i + 1] }
        end
    end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local pos, pass, missing = 1, 1, {}
    craftLoader = HU:Every(0.5, "Comercio: nombres", function()
        for _ = 1, 30 do
            local id = queue[pos]
            if not id then
                if pass >= 3 or #missing == 0 then craftLoader:Cancel(); return end
                queue, missing, pos, pass = missing, {}, 1, pass + 1
                return
            end
            pos = pos + 1
            local ok, name, link = pcall(get, id)
            if ok and type(name) == "string" and type(link) == "string" and not HU.Secret(name) then
                craft[id] = { key = HU.Fold(name), link = link, skill = info[id].skill, lv = info[id].lv }
            else
                missing[#missing + 1] = id
            end
        end
    end, { pauseInCombat = true })
end

-- (las profesiones y el nivel que hacen falta para algo que encaje con q, por su nombre. Solo cuenta lo que mejor encaja:
-- con «bolsa», lo que lleva esa palabra entera y no «Bolsas» ni «Embolsar», si lo hay. Jorge, 24/11: «más al grano»)
local function CraftNeeds(q)
    local needs, best = {}, nil
    for _, c in pairs(craft) do
        local r = HU.TextRank(c.key, q)
        if r then
            local tier = (r <= 2 and 1) or (r <= 4 and 2) or 3
            if not best or tier < best then best, needs = tier, {} end
            if tier == best and (needs[c.skill] == nil or c.lv < needs[c.skill]) then needs[c.skill] = c.lv end
        end
    end
    return best and needs or nil
end

local function SearchMembers(q)
    q = q:lower()
    local out = {}
    local needs = CraftNeeds(q)
    local cid = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not cid or HU.Secret(cid) then return out end
    local ok, ids = pcall(C_Club.GetClubMembers, cid)
    if not ok or type(ids) ~= "table" then return out end
    for _, id in ipairs(ids) do
        local ok2, info = pcall(C_Club.GetMemberInfo, cid, id)
        local n = ok2 and info and info.name
        if type(n) == "string" and not HU.Secret(n) then
            local off = Enum and Enum.ClubMemberPresence and info.presence == Enum.ClubMemberPresence.Offline
            for _, p in ipairs(HU:ClubProfessions(info)) do
                local need = needs and type(p.id) == "number" and needs[p.id]
                -- (sin nivel —el de los demás, que la comunidad no da—: sale si tiene la profesión)
                if HU.TextRank(p.name, q) or (need and (p.rank == nil or p.rank >= need)) then
                    out[#out + 1] = { name = HU:FullName(n) or n, tag = HU.myTag, prof = p.name, icon = p.icon, online = not off,
                        rank = p.rank }
                end
            end
        end
    end
    -- (los de nivel sabido primero, de más a menos; los demás, detrás)
    table.sort(out, function(a, b)
        local ra, rb = a.rank or -1, b.rank or -1
        if ra ~= rb then return ra > rb end
        return a.name < b.name
    end)
    return out
end

---------------------------------------------------------------------------
-- ¿Puedo hacerlo? Mis profesiones (el juego las da siempre) y mis recetas (solo con la ventana de la profesión abierta:
-- se guardan al abrirla) [+ARCHITECTURE.md]
---------------------------------------------------------------------------
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
local function Pack(...) return { n = select("#", ...), ... } end
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
-- columna de profesiones y la ficha (UnionRoster.lua) y «Quién lo hace» [+ARCHITECTURE.md]
function HU:ClubProfessions(info)
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
-- leer mis profesiones, sí: no se puede comprobar. `profs`: las de MyProfessions [+ARCHITECTURE.md]
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
function HU:CanCraft(item) return CraftCheck(item, MyProfessions()) end

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
    if ui and ui:IsShown() then Paint() end
end
-- (la ventana avisa varias veces seguidas al abrirse y con cada cambio: se lee una vez, un momento después)
local function QueueRead()
    if readQueued then return end
    readQueued = true
    HU.After(0.3, ReadRecipes)
end
HU:On("TRADE_SKILL_SHOW", QueueRead)
HU:On("TRADE_SKILL_LIST_UPDATE", QueueRead)

---------------------------------------------------------------------------
-- Solicitudes
---------------------------------------------------------------------------
local function StateText(r)
    if r.state == "done" then return "|cff9a8f78" .. L("Hecha") .. "|r" end
    if r.state == "taken" then return "|cff40ff40" .. L("Aceptada") .. "|r" end
    return L("Abierta")
end

local function Matches(r, q)
    for _, v in ipairs({ HU:Short(r.who or ""), Plain(r.item), r.taker and HU:Short(r.taker) or "" }) do
        if HU.TextRank(v, q) then return true end
    end
    return false
end

-- (¿está puesta «Solo lo que puedo hacer»? vale en las dos vistas y al buscar)
local function OnlyCraft() return HU.db ~= nil and HU.db.tradeOnlyCraft == true end

-- (profs: las de MyProfessions, si ya están leídas)
local function Visible(profs)
    local out = {}
    local q = Searching() and Query()
    local priv = view == "priv" and not q
    local only = OnlyCraft()
    if only and profs == nil then profs = MyProfessions() end
    for i = #reqs, 1, -1 do
        local r = reqs[i]
        local ok
        if q then
            ok = r.pub == true and (r.state == "open" or (r.state == "taken" and time() - (r.takenAt or 0) < PUB_KEEP))
                and Matches(r, q)
        elseif view == "pub" then
            -- (Tablón: las públicas abiertas y, 10 min más, las aceptadas, con quién la aceptó)
            ok = r.pub == true and (r.state == "open" or (r.state == "taken" and time() - (r.takenAt or 0) < PUB_KEEP))
        else
            -- (Mis encargos: las que me tocan: las mías, las que me piden a mí y las que hago yo)
            -- (una pública sin aceptar no tiene a nadie al otro lado: solo sale en el Tablón)
            ok = Involved(r) and not r.closed and not (r.pub and r.state == "open")
        end
        -- (con la casilla: en el Tablón y al buscar, solo lo que se reconoce y puedo hacer; en Mis encargos, fuera lo que
        -- haría yo y no puedo hacer, y lo que pedí yo, siempre: Jorge, 24/11)
        if ok and only then
            if priv then ok = IsMine(r) or (CraftCheck(r.item, profs))
            else ok = CraftTargets(r.item) ~= nil and (CraftCheck(r.item, profs)) end
        end
        if ok and r.state ~= "gone" then out[#out + 1] = r end
    end
    if sortKey then
        local STATE = { open = 1, taken = 2, done = 3 }
        local function V(r)
            -- (Quién: lo que enseña la columna; en Mis encargos, la otra persona)
            if sortKey == "who" then return (priv and Other(r) or r.who or ""):lower() end
            if sortKey == "item" then return Plain(r.item):lower() end
            if sortKey == "mats" then return r.mats and 1 or 0 end
            if sortKey == "qty" then return r.qty or 1 end
            if sortKey == "tip" then return r.tip or -1 end
            if sortKey == "state" then return STATE[r.state] or 9 end
            if sortKey == "act" then return (r.taker or ""):lower() end
            return r.t or 0
        end
        table.sort(out, function(a, b)
            local va, vb = V(a), V(b)
            if va == vb then return (a.t or 0) > (b.t or 0) end
            if sortDesc then return va > vb end
            return va < vb
        end)
    end
    return out
end

-- (las mías sin terminar, para el tope: abiertas o aceptadas; las que he quitado de mi lista ya no cuentan)
local function OpenCount()
    local n = 0
    for _, r in ipairs(reqs) do
        if IsMine(r) and not r.closed and (r.state == "open" or r.state == "taken") then n = n + 1 end
    end
    return n
end

-- Aceptar una de otro: la haces tú (sigue en el Tablón con tu nombre, y aparece en tus encargos con su chat). Solo si
-- puedes hacerla (HU:CanCraft): el botón ya sale apagado
local function Accept(r)
    if IsMine(r) or r.state ~= "open" or not HU:CanCraft(r.item) then return end
    r.state, r.taker, r.takenAt = "taken", Me(), time()
    OpenChat(r.who)
    Paint()
end
-- La X: mía, cancelarla; de otro (privada, me la piden a mí), rechazarla
local function Cancel(r)
    if r.state == "done" then return end
    if IsMine(r) or r.to == Me() then r.state = "gone"; selected = nil; Paint() end
end

-- (una solicitud por su id)
local function FindReq(id) for _, r in ipairs(reqs) do if r.id == id then return r end end end
-- (eliminar de Mis encargos: la mía sin aceptar se cancela; las demás solo se quitan de mi lista)
local function RemoveReq(r)
    if IsMine(r) and r.state == "open" then r.state = "gone" else r.closed = true end
end
-- «Hecha»: solo quien la hace (quien la aceptó) y mientras está aceptada
local function CanMarkDone(r) return r ~= nil and r.state == "taken" and r.taker == Me() end
local function MarkDone(r)
    if CanMarkDone(r) then r.state = "done"; Paint() end
end

-- Clic derecho en una fila: la otra persona (susurrar, invitar al grupo); en Mis encargos, marcarla como hecha (si la
-- hago yo y está aceptada) y eliminarla; en la búsqueda, pedirle una receta; y Cancelar (cierra el menú)
local function RowMenu(owner, r)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local person
    if not r.id then person = r.name
    elseif view == "priv" and not Searching() then person = Other(r)
    elseif IsMine(r) then person = r.taker
    else person = r.who end
    local priv = r.id and view == "priv" and not Searching()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        if person then
            root:CreateTitle(HU:Short(person))
            root:CreateButton(L("Susurrar"), function() HU.WhisperTo(person) end)
            root:CreateButton(L("Invitar al grupo"), function()
                local fn = C_PartyInfo and C_PartyInfo.InviteUnit
                if fn then pcall(fn, HU:FullName(person) or person) end
            end)
            if not r.id then root:CreateButton(L("Pedir una receta"), function() ui.OpenNew(person) end) end
        end
        if priv and CanMarkDone(r) then
            root:CreateButton(L("Marcar como hecha"), function() MarkDone(r) end)
        end
        if priv then
            local n = 0
            for _ in pairs(picks) do n = n + 1 end
            if n > 0 then
                root:CreateButton(string.format(L("Eliminar (%d)"), n), function()
                    for id in pairs(picks) do local x = FindReq(id); if x then RemoveReq(x) end end
                    picks, selected = {}, nil
                    Paint()
                end)
            else
                root:CreateButton(L("Eliminar"), function() RemoveReq(r); selected = nil; Paint() end)
            end
        end
        root:CreateButton(L("Cancelar"), function() end)
    end)
end

-- Coloca columnas, títulos y filas según lo que toca
local function Columns(lst, cols, width)
    local total = lst.list:GetWidth()
    if type(total) ~= "number" or total <= 0 then total = 560 end
    local used = 0
    for _, col in ipairs(cols) do used = used + col[3] end
    local x = 2
    for i, h in ipairs(lst.hdrCells) do
        local col = cols[i]
        h:SetShown(col ~= nil)
        if col then
            local w = col[3] > 0 and col[3] or math.max(50, total - used - (width or 4) - 4)
            h:ClearAllPoints(); h:SetPoint("BOTTOMLEFT", lst.hdr, "BOTTOMLEFT", x, 0); h:SetWidth(w + 2)
            h.key = col[1]
            -- (la columna por la que se ordena, con una flecha)
            local arrow = (sortKey == col[1]) and (sortDesc and " v" or " ^") or ""
            h:SetText(col[2] ~= "" and (L(col[2]) .. arrow) or "")
            for _, row in ipairs(lst.rows) do
                local c = row.cells[i]
                c:Show(); c:ClearAllPoints(); c:SetPoint("LEFT", row, "LEFT", x + CELL_PAD, 0); c:SetWidth(w - 2 * CELL_PAD)
            end
            x = x + w
        else
            for _, row in ipairs(lst.rows) do row.cells[i]:Hide() end
        end
    end
end

-- (una lista con o sin su título encima; da lo que mide de alto)
local function Titled(lst, text)
    lst.title:SetText(text or ""); lst.title:SetShown(text ~= nil)
    lst.hdr:ClearAllPoints()
    lst.hdr:SetPoint("TOPLEFT", lst.list, "TOPLEFT", 0, text and -14 or 0); lst.hdr:SetPoint("RIGHT", lst.list, "RIGHT", 0, 0)
    lst.scroll:SetHeight(lst.n * ROW_H)
    lst.list:SetHeight((text and 14 or 0) + HDR_H + 2 + lst.n * ROW_H)
end

-- (las columnas de la lista de solicitudes: las de Mis encargos o, en el Tablón y al buscar, las del Tablón; sin
-- propinas, sin la suya)
local function ReqCols()
    local cols = (view == "priv" and not Searching()) and COLS.priv or COLS.pub
    if not HU:UnionCfg().tipsOff then return cols end
    local out = {}
    for _, col in ipairs(cols) do if col[1] ~= "tip" then out[#out + 1] = col end end
    return out
end

-- En Mis encargos, con el chat a la derecha; en el Tablón, a todo lo ancho. Al buscar: arriba las publicadas que
-- encajan y abajo quién lo hace [+ARCHITECTURE.md]. `list`: las solicitudes que se ven (Visible)
local function Layout(cols, list)
    local searching = Searching()
    local priv = view == "priv" and not searching
    local req, found = ui.req, ui.found
    -- (en Mis encargos, el chat siempre a la derecha)
    local withChat = priv
    ui.chat:SetShown(withChat)
    req.list:ClearAllPoints()
    req.list:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 6, 0)
    if withChat then req.list:SetPoint("RIGHT", ui.chat, "LEFT", -6, 0)
    else req.list:SetPoint("RIGHT", ui.body, "RIGHT", -24, 0) end
    local noPub = searching and #list == 0
    req.list:SetShown(not noPub)
    req.n = searching and SEARCH_ROWS or ROWS
    Titled(req, searching and L("Publicadas") or nil)
    -- (quién lo hace, sola: con su título, cabe una fila menos)
    found.n = noPub and ROWS - 1 or SEARCH_ROWS
    found.list:ClearAllPoints()
    if noPub then found.list:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 6, 0)
    else found.list:SetPoint("TOPLEFT", req.list, "BOTTOMLEFT", 0, -6) end
    found.list:SetPoint("RIGHT", ui.body, "RIGHT", -24, 0)
    Titled(found, L("Quién lo hace"))
    found.list:SetShown(searching)
    Columns(req, cols, priv and 44 or 4)
    if searching then Columns(found, COLS.search, 4) end
    -- («+ Nueva solicitud», en el centro de la sección; en Mis encargos, en el de la lista, que deja la derecha al chat:
    -- así no choca con él. Jorge, 24/11)
    ui.new:ClearAllPoints()
    ui.new:SetPoint("BOTTOM", ui, "BOTTOM", withChat and -(24 + CHAT_W) / 2 or 0, 8)
    ui.new:SetShown(not searching)
end

local function PaintRows(lst, list, fill)
    FauxScrollFrame_Update(lst.scroll, #list, lst.n, ROW_H)
    local off = FauxScrollFrame_GetOffset(lst.scroll)
    for i, row in ipairs(lst.rows) do
        local e = i <= lst.n and list[off + i] or nil
        row.entry = e
        row.accept:Hide(); row.cancel:Hide(); row.actText:Hide()
        row.itemBtn:SetShown(e ~= nil and e.id ~= nil); row.yes:Hide(); row.no:Hide(); row.pickTex:Hide()
        if e then fill(row, e); row:Show() else row:Hide() end
        -- (el clic del enlace, solo encima del texto del enlace, no en toda la casilla)
        if row.itemBtn:IsShown() then
            local fs = row.cells[2]
            local w = fs:GetStringWidth() or 0
            local cw = fs:GetWidth() or w
            row.itemBtn:SetWidth(math.max(8, math.min(w, cw > 0 and cw or w) + 2))
        end
    end
    lst.empty:SetShown(#list == 0)
end

function Paint()
    if not (ui and ui:IsShown()) then return end
    -- (comercio apagado por el maestro: solo el panel con el aviso; ni interruptor, ni buscador, ni casilla, ni pedir)
    local off = HU:UnionCfg().tradeOff and true or false
    ui.offMsg:SetShown(off)
    for _, w in ipairs(ui.onlyOn) do w:SetShown(not off) end
    if off then ui.newDlg:Hide(); return end
    BuildOnline()
    local searching = Searching()
    -- (el chat que queda en pantalla, leído; antes de pintar las filas, que llevan lo de cada uno)
    if ChatOnScreen(chatKey) then MarkRead(chatKey) end
    PaintUnread()
    for k, b in pairs(ui.viewBtns) do b:SetSelected(k == view and not searching) end
    -- (se ordena por una columna de la vista: si esta no la tiene (Mats y Acción solo están en el Tablón; sin propinas,
    -- tampoco la suya), vuelve a lo más nuevo arriba)
    local cols = ReqCols()
    local sorted = false
    for _, col in ipairs(cols) do if col[1] == sortKey then sorted = true end end
    if not sorted then sortKey, sortDesc = nil, nil end
    local profs = MyProfessions()
    ui.lastList = Visible(profs)
    Layout(cols, ui.lastList)
    -- («Solo lo que puedo hacer»: vale y se ve en las dos vistas y al buscar)
    local only = OnlyCraft()
    ui.onlyCraft:SetChecked(only)
    if searching then
        ui.found.empty:SetText(L("Nadie de tu hermandad lo hace (profesión u objeto fabricable). Otras hermandades, con la red."))
        PaintRows(ui.found, SearchMembers(Query()), function(row, e)
            local c = row.cells
            -- (con su color de siempre y el circulito; clic derecho: pedir una receta)
            c[1]:SetText((e.name == Me() and MINE or OTHERS) .. HU:Short(e.name) .. "|r " .. (e.online and DOT_ON or DOT_OFF))
            c[2]:SetText("|cff" .. HU:GuildColorHex(e.tag) .. tostring(e.tag or "") .. "|r")
            c[3]:SetText((e.icon and ("|T" .. e.icon .. ":14:14|t ") or "") .. e.prof); c[4]:SetText(e.rank and tostring(e.rank) or "—")
        end)
    end
    ui.req.empty:SetText(searching and L("Ninguna solicitud publicada encaja.")
        or (view == "pub" and only and L("En el tablón no hay nada que puedas hacer.")) or L("No hay solicitudes."))
    local nPicks = 0
    for _ in pairs(picks) do nPicks = nPicks + 1 end
    ui.delBtn:SetShown(view == "priv" and not searching and nPicks > 0)
    ui.delBtn:SetText(string.format(L("Eliminar (%d)"), nPicks))
    local cur = selected and FindReq(selected)
    -- («Hecha», en las que hago yo; ya hecha, apagado)
    ui.doneBtn:SetShown(view == "priv" and not searching and cur ~= nil and cur.taker == Me())
    ui.doneBtn:SetEnabled(CanMarkDone(cur))
    PaintRows(ui.req, ui.lastList, function(row, r)
        local mine = IsMine(r)
        local test = r.test and (" |cff808080(" .. L("prueba") .. ")|r") or ""
        row.pickTex:SetShown(r.id == selected or picks[r.id] == true)
        -- (lo de cada columna, por su clave: sin propinas, la suya no está)
        local v = { item = r.item or "?", qty = tostring(r.qty or 1), state = StateText(r) .. test,
            tip = r.tip and Coins(r.tip) or ("|cff9a8f78" .. L("A negociar") .. "|r") }
        if view == "pub" or searching then
            v.who = mine and (MINE .. L("Yo") .. "|r " .. DOT_ON) or (OTHERS .. HU:Short(r.who) .. "|r " .. Dot(r.who))
            v.mats = r.mats == nil and "—" or (r.mats and L("Sí") or L("No"))
            -- (la última columna: Aceptar si es de otro y está abierta; Cancelar si es mía; si ya la
            -- aceptó alguien, su nombre)
            if r.taker then
                row.actText:SetText(r.taker == Me() and (MINE .. L("Yo") .. "|r") or (OTHERS .. HU:Short(r.taker) .. "|r " .. Dot(r.taker))); row.actText:Show()
            elseif mine then
                row.cancel:Show()
            elseif r.state == "open" then
                -- (apagado si no puedo hacerla: el porqué, al pasar el ratón)
                local can, why = CraftCheck(r.item, profs)
                row.accept:SetEnabled(can); row.accept.why = why
                row.accept:Show()
            end
        else
            -- (la otra persona, con cuántas suyas hay sin leer)
            local other = Other(r)
            v.who = (mine and MINE or OTHERS) .. HU:Short(other) .. "|r " .. Dot(other) .. UnreadMark(other)
            -- (solo en las abiertas: el tic para aceptarla —si me la piden a mí y puedo hacerla— y la X para
            -- cancelarla —mía— o rechazarla; las aceptadas, sin nada)
            local ask = r.state == "open" and not mine
            row.yes:SetShown(ask)
            if ask then
                local can, why = CraftCheck(r.item, profs)
                row.yes:SetEnabled(can); row.yes.why = why
            end
            row.no:SetShown(r.state == "open")
        end
        for i, col in ipairs(cols) do row.cells[i]:SetText(v[col[1]] or "") end
    end)
end

---------------------------------------------------------------------------
-- Nueva solicitud: objeto (con autorrelleno), quién pone los materiales, propina en oro · plata · cobre
-- y si es pública o para alguien (con autorrelleno del nombre) [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local SUGGEST_N = 6

-- (lo que encaja con lo escrito, de mejor a peor (HU.TextRank: lo exacto y las palabras enteras primero); en cada grupo,
-- el nombre más corto, que es el que más se parece a lo escrito, y luego por nombre)
local function Better(x, y)
    if x.rank ~= y.rank then return x.rank < y.rank end
    if #x.key ~= #y.key then return #x.key < #y.key end
    return x.key < y.key
end

-- Lista de sugerencias bajo una caja: source(q) da { { text, value, key, rank } }; clic o Intro (la primera) la elige
-- (la ficha del juego de lo que lleva `text`, si es un enlace, a la derecha de `owner`, sin taparlo: Jorge, 24/11, «que
-- aparezca al pasar el ratón lo que es, pero que no moleste»)
local function HyperTip(owner, text)
    local link = type(text) == "string" and not HU.Secret(text) and text:match("|H(.-)|h")
    if not link then return end
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() else GameTooltip:Hide() end
end

local function Suggest(box, source)
    local list = CreateFrame("Frame", nil, box, "BackdropTemplate")
    list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -1)
    list:SetWidth(math.max(box:GetWidth() + 8, 260))
    DJ.Panel(list, DJ.T.frame, DJ.T.border, 10, 2)
    list:SetFrameLevel(box:GetFrameLevel() + 30)
    list:Hide()
    local btns, found = {}, {}
    local function Pick(v) box:SetText(v); box:SetCursorPosition(#v); list:Hide() end
    for i = 1, SUGGEST_N do
        local b = CreateFrame("Button", nil, list)
        b:SetHeight(16)
        b:SetPoint("TOPLEFT", 4, -2 - (i - 1) * 16); b:SetPoint("RIGHT", list, "RIGHT", -4, 0)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 2, 0); b.text:SetPoint("RIGHT", -2, 0); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.15)
        b:SetScript("OnClick", function(s) if s.value then Pick(s.value) end end)
        -- (un objeto: al pasar el ratón, su ficha, al lado de la lista)
        b:SetScript("OnEnter", function(s) HyperTip(list, s.value) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btns[i] = b
    end
    box:HookScript("OnTextChanged", function(s, user)
        if not user then list:Hide(); return end
        local q = HU.Trim(s:GetText() or "")
        found = #q >= 2 and source(q) or {}
        table.sort(found, Better)
        for i, b in ipairs(btns) do
            local f = found[i]
            b.value = f and f.value
            b.text:SetText(f and f.text or ""); b:SetShown(f ~= nil)
        end
        list:SetHeight(4 + math.min(#found, SUGGEST_N) * 16)
        list:SetShown(#found > 0)
    end)
    box:HookScript("OnEnterPressed", function() if list:IsShown() and found[1] then Pick(found[1].value) end end)
    box:HookScript("OnEscapePressed", function() list:Hide() end)
    box:HookScript("OnHide", function() list:Hide() end)
end

-- Objetos que el juego ya conoce: el de ese nombre exacto, los de mis bolsas, los de las solicitudes y los
-- fabricables. Todos los que encajan, de mejor a peor, y luego los primeros (antes se cortaba a 60 en el orden de
-- la tabla y los mejores se podían quedar fuera)
local function ItemMatches(text)
    local out, seen = {}, {}
    local function push(link, k)
        if seen[k] then return end
        local rank = HU.TextRank(k, text)
        if not rank then return end
        seen[k] = true
        out[#out + 1] = { text = link, value = link, key = k, rank = rank }
    end
    local function add(link)
        if type(link) ~= "string" or HU.Secret(link) or not link:find("|H", 1, true) then return end
        push(link, (HU.Fold(Plain(link)):gsub("^%[", ""):gsub("%]$", "")))
    end
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, _, link = pcall(get, text)
    if ok then add(link) end
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local slotLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local okN, n = pcall(numSlots, bag)
        for slot = 1, (okN and type(n) == "number") and n or 0 do
            local okL, l = pcall(slotLink, bag, slot)
            if okL then add(l) end
        end
    end
    for _, r in ipairs(reqs) do add(r.item) end
    for _, c in pairs(craft) do push(c.link, c.key) end
    table.sort(out, Better)
    for i = #out, SUGGEST_N + 1, -1 do out[i] = nil end
    return out
end

-- Personajes que conozco: mi hermandad, las listas de las otras y los que tienen GuildUnion
local function NameMatches(text)
    local out, seen = {}, { [Me():lower()] = true }
    local function add(full, tag)
        if type(full) ~= "string" or HU.Secret(full) then return end
        local k = full:lower()
        local short = HU:Short(full)
        local rank = not seen[k] and HU.TextRank(short, text)
        if not rank then return end
        seen[k] = true
        local t = tag and (" |cff" .. HU:GuildColorHex(tag) .. "<" .. tag .. ">|r") or ""
        out[#out + 1] = { text = short .. t, value = full, key = HU.Fold(short), rank = rank }
    end
    for _, e in ipairs(HU.rosterList or {}) do add(e.name, HU.myTag) end
    for tag, rr in pairs(HU.remoteRoster or {}) do for _, m in ipairs(rr.members or {}) do add(m.name, tag) end end
    for _, pr in pairs(HU.remote or {}) do add(pr.name, pr.tag) end
    return out
end

local function BuildNewDialog(host)
    local d = CreateFrame("Frame", "GuildUnionTradeNew", host, "BackdropTemplate")
    d:SetSize(310, 264)
    d:SetPoint("CENTER", host, "CENTER", 0, 0)
    d:SetFrameStrata("DIALOG")
    DJ.Panel(d, DJ.T.content, DJ.T.border, 14, 4)
    DJ.Parchment(d, 0.18)
    d:EnableMouse(true)
    d:Hide()
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.title:SetPoint("TOPLEFT", 12, -10)
    local function Label(text, x, y, font)
        local l = d:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", x, y); l:SetText(text)
        return l
    end
    local function Check(text, x, y)
        local c = CreateFrame("CheckButton", nil, d, "UICheckButtonTemplate")
        c:SetSize(20, 20); c:SetPoint("TOPLEFT", x, y)
        if c.Text then c.Text:SetFontObject("GameFontHighlightSmall"); c.Text:SetText(text) end
        return c
    end
    -- (dos casillas que se excluyen: marcar una desmarca la otra)
    local function Pair(a, b, onChange)
        a:SetScript("OnClick", function() a:SetChecked(true); b:SetChecked(false); if onChange then onChange() end end)
        b:SetScript("OnClick", function() b:SetChecked(true); a:SetChecked(false); if onChange then onChange() end end)
    end

    Label(L("Objeto o encantamiento (o Mayús+clic):"), 12, -34)
    d.item = HU.NewEditBox(d, 222); d.item:SetPoint("TOPLEFT", 18, -48)
    Label(L("Cantidad:"), 248, -34)
    d.qty = HU.NewEditBox(d, 42); d.qty:SetPoint("TOPLEFT", 254, -48); d.qty:SetNumeric(true); d.qty:SetMaxLetters(3)
    d.qty:SetJustifyH("CENTER")
    Suggest(d.item, ItemMatches)

    Label(L("Materiales:"), 12, -80)
    d.matsMe = Check(L("Yo"), 96, -75)
    d.matsSeller = Check(L("Vendedor"), 170, -75)
    Pair(d.matsMe, d.matsSeller)

    -- (lo de la propina: se esconde si el maestro no permite propinas, UnionConfig.lua)
    d.tipParts = { Label(L("Propina:"), 12, -106), Label(L("(en blanco: a negociar)"), 64, -106, "GameFontDisableSmall") }
    d.coins = {}
    for i, icon in ipairs(COIN_ICON) do
        local box = HU.NewEditBox(d, 56); box:SetPoint("TOPLEFT", 18 + (i - 1) * 74, -138); box:SetNumeric(true)
        box:SetMaxLetters(i == 1 and 6 or 2); box:SetJustifyH("CENTER")
        local tex = d:CreateTexture(nil, "ARTWORK")
        tex:SetSize(14, 14); tex:SetTexture(icon); tex:SetPoint("BOTTOM", box, "TOP", -3, 2)
        d.coins[i] = box
        d.tipParts[#d.tipParts + 1] = box; d.tipParts[#d.tipParts + 1] = tex
    end

    Label(L("En el tablón:"), 12, -170)
    d.pubYes = Check(L("Sí"), 96, -165)
    d.pubNo = Check(L("No"), 170, -165)
    d.toLabel = Label(L("Personaje:"), 12, -198)
    d.to = HU.NewEditBox(d, 196); d.to:SetPoint("TOPLEFT", 102, -194)
    Suggest(d.to, NameMatches)
    function d.SetPub(pub)
        d.pubYes:SetChecked(pub); d.pubNo:SetChecked(not pub)
        d.toLabel:SetShown(not pub); d.to:SetShown(not pub)
        d:SetHeight(pub and 236 or 264)
    end
    Pair(d.pubYes, d.pubNo, function()
        d.SetPub(d.pubYes:GetChecked() and true or false)
        if d.to:IsShown() then d.to:SetFocus() end
    end)

    local ok = Flat(d, L("Pedir"), 110, 22); ok:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 12)
    local no = Flat(d, L("Cancelar"), 110, 22); no:SetPoint("BOTTOMLEFT", d, "BOTTOM", 6, 12)
    no:SetScript("OnClick", function() d:Hide() end)
    ok:SetScript("OnClick", function()
        -- (con el comercio apagado no se pide nada, aunque la ventana se hubiera quedado abierta de antes)
        if HU:UnionCfg().tradeOff then
            d:Hide()
            return HU:Print(L("El maestro de la hermandad ha desactivado el comercio (pestaña GuildUnion, Configuración → Comercio)."))
        end
        local item = HU.Trim(d.item:GetText() or "")
        if item == "" then return HU:Print(L("Pon el objeto que pides (Mayús+clic en él).")) end
        if OpenCount() >= MAX_OPEN then return HU:Print(string.format(L("Ya tienes %d solicitudes abiertas: cierra alguna antes."), MAX_OPEN)) end
        local pub = d.pubYes:GetChecked() and true or false
        local to = HU.Trim(d.to:GetText() or "")
        if not pub and to == "" then return HU:Print(L("Si no va al tablón, pon a quién se la pides.")) end
        -- (la propina, en cobre; las tres cajas vacías: a negociar)
        local tip, any = 0, false
        for i, box in ipairs(d.coins) do
            local v = tonumber(box:GetText() or "")
            if v then any = true; tip = tip + v * (i == 1 and 10000 or i == 2 and 100 or 1) end
        end
        local mats
        if d.matsMe:GetChecked() then mats = true elseif d.matsSeller:GetChecked() then mats = false end
        reqs[#reqs + 1] = { id = NewId(), who = Me(), item = item, mats = mats, tip = (any and not (HU:UnionCfg().tipsOff)) and tip or nil, qty = math.max(1, tonumber(d.qty:GetText() or "") or 1), state = "open", pub = pub,
            to = (not pub) and (HU:FullName(to) or to) or nil, t = time() }
        d:Hide()
        view = pub and "pub" or "priv"
        ui.search:SetText("")
        Paint()
    end)
    -- (Mayús+clic en un objeto con esta caja escribiendo: entra su enlace)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", function(text)
            if d:IsShown() and d.item:HasFocus() and type(text) == "string" then d.item:SetText(text) end
        end)
    end
    return d
end

---------------------------------------------------------------------------
-- Modo prueba: solicitudes y chats de mentira; no se manda nada. Sin botón ni comando (Jorge, 24/11: «quitando el
-- test mode»): solo por código, con HU:TradeTest; lo usan las pruebas
---------------------------------------------------------------------------
-- (quitar lo de prueba: sus solicitudes y los chats con los de prueba)
local function ClearTest()
    for k = #reqs, 1, -1 do if reqs[k].test then table.remove(reqs, k) end end
    for key in pairs(chats) do if key:find("%-Prueba$") then chats[key] = nil end end
    -- (y sus líneas sin leer)
    local had = false
    for key in pairs(unread) do if key:find("%-Prueba$") then unread[key] = nil; had = true end end
    if chatKey and chatKey:find("%-Prueba$") then OpenChat(nil) end
    selected, picks = nil, {}
    if had then PaintUnread(); HU:Changed("tradeUnread") end
end

local function AddTest()
    ClearTest()
    local now = time()
    local function R(who, item, mats, tip, state, pub, to, taker, qty)
        reqs[#reqs + 1] = { id = NewId(), who = who, item = item, mats = mats, tip = tip and tip * 10000, qty = qty, state = state, pub = pub,
            to = to, taker = taker, takenAt = taker and now or nil, t = now, test = true }
    end
    local function Link(id, name, color)
        local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local ok, _, link = pcall(get, id)
        if ok and type(link) == "string" then return link end
        return "|cff" .. color .. "|Hitem:" .. id .. "::::::::60:::::::|h[" .. name .. "]|h|r"
    end
    R("Jandra-Prueba", Link(3928, "Poción de curación superior", "ffffff"), false, 2.5, "open", true, nil, nil, 5)
    R("Pepe-Prueba", Link(7378, "Bolsa de tejido de lana", "1eff00"), true, nil, "open", true)
    R("Lyra-Prueba", Link(7931, "Cofia de mitril", "1eff00"), true, 3, "taken", true, nil, "Bea-Prueba")
    R(Me(), Link(7056, "Capa de seda carmesí", "1eff00"), true, 5, "open", true)
    R("Bea-Prueba", Link(8949, "Elixir de agilidad", "ffffff"), false, 1, "open", false, Me())
    R(Me(), Link(7954, "Gran espada de mitril", "0070dd"), true, nil, "taken", false, "Pepe-Prueba", "Pepe-Prueba")
    R("Lyra-Prueba", Link(7931, "Cofia de mitril", "1eff00"), true, 2, "open", false, Me())
    R(Me(), Link(3928, "Poción de curación superior", "ffffff"), false, 0.5, "open", false, "Jandra-Prueba")
    ChatLine("Lyra-Prueba", "Lyra-Prueba", L("Te dejo el encargo; mañana me conecto."))
    ChatLine("Pepe-Prueba", "Pepe-Prueba", L("Te hago la espada esta noche."))
    ChatLine("Bea-Prueba", "Bea-Prueba", L("¿Me haces el elixir? Pago bien."))
    Paint()
end

-- Poner (on) o quitar lo de prueba
function HU:TradeTest(on)
    if on then AddTest() else ClearTest(); Paint() end
end

---------------------------------------------------------------------------
-- Montar la sección (UnionRoster.lua la pone en la pestaña Trade)
---------------------------------------------------------------------------
-- (Aceptar o el tic, apagados: por qué no puedo hacerla, en rojo; Paint deja el porqué en `why`)
local function WhyTip(s)
    if not s.why then return end
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:SetText(s.why, 1, 0.35, 0.35)
    GameTooltip:Show()
end

function HU:BuildTrade(host)
    ui = host
    -- Arriba, los botones rojos Tablón · Mis encargos, juntos en el centro; debajo, el buscador a la izquierda y «Solo lo
    -- que puedo hacer» a la derecha; abajo, «+ Nueva solicitud» (Jorge, 24/11: el sitio de la «opción 3», con los botones
    -- y el buscador y la casilla de antes) [+ARCHITECTURE.md]
    local sw = DJ.Switch(host, { { "pub", L("Tablón") }, { "priv", L("Mis encargos") } })
    sw:SetPoint("TOP", host, "TOP", 0, -4)
    ui.switch = sw
    ui.viewBtns = sw.btns
    for k, b in pairs(sw.btns) do
        b:SetScript("OnClick", function()
            view, selected, picks = k, nil, {}
            ui.search:SetText("")
            FauxScrollFrame_SetOffset(ui.scroll, 0)
            Paint()
        end)
    end
    -- (el buscador, como antes: el del juego, con su ayuda en gris claro y un marco oscuro de borde dorado detrás; centrado
    -- en la fila)
    local search = CreateFrame("EditBox", "GuildUnionTradeSearch", host, "SearchBoxTemplate")
    search:SetSize(SEARCH_W, 22)
    search:SetPoint("TOPLEFT", host, "TOPLEFT", 23, ROW2_Y - (ROW2_H - 22) / 2)
    if search.Instructions then
        search.Instructions:SetText(L("Buscar receta")); DJ.C(search.Instructions, DJ.T.muted)
    end
    local sbox = CreateFrame("Frame", nil, host, "BackdropTemplate")
    sbox:SetPoint("TOPLEFT", search, "TOPLEFT", -9, 3); sbox:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", 3, -3)
    DJ.Panel(sbox, DJ.T.row, { DJ.T.line[1], DJ.T.line[2], DJ.T.line[3], 0.55 }, 10, 2)
    sbox:SetFrameLevel(search:GetFrameLevel())
    search:SetFrameLevel(sbox:GetFrameLevel() + 2)
    ui.searchBox = sbox
    -- (con un objeto escrito, al pasar el ratón, su ficha, a la derecha del buscador)
    search:HookScript("OnEnter", function(s) HyperTip(s, s:GetText()) end)
    search:HookScript("OnLeave", function() GameTooltip:Hide() end)
    search:HookScript("OnTextChanged", function()
        if not ui.found then return end
        FauxScrollFrame_SetOffset(ui.req.scroll, 0); FauxScrollFrame_SetOffset(ui.found.scroll, 0)
        Paint()
    end)
    ui.search = search
    -- «Solo lo que puedo hacer», a la derecha de la misma fila: la casilla del juego, como antes, con su texto detrás, que
    -- acaba en el borde. En el Tablón (y al buscar), solo lo que HU:CanCraft deja; en Mis encargos, fuera lo que haría yo
    -- y no puedo hacer. Se recuerda por personaje
    local only = CreateFrame("CheckButton", nil, host, "UICheckButtonTemplate")
    only:SetSize(22, 22)
    if only.Text then only.Text:SetFontObject("GameFontHighlightSmall"); only.Text:SetText(L("Solo lo que puedo hacer")) end
    local tw = only.Text and only.Text:GetStringWidth()
    tw = (type(tw) == "number" and tw > 0 and not HU.Secret(tw)) and tw or 130
    only:SetPoint("LEFT", host, "TOPRIGHT", -(14 + 22 + 2 + tw), ROW2_Y - ROW2_H / 2)
    only:SetScript("OnClick", function(s)
        HU.db.tradeOnlyCraft = (not OnlyCraft()) or nil
        s:SetChecked(OnlyCraft())
        FauxScrollFrame_SetOffset(ui.req.scroll, 0)
        Paint()
    end)
    only:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(L("Solo lo que puedo hacer"))
        GameTooltip:AddLine(L("En el tablón, solo lo que puedes hacer con tus profesiones y tus recetas (lo que no se sabe qué es, tampoco). En Mis encargos, esconde los que harías tú y no puedes hacer; los que pides tú se ven siempre."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    only:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.onlyCraft = only

    -- (detrás de todo, el panel de la sección, justo debajo de las dos filas: color «content» y borde, como el calendario)
    local bg = CreateFrame("Frame", nil, host, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", host, "TOPLEFT", 2, BODY_Y + 4); bg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)
    bg:SetFrameLevel(host:GetFrameLevel() + 1)
    DJ.Panel(bg, DJ.T.content, DJ.T.border, 14, 4)
    DJ.Parchment(bg, 0.18)
    local body = CreateFrame("Frame", nil, host)
    body:SetPoint("TOPLEFT", host, "TOPLEFT", 0, BODY_Y); body:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, BOTTOM_H)
    body:SetFrameLevel(bg:GetFrameLevel() + 2)
    ui.body = body
    -- (el aviso de apagado, en el panel: en host quedaba por debajo de él y no se veía)
    ui.offMsg = DJ.C(bg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), DJ.T.muted)
    ui.offMsg:SetPoint("CENTER"); ui.offMsg:SetWidth(420)
    ui.offMsg:SetText(L("El maestro de la hermandad ha desactivado el comercio (pestaña GuildUnion, Configuración → Comercio)."))
    HU:Listen("CHANGED", function(what) if what == "unionCfg" and ui:IsShown() then Paint() end end)

    -- Derecha (solo en Mis encargos): el chat de la persona del comercio que eliges, de arriba abajo: desde debajo del
    -- buscador hasta el borde de abajo de la sección (Jorge, 24/11)
    local chat = CreateFrame("Frame", nil, body, "BackdropTemplate")
    chat:SetPoint("TOPRIGHT", body, "TOPRIGHT", -24, 0); chat:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -24, 8)
    chat:SetWidth(CHAT_W)
    DJ.Panel(chat, DJ.T.panel, DJ.T.border, 12, 3)
    DJ.Parchment(chat, 0.13)
    ui.chat = chat
    ui.chatTitle = chat:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.chatTitle:SetPoint("TOPLEFT", 8, -7); ui.chatTitle:SetPoint("RIGHT", chat, "RIGHT", -8, 0)
    ui.chatTitle:SetJustifyH("LEFT"); ui.chatTitle:SetWordWrap(false)
    local done = Flat(chat, L("Hecha"), 64, 18)
    done:SetPoint("TOPRIGHT", -5, -4)
    done:SetScript("OnClick", function() MarkDone(selected and FindReq(selected)) end)
    ui.doneBtn = done
    ui.chatTitle:SetPoint("RIGHT", done, "LEFT", -6, 0)
    local msgs = CreateFrame("ScrollingMessageFrame", nil, chat)
    msgs:SetPoint("TOPLEFT", 6, -24); msgs:SetPoint("BOTTOMRIGHT", -6, 28)
    -- (la letra pequeña de siempre con 3 de aire entre líneas: el marco de mensajes la reparte a cada línea)
    local font = CreateFont("GuildUnionTradeChatFont")
    font:CopyFontObject(GameFontHighlightSmall); font:SetSpacing(3)
    msgs:SetFontObject(font); msgs:SetJustifyH("LEFT")
    msgs:SetFading(false); msgs:SetMaxLines(200)
    msgs:EnableMouseWheel(true)
    msgs:SetScript("OnMouseWheel", function(s, d) if d > 0 then s:ScrollUp() else s:ScrollDown() end end)
    ui.msgs = msgs
    local input = HU.NewEditBox(chat, CHAT_W - 14)
    input:SetPoint("BOTTOMLEFT", 10, 6)
    input:SetScript("OnEnterPressed", function(s)
        local text = HU.Trim(s:GetText() or "")
        -- (también a un desconectado: con la red, lo leerá al entrar)
        if text ~= "" and chatKey then ChatLine(chatKey, Me(), text) end
        s:SetText(""); s:ClearFocus()
    end)
    ui.chatInput = input
    ui.chatHint = chat:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.chatHint:SetPoint("LEFT", input, "LEFT", 2, 0); ui.chatHint:SetText(L("Elige un comercio con alguien para escribir"))

    -- Las listas: las solicitudes y, al buscar, debajo, quién lo hace
    local function MakeList(n, sortable, sfName)
        local lst = { n = n, rows = {}, hdrCells = {} }
        local list = CreateFrame("Frame", nil, body)
        lst.list = list
        lst.title = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lst.title:SetPoint("TOPLEFT", list, "TOPLEFT", 4, 0); lst.title:Hide()
        local hdr = CreateFrame("Frame", nil, list)
        hdr:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0); hdr:SetPoint("RIGHT", list, "RIGHT", 0, 0); hdr:SetHeight(HDR_H)
        local hline = hdr:CreateTexture(nil, "ARTWORK")
        hline:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35); hline:SetHeight(1)
        hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT")
        lst.hdr = hdr
        for i = 1, 7 do
            local b = CreateFrame("Button", nil, hdr)
            b:SetHeight(HDR_H)
            b:SetNormalFontObject("GameFontNormalSmall")
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
            b:SetScript("OnClick", function(s)
                local key = s.key
                -- (solo se ven los títulos de la vista, y Paint quita el orden de una columna que ya no está)
                if not sortable or not key then return end
                if sortKey == key then
                    if sortDesc then sortKey, sortDesc = nil, nil else sortDesc = true end
                else
                    sortKey, sortDesc = key, false
                end
                Paint()
            end)
            lst.hdrCells[i] = b
        end
        local sf = CreateFrame("ScrollFrame", sfName, list, "FauxScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -2); sf:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
        sf:SetHeight(n * ROW_H)
        sf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, Paint) end)
        lst.scroll = sf
        for i = 1, n do
            local row = CreateFrame("Button", nil, list)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("RIGHT", sf, "RIGHT", 0, 0)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.pickTex = row:CreateTexture(nil, "BORDER")
            row.pickTex:SetAllPoints(); row.pickTex:SetColorTexture(0.25, 0.55, 1, 0.28); row.pickTex:Hide()
            if i % 2 == 0 then
                local stripe = row:CreateTexture(nil, "BACKGROUND")
                stripe:SetAllPoints(); stripe:SetColorTexture(1, 1, 1, 0.05)
            end
            row.cells = {}
            for c = 1, 7 do
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetJustifyH("CENTER"); fs:SetWordWrap(false)
                row.cells[c] = fs
            end
            local itemBtn = CreateFrame("Button", nil, row)
            itemBtn:SetPoint("CENTER", row.cells[2], "CENTER"); itemBtn:SetHeight(ROW_H)
            itemBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            itemBtn:SetScript("OnClick", function(_, button)
                local link = row.entry and row.entry.item
                local h = link and link:match("|H(.-)|h")
                if h then SetItemRef(h, link, button) end
            end)
            itemBtn:SetScript("OnEnter", function(s)
                if view == "priv" and not Searching() then return end
                local link = row.entry and row.entry.item
                local h = link and link:match("|H(.-)|h")
                if h then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); pcall(GameTooltip.SetHyperlink, GameTooltip, h); GameTooltip:Show() end
            end)
            itemBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.itemBtn = itemBtn
            -- (Tablón, última columna: Aceptar / Cancelar, o el nombre de quien la aceptó. Aceptar, apagado si no
            -- puedo hacerla, con el porqué al pasar el ratón)
            local accept = Flat(row, L("Aceptar"), ACT_W, 20)
            accept:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            accept:SetScript("OnClick", function() if row.entry then Accept(row.entry) end end)
            accept:SetMotionScriptsWhileDisabled(true)
            accept:SetScript("OnEnter", WhyTip); accept:SetScript("OnLeave", function() GameTooltip:Hide() end)
            local actText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            actText:SetPoint("RIGHT", row, "RIGHT", -2, 0); actText:SetWidth(ACT_W); actText:SetJustifyH("CENTER")
            local cancel = Flat(row, L("Cancelar"), ACT_W, 20)
            cancel:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            cancel:SetScript("OnClick", function() if row.entry then Cancel(row.entry) end end)
            row.accept, row.cancel, row.actText = accept, cancel, actText
            -- (Mis encargos, en las abiertas: el tic acepta la que me piden a mí —apagado y gris si no puedo hacerla, con
            -- el porqué—; la X cancela la mía o rechaza la que me piden)
            local no = CreateFrame("Button", nil, row)
            no:SetSize(18, 18); no:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            no:SetNormalTexture(CROSS); no:SetHighlightTexture(CROSS, "ADD")
            no:SetScript("OnClick", function() if row.entry then Cancel(row.entry) end end)
            local yes = CreateFrame("Button", nil, row)
            yes:SetSize(18, 18); yes:SetPoint("RIGHT", no, "LEFT", -4, 0)
            yes:SetNormalTexture(TICK); yes:SetHighlightTexture(TICK, "ADD"); yes:SetDisabledTexture(TICK)
            local grey = yes:GetDisabledTexture()
            if grey then grey:SetDesaturated(true); grey:SetAlpha(0.35) end
            yes:SetScript("OnClick", function() if row.entry then Accept(row.entry) end end)
            yes:SetMotionScriptsWhileDisabled(true)
            yes:SetScript("OnEnter", WhyTip); yes:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.yes, row.no = yes, no
            -- (clic: elegirla; en Mis encargos, además, el chat pasa a ser el de esa persona. En la búsqueda, clic
            -- derecho: pedirle una receta)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(s, button)
                local r = s.entry
                if r and button == "RightButton" then return RowMenu(s, r) end
                if not (r and r.id) then return end
                -- (en Mis encargos: Ctrl suma o quita; Mayús elige desde la última hasta esta; clic solo, solo esa)
                if view == "priv" and not Searching() then
                    if IsControlKeyDown() then
                        -- (la elegida con un clic solo también cuenta: si no, quedaba fuera de las marcadas)
                        if selected and selected ~= r.id and next(picks) == nil then
                            for _, x in ipairs(ui.lastList or {}) do if x.id == selected then picks[selected] = true end end
                        end
                        picks[r.id] = (not picks[r.id]) or nil
                    elseif IsShiftKeyDown() and lastPick then
                        local a, b
                        for k, x in ipairs(ui.lastList or {}) do
                            if x.id == lastPick then a = k end
                            if x.id == r.id then b = k end
                        end
                        if a and b then
                            if a > b then a, b = b, a end
                            for k = a, b do picks[ui.lastList[k].id] = true end
                        end
                    else
                        picks = {}
                    end
                    lastPick = r.id
                end
                selected = r.id
                if view == "priv" and not Searching() then
                    OpenChat(Other(r))
                end
                Paint()
            end)
            lst.rows[i] = row
        end
        lst.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        lst.empty:SetPoint("TOP", sf, "TOP", 0, -24); lst.empty:SetWidth(380)
        return lst
    end
    ui.req = MakeList(ROWS, true, "GuildUnionTradeScroll")
    ui.found = MakeList(ROWS, false, "GuildUnionTradeScroll2")
    ui.list, ui.scroll = ui.req.list, ui.req.scroll

    -- Abajo: «+ Nueva solicitud», como hasta la copia 304 (teñido de verde, letra blanca), centrado debajo de la lista
    -- (Layout); va en el panel, para quedar encima de él [+ARCHITECTURE.md]
    local newDlg = BuildNewDialog(host)
    local new = Flat(bg, "+ " .. L("Nueva solicitud"), 200, 24)
    new:SetPoint("BOTTOM", host, "BOTTOM", 0, 8)
    for _, k in ipairs({ "Left", "Middle", "Right" }) do if new[k] then new[k]:SetVertexColor(0.45, 1, 0.45) end end
    new:SetNormalFontObject("GameFontHighlight")
    -- (to: pedírsela a alguien en concreto, privada: «Pedir una receta» desde la búsqueda. Con el comercio
    -- apagado no se abre)
    function ui.OpenNew(to)
        if HU:UnionCfg().tradeOff then return end
        newDlg.title:SetText(to and (L("Pedir una receta a ") .. HU:Short(to)) or L("Nueva solicitud"))
        newDlg.item:SetText(""); newDlg.to:SetText(to or ""); newDlg.qty:SetText("1")
        for _, box in ipairs(newDlg.coins) do box:SetText("") end
        local noTips = HU:UnionCfg().tipsOff
        for _, w in ipairs(newDlg.tipParts) do w:SetShown(not noTips) end
        newDlg.matsMe:SetChecked(true); newDlg.matsSeller:SetChecked(false)
        newDlg.SetPub(not to and view == "pub")
        newDlg:Show(); newDlg.item:SetFocus()
    end
    new:SetScript("OnClick", function() ui.OpenNew(nil) end)
    ui.new, ui.newDlg = new, newDlg
    -- (a su derecha, «Eliminar (N)», con algo marcado en Mis encargos: cabe antes del chat)
    local del = Flat(body, "", 80, 22)
    del:SetPoint("LEFT", new, "RIGHT", 6, 0)
    del:SetScript("OnClick", function()
        for id in pairs(picks) do local x = FindReq(id); if x then RemoveReq(x) end end
        picks, selected = {}, nil
        Paint()
    end)
    del:Hide()
    ui.delBtn = del
    -- (lo que solo se ve con el comercio encendido: apagado, queda el panel con el aviso)
    ui.onlyOn = { body, sw, search, sbox, only, new }

    Suggest(ui.search, ItemMatches)
    host:HookScript("OnShow", function() LoadCraftNames(); Paint() end)
    LoadCraftNames()
    OpenChat(nil)
    Paint()
end

HU:Module("Trade", { "BlizzTab", "Config", "Core", "ListWindow", "Lists", "UnionConfig" })
