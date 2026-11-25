-- Guild Union - registro de mi hermandad: quién invitó a quién, y quién se fue o fue echado, y cuándo
-- El juego ya lo apunta en su registro de hermandad, pero solo conserva las últimas entradas. Aquí se
-- van guardando (db.inviteLog y db.leaveLog, por hermandad) para tener el historial largo. Cada uno guarda
-- lo que ve su addon: no se reparte entre jugadores. [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L

local MAX = 2000 -- entradas guardadas por hermandad y por registro

-- kind: "inviteLog" (invitaciones) o "leaveLog" (salidas)
local function Log(kind)
    local guild = IsInGuild() and GetGuildInfo and GetGuildInfo("player")
    if not guild or not HU.db then return nil end
    HU.db[kind] = HU.db[kind] or {}
    local log = HU.db[kind][guild]
    if not log then log = {}; HU.db[kind][guild] = log end
    return log
end

-- El juego no da la fecha, sino hace cuánto fue (años, meses, días, horas). Se pasa a una hora
-- aproximada, y una entrada ya guardada se reconoce por «mismas personas y hora parecida» (el margen
-- crece con la antigüedad, porque «hace 2 meses» es poco preciso)
local function Merge(log, seen, e, age, now)
    local t, margin = now - age, math.max(7200, age * 0.1)
    local key = (e.by or "") .. "\1" .. e.who
    for _, old in ipairs(seen[key] or {}) do
        if math.abs(old - t) <= margin then return false end
    end
    e.t = t
    log[#log + 1] = e
    seen[key] = seen[key] or {}
    table.insert(seen[key], t)
    return true
end

local function Seen(log)
    local seen = {}
    for _, e in ipairs(log) do
        local key = (e.by or "") .. "\1" .. e.who
        seen[key] = seen[key] or {}
        table.insert(seen[key], e.t)
    end
    return seen
end

local function Trim(log)
    table.sort(log, function(a, b) return a.t < b.t end)
    while #log > MAX do table.remove(log, 1) end
end

local function ReadGameLog()
    local invites, leaves = Log("inviteLog"), Log("leaveLog")
    if not (invites and leaves) or not GetNumGuildEvents then return end
    local seenI, seenL = Seen(invites), Seen(leaves)
    local now, addedI, addedL = time(), false, false
    for i = 1, GetNumGuildEvents() do
        local kind, p1, p2, _, y, m, d, h = GetGuildEventInfo(i)
        local age = ((((y or 0) * 12 + (m or 0)) * 30 + (d or 0)) * 24 + (h or 0)) * 3600
        local ok1 = type(p1) == "string" and not HU.Secret(p1)
        local ok2 = type(p2) == "string" and not HU.Secret(p2)
        if kind == "invite" and ok1 and ok2 then
            local e = { by = HU:FullName(p1) or p1, who = HU:FullName(p2) or p2 }
            if Merge(invites, seenI, e, age, now) then addedI = true end
        elseif kind == "quit" and ok1 then
            -- (se fue él)
            if Merge(leaves, seenL, { who = HU:FullName(p1) or p1 }, age, now) then addedL = true end
        elseif kind == "remove" and ok1 and ok2 then
            -- (lo echó otro: p1 echó a p2)
            if Merge(leaves, seenL, { by = HU:FullName(p1) or p1, who = HU:FullName(p2) or p2 }, age, now) then addedL = true end
        end
    end
    if addedI then Trim(invites) end
    if addedL then Trim(leaves) end
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
    HU:Every(600, "invitaciones", Ask)
end)

-- Al echar a alguien por una solicitud de otra hermandad: se apunta ya en Salidas, con quién lo pidió.
-- Cuando el juego lo apunte en su registro («remove», por mí), se reconoce como la misma (Merge)
function HU:LogRequestedKick(r)
    local log = Log("leaveLog")
    if not log then return end
    local who = HU:FullName(r.target) or r.target
    local by = HU:Me()
    for i = #log, 1, -1 do
        local e = log[i]
        if e.who == who and e.by == by and math.abs(time() - e.t) < 7200 then
            e.req, e.reqTag = r.requester, r.reqTag
            return
        end
    end
    log[#log + 1] = { t = time(), by = by, who = who, req = r.requester, reqTag = r.reqTag }
    Trim(log)
end

-- Quién invitó a esa persona (la última vez), o nil si no consta
function HU:InvitedBy(name)
    local k, log = self:Key(name), Log("inviteLog")
    if not (k and log) then return nil end
    for i = #log, 1, -1 do
        if log[i].who:lower() == k then return log[i].by, log[i].t end
    end
    return nil
end

---------------------------------------------------------------------------
-- Ventana (el armazón, en ListWindow.lua): dos pestañas, Invitaciones y Salidas, con lo guardado de
-- todas mis hermandades (si tengo personajes en varias de la comunidad, salen todas, con su etiqueta)
---------------------------------------------------------------------------
local win
local view = "inviteLog"

-- La etiqueta de una hermandad por su nombre (la de la configuración de la comunidad), en su color
local function GuildLabel(name)
    local g = HU.cfg and HU.cfg.byName and HU.cfg.byName[name:lower()]
    if g then return "|cff" .. HU:GuildColorHex(g.tag) .. g.tag .. "|r" end
    return "|cff9a8f78" .. HU.Utf8Cut(name, 10) .. "|r"
end

-- (en blanco quien sigue en la hermandad, en gris quien ya no está, en rojo quien está en la lista negra)
local function WhoColor(name)
    return (HU:IsBanned(name) and "|cffff4444") or (HU:InMyGuild(name) and "|cffffffff") or "|cff808080"
end

local function Paint(row, e)
    row.cells[1]:SetText("|cff9a8f78" .. HU.SafeDate("%d/%m/%y %H:%M", e.t) .. "|r")
    row.cells[2]:SetText(GuildLabel(e.guild))
    if view == "inviteLog" then
        row.cells[3]:SetText(HU:Short(e.by))
        row.cells[4]:SetText(WhoColor(e.who) .. HU:Short(e.who) .. "|r")
    else
        row.cells[3]:SetText(WhoColor(e.who) .. HU:Short(e.who) .. "|r")
        -- (si fue por una solicitud de otra hermandad, quién la pidió)
        local req = e.req and ("  |cff9a8f78" .. L("pedido por ") .. HU:Short(e.req) .. " <" .. tostring(e.reqTag or "?") .. ">|r") or ""
        row.cells[4]:SetText((e.by and (L("Echado por ") .. HU:Short(e.by)) or ("|cff9a8f78" .. L("Se fue") .. "|r")) .. req)
    end
end

local function Refresh()
    if not (win and win:IsShown()) then return end
    -- (las de todas mis hermandades guardadas, juntas, lo más nuevo arriba; el buscador mira en los nombres)
    local all, total = {}, 0
    for guild, log in pairs(HU.db and HU.db[view] or {}) do
        for _, e in ipairs(log) do
            total = total + 1
            all[#all + 1] = { t = e.t, by = e.by, who = e.who, guild = guild, req = e.req, reqTag = e.reqTag }
        end
    end
    table.sort(all, function(a, b) return a.t > b.t end)
    local q = HU.Trim(win.search:GetText() or ""):lower()
    local list = {}
    for _, e in ipairs(all) do
        if q == "" or e.who:lower():find(q, 1, true) or (e.by and e.by:lower():find(q, 1, true)) or e.guild:lower():find(q, 1, true) then
            list[#list + 1] = e
        end
    end
    win:Fill(list, Paint)
    -- (hay guardadas, pero ninguna sale con lo buscado)
    local noMatch = q ~= "" and total > 0 and L("Nada coincide con la búsqueda.")
    local h = win.hdrCells
    if view == "inviteLog" then
        h[3]:SetText(L("Invitó")); h[4]:SetText(L("A quién"))
        win.who:SetText(L("Quién invitó a quién a tus hermandades. Se guarda lo que tu addon va viendo en el registro del juego.") .. "  |cff808080" .. total .. "|r")
        win.empty:SetText(noMatch or L("Todavía no hay invitaciones guardadas."))
    else
        h[3]:SetText(L("Quién")); h[4]:SetText(L("Cómo"))
        win.who:SetText(L("Quién se fue de tus hermandades o fue echado. Se guarda lo que tu addon va viendo en el registro del juego.") .. "  |cff808080" .. total .. "|r")
        win.empty:SetText(noMatch or L("Todavía no hay salidas guardadas."))
    end
    for k, b in pairs(win.tabs) do
        HU.DJ.PickRed(b, k == view)
    end
end

function HU:ShowInviteLog()
    if not IsInGuild() then return self:Print(L("No estás en una hermandad.")) end
    if not win then
        win = HU.NewListWindow({ name = "GuildUnionInviteLogFrame", title = L("Registro"), width = 600, height = 400, rows = 14,
            columns = { { L("Fecha"), 110 }, { L("Hermandad"), 70 }, { L("Invitó"), 170 }, { L("A quién") } }, empty = "" })
        win.Refresh = Refresh
        -- (las dos pestañas, botones rojos del juego, arriba a la derecha)
        win.tabs = {}
        local prev
        for _, t in ipairs({ { "inviteLog", L("Invitaciones") }, { "leaveLog", L("Salidas") } }) do
            local b = HU.NewButton(win, t[2], 110)
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPRIGHT", win, "TOPRIGHT", -150, -10) end
            b:SetScript("OnClick", function() view = t[1]; FauxScrollFrame_SetOffset(win.scroll, 0); Refresh() end)
            win.tabs[t[1]] = b
            prev = b
        end
        local lSearch = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lSearch:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 14, 20)
        lSearch:SetText(L("Buscar"))
        win.search = HU.NewEditBox(win, 170)
        win.search:SetPoint("LEFT", lSearch, "LEFT", 60, 0)
        win.search:SetScript("OnTextChanged", Refresh)
        -- (la leyenda cabe dentro: con su ancho fijo y, si hace falta, en dos líneas)
        local legend = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        legend:SetPoint("LEFT", win.search, "RIGHT", 12, 0)
        legend:SetPoint("RIGHT", win, "RIGHT", -14, 0)
        legend:SetJustifyH("LEFT"); legend:SetWordWrap(true); legend:SetMaxLines(2)
        legend:SetText("|cff808080" .. L("En gris") .. "|r" .. L(": ya no está.") .. "  |cffff4444" .. L("En rojo") .. "|r" .. L(": en la lista negra."))
    end
    if win:IsShown() then win:Hide() return end
    Ask()
    win:Show()
end

---------------------------------------------------------------------------
-- Peticiones de oficiales: otra hermandad pide echar a alguien de la mía (GK, Social.lua) o cambiarle el
-- rango (GP, Ranks.lua). No salta ninguna ventana: se guardan (db.kickRequests, caducan en 24 h) y un
-- oficial las acepta o rechaza desde aquí [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local REQ_TTL = 86400
local function Requests()
    if not HU.db then return {} end
    HU.db.kickRequests = HU.db.kickRequests or {}
    local list, now = HU.db.kickRequests, time()
    for i = #list, 1, -1 do
        if now - (list[i].t or 0) > REQ_TTL then table.remove(list, i) end
    end
    return list
end

function HU:AddKickRequest(r)
    local list = Requests()
    for _, x in ipairs(list) do if x.id == r.id then return end end
    list[#list + 1] = r
    self:Changed("requests")
end

function HU:RemoveKickRequest(id)
    local list = Requests()
    for i = #list, 1, -1 do if list[i].id == id then table.remove(list, i) end end
    self:Changed("requests")
end

-- ¿La puedo hacer yo? Solo se enseñan esas: un cambio a oficial o admin, solo a quien puede dar ese
-- rango (`HU:RankMacro`: permiso, y rango por debajo del mío); echar, a quien puede echar a esa persona
-- (`HU:CanKickMember`). Las de prueba, siempre
local function Doable(r)
    if r.test then return true end
    if (r.kind or "kick") == "rank" then return (HU:RankMacro(r.target, r.rank)) ~= nil end
    return (HU:CanKickMember(r.target)) == true
end

function HU:KickRequestCount()
    local n = 0
    for _, r in ipairs(Requests()) do if Doable(r) then n = n + 1 end end
    return n
end

-- (elegidas: por id. Clic, una; Mayús, desde la última hasta esta; Ctrl, suma o quita una)
-- (una sola lista: «Echar» —GK, Social.lua— en rojo y «Rango» —GP, Ranks.lua— en amarillo; arriba, un
-- filtro: todas, solo echar o solo rango. kind nil = echar)
local reqWin, picked, lastPick, shownReq = nil, {}, nil, {}
local reqView = "all"
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local function KindOf(r) return r.kind or "kick" end

local function PaintRequest(row, r)
    row.cells[1]:SetText("|cff9a8f78" .. HU.SafeDate("%d/%m %H:%M", r.t) .. "|r")
    row.cells[2]:SetText(HU:Short(r.requester) .. " |cff" .. HU:GuildColorHex(r.reqTag) .. "<" .. tostring(r.reqTag or "?") .. ">|r")
    row.cells[3]:SetText("|cffffd100" .. HU:Short(r.target) .. "|r")
    local what = KindOf(r) == "rank" and ("|cffffd100" .. L("Rango") .. ": " .. (HU:RankName(HU.myTag, r.rank) or "?") .. "|r")
        or ("|cffff4040" .. L("Echar") .. "|r")
    row.cells[4]:SetText(what .. (r.test and ("  |cff808080(" .. L("prueba") .. ")|r") or ""))
    row.pickTex:SetShown(picked[r.id] == true)
end

local function Picked()
    local out = {}
    for _, r in ipairs(shownReq) do if picked[r.id] then out[#out + 1] = r end end
    return out
end

local function CanAnswer(kind)
    if kind == "rank" then return HU:CanPromote() or HU:CanDemote() end
    return HU:CanKickGuild()
end

local function RefreshRequests()
    if not (reqWin and reqWin:IsShown()) then return end
    local list, all = {}, Requests()
    local counts = { all = #all, kick = 0, rank = 0 }
    counts.all = 0
    for i = #all, 1, -1 do
        if Doable(all[i]) then
            local k = KindOf(all[i])
            counts[k] = (counts[k] or 0) + 1
            counts.all = counts.all + 1
            if reqView == "all" or k == reqView then list[#list + 1] = all[i] end
        end
    end
    shownReq = list
    local live = {}
    for _, r in ipairs(list) do if picked[r.id] then live[r.id] = true end end
    picked = live
    reqWin:Fill(list, PaintRequest)
    local n = #Picked()
    reqWin.accept:SetText(n > 1 and (L("Aceptar") .. " (" .. n .. ")") or L("Aceptar"))
    reqWin.reject:SetText(n > 1 and (L("Rechazar") .. " (" .. n .. ")") or L("Rechazar"))
    local can = n > 0
    for _, r in ipairs(Picked()) do if not r.test and not CanAnswer(KindOf(r)) then can = false end end
    reqWin.accept:SetEnabled(can)
    reqWin.reject:SetEnabled(n > 0)
    for k, b in pairs(reqWin.tabs) do
        local c = counts[k] or 0
        b:SetText(b.base .. (c > 0 and (" (" .. c .. ")") or ""))
        HU.DJ.PickRed(b, k == reqView)
    end
    reqWin.who:SetText(L("Otras hermandades piden echar o cambiar el rango a alguien de la tuya. Mayús o Ctrl para elegir varias. Caducan en 24 h."))
end

local function Answer(r, ok)
    if KindOf(r) == "rank" then HU:AnswerRank(r, ok) else HU:AnswerKick(r, ok) end
end

-- Aceptar: la ventana de órdenes con las de cada una (echar: un /gremove; rango: un /gpromote o /gdemote
-- por cada rango que sube o baja). Cuando mandas todas las de una, se contesta a quien la pidió. Las de
-- prueba no hacen nada: solo se quitan
local function Accept(list)
    local real, lines = {}, {}
    for _, r in ipairs(list) do
        if r.test then
            HU:Print(L("(prueba) Aceptada: ") .. HU:Short(r.target))
            HU:RemoveKickRequest(r.id)
        elseif KindOf(r) == "rank" then
            local macro, why = HU:RankMacro(r.target, r.rank)
            if macro then
                for line in macro:gmatch("[^\n]+") do lines[#lines + 1] = line end
                real[#real + 1] = { r = r, upto = #lines }
            else
                HU:Print(HU:Short(r.target) .. ": " .. tostring(why))
            end
        else
            lines[#lines + 1] = HU.GuildCmd("gremove", r.target)
            real[#real + 1] = { r = r, upto = #lines }
        end
    end
    if #lines == 0 then return end
    HU:RunOrders({ title = L("Peticiones de oficiales"), text = HU:Short(real[1].r.target) .. (#real > 1 and (" (+" .. (#real - 1) .. ")") or ""), lines = lines,
        onDone = function(sent)
            for _, x in ipairs(real) do
                if (sent or 0) >= x.upto then
                    Answer(x.r, true)
                    if KindOf(x.r) == "kick" then HU:LogRequestedKick(x.r) end
                    HU:RemoveKickRequest(x.r.id)
                end
            end
        end })
end

local function Reject(list)
    for _, r in ipairs(list) do
        if r.test then HU:Print(L("(prueba) Rechazada: ") .. HU:Short(r.target))
        else Answer(r, false) end
        HU:RemoveKickRequest(r.id)
    end
end

-- Modo prueba: unas solicitudes de mentira (de echar y de rango) para ver la ventana; no se manda nada
local function AddTestRequests()
    local now = time()
    local tag = HU:OtherTags()[1] or "TEST"
    for i, who in ipairs({ "Prueba-Uno", "Prueba-Dos", "Prueba-Tres" }) do
        HU:AddKickRequest({ id = "testk" .. i .. now, target = who, requester = "Oficial-Prueba", reqTag = tag, t = now - i * 600, test = true })
    end
    for i, who in ipairs({ "Prueba-Cuatro", "Prueba-Cinco" }) do
        HU:AddKickRequest({ id = "testr" .. i .. now, kind = "rank", rank = i, target = who, requester = "Oficial-Prueba", reqTag = tag,
            t = now - i * 900, test = true })
    end
end

local function RowPick(row)
    local r = row.entry
    if not r then return end
    if IsControlKeyDown() then
        picked[r.id] = (not picked[r.id]) or nil
        lastPick = r.id
    elseif IsShiftKeyDown() and lastPick then
        local a, b
        for i, x in ipairs(shownReq) do
            if x.id == lastPick then a = i end
            if x.id == r.id then b = i end
        end
        if a and b then
            if a > b then a, b = b, a end
            picked = {}
            for i = a, b do picked[shownReq[i].id] = true end
        end
    else
        picked, lastPick = { [r.id] = true }, r.id
    end
    RefreshRequests()
end

function HU:ShowRequests()
    if not reqWin then
        reqWin = HU.NewListWindow({ name = "GuildUnionRequestsFrame", title = L("Peticiones de oficiales"), width = 600, height = 380, rows = 12,
            columns = { { L("Fecha"), 95 }, { L("Pide"), 175 }, { L("Persona"), 130 }, { L("Petición") } }, empty = L("No hay solicitudes.") })
        reqWin.Refresh = RefreshRequests
        -- (las dos pestañas, botones rojos del juego, arriba a la derecha)
        reqWin.tabs = {}
        local prev
        for _, t in ipairs({ { "all", L("Todas") }, { "kick", L("Echar") }, { "rank", L("Rango") } }) do
            local b = HU.NewButton(reqWin, t[2], 90)
            b.base = t[2]
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPRIGHT", reqWin, "TOPRIGHT", -310, -10) end
            b:SetScript("OnClick", function() reqView, picked = t[1], {}; FauxScrollFrame_SetOffset(reqWin.scroll, 0); RefreshRequests() end)
            reqWin.tabs[t[1]] = b
            prev = b
        end
        for _, row in ipairs(reqWin.rows) do
            row.pickTex = row:CreateTexture(nil, "BORDER")
            row.pickTex:SetAllPoints(); row.pickTex:SetColorTexture(0.25, 0.55, 1, 0.28)
            row.pickTex:Hide()
            row:SetScript("OnClick", RowPick)
            -- (al final de cada una, el tic para aceptarla y la X para rechazarla)
            local no = CreateFrame("Button", nil, row)
            no:SetSize(16, 16); no:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            no:SetNormalTexture(CROSS); no:SetHighlightTexture(CROSS, "ADD")
            no:SetScript("OnClick", function() if row.entry then Reject({ row.entry }) end end)
            local yes = CreateFrame("Button", nil, row)
            yes:SetSize(16, 16); yes:SetPoint("RIGHT", no, "LEFT", -6, 0)
            yes:SetNormalTexture(TICK); yes:SetHighlightTexture(TICK, "ADD")
            -- (las de prueba se quitan siempre, sin mirar permisos: no mandan nada)
            yes:SetScript("OnClick", function()
                local r = row.entry
                if r and (r.test or CanAnswer(KindOf(r))) then Accept({ r }) end
            end)
            row.yes, row.no = yes, no
            -- (la última columna no se mete debajo del tic y la X)
            row.cells[4]:SetPoint("RIGHT", row, "RIGHT", -52, 0)
        end
        -- (abajo: aceptar o rechazar las elegidas, y el modo prueba)
        reqWin.accept = HU.NewButton(reqWin, L("Aceptar"), 110)
        reqWin.accept:SetPoint("BOTTOMLEFT", reqWin, "BOTTOMLEFT", 14, 14)
        reqWin.accept:SetScript("OnClick", function() Accept(Picked()) end)
        reqWin.reject = HU.NewButton(reqWin, L("Rechazar"), 110)
        reqWin.reject:SetPoint("LEFT", reqWin.accept, "RIGHT", 6, 0)
        reqWin.reject:SetScript("OnClick", function() Reject(Picked()) end)
        reqWin.test = HU.NewButton(reqWin, L("Modo prueba"), 110)
        reqWin.test:SetPoint("BOTTOMRIGHT", reqWin, "BOTTOMRIGHT", -14, 14)
        reqWin.test:SetScript("OnClick", AddTestRequests)
        HU:Listen("CHANGED", function(what) if what == "requests" then RefreshRequests() end end)
    end
    if reqWin:IsShown() then reqWin:Hide() return end
    reqWin:Show()
end

---------------------------------------------------------------------------
-- «Oficiales»: un botón con su desplegable, siempre encima de él, con «Peticiones de oficiales» y «Ver registro» (Jorge,
-- 25/11: los dos botones «dentro de un mismo botón»). Lo ponen la vista de miembros y la de chat [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- (el texto con el número de peticiones que puedo hacer, si hay)
local function WithCount(text)
    local n = HU:KickRequestCount()
    return n > 0 and (text .. " (" .. n .. ")") or text, n
end
-- (atado encima del botón, como los desplegables del juego; sin su sistema de menús, el de clic derecho)
local function OpenAbove(owner, gen)
    local M, V, U = Menu, MenuVariants, MenuUtil
    if M and M.GetManager and M.PopulateDescription and V and V.GetDefaultContextMenuMixin and CreateAnchor
        and U and U.CreateRootMenuDescription then
        local desc = U.CreateRootMenuDescription(V.GetDefaultContextMenuMixin())
        M.PopulateDescription(gen, owner, desc)
        return M.GetManager():OpenMenu(owner, desc, CreateAnchor("BOTTOMLEFT", owner, "TOPLEFT", 0, 2))
    end
    if U and U.CreateContextMenu then return U.CreateContextMenu(owner, gen) end
end

function HU:OfficersButton(parent, name)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(110, 20)
    local menu, closedAt, wasOpen
    -- (con peticiones pendientes, el número y encendido)
    local function Sync()
        local text, n = WithCount(L("Oficiales"))
        b:SetText(text)
        if n > 0 then b:LockHighlight() else b:UnlockHighlight() end
    end
    -- (otro clic lo cierra. El juego cierra el menú con cualquier clic fuera de él, también en este botón, antes o
    -- después de que el botón se entere: lo cerrado en este mismo clic no se vuelve a abrir) [+ARCHITECTURE.md]
    b:HookScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        wasOpen = menu ~= nil or (closedAt ~= nil and GetTime() - closedAt < 0.1)
        if menu then menu:Close(); menu = nil end
    end)
    b:SetScript("OnClick", function(s)
        if wasOpen then wasOpen = nil; return end
        menu = OpenAbove(s, function(_, root)
            root:CreateButton((WithCount(L("Peticiones de oficiales"))), function() HU:ShowRequests() end)
            root:CreateButton(L("Ver registro"), function() HU:ShowInviteLog() end)
        end)
        if menu and menu.SetClosedCallback then menu:SetClosedCallback(function() menu, closedAt = nil, GetTime() end) end
    end)
    HU:Listen("CHANGED", function(what) if what == "requests" then Sync() end end)
    b:HookScript("OnShow", Sync)
    Sync()
    return b
end

HU:Module("InviteLog", { "Config", "Core", "ListWindow", "Orders", "Ranks", "Roster", "Social" })
