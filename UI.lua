-- Guild Union - piezas para las ventanas sueltas, la tecla J y lo que queda del panel [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L

local UI = {}
HU.UI = UI

local unpack = unpack or table.unpack
local WHITE = "Interface\\Buttons\\WHITE8x8"
local EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"

local T = {
    frameBg     = { 0.09, 0.065, 0.04, 0.97 },
    frameBorder = { 0.80, 0.64, 0.32, 1 },
    inset       = { 0.13, 0.095, 0.06, 0.96 },
    insetBorder = { 0.55, 0.43, 0.25, 1 },
    cardBorder  = { 0.40, 0.31, 0.19, 1 },
    inputBg     = { 0.05, 0.035, 0.02, 0.95 },
    gold        = { 1.00, 0.82, 0.00 },
    sub         = { 0.86, 0.82, 0.72 },
}

---------------------------------------------------------------------------
-- Piezas
---------------------------------------------------------------------------
local function Box(f, bg, border, edgeSize)
    if not f.SetBackdrop then return end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = EDGE, edgeSize = edgeSize or 14,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(unpack(bg))
    f:SetBackdropBorderColor(unpack(border))
end

local function Label(parent, text, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetText(text or "")
    if color then fs:SetTextColor(unpack(color)) end
    return fs
end

local function Inset(parent, title)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Box(f, T.inset, T.insetBorder)
    if title then
        f.title = Label(f, title, "GameFontNormal", T.gold)
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    end
    return f
end

-- Botón rojo de Blizzard
local function RedButton(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(text or "")
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Piezas que usan las ventanas sueltas (UIWindows.lua)
UI.Kit = { T = T, Box = Box, Label = Label, Inset = Inset, RedButton = RedButton }

---------------------------------------------------------------------------
-- Sin ventana principal (GuildUnion Reduce): todo está en la ventana de hermandad de Blizzard
-- (BlizzTab.lua). Quedan estas tres para quien todavía las llama.
---------------------------------------------------------------------------
function UI:Toggle() if HU.OpenReduce then HU:OpenReduce() end end
function UI:MarkDirty() end
function UI:Refresh() end


-- Atajo de teclado (Bindings.xml, Menú > Atajos de teclado > GuildUnion > «Abrir GuildUnion»). [+ARCHITECTURE.md]
BINDING_HEADER_GUILDUNION = "GuildUnion"
BINDING_NAME_GUILDUNION_TOGGLE = L("Abrir GuildUnion")
function GuildUnion_Toggle()
    if HU.UI and HU.UI.Toggle then HU.UI:Toggle() end
end

local keyOwner = CreateFrame("Frame")
function HU:ApplyKeyJ()
    if InCombatLockdown and InCombatLockdown() then HU.keyJPending = true return end
    HU.keyJPending = nil
    -- (la J es siempre la del juego: si abría la ventana nuestro código, el juego bloqueaba después
    -- cambiar rangos y guardar notas. Con /gu tecla on, al abrirla sale ya la pestaña GuildUnion: BlizzTab.lua)
    ClearOverrideBindings(keyOwner)
end
HU:OnStart(function() HU:ApplyKeyJ() end)
HU:On("PLAYER_REGEN_ENABLED", function() if HU.keyJPending then HU:ApplyKeyJ() end end)
