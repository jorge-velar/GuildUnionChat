-- Guild Union Reduce - todo dentro de la ventana de hermandad de Blizzard: [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L

local tab, panel
local KEEP = 60                 -- últimas líneas de otras hermandades que se repintan al volver al chat
local recent = {}

local function Win() return _G.CommunitiesFrame end

-- ¿Está la ventana enseñando el chat general de mi hermandad?
local function GuildChatShown()
    local f = Win()
    if not (f and f:IsShown() and f.Chat and f.Chat:IsShown() and f.Chat.MessageFrame) then return false end
    local clubId = f.GetSelectedClubId and f:GetSelectedClubId()
    local streamId = f.GetSelectedStreamId and f:GetSelectedStreamId()
    if not (clubId and streamId and C_Club) then return false end
    local ok, info = pcall(C_Club.GetClubInfo, clubId)
    if not ok or not info or info.clubType ~= Enum.ClubType.Guild then return false end
    local ok2, s = pcall(C_Club.GetStreamInfo, clubId, streamId)
    return ok2 and s and s.streamType == Enum.ClubStreamType.Guild or false
end

---------------------------------------------------------------------------
-- El chat de las otras hermandades en el chat de la ventana
---------------------------------------------------------------------------
local function AddToWindow(line, r, g, b)
    if not GuildChatShown() then return end
    pcall(Win().Chat.MessageFrame.AddMessage, Win().Chat.MessageFrame, line, r, g, b)
end

local origDisplay = HU.Display
function HU:Display(kind, tag, author, msg, guid)
    origDisplay(self, kind, tag, author, msg, guid)
    if kind ~= "main" or not tag or tag == self.myTag then return end
    -- (sin «[Guild]» delante: en esta ventana las líneas de Blizzard tampoco lo llevan)
    local head, body = self:FormatLineParts(kind, tag, author, self:HighlightMentions(msg), guid, true)
    local line = head .. body
    local r, g, b = self:KindColor(kind)
    recent[#recent + 1] = { line, r, g, b, t = (GetServerTime and GetServerTime()) or time() }
    if #recent > KEEP then table.remove(recent, 1) end
    AddToWindow(line, r, g, b)
end

-- Cuando Blizzard rehace su chat (al abrir la ventana o cambiar de canal), borra lo nuestro. Para [+ARCHITECTURE.md]
local rebuild   -- { epochs = {...}, k = 0, ptr = 1 } mientras Blizzard repinta
local function PutOurs(mf, upto)
    while rebuild.ptr <= #recent and recent[rebuild.ptr].t * 1000000 < upto do
        local e = recent[rebuild.ptr]
        pcall(mf.AddMessage, mf, e[1], e[2], e[3], e[4])
        rebuild.ptr = rebuild.ptr + 1
    end
end
local function OnClear()
    rebuild = nil
    if not GuildChatShown() or #recent == 0 then return end
    local chat = Win().Chat
    local ok, msgs = pcall(chat.GetMessagesToDisplay, chat)
    local epochs = {}
    for i, m in ipairs(ok and msgs or {}) do epochs[i] = m.messageId and m.messageId.epoch or 0 end
    rebuild = { epochs = epochs, k = 0, ptr = 1 }
    -- (lo nuestro más viejo que su primer mensaje, arriba del todo)
    PutOurs(chat.MessageFrame, epochs[1] or math.huge)
end
local function OnBlizzLine(_, _, _, _, backfill)
    if not rebuild or backfill then return end
    rebuild.k = rebuild.k + 1
    PutOurs(Win().Chat.MessageFrame, rebuild.epochs[rebuild.k + 1] or math.huge)
end
---------------------------------------------------------------------------
-- Mensaje fijado de los oficiales: una franja arriba del chat de la ventana (solo en el chat de la
-- hermandad). Los mensajes del chat bajan lo que mida la franja.
---------------------------------------------------------------------------
local pinBar
local PIN_BG, PIN_FLASH = { 0.30, 0.20, 0.04, 0.92 }, { 0.55, 0.38, 0.06, 0.97 }
local function UpdatePinBar()
    local f = Win()
    if not (f and f.Chat and f.Chat.MessageFrame) then return end
    local mf = f.Chat.MessageFrame
    if not pinBar then
        pinBar = CreateFrame("Frame", "GuildUnionPinBar", f.Chat, "BackdropTemplate")
        pinBar:SetPoint("TOPLEFT", f.Chat, "TOPLEFT", -4, 2)
        pinBar:SetPoint("TOPRIGHT", f.Chat, "TOPRIGHT", 8, 2)
        pinBar:SetFrameLevel(mf:GetFrameLevel() + 5)
        if pinBar.SetBackdrop then
            pinBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            pinBar:SetBackdropColor(unpack(PIN_BG))
            pinBar:SetBackdropBorderColor(1, 0.82, 0.1, 1)
        end
        pinBar.icon = pinBar:CreateTexture(nil, "ARTWORK")
        pinBar.icon:SetSize(16, 16)
        pinBar.icon:SetPoint("TOPLEFT", pinBar, "TOPLEFT", 8, -6)
        pinBar.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_02")
        pinBar.text = pinBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        pinBar.text:SetPoint("TOPLEFT", pinBar.icon, "TOPRIGHT", 6, -1)
        pinBar.text:SetPoint("RIGHT", pinBar, "RIGHT", -8, 0)
        pinBar.text:SetJustifyH("LEFT")
        pinBar.text:SetWordWrap(true)
        pinBar.text:SetTextColor(1, 0.86, 0.45)
    end
    -- (/gu test: una franja de prueba solo en mi ventana, que no se manda ni se guarda)
    local p = HU.pinPreview or (HU.db and HU.db.pinned)
    local show = p and (p.text or "") ~= "" and GuildChatShown()
    if show then
        local who = HU:Nice(p.author or "?") .. ((p.tag and p.tag ~= HU.myTag) and (" <" .. p.tag .. ">") or "")
        pinBar.text:SetText(p.text .. "  |cffa89f8a— " .. who .. ", " .. HU.SafeDate("%d/%m %H:%M", p.t) .. "|r")
        local h = math.max(28, math.floor((pinBar.text:GetStringHeight() or 14) + 14))
        pinBar:SetHeight(h)
        pinBar:Show()
        mf:ClearAllPoints()
        mf:SetPoint("TOPLEFT", f.Chat, "TOPLEFT", 0, -(h + 2))
        mf:SetPoint("BOTTOMRIGHT", f.Chat, "BOTTOMRIGHT", 0, 0)
    else
        pinBar:Hide()
        mf:ClearAllPoints()
        mf:SetPoint("TOPLEFT", f.Chat, "TOPLEFT", 0, 0)
        mf:SetPoint("BOTTOMRIGHT", f.Chat, "BOTTOMRIGHT", 0, 0)
    end
end
-- (al abrir, el ancho aún no está calculado y el alto del texto sale mal: se repite un instante después)
local function UpdatePinBarSoon() UpdatePinBar(); HU.After(0.05, UpdatePinBar) end
local function PinChanged() HU:SafeCall("fijado", UpdatePinBarSoon) end
if HU.UI then
    HU.UI.UpdatePinned = PinChanged
    HU.UI.FlashPinned = function()
        if not (pinBar and pinBar:IsShown() and pinBar.SetBackdropColor) then return end
        pinBar:SetBackdropColor(unpack(PIN_FLASH))
        HU.After(1.2, function() if pinBar.SetBackdropColor then pinBar:SetBackdropColor(unpack(PIN_BG)) end end)
    end
end

local function Repaint()
    if rebuild then PutOurs(Win().Chat.MessageFrame, math.huge) end
    rebuild = nil
end

---------------------------------------------------------------------------
-- La pestaña
---------------------------------------------------------------------------
local function Whisper(name)
    local target = HU:FullName(name) or name
    if ChatFrame_SendTell then pcall(ChatFrame_SendTell, target)
    elseif ChatFrameUtil and ChatFrameUtil.SendTell then pcall(ChatFrameUtil.SendTell, target) end
end

-- Menú del clic derecho sobre un jugador (con el menú de Blizzard, MenuUtil): susurrar, invitar al
-- grupo, añadir amigo, ignorar y, para oficiales, silenciar. Son llamadas que el juego deja a los addons
local function PlayerMenu(owner, e)
    if not (e and MenuUtil and MenuUtil.CreateContextMenu) then return Whisper(e and e.name) end
    local target = HU:FullName(e.name) or e.name
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(HU:Nice(e.name))
        root:CreateButton(L("Susurrar"), function() Whisper(e.name) end)
        root:CreateButton(L("Invitar al grupo"), function()
            local fn = C_PartyInfo and C_PartyInfo.InviteUnit
            if fn then pcall(fn, target) end
        end)
        if C_FriendList and C_FriendList.AddFriend then
            root:CreateButton(L("Añadir a amigos"), function() pcall(C_FriendList.AddFriend, target) end)
        end
        if C_FriendList and C_FriendList.AddIgnore then
            root:CreateButton(L("Ignorar"), function() pcall(C_FriendList.AddIgnore, target) end)
        end
        if HU:CanPin() then
            root:CreateDivider()
            root:CreateButton(L("Silenciar 10 min"), function() HU:SetMute(e.name, 600, L("desde el menú")) end)
            root:CreateButton(L("Quitar silencio"), function() HU:SetMute(e.name, -1) end)
            root:CreateButton(L("Buscar lo que ha dicho"), function() HU:HistSearch(e.name, nil) end)
        end
    end)
end

local function Header(parent, text, anchor, y)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -14)
    h:SetText(text)
    return h
end

local function Box(parent, w, anchor, x, y)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 6, y or -6)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

local function Button(parent, text, w, anchor, x)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetPoint("LEFT", anchor, "RIGHT", x or 8, 0)
    return b
end

-- Lista de oficiales de las otras hermandades (la lista pequeña que va por dentro)
local ROW_H, ROWS = 18, 18
local function OfficerEntries(withOwn)
    local out = {}
    -- (los de mi hermandad, de la lista del juego: maestro y oficiales conectados)
    if withOwn and HU.myTag then
        for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
            local name, rank, ri, _, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
            if name and online and HU:RankRole(HU.myTag, ri) then
                out[#out + 1] = { name = name, tag = HU.myTag, rank = rank or "", class = class, online = true, ri = ri or 99 }
            end
        end
    end
    for _, tag in ipairs(HU:OtherTags()) do
        local r = HU.remoteRoster and HU.remoteRoster[tag]
        for _, e in ipairs(r and r.members or {}) do
            -- (solo los conectados: así se llama la lista)
            if e.online and HU:RankRole(tag, e.rankIndex) then
                local rank = (e.rank and e.rank ~= "") and e.rank or (e.rankIndex and HU:RankName(tag, e.rankIndex)) or ""
                out[#out + 1] = { name = e.name, tag = tag, rank = rank, class = e.class, online = e.online, ri = e.rankIndex or 99 }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online and true or false end
        -- (primero los de mi hermandad)
        if (a.tag == HU.myTag) ~= (b.tag == HU.myTag) then return a.tag == HU.myTag end
        if a.tag ~= b.tag then return tostring(a.tag) < tostring(b.tag) end
        if a.ri ~= b.ri then return a.ri < b.ri end
        return a.name < b.name
    end)
    return out
end

local function RefreshOfficers()
    if not (panel and panel:IsShown()) then return end
    local list = OfficerEntries(true)
    local sf = panel.offScroll
    FauxScrollFrame_Update(sf, #list, ROWS, ROW_H)
    local off = FauxScrollFrame_GetOffset(sf)
    for i = 1, ROWS do
        local row, e = panel.offRows[i], list[off + i]
        if e then
            local c = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
            local hex = c and string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "ffffff"
            row.name:SetText("|cff" .. hex .. HU:Nice(e.name) .. "|r")
            -- (corona para el maestro, espadas para los oficiales; la etiqueta de la hermandad, corta)
            if e.ri == 0 then
                row.icon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon"); row.icon:SetTexCoord(0, 1, 0, 1)
            else
                row.icon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon"); row.icon:SetTexCoord(34 / 64, 62 / 64, 2 / 64, 30 / 64)
            end
            -- (la etiqueta; si mi hermandad aún no tiene, su nombre)
            local gtxt = e.tag or (IsInGuild() and GetGuildInfo("player")) or ""
            row.guild:SetText("|cff" .. HU:GuildColorHex(e.tag) .. gtxt .. "|r")
            row.rank:SetText(e.rank)
            row.name:SetAlpha(e.online and 1 or 0.45)
            row.entry = e
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    panel.offEmpty:SetShown(#list == 0)
end

local function RefreshStatus()
    if not panel then return end
    local chan = HU.IsJoined and HU:IsJoined("main")
    local relay = (HU.IsRelay and HU:IsRelay()) and L("tú") or (HU.RelayName and HU:RelayName()) or "?"
    local n = #HU:OtherTags()
    panel.status:SetText(
        L("Canal: ") .. (chan and "|cff44ff44" .. L("conectado") .. "|r" or "|cffff4444" .. L("sin conectar") .. "|r")
        .. "    " .. L("Enlace: ") .. "|cffffffff" .. HU:Nice(relay) .. "|r"
        .. "    " .. L("Hermandades unidas: ") .. "|cffffffff" .. n .. "|r")
    local officer = HU:CanPin()
    for _, f in ipairs(panel.officerOnly) do f:SetShown(officer) end
    panel.ecoBtn:SetShown(HU:IsMaster())
    panel.ecoBtn:SetText((HU.cfg and HU.cfg.echo) and L("Eco: quitar") or L("Eco: poner"))
end

local function ShowPanel(on)
    if not panel then return end
    panel:SetShown(on)
    tab:SetChecked(on)
    if on then RefreshStatus(); RefreshOfficers() end
end

local function BuildPanel(f)
    panel = CreateFrame("Frame", "GuildUnionReducePanel", f, "InsetFrameTemplate")
    -- (tapa toda la zona de contenido: chat y lista de miembros de la derecha. Por encima de todo lo
    -- de la ventana —su texto del chat se pintaba encima— y con fondo opaco)
    panel:SetPoint("TOPLEFT", f.Chat, "TOPLEFT", -6, 6)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 28)
    -- (DIALOG: la ventana de hermandad ya va en HIGH y su chat quedaba por encima)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:EnableMouse(true)
    panel:Hide()
    local bg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.05, 1)
    if panel.Bg then panel.Bg:SetAlpha(1) end
    panel.officerOnly = {}

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("GuildUnion Reduce" .. (HU.REDUCE_VERSION and (" " .. HU.REDUCE_VERSION) or ""))
    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    panel.status:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    panel.status:SetJustifyH("LEFT")
    -- (la columna izquierda no pasa de la mitad, para no pisar la de los oficiales)
    local mid = panel:CreateTexture(nil, "ARTWORK")
    mid:SetColorTexture(1, 1, 1, 0.08)
    mid:SetWidth(1)
    mid:SetPoint("TOP", panel, "TOP", 0, -66)
    mid:SetPoint("BOTTOM", panel, "BOTTOM", 0, 10)

    -- Columna izquierda: buscar, silenciar y ajustes (oficiales)
    local h1 = Header(panel, L("Buscar en el chat"), panel.status, -16)
    local qText = Box(panel, 160, h1)
    local b1 = Button(panel, L("Buscar"), 70, qText)
    b1:SetScript("OnClick", function() HU:HistSearch(nil, qText:GetText()) end)
    qText:SetScript("OnEnterPressed", function(s) s:ClearFocus(); HU:HistSearch(nil, s:GetText()) end)

    local h2 = Header(panel, L("Buscar jugador"), qText, -12)
    h2:SetPoint("TOPLEFT", qText, "BOTTOMLEFT", -6, -12)
    local qName = Box(panel, 160, h2)
    local b2 = Button(panel, L("Buscar"), 70, qName)
    b2:SetScript("OnClick", function() HU:HistSearch(qName:GetText(), nil) end)
    qName:SetScript("OnEnterPressed", function(s) s:ClearFocus(); HU:HistSearch(s:GetText(), nil) end)

    local h3 = Header(panel, L("Silenciar"), qName, -12)
    h3:SetPoint("TOPLEFT", qName, "BOTTOMLEFT", -6, -12)
    local mName = Box(panel, 120, h3)
    local mName2 = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mName2:SetPoint("BOTTOMLEFT", mName, "TOPLEFT", 120, 2)
    mName2:SetText(L("nombre"))
    local mMin = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    mMin:SetSize(40, 20); mMin:SetAutoFocus(false); mMin:SetNumeric(true)
    mMin:SetPoint("LEFT", mName, "RIGHT", 10, 0)
    mMin:SetText("10")
    local mMinL = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mMinL:SetPoint("LEFT", mMin, "RIGHT", 4, 0)
    mMinL:SetText(L("min"))
    local mWhy = Box(panel, 180, mName)
    mWhy:SetPoint("TOPLEFT", mName, "BOTTOMLEFT", 0, -8)
    local mWhyL = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mWhyL:SetPoint("LEFT", mWhy, "RIGHT", 6, 0)
    mWhyL:SetText(L("motivo"))
    local bMute = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    bMute:SetSize(110, 22); bMute:SetText(L("Silenciar"))
    bMute:SetPoint("TOPLEFT", mWhy, "BOTTOMLEFT", -6, -8)
    bMute:SetScript("OnClick", function()
        local mins = tonumber(mMin:GetText()) or 10
        HU:SetMute(mName:GetText(), mins * 60, mWhy:GetText())
    end)
    local bUnmute = Button(panel, L("Quitar"), 80, bMute)
    bUnmute:SetScript("OnClick", function() HU:SetMute(mName:GetText(), -1) end)
    HU:NameSuggest(qName)
    HU:NameSuggest(mName)
    for _, w in ipairs({ h1, qText, b1, h2, qName, b2, h3, mName, mName2, mMin, mMinL, mWhy, mWhyL, bMute, bUnmute }) do
        panel.officerOnly[#panel.officerOnly + 1] = w
    end

    -- Ajustes (para todos) y eco (el maestro)
    local h4 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h4:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 44)
    h4:SetText(L("Ajustes"))
    local bTabs = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    bTabs:SetSize(190, 22); bTabs:SetText(L("Pestaña del chat GuildUnion"))
    bTabs:SetPoint("TOPLEFT", h4, "BOTTOMLEFT", -2, -6)
    bTabs:SetScript("OnClick", function() if HU.CreateChatTabs then HU:CreateChatTabs() end end)
    panel.ecoBtn = Button(panel, L("Eco: poner"), 110, bTabs)
    panel.ecoBtn:SetScript("OnClick", function()
        if HU.EchoCommand then HU:EchoCommand((HU.cfg and HU.cfg.echo) and "off" or "on") end
        RefreshStatus()
    end)

    -- Columna derecha: oficiales de las otras hermandades
    local h5 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- (debajo de la línea de estado, que ocupa todo el ancho: antes se pisaban)
    h5:SetPoint("TOPLEFT", panel, "TOP", 10, -70)
    h5:SetText(L("Oficiales conectados"))
    -- (cabecera de columnas, como la lista de miembros de Blizzard)
    -- (anchos que caben en media ventana: antes «Hermandad» se salía por la derecha)
    local COL_NAME, COL_RANK = 118, 78
    local hdr = CreateFrame("Frame", nil, panel)
    hdr:SetHeight(16)
    hdr:SetPoint("TOPLEFT", h5, "BOTTOMLEFT", 0, -6)
    hdr:SetPoint("RIGHT", panel, "RIGHT", -30, 0)
    local hbg = hdr:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints(); hbg:SetColorTexture(1, 1, 1, 0.06)
    local function Col(text, x)
        local c = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        c:SetPoint("LEFT", x, 0); c:SetText(text)
    end
    Col(L("Nombre"), 22); Col(L("Rango"), 22 + COL_NAME); Col(L("Herm."), 22 + COL_NAME + COL_RANK)
    local sf = CreateFrame("ScrollFrame", "GuildUnionReduceOffScroll", panel, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -2)
    sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)
    sf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, RefreshOfficers) end)
    panel.offScroll = sf
    panel.offRows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, panel)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", sf, "RIGHT", 0, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        -- (filas alternas, una línea cada columna, sin cortes)
        if i % 2 == 0 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints(); stripe:SetColorTexture(1, 1, 1, 0.03)
        end
        row.icon = row:CreateTexture(nil, "OVERLAY")
        row.icon:SetSize(14, 14)
        row.icon:SetPoint("LEFT", 4, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 22, 0)
        row.name:SetWidth(COL_NAME - 4); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.rank:SetPoint("LEFT", 22 + COL_NAME, 0)
        row.rank:SetWidth(COL_RANK - 4); row.rank:SetJustifyH("LEFT"); row.rank:SetWordWrap(false)
        row.rank:SetTextColor(0.75, 0.75, 0.75)
        row.guild = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.guild:SetPoint("LEFT", 22 + COL_NAME + COL_RANK, 0)
        row.guild:SetPoint("RIGHT", row, "RIGHT", -4, 0); row.guild:SetJustifyH("LEFT"); row.guild:SetWordWrap(false)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(s, button)
            if not s.entry then return end
            if button == "RightButton" then PlayerMenu(s, s.entry) else Whisper(s.entry.name) end
        end)
        row:SetScript("OnEnter", function(s)
            if not s.entry then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(HU:Nice(s.entry.name))
            GameTooltip:AddLine(HU:GuildName(s.entry.tag) .. " · " .. s.entry.rank, 1, 1, 1)
            GameTooltip:AddLine(s.entry.online and L("Conectado") or L("Desconectado"), 0.6, 0.6, 0.6)
            GameTooltip:AddLine(L("Clic: susurrar · Clic derecho: más"), 0, 1, 0)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.offRows[i] = row
    end
    panel.offEmpty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.offEmpty:SetPoint("TOPLEFT", sf, "TOPLEFT", 4, -4)
    panel.offEmpty:SetText(L("Todavía no ha llegado ninguno."))
    panel:SetScript("OnShow", function()
        -- (se pide la lista de la hermandad al juego: si no, puede estar vieja y faltar alguien, como el maestro)
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        RefreshStatus(); RefreshOfficers()
    end)
    panel:RegisterEvent("GUILD_ROSTER_UPDATE")
    panel:SetScript("OnEvent", function() RefreshOfficers() end)
end

---------------------------------------------------------------------------
-- Buscador de personajes en la pestaña de miembros de Blizzard, junto a su filtro (como el de [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local ACCENTS = { ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n",
    ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ü"] = "u", ["Ñ"] = "n" }
local function Fold(s)
    s = tostring(s or ""):lower()
    for a, b in pairs(ACCENTS) do s = s:gsub(a, b) end
    return s
end

-- ¿Encaja el nombre con lo escrito, en orden? Tiene que empezar por ello el nombre (2) o el
-- apellido (1): «ma» encuentra «Masomenos Furra» y «Monaguillo Mamut», pero no «Rast Rero»
local function Match(name, q)
    local n = Fold(HU:Nice(name))
    if n:sub(1, #q) == q then return 2 end
    for word in n:gmatch("%s(%S+)") do
        if word:sub(1, #q) == q then return 1 end
    end
    -- (si escribe nombre y apellido con espacio, también vale tal cual)
    if q:find(" ", 1, true) and n:sub(1, #q) == q then return 2 end
    return nil
end

local function FindChars(query)
    local q = Fold(HU.Trim(query or ""))
    local out = {}
    if #q < 1 then return out end
    for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local name, rank, _, level, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
        local m = name and Match(name, q)
        if m then
            out[#out + 1] = { name = name, rank = rank or "", level = level, online = online, class = class, tag = HU.myTag, own = true, m = m }
        end
    end
    for _, e in ipairs(OfficerEntries()) do
        local m = Match(e.name, q)
        if m then
            out[#out + 1] = { name = e.name, rank = e.rank, online = true, class = e.class, tag = e.tag, m = m }
        end
    end
    -- (primero TODOS los conectados y luego los desconectados, sin mezclarlos; dentro de cada grupo,
    -- primero los que empiezan por ello en el nombre y luego en el apellido)
    table.sort(out, function(a, b)
        if (a.online and true or false) ~= (b.online and true or false) then return a.online and true or false end
        if a.m ~= b.m then return a.m > b.m end
        return HU:Nice(a.name) < HU:Nice(b.name)
    end)
    return out
end

---------------------------------------------------------------------------
-- Sugerencias de nombres al escribir en un cuadro (mi hermandad y todos los de las listas de las otras)
---------------------------------------------------------------------------
local SUGG_MAX = 8
local function FindNames(query)
    local q = Fold(HU.Trim(query or ""))
    local out, seen = {}, {}
    if #q < 1 then return out end
    local function add(name, class, tag, online)
        local k = HU:Key(name) or ""
        local m = not seen[k] and Match(name, q)
        if m then seen[k] = true; out[#out + 1] = { name = name, class = class, tag = tag, online = online, m = m } end
    end
    for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local name, _, _, _, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
        if name then add(name, class, HU.myTag, online) end
    end
    for _, tag in ipairs(HU:OtherTags()) do
        local r = HU.remoteRoster and HU.remoteRoster[tag]
        for _, e in ipairs(r and r.members or {}) do
            if e.name then add(e.name, e.class, tag, e.online) end
        end
    end
    table.sort(out, function(a, b)
        if (a.online and true or false) ~= (b.online and true or false) then return a.online and true or false end
        if a.m ~= b.m then return a.m > b.m end
        return HU:Nice(a.name) < HU:Nice(b.name)
    end)
    return out
end

local sugg
local function SuggFrame()
    if sugg then return sugg end
    sugg = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    sugg:SetFrameStrata("FULLSCREEN_DIALOG")
    sugg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    sugg:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
    sugg.rows = {}
    for i = 1, SUGG_MAX do
        local b = CreateFrame("Button", nil, sugg)
        b:SetHeight(16)
        b:SetPoint("TOPLEFT", 6, -5 - (i - 1) * 16)
        b:SetPoint("RIGHT", -6, 0)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 2, 0)
        b.text:SetPoint("RIGHT", -2, 0)
        b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self)
            local box = sugg.owner
            if box then box:SetText(HU:Nice(self.name)); box:SetCursorPosition(#box:GetText()) end
            sugg:Hide()
        end)
        sugg.rows[i] = b
    end
    sugg:Hide()
    return sugg
end

local function ShowSuggestions(box)
    local f = SuggFrame()
    local list = FindNames(box:GetText())
    if #list == 0 or (#list == 1 and Fold(HU:Nice(list[1].name)) == Fold(HU.Trim(box:GetText()))) then f:Hide(); return end
    f.owner = box
    local n = math.min(SUGG_MAX, #list)
    for i, b in ipairs(f.rows) do
        local e = list[i]
        if i <= n then
            local r, g, bl = HU.ClassRGB(e.class)
            local hex = r and string.format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(bl * 255)) or "ff9933"
            local where = (e.tag and e.tag ~= HU.myTag) and ("  |cff" .. HU:GuildColorHex(e.tag) .. "<" .. e.tag .. ">|r") or ""
            b.text:SetText("|cff" .. hex .. HU:Nice(e.name) .. "|r" .. where .. (e.online and "" or "  |cff808080·|r"))
            b.name = e.name
            b:Show()
        else
            b:Hide()
        end
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -2)
    f:SetSize(math.max(200, box:GetWidth() + 40), 10 + n * 16)
    f:Show()
end

-- Engancha las sugerencias a un cuadro: aparecen al escribir; clic o Tab para coger una
function HU:NameSuggest(box)
    if not box or box.guSuggest then return end
    box.guSuggest = true
    local function close() if sugg and sugg.owner == box then sugg:Hide() end end
    box:HookScript("OnTextChanged", function(_, user) if user then ShowSuggestions(box) end end)
    box:HookScript("OnTabPressed", function()
        if sugg and sugg:IsShown() and sugg.owner == box and sugg.rows[1]:IsShown() then sugg.rows[1]:Click() end
    end)
    box:HookScript("OnEnterPressed", close)
    box:HookScript("OnEscapePressed", close)
    -- (con un poco de margen: si se pierde el foco por hacer clic en una sugerencia, que el clic llegue)
    box:HookScript("OnEditFocusLost", function()
        HU.After(0.2, function() if not box:HasFocus() then close() end end)
    end)
    box:HookScript("OnHide", close)
end

-- lleva la lista de Blizzard hasta ese miembro (si se ve en ella), sin tocar sus datos
local ScrollTo
ScrollTo = function(name)
    local f = Win()
    local box = f and f.MemberList and f.MemberList.ScrollBox
    if not (box and box.ScrollToElementDataByPredicate) then return end
    local k = HU:Key(name)
    local function IsHim(data)
        local info = type(data) == "table" and data.memberInfo
        return info and info.name and HU:Key(info.name) == k or false
    end
    -- (desconectado y la lista no enseña desconectados: no se marca la casilla desde el addon —eso [+ARCHITECTURE.md]
    local found = box.FindElementDataByPredicate and select(2, pcall(box.FindElementDataByPredicate, box, IsHim))
    local chk = f.MemberList.ShowOfflineButton
    if not found and chk and chk:IsShown() and not chk:GetChecked() then
        HU.pendingFind = name
        if not chk.guFlash then
            chk.guFlash = chk:CreateTexture(nil, "OVERLAY")
            chk.guFlash:SetTexture("Interface\\Buttons\\CheckButtonHilight")
            chk.guFlash:SetBlendMode("ADD")
            chk.guFlash:SetAllPoints()
            chk:HookScript("OnClick", function(s)
                if s.guFlash then s.guFlash:Hide() end
                local who = HU.pendingFind
                HU.pendingFind = nil
                if who and s:GetChecked() then HU.After(0.3, function() ScrollTo(who) end) end
            end)
        end
        chk.guFlash:Show()
        HU:Print(HU:Nice(name) .. L(" está desconectado: marca «Show Offline Members» (brilla) y te llevo a él."))
        return
    end
    pcall(box.ScrollToElementDataByPredicate, box, IsHim, ScrollBoxConstants and ScrollBoxConstants.AlignCenter or 0.5)
    -- (su fila se resalta unos segundos, como seleccionada. No se usa la selección de Blizzard: si
    -- la pone un addon, sus botones de ascender o expulsar quedan bloqueados)
    HU.After(0.05, function()
        if not box.FindFrameByPredicate then return end
        local ok, row = pcall(box.FindFrameByPredicate, box, function(fr, data) return IsHim(data or (fr and fr.GetElementData and fr:GetElementData())) end)
        if not ok or not row then return end
        local hl = _G.GuildUnionReduceHL
        if not hl then
            hl = CreateFrame("Frame", "GuildUnionReduceHL", f)
            local t = hl:CreateTexture(nil, "OVERLAY")
            t:SetAllPoints(); t:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); t:SetBlendMode("ADD")
            t:SetVertexColor(1, 0.85, 0.2, 0.9)
        end
        hl:SetParent(row)
        hl:ClearAllPoints(); hl:SetAllPoints(row)
        hl:SetFrameLevel(row:GetFrameLevel() + 5)
        hl:Show()
        hl.token = (hl.token or 0) + 1
        local mine = hl.token
        HU.After(6, function() if hl.token == mine then hl:Hide() end end)
    end)
end

local search
local function BuildCharSearch(f)
    local ml = f.MemberList
    local anchor = ml and ml.ShowOfflineButton
    if search or not anchor then return end
    local box = CreateFrame("EditBox", "GuildUnionReduceSearch", f, "SearchBoxTemplate")
    search = box
    box:SetSize(170, 20)
    box:SetFrameLevel(anchor:GetFrameLevel() + 2)
    if box.Instructions then box.Instructions:SetText(L("Buscar personaje")) end
    local pop = CreateFrame("Frame", nil, box, "BackdropTemplate")
    pop:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2)
    pop:SetWidth(300)
    pop:SetFrameStrata("DIALOG")
    pop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    pop:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    pop:Hide()
    pop.rows = {}
    for i = 1, 10 do
        local r = CreateFrame("Button", nil, pop)
        r:SetHeight(18)
        r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 18)
        r:SetPoint("RIGHT", -6, 0)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.name = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", 4, 0)
        r.info = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        r.info:SetPoint("RIGHT", -4, 0)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(s, button)
            if not s.e then return end
            if button == "RightButton" then return PlayerMenu(s, s.e) end
            pop:Hide(); box:ClearFocus()
            if s.e.own then ScrollTo(s.e.name) else Whisper(s.e.name) end
        end)
        pop.rows[i] = r
    end
    pop.more = pop:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    local function Fill()
        local list = FindChars(box:GetText())
        if HU.Trim(box:GetText() or "") == "" then return pop:Hide() end
        local shown = math.min(#list, 10)
        for i, r in ipairs(pop.rows) do
            local e = list[i]
            r.e = e
            if e then
                local c = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
                r.name:SetText((c and ("|c" .. c.colorStr) or "|cffffffff") .. HU:Nice(e.name) .. "|r")
                local where = e.own and "" or ("|cff" .. HU:GuildColorHex(e.tag) .. HU:GuildName(e.tag) .. "|r  ·  ")
                r.info:SetText(where .. e.rank .. "  ·  " .. (e.online and "|cff40ff40" .. L("conectado") .. "|r" or L("desconectado")))
                r:Show()
            else
                r:Hide()
            end
        end
        pop.more:ClearAllPoints()
        if #list == 0 then
            pop.more:SetPoint("TOPLEFT", 10, -8)
            pop.more:SetText(L("Nadie con ese nombre."))
            pop.more:Show(); pop:SetHeight(28)
        elseif #list > shown then
            pop.more:SetPoint("TOPLEFT", 10, -8 - shown * 18)
            pop.more:SetText(string.format(L("y %d más: escribe más letras"), #list - shown))
            pop.more:Show(); pop:SetHeight(30 + shown * 18)
        else
            pop.more:Hide(); pop:SetHeight(12 + shown * 18)
        end
        pop:Show()
    end
    box:HookScript("OnTextChanged", Fill)
    -- (al empezar a buscar se pide la lista de la hermandad al juego, por si estaba vieja o vacía)
    box:HookScript("OnEditFocusGained", function()
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    end)
    box:RegisterEvent("GUILD_ROSTER_UPDATE")
    box:HookScript("OnEvent", function() if box:HasFocus() then Fill() end end)
    box:HookScript("OnEditFocusLost", function() HU.After(0.2, function() if not box:HasFocus() then pop:Hide() end end) end)
    box:SetScript("OnEscapePressed", function(s) s:SetText(""); pop:Hide(); s:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(s)
        local first = FindChars(s:GetText())[1]
        pop:Hide(); s:ClearFocus()
        if first then if first.own then ScrollTo(first.name) else Whisper(first.name) end end
    end)
    -- (en las dos vistas: en la de miembros, a la derecha de «Mostrar desconectados»; en la del
    -- chat, a la derecha del desplegable «Guild». Se recoloca al cambiar de vista)
    local dd = f.StreamDropdown
    local function Sync()
        box:ClearAllPoints()
        if anchor:IsShown() then
            box:SetPoint("BOTTOMRIGHT", ml, "TOPRIGHT", -24, 30)
            box:Show()
        elseif dd and dd:IsShown() then
            box:SetPoint("LEFT", dd, "RIGHT", 16, 0)
            box:Show()
        else
            box:Hide()
        end
    end
    for _, w in ipairs({ anchor, dd }) do
        if w then w:HookScript("OnShow", Sync); w:HookScript("OnHide", Sync) end
    end
    f:HookScript("OnShow", function() HU.After(0, Sync) end)
    Sync()
end

local function SyncTab()
    local f = Win()
    if not (f and tab) then return end
    -- (solo con la hermandad elegida: va debajo de su pestaña de Información)
    -- (ya no depende de que la configuración esté leída: al entrar tarda y la pestaña se quedaba escondida)
    local show = f.GuildInfoTab and f.GuildInfoTab:IsShown()
    tab:SetShown(show and true or false)
    if not show then ShowPanel(false) end
end

local function Setup()
    local f = Win()
    if tab or not f or not f.GuildInfoTab then return end
    tab = CreateFrame("CheckButton", "GuildUnionReduceTab", f, "CommunitiesFrameTabTemplate")
    tab:SetPoint("TOPLEFT", f.GuildInfoTab, "BOTTOMLEFT", 0, -20)
    tab.Icon:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
    tab.tooltip = "GuildUnion"
    -- (nuestro clic: no llama a SetDisplayMode de Blizzard)
    tab:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ShowPanel(not (panel and panel:IsShown()))
    end)
    -- (cada parte por separado: si una falla, las demás siguen y el fallo queda en /gu errores)
    HU:SafeCall("pestaña", BuildPanel, f)
    HU:SafeCall("buscador", BuildCharSearch, f)
    -- (al pulsar una pestaña suya o cambiar de vista, se cierra la nuestra)
    hooksecurefunc(f, "SetDisplayMode", function() ShowPanel(false) end)
    for _, key in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }) do
        if f[key] then f[key]:HookScript("OnClick", function() ShowPanel(false) end) end
    end
    if f.UpdateCommunitiesTabs then hooksecurefunc(f, "UpdateCommunitiesTabs", SyncTab) end
    f:HookScript("OnShow", SyncTab)
    f:HookScript("OnHide", function() ShowPanel(false) end)
    if f.Chat and f.Chat.DisplayChat then
        hooksecurefunc(f.Chat, "DisplayChat", Repaint)
        hooksecurefunc(f.Chat, "DisplayChat", PinChanged)
        f.Chat:HookScript("OnShow", PinChanged)
        f.Chat:HookScript("OnSizeChanged", PinChanged)
        if f.Chat.MessageFrame then hooksecurefunc(f.Chat.MessageFrame, "Clear", OnClear) end
        if f.Chat.AddMessage then hooksecurefunc(f.Chat, "AddMessage", OnBlizzLine) end
    end
    -- (abrirla con nuestra pestaña: si se acaba de pulsar el botón del minimapa, o con /gu tecla on)
    f:HookScript("OnShow", function() HU.After(0.1, function() if HU:WantsTab() then SyncTab(); if tab and tab:IsShown() then ShowPanel(true) end end end) end)
    -- (el botón del minimapa no cierra la ventana si ya está abierta: Minimap.lua)
    local function MinimapClick() if HU.UpdateMinimapClick then HU:UpdateMinimapClick() end end
    f:HookScript("OnShow", MinimapClick)
    f:HookScript("OnHide", MinimapClick)
    MinimapClick()
    SyncTab()
    if f:IsShown() and HU:WantsTab() then HU.After(0.1, function() SyncTab(); if tab and tab:IsShown() then ShowPanel(true) end end) end
    HU.NewTicker(5, function()
        if f:IsShown() then SyncTab() end
        if panel and panel:IsShown() then RefreshStatus(); RefreshOfficers() end
    end)
end

HU:On("ADDON_LOADED", function(name) if name == "Blizzard_Communities" then HU:SafeCall("ventana", Setup) end end)
HU:OnStart(function()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities")
    if loaded then Setup() end
end)

---------------------------------------------------------------------------
-- Sin panel grande: la ventana de hermandad la abre SIEMPRE el juego (la J o su botón de Hermandad; el
-- del minimapa es un botón seguro que pulsa ese, Minimap.lua). Si la abría el addon (ToggleGuildFrame
-- desde nuestro código), toda la ventana quedaba «contaminada» y el juego bloqueaba lo que solo puede
-- hacer su interfaz: cambiar el rango de un miembro (SetGuildRankOrder) o guardar una nota (SetNote).
---------------------------------------------------------------------------
-- ¿Hay que abrir la pestaña GuildUnion al abrirse la ventana? (botón del minimapa hace <1 s, o /gu tecla on)
function HU:WantsTab()
    return (self.tabWantedT and GetTime() - self.tabWantedT < 1) or (self.db and self.db.keyJ) or false
end
function HU:OpenReduce()
    local f = Win()
    -- (abierta: nuestra pestaña se abre y se cierra, sin tocar la ventana)
    if f and f:IsShown() then
        Setup(); SyncTab()
        if tab and tab:IsShown() then ShowPanel(not (panel and panel:IsShown())) end
        return
    end
    self:Print(L("Pulsa J (o el botón de Hermandad) para abrir la ventana de hermandad; la pestaña GuildUnion está a la derecha."))
end
-- Con la ventana ya abierta, el panel de GuildUnion (sin cerrarlo si ya está): clic izquierdo del minimapa
function HU:ShowReducePanel()
    local f = Win()
    if not (f and f:IsShown()) then return end
    Setup(); SyncTab()
    if tab and tab:IsShown() then ShowPanel(true) end
end
HU:OnStart(function()
    if HU.UI then
        HU.UI.Toggle = function() HU:OpenReduce() end
    end
end)
