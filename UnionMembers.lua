-- Guild Union - Miembros de la unión: todos los conectados de otra hermandad, solo para verlos [+ARCHITECTURE.md]
--   MP~miEtiq~suEtiq             pide la lista (por GUILD, a quien se encarga de esa hermandad; por
--                                susurro, a alguien de esa hermandad)
--   ML~etiq~id~parte~partes~datos  un trozo de la lista («nombre,clase,nivel,rango,zona[,a]», como RB)
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
    st.fetch, st.failed = nil, GetTime()
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
    self:Whisper(target, "MP~" .. self.myTag .. "~" .. tag, true)
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
local function Busy(st, now)
    return st.fetch ~= nil or (st.cur ~= nil and now - st.cur.t < WAIT)
        or (st.guildAskT ~= nil and now - st.guildAskT < GUILD_WAIT and (st.t or 0) < st.guildAskT)
end

-- La ventana la está enseñando: se pide si no la tengo reciente (las esperas van aquí dentro).
-- Sin etiqueta (todas): de una en una y cada una como mucho cada ALL_FRESH, para no pedir las 19
-- hermandades a la vez
function HU:WantUnionMembers(tag)
    if tag == nil then
        local now = GetTime()
        for _, t in ipairs(self:OtherTags()) do
            local st = self.unionMembers[t]
            if st and Busy(st, now) then return self:WantUnionMembers(t) end
        end
        for _, t in ipairs(self:OtherTags()) do
            local st = self.unionMembers[t]
            if not st or not ((st.members and now - st.t < ALL_FRESH) or (st.failed and now - st.failed < FRESH)) then
                return self:WantUnionMembers(t)
            end
        end
        return
    end
    if not self.myTag or not Known(self, tag) then return end
    local st, now = State(tag), GetTime()
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
local function SendList(self, target)
    local now = GetTime()
    for i = #sentT, 1, -1 do if now - sentT[i] > 60 then table.remove(sentT, i) end end
    local k = target:lower()
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
    SendList(self, sender)
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

---------------------------------------------------------------------------
-- Para la ventana
---------------------------------------------------------------------------
-- Las filas: de una hermandad o de todas, por hermandad, rango y nombre
function HU:UnionMemberEntries(tag)
    local out, now = {}, GetTime()
    for _, t in ipairs(tag and { tag } or self:OtherTags()) do
        local st = self.unionMembers[t]
        if st and st.members and now - st.t > KEEP then st.members, st.t, st.id, st.parts = nil, nil, nil, nil end
        local list = st and (st.members or (st.cur and Decode(self, t, st.cur.parts, st.cur.n)))
        for _, m in ipairs(list or {}) do
            out[#out + 1] = { name = m.name, tag = t, class = m.class, level = m.level, zone = m.zone, afk = m.afk,
                ri = m.rankIndex or 99, rank = m.rankIndex and self:RankName(t, m.rankIndex) or "", online = true }
        end
    end
    table.sort(out, function(a, b)
        if a.tag ~= b.tag then return a.tag < b.tag end
        if a.ri ~= b.ri then return a.ri < b.ri end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- Cómo va la lista de esa hermandad, en pocas palabras
function HU:UnionMembersStatus(tag)
    local st = self.unionMembers[tag]
    if not st then return "" end
    local now = GetTime()
    if st.cur then return string.format(L("llegando %d/%d"), st.cur.got, st.cur.n) end
    if st.members then return string.format(L("hace %d s"), math.floor(now - st.t)) end
    if st.failed then return L("no contesta (¿versión antigua?)") end
    if st.fetch or st.guildAskT then return L("pidiendo…") end
    return ""
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
