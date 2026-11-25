-- Guild Union - Comercio: la ventana de nuevo encargo (pedir o vender un BOE, el objeto, quién pone los materiales, la
-- propina y para quién) y su autorrelleno. Comparte lo suyo por HU.TradeInternal (Trade.lua) [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L
local DJ = HU.DJ

local T = HU.TradeInternal
local Me, IsMine, NewId, Plain, Expired, Fresh = T.Me, T.IsMine, T.NewId, T.Plain, T.Expired, T.Fresh
local COIN_ICON, GOLD = T.COIN_ICON, T.GOLD
local ItemInfo, BoeOf, craft = T.ItemInfo, T.BoeOf, T.craft

local MAX_OPEN = 5          -- anuncios abiertos por persona
-- (lo que dura un anuncio del tablón, a elegir al ponerlo: Jorge, 25/11, «desde 5h-12h-24-48h»)
local EXPIRY_HOURS, EXPIRY_DEFAULT = { 5, 12, 24, 48 }, 24
local ITEM_WAIT = 5         -- lo que se espera a que el juego conozca un objeto para decidir si es BOE

---------------------------------------------------------------------------
-- Nuevo anuncio: pedir o vender (un BOE solo se vende, y solo se venden BOE), el objeto (con autorrelleno), quién pone
-- los materiales, propina o precio en oro · plata · cobre, si va al tablón (con cuánto dura) o para alguien (con
-- autorrelleno del nombre) [+ARCHITECTURE.md]
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
    local exact = ItemInfo(text)
    if exact then add(exact.link) end
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local slotLink = C_Container and C_Container.GetContainerItemLink
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local okN, n = pcall(numSlots, bag)
        for slot = 1, (okN and type(n) == "number") and n or 0 do
            local okL, l = pcall(slotLink, bag, slot)
            if okL then add(l) end
        end
    end
    for _, r in ipairs(T.reqs) do add(r.item) end
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
    -- (y las listas completas de las otras hermandades (MB), también los desconectados: Jorge, 25/11, «el nombre del
    -- private con auto relleno»)
    for _, tag in ipairs(HU:OtherTags()) do
        for _, m in ipairs(HU:PackedMembers(tag)) do add(m.name, tag) end
    end
    return out
end

-- (los míos sin terminar, para el tope: abiertos o aceptados; los quitados de mi lista y los caducados ya no cuentan)
local function OpenCount()
    local n, now = 0, HU.StampNow()
    for _, r in ipairs(T.reqs) do
        if IsMine(r) and not r.closed and (r.state == "open" or r.state == "taken") and not Expired(r, now) then n = n + 1 end
    end
    return n
end

-- (lo que espera a que el juego conozca el objeto para decidir si es BOE: { id }; se publica al llegar)
local pendingSubmit

-- (la ventana, hija de la sección; también pone `host.OpenNew`, la que la abre)
local function BuildNewDialog(host)
    local d = CreateFrame("Frame", "GuildUnionTradeNew", host, "BackdropTemplate")
    d:SetSize(310, 290)
    -- (atada por arriba: al cambiar de alto, lo de arriba no se mueve. Centrada, bajaba al encoger y el clic siguiente
    -- caía en la fila de encima: Jorge, 25/11, «cuando pulso no tip no tengo manera de volver a ponerle un tip») [+ARCHITECTURE.md]
    d:SetPoint("TOP", host, "CENTER", 0, 160)
    d:SetFrameStrata("DIALOG")
    DJ.Panel(d, DJ.T.content, DJ.T.border, 14, 4)
    DJ.Parchment(d, 0.18)
    d:EnableMouse(true)
    -- (se mueve arrastrándola, sin salirse de la pantalla: Jorge, 25/11, «la ventana del request order debe ser movible».
    -- Al soltarla, otra vez atada por arriba, donde quedó)
    d:SetMovable(true); d:SetClampedToScreen(true); d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local left, top = s:GetLeft(), s:GetTop()
        if left and top then s:ClearAllPoints(); s:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) end
    end)
    d:Hide()
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.title:SetPoint("TOPLEFT", 12, -10)
    -- (la X de arriba a la derecha la cierra, como «Cancelar»: Jorge, 25/11)
    d.close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    d.close:SetPoint("TOPRIGHT", -2, -2)
    d.close:SetScript("OnClick", function() d:Hide() end)
    local function Label(text, font)
        local l = d:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
        l:SetText(text)
        return l
    end
    local function Check(text)
        local c = CreateFrame("CheckButton", nil, d, "UICheckButtonTemplate")
        c:SetSize(20, 20)
        if c.Text then c.Text:SetFontObject("GameFontHighlightSmall"); c.Text:SetText(text) end
        return c
    end
    -- (casillas que se excluyen: marcar una desmarca las demás)
    local function Group(list, onChange)
        for _, c in ipairs(list) do
            c:SetScript("OnClick", function()
                for _, o in ipairs(list) do o:SetChecked(o == c) end
                if onChange then onChange() end
            end)
        end
    end

    d.kindLabel = Label(L("Anuncio:"))
    d.kindAsk, d.kindSell = Check(L("Encargo")), Check(L("Vender"))
    d.itemLabel = Label(L("Objeto o encantamiento (o Mayús+clic):"))
    d.item = HU.NewEditBox(d, 222)
    d.qtyLabel = Label(L("Cantidad:"))
    d.qty = HU.NewEditBox(d, 42); d.qty:SetNumeric(true); d.qty:SetMaxLetters(3)
    d.qty:SetJustifyH("CENTER")
    Suggest(d.item, ItemMatches)

    d.matsLabel = Label(L("Materiales:"))
    d.matsMe, d.matsSeller = Check(L("Yo")), Check(L("Vendedor"))
    Group({ d.matsMe, d.matsSeller })

    -- (la propina (o el precio, al vender): se esconde si el maestro no permite propinas, UnionConfig.lua. «Sin propina»
    -- o «A negociar» esconden las monedas (Jorge, 25/11); al vender, solo «A negociar». Sin marcar nada y sin monedas,
    -- a negociar, como antes)
    d.tipLabel = Label(L("Propina:"))
    d.noTip, d.nego = Check(L("Sin propina")), Check(L("A negociar"))
    d.coins, d.coinIcons = {}, {}
    for i, icon in ipairs(COIN_ICON) do
        local box = HU.NewEditBox(d, 56); box:SetNumeric(true)
        box:SetMaxLetters(i == 1 and 6 or 2); box:SetJustifyH("CENTER")
        local tex = d:CreateTexture(nil, "ARTWORK")
        tex:SetSize(14, 14); tex:SetTexture(icon); tex:SetPoint("BOTTOM", box, "TOP", -3, 2)
        d.coins[i], d.coinIcons[i] = box, tex
    end

    -- (un encargo personal, para alguien en concreto: con la casilla, a quién, con autorrelleno; sin ella, al tablón.
    -- Hasta el 25/11, «En el tablón: Sí · No»)
    d.personal = Check(L("Encargo personal"))
    d.sep = DJ.Line(d, 0.35)
    d.toLabel = Label(L("Personaje:"))
    d.to = HU.NewEditBox(d, 196)
    Suggest(d.to, NameMatches)
    -- (cuánto dura en el tablón: 5, 12, 24 (de entrada) o 48 h; las personales no caducan, como hasta ahora)
    d.expLabel = Label(L("Duración:"))
    d.expChecks = {}
    for i, h in ipairs(EXPIRY_HOURS) do
        local c = Check(h .. " h")
        c.hours = h
        d.expChecks[i] = c
    end
    Group(d.expChecks)

    -- Coloca las filas que tocan, de arriba abajo: al vender no hay materiales ni «Encargo personal» (una venta va siempre
    -- al tablón) y la propina es el precio; en el tablón, cuánto dura; si no, a quién
    function d.Relayout()
        local sale = d.kindSell:GetChecked() and true or false
        local pub = sale or not d.personal:GetChecked()
        local tips = not HU:UnionCfg().tipsOff
        local y = -34
        local function At(w, x, dy)
            w:ClearAllPoints(); w:SetPoint("TOPLEFT", x, y + (dy or 0)); w:Show()
        end
        At(d.kindLabel, 12); At(d.kindAsk, 96, 5); At(d.kindSell, 170, 5)
        y = y - 26
        At(d.itemLabel, 12); At(d.qtyLabel, 248); At(d.item, 18, -14); At(d.qty, 254, -14)
        y = y - 46
        for _, w in ipairs({ d.matsLabel, d.matsMe, d.matsSeller, d.personal }) do w:SetShown(not sale) end
        if not sale then
            At(d.matsLabel, 12); At(d.matsMe, 96, 5); At(d.matsSeller, 170, 5)
            y = y - 26
        end
        d.tipLabel:SetText(sale and L("Precio:") or L("Propina:"))
        local coins = tips and not ((d.noTip:GetChecked() and not sale) or d.nego:GetChecked())
        for _, w in ipairs({ d.tipLabel, d.noTip, d.nego }) do w:SetShown(tips) end
        for i, box in ipairs(d.coins) do box:SetShown(coins); d.coinIcons[i]:SetShown(coins) end
        if tips then
            At(d.tipLabel, 12)
            if sale then d.noTip:Hide(); At(d.nego, 96, 5) else At(d.noTip, 96, 5); At(d.nego, 190, 5) end
            y = y - 22
            if coins then
                for i, box in ipairs(d.coins) do At(box, 18 + (i - 1) * 74, -14) end
                y = y - 44
            end
        end
        -- («Encargo personal», algo más abajo y con una raya encima: que no parezca de la propina. Jorge, 25/11)
        d.sep:SetShown(not sale)
        if not sale then
            y = y - 6
            d.sep:ClearAllPoints(); d.sep:SetPoint("TOPLEFT", 12, y + 2); d.sep:SetPoint("TOPRIGHT", -12, y + 2)
            y = y - 6
            At(d.personal, 10, 5)
            y = y - 26
        end
        d.toLabel:SetShown(not pub); d.to:SetShown(not pub); d.expLabel:SetShown(pub)
        for _, c in ipairs(d.expChecks) do c:SetShown(pub) end
        if pub then
            At(d.expLabel, 12)
            for i, c in ipairs(d.expChecks) do At(c, 86 + (i - 1) * 54, 5) end
        else
            At(d.toLabel, 12); At(d.to, 102, 4)
        end
        y = y - 28
        d:SetHeight(-y + 38)
    end
    function d.SetPub(pub)
        d.personal:SetChecked(not pub)
        d.Relayout()
    end
    function d.SetExpiry(hours)
        for _, c in ipairs(d.expChecks) do c:SetChecked(c.hours == hours) end
    end
    local function Hours()
        for _, c in ipairs(d.expChecks) do if c:GetChecked() then return c.hours end end
        return EXPIRY_DEFAULT
    end
    Group({ d.kindAsk, d.kindSell }, d.Relayout)
    d.personal:SetScript("OnClick", function()
        d.Relayout()
        if d.to:IsShown() then d.to:SetFocus() end
    end)
    -- («Sin propina» y «A negociar» se excluyen; sin ninguna, las monedas)
    for _, c in ipairs({ d.noTip, d.nego }) do
        c:SetScript("OnClick", function(s)
            if s:GetChecked() then (s == d.noTip and d.nego or d.noTip):SetChecked(false) end
            d.Relayout()
        end)
    end

    -- Publicar. Un BOE solo se vende y solo se venden BOE: si el juego aún no conoce el objeto, se le pide y se decide al
    -- llegar (final: ya no se espera más; lo que sigue sin saberse, al pedir vale y al vender no) [+ARCHITECTURE.md]
    function d.Submit(final)
        -- (con el comercio apagado no se pide nada, aunque la ventana se hubiera quedado abierta de antes)
        if HU:UnionCfg().tradeOff then
            d:Hide()
            return HU:Print(L("El maestro de la hermandad ha desactivado el comercio (pestaña GuildUnion, Configuración → Comercio)."))
        end
        local item = HU.Trim(d.item:GetText() or "")
        if item == "" then return HU:Print(L("Pon el objeto que pides (Mayús+clic en él).")) end
        Fresh()
        if OpenCount() >= MAX_OPEN then return HU:Print(string.format(L("Ya tienes %d solicitudes abiertas: cierra alguna antes."), MAX_OPEN)) end
        local sale = d.kindSell:GetChecked() and true or false
        local pub = sale or not d.personal:GetChecked()
        local to = HU.Trim(d.to:GetText() or "")
        if not pub and to == "" then return HU:Print(L("Para un encargo personal, pon para quién es.")) end
        -- (solo se venden BOE: si el juego aún no conoce el objeto, se le pide y se decide al llegar. Un encargo vale de
        -- cualquier objeto, también de un BOE: Jorge, 25/11, «que los BOE también sea posible crear un order»)
        if sale then
            local boe, id = BoeOf(item)
            if boe == nil and not final then
                local p = { id = id }
                pendingSubmit = p
                HU.After(ITEM_WAIT, function()
                    if pendingSubmit ~= p then return end
                    pendingSubmit = nil
                    if d:IsShown() then d.Submit(true) end
                end)
                return HU:Print(L("Comprobando el objeto con el juego…"))
            end
            if boe == nil then return HU:Print(L("No se ha podido comprobar el objeto: prueba otra vez.")) end
            if not boe then return HU:Print(L("Solo se venden objetos BOE: los que se ligan al equipar, de verde a legendario.")) end
        end
        -- (la propina o el precio, en cobre: «Sin propina», 0; «A negociar» o las tres cajas vacías, sin nada)
        local tip, any = 0, false
        if not ((d.noTip:GetChecked() and not sale) or d.nego:GetChecked()) then
            for i, box in ipairs(d.coins) do
                local v = tonumber(box:GetText() or "")
                if v then any = true; tip = tip + v * (i == 1 and 10000 or i == 2 and 100 or 1) end
            end
        elseif d.noTip:GetChecked() and not sale then
            any = true
        end
        local mats
        if d.matsMe:GetChecked() then mats = true elseif d.matsSeller:GetChecked() then mats = false end
        -- (a toda la unión, con el conjunto TR: queda ya en lo mío y sale por mi hermandad; sin la unión, no se puede)
        local r = { id = NewId(), who = Me(), item = item, sale = sale or nil, mats = (not sale) and mats or nil,
            tip = (any and not (HU:UnionCfg().tipsOff)) and tip or nil, qty = math.max(1, tonumber(d.qty:GetText() or "") or 1),
            state = "open", pub = pub, to = (not pub) and (HU:FullName(to) or to) or nil,
            exp = pub and (HU.StampNow() + Hours() * 3600) or nil }
        if not HU:TradeOrder(r) then return HU:Print(L("No se ha podido pedir: tu hermandad todavía no está en la unión.")) end
        d:Hide()
        T.view = pub and "pub" or "priv"
        T.ui.rerank = true
        T.ui.search:SetText("")
        T.Paint()
    end
    local ok = DJ.Button(d, L("Publicar"), 110, 22); ok:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 12)
    local no = DJ.Button(d, L("Cancelar"), 110, 22); no:SetPoint("BOTTOMLEFT", d, "BOTTOM", 6, 12)
    no:SetScript("OnClick", function() d:Hide() end)
    ok:SetScript("OnClick", function() pendingSubmit = nil; d.Submit(false) end)
    -- (Mayús+clic en un objeto con esta caja escribiendo: entra su enlace)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", function(text)
            if d:IsShown() and d.item:HasFocus() and type(text) == "string" then d.item:SetText(text) end
        end)
    end
    -- (to: pedírsela a alguien en concreto, privada: «Pedir una receta» desde la búsqueda; item: lo que se pide (en
    -- Buscar, el objeto elegido). Con el comercio apagado no se abre)
    function host.OpenNew(to, item)
        if HU:UnionCfg().tradeOff then return end
        pendingSubmit = nil
        d.title:SetText(to and (L("Encargo para ") .. HU:Short(to)) or L("Nuevo encargo"))
        d.item:SetText(item or ""); d.to:SetText(to or ""); d.qty:SetText("1")
        for _, box in ipairs(d.coins) do box:SetText("") end
        d.noTip:SetChecked(false); d.nego:SetChecked(false)
        d.matsMe:SetChecked(true); d.matsSeller:SetChecked(false)
        d.kindAsk:SetChecked(true); d.kindSell:SetChecked(false)
        d.SetExpiry(EXPIRY_DEFAULT)
        d.SetPub(not to and T.view ~= "priv")
        d:Show(); d.item:SetFocus()
    end
    return d
end
-- (el juego ya conoce el objeto que esperaba un anuncio: se decide ahora)
local function ItemArrived(itemID)
    local p = pendingSubmit
    if not (p and itemID == p.id) then return end
    pendingSubmit = nil
    if T.ui and T.ui.newDlg:IsShown() then T.ui.newDlg.Submit(true) end
end
HU:On("ITEM_DATA_LOAD_RESULT", ItemArrived)
HU:On("GET_ITEM_INFO_RECEIVED", ItemArrived)

T.HyperTip, T.Suggest, T.ItemMatches, T.BuildNewDialog = HyperTip, Suggest, ItemMatches, BuildNewDialog

HU:Module("TradeOrder", { "Config", "Core", "ListWindow", "Packs/Members", "Packs/Trade", "UnionConfig" })
