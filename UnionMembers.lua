-- Guild Union - Miembros de la unión: todos los conectados de otra hermandad, solo para verlos [+ARCHITECTURE.md]
--   MP~miEtiq~suEtiq[~o]         pide la lista (por GUILD, a quien se encarga de esa hermandad; por
--                                susurro, a alguien de esa hermandad). Con «o», también los desconectados
--   ML~etiq~id~parte~partes~datos  un trozo de la lista («nombre,clase,nivel,rango,zona[,a]», como RB)
--   MO~etiq~id~parte~partes~datos  un trozo de los desconectados («nombre,clase,nivel,rango,horas»)
local _, HU = ...
local L = HU.L

local FRESH = 60        -- una copia de menos de esto no se vuelve a pedir
local WAIT = 20         -- una lista que estaba llegando y lleva esto parada, ya no llega
local ASK_WAIT = 10     -- quien no ha empezado a contestar en esto, no la tiene: se pregunta a otro
local TRIES = 8         -- a cuántos de esa hermandad se pregunta antes de darla por perdida
local GUILD_WAIT = 40   -- si mi hermandad no la trae en este tiempo, la pido yo mismo
local ALL_FRESH = 300   -- viendo todas las hermandades, cada una se refresca como mucho cada tanto
local KEEP = 600        -- una copia de más de esto ya no se enseña
local ANSWER_GAP = 60   -- a cada uno, como mucho una lista por minuto
local ANSWER_MAX = 3    -- y como mucho tantas listas por minuto en total
local RESHARE_GAP = 30  -- la copia que ya tengo, a mi hermandad como mucho cada tanto
local CHUNK = 190       -- bytes de datos por trozo (el mensaje entero no pasa de 255)
local OFF_MAX = 300     -- desconectados que se mandan como mucho (los que se conectaron hace menos)
local OFF_WAIT = 15     -- llegada la de conectados, los desconectados empiezan antes de esto (si no, no los tiene)

HU.unionMembers = {}    -- [etiqueta] = estado de su lista (ver State)
HU.unionAnswered = {}   -- [nombre en minúsculas] = true: ya me ha contestado una vez (tiene Miembros)

local function State(tag)
    local st = HU.unionMembers[tag]
    if not st then
        -- members/t: la última lista entera y cuándo llegó; cur: la que está llegando;
        -- fetch: a quién se la he pedido; guildAskT: cuándo se la pedí a mi hermandad; failed: cuándo
        -- dejó de contestar
        st = {}
        HU.unionMembers[tag] = st
    end
    return st
end

-- Los desconectados de esa hermandad, aparte (MO): members/t/id: la última lista entera; cur: la que
-- está llegando; askT/from: cuándo y a quién se la pedí; doneT: cuándo llegó la de conectados que la
-- acompañaba; failed: quien contestó no los tiene (una versión de antes)
local function Off(st)
    local o = st.off
    if not o then o = {}; st.off = o end
    return o
end

local function Known(self, tag)
    return tag and tag ~= "" and tag ~= self.myTag and self.cfg ~= nil and self.cfg.byTag[tag] ~= nil
end

---------------------------------------------------------------------------
-- Trozos: cada uno se entiende solo (los códigos de zona, «#1=Orgrimmar», van en el mismo trozo)
---------------------------------------------------------------------------
function HU.PackMembers(entries, max)
    max = max or CHUNK
    local chunks, cur, codes, n, size = {}, {}, {}, 0, 0
    local function flush()
        if #cur > 0 then chunks[#chunks + 1] = table.concat(cur, ";") end
        cur, codes, n, size = {}, {}, 0, 0
    end
    for _, en in ipairs(entries) do
        local head, rest = en:match("^([^,]*,%d*,%d*,%d*),?(.*)$")
        if head then
            local zone, flags = rest, ""
            local z, fl = rest:match("^(.-),(%a*)$")
            if z then zone, flags = z, "," .. fl end
            local function Line()
                local code = zone ~= "" and codes[zone] or nil
                local def
                if zone ~= "" and not code then code = "#" .. (n + 1); def = code .. "=" .. zone end
                local line = head .. "," .. (code or "") .. flags
                return line, def, code, #line + 1 + (def and #def + 1 or 0)
            end
            local line, def, code, cost = Line()
            if size + cost > max and #cur > 0 then
                flush()
                line, def, code, cost = Line()
            end
            if def then n = n + 1; codes[zone] = code; cur[#cur + 1] = def end
            cur[#cur + 1] = line
            size = size + cost
        end
    end
    flush()
    if #chunks == 0 then chunks[1] = "" end
    return chunks
end

local function Decode(self, tag, parts, n)
    local out = {}
    for i = 1, n do
        local part = parts[i]
        if part then
            local dict = HU.ZoneDict({ part }, 1)
            for en in part:gmatch("[^;]+") do
                local m = HU.ParseRosterEntry(self, en, tag, dict)
                if m then out[#out + 1] = m end
            end
        end
    end
    return out
end

-- Los desconectados de mi hermandad, una línea cada uno («nombre,clase,nivel,rango,horas», las horas en
-- base 36 y vacías si el juego no lo dice), primero los que se conectaron hace menos; como mucho OFF_MAX
function HU:OfflineEntries()
    local now, list = GetTime(), {}
    for _, e in ipairs(self.rosterList or {}) do
        if e.online == false and e.name then
            local secs = e.offSecs and (e.offSecs + math.max(0, now - (e.offAt or now))) or nil
            list[#list + 1] = { e = e, secs = secs }
        end
    end
    table.sort(list, function(a, b)
        if (a.secs ~= nil) ~= (b.secs ~= nil) then return a.secs ~= nil end
        return (a.secs or 0) < (b.secs or 0)
    end)
    local out = {}
    for i = 1, math.min(#list, OFF_MAX) do
        local e, secs = list[i].e, list[i].secs
        out[i] = table.concat({ (self:Short(e.name):gsub("[~,;|]", "")), HU.CLASS_INDEX[e.class or ""] or 0,
            e.level or 0, e.rankIndex or "", secs and HU.B36(math.floor(secs / 3600)) or "" }, ",")
    end
    return out
end

-- Líneas en trozos de como mucho max bytes, separadas por «;»
function HU.PackLines(lines, max)
    max = max or CHUNK
    local chunks, cur, size = {}, {}, 0
    for _, line in ipairs(lines) do
        if size + #line + 1 > max and #cur > 0 then
            chunks[#chunks + 1] = table.concat(cur, ";")
            cur, size = {}, 0
        end
        cur[#cur + 1] = line
        size = size + #line + 1
    end
    if #cur > 0 then chunks[#chunks + 1] = table.concat(cur, ";") end
    if #chunks == 0 then chunks[1] = "" end
    return chunks
end

local function DecodeOff(self, tag, parts, n)
    local out = {}
    for i = 1, n do
        for en in (parts[i] or ""):gmatch("[^;]+") do
            local name, cls, lvl, rank, hours = en:match("^([^,]*),(%d*),(%d*),(%d*),(%w*)$")
            if HU.SafeName(name) then
                out[#out + 1] = { name = self:FullName(name), class = HU.CLASSES[tonumber(cls) or 0],
                    level = tonumber(lvl) or 0, rankIndex = tonumber(rank), online = false, tag = tag,
                    offHours = hours ~= "" and tonumber(hours, 36) or nil }
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Pedirla
---------------------------------------------------------------------------
-- A quién de esa hermandad: su enlace, sus ayudantes, sus mejores contactos y los de su lista pequeña.
-- Primero quien ya me ha contestado alguna vez; luego aquellos de los que no sé la versión; al final
-- los contactos con la versión sabida. (El número de versión no dice si alguien tiene Miembros: una
-- copia de prueba puede decir el mismo número que la publicada, o uno más viejo. Visto el 22/11: los
-- contactos de WLP3 con la 5.4.43 iban siempre delante y su maestro, que la tenía, nunca se preguntaba)
local function Candidates(self, tag)
    local seen, list = {}, {}
    local function add(name)
        local k = name and name:lower()
        if k and not seen[k] then
            seen[k] = true
            local p = self.remote[k]
            local rank = HU.unionAnswered[k] and 0 or ((p and p.ver) and 2 or 1)
            list[#list + 1] = { name = name, rank = rank, r = math.random() }
        end
    end
    local rp = self:KnownRelay(tag)
    if rp then add(rp.name) end
    local h = self.helpers[tag]
    if h and GetTime() - h.t < 900 then for _, n in ipairs(h.list) do add(self:FullName(n)) end end
    for _, p in ipairs(self:BestPeers(tag, 3)) do add(p.name) end
    -- (y los de la lista pequeña que ya tengo de esa hermandad: su maestro, sus oficiales, su enlace y
    -- sus ayudantes, todos conectados. Quien se encarga en mi hermandad no siempre habla con ellos)
    local r = self.remoteRoster[tag]
    for _, m in ipairs(r and r.members or {}) do if m.online ~= false then add(m.name) end end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.r < b.r
    end)
    return list
end

local function GiveUp(self, st)
    st.fetch, st.failed, st.wantOff = nil, GetTime(), nil
    self:Changed("unionMembers")
end

-- La pido yo a alguien de esa hermandad (si no empieza a contestar en ASK_WAIT, a otro; como mucho
-- TRIES, y si ya está llegando se espera a que llegue)
local function Fetch(self, tag)
    local st, now = State(tag), GetTime()
    local fx = st.fetch
    if fx and now - fx.t < (fx.started and WAIT or ASK_WAIT) then return end
    if not fx then fx = { tries = 0, tried = {} }; st.fetch = fx end
    if fx.tries >= TRIES then return GiveUp(self, st) end
    local target
    for _, c in ipairs(Candidates(self, tag)) do
        if not fx.tried[c.name:lower()] then target = c.name break end
    end
    if not target then return GiveUp(self, st) end
    fx.tried[target:lower()] = true
    fx.tries, fx.t, fx.target = fx.tries + 1, now, target:lower()
    -- (con los desconectados: se esperan de este mismo)
    if st.wantOff then
        local o = Off(st)
        o.askT, o.from, o.doneT = now, target:lower(), nil
    end
    self:Whisper(target, "MP~" .. self.myTag .. "~" .. tag .. (st.wantOff and "~o" or ""), true)
    self:Changed("unionMembers")
end

-- La copia que tengo, otra vez a mi hermandad (quien se encarga, cuando otro la pide y ya la tiene)
local function Reshare(self, tag)
    local st, now = State(tag), GetTime()
    if not st.parts or (st.reshareT and now - st.reshareT < RESHARE_GAP) then return end
    if not self:IsGuildForwarder(self:Me()) then return end
    st.reshareT = now
    for i = 1, st.n do
        self:Send(table.concat({ "ML", tag, st.id, i, st.n, st.parts[i] or "" }, "~"), "GUILD")
    end
end

-- ¿Está en camino? (pedida a alguien, llegando, o pedida a mi hermandad y aún esperando)
local function Busy(st, now, off)
    local o = off and st.off
    return st.fetch ~= nil or (st.cur ~= nil and now - st.cur.t < WAIT)
        or (st.guildAskT ~= nil and now - st.guildAskT < GUILD_WAIT and (st.t or 0) < st.guildAskT)
        or (o and ((o.cur ~= nil and now - o.cur.t < WAIT) or o.doneT ~= nil)) or false
end

-- ¿Hay que pedir los desconectados? (no, si están llegando, si los tengo de hace menos de fresh o si
-- quien contestó no los tiene). Llegada la de conectados, si en OFF_WAIT no empiezan, no los tiene
local function NeedOff(st, now, fresh)
    if st.failed and now - st.failed < FRESH then return false end
    local o = Off(st)
    if o.cur and now - o.cur.t < WAIT then return false end
    if o.members and now - o.t < fresh then return false end
    if o.failed and now - o.failed < FRESH then return false end
    if o.doneT then
        if now - o.doneT < OFF_WAIT then return false end
        o.doneT, o.failed = nil, now
        HU:Changed("unionMembers")
        return false
    end
    return true
end

-- La ventana la está enseñando: se pide si no la tengo reciente (las esperas van aquí dentro).
-- Sin etiqueta (todas): de una en una y cada una como mucho cada ALL_FRESH, para no pedir las 19
-- hermandades a la vez. off: también los desconectados (se piden siempre a alguien de esa hermandad:
-- solo los quiere quien mira, no toda mi hermandad)
function HU:WantUnionMembers(tag, off)
    if tag == nil then
        local now = GetTime()
        for _, t in ipairs(self:OtherTags()) do
            local st = self.unionMembers[t]
            if st and Busy(st, now, off) then return self:WantUnionMembers(t, off) end
        end
        for _, t in ipairs(self:OtherTags()) do
            local st = self.unionMembers[t]
            if not st or not ((st.members and now - st.t < ALL_FRESH) or (st.failed and now - st.failed < FRESH))
                or (off and Known(self, t) and NeedOff(st, now, ALL_FRESH)) then
                return self:WantUnionMembers(t, off)
            end
        end
        return
    end
    if not self.myTag or not Known(self, tag) then return end
    local st, now = State(tag), GetTime()
    if off and NeedOff(st, now, FRESH) then
        if st.fetch then return Fetch(self, tag) end
        if st.cur and now - st.cur.t < WAIT then return end
        st.wantOff = true
        return Fetch(self, tag)
    end
    if st.members and now - st.t < FRESH then return end
    if st.cur and now - st.cur.t < WAIT then return end
    if st.fetch then return Fetch(self, tag) end
    if st.failed and now - st.failed < FRESH then return end
    -- (si me toca a mí, o no hay enlace en mi hermandad que la pueda traer, la pido yo)
    if self:ResponsibleFor(tag) or not self:KnownGuildRelay() then return Fetch(self, tag) end
    if not st.guildAskT or now - st.guildAskT > FRESH then
        st.guildAskT = now
        self:Send("MP~" .. self.myTag .. "~" .. tag, "GUILD")
        self:Changed("unionMembers")
    elseif now - st.guildAskT >= GUILD_WAIT and (st.t or 0) < st.guildAskT then
        -- (mi hermandad no la ha traído: quizá su enlace tiene una versión de antes)
        Fetch(self, tag)
    end
end

---------------------------------------------------------------------------
-- Contestar
---------------------------------------------------------------------------
local answered, sentT = {}, {}
-- off: también los desconectados (MO, detrás de la de conectados). Pedirla con y sin ellos cuenta aparte
-- en el tope de cada uno (quien la tenía sin ellos y marca la casilla no espera un minuto)
local function SendList(self, target, off)
    local now = GetTime()
    for i = #sentT, 1, -1 do if now - sentT[i] > 60 then table.remove(sentT, i) end end
    local k = target:lower() .. (off and "+o" or "")
    if answered[k] and now - answered[k] < ANSWER_GAP then return false end
    if #sentT >= ANSWER_MAX or self:MainQueueSize() > 30 then return false end
    answered[k] = now
    sentT[#sentT + 1] = now
    local chunks = HU.PackMembers(self:OnlineEntries(), CHUNK)
    local id = HU.B36(math.floor(GetServerTime and GetServerTime() or time()))
    self:MarkPinged(target)
    for i, c in ipairs(chunks) do
        self:Send(table.concat({ "ML", self.myTag, id, i, #chunks, c }, "~"), "WHISPER", target)
    end
    if off then
        local offChunks = HU.PackLines(self:OfflineEntries(), CHUNK)
        for i, c in ipairs(offChunks) do
            self:Send(table.concat({ "MO", self.myTag, id, i, #offChunks, c }, "~"), "WHISPER", target)
        end
    end
    return true
end

-- (abierta: lo que vale lo mira el manejador. Por GUILD, un compañero la quiere; por susurro, la pide
-- alguien de otra hermandad de la comunidad, nunca un desconocido: la lista lleva la zona de cada uno)
HU:RegisterMessage("MP", { open = true, combat = "req" })
HU.comm.MP = function(self, sender, f, dist)
    local from, want = f[1], f[2]
    if not self.myTag then return end
    if dist == "GUILD" then
        if from ~= self.myTag or not Known(self, want) or not self:ResponsibleFor(want) then return end
        local st = State(want)
        if st.members and GetTime() - st.t < FRESH then return Reshare(self, want) end
        return Fetch(self, want)
    end
    if dist ~= "WHISPER" or want ~= self.myTag or not Known(self, from) then return end
    if not (self:InAnyGuild(sender) or self:Vouched(sender)) then return end
    SendList(self, sender, f[3] == "o")
end

---------------------------------------------------------------------------
-- Recibir
---------------------------------------------------------------------------
local function Store(self, st, tag, id, i, n, data)
    if st.id == id then return end -- (esa ya la tengo entera)
    local cur = st.cur
    if not cur or cur.id ~= id then cur = { id = id, n = n, parts = {}, got = 0 }; st.cur = cur end
    cur.t = GetTime()
    if cur.n ~= n or cur.parts[i] then return end
    cur.parts[i] = data
    cur.got = cur.got + 1
    if cur.got >= cur.n then
        st.members, st.t, st.id, st.parts, st.n = Decode(self, tag, cur.parts, cur.n), GetTime(), id, cur.parts, cur.n
        st.cur, st.fetch, st.failed = nil, nil, nil
        -- (pedida con los desconectados: si no empiezan a llegar en OFF_WAIT, no los tiene)
        if st.wantOff then
            local o = Off(st)
            if not o.cur then o.doneT = GetTime() end
            st.wantOff = nil
        end
    end
    self:Changed("unionMembers")
end

-- (por GUILD, solo de quien reparte por mi hermandad (remoteData); por susurro, solo de a quien se la
-- pedí y de la hermandad que pedí)
HU:RegisterMessage("ML", { tagField = 1, remoteData = true, open = true, queue = "bmid", ttl = 120, combat = "data" })
HU.comm.ML = function(self, sender, f, dist, raw)
    local tag, id, i, n = f[1], f[2], tonumber(f[3]), tonumber(f[4])
    if not Known(self, tag) or not id or id == "" or not (i and n and i >= 1 and i <= n and n <= 200) then return end
    local st = State(tag)
    if dist == "WHISPER" then
        local fx = st.fetch
        if not (fx and fx.target == sender:lower()) then return end
        fx.t, fx.started = GetTime(), true
        -- (tiene Miembros: la próxima vez se le pregunta el primero)
        HU.unionAnswered[sender:lower()] = true
        if self:IsGuildForwarder(self:Me()) then self:Send(raw, "GUILD") end
    elseif dist ~= "GUILD" then
        return
    end
    Store(self, st, tag, id, i, n, f[5] or "")
end

-- Los desconectados: solo por susurro, de a quien se los pedí y hace poco (no se reparten por GUILD:
-- solo los quiere quien mira)
HU:RegisterMessage("MO", { tagField = 1, open = true, queue = "bmid", ttl = 120, combat = "data" })
HU.comm.MO = function(self, sender, f, dist)
    local tag, id, i, n = f[1], f[2], tonumber(f[3]), tonumber(f[4])
    if dist ~= "WHISPER" or not Known(self, tag) or not id or id == "" then return end
    if not (i and n and i >= 1 and i <= n and n <= 200) then return end
    local st = State(tag)
    local o, now = Off(st), GetTime()
    if not (o.from == sender:lower() and o.askT and now - o.askT < 120) then return end
    if o.id == id then return end -- (esa ya la tengo entera)
    local cur = o.cur
    if not cur or cur.id ~= id then cur = { id = id, n = n, parts = {}, got = 0 }; o.cur = cur end
    cur.t, o.doneT = now, nil
    if cur.n ~= n or cur.parts[i] then return end
    cur.parts[i] = f[5] or ""
    cur.got = cur.got + 1
    if cur.got >= cur.n then
        o.members, o.t, o.id = DecodeOff(self, tag, cur.parts, cur.n), now, id
        o.cur, o.failed = nil, nil
    end
    self:Changed("unionMembers")
end

---------------------------------------------------------------------------
-- Con /who: los conectados de una hermandad aunque nadie de ella tenga Miembros [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local WHO_WAIT = 15     -- la respuesta del /who que pedí llega antes de esto; luego ya no es mía
local WHO_GAP = 5       -- entre un /who y el siguiente (el servidor no deja más seguidos)
local WHO_FRESH = 60    -- un /who de menos de esto no se repite solo
local whoAsk            -- { tag, guild, t }: el /who que he pedido y espero
local lastWhoT = -1e9

-- Mientras espero la respuesta de MI /who, las ventanas del juego que escuchan WHO_LIST_UPDATE (la
-- de búsqueda) no la oyen: así no se abren. Vuelven a escuchar en cuanto llega, o a los WHO_WAIT si no
-- llega; un /who escrito a mano sigue abriéndolas como siempre
local muted, muteN = nil, 0
local function Unmute()
    if not muted then return end
    for _, f in ipairs(muted) do pcall(f.RegisterEvent, f, "WHO_LIST_UPDATE") end
    muted = nil
end
local function Mute()
    if muted or not GetFramesRegisteredForEvent then return end
    local ok, frames = pcall(function() return { GetFramesRegisteredForEvent("WHO_LIST_UPDATE") } end)
    if not ok then return end
    muted = {}
    for _, f in ipairs(frames) do
        if f ~= HU.eventFrame and type(f) == "table" and f.UnregisterEvent and pcall(f.UnregisterEvent, f, "WHO_LIST_UPDATE") then
            muted[#muted + 1] = f
        end
    end
    -- (por si no llega: solo deshace ESTE silencio, no el de un /who posterior)
    muteN = muteN + 1
    local mine = muteN
    HU.After(WHO_WAIT, function() if muteN == mine then Unmute() end end)
end

-- Solo desde un clic: el juego no deja a un addon hacer /who por su cuenta (probado en Forever el
-- 23/11: desde un temporizador no hace nada). Devuelve si se ha pedido
function HU:WhoUnionMembers(tag)
    local FL = C_FriendList
    if not Known(self, tag) or not (FL and FL.SendWho) then return false end
    local now = GetTime()
    if now - lastWhoT < WHO_GAP or (whoAsk and now - whoAsk.t < WHO_WAIT) then return false end
    local guild = self:GuildName(tag)
    -- (que la respuesta avise con WHO_LIST_UPDATE y no salga en el chat, también si son pocos)
    if FL.SetWhoToUi then pcall(FL.SetWhoToUi, true) end
    whoAsk = { tag = tag, guild = guild, t = now }
    Mute()
    if not pcall(FL.SendWho, 'g-"' .. guild .. '"') then whoAsk = nil; Unmute() return false end
    lastWhoT = now
    State(tag).whoAskT = now
    self:Changed("unionMembers")
    return true
end

-- Un clic en la pestaña (el juego solo deja hacer /who desde un clic): si alguna hermandad de las que
-- se miran no tiene lista (ni la de Miembros ni un /who reciente), se busca una con /who
function HU:UnionWhoTick(tag)
    local now = GetTime()
    for _, t in ipairs(tag and { tag } or self:OtherTags()) do
        local st = self.unionMembers[t]
        local has = st and (st.members or st.cur)
        local fresh = st and st.who and now - st.who.t < WHO_FRESH
        if Known(self, t) and not has and not fresh then return self:WhoUnionMembers(t) end
    end
    return false
end

local function Plain(v)
    if type(v) ~= "string" or HU.Secret(v) then return nil end
    return (v:gsub("[|%c]", ""))
end

-- Una fila del /who como tabla (C_FriendList.GetWhoInfo; o la GetWhoInfo de antes, que devuelve
-- nombre, hermandad, nivel, raza, clase, zona y clase en inglés)
local function WhoInfo(i)
    local FL = C_FriendList
    if FL and FL.GetWhoInfo then
        local ok, info = pcall(FL.GetWhoInfo, i)
        return ok and type(info) == "table" and info or nil
    end
    if not GetWhoInfo then return nil end
    local ok, name, guild, level, _, _, zone, file = pcall(GetWhoInfo, i)
    if not ok then return nil end
    return { fullName = name, fullGuildName = guild, level = level, area = zone, filename = file }
end
local function WhoCount()
    local FL = C_FriendList
    local fn = (FL and FL.GetNumWhoResults) or GetNumWhoResults
    if not fn then return nil end
    local ok, n, total = pcall(fn)
    if not ok then return nil end
    return n, total
end

HU:On("WHO_LIST_UPDATE", function()
    local ask = whoAsk
    if not ask or GetTime() - ask.t > WHO_WAIT then return end
    whoAsk = nil
    -- (en el fotograma siguiente: si vuelven a escuchar mientras se reparte este mismo aviso, aún lo oyen)
    HU.After(0, Unmute)
    local n, total = WhoCount()
    if type(n) ~= "number" or HU.Secret(n) then return end
    local list, want = {}, ask.guild:lower()
    for i = 1, n do
        local info = WhoInfo(i)
        local name = info and Plain(info.fullName)
        local guild = name and Plain(info.fullGuildName)
        -- (solo los de esa hermandad: el /who puede traer a alguien de otra con un nombre parecido)
        if name and name ~= "" and guild and guild:lower() == want then
            local level = info.level
            list[#list + 1] = { name = HU:FullName(name) or name, class = Plain(info.filename),
                level = (type(level) == "number" and not HU.Secret(level)) and level or 0,
                zone = Plain(info.area), tag = ask.tag, online = true }
        end
    end
    local st = State(ask.tag)
    total = (type(total) == "number" and not HU.Secret(total)) and total or n
    st.who, st.whoAskT = { members = list, t = GetTime(), shown = n, total = total }, nil
    HU:Changed("unionMembers")
end)

---------------------------------------------------------------------------
-- Para la ventana
---------------------------------------------------------------------------
-- Las filas: de una hermandad o de todas, por hermandad, rango y nombre. off: también los desconectados
-- que hayan llegado (offSecs: cuánto llevan desconectados, contando desde que llegó la lista)
function HU:UnionMemberEntries(tag, off)
    local out, now = {}, GetTime()
    for _, t in ipairs(tag and { tag } or self:OtherTags()) do
        local st = self.unionMembers[t]
        if st and st.members and now - st.t > KEEP then st.members, st.t, st.id, st.parts = nil, nil, nil, nil end
        if st and st.who and now - st.who.t > KEEP then st.who = nil end
        if st and st.off and st.off.members and now - st.off.t > KEEP then st.off.members, st.off.t, st.off.id = nil, nil, nil end
        -- (la de Miembros, si la hay, que trae los rangos; si no, la del /who)
        local list = st and (st.members or (st.cur and Decode(self, t, st.cur.parts, st.cur.n)) or (st.who and st.who.members))
        local seen = {}
        for _, m in ipairs(list or {}) do
            seen[m.name:lower()] = true
            out[#out + 1] = { name = m.name, tag = t, class = m.class, level = m.level, zone = m.zone, afk = m.afk,
                ri = m.rankIndex or 99, rank = m.rankIndex and self:RankName(t, m.rankIndex) or "", online = true }
        end
        local o = off and st and st.off
        -- (quien se ha conectado después de llegar la lista sale una vez, conectado)
        for _, m in ipairs(o and o.members or {}) do
            if not seen[m.name:lower()] then
                out[#out + 1] = { name = m.name, tag = t, class = m.class, level = m.level, ri = m.rankIndex or 99,
                    rank = m.rankIndex and self:RankName(t, m.rankIndex) or "", online = false,
                    offSecs = m.offHours and (m.offHours * 3600 + math.floor(now - o.t)) or nil }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.tag ~= b.tag then return a.tag < b.tag end
        if a.ri ~= b.ri then return a.ri < b.ri end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- «Unión» en la lista de miembros del juego (UnionRoster.lua): los conectados de mi hermandad (de la
-- lista del juego, con su rango) y los de las otras, todos juntos; primero la mía, luego por hermandad,
-- rango y nombre. off: también los desconectados de las otras (los de la mía los pone UnionRoster.lua)
function HU:UnionRosterEntries(off)
    local out = {}
    for _, e in ipairs(self.rosterList or {}) do
        if e.online and e.name then
            out[#out + 1] = { name = e.name, tag = self.myTag, class = e.class, level = e.level, zone = e.zone,
                afk = e.afk, ri = e.rankIndex or 99, rank = e.rank or "", online = true, own = true }
        end
    end
    for _, e in ipairs(self:UnionMemberEntries(nil, off)) do out[#out + 1] = e end
    table.sort(out, function(a, b)
        if (a.own or false) ~= (b.own or false) then return a.own == true end
        if a.tag ~= b.tag then return tostring(a.tag) < tostring(b.tag) end
        if a.ri ~= b.ri then return a.ri < b.ri end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- Cómo van los desconectados de esa hermandad (detrás de cómo va la lista)
local function OffStatus(st)
    local o = st.off
    if not o then return "" end
    if o.cur then return string.format(L(", desconectados %d/%d"), o.cur.got, o.cur.n) end
    if o.members then return string.format(L(", %d desconectados"), #o.members) end
    if o.failed then return L(", sin desconectados (versión de antes)") end
    return ""
end

-- Cómo va la lista de esa hermandad, en pocas palabras
local function OnlineStatus(self, tag)
    local st = self.unionMembers[tag]
    if not st then return "" end
    local now = GetTime()
    if st.cur then return string.format(L("llegando %d/%d"), st.cur.got, st.cur.n) end
    if st.members then return string.format(L("hace %d s"), math.floor(now - st.t)) end
    if st.whoAskT and now - st.whoAskT < WHO_WAIT then return L("buscando con /who…") end
    if st.who then
        local s = string.format(L("con /who, hace %d s"), math.floor(now - st.who.t))
        -- (el juego da como mucho unos cuantos por búsqueda: si hay más, se dice)
        if st.who.total > st.who.shown then s = s .. string.format(L(" (%d de %d)"), st.who.shown, st.who.total) end
        return s
    end
    if st.failed then return L("no contesta: un clic en la lista lo busca con /who") end
    if st.fetch or st.guildAskT then return L("pidiendo…") end
    return ""
end

-- (off: y la de sus desconectados)
function HU:UnionMembersStatus(tag, off)
    local s = OnlineStatus(self, tag)
    local st = off and self.unionMembers[tag]
    if st and s ~= "" then s = s .. OffStatus(st) end
    return s
end

-- (quien se encarga y nadie mira: sigue preguntando a otro si el primero no contesta)
HU:OnStart(function()
    HU:Every(5, "miembros-union", function()
        for tag, st in pairs(HU.unionMembers) do
            if st.fetch then Fetch(HU, tag) end
        end
    end)
end)

HU:Module("UnionMembers", { "Config", "Core", "Domain/Trust", "Lists", "Net/Relay", "Net/RosterSync", "Net/Security", "Net/Transport", "Protocol", "Ranks" })
