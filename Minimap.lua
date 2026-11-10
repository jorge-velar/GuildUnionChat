-- Guild Union - botón del minimapa
local _, HU = ...
local L = HU.L

local button
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function UpdatePosition()
    local angle = math.rad(HU.db.minimapAngle or 200)
    local radius = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    HU.db.minimapAngle = math.deg(atan2(py - my, px - mx)) % 360
    UpdatePosition()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(HU:Title(), 0.2, 1, 0.6)
    if HU.cfg and HU.cfg.ok then
        GameTooltip:AddLine(L("Canal: ") .. (HU:IsJoined("main") and "|cff44ff44conectado|r" or L("|cffff4444sin conectar|r")), 1, 1, 1)
        local on = HU.rosterOnline or 0
        for tag, r in pairs(HU.remoteRoster) do
            if HU.cfg.byTag[tag] then on = on + (r.online or 0) end
        end
        if not HU.CHAT_ONLY then GameTooltip:AddLine(L("Conectados en total: ") .. on, 1, 1, 1) end
        if HU.intruders and #HU.intruders > 0 then
            GameTooltip:AddLine(L("Intrusos: ") .. #HU.intruders, 1, 0.3, 0.3)
        end
    else
        GameTooltip:AddLine(L("Sin configurar (/gu config)"), 1, 0.5, 0)
    end
    GameTooltip:Show()
end

local function Create()
    if button or not Minimap then return end
    -- (botón seguro: el clic izquierdo pulsa el botón de Hermandad del juego, que abre la ventana sin
    -- «contaminarla». Si la abría nuestro código, el juego bloqueaba luego cambiar rangos y notas)
    -- (los atributos solo se pueden poner fuera de combate)
    if InCombatLockdown and InCombatLockdown() then HU.minimapPending = true return end
    button = CreateFrame("Button", "HermandadUnidaMinimapButton", Minimap, "SecureActionButtonTemplate")
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    -- (arriba y abajo: el juego decide con «ActionButtonUseKeyDown» en cuál de los dos actúa)
    button:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local micro = _G.GuildMicroButton
    if micro then
        button:SetAttribute("type1", "click")
        button:SetAttribute("clickbutton1", micro)
    end
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    -- (antes del clic: que al abrirse la ventana salga nuestra pestaña; BlizzTab.lua, HU:WantsTab)
    local wasOpen = false
    button:HookScript("OnMouseDown", function(_, which)
        if which ~= "LeftButton" then return end
        HU.tabWantedT = GetTime()
        wasOpen = _G.CommunitiesFrame and _G.CommunitiesFrame:IsShown() or false
    end)
    -- (después del clic. Izquierdo: SIEMPRE el panel de GuildUnion; si la ventana estaba cerrada la abre
    -- el botón de Hermandad del juego y la pestaña sale sola; si ya estaba abierta, el botón no la cierra
    -- (UpdateMinimapClick) y aquí se abre el panel. Derecho: abre o cierra solo nuestra pestaña.
    -- Nunca se abre la ventana desde nuestro código)
    button:HookScript("OnClick", function(_, which)
        if which == "RightButton" or not micro then
            if HU.OpenReduce then HU:OpenReduce() end
        elseif wasOpen and HU.ShowReducePanel then
            HU:ShowReducePanel()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        -- (en combate no se puede mover un botón seguro)
        if InCombatLockdown and InCombatLockdown() then return end
        self:SetScript("OnUpdate", OnDragUpdate)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
end

function HU:ShowMinimapButton(show)
    self.db.minimapHidden = not show
    if show then
        Create()
        if button then button:Show() end
    elseif button then
        button:Hide()
    end
end

HU:OnStart(function()
    if not HU.db.minimapHidden then HU:ShowMinimapButton(true) end
end)
HU:On("PLAYER_REGEN_ENABLED", function()
    if HU.minimapPending and not HU.db.minimapHidden then HU.minimapPending = nil; HU:ShowMinimapButton(true) end
    if HU.minimapClickPending then HU.minimapClickPending = nil; HU:UpdateMinimapClick() end
end)

-- Con la ventana de hermandad abierta, el clic izquierdo no pulsa el botón de Hermandad (la cerraría):
-- solo abre nuestro panel. Con ella cerrada, sí (la abre el juego, sin contaminarla). Lo llama BlizzTab.lua
-- al abrirse y cerrarse la ventana. (Los atributos de un botón seguro solo cambian fuera de combate)
function HU:UpdateMinimapClick()
    if not (button and _G.GuildMicroButton) then return end
    if InCombatLockdown and InCombatLockdown() then HU.minimapClickPending = true return end
    local open = _G.CommunitiesFrame and _G.CommunitiesFrame:IsShown()
    button:SetAttribute("type1", (not open) and "click" or nil)
end
