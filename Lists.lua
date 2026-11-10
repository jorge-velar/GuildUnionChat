-- Guild Union - listas completas de miembros (lista blanca del canal)
local ADDON_NAME, HU = ...

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

HU.whitelist = {}          -- [tag] = { list = {nombres}, set = {[clave]=true}, hash, count, t }
local FRESH = 30 * 60      -- una lista sin confirmar en 30 min deja de valer (GU20: se confirma cada 10)

function HU.Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%04x%04x", math.floor(h / 65536), math.floor(h % 65536))
end

-- Mi propia lista, a partir de la lista de la hermandad
local myCache = {}
function HU:MyList()
    -- (solo se rehace si han cambiado los nombres, no con cada lectura de la lista)
    local v = self.rosterNamesV
    if myCache.src == self.rosterList or (v and myCache.v == v) then return myCache end
    local names = {}
    for _, e in ipairs(self.rosterList) do names[#names + 1] = self:Short(e.name):gsub("[~,]", "") end
    table.sort(names)
    myCache = { src = self.rosterList, v = v, list = names, hash = HU.Hash(table.concat(names, ",")), count = #names }
    return myCache
end

function HU:ListFor(tag)
    if tag == self.myTag then
        if #self.rosterList == 0 then return nil end
        local m = self:MyList()
        return { list = m.list, hash = m.hash, count = m.count, t = time() }
    end
    return self.whitelist[tag]
end

function HU:ListFresh(tag)
    local L = self:ListFor(tag)
    return L ~= nil and (time() - (L.t or 0)) < FRESH
end

-- ¿Está en alguna de las hermandades?
function HU:InAnyGuild(name)
    local k = self:Key(name)
    if not k then return false end
    if self.roster[k] then return true end
    for _, L in pairs(self.whitelist) do
        if L.set[k] then return true end
    end
    -- (también los conectados de las otras hermandades, aunque su lista
    -- completa aún no haya llegado o no tenga todavía a alguien que acaba de entrar)
    for _, r in pairs(self.remoteRoster) do
        if r.byKey and r.byKey[k] and not r.byKey[k].weak then return true end
    end
    -- confirmado por su hermandad (la guardia le preguntó) o en sus inactivos
    if self.GuardKnown and self:GuardKnown(name) then return true end
    for _, list in pairs(self.db.offline or {}) do
        if list[k] then return true end
    end
    return false
end

-- ¿Está este jugador en la lista de ESA hermandad? (no basta con estar en cualquiera)
local memberIdx = setmetatable({}, { __mode = "k" })
function HU:MemberOf(name, tag)
    local k = self:Key(name)
    if not k or not tag then return false end
    if tag == self.myTag then
        if self.roster[k] then return true end
        return self:IsTest() and (k == self:MeKey() or (self.db.test and self.db.test.allow[k] ~= nil)) or false
    end
    local L = self.whitelist[tag]
    if L and L.set and L.set[k] then return true end
    local r = self.remoteRoster[tag]
    if r and r.byKey then return r.byKey[k] ~= nil and not r.byKey[k].weak end
    if r then
        -- (sin índice: se hace uno aparte la primera vez y se rehace si la lista cambia. Antes se [+ARCHITECTURE.md]
        local members = r.members or {}
        local ix = memberIdx[r]
        local function build()
            ix = { m = members, n = #members, pos = {} }
            for i, m in ipairs(members) do
                local key = m.name and m.name:lower()
                if key and not ix.pos[key] then ix.pos[key] = i end
            end
            memberIdx[r] = ix
        end
        if not ix or ix.m ~= members or ix.n ~= #members then build() end
        local i = ix.pos[k]
        local m = i and members[i]
        if i and not (m and m.name and m.name:lower() == k) then
            build()
            i = ix.pos[k]
            m = i and members[i]
        end
        -- (altas: la lista crece y se rehace; bajas: la lista es otra y se rehace; correcciones: el
        -- mismo nombre en el mismo sitio. Así que si no está en el índice, no está en la lista)
        if not m then return false end
        if not m.weak then return true end
        -- (por si hay dos con el mismo nombre y el primero era de arranque)
        for _, m2 in ipairs(members) do if m2.name and m2.name:lower() == k and not m2.weak then return true end end
        return false
    end
    return false
end

-- Seguridad: quien firma una acción de oficial (fijar, silenciar, notas públicas, canales...) [+ARCHITECTURE.md]
function HU:TrustedOfficer(author, tag)
    if not author or author == "" then return false end
    if not self:InAnyGuild(author) then
        -- todavía no tengo la lista de su hermandad (acabo de entrar): se espera a tenerla
        if tag and tag ~= "" and tag ~= self.myTag and self.cfg and self.cfg.byTag[tag] and not self.whitelist[tag] then
            return false, "unknown"
        end
        return false
    end
    local rTag, idx = self:RankInfoOf(author)
    if idx == nil then return false, "unknown" end
    return self:RankRole(rTag or tag, idx) ~= nil
end

-- ¿Es maestro de su hermandad? (para lo que solo puede hacer el maestro)
function HU:TrustedMaster(author, tag)
    if not author or author == "" then return false end
    if not self:InAnyGuild(author) then
        if tag and tag ~= "" and tag ~= self.myTag and self.cfg and self.cfg.byTag[tag] and not self.whitelist[tag] then
            return false, "unknown"
        end
        return false
    end
    local _, idx = self:RankInfoOf(author)
    if idx == nil then return false, "unknown" end
    return idx == 0
end
function HU:CheckMaster(author, tag, retry, sender, dist)
    if not self:MayCarryOrDefer(author, tag, retry, sender, dist) then return false end
    local ok, why = self:TrustedMaster(author, tag)
    if not ok and why == "unknown" and retry then self:Defer(retry) end
    return ok
end

-- Acciones de oficial que esperan a conocer el rango de quien las firma [+ARCHITECTURE.md]
local deferred, deferT = {}, nil
function HU:Defer(fn)
    if #deferred >= 60 then table.remove(deferred, 1) end
    deferred[#deferred + 1] = { fn = fn, t = deferT or GetTime() }
end

function HU:RetryDeferred()
    if #deferred == 0 then return end
    local list = deferred
    deferred = {}
    local now = GetTime()
    for _, d in ipairs(list) do
        if now - d.t < 900 then
            deferT = d.t
            local ok, err = pcall(d.fn)
            deferT = nil
            if not ok and self.Debug then self:Debug("Acción en espera:", err) end
        end
    end
end

---------------------------------------------------------------------------
-- Seguridad: QUIÉN TRAE una acción de oficial (no solo quién dice firmarla). [+ARCHITECTURE.md]
---------------------------------------------------------------------------
function HU:IsGuildForwarder(sender)
    local sk = self:Key(sender)
    local e = sk and self.roster[sk]
    if not e then return false end
    if self:RankRole(self.myTag, e.rankIndex) then return true end
    local relay = self.RelayName and self:RelayName()
    if relay and self:Key(relay) == sk then return true end
    local short = self:Short(sender):lower()
    local h = self.relayHelpers
    if h and GetTime() - h.t < 700 then
        if h.relay and self:Key(h.relay) == sk then return true end
        for _, n in ipairs(h.list) do if self:Short(n):lower() == short then return true end end
    end
    if self.IsRelay and self:IsRelay() then
        for _, n in ipairs(self.advertisedHelpers or {}) do if self:Short(n):lower() == short then return true end end
    end
    return false
end

function HU:IsRemoteForwarder(sender, tag)
    local sk = self:Key(sender)
    if not sk or not tag or tag == "" or tag == self.myTag then return false end
    if not self:MemberOf(sender, tag) then return false end
    local rTag, idx = self:RankInfoOf(sender)
    if idx ~= nil and self:RankRole(rTag or tag, idx) then return true end
    local p = self.remote[sk]
    if p and p.tag == tag and p.relay then return true end
    local h = self.helpers and self.helpers[tag]
    if h and GetTime() - h.t < 900 then
        local short = self:Short(sender):lower()
        for _, n in ipairs(h.list) do if self:Short(n):lower() == short then return true end end
    end
    return false
end

-- Peticiones a los oficiales (echar, cambiar rango): como mucho 3 por minuto de cada uno.
-- Antes no había límite y cualquiera inundaba de ventanas a los oficiales.
local reqRate = {}
function HU.RequestRate(name)
    local k, now = (name or ""):lower(), GetTime()
    local r = reqRate[k]
    if not r or now - r.t > 60 then r = { t = now, n = 0 }; reqRate[k] = r end
    r.n = r.n + 1
    return r.n <= 3
end

-- sender == nil: la llamada no viene de la red (la hace el propio addon)
function HU:MayCarry(author, sender, dist, tag)
    if sender == nil or self:IsTest() then return true end
    local sk = self:Key(sender)
    if not sk then return false end
    if author and author ~= "" and self:Key(author) == sk then return true end
    if dist == "GUILD" then return self:IsGuildForwarder(sender) end
    if dist == "WHISPER" then
        -- (la hermandad de verdad del firmante, no la que pone el mensaje: antes el enlace o un
        -- ayudante de Y traía acciones firmadas por un oficial de X poniendo «Y» en el mensaje)
        local aTag = self:RankInfoOf(author)
        if aTag and tag and tag ~= "" and tag ~= aTag then return false end
        aTag = aTag or ((tag and tag ~= "") and tag or nil)
        return aTag ~= nil and self:IsRemoteForwarder(sender, aTag)
    end
    return false
end

-- Como MayCarry, pero si aún no sé quién es el enlace de mi hermandad (acabo de entrar) la acción
-- espera en vez de perderse: se reintenta al saberlo
function HU:MayCarryOrDefer(author, tag, retry, sender, dist)
    if self:MayCarry(author, sender, dist, tag) then return true end
    if retry and dist == "GUILD" and self.KnownGuildRelay and not self:KnownGuildRelay() then self:Defer(retry)
    elseif retry and dist == "WHISPER" and not self:MemberOf(sender, (tag and tag ~= "") and tag or "") then self:Defer(retry) end
    if self.Debug then self:Debug("Acción de oficial rechazada: la trae", sender, "firmada por", author) end
    return false
end

-- Comprueba al oficial; si aún no se sabe su rango, deja la acción en espera
function HU:CheckOfficer(author, tag, retry, sender, dist)
    if not self:MayCarryOrDefer(author, tag, retry, sender, dist) then return false end
    local ok, why = self:TrustedOfficer(author, tag)
    if not ok and why == "unknown" and retry then self:Defer(retry) end
    return ok
end

-- Seguridad: acciones que cambian la comunidad y se quedan (canal y contraseña, canales extra, [+ARCHITECTURE.md]
local function FirmRank(self, author)
    local rTag = self:RankInfoOf(author)
    if not rTag or rTag == self.myTag then return true end
    local stateOf = HU.RosterStateOf
    if not stateOf then return true end -- (sin el estado de las listas: como antes)
    local s = stateOf(self.remoteRoster[rTag])
    return s == nil or s == "c"
end
function HU:CheckOfficerFirm(author, tag, retry, sender, dist)
    if not self:CheckOfficer(author, tag, retry, sender, dist) then return false end
    if self:IsTest() or FirmRank(self, author) then return true end
    if retry then self:Defer(retry) end
    if self.Debug then self:Debug("Acción de estructura en espera (lista sin confirmar):", author) end
    return false
end
function HU:CheckMasterFirm(author, tag, retry, sender, dist)
    if not self:CheckMaster(author, tag, retry, sender, dist) then return false end
    if self:IsTest() or FirmRank(self, author) then return true end
    if retry then self:Defer(retry) end
    return false
end

-- en comunidades grandes (más de 6 hermandades) las listas completas ya no se [+ARCHITECTURE.md]
function HU:BigCommunity()
    return self.cfg ~= nil
end

-- Fase de lanzamiento: a las otras hermandades solo van el maestro, los oficiales, el enlace y sus [+ARCHITECTURE.md]
HU.PHASE = "launch"
-- Versión «solo chat» (5.4.11): siempre fase de lanzamiento. Por dentro solo viaja la lista pequeña [+ARCHITECTURE.md]
HU.CHAT_ONLY = true
function HU:LaunchPhase()
    if HU.CHAT_ONLY then return true end
    local p = (self.db and self.db.phase) or HU.PHASE
    return p ~= "full"
end

-- (ReduceClean: sin listas completas de miembros —WH, WQ, WL, WD, envío por trozos y ciclo de 3 min—:
-- estaban siempre cortadas por BigCommunity. Quedan vacías estas dos, que aún llaman Comm.lua)
function HU:AnnounceList() end
function HU:SendList() end

-- avisos del juego de altas y bajas en la hermandad: se pide la lista de la hermandad enseguida
local joinPat
local function GuildChangePatterns()
    if joinPat then return joinPat end
    joinPat = {}
    for _, g in ipairs({ "ERR_GUILD_JOIN_S", "ERR_GUILD_LEAVE_S", "ERR_GUILD_REMOVE_SS", "ERR_GUILD_PROMOTE_SSS", "ERR_GUILD_DEMOTE_SSS" }) do
        local fmt = _G[g]
        if type(fmt) == "string" then
            local tmp = fmt:gsub("%%%d?%$?s", "\001")
            tmp = tmp:gsub("([%(%)%.%-%+%*%?%[%]%^%$])", "%%%1")
            local pat = "^" .. tmp:gsub("\001", ".+") .. "$"
            joinPat[#joinPat + 1] = pat
        end
    end
    return joinPat
end
HU:On("CHAT_MSG_SYSTEM", function(text)
    if type(text) ~= "string" or not HU.myTag then return end
    for _, pat in ipairs(GuildChangePatterns()) do
        if text:find(pat) then
            if HU.RequestRoster then HU:RequestRoster(true) end
            return
        end
    end
end)

---------------------------------------------------------------------------
-- Arranque y ciclo
---------------------------------------------------------------------------
HU:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    -- (las listas completas guardadas de antes tampoco se cargan: pudieron llegar de cualquiera.
    -- Con las listas apagadas no vuelven a llenarse; si se encienden, se piden de nuevo)
    HU.db.lists = {}
end)

