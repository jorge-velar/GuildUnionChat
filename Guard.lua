-- Guild Union - guardia: solo se echa a quien no está en ninguna de las hermandades
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

HU.pendingSince = {} -- [clave] = desde cuándo está en el canal sin aparecer en ninguna lista
HU.intruders = {}    -- para el panel: { name, since }
HU.kicked = {}       -- [clave] = momento
HU.guardStatus = "Sin iniciar"

---------------------------------------------------------------------------
-- Lista de miembros del canal
---------------------------------------------------------------------------
-- (con miles de personas leerla entera cuesta: se guarda unos segundos y se reutiliza)
local MEMBERS_TTL = 10
local membersCache = {} -- [kind] = { id, t, list, iAmMod }

local function IsMe(self, k, name, me, meShort)
    return k == me or k:gsub("%-.*$", "") == meShort or self:Short(name):lower() == meShort
end

function HU:GetChannelMembers(kind, fresh)
    kind = kind or "main"
    local id = self:ChannelId(kind)
    if not id then membersCache[kind] = nil return nil end
    local c = membersCache[kind]
    if not fresh and c and c.id == id and GetTime() - c.t < MEMBERS_TTL then return c.list end
    local rid, num, info = self:ChannelRoster(kind)
    if not rid or num == 0 then return nil end
    local me = self:MeKey()
    local list, iAmMod, found = {}, false, false
    local mods, modList, seen, keys = {}, {}, {}, {}
    for i = 1, num do
        local name, owner, mod = info(rid, i)
        if name then
            local m = { name = self:FullName(name), owner = owner and true or false, mod = (mod or owner) and true or false }
            list[#list + 1] = m
            local k = m.name:lower()
            keys[k] = true
            -- (primero la comprobación barata; la completa, solo si no aparezco así)
            if not found and k == me then found, iAmMod = true, m.mod end
            if m.mod then mods[k] = true; modList[#modList + 1] = m end
            seen[#seen + 1] = m.name
        end
    end
    if #list == 0 then return nil end -- (el juego aún no ha cargado la lista: se repite luego)
    return self:StoreChannelMembers(kind, id, list, iAmMod, found, mods, modList, seen, keys)
end

-- sliced: la lectura por trozos ya ha hecho la búsqueda de mi línea y el «visto en el canal»
function HU:StoreChannelMembers(kind, id, list, iAmMod, found, mods, modList, seen, keys, sliced)
    if #list == 0 then return nil end
    if sliced then found = true end
    -- (quién está en el canal: tiene la contraseña. En Forever lo oculto por el canal no llega, así que
    -- esto sustituye a «ha hablado por el canal oculto» para arrancar con otra hermandad: HU:Vouched)
    if kind == "main" and keys then
        self.chanRosterKeys, self.chanRosterKeysT = keys, GetTime()
        if self.ReplayHeld then HU.After(0, function() HU:ReplayHeld() end) end
    end
    if not found then
        local me = self:MeKey()
        local meShort = self:Short(self:Me() or ""):lower()
        for _, m in ipairs(list) do
            if IsMe(self, m.name:lower(), m.name, me, meShort) then iAmMod = m.mod break end
        end
    end
    membersCache[kind] = { id = id, t = GetTime(), list = list, iAmMod = iAmMod, keys = keys }
    -- («visto en el canal» = quien está ahora en él: hace falta la contraseña para entrar. En Forever no [+ARCHITECTURE.md]
    if kind == "main" and self.chanSeen and not sliced then
        local now = GetTime()
        for _, m in ipairs(list) do
            local k = m.name and m.name:lower()
            if k then self.chanSeen[k] = now end
        end
        if self.ReplayHeld then HU.After(0, function() HU:ReplayHeld() end) end
    end
    if kind == "main" then
        -- quiénes son moderadores (para saludarlos)
        self.chanMods, self.chanModList = mods, modList
        self.chanIAmMod = iAmMod
        self.chanMembersSeen = seen
    end
    return list
end

-- La misma lista, leída por trozos: para lo que no tiene prisa, como el saludo (con miles en el canal, [+ARCHITECTURE.md]
local ASYNC_SLICE, ASYNC_STEP, ASYNC_BUDGET = 150, 0.02, 1.5
local profile = debugprofilestop
local building = {} -- [kind] = lectura en curso
function HU:GetChannelMembersAsync(kind, fn)
    kind = kind or "main"
    local id = self:ChannelId(kind)
    if not id then membersCache[kind] = nil; return fn(nil) end
    local c = membersCache[kind]
    if c and c.id == id and GetTime() - c.t < MEMBERS_TTL then return fn(c.list) end
    local b = building[kind]
    if b and b.id == id and GetTime() - b.started < 10 then b.fns[#b.fns + 1] = fn; return end
    local rid, num, info = self:ChannelRoster(kind)
    if not rid or num == 0 then return fn(nil) end
    b = { id = id, rid = rid, num = num, i = 1, started = GetTime(), fns = { fn }, list = {}, mods = {}, modList = {},
        seen = {}, keys = {}, found = false, iAmMod = false, me = self:MeKey() }
    building[kind] = b
    local meShort = self:Short(self:Me() or ""):lower()
    local seenT = (kind == "main") and self.chanSeen
    local function Step()
        if building[kind] ~= b then return end
        local t0 = profile and profile()
        local last = math.min(b.num, b.i + ASYNC_SLICE - 1)
        local i = b.i
        while i <= last do
            local name, owner, mod = info(b.rid, i)
            if name then
                local m = { name = self:FullName(name), owner = owner and true or false, mod = (mod or owner) and true or false }
                local k = m.name and m.name:lower()
                -- (repetido: el canal se movió mientras se leía)
                if k and not b.keys[k] then
                    b.keys[k] = true
                    b.list[#b.list + 1] = m
                    if not b.found and (k == b.me or IsMe(self, k, m.name, b.me, meShort)) then b.found, b.iAmMod = true, m.mod end
                    if m.mod then b.mods[k] = true; b.modList[#b.modList + 1] = m end
                    b.seen[#b.seen + 1] = m.name
                    if seenT then seenT[k] = GetTime() end
                end
            end
            i = i + 1
            if t0 and profile() - t0 > ASYNC_BUDGET then break end
        end
        b.i = i
        if b.i <= b.num then return HU.After(ASYNC_STEP, Step) end
        building[kind] = nil
        if #b.list == 0 then -- (el juego aún no ha cargado la lista: se repite luego)
            for _, f in ipairs(b.fns) do HU:SafeCall("canal", f, nil) end
            return
        end
        local list = HU:StoreChannelMembers(kind, b.id, b.list, b.iAmMod, b.found, b.mods, b.modList, b.seen, b.keys, seenT and true or nil)
        HU.After(0, function()
            for _, f in ipairs(b.fns) do HU:SafeCall("canal", f, list) end
        end)
    end
    Step()
end

-- Busca solo mi línea en la lista del canal: true/false, o nil si no se puede saber así
function HU:QuickAmIMod()
    local id, num, info = self:ChannelRoster("main")
    if not id or num == 0 then return nil end
    local me = self:MeKey()
    if not me then return nil end
    -- (en Forever el juego puede dar "Nombre Apellido" o "Nombre-Apellido")
    local meSpace = me:gsub("%-", " ", 1)
    for i = 1, num do
        local name, owner, mod = info(id, i)
        if name then
            local k = name:lower()
            if k == me or k == meSpace then return (mod or owner) and true or false end
        end
    end
    return nil -- (no me he encontrado así: que lo mire la lectura completa)
end

-- Los moderadores han cambiado: la próxima lectura será nueva
function HU:ForgetChannelMembers()
    wipe(membersCache)
end

-- ¿Soy moderador? Sin construir la lista entera del canal (con miles de personas costaba 10-15 ms
-- de golpe al silenciar): lo que ya sabe la guardia y, si no, la búsqueda rápida
function HU:AmIModFast()
    if self.chanIAmMod ~= nil then return self.chanIAmMod == true end
    -- (quien no puede ser moderador no recorre el canal para saberlo: ver NeedsChannelList)
    if self.NeedsChannelList and not self:NeedsChannelList() then return false end
    return self:QuickAmIMod() == true
end

function HU:AmIMod(members)
    if members == nil then
        if not self:GetChannelMembers("main") then return false end
        return membersCache.main and membersCache.main.iAmMod or false
    end
    for _, c in pairs(membersCache) do
        if c.list == members then return c.iAmMod end
    end
    local me = self:MeKey()
    local meShort = self:Short(self:Me() or ""):lower()
    for _, m in ipairs(members) do
        if IsMe(self, m.name:lower(), m.name, me, meShort) then return m.mod end
    end
    return false
end

-- Resumen del canal para el panel y para /gu canal
function HU:ChannelSummary()
    local members = self:GetChannelMembers("main")
    if not members then return nil end
    local owner, mods = nil, {}
    for _, m in ipairs(members) do
        if m.owner then owner = self:Short(m.name)
        elseif m.mod then mods[#mods + 1] = self:Short(m.name) end
    end
    return #members, owner, mods
end

function HU:PrintChannelRoster()
    local id, num, info, chatId = self:ChannelRoster("main")
    if not id then
        if self:ChannelId("main") and ChannelFrame and ChannelFrame:IsShown() then
            return self:Print(L("Cierra la ventana de canales (o selecciona en ella el de la comunidad) y vuelve a probar."))
        end
        self:Print(L("No estás en el canal.")) return
    end
    self:Print(L("Canal ") .. self.chan.main.name .. L(" (número ") .. chatId .. "): " .. num .. L(" personas. Tu nombre: ") .. tostring(self:Me()))
    for i = 1, math.min(num, 40) do
        local a, b, c, d, e = info(id, i)
        self:Print(string.format(L("  %d. %s  propietario=%s  moderador=%s  [%s %s]"), i, tostring(a), tostring(b), tostring(c), tostring(d), tostring(e)))
    end
end

-- Lista de conectados de otra hermandad que vale para la guardia: llegó o su enlace confirmó
-- su huella hace menos de 15 minutos
local ONLINE_FRESH = 900
function HU:OnlineListFresh(tag)
    local r = self.remoteRoster[tag]
    if not r then return false end
    return GetTime() - math.max(r.updated or 0, r.confirmed or 0) < ONLINE_FRESH
end

function HU:MissingLists()
    local missing = {}
    if not self.cfg or self:IsTest() then return missing end
    -- con más de 6 hermandades las listas completas no se reparten; quien está en el canal está
    -- conectado, así que basta con la lista de conectados de su hermandad
    for _, g in ipairs(self.cfg.guilds) do
        local ok
        if g.tag ~= self.myTag then ok = self:OnlineListFresh(g.tag) else ok = self:ListFresh(g.tag) end
        if not ok then missing[#missing + 1] = g.tag end
    end
    return missing
end

---------------------------------------------------------------------------
-- Expulsar
---------------------------------------------------------------------------
function HU:KickPlayer(name, ban, force, auto)
    local c = self.chan.main
    if not c or not c.name or not name then return end
    if force then
        -- recién echado de su hermandad: solo si está en el canal y somos moderadores
        local members = self:GetChannelMembers("main")
        if not members then return end
        local inChan = false
        for _, m in ipairs(members) do if m.name:lower() == name:lower() then inChan = true end end
        if not inChan then return end
        if not self:AmIMod(members) then
            self:Print(L("No eres moderador del canal: a ") .. self:Short(name) .. L(" lo echará del chat la guardia de un moderador."))
            return
        end
    -- última comprobación: jamás a alguien de las hermandades
    elseif self:InAnyGuild(name) then
        self:Print(self:Short(name) .. L(" está en una de las hermandades: no se le echa."))
        return
    end
    local fn
    if ban then fn = ChannelBan or (C_ChatInfo and C_ChatInfo.ChannelBan)
    else fn = ChannelKick or (C_ChatInfo and C_ChatInfo.ChannelKick) end
    if not fn then
        self:Print(L("Esta versión del juego no permite ") .. (ban and "vetar" or "echar") .. L(" desde un addon. Usa /") .. (ban and "ban" or "ckick") .. ".")
        return
    end
    fn(c.name, self:Short(name))
    local k = name:lower()
    self.kicked[k] = GetTime()
    self.pendingSince[k] = nil
    for i = #self.intruders, 1, -1 do
        if self.intruders[i].name:lower() == k then table.remove(self.intruders, i) end
    end
    self:AddAudit({ tag = self.myTag, actor = self:Me(), text = (ban and L("vetó a ") or L("echó a ")) .. self:Short(name) .. L(" del canal") }, "all")
    -- (lo que echa la guardia sola no cuenta para las rachas; el veto del chat cuenta en SetBan)
    if not auto and not force and self.KillStreak then self:KillStreak(ban and "ban" or "kick", name) end
    self:Changed("guard")
end

-- "Chats oficiales": echa del canal de oficiales a quien no sea maestro u oficial
---------------------------------------------------------------------------
-- la guardia pregunta. Si falta la lista completa de alguna hermandad, en [+ARCHITECTURE.md]
---------------------------------------------------------------------------
HU.guardKnown = {}    -- [clave] = { tag, t }  confirmados como miembros por su hermandad
local queries = {}    -- [id] = { names = {clave=nombre}, wait = {tag=true}, t }
local asked = {}      -- [clave] = id de la última pregunta
local verdict = {}    -- [clave] = { intruder = true/false, t }
local QUERY_TTL = 180 -- segundos que se espera la respuesta a una pregunta

function HU:GuardKnown(name)
    local k = self:Key(name)
    local g = k and self.guardKnown[k]
    return g ~= nil and GetTime() - g.t < 3600
end

-- Pregunta por estos sospechosos a las hermandades cuya lista falta
function HU:GuardAsk(names, tags)
    local now = GetTime()
    -- solo van en la pregunta (y solo cuentan como preguntados) los nombres enteros que caben en [+ARCHITECTURE.md]
    local MAX_BODY = 200
    local list, set, size = {}, {}, 0
    -- primero quien lleva más tiempo sin aparecer en ninguna lista (los recién llegados de verdad
    -- aparecen enseguida; los intrusos se quedan)
    local order = {}
    for k in pairs(names) do order[#order + 1] = k end
    table.sort(order, function(a, b) return (self.pendingSince[a] or now) < (self.pendingSince[b] or now) end)
    for _, k in ipairs(order) do
        local n = names[k]
        local a = asked[k]
        if not (a and queries[a] and now - queries[a].t < QUERY_TTL) and not (verdict[k] and now - verdict[k].t < 300) then
            local short = self:Short(n)
            local add = #short + (#list > 0 and 1 or 0)
            if size + add <= MAX_BODY then
                list[#list + 1] = short; set[k] = n
                size = size + add
            end
        end
    end
    if #list == 0 then return end
    -- como mucho 3 preguntas en marcha, y una nueva cada 5 s
    local active, newest = 0, -999
    for _, q in pairs(queries) do
        active = active + 1
        if q.t > newest then newest = q.t end
    end
    if active >= 3 then return end
    local id = tostring(math.floor(now * 10) % 1000000) .. math.random(10, 99) .. active
    local q = { names = set, wait = {}, wit = {}, ans = {}, done = {}, left = 0, t = now }
    for _, tag in ipairs(tags) do
        local p = self:BestPeer(tag)
        if not p then return end -- sin contacto en alguna: no se puede saber, no se pregunta
        q.wait[tag] = p.name
        q.wit[tag] = self.GuardWitness and self:GuardWitness(tag, p.name) or nil
        q.left = q.left + 1
    end
    queries[id] = q
    for k in pairs(set) do asked[k] = id end
    local body = table.concat(list, ",")
    -- (con prioridad: detrás de cientos de saludos y listas tardaba minutos en salir y la pregunta
    -- caducaba antes de que llegara la respuesta)
    for _, name in pairs(q.wait) do self:Whisper(name, "MQ~" .. id .. "~" .. body, true) end
    for _, name in pairs(q.wit) do self:Whisper(name, "MQ~" .. id .. "~" .. body, true) end
    -- quien no conteste a tiempo: no se echa a nadie (se volverá a preguntar)
    HU.After(QUERY_TTL, function() queries[id] = nil end)
end

HU.comm.MQ = function(self, sender, f, dist)
    if dist ~= "WHISPER" or not self.myTag or not f[1] then return end
    -- sin la lista de mi hermandad cargada (acabo de entrar) no contesto: diría que nadie es mío
    -- y se darían por intrusos (sin respuesta, la pregunta caduca y no se marca a nadie)
    if not self.rosterList or #self.rosterList == 0 then return end
    local mine = {}
    for n in (f[2] or ""):gmatch("[^,]+") do
        local k = self:Key(n)
        if k and self.roster[k] then mine[#mine + 1] = n end
    end
    self:Whisper(sender, "MA~" .. f[1] .. "~" .. table.concat(mine, ","), true)
end

-- Seguridad (idea n.º 10 de Olympus): un TESTIGO. A cada hermandad se le pregunta a su mejor contacto [+ARCHITECTURE.md]
local WIT_WAIT = 20
function HU:GuardWitness(tag, mainName)
    local best, bestT
    local now = GetTime()
    for _, p in pairs(self.remote) do
        if p.tag == tag and p.name and not self:SameName(p.name, mainName) and now - (p.last or 0) < 900
            and self:MemberOf(p.name, tag) and (not bestT or p.last > bestT) then best, bestT = p.name, p.last end
    end
    return best
end

local function FinishTag(self, id, q, tag)
    if q.done[tag] then return end
    q.done[tag] = true
    q.left = q.left - 1
    local a = q.ans[tag] or {}
    local main, wit = a.main or {}, a.wit
    local now = GetTime()
    for k in pairs(main) do
        if q.names[k] then
            if not wit or wit[k] then
                self.guardKnown[k] = { tag = tag, t = now }
                verdict[k] = { intruder = false, t = now }
            elseif self.Debug then self:Debug("Guardia: el testigo de", tag, "no confirma a", k) end
            q.names[k] = nil
        end
    end
    -- (el testigo dice «es mío» y el primero no: tampoco se decide)
    if wit then for k in pairs(wit) do if q.names[k] and not main[k] then q.names[k] = nil end end end
    if q.left <= 0 then
        -- todas han contestado: los que nadie reclama son intrusos
        for k in pairs(q.names) do verdict[k] = { intruder = true, t = now } end
        queries[id] = nil
        HU.After(1, function() HU:GuardTick() end)
    end
end

HU.comm.MA = function(self, sender, f, dist)
    local id = f[1]
    local q = id and queries[id]
    if not q or dist ~= "WHISPER" then return end
    local tag, role
    for t, name in pairs(q.wait) do if self:SameName(name, sender) then tag, role = t, "main" end end
    if not tag then for t, name in pairs(q.wit or {}) do if self:SameName(name, sender) then tag, role = t, "wit" end end end
    if not tag then return end
    -- (contesta por X solo quien está en la lista buena de X: antes valía el «mejor contacto», que [+ARCHITECTURE.md]
    if not self:IsTest() and not self:MemberOf(sender, tag) then
        if self.Debug then self:Debug("Respuesta de la guardia no aceptada:", sender, tag) end
        return
    end
    local set = {}
    for n in (f[2] or ""):gmatch("[^,]+") do
        local k = self:Key(n)
        if k then set[k] = true end
    end
    q.ans[tag] = q.ans[tag] or {}
    q.ans[tag][role] = set
    if role == "main" then
        q.wait[tag] = nil
        if q.wit[tag] and not q.ans[tag].wit then
            HU.After(WIT_WAIT, function() if queries[id] == q then FinishTag(HU, id, q, tag) end end)
        else
            FinishTag(self, id, q, tag)
        end
    else
        q.wit[tag] = nil
        if q.ans[tag].main then FinishTag(self, id, q, tag) end
    end
end

function HU:GuardVerdict(name)
    local k = self:Key(name)
    local v = k and verdict[k]
    if v and GetTime() - v.t < 300 then return v.intruder end
    return nil
end

---------------------------------------------------------------------------
-- Comprobación periódica
---------------------------------------------------------------------------
-- Todos los conocidos de todas las hermandades en una sola tabla (lo mismo que mira InAnyGuild,
-- pero preparado una vez por revisión y no por cada persona del canal)
local function KnownSet(self)
    local set, now = {}, GetTime()
    for k in pairs(self.roster) do set[k] = true end
    for _, W in pairs(self.whitelist) do
        if W.set then for k in pairs(W.set) do set[k] = true end end
    end
    -- (los de una lista de arranque o débil no cuentan como conocidos: los ha puesto quien la manda,
    -- que puede ser un intruso con sus amigos. Quedan de sospechosos y se pregunta por ellos)
    for _, r in pairs(self.remoteRoster) do
        if r.byKey and not r.boot then
            for k, m in pairs(r.byKey) do if not (type(m) == "table" and m.weak) then set[k] = true end end
        end
    end
    for k, g in pairs(self.guardKnown) do
        if now - g.t < 3600 then set[k] = true end
    end
    for _, list in pairs(self.db.offline or {}) do
        for k in pairs(list) do set[k] = true end
    end
    return set
end
HU.GuardKnownSet = KnownSet -- (lo usa la revisión a petición: GuardKeeper.lua)

-- (desde la 5.4.8 el canal principal solo se revisa a petición y los vetados los echa un encargado:
-- GuardKeeper.lua. Aquí estaba la revisión periódica del canal entero; se quitó en la 58)
function HU:GuardTick(full)
    if self.GuardRedirect then return self:GuardRedirect(full) end
end

-- Agrupa ráfagas de eventos: una sola revisión por lote, no una por evento
local guardTickPending = false

function HU:ScheduleGuardTick(delay)
    if guardTickPending then return end
    guardTickPending = true
    HU.After(delay, function()
        guardTickPending = false
        HU:GuardTick()
    end)
end

-- Guardia por hermandad: alguien escribe en el canal con la etiqueta de MI hermandad y no está en [+ARCHITECTURE.md]
function HU:GuildVerified(k)
    local p = k and self.guildPeers[k]
    return p ~= nil and GetTime() - (p.last or 0) < self.PEER_TTL
end

-- ¿Sigue en el canal? (nil si no se puede saber) [+ARCHITECTURE.md]
local CHANNEL_HAS_STALE = 60
function HU:ChannelHas(name)
    local k = self:Key(name)
    if not k then return nil end
    local id = self:ChannelId("main")
    local c = membersCache.main
    if id and c and c.id == id and c.keys then
        local age = GetTime() - c.t
        if age < MEMBERS_TTL then return c.keys[k] == true end
        if age < CHANNEL_HAS_STALE then
            local b = building.main
            if not (b and b.id == id and GetTime() - b.started < 10) then self:GetChannelMembersAsync("main", function() end) end
            return c.keys[k] == true
        end
    end
    local members = self:GetChannelMembers("main")
    if not members then return nil end
    c = membersCache.main
    if c and c.keys then return c.keys[k] == true end
    for _, m in ipairs(members) do if m.name and m.name:lower() == k then return true end end
    return false
end

-- Alguien escribe con MI etiqueta y no está en mi lista ni ha hablado por la hermandad: un oficial le [+ARCHITECTURE.md]
local impAsk = {}
local impRate = { t = 0, n = 0 }
-- (otro oficial ya ha preguntado por él: mi pregunta pendiente se anula)
function HU:ImpostorAsked(k)
    local a = impAsk[k]
    if a then a.seen = true else impAsk[k] = { t = GetTime(), seen = true } end
end
function HU:CheckImpostor(author)
    local k = self:Key(author)
    if not k or not self.myTag then return end
    if self:GuildVerified(k) or self:InMyGuild(author) then return true end
    if not (self.CanPin and self:CanPin()) then return end
    local now = GetTime()
    local a = impAsk[k]
    if a and now - a.t < 300 then return end
    if now - impRate.t > 60 then impRate.t, impRate.n = now, 0 end
    if impRate.n >= 5 then return end
    impRate.n = impRate.n + 1
    impAsk[k] = { t = now }
    local function ask(try)
        if HU:GuildVerified(k) or HU:InMyGuild(author) or HU:IsMuted(author) then return end
        HU:Send("PG~" .. author, "GUILD", nil, true)
        HU.After(20, function()
            if HU:GuildVerified(k) or HU:InMyGuild(author) or HU:IsMuted(author) then return end
            if try < 2 then return ask(try + 1) end
            -- (se ha ido del canal: nada que hacer)
            if HU:ChannelHas(author) == false then return end
            HU:SetMute(author, 3600, L("Se hace pasar por <") .. HU.myTag .. ">")
            if HU:AmIModFast() then HU:KickPlayer(author, false, nil, true) end
            if HU.DropHeldChat then HU:DropHeldChat(k) end
        end)
    end
    -- (la espera al azar es para que, si hay varios oficiales, pregunte solo el primero: los demás
    -- ven su PG por la hermandad y no preguntan)
    HU.After(math.random() * 3, function() if not (impAsk[k] and impAsk[k].seen) then ask(1) end end)
end

---------------------------------------------------------------------------
-- Propietario del canal: siempre un maestro u oficial [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local lastOwnerCheck = -999
local modTried = {} -- [nombre] = cuándo se le intentó dar moderador (una vez cada 10 min)

function HU:IsOfficerName(name)
    local tag, idx = self:RankInfoOf(name)
    return idx ~= nil and self:RankRole(tag, idx) ~= nil, idx
end

local OWNER_STEP, OWNER_FIND_STEP = 100, 400
function HU:CheckChannelOwner(force)
    if self:IsTest() or not self.myTag then return end
    -- (sin la lista de mi hermandad no sé quién es oficial: se le quitaría el moderador a todos)
    if not self.rosterList or #self.rosterList == 0 then return end
    if not force and GetTime() - lastOwnerCheck < 60 then return end
    lastOwnerCheck = GetTime()
    local c = self.chan.main
    local id, num, info = self:ChannelRoster("main")
    if not (c and c.name and id and num > 0) then return end
    -- (por trozos de OWNER_STEP: con miles de personas, de golpe pasaba de 5 ms. Primero me busco a
    -- mí, que es barato; casi nadie es propietario, y solo él recorre el canal entero)
    local me = self:MeKey()
    if not me then return end
    local meSpace = me:gsub("%-", " ", 1)
    local st = { best = nil, bestScore = -1, toUnmod = {}, toMod = {}, now = GetTime(), i = 1 }
    local function Step()
        if self.chan.main ~= c then return end
        local last = math.min(num, st.i + OWNER_STEP - 1)
        for i = st.i, last do
            local name, owner, mod = info(id, i)
            if name and not owner then
                local full = self:FullName(name) or name
                if full:lower() ~= me then
                    local isOff, idx = self:IsOfficerName(full)
                    if isOff then
                        local score = (idx == 0 and 3 or 1) + (mod and 1 or 0)
                        if score > st.bestScore then st.best, st.bestScore = name, score end
                        if not mod and #st.toMod < 5 and st.now - (modTried[full:lower()] or -999) > 600 then st.toMod[#st.toMod + 1] = name end
                    elseif mod and #st.toUnmod < 10 then
                        st.toUnmod[#st.toUnmod + 1] = name
                    end
                end
            end
        end
        st.i = last + 1
        if st.i <= num then HU.After(0, Step) return end
        self:OwnerApply(c, st.best, st.toMod, st.toUnmod, st.now)
    end
    local f = 1
    local function Find()
        if self.chan.main ~= c then return end
        local last = math.min(num, f + OWNER_FIND_STEP - 1)
        for i = f, last do
            local name, owner = info(id, i)
            if name then
                local k = name:lower()
                if k == me or k == meSpace then
                    if owner then HU.After(0, Step) end
                    return
                end
            end
        end
        f = last + 1
        if f <= num then HU.After(0, Find) end
    end
    Find()
end

function HU:OwnerApply(c, best, toMod, toUnmod, now)
    if not self:CanPin() then
        local setOwner = SetChannelOwner or (C_ChatInfo and C_ChatInfo.SetChannelOwner)
        if best and setOwner then
            pcall(setOwner, c.name, self:Short(best))
            self:Print(L("Eras propietario del canal sin ser oficial: se lo has pasado a ") .. self:Short(best) .. ".")
        end
        return
    end
    -- (moderan el canal los maestros y oficiales de las hermandades: decisión de Jorge, 06/11; un
    -- moderador puede echar a cualquiera, así que solo ellos)
    local setMod = ChannelModerator or (C_ChatInfo and C_ChatInfo.ChannelModerator)
    if setMod then
        for _, n in ipairs(toMod) do
            modTried[(self:FullName(n) or n):lower()] = now
            pcall(setMod, c.name, self:Short(n))
        end
    end
    local unMod = ChannelUnmoderator or (C_ChatInfo and C_ChatInfo.ChannelUnmoderator)
    if unMod then for _, n in ipairs(toUnmod) do pcall(unMod, c.name, self:Short(n)) end end
end

function HU:OnSomeoneJoined(author)
    local name = author and self:FullName(author)
    -- (entra un maestro u oficial: si el canal lo tiene alguien que no lo es, que se lo pase ya)
    if name and GetTime() - lastOwnerCheck > 10 and self:IsOfficerName(name) then
        HU.After(3, function() HU:CheckChannelOwner(true) end)
    end
    self:ScheduleGuardTick(5)
end

function HU:OnSomeoneLeft(author)
    local name = author and self:FullName(author)
    if not name then return end
    self.pendingSince[name:lower()] = nil
end

function HU:OnChannelRolesChanged()
    -- (puede que ahora sea moderador, o que haya dejado de serlo)
    self:ForgetChannelMembers()
    self:ScheduleGuardTick(2)
    -- (puede que el juego me haya hecho propietario)
    HU.After(2 + math.random() * 3, function() HU:CheckChannelOwner(true) end)
end

HU:OnStart(function()
    HU.NewTicker(15, function() HU:GuardTick() end)
    -- (con retraso al azar, para no coincidir con los demás relojes en el mismo fotograma)
    HU.After(math.random() * 60, function() HU.NewTicker(60, function() HU:CheckChannelOwner() end) end)
end)

---------------------------------------------------------------------------
-- Estado (para /gu estado y el panel)
---------------------------------------------------------------------------
-- "Mi Hermandad <PRU>, Hermandad Demo <DEMO>" con su color
function HU:AllowedGuildsText()
    local out = {}
    for _, g in ipairs(self.cfg and self.cfg.guilds or {}) do
        out[#out + 1] = "|cff" .. self:GuildColorHex(g.tag) .. g.name .. "|r <" .. g.tag .. ">"
    end
    return table.concat(out, ", ")
end

-- compact = true (el recuadro Estado del panel): con muchas hermandades, un resumen en vez de
-- una línea por hermandad (el detalle sale con /gu estado)
function HU:StatusLines(compact)
    local Lines = {}
    if not IsInGuild() then
        Lines[#Lines + 1] = L("No estás en una hermandad.")
        return Lines
    end
    if not self.cfg then
        Lines[#Lines + 1] = L("No hay configuración en la Información de hermandad. Escribe /gu config.")
        return Lines
    end
    if self.cfg.missingChannel and not self.cfg.chanFromNote and #self.cfg.errors == 1 then
        Lines[#Lines + 1] = L("Esperando el canal: lo pasa un oficial conectado (está en la nota de oficial del maestro).")
        return Lines
    end
    if not self.cfg.ok then
        Lines[#Lines + 1] = L("|cffff4444Configuración con errores:|r ") .. table.concat(self.cfg.errors, "; ")
        return Lines
    end
    Lines[#Lines + 1] = L("Tu hermandad: ") .. (self.guildName or "?") .. " <" .. (self.myTag or "?") .. ">"
    local many = compact and #self.cfg.guilds > 6
    if many then
        Lines[#Lines + 1] = L("Hermandades permitidas: ") .. #self.cfg.guilds .. L(" (lista en Opciones > Hermandades)")
    else
        Lines[#Lines + 1] = L("Hermandades permitidas (") .. #self.cfg.guilds .. "): " .. self:AllowedGuildsText()
    end
    local n = self.db.netChan
    if self.cfg.chanFromNote and n then
        Lines[#Lines + 1] = L("Contraseña: de la nota de oficial (") .. self:Short(n.by or "?") .. ", " .. HU.SafeDate("%d/%m %H:%M", n.t) .. ")"
    end
    if self.cfg.chanInInfo then
        Lines[#Lines + 1] = L("|cffff8800Aviso: la línea GU:c está en la Información de hermandad y la puede leer cualquiera. Pásala a la nota de oficial del maestro.|r")
    end
    local id = self:ChannelId("main")
    Lines[#Lines + 1] = L("Canal: ") .. self.cfg.channel .. (id and (" (/" .. id .. ")") or "") .. " - " .. (id and "|cff44ff44conectado|r" or L("|cffff4444sin conectar|r"))
    if self.offCfg then
        local oid = self:ChannelId("off")
        Lines[#Lines + 1] = L("Oficiales: ") .. self.offCfg.channel .. (oid and (" (/" .. oid .. ")") or "") .. " - " .. (oid and "|cff44ff44conectado|r" or L("|cffff4444sin conectar|r"))
    elseif self:CanOfficer() then
        Lines[#Lines + 1] = L("Oficiales: sin configurar (nota de oficial GU:o:Canal:clave)")
    end
    local gp = 0
    for _ in pairs(self.guildPeers) do gp = gp + 1 end
    Lines[#Lines + 1] = L("Con el addon en tu hermandad: ") .. (gp + 1) .. L(".  Enlace de tu hermandad: ") .. self:Short(self:RelayName() or "?")
    Lines[#Lines + 1] = self:QueueText()
    if self:IsChatLockedDown() then
        -- (lo de abajo —contactos, «sin confirmar»— puede salir en naranja por esto, no por un fallo)
        Lines[#Lines + 1] = "|cffff8800" .. L("El juego tiene bloqueado el chat ahora (combate en una instancia o un campo de batalla): el addon no puede enviar ni leer. Se reanuda solo al acabar.") .. "|r"
    end
    local old = self.OldVersions and self.OldVersions() or {}
    if #old > 0 then
        Lines[#Lines + 1] = "|cffff8800" .. L("Versiones viejas en tu hermandad: ") .. "|r" .. table.concat(old, ", ", 1, math.min(#old, 8)) .. (#old > 8 and "..." or "")
    end
    if many then
        local others, contact, online, full = self:OtherTags(), {}, {}, {}
        local noContact, noOnline, noFull = {}, {}, {}
        for _, tag in ipairs(others) do
            if self:BestPeer(tag) then contact[#contact + 1] = tag else noContact[#noContact + 1] = tag end
            if self.remoteRoster[tag] then online[#online + 1] = tag else noOnline[#noOnline + 1] = tag end
            if self:ListFresh(tag) then full[#full + 1] = tag else noFull[#noFull + 1] = tag end
        end
        local function missing(list)
            if #list == 0 then return "" end
            return "  |cffff8800(" .. L("faltan: ") .. table.concat(list, ", ", 1, math.min(#list, 6)) .. (#list > 6 and "..." or "") .. ")|r"
        end
        Lines[#Lines + 1] = L("Otras hermandades: ") .. #others .. L(".  Con contacto: ") .. #contact .. missing(noContact)
        Lines[#Lines + 1] = L("  Lista de conectados: ") .. #online .. missing(noOnline)
        Lines[#Lines + 1] = L("  Lista completa: ") .. #full .. missing(noFull) .. L("   (detalle: /gu estado)")
    end
    for _, tag in ipairs(many and {} or self:OtherTags()) do
        local p = self:BestPeer(tag)
        -- (la lista que de verdad se reparte: los conectados de esa hermandad; en la fase de [+ARCHITECTURE.md]
        local r = self.remoteRoster[tag]
        local listText
        if not r or not r.members then
            listText = L("|cffff8800sin lista|r")
        else
            local gm, off = 0, 0
            for _, m in ipairs(r.members) do
                local role = self:RankRole(tag, m.rankIndex)
                if role == "gm" then gm = gm + 1 elseif role == "officer" then off = off + 1 end
            end
            -- (al día = su enlace ha confirmado hace poco que mi copia es la suya; si no hay cambios
            -- no llega nada nuevo, así que la hora del último cambio no dice si está bien)
            local fresh = math.floor(GetTime() - math.max(r.updated or 0, r.confirmedT or 0))
            local freshText = fresh < 90 and (L("hace ") .. fresh .. " s") or (L("hace ") .. math.floor(fresh / 60) .. " min")
            local state = fresh <= 720 and (L("al día ") .. freshText) or ("|cffff8800" .. L("sin confirmar desde ") .. freshText .. "|r")
            listText = L("maestro ") .. gm .. L(" y oficiales ") .. off .. L(" conectados (") .. state .. ")"
        end
        Lines[#Lines + 1] = "  <" .. tag .. L("> contacto: ") .. (p and self:Short(p.name) or L("|cffff8800ninguno todavía|r")) .. "  - " .. listText
    end
    local num, owner, mods = self:ChannelSummary()
    if num then
        Lines[#Lines + 1] = L("En el canal: ") .. num .. L(".  Propietario: ") .. (owner or "|cffff8800ninguno|r")
            .. ((#mods > 0) and (L("  Moderadores: ") .. table.concat(mods, ", ")) or "")
    end
    Lines[#Lines + 1] = L("Guardia: ") .. (self.guardStatus or "?")
    return Lines
end
