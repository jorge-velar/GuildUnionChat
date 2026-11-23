-- Guild Union - Banco de la unión (la sección Bank de la lista de miembros) [+ARCHITECTURE.md]
-- Fase 1: solo la ventana, sin red. Pestañas: Bancos de hermandad (los de la unión: buscador, filtro por hermandad y
-- la pestaña del banco de cada objeto), Banco propio (Bolsas o Banco de mi personaje) y Solicitudes (registro de lo
-- pedido: quién lo pide, de qué banco y pestaña, y quién lo saca). Se saca en el banco de hermandad del juego: al
-- abrirlo sale una ventanita con lo pedido a mi hermandad. Rechazar, solo el maestro. Lo ven los oficiales; todos, si
-- el maestro lo abre (UnionConfig.lua). El «Modo prueba» rellena bancos y solicitudes de mentira.
local _, HU = ...
local L = HU.L

HU:Saved({ char = { "myBankSnap" } }) -- (lo último que se vio del banco de este personaje: { items, t })

local SLOT, GAP = 37, 4
local REQ_ROWS, ROW_H = 10, 20
local DJ = HU.DJ
local T = DJ.T

-- (en la sesión: fase 1, sin red)
local banks = {}            -- [etiqueta] = { { id, count, tab }, ... }  (el banco de cada hermandad, por pestañas)
local reqs = {}             -- { id, item, count, tab, who, tag, note, state = "open"|"done"|"no", t, takenBy, takenAt, noBy, noAt, test }
local view = "guild"        -- "guild" (bancos de hermandad), "own" (banco propio), "reqs" (solicitudes)
local reqLog = false        -- en Solicitudes: true = se ve el registro
local log = {}              -- { t, text, test }: lo pedido, sacado y rechazado, en orden
local ownSet = {}           -- en Banco propio: lo elegido ([bank] / [bags] = true); vacío = todo
local filterTags = {}       -- las hermandades elegidas ([etiqueta] = true); vacío = todas
local ui

local function Me() return HU:Me() or "?" end
local function NewId() return string.format("%x%x", math.random(0, 0xffff), time() % 0xffff) end
local function Cfg() return HU:UnionCfg() end
local function IsGM() return HU:IsUnionGM() end
-- (lo ve: oficial, o todos si el maestro lo abrió, o el modo prueba)
local function CanSee() return HU:CanPin() or Cfg().bankView == "all" or ui.testOn == true end
local function CanRequest()
    local who = Cfg().bankRequest or "all"
    if who == "none" then return false end
    return who == "all" or HU:CanPin() or ui.testOn == true
end
local function ItemName(id)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local ok, name, link, quality = pcall(get, id)
    if ok and name then return name, link, quality end
end
local function ItemIcon(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    local ok, icon = pcall(f, id)
    return ok and icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function TagText(tag) return "|cff" .. HU:GuildColorHex(tag) .. tostring(tag) .. "|r" end
-- («WLP3 · pestaña 2»)
local function WhereText(tag, tab) return TagText(tag) .. (tab and ("  |cffb0b0b0" .. string.format(L("pestaña %d"), tab) .. "|r") or "") end
local function When(t) return t and date("%d/%m %H:%M", t) or "" end
local function ReqText(r)
    local name, link = ItemName(r.item)
    return (r.count > 1 and (r.count .. " x ") or "") .. (link or name or ("#" .. r.item))
end
local function Log(text, test) log[#log + 1] = { t = time(), text = text, test = test } end
-- (el nombre a color: el de su clase si se sabe; si no, uno fijo para ese nombre)
local NAME_COLORS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local function Who(name)
    local short = HU:Short(name or "?")
    local e = HU.roster[HU:Key(name or "") or ""]
    local class = e and e.class
    if not class and name == Me() and UnitClass then class = select(2, UnitClass("player")) end
    if not class then
        local h = 0
        for i = 1, #short do h = (h * 31 + short:byte(i)) % 997 end
        class = NAME_COLORS[h % #NAME_COLORS + 1]
    end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then return short end
    return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, short)
end

-- (mi banco de personaje: el juego solo deja leerlo con el banco abierto; se guarda lo último que se vio)
local function ReadContainers(list)
    local out = {}
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local slotInfo = C_Container and C_Container.GetContainerItemInfo
    for _, bag in ipairs(list) do
        local okN, n = pcall(numSlots, bag)
        for slot = 1, (okN and type(n) == "number") and n or 0 do
            local okI, info = pcall(slotInfo, bag, slot)
            if okI and type(info) == "table" and info.itemID then out[#out + 1] = { info.itemID, info.stackCount or 1 } end
        end
    end
    return out
end
local function BagIDs()
    local n = NUM_BAG_SLOTS or 4
    local t = {}
    for i = 0, n do t[#t + 1] = i end
    return t
end
local function BankIDs()
    -- (con Enum.BagIndex, los números del juego; si no, tras las bolsas y la de componentes)
    local E = Enum and Enum.BagIndex
    if E and E.Bank and E.BankBag_1 then
        local t = { E.Bank }
        for i = 1, NUM_BANKBAGSLOTS or 7 do if E["BankBag_" .. i] then t[#t + 1] = E["BankBag_" .. i] end end
        return t
    end
    local first, n = (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0) + 1, NUM_BANKBAGSLOTS or 7
    local t = { -1 }
    for i = first, first + n - 1 do t[#t + 1] = i end
    return t
end
local function MyBank()
    local now = ReadContainers(BankIDs())
    if #now > 0 then
        HU.db.myBankSnap = { items = now, t = time() }
        return now, nil
    end
    local snap = HU.db.myBankSnap
    return snap and snap.items or {}, snap and snap.t
end

-- Lo que se ve: los objetos del banco elegido (y el buscador)
local function Items()
    local out = {}
    local q = ui.search and HU.Trim(ui.search:GetText() or ""):lower() or ""
    local function add(id, count, tag, tab)
        if q ~= "" then
            local name = ItemName(id)
            if not (name and name:lower():find(q, 1, true)) then return end
        end
        out[#out + 1] = { id = id, count = count, tag = tag, tab = tab }
    end
    if view == "own" then
        local seen
        local all = not next(ownSet)
        if all or ownSet.bank then
            local list
            list, seen = MyBank()
            for _, it in ipairs(list) do add(it[1], it[2], HU.myTag) end
        end
        if all or ownSet.bags then
            for _, it in ipairs(ReadContainers(BagIDs())) do add(it[1], it[2], HU.myTag) end
        end
        return out, seen
    end
    for tag, list in pairs(banks) do
        if not next(filterTags) or filterTags[tag] then
            for _, it in ipairs(list) do add(it[1], it[2], tag, it[3]) end
        end
    end
    table.sort(out, function(a, b)
        if a.tag ~= b.tag then return tostring(a.tag) < tostring(b.tag) end
        if (a.tab or 0) ~= (b.tab or 0) then return (a.tab or 0) < (b.tab or 0) end
        return a.id < b.id
    end)
    return out
end

local Paint

---------------------------------------------------------------------------
-- Pedir algo de un banco: cantidad y nota. Lo saca alguien de esa hermandad en su banco del juego
---------------------------------------------------------------------------
local function BuildAsk(host)
    local d = DJ.Window("GuildUnionBankAsk", host, 340, 250)
    d.titleText:SetText(L("Pedir al banco"))
    local cf = d.content
    d.icon = cf:CreateTexture(nil, "ARTWORK"); d.icon:SetSize(36, 36); d.icon:SetPoint("TOPLEFT", 12, -12)
    d.name = cf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -2); d.name:SetPoint("RIGHT", cf, "RIGHT", -10, 0)
    d.name:SetJustifyH("LEFT"); d.name:SetWordWrap(false)
    d.from = DJ.C(cf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    d.from:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    local l1 = DJ.C(cf:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.title)
    l1:SetPoint("TOPLEFT", 12, -62); l1:SetText(L("Cantidad:"))
    d.qty = HU.NewEditBox(cf, 60); d.qty:SetPoint("LEFT", l1, "RIGHT", 12, 0); d.qty:SetNumeric(true); d.qty:SetMaxLetters(4)
    d.max = DJ.C(cf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    d.max:SetPoint("LEFT", d.qty, "RIGHT", 8, 0)
    local l2 = DJ.C(cf:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.title)
    l2:SetPoint("TOPLEFT", 12, -94); l2:SetText(L("Nota:"))
    d.note = HU.NewEditBox(cf, 280); d.note:SetPoint("TOPLEFT", 18, -110); d.note:SetMaxLetters(100)
    local ok = DJ.Button(d, L("Pedir"), 120, 24); ok:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 18, 14)
    local no = DJ.Button(d, L("Cancelar"), 120, 24); no:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -18, 14)
    no:SetScript("OnClick", function() d:Hide() end)
    ok:SetScript("OnClick", function()
        local n = tonumber(d.qty:GetText() or "") or 1
        n = math.max(1, math.min(n, d.it.count))
        reqs[#reqs + 1] = { id = NewId(), item = d.it.id, count = n, tab = d.it.tab, who = Me(), tag = d.it.tag,
            note = HU.Trim(d.note:GetText() or ""), state = "open", t = time(), test = ui.testOn or nil }
        local r = reqs[#reqs]
        Log(string.format(L("%s pide %s a %s"), Who(r.who), ReqText(r), WhereText(r.tag, r.tab)), r.test)
        d:Hide()
        HU:Print(string.format(L("Pedido al banco de %s: %d x %s."), tostring(d.it.tag), n, ItemName(d.it.id) or "?"))
        Paint()
    end)
    function d.Open(it)
        d.it = it
        local name, link = ItemName(it.id)
        d.icon:SetTexture(ItemIcon(it.id))
        d.name:SetText(link or name or ("#" .. it.id))
        d.from:SetText(L("Banco:") .. " " .. WhereText(it.tag, it.tab))
        d.qty:SetText("1"); d.max:SetText(string.format(L("(hay %d)"), it.count))
        d.note:SetText("")
        d:Show()
    end
    return d
end

---------------------------------------------------------------------------
-- Sacar: al abrir el banco de hermandad del juego, una ventanita con lo pedido a mi hermandad (y «Sacar»)
---------------------------------------------------------------------------
local W_ROWS = 8
local withdraw
local function PaintWithdraw()
    if not (withdraw and withdraw:IsShown()) then return end
    local list = {}
    for _, r in ipairs(reqs) do
        if r.state == "open" and (r.tag == HU.myTag or r.test) then list[#list + 1] = r end
    end
    for i, row in ipairs(withdraw.rows) do
        local r = list[i]
        row.r = r
        if r then
            local name, link = ItemName(r.item)
            row.icon:SetTexture(ItemIcon(r.item))
            row.text:SetText((r.count > 1 and (r.count .. " x ") or "") .. (link or name or ("#" .. r.item)))
            row.sub:SetText(L("para") .. " " .. HU:Short(r.who) .. "   " .. WhereText(r.tag, r.tab))
            row:Show()
        else
            row:Hide()
        end
    end
    withdraw.empty:SetShown(#list == 0)
end
local function BuildWithdraw()
    local d = DJ.Window("GuildUnionBankWithdraw", UIParent, 330, 64 + W_ROWS * 34 + 46)
    d.titleText:SetText(L("Lo pedido a tu hermandad"))
    local cf = d.content
    d.rows = {}
    for i = 1, W_ROWS do
        local row = CreateFrame("Frame", nil, cf)
        row:SetHeight(32)
        row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 34); row:SetPoint("RIGHT", cf, "RIGHT", -6, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(28, 28); row.icon:SetPoint("LEFT", 2, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1); row.text:SetPoint("RIGHT", -70, 0)
        row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
        row.sub = DJ.C(row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
        row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2); row.sub:SetPoint("RIGHT", -70, 0)
        row.sub:SetJustifyH("LEFT"); row.sub:SetWordWrap(false)
        local take = DJ.Button(row, L("Sacar"), 62, 22)
        take:SetPoint("RIGHT", 0, 0)
        take:SetScript("OnClick", function()
            local r = row.r
            if not r then return end
            r.state, r.takenBy, r.takenAt = "done", Me(), time()
            Log(string.format(L("%s saca %s de %s para %s"), Who(Me()), ReqText(r), WhereText(r.tag, r.tab), Who(r.who)), r.test)
            HU:Print(string.format(L("Sacado para %s: envíaselo por correo."), HU:Short(r.who)))
            PaintWithdraw(); Paint()
        end)
        row:Hide()
        d.rows[i] = row
    end
    d.empty = DJ.C(cf:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.muted)
    d.empty:SetPoint("CENTER"); d.empty:SetText(L("No hay nada pedido."))
    d:SetScript("OnShow", PaintWithdraw)
    return d
end
local function ShowWithdraw()
    withdraw = withdraw or BuildWithdraw()
    withdraw:ClearAllPoints()
    if GuildBankFrame and GuildBankFrame:IsShown() then withdraw:SetPoint("TOPLEFT", GuildBankFrame, "TOPRIGHT", 6, 0)
    else withdraw:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
    withdraw:Show()
    PaintWithdraw()
end
HU:On("GUILDBANKFRAME_OPENED", function() if HU.db then ShowWithdraw() end end)
HU:On("GUILDBANKFRAME_CLOSED", function() if withdraw then withdraw:Hide() end end)

---------------------------------------------------------------------------
-- Pintar
---------------------------------------------------------------------------
local function PaintGrid()
    local list, seen = Items()
    local cols = ui.cols
    local rows = math.ceil(#list / cols)
    FauxScrollFrame_Update(ui.scroll, rows, ui.rowsVisible, SLOT + GAP)
    local off = FauxScrollFrame_GetOffset(ui.scroll) * cols
    for i, b in ipairs(ui.slots) do
        local it = list[off + i]
        b.it = it
        if it and i <= cols * ui.rowsVisible then
            b.icon:SetTexture(ItemIcon(it.id))
            b.count:SetText(it.count > 1 and it.count or "")
            local _, _, quality = ItemName(it.id)
            local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if c and quality > 1 then b.ring:SetVertexColor(c.r, c.g, c.b, 1); b.ring:Show() else b.ring:Hide() end
            -- (la etiqueta en cada hueco, salvo si se ve una sola hermandad)
            local one = 0
            for _ in pairs(filterTags) do one = one + 1 end
            b.tag:SetText(view == "guild" and one ~= 1 and TagText(it.tag) or "")
            b:Show()
        else
            b:Hide()
        end
    end
    ui.empty:SetShown(#list == 0)
    if view == "own" then
        local bank = not next(ownSet) or ownSet.bank
        ui.empty:SetText(bank and L("Tu banco: ábrelo una vez en el juego (en un banquero) para verlo aquí.")
            or L("No hay nada en tus bolsas."))
        ui.seen:SetText(bank and seen and string.format(L("Visto por última vez: %s"), When(seen)) or "")
    else
        ui.empty:SetText(L("No hay objetos. (Los bancos de las hermandades llegarán con la red; prueba el modo prueba.)"))
        ui.seen:SetText("")
    end
end

local function PaintReqs()
    local list = {}
    for i = #reqs, 1, -1 do list[#list + 1] = reqs[i] end
    FauxScrollFrame_Update(ui.reqScroll, #list, REQ_ROWS, ROW_H)
    local off = FauxScrollFrame_GetOffset(ui.reqScroll)
    local gm = IsGM()
    for i, row in ipairs(ui.reqRows) do
        local r = list[off + i]
        row.r = r
        if r then
            local name, link = ItemName(r.item)
            row.item:SetText((r.count > 1 and (r.count .. " x ") or "") .. (link or name or ("#" .. r.item)))
            row.who:SetText(HU:Short(r.who))
            row.tag:SetText(WhereText(r.tag, r.tab))
            if r.state == "done" then row.state:SetText("|cff40ff40" .. string.format(L("Sacado por %s"), HU:Short(r.takenBy or "?")) .. "|r")
            elseif r.state == "no" then row.state:SetText("|cffff5050" .. L("Rechazada") .. "|r")
            else row.state:SetText(L("Pendiente")) end
            -- (rechazar: solo el maestro de la hermandad del banco; en el modo prueba, el que prueba como maestro)
            row.no:SetShown(gm and r.state == "open" and (r.tag == HU.myTag or r.test == true))
            row:Show()
        else
            row:Hide()
        end
    end
    ui.reqEmpty:SetShown(#list == 0)
end

local function PaintLog()
    local m = ui.logMsgs
    m:Clear()
    local day
    local today, yesterday = date("%d/%m/%Y"), date("%d/%m/%Y", time() - 86400)
    for _, e in ipairs(log) do
        local d = date("%d/%m/%Y", e.t or 0)
        if d ~= day then
            if day then m:AddMessage(" ") end
            day = d
            local label = (d == today and L("Hoy")) or (d == yesterday and L("Ayer")) or date("%d/%m/%Y", e.t or 0)
            m:AddMessage("|cffffd100— " .. label .. " —|r")
        end
        m:AddMessage("|cffb0b0b0" .. date("%H:%M", e.t or 0) .. "|r  " .. e.text)
    end
    ui.logEmpty:SetShown(#log == 0)
end

function Paint()
    if not (ui and ui:IsShown()) then return end
    local see = CanSee()
    ui.locked:SetShown(not see)
    ui.body:SetShown(see)
    local open = 0
    for _, r in ipairs(reqs) do if r.state == "open" then open = open + 1 end end
    ui.viewBtns.reqs:Label(open > 0 and string.format(L("Solicitudes (%d)"), open) or L("Solicitudes"))
    for k, b in pairs(ui.viewBtns) do b:Pick(k == view) end
    ui.gridF:SetShown(view == "guild" or view == "own")
    ui.reqF:SetShown(view == "reqs" and not reqLog)
    ui.logF:SetShown(view == "reqs" and reqLog)
    ui.logBtn:SetShown(view == "reqs")
    ui.logBtn:SetText(reqLog and L("Volver a solicitudes") or L("Ver registro"))
    ui.tagBtn:SetShown(view == "guild")
    ui.ownBtn:SetShown(view == "own")
    ui.ownBtn:SetText((not next(ownSet) or (ownSet.bank and ownSet.bags)) and L("Todo") or ownSet.bank and L("Banco") or L("Bolsas"))
    ui.simBtn:SetShown(view == "reqs" and ui.testOn == true)
    ui.tagBtn.Paint()
    ui.hint:SetText(view == "guild" and (CanRequest() and L("Clic en un objeto: pedirlo.") or L("Pedir está cerrado por el maestro."))
        or view == "reqs" and L("Se saca en el banco de hermandad del juego: al abrirlo sale lo pedido.") or "")
    if view == "reqs" then if reqLog then PaintLog() else PaintReqs() end else PaintGrid() end
    PaintWithdraw()
end

---------------------------------------------------------------------------
-- Modo prueba: tres bancos de mentira (el de mi hermandad y dos más), con pestañas, y dos solicitudes
---------------------------------------------------------------------------
local function ClearTest()
    banks = {}
    for k = #reqs, 1, -1 do if reqs[k].test then table.remove(reqs, k) end end
    for k = #log, 1, -1 do if log[k].test then table.remove(log, k) end end
    filterTags = {}
end

local function AddTest()
    ClearTest()
    local tags = { HU.myTag or "GU" }
    for _, t in ipairs(HU:OtherTags()) do tags[#tags + 1] = t end
    if #tags < 3 then tags[#tags + 1] = "OTRA" end
    local POOL = { 2589, 2592, 4306, 4338, 14047, 2318, 2319, 4234, 8170, 2770, 2771, 2772, 3858, 10620, 2447, 785,
        2449, 3820, 3355, 3356, 3357, 13463, 13464, 13465, 929, 1710, 3928, 13446, 13444, 6149, 3823, 9155, 12808, 7076,
        7078, 7080, 7082, 12803, 11176, 11175, 16204, 16203, 14343, 14344, 7909, 7910, 12361, 12364, 3577, 6037, 12359 }
    for k, tag in ipairs(tags) do
        local list = {}
        for j = 1, 18 + k * 7 do
            local id = POOL[((j * 7 + k * 13) % #POOL) + 1]
            list[#list + 1] = { id, (j % 4 == 0) and 1 or (5 + (j * 3) % 16), (j % 3) + 1 }
        end
        banks[tag] = list
    end
    reqs[#reqs + 1] = { id = NewId() .. "a", item = 13446, count = 5, tab = 2, who = "Pepe-Prueba", tag = tags[1],
        note = L("Para la raid del jueves."), state = "open", t = time() - 3600, test = true }
    reqs[#reqs + 1] = { id = NewId() .. "b", item = 14047, count = 20, tab = 1, who = Me(), tag = tags[2], note = "",
        state = "open", t = time() - 600, test = true }
    reqs[#reqs + 1] = { id = NewId() .. "c", item = 3928, count = 10, tab = 3, who = "Bea-Prueba", tag = tags[1], note = "",
        state = "done", t = time() - 86400, takenBy = "Janeth-Prueba", takenAt = time() - 80000, test = true }
    for _, r in ipairs(reqs) do
        if r.test then
            log[#log + 1] = { t = r.t, test = true, text = string.format(L("%s pide %s a %s"), Who(r.who), ReqText(r), WhereText(r.tag, r.tab)) }
            if r.takenBy then
                log[#log + 1] = { t = r.takenAt, test = true, text = string.format(L("%s saca %s de %s para %s"), Who(r.takenBy), ReqText(r), WhereText(r.tag, r.tab), Who(r.who)) }
            end
        end
    end
    table.sort(log, function(a, b) return (a.t or 0) < (b.t or 0) end)
    ui.testOn = true
    Paint()
end

---------------------------------------------------------------------------
-- Montar la sección (UnionRoster.lua la pone en la pestaña Bank)
---------------------------------------------------------------------------
function HU:BuildBank(host)
    ui = host
    -- Arriba: pestañas (centradas) y modo prueba (derecha)
    ui.viewBtns = {}
    local prev
    for _, t in ipairs({ { "guild", L("Bancos de hermandad") }, { "own", L("Banco propio") }, { "reqs", L("Solicitudes") } }) do
        local b = DJ.Button(host, t[2], 124, 24)
        -- (las tres, centradas: 3 x 124 + 2 x 4 = 380 de ancho)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", host, "TOP", -190, -2) end
        b:SetScript("OnClick", function() view = t[1]; reqLog = false; FauxScrollFrame_SetOffset(ui.scroll, 0); Paint() end)
        ui.viewBtns[t[1]] = b
        prev = b
    end
    local test = DJ.Button(host, L("Modo prueba"), 100, 24)
    test:SetPoint("TOPRIGHT", host, "TOPRIGHT", -14, -36)
    -- (el modo prueba se enciende y se apaga: apagado, se quita lo de prueba)
    test:SetScript("OnClick", function(b)
        if ui.testOn then ClearTest(); ui.testOn = nil else AddTest(); ui.testOn = true end
        b:Pick(ui.testOn == true)
        Paint()
    end)

    -- (sin permiso: el aviso)
    ui.locked = DJ.C(host:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), T.muted)
    ui.locked:SetPoint("CENTER", 0, 0); ui.locked:SetWidth(420)
    ui.locked:SetText(L("Solo los oficiales pueden ver el banco. El maestro puede abrirlo a todos en la pestaña GuildUnion, Configuración → Banco."))

    local body = CreateFrame("Frame", nil, host, "BackdropTemplate")
    body:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -30); body:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)
    body:SetFrameLevel(host:GetFrameLevel() + 1)
    test:SetFrameLevel(body:GetFrameLevel() + 10)
    DJ.Panel(body, T.content, T.border, 14, 4)
    ui.body = body

    -- (segunda fila: buscador; filtro de hermandad, o Bolsas · Banco; y la ayuda)
    local search = CreateFrame("EditBox", "GuildUnionBankSearch", body, "SearchBoxTemplate")
    search:SetSize(170, 20); search:SetPoint("TOPLEFT", 14, -8)
    if search.Instructions then search.Instructions:SetText(L("Buscar en el banco")) end
    search:HookScript("OnTextChanged", function() FauxScrollFrame_SetOffset(ui.scroll, 0); Paint() end)
    ui.search = search
    -- (el filtro de hermandad: un botón que dice «Todas» o las elegidas; al pulsarlo, una casilla por hermandad)
    ui.tagBtn = DJ.Button(body, "", 150, 22)
    ui.tagBtn:SetPoint("LEFT", search, "RIGHT", 10, 0)
    function ui.tagBtn.Paint()
        local list = {}
        for tag in pairs(filterTags) do list[#list + 1] = tag end
        table.sort(list)
        local text
        if #list == 0 then text = L("Todas las hermandades")
        elseif #list <= 2 then
            local parts = {}
            for _, t in ipairs(list) do parts[#parts + 1] = TagText(t) end
            text = table.concat(parts, ", ")
        else text = string.format(L("%d hermandades"), #list) end
        ui.tagBtn:SetText(text)
    end
    ui.tagBtn:SetScript("OnClick", function(sb)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(sb, function(_, root)
            root:CreateCheckbox(L("Todas"), function() return not next(filterTags) end,
                function() filterTags = {}; FauxScrollFrame_SetOffset(ui.scroll, 0); Paint() end)
            root:CreateDivider()
            local tags = {}
            for tag in pairs(banks) do tags[#tags + 1] = tag end
            table.sort(tags)
            for _, tag in ipairs(tags) do
                root:CreateCheckbox(TagText(tag), function() return filterTags[tag] == true end,
                    function() filterTags[tag] = (not filterTags[tag]) or nil; FauxScrollFrame_SetOffset(ui.scroll, 0); Paint() end)
            end
        end)
    end)
    ui.ownBtn = DJ.Button(body, L("Todo"), 100, 22)
    ui.ownBtn:SetPoint("LEFT", search, "RIGHT", 10, 0)
    ui.ownBtn:SetScript("OnClick", function(sb)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(sb, function(_, root)
            root:CreateCheckbox(L("Todo"), function() return not next(ownSet) end,
                function() ownSet = {}; FauxScrollFrame_SetOffset(ui.scroll, 0); Paint() end)
            root:CreateDivider()
            for _, o in ipairs({ { "bank", L("Banco") }, { "bags", L("Bolsas") } }) do
                root:CreateCheckbox(o[2], function() return ownSet[o[1]] == true end,
                    function() ownSet[o[1]] = (not ownSet[o[1]]) or nil; FauxScrollFrame_SetOffset(ui.scroll, 0); Paint() end)
            end
        end)
    end)
    ui.hint = DJ.C(body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    ui.hint:SetPoint("LEFT", ui.tagBtn, "RIGHT", 10, 0); ui.hint:SetPoint("RIGHT", body, "RIGHT", -124, 0)
    ui.hint:SetJustifyH("LEFT"); ui.hint:SetWordWrap(false)
    ui.seen = DJ.C(body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), T.muted)
    ui.seen:SetPoint("LEFT", ui.ownBtn, "RIGHT", 10, 0)

    -- La rejilla de huecos, como un banco (con barra)
    local gridF = CreateFrame("Frame", nil, body, "BackdropTemplate")
    gridF:SetPoint("TOPLEFT", 12, -36); gridF:SetPoint("BOTTOMRIGHT", -12, 10)
    DJ.Panel(gridF, T.panel, T.border, 12, 3)
    ui.gridF = gridF
    local sf = CreateFrame("ScrollFrame", "GuildUnionBankScroll", gridF, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -8); sf:SetPoint("BOTTOMRIGHT", -30, 8)
    sf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, SLOT + GAP, Paint) end)
    ui.scroll = sf
    ui.cols, ui.rowsVisible = 13, 5
    ui.slots = {}
    for i = 1, 13 * 6 do
        local col, row = (i - 1) % 13, math.floor((i - 1) / 13)
        local b = CreateFrame("Button", nil, gridF)
        b:SetSize(SLOT, SLOT)
        b:SetPoint("TOPLEFT", sf, "TOPLEFT", col * (SLOT + GAP), -row * (SLOT + GAP))
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled"); bg:SetTexCoord(0.14, 0.86, 0.14, 0.86)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.ring = b:CreateTexture(nil, "OVERLAY"); b.ring:SetAllPoints()
        b.ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border"); b.ring:SetBlendMode("ADD")
        b.ring:SetTexCoord(0.2, 0.8, 0.2, 0.8)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); b.count:SetPoint("BOTTOMRIGHT", -3, 3)
        b.tag = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.tag:SetPoint("TOPLEFT", 2, -2)
        DJ.Big(b.tag, 8)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnEnter", function(s)
            if not s.it then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetItemByID, GameTooltip, s.it.id)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format(L("Cantidad: %d"), s.it.count), 1, 1, 1)
            if view == "guild" then
                GameTooltip:AddLine(L("Banco:") .. " " .. WhereText(s.it.tag, s.it.tab), 1, 1, 1)
                if CanRequest() then GameTooltip:AddLine(L("Clic: pedirlo."), 0, 1, 0) end
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(s)
            if not s.it then return end
            if IsModifiedClick("CHATLINK") then
                local _, link = ItemName(s.it.id)
                if link then ChatFrameUtil.InsertLink(link) end
                return
            end
            if view == "guild" and CanRequest() then ui.ask.Open(s.it) end
        end)
        ui.slots[i] = b
    end
    -- (cuántas filas caben: según el alto)
    sf:SetScript("OnSizeChanged", function(s)
        local h = s:GetHeight()
        if type(h) == "number" and h > 0 then ui.rowsVisible = math.max(1, math.min(6, math.floor((h + GAP) / (SLOT + GAP)))) end
        if ui:IsShown() then Paint() end
    end)
    ui.empty = DJ.C(gridF:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.muted)
    ui.empty:SetPoint("CENTER"); ui.empty:SetWidth(420)

    -- Solicitudes: registro (objeto, quién pide, banco y pestaña, estado: pendiente, sacado por, rechazada)
    local reqF = CreateFrame("Frame", nil, body, "BackdropTemplate")
    reqF:SetPoint("TOPLEFT", 12, -36); reqF:SetPoint("BOTTOMRIGHT", -12, 10)
    DJ.Panel(reqF, T.panel, T.border, 12, 3)
    ui.reqF = reqF
    local hdr = CreateFrame("Frame", nil, reqF)
    hdr:SetPoint("TOPLEFT", 8, -6); hdr:SetPoint("RIGHT", -30, 0); hdr:SetHeight(18)
    local function Head(text, x)
        local h = DJ.C(hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), T.title)
        h:SetPoint("LEFT", x, 0); h:SetText(text)
    end
    Head(L("Objeto"), 4); Head(L("Pide"), 210); Head(L("Banco"), 300); Head(L("Estado"), 410)
    local rsf = CreateFrame("ScrollFrame", "GuildUnionBankReqScroll", reqF, "FauxScrollFrameTemplate")
    rsf:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -2); rsf:SetPoint("RIGHT", hdr, "RIGHT"); rsf:SetHeight(REQ_ROWS * ROW_H)
    rsf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, Paint) end)
    ui.reqScroll = rsf
    ui.reqRows = {}
    for i = 1, REQ_ROWS do
        local row = CreateFrame("Button", nil, reqF)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", rsf, "TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("RIGHT", rsf, "RIGHT")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        if i % 2 == 0 then local st = row:CreateTexture(nil, "BACKGROUND"); st:SetAllPoints(); st:SetColorTexture(1, 1, 1, 0.04) end
        local function Cell(x, w)
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", x, 0); fs:SetWidth(w); fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
            return fs
        end
        row.item, row.who, row.tag, row.state = Cell(4, 200), Cell(210, 86), Cell(300, 106), Cell(410, 120)
        row.no = DJ.Button(row, L("Rechazar"), 76, 18); row.no:SetPoint("RIGHT", -2, 0)
        row.no:SetScript("OnClick", function()
            local r = row.r
            if r then
                r.state, r.noBy, r.noAt = "no", Me(), time()
                Log(string.format(L("%s rechaza %s (pedido por %s)"), Who(Me()), ReqText(r), Who(r.who)), r.test)
                Paint()
            end
        end)
        -- (al pasar el ratón: el registro completo)
        row:SetScript("OnEnter", function(s)
            local r = s.r
            if not r then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(L("Registro"))
            GameTooltip:AddLine(string.format(L("Pedido por %s el %s"), HU:Short(r.who), When(r.t)), 1, 1, 1)
            GameTooltip:AddLine(L("Banco:") .. " " .. WhereText(r.tag, r.tab), 1, 1, 1)
            if r.takenBy then GameTooltip:AddLine(string.format(L("Sacado por %s el %s"), HU:Short(r.takenBy), When(r.takenAt)), 0.25, 1, 0.25) end
            if r.noBy then GameTooltip:AddLine(string.format(L("Rechazada por %s el %s"), HU:Short(r.noBy), When(r.noAt)), 1, 0.3, 0.3) end
            if r.note and r.note ~= "" then GameTooltip:AddLine(L("Nota:") .. " " .. r.note, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ui.reqRows[i] = row
    end
    ui.reqEmpty = DJ.C(reqF:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.muted)
    ui.reqEmpty:SetPoint("CENTER"); ui.reqEmpty:SetText(L("No hay solicitudes."))
    -- (modo prueba: abrir la ventanita de sacar sin estar en el banco de hermandad)
    ui.simBtn = DJ.Button(reqF, L("Probar: abrir el banco de hermandad"), 230, 22)
    ui.simBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    ui.simBtn:SetScript("OnClick", ShowWithdraw)

    -- Registro: lo que ha pasado (pedido, sacado, rechazado), una línea cada cosa, la más nueva abajo
    local logF = CreateFrame("Frame", nil, body, "BackdropTemplate")
    logF:SetPoint("TOPLEFT", 12, -36); logF:SetPoint("BOTTOMRIGHT", -12, 10)
    DJ.Panel(logF, T.panel, T.border, 12, 3)
    ui.logF = logF
    local msgs = CreateFrame("ScrollingMessageFrame", nil, logF)
    msgs:SetPoint("TOPLEFT", 10, -8); msgs:SetPoint("BOTTOMRIGHT", -10, 8)
    msgs:SetFontObject(GameFontHighlightSmall); msgs:SetJustifyH("LEFT")
    msgs:SetFading(false); msgs:SetMaxLines(500); msgs:SetInsertMode("BOTTOM")
    msgs:EnableMouseWheel(true)
    msgs:SetScript("OnMouseWheel", function(sm, delta) if delta > 0 then sm:ScrollUp() else sm:ScrollDown() end end)
    msgs:SetHyperlinksEnabled(true)
    msgs:SetScript("OnHyperlinkClick", function(_, link, text, button) SetItemRef(link, text, button) end)
    ui.logMsgs = msgs
    ui.logEmpty = DJ.C(logF:CreateFontString(nil, "OVERLAY", "GameFontNormal"), T.muted)
    ui.logEmpty:SetPoint("CENTER"); ui.logEmpty:SetText(L("Todavía no ha pasado nada."))
    msgs:SetPoint("BOTTOMRIGHT", -10, 36)
    -- (abajo a la izquierda de Solicitudes, verde como «+ Nuevo evento»: ver el registro y volver)
    ui.logBtn = DJ.Button(body, L("Ver registro"), 160, 22)
    ui.logBtn:SetPoint("BOTTOMLEFT", reqF, "BOTTOMLEFT", 8, 8)
    ui.logBtn:SetFrameLevel(math.max(reqF:GetFrameLevel(), logF:GetFrameLevel()) + 5)
    for _, k in ipairs({ "Left", "Middle", "Right" }) do if ui.logBtn[k] then ui.logBtn[k]:SetVertexColor(0.45, 1, 0.45) end end
    ui.logBtn:SetNormalFontObject("GameFontHighlight")
    ui.logBtn:SetScript("OnClick", function() reqLog = not reqLog; Paint() end)

    ui.ask = BuildAsk(host)
    host:HookScript("OnShow", Paint)
    HU:Listen("CHANGED", function(what) if what == "unionCfg" then Paint() end end)
    Paint()
end

HU:Module("UnionBank", { "Config", "Core", "ListWindow", "Pinned", "UnionConfig" })
