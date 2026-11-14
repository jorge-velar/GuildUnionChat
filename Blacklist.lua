-- Guild Union - lista negra de la comunidad (maestros, administradores y oficiales)
-- No tiene datos propios: es la lista de vetados (db.bans, Social.lua), que ya se reparte entre las
-- hermandades. Aquí van la ventana para verla y cambiarla y el aviso cuando alguien de la lista
-- está en mi hermandad. [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L

-- Los vetados vigentes, por orden alfabético
function HU:BlacklistEntries()
    local list = {}
    for k, b in pairs((self.db and self.db.bans) or {}) do
        if b.on then list[#list + 1] = { key = k, name = b.name or k, by = b.by, tag = b.tag, why = b.why } end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

---------------------------------------------------------------------------
-- Cotejo con mi hermandad: se avisa a quien puede actuar (una vez por persona y sesión)
---------------------------------------------------------------------------
-- Cada hermandad mira solo a sus miembros (Jorge, 14/11): la lista es común, el cotejo es de cada una
-- El aviso sale en el chat de oficiales de la hermandad (/o), para que lo vean todos los oficiales,
-- también los que no tienen el addon. Para no repetirlo: lo escribe un solo oficial (cada uno espera
-- un rato al azar y, si ve que otro ya lo ha escrito, calla) y de cada persona se dice como mucho
-- una vez al día (db.blackSaid). Si no puedo escribir en /o, me lo dice solo a mí. [+ARCHITECTURE.md]
local SAY_MARK, SAY_EVERY = "[Guild Union] ", 86400
local function SaidLately(k)
    local t = HU.db.blackSaid and HU.db.blackSaid[k]
    return t ~= nil and time() - t < SAY_EVERY
end
local function MarkSaid(k)
    HU.db.blackSaid = HU.db.blackSaid or {}
    HU.db.blackSaid[k] = time()
end
HU:On("CHAT_MSG_OFFICER", function(text)
    if HU.Secret(text) or type(text) ~= "string" or text:sub(1, #SAY_MARK) ~= SAY_MARK then return end
    for k, b in pairs((HU.db and HU.db.bans) or {}) do
        if b.on and text:find(HU:Short(b.name or k), 1, true) then MarkSaid(k) end
    end
end)

-- (again: repasa también a los ya avisados y dice el resultado aunque no haya nadie; el botón.
-- Ese repaso a mano solo me contesta a mí, no escribe en /o)
local warned = {}
function HU:BlacklistCheck(again)
    if not (self.db and self.db.bans and self.myTag and self:CanPin()) then return end
    local found = 0
    for k, b in pairs(self.db.bans) do
        if b.on and (again or not warned[k]) and self.roster[k] then
            warned[k] = true
            found = found + 1
            local by = b.by and (self:Short(b.by) .. ((b.tag and b.tag ~= "") and (" <" .. b.tag .. ">") or "")) or "?"
            local name, tail = self:Short(b.name or k), L(" Lo vetó ") .. by .. "." .. (b.why and (L(" Motivo: ") .. b.why) or "")
            -- (y quién lo metió en la hermandad, si consta en el registro de invitaciones)
            local inviter = self.InvitedBy and self:InvitedBy(k)
            if inviter then tail = tail .. L(" Lo invitó ") .. self:Short(inviter) .. "." end
            local function Mine()
                self:Print("|cffff4444" .. L("Lista negra") .. ":|r |cffffffff" .. name .. "|r " .. L("está en tu hermandad.") .. tail)
            end
            -- (ya dicho hoy en /o: a quien entra después se le dice solo a él, por si no lo vio)
            if again or SaidLately(k) then
                Mine()
            else
                HU.After(2 + math.random() * 10, function()
                    local cur = HU.db.bans[k]
                    if not (cur and cur.on and HU.roster[k]) or SaidLately(k) then return end
                    local line = HU.Utf8Cut(SAY_MARK .. L("Lista negra") .. ": " .. name .. " " .. L("está en la hermandad.") .. tail, 240)
                    if HU.RawSend(line, "OFFICER") then MarkSaid(k) else Mine() end
                end)
            end
        end
    end
    if again and found == 0 then
        self:Print(L("Lista negra") .. ": " .. L("nadie de la lista está en tu hermandad."))
    end
end
HU:OnStart(function()
    HU.NewTicker(60, function() HU:BlacklistCheck() end)
end)

---------------------------------------------------------------------------
-- Aviso al invitar: a quien invita a la hermandad a alguien de la lista negra (cualquiera con el
-- addon, no solo los oficiales). El juego no deja a un addon parar la invitación: se mira justo
-- después de que salga (hooksecurefunc, que no toca la función del juego) y se avisa en grande, en
-- el centro de la pantalla, y en el chat. [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local function OnGuildInvite(name)
    if type(name) ~= "string" or HU.Secret(name) or not (HU.db and HU.db.bans) then return end
    local k = HU:Key(HU.Trim(name))
    local b = k and HU.db.bans[k]
    if not (b and b.on) then return end
    local by = b.by and (HU:Short(b.by) .. ((b.tag and b.tag ~= "") and (" <" .. b.tag .. ">") or "")) or "?"
    local who = HU:Short(b.name or k)
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(who .. " " .. L("está en la lista negra de la comunidad."), 1, 0.25, 0.25)
    end
    if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959) end
    HU:Print("|cffff4444" .. L("Lista negra") .. ":|r |cffffffff" .. who .. "|r " .. L("está en la lista negra de la comunidad.")
        .. L(" Lo vetó ") .. by .. "." .. (b.why and (L(" Motivo: ") .. b.why) or "")
        .. " " .. L("La invitación ya ha salido: si entra, habla con un oficial."))
end
HU:OnStart(function()
    if not hooksecurefunc then return end
    if C_GuildInfo and C_GuildInfo.Invite then
        hooksecurefunc(C_GuildInfo, "Invite", function(name) HU:SafeCall("blacklist invite", OnGuildInvite, name) end)
    end
    -- (el nombre viejo de la función, por si alguna parte del juego u otro addon lo sigue usando)
    if type(rawget(_G, "GuildInvite")) == "function" then
        hooksecurefunc("GuildInvite", function(name) HU:SafeCall("blacklist invite", OnGuildInvite, name) end)
    end
end)

---------------------------------------------------------------------------
-- Ventana (el armazón, en ListWindow.lua)
---------------------------------------------------------------------------
local win

local function Paint(row, e)
    row.cells[1]:SetText((HU.roster[e.key] and "|cffff4444" or "|cffffffff") .. HU:Short(e.name) .. "|r")
    row.cells[2]:SetText(e.by and (HU:Short(e.by) .. ((e.tag and e.tag ~= "") and (" |cff" .. HU:GuildColorHex(e.tag) .. "<" .. e.tag .. ">|r") or "")) or "")
    row.cells[3]:SetText(e.why or "")
end

local function Refresh()
    if not (win and win:IsShown()) then return end
    win:Fill(HU:BlacklistEntries(), Paint)
    local can = HU:CanPin()
    for _, w in ipairs(win.editParts) do w:SetShown(can) end
    win.who:SetText(can and L("Añade a quien no deba entrar en ninguna hermandad de la comunidad. La lista la comparten todas.")
        or L("Solo el maestro y los oficiales pueden cambiar la lista."))
end

local function Build()
    win = HU.NewListWindow({ name = "GuildUnionBlacklistFrame", title = L("Lista negra"), width = 520, height = 400, rows = 12,
        columns = { { L("Nombre"), 150 }, { L("Lo vetó"), 150 }, { L("Motivo") } }, empty = L("No hay nadie en la lista negra.") })
    win.Refresh = Refresh
    for _, row in ipairs(win.rows) do
        -- (pulsar una fila deja el nombre abajo, listo para quitarlo; el motivo entero, al pasar el ratón)
        row:SetScript("OnClick", function(s) if s.entry then win.nameBox:SetText(HU:Short(s.entry.name)) end end)
        row:SetScript("OnEnter", function(s)
            if not (s.entry and s.entry.why) then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:AddLine(HU:Short(s.entry.name))
            GameTooltip:AddLine(s.entry.why, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local legend = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    legend:SetPoint("TOPLEFT", win.scroll, "BOTTOMLEFT", 0, -6)
    legend:SetText("|cffff4444" .. L("En rojo") .. "|r" .. L(": está ahora mismo en tu hermandad."))
    -- (repasa la lista contra los miembros ahora, sin esperar al repaso de cada minuto)
    local bCheck = HU.NewButton(win, L("Comprobar ahora"), 130)
    bCheck:SetPoint("TOPRIGHT", win.scroll, "BOTTOMRIGHT", 0, -2)
    bCheck:SetScript("OnClick", function() HU:BlacklistCheck(true); Refresh() end)

    -- Añadir y quitar (maestro y oficiales)
    local lName = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lName:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 14, 44)
    lName:SetText(L("Nombre"))
    win.nameBox = HU.NewEditBox(win, 150)
    win.nameBox:SetPoint("LEFT", lName, "LEFT", 60, 0)
    if HU.NameSuggest then HU:NameSuggest(win.nameBox) end
    local lWhy = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lWhy:SetPoint("TOPLEFT", lName, "BOTTOMLEFT", 0, -12)
    lWhy:SetText(L("Motivo"))
    local whyBox = HU.NewEditBox(win, 280)
    whyBox:SetPoint("LEFT", lWhy, "LEFT", 60, 0)
    whyBox:SetMaxLetters(80)
    local bAdd = HU.NewButton(win, L("Añadir"), 80)
    bAdd:SetPoint("LEFT", whyBox, "RIGHT", 10, 0)
    local bDel = HU.NewButton(win, L("Quitar"), 80)
    bDel:SetPoint("LEFT", win.nameBox, "RIGHT", 10, 0)
    bAdd:SetScript("OnClick", function()
        local name = HU.Trim(win.nameBox:GetText() or "")
        if name == "" then return end
        HU:SetBan(name, true, whyBox:GetText())
        if HU:IsBanned(name) then win.nameBox:SetText(""); whyBox:SetText("") end
        Refresh(); HU:BlacklistCheck()
    end)
    bDel:SetScript("OnClick", function()
        local name = HU.Trim(win.nameBox:GetText() or "")
        if name == "" or not HU:IsBanned(name) then return end
        HU:SetBan(name, false)
        local k = HU:Key(name) or ""
        warned[k] = nil
        if HU.db.blackSaid then HU.db.blackSaid[k] = nil end
        win.nameBox:SetText("")
        Refresh()
    end)
    win.editParts = { lName, win.nameBox, lWhy, whyBox, bAdd, bDel }
end

function HU:ShowBlacklist()
    if not self.myTag then return self:Print(L("Sin configurar.")) end
    if not win then Build() end
    if win:IsShown() then win:Hide() else win:Show() end
end

