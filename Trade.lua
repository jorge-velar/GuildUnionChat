-- Guild Union - Comercio (la sección Trade de la lista de miembros) [+ARCHITECTURE.md]
-- Fase 1 (copias 211-214): solo la ventana, sin red. Lo que se pide o se escribe se queda en tu sesión, y
-- el «Modo prueba» rellena solicitudes y chats de mentira. Diseño: Obsidian/Addons/GuildUnion - Comercio (diseño).md
local _, HU = ...
local L = HU.L

local ROW_H, ROWS = 18, 10
local SEARCH_ROWS = 4       -- al buscar: filas de cada mitad (publicadas arriba, quién lo hace abajo)
local MAX_OPEN = 5          -- solicitudes abiertas por persona
local MINE, OTHERS = "|cff4da6ff", "|cffffd100"
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local CHAT_W = 200
local DOT_ON = "|TInterface\\FriendsFrame\\StatusIcon-Online:10:10|t"
local DOT_OFF = "|TInterface\\FriendsFrame\\StatusIcon-Offline:10:10|t"
local testOnline = { ["Pepe-Prueba"] = true, ["Bea-Prueba"] = true, ["Lyra-Prueba"] = false, ["Janeth-Prueba"] = false }
local ACT_W = 84            -- la última columna: el botón (Aceptar / Cancelar) o quién la aceptó
local COIN_ICON = { "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon" }
local GOLD, GREEN, RED = { 1, 0.82, 0.2 }, { 0.3, 0.85, 0.35 }, { 0.9, 0.3, 0.25 }

-- Botones y pestañas con el estilo del Dungeon Journal (DJStyle.lua): rojos, y negros los elegidos
local DJ = HU.DJ
local function Flat(parent, text, w, h) return DJ.Button(parent, text, w, h) end
local function Tab(parent, text, w)
    local b = DJ.Button(parent, text, w, 24)
    function b:SetSelected(on) self:Pick(on) end
    return b
end

-- Columnas: en Público, con materiales; en Privado (más estrecha, con el chat al lado), sin ellos
local COLS = {
    pub = { { "who", "Quién", 100 }, { "item", "Receta / objeto", 170 }, { "qty", "Cant.", 40 }, { "mats", "Mats", 44 }, { "tip", "Propina", 66 }, { "state", "Estado", 0 },
        { "act", "Acción", ACT_W + 6 } },
    priv = { { "who", "Con quién", 86 }, { "item", "Receta / objeto", 120 }, { "qty", "Cant.", 36 }, { "tip", "Propina", 56 }, { "state", "Estado", 0 } },
    search = { { "who", "Quién", 110 }, { "guild", "Hermandad", 80 }, { "prof", "Profesión", 130 }, { "lvl", "Nivel", 0 } },
}

-- (en la sesión: fase 1, sin red)
local reqs = {}             -- { id, who, item, mats, tip, state = "open"|"taken"|"done"|"gone", taker, pub, to, t, test }
local chats = {}            -- [persona] = { líneas }: uno por persona
local chatKey
local view, filter, pubFilter = "pub", "all", "all"
local sortKey, sortDesc     -- nil: lo más nuevo arriba; si no, por esa columna (clic en su título)
local PUB_KEEP = 600        -- una aceptada sigue 10 min en el tablón de Público
local selected
local picks = {}            -- Privado: las elegidas con Ctrl / Mayús (para eliminar varias)
local lastPick              -- la última elegida (para Mayús)
local ui

local function Me() return HU:Me() or "?" end
local function IsMine(r) return r.who == Me() end
local function NewId() return string.format("%x%x", math.random(0, 0xffff), time() % 0xffff) end
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
-- Chat (derecha, solo en Privado): el de la persona del comercio que eliges. Solo se ve aquí
---------------------------------------------------------------------------
local function ChatLine(key, who, text)
    chats[key] = chats[key] or {}
    local line = (who == Me() and MINE or OTHERS) .. HU:Short(who) .. "|r: " .. text
    local l = chats[key]
    l[#l + 1] = line
    if #l > 200 then table.remove(l, 1) end
    if key == chatKey and ui then ui.msgs:AddMessage(line) end
end

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
end

---------------------------------------------------------------------------
-- Buscar: escribes y la lista pasa a ser la de quién lo tiene. Por ahora, las profesiones de mi
-- hermandad (las da el juego) y los nombres; recetas y objetos, y las otras hermandades, por red
---------------------------------------------------------------------------
-- Fabricables (CraftItems.lua): el juego da su nombre y enlace en tu idioma; se piden poco a poco (30 cada
-- medio segundo) la primera vez que se abre Comercio, y los que tarda se reintentan dos vueltas más [+ARCHITECTURE.md]
local craft = {}            -- [objeto] = { key = nombre en minúsculas, link, skill, lv }
local craftLoader
local function LoadCraftNames()
    if craftLoader or type(HU.CRAFT_ITEMS) ~= "table" then return end
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
                craft[id] = { key = name:lower(), link = link, skill = info[id].skill, lv = info[id].lv }
            else
                missing[#missing + 1] = id
            end
        end
    end, { pauseInCombat = true })
end

-- (las profesiones y el nivel que hacen falta para algo que encaje con q, por su nombre)
local function CraftNeeds(q)
    local needs, any = {}, false
    for _, c in pairs(craft) do
        if c.key:find(q, 1, true) and (needs[c.skill] == nil or c.lv < needs[c.skill]) then
            needs[c.skill] = c.lv; any = true
        end
    end
    return any and needs or nil
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
            for _, k in ipairs({ "1", "2" }) do
                local pid, pn, pr = info["profession" .. k .. "ID"], info["profession" .. k .. "Name"], info["profession" .. k .. "Rank"]
                local rank = (type(pr) == "number" and not HU.Secret(pr)) and pr or 0
                local need = needs and type(pid) == "number" and needs[pid]
                if type(pn) == "string" and not HU.Secret(pn) and (pn:lower():find(q, 1, true) or (need and rank >= need)) then
                    local icon
                    if type(pid) == "number" and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture then
                        local okI, tex = pcall(C_TradeSkillUI.GetTradeSkillTexture, pid)
                        if okI and tex and not HU.Secret(tex) then icon = tex end
                    end
                    out[#out + 1] = { name = HU:FullName(n) or n, tag = HU.myTag, prof = pn, icon = icon, online = not off,
                        rank = rank }
                end
            end
        end
    end
    table.sort(out, function(a, b) if a.rank ~= b.rank then return a.rank > b.rank end return a.name < b.name end)
    return out
end

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
        if v:lower():find(q, 1, true) then return true end
    end
    return false
end

local function Visible()
    local out = {}
    local q = Searching() and Query()
    for i = #reqs, 1, -1 do
        local r = reqs[i]
        local ok
        if q then
            ok = r.pub == true and (r.state == "open" or (r.state == "taken" and time() - (r.takenAt or 0) < PUB_KEEP))
                and Matches(r, q)
        elseif view == "pub" then
            -- (Público: las públicas abiertas y, 10 min más, las aceptadas, con quién la aceptó; el
            -- filtro deja solo las que nadie ha aceptado)
            ok = r.pub == true and (r.state == "open" or (r.state == "taken" and time() - (r.takenAt or 0) < PUB_KEEP))
            if pubFilter == "open" and r.state ~= "open" then ok = false end
        else
            -- (Privado: las que me tocan: las mías, las que me piden a mí y las que hago yo; con el filtro)
            -- (una pública sin aceptar no tiene a nadie al otro lado: solo sale en Público)
            ok = Involved(r) and not r.closed and not (r.pub and r.state == "open")
            if filter == "mine" then ok = ok and IsMine(r) elseif filter == "others" then ok = ok and not IsMine(r) end
        end
        if ok and r.state ~= "gone" then out[#out + 1] = r end
    end
    if sortKey then
        local STATE = { open = 1, taken = 2, done = 3 }
        local function V(r)
            if sortKey == "who" then return (view == "priv" and Other(r) or r.who or ""):lower() end
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

local function OpenCount()
    local n = 0
    for _, r in ipairs(reqs) do if IsMine(r) and r.state ~= "done" and r.state ~= "gone" then n = n + 1 end end
    return n
end

local Paint

-- Aceptar una de otro: la haces tú (sigue en Público con tu nombre, y aparece en tu Privado con su chat)
local function Accept(r)
    if IsMine(r) or r.state ~= "open" then return end
    r.state, r.taker, r.takenAt = "taken", Me(), time()
    OpenChat(r.who)
    Paint()
end
-- La X: mía, cancelarla; de otro (privada, me la piden a mí), rechazarla
local function Cancel(r)
    if r.state == "done" then return end
    if IsMine(r) or r.to == Me() then r.state = "gone"; selected = nil; Paint() end
end

-- Privado: quitar los comercios con esa persona y su chat
local function FindReq(id) for _, r in ipairs(reqs) do if r.id == id then return r end end end
-- (eliminar de mi Privado: la mía sin aceptar se cancela; las demás solo se quitan de mi lista)
local function RemoveReq(r)
    if IsMine(r) and r.state == "open" then r.state = "gone" else r.closed = true end
end
local function MarkDone(r)
    if r and r.state ~= "done" then r.state = "done"; Paint() end
end

-- Clic derecho en una fila: la otra persona (susurrar, invitar al grupo), en Privado cerrar con ella, en la
-- búsqueda pedirle una receta, y Cancelar (cierra el menú)
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
        if priv and r.state ~= "done" then
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
                c:Show(); c:ClearAllPoints(); c:SetPoint("LEFT", row, "LEFT", x + 3, 0); c:SetWidth(w - 4)
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
    lst.list:SetHeight((text and 14 or 0) + 24 + lst.n * ROW_H)
end

-- En Privado, con el chat a la derecha; en Público, a todo lo ancho. Al buscar: arriba las publicadas que
-- encajan y abajo quién lo hace [+ARCHITECTURE.md]
local function Layout()
    local searching = Searching()
    local priv = view == "priv" and not searching
    local req, found = ui.req, ui.found
    -- (en Privado, el chat siempre a la derecha)
    local withChat = priv
    ui.chat:SetShown(withChat)
    ui.filterBar:Hide()
    ui.pubFilterBar:Hide()
    req.list:ClearAllPoints()
    req.list:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 6, 0)
    if withChat then req.list:SetPoint("RIGHT", ui.chat, "LEFT", -6, 0)
    else req.list:SetPoint("RIGHT", ui.body, "RIGHT", -24, 0) end
    local noPub = searching and #Visible() == 0
    req.list:SetShown(not noPub)
    req.n = searching and SEARCH_ROWS or ROWS
    Titled(req, searching and L("Publicadas") or nil)
    found.n = noPub and ROWS or SEARCH_ROWS
    found.list:ClearAllPoints()
    if noPub then found.list:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 6, 0)
    else found.list:SetPoint("TOPLEFT", req.list, "BOTTOMLEFT", 0, -6) end
    found.list:SetPoint("RIGHT", ui.body, "RIGHT", -24, 0)
    Titled(found, L("Quién lo hace"))
    found.list:SetShown(searching)
    if priv then Columns(req, COLS.priv, 44) else Columns(req, COLS.pub, 4) end
    if searching then Columns(found, COLS.search, 4) end
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
    -- (comercio apagado por el maestro: solo el aviso)
    local off = HU.db.unionCfg and HU.db.unionCfg.tradeOff
    ui.offMsg:SetShown(off and true or false)
    ui.body:SetShown(not off)
    if off then return end
    BuildOnline()
    for k, b in pairs(ui.viewBtns) do b:SetSelected(k == view and not Searching()) end
    for k, b in pairs(ui.filterBtns) do
        b.text:SetText(k == filter and ("|cffffd100" .. b.label .. "|r") or ("|cff9a8f78" .. b.label .. "|r"))
        b.line:SetShown(k == filter)
    end
    for k, b in pairs(ui.pubFilterBtns) do
        b.text:SetText(k == pubFilter and ("|cffffd100" .. b.label .. "|r") or ("|cff9a8f78" .. b.label .. "|r"))
        b.line:SetShown(k == pubFilter)
    end
    Layout()
    local searching = Searching()
    if searching then
        ui.found.empty:SetText(L("Nadie de tu hermandad lo hace (profesión u objeto fabricable). Otras hermandades, con la red."))
        PaintRows(ui.found, SearchMembers(Query()), function(row, e)
            local c = row.cells
            -- (con su color de siempre y el circulito; clic derecho: pedir una receta)
            c[1]:SetText((e.name == Me() and MINE or OTHERS) .. HU:Short(e.name) .. "|r " .. (e.online and DOT_ON or DOT_OFF))
            c[2]:SetText("|cff" .. HU:GuildColorHex(e.tag) .. tostring(e.tag or "") .. "|r")
            c[3]:SetText((e.icon and ("|T" .. e.icon .. ":14:14|t ") or "") .. e.prof); c[4]:SetText(tostring(e.rank))
        end)
    end
    ui.req.empty:SetText(searching and L("Ninguna solicitud publicada encaja.") or L("No hay solicitudes."))
    ui.lastList = Visible()
    local nPicks = 0
    for _ in pairs(picks) do nPicks = nPicks + 1 end
    ui.delBtn:SetShown(view == "priv" and not searching and nPicks > 0)
    ui.delBtn:SetText(string.format(L("Eliminar (%d)"), nPicks))
    local cur = selected and FindReq(selected)
    ui.doneBtn:SetShown(view == "priv" and not searching and cur ~= nil and Involved(cur))
    ui.doneBtn:SetEnabled(cur ~= nil and cur.state ~= "done")
    PaintRows(ui.req, ui.lastList, function(row, r)
        local mine = IsMine(r)
        local c = row.cells
        local tip = r.tip and Coins(r.tip) or ("|cff9a8f78" .. L("A negociar") .. "|r")
        local test = r.test and (" |cff808080(" .. L("prueba") .. ")|r") or ""
        row.pickTex:SetShown(r.id == selected or picks[r.id] == true)
        if view == "pub" or searching then
            c[1]:SetText(mine and (MINE .. L("Yo") .. "|r " .. DOT_ON) or (OTHERS .. HU:Short(r.who) .. "|r " .. Dot(r.who)))
            c[2]:SetText(r.item or "?"); c[3]:SetText(tostring(r.qty or 1))
            c[4]:SetText(r.mats == nil and "—" or (r.mats and L("Sí") or L("No"))); c[5]:SetText(tip)
            c[6]:SetText(StateText(r) .. test)
            -- (la última columna: Aceptar si es de otro y está abierta; Cancelar si es mía; si ya la
            -- aceptó alguien, su nombre)
            -- (Aceptar si es de otro y está abierta; Cancelar si es mía; si ya la aceptó alguien, su nombre)
            if r.taker then
                row.actText:SetText(r.taker == Me() and (MINE .. L("Yo") .. "|r") or (OTHERS .. HU:Short(r.taker) .. "|r " .. Dot(r.taker))); row.actText:Show()
            elseif mine then
                row.cancel:Show()
            elseif r.state == "open" then
                row.accept:Show()
            end
        else
            local other = Other(r)
            c[1]:SetText(other and ((mine and MINE or OTHERS) .. HU:Short(other) .. "|r " .. Dot(other)) or ("|cff9a8f78" .. L("Tablón") .. "|r"))
            c[2]:SetText(r.item or "?"); c[3]:SetText(tostring(r.qty or 1)); c[4]:SetText(tip)
            c[5]:SetText(StateText(r) .. test)
            -- (solo en las abiertas: el tic para aceptarla —si me la piden a mí— y la X para cancelarla —mía—
            -- o rechazarla; las aceptadas, sin nada)
            row.yes:SetShown(r.state == "open" and not mine)
            row.no:SetShown(r.state == "open")
        end
    end)
end

---------------------------------------------------------------------------
-- Nueva solicitud: objeto (con autorrelleno), quién pone los materiales, propina en oro · plata · cobre
-- y si es pública o para alguien (con autorrelleno del nombre) [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local SUGGEST_N = 6

-- Lista de sugerencias bajo una caja: source(q) da { { text, value, pre } }; clic o Intro (la primera) la elige
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
        btns[i] = b
    end
    box:HookScript("OnTextChanged", function(s, user)
        if not user then list:Hide(); return end
        local q = HU.Trim(s:GetText() or "")
        found = #q >= 2 and source(q) or {}
        table.sort(found, function(x, y) if x.pre ~= y.pre then return x.pre end return Plain(x.text) < Plain(y.text) end)
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

-- Objetos que el juego ya conoce: el de ese nombre exacto, los de mis bolsas y los de las solicitudes
local function ItemMatches(text)
    local q = text:lower()
    local out, seen = {}, {}
    local function add(link)
        if type(link) ~= "string" or HU.Secret(link) or not link:find("|H", 1, true) then return end
        local k = Plain(link):lower():gsub("^%[", ""):gsub("%]$", "")
        if seen[k] or not k:find(q, 1, true) then return end
        seen[k] = true
        out[#out + 1] = { text = link, value = link, pre = k:sub(1, #q) == q }
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
    for _, c in pairs(craft) do
        if #out >= 60 then break end
        if not seen[c.key] and c.key:find(q, 1, true) then
            seen[c.key] = true
            out[#out + 1] = { text = c.link, value = c.link, pre = c.key:sub(1, #q) == q }
        end
    end
    return out
end

-- Personajes que conozco: mi hermandad, las listas de las otras y los que tienen GuildUnion
local function NameMatches(text)
    local q = text:lower()
    local out, seen = {}, { [Me():lower()] = true }
    local function add(full, tag)
        if type(full) ~= "string" or HU.Secret(full) then return end
        local k = full:lower()
        local short = HU:Short(full)
        if seen[k] or not short:lower():find(q, 1, true) then return end
        seen[k] = true
        local t = tag and (" |cff" .. HU:GuildColorHex(tag) .. "<" .. tag .. ">|r") or ""
        out[#out + 1] = { text = short .. t, value = full, pre = short:lower():sub(1, #q) == q }
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

    Label(L("Objeto (escribe su nombre o Mayús+clic):"), 12, -34)
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

    Label(L("Pública:"), 12, -170)
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

    local ok = Flat(d, L("Pedir"), 110, 22, GREEN); ok:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 12)
    local no = Flat(d, L("Cancelar"), 110, 22, { 0.75, 0.75, 0.75 }); no:SetPoint("BOTTOMLEFT", d, "BOTTOM", 6, 12)
    no:SetScript("OnClick", function() d:Hide() end)
    ok:SetScript("OnClick", function()
        local item = HU.Trim(d.item:GetText() or "")
        if item == "" then return HU:Print(L("Pon el objeto que pides (Mayús+clic en él).")) end
        if OpenCount() >= MAX_OPEN then return HU:Print(string.format(L("Ya tienes %d solicitudes abiertas: cierra alguna antes."), MAX_OPEN)) end
        local pub = d.pubYes:GetChecked() and true or false
        local to = HU.Trim(d.to:GetText() or "")
        if not pub and to == "" then return HU:Print(L("Una solicitud privada necesita a quién se la pides.")) end
        -- (la propina, en cobre; las tres cajas vacías: a negociar)
        local tip, any = 0, false
        for i, box in ipairs(d.coins) do
            local v = tonumber(box:GetText() or "")
            if v then any = true; tip = tip + v * (i == 1 and 10000 or i == 2 and 100 or 1) end
        end
        local mats
        if d.matsMe:GetChecked() then mats = true elseif d.matsSeller:GetChecked() then mats = false end
        reqs[#reqs + 1] = { id = NewId(), who = Me(), item = item, mats = mats, tip = (any and not (HU.db.unionCfg and HU.db.unionCfg.tipsOff)) and tip or nil, qty = math.max(1, tonumber(d.qty:GetText() or "") or 1), state = "open", pub = pub,
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
-- Modo prueba: solicitudes y chats de mentira; no se manda nada
---------------------------------------------------------------------------
-- (quitar lo de prueba: sus solicitudes y los chats con los de prueba)
local function ClearTest()
    for k = #reqs, 1, -1 do if reqs[k].test then table.remove(reqs, k) end end
    for key in pairs(chats) do if key:find("%-Prueba$") then chats[key] = nil end end
    if chatKey and chatKey:find("%-Prueba$") then OpenChat(nil) end
    selected, picks = nil, {}
end

local function AddTest()
    ClearTest()
    local now = time()
    local function R(who, item, mats, tip, state, pub, to, taker, qty)
        reqs[#reqs + 1] = { id = NewId() .. #reqs, who = who, item = item, mats = mats, tip = tip and tip * 10000, qty = qty, state = state, pub = pub,
            to = to, taker = taker, takenAt = taker and now or nil, t = now, test = true }
    end
    local function Link(id, name, color)
        local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local ok, _, link = pcall(get, id)
        if ok and type(link) == "string" then return link end
        return "|cff" .. color .. "|Hitem:" .. id .. "::::::::60:::::::|h[" .. name .. "]|h|r"
    end
    R("Janeth-Prueba", Link(3928, "Poción de curación superior", "ffffff"), false, 2.5, "open", true, nil, nil, 5)
    R("Pepe-Prueba", Link(7378, "Bolsa de tejido de lana", "1eff00"), true, nil, "open", true)
    R("Lyra-Prueba", Link(7931, "Cofia de mitril", "1eff00"), true, 3, "taken", true, nil, "Bea-Prueba")
    R(Me(), Link(7056, "Capa de seda carmesí", "1eff00"), true, 5, "open", true)
    R("Bea-Prueba", Link(8949, "Elixir de agilidad", "ffffff"), false, 1, "open", false, Me())
    R(Me(), Link(7954, "Gran espada de mitril", "0070dd"), true, nil, "taken", false, "Pepe-Prueba", "Pepe-Prueba")
    R("Lyra-Prueba", Link(7931, "Cofia de mitril", "1eff00"), true, 2, "open", false, Me())
    R(Me(), Link(3928, "Poción de curación superior", "ffffff"), false, 0.5, "open", false, "Janeth-Prueba")
    ChatLine("Lyra-Prueba", "Lyra-Prueba", L("Te dejo el encargo; mañana me conecto."))
    ChatLine("Pepe-Prueba", "Pepe-Prueba", L("Te hago la espada esta noche."))
    ChatLine("Bea-Prueba", "Bea-Prueba", L("¿Me haces el elixir? Pago bien."))
    Paint()
end

---------------------------------------------------------------------------
-- Montar la sección (UnionRoster.lua la pone en la pestaña Trade)
---------------------------------------------------------------------------
function HU:BuildTrade(host)
    ui = host
    -- Arriba: Público · Privado, el buscador y el modo prueba
    ui.viewBtns = {}
    local prev
    for _, t in ipairs({ { "pub", L("Público") }, { "priv", L("Privado") } }) do
        local b = Tab(host, t[2], 100)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPRIGHT", host, "TOP", -2, -1) end
        b:SetScript("OnClick", function()
            view, selected, picks = t[1], nil, {}
            ui.search:SetText("")
            FauxScrollFrame_SetOffset(ui.scroll, 0)
            Paint()
        end)
        ui.viewBtns[t[1]] = b
        prev = b
    end
    local search = CreateFrame("EditBox", "GuildUnionTradeSearch", host, "SearchBoxTemplate")
    search:SetSize(150, 20)
    search:SetPoint("TOPLEFT", host, "TOPLEFT", 14, -4)
    if search.Instructions then search.Instructions:SetText(L("Buscar")) end
    search:HookScript("OnTextChanged", function()
        if not ui.found then return end
        FauxScrollFrame_SetOffset(ui.req.scroll, 0); FauxScrollFrame_SetOffset(ui.found.scroll, 0)
        Paint()
    end)
    ui.search = search
    local test = Flat(host, L("Modo prueba"), 100, 22)
    test:SetPoint("TOPRIGHT", host, "TOPRIGHT", -26, -3)
    -- (el modo prueba se enciende y se apaga: apagado, se quita lo de prueba)
    test:SetScript("OnClick", function(b)
        if ui.testOn then ClearTest(); ui.testOn = nil else AddTest(); ui.testOn = true end
        b:Pick(ui.testOn == true)
        Paint()
    end)
    ui.testBtn = test

    local rule = host:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25); rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", host, "TOPLEFT", 6, -27); rule:SetPoint("TOPRIGHT", host, "TOPRIGHT", -24, -27)

    -- (detrás de todo, el panel de la sección: color «content», borde y pergamino, como el calendario)
    local bg = CreateFrame("Frame", nil, host, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -58); bg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)
    bg:SetFrameLevel(host:GetFrameLevel() + 1)
    DJ.Panel(bg, DJ.T.content, DJ.T.border, 14, 4)
    DJ.Parchment(bg, 0.18)
    local body = CreateFrame("Frame", nil, host)
    body:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -62); body:SetPoint("BOTTOMRIGHT")
    body:SetFrameLevel(bg:GetFrameLevel() + 2)
    ui.body = body
    ui.offMsg = DJ.C(host:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), DJ.T.muted)
    ui.offMsg:SetPoint("CENTER"); ui.offMsg:SetWidth(420)
    ui.offMsg:SetText(L("El maestro de la hermandad ha desactivado el comercio (pestaña GuildUnion, Configuración → Comercio)."))
    HU:Listen("CHANGED", function(what) if what == "unionCfg" and ui:IsShown() then Paint() end end)

    -- Derecha (solo en Privado): el chat de la persona del comercio que eliges
    local chat = CreateFrame("Frame", nil, body, "BackdropTemplate")
    chat:SetPoint("TOPRIGHT", -24, 0); chat:SetPoint("BOTTOMRIGHT", -24, 10); chat:SetWidth(CHAT_W)
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
    msgs:SetFontObject(GameFontHighlightSmall); msgs:SetJustifyH("LEFT")
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

    -- (en Privado, encima de la lista: Todas · Mías · De otros, como texto: el elegido, dorado y subrayado)
    local bar = CreateFrame("Frame", nil, body)
    bar:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -2); bar:SetSize(260, 14)
    ui.filterBar = bar
    ui.filterBtns = {}
    prev = nil
    for _, t in ipairs({ { "all", L("Todas") }, { "mine", L("Mías") }, { "others", L("De otros") } }) do
        local b = CreateFrame("Button", nil, bar)
        b.label = t[2]
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("LEFT"); b.text:SetText(t[2])
        b:SetSize(math.max(40, (b.text:GetStringWidth() or 40) + 4), 14)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetColorTexture(1, 0.82, 0, 0.9); b.line:SetHeight(1)
        b.line:SetPoint("BOTTOMLEFT", 0, -1); b.line:SetPoint("BOTTOMRIGHT", 0, -1)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 14, 0) else b:SetPoint("LEFT", bar, "LEFT", 0, 0) end
        b:SetScript("OnClick", function() filter = t[1]; Paint() end)
        ui.filterBtns[t[1]] = b
        prev = b
    end

    local pbar = CreateFrame("Frame", nil, body)
    pbar:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -2); pbar:SetSize(260, 14)
    ui.pubFilterBar = pbar
    ui.pubFilterBtns = {}
    prev = nil
    for _, t in ipairs({ { "all", L("Todas") }, { "open", L("Sin aceptar") } }) do
        local b = CreateFrame("Button", nil, pbar)
        b.label = t[2]
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("LEFT"); b.text:SetText(t[2])
        b:SetSize(math.max(40, (b.text:GetStringWidth() or 40) + 4), 14)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetColorTexture(1, 0.82, 0, 0.9); b.line:SetHeight(1)
        b.line:SetPoint("BOTTOMLEFT", 0, -1); b.line:SetPoint("BOTTOMRIGHT", 0, -1)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 14, 0) else b:SetPoint("LEFT", pbar, "LEFT", 0, 0) end
        b:SetScript("OnClick", function() pubFilter = t[1]; Paint() end)
        ui.pubFilterBtns[t[1]] = b
        prev = b
    end

    -- Las listas: las solicitudes y, al buscar, debajo, quién lo hace
    local function MakeList(n, sortable, sfName)
        local lst = { n = n, rows = {}, hdrCells = {} }
        local list = CreateFrame("Frame", nil, body)
        lst.list = list
        lst.title = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lst.title:SetPoint("TOPLEFT", list, "TOPLEFT", 4, 0); lst.title:Hide()
        local hdr = CreateFrame("Frame", nil, list)
        hdr:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0); hdr:SetPoint("RIGHT", list, "RIGHT", 0, 0); hdr:SetHeight(22)
        local hline = hdr:CreateTexture(nil, "ARTWORK")
        hline:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35); hline:SetHeight(1)
        hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT")
        lst.hdr = hdr
        for i = 1, 7 do
            local b = CreateFrame("Button", nil, hdr)
            b:SetHeight(22)
            b:SetNormalFontObject("GameFontNormalSmall")
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
            b:SetScript("OnClick", function(s)
                local key = s.key
                if not sortable or not key or key == "act" and view ~= "pub" then return end
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
                stripe:SetAllPoints(); stripe:SetColorTexture(1, 1, 1, 0.04)
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
            -- (Público, última columna: Aceptar / Cancelar, o el nombre de quien la aceptó)
            local accept = Flat(row, L("Aceptar"), ACT_W, 16, GREEN)
            accept:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            accept:SetScript("OnClick", function() if row.entry then Accept(row.entry) end end)
            local actText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            actText:SetPoint("RIGHT", row, "RIGHT", -2, 0); actText:SetWidth(ACT_W); actText:SetJustifyH("CENTER")
            local cancel = Flat(row, L("Cancelar"), ACT_W, 16, RED)
            cancel:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            cancel:SetScript("OnClick", function() if row.entry then Cancel(row.entry) end end)
            row.accept, row.cancel, row.actText = accept, cancel, actText
            -- (Privado: el tic y la X, en las mías)
            local no = CreateFrame("Button", nil, row)
            no:SetSize(16, 16); no:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            no:SetNormalTexture(CROSS); no:SetHighlightTexture(CROSS, "ADD")
            no:SetScript("OnClick", function() if row.entry then Cancel(row.entry) end end)
            local yes = CreateFrame("Button", nil, row)
            yes:SetSize(16, 16); yes:SetPoint("RIGHT", no, "LEFT", -4, 0)
            yes:SetNormalTexture(TICK); yes:SetHighlightTexture(TICK, "ADD")
            yes:SetScript("OnClick", function() if row.entry then Accept(row.entry) end end)
            row.yes, row.no = yes, no
            -- (clic: elegirla; en Privado, además, el chat pasa a ser el de esa persona. En la búsqueda, clic
            -- derecho: pedirle una receta)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(s, button)
                local r = s.entry
                if r and button == "RightButton" then return RowMenu(s, r) end
                if not (r and r.id) then return end
                -- (en Privado: Ctrl suma o quita; Mayús elige desde la última hasta esta; clic solo, solo esa)
                if view == "priv" and not Searching() then
                    if IsControlKeyDown() then
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

    -- Abajo: Nueva solicitud
    local newDlg = BuildNewDialog(host)
    local new = Flat(host, "+ " .. L("Nueva solicitud"), 200, 24)
    new:SetPoint("TOP", host, "TOP", 0, -30)
    -- (destacado como «+ Nuevo evento»: las piezas del botón teñidas de verde y la letra blanca)
    for _, k in ipairs({ "Left", "Middle", "Right" }) do if new[k] then new[k]:SetVertexColor(0.45, 1, 0.45) end end
    new:SetNormalFontObject("GameFontHighlight")
    -- (to: pedírsela a alguien en concreto, privada: «Pedir una receta» desde la búsqueda)
    function ui.OpenNew(to)
        newDlg.title:SetText(to and (L("Pedir una receta a ") .. HU:Short(to)) or L("Nueva solicitud"))
        newDlg.item:SetText(""); newDlg.to:SetText(to or ""); newDlg.qty:SetText("1")
        for _, box in ipairs(newDlg.coins) do box:SetText("") end
        local noTips = HU.db.unionCfg and HU.db.unionCfg.tipsOff
        for _, w in ipairs(newDlg.tipParts) do w:SetShown(not noTips) end
        newDlg.matsMe:SetChecked(true); newDlg.matsSeller:SetChecked(false)
        newDlg.SetPub(not to and view == "pub")
        newDlg:Show(); newDlg.item:SetFocus()
    end
    new:SetScript("OnClick", function() ui.OpenNew(nil) end)
    ui.new = new
    local del = Flat(body, "", 110, 22)
    del:SetPoint("LEFT", new, "RIGHT", 8, 0)
    del:SetScript("OnClick", function()
        for id in pairs(picks) do local x = FindReq(id); if x then RemoveReq(x) end end
        picks, selected = {}, nil
        Paint()
    end)
    del:Hide()
    ui.delBtn = del

    Suggest(ui.search, ItemMatches)
    host:HookScript("OnShow", function() LoadCraftNames(); Paint() end)
    LoadCraftNames()
    OpenChat(nil)
    Paint()
end

HU:Module("Trade", { "BlizzTab", "Config", "Core", "ListWindow" })
