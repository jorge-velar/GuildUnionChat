-- Guild Union - cambiar rangos (en tu hermandad y, con permiso, en las demás)
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

HU.remoteRanks = {}   -- [tag] = { "Maestro", "Oficial", ... }  (posición 1 = rango 0)
local myRequests = {}

---------------------------------------------------------------------------
-- Permisos y rangos de mi hermandad
---------------------------------------------------------------------------
local function Can(old, new) local f = old or new; return f and f() and true or false end
function HU:CanPromote() return IsInGuild() and Can(CanGuildPromote, C_GuildInfo and C_GuildInfo.CanPromote) end
function HU:CanDemote() return IsInGuild() and Can(CanGuildDemote, C_GuildInfo and C_GuildInfo.CanDemote) end
function HU:CanManageRanks()
    return self:CanPromote() or self:CanDemote()
end

function HU:MyRankIndex()
    local _, _, idx = GetGuildInfo("player")
    return idx
end

function HU:MyRankNames()
    local out = {}
    if not IsInGuild() or not GuildControlGetNumRanks then return out end
    for i = 1, GuildControlGetNumRanks() do out[i] = GuildControlGetRankName(i) or (L("Rango ") .. (i - 1)) end
    return out
end

function HU:RankNames(tag)
    if tag == self.myTag then return self:MyRankNames() end
    return self.remoteRanks[tag] or {}
end

function HU:RankName(tag, idx)
    if idx == nil then return nil end
    local names = self:RankNames(tag)
    return names[idx + 1] or (L("Rango ") .. idx)
end

-- RN~ETIQ~nombres~rangos de oficial («1,2»). Los rangos van detrás y no se recortan nunca: si no
-- cabe todo, se recortan los nombres
function HU:RankNamesMessage()
    if not self.myTag then return nil end
    local names = {}
    for _, n in ipairs(self:MyRankNames()) do names[#names + 1] = (n:gsub("[~,]", " ")) end
    if #names == 0 then return nil end
    local officers = self.MyOfficerRanksText and self:MyOfficerRanksText() or ""
    local head = "RN~" .. self.myTag .. "~"
    local room = 250 - #head - #officers - 1
    return head .. HU.Utf8Cut(table.concat(names, ","), room) .. "~" .. officers
end

HU.comm.RN = function(self, sender, f, dist, raw)
    local tag = f[1]
    if not tag or tag == self.myTag or not self.cfg or not self.cfg.byTag[tag] then return end
    local names = {}
    for n in (f[2] or ""):gmatch("[^,]+") do if #names < 20 then names[#names + 1] = (n:gsub("[|%c~]", "")) end end
    if #names > 0 then
        self.remoteRanks[tag] = names
        -- (se guardan: los nombres de los rangos solo llegan con la lista entera, cada 30 min, y
        -- tras un /reload salía «Rango 0», «Rango 1» hasta entonces)
        self.db.remoteRanks = self.db.remoteRanks or {}
        self.db.remoteRanks[tag] = names
    end
    -- rangos de oficial de esa hermandad (si su versión los manda): valen lo mismo que los rangos de
    -- su lista, que trae el mismo enlace
    if f[3] and f[3] ~= "" then
        local set = {}
        for n in f[3]:gmatch("%d+") do
            local idx = tonumber(n)
            if idx and idx >= 1 and idx < 20 then set[idx] = true end
        end
        self.officerRanks[tag] = set
        self.db.officerRanks = self.db.officerRanks or {}
        self.db.officerRanks[tag] = set
        if self.RetryDeferred then self:RetryDeferred() end
    end
    if dist == "WHISPER" then self:Send(raw, "GUILD") end
    self:Changed("members")
end

HU:OnStart(function()
    for tag, names in pairs(HU.db.remoteRanks or {}) do
        if type(names) == "table" and not HU.remoteRanks[tag] then HU.remoteRanks[tag] = names end
    end
end)

---------------------------------------------------------------------------
-- Cambiar un rango en mi hermandad
---------------------------------------------------------------------------
local function FindRosterIndex(name)
    local k = HU:Key(name)
    for i = 1, (GetNumGuildMembers() or 0) do
        local n, _, rankIndex = GetGuildRosterInfo(i)
        if n and HU:Key(n) == k then return i, rankIndex end
    end
end

-- Cambiar un rango también es "protegido": se hace con /gpromote o /gdemote (una línea por
-- cada rango que sube o baja) desde un botón del juego. Devuelve el comando, o nil y el motivo.
function HU:RankMacro(name, newIndex)
    local i, cur = FindRosterIndex(name)
    if not i then return nil, L("no está en tu hermandad") end
    local mine = self:MyRankIndex() or 0
    local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks() or 10
    if newIndex == cur then return nil, L("ya tiene ese rango") end
    if newIndex < 0 or newIndex >= numRanks then return nil, L("ese rango no existe") end
    if cur <= mine then return nil, L("tiene un rango igual o superior al tuyo") end
    if newIndex <= mine then return nil, L("no puedes dar un rango igual o superior al tuyo") end
    if newIndex < cur and not self:CanPromote() then return nil, L("no tienes permiso para ascender") end
    if newIndex > cur and not self:CanDemote() then return nil, L("no tienes permiso para degradar") end
    local cmd = (newIndex < cur) and "gpromote" or "gdemote"
    local lines = {}
    for _ = 1, math.abs(newIndex - cur) do lines[#lines + 1] = HU.GuildCmd(cmd, name) end
    return table.concat(lines, "\n"), cur
end

-- Devuelve true si se ha hecho, o false y el motivo (lo usa el modo prueba y versiones viejas)
---------------------------------------------------------------------------
-- Pedir un cambio de rango a otra hermandad
---------------------------------------------------------------------------
HU.Dialogs["HERMANDADUNIDA_RANK"] = HU.LT({
    text = "%s",
    button1 = "Aceptar",
    button2 = "Rechazar",
    secure = function(data) return data and HU:RankMacro(data.target, data.rank) or nil end,
    OnAccept = function(_, data) HU:AnswerRank(data, true) end,
    OnCancel = function(_, data, reason) if reason == "clicked" then HU:AnswerRank(data, false) end end,
    timeout = 300,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
})

function HU:AnswerRank(data, accept)
    if not data then return end
    local ok, why = false, "rechazado"
    if accept then
        -- (el botón del juego ya ha hecho /gpromote o /gdemote)
        local macro, why2 = self:RankMacro(data.target, data.rank)
        local _, nowRank = FindRosterIndex(data.target)
        -- (vale si aún se puede hacer, o si ya lo tiene: el juego a veces ya lo ha aplicado)
        ok, why = (macro ~= nil or nowRank == data.rank), why2
        if not ok then self:Print(L("No se pudo cambiar el rango: ") .. (why or "?"))
        else HU.After(1, function() HU:RequestRoster(true) end) end
    end
    self:Send("RD~" .. data.id, "GUILD", nil, true)
    self:Whisper(data.requester, table.concat({ "RR", data.id, ok and "ok" or "no", self:Me(), data.target, ok and "" or (why or "") }, "~"), true)
    if not accept then
        self:AddAudit({ tag = self.myTag, actor = self:Me(),
            text = L("rechazó la petición de ") .. self:Short(data.requester) .. " (" .. data.target .. L(" como ") .. self:RankName(self.myTag, data.rank) .. ")" }, "all")
    end
end

HU.comm.RD = function(self, _, f)
    local id = f[1]
    if not id then return end
    HU:HideDialogs("HERMANDADUNIDA_RANK", function(d) return d and d.id == id end)
end

HU.comm.RR = function(self, _, f)
    local id, result, who, target, why = f[1], f[2], f[3], f[4], f[5]
    local req = id and myRequests[id]
    if not req then return end
    myRequests[id] = nil
    if result == "ok" then
        self:Print(L("|cff44ff44Hecho:|r ") .. (target or "?") .. L(" ahora es ") .. self:RankName(req.tag, req.rank) .. L(" (lo aplicó ") .. self:Short(who or "?") .. ").")
    else
        self:Print(L("|cffff4444No aplicado:|r ") .. (target or "?") .. " (" .. self:Short(who or "?") .. ": " .. ((why and why ~= "") and why or "rechazado") .. ").")
    end
end

---------------------------------------------------------------------------
-- Punto único para el panel
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Rango "Castigado": al silenciar o vetar a alguien de tu hermandad, se le puede bajar a ese [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local PUNISH_NAMES = { castigado = true, castigada = true, castigados = true, punished = true }
function HU:PunishRank()
    if not (GuildControlGetNumRanks and GuildControlGetRankName) then return nil end
    for i = 1, GuildControlGetNumRanks() do
        local n = GuildControlGetRankName(i)
        if n and PUNISH_NAMES[HU.Trim(n):lower()] then return i - 1, n end
    end
    return nil
end

function HU:OfferPunish(name)
    if not self:InMyGuild(name) or not self:CanDemote() then return end
    local idx, rname = self:PunishRank()
    if not idx then
        -- (sin rango de castigo: el silencio vale en la comunidad, pero en /g le siguen viendo quienes no tienen el addon)
        return self:ShowDialog("GU_NOPUNISH", self:Nice(name))
    end
    local _, cur = FindRosterIndex(name)
    if not cur or cur >= idx then return end
    local macro = self:RankMacro(name, idx)
    if not macro then return end
    self.db.punished = self.db.punished or {}
    self.db.punished[self:Key(name)] = { name = self:FullName(name), rank = cur, by = self:Me(), t = HU.StampNow() }
    self:ShowDialog("GU_PUNISH", string.format(L("¿Bajar a |cffffd100%s|r al rango |cffff6060%s|r mientras dure?\n(así el juego tampoco le deja escribir en la hermandad)"),
        self:Nice(name), rname), nil, { name = name, rank = idx })
end

-- ¿Está conectado ese jugador de mi hermandad?
local function OnlineInGuild(name)
    local i = name and FindRosterIndex(name)
    return i and select(9, GetGuildRosterInfo(i)) and true or false
end

-- Castigo repartido a los oficiales de mi hermandad: KS~nombre~rango de antes~quién~t (rango -1 = ya devuelto) [+ARCHITECTURE.md]
local function SharePunish(name, rank, by)
    if not (HU.myTag and IsInGuild()) then return end
    HU:Send(table.concat({ "KS", HU:FullName(name) or name, rank, by or "", HU.StampNow() }, "~"), "GUILD", nil, true)
end

HU.comm.KS = function(self, sender, f, dist)
    if dist ~= "GUILD" then return end
    local name, rank, by, t = HU.SafeName(f[1]), tonumber(f[2]), f[3], HU.NetStamp(f[4])
    local k = name and self:Key(name)
    if not (k and rank and t) then return end
    if not self:CheckOfficer(sender, self.myTag, function() HU.comm.KS(self, sender, f, dist) end, sender, dist) then return end
    self.db.punished = self.db.punished or {}
    local cur = self.db.punished[k]
    if cur and (cur.t or 0) > t then return end
    if rank < 0 then
        self.db.punished[k] = nil
        self:HideDialogs("GU_UNPUNISH", function(d) return d and d.key == k end)
    else
        self.db.punished[k] = { name = self:FullName(name) or name, rank = rank, by = (HU.SafeName(by) or sender), t = t }
    end
end

-- Devolver el rango: lo ofrece quien castigó; si no está conectado, cualquier oficial que pueda.
-- (quien castigó lo vuelve a ver al entrar; el primero que pulsa Devolver, y a los demás se les cierra)
local offeredT = {}
local OFFER_AGAIN = 600
function HU:OfferRestoreRank(name, force)
    local k = self:Key(name)
    local p = k and self.db.punished and self.db.punished[k]
    if not p or self:IsTest() or not self:InMyGuild(name) then return end
    local idx = self:PunishRank()
    local _, cur = FindRosterIndex(name)
    if not cur or (idx and cur ~= idx) then self.db.punished[k] = nil return end -- (ya le han cambiado el rango)
    local mine = not p.by or self:Key(p.by) == self:MeKey()
    if not mine and OnlineInGuild(p.by) then return end
    if not force and offeredT[k] and GetTime() - offeredT[k] < OFFER_AGAIN then return end
    if not self:RankMacro(name, p.rank) then return end
    offeredT[k] = GetTime()
    self:HideDialogs("GU_UNPUNISH", function(d) return d and d.key == k end)
    self:ShowDialog("GU_UNPUNISH", string.format(L("Se ha acabado el castigo de |cffffd100%s|r. ¿Devolverle su rango (|cffffd100%s|r)?"),
        self:Nice(name), self:RankName(self.myTag, p.rank) or "?"), nil, { name = name, rank = p.rank, key = k })
end

HU.Dialogs["GU_PUNISH"] = HU.LT({
    text = "%s",
    button1 = "Bajar",
    button2 = "No",
    secure = function(data) return data and HU:RankMacro(data.name, data.rank) or nil end,
    OnAccept = function(_, data)
        HU:AddAudit({ tag = HU.myTag, actor = HU:Me(), text = L("bajó al rango de castigo a ") .. HU:Short(data.name) }, "all")
        local p = HU.db.punished and HU.db.punished[HU:Key(data.name)]
        if p then SharePunish(p.name, p.rank, HU:Me()) end
        HU.After(1, function() HU:RequestRoster(true) end)
    end,
    OnCancel = function(_, data) if data and HU.db.punished then HU.db.punished[HU:Key(data.name)] = nil end end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
})
HU.Dialogs["GU_NOPUNISH"] = HU.LT({
    text = "Para que |cffffd100%s|r tampoco pueda escribir en la hermandad, crea un rango llamado |cffff6060Castigado|r sin permiso para hablar en el chat de hermandad.\n(El silencio en el chat de la comunidad ya está puesto.)",
    button1 = "Entendido",
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
})
HU.Dialogs["GU_UNPUNISH"] = HU.LT({
    text = "%s",
    button1 = "Devolver",
    button2 = "Ahora no",
    secure = function(data) return data and HU:RankMacro(data.name, data.rank) or nil end,
    OnAccept = function(_, data)
        if HU.db.punished then HU.db.punished[data.key] = nil end
        SharePunish(data.name, -1, HU:Me())
        HU:AddAudit({ tag = HU.myTag, actor = HU:Me(), text = L("devolvió su rango a ") .. HU:Short(data.name) }, "all")
        HU.After(1, function() HU:RequestRoster(true) end)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
})

-- Castigos ya acabados: 20 s después de entrar y luego cada 30 s (los silencios llegan a todos los oficiales)
local function CheckPunished()
    for _, p in pairs(HU.db.punished or {}) do
        if not HU:IsMuted(p.name) then HU:OfferRestoreRank(p.name) end
    end
end
HU:OnStart(function()
    HU.After(20, function()
        CheckPunished()
        HU.NewTicker(30, CheckPunished)
    end)
end)
