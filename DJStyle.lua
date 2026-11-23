-- Guild Union - estilo compartido de Calendario y Comercio: el del addon Dungeon Journal de Forever [+ARCHITECTURE.md]
-- Paneles de pizarra oscura con borde de tooltip, títulos dorados, rayas doradas de 1 px y
-- botones rojos del juego que, elegidos o pulsados, se quedan negros.
local _, HU = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TIP_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local DLG_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Border"
local PARCHMENT = "Interface\\QuestFrame\\QuestBG"

local DJ = {}
HU.DJ = DJ
DJ.ROW_HL = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
DJ.WHITE, DJ.TIP_BORDER = WHITE, TIP_BORDER
-- (los colores: pizarra fría, como el fondo de los bocadillos del juego y la piedra gris de la ventana de
-- hermandad; dorado del juego para títulos y lo elegido; sin marrones) [+ARCHITECTURE.md]
DJ.T = {
    -- (los fondos, los de WhisperMessenger: casi negro y grises muy oscuros, lisos)
    frame = { 0.03, 0.03, 0.03, 0.98 }, content = { 0.06, 0.06, 0.07, 0.95 }, border = { 0.40, 0.40, 0.45, 1 },
    header = { 0.09, 0.09, 0.10, 0.96 }, panel = { 0.05, 0.05, 0.06, 0.95 }, row = { 0.10, 0.10, 0.12, 0.95 },
    rowSel = { 0.16, 0.18, 0.28, 0.95 }, title = { 1.00, 0.82, 0.00 }, text = { 0.90, 0.90, 0.92 },
    muted = { 0.66, 0.68, 0.74 }, hover = { 1.00, 0.82, 0.00 }, line = { 1.00, 0.82, 0.00 },
}
local T = DJ.T

function DJ.Big(fs, size)
    local f, _, fl = fs:GetFont()
    if f then fs:SetFont(f, size, fl) end
end
function DJ.C(fs, c) fs:SetTextColor(c[1], c[2], c[3]); return fs end

-- Fondo liso y borde de tooltip (bg y border, colores de T)
function DJ.Panel(f, bg, border, edge, inset)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = TIP_BORDER, tile = true, tileSize = 16, edgeSize = edge or 12,
        insets = { left = inset or 3, right = inset or 3, top = inset or 3, bottom = inset or 3 } })
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end
-- (el grano de pergamino por encima, muy suave)
function DJ.Parchment(f, alpha)
    local tex = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    tex:SetPoint("TOPLEFT", 3, -3); tex:SetPoint("BOTTOMRIGHT", -3, 3)
    -- (con el fondo de WhisperMessenger, liso: se deja la textura pero sin verse)
    tex:SetTexture(PARCHMENT); tex:SetAlpha(0 * (alpha or 0))
    return tex
end
-- (una raya dorada de 1 px)
function DJ.Line(f, alpha)
    local l = f:CreateTexture(nil, "ARTWORK")
    l:SetColorTexture(T.line[1], T.line[2], T.line[3], alpha or 0.55); l:SetHeight(1)
    return l
end

-- Un botón rojo del juego (UIPanelButtonTemplate) elegido: sus tres piezas se quedan en gris oscuro (la misma
-- forma, en negro) con letra blanca; sin elegir, vuelve a rojo con letra dorada. Vale para cualquier botón rojo (también
-- los de arriba de la lista de miembros, UnionRoster.lua) [+ARCHITECTURE.md]
function DJ.PickRed(b, on)
    on = on and true or false
    if b.djPicked == on then return end
    b.djPicked = on
    -- (las mismas tres piezas del botón rojo, en gris y oscurecidas: queda negro con su misma forma)
    for _, k in ipairs({ "Left", "Middle", "Right" }) do
        local t = b[k]
        if t then
            t:SetDesaturated(on)
            if on then t:SetVertexColor(0.30, 0.30, 0.32) else t:SetVertexColor(1, 1, 1) end
        end
    end
    b:SetNormalFontObject(on and "GameFontHighlight" or "GameFontNormal")
end

-- Botón rojo del juego; :Pick(on) lo deja negro (elegido) y :Label(texto) cambia el texto
function DJ.Button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(text)
    function b:Pick(on) DJ.PickRed(self, on); self.picked = self.djPicked end
    function b:Label(t) self:SetText(t) end
    b.picked = false
    return b
end

-- (un icono redondo, como los retratos, con el aro del minimapa)
function DJ.RoundIcon(parent, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    if t.SetMask then t:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end
    local ring = parent:CreateTexture(nil, "OVERLAY")
    local k = size / 20
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); ring:SetSize(54 * k, 54 * k)
    ring:SetPoint("TOPLEFT", t, "TOPLEFT", -6 * k, 5 * k)
    return t
end

-- Una ventana como la del Dungeon Journal: fondo liso casi negro con marco de diálogo, franja de título con rayas
-- doradas, X y un panel de dentro («content»). Se mueve arrastrándola
function DJ.Window(name, parent, w, h, onClose)
    local d = CreateFrame("Frame", name, parent, "BackdropTemplate")
    d:SetSize(w, h)
    d:SetPoint("CENTER", parent, "CENTER", 0, 0)
    d:SetFrameStrata("DIALOG"); d:SetToplevel(true)
    d:SetBackdrop({ bgFile = WHITE, edgeFile = DLG_BORDER, tile = true, tileSize = 16, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    d:SetBackdropColor(T.frame[1], T.frame[2], T.frame[3], T.frame[4])
    d:EnableMouse(true)
    d:SetMovable(true); d:SetClampedToScreen(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:Hide()
    local strip = d:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT", 12, -10); strip:SetPoint("TOPRIGHT", -12, -10); strip:SetHeight(34)
    strip:SetColorTexture(0.09, 0.09, 0.10, 0.96)
    local top = DJ.Line(d, 0.65); top:SetPoint("TOPLEFT", strip, "TOPLEFT"); top:SetPoint("TOPRIGHT", strip, "TOPRIGHT")
    local bot = DJ.Line(d, 0.45); bot:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT")
    d.titleText = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.titleText:SetPoint("TOP", 0, -19); DJ.C(d.titleText, { 0.96, 0.79, 0.25 })
    local x = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", -3, -3)
    x:SetScript("OnClick", onClose or function() d:Hide() end)
    local content = CreateFrame("Frame", nil, d, "BackdropTemplate")
    content:SetPoint("TOPLEFT", 18, -52); content:SetPoint("BOTTOMRIGHT", -18, 44)
    DJ.Panel(content, T.content, T.border, 14, 4)
    DJ.Parchment(content, 0.18)
    d.content = content
    return d
end

HU:Module("DJStyle", { })
