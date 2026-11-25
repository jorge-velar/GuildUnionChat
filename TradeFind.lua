-- Guild Union - Comercio: la pestaña Buscar (view = "find"): los fabricables que encajan con sus filtros y su buscador, su
-- lista y la ventana «Quién lo hace». Comparte lo suyo por HU.TradeInternal (Trade.lua) [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L
local DJ = HU.DJ

local T = HU.TradeInternal
local IsMe, Plain = T.IsMe, T.Plain
local craft, CraftIndex, CraftersOf, ProfLabel, PROF_NAMES = T.craft, T.CraftIndex, T.CraftersOf, T.ProfLabel, T.PROF_NAMES
local Paint, PaintRows, Titled, Columns, FillWho, MakeList, SearchBox = T.Paint, T.PaintRows, T.Titled, T.Columns, T.FillWho, T.MakeList, T.SearchBox
local ROW_H, ROWS, ROW2_Y, ROW2_H, SIZES, COLS = T.ROW_H, T.ROWS, T.ROW2_Y, T.ROW2_H, T.SIZES, T.COLS

-- (los filtros: la rareza (la calidad del juego, con los nombres de Blizzard; sin legendario, que no se fabrica: Jorge,
-- 25/11, «quita el orange») y tipos (las clases del juego, Enum.ItemClass); varios a la vez)
local QUALITIES = { { 1, "Común", "ffffff" }, { 2, "Poco común", "1eff00" }, { 3, "Raro", "0070dd" }, { 4, "Épico", "a335ee" } }
local TYPES = { { "cons", "Consumible", { 0 } }, { "trade", "Mercancías", { 7 } }, { "cont", "Contenedores", { 1, 11 } },
    { "armor", "Armadura", { 4 } }, { "weapon", "Armas", { 2 } }, { "ammo", "Munición", { 6 } },
    { "misc", "Misceláneo", { 15 } } }

---------------------------------------------------------------------------
-- Buscar (la pestaña): los fabricables que encajan con los filtros (profesión, nivel requerido, rareza y tipo; de
-- varios, cualquiera) y con su buscador (nombre o enlace) y, de cada uno, quién de la unión lo hace, conectados primero.
-- La lista, solo al cambiar un filtro o al llegar objetos; quién lo hace, solo de las filas que se ven y de la ventana
-- de «Ver todos» [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local findProf, findQual, findType = {}, {}, {}   -- [profesión] / [calidad] / [tipo] = true
local findMin, findMax                             -- nivel requerido (el que pide el objeto para usarlo), de… a…
local findList                                     -- lo que encaja: { key, item, rl, il, skill, lv, name }
local findSel                                      -- el elegido (su clave)
local function FindItems(idx)
    if findList and not T.findDirty then return findList end
    T.findDirty = false
    local classes = {}
    for _, t in ipairs(TYPES) do if findType[t[1]] then for _, c in ipairs(t[3]) do classes[c] = true end end end
    local anyP, anyQ, anyT = next(findProf) ~= nil, next(findQual) ~= nil, next(findType) ~= nil
    -- (un encantamiento no es un objeto: no tiene rareza, tipo ni nivel; con uno de esos filtros, fuera)
    local itemOnly = anyQ or anyT or findMin ~= nil or findMax ~= nil
    -- (su buscador: un enlace (Mayús+clic) es ese fabricable y nada más (`only`, su clave); un texto, los que lo llevan
    -- en el nombre (`q`), como el buscador del Tablón (HU.TextRank))
    local box = T.ui.filters.search
    local text = box.link or box:GetText() or ""
    local q, only = nil, tonumber(text:match("|Hitem:(%d+)") or "")
    local sp = text:match("|Hspell:(%d+)") or text:match("|Henchant:(%d+)")
    if sp then only = "s" .. sp end
    if not only then
        q = HU.Trim((Plain(text):gsub("^%s*%[", ""):gsub("%]%s*$", "")))
        if q == "" then q = nil end
    end
    local out = {}
    for k, c in pairs(craft) do
        local spell = type(k) ~= "number"
        local skill, lv
        for _, t in ipairs(idx[k] or {}) do
            if (not anyP or findProf[t.skill]) and (lv == nil or t.lv < lv) then skill, lv = t.skill, t.lv end
        end
        local ok = skill ~= nil and not (spell and itemOnly) and (only == nil or k == only)
            and (q == nil or HU.TextRank(c.key, q) ~= nil)
        -- (sin nivel requerido, 0: vale con cualquier «hasta»)
        if ok and not spell then
            ok = (not anyQ or findQual[c.q] == true) and (not anyT or classes[c.cls] == true)
                and (not findMin or (c.rl or -1) >= findMin) and (not findMax or (c.rl or math.huge) <= findMax)
        end
        if ok then
            out[#out + 1] = { key = k, item = c.link, rl = (not spell) and c.rl or nil, il = (not spell) and c.il or nil,
                skill = skill, lv = lv, name = c.key }
        end
    end
    -- (de más nivel requerido a menos; sin él, detrás; luego por nivel de objeto, por el que pide la profesión y por
    -- nombre)
    table.sort(out, function(a, b)
        local ra, rb = a.rl or -1, b.rl or -1
        if ra ~= rb then return ra > rb end
        local ia, ib = a.il or -1, b.il or -1
        if ia ~= ib then return ia > ib end
        if a.lv ~= b.lv then return a.lv > b.lv end
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.key) < tostring(b.key)
    end)
    findList = out
    return out
end
-- (el enlace del objeto elegido en Buscar, para pedirlo)
local function FindLink() return findSel and craft[findSel] and craft[findSel].link or nil end

-- (Buscar: los objetos que encajan, en toda la altura; en sus dos últimas columnas, «Ver todos» (quién lo hace, en su
-- ventana) y «Publicarlo» (al tablón). Hasta el 25/11 iba debajo una lista de quién lo hace el elegido: Jorge, «la
-- quitas»)
local function LayoutFind()
    local ui = T.ui
    local items = ui.items
    ui.chat:Hide(); ui.req.list:Hide(); ui.found.list:Hide()
    items.list:ClearAllPoints()
    items.list:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 6, 0); items.list:SetPoint("RIGHT", ui.body, "RIGHT", -SIZES.listR, 0)
    items.n = ROWS
    Titled(items, nil)
    items.list:Show()
    Columns(items, COLS.find, 4)
    ui.new:ClearAllPoints()
    ui.new:SetPoint("BOTTOM", ui, "BOTTOM", 0, 8)
    ui.new:Show()
end

-- Buscar: los objetos que encajan, con «Ver todos» y «Publicarlo» en cada fila. Quién lo hace ya no se mira al pintar
-- (era lo que trababa la lista al bajar: Jorge, 25/11); lo calcula la ventana de «Ver todos». Mientras el juego da
-- los nombres, las flechas de «cargando» arriba a la derecha [+ARCHITECTURE.md]
local function PaintFind()
    local ui = T.ui
    local items = FindItems(CraftIndex())
    local still = false
    for _, e in ipairs(items) do if e.key == findSel then still = true; break end end
    if not still then findSel = nil end
    LayoutFind()
    ui.items.spin:SetShown(T.craftLoader ~= nil and not T.craftLoader.done)
    ui.items.empty:SetText(next(craft) and L("Ningún objeto fabricable encaja con los filtros.") or L("Cargando los objetos del juego…"))
    PaintRows(ui.items, items, function(row, e)
        local c = row.cells
        row.pickTex:SetShown(e.key == findSel)
        c[1]:SetText(e.item)
        c[2]:SetText((e.rl and e.rl > 0) and tostring(e.rl) or "—")
        c[3]:SetText(ProfLabel(e.skill))
        c[4]:SetText(""); c[5]:SetText("")
        row.allBtn:Show(); row.postBtn:Show()
    end)
end

---------------------------------------------------------------------------
-- Montar la pestaña (lo llama T.Build, TradeView.lua): la fila de los filtros y la ventana «Quién lo hace»
---------------------------------------------------------------------------
-- (un filtro de Buscar cambia: la lista se rehace y se vuelve arriba)
local function FilterChanged()
    T.findDirty = true
    FauxScrollFrame_SetOffset(T.ui.items.scroll, 0)
    Paint()
end
-- (el texto del botón de un filtro: su nombre sin nada elegido; lo elegido, si es uno; si no, cuántos)
local function FilterLabel(base, set, opts)
    local n, one = 0, nil
    for _, o in ipairs(opts) do if set[o[1]] then n, one = n + 1, o end end
    if n == 0 then return L(base) end
    if n == 1 then return L(one[2]) end
    return string.format("%s (%d)", L(base), n)
end
-- (el menú de un filtro: casillas, varias a la vez; con su color o, las profesiones, con su icono detrás de la casilla.
-- Sale siempre debajo de su botón, como los desplegables del juego: con el de clic derecho salía donde estaba el ratón.
-- Jorge, 25/11: «cada vez que salga este desplegable, debe salir siempre en el mismo sitio». Sin el sistema de menús
-- del juego, el de clic derecho) [+ARCHITECTURE.md]
local function FilterMenu(owner, base, set, opts)
    local M, V, U = Menu, MenuVariants, MenuUtil
    local function Open(gen)
        if M and M.GetManager and M.PopulateDescription and V and V.GetDefaultContextMenuMixin and CreateAnchor
            and U and U.CreateRootMenuDescription then
            local desc = U.CreateRootMenuDescription(V.GetDefaultContextMenuMixin())
            M.PopulateDescription(gen, owner, desc)
            return M.GetManager():OpenMenu(owner, desc, CreateAnchor("TOPLEFT", owner, "BOTTOMLEFT", 0, -2))
        end
        if U and U.CreateContextMenu then return U.CreateContextMenu(owner, gen) end
    end
    -- (otro clic en el botón con su menú abierto lo cierra (Jorge, 25/11): el juego cierra los menús al pulsar fuera de
    -- ellos, antes del clic; por eso el botón mira al pulsar (OnMouseDown, BuildFilters) si estaba abierto: `wasOpen`)
    if owner.wasOpen then
        owner.wasOpen = nil
        if owner.menu and owner.menu.Close then owner.menu:Close() end
        owner.menu = nil
        return
    end
    local menu = Open(function(_, root)
        root:CreateTitle(L(base))
        for _, o in ipairs(opts) do
            local text = (o.skill and ProfLabel(o.skill)) or (o.color and ("|cff" .. o.color .. L(o[2]) .. "|r")) or L(o[2])
            root:CreateCheckbox(text, function() return set[o[1]] == true end, function()
                set[o[1]] = (not set[o[1]]) or nil
                owner:SetText(FilterLabel(base, set, opts))
                FilterChanged()
            end)
        end
    end)
    owner.menu = menu
    if menu and menu.SetClosedCallback then
        menu:SetClosedCallback(function() owner.menu, owner.closedAt = nil, GetTime() end)
    end
end

-- La fila 2 de Buscar: profesión · nivel (el requerido) de… a… · rareza · tipo · buscador, en vez del buscador y la
-- casilla. Los menús, con casillas, salen debajo de su botón (FilterMenu) [+ARCHITECTURE.md]
local function BuildFilters(host)
    local f = CreateFrame("Frame", nil, host)
    f:SetAllPoints(host)
    local y = ROW2_Y - ROW2_H / 2
    local profs = {}
    for skill, name in pairs(PROF_NAMES) do profs[#profs + 1] = { skill, name, skill = skill } end
    table.sort(profs, function(a, b) return L(a[2]) < L(b[2]) end)
    local quals, types = {}, {}
    for i, q in ipairs(QUALITIES) do quals[i] = { q[1], q[2], color = q[3] } end
    for i, t in ipairs(TYPES) do types[i] = { t[1], t[2] } end
    local function FilterBtn(base, set, opts, x, w)
        local b = DJ.Button(f, L(base), w, 22)
        b:SetPoint("LEFT", host, "TOPLEFT", x, y)
        -- (abierto al pulsar: aún lo está, o el juego lo acaba de cerrar en este mismo momento por ese clic)
        b:SetScript("OnMouseDown", function(s) s.wasOpen = s.menu ~= nil or s.closedAt == GetTime() end)
        b:SetScript("OnClick", function(s) FilterMenu(s, base, set, opts) end)
        return b
    end
    f.prof = FilterBtn("Profesión", findProf, profs, 23, 118)
    -- («Nivel:», el que pide el objeto para usarlo, con las dos cajas pegadas. Jorge, 25/11: «item lvl no, debe ser Level
    -- nada más (nivel requerido), los 2 campos más pegados a donde pone level»)
    f.lvlLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.lvlLabel:SetPoint("LEFT", host, "TOPLEFT", 149, y); f.lvlLabel:SetWidth(32); f.lvlLabel:SetJustifyH("LEFT")
    f.lvlLabel:SetText(L("Nivel:"))
    local function Level(x, set)
        local box = HU.NewEditBox(f, 30)
        box:SetPoint("LEFT", host, "TOPLEFT", x, y); box:SetNumeric(true); box:SetMaxLetters(3); box:SetJustifyH("CENTER")
        box:HookScript("OnTextChanged", function(s)
            set(tonumber(s:GetText() or ""))
            FilterChanged()
        end)
        return box
    end
    f.lvlMin = Level(187, function(v) findMin = v end)
    f.lvlTo = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.lvlTo:SetPoint("LEFT", host, "TOPLEFT", 221, y); f.lvlTo:SetWidth(14); f.lvlTo:SetJustifyH("CENTER")
    f.lvlTo:SetText(L("a"))
    f.lvlMax = Level(241, function(v) findMax = v end)
    f.qual = FilterBtn("Rareza", findQual, quals, 281, 92)
    f.type = FilterBtn("Tipo", findType, types, 381, 104)
    -- Un enlace en un buscador (Mayús+clic o una sugerencia): se ve su nombre entre corchetes, del color de su calidad, y
    -- el enlace queda aparte (`box.link`). Con los códigos del enlace dentro, en una caja estrecha el juego no lo pintaba
    -- (Jorge, 25/11: «cuando linkeo no se ve, pero está»). Con un enlace puesto, borrar (o escribir) lo quita entero, de
    -- una vez («si le doy al botón de borrar… debería borrarse, entero de una si es linkeado») [+ARCHITECTURE.md]
    function f.SetLink(box, link)
        box.link, box.linkText = link, "[" .. (link:match("|h%[(.-)%]|h") or Plain(link)) .. "]"
        local hex = link:match("^|c%x%x(%x%x%x%x%x%x)")
        if hex then
            box:SetTextColor(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255)
        end
        box:SetText(box.linkText)
    end
    function f.WatchLink(box)
        box:HookScript("OnTextChanged", function(s, user)
            local text = s:GetText() or ""
            if s.link and text == s.linkText then return end
            if s.link then
                s.link, s.linkText = nil, nil
                s:SetTextColor(1, 1, 1)
                if user then s:SetText(""); return end
            end
            -- (otro enlace encima del que había, o uno nuevo: se ve por su nombre)
            if text:find("|H", 1, true) then f.SetLink(s, text) end
        end)
    end
    -- (al final, su buscador, como el del Tablón: un nombre, o el enlace de un objeto con Mayús+clic (T.Build), que deja
    -- solo ese objeto; con un enlace, al pasar el ratón, su ficha. Jorge, 25/11: «añade buscador para el item también,
    -- que se pueda linkear ahí con el shift+click»)
    local search = SearchBox("GuildUnionTradeFindSearch", f, 108, L("Buscar objeto"))
    search:SetPoint("RIGHT", host, "TOPRIGHT", -14, y)
    f.WatchLink(search)
    search:HookScript("OnTextChanged", FilterChanged)
    f.search = search
    return f
end

-- «Quién lo hace» un objeto de Buscar (`who.key`), en su ventana, que se mueve: todos los que pueden, como en la columna;
-- clic derecho en alguien, susurrarle o solicitar pedido (un anuncio privado para esa persona con el objeto ya puesto; a
-- mí, nada). Se abre con «Ver todos», al final de quién lo hace en cada fila de Buscar. Jorge, 25/11: «un botón para sacar
-- una pestaña (movible) con todos los que pueden, con botón derecho susurrar o solicitar pedido». Aquí van también los
-- clics de las filas de objetos [+ARCHITECTURE.md]
local function BuildWho(host)
    local ui = T.ui
    local S = SIZES
    -- (las filas de objetos de Buscar: clic, se elige (lo que pide «+ Nuevo encargo»); clic derecho, publicarlo en el
    -- tablón o ver quién lo hace (Jorge, 25/11: «que pueda hacer botón derecho "publicar en tablón"… y hacerlo público»);
    -- en sus dos últimas columnas, «Ver todos» y «Publicarlo» (Jorge: «all [see all]… otra columna de board… [post it]»))
    local function Small(row, text, cell, fn)
        local b = DJ.Button(row, text, S.allW, 18)
        b:SetNormalFontObject("GameFontNormalSmall"); b:SetHighlightFontObject("GameFontHighlightSmall")
        b:SetPoint("CENTER", row.cells[cell], "CENTER")
        b:SetScript("OnClick", function() if row.entry then fn(row.entry) end end)
        b:Hide()
        return b
    end
    for _, row in ipairs(ui.items.rows) do
        row:SetScript("OnClick", function(s, button)
            local e = s.entry
            if not e then return end
            findSel = e.key
            PaintFind()
            if button ~= "RightButton" or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(s, function(_, root)
                root:CreateTitle(e.item)
                root:CreateButton(L("Publicar en el tablón"), function() ui.OpenNew(nil, e.item) end)
                root:CreateButton(L("Ver quién lo hace"), function() ui.OpenWho(e.key) end)
                root:CreateButton(L("Cancelar"), function() end)
            end)
        end)
        row.allBtn = Small(row, L("Ver todos"), 4, function(e) ui.OpenWho(e.key) end)
        row.postBtn = Small(row, L("Publicarlo"), 5, function(e)
            findSel = e.key
            ui.OpenNew(nil, e.item)
        end)
    end
    -- (bajar por la lista solo repinta la lista, sin lo demás de la sección: con todo, se trababa. Jorge, 25/11)
    ui.items.scroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, PaintFind)
    end)
    -- (arriba a la derecha de la lista, las flechas que giran mientras el juego da los nombres de los objetos)
    local spin = ui.items.hdr:CreateTexture(nil, "OVERLAY")
    spin:SetSize(16, 16); spin:SetPoint("RIGHT", ui.items.hdr, "RIGHT", -4, 0)
    spin:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    local turn = spin:CreateAnimationGroup()
    local rot = turn:CreateAnimation("Rotation")
    rot:SetDegrees(-360); rot:SetDuration(1)
    turn:SetLooping("REPEAT"); turn:Play()
    spin:Hide()
    ui.items.spin = spin
    -- (en la capa HIGH, por debajo de la ventana de pedir (DIALOG) y de los menús, que así salen por encima)
    local who = DJ.Window("GuildUnionTradeWho", host, S.whoW, S.whoH)
    who:SetFrameStrata("HIGH")
    tinsert(UISpecialFrames, "GuildUnionTradeWho")
    who.titleText:SetWidth(S.whoW - 70); who.titleText:SetWordWrap(false)
    -- (arriba, un buscador por nombre, solo entre los de la ventana: Jorge, 25/11)
    local find = CreateFrame("EditBox", "GuildUnionTradeWhoSearch", who.content, "SearchBoxTemplate")
    find:SetSize(170, 20)
    find:SetPoint("TOPLEFT", who.content, "TOPLEFT", 14, -7)
    if find.Instructions then find.Instructions:SetText(L("Buscar nombre")); DJ.C(find.Instructions, DJ.T.muted) end
    who.find = find
    local wl = MakeList(S.whoRows, false, "GuildUnionTradeWhoScroll", who.content)
    wl.list:SetPoint("TOPLEFT", who.content, "TOPLEFT", 6, -32)
    wl.list:SetWidth(S.whoW - 36 - 12 - S.scroll)
    Titled(wl, nil)
    wl.empty:SetText(L("Nadie de la unión lo hace."))
    find:HookScript("OnTextChanged", function()
        FauxScrollFrame_SetOffset(wl.scroll, 0)
        who.Paint()
    end)
    -- (clic derecho en alguien: susurrarle o hacerle un encargo con el objeto ya puesto; a mí mismo, solo mi nombre.
    -- Jorge, 25/11: «añadir en el botón derecho, whisp y make an order»)
    local function WhoMenu(owner, r)
        local c = who.key and craft[who.key]
        if not (c and MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateTitle(HU:Short(r.name))
            if not IsMe(r.name) then
                root:CreateButton(L("Susurrar"), function() HU.WhisperTo(r.name) end)
                root:CreateButton(L("Hacer un encargo"), function() ui.OpenNew(r.name, c.link) end)
            end
            root:CreateButton(L("Cancelar"), function() end)
        end)
    end
    for _, row in ipairs(wl.rows) do
        -- (las filas, por encima de su lista y de su barra, para que les lleguen los clics)
        row:SetFrameLevel(wl.scroll:GetFrameLevel() + 3)
        row:SetScript("OnClick", function(s, button)
            if button == "RightButton" and s.entry then WhoMenu(s, s.entry) end
        end)
    end
    who.lst = wl
    who.hint = DJ.C(who:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), DJ.T.muted)
    who.hint:SetPoint("BOTTOM", who, "BOTTOM", 0, 20)
    ui.who = who
    -- (lo pinta Paint, si está abierta: con lo de ahora, como la columna; con el buscador, solo los nombres que encajan)
    function who.Paint()
        if not who:IsShown() then return end
        local c = who.key and craft[who.key]
        if not c then who:Hide(); return end
        local list = CraftersOf(who.key)
        who.titleText:SetText(L("Quién lo hace") .. ": " .. c.link)
        who.hint:SetText(string.format(L("Pueden hacerlo: %d · clic derecho: susurrar o solicitar pedido"), #list))
        local q = HU.Trim(find:GetText() or "")
        if q ~= "" then
            local out = {}
            for _, r in ipairs(list) do if HU.TextRank(r.name, q) then out[#out + 1] = r end end
            list = out
        end
        Columns(wl, COLS.search, 4)
        PaintRows(wl, list, FillWho)
    end
    function ui.OpenWho(key)
        if key ~= who.key then
            FauxScrollFrame_SetOffset(wl.scroll, 0)
            find:SetText("")
        end
        who.key, findSel = key, key
        -- (la primera vez, a la derecha de la ventana de hermandad; luego, donde la deje el jugador)
        if not who.placed then
            who.placed = true
            who:ClearAllPoints()
            who:SetPoint("TOPLEFT", CommunitiesFrame or host, "TOPRIGHT", 4, 0)
        end
        who:Show(); who:Raise()
        Paint()
    end
    -- (es de la sección: se cierra con ella)
    host:HookScript("OnHide", function() who:Hide() end)
end

T.FindLink, T.PaintFind, T.BuildFilters, T.BuildWho = FindLink, PaintFind, BuildFilters, BuildWho

HU:Module("TradeFind", { "BlizzTab", "Core", "ListWindow" })
