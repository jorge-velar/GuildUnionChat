-- Guild Union - El enlace y sus ayudantes: puntuación, saludos, presentaciones, carriles y ciclos (antes en Comm.lua)
local _, HU = ...
local L = HU.L
local perf = HU.netPerf          -- (Comm.lua)
local VOUCH_TTL = HU.VOUCH_TTL   -- (Domain/Trust.lua)

---------------------------------------------------------------------------
-- Contactos
---------------------------------------------------------------------------
local function Bit(v) return v and "1" or "0" end

---------------------------------------------------------------------------
-- Quién es el enlace: primero los oficiales y el maestro (si su conexión va bien), y entre [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local function SamplePerf()
    local lat, fps = 0, 0
    if GetNetStats then
        local _, _, home, world = GetNetStats()
        lat = math.max(tonumber(home) or 0, tonumber(world) or 0)
    end
    if GetFramerate then fps = tonumber(GetFramerate()) or 0 end
    -- (media que cambia poco a poco: un tirón de lag no cambia el enlace)
    if lat > 0 then perf.lat = perf.lat and (perf.lat * 0.8 + lat * 0.2) or lat end
    if fps > 0 then perf.fps = perf.fps and (perf.fps * 0.8 + fps * 0.2) or fps end
    -- saltos del ping: cuánto cambia de una medida a la siguiente
    if lat > 0 then
        if perf.lastLat then
            local d = math.abs(lat - perf.lastLat)
            perf.jit = perf.jit and (perf.jit * 0.8 + d * 0.2) or d
        end
        perf.lastLat = lat
    end
end

-- Entradas al juego de este personaje (no cuentan los /reload): varias en la última hora = se le cae la conexión
local LOGIN_WINDOW = 3600
local function RecentRelogs()
    local c = HU.cdb
    local list = c and type(c.logins) == "table" and c.logins
    if not list then return 0 end
    local now, n = time(), 0
    for i = 1, #list do if now - list[i] <= LOGIN_WINDOW then n = n + 1 end end
    return math.max(0, n - 1)
end

HU:On("PLAYER_ENTERING_WORLD", function(isInitialLogin)
    local c = HU.cdb
    if not (c and isInitialLogin) then return end
    local now, keep = time(), {}
    for _, t in ipairs(type(c.logins) == "table" and c.logins or {}) do
        if now - t <= LOGIN_WINDOW then keep[#keep + 1] = t end
    end
    keep[#keep + 1] = now
    c.logins, c.sessionStart = keep, now
end)

-- segundos conectado desde que entró al juego (un /reload no lo pone a cero)
local function Uptime()
    local st = HU.cdb and HU.cdb.sessionStart
    if st then return time() - st end
    return HU.loginT and GetTime() - HU.loginT or 0
end

-- Prueba de velocidad: cuánto tarda este ordenador en hacer un trabajo como el del addon
-- (trocear y juntar textos). Se repite cada 10 minutos y se queda la media.
local function Bench()
    if not debugprofilestop then return end
    local t0 = debugprofilestop()
    local parts = {}
    for i = 1, 300 do parts[i] = "Jugador" .. i .. ",3,60,4,#2" end
    local joined = table.concat(parts, ";")
    local n = 0
    for _ in joined:gmatch("[^;]+") do n = n + 1 end
    local ms = (debugprofilestop() - t0) * 10 -- (equivale a la prueba de antes, de 3.000)
    if type(ms) == "number" and ms >= 0 then perf.bench = perf.bench and (perf.bench * 0.7 + ms * 0.3) or ms end
end
HU.Bench = Bench

-- Ocupado: en una banda, un campo de batalla o una arena (resta 150), o ausente (AFK) desde hace [+ARCHITECTURE.md]
local AFK_AFTER, AFK_PENALTY, BUSY_PENALTY = 180, 40, 150
local afkSince
local function Busy()
    if IsInInstance then
        local inInst, kind = IsInInstance()
        if inInst and (kind == "raid" or kind == "pvp" or kind == "arena") then return true, BUSY_PENALTY end
    end
    if UnitIsAFK and HU.SafeBool(UnitIsAFK("player"), false) then
        afkSince = afkSince or GetTime()
        if GetTime() - afkSince >= AFK_AFTER then return true, AFK_PENALTY end
    else
        afkSince = nil
    end
    return false, 0
end
HU.RelayBusy = Busy
HU.SamplePerf = SamplePerf

function HU:RelayScore()
    local lat, fps, bench, rtt = perf.lat, perf.fps, perf.bench, perf.rtt
    local good = (not lat or lat < 500) and (not fps or fps >= 12)
    local s = 0
    -- (oficial por rango, que es lo que los demás pueden comprobar en su lista: con «ver notas de
    -- oficial» cada uno se daba los 100 y nadie podía verificarlo, ver SaneScore)
    local idx = self.MyRankIndex and self:MyRankIndex()
    local officer = idx ~= nil and self:RankRole(self.myTag, idx) ~= nil
    if officer and good then s = s + 100 end
    -- conexión: ping del juego y lo que tardan en volverme mis propios mensajes
    -- (sin escalones: cada 5 ms menos de ping, 1 punto más; 0 ms = 30, 150 ms o más = 0)
    if lat then s = s + math.max(0, math.floor(30 - lat / 5)) end
    if rtt then s = s + (rtt < 0.4 and 6 or rtt < 1 and 3 or 0) end
    -- ordenador: fotogramas por segundo y la prueba de velocidad
    if fps then s = s + (fps >= 50 and 3 or fps >= 25 and 2 or fps >= 12 and 1 or 0) end
    if bench then s = s + (bench < 4 and 6 or bench < 10 and 4 or bench < 25 and 2 or 0) end
    -- estable: ping que no salta, lleva un rato conectado y no se le cae la conexión
    local jit = perf.jit
    if jit then s = s + (jit < 5 and 6 or jit < 15 and 4 or jit < 40 and 2 or 0) end
    local up = Uptime()
    s = s + (up > 3600 and 6 or up > 1800 and 4 or up > 600 and 2 or 0)
    s = s - math.min(30, 10 * RecentRelogs())
    -- en banda, campo de batalla o ausente: mejor que lo haga otro
    local busy, penalty = Busy()
    if busy then s = s - penalty end
    -- en zona de descanso (ciudad, posada) se sale del juego al momento y no da tiempo a pasar el puesto: [+ARCHITECTURE.md]
    if IsResting and HU.SafeBool(IsResting(), false) then
        self.restSince = self.restSince or GetTime()
        if GetTime() - self.restSince >= 60 then s = s - 20 end
    else
        self.restSince = nil
    end
    -- (copia 119, transición) En las versiones anteriores solo el enlace sube de carril, y lo hace por la
    -- falsa alarma de recién entrado. Para que eso no pase mientras haya alguien actualizado conectado,
    -- un oficial con esta versión dice una puntuación por encima de la más alta que puede tener un
    -- oficial con una versión vieja (157, más 15 si ya es el enlace = 172) y dentro del tope que todos
    -- aceptan de un oficial (199, SaneScore). Entre actualizados sigue ganando el de mejor conexión.
    -- Ocupado (banda, campo de batalla, ausente) no: mejor que lo sea otro. Se quitará cuando todos
    -- estén actualizados.
    if officer and good and not busy then
        s = math.max(173, math.min(199, 173 + math.floor((s - 100) * 26 / 57)))
    elseif good and not busy then
        -- (copia 120: quien no es oficial también: entre 80 y 99. Las versiones viejas no le aceptan
        -- más de 99 a quien no sale como oficial en la lista, y un no oficial con versión vieja llega
        -- como mucho a 57 + 15 = 72. A un oficial con versión vieja no le gana: eso no se puede desde aquí)
        s = math.max(80, math.min(99, 80 + math.floor(s * 19 / 57)))
    end
    return s
end

-- La puntuación que dice un compañero, dentro de lo posible: como mucho 199, y los 100 de oficial [+ARCHITECTURE.md]
-- (sin oficial se puede llegar a 57: el tope de 99 no corta a nadie y sigue por debajo de los 100 de oficial)
function HU:SaneScore(name, s)
    s = tonumber(s) or 0
    if s ~= s then return 0 end
    s = math.max(-150, math.min(199, s))
    if s > 99 then
        local e = self.roster[self:Key(name) or ""]
        if not (e and self:RankRole(self.myTag, e.rankIndex)) then s = 99 end
    end
    return s
end

-- ¿a va antes que b para ser enlace?
local function Better(sa, ka, sb, kb)
    if sa ~= sb then return sa > sb end
    return ka < kb
end
HU.RelayBetter = Better

-- Ayudantes del enlace: unos pocos compañeros con el addon que también reciben (y reparten
-- en la hermandad) los datos de las otras hermandades, para que no recaiga todo en uno
local HELPER_MARGIN = 10 -- (ventaja de quien ya es ayudante: no se cambia por poca diferencia)
-- (se recuerda 2 s, salvo que alguien de mi hermandad entre o salga: lo piden el saludo y el reparto de
-- trabajo, y recorrer a cientos de compañeros cada vez llegaba a 2,6 ms)
local helpersMemo = { t = -99 }
function HU:MyHelpers()
    local now = GetTime()
    local m = helpersMemo
    if now - m.t < 2 and m.v == self.rosterVersion and m.a == self.advertisedHelpers and m.n == #self:OtherTags() then
        local out = {}
        for i, n in ipairs(m.out) do out[i] = n end
        return out
    end
    local out = self:MyHelpersCalc()
    helpersMemo = { t = now, v = self.rosterVersion, a = self.advertisedHelpers, n = #self:OtherTags(), out = out }
    local copy = {}
    for i, n in ipairs(out) do copy[i] = n end
    return copy
end
function HU:MyHelpersCalc()
    local me, now, list, keys = self:MeKey(), GetTime(), {}, {}
    for k, p in pairs(self.guildPeers) do
        local r = self.roster[k]
        if k ~= me and now - p.last < self.PEER_TTL and (not r or r.online) then list[#list + 1] = p; keys[#list] = k end
    end
    -- más ayudantes cuantas más hermandades haya (de 4 a 8)
    -- (hasta 10, para repartir 19 hermandades)
    local want = math.max(4, math.min(10, math.ceil(#self:OtherTags() / 2)))
    -- (los ayudantes, en el mismo orden que el enlace: los mejores primero; se buscan los mejores [+ARCHITECTURE.md]
    local current = {}
    for _, n in ipairs(self.advertisedHelpers or {}) do
        current[n:lower()] = true
        local fk = self:Key(n)
        if fk then current[fk] = true end
    end
    local top = {}
    for i, p in ipairs(list) do
        local k = keys[i] -- (la clave de guildPeers, ya en minúsculas: antes se rehacía con lower() para cada uno)
        local s = (p.score or 0) + (current[k] and HELPER_MARGIN or 0)
        local pos = #top + 1
        while pos > 1 and Better(s, k, top[pos - 1].s, top[pos - 1].k) do pos = pos - 1 end
        if pos <= want then
            table.insert(top, pos, { p = p, s = s, k = k })
            if #top > want then top[#top] = nil end
        end
    end
    local out = {}
    for i, t in ipairs(top) do out[i] = self:Short(t.p.name) end
    return out
end

-- Acabo de pasar a ser el enlace: me quedo con los ayudantes del anterior, y con él si sigue [+ARCHITECTURE.md]
function HU:InheritHelpers()
    local h = self.relayHelpers
    if not h or GetTime() - h.t > 700 then return end
    local me = self:Short(self:Me() or ""):lower()
    local out, seen = {}, {}
    local function add(n)
        local s = type(n) == "string" and self:Short(n) or nil
        if not s or s == "" or #out >= 10 then return end
        local k = s:lower()
        if k == me or seen[k] then return end
        local e = self.roster[self:Key(s) or ""]
        if e and not e.online then return end
        seen[k] = true
        out[#out + 1] = s
    end
    add(h.relay)
    for _, n in ipairs(h.list or {}) do add(n) end
    if #out == 0 then return end
    self.advertisedHelpers = out
    self.helpersChangedT = GetTime()
end

-- Quién manda la lista de conectados a cada hermandad: el enlace y sus ayudantes se reparten
-- las otras hermandades (con muchas hermandades, uno solo no daría abasto)
function HU:RosterSlot()
    if self:IsRelay() then return 0, #(self.advertisedHelpers or {}) end
    local h = self.relayHelpers
    if not h or GetTime() - h.t > 700 then return nil end
    local me = self:Short(self:Me() or ""):lower()
    for i, n in ipairs(h.list) do if n:lower() == me then return i, #h.list end end
    return nil
end
function HU:HandlesTag(tag)
    local slot, n = self:RosterSlot()
    if not slot then return false end
    local tags = self:OtherTags()
    table.sort(tags)
    for j, t in ipairs(tags) do
        if t == tag then return ((j - 1) % (n + 1)) == slot end
    end
    return false
end

function HU:HelloText(cmd)
    -- mi puntuación para ser enlace (la que ven los demás; yo uso la misma)
    if cmd ~= "HR" then self.myAdvScore = self:RelayScore() end
    local relay = self:IsRelay()
    if relay and self.wasRelay == false and HU.ForgetRosterState then HU.ForgetRosterState() end
    -- (acabo de ser enlace: solo conozco a quien ha saludado desde que entré, y los demás no vuelven
    -- a saludar hasta dentro de 2-5 min. Se les pregunta, para elegir ya a todos los ayudantes)
    if relay and not self.wasRelay and cmd ~= "HR" and HU.AskGuildHello then HU:AskGuildHello() end
    self.wasRelay = relay
    local helpers = relay and self:MyHelpers() or nil
    if relay then
        -- (los ayudantes no se cambian más de una vez cada 2 minutos mientras los de ahora sigan [+ARCHITECTURE.md]
        local cur = self.advertisedHelpers
        if cur and #cur > 0 and self.helpersChangedT and GetTime() - self.helpersChangedT < 120 then
            local allOn = true
            for _, n in ipairs(cur) do
                local k = self:Key(n) or ""
                local p, r = self.guildPeers[k], self.roster[k]
                -- (el que se ha desconectado sale ya: antes seguía de ayudante hasta 2 min y nadie
                -- mandaba los cambios de las hermandades que le tocaban)
                if not p or GetTime() - p.last > self.PEER_TTL or (r and not r.online) then allOn = false break end
            end
            -- (rellenar un hueco sí: si los de ahora siguen todos y solo se añade alguien, no se espera)
            local onlyAdds = #helpers > #cur
            if onlyAdds then
                local inNew = {}
                for _, n in ipairs(helpers) do inNew[n:lower()] = true end
                for _, n in ipairs(cur) do if not inNew[n:lower()] then onlyAdds = false break end end
            end
            if allOn and not onlyAdds then helpers = cur end
        end
        local changed = table.concat(self.advertisedHelpers or {}, ",") ~= table.concat(helpers, ",")
        if changed then self.helpersChangedT = GetTime() end
        self.advertisedHelpers = helpers
        if changed and self.PresenceSchedule then HU.After(0, function() HU:PresenceSchedule() end) end
        -- (y a mi hermandad enseguida, no en el saludo de dentro de 2-5 minutos: los ayudantes van en [+ARCHITECTURE.md]
        if changed and cmd ~= "HR" then self:HelpersChangedHello() end
    end
    local text = HU.Utf8Cut(table.concat({ cmd or "HI", self.version, self.myTag or "", Bit(self:AmIModFast()), Bit(relay),
        relay and HU.Utf8Cut(table.concat(helpers, ","), 180) or "", self.myAdvScore or 0,
        self.ChannelLane and self:ChannelLane() or 0 }, "~"), 250)
    -- (campos 8 y 9: generación y hora del carril de la comunidad; enteros o nada)
    local st = self.LaneState and self:LaneState()
    if st then
        local extra = "~" .. st.gen .. "~" .. math.floor(st.t)
        local _, seps = text:gsub("~", "")
        if seps == 7 and #text + #extra <= 250 then text = text .. extra end
    end
    -- (campo 10, al final: la versión mínima compatible; las versiones viejas no lo leen)
    local minv = HU.MIN_VERSION
    if minv then
        local _, seps = text:gsub("~", "")
        local tail = (seps == 9 and "~" or seps == 7 and "~~~" or nil)
        if tail and #text + #tail + #minv <= 250 then text = text .. tail .. minv end
    end
    return text
end

-- Contacto de otra hermandad que dice ser su enlace, sin estar comprobado: el que me toca para esa [+ARCHITECTURE.md]
HU.LaneContact = function(sender, tag)
    local p = sender and HU.remote[sender:lower()]
    tag = tag or (p and p.tag)
    if not (p and tag and p.tag == tag and HU:MemberOf(sender, tag)) then return false end
    local bp = HU:BestPeer(tag)
    return bp ~= nil and bp.name:lower() == sender:lower()
end
-- ¿Puedo fiarme de lo que dice sender sobre el carril? (el enlace o un oficial)
local function LaneStrong(sender, dist, tag)
    local officer = HU.IsOfficerName and HU:IsOfficerName(sender) or false
    -- (copia 118) Cada uno sigue solo a los de SU hermandad: su enlace o un oficial suyo, por GUILD.
    -- A los de otra hermandad (su enlace o un oficial, por susurro) solo les hace caso MI enlace, que
    -- luego se lo dice a los míos. Antes cualquier oficial de la comunidad movía a cualquiera.
    if dist == "GUILD" then return officer or HU:Key(HU:RelayName() or "") == HU:Key(sender) end
    if not HU:IsRelay() then return false end
    if officer then return true end
    local p = tag and HU:KnownRelay(tag)
    return p and p.name and p.name:lower() == sender:lower() or false
end

-- El enlace nuevo pide a la hermandad que salude (HY); cada uno contesta una vez, repartidos en
-- unos segundos, con un saludo de respuesta (HR) que no provoca más saludos
local askHelloAt = -999
function HU:AskGuildHello()
    if GetTime() - askHelloAt < 300 then return end
    askHelloAt = GetTime()
    HU.After(1, function() if HU.myTag and HU:IsRelay() then HU:Send("HY", "GUILD") end end)
    -- (las respuestas llegan en 1-12 s: entonces se vuelven a elegir los ayudantes con todos)
    HU.After(15, function() if HU.myTag and HU:IsRelay() then HU:HelpersChangedHello() end end)
end
local answeredHQ = -999
-- (HY y no HQ: HQ es la petición del historial al entrar, en Social.lua)
HU:RegisterMessage("HY", { ttl = 60, latestWins = true, skipLocked = true })
HU.comm.HY = function(self, sender, f, dist)
    if dist ~= "GUILD" or not self.myTag or self:Key(sender) == self:MeKey() then return end
    if GetTime() - answeredHQ < 60 then return end
    answeredHQ = GetTime()
    HU.After(1 + math.random() * 11, function()
        if HU.myTag and IsInGuild() then HU:Send(HU:HelloText("HR"), "GUILD") end
    end)
end

-- El primero de su hermandad en entrar no espera los 30 s de prudencia para ser enlace: pregunta [+ARCHITECTURE.md]
local guildHeardT -- última vez que oí un mensaje del addon de otro de mi hermandad (por GUILD)
HU:On("CHAT_MSG_ADDON", function(prefix, _, dist, sender)
    if dist ~= "GUILD" or type(prefix) ~= "string" or prefix:sub(1, 4) ~= "HU20" then return end
    local s, me = HU:FullName(sender), HU:MeKey()
    if s and me and s:lower() ~= me then guildHeardT = GetTime() end
end)
local rqAnswerT, rqFrom, rqFromN = -999, {}, 0
HU:RegisterMessage("RQ")
HU.comm.RQ = function(self, sender, f, dist)
    if dist ~= "GUILD" or not self.myTag or self:Key(sender) == self:MeKey() then return end
    local k, now = sender:lower(), GetTime()
    -- (de cada uno, como mucho uno cada 60 s; y el enlace contesta como mucho uno cada 5 s)
    if rqFrom[k] and now - rqFrom[k] < 60 then return end
    if not rqFrom[k] then rqFromN = rqFromN + 1 end
    rqFrom[k] = now
    if rqFromN > 200 then
        for key, t in pairs(rqFrom) do if now - t >= 60 then rqFrom[key] = nil; rqFromN = rqFromN - 1 end end
    end
    if not self:IsRelay() or now - rqAnswerT < 5 then return end
    rqAnswerT = now
    self:Send(self:HelloText("HI"), "GUILD", nil, true)
end
local rqSentT
function HU:AskGuildRelay()
    if rqSentT or guildHeardT or not self.myTag or not IsInGuild() then return end
    rqSentT = GetTime()
    self:Send("RQ", "GUILD", nil, true)
end
function HU:AloneAskRosters()
    if not self.aloneRelay or not self.myTag then return end
    for _, tag in ipairs(self:OtherTags()) do
        local p = not self.remoteRoster[tag] and self:BestPeer(tag)
        if p then self:Whisper(p.name, "RF~" .. self.myTag .. "~1", true) end
    end
end
-- ¿Estoy solo? Se decide al entrar en el canal, al menos 4 s después de preguntar
function HU:AloneCheck(tries)
    tries = tries or 0
    if guildHeardT or self.aloneRelay or tries > 20 then return end
    if not rqSentT then self:AskGuildRelay() end
    local ready = rqSentT and GetTime() - rqSentT >= 4 and self:IsJoined("main")
    if not ready then HU.After(1, function() HU:AloneCheck(tries + 1) end) return end
    self.aloneRelay = true
    self:Debug("Solo de mi hermandad con el addon: soy el enlace sin esperar")
    -- (a los 12 y 25 s pido la lista a quien conozco de cada hermandad que me falte: la que me mandan [+ARCHITECTURE.md]
    for _, d in ipairs({ 12, 25 }) do HU.After(d, function() HU:AloneAskRosters() end) end
    -- (1,1 s: quién es el enlace se recuerda 1 s, MassLogin.lua)
    HU.After(1.1, function() if not guildHeardT or HU:IsRelay() then HU:SafeCall("hello", HU.HelloCycle, HU) end end)
end

local helpersHelloAt, helpersHelloDue = -999, false
-- soon = true: se ha ido el enlace o un ayudante, sin esperar (Presence.lua)
function HU:HelpersChangedHello(soon)
    if helpersHelloDue then return end
    helpersHelloDue = true
    HU.After(soon and 0.3 or math.max(2, helpersHelloAt + 15 - GetTime()), function()
        helpersHelloDue = false
        if not HU.myTag or not IsInGuild() or not HU:IsRelay() then return end
        helpersHelloAt = GetTime()
        HU:Send(HU:HelloText("HI"), "GUILD")
    end)
end

-- Datos grandes para otra hermandad (listas de conectados, fichas, desconectados): los
-- trozos se reparten entre su contacto y sus ayudantes (cada uno los pasa a su hermandad)
HU.helpers = {}
local rrHelper = {}
local fastOff = {} -- [etiqueta] = { t, off = oficial elegido, R = la copia con la que se eligió }
function HU:BulkWhisper(target, msg, fast)
    local p = self.remote[target:lower()]
    local tag = p and p.tag
    local h = tag and self.helpers[tag]
    -- (cambio pequeño: a dos de esa hermandad, por las dos vías, que tienen cupo aparte (1 mensaje por [+ARCHITECTURE.md]
    if fast then
        local R = tag and self.remoteRoster[tag]
        local off
        -- (el oficial elegido se recuerda 5 s por hermandad: buscarlo recorría a todos sus contactos en cada
        -- trozo de cada cambio, y era lo que más pesaba en el envío (hasta 3,4 ms en el enlace))
        local now, c = GetTime(), fastOff[tag]
        if c and now - c.t < 5 and c.R == R and (not c.off or (R and R.byKey and R.byKey[c.off:lower()])) then
            off = c.off
        elseif R and R.byKey then
            local bestT
            for _, key in ipairs(self:RemoteKeys(tag)) do
                local q, m = self.remote[key], R.byKey[key]
                if q and m and q.tag == tag and now - (q.last or 0) < 900 and self:RankRole(tag, m.rankIndex or m.rankHidden)
                    and (not bestT or q.last > bestT) then off, bestT = q.name, q.last end
            end
            fastOff[tag] = { t = now, off = off, R = R }
        end
        local ok = self:Whisper(off or target, msg, nil, nil, true)
        if off and off:lower() ~= target:lower() then self:Whisper(target, msg) end
        return ok
    end
    if not h or GetTime() - h.t > 900 or #h.list == 0 then return self:Whisper(target, msg, nil, nil, fast) end
    local pool = { target }
    -- (solo ayudantes que sigan conectados según la lista de su hermandad, si la tengo)
    local R = self.remoteRoster[tag]
    for _, n in ipairs(h.list) do
        local full = self:FullName(n)
        local online = not (R and R.byKey) or R.byKey[full and full:lower() or ""] ~= nil
        if full and online and full:lower() ~= target:lower() then pool[#pool + 1] = full end
    end
    -- (todos los trozos de un mismo envío, al mismo: si cada trozo iba a un ayudante distinto, cada uno [+ARCHITECTURE.md]
    local g = HU.sendGroup
    if g and g.to then return self:Whisper(g.to, msg, nil, nil, fast) end
    rrHelper[tag] = ((rrHelper[tag] or 0) % #pool) + 1
    if g then g.to = pool[rrHelper[tag]] end
    return self:Whisper(pool[rrHelper[tag]], msg, nil, nil, fast)
end


-- Soy el "enlace" de mi hermandad si mi nombre es el primero (alfabéticamente) [+ARCHITECTURE.md]
HU.PEER_TTL = 700

-- (el que ya es enlace tiene 15 puntos de ventaja: no se cambia por poca diferencia)
local RELAY_MARGIN = 15
local function EffScore(score, isRelay) return (score or 0) + (isRelay and RELAY_MARGIN or 0) end

-- (IsRelay y RelayName recorren a todos los compañeros con el addon y se llaman cientos de veces:
-- el resultado se guarda durante el fotograma, y se olvida si cambia mi puntuación o llega un saludo)
local relayMemo = { t = -1 }
function HU.ForgetRelayMemo() relayMemo.t = -1 end
local function RelayCalc(self)
    local now = GetTime()
    if relayMemo.t == now and relayMemo.s == self.myAdvScore and relayMemo.w == self.wasRelay and relayMemo.np == self.guildPeers then
        return relayMemo.best, relayMemo.name
    end
    local me = self:MeKey()
    local best, bestS, bestName = me, EffScore(self.myAdvScore, self.wasRelay), self:Me()
    for k, p in pairs(self.guildPeers) do
        local r = self.roster[k]
        local ps = EffScore(p.score, p.relay)
        if now - p.last < HU.PEER_TTL and (not r or r.online) and Better(ps, k, bestS, best) then best, bestS, bestName = k, ps, p.name end
    end
    relayMemo.t, relayMemo.s, relayMemo.w, relayMemo.np, relayMemo.best, relayMemo.name = now, self.myAdvScore, self.wasRelay, self.guildPeers, best, bestName
    return best, bestName
end
function HU:IsRelay()
    local me = self:MeKey()
    if not me then return false end
    -- (recién entrado no se es enlace: aún no se ha oído a nadie y cada uno se creía el enlace [+ARCHITECTURE.md]
    if self.loginT and GetTime() - self.loginT < 30 and not self.aloneRelay then return false end
    return (RelayCalc(self)) == me
end

-- ¿Sé ya quién es el enlace de mi hermandad (yo o alguien que lo ha dicho hace poco)?
function HU:KnownGuildRelay()
    if self:IsRelay() then return true end
    local now = GetTime()
    for _, p in pairs(self.guildPeers) do
        if p.relay and now - p.last < HU.PEER_TTL then return true end
    end
    return false
end

function HU:RelayName()
    local _, name = RelayCalc(self)
    return name
end

-- old = true: se guarda como antiguo (sin comprobar); no rebaja a quien ya estaba comprobado
function HU:RememberPeer(name, tag, old)
    if not tag or tag == self.myTag or not self.cfg or not self.cfg.byTag[tag] then return end
    local list = self.db.peers[tag] or {}
    self.db.peers[tag] = list
    local prev = list[name:lower()]
    list[name:lower()] = { name = name, t = time(), old = (old and (not prev or prev.old)) or nil }
    -- guardamos como mucho 8 por hermandad
    local count, oldestK, oldestT = 0, nil, nil
    for k, v in pairs(list) do
        count = count + 1
        if not oldestT or v.t < oldestT then oldestK, oldestT = k, v.t end
    end
    if count > 8 and oldestK then list[oldestK] = nil end
end

-- Alguien de otra hermandad ha hablado en el canal: tiene el addon
function HU:SeenPeer(name, tag)
    if not name or not tag or tag == self.myTag then return end
    local k = name:lower()
    local p = self.remote[k]
    if not p then
        p = { name = name, tag = tag, last = 0 }
        self.remote[k] = p
    end
    p.tag = tag
    p.last = math.max(p.last, GetTime() - 60)
    -- (guardarlo entre sesiones: como mucho una vez por minuto por persona; antes, con cada [+ARCHITECTURE.md]
    if (not p.remT or GetTime() - p.remT > 60) and self:CheckedOf(name, tag) then
        p.remT = GetTime()
        self:RememberPeer(name, tag)
    end
end

local relayShared, phShared = {}, {}
-- (de qué enlace se contó lo último: si cambia, se cuenta ya, sin esperar los 300/600 s. Si no, tras un [+ARCHITECTURE.md]
local sharedRelayOf, plRelayOf = {}, {}
local function RelayChanged(tag, name) return sharedRelayOf[tag] ~= (name and name:lower()) end
-- Cada hermandad tiene un solo enlace: al saber cuál es, los demás de esa hermandad dejan de
-- contar como enlace (si no, el primero que entró seguía recibiéndolo todo aunque ya no lo fuera)
local function MarkRelay(tag, name, firsthand)
    local k = name:lower()
    for _, key in ipairs(HU:RemoteKeys(tag)) do
        local p = HU.remote[key]
        if p and p.tag == tag then
            if key ~= k then p.relay, p.relaySelfT = false, nil
            else
                p.relay, p.relayT = true, GetTime()
                -- (lo ha dicho él mismo, en su saludo o en su presentación del canal)
                if firsthand then p.relaySelfT = GetTime() end
            end
        end
    end
end

-- El enlace de esa hermandad, solo si lo dijo él mismo hace poco. Es lo único que se cuenta a [+ARCHITECTURE.md]
function HU:KnownRelay(tag)
    local best
    for _, key in ipairs(self:RemoteKeys(tag)) do
        local p = self.remote[key]
        if p and p.tag == tag and p.relay and p.relaySelfT and GetTime() - p.relaySelfT < 900
            and (not best or p.relaySelfT > best.relaySelfT) then best = p end
    end
    return best
end
HU.MarkRelay = MarkRelay
local function OnHello(sender, f, dist, isReply)
    local ver, tag, mod, relay = f[1], f[2], f[3] == "1", f[4] == "1"
    if ver and ver:match("^[%d%.]+$") and #ver < 12 and HU.VersionGreater(ver, HU.version) and not HU.newerWarned then
        HU.newerWarned = true
        HU:Print(L("Hay una versión más nueva del addon (") .. ver .. L("). Tú tienes la ") .. HU.version .. ".")
    end
    -- actualización IMPORTANTE: su versión mínima es más nueva que la mía. Solo de un oficial o GM: de [+ARCHITECTURE.md]
    local minv = f[10]
    if minv and minv:match("^[%d%.]+$") and #minv < 12 and ver and ver:match("^[%d%.]+$")
        and HU.VersionGreater(minv, HU.version) and not HU.VersionGreater(minv, ver)
        and (not HU.mustUpdate or minv == HU.mustUpdate or HU.VersionGreater(minv, HU.mustUpdate)) then
        local trusted
        if dist == "GUILD" then
            local re = HU.roster[HU:Key(sender) or ""]
            trusted = re ~= nil and HU:RankRole(HU.myTag, re.rankIndex) ~= nil
        elseif tag and tag ~= "" and tag ~= HU.myTag and HU.cfg and HU.cfg.byTag[tag] then
            trusted = (HU.CheckOfficerFirm and HU:CheckOfficerFirm(sender, tag, nil, sender, dist))
                or (HU.TrustedOfficer and HU:TrustedOfficer(sender, tag) and HU.RosterStateOf(HU.remoteRoster[tag]) == "c")
        end
        if trusted then
            local fresh = HU.mustUpdate ~= minv
            HU.mustUpdate = minv
            -- (se guarda con la hora: sigue tras /reload, y caduca si en 7 días ningún oficial lo repite)
            if HU.db then HU.db.mustUpdate = { v = minv, t = time() } end
            if fresh and HU.MustUpdateNotice then HU.After(0, function() HU:MustUpdateNotice(true) end) end
        end
    end
    local k = sender:lower()
    if dist == "GUILD" then
        local wasKnown = HU.guildPeers[k] ~= nil
        HU.guildPeers[k] = { name = sender, last = GetTime(), mod = mod, ver = ver, score = HU:SaneScore(sender, f[6]), relay = relay }
        HU.ForgetRelayMemo()
        -- (compañero nuevo: el enlace vuelve a saludar enseguida, así el nuevo sabe quién es el
        -- enlace sin esperar 2-5 min y entra ya de ayudante si le toca)
        if not wasKnown and not isReply and HU.HelpersChangedHello and HU:IsRelay() then HU:HelpersChangedHello() end
        -- (solo vale lo que dice el enlace que calculo yo: antes bastaba con decir relay=1 en el
        -- saludo, y cualquiera movía de carril a toda la hermandad o se nombraba ayudante)
        local isRelay = relay and HU:Key(HU:RelayName() or "") == k
        -- (carril de la comunidad: del enlace o de un oficial, se sigue; de cualquier otro compañero [+ARCHITECTURE.md]
        if f[7] and HU.OfferLane and ((f[8] and f[8] ~= "") or isRelay) then
            HU:OfferLane(HU.ParseLane(f[7], f[8], f[9]), sender, isRelay or LaneStrong(sender, dist))
        end
        -- el enlace de mi hermandad dice quiénes le ayudan (y en qué orden)
        if isRelay and f[5] then
            local list = {}
            for n in f[5]:gmatch("[^,]+") do list[#list + 1] = n end
            local old = HU.relayHelpers
            HU.relayHelpers = { list = list, t = GetTime(), relay = sender }
            -- (fase de lanzamiento: el enlace y sus ayudantes van en las listas; si cambian, el cambio
            -- sale en unos segundos y no en la vuelta de cada 2 minutos)
            if HU.PresenceSchedule and (not old or old.relay ~= sender or table.concat(old.list, ",") ~= f[5]) then
                HU:PresenceSchedule()
            end
        end
        -- (ya sé quién reparte en mi hermandad: lo que esperaba por eso, se aplica)
        if isRelay and HU.RetryDeferred and (not HU.relayRetryT or GetTime() - HU.relayRetryT > 5) then
            HU.relayRetryT = GetTime()
            -- (hasta 60 acciones en espera: en el fotograma siguiente, no dentro del saludo)
            HU.After(0, function() HU:RetryDeferred() end)
        end
    else
        if tag == "" or not HU.cfg or not HU.cfg.byTag[tag] then return end
        -- (por susurro, «soy el enlace de X» solo vale de alguien de la lista de X, o avalado por X: [+ARCHITECTURE.md]
        if relay and not (HU:CheckedOf(sender, tag) or HU:FullPeer(sender, tag) or (HU.VouchedOf and HU:VouchedOf(sender, tag))) then
            HU:Debug("Saludo de enlace no aceptado (no está en la lista de su hermandad):", sender, tag)
            relay = false
            -- (pero sin datos buenos de X vale como una presentación del canal (raSeen): solo sirve para [+ARCHITECTURE.md]
            if not (HU.RosterTrusted and HU:RosterTrusted(tag)) and HU.BootPresented then HU.BootPresented(tag, sender, GetTime()) end
        end
        -- ¿contacto nuevo (o que no daba señales desde hace un rato)?
        local isNew = not HU.remote[k] or GetTime() - (HU.remote[k].last or 0) > 900
        local p = HU.remote[k] or { name = sender }
        p.tag, p.last, p.mod, p.relay, p.ver = tag, GetTime(), mod, relay, ver
        if relay then MarkRelay(tag, sender, true) end
        -- (el carril de la comunidad según el enlace de otra hermandad, ya comprobado arriba: es lo
        -- que junta a dos hermandades en carriles distintos, porque el susurro cruza carriles)
        if relay and f[7] and HU.OfferLane then
            HU:OfferLane(HU.ParseLane(f[7], f[8], f[9]), sender, LaneStrong(sender, dist, tag))
        elseif f[4] == "1" and f[7] and HU.OfferLane and HU.LaneContact(sender, tag) then
            -- (dice ser su enlace sin estar comprobado: vale como contacto, ver OfferLane)
            local new = HU.ParseLane(f[7], f[8], f[9])
            -- (y si yo no soy el enlace, se lo paso al mío, como con LN: ver HU.comm.LX)
            if new and (new.lane > HU:ChannelLane() or (new.lane == 0 and new.gen > HU:LaneState().gen))
                and not HU:IsRelay() and HU.myTag and IsInGuild()
                and (not HU.laneFwdT or GetTime() - HU.laneFwdT > 30) then
                HU.laneFwdT = GetTime()
                HU:Send(table.concat({ "LX", f[7], f[8] or "", f[9] or "", tag, sender }, "~"), "GUILD")
            end
            HU:OfferLane(new, sender, "contact")
        end
        -- me saluda el enlace de otra hermandad y yo no soy el mío: se lo digo a mi hermandad
        -- (así mi enlace habla directamente con el suyo)
        if relay and not HU:IsRelay() and (not relayShared[tag] or GetTime() - relayShared[tag] > 600 or plRelayOf[tag] ~= sender:lower()) then
            relayShared[tag], plRelayOf[tag] = GetTime(), sender:lower()
            HU:Send("PL~" .. tag .. ":" .. sender, "GUILD")
        end
        -- el enlace de esa hermandad dice quiénes le ayudan a repartir (y se lo cuento a mi
        -- hermandad: así los que le mandan datos los reparten entre todos ellos, no a uno solo)
        if relay and f[5] then
            local list = {}
            for n in f[5]:gmatch("[^,]+") do if #list < 10 then list[#list + 1] = n end end
            HU.helpers[tag] = { list = list, t = GetTime() }
            if #list > 0 and (not phShared[tag] or GetTime() - phShared[tag] > 300 or RelayChanged(tag, sender)) then
                phShared[tag] = GetTime()
                sharedRelayOf[tag] = sender:lower()
                HU:Send(HU.Utf8Cut("PH~" .. tag .. "~" .. sender .. "~" .. table.concat(list, ","), 250), "GUILD")
            end
        end
        HU.remote[k] = p
        -- (contacto guardado = comprobado: solo si sale en la lista confirmada de su hermandad. Antes se [+ARCHITECTURE.md]
        if HU:CheckedOf(sender, tag) then HU:RememberPeer(sender, tag) end
        if not isReply and (not p.replied or GetTime() - p.replied > 240) then
            p.replied = GetTime()
            -- (en el fotograma siguiente: montar el saludo calcula la puntuación y los ayudantes, ~3 ms;
            -- lo que decide si se acepta a este contacto ya está hecho arriba)
            HU.After(0, function() HU:Whisper(sender, HU:HelloText("HR"), true) end)
        end
        -- nuevo contacto: si soy el enlace, le mando mi lista (si ya la tienen, solo irán los cambios)
        local st = HU.RosterStateFor and HU.RosterStateFor(tag)
        local stale = not st or GetTime() - st.fullT >= 1800
        -- (se manda al mejor contacto de esa hermandad, normalmente su enlace,
        -- y de ahí se reparte entre sus ayudantes; no a cualquiera que salude, como un moderador)
        local best = HU:BestPeer(tag)
        local to = (best and best.name) or sender
        local tp = HU.remote[to:lower()] or p
        if (isNew or stale) and HU:HandlesTag(tag) and tag ~= HU.myTag and (not tp.sentRoster or GetTime() - tp.sentRoster > 120) then
            tp.sentRoster = GetTime()
            -- (la lista, en otro fotograma: montarla entera con cientos de conectados daba el tirón del
            -- saludo, hasta 17 ms en el enlace tras un cambio de carril)
            HU.After(0.05, function() HU:SendRosterTo(to) end)
        end
    end
    HU:Changed("peers")
end

---------------------------------------------------------------------------
-- cada enlace se presenta en el canal oculto (lo ven todos los del addon de [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local lastAnnounce, lastAnnounceText = -999, nil
-- La presentación por susurro: al enlace (o mejor contacto) de cada hermandad y a sus ayudantes, [+ARCHITECTURE.md]
function HU:AnnounceByWhisper(text, target)
    if target then return self:Whisper(target, text) end
    local now, sent = GetTime(), {}
    local function To(name)
        local k = name and self:Key(name)
        if not k or sent[k] or k == self:MeKey() then return end
        sent[k] = true
        self:Whisper(name, text)
    end
    for _, tag in ipairs(self:OtherTags()) do
        local rp = self:KnownRelay(tag) or self:BestPeer(tag)
        if rp then To(rp.name) end
        local h = self.helpers[tag]
        if h and h.list and h.t and now - h.t < 900 then
            for i = 1, math.min(4, #h.list) do To(h.list[i]) end
        end
    end
end
function HU:AnnounceRelay(force)
    if self:IsChatLockedDown() then return end
    if not self.myTag or not self:IsRelay() or not self:IsJoined("main") then return end
    local id = self:ChannelId("main")
    if not id then return end
    -- (los 2 min después de un cambio, los mismos que en el saludo: antes la presentación los volvía a
    -- elegir de cero, se saltaba esa espera y los ayudantes entraban y salían)
    local cur = self.advertisedHelpers
    local helpers = (cur and #cur > 0 and self.helpersChangedT and GetTime() - self.helpersChangedT < 120) and cur or self:MyHelpers()
    self.advertisedHelpers = helpers
    local text = "[" .. self.myTag .. ":R] " .. HU.Utf8Cut(table.concat(helpers, ","), 200)
    local now = GetTime()
    if not force and text == lastAnnounceText and now - lastAnnounce < 300 then return end
    if now - lastAnnounce < 30 then return end
    lastAnnounce, lastAnnounceText = now, text
    -- (al final, la huella de mi lista de conectados: quien tenga otra distinta, se ha
    -- perdido algún cambio y la vuelve a pedir)
    local hash = self.MyRosterHash and self:MyRosterHash()
    -- Siempre por susurro al enlace y a los ayudantes de cada hermandad: en Forever un addon no puede
    -- escribir solo en un canal (el juego lo bloquea y sale el aviso rojo «ADDON_ACTION_BLOCKED»), y lo
    -- oculto por un canal de jugadores no le llega a nadie (medido por Olympus: 0 de 123)
    self:AnnounceByWhisper(table.concat({ "RA", self.myTag, HU.Utf8Cut(table.concat(helpers, ","), 200) .. (hash and (" #" .. hash) or "") }, "~"))
end

-- la presentación del enlace como mensaje oculto (la mandan los de Retail)
-- (o por susurro, en Forever: ver AnnounceByWhisper; la seguridad es la de un saludo, AllowAddonMessage)
-- (RA por susurro: la presentación del enlace en Forever, con las mismas reglas que su saludo)
HU:RegisterMessage("RA", { tagField = 1, bootstrap = true, channel = true, ttl = 60, latestWins = true, skipLocked = true })
HU.comm.RA = function(self, sender, f, dist)
    if dist ~= "CHANNEL" and dist ~= "WHISPER" then return end
    local tag = f[1]
    if not tag or tag == self.myTag or not self.cfg or not self.cfg.byTag[tag] then return end
    self:OnRelayAnnounce(sender, tag, f[2] or "", dist == "WHISPER")
end

-- Contestar a una presentación que llegó por susurro: la mía, solo a él
local function AnswerRAByWhisper(author)
    if not HU:IsRelay() or not HU.myTag then return end
    local hash = HU.MyRosterHash and HU:MyRosterHash()
    local helpers = HU.advertisedHelpers or HU:MyHelpers()
    HU:AnnounceByWhisper(table.concat({ "RA", HU.myTag, HU.Utf8Cut(table.concat(helpers, ","), 200) .. (hash and (" #" .. hash) or "") }, "~"), author)
end

local answeredRA = {}
-- Enlace provisional de X (quien se presenta sin estar comprobado, cuando X no tiene enlace «dicho por [+ARCHITECTURE.md]
local PROV_SPAM, PROV_HOLD = 25, 75
local provRelay = {}   -- [tag] = { k = clave, t = su última presentación }
local raLast, raSpam = {}, {}   -- [tag .. clave] = su último RA / su último RA demasiado seguido
HU.ClearProvRelay = function(tag, k)
    local cur = provRelay[tag]
    if cur and cur.k ~= k then provRelay[tag] = nil end
end
local function TakeProv(self, tag, author)
    local pk = author:lower()
    local now = GetTime()
    local key = tag .. "\1" .. pk
    local last = raLast[key]
    raLast[key] = now
    if last and now - last < PROV_SPAM then raSpam[key] = now end
    local cur = provRelay[tag]
    -- 2) demasiado seguido: ni se queda ni sigue
    if raSpam[key] and now - raSpam[key] < PROV_HOLD then
        if cur and cur.k == pk then provRelay[tag] = nil end
        -- (y deja de ser «el enlace» para lo que va a X: si no, BestPeer le seguiría eligiendo)
        local sp = self.remote[pk]
        if sp and sp.tag == tag then sp.relay, sp.relaySelfT = false, nil end
        return false
    end
    if cur and cur.k ~= pk then
        -- 3) con lista de X: quien sale en ella gana a quien no sale
        local R = self.remoteRoster[tag]
        if R and R.byKey and #(R.members or {}) > 0 then
            local inR, curInR = R.byKey[pk] ~= nil, R.byKey[cur.k] ~= nil
            local curSpam = raSpam[tag .. "\1" .. cur.k]
            local curOk = not (curSpam and now - curSpam < PROV_HOLD)
            if curInR and not inR and curOk then return false end
        end
    end
    -- 1) el último que se presenta
    provRelay[tag] = { k = pk, t = now }
    return true
end
function HU:OnRelayAnnounce(author, tag, msg, byWhisper)
    -- (si ya tengo la lista de esa hermandad, el que se presenta como su enlace tiene que estar en [+ARCHITECTURE.md]
    -- (una lista de arranque no cuenta como «ya tengo su lista»: en ella nadie es miembro todavía)
    local R = self.remoteRoster[tag]
    local RS = HU.RosterStateOf(R)
    -- (comprobado, para ser enlace «dicho por él»: sale en su lista confirmada, lo nombró su enlace
    -- comprobado (como el nuevo tras un relevo) o es un contacto comprobado)
    local checked = self:CheckedOf(author, tag) or self:VouchedOf(author, tag) or self:FullPeer(author, tag)
    -- (salir en una presentación del canal se apunta siempre: solo vale para arrancar, y una lista [+ARCHITECTURE.md]
    do
        local names0 = (msg or ""):match("^(.-)%s*#%x+%s*$") or msg or ""
        local now0 = GetTime()
        HU.BootPresented(tag, author, now0)
        local c0 = 0
        for n in names0:gmatch("[^,%s]+") do
            c0 = c0 + 1
            if c0 <= 10 then HU.BootPresented(tag, n, now0) end
        end
    end
    if R and RS ~= "b" and not (checked or self:MemberOf(author, tag)) then
        -- No sale en mi lista de X. Si X no tiene enlace «dicho por él» desde hace más de 900 s (el [+ARCHITECTURE.md]
        if byWhisper or self:KnownRelay(tag) then return end
        local pk = author:lower()
        if not TakeProv(self, tag, author) then return end
        local pp = self.remote[pk] or { name = author, tag = tag, last = 0 }
        pp.tag, pp.last = tag, GetTime()
        self.remote[pk] = pp
        MarkRelay(tag, author)
        -- (y se le contesta como a cualquier enlace nuevo: si no, no me oía hasta mi siguiente [+ARCHITECTURE.md]
        if self:IsRelay() and (not answeredRA[pk] or GetTime() - answeredRA[pk] > 600) then
            answeredRA[pk] = GetTime()
            HU.After(2 + math.random() * 3, function() HU:AnnounceRelay(true) end)
            HU.After(1 + math.random(), function() HU:Whisper(author, HU:HelloText("HI")) end)
        end
        if not pp.sentRoster then HU.After(2 + math.random() * 2, function() HU:RosterCycle() end) end
        return
    end
    local k = author:lower()
    -- (un enlace nuevo para mí: me presento yo también, para que él me vea en el canal)
    if self:IsRelay() and (not answeredRA[k] or GetTime() - answeredRA[k] > 600) then
        answeredRA[k] = GetTime()
        if byWhisper then
            -- (por susurro, se le contesta solo a él: la presentación de todos sale a su hora)
            HU.After(2 + math.random() * 3, function() AnswerRAByWhisper(author) end)
        else
            local wait = math.max(2 + math.random() * 3, lastAnnounce + 31 - GetTime())
            HU.After(wait, function() HU:AnnounceRelay(true) end)
        end
        -- (la presentación puede tardar hasta 31 s por la prudencia del canal: el saludo directo llega ya
        -- y le basta para aceptar mi lista mientras no tenga datos buenos de mi hermandad)
        HU.After(1 + math.random(), function() HU:Whisper(author, HU:HelloText("HI")) end)
    end
    local p = self.remote[k] or { name = author, tag = tag, last = 0 }
    p.tag, p.last = tag, GetTime()
    self.remote[k] = p
    -- Sin datos buenos de esa hermandad, quien se presenta no es aún su enlace «dicho por él» ni nombra [+ARCHITECTURE.md]
    local names, hash = (msg or ""):match("^(.-)%s*#(%x+)%s*$")
    if not names then names = msg or "" end
    local list = {}
    for n in names:gmatch("[^,%s]+") do if #list < 10 then list[#list + 1] = n end end
    if checked then
        MarkRelay(tag, author, true)
        self.helpers[tag] = { list = list, t = GetTime() }
        -- (por susurro solo me llega a mí: si su enlace ha cambiado, se lo cuento ya a mi hermandad, como
        -- con su saludo; por el canal les llegaba a todos)
        if byWhisper and #list > 0 and RelayChanged(tag, author) then
            phShared[tag], sharedRelayOf[tag] = GetTime(), author:lower()
            self:Send(HU.Utf8Cut("PH~" .. tag .. "~" .. author .. "~" .. table.concat(list, ","), 250), "GUILD")
        end
    elseif not self:KnownRelay(tag) and TakeProv(self, tag, author) then
        -- (sin enlace «dicho por él» de X: el que se presenta queda de enlace provisional con la misma [+ARCHITECTURE.md]
        MarkRelay(tag, author)
    end
    -- (enlace comprobado: está en la lista confirmada de su hermandad. Él y los ayudantes que nombra
    -- pueden mandarme ya su lista aunque aún no salgan en mi copia, como el enlace nuevo tras un relevo)
    if self:CheckedOf(author, tag) or self:FullPeer(author, tag) then
        local v = self.vouchOf[tag] or {}
        self.vouchOf[tag] = v
        local now = GetTime()
        for key, t in pairs(v) do if now - t > VOUCH_TTL then v[key] = nil end end
        v[k] = now
        for _, n in ipairs(list) do
            local nk = self:Key(n)
            if nk then v[nk] = now end
        end
        if self:CheckedOf(author, tag) then self:RememberPeer(author, tag) end
    end
    -- (sin lista buena de esa hermandad, salir en su presentación es lo único que vale para arrancar)
    local now = GetTime()
    HU.BootPresented(tag, author, now)
    for _, n in ipairs(list) do HU.BootPresented(tag, n, now) end
    -- Dos cuentas que coinciden: la lista sin confirmar me la mandó otro de esa hermandad y la huella
    -- de esta presentación (de alguien que sale en ella) es la misma
    local st = self.bootState[tag]
    if R and RS ~= "c" and hash and R.byKey and R.byKey[k] and HU.HashNoKept(R.members) == hash then
        local kind = self:SenderKind(author, tag)
        if kind == "peer" or kind == "vouched" then
            self:SetRosterState(tag, "c", "la confirma la presentación de " .. author)
        elseif st and not st.origins[k] then
            st.origins[k] = (kind == "old") and "old" or "boot"
            st.two = true
            -- (solo con rangos si una de las dos cuentas es conocida de antes)
            local hasOld = false
            for _, kd in pairs(st.origins) do if kd == "old" then hasOld = true end end
            if hasOld and HU.STATE_RANK[st.state] < 3 then
                st.upgrade = true
                self:SetRosterState(tag, "p", "dos cuentas, una conocida", "old")
                self:AfterRosterDecided(tag, nil, R)
            elseif HU.STATE_RANK[st.state] < 2 then
                self:SetRosterState(tag, "m", "dos cuentas")
            end
        end
    end
    self:ReplayHeld()
    -- (contacto nuevo: la lista sale ya, sin esperar a la vuelta del ciclo)
    if not self.remote[k].sentRoster then HU.After(2 + math.random() * 2, function() HU:RosterCycle() end) end
    -- huecos: si mi lista de conectados de esa hermandad no coincide con la suya dos avisos [+ARCHITECTURE.md]
    if hash and tag ~= self.myTag then
        local r = self.remoteRoster[tag]
        if not r then
            if self.NeedRoster then self:NeedRoster(tag) end
        elseif HU.HashNoKept(r.members) == hash then
            r.annMiss = 0
            r.confirmedT = GetTime() -- (su enlace confirma que mi copia es la suya)
            r.confirmed = GetTime() -- (sigue al día: le vale a la guardia)
        else
            r.annMiss = (r.annMiss or 0) + 1
            if r.annMiss >= 2 and self.NeedRoster then self:NeedRoster(tag) end
            -- (fase de lanzamiento: la lista son unos nombres; si no cuadra dos veces, se le pide [+ARCHITECTURE.md]
            if r.annMiss >= 2 and self.ResponsibleFor and self:ResponsibleFor(tag)
                and (not r.rfAskT or GetTime() - r.rfAskT > 60) then
                r.rfAskT = GetTime()
                self:Whisper(author, "RF~" .. (self.myTag or "") .. "~1", true)
            end
            if r.annMiss >= 3 and self.ResponsibleFor and self:ResponsibleFor(tag) then
                r.annMiss = 0
                self:Whisper(author, "RF~" .. (self.myTag or ""), true)
            end
        end
    end
    self:Changed("peers")
end

-- Ayudantes de otra hermandad, contados por un compañero:  PH~ETIQ~enlace~ayudante,ayudante
-- (combat = "last": quién es el enlace o los ayudantes de otra hermandad, contado por la mía: vale el último)
HU:RegisterMessage("PH", { ttl = 60, skipLocked = true, combat = "last" })
HU.comm.PH = function(self, sender, f, dist)
    if dist ~= "GUILD" then return end
    local tag, relay = f[1], f[2]
    if not tag or tag == self.myTag or not self.cfg or not self.cfg.byTag[tag] then return end
    -- Seguridad: de mi enlace, sus ayudantes o un oficial, como antes. De otro compañero, solo si el [+ARCHITECTURE.md]
    local strict = not self:IsGuildForwarder(sender)
    if strict and not (relay and relay ~= "" and self:MemberOf(relay, tag)) then
        if self.Debug then self:Debug("PH no aceptado:", sender, tag, relay) end
        return
    end
    local list = {}
    for n in (f[3] or ""):gmatch("[^,]+") do if #list < 10 and (not strict or self:MemberOf(n, tag)) then list[#list + 1] = n end end
    if #list == 0 then return end
    self.helpers[tag] = { list = list, t = GetTime() }
    phShared[tag] = GetTime()
    if relay and relay ~= "" then sharedRelayOf[tag] = relay:lower() end
    -- (lo cuenta el enlace, un ayudante o un oficial de mi hermandad: valen para mandarme su lista)
    if self:IsGuildForwarder(sender) then
        local now = GetTime()
        if relay and relay ~= "" then HU.ForwarderPresented(tag, relay, now) end
        for _, n in ipairs(list) do HU.ForwarderPresented(tag, n, now) end
    end
    if relay and relay ~= "" then
        local k = relay:lower()
        local p = self.remote[k]
        if not p then self.remote[k] = { name = relay, tag = tag, last = GetTime() - 300, relay = true }
        elseif p.tag == tag then p.relay = true end
        -- (PH lo manda quien acaba de recibir el saludo del propio enlace: vale como dicho por él, pero [+ARCHITECTURE.md]
        local firm = self:CheckedOf(relay, tag) or self:FullPeer(relay, tag) or self:VouchedOf(relay, tag)
        MarkRelay(tag, relay, firm and true or nil)
    end
end

-- Un compañero se ha pasado a otro carril del canal (LN~n): el enlace lo comprueba sondeando el [+ARCHITECTURE.md]
local laneProbeT = -999
HU:RegisterMessage("LN", { ttl = 60, latestWins = true, skipLocked = true })
HU.comm.LN = function(self, sender, f, dist)
    if dist ~= "GUILD" and dist ~= "WHISPER" then return end
    -- LN~carril~generación~hora: el carril de la comunidad (5.4.8); se sigue el más alto
    if f[2] and f[2] ~= "" and self.OfferLane then
        local p = dist == "WHISPER" and self.remote[sender:lower()]
        local strong = LaneStrong(sender, dist, p and p.tag)
        if not strong and p and HU.LaneContact(sender, p.tag) then strong = "contact" end
        -- (el aviso de otra hermandad me llega a mí porque soy su contacto, pero solo mi enlace puede [+ARCHITECTURE.md]
        if strong == "contact" and not self:IsRelay() and self.myTag and IsInGuild()
            and (not HU.laneFwdT or GetTime() - HU.laneFwdT > 30) then
            HU.laneFwdT = GetTime()
            self:Send(table.concat({ "LX", f[1], f[2], f[3] or "", p.tag, sender }, "~"), "GUILD")
        end
        -- (el aviso viene de alguien de la otra hermandad que no es mi contacto: no le hago caso, pero le
        -- pregunto el carril a mi contacto, cuya respuesta sí vale. Si no, me quedaba atrás 7 min)
        local new = HU.ParseLane(f[1], f[2], f[3])
        if not strong and p and p.tag and new and new.lane > (self.ChannelLane and self:ChannelLane() or 0)
            and self:MemberOf(sender, p.tag) and (not HU.laneAskT or GetTime() - HU.laneAskT > 90) then
            HU.laneAskT = GetTime()
            local tag = p.tag
            for _, d in ipairs({ 0, 20, 60 }) do
                HU.After(d, function()
                    if (self:ChannelLane() or 0) >= new.lane then return end
                    local bp = self:BestPeer(tag)
                    if bp and bp.name:lower() ~= sender:lower() then self:Whisper(bp.name, "LQ", true) end
                end)
            end
        end
        self:OfferLane(new, sender, strong)
        return
    end
    -- LN~carril (versiones anteriores, o un compañero que pide comprobarlo): el enlace sondea
    if not self:IsRelay() or not self.ProbeLane then return end
    local n = tonumber(f[1])
    if not n or n <= (self.ChannelLane and self:ChannelLane() or 0) then return end
    if GetTime() - laneProbeT < 20 then return end
    laneProbeT = GetTime()
    self:ProbeLane()
end
-- (sin latestWins: el sondeo manda 3 a propósito)
HU:RegisterMessage("LP", { channel = true, ttl = 60, skipLocked = true })
HU.comm.LP = function() end
-- LO~up|reset (copia 118): un oficial de MI hermandad propone cambiar de sala a toda la comunidad.
-- Solo lo ven los oficiales; se hace si otro escribe /gu carril confirmar (HU:ConfirmLane, Channel.lua)
HU:RegisterMessage("LO", { ttl = 60 })
HU.comm.LO = function(self, sender, f, dist)
    if dist ~= "GUILD" or not self.OnLaneProposal or sender:lower() == (self:MeKey() or "") then return end
    if not (self.IsOfficerName and self:IsOfficerName(sender)) then return end
    if not ((self.IsOfficerName and self:IsOfficerName(self:Me())) or self:CanOfficer()) then return end
    self:OnLaneProposal(sender, f[1])
end
-- LV~carril (copia 117): el enlace de OTRA hermandad dice que a él el canal le lleva minutos sin
-- aceptar nada y propone ese carril. Solo cuenta como confirmación para mi propia mudanza, que
-- además exige que a mí me pase lo mismo (HU:OnLaneVote, Channel.lua). Nunca me mueve por sí solo.
HU:RegisterMessage("LV", { ttl = 60 })
HU.comm.LV = function(self, sender, f, dist)
    if dist ~= "WHISPER" or not self.OnLaneVote then return end
    local lane = tonumber(f[1])
    local p = self.remote[sender:lower()]
    local tag = p and p.tag
    if not lane or lane ~= lane or lane < 1 or lane > 9 or not tag or tag == self.myTag then return end
    local rp = self.KnownRelay and self:KnownRelay(tag)
    if not (rp and rp.name and rp.name:lower() == sender:lower()) then return end
    -- (copia 120: solo vale la confirmación de un enlace que sea oficial de su hermandad)
    if not (self.IsOfficerName and self:IsOfficerName(sender)) then return end
    self:OnLaneVote(math.floor(lane), tag)
end
-- LQ: «¿en qué carril estás?» de otra hermandad. Contesto con mi LN por susurro (a cada uno como [+ARCHITECTURE.md]
local laneAnswerT, laneAnswered, laneAnswerN = -999, {}, 0
HU:RegisterMessage("LQ")
HU.comm.LQ = function(self, sender, f, dist)
    if dist ~= "WHISPER" or not self.LaneState or GetTime() - laneAnswerT < 1 then return end
    local k = sender:lower()
    local p = self.remote[k]
    if p and p.tag == self.myTag then return end
    if self.roster[self:Key(sender) or ""] then return end
    if laneAnswered[k] and GetTime() - laneAnswered[k] < 10 then return end
    laneAnswerN = laneAnswerN + 1
    if laneAnswerN > 200 then laneAnswered, laneAnswerN = {}, 0 end
    laneAnswerT, laneAnswered[k] = GetTime(), GetTime()
    local st = self:LaneState()
    self:Whisper(sender, "LN~" .. st.lane .. "~" .. st.gen .. "~" .. st.t, true)
end
-- LX~carril~gen~hora~ETIQ~contacto: un compañero me pasa el aviso de carril del contacto de otra [+ARCHITECTURE.md]
HU:RegisterMessage("LX")
HU.comm.LX = function(self, sender, f, dist)
    if dist ~= "GUILD" or not self:IsRelay() or not self.OfferLane then return end
    local tag, contact = f[4], f[5]
    if not tag or tag == "" or tag == self.myTag or not self.cfg or not self.cfg.byTag[tag] then return end
    if not contact or not HU.SafeName(contact) or not self:MemberOf(contact, tag) then return end
    self:OfferLane(HU.ParseLane(f[1], f[2], f[3]), contact, "contact")
end
-- «¿Eres de la hermandad?» (PG~nombre) y la respuesta (PA), las dos por la vía GUILD del juego
HU:RegisterMessage("PG")
HU.comm.PG = function(self, sender, f, dist)
    if dist ~= "GUILD" or not f[1] then return end
    local k = self:Key(f[1])
    if not k then return end
    -- (otro oficial ya pregunta por él: yo no. Solo si quien pregunta es oficial de verdad: antes
    -- cualquier compañero con el addon mandaba este PG y ningún oficial comprobaba al impostor)
    local re = self.roster[self:Key(sender) or ""]
    local byOfficer = re ~= nil and self:RankRole(self.myTag, re.rankIndex) ~= nil
    if self.ImpostorAsked and byOfficer and k ~= self:MeKey() and sender:lower() ~= self:MeKey() then self:ImpostorAsked(k) end
    if k == self:MeKey() then
        if self.lastPA and GetTime() - self.lastPA < 10 then return end
        self.lastPA = GetTime()
        self:Send("PA", "GUILD", nil, true)
    end
end
HU:RegisterMessage("PA")
HU.comm.PA = function(self, sender, f, dist)
    if dist ~= "GUILD" then return end
    local k = sender:lower()
    local p = self.guildPeers[k]
    if not p then self.guildPeers[k] = { name = sender, last = GetTime(), score = 0 } else p.last = GetTime() end
    HU.ForgetRelayMemo()
    if self.ReplayHeldChat then self:ReplayHeldChat(k) end
end
HU:RegisterMessage("HI", { tagField = 2, bootstrap = true, ttl = 60, latestWins = true, skipLocked = true })
HU.comm.HI = function(_, sender, f, dist) OnHello(sender, f, dist, false) end
HU:RegisterMessage("HR", { tagField = 2, bootstrap = true, ttl = 60, latestWins = true, skipLocked = true })
HU.comm.HR = function(_, sender, f, dist) OnHello(sender, f, dist, true) end

-- Lista de contactos compartida por el enlace dentro de la hermandad
local plSeen = {}
-- También llega por susurro: el enlace de otra hermandad nos presenta a los contactos que
-- conoce de las demás (si no, dos hermandades sin moderadores en el canal no se encontraban)
local plForward = {}
HU:RegisterMessage("PL", { ttl = 60, skipLocked = true, combat = "last" })
HU.comm.PL = function(self, sender, f, dist, raw)
    if dist ~= "GUILD" and dist ~= "WHISPER" then return end
    -- Seguridad: por susurro solo lo presenta el enlace (o un ayudante u oficial) comprobado de otra [+ARCHITECTURE.md]
    local strict = false
    if dist == "WHISPER" then
        local sp = self.remote[sender:lower()]
        if not (sp and sp.tag and self:IsRemoteForwarder(sender, sp.tag)) then
            if self.Debug then self:Debug("PL por susurro no aceptado:", sender) end
            return
        end
    else
        strict = not self:IsGuildForwarder(sender)
    end
    for pair in (f[1] or ""):gmatch("[^,]+") do
        local tag, name = pair:match("^(%w+):(.+)$")
        if tag then plSeen[tag] = GetTime() end
        local rr = tag and self.remoteRoster[tag]
        local known = tag and rr and HU.RosterStateOf(rr) ~= "b"
        local firsthand
        if tag then
            for _, key in ipairs(self:RemoteKeys(tag)) do
                local q = self.remote[key]
                if q and q.tag == tag and q.relaySelfT and GetTime() - q.relaySelfT < 600 then firsthand = q end
            end
        end
        if firsthand and name and firsthand.name:lower() == name:lower() then firsthand = nil end
        if tag and HU.SafeName(name) and not firsthand and ((not known and not strict) or self:MemberOf(name, tag))
            and tag ~= self.myTag and self.cfg and self.cfg.byTag[tag] then
            local k = name:lower()
            local p = self.remote[k]
            if not p then
                self.remote[k] = { name = name, tag = tag, last = GetTime() - 300, relay = true }
            elseif p.tag == tag then
                p.relay = true
                if p.last < GetTime() - 300 then p.last = GetTime() - 300 end
            end
            MarkRelay(tag, name)
            -- (presentado por el enlace, un ayudante o un oficial de mi hermandad: vale para mandarme su lista)
            if dist == "GUILD" and self:IsGuildForwarder(sender) then HU.ForwarderPresented(tag, name, GetTime()) end
        end
    end
    -- me han presentado contactos por susurro: lo paso a mi hermandad (lo ve también mi enlace)
    if dist == "WHISPER" and raw and (not plForward[raw] or GetTime() - plForward[raw] > 120) then
        -- (la tabla no crece sin límite: la clave la elige quien manda)
        local n = 0
        for key, t in pairs(plForward) do
            if GetTime() - t > 120 then plForward[key] = nil else n = n + 1 end
        end
        if n > 200 then return end
        plForward[raw] = GetTime()
        self:Send(raw, "GUILD")
    end
end

-- El enlace no tiene contacto en alguna hermandad: lo pregunta a su hermandad, y
-- contesta (una sola vez) cualquiera que tenga uno.   PR~ETIQ1,ETIQ2
HU:RegisterMessage("PR")
HU.comm.PR = function(self, sender, f, dist)
    if dist ~= "GUILD" then return end
    for tag in (f[1] or ""):gmatch("%w+") do
        local p = self:KnownRelay(tag)
        -- en hermandades grandes contestan solo unos pocos (al azar), no todos
        if p and math.random() <= math.min(1, 8 / math.max(1, HU:PeerCount())) then
            HU.After(0.5 + math.random() * 4, function()
                if plSeen[tag] and GetTime() - plSeen[tag] < 6 then return end
                plSeen[tag] = GetTime()
                HU:Send("PL~" .. tag .. ":" .. p.name, "GUILD")
            end)
        end
    end
end

local lastPR = -999
function HU:AskPeers(tags)
    if #tags == 0 or GetTime() - lastPR < 60 then return end
    lastPR = GetTime()
    self:Send("PR~" .. table.concat(tags, ","), "GUILD")
end

---------------------------------------------------------------------------
-- Ciclos
---------------------------------------------------------------------------
-- (el juego avisa también al mover el canal de número: solo se saluda una vez por minuto)
local lastJoinHello = -999
function HU:OnMainJoined()
    if GetTime() - lastJoinHello < 60 then return end
    lastJoinHello = GetTime()
    HU.After(3, function() HU:HelloCycle() end)
end

local plSent = {}
local modHello = {}
function HU:HelloCycle()
    if not self.myTag or not IsInGuild() then return end
    -- (con el chat bloqueado no sale nada: se saluda al acabar. Combat.lua)
    if self:IsChatLockedDown() then return end
    self:Send(self:HelloText("HI"), "GUILD")
    -- (lo demás, en el fotograma siguiente: montar el saludo ya cuesta ~3 ms)
    HU.After(0, function() HU:HelloCycleExpire() end)
end

function HU:HelloCycleExpire()
    if not self.myTag then return end
    -- caducar contactos viejos
    local now = GetTime()
    for k, p in pairs(self.guildPeers) do if now - p.last > 1000 then self.guildPeers[k] = nil end end
    for k, p in pairs(self.remote) do if now - p.last > 1800 then self.remote[k] = nil end end
    for tag, r in pairs(self.remoteRoster) do if now - r.updated > 2400 then self.remoteRoster[tag] = nil end end
    for k, t in pairs(self.chanSeen) do if now - t > 7200 then self.chanSeen[k] = nil end end

    if not self:IsJoined("main") then return end
    -- (la lista del canal solo la leen el enlace y los que pueden ser moderadores: ver NeedsChannelList)
    if not self:NeedsChannelList() then return self:HelloCycleRest(nil, now) end
    -- (la lista del canal, por trozos: con miles de personas, leerla de golpe daba un tirón)
    self:GetChannelMembersAsync("main", function(members) HU:HelloCycleRest(members, now) end)
end

function HU:HelloCycleRest(members, now)
    if not self.myTag or not self:IsJoined("main") then return end
    -- los moderadores se saludan entre ellos (los necesita la guardia) [+ARCHITECTURE.md]
    local modList = members and self.chanModList or {}
    if members and self:AmIMod(members) then
        local hi
        for _, m in ipairs(modList) do
            local k = m.name:lower()
            if m.mod and k ~= self:MeKey() and not self.roster[k] and (not modHello[k] or now - modHello[k] > 900) then
                modHello[k] = now
                hi = hi or self:HelloText("HI")
                self:Whisper(m.name, hi)
            end
        end
    end

    if not self:IsRelay() then return end
    -- (lo del enlace, en los fotogramas siguientes: todo seguido daba un tirón)
    HU.After(0, function() HU:AnnounceRelay() end)
    HU.After(0.1, function() HU:RelayHelloRest(members, now) end)
end

function HU:RelayHelloRest(members, now, hi)
    if not self.myTag or not self:IsRelay() then return end
    -- (montar el saludo cuesta ~3 ms: se monta una vez, en un fotograma, y el resto va en el siguiente;
    -- antes se montaba de nuevo para cada susurro y todo junto daba picos de 9 ms)
    if not hi then
        hi = self:HelloText("HI")
        HU.After(0, function() HU:RelayHelloRest(members, now, hi) end)
        return
    end
    local modList = members and self.chanModList or {}

    -- el enlace busca o mantiene un contacto en cada hermandad
    local shared, missing, greeted = {}, {}, {}
    for _, tag in ipairs(self:OtherTags()) do
        local p = self:BestPeer(tag)
        if p then
            -- (los enlaces ya se ven en el canal: el saludo directo, cada 10 minutos basta)
            if not p.helloT or now - p.helloT > 600 then
                p.helloT = now
                self:Whisper(p.name, hi)
            end
            -- (a los demás, solo un enlace que lo haya dicho él mismo)
            local rp = self:KnownRelay(tag)
            if rp then shared[#shared + 1] = tag .. ":" .. rp.name end
        else
            missing[#missing + 1] = tag
            local tried = 0
            -- 1) contactos guardados de otras sesiones
            for _, v in pairs(self.db.peers[tag] or {}) do
                local k = v.name:lower()
                if tried < 3 and not greeted[k] then greeted[k] = true; self:Whisper(v.name, hi); tried = tried + 1 end
            end
            -- 2) moderadores del canal que no son de mi hermandad
            if members then
                for _, m in ipairs(modList) do
                    local k = m.name:lower()
                    -- (a cada moderador, una vez por vuelta aunque falten varias hermandades,
                    -- y como mucho cada 2 minutos)
                    if tried < 6 and m.mod and k ~= self:MeKey() and not self.roster[k] and not self.remote[k]
                        and not greeted[k] and (not modHello[k] or now - modHello[k] > 120) then
                        greeted[k], modHello[k] = true, now
                        self:Whisper(m.name, hi); tried = tried + 1
                    end
                end
            end
        end
    end
    -- y si le falta alguno, pregunta a los de su hermandad (alguien puede conocer a uno)
    self:AskPeers(missing)
    self.relayMissing = #missing
    -- (en varios mensajes si no caben: con 20 hermandades no entran en uno y las últimas
    -- se quedaban sin contacto)
    local function PLChunks(list)
        local out, cur = {}, ""
        for _, it in ipairs(list) do
            if cur ~= "" and #cur + #it + 1 > 240 then out[#out + 1] = "PL~" .. cur; cur = "" end
            cur = (cur == "") and it or (cur .. "," .. it)
        end
        if cur ~= "" then out[#out + 1] = "PL~" .. cur end
        return out
    end
    -- (a mi hermandad: si ha cambiado algo, o cada 10 minutos)
    local sharedText = table.concat(shared, ",")
    if #shared > 0 and (sharedText ~= self.lastSharedPL or GetTime() - (self.lastSharedPLT or 0) > 600) then
        self.lastSharedPL, self.lastSharedPLT = sharedText, GetTime()
        for _, text in ipairs(PLChunks(shared)) do self:Send(text, "GUILD") end
    end
    if #shared > 0 then
        -- presento a cada hermandad los contactos de las demás
        for _, pair in ipairs(shared) do
            local name = pair:match("^%w+:(.+)$")
            local others = {}
            for _, o in ipairs(shared) do if o ~= pair then others[#others + 1] = o end end
            -- (solo si ha cambiado algo, o cada 15 minutos)
            local text = table.concat(others, ",")
            local last = plSent[name]
            -- (con el aviso en el canal casi no hace falta; solo cada 30 minutos)
            if #others > 0 and (not last or GetTime() - last.t > 1800) then
                plSent[name] = { text = text, t = GetTime() }
                for _, m in ipairs(PLChunks(others)) do self:Whisper(name, m) end
            end
        end
    end
end

-- Compañeros de mi hermandad con el addon (vistos hace poco)
function HU:PeerCount()
    local n, now = 0, GetTime()
    for _, p in pairs(self.guildPeers) do if now - p.last < self.PEER_TTL then n = n + 1 end end
    return n
end

-- Cada cuánto se saluda: 2 min en hermandades pequeñas, hasta 5 min en las muy grandes
function HU:HelloInterval()
    return math.max(120, math.min(300, self:PeerCount() * 0.6))
end

-- Con cientos de compañeros con el addon, solo los primeros (los que pueden ser enlace o
-- ayudantes) saludan a menudo; el resto, cada 15 minutos
function HU:MyHelloInterval()
    local me, now, lower = self:MeKey(), GetTime(), 0
    if not me then return self:HelloInterval() end
    -- (el enlace al que aún le faltan contactos de otras hermandades vuelve a
    -- saludar enseguida; con 20 hermandades, encontrarlos a todos llevaba muchas vueltas)
    if (self.relayMissing or 0) > 0 and self:IsRelay() then return 40 end
    local myS = self.myAdvScore or 0
    for k, p in pairs(self.guildPeers) do
        if Better(p.score or 0, k, myS, me) and now - p.last < self.PEER_TTL then lower = lower + 1 end
    end
    if lower >= 12 then return 600 end -- (por debajo de PEER_TTL incluso con el ±10 %)
    return self:HelloInterval()
end

-- El enlace manda la lista de conectados a las otras hermandades: la lista entera cada
-- 30 minutos y, entre medias, cada 2 minutos solo los cambios (quién entra, sale o cambia)
function HU:RosterCycle()
    if not self.myTag or not self:IsJoined("main") or not self:RosterSlot() then return end
    if self:IsChatLockedDown() then return end
    -- si aún estoy mandando lo anterior, espero (con hermandades enormes son cientos de mensajes)
    if HU:BulkQueueSize() > 150 then return end -- (las listas de conectados van en su propia cola)
    -- (una hermandad por fotograma, como PresenceFlush: todas seguidas pasaban de 1,85 ms)
    local n = 0
    for _, tag in ipairs(self:OtherTags()) do
        if self:HandlesTag(tag) then
            n = n + 1
            HU.After(0.02 * (n - 1), function() HU:RosterCycleTag(tag) end)
        end
    end
end
function HU:RosterCycleTag(tag)
    if not self.myTag or not self:HandlesTag(tag) then return end
    local p = self:BestPeer(tag)
    if not p then return end
    local now = GetTime()
    local st = HU.RosterStateFor(tag)
    -- (fase de lanzamiento: la lista entera son 2 mensajes; cada 5 min, por si algún cambio
    -- se perdió por el camino. Con la lista de todos, cada 30 min)
    if not st or now - st.fullT >= 300 then
        p.sentRoster = now
        self:SendRosterTo(p.name)
    elseif now - st.t >= 120 then
        if not self:SendRosterDelta(p.name, st) then
            p.sentRoster = now
            self:SendRosterTo(p.name)
        end
    end
end

HU:OnStart(function()
    C_ChatInfo.RegisterAddonMessagePrefix(HU.PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(HU.PREFIX_B)
    HU.loginT = GetTime()
    SamplePerf()
    HU.NewTicker(30, SamplePerf)
    HU.After(20, Bench)
    HU.NewTicker(600, Bench)
    -- el enlace que entra en una banda o se pone ausente lo dice enseguida (para que lo
    -- haga otro), y al salir vuelve a decir su puntuación
    local wasBusy = false
    -- (acabo de pasar a ser el enlace: saludo y presentación en el canal ya, sin esperar al saludo [+ARCHITECTURE.md]
    local TAKEOVER_GAP = 45
    local relayNow, lastTakeover = false, -999
    HU.NewTicker(15, function()
        local b = Busy()
        if b ~= wasBusy then
            wasBusy = b
            if HU.myTag and IsInGuild() then HU:Send(HU:HelloText("HI"), "GUILD") end
        end
        local r = HU.myTag and IsInGuild() and HU:IsRelay() or false
        -- (los primeros 60 s ya los cubre el saludo de los 36 s)
        if r and not relayNow and GetTime() - (HU.loginT or 0) > 60 and GetTime() - lastTakeover >= TAKEOVER_GAP then
            lastTakeover = GetTime()
            HU:SafeCall("hello", HU.HelloCycle, HU)
        end
        relayNow = r
    end)
    HU.NewTicker(1.0, HU.QueueTick) -- (el cupo de la cola de envío: Net/Transport.lua)
    -- saludo: cada 2 a 5 minutos (según cuántos tengan el addon en la hermandad)
    local function hello()
        HU:SafeCall("hello", HU.HelloCycle, HU)
        -- (sin enlace conocido aún: se vuelve a saludar pronto, por si el enlace entró después de mi
        -- primer saludo y no me oyó; si no, tardaba 2-5 min en contar conmigo como ayudante)
        local soon = GetTime() - (HU.loginT or 0) < 300 and not HU:KnownGuildRelay()
        HU.After((soon and 45 or HU:MyHelloInterval()) * (0.9 + math.random() * 0.2), hello)
    end
    HU.After(15, hello)
    -- (¿soy el primero de mi hermandad? pregunta a los 3-6 s y decide al entrar en el canal, ~11 s)
    HU.After(3 + math.random() * 3, function() HU:AskGuildRelay() end)
    HU.After(10.5, function() HU:AloneCheck() end)
    -- (otro saludo justo al acabar los 30 s de prudencia: el primero cae antes y, si soy el enlace,
    -- la presentación en el canal esperaba al siguiente, de 2 a 5 minutos después)
    HU.After(36, function() HU:SafeCall("hello", HU.HelloCycle, HU) end)
    -- primero a mi hermandad (al momento) y, si sigue faltando algo, a las otras hermandades [+ARCHITECTURE.md]
    HU.After(2, function()
        local _, onlineNow = GetNumGuildMembers()
        onlineNow = tonumber(onlineNow) or 0
        -- (como mucho 8 s: lo normal es que la lista llegue antes por la bienvenida, WelcomeGuildmate)
        local spread = (onlineNow < 1) and 8 or math.max(1, math.min(8, onlineNow / 50))
        -- (día a día, entrando suelto: al momento. La espera al azar, solo en una entrada masiva)
        if HU.QuietLogins and HU.QuietLogins(10) then HU.AskGuildForMissing(HU)
        else HU.After(1 + math.random() * spread, function() HU:AskGuildForMissing() end) end
        for _, d in ipairs({ 6, 13, 28 }) do
            HU.After(d + math.random() * math.min(spread, 10), function() HU:AskGuildForMissing() end)
        end
    end)
    -- y a los contactos guardados de cada otra hermandad, sin esperar a ser enlace (oficiales, quien está [+ARCHITECTURE.md]
    for _, d in ipairs({ 2, 6 }) do HU.After(d + math.random() * 1.5, function() HU:AskSavedContacts() end) end
    -- (los rasos, solo si siguen sin confirmar, con una espera al azar que crece con los conectados, [+ARCHITECTURE.md]
    HU.After(2, function()
        local _, onlineNow = GetNumGuildMembers()
        local spread = math.max(1, math.min(10, (tonumber(onlineNow) or 0) / 50))
        if HU.QuietLogins and HU.QuietLogins(10) then
            HU.After(math.random() * 2, function() HU:AskSavedContacts(true) end)
            HU.After(5 + math.random() * 2, function() HU:AskSavedContacts(true) end)
            -- (si la hermandad aún se asienta, los contactos tardan en tenerla confirmada: dos más de reserva)
            HU.After(18 + math.random() * 4, function() HU:AskSavedContacts(true) end)
            HU.After(43 + math.random() * 4, function() HU:AskSavedContacts(true) end)
        else
            HU.After(4 + math.random() * spread, function() HU:AskSavedContacts(true) end)
            HU.After(11 + math.random() * spread, function() HU:AskSavedContacts(true) end)
        end
    end)
    for _, d in ipairs({ 100, 180, 260 }) do HU.After(d, function() HU:AskMissingRosters() end) end
    -- (fase de lanzamiento: antes, por si la hermandad no se la ha pasado)
    for _, d in ipairs({ 30, 60 }) do HU.After(d, function() HU:AskMissingRosters() end) end
    HU.NewTicker(300, function() HU:AskGuildForMissing(); HU:AskMissingRosters() end)
    -- (cada 15 s, no 60: así la lista sale poco después de conocer al enlace de otra hermandad; los
    -- cambios siguen saliendo cada 2 minutos)
    HU.NewTicker(15, function() HU:RosterCycle() end)
end)

HU:OnStart(function()
    local tries = 0
    local function restore()
        tries = tries + 1
        if HU.myTag and HU.cfg then return HU:RestoreRosterCache() end
        if tries < 20 then HU.After(1, restore) elseif HU.db then HU.db.rosterCache = nil end
    end
    HU.After(1, restore)
end)
