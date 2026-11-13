-- Guild Union - pestañas propias en la ventana de chat del juego
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

local TABS = HU.LT({
    { key = "main", name = "Hermandad",    groups = { "GUILD", "GUILD_ACHIEVEMENT" } },
    { key = "off",  name = "Oficiales",    groups = { "OFFICER" }, officer = true },
})

local function Frame(i) return _G["ChatFrame" .. i] end

-- Busca una ventana de chat por su nombre
local function FindWindow(name)
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local n, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(i)
        if n and n:lower() == name:lower() and (shown or docked) then return Frame(i), i end
    end
    return nil
end

local function AddGroup(f, g)
    if ChatFrame_AddMessageGroup then ChatFrame_AddMessageGroup(f, g)
    elseif f.AddMessageGroup then f:AddMessageGroup(g) end
end

local function ClearGroups(f)
    if ChatFrame_RemoveAllMessageGroups then ChatFrame_RemoveAllMessageGroups(f)
    elseif f.RemoveAllMessageGroups then f:RemoveAllMessageGroups() end
    if ChatFrame_RemoveAllChannels then pcall(ChatFrame_RemoveAllChannels, f)
    elseif f.RemoveAllChannels then pcall(f.RemoveAllChannels, f) end
end

-- por si se cambió de idioma después de crear las pestañas: se buscan con los dos nombres
local OTHER_NAMES = { main = { "Hermandad", "Guild" }, off = { "Oficiales", "Officers" } }
local function FindTab(t)
    local f = FindWindow(t.name)
    if f then return f end
    for _, n in ipairs(OTHER_NAMES[t.key] or {}) do
        f = FindWindow(n)
        if f then return f end
    end
end

function HU:ChatTabFrame(key)
    for _, t in ipairs(TABS) do
        if t.key == key then return (FindTab(t)) end
    end
end

-- ¿Está Chattynator? Esconde las ventanas y pestañas de chat del juego y pone las suyas; de lo que
-- escriben los addons solo recoge lo que va a la ventana principal (DEFAULT_CHAT_FRAME). [+ARCHITECTURE.md]
function HU.UsingChattynator()
    local c = _G.Chattynator
    return type(c) == "table" and type(c.API) == "table"
end

function HU:CreateChatTabs(silent)
    if HU.UsingChattynator() then
        -- (las pestañas del juego no se ven: no se crean, y no se apunta como hecho por si lo quita)
        if not silent then
            self:Print(L("Con Chattynator no hacen falta: los chats de Guild Union salen en su ventana principal. En los ajustes de Chattynator puedes elegir en qué pestañas se ven los mensajes del addon GuildUnion."))
        end
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        if not silent then self:Print(L("No se pueden crear pestañas de chat en combate.")) end
        return
    end
    if not FCF_OpenNewWindow then
        if not silent then self:Print(L("Este cliente no permite crear pestañas de chat desde un addon.")) end
        return
    end
    local made = {}
    for _, t in ipairs(TABS) do
        if (not t.officer or self:CanOfficer() or self:IsTest()) and not FindTab(t) then
            local f = FCF_OpenNewWindow(t.name, true)
            if not f or type(f) ~= "table" then f = FindWindow(t.name) end
            if f then
                ClearGroups(f)
                for _, g in ipairs(t.groups) do AddGroup(f, g) end
                made[#made + 1] = t.name
            end
        end
    end
    self.db.chatTabsMade = true
    if not silent then
        if #made > 0 then self:Print(L("Pestañas de chat creadas: ") .. table.concat(made, ", ") .. ".")
        else self:Print(L("Las pestañas de chat ya existen.")) end
    end
end

-- La primera vez que se usa el addon, crea las pestañas solas
HU:OnStart(function()
    HU.After(12, function()
        if not HU.db.chatTabsMade and HU.cfg and HU.cfg.ok then HU:CreateChatTabs(HU.UsingChattynator()) end
    end)
end)

-- Ventanas donde mostrar cada tipo de mensaje del addon
local framesCache, framesT = {}, {}
local function FramesForUncached(self, kind)
    local out, used = {}, {}
    local function add(f) if f and not used[f] then used[f] = true; out[#out + 1] = f end end
    local mainTab, offTab = self:ChatTabFrame("main"), self:ChatTabFrame("off")
    local wantType = (kind == "off") and "OFFICER" or "GUILD"
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = Frame(i)
        if f and f.messageTypeList then
            for _, t in pairs(f.messageTypeList) do
                if t == wantType then add(f); break end
            end
        end
    end
    if kind == "main" then add(mainTab) elseif kind == "off" then add(offTab) end
    if #out == 0 then add(DEFAULT_CHAT_FRAME) end
    return out
end

-- Lo que el jugador ha elegido a mano para cada ventana (clic derecho en su pestaña > Guild Union):
-- db.chatShow[número de ventana][tipo] = true (se ve) / false (no se ve); sin apuntar, lo de siempre
local function WithChoices(self, kind, out)
    local all = self.db and self.db.chatShow
    if type(all) ~= "table" or not next(all) then return out end
    local has = {}
    for _, f in ipairs(out) do has[f] = true end
    local res = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = Frame(i)
        if f then
            -- (v: true/false si el jugador lo eligió para esta ventana; nil si no ha tocado nada en ella)
            local v
            if type(all[i]) == "table" then v = all[i][kind] end
            if v == true or (v == nil and has[f]) then res[#res + 1] = f end
        end
    end
    return res
end

local chattyFrames
function HU:FramesFor(kind)
    -- (con Chattynator, todo a la ventana principal: es la única que recoge. Lo que se escribiera en
    -- otra pestaña del juego no se vería)
    if HU.UsingChattynator() then
        if not chattyFrames or chattyFrames[1] ~= DEFAULT_CHAT_FRAME then chattyFrames = { DEFAULT_CHAT_FRAME } end
        return chattyFrames
    end
    local now = GetTime()
    if not framesT[kind] or now - framesT[kind] > 2 then
        framesCache[kind], framesT[kind] = WithChoices(self, kind, FramesForUncached(self, kind)), now
    end
    return framesCache[kind]
end

function HU:ChatShownIn(kind, frame)
    for _, f in ipairs(WithChoices(self, kind, FramesForUncached(self, kind))) do
        if f == frame then return true end
    end
    return false
end
function HU:SetChatShownIn(kind, frame, on)
    local id = frame and frame.GetID and frame:GetID()
    if not id or not self.db then return end
    local all = self.db.chatShow
    if type(all) ~= "table" then all = {}; self.db.chatShow = all end
    all[id] = type(all[id]) == "table" and all[id] or {}
    all[id][kind] = on and true or false
    framesCache, framesT = {}, {}
end

-- La entrada «Guild Union» del menú de la pestaña (MENU_FCF_TAB es la etiqueta que le pone el juego
-- a ese menú para que los addons le añadan cosas)
local function TabMenu(owner, root)
    if not (HU.myTag and owner and owner.GetID and FCF_GetChatFrameByID) then return end
    local frame = FCF_GetChatFrameByID(owner:GetID())
    if not frame or frame.isTemporary then return end
    local sub = root:CreateButton(HU.ADDON_TITLE)
    sub:CreateTitle(L("Chats en esta pestaña"))
    local function item(kind, text)
        sub:CreateCheckbox(text,
            function() return HU:ChatShownIn(kind, frame) end,
            function() HU:SetChatShownIn(kind, frame, not HU:ChatShownIn(kind, frame)) end)
    end
    item("main", L("Otras hermandades"))
    if HU.offCfg and HU:CanOfficer() then item("off", L("Oficiales de la comunidad")) end
    for _, x in ipairs(HU.ExtraChannels and HU:ExtraChannels() or {}) do
        item("x:" .. x.name, x.name)
    end
end
if Menu and Menu.ModifyMenu then
    Menu.ModifyMenu("MENU_FCF_TAB", function(...) HU:SafeCall("menú de pestaña", TabMenu, ...) end)
end

---------------------------------------------------------------------------
-- Cada pestaña escribe en lo suyo (Jorge, 10/11): al abrir el chat (Intro) y al hacer clic en la pestaña.
-- Hermandad → /g, Oficiales → /o. [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local TAB_TYPE = { main = "GUILD", off = "OFFICER" }

local function SelectedChatFrame()
    if GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow then return FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) end
    return SELECTED_CHAT_FRAME
end

local function TabKeyOf(frame)
    if not frame then return end
    for key in pairs(TAB_TYPE) do
        if frame == HU:ChatTabFrame(key) then return key end
    end
end

local function ApplyTab(eb, frame)
    if not (eb and eb.GetChatType and frame) then return end
    -- (respondiendo un susurro u otro tipo puesto a propósito: el tipo ya no es el «pegajoso»)
    if eb:GetChatType() ~= eb:GetStickyType() then return end
    local chatType = TAB_TYPE[TabKeyOf(frame)]
    if chatType and eb:GetChatType() ~= chatType then
        eb:SetChatType(chatType)
        eb:SetStickyType(chatType)
        eb:UpdateHeader()
    end
end

local function StickyTab(text)
    -- (pulsar Intro lo hace el jugador: aquí el juego deja cambiar los canales de sitio)
    if HU.FixChannelOrder then HU:FixChannelOrder() end
    if text and text ~= "" then return end
    -- (misma pestaña que la última vez: se respeta lo que el jugador eligiera en ella (/s, /p...).
    -- Antes cada Intro lo devolvía a /g. Jorge, 12/11. Lo suyo vuelve al hacer clic en la pestaña)
    local frame = SelectedChatFrame()
    if frame == HU.tabApplied then return end
    HU.tabApplied = frame
    local eb = ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
    ApplyTab(eb, frame)
end
if ChatFrameUtil and ChatFrameUtil.OpenChat then
    hooksecurefunc(ChatFrameUtil, "OpenChat", function(text) HU:SafeCall("pestañas de chat", StickyTab, text) end)
end

if FCF_Tab_OnClick and FCF_GetChatFrameByID then
    hooksecurefunc("FCF_Tab_OnClick", function(tab, button)
        if button == "RightButton" or button == "MiddleButton" then return end
        local f = FCF_GetChatFrameByID(tab:GetID())
        HU.tabApplied = f
        HU:SafeCall("pestañas de chat", ApplyTab, f and f.editBox, f)
    end)
end
