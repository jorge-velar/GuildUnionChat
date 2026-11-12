-- Guild Union Reduce - ventanas sueltas que siguen haciendo falta: copiar texto, novedades, crear [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L
local UI = HU.UI
local K = UI.Kit
local T, Box, Label, Inset = K.T, K.Box, K.Label, K.Inset
local RedButton = K.RedButton
---------------------------------------------------------------------------
-- Ventana para copiar texto
---------------------------------------------------------------------------
-- opts (opcional): { hint = "texto de ayuda", button = "Borrar", onClick = function(f) end }
function UI:ShowCopy(title, text, opts)
    opts = opts or {}
    local f = self.copyFrame
    if not f then
        f = CreateFrame("Frame", "HermandadUnidaCopy", UIParent, "BackdropTemplate")
        f:SetScale(0.85)
        Box(f, T.frameBg, T.frameBorder, 16)
        f:SetSize(640, 460)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, "HermandadUnidaCopy")
        local close = HU.CloseButton(f)
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
        -- título arriba a la izquierda y, debajo, la ayuda (antes iban a la misma altura y se pisaban)
        f.title = Label(f, "", "GameFontNormalLarge", T.gold)
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -14)
        f.title:SetPoint("RIGHT", close, "LEFT", -6, 0)
        f.title:SetJustifyH("LEFT")
        f.hint = Label(f, "", "GameFontDisableSmall")
        f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
        local bg = Inset(f)
        bg:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -50)
        bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 46)
        local ok = RedButton(f, L("Cerrar"), 100, 24, function() f:Hide() end)
        ok:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
        f.extra = RedButton(f, "", 100, 24, function() if f.onExtra then f.onExtra(f) end end)
        f.extra:SetPoint("RIGHT", ok, "LEFT", -8, 0)
        local sf = CreateFrame("ScrollFrame", "HermandadUnidaCopyScroll", bg, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", bg, "TOPLEFT", 10, -10)
        sf:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -30, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(570)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        eb:SetScript("OnTextChanged", function(s, user) if user then s:SetText(f.text or ""); s:HighlightText() end end)
        sf:SetScrollChild(eb)
        f.edit = eb
        self.copyFrame = f
    end
    f.text = text
    f.title:SetText(title)
    f.hint:SetText(opts.hint or L("Ctrl+A selecciona todo  ·  Ctrl+C copia"))
    f.onExtra = opts.onClick
    f.extra:SetText(opts.button or "")
    f.extra:SetShown(opts.button ~= nil)
    f.edit:SetText(text)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end

-- Aviso a los oficiales de versiones viejas en su hermandad
local function OldVersions()
    local out = {}
    for _, p in pairs(HU.guildPeers or {}) do
        if p.ver and HU.VersionGreater(HU.version, p.ver) and GetTime() - (p.last or 0) < 600 then
            out[#out + 1] = HU:Nice(p.name) .. " (" .. p.ver .. ")"
        end
    end
    table.sort(out)
    return out
end
HU.OldVersions = OldVersions

