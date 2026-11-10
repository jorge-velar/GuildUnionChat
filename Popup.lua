-- Guild Union - ventanas de confirmación propias
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

HU.Dialogs = {}

local frames = {}
local MAX = 4

local function Finish(f, accepted, reason)
    if not f:IsShown() then return end
    local d, data = f.dialog, f.data
    f.answered = true
    f:Hide()
    if not d then return end
    if accepted then
        if d.OnAccept then d.OnAccept(f, data) end
    elseif d.OnCancel then
        d.OnCancel(f, data, reason or "clicked")
    end
end

local function Layout()
    local prev
    for i = 1, MAX do
        local f = frames[i]
        if f and f:IsShown() then
            f:ClearAllPoints()
            if prev then f:SetPoint("TOP", prev, "BOTTOM", 0, -6)
            else f:SetPoint("TOP", UIParent, "TOP", 0, -135) end
            prev = f
        end
    end
end

local function NewFrame(i)
    local f = CreateFrame("Frame", "WeLovePvPDialog" .. i, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(320, 120)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    f.alert = f:CreateTexture(nil, "ARTWORK")
    f.alert:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    f.alert:SetSize(36, 36)
    f.alert:SetPoint("LEFT", f, "LEFT", 22, 0)
    f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.text:SetWidth(270)
    f.text:SetJustifyH("CENTER")
    f.text:SetPoint("TOP", f, "TOP", 0, -18)

    f.editBox = CreateFrame("EditBox", "WeLovePvPDialog" .. i .. "EditBox", f, "InputBoxTemplate")
    f.editBox:SetAutoFocus(false)
    f.editBox:SetHeight(20)
    f.editBox:SetScript("OnEnterPressed", function(eb)
        local d = f.dialog
        if d and d.EditBoxOnEnterPressed then d.EditBoxOnEnterPressed(eb, f.data)
        else Finish(f, true) end
        if f:IsShown() then f.answered = true; f:Hide() end
    end)
    f.editBox:SetScript("OnEscapePressed", function(eb)
        local d = f.dialog
        if d and d.EditBoxOnEscapePressed then d.EditBoxOnEscapePressed(eb, f.data) end
        if f:IsShown() then f.answered = true; f:Hide() end
    end)

    f.button1 = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.button1:SetSize(120, 22)
    f.button1:SetScript("OnClick", function()
        -- (lo que el juego solo deja hacer escrito por el jugador: se escribe en el chat al abrirlo)
        if f.pendingMacro and HU.TypeLines then HU:TypeLines(f.pendingMacro) end
        Finish(f, true)
    end)
    f.button2 = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.button2:SetSize(120, 22)
    f.button2:SetScript("OnClick", function() Finish(f, false, "clicked") end)

    f:SetScript("OnUpdate", function(self, elapsed)
        if self.timeLeft and self.timeLeft > 0 then
            self.timeLeft = self.timeLeft - elapsed
            if self.timeLeft <= 0 then Finish(self, false, "timeout") end
        end
    end)
    f:SetScript("OnHide", function(self)
        -- cerrada con Escape u otra ventana: no cuenta como respuesta
        if not self.answered and self.dialog and self.dialog.OnCancel then
            pcall(self.dialog.OnCancel, self, self.data, "override")
        end
        self.answered = true
        self.editBox:ClearFocus()
        HU.After(0, Layout)
        -- (la siguiente que esperaba)
        local q = HU.dialogQueue
        if q and #q > 0 then
            local n = table.remove(q, 1)
            HU.After(0.1, function() HU:ShowDialog(n[1], n[2], n[3], n[4]) end)
        end
    end)
    -- Escape la cierra (como las del juego)
    tinsert(UISpecialFrames, "WeLovePvPDialog" .. i)
    f:Hide()
    return f
end

-- Igual que StaticPopup_Show(which, textArg1, textArg2, data)
function HU:ShowDialog(which, a1, a2, data)
    local d = self.Dialogs[which]
    if not d then return end
    -- (avisos de recargar en Forever: con la ventana del juego, que sí puede recargar)
    if d.reload and StaticPopup_Show then return self:BlizzardReloadDialog(d, a1, a2) end
    local f
    for i = 1, MAX do
        frames[i] = frames[i] or NewFrame(i)
        if not frames[i]:IsShown() then f = frames[i] break end
    end
    if not f then
        -- todas ocupadas: espera a que se cierre una (antes se reutilizaba la primera y su
        -- petición se perdía sin avisar)
        self.dialogQueue = self.dialogQueue or {}
        if #self.dialogQueue < 50 then self.dialogQueue[#self.dialogQueue + 1] = { which, a1, a2, data } end
        return
    end
    f.which, f.dialog, f.data, f.answered = which, d, data, false
    local text = d.text or ""
    if text:find("%%s") then text = string.format(text, a1 or "", a2 or "") end
    local hasEdit = d.hasEditBox and true or false
    f.text:SetWidth(d.showAlert and 250 or 280)
    f.text:ClearAllPoints()
    f.text:SetPoint("TOP", f, "TOP", d.showAlert and 18 or 0, -18)
    f.text:SetText(text)
    f.alert:SetShown(d.showAlert and true or false)
    f.editBox:SetShown(hasEdit)
    f.editBox:SetText("")
    f.editBox:SetMaxLetters(d.maxLetters or 0)
    f.editBox:SetWidth(d.editBoxWidth or 200)
    local width = math.max(320, (d.editBoxWidth or 0) + 60)
    local th = f.text:GetStringHeight() or 14
    if type(th) ~= "number" then th = 14 end
    f.editBox:ClearAllPoints()
    f.editBox:SetPoint("TOP", f.text, "BOTTOM", 0, -10)
    f.button1:SetText(d.button1 or L("Aceptar"))
    f.button2:SetText(d.button2 or L("Cancelar"))
    f.button2:SetShown(d.button2 ~= nil)
    f.button1:ClearAllPoints()
    f.button2:ClearAllPoints()
    if d.button2 then
        f.button1:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16)
        f.button2:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 16)
    else
        f.button1:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
    end
    -- (d.secure devuelve un comando que el juego solo deja hacer a su interfaz: echar, ascender...
    -- En Forever ni su botón seguro vale: se acepta con el botón normal y va a la ventana de órdenes)
    f.pendingMacro = d.secure and d.secure(data) or nil
    f.button1:Enable()
    f.button1:Show()
    f:SetSize(width, math.max(d.showAlert and 110 or 90, th + 70 + (hasEdit and 30 or 0)))
    f.timeLeft = (d.timeout and d.timeout > 0) and d.timeout or nil
    f:Show()
    Layout()
    if d.OnShow then d.OnShow(f, data) end
    if hasEdit then f.editBox:SetFocus() end
    return f
end

-- Cierra las ventanas de un tipo (si se da filtro, solo las que cumplan filtro(data))
function HU:HideDialogs(which, filter)
    for i = 1, MAX do
        local f = frames[i]
        if f and f:IsShown() and f.which == which and (not filter or filter(f.data)) then
            f.answered = true
            f:Hide()
        end
    end
end

-- Un aviso de recargar con la ventana de aviso del propio juego (StaticPopup): su botón es de
-- Blizzard y al pulsarlo tú sí recarga en Forever (desde una ventana nuestra lo bloquea)
function HU:BlizzardReloadDialog(d, a1, a2)
    local text = d.text or ""
    if text:find("%%s") then text = string.format(text, a1 or "", a2 or "") end
    StaticPopupDialogs.GUILDUNION_RELOAD = StaticPopupDialogs.GUILDUNION_RELOAD or {
        text = "%s", timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
        OnAccept = function() HU:Reload(true) end,
    }
    local sp = StaticPopupDialogs.GUILDUNION_RELOAD
    sp.button1 = d.button1 or L("Recargar")
    sp.button2 = d.button2 or L("Luego")
    StaticPopup_Show("GUILDUNION_RELOAD", text)
end

---------------------------------------------------------------------------
-- Actualización IMPORTANTE (HU.mustUpdate, lo pone OnHello solo si alguien de confianza trae una [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local MUST_TEXT = "Actualización IMPORTANTE de GuildUnion (%s). Tu versión (%s) puede dejar de funcionar con las demás hermandades. Actualízala."
-- (versión mínima que pone tu hermandad con GU:v: en su Información: el addon queda en pausa, HU.paused)
local PAUSED_TEXT = "Tu GuildUnion (%s) es más viejo que el mínimo que ha puesto tu hermandad (%s). El addon está en pausa hasta que lo actualices."
function HU:MustUpdateText()
    if self.paused then return string.format(L(PAUSED_TEXT), tostring(self.version), tostring(self.paused)) end
    return string.format(L(MUST_TEXT), tostring(self.mustUpdate), tostring(self.version))
end
-- La versión mínima de la Información de MI hermandad (Config.lua). Con mi versión por debajo, el addon [+ARCHITECTURE.md]
function HU:SetGuildMin(v, fromSaved)
    self.guildMin = v
    -- (se guarda la última leída de la Información: al entrar se aplica antes del primer saludo, y
    -- cuando llega la Información de verdad, manda ella)
    if not fromSaved and self.db then self.db.guildMin = v end
    local p = (v and self.VersionGreater(v, self.version)) and v or nil
    if p == self.paused then return end
    self.paused = p
    if self.UI and self.UI.UpdateUpdateBanner then self.UI:UpdateUpdateBanner() end
    if p then HU.After(0, function() HU:MustUpdateNotice(true) end) end
end
local mustShownT = nil
function HU:MustUpdateNotice(fresh)
    if not self.mustUpdate and not self.paused then return end
    if self.UI and self.UI.UpdateUpdateBanner then self.UI:UpdateUpdateBanner() end
    if not fresh and mustShownT and GetTime() - mustShownT < 1800 then return end
    -- (al entrar la Información llega varias veces seguidas: la línea del chat, una sola)
    if fresh and mustShownT and GetTime() - mustShownT < 60 then return end
    -- (en combate o dentro de una mazmorra/banda, se espera a la vuelta siguiente del reloj)
    if InCombatLockdown and InCombatLockdown() then return end
    local inInstance = IsInInstance and IsInInstance()
    if inInstance then return end
    mustShownT = GetTime()
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffff3333" .. self:MustUpdateText() .. "|r") end
end
-- (lo guardado: sigue mientras mi versión sea más vieja que esa; al actualizar, se borra solo) [+ARCHITECTURE.md]
local MUST_TTL = 7 * 86400
local function MustValid(s)
    return type(s) == "table" and type(s.v) == "string" and s.v:match("^[%d%.]+$") and #s.v < 12
        and type(s.t) == "number" and time() - s.t < MUST_TTL and HU.VersionGreater(s.v, HU.version)
end
HU:OnStart(function()
    -- (versión mínima de mi hermandad de la última vez: hasta que llegue la Información, vale esa)
    local gm = HU.db and HU.db.guildMin
    if HU.guildMin == nil and type(gm) == "string" and gm:match("^[%d%.]+$") and #gm < 12 then HU:SetGuildMin(gm, true) end
    local saved = HU.db and HU.db.mustUpdate
    if MustValid(saved) then
        HU.mustUpdate = saved.v
        HU.After(10, function() HU:MustUpdateNotice(true) end)
    elseif HU.db then
        HU.db.mustUpdate = nil
    end
    HU.NewTicker(60, function()
        -- (7 días sin que ningún oficial lo repita: se quita la franja)
        if HU.mustUpdate and HU.db and not MustValid(HU.db.mustUpdate) then
            HU.mustUpdate, HU.db.mustUpdate = nil, nil
            if HU.UI and HU.UI.UpdateUpdateBanner then HU.UI:UpdateUpdateBanner() end
        end
        HU:MustUpdateNotice(false)
    end)
end)

HU.Dialogs.GU_LANG = {
    text = "Reload the interface to change the language.\nRecarga la interfaz para cambiar el idioma.",
    button1 = "Reload / Recargar", button2 = "Later / Luego", reload = true,
    OnAccept = function() HU:Reload() end,
}
