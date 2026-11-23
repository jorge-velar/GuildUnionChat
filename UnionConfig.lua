-- Guild Union - Configuración de la hermandad (mitad derecha de la pestaña GuildUnion) [+ARCHITECTURE.md]
-- Fase 1: sin red; se guarda en este PC (HU.db.unionCfg) y la usan Banco y Comercio. Pestañas: Hermandad (color,
-- solo el maestro), Banco (quién lo ve y quién puede pedir), Comercio (activo, propinas) y Lista negra.
-- Lo cambia el maestro de la hermandad; los demás lo ven sin poder tocarlo.
local _, HU = ...
local L = HU.L
local DJ = HU.DJ
local T = DJ.T

HU:Saved({ char = { "unionCfg" } }) -- (de cada personaje: cada hermandad tiene la suya)

function HU:UnionCfg()
    self.db.unionCfg = self.db.unionCfg or {}
    return self.db.unionCfg
end
-- (el maestro de la hermandad, o quien tiene el rango 0; o «Probar como maestro» para probar la ventana)
function HU:IsUnionGM() return self:IsMaster() or self:UnionCfg().testGM == true end
local function Cfg() return HU:UnionCfg() end
local function IsGM() return HU:IsUnionGM() end
local function Changed() HU:Changed("unionCfg") end

-- (¿puedo crear eventos? Según la configuración del calendario, o con un permiso por un tiempo)
function HU:CanMakeEvents()
    local c = Cfg()
    local who = c.calMake or "officers"
    if who == "all" or IsGM() then return true end
    if who == "officers" and self:CanPin() then return true end
    local p = c.calAllow and c.calAllow[self:Key(self:Me() or "") or ""]
    return p ~= nil and (p.untilT or 0) > time()
end

function HU:BuildUnionConfig(panel)
    local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    box:SetPoint("TOPLEFT", panel, "TOP", 10, -66); box:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 12)
    DJ.Panel(box, T.panel, T.border, 12, 3)
    local title = DJ.C(box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), T.title)
    title:SetPoint("TOPLEFT", 10, -8); title:SetText(L("Configuración"))
    -- (quién puede cambiarla, arriba a la derecha; y la casilla para probarla sin ser maestro)
    local who = DJ.C(box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    who:SetPoint("LEFT", title, "RIGHT", 10, 0); who:SetJustifyH("LEFT")
    local testCb = CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
    testCb:SetSize(20, 20); testCb:SetPoint("BOTTOMLEFT", 8, 6)
    local testL = DJ.C(box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    testL:SetPoint("LEFT", testCb, "RIGHT", 2, 0); testL:SetText(L("Probar como maestro (solo en este PC)"))

    -- Pestañas
    local pages, tabs = {}, {}
    local current = "trade"
    local TABS = { { "trade", L("Comercio") }, { "black", L("Lista negra") }, { "bank", L("Banco") }, { "calendar", L("Calendario") },
        { "guild", L("Hermandad") } }
    for i, t in ipairs(TABS) do
        local b = DJ.Button(box, t[2], 84, 22)
        local col, line = (i - 1) % 3, math.floor((i - 1) / 3)
        b:SetPoint("TOPLEFT", 8 + col * 87, -32 - line * 24)
        tabs[t[1]] = b
        local p = CreateFrame("Frame", nil, box)
        p:SetPoint("TOPLEFT", 8, -86); p:SetPoint("BOTTOMRIGHT", -8, 30)
        p:Hide()
        pages[t[1]] = p
    end

    local controls = {}       -- lo que solo puede tocar el maestro
    local function Head(p, text, y)
        local h = DJ.C(p:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.title)
        h:SetPoint("TOPLEFT", 4, y); h:SetText(text)
        return h
    end
    -- (una fila de botones que se excluyen: el elegido, oscuro)
    local function Choice(p, y, options, get, set)
        local btns, x = {}, 4
        for _, o in ipairs(options) do
            local b = DJ.Button(p, o[2], o[3] or 96, 22)
            b:SetPoint("TOPLEFT", x, y)
            b:SetScript("OnClick", function() set(o[1]); Changed() end)
            btns[#btns + 1] = { b = b, v = o[1] }
            controls[#controls + 1] = b
            x = x + (o[3] or 96) + 4
        end
        return function() for _, it in ipairs(btns) do it.b:Pick(get() == it.v) end end
    end
    local function Check(p, y, text, get, set)
        local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", 0, y)
        local fs = DJ.C(p:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), T.text)
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0); fs:SetText(text)
        cb:SetScript("OnClick", function(s) set(s:GetChecked() and true or false); Changed() end)
        controls[#controls + 1] = cb
        return function() cb:SetChecked(get() and true or false) end
    end
    local refresh = {}

    -- Hermandad: el color (el maestro), en una línea: muestra y «Elegir color» (selector del juego)
    local pg = pages.guild
    local cl = DJ.C(pg:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.title)
    cl:SetPoint("TOPLEFT", 4, -6); cl:SetText(L("Color:"))
    local sw = CreateFrame("Button", nil, pg, "BackdropTemplate")
    sw:SetSize(30, 16); sw:SetPoint("LEFT", cl, "RIGHT", 8, 0)
    DJ.Panel(sw, { 1, 1, 1, 1 }, T.border, 10, 2)
    local swText = DJ.C(pg:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), T.text)
    swText:SetPoint("LEFT", sw, "RIGHT", 6, 0)
    local function SetColor(hex)
        local tag = HU.myTag
        if not tag then return end
        HU.db.guildColors = HU.db.guildColors or {}
        HU.db.guildColors[tag] = { hex = hex, by = HU:Me(), byTag = tag, t = time() }
        HU:Changed("config"); Changed()
    end
    local pick = DJ.Button(pg, L("Elegir color"), 96, 20)
    pick:SetPoint("TOPLEFT", 4, -28)
    controls[#controls + 1] = pick
    pick:SetScript("OnClick", function()
        if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
        local r, g, b = HU:GuildColor(HU.myTag)
        local function Apply()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            SetColor(string.format("%02x%02x%02x", nr * 255, ng * 255, nb * 255))
        end
        ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, swatchFunc = Apply,
            cancelFunc = function() SetColor(string.format("%02x%02x%02x", r * 255, g * 255, b * 255)) end })
    end)
    refresh[#refresh + 1] = function()
        local r, g, b = HU:GuildColor(HU.myTag)
        sw:SetBackdropColor(r, g, b, 1)
        swText:SetText(tostring(HU.myTag or "?"))
    end

    -- Banco: quién lo ve y quién puede pedir
    local pb = pages.bank
    Head(pb, L("Quién puede ver el banco"), -4)
    refresh[#refresh + 1] = Choice(pb, -24, { { "officers", L("Oficiales"), 90 }, { "all", L("Todos"), 90 } },
        function() return Cfg().bankView or "officers" end, function(v) Cfg().bankView = v end)
    Head(pb, L("Quién puede pedir sacar algo"), -58)
    refresh[#refresh + 1] = Choice(pb, -78, { { "all", L("Todos"), 80 }, { "officers", L("Oficiales"), 80 }, { "none", L("Nadie"), 80 } },
        function() return Cfg().bankRequest or "all" end, function(v) Cfg().bankRequest = v end)
    local bNote = DJ.C(pb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    bNote:SetPoint("TOPLEFT", 4, -110); bNote:SetWidth(250); bNote:SetJustifyH("LEFT")
    bNote:SetText(L("Las solicitudes las aprueba o rechaza un oficial de la hermandad del banco, y lo envía por correo."))

    -- Comercio: activo y propinas
    local pt = pages.trade
    Head(pt, L("Comercio"), -4)
    refresh[#refresh + 1] = Check(pt, -22, L("Comercio activo en la hermandad"),
        function() return not Cfg().tradeOff end, function(v) Cfg().tradeOff = (not v) or nil end)
    refresh[#refresh + 1] = Check(pt, -48, L("Permitir propinas"),
        function() return not Cfg().tipsOff end, function(v) Cfg().tipsOff = (not v) or nil end)
    local tNote = DJ.C(pt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    tNote:SetPoint("TOPLEFT", 4, -82); tNote:SetWidth(250); tNote:SetJustifyH("LEFT")
    tNote:SetText(L("Sin propinas, las solicitudes no llevan oro. Con el comercio apagado, la sección Comercio no deja pedir."))

    -- Calendario: quién crea eventos y permisos de un rato (a alguien que no es oficial, por ejemplo)
    local pc = pages.calendar
    Head(pc, L("Quién puede crear eventos"), -4)
    refresh[#refresh + 1] = Choice(pc, -24, { { "gm", L("Maestro"), 80 }, { "officers", L("Oficiales"), 80 }, { "all", L("Todos"), 80 } },
        function() return Cfg().calMake or "officers" end, function(v) Cfg().calMake = v end)
    Head(pc, L("Permiso por un tiempo"), -56)
    local pName = HU.NewEditBox(pc, 118)
    pName:SetPoint("TOPLEFT", 8, -76)
    HU:NameSuggest(pName)
    local pHours = HU.NewEditBox(pc, 30)
    pHours:SetPoint("LEFT", pName, "RIGHT", 8, 0)
    pHours:SetNumeric(true); pHours:SetMaxLetters(3); pHours:SetText("24")
    local pH = DJ.C(pc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    pH:SetPoint("LEFT", pHours, "RIGHT", 3, 0); pH:SetText(L("h"))
    local pGive = DJ.Button(pc, L("Dar"), 54, 20)
    pGive:SetPoint("LEFT", pH, "RIGHT", 6, 0)
    controls[#controls + 1] = pName; controls[#controls + 1] = pHours; controls[#controls + 1] = pGive
    local permRows = {}
    for i = 1, 5 do
        local row = CreateFrame("Frame", nil, pc)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT", 4, -100 - (i - 1) * 18); row:SetPoint("RIGHT", pc, "RIGHT", -4, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 2, 0); row.name:SetWidth(110); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.till = DJ.C(row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
        row.till:SetPoint("LEFT", 116, 0)
        row.del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        row.del:SetSize(20, 20); row.del:SetPoint("RIGHT", 0, 0)
        row.del:SetScript("OnClick", function()
            local allow = Cfg().calAllow
            if allow and row.key then allow[row.key] = nil; Changed() end
        end)
        permRows[i] = row
    end
    local permNone = DJ.C(pc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    permNone:SetPoint("TOPLEFT", 6, -104); permNone:SetText(L("Nadie tiene permiso por un tiempo."))
    pGive:SetScript("OnClick", function()
        local name = HU.Trim(pName:GetText() or "")
        local key = name ~= "" and HU:Key(name)
        if not key then return end
        local h = math.max(1, math.min(999, tonumber(pHours:GetText() or "") or 24))
        local c = Cfg()
        c.calAllow = c.calAllow or {}
        c.calAllow[key] = { name = HU:FullName(name) or name, untilT = time() + h * 3600, by = HU:Me() }
        pName:SetText("")
        Changed()
    end)
    refresh[#refresh + 1] = function()
        local allow = Cfg().calAllow or {}
        local list, now = {}, time()
        for k, p in pairs(allow) do
            if (p.untilT or 0) <= now then allow[k] = nil else list[#list + 1] = { key = k, p = p } end
        end
        table.sort(list, function(x, y) return x.p.untilT < y.p.untilT end)
        local gm = IsGM()
        local ph = pc:GetHeight()
        local fit = (type(ph) == "number" and ph > 0) and math.max(1, math.floor((ph - 100) / 18)) or 3
        for i, row in ipairs(permRows) do
            local it = (i <= fit) and list[i] or nil
            row.key = it and it.key
            if it then
                row.name:SetText(HU:Short(it.p.name))
                row.till:SetText(string.format(L("hasta %s"), date("%d/%m %H:%M", it.p.untilT)))
                row.del:SetShown(gm)
            end
            row:SetShown(it ~= nil)
        end
        permNone:SetShown(#list == 0)
    end

    -- Lista negra: la lista, aquí mismo; añadir y quitar, el maestro y los oficiales
    local pl = pages.black
    Head(pl, L("Lista negra de la comunidad"), -4)
    local list = CreateFrame("Frame", nil, pl, "BackdropTemplate")
    list:SetPoint("TOPLEFT", 0, -22); list:SetPoint("BOTTOMRIGHT", 0, 76)
    DJ.Panel(list, T.row, T.border, 10, 2)
    local BL_ROW, BL_MAX = 16, 14
    local lsf = CreateFrame("ScrollFrame", "GuildUnionCfgBlackScroll", list, "FauxScrollFrameTemplate")
    lsf:SetPoint("TOPLEFT", 4, -4); lsf:SetPoint("BOTTOMRIGHT", -26, 4)
    local blRows, PaintBlack = {}, nil
    lsf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, BL_ROW, PaintBlack) end)
    local nameBox, whyBox
    for i = 1, BL_MAX do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(BL_ROW)
        row:SetPoint("TOPLEFT", lsf, "TOPLEFT", 0, -(i - 1) * BL_ROW); row:SetPoint("RIGHT", lsf, "RIGHT")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 4, 0); row.name:SetWidth(110); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.by = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.by:SetPoint("LEFT", 118, 0); row.by:SetPoint("RIGHT", -2, 0); row.by:SetJustifyH("LEFT"); row.by:SetWordWrap(false)
        -- (pulsar: el nombre abajo, listo para quitarlo; al pasar el ratón, quién lo vetó y el motivo)
        row:SetScript("OnClick", function(s) if s.e and nameBox:IsShown() then nameBox:SetText(HU:Short(s.e.name)) end end)
        row:SetScript("OnEnter", function(s)
            if not s.e then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(HU:Short(s.e.name))
            if s.e.by then GameTooltip:AddLine(L("Lo vetó") .. ": " .. HU:Short(s.e.by), 0.8, 0.8, 0.8) end
            if s.e.why and s.e.why ~= "" then GameTooltip:AddLine(s.e.why, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        blRows[i] = row
    end
    local blEmpty = DJ.C(list:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.muted)
    blEmpty:SetPoint("CENTER"); blEmpty:SetText(L("No hay nadie en la lista negra."))
    PaintBlack = function()
        local all = HU:BlacklistEntries()
        local h = lsf:GetHeight()
        local shown = (type(h) == "number" and h > 0) and math.max(1, math.min(BL_MAX, math.floor(h / BL_ROW))) or 8
        FauxScrollFrame_Update(lsf, #all, shown, BL_ROW)
        local off = FauxScrollFrame_GetOffset(lsf)
        for i, row in ipairs(blRows) do
            local e = (i <= shown) and all[off + i] or nil
            row.e = e
            if e then
                row.name:SetText((HU.roster[e.key] and "|cffff4444" or "|cffffffff") .. HU:Short(e.name) .. "|r")
                row.by:SetText(e.by and (HU:Short(e.by) .. ((e.tag and e.tag ~= "") and (" |cff" .. HU:GuildColorHex(e.tag) .. "<" .. e.tag .. ">|r") or "")) or "")
            end
            row:SetShown(e ~= nil)
        end
        blEmpty:SetShown(#all == 0)
    end
    lsf:SetScript("OnSizeChanged", function() if pl:IsVisible() then PaintBlack() end end)
    -- (abajo: nombre + Quitar, motivo + Añadir, y la leyenda con «Comprobar ahora»)
    local lName = DJ.C(pl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.text)
    lName:SetPoint("BOTTOMLEFT", 4, 58); lName:SetText(L("Nombre"))
    nameBox = HU.NewEditBox(pl, 130)
    nameBox:SetPoint("LEFT", lName, "LEFT", 50, 0)
    HU:NameSuggest(nameBox)
    local bDel = DJ.Button(pl, L("Quitar"), 70, 20)
    bDel:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    local lWhy = DJ.C(pl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.text)
    lWhy:SetPoint("BOTTOMLEFT", 4, 32); lWhy:SetText(L("Motivo"))
    whyBox = HU.NewEditBox(pl, 130)
    whyBox:SetPoint("LEFT", lWhy, "LEFT", 50, 0)
    whyBox:SetMaxLetters(80)
    local bAdd = DJ.Button(pl, L("Añadir"), 70, 20)
    bAdd:SetPoint("LEFT", whyBox, "RIGHT", 8, 0)
    local legend = pl:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    legend:SetPoint("BOTTOMLEFT", 4, 8)
    legend:SetText("|cffff4444" .. L("En rojo") .. "|r" .. L(": está ahora mismo en tu hermandad."))
    local bCheck = DJ.Button(pl, L("Comprobar ahora"), 120, 20)
    bCheck:SetPoint("BOTTOMRIGHT", 0, 4)
    bCheck:SetScript("OnClick", function() HU:BlacklistCheck(true); PaintBlack() end)
    bAdd:SetScript("OnClick", function()
        local name = HU.Trim(nameBox:GetText() or "")
        if name == "" then return end
        HU:SetBan(name, true, whyBox:GetText())
        if HU:IsBanned(name) then nameBox:SetText(""); whyBox:SetText("") end
        PaintBlack(); HU:BlacklistCheck()
    end)
    bDel:SetScript("OnClick", function()
        local name = HU.Trim(nameBox:GetText() or "")
        if name == "" or not HU:IsBanned(name) then return end
        HU:Unban(name)
        nameBox:SetText("")
        PaintBlack()
    end)
    local blEdit = { lName, nameBox, bDel, lWhy, whyBox, bAdd }
    refresh[#refresh + 1] = function()
        local can = HU:CanPin()
        for _, w in ipairs(blEdit) do w:SetShown(can) end
        if pl:IsVisible() then PaintBlack() end
    end

    local function Paint()
        for k, b in pairs(tabs) do b:Pick(k == current) end
        for k, p in pairs(pages) do p:SetShown(k == current) end
        local gm = IsGM()
        for _, c in ipairs(controls) do c:SetEnabled(gm) end
        testCb:SetChecked(Cfg().testGM == true)
        who:SetText(gm and ("|cff40ff40" .. L("Puedes cambiarla") .. "|r") or L("Solo el maestro la cambia"))
        for _, f in ipairs(refresh) do f() end
    end
    for k, b in pairs(tabs) do b:SetScript("OnClick", function() current = k; Paint() end) end
    testCb:SetScript("OnClick", function(s) Cfg().testGM = s:GetChecked() and true or nil; Changed() end)
    HU:Listen("CHANGED", function(what)
        if (what == "unionCfg" or what == "config") and box:IsVisible() then Paint()
        elseif pl:IsVisible() then PaintBlack() end
    end)
    box:SetScript("OnShow", Paint)
    Paint()
    return box
end

HU:Module("UnionConfig", { "Blacklist", "BlizzTab", "Config", "Core", "ListWindow", "Pinned", "Social" })
