-- Guild Union - pestaña propia dentro de la ventana de Whisper Messenger (copias 125 a 130, de prueba).
-- Whisper Messenger deja que otro addon registre un panel: le pone una pestaña junto a «Whispers» y
-- «Groups», con su número de no leídos, y le da el hueco vacío para dibujar. No usa ninguna librería
-- de interfaz y sus piezas son privadas, así que aquí se dibuja lo mismo con sus mismos valores:
-- estilo, tema, colores de burbuja, letras y medidas se leen de él. [+ARCHITECTURE.md]
-- Los valores de THEMES, BUBBLE_SETS y las medidas son de Whisper Messenger (licencia MIT,
-- Copyright (c) 2025 WhisperMessenger Contributors).
local _, HU = ...
local L = HU.L

-- (copia 156: filas silenciadas, ancladas y eliminadas de la pestaña de Whisper Messenger)
HU:Saved({ char = { "wmRows" } })

local PANEL_ID = "guildunion"
-- (copia 133) Los botones de la zona de escribir, como los suyos: 26 de lado, 4 entre ellos, icono de 18
local BTN, BTN_GAP, BTN_ICON, GUTTER = 26, 4, 18, 8
-- (copia 135) Sus 18 emojis, en el orden de su hoja (1024 x 256: 9 por fila, celdas de 112 x 128 con
-- el dibujo de 72 a 28 del borde). Su botón escribe «:nombre:» en la caja y su ventana lo pinta como
-- dibujo; aquí igual.
local EMOJI_KEYS = { "heart", "thumbsup", "laugh", "smile", "wink", "clap", "party", "fire", "gg",
    "wow", "sad", "cry", "angry", "thinking", "eyes", "question", "pray", "skull" }
local EMOJI_COLS = 9
local EMOJI_AT = {}
for i, k in ipairs(EMOJI_KEYS) do
    local x, y = 28 + ((i - 1) % EMOJI_COLS) * 112, 28 + math.floor((i - 1) / EMOJI_COLS) * 128
    EMOJI_AT[k] = { x, x + 72, y, y + 72 }
end
local WINK = { EMOJI_AT.wink[1] / 1024, EMOJI_AT.wink[2] / 1024, EMOJI_AT.wink[3] / 256, EMOJI_AT.wink[4] / 256 }
local KEEP, FILL = 150, 80            -- burbujas en pantalla como mucho; las que se cargan al abrir
local GROUP_SECS = 180                -- del mismo autor y seguidas en este tiempo: sin repetir la cabecera
-- (medidas de su tema: icono 24 con 8 de hueco, borde de la burbuja 12 y 8, 75 % del ancho, 4 entre
-- burbujas de un grupo y 12 entre grupos, cabecera 56, fila de la lista 48, zona de escribir 44)
local EDGE, ICON, ICON_GAP, PAD_X, PAD_Y, MAX_PCT = 12, 24, 8, 12, 8, 0.75
local SPACING, GROUP_GAP, TIME_GAP = 4, 12, 6
local HEADER_H, ROW_H, COMPOSER_H = 56, 48, 44
local LEFT = EDGE + ICON + ICON_GAP
local BORDER_LIGHTEN = 0.35           -- el borde de la burbuja: su color de fondo, aclarado esto
-- (copia 139, medido sobre capturas de Jorge: su bocadillo de una línea mide ~33 px de alto y el
-- nuestro ~25, y 9 px más de ancho con el mismo texto. Con el recuadro del juego, él suma el grosor
-- del borde al margen por cada lado. Y deja un poco más de hueco entre el nombre y el bocadillo.)
local BORDER_INSET, HEAD_GAP = 4, 6
local WM_MEDIA = "Interface\\AddOns\\WhisperMessenger\\Media\\"
-- (copia 131) Sus fondos no son colores: con el estilo «retail» pinta el panel de los mensajes y el de
-- la lista con dos texturas del juego, resalta la fila elegida con la del registro de misiones y
-- la caja de escribir lleva el borde de las cajas de texto del juego. Con «classic» deja los
-- fondos transparentes; con «off», colores lisos.
local ATLAS_PANE, ATLAS_LIST = "auctionhouse-background-index", "Professions-background-summarylist"
local TEX_SELECTED, TEX_HOVER = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local SELECTED_ALPHA, HOVER_ALPHA = 0.45, 0.18
local TEX_INPUT = "Interface\\Common\\Common-Input-Border"
local ICON_ALL, ICON_GUILD, ICON_UNKNOWN = "Interface\\ICONS\\Achievement_GuildPerk_EverybodysFriend",
    "Interface\\ICONS\\INV_Shield_06", "Interface\\ICONS\\Achievement_Character_Human_Male"

-- Sus temas de color (ajuste themePreset): burbuja de otros, burbuja mía, texto, texto mío, hora,
-- título, fondo del panel, fondo de la caja de escribir
local THEMES = {
    wow_default  = { bin = { 0.20, 0.24, 0.34, 0.95 }, bout = { 0.05, 0.30, 0.40, 0.90 }, text = { 0.92, 0.92, 0.95, 1 },
        bright = { 1, 1, 1, 1 }, time = { 1, 1, 1, 0.40 }, title = { 0.98, 0.99, 1.0, 1 }, second = { 1, 1, 1, 0.55 },
        surface = { 0.07, 0.07, 0.10, 0.97 }, input = { 0.17, 0.19, 0.26, 1 }, accent = { 0.12, 0.72, 0.96 } },
    elvui_dark   = { bin = { 0.16, 0.17, 0.20, 0.95 }, bout = { 0.13, 0.16, 0.20, 0.88 }, text = { 0.96, 0.96, 0.96, 1 },
        bright = { 1, 1, 1, 1 }, time = { 1, 1, 1, 0.40 }, title = { 0.99, 0.99, 1.0, 1 }, second = { 1, 1, 1, 0.55 },
        surface = { 0.03, 0.03, 0.03, 0.98 }, input = { 0.09, 0.10, 0.12, 1 }, accent = { 0.34, 0.51, 0.90 } },
    plumber_warm = { bin = { 0.24, 0.18, 0.14, 0.90 }, bout = { 0.55, 0.30, 0.18, 0.84 }, text = { 0.95, 0.90, 0.84, 1 },
        bright = { 1, 0.97, 0.92, 1 }, time = { 0.72, 0.60, 0.48, 1 }, title = { 1.0, 0.97, 0.92, 1 }, second = { 0.82, 0.72, 0.62, 1 },
        surface = { 0.12, 0.10, 0.08, 0.97 }, input = { 0.31, 0.22, 0.16, 0.98 }, accent = { 0.88, 0.56, 0.22 } },
    jade_dark    = { bin = { 0.14, 0.14, 0.14, 0.95 }, bout = { 0.09, 0.22, 0.19, 0.90 }, text = { 0.96, 0.96, 0.96, 1 },
        bright = { 1, 1, 1, 1 }, time = { 1, 1, 1, 0.40 }, title = { 0.99, 1.0, 0.99, 1 }, second = { 1, 1, 1, 0.55 },
        surface = { 0.067, 0.067, 0.067, 0.94 }, input = { 0.10, 0.10, 0.10, 1 }, accent = { 0.047, 0.824, 0.616 } },
    wow_native   = { bin = { 0.18, 0.20, 0.26, 0.95 }, bout = { 0.24, 0.19, 0.09, 0.92 }, text = { 1, 1, 1, 1 },
        bright = { 1, 1, 1, 1 }, time = { 1, 1, 1, 0.40 }, title = { 1.0, 0.82, 0.0, 1 }, second = { 1, 1, 1, 0.55 },
        surface = { 0.06, 0.06, 0.07, 0.97 }, input = { 0.16, 0.14, 0.10, 1 }, accent = { 1.0, 0.82, 0.0 } },
}
THEMES.ellesmere_ui = THEMES.elvui_dark -- (lo calcula de los colores de EllesmereUI: aquí, el oscuro más parecido)
-- Sus juegos de color de burbuja (ajuste bubbleColorPreset; «default» = los del tema)
local BUBBLE_SETS = {
    shadow = { { 0.16, 0.17, 0.20, 0.95 }, { 0.13, 0.16, 0.20, 0.88 } },
    ember  = { { 0.24, 0.18, 0.14, 0.90 }, { 0.55, 0.30, 0.18, 0.84 } },
    arcane = { { 0.22, 0.14, 0.30, 0.92 }, { 0.36, 0.18, 0.48, 0.85 } },
    frost  = { { 0.18, 0.22, 0.30, 0.92 }, { 0.28, 0.42, 0.58, 0.82 } },
    fel    = { { 0.10, 0.22, 0.12, 0.90 }, { 0.14, 0.38, 0.16, 0.82 } },
}

local api                 -- lo que devuelve WhisperMessengerAPI.Connect
local registered = false
local root, pane, list, lbg, header, hbg, hdiv, cbg, cdiv, comp, scroll, content, edit, hint, thumb, rows
local topShade, bottomShade
-- (copia 132, como él: una sombra de 10 px arriba y abajo de los mensajes, negra al 35 %, que solo
-- sale si hay mensajes por ese lado; y los bocadillos se desvanecen en los últimos 24 px del borde)
local SHADE_H, SHADE_ALPHA, FADE = 10, 0.35, 24
local bubbles, shownEntries, lastBy = {}, {}, {}
local skin, builtOn       -- el aspecto de ahora (Skin) y con qué tipo de marco se hicieron las burbujas
local filter              -- nil = todas; o la etiqueta de una hermandad
local shown, badgeDue, layoutDue, stick = false, false, false, true
-- (copia 156) Clic derecho en las filas, como el de Whisper Messenger: marcar como no leídos, exportar,
-- silenciar, anclar arriba y eliminar. Los no leídos van por fila; silenciadas, ancladas y
-- eliminadas se guardan por personaje (db.wmRows). [+ARCHITECTURE.md]
local unreadBy = {}       -- [etiqueta o "*"] = no leídos de esa fila
local function RowKey(tag) return tag or "*" end
local function RowPrefs()
    local db = HU.db
    if not db then return { muted = {}, pinned = {}, hidden = {} } end
    local p = db.wmRows
    if type(p) ~= "table" then
        p = {}
        db.wmRows = p
    end
    p.muted = type(p.muted) == "table" and p.muted or {}
    p.pinned = type(p.pinned) == "table" and p.pinned or {}   -- [clave] = hora en que se ancló
    p.hidden = type(p.hidden) == "table" and p.hidden or {}
    return p
end
local function TotalUnread()
    local n = 0
    for _, c in pairs(unreadBy) do n = n + c end
    return math.min(999, n)
end
-- (al ver una fila se dan por leídas las suyas; la de «todas», todas)
local function ClearUnread(tag)
    if tag then unreadBy[tag] = nil else unreadBy = {} end
end
HU.wmStats = { tries = 0 }

-- El aspecto que el jugador tiene puesto en Whisper Messenger, leído de él
local function Skin()
    local db = _G.WhisperMessengerDB
    local S = type(db) == "table" and type(db.settings) == "table" and db.settings or {}
    local look = api and api.GetLook and api.GetLook()
    look = type(look) == "table" and look or {}
    local hud = look.hud
    if hud ~= "off" and hud ~= "classic" and hud ~= "retail" then hud = S.hudStyle end
    if hud ~= "off" and hud ~= "classic" and hud ~= "retail" then hud = "retail" end
    local t = THEMES[S.themePreset] or (hud == "off" and THEMES.wow_default or THEMES.wow_native)
    local set = BUBBLE_SETS[S.bubbleColorPreset]
    return { hud = hud, on = hud ~= "off", c = type(look.colors) == "table" and look.colors or {}, t = t,
        bin = set and set[1] or t.bin, bout = set and set[2] or t.bout }
end
local function Paint(tex, c, fb)
    c = type(c) == "table" and c or fb
    tex:SetColorTexture(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
end
-- Sus letras (WM_Highlight, WM_DisableSmall...): las crea con nombre y siguen el tamaño y el tipo que
-- el jugador elija en sus ajustes. Si no están, se queda la del juego con la que se creó el texto.
local function UseFont(fs, name)
    local f = _G[name]
    if type(f) == "table" and type(f.GetFont) == "function" and fs.SetFontObject then pcall(fs.SetFontObject, fs, f) end
end
local function Text(parent, wmFont, gameFont)
    local fs = parent:CreateFontString(nil, "OVERLAY", gameFont)
    UseFont(fs, wmFont)
    return fs
end
-- La hora como la enseña él: 24 h si el jugador lo tiene así en el reloj del juego; si no, «12:17 AM»
local function Clock(t)
    if GetCVarBool and GetCVarBool("timeMgrUseMilitaryTime") then return HU.SafeDate("%H:%M", t) end
    return (HU.SafeDate("%I:%M", t):gsub("^0", "")) .. " " .. HU.SafeDate("%p", t)
end
local function Plain(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|", ""))
end
-- Un fondo liso de esquinas redondeadas sobre el marco f, hecho como el suyo: cinco rectángulos y
-- cuatro esquinas (cuartos del círculo de retratos del juego), todo del mismo color.
local function Rounded(f, R)
    local fills, corners = {}, {}
    local function fill()
        local t = f:CreateTexture(nil, "BACKGROUND")
        fills[#fills + 1] = t
        return t
    end
    local c = fill()
    c:SetPoint("TOPLEFT", R, -R)
    c:SetPoint("BOTTOMRIGHT", -R, R)
    local top = fill()
    top:SetPoint("TOPLEFT", R, 0)
    top:SetPoint("TOPRIGHT", -R, 0)
    top:SetHeight(R)
    local bot = fill()
    bot:SetPoint("BOTTOMLEFT", R, 0)
    bot:SetPoint("BOTTOMRIGHT", -R, 0)
    bot:SetHeight(R)
    local lft = fill()
    lft:SetPoint("TOPLEFT", 0, -R)
    lft:SetPoint("BOTTOMLEFT", 0, R)
    lft:SetWidth(R)
    local rgt = fill()
    rgt:SetPoint("TOPRIGHT", 0, -R)
    rgt:SetPoint("BOTTOMRIGHT", 0, R)
    rgt:SetWidth(R)
    local function corner(point, x1, x2, y1, y2)
        local t = f:CreateTexture(nil, "BACKGROUND")
        t:SetSize(R, R)
        t:SetPoint(point)
        t:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall")
        t:SetTexCoord(x1, x2, y1, y2)
        corners[#corners + 1] = t
    end
    corner("TOPLEFT", 0, 0.5, 0, 0.5)
    corner("TOPRIGHT", 0.5, 1, 0, 0.5)
    corner("BOTTOMLEFT", 0, 0.5, 0.5, 1)
    corner("BOTTOMRIGHT", 0.5, 1, 0.5, 1)
    local o = {}
    function o.color(r, g, b, a)
        for _, t in ipairs(fills) do t:SetColorTexture(r, g, b, a or 1) end
        for _, t in ipairs(corners) do t:SetVertexColor(r, g, b, a or 1) end
    end
    function o.show(v)
        for _, t in ipairs(fills) do t:SetShown(v) end
        for _, t in ipairs(corners) do t:SetShown(v) end
    end
    return o
end

-- El marco de una burbuja o de la caja de escribir. Con el estilo «classic» o «retail» es el marco
-- de los recuadros de ayuda del juego (como hace él); con «off», un fondo liso.
local function Box(parent, on)
    if on then
        local ok, f = pcall(CreateFrame, "Frame", nil, parent, "TooltipBackdropTemplate")
        if ok and f and f.SetBackdropColor then return f end
        f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        return f
    end
    -- (con «off»: fondo liso redondeado de radio 8, sin borde)
    local f = CreateFrame("Frame", nil, parent)
    local rb = Rounded(f, 8)
    function f:SetBackdropColor(r, g, b, a) rb.color(r, g, b, a) end
    f.flat = true
    return f
end
local function Tint(f, c)
    local r, g, b, a = c[1], c[2], c[3], c[4] or 1
    f:SetBackdropColor(r, g, b, a)
    if f.SetBackdropBorderColor then
        local n = f.flat and 0 or BORDER_LIGHTEN
        pcall(f.SetBackdropBorderColor, f, r + (1 - r) * n, g + (1 - g) * n, b + (1 - b) * n, a)
    end
end
-- Pone en tex una textura del juego por su nombre; false si este juego no la tiene
local function Atlas(tex, name)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
    if not info or not tex.SetAtlas then return false end
    tex:SetAtlas(name, false)
    tex:SetVertexColor(1, 1, 1, 1)
    return true
end
local function Flat(tex, c, fb)
    tex:SetTexture(nil)
    tex:SetVertexColor(1, 1, 1, 1)
    Paint(tex, c, fb)
end
-- La caja de escribir con el borde de las cajas de texto del juego (tres trozos: izquierda, centro
-- y derecha) y un relleno detrás que se tiñe
-- El borde de la caja de escribir con el estilo nativo, como el suyo: tres trozos en el fondo de la
-- propia caja de texto, los laterales de 8 de ancho y a toda la altura, y el centro entre los dos.
-- Con «retail», los de las cajas de búsqueda del juego si existen; si no, el de las cajas de texto.
local function NativeBorder(frame)
    local l = frame:CreateTexture(nil, "BACKGROUND")
    local m = frame:CreateTexture(nil, "BACKGROUND")
    local r = frame:CreateTexture(nil, "BACKGROUND")
    l:SetWidth(8)
    l:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    l:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    r:SetWidth(8)
    r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT", 0, 0)
    m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT", 0, 0)
    local o = { used = "ninguno" }
    function o.apply(retail)
        local atlas = retail and l.SetAtlas and C_Texture and C_Texture.GetAtlasInfo
            and C_Texture.GetAtlasInfo("common-search-border-left") ~= nil
        if atlas then
            l:SetAtlas("common-search-border-left", false)
            m:SetAtlas("common-search-border-middle", false)
            r:SetAtlas("common-search-border-right", false)
            o.used = "cajas de búsqueda"
        else
            local tc = { { 0, 0.0625 }, { 0.0625, 0.9375 }, { 0.9375, 1 } }
            for i, t in ipairs({ l, m, r }) do
                t:SetTexture(TEX_INPUT)
                t:SetTexCoord(tc[i][1], tc[i][2], 0, 0.625)
            end
            o.used = "cajas de texto"
        end
    end
    function o.show(v)
        l:SetShown(v)
        m:SetShown(v)
        r:SetShown(v)
    end
    return o
end
local function Round(tex, owner)
    if owner.CreateMaskTexture and tex.AddMaskTexture then
        local mask = owner:CreateMaskTexture()
        mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(tex)
        tex:AddMaskTexture(mask)
    end
end
-- El marco dorado redondeado que él pone a los iconos (su imagen; si no está, no se ve nada)
local function Framed(owner, tex)
    local fr = owner:CreateTexture(nil, "OVERLAY")
    fr:SetPoint("TOPLEFT", tex, "TOPLEFT", -3, 3)
    fr:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 3, -3)
    fr:SetTexture(WM_MEDIA .. "frame_gold_square_rounded.png")
end

-- ¿Vale esta entrada del historial para el panel? (tag: el filtro; nil = todas)
local function Wanted(e, tag)
    if type(e) ~= "table" or e.k ~= "main" or not e.a or not e.m or not e.tag then return false end
    if type(e.m) ~= "string" or type(e.a) ~= "string" or HU.Secret(e.m) or HU.Secret(e.a) then return false end
    return not tag or e.tag == tag
end

local function ClassOf(e)
    return HU:ClassFor(e.a, e.g)
end

-- «:heart:» y compañía, pintados con su hoja de emojis (solo existe si él está instalado, y este
-- panel solo existe entonces)
local function Emojis(s)
    if not s:find(":", 1, true) then return s end
    return (s:gsub(":(%a+):", function(k)
        local c = EMOJI_AT[k]
        if not c then return nil end
        return "|T" .. WM_MEDIA .. "reactions.png:16:16:0:0:1024:256:" .. c[1] .. ":" .. c[2] .. ":" .. c[3] .. ":" .. c[4] .. "|t"
    end))
end

local function OnLink(self, link, text, button)
    if type(SetItemRef) == "function" then pcall(SetItemRef, link, text, button, self) end
end

local function NewBubble()
    local row = CreateFrame("Frame", nil, content)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Round(row.icon, row)
    row.name = Text(row, "WM_HighlightSmall", "GameFontHighlightSmall")
    row.name:SetJustifyH("LEFT")
    row.when = Text(row, "WM_DisableSmall", "GameFontDisableSmall")
    row.box = Box(row, skin.on)
    row.text = Text(row.box, "WM_Highlight", "GameFontHighlight")
    row.text:SetJustifyH("LEFT")
    row.text:SetJustifyV("TOP")
    row.text:SetWordWrap(true)
    if row.text.SetNonSpaceWrap then row.text:SetNonSpaceWrap(true) end
    -- (para que se pueda pulsar el nombre y los enlaces de objetos)
    pcall(row.SetHyperlinksEnabled, row, true)
    pcall(row.box.SetHyperlinksEnabled, row.box, true)
    row:SetScript("OnHyperlinkClick", OnLink)
    row.box:SetScript("OnHyperlinkClick", OnLink)
    -- (copia 146) El botón de copiar, como el suyo (HoverCopy.lua): un icono de 14, al 45 %, que sale
    -- en la esquina de arriba del bocadillo al pasar el ratón; al pulsarlo, una ventana con el texto.
    local copy = CreateFrame("Button", nil, row)
    copy:SetSize(14, 14)
    local ct = copy:CreateTexture(nil, "OVERLAY")
    ct:SetAllPoints()
    ct:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    copy:SetAlpha(0.45)
    copy:Hide()
    copy:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L("Copiar texto"))
            GameTooltip:Show()
        end
    end)
    copy:SetScript("OnLeave", function(self)
        self:SetAlpha(0.45)
        if GameTooltip then GameTooltip:Hide() end
        if not row.box:IsMouseOver() then self:Hide() end
    end)
    copy:SetScript("OnClick", function()
        local e = row.entry
        if e and type(e.m) == "string" and HU.UI and HU.UI.ShowCopy then
            HU.UI:ShowCopy(L("Copiar texto"), Plain(e.m))
        end
    end)
    row.copy = copy
    row.box:EnableMouse(true)
    row.box:SetScript("OnEnter", function() copy:Show() end)
    row.box:SetScript("OnLeave", function() if not copy:IsMouseOver() then copy:Hide() end end)
    row.box:SetScript("OnHide", function() copy:Hide() end)
    return row
end

local function MaxScroll()
    return math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
end
local function UpdateEdges()
    if not (scroll and content) then return end
    local off, max, view = scroll:GetVerticalScroll() or 0, MaxScroll(), scroll:GetHeight() or 0
    if topShade then
        topShade:SetShown(off > 1)
        bottomShade:SetShown(off < max - 1)
    end
    for i = 1, #shownEntries do
        local row = bubbles[i]
        if row and row.y then
            local t = row.y - off
            local a = math.min(math.max(0, math.min((t + row.h) / FADE, 1)), math.max(0, math.min((view - t) / FADE, 1)))
            row:SetAlpha(a)
        end
    end
end
local function UpdateThumb()
    UpdateEdges()
    if not thumb then return end
    local view, total = scroll:GetHeight() or 0, content:GetHeight() or 0
    if total <= view + 1 or view < 20 then return thumb:Hide() end
    local h = math.max(24, view * view / total)
    local pos = (scroll:GetVerticalScroll() or 0) / math.max(1, total - view)
    thumb:SetHeight(h)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 4, -pos * (view - h))
    thumb:Show()
end

-- Coloca todas las burbujas de arriba abajo. Las alturas dependen del ancho, así que se rehace entero
-- (son 150 como mucho, y solo con el panel a la vista)
local function Layout()
    layoutDue = false
    if not (content and scroll and shown and skin) then return end
    local width = scroll:GetWidth() or 0
    if width < 120 then return end
    content:SetWidth(width)
    local px, py = PAD_X + (skin.on and BORDER_INSET or 0), PAD_Y + (skin.on and BORDER_INSET or 0)
    local maxText = math.max(80, math.floor(width * MAX_PCT) - 2 * px)
    local me, t = HU:MeKey(), skin.t
    local y, prev = 2, nil
    for i, e in ipairs(shownEntries) do
        local row = bubbles[i]
        if not row then row = NewBubble(); bubbles[i] = row end
        local grouped = prev ~= nil and prev.a == e.a and prev.tag == e.tag and math.abs((e.t or 0) - (prev.t or 0)) <= GROUP_SECS
        local mine = HU:Key(e.a) == me
        local top = 0
        if grouped then
            row.icon:Hide(); row.name:Hide(); row.when:Hide()
            y = y + SPACING
        else
            y = y + GROUP_GAP
            local class = ClassOf(e)
            if type(class) == "string" and class:match("^%a+$") then
                row.icon:SetTexture("Interface\\ICONS\\ClassIcon_" .. class)
            else
                row.icon:SetTexture(ICON_UNKNOWN)
            end
            -- (el nombre, con el color de su clase como hace él; delante, el punto de su hermandad
            -- cuando se ven todas juntas: es lo único que él no tiene y aquí hace falta)
            local r, g, b = HU.ClassRGB(class)
            local hex = r and string.format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
            local nice = HU:Nice(e.a)
            row.name:SetTextColor(t.second[1], t.second[2], t.second[3], 1)
            row.name:ClearAllPoints()
            row.when:ClearAllPoints()
            if mine then
                -- (copia 138, como él: lo mío a la derecha, con la hora y «Tú» encima)
                row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(LEFT + 2), 0)
                row.when:SetPoint("RIGHT", row.name, "LEFT", -TIME_GAP, 0)
                row.name:SetText(L("Tú"))
            else
                row.name:SetPoint("TOPLEFT", row, "TOPLEFT", LEFT + 2, 0)
                row.when:SetPoint("LEFT", row.name, "RIGHT", TIME_GAP, 0)
                -- (copia 137: sin clase sabida, el mismo naranja que en el chat; Jorge, 08/11)
                row.name:SetText(((not filter) and (HU:DotText(e.tag) .. " ") or "")
                    .. "|Hplayer:" .. e.a .. "|h|cff" .. (hex or "ff9933") .. nice .. "|r|h")
            end
            row.when:SetTextColor(t.time[1], t.time[2], t.time[3], t.time[4])
            row.when:SetText(Clock(e.t))
            row.icon:Show(); row.name:Show(); row.when:Show()
            top = (row.name:GetStringHeight() or 10) + HEAD_GAP
        end
        local tc = mine and t.bright or t.text
        row.text:SetTextColor(tc[1], tc[2], tc[3], tc[4])
        row.text:SetWidth(maxText)
        row.text:SetText(Emojis(HU:Emotes(HU:HighlightMentions(e.m, e.a, e.tag))))
        local tw = math.min(maxText, math.max(12, (row.text.GetUnboundedStringWidth and row.text:GetUnboundedStringWidth()) or maxText))
        row.text:SetWidth(tw)
        local th = row.text:GetStringHeight() or 12
        local bh = th + 2 * py
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", row.box, "TOPLEFT", px, -py)
        row.box:ClearAllPoints()
        if mine then
            row.box:SetPoint("TOPRIGHT", row, "TOPRIGHT", -LEFT, -top)
        else
            row.box:SetPoint("TOPLEFT", row, "TOPLEFT", LEFT, -top)
        end
        row.box:SetSize(tw + 2 * px, bh)
        Tint(row.box, mine and skin.bout or skin.bin)
        row.entry = e
        row.copy:ClearAllPoints()
        if mine then
            row.copy:SetPoint("TOPLEFT", row.box, "TOPLEFT", 5, 7)
        else
            row.copy:SetPoint("TOPRIGHT", row.box, "TOPRIGHT", -5, 7)
        end
        row.copy:SetFrameLevel((row.box:GetFrameLevel() or 1) + 10)
        row.copy:Hide()
        -- (el icono, a la altura de la burbuja)
        row.icon:ClearAllPoints()
        local iy = -top - math.max(0, (math.min(bh, 34) - ICON) / 2)
        if mine then
            row.icon:SetPoint("TOPRIGHT", row, "TOPRIGHT", -EDGE, iy)
        else
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", EDGE, iy)
        end
        local h = top + bh
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetSize(width, h)
        row:Show()
        row.y, row.h = y, h
        y = y + h
        prev = e
    end
    for i = #shownEntries + 1, #bubbles do bubbles[i]:Hide() end
    content:SetHeight(y + 10)
    if stick then scroll:SetVerticalScroll(MaxScroll()) end
    UpdateThumb()
end
local function AskLayout()
    if layoutDue then return end
    layoutDue = true
    HU.After(0, function()
        local ok, err = pcall(Layout)
        if not ok then HU.wmStats.err = tostring(err) end
    end)
end

-- La lista de la izquierda: una fila por «todas» y por hermandad, con su último mensaje y la hora
local function RowTexts()
    if not (rows and skin) then return end
    local c, t = skin.c, skin.t
    for _, row in ipairs(rows) do
        local sel = (row.tag or false) == (filter or false)
        if skin.on then
            local a = t.accent
            row.bg:SetTexture(TEX_SELECTED)
            row.bg:SetBlendMode("ADD")
            row.bg:SetVertexColor(a[1], a[2], a[3], sel and SELECTED_ALPHA or 0)
            row.hl:SetTexture(TEX_HOVER)
            row.hl:SetBlendMode("ADD")
            row.hl:SetVertexColor(1, 1, 1, HOVER_ALPHA)
        else
            row.bg:SetBlendMode("BLEND")
            row.hl:SetBlendMode("BLEND")
            if sel then Flat(row.bg, c.bg_contact_selected, { 1, 0.82, 0, 0.16 }) else Flat(row.bg, nil, { 0, 0, 0, 0 }) end
            Flat(row.hl, c.bg_contact_hover, { 1, 1, 1, 0.05 })
        end
        row.title:SetTextColor(t.title[1], t.title[2], t.title[3], 1)
        row.sub:SetTextColor(t.second[1], t.second[2], t.second[3], t.second[4])
        row.when:SetTextColor(t.time[1], t.time[2], t.time[3], t.time[4])
        local e = lastBy[row.tag or "*"]
        if e then
            row.sub:SetText(Plain(e.m))
            row.when:SetText((time() - (e.t or 0) < 60) and L("ahora") or Clock(e.t))
        else
            row.sub:SetText("")
            row.when:SetText("")
        end
        local p, key = RowPrefs(), RowKey(row.tag)
        row.muteIc:SetShown(p.muted[key] and true or false)
        row.muteIc:SetVertexColor(t.second[1], t.second[2], t.second[3], 1)
        row.pinIc:SetShown(p.pinned[key] and true or false)
        row.pinIc:SetVertexColor(t.second[1], t.second[2], t.second[3], 1)
        local n = unreadBy[key] or 0
        row.count:SetText(n > 0 and tostring(math.min(n, 99)) or "")
        row.count:SetTextColor(t.accent[1], t.accent[2], t.accent[3], p.muted[key] and 0.5 or 1)
    end
    if header then
        header.icon:SetTexture(filter and ICON_GUILD or ICON_ALL)
        header.title:SetText(filter and (HU:GuildName(filter) or filter) or L("Todas las hermandades"))
    end
end

-- Pone a todo lo fijo los colores del aspecto de ahora; si ha cambiado el tipo de marco, las
-- burbujas se hacen de nuevo
local function ApplySkin()
    skin = Skin()
    local c, t = skin.c, skin.t
    if skin.hud == "retail" then
        if not Atlas(pane, ATLAS_PANE) then Flat(pane, c.bg_primary, t.surface) end
        if not Atlas(lbg, ATLAS_LIST) then Flat(lbg, c.bg_secondary, { 0.10, 0.09, 0.08, 0.60 }) end
    elseif skin.hud == "classic" then
        Flat(pane, nil, { 0, 0, 0, 0 })
        Flat(lbg, nil, { 0, 0, 0, 0 })
    else
        Flat(pane, c.bg_primary, t.surface)
        Flat(lbg, c.bg_secondary, { 0.10, 0.09, 0.08, 0.60 })
    end
    Paint(hbg, c.bg_header, { 0.09, 0.08, 0.07, 0.60 })
    Paint(hdiv, c.divider, { 1, 1, 1, 0.08 })
    -- la zona de escribir, como la suya: con el estilo nativo, sin fondo ni raya y con el borde de
    -- tres trozos en la caja; con «off», fondo de cromo, raya arriba, brillo y la caja redondeada
    root.csheen:SetShown(not skin.on)
    edit.rounded.show(not skin.on)
    edit.native.show(skin.on)
    if skin.on then
        cbg:SetColorTexture(0, 0, 0, 0)
        cdiv:SetColorTexture(0, 0, 0, 0)
        edit.native.apply(skin.hud == "retail")
    else
        Paint(cbg, c.bg_header, { 0.09, 0.08, 0.07, 0.60 })
        Paint(cdiv, c.divider, { 1, 1, 1, 0.08 })
        local ic = type(c.bg_input) == "table" and c.bg_input or t.input
        edit.rounded.color(ic[1], ic[2], ic[3], ic[4] or 1)
    end
    Paint(thumb, c.scrollbar, { 1, 1, 1, 0.14 })
    header.title:SetTextColor(t.title[1], t.title[2], t.title[3], 1)
    header.kind:SetTextColor(t.second[1], t.second[2], t.second[3], t.second[4])
    hint:SetTextColor(t.second[1], t.second[2], t.second[3], t.second[4])
    edit:SetTextColor(t.text[1], t.text[2], t.text[3], 1)
    if skin.on then
        -- (con el estilo nativo: texto blanco y la ayuda en gris medio)
        edit:SetTextColor(1, 1, 1, 1)
        hint:SetTextColor(0.5, 0.5, 0.5, 1)
    end
    if root.sendIcon then
        local a = t.accent
        root.sendIcon:SetVertexColor(a[1], a[2], a[3], 1)
    end
    if builtOn ~= skin.hud then
        for _, row in ipairs(bubbles) do row:Hide() end
        bubbles = {}
        builtOn = skin.hud
    end
end

local function Fill()
    shownEntries, lastBy = {}, {}
    local h = HU.db and HU.db.history or {}
    local tmp, n = {}, 0
    for i = #h, math.max(1, #h - 1500), -1 do
        local e = h[i]
        if Wanted(e) then
            if not lastBy["*"] then lastBy["*"] = e end
            if not lastBy[e.tag] then lastBy[e.tag] = e end
            if n < FILL and (not filter or e.tag == filter) then
                n = n + 1
                tmp[n] = e
            end
        end
    end
    for i = n, 1, -1 do shownEntries[#shownEntries + 1] = tmp[i] end
    stick = true
    RowTexts()
    AskLayout()
end

local function BuildRows()
    for _, row in ipairs(rows or {}) do row:Hide() end
    rows = {}
    local p = RowPrefs()
    local all = { { tag = nil, text = L("Todas las hermandades"), icon = ICON_ALL, o = 0 } }
    for i, g in ipairs(HU.cfg and HU.cfg.guilds or {}) do
        all[#all + 1] = { tag = g.tag, text = HU:DotText(g.tag) .. " " .. (HU:GuildName(g.tag) or g.tag), icon = ICON_GUILD, o = i }
    end
    local items = {}
    for _, it in ipairs(all) do
        if not p.hidden[RowKey(it.tag)] then items[#items + 1] = it end
    end
    if #items == 0 then items[1] = all[1] end
    -- (las ancladas arriba, en el orden en que se anclaron; las demás, en su orden de siempre)
    table.sort(items, function(a, b)
        local pa, pb = p.pinned[RowKey(a.tag)], p.pinned[RowKey(b.tag)]
        if pa and pb then return pa < pb end
        if pa or pb then return pa ~= nil end
        return a.o < b.o
    end)
    for i, it in ipairs(items) do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -(i - 1) * ROW_H - 6)
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(i - 1) * ROW_H - 6)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        local ic = row:CreateTexture(nil, "ARTWORK")
        ic:SetSize(34, 34)
        ic:SetPoint("LEFT", 8, 0)
        ic:SetTexture(it.icon)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        Framed(row, ic)
        row.when = Text(row, "WM_DisableSmall", "GameFontDisableSmall")
        row.when:SetPoint("TOPRIGHT", -8, -8)
        -- (como las suyas: campana tachada a la izquierda de la hora; chincheta y número abajo)
        row.muteIc = row:CreateTexture(nil, "OVERLAY")
        row.muteIc:SetSize(12, 12)
        row.muteIc:SetPoint("RIGHT", row.when, "LEFT", -3, 0)
        row.muteIc:SetTexture(WM_MEDIA .. "muted.png")
        row.count = Text(row, "WM_Normal", "GameFontNormal")
        row.count:SetPoint("BOTTOMRIGHT", -8, 8)
        row.pinIc = row:CreateTexture(nil, "OVERLAY")
        row.pinIc:SetSize(12, 12)
        row.pinIc:SetPoint("RIGHT", row.count, "LEFT", -3, 0)
        row.pinIc:SetTexture(WM_MEDIA .. "pinned.png")
        row.title = Text(row, "WM_Normal", "GameFontNormal")
        row.title:SetPoint("TOPLEFT", ic, "TOPRIGHT", 10, -1)
        row.title:SetPoint("RIGHT", row.muteIc, "LEFT", -3, 0)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)
        row.title:SetText(it.text)
        row.sub = Text(row, "WM_DisableSmall", "GameFontDisableSmall")
        row.sub:SetPoint("BOTTOMLEFT", ic, "BOTTOMRIGHT", 10, 1)
        row.sub:SetPoint("RIGHT", row.pinIc, "LEFT", -4, 0)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row.tag = it.tag
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                HU.WMRowMenu(self, it.tag)
                return
            end
            filter = it.tag
            ClearUnread(it.tag)
            HU.WMRefreshBadge()
            Fill()
        end)
        rows[i] = row
    end
    RowTexts()
end

local function Build(frame)
    root = CreateFrame("Frame", nil, frame)
    root:SetAllPoints(frame)

    list = CreateFrame("Frame", nil, root)
    list:SetPoint("TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMLEFT", 0, 0)
    list:SetWidth(290)
    lbg = list:CreateTexture(nil, "BACKGROUND")
    lbg:SetAllPoints()

    -- (el fondo de la parte de los mensajes: sin pintarlo se veía la textura de la ventana)
    pane = root:CreateTexture(nil, "BACKGROUND")
    pane:SetPoint("TOPLEFT", list, "TOPRIGHT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)

    -- cabecera de la conversación, como la suya: icono, nombre, marca pequeña y una raya debajo
    header = CreateFrame("Frame", nil, root)
    header:SetPoint("TOPLEFT", list, "TOPRIGHT", 0, 0)
    header:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_H)
    hbg = header:CreateTexture(nil, "BORDER")
    hbg:SetAllPoints()
    -- (copia 140, como él: un brillo blanco al 5 % sobre la cabecera, que se apaga hacia abajo. Sin
    -- él la cabecera era un color plano y, junto a la sombra de los mensajes, parecía hundida)
    local sheen = header:CreateTexture(nil, "BORDER", nil, 1)
    sheen:SetAllPoints()
    sheen:SetColorTexture(1, 1, 1, 0.05)
    if sheen.SetGradient and CreateColor then
        pcall(sheen.SetGradient, sheen, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1))
    end
    header.icon = header:CreateTexture(nil, "ARTWORK")
    header.icon:SetSize(32, 32)
    header.icon:SetPoint("LEFT", 14, 0)
    header.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Framed(header, header.icon)
    header.title = Text(header, "WM_HighlightLarge", "GameFontHighlightLarge")
    header.title:SetPoint("TOPLEFT", header.icon, "TOPRIGHT", 12, -1)
    header.title:SetJustifyH("LEFT")
    header.title:SetWordWrap(false)
    header.kind = Text(header, "WM_DisableSmall", "GameFontDisableSmall")
    header.kind:SetPoint("BOTTOMLEFT", header.title, "BOTTOMRIGHT", 8, 3)
    header.kind:SetText("[" .. (HU.ADDON_TITLE or "Guild Union") .. "]")
    hdiv = header:CreateTexture(nil, "ARTWORK")
    hdiv:SetPoint("BOTTOMLEFT")
    hdiv:SetPoint("BOTTOMRIGHT")
    hdiv:SetHeight(1)

    -- (copia 144) La zona de escribir, pieza por pieza como la suya (Composer.lua, ComposerSurface.lua
    -- y ComposerLayout.lua de Whisper Messenger):
    --   · un panel de 44 de alto pegado abajo, con su fondo, una raya de 1 arriba y un brillo;
    --   · la caja de texto a 8 de la izquierda y a 8 del suelo, de 28 de alto, y hasta dejar sitio a
    --     tres botones de 26 con 4 de hueco y 8 de margen;
    --   · el texto con márgenes 8, 8, 4, 4 y la ayuda a 8 de la izquierda;
    --   · los adornos van EN la propia caja de texto: fondo redondeado con «off», borde de tres
    --     trozos con «classic» y «retail» (ver ApplySkin).
    comp = CreateFrame("Frame", nil, root)
    comp:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 0, 0)
    comp:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    comp:SetHeight(COMPOSER_H)
    cbg = comp:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    cdiv = comp:CreateTexture(nil, "OVERLAY")
    cdiv:SetPoint("TOPLEFT")
    cdiv:SetPoint("TOPRIGHT")
    cdiv:SetHeight(1)
    root.csheen = comp:CreateTexture(nil, "BACKGROUND", nil, 1)
    root.csheen:SetAllPoints()
    root.csheen:SetColorTexture(1, 1, 1, 0.05)
    if root.csheen.SetGradient and CreateColor then
        pcall(root.csheen.SetGradient, root.csheen, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1))
    end
    edit = CreateFrame("EditBox", nil, comp)
    edit:SetPoint("BOTTOMLEFT", comp, "BOTTOMLEFT", GUTTER, GUTTER)
    edit:SetPoint("BOTTOMRIGHT", comp, "BOTTOMRIGHT", -(GUTTER + 3 * BTN + 3 * BTN_GAP), GUTTER)
    edit:SetHeight(COMPOSER_H - 2 * GUTTER)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(255)
    edit:SetFontObject(GameFontHighlight)
    UseFont(edit, "WM_ChatNormal")
    edit:SetTextInsets(8, 8, 4, 4)
    if edit.SetAltArrowKeyMode then edit:SetAltArrowKeyMode(false) end
    edit.rounded = Rounded(edit, 8)
    edit.native = NativeBorder(edit)
    hint = Text(edit, "WM_ChatNormal", "GameFontHighlight")
    hint:SetPoint("LEFT", edit, "LEFT", 8, 0)
    hint:SetText(L("Intro para enviar"))
    local function Hint() hint:SetShown((edit:GetText() or "") == "" and not edit:HasFocus()) end
    edit:SetScript("OnEditFocusGained", Hint)
    edit:SetScript("OnEditFocusLost", Hint)
    edit:SetScript("OnTextChanged", Hint)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self)
        local text = HU.Trim(self:GetText() or "")
        self:SetText("")
        if text == "" then return end
        -- (sale por el chat de MI hermandad, como si lo escribiera en /g: el addon lo lleva a las otras)
        local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        if fn then pcall(fn, text, "GUILD") end
        stick = true
    end)
    local function IconButton(tex, tip)
        local b = CreateFrame("Button", nil, root)
        b:SetSize(BTN, BTN)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(BTN_ICON, BTN_ICON)
        b.icon:SetPoint("CENTER")
        b.icon:SetTexture(tex)
        local glow = b:CreateTexture(nil, "HIGHLIGHT")
        glow:SetAllPoints()
        glow:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        glow:SetBlendMode("ADD")
        b:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(tip)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        return b
    end
    local popups = {}
    local function Popup()
        local p = Box(root, true)
        -- (copia 136: los bocadillos están más adentro que el desplegable y, en la misma capa, se
        -- pintaban por encima. Se sube de capa y de nivel)
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        p:SetFrameLevel(200)
        if p.SetToplevel then p:SetToplevel(true) end
        p:EnableMouse(true)
        p:Hide()
        popups[#popups + 1] = p
        return p
    end
    local function Toggle(p, owner)
        local was = p:IsShown()
        for _, o in ipairs(popups) do o:Hide() end
        if was then return end
        p:ClearAllPoints()
        p:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", 0, 8)
        p:Show()
    end
    local function Insert(text)
        for _, o in ipairs(popups) do o:Hide() end
        local cur = edit:GetText() or ""
        edit:SetText(cur .. ((cur ~= "" and cur:sub(-1) ~= " ") and " " or "") .. text)
        edit:SetFocus()
        edit:SetCursorPosition(#(edit:GetText() or ""))
    end

    -- enviar (su flecha), emojis (los de Guild Union) y respuestas rápidas (las guardadas en Whisper Messenger)
    local send = IconButton(WM_MEDIA .. "send.png", L("Enviar"))
    send:SetPoint("BOTTOMRIGHT", comp, "BOTTOMRIGHT", -GUTTER, GUTTER + (COMPOSER_H - 2 * GUTTER - BTN) / 2)
    root.sendIcon = send.icon
    send:SetScript("OnClick", function()
        local run = edit:GetScript("OnEnterPressed")
        if run then run(edit) end
    end)

    local emoji = IconButton(WM_MEDIA .. "reactions.png", L("Emoticonos"))
    emoji.icon:SetTexCoord(WINK[1], WINK[2], WINK[3], WINK[4])
    emoji:SetPoint("RIGHT", send, "LEFT", -BTN_GAP, 0)
    local epop = Popup()
    local cell = 26
    epop:SetSize(EMOJI_COLS * cell + 20, math.ceil(#EMOJI_KEYS / EMOJI_COLS) * cell + 20)
    for i, k in ipairs(EMOJI_KEYS) do
        local b = CreateFrame("Button", nil, epop)
        b:SetSize(cell, cell)
        b:SetPoint("TOPLEFT", 10 + ((i - 1) % EMOJI_COLS) * cell, -10 - math.floor((i - 1) / EMOJI_COLS) * cell)
        local tx = b:CreateTexture(nil, "ARTWORK")
        tx:SetSize(20, 20)
        tx:SetPoint("CENTER")
        tx:SetTexture(WM_MEDIA .. "reactions.png")
        local c = EMOJI_AT[k]
        tx:SetTexCoord(c[1] / 1024, c[2] / 1024, c[3] / 256, c[4] / 256)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hl:SetBlendMode("ADD")
        b:SetScript("OnClick", function() Insert(":" .. k .. ":") end)
    end
    emoji:SetScript("OnClick", function() Toggle(epop, send) end)

    local quick = IconButton(WM_MEDIA .. "quick_reply.png", L("Respuestas rápidas"))
    quick.icon:SetVertexColor(1, 1, 1, 0.45)
    quick:SetPoint("RIGHT", emoji, "LEFT", -BTN_GAP, 0)
    local qpop = Popup()
    local qrows = {}
    quick:SetScript("OnClick", function()
        -- (las suyas, de sus ajustes; si no ha tocado la lista, las cuatro que trae él)
        local db = _G.WhisperMessengerDB
        local saved = type(db) == "table" and type(db.settings) == "table" and db.settings.quickReplies
        local items = {}
        for _, s in ipairs(type(saved) == "table" and saved or {}) do
            if type(s) == "string" and s ~= "" then items[#items + 1] = s end
        end
        if type(saved) ~= "table" then
            items = { L("Un segundo"), L("Voy para allá"), L("¡Claro!"), L("Perdona, ahora estoy ocupado: te contesto pronto") }
        end
        for _, b in ipairs(qrows) do b:Hide() end
        local w, rh = 256, 23
        local a = (skin and skin.t.accent) or { 1, 0.82, 0 }
        for i, s in ipairs(items) do
            local b = qrows[i]
            if not b then
                b = CreateFrame("Button", nil, qpop)
                b:SetHeight(rh)
                b.fs = Text(b, "WM_Highlight", "GameFontHighlight")
                b.fs:SetPoint("LEFT", 12, 0)
                b.fs:SetPoint("RIGHT", -8, 0)
                b.fs:SetJustifyH("LEFT")
                b.fs:SetWordWrap(false)
                b.hl = b:CreateTexture(nil, "HIGHLIGHT")
                b.hl:SetAllPoints()
                b.hl:SetTexture(TEX_SELECTED)
                b.hl:SetBlendMode("ADD")
                qrows[i] = b
            end
            b.hl:SetVertexColor(a[1], a[2], a[3], 0.6)
            b.fs:SetText(Plain(s))
            b:SetScript("OnClick", function() Insert(s) end)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 8, -10 - (i - 1) * rh)
            b:SetWidth(w)
            b:Show()
        end
        qpop:SetSize(w + 16, math.max(1, #items) * rh + 20)
        Toggle(qpop, send)
    end)
    root:SetScript("OnHide", function() for _, o in ipairs(popups) do o:Hide() end end)

    scroll = CreateFrame("ScrollFrame", nil, root)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, COMPOSER_H + 4)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(300, 10)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = MaxScroll()
        local step = IsShiftKeyDown() and max or 60
        local v = math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * step))
        self:SetVerticalScroll(v)
        stick = v >= max - 2 -- (abajo del todo: lo nuevo sigue bajando solo; si has subido a leer, no)
        UpdateThumb()
    end)
    scroll:SetScript("OnSizeChanged", AskLayout)
    thumb = root:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4)
    thumb:Hide()
    -- las sombras, en un marco por encima de los mensajes (no recoge el ratón)
    local shade = CreateFrame("Frame", nil, root)
    shade:SetAllPoints(scroll)
    shade:SetFrameLevel(scroll:GetFrameLevel() + 20)
    local function Shade(top)
        local tex = shade:CreateTexture(nil, "OVERLAY")
        local side = top and "TOP" or "BOTTOM"
        tex:SetPoint(side .. "LEFT")
        tex:SetPoint(side .. "RIGHT")
        tex:SetHeight(SHADE_H)
        tex:SetColorTexture(0, 0, 0, SHADE_ALPHA)
        -- (de transparente a negro hacia el borde; en vertical, el primer color es el de abajo)
        if tex.SetGradient and CreateColor then
            pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(1, 1, 1, top and 0 or 1), CreateColor(1, 1, 1, top and 1 or 0))
        end
        tex:Hide()
        return tex
    end
    topShade, bottomShade = Shade(true), Shade(false)
end

local function RefreshBadge()
    if badgeDue or not (api and api.RefreshPanelBadge) then return end
    badgeDue = true
    HU.After(1, function()
        badgeDue = false
        pcall(api.RefreshPanelBadge, PANEL_ID)
    end)
end

HU.WMRefreshBadge = function() RefreshBadge() end
local function OnShow(frame)
    HU.wmStats.err = nil
    if not root then
        local ok, err = pcall(Build, frame)
        if not ok then
            HU.wmStats.err = tostring(err)
            root = nil
            return
        end
    end
    shown = true
    ClearUnread(filter)
    for _, step in ipairs({ ApplySkin, BuildRows, Fill }) do
        local ok, err = pcall(step)
        if not ok then HU.wmStats.err = tostring(err) end
    end
    RefreshBadge()
end
local function OnHide() shown = false end
local function OnSplit(_, listWidth)
    if list and type(listWidth) == "number" and listWidth > 80 then
        list:SetWidth(listWidth)
        AskLayout()
    end
end

-- Cada línea nueva del chat de la comunidad: una burbuja más si el panel está a la vista; si no,
-- cuenta como no leída SOLO si me nombran (@Nombre Apellido o @everyone). (copia 155: contaba todas las
-- de otras hermandades y Whisper Messenger avisaba de 900 pendientes. Jorge, 16/11: «solo si me nombran»)
local function OnEntry(e)
    if not registered or not Wanted(e) then return end
    -- (una fila eliminada vuelve cuando llega algo suyo, como en Whisper Messenger)
    local p = RowPrefs()
    if p.hidden[e.tag] or p.hidden["*"] then
        p.hidden[e.tag], p.hidden["*"] = nil, nil
        if rows then BuildRows() end
    end
    local mention = type(e.m) == "string" and type(e.a) == "string" and e.a:lower() ~= (HU:MeKey() or "")
        and not p.muted["*"] and not p.muted[e.tag] and HU:MentionsMe(e.m, e.a, e.tag)
    if shown and content then
        -- (con la pestaña abierta en otra hermandad, la mención cuenta en la suya)
        if mention and filter and e.tag ~= filter then
            unreadBy[e.tag] = (unreadBy[e.tag] or 0) + 1
            RefreshBadge()
        end
        lastBy["*"], lastBy[e.tag] = e, e
        if not filter or e.tag == filter then
            shownEntries[#shownEntries + 1] = e
            while #shownEntries > KEEP do table.remove(shownEntries, 1) end
            AskLayout()
        end
        RowTexts()
    elseif mention then
        unreadBy[e.tag] = (unreadBy[e.tag] or 0) + 1
        RowTexts()
        RefreshBadge()
    end
end

-- Las líneas de una fila desde la última mía (lo que «marcar como no leídos» vuelve a marcar)
local function SinceMine(tag)
    local h, me, n = HU.db and HU.db.history or {}, HU:MeKey() or "", 0
    for i = #h, math.max(1, #h - 1500), -1 do
        local e = h[i]
        if Wanted(e, tag) then
            if e.a:lower() == me then break end
            n = n + 1
        end
    end
    return n
end

local function Export(tag)
    local h, out = HU.db and HU.db.history or {}, {}
    for i = math.max(1, #h - 1500), #h do
        local e = h[i]
        if Wanted(e, tag) then
            out[#out + 1] = date("%d/%m %H:%M", e.t or 0) .. " <" .. e.tag .. "> " .. HU:Nice(e.a) .. ": " .. Plain(e.m)
        end
    end
    while #out > 500 do table.remove(out, 1) end
    if HU.UI and HU.UI.ShowCopy then
        HU.UI:ShowCopy(L("Exportar conversación") .. " - " .. (tag and (HU:GuildName(tag) or tag) or L("Todas las hermandades")),
            #out > 0 and table.concat(out, "\n") or L("No hay mensajes."))
    end
end

-- El menú del clic derecho de una fila: las mismas opciones, en el mismo orden, que el suyo
-- (copia 157) ¿Está puesta la interfaz de mando de Blizzard? Un menú abierto desde un addon le
-- contamina el foco y deja el mando bloqueado (lo miden ForeverPlusPlus y ChillZone, que apaga lo
-- suyo con mando de la misma forma)
local function GamepadUI()
    local IS = _G.C_InputInterfaceStyle
    local pad = Enum and Enum.InputDeviceInterfaceType and Enum.InputDeviceInterfaceType.Gamepad
    if type(IS) ~= "table" or type(IS.GetCurrentStyle) ~= "function" or pad == nil then return false end
    local ok, style = pcall(IS.GetCurrentStyle)
    return ok and style == pad
end

function HU.WMRowMenu(owner, tag)
    local MU = _G.MenuUtil
    if type(MU) ~= "table" or type(MU.CreateContextMenu) ~= "function" then return end
    if GamepadUI() then
        HU:Print(L("Con la interfaz de mando este menú no se abre: el juego dejaría el mando bloqueado."))
        return
    end
    local key, p = RowKey(tag), RowPrefs()
    MU.CreateContextMenu(owner, function(_, menu)
        local back = SinceMine(tag)
        local b = menu:CreateButton(L("Marcar los últimos mensajes como no leídos"), function()
            unreadBy[key] = SinceMine(tag)
            RowTexts()
            RefreshBadge()
        end)
        if b and b.SetEnabled then b:SetEnabled(back > 0) end
        menu:CreateButton(L("Exportar conversación"), function() Export(tag) end)
        menu:CreateButton(p.muted[key] and L("Quitar silencio") or L("Silenciar"), function()
            p.muted[key] = (not p.muted[key]) or nil
            if p.muted[key] then
                if tag then unreadBy[key] = nil else unreadBy = {} end
            end
            RowTexts()
            RefreshBadge()
        end)
        menu:CreateButton(p.pinned[key] and L("Desanclar") or L("Anclar arriba"), function()
            p.pinned[key] = (not p.pinned[key]) and time() or nil
            BuildRows()
        end)
        local r = menu:CreateButton(L("Eliminar"), function()
            p.hidden[key] = true
            unreadBy[key] = nil
            if (filter or false) == (tag or false) then
                -- (si era la que se estaba viendo, se pasa a la primera que quede)
                filter = nil
                if p.hidden["*"] then
                    for _, g in ipairs(HU.cfg and HU.cfg.guilds or {}) do
                        if not p.hidden[g.tag] then
                            filter = g.tag
                            break
                        end
                    end
                end
                BuildRows()
                Fill()
            else
                BuildRows()
            end
            RefreshBadge()
        end)
        -- (la última fila que queda no se puede eliminar)
        if r and r.SetEnabled then r:SetEnabled(rows ~= nil and #rows > 1) end
    end)
end

local function TryRegister()
    if registered then return true end
    HU.wmStats.tries = HU.wmStats.tries + 1
    local A = _G.WhisperMessengerAPI
    if type(A) ~= "table" or type(A.Connect) ~= "function" then return false end
    local ok, h = pcall(A.Connect, "GuildUnion")
    if not ok or type(h) ~= "table" or type(h.RegisterPanel) ~= "function" then return false end
    api = h
    local ok2, res = pcall(h.RegisterPanel, PANEL_ID, {
        title = HU.ADDON_TITLE or "Guild Union",
        onShow = OnShow,
        onHide = OnHide,
        onSplit = OnSplit,
        badge = function() return TotalUnread() end,
        onMarkAllRead = function()
            unreadBy = {}
            RowTexts()
        end,
    })
    registered = ok2 and res == true
    return registered
end

function HU:WMStatus()
    local A = _G.WhisperMessengerAPI
    local db = _G.WhisperMessengerDB
    local S = type(db) == "table" and type(db.settings) == "table" and db.settings or {}
    return "Whisper Messenger: " .. (type(A) == "table" and "cargado" or "no está")
        .. " · pestaña registrada: " .. (registered and "sí" or "no")
        .. " · intentos: " .. (HU.wmStats.tries or 0)
        .. " · sin leer: " .. TotalUnread()
        .. " · burbujas: " .. #shownEntries
        .. " · estilo: " .. tostring(skin and skin.hud or "?")
        .. " · tema: " .. tostring(S.themePreset or "(el suyo por defecto)")
        .. " · color de burbuja: " .. tostring(S.bubbleColorPreset or "default")
        .. " · letra: " .. tostring(S.fontSize or 12)
        .. " · borde de la caja: " .. tostring(edit and edit.native and edit.native.used or "?")
        .. (HU.wmStats.err and (" · fallo al dibujar: " .. HU.wmStats.err) or "")
end

HU:On("PLAYER_LOGIN", function()
    -- (lo que se guarda en el historial pasa por aquí. Se envuelve una vez; Channel.lua cambia
    -- HU.AddHistory un momento mientras reparte las líneas del canal y luego la deja como estaba)
    local orig = HU.AddHistory
    function HU:AddHistory(...)
        orig(self, ...)
        local h = self.db and self.db.history
        if h then pcall(OnEntry, h[#h]) end
    end
    -- (Whisper Messenger publica su API al cargar; si aún no está, se reintenta unas veces)
    local delays = { 0, 2, 5, 15, 40 }
    for _, d in ipairs(delays) do
        HU.After(d, function() if not registered then pcall(TryRegister) end end)
    end
end)

HU:Module("WMPanel", { "Channel", "Config", "Core" })
