-- Guild Union - pestañas propias en la ventana de chat del juego
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

-- (copia 87: el addon ya no crea pestañas ni cambia la caja de escribir; solo reconoce por su nombre
-- las que el jugador tenga, para pintar ahí lo de las otras hermandades) [+ARCHITECTURE.md]
local TABS = HU.LT({
    { key = "main", name = "Hermandad" },
    { key = "off",  name = "Oficiales" },
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

-- Al abrir el chat (pulsar Intro lo hace el jugador): aquí el juego deja cambiar los canales de sitio
if ChatFrameUtil and ChatFrameUtil.OpenChat then
    hooksecurefunc(ChatFrameUtil, "OpenChat", function()
        if HU.FixChannelOrder then HU:SafeCall("orden de canales", HU.FixChannelOrder, HU) end
    end)
end
