-- Guild Union - registro de invitaciones a mi hermandad: quién invitó a quién y cuándo
-- El juego ya lo apunta en su registro de hermandad, pero solo conserva las últimas entradas. Aquí se
-- van guardando (db.inviteLog, por hermandad) para tener el historial largo. Cada uno guarda lo que
-- ve su addon: no se reparte entre jugadores. [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L

local MAX = 2000 -- invitaciones guardadas por hermandad

local function Log()
    local guild = IsInGuild() and GetGuildInfo and GetGuildInfo("player")
    if not guild or not HU.db then return nil end
    HU.db.inviteLog = HU.db.inviteLog or {}
    local log = HU.db.inviteLog[guild]
    if not log then log = {}; HU.db.inviteLog[guild] = log end
    return log
end

-- El juego no da la fecha, sino hace cuánto fue (años, meses, días, horas). Se pasa a una hora
-- aproximada, y una entrada ya guardada se reconoce por «mismo invitador, mismo invitado y hora
-- parecida» (el margen crece con la antigüedad, porque «hace 2 meses» es poco preciso)
local function ReadGameLog()
    local log = Log()
    if not log or not GetNumGuildEvents then return end
    local seen = {}
    for _, e in ipairs(log) do
        local key = e.by .. "\1" .. e.who
        seen[key] = seen[key] or {}
        table.insert(seen[key], e.t)
    end
    local now, added = time(), false
    for i = 1, GetNumGuildEvents() do
        local kind, p1, p2, _, y, m, d, h = GetGuildEventInfo(i)
        if kind == "invite" and type(p1) == "string" and type(p2) == "string" and not HU.Secret(p1) and not HU.Secret(p2) then
            local age = ((((y or 0) * 12 + (m or 0)) * 30 + (d or 0)) * 24 + (h or 0)) * 3600
            local t, margin = now - age, math.max(7200, age * 0.1)
            local by, who = HU:FullName(p1) or p1, HU:FullName(p2) or p2
            local key, known = by .. "\1" .. who, false
            for _, old in ipairs(seen[key] or {}) do
                if math.abs(old - t) <= margin then known = true break end
            end
            if not known then
                log[#log + 1] = { t = t, by = by, who = who }
                seen[key] = seen[key] or {}
                table.insert(seen[key], t)
                added = true
            end
        end
    end
    if added then
        table.sort(log, function(a, b) return a.t < b.t end)
        while #log > MAX do table.remove(log, 1) end
    end
end
HU:On("GUILD_EVENT_LOG_UPDATE", ReadGameLog)

-- (se le pide el registro al juego al entrar y cada 10 min; la respuesta llega por el evento de arriba)
-- (QueryGuildEventLog: la usa la ventana de hermandad del juego, GuildInfo.xml; se busca por nombre
-- porque no sale en la lista de funciones conocidas de luacheck)
local function Ask()
    local query = rawget(_G, "QueryGuildEventLog")
    if IsInGuild() and type(query) == "function" then query() end
end
HU:OnStart(function()
    HU.After(15, Ask)
    HU.NewTicker(600, Ask)
end)

-- Quién invitó a esa persona (la última vez), o nil si no consta
function HU:InvitedBy(name)
    local k, log = self:Key(name), Log()
    if not (k and log) then return nil end
    for i = #log, 1, -1 do
        if log[i].who:lower() == k then return log[i].by, log[i].t end
    end
    return nil
end

---------------------------------------------------------------------------
-- Ventana (el armazón, en ListWindow.lua)
---------------------------------------------------------------------------
local win

local function Paint(row, e)
    row.cells[1]:SetText("|cff9a8f78" .. HU.SafeDate("%d/%m/%y %H:%M", e.t) .. "|r")
    row.cells[2]:SetText(HU:Short(e.by))
    -- (en blanco quien sigue en la hermandad, en gris quien ya no está, en rojo quien está en la lista negra)
    local color = (HU.IsBanned and HU:IsBanned(e.who)) and "|cffff4444" or (HU:InMyGuild(e.who) and "|cffffffff" or "|cff808080")
    row.cells[3]:SetText(color .. HU:Short(e.who) .. "|r")
end

local function Refresh()
    if not (win and win:IsShown()) then return end
    local log, list = Log() or {}, {}
    local q = HU.Trim(win.search:GetText() or ""):lower()
    -- (lo más nuevo arriba; el buscador mira en los dos nombres)
    for i = #log, 1, -1 do
        local e = log[i]
        if q == "" or e.by:lower():find(q, 1, true) or e.who:lower():find(q, 1, true) then list[#list + 1] = e end
    end
    win:Fill(list, Paint)
    win.who:SetText(L("Quién invitó a quién a tu hermandad. Se guarda lo que tu addon va viendo en el registro del juego.")
        .. "  |cff808080" .. #log .. "|r")
end

function HU:ShowInviteLog()
    if not IsInGuild() then return self:Print(L("No estás en una hermandad.")) end
    if not win then
        win = HU.NewListWindow({ name = "GuildUnionInviteLogFrame", title = L("Registro de invitaciones"), width = 520, height = 400, rows = 14,
            columns = { { L("Fecha"), 120 }, { L("Invitó"), 170 }, { L("A quién") } }, empty = L("Todavía no hay invitaciones guardadas.") })
        win.Refresh = Refresh
        local lSearch = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lSearch:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 14, 20)
        lSearch:SetText(L("Buscar"))
        win.search = HU.NewEditBox(win, 170)
        win.search:SetPoint("LEFT", lSearch, "LEFT", 60, 0)
        win.search:SetScript("OnTextChanged", Refresh)
        local legend = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        legend:SetPoint("LEFT", win.search, "RIGHT", 12, 0)
        legend:SetText("|cff808080" .. L("En gris") .. "|r" .. L(": ya no está.") .. "  |cffff4444" .. L("En rojo") .. "|r" .. L(": en la lista negra."))
    end
    if win:IsShown() then win:Hide() return end
    Ask()
    win:Show()
end
