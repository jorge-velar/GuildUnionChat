-- Guild Union - pestañas propias en la ventana de chat del juego
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

local TABS = HU.LT({
    { key = "main", name = "Hermandad",    groups = { "GUILD", "GUILD_ACHIEVEMENT" } },
    { key = "lfg",  name = "Buscar grupo", groups = {} },
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
local OTHER_NAMES = { main = { "Hermandad", "Guild" }, lfg = { "Buscar grupo", "Looking for group" }, off = { "Oficiales", "Officers" } }
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

function HU:CreateChatTabs(silent)
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
        if not HU.db.chatTabsMade and HU.cfg and HU.cfg.ok then HU:CreateChatTabs(false) end
    end)
end)

-- Ventanas donde mostrar cada tipo de mensaje del addon
local framesCache, framesT = {}, {}
local function FramesForUncached(self, kind)
    local out, used = {}, {}
    local function add(f) if f and not used[f] then used[f] = true; out[#out + 1] = f end end
    local mainTab, lfgTab, offTab = self:ChatTabFrame("main"), self:ChatTabFrame("lfg"), self:ChatTabFrame("off")
    local wantType = (kind == "off") and "OFFICER" or "GUILD"
    if kind == "lfg" then
        add(lfgTab)
        if not self.db.showLFG then return out end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = Frame(i)
        if f and f.messageTypeList and not (kind == "lfg" and (f == mainTab or f == offTab)) then
            for _, t in pairs(f.messageTypeList) do
                if t == wantType then add(f); break end
            end
        end
    end
    if kind == "main" then add(mainTab) elseif kind == "off" then add(offTab) end
    if #out == 0 and kind ~= "lfg" then add(DEFAULT_CHAT_FRAME) end
    return out
end
function HU:FramesFor(kind)
    local now = GetTime()
    if not framesT[kind] or now - framesT[kind] > 2 then
        framesCache[kind], framesT[kind] = FramesForUncached(self, kind), now
    end
    return framesCache[kind]
end

---------------------------------------------------------------------------
-- Cada pestaña escribe en lo suyo (Jorge, 10/11): al abrir el chat (Intro) con la pestaña Hermandad
-- elegida se escribe en /g, con la de Oficiales en /o, y con la de Buscar grupo sale ya «/buscargrupo ».
-- Antes, tras mandar algo, la siguiente vez volvía a /decir. Solo al abrirlo normal: si se abre para
-- contestar un susurro o con un texto (/, un enlace...), no se toca
---------------------------------------------------------------------------
local LFG_PREFIX = "/buscargrupo "
local TAB_TYPE = { main = "GUILD", off = "OFFICER" }
local function SelectedChatFrame()
    if GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow then return FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) end
    return SELECTED_CHAT_FRAME
end
local function StickyTab(text)
    if text and text ~= "" then return end
    local eb = ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
    local sel = SelectedChatFrame()
    if not (eb and eb.GetChatType and sel) then return end
    -- (respondiendo un susurro u otro tipo puesto a propósito: el tipo ya no es el «pegajoso»)
    if eb:GetChatType() ~= eb:GetStickyType() then return end
    for key, chatType in pairs(TAB_TYPE) do
        if sel == HU:ChatTabFrame(key) then
            if eb:GetChatType() ~= chatType then eb:SetChatType(chatType); eb:UpdateHeader() end
            return
        end
    end
    if sel == HU:ChatTabFrame("lfg") and (eb:GetText() or "") == "" then
        -- (como lo hace el propio juego al abrir con un texto: lo pone en el siguiente fotograma)
        eb.text, eb.setText, eb.desiredCursorPosition = LFG_PREFIX, 1, #LFG_PREFIX
    end
end
if ChatFrameUtil and ChatFrameUtil.OpenChat then
    hooksecurefunc(ChatFrameUtil, "OpenChat", function(text) HU:SafeCall("pestañas de chat", StickyTab, text) end)
end
