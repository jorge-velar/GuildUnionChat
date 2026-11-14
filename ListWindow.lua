-- Guild Union - ventana con una lista por columnas (la usan la lista negra y el registro de invitaciones)
local _, HU = ...

local ROW_H = 18

-- o = { name, title, width, height, rows, columns = { { texto, ancho }, … (la última sin ancho: hasta el borde) },
--       empty = texto si no hay nada }
-- Devuelve la ventana, con: win.who (texto bajo el título), win.scroll, win.rows[i].cells[c],
-- win:Fill(lista, pintar) y win.Refresh (lo pone quien la usa; se llama al abrir, al mover la lista
-- y cada 2 s mientras está abierta, porque lo que enseña puede cambiar por lo que llega de fuera)
function HU.NewListWindow(o)
    local win = CreateFrame("Frame", o.name, UIParent, "BackdropTemplate")
    win:SetSize(o.width, o.height)
    win:SetPoint("CENTER")
    -- (por encima de la ventana de GuildUnion y de la de hermandad, que van en DIALOG)
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    win:SetBackdropColor(0.05, 0.05, 0.08, 0.96)
    tinsert(UISpecialFrames, o.name)
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(o.title)
    HU.CloseButton(win):SetPoint("TOPRIGHT", -2, -2)
    win.who = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.who:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    win.who:SetWidth(o.width - 30); win.who:SetJustifyH("LEFT")

    local hdr = CreateFrame("Frame", nil, win)
    hdr:SetHeight(16)
    hdr:SetPoint("TOPLEFT", win.who, "BOTTOMLEFT", 0, -10)
    hdr:SetPoint("RIGHT", win, "RIGHT", -34, 0)
    local hbg = hdr:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints(); hbg:SetColorTexture(1, 1, 1, 0.06)
    local x = 4
    local starts = {}
    for c, col in ipairs(o.columns) do
        local fs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", x, 0); fs:SetText(col[1])
        starts[c] = x
        x = x + (col[2] or 0)
    end
    win.scroll = CreateFrame("ScrollFrame", o.name .. "Scroll", win, "FauxScrollFrameTemplate")
    win.scroll:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -2)
    win.scroll:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    win.scroll:SetHeight(o.rows * ROW_H)
    win.scroll:SetScript("OnVerticalScroll", function(s, offset)
        FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, function() if win.Refresh then win.Refresh() end end)
    end)
    win.rows = {}
    for i = 1, o.rows do
        local row = CreateFrame("Button", nil, win)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", win.scroll, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", win.scroll, "RIGHT", 0, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        if i % 2 == 0 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints(); stripe:SetColorTexture(1, 1, 1, 0.03)
        end
        row.cells = {}
        for c, col in ipairs(o.columns) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", starts[c], 0)
            if col[2] then fs:SetWidth(col[2] - 6) else fs:SetPoint("RIGHT", row, "RIGHT", -4, 0) end
            fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
            row.cells[c] = fs
        end
        win.rows[i] = row
    end
    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    win.empty:SetPoint("TOP", win.scroll, "TOP", 0, -30)
    win.empty:SetText(o.empty or "")

    function win:Fill(list, paint)
        FauxScrollFrame_Update(self.scroll, #list, o.rows, ROW_H)
        local off = FauxScrollFrame_GetOffset(self.scroll)
        for i = 1, o.rows do
            local row, e = self.rows[i], list[i + off]
            row.entry = e
            if e then paint(row, e); row:Show() else row:Hide() end
        end
        self.empty:SetShown(#list == 0)
    end
    local acc = 0
    win:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc > 2 then acc = 0; if win.Refresh then win.Refresh() end end
    end)
    win:SetScript("OnShow", function() if win.Refresh then win.Refresh() end end)
    win:Hide()
    return win
end

-- Caja de texto y botón sueltos, para el pie de esas ventanas
function HU.NewEditBox(parent, w)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end
function HU.NewButton(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22); b:SetText(text)
    return b
end
