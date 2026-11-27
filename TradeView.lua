-- Guild Union - Comercio: lo que se ve en el Tablón y en Mis encargos (qué solicitudes, en qué orden y con qué texto), las
-- columnas, las listas y Paint, y el montaje de la sección (T.Build, que es HU:BuildTrade en Trade.lua). Comparte lo suyo
-- por HU.TradeInternal (Trade.lua) [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L
local DJ = HU.DJ

-- (la casilla «Solo lo que puedo hacer», por personaje: ver OnlyCraft)
HU:Saved({ char = { "tradeOnlyCraft" } })

local T = HU.TradeInternal
local Me, IsMe, IsMine, Other, EntryKey, IdOf, Plain, Coins = T.Me, T.IsMe, T.IsMine, T.Other, T.EntryKey, T.IdOf, T.Plain, T.Coins
local Interested, Involved, Expired, Dot, Searching, BuildOnline = T.Interested, T.Involved, T.Expired, T.Dot, T.Searching, T.BuildOnline
local ChatOnScreen, MarkRead, PaintUnread, UnreadMark = T.ChatOnScreen, T.MarkRead, T.PaintUnread, T.UnreadMark
local ChatLine, OpenChat, SendChat, Fresh, NeedAll, FindReq = T.ChatLine, T.OpenChat, T.SendChat, T.Fresh, T.NeedAll, T.FindReq
local Accept, Cancel, RemoveReq, RemovePicked = T.Accept, T.Cancel, T.RemoveReq, T.RemovePicked
local CanMarkDone, MarkDone, CanMarkSold, MarkSold = T.CanMarkDone, T.MarkDone, T.CanMarkSold, T.MarkSold
local MINE, OTHERS, GREY, DOT_ON, DOT_OFF, GOLD = T.MINE, T.OTHERS, T.GREY, T.DOT_ON, T.DOT_OFF, T.GOLD
local LoadCraftNames, SearchMembers, ResetCrafters = T.LoadCraftNames, T.SearchMembers, T.ResetCrafters
local MyProfessions, CraftCheck, CraftTargets = T.MyProfessions, T.CraftCheck, T.CraftTargets
local HyperTip, Suggest, ItemMatches, BuildNewDialog = T.HyperTip, T.Suggest, T.ItemMatches, T.BuildNewDialog

-- (filas y títulos de 24, con 4 de margen a cada lado del texto: Jorge, 24/11, «muy apelotonado». Caben en la sección
-- con la ventana del juego a su alto de siempre: comercio_spec)
local ROW_H, ROWS = 24, 9
local HDR_H, CELL_PAD = 24, 4
-- (arriba, dos filas: los botones Tablón · Mis encargos · Buscar (DJ.Switch) y, en ROW2_Y, el buscador y la casilla (en
-- Buscar, los filtros); las listas van de BODY_Y a BOTTOM_H por encima del borde de abajo, donde va «+ Nuevo anuncio» (24
-- de alto, a 8 del borde), para que no tape nada) [+ARCHITECTURE.md]
local ROW2_Y, ROW2_H = -36, 28   -- (más pegada a los botones: Jorge, 24/11, «sube un poco más»)
local BODY_Y, BOTTOM_H = -74, 36   -- (la lista, 6 por debajo del buscador: Jorge, 24/11, «un poco menos» de gris)
local SEARCH_W = 200
local SEARCH_ROWS = 3       -- al buscar: filas de cada mitad (publicadas arriba, quién lo hace abajo)
-- (la barra de bajar va a la derecha de su lista, por fuera; cada lista le deja su sitio (scroll) y el borde del panel
-- (edge), para que no se salga: listR en total. Jorge, 25/11: «cuidado con las barras de bajar que se salen un poco». Y la
-- ventana de quién lo hace un objeto de Buscar (who*) y su botón «Ver todos» (allW), en TradeFind.lua) [+ARCHITECTURE.md]
local SIZES = { edge = 10, scroll = 24, listR = 34, whoW = 460, whoH = 402, whoRows = 10, allW = 64 }
-- (las ventas, de otro color: su texto y un fondo suave en la fila)
local SALE, SALE_RGB = "|cff3fd0c0", { 0.25, 0.82, 0.75 }
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local CHAT_W = 200
local ACT_W = 84            -- la última columna: el botón (Aceptar / Me interesa / Cancelar) o quién la aceptó
local PUB_KEEP = 600        -- una aceptada (o vendida) sigue 10 min en el Tablón

-- Columnas: en el Tablón, con materiales; en Mis encargos (más estrecha, con el chat al lado), sin ellos; en Buscar, los
-- objetos que encajan con quién lo hace
local COLS = {
    pub = { { "who", "Quién", 100 }, { "item", "Receta / objeto", 170 }, { "qty", "Cant.", 40 }, { "mats", "Mats", 44 }, { "tip", "Propina", 66 }, { "state", "Estado", 0 },
        { "act", "Acción", ACT_W + 6 } },
    priv = { { "who", "Con quién", 86 }, { "item", "Receta / objeto", 120 }, { "qty", "Cant.", 36 }, { "tip", "Propina", 56 }, { "state", "Estado", 0 } },
    search = { { "who", "Quién", 110 }, { "guild", "Hermandad", 80 }, { "prof", "Profesión", 130 }, { "lvl", "Nivel", 0 } },
    find = { { "item", "Objeto", 0 }, { "lvl", "Nivel", 44 }, { "prof", "Profesión", 120 }, { "who", "Quién lo hace", 92 },
        { "board", "Tablón", 84 } },
}

local sortKey, sortDesc     -- nil: lo más nuevo arriba; si no, por esa columna (clic en su título), si la vista la tiene
local lastPick              -- Mis encargos: la última elegida (para Mayús)

---------------------------------------------------------------------------
-- Lo que se ve: las solicitudes de cada vista, en su orden, y lo que dice cada una
---------------------------------------------------------------------------
local function Query()
    local t = Plain(HU.Trim(T.ui.search:GetText() or ""))
    return (t:gsub("^%[", ""):gsub("%]$", "")):lower()
end

local function StateText(r)
    if r.sale then
        if r.state == "sold" then return GREY .. L("Vendida") .. "|r" end
        return SALE .. L("Venta") .. "|r"
    end
    if r.state == "done" then return GREY .. L("Hecha") .. "|r" end
    if r.state == "taken" then return "|cff40ff40" .. L("Aceptada") .. "|r" end
    return L("Abierta")
end
-- (en el Tablón, cuánto le queda a uno abierto: «5h» o, la última hora, «<1h»; en minutos no cabía sin apretar)
local function TimeLeft(r, now)
    if not r.exp or r.state ~= "open" then return "" end
    local s = r.exp - now
    return " " .. GREY .. (s >= 3600 and (math.floor(s / 3600 + 0.5) .. "h") or "<1h") .. "|r"
end

local function Matches(r, q)
    for _, v in ipairs({ HU:Short(r.who or ""), Plain(r.item), r.taker and HU:Short(r.taker) or "" }) do
        if HU.TextRank(v, q) then return true end
    end
    return false
end

-- (¿está puesta «Solo lo que puedo hacer»? vale en las dos vistas y al buscar)
local function OnlyCraft() return HU.db ~= nil and HU.db.tradeOnlyCraft == true end

-- (¿sale en el Tablón? los abiertos y, 10 min más, los aceptados, con quién lo aceptó, y los vendidos; con la hora del
-- servidor, la de la red)
local function OnBoard(r, now)
    if r.pub ~= true then return false end
    if r.state == "open" then return true end
    if r.state == "taken" then return now - (r.takenAt or 0) < PUB_KEEP end
    return r.state == "sold" and now - (r.soldAt or 0) < PUB_KEEP
end

-- (profs: las de MyProfessions, si ya están leídas)
local function Visible(profs)
    local out = {}
    local q = Searching() and Query()
    local priv = T.view == "priv" and not q
    local only = OnlyCraft()
    local now = HU.StampNow()
    if only and profs == nil then profs = MyProfessions() end
    local reqs = T.reqs
    for i = #reqs, 1, -1 do
        local r = reqs[i]
        local ok
        if r.state == "gone" or Expired(r, now) then
            ok = false
        elseif not priv then
            -- (Tablón y, al buscar, lo publicado que encaja)
            ok = OnBoard(r, now) and (not q or Matches(r, q))
        else
            -- (Mis encargos: las que me tocan: las mías, las que me piden a mí, las que hago yo y las ventas que me
            -- interesan. Una pública sin aceptar no tiene a nadie al otro lado: solo sale en el Tablón; una venta mía,
            -- una fila con cada interesado)
            ok = Involved(r) and not r.closed
            if ok and r.sale and IsMine(r) then
                for _, b in ipairs(r.buyers or {}) do out[#out + 1] = setmetatable({ buyer = b }, { __index = r }) end
                ok = false
            elseif ok and not r.sale then
                ok = not (r.pub and r.state == "open")
            end
        end
        -- (con la casilla: en el Tablón y al buscar, solo lo que se reconoce y puedo hacer (una venta no se hace); en Mis
        -- encargos, fuera lo que haría yo y no puedo hacer, y lo que pedí yo o quiero comprar, siempre: Jorge, 24/11)
        if ok and only then
            if priv then ok = IsMine(r) or r.sale or (CraftCheck(r.item, profs))
            else ok = not r.sale and CraftTargets(r.item) ~= nil and (CraftCheck(r.item, profs)) end
        end
        if ok then out[#out + 1] = r end
    end
    if sortKey then
        local STATE = { open = 1, taken = 2, done = 3, sold = 4 }
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
    -- (en Mis encargos, primero las de los chats con algo sin leer, cada grupo en su orden: Jorge, 25/11, «los chats sin
    -- leer en la pestaña de "my orders" serán los primeros que aparezcan y con un "brillo"». Ese orden se hace al entrar
    -- en Mis encargos, al abrir la sección y cuando llega algo sin leer (`ui.rerank`), y se guarda (`ui.privRank`):
    -- leer un chat no lo cambia, para que las filas no salten bajo el ratón. Lo que no estaba, detrás) [+ARCHITECTURE.md]
    local ui = T.ui
    if priv and ui then
        if ui.rerank or not ui.privRank then
            ui.rerank, ui.privRank = nil, {}
            local n = 0
            for pass = 1, 2 do
                for _, r in ipairs(out) do
                    if (T.unread[Other(r) or ""] ~= nil) == (pass == 1) then n = n + 1; ui.privRank[EntryKey(r)] = n end
                end
            end
        end
        local rank, pos = ui.privRank, {}
        for i, r in ipairs(out) do pos[r] = i end
        table.sort(out, function(a, b)
            local ra, rb = rank[EntryKey(a)] or math.huge, rank[EntryKey(b)] or math.huge
            if ra ~= rb then return ra < rb end
            return pos[a] < pos[b]
        end)
    end
    return out
end

---------------------------------------------------------------------------
-- Columnas, listas y Paint
---------------------------------------------------------------------------
-- Coloca columnas, títulos y filas según lo que toca (la flecha de orden, solo en las listas que se ordenan)
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
            local arrow = (lst.sortable and sortKey == col[1]) and (sortDesc and " v" or " ^") or ""
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
    local cols = (T.view == "priv" and not Searching()) and COLS.priv or COLS.pub
    if not HU:UnionCfg().tipsOff then return cols end
    local out = {}
    for _, col in ipairs(cols) do if col[1] ~= "tip" then out[#out + 1] = col end end
    return out
end

-- En Mis encargos, con el chat a la derecha; en el Tablón, a todo lo ancho. Al buscar: arriba las publicadas que
-- encajan y abajo quién lo hace [+ARCHITECTURE.md]. `list`: las solicitudes que se ven (Visible). (Buscar: TradeFind.lua)
local function Layout(cols, list)
    local ui = T.ui
    local searching = Searching()
    local priv = T.view == "priv" and not searching
    local req, found = ui.req, ui.found
    ui.items.list:Hide()
    -- (en Mis encargos, el chat siempre a la derecha)
    local withChat = priv
    ui.chat:SetShown(withChat)
    req.list:ClearAllPoints()
    req.list:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 6, 0)
    -- (con el chat, su barra de bajar va entre la lista y el chat, sin pisarlo)
    if withChat then req.list:SetPoint("RIGHT", ui.chat, "LEFT", -(6 + SIZES.scroll), 0)
    else req.list:SetPoint("RIGHT", ui.body, "RIGHT", -SIZES.listR, 0) end
    local noPub = searching and #list == 0
    req.list:SetShown(not noPub)
    req.n = searching and SEARCH_ROWS or ROWS
    Titled(req, searching and L("Publicadas") or nil)
    -- (quién lo hace, sola: con su título, cabe una fila menos)
    found.n = noPub and ROWS - 1 or SEARCH_ROWS
    found.list:ClearAllPoints()
    if noPub then found.list:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 6, 0)
    else found.list:SetPoint("TOPLEFT", req.list, "BOTTOMLEFT", 0, -6) end
    found.list:SetPoint("RIGHT", ui.body, "RIGHT", -SIZES.listR, 0)
    Titled(found, L("Quién lo hace"))
    found.list:SetShown(searching)
    Columns(req, cols, priv and 44 or 4)
    if searching then Columns(found, COLS.search, 4) end
    -- («+ Nuevo anuncio», en el centro de la sección; en Mis encargos, en el de la lista, que deja la derecha al chat:
    -- así no choca con él. Jorge, 24/11)
    ui.new:ClearAllPoints()
    ui.new:SetPoint("BOTTOM", ui, "BOTTOM", withChat and -(SIZES.edge + CHAT_W + SIZES.scroll) / 2 or 0, 8)
    ui.new:SetShown(not searching)
end

local function PaintRows(lst, list, fill)
    FauxScrollFrame_Update(lst.scroll, #list, lst.n, ROW_H)
    local off = FauxScrollFrame_GetOffset(lst.scroll)
    for i, row in ipairs(lst.rows) do
        local e = i <= lst.n and list[off + i] or nil
        row.entry = e
        row.accept:Hide(); row.cancel:Hide(); row.actText:Hide()
        row.itemBtn:SetShown(e ~= nil and e.item ~= nil); row.yes:Hide(); row.no:Hide(); row.pickTex:Hide(); row.saleTex:Hide()
        row.glow:Hide()
        if e then fill(row, e); row:Show() else row:Hide() end
        -- (el clic del enlace, solo encima del texto del enlace, no en toda la casilla)
        if row.itemBtn:IsShown() then
            local fs = row.cells[lst.itemCol or 2]
            local w = fs:GetStringWidth() or 0
            local cw = fs:GetWidth() or w
            row.itemBtn:SetWidth(math.max(8, math.min(w, cw > 0 and cw or w) + 2))
        end
    end
    lst.empty:SetShown(#list == 0)
end

-- (una fila de «Quién lo hace»: con su color de siempre y el circulito; clic derecho: pedir una receta. El tic: sabe la
-- receta)
local function FillWho(row, e)
    local c = row.cells
    c[1]:SetText((e.name == Me() and MINE or OTHERS) .. HU:Short(e.name) .. "|r " .. (e.online and DOT_ON or DOT_OFF))
    c[2]:SetText("|cff" .. HU:GuildColorHex(e.tag) .. tostring(HU:TagLabel(e.tag) or "") .. "|r")
    c[3]:SetText((e.icon and ("|T" .. e.icon .. ":14:14|t ") or "") .. e.prof)
    c[4]:SetText((e.rank and tostring(e.rank) or "—") .. (e.knows and (" |T" .. TICK .. ":12:12|t") or ""))
end

-- (una fila de solicitudes, de Paint: lo de cada columna y lo de la última o, en Mis encargos, el tic y la X. `profs`, las
-- de MyProfessions; `now`, la hora del servidor; `searching`, si se busca)
local function FillReq(row, r, cols, profs, now, searching)
    local mine = IsMine(r)
    local test = r.test and (" |cff808080(" .. L("prueba") .. ")|r") or ""
    local key = EntryKey(r)
    row.pickTex:SetShown(key == T.selected or T.picks[key] == true)
    row.saleTex:SetShown(r.sale == true)
    -- (lo de cada columna, por su clave: sin propinas, la suya no está)
    local v = { item = r.item or "?", qty = tostring(r.qty or 1), state = StateText(r) .. test,
        tip = (r.tip == 0 and (GREY .. L("Sin propina") .. "|r")) or (r.tip and Coins(r.tip)) or (GREY .. L("A negociar") .. "|r") }
    if T.view == "pub" or searching then
        v.state = v.state .. TimeLeft(r, now)
        v.who = mine and (MINE .. L("Yo") .. "|r " .. DOT_ON) or (OTHERS .. HU:Short(r.who) .. "|r " .. Dot(r.who))
        v.mats = (r.mats == nil or r.sale) and "—" or (r.mats and L("Sí") or L("No"))
        -- (la última columna: Aceptar (o Me interesa, en una venta) si es de otro y está abierta; Cancelar si es mía;
        -- si ya la aceptó alguien, su nombre; vendida, «Vendida»; una venta que ya me interesa, «Te interesa»)
        if r.taker then
            row.actText:SetText(IsMe(r.taker) and (MINE .. L("Yo") .. "|r") or (OTHERS .. HU:Short(r.taker) .. "|r " .. Dot(r.taker))); row.actText:Show()
        elseif r.state == "sold" then
            row.actText:SetText(GREY .. L("Vendida") .. "|r"); row.actText:Show()
        elseif mine then
            row.cancel:Show()
        elseif r.sale and Interested(r) then
            row.actText:SetText("|cff40ff40" .. L("Te interesa") .. "|r"); row.actText:Show()
        elseif r.state == "open" then
            -- (apagado si no puedo hacerla: el porqué, al pasar el ratón. Una venta no se hace: siempre encendido)
            local can, why = true, nil
            if not r.sale then can, why = CraftCheck(r.item, profs) end
            row.accept:SetText(r.sale and L("Me interesa") or L("Aceptar"))
            row.accept:SetEnabled(can); row.accept.why = why
            row.accept:Show()
        end
    else
        -- (la otra persona, con cuántas suyas hay sin leer)
        local other = Other(r)
        v.who = (mine and MINE or OTHERS) .. HU:Short(other) .. "|r " .. Dot(other) .. UnreadMark(other)
        row.glow:SetShown(T.unread[other or ""] ~= nil)
        -- (solo en las abiertas: el tic para aceptarla —si me la piden a mí y puedo hacerla— y la X para
        -- cancelarla —mía, también una venta— o rechazarla; las aceptadas y las ventas de otros, sin nada)
        local ask = r.state == "open" and not mine and not r.sale
        row.yes:SetShown(ask)
        if ask then
            local can, why = CraftCheck(r.item, profs)
            row.yes:SetEnabled(can); row.yes.why = why
        end
        row.no:SetShown(r.state == "open" and (mine or not r.sale))
    end
    for i, col in ipairs(cols) do row.cells[i]:SetText(v[col[1]] or "") end
end

local function Paint()
    local ui = T.ui
    if not (ui and ui:IsShown()) then return end
    -- (comercio apagado por el maestro: solo el panel con el aviso; ni interruptor, ni buscador, ni casilla, ni pedir)
    local off = HU:UnionCfg().tradeOff and true or false
    local find = T.view == "find"
    ui.offMsg:SetShown(off)
    for _, w in ipairs(ui.onlyOn) do w:SetShown(not off) end
    -- (la fila 2: el buscador y la casilla; en Buscar, los filtros)
    for _, w in ipairs(ui.row2) do w:SetShown(not off and not find) end
    ui.filters:SetShown(not off and find)
    if off then ui.newDlg:Hide(); ui.who:Hide(); return end
    Fresh()
    BuildOnline()
    ResetCrafters()
    ui.who.Paint()
    local searching = Searching()
    -- (el chat que queda en pantalla, leído; antes de pintar las filas, que llevan lo de cada uno)
    if ChatOnScreen(T.chatKey) then MarkRead(T.chatKey) end
    PaintUnread()
    for k, b in pairs(ui.viewBtns) do b:SetSelected(k == T.view and not searching) end
    -- (la ayuda del buscador, según la vista: Jorge, 25/11, «search on board» y «search order»)
    if ui.search.Instructions then
        ui.search.Instructions:SetText(T.view == "priv" and L("Buscar encargo") or L("Buscar en el tablón"))
    end
    if find then
        ui.delBtn:Hide(); ui.doneBtn:Hide()
        return T.PaintFind()
    end
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
        ui.found.empty:SetText(L("Nadie de la unión lo hace (profesión u objeto fabricable)."))
        PaintRows(ui.found, SearchMembers(Query()), FillWho)
    end
    ui.req.empty:SetText(searching and L("Ninguna solicitud publicada encaja.")
        or (T.view == "pub" and only and L("En el tablón no hay nada que puedas hacer.")) or L("No hay solicitudes."))
    local nPicks = 0
    for _ in pairs(T.picks) do nPicks = nPicks + 1 end
    ui.delBtn:SetShown(T.view == "priv" and not searching and nPicks > 0)
    ui.delBtn:SetText(string.format(L("Eliminar (%d)"), nPicks))
    local cur = T.selected and FindReq(IdOf(T.selected))
    -- («Hecha», en las que hago yo; ya hecha, apagado. En una venta mía, «Vendida»)
    local sale = cur ~= nil and cur.sale == true and IsMine(cur)
    ui.doneBtn:SetText(sale and L("Vendida") or L("Hecha"))
    ui.doneBtn:SetShown(T.view == "priv" and not searching and cur ~= nil and (sale or IsMe(cur.taker)))
    ui.doneBtn:SetEnabled(sale and CanMarkSold(cur) or CanMarkDone(cur))
    local now = HU.StampNow()
    PaintRows(ui.req, ui.lastList, function(row, r) FillReq(row, r, cols, profs, now, searching) end)
end

---------------------------------------------------------------------------
-- Montar la sección (UnionRoster.lua la pone en la pestaña Trade con HU:BuildTrade, Trade.lua). Lo de Buscar (la fila de
-- los filtros, los clics de sus filas y la ventana «Quién lo hace»), en TradeFind.lua
---------------------------------------------------------------------------
-- (Aceptar o el tic, apagados: por qué no puedo hacerla, en rojo; Paint deja el porqué en `why`)
local function WhyTip(s)
    if not s.why then return end
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:SetText(s.why, 1, 0.35, 0.35)
    GameTooltip:Show()
end

-- Clic derecho en una fila: la otra persona (susurrar, invitar al grupo); en Mis encargos, marcarla como hecha (si la
-- hago yo y está aceptada) y eliminarla; una venta mía, marcarla vendida; en la búsqueda, pedirle una receta (en Buscar,
-- el objeto elegido); y Cancelar (cierra el menú)
local function RowMenu(owner, r)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local person
    if not r.id then person = r.name
    elseif T.view == "priv" and not Searching() then person = Other(r)
    elseif IsMine(r) then person = r.taker
    else person = r.who end
    local priv = r.id and T.view == "priv" and not Searching()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        if person then
            root:CreateTitle(HU:Short(person))
            root:CreateButton(L("Susurrar"), function() HU.WhisperTo(person) end)
            root:CreateButton(L("Invitar al grupo"), function()
                local fn = C_PartyInfo and C_PartyInfo.InviteUnit
                if fn then pcall(fn, HU:FullName(person) or person) end
            end)
            if not r.id then root:CreateButton(L("Hacer un encargo"), function() T.ui.OpenNew(person, T.view == "find" and T.FindLink() or nil) end) end
        end
        if priv and CanMarkDone(r) then
            root:CreateButton(L("Marcar como hecha"), function() MarkDone(r) end)
        end
        if r.id and CanMarkSold(r) then
            root:CreateButton(L("Marcar como vendida"), function() MarkSold(r) end)
        end
        if priv then
            local n = 0
            for _ in pairs(T.picks) do n = n + 1 end
            if n > 0 then
                root:CreateButton(string.format(L("Eliminar (%d)"), n), RemovePicked)
            else
                root:CreateButton(L("Eliminar"), function() RemoveReq(r); T.selected = nil; Paint() end)
            end
        end
        root:CreateButton(L("Cancelar"), function() end)
    end)
end

-- (una fila de lista, la `i` de `sf`: sus casillas, el botón del enlace, lo de la última columna del Tablón, el tic y la X
-- de Mis encargos, y su clic)
local function MakeRow(list, sf, i)
    local ui = T.ui
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("RIGHT", sf, "RIGHT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.pickTex = row:CreateTexture(nil, "BORDER")
    row.pickTex:SetAllPoints(); row.pickTex:SetColorTexture(0.25, 0.55, 1, 0.28); row.pickTex:Hide()
    -- (una venta: un fondo suave de su color)
    row.saleTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.saleTex:SetAllPoints(); row.saleTex:SetColorTexture(SALE_RGB[1], SALE_RGB[2], SALE_RGB[3], 0.10); row.saleTex:Hide()
    -- (un chat con algo sin leer, en Mis encargos: un brillo verde que late)
    row.glow = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.glow:SetAllPoints(); row.glow:SetColorTexture(0.25, 1, 0.35, 0.18); row.glow:Hide()
    local beat = row.glow:CreateAnimationGroup()
    local fade = beat:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.35); fade:SetToAlpha(1); fade:SetDuration(0.8)
    beat:SetLooping("BOUNCE"); beat:Play()
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
        if T.view == "priv" and not Searching() then return end
        local link = row.entry and row.entry.item
        local h = link and link:match("|H(.-)|h")
        if h then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); pcall(GameTooltip.SetHyperlink, GameTooltip, h); GameTooltip:Show() end
    end)
    itemBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.itemBtn = itemBtn
    -- (Tablón, última columna: Aceptar / Me interesa / Cancelar, o el nombre de quien la aceptó. Aceptar, apagado si
    -- no puedo hacerla, con el porqué al pasar el ratón)
    local accept = DJ.Button(row, L("Aceptar"), ACT_W, 20)
    accept:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    accept:SetScript("OnClick", function() if row.entry then Accept(row.entry) end end)
    accept:SetMotionScriptsWhileDisabled(true)
    accept:SetScript("OnEnter", WhyTip); accept:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local actText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    actText:SetPoint("RIGHT", row, "RIGHT", -2, 0); actText:SetWidth(ACT_W); actText:SetJustifyH("CENTER")
    local cancel = DJ.Button(row, L("Cancelar"), ACT_W, 20)
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
        local key = EntryKey(r)
        -- (en Mis encargos: Ctrl suma o quita; Mayús elige desde la última hasta esta; clic solo, solo esa)
        if T.view == "priv" and not Searching() then
            if IsControlKeyDown() then
                -- (la elegida con un clic solo también cuenta: si no, quedaba fuera de las marcadas)
                if T.selected and T.selected ~= key and next(T.picks) == nil then
                    for _, x in ipairs(ui.lastList or {}) do if EntryKey(x) == T.selected then T.picks[T.selected] = true end end
                end
                T.picks[key] = (not T.picks[key]) or nil
            elseif IsShiftKeyDown() and lastPick then
                local a, b
                for k, x in ipairs(ui.lastList or {}) do
                    if EntryKey(x) == lastPick then a = k end
                    if EntryKey(x) == key then b = k end
                end
                if a and b then
                    if a > b then a, b = b, a end
                    for k = a, b do T.picks[EntryKey(ui.lastList[k])] = true end
                end
            else
                T.picks = {}
            end
            lastPick = key
        end
        T.selected = key
        if T.view == "priv" and not Searching() then
            OpenChat(Other(r))
        end
        Paint()
    end)
    return row
end

-- Las listas: las solicitudes y, al buscar, debajo, quién lo hace; en Buscar, los objetos (y quién lo hace uno, en su
-- ventana: `parent`, TradeFind.lua)
local function MakeList(n, sortable, sfName, parent)
    local lst = { n = n, rows = {}, hdrCells = {}, sortable = sortable }
    local list = CreateFrame("Frame", nil, parent or T.ui.body)
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
            T.ui.rerank = true
            Paint()
        end)
        lst.hdrCells[i] = b
    end
    local sf = CreateFrame("ScrollFrame", sfName, list, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -2); sf:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    sf:SetHeight(n * ROW_H)
    sf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, Paint) end)
    lst.scroll = sf
    for i = 1, n do lst.rows[i] = MakeRow(list, sf, i) end
    lst.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    lst.empty:SetPoint("TOP", sf, "TOP", 0, -24); lst.empty:SetWidth(380)
    return lst
end

-- (un buscador del juego: su ayuda en gris claro, detrás un marco oscuro de borde dorado y, con un objeto escrito, al
-- pasar el ratón, su ficha (HyperTip), a su derecha. Lo coloca quien lo pide: el del Tablón y el de Buscar)
local function SearchBox(name, parent, w, hint)
    local search = CreateFrame("EditBox", name, parent, "SearchBoxTemplate")
    search:SetSize(w, 22)
    if search.Instructions then
        search.Instructions:SetText(hint); DJ.C(search.Instructions, DJ.T.muted)
    end
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetPoint("TOPLEFT", search, "TOPLEFT", -9, 3); box:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", 3, -3)
    DJ.Panel(box, DJ.T.row, { DJ.T.line[1], DJ.T.line[2], DJ.T.line[3], 0.55 }, 10, 2)
    box:SetFrameLevel(search:GetFrameLevel())
    search:SetFrameLevel(box:GetFrameLevel() + 2)
    search:HookScript("OnEnter", function(s) HyperTip(s, s.link or s:GetText()) end)
    search:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return search, box
end

-- Derecha (solo en Mis encargos): el chat de la persona del comercio que eliges, de arriba abajo: desde debajo del
-- buscador hasta el borde de abajo de la sección (Jorge, 24/11)
local function BuildChat(host, body)
    local ui = host
    local chat = CreateFrame("Frame", nil, body, "BackdropTemplate")
    chat:SetPoint("TOPRIGHT", body, "TOPRIGHT", -SIZES.edge, 0); chat:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -SIZES.edge, 8)
    chat:SetWidth(CHAT_W)
    DJ.Panel(chat, DJ.T.panel, DJ.T.border, 12, 3)
    DJ.Parchment(chat, 0.13)
    ui.chat = chat
    ui.chatTitle = chat:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.chatTitle:SetPoint("TOPLEFT", 8, -7); ui.chatTitle:SetPoint("RIGHT", chat, "RIGHT", -8, 0)
    ui.chatTitle:SetJustifyH("LEFT"); ui.chatTitle:SetWordWrap(false)
    -- («Hecha» en lo que hago yo; «Vendida» en una venta mía)
    local done = DJ.Button(chat, L("Hecha"), 64, 18)
    done:SetPoint("TOPRIGHT", -5, -4)
    done:SetScript("OnClick", function()
        local r = T.selected and FindReq(IdOf(T.selected))
        if r and r.sale then MarkSold(r) else MarkDone(r) end
    end)
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
        -- (a la otra persona por susurro; a un desconectado, cuando se conecte. A las de prueba, no)
        if text ~= "" and T.chatKey then
            ChatLine(T.chatKey, Me(), text)
            if not T.chatKey:find("%-Prueba$") then SendChat(T.chatKey, text) end
        end
        s:SetText(""); s:ClearFocus()
    end)
    ui.chatInput = input
    ui.chatHint = chat:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.chatHint:SetPoint("LEFT", input, "LEFT", 2, 0); ui.chatHint:SetText(L("Elige un comercio con alguien para escribir"))
end

local function Build(host)
    T.ui = host
    local ui = host
    -- Arriba, los botones rojos Tablón · Mis encargos · Buscar, juntos en el centro; debajo, el buscador a la izquierda y
    -- «Solo lo que puedo hacer» a la derecha (en Buscar, los filtros); abajo, «+ Nuevo anuncio» (Jorge, 24/11: el sitio
    -- de la «opción 3», con los botones y el buscador y la casilla de antes) [+ARCHITECTURE.md]
    local sw = DJ.Switch(host, { { "pub", L("Tablón") }, { "priv", L("Mis encargos") }, { "find", L("Buscar") } })
    sw:SetPoint("TOP", host, "TOP", 0, -4)
    ui.switch = sw
    ui.viewBtns = sw.btns
    for k, b in pairs(sw.btns) do
        b:SetScript("OnClick", function()
            T.view, T.selected, T.picks = k, nil, {}
            ui.rerank = true
            ui.search:SetText("")
            FauxScrollFrame_SetOffset(ui.req.scroll, 0)
            Paint()
        end)
    end
    -- (el buscador, como antes: el del juego, centrado en la fila)
    local search, sbox = SearchBox("GuildUnionTradeSearch", host, SEARCH_W, L("Buscar en el tablón"))
    search:SetPoint("TOPLEFT", host, "TOPLEFT", 23, ROW2_Y - (ROW2_H - 22) / 2)
    ui.searchBox = sbox
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
    -- (en Buscar, en la misma fila, los filtros: TradeFind.lua)
    ui.filters = T.BuildFilters(host)
    ui.filters.WatchLink(search)
    -- (Mayús+clic en un objeto con uno de los dos buscadores escribiendo: entra su enlace, que se ve por su nombre)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", function(text)
            if type(text) ~= "string" then return end
            for _, box in ipairs({ search, ui.filters.search }) do
                if box:HasFocus() then box:SetText(text) end
            end
        end)
    end

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

    BuildChat(host, body)

    ui.req = MakeList(ROWS, true, "GuildUnionTradeScroll")
    ui.found = MakeList(ROWS, false, "GuildUnionTradeScroll2")
    -- (Buscar: los objetos, con su enlace en la primera columna; sus clics y «Ver todos», en TradeFind.lua)
    ui.items = MakeList(ROWS, false, "GuildUnionTradeScroll3")
    ui.items.itemCol = 1
    for _, row in ipairs(ui.items.rows) do
        row.itemBtn:ClearAllPoints(); row.itemBtn:SetPoint("CENTER", row.cells[1], "CENTER")
    end
    ui.items.list:Hide()
    T.BuildWho(host)

    -- Abajo: «+ Nuevo anuncio», como hasta la copia 304 (teñido de verde, letra blanca), centrado debajo de la lista
    -- (Layout); va en el panel, para quedar encima de él. Su ventana (y ui.OpenNew), TradeOrder.lua [+ARCHITECTURE.md]
    local newDlg = BuildNewDialog(host)
    local new = DJ.Button(bg, "+ " .. L("Nuevo encargo"), 200, 24)
    new:SetPoint("BOTTOM", host, "BOTTOM", 0, 8)
    for _, k in ipairs({ "Left", "Middle", "Right" }) do if new[k] then new[k]:SetVertexColor(0.45, 1, 0.45) end end
    new:SetNormalFontObject("GameFontHighlight")
    new:SetScript("OnClick", function() ui.OpenNew(nil, T.view == "find" and T.FindLink() or nil) end)
    ui.new, ui.newDlg = new, newDlg
    -- (a su derecha, «Eliminar (N)», con algo marcado en Mis encargos: cabe antes del chat)
    local del = DJ.Button(body, "", 80, 22)
    del:SetPoint("LEFT", new, "RIGHT", 6, 0)
    del:SetScript("OnClick", RemovePicked)
    del:Hide()
    ui.delBtn = del
    -- (lo que solo se ve con el comercio encendido: apagado, queda el panel con el aviso. La fila 2 va aparte: en Buscar
    -- lleva los filtros)
    ui.onlyOn = { body, sw, new }
    ui.row2 = { search, sbox, only }

    Suggest(ui.search, ItemMatches)
    -- (al abrirla: las solicitudes otra vez y lo que falte de toda la unión)
    host:HookScript("OnShow", function() LoadCraftNames(); T.netDirty = true; ui.rerank = true; NeedAll(); Paint() end)
    LoadCraftNames()
    OpenChat(nil)
    Paint()
end

T.Paint, T.Titled, T.Columns, T.PaintRows, T.FillWho, T.MakeList, T.SearchBox, T.Build = Paint, Titled, Columns, PaintRows, FillWho, MakeList, SearchBox, Build
T.ROW_H, T.ROWS, T.ROW2_Y, T.ROW2_H, T.SIZES, T.COLS = ROW_H, ROWS, ROW2_Y, ROW2_H, SIZES, COLS

HU:Module("TradeView", { "BlizzTab", "Config", "Core", "ListWindow", "UnionConfig" })
