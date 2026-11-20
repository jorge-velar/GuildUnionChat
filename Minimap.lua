-- Guild Union - botón del minimapa (LibDBIcon: como el de casi todos los addons, así las «bolsas» de
-- botones como MinimapButtonButton lo recogen). Clic izquierdo: la ventana propia de GuildUnion (no es
-- la de hermandad de Blizzard, así que no la «contamina»); derecho: Gestión de hermandades.
local _, HU = ...
local L = HU.L

local LibStub = _G.LibStub
local NAME = "GuildUnion"
local registered = false

local function ShowTooltip(tt)
    tt:AddLine(HU:Title(), 0.2, 1, 0.6)
    if HU.cfg and HU.cfg.ok then
        tt:AddLine(L("Canal: ") .. (HU:IsJoined("main") and "|cff44ff44conectado|r" or L("|cffff4444sin conectar|r")), 1, 1, 1)
        if HU.intruders and #HU.intruders > 0 then
            tt:AddLine(L("Intrusos: ") .. #HU.intruders, 1, 0.3, 0.3)
        end
    else
        tt:AddLine(L("Sin configurar (/gu config)"), 1, 0.5, 0)
    end
    tt:AddLine(" ")
    tt:AddLine(L("Clic izquierdo: abrir GuildUnion"), 0.8, 0.8, 0.8)
    tt:AddLine(L("Clic derecho: Gestión de hermandades"), 0.8, 0.8, 0.8)
end

local function OnClick(_, button)
    if button == "RightButton" and HU.ShowGuildsWindow and HU:CanPin() then return HU:ShowGuildsWindow() end
    if HU.OpenMainWindow then HU:OpenMainWindow() end
end

local function Register()
    if registered then return true end
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (LDB and icon) then return false end
    -- (la posición la guarda LibDBIcon aquí; la de antes, en grados, se aprovecha)
    HU.db.minimapIcon = HU.db.minimapIcon or { hide = HU.db.minimapHidden and true or nil, minimapPos = HU.db.minimapAngle }
    local obj = LDB:NewDataObject(NAME, {
        type = "launcher",
        text = "GuildUnion",
        icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
        OnClick = OnClick,
        OnTooltipShow = ShowTooltip,
    })
    icon:Register(NAME, obj, HU.db.minimapIcon)
    registered = true
    return true
end

-- /gu minimapa on|off (y lo de siempre: db.minimapHidden)
function HU:ShowMinimapButton(show)
    self.db.minimapHidden = not show
    if not Register() then return end
    self.db.minimapIcon.hide = (not show) or nil
    local icon = LibStub("LibDBIcon-1.0")
    if show then icon:Show(NAME) else icon:Hide(NAME) end
end

-- (en cuanto carga el addon, no al entrar al juego: las «bolsas» de botones recogen los que ya existen
-- cuando miran, y al entrar ya era tarde)
local ADDON = ...
HU:On("ADDON_LOADED", function(name)
    if name ~= ADDON or not HU.db then return end
    Register()
    if HU.db.minimapHidden then HU:ShowMinimapButton(false) end
end)
HU:OnStart(function()
    if Register() and HU.db.minimapHidden then HU:ShowMinimapButton(false) end
end)
