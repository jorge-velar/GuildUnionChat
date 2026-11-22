-- Guild Union - «Unión» en la lista de miembros del juego: todos los conectados (mi hermandad y las otras) en una lista, encima de la del juego [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L

local ROW_H, ROWS = 18, 40
-- (columnas: título y ancho; la última, hasta el borde)
local COLS = { { "Nombre", 150 }, { "Nivel", 42 }, { "Zona", 150 }, { "Rango", 110 }, { "Hermandad" } }
local view = "guild"      -- «guild»: la lista del juego, tal cual; «union»: la nuestra, encima
local switch, cover

local function Win() return _G.CommunitiesFrame end

local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "ffffff"
end

-- Las filas que caben (como la lista de la pestaña): las demás, con la barra
local function Paint()
    if not (cover and cover:IsShown()) then return end
    HU:WantUnionMembers(nil)
    local list = HU:UnionRosterEntries()
    local sf = cover.scroll
    local visible = ROWS
    local h = sf:GetHeight()
    if type(h) == "number" and h > 0 then visible = math.max(1, math.min(ROWS, math.floor(h / ROW_H))) end
    FauxScrollFrame_Update(sf, #list, visible, ROW_H)
    local off = FauxScrollFrame_GetOffset(sf)
    for i = 1, ROWS do
        local row, e = cover.rows[i], i <= visible and list[off + i] or nil
        row.entry = e
        if e then
            local c = row.cells
            c[1]:SetText("|cff" .. ClassHex(e.class) .. HU:Nice(e.name) .. "|r")
            c[2]:SetText((e.level and e.level > 0) and tostring(e.level) or "")
            c[3]:SetText((e.zone or "") .. (e.afk and (" |cff808080(" .. L("Ausente") .. ")|r") or ""))
            c[4]:SetText(e.rank or "")
            c[5]:SetText("|cff" .. HU:GuildColorHex(e.tag) .. HU:GuildName(e.tag) .. "|r")
            row:Show()
        else
            row:Hide()
        end
    end
    -- (abajo: cuántos y cómo va la lista de cada hermandad)
    local parts = { string.format(L("%d conectados"), #list) }
    for _, t in ipairs(HU:OtherTags()) do
        local s = HU:UnionMembersStatus(t)
        if s ~= "" then parts[#parts + 1] = "|cff" .. HU:GuildColorHex(t) .. t .. "|r " .. s end
    end
    cover.status:SetText(table.concat(parts, "  ·  "))
end

-- Un clic del jugador aquí: el único momento en que el juego deja hacer /who (UnionMembers.lua)
local function WhoTick()
    if cover and cover:IsShown() and HU:UnionWhoTick(nil) then Paint() end
end

local function Build(f)
    local ml = f and f.MemberList
    local anchor = ml and ml.ShowOfflineButton
    if switch or not anchor then return end

    -- La lista, encima de la del juego (sin tocarla: hija de la ventana, no de su lista)
    cover = CreateFrame("Frame", "GuildUnionUnionRoster", f, "BackdropTemplate")
    cover:SetAllPoints(ml)
    cover:SetFrameLevel(ml:GetFrameLevel() + 20)
    cover:EnableMouse(true)
    cover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    cover:SetBackdropColor(0.04, 0.04, 0.05, 1)
    cover:Hide()
    local hdr = CreateFrame("Frame", nil, cover)
    hdr:SetHeight(18)
    hdr:SetPoint("TOPLEFT", 4, -4)
    hdr:SetPoint("RIGHT", cover, "RIGHT", -26, 0)
    local hbg = hdr:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints(); hbg:SetColorTexture(1, 1, 1, 0.06)
    local x, starts = 4, {}
    for i, col in ipairs(COLS) do
        local fs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", x, 0); fs:SetText(L(col[1]))
        starts[i] = x
        x = x + (col[2] or 0)
    end
    cover.status = cover:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cover.status:SetPoint("BOTTOMLEFT", 8, 6)
    cover.status:SetPoint("RIGHT", cover, "RIGHT", -8, 0)
    cover.status:SetJustifyH("LEFT"); cover.status:SetWordWrap(false)
    local sf = CreateFrame("ScrollFrame", "GuildUnionUnionRosterScroll", cover, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -2)
    sf:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", -26, 22)
    sf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, Paint); WhoTick() end)
    sf:SetScript("OnSizeChanged", function() Paint() end)
    cover.scroll = sf
    cover.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, cover)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", sf, "RIGHT", 0, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        if i % 2 == 0 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints(); stripe:SetColorTexture(1, 1, 1, 0.03)
        end
        row.cells = {}
        for c, col in ipairs(COLS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", starts[c], 0)
            if col[2] then fs:SetWidth(col[2] - 6) else fs:SetPoint("RIGHT", row, "RIGHT", -4, 0) end
            fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
            row.cells[c] = fs
        end
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        -- (clic: susurrar; clic derecho: el menú de GuildUnion, como en la pestaña)
        row:SetScript("OnClick", function(s, button)
            WhoTick()
            if not s.entry then return end
            if button == "RightButton" then HU.PlayerMenu(s, s.entry) else HU.WhisperTo(s.entry.name) end
        end)
        cover.rows[i] = row
    end
    cover:SetScript("OnMouseDown", function() WhoTick() end)
    cover:SetScript("OnShow", function()
        -- (se pide la lista de la hermandad al juego, por si estaba vieja)
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        Paint()
    end)
    cover:RegisterEvent("GUILD_ROSTER_UPDATE")
    cover:SetScript("OnEvent", function() Paint() end)
    HU:Listen("CHANGED", function(what) if what == "unionMembers" then Paint() end end)
    local acc = 0
    cover:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc > 2 then acc = 0; Paint() end
    end)

    -- El interruptor «Mi hermandad | Unión», a la izquierda del buscador de personajes
    switch = CreateFrame("Frame", "GuildUnionRosterSwitch", f)
    switch:SetSize(200, 20)
    switch:SetPoint("BOTTOMRIGHT", ml, "TOPRIGHT", -210, 30)
    switch:SetFrameLevel(anchor:GetFrameLevel() + 2)
    local bGuild = CreateFrame("Button", "GuildUnionRosterGuild", switch, "UIPanelButtonTemplate")
    bGuild:SetSize(100, 20); bGuild:SetPoint("LEFT"); bGuild:SetText(L("Mi hermandad"))
    local bUnion = CreateFrame("Button", "GuildUnionRosterUnion", switch, "UIPanelButtonTemplate")
    bUnion:SetSize(80, 20); bUnion:SetPoint("LEFT", bGuild, "RIGHT", 4, 0); bUnion:SetText(L("Unión"))
    bUnion:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:AddLine(L("Unión"))
        GameTooltip:AddLine(L("Los conectados de todas las hermandades de la comunidad en una lista. La del juego sigue debajo, sin tocar: para ascender, expulsar o las notas, «Mi hermandad»."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bUnion:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local function Sync()
        -- (solo en la vista de miembros: la casilla de desconectados se ve; IsVisible y no IsShown, como el buscador)
        local members = anchor:IsVisible()
        switch:SetShown(members)
        cover:SetShown(members and view == "union")
        if view == "union" then bUnion:LockHighlight(); bGuild:UnlockHighlight() else bGuild:LockHighlight(); bUnion:UnlockHighlight() end
    end
    local function SyncSoon() HU.After(0, Sync) end
    bGuild:SetScript("OnClick", function() view = "guild"; Sync() end)
    bUnion:SetScript("OnClick", function() view = "union"; Sync(); WhoTick() end)
    for _, w in ipairs({ anchor, ml }) do w:HookScript("OnShow", SyncSoon); w:HookScript("OnHide", SyncSoon) end
    if f.SetDisplayMode then hooksecurefunc(f, "SetDisplayMode", SyncSoon) end
    f:HookScript("OnShow", SyncSoon)
    Sync()
end

local function Setup() HU:SafeCall("unión en la lista", Build, Win()) end
HU:On("ADDON_LOADED", function(name) if name == "Blizzard_Communities" then Setup() end end)
HU:OnStart(function()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities") then Setup() end
end)

HU:Module("UnionRoster", { "BlizzTab", "Config", "Core", "UnionMembers" })
