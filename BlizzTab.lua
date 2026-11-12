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
    local mentioned = author and author:lower() ~= (self:MeKey() or "") and self:MentionsMe(msg, author, tag)
    local head, body = self:FormatLineParts(kind, tag, author, self:HighlightMentions(msg, author, tag), guid, true, nil, HU.MENTION_MARK[mentioned])
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

-- Clic derecho en la lista de miembros de Blizzard: las opciones de oficial de GuildUnion, al final
local function AddToGuildMemberMenu(_, root, ctx)
    local name = ctx and ctx.name
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) or ctx.isSelf or not HU:CanPin() then return end
    root:CreateDivider()
    root:CreateTitle("GuildUnion")
    root:CreateButton(L("Silenciar 10 min"), function() HU:SetMute(name, 600, L("desde el menú")) end)
    root:CreateButton(L("Quitar silencio"), function() HU:SetMute(name, -1) end)
    root:CreateButton(L("Buscar lo que ha dicho"), function() HU:HistSearch(name, nil) end)
end
HU:OnStart(function()
    if Menu and Menu.ModifyMenu then
        Menu.ModifyMenu("MENU_UNIT_COMMUNITIES_GUILD_MEMBER", function(...) HU:SafeCall("menú de miembro", AddToGuildMemberMenu, ...) end)
    end
end)

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
            -- (corona para el maestro, espadas rojas para el admin y normales para el oficial)
            if e.ri == 0 then
                row.icon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon"); row.icon:SetTexCoord(0, 1, 0, 1)
                row.icon:SetVertexColor(1, 1, 1)
            else
                row.icon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon"); row.icon:SetTexCoord(34 / 64, 62 / 64, 2 / 64, 30 / 64)
                if HU:IsAdminRank(e.tag, e.ri) then row.icon:SetVertexColor(unpack(HU.ADMIN_COLOR)) else row.icon:SetVertexColor(1, 1, 1) end
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
    -- (cuenta también la mía: con WLP, WLP2 y WLP3 son 3, no 2. Jorge, 12/11)
    local n = #HU:OtherTags() + (HU.myTag and 1 or 0)
    panel.status:SetText(
        L("Canal: ") .. (chan and "|cff44ff44" .. L("conectado") .. "|r" or "|cffff4444" .. L("sin conectar") .. "|r")
        .. "    " .. L("Enlace: ") .. "|cffffffff" .. HU:Nice(relay) .. "|r"
        .. "    " .. L("Hermandades unidas: ") .. "|cffffffff" .. n .. "|r")
    local officer = HU:CanPin()
    for _, f in ipairs(panel.officerOnly) do f:SetShown(officer) end
    panel.ecoBtn:SetShown(HU:IsMaster())
    panel.ecoBtn:SetText((HU.cfg and HU.cfg.echo) and L("Eco: quitar") or L("Eco: poner"))
    if panel.createBtn then
        local has = HU.myTag ~= nil
        panel.createBtn:SetText(has and L("Invitar a la comunidad") or L("Crear comunidad"))
        panel.createBtn:SetShown(has and HU:CanInvite() or (not has and IsInGuild() and HU:IsMaster()))
        panel.manageBtn:SetShown(has and officer)
    end
end

-- El panel es uno solo y vive en dos sitios (Jorge, 10/11): en la pestaña de la ventana de hermandad
-- de Blizzard (J) o en la ventana propia de GuildUnion (minimapa, /gu). La propia no es de Blizzard:
-- abrirla no «contamina» nada, así que cambiar rangos y notas sigue funcionando
local main
local function AttachBlizz()
    local f = Win()
    if not (panel and f and f.Chat) or panel.where == "blizz" then return end
    panel:SetParent(f)
    panel:ClearAllPoints()
    -- (tapa toda la zona de contenido: chat y lista de miembros de la derecha; y también la franja
    -- de arriba, la de los desplegables, el buscador y «N/M conectados»: lo que hay en ella depende
    -- de la pestaña de la que se venga y se quedaba a la vista, cada vez distinto. Jorge, 12/11.
    -- La barra del título, con la X, mide HEADER_TOP y no se tapa)
    local HEADER_TOP = 24
    local up = 6
    local top, chatTop = f:GetTop(), f.Chat:GetTop()
    if top and chatTop then up = math.max(6, math.min(80, (top - HEADER_TOP) - chatTop)) end
    panel:SetPoint("TOPLEFT", f.Chat, "TOPLEFT", -6, up)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 28)
    -- (DIALOG: la ventana de hermandad ya va en HIGH y su chat quedaba por encima)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel.where = "blizz"
    if main then main:Hide() end
end

local function ShowPanel(on)
    if not panel then return end
    -- (lo que cierra la pestaña de Blizzard no cierra la ventana propia)
    if not on and panel.where == "own" then
        if tab then tab:SetChecked(false) end
        return
    end
    if on then AttachBlizz() end
    panel:SetShown(on)
    if tab then tab:SetChecked(on) end
    if HU.SyncCharSearch then HU.SyncCharSearch() end
    if on then RefreshStatus(); RefreshOfficers() end
end

local function BuildPanel()
    panel = CreateFrame("Frame", "GuildUnionReducePanel", UIParent, "InsetFrameTemplate")
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
    -- (el nombre y la versión de verdad, la misma que CurseForge y /gu errores: Jorge, 10/11)
    title:SetText(HU.ADDON_TITLE .. " " .. tostring(HU.version))
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
    -- (Intro = pulsar «Buscar»: lo mismo, por el mismo botón)
    qText:SetScript("OnEnterPressed", function(s) s:ClearFocus(); b1:Click() end)

    local h2 = Header(panel, L("Buscar jugador"), qText, -12)
    h2:SetPoint("TOPLEFT", qText, "BOTTOMLEFT", -6, -12)
    local qName = Box(panel, 160, h2)
    local b2 = Button(panel, L("Buscar"), 70, qName)
    b2:SetScript("OnClick", function() HU:HistSearch(qName:GetText(), nil) end)
    qName:SetScript("OnEnterPressed", function(s) s:ClearFocus(); b2:Click() end)

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
    HU:NameSuggest(qName, function(s) s:ClearFocus(); b2:Click() end)
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
    -- Comunidad (arriba a la derecha): «Crear comunidad» sin comunidad (el maestro), «Invitar a la
    -- comunidad» con ella (principal y gestores), y «Gestionar comunidad» (oficiales)
    panel.manageBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.manageBtn:SetSize(150, 22); panel.manageBtn:SetText(L("Gestionar comunidad"))
    panel.manageBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -10)
    panel.manageBtn:SetScript("OnClick", function() if HU.ShowGuildsWindow then HU:ShowGuildsWindow() end end)
    panel.createBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.createBtn:SetSize(170, 22)
    panel.createBtn:SetPoint("RIGHT", panel.manageBtn, "LEFT", -6, 0)
    panel.createBtn:SetScript("OnClick", function() if HU.OpenWizard then HU:OpenWizard() end end)

    -- Columna derecha: oficiales de las otras hermandades
    local h5 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- (debajo de la línea de estado, que ocupa todo el ancho: antes se pisaban)
    h5:SetPoint("TOPLEFT", panel, "TOP", 10, -70)
    h5:SetText(L("Oficiales conectados"))
    -- Emoticonos sí/no (para todos), a la derecha del título
    local bEmotes = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    bEmotes:SetSize(130, 22)
    bEmotes:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -30, -64)
    local function EmotesText() bEmotes:SetText(HU.db.emotesOff and L("Emoticonos: no") or L("Emoticonos: sí")) end
    bEmotes:SetScript("OnClick", function()
        HU.db.emotesOff = not HU.db.emotesOff or nil
        EmotesText()
    end)
    bEmotes:SetScript("OnShow", EmotesText)
    EmotesText()
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
            -- (el cuadro puede pedir hacer algo al elegir, p. ej. buscar ya: «Buscar jugador»)
            if box and box.guOnPick then box.guOnPick(box) end
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
function HU:NameSuggest(box, onPick)
    if not box or box.guSuggest then return end
    box.guSuggest = true
    box.guOnPick = onPick
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

-- Marca a ese miembro en la lista de Blizzard SIN moverla: solo mira (ver ARCHITECTURE.md, «El buscador
-- no mueve la lista de Blizzard»)
local offFlash
-- Quita la marca y el aviso (al borrar lo escrito en el buscador)
local function ClearMark()
    local hl, arrow = _G.GuildUnionReduceHL, _G.GuildUnionReduceArrow
    if hl then
        if hl.ticker then hl.ticker:Cancel(); hl.ticker = nil end
        hl:Hide()
    end
    if arrow then arrow:Hide() end
    if _G.GuildUnionReduceNums then _G.GuildUnionReduceNums:Hide() end
    if offFlash then offFlash:Hide() end
    HU.pendingFind = nil
end
local ScrollTo
ScrollTo = function(name)
    local f = Win()
    local box = f and f.MemberList and f.MemberList.ScrollBox
    if not box then return end
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
        if not offFlash then
            offFlash = chk:CreateTexture(nil, "OVERLAY")
            offFlash:SetTexture("Interface\\Buttons\\CheckButtonHilight")
            offFlash:SetBlendMode("ADD")
            offFlash:SetAllPoints()
            chk:HookScript("OnClick", function(s)
                offFlash:Hide()
                local who = HU.pendingFind
                HU.pendingFind = nil
                if who and s:GetChecked() then HU.After(0.3, function() ScrollTo(who) end) end
            end)
        end
        offFlash:Show()
        HU:Print(HU:Nice(name) .. L(" está desconectado: marca «Show Offline Members» (brilla) y te lo marco."))
        return
    end
    -- (su fila se resalta, como seleccionada, mientras siga escrito lo que buscaste. No se usa la
    -- selección de Blizzard: si la pone un addon, sus botones de ascender o expulsar quedan bloqueados)
    local hl = _G.GuildUnionReduceHL
    if not hl then
        hl = CreateFrame("Frame", "GuildUnionReduceHL", f)
        local t = hl:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints(); t:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); t:SetBlendMode("ADD")
        t:SetVertexColor(1, 0.85, 0.2, 0.9)
    end
    -- aviso fijo en el borde de la lista hacia donde está, con su posición (solo se lee la lista, no se
    -- mueve). Con el borde de las fichas del juego, sin parpadear
    local arrow = _G.GuildUnionReduceArrow
    if not arrow then
        arrow = CreateFrame("Frame", "GuildUnionReduceArrow", f, "BackdropTemplate")
        arrow:SetSize(240, 28)
        arrow:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        arrow:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
        arrow:SetBackdropBorderColor(1, 0.82, 0, 0.9)
        arrow.icon = arrow:CreateTexture(nil, "OVERLAY")
        arrow.icon:SetSize(16, 16); arrow.icon:SetPoint("LEFT", 9, 0)
        arrow.text = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        arrow.text:SetPoint("LEFT", arrow.icon, "RIGHT", 6, 0)
    end
    -- (la lista estrecha de la vista del chat: solo la flecha; la ancha de Miembros: flecha y texto)
    local function Wide() return (box:GetWidth() or 0) >= 300 end
    local function ShowArrow(down, pos, total)
        arrow:ClearAllPoints()
        if down then
            arrow:SetPoint("BOTTOM", box, "BOTTOM", 0, 6)
            arrow.icon:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
        else
            arrow:SetPoint("TOP", box, "TOP", 0, -6)
            arrow.icon:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
        end
        -- (sin borde dorado: con él parecía un botón, y pulsarlo no puede hacer nada sin bloquear la
        -- lista. Solo un fondo oscuro suave con el texto, o la flecha sola en la lista estrecha)
        arrow:SetBackdropBorderColor(0, 0, 0, 0)
        if Wide() then
            arrow.text:SetText(string.format(L("%s: %s · %d de %d"), "|cffffd100" .. HU:Nice(name) .. "|r",
                down and L("más abajo") or L("más arriba"), pos, total))
            arrow.text:Show()
            arrow.icon:SetSize(16, 16)
            arrow:SetBackdropColor(0, 0, 0, 0.6)
            arrow:SetWidth(36 + arrow.text:GetStringWidth())
        else
            arrow.text:Hide()
            arrow.icon:SetSize(22, 22)
            arrow:SetBackdropColor(0, 0, 0, 0)
            arrow:SetWidth(34)
        end
        arrow:EnableMouse(false)
        arrow:SetFrameStrata(box:GetFrameStrata())
        arrow:SetFrameLevel(box:GetFrameLevel() + 20)
        arrow:Show()
    end
    local function HideArrow() arrow:Hide() end
    -- (dónde está en la lista y qué parte se ve: lecturas, sin tocar nada)
    local function Where()
        if not (box.FindElementDataIndexByPredicate and box.GetDataIndexBegin and box.GetDataIndexEnd) then return nil end
        local ok, idx = pcall(box.FindElementDataIndexByPredicate, box, IsHim)
        if not ok or not idx then return nil end
        local ok2, first = pcall(box.GetDataIndexBegin, box)
        local ok3, last = pcall(box.GetDataIndexEnd, box)
        local ok4, total = pcall(box.GetDataProviderSize, box)
        if not (ok2 and ok3 and first and last) then return nil end
        return idx, idx > last, (ok4 and total) or last
    end

    -- números de posición en las filas que se ven (solo en la lista ancha de Miembros), para que el
    -- «183 de 690» del aviso sirva de algo: Blizzard no los pone. Solo se leen las filas
    local nums = _G.GuildUnionReduceNums
    if not nums then
        nums = CreateFrame("Frame", "GuildUnionReduceNums", f)
        nums.fs = {}
    end
    local function ShowNumbers()
        local n = 0
        if Wide() and box.GetFrames and box.FindFrameElementDataIndex then
            local ok, frames = pcall(box.GetFrames, box)
            for _, fr in ipairs(ok and type(frames) == "table" and frames or {}) do
                local ok2, idx = pcall(box.FindFrameElementDataIndex, box, fr)
                if ok2 and idx and fr:IsVisible() then
                    n = n + 1
                    local fs = nums.fs[n]
                    if not fs then
                        fs = nums:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                        fs:SetJustifyH("RIGHT")
                        nums.fs[n] = fs
                    end
                    fs:ClearAllPoints()
                    fs:SetPoint("RIGHT", fr, "RIGHT", -8, 0)
                    fs:SetText(idx)
                    fs:Show()
                end
            end
        end
        for i = n + 1, #nums.fs do nums.fs[i]:Hide() end
        nums:SetFrameStrata(box:GetFrameStrata())
        nums:SetFrameLevel(box:GetFrameLevel() + 15)
        nums:SetShown(n > 0)
    end

    if hl.ticker then hl.ticker:Cancel() end
    local told = false
    local function Mark()
        ShowNumbers()
        local ok, row = false, nil
        if f:IsShown() and box.FindFrameByPredicate then
            ok, row = pcall(box.FindFrameByPredicate, box, function(fr, data) return IsHim(data or (fr and fr.GetElementData and fr:GetElementData())) end)
        end
        if not (ok and row) then
            hl:Hide()
            local pos, down, total
            if f:IsShown() then pos, down, total = Where() end
            if pos then
                ShowArrow(down, pos, total)
            else
                HideArrow()
                if found and not told and f:IsShown() then
                    told = true
                    HU:Print(HU:Nice(name) .. L(" está en la lista pero no se ve: baja con la rueda y lo verás marcado."))
                end
            end
            return
        end
        HideArrow()
        -- (pegado a su fila, sin meterse dentro de ella: las filas son de Blizzard)
        hl:ClearAllPoints(); hl:SetAllPoints(row)
        hl:SetFrameStrata(row:GetFrameStrata())
        hl:SetFrameLevel(row:GetFrameLevel() + 5)
        hl:Show()
    end
    Mark()
    -- (mientras su nombre siga en el buscador: lo quita ClearMark al borrarlo, al esconderse el
    -- buscador o al buscar a otro)
    hl.ticker = HU.NewTicker(0.25, function() if f:IsShown() then Mark() end end)
end

local search
-- Elegir a alguien en el buscador: de mi hermandad, se marca en la lista; de otra, solo se dice de
-- dónde es (antes se abría un susurro con él: Jorge, 10/11). Para susurrar, el clic derecho
local function Pick(e)
    if e.own then return ScrollTo(e.name) end
    HU:Print(string.format(L("%s es de %s: no sale en esta lista. Clic derecho en su nombre para susurrarle."),
        HU:Nice(e.name), "|cff" .. HU:GuildColorHex(e.tag) .. HU:GuildName(e.tag) .. "|r"))
end
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
            Pick(s.e)
        end)
        pop.rows[i] = r
    end
    pop.more = pop:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    local function Fill()
        local list = FindChars(box:GetText())
        if HU.Trim(box:GetText() or "") == "" then ClearMark(); return pop:Hide() end
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
    -- (si cambias lo escrito, la marca del que buscaste antes se quita)
    box:HookScript("OnTextChanged", function(_, user) if user then ClearMark() end; Fill() end)
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
        if first then Pick(first) end
    end)
    -- (en la vista de miembros, a la derecha de «Mostrar desconectados»; en la del chat, a la derecha
    -- del desplegable «Guild». No sale en Información ni en nuestra pestaña: Jorge, 10/11. IsVisible
    -- y no IsShown: la casilla sigue «puesta» aunque su lista esté escondida)
    local dd = f.StreamDropdown
    local function Sync()
        box:ClearAllPoints()
        local ours = panel and panel.where == "blizz" and panel:IsShown()
        if not ours and anchor:IsVisible() then
            box:SetPoint("BOTTOMRIGHT", ml, "TOPRIGHT", -24, 30)
            box:Show()
        elseif not ours and dd and dd:IsVisible() then
            box:SetPoint("LEFT", dd, "RIGHT", 16, 0)
            box:Show()
        else
            box:Hide()
            ClearMark()
        end
    end
    HU.SyncCharSearch = function() HU.After(0, Sync) end
    for _, w in ipairs({ anchor, ml, dd }) do
        if w then w:HookScript("OnShow", HU.SyncCharSearch); w:HookScript("OnHide", HU.SyncCharSearch) end
    end
    if f.SetDisplayMode then hooksecurefunc(f, "SetDisplayMode", HU.SyncCharSearch) end
    f:HookScript("OnShow", HU.SyncCharSearch)
    Sync()
end

local function SyncTab()
    local f = Win()
    if not (f and tab) then return end
    -- (solo con la hermandad elegida: va debajo de su pestaña de Información)
    -- (ya no depende de que la configuración esté leída: al entrar tarda y la pestaña se quedaba escondida)
    local show = f.GuildInfoTab and f.GuildInfoTab:IsShown()
    -- (debajo de la última pestaña del juego que esté a la vista: la de preferencias de juego de la
    -- hermandad va justo debajo de la de Información, y la nuestra la tapaba. Jorge, 13/11)
    local prefs = f.GuildPreferredPlaySettingsTab
    local anchor = (prefs and prefs:IsShown()) and prefs or f.GuildInfoTab
    if anchor and tab.anchoredTo ~= anchor then
        tab.anchoredTo = anchor
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    end
    tab:SetShown(show and true or false)
    if not show then ShowPanel(false) end
end

local function Setup()
    local f = Win()
    if tab or not f or not f.GuildInfoTab then return end
    tab = CreateFrame("CheckButton", "GuildUnionReduceTab", f, "CommunitiesFrameTabTemplate")
    tab:SetPoint("TOPLEFT", f.GuildInfoTab, "BOTTOMLEFT", 0, -20)
    tab.anchoredTo = f.GuildInfoTab
    tab.Icon:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
    tab.tooltip = "GuildUnion"
    -- (nuestro clic: no llama a SetDisplayMode de Blizzard)
    tab:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ShowPanel(not (panel and panel.where == "blizz" and panel:IsShown()))
    end)
    -- (cada parte por separado: si una falla, las demás siguen y el fallo queda en /gu errores)
    if not panel then HU:SafeCall("pestaña", BuildPanel) end
    HU:SafeCall("buscador", BuildCharSearch, f)
    -- (al pulsar una pestaña suya o cambiar de vista, se cierra la nuestra)
    hooksecurefunc(f, "SetDisplayMode", function() ShowPanel(false) end)
    for _, key in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }) do
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
        if tab and tab:IsShown() then ShowPanel(not (panel and panel.where == "blizz" and panel:IsShown())) return end
    end
    -- (cerrada: la ventana propia de GuildUnion)
    self:OpenMainWindow()
end

-- Ventana propia de GuildUnion: el mismo panel, fuera de la ventana de Blizzard (minimapa y /gu)
function HU:OpenMainWindow()
    if main and main:IsShown() and panel and panel.where == "own" then main:Hide() return end
    if not main then
        main = CreateFrame("Frame", "GuildUnionMain", UIParent, "BackdropTemplate")
        main:SetSize(700, 454)
        main:SetPoint("CENTER")
        -- (sin «toplevel»: al pulsarla el juego la subía por encima de su propio panel y lo tapaba)
        main:SetFrameStrata("DIALOG")
        main:SetMovable(true); main:EnableMouse(true); main:RegisterForDrag("LeftButton")
        main:SetScript("OnDragStart", main.StartMoving)
        main:SetScript("OnDragStop", main.StopMovingOrSizing)
        main:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        main:SetBackdropColor(0.04, 0.04, 0.05, 0.97)
        tinsert(UISpecialFrames, "GuildUnionMain")
        local close = HU.CloseButton(main)
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetFrameLevel(main:GetFrameLevel() + 20)
        local head = main:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        head:SetPoint("TOPLEFT", 12, -9)
        head:SetText("GuildUnion")
        main:SetScript("OnHide", function() if panel and panel.where == "own" then panel:Hide() end end)
        main:Hide()
    end
    if not panel then BuildPanel() end
    panel:SetParent(main)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", main, "TOPLEFT", 4, -28)   -- (arriba queda la barra con el título y la X)
    panel:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -4, 4)
    panel:SetFrameStrata("DIALOG")
    -- (sin «toplevel» aquí: al pulsar el panel el juego lo subía por encima de la X de la ventana)
    panel:SetToplevel(false)
    panel.where = "own"
    if tab then tab:SetChecked(false) end
    main:Show()
    panel:Show()
    -- (el panel siempre encima del fondo de la ventana; se pone después de enseñarla)
    panel:SetFrameLevel(main:GetFrameLevel() + 2)
    RefreshStatus(); RefreshOfficers()
end
---------------------------------------------------------------------------
-- Gestión de hermandades (Jorge, 10/11): quién es la principal, quiénes son los gestores, invitar y
-- quitar hermandades. Invitan el maestro de la principal y los gestores; nombra gestores el maestro.
---------------------------------------------------------------------------
local gw
local function GuildsText()
    local lines = {}
    local principal = HU:PrincipalTag()
    for _, g in ipairs((HU.cfg and HU.cfg.guilds) or {}) do
        local mark = (g.tag == principal) and ("  |cffffd100" .. L("(principal)") .. "|r") or ""
        local how = g.net and ("  |cff808080" .. L("(por invitación)") .. "|r") or ""
        lines[#lines + 1] = "|cff" .. HU:GuildColorHex(g.tag) .. "<" .. g.tag .. ">|r  " .. g.name .. mark .. how
    end
    return #lines > 0 and table.concat(lines, "\n") or L("Sin configurar.")
end
local function RefreshGuildsWindow()
    if not (gw and gw:IsShown()) then return end
    local list = HU:Managers()
    gw.guilds:SetText(GuildsText())
    gw.managers:SetText(L("Gestores: ") .. (#list > 0 and ("|cffffffff" .. table.concat(list, ", ") .. "|r") or ("|cff808080" .. L("ninguno") .. "|r")))
    local canInvite, isBoss = HU:CanInvite(), HU:IsPrincipalMaster()
    for _, w in ipairs(gw.inviteParts) do w:SetShown(canInvite) end
    for _, w in ipairs(gw.bossParts) do w:SetShown(isBoss) end
    gw.status:SetText(HU.inviteStatus or "")
    gw.who:SetText(isBoss and L("Eres el maestro de la hermandad principal: invitas y nombras gestores.")
        or canInvite and L("Eres gestor: puedes invitar y quitar hermandades.")
        or L("Solo el maestro de la hermandad principal y sus gestores pueden invitar hermandades."))
end
function HU:ShowGuildsWindow()
    if not gw then
        gw = CreateFrame("Frame", "GuildUnionGuildsFrame", UIParent, "BackdropTemplate")
        gw:SetSize(460, 420)
        gw:SetPoint("CENTER")
        -- (por encima de la ventana de GuildUnion y de la de hermandad, que van en DIALOG)
        gw:SetFrameStrata("FULLSCREEN_DIALOG")
        gw:SetMovable(true); gw:EnableMouse(true); gw:RegisterForDrag("LeftButton")
        gw:SetScript("OnDragStart", gw.StartMoving)
        gw:SetScript("OnDragStop", gw.StopMovingOrSizing)
        gw:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        gw:SetBackdropColor(0.05, 0.05, 0.08, 0.96)
        tinsert(UISpecialFrames, "GuildUnionGuildsFrame")
        local title = gw:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText(L("Gestión de hermandades"))
        local close = HU.CloseButton(gw)
        close:SetPoint("TOPRIGHT", -2, -2)
        gw.who = gw:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gw.who:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        gw.who:SetWidth(430); gw.who:SetJustifyH("LEFT")
        local hG = Header(gw, L("Hermandades de la comunidad"), gw.who, -12)
        gw.guilds = gw:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        gw.guilds:SetPoint("TOPLEFT", hG, "BOTTOMLEFT", 4, -6)
        gw.guilds:SetWidth(420); gw.guilds:SetJustifyH("LEFT")
        gw.managers = gw:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gw.managers:SetPoint("TOPLEFT", gw.guilds, "BOTTOMLEFT", -4, -10)
        gw.managers:SetWidth(430); gw.managers:SetJustifyH("LEFT")

        -- Invitar (y quitar) — maestro de la principal y gestores
        local hI = Header(gw, L("Invitar una hermandad"), gw.managers, -14)
        local note = gw:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", hI, "BOTTOMLEFT", 0, -2)
        note:SetText(L("Al maestro (u oficial que pueda editar la Información) de esa hermandad, y su etiqueta"))
        local who = Box(gw, 170, note, 6, -6)
        local tagBox = CreateFrame("EditBox", nil, gw, "InputBoxTemplate")
        tagBox:SetSize(60, 20); tagBox:SetAutoFocus(false); tagBox:SetMaxLetters(6)
        tagBox:SetPoint("LEFT", who, "RIGHT", 12, 0)
        tagBox:SetScript("OnEscapePressed", tagBox.ClearFocus)
        local bInv = Button(gw, L("Invitar"), 80, tagBox, 10)
        bInv:SetScript("OnClick", function()
            local ok, why = HU:InviteGuild(who:GetText(), tagBox:GetText())
            if not ok and why then HU.inviteStatus = "|cffff6060" .. why .. "|r" end
            RefreshGuildsWindow()
        end)
        gw.status = gw:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gw.status:SetPoint("TOPLEFT", who, "BOTTOMLEFT", -6, -6)
        gw.status:SetWidth(430); gw.status:SetJustifyH("LEFT")
        local hR = gw:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hR:SetPoint("TOPLEFT", gw.status, "BOTTOMLEFT", 0, -10)
        hR:SetText(L("Quitar una hermandad añadida por invitación (etiqueta):"))
        local remBox = Box(gw, 60, hR, 6, -6)
        remBox:SetMaxLetters(6)
        local bRem = Button(gw, L("Quitar"), 80, remBox, 10)
        bRem:SetScript("OnClick", function()
            local ok, why = HU:RemoveNetGuild(remBox:GetText())
            HU.inviteStatus = ok and (L("Hermandad quitada de la comunidad: <") .. remBox:GetText():upper() .. ">") or ("|cffff6060" .. (why or "?") .. "|r")
            RefreshGuildsWindow()
        end)
        gw.inviteParts = { hI, note, who, tagBox, bInv, gw.status, hR, remBox, bRem }

        -- Gestores — solo el maestro de la principal
        local hM = Header(gw, L("Gestores (pueden invitar)"), remBox, -16)
        hM:SetPoint("TOPLEFT", remBox, "BOTTOMLEFT", -6, -16)
        local mBox = Box(gw, 170, hM, 6, -6)
        if HU.NameSuggest then HU:NameSuggest(mBox) end
        local bAdd = Button(gw, L("Nombrar"), 80, mBox, 10)
        local bDel = Button(gw, L("Quitar"), 80, bAdd, 6)
        local function Set(add)
            local ok, why = HU:SetManager(mBox:GetText(), add)
            HU.inviteStatus = ok and ((add and L("Gestor añadido: ") or L("Gestor quitado: ")) .. HU:Short(HU:FullName(mBox:GetText()) or mBox:GetText()))
                or ("|cffff6060" .. (why or "?") .. "|r")
            RefreshGuildsWindow()
        end
        bAdd:SetScript("OnClick", function() Set(true) end)
        bDel:SetScript("OnClick", function() Set(false) end)
        gw.bossParts = { hM, mBox, bAdd, bDel }
        gw:SetScript("OnShow", RefreshGuildsWindow)
        gw:Hide()
    end
    if gw:IsShown() then gw:Hide() else gw:Show(); gw:Raise() end
end
if HU.UI then HU.UI.UpdateGuildsWindow = function() HU:SafeCall("hermandades", RefreshGuildsWindow) end end

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
