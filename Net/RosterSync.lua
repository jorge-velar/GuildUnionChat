-- Guild Union - Listas de conectados entre hermandades: enteras (RB), cambios (RC), peticiones (RF, NQ) y huellas (antes en Comm.lua)
local _, HU = ...
local Reshare = HU.ReshareRoster -- (Domain/Trust.lua)

HU:Saved({ char = { rankCache = {} } }) -- rangos vistos de otras hermandades: [clave] = { tag, idx, t }

---------------------------------------------------------------------------
-- Listas de miembros
---------------------------------------------------------------------------
local seqCounter = 0
-- Número de envío siguiente: la HORA DEL SERVIDOR (igual para todos) por 10, más un contador para que dos [+ARCHITECTURE.md]
local function NextSeq()
    local now = ((GetServerTime and GetServerTime()) or time()) * 10
    seqCounter = math.max(now, seqCounter + 1)
    return seqCounter
end
HU.ListStampNow = function() return ((GetServerTime and GetServerTime()) or time()) * 10 end
-- (en los mensajes va en base 36: 7 letras en vez de 11 cifras. Se lee con tonumber(s, 36))
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
function HU.B36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local out = {}
    while n > 0 do
        local d = n % 36
        out[#out + 1] = B36:sub(d + 1, d + 1)
        n = (n - d) / 36
    end
    return string.reverse(table.concat(out))
end

local function Clean(s)
    return (tostring(s or ""):gsub("[~,;|]", " "))
end

-- Lista de conectados de mi hermandad: cada uno en una línea corta
--   nombre,clase,nivel,rango,zona[,a]   (a = ausente)
local RosterEntriesFn
local reCache = {}

-- Fase de lanzamiento: además del maestro y los oficiales, el enlace y sus ayudantes (son los que
-- susurran a las otras hermandades, y solo se acepta a quien está en sus listas)
local function SharedExtra(self)
    local relay, list
    if self:IsRelay() then
        relay, list = self:Me(), self.advertisedHelpers
    elseif self.relayHelpers and GetTime() - self.relayHelpers.t < 700 then
        relay, list = self.relayHelpers.relay, self.relayHelpers.list
    end
    local set, names = {}, {}
    if relay then local k = self:Short(relay):lower(); set[k] = true; names[#names + 1] = k end
    for _, n in ipairs(list or {}) do local k = self:Short(n):lower(); set[k] = true; names[#names + 1] = k end
    table.sort(names)
    return set, table.concat(names, ",")
end

-- ¿Va este compañero de mi hermandad a las otras? (nil = todos; si no, la tabla de los de más)
function HU:SharedExtraSet() return (SharedExtra(self)) end
function HU:SharedWithOthers(e, extra)
    return not extra or self:RankRole(self.myTag, e.rankIndex) ~= nil or extra[self:Short(e.name):lower()] == true
end

-- everyone: todos los conectados, sin el filtro de la fase de lanzamiento (la lista de «Miembros de
-- la unión», UnionMembers.lua, que solo es para verla). Tiene su propia copia guardada
local reCacheAll = {}
local function RosterEntries(self, everyone)
    -- (se guarda hasta que cambia la lista: antes se rehacía para cada aviso y cada presentación)
    local v = self.rosterVersion or 0
    local extra, extraKey
    if not everyone then extra, extraKey = SharedExtra(self) end
    local cache = everyone and reCacheAll or reCache
    if cache.v == v and cache.src == self.rosterList and cache.ek == extraKey then return cache.list, cache.sig, cache.full end
    local list, sig, full = {}, {}, {}
    local myTag = self.myTag
    for _, e in ipairs(self.rosterList) do
        -- (el nombre corto en minúsculas se guarda en la ficha: antes se rehacía para cada conectado en cada
        -- vuelta, y con 600 conectados era casi todo el coste de rehacer la lista)
        local sk = e._sk
        if e.online and extra and (not sk or e._skn ~= e.name) then sk = self:Short(e.name):lower(); e._sk, e._skn = sk, e.name end
        if e.online and (not extra or self:RankRole(myTag, e.rankIndex) or extra[sk]) then
            -- (las líneas de cada uno se guardan en su ficha y solo se rehacen si cambia algo)
            local c = e._re
            if not (c and c.n == e.name and c.c == e.class and c.l == e.level and c.r == e.rankIndex and c.z == e.zone and c.a == e.afk) then
                local short = Clean(self:Short(e.name))
                local cls, lvl, rank = HU.CLASS_INDEX[e.class or ""] or 0, e.level or 0, e.rankIndex or ""
                c = { n = e.name, c = e.class, l = e.level, r = e.rankIndex, z = e.zone, a = e.afk, short = short,
                    en = table.concat({ short, cls, lvl, rank, Clean(HU.Utf8Cut(HU.ZoneOut(e.zone) or "", 24)) .. (e.afk and ",a" or "") }, ","),
                    -- lo que importa para avisar de un cambio (la zona cambia sin parar: no cuenta)
                    sig = table.concat({ cls, lvl, rank, e.afk and "a" or "" }, ",") }
                e._re = c
            end
            list[#list + 1] = c.en
            full[c.short] = c.en
            sig[c.short] = c.sig
        end
    end
    local made = { v = v, src = self.rosterList, ek = extraKey, list = list, sig = sig, full = full }
    if everyone then reCacheAll = made else reCache = made end
    return list, sig, full
end
RosterEntriesFn = RosterEntries
-- Todos los conectados de mi hermandad, una línea cada uno («nombre,clase,nivel,rango,zona[,a]»)
function HU:OnlineEntries() return (RosterEntries(self, true)) end
-- (rehacer las líneas de la lista en un fotograma aparte; lo usa Presence antes de mandar los cambios)
function HU:WarmRosterEntries() RosterEntries(self) end
HU.RosterSigNow = function() local _, sig = RosterEntries(HU) return sig end

-- Huella de una lista de conectados (sin la zona): con ella, los cambios valen aunque los mande
-- otro (en 4.x iban por número de envío y, al cambiar quién los mandaba, se pedía la lista entera)
local SigHash
-- huella de mi propia lista de conectados (la misma que calculan los demás al recibirla)
local myHash = {}
function HU:MyRosterHash()
    local _, sig = RosterEntriesFn(self)
    if myHash.sig ~= sig then myHash = { sig = sig, h = SigHash(sig) } end
    return myHash.h
end
-- La huella es la suma de la de cada uno: no depende del orden (antes había que ordenar a miles de
-- personas y juntarlas en un texto enorme, 20-30 ms de golpe) y la de quien no ha cambiado se recuerda
local entryHash, entryCount = {}, 0
local function EntryHash(k, v)
    local c = entryHash[k]
    if c and c.v == v then return c.h end
    local s = k .. "=" .. v
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    if not c then
        entryCount = entryCount + 1
        if entryCount > 50000 then entryHash, entryCount = {}, 1 end
        c = {}
        entryHash[k] = c
    end
    c.v, c.h = v, h
    return h
end
SigHash = function(sig)
    local total = 0
    for k, v in pairs(sig) do total = (total + EntryHash(k, v)) % 4294967296 end
    return string.format("%04x%04x", math.floor(total / 65536), math.floor(total % 65536))
end
local function MembersSigHash(members)
    local sig = {}
    for _, m in ipairs(members) do
        sig[(HU:Short(m.name):gsub("[~,;|]", " "))] = table.concat({ HU.CLASS_INDEX[m.class or ""] or 0, m.level or 0,
            m.rankIndex or m.rankHidden or "", m.afk and "a" or "" }, ",")
    end
    return SigHash(sig)
end
-- (el rango apartado de una lista sin confirmar también cuenta: la huella es la misma que la del que la manda)
HU.MembersSigHash = MembersSigHash

-- Zonas en el idioma de cada uno: el nombre que da el juego está en el idioma de quien la manda (en una lista
-- salían mitad en español y mitad en inglés). Se manda el número de su mapa («@1429», C_Map) y quien la recibe
-- pone el nombre de ese mapa en su idioma; la que no está en el mapa del juego va tal cual [+ARCHITECTURE.md]
local zoneIds
local function ZoneIds()
    if zoneIds then return zoneIds end
    local ids, any = {}, false
    local M = C_Map
    if M and M.GetMapChildrenInfo then
        local root = M.GetFallbackWorldMapID and M.GetFallbackWorldMapID() or 947
        local ok, maps = pcall(M.GetMapChildrenInfo, root, nil, true)
        for _, info in ipairs(ok and type(maps) == "table" and maps or {}) do
            local name = info.name
            if type(name) == "string" and name ~= "" and not HU.Secret(name) and not ids[name] then
                ids[name], any = info.mapID, true
            end
        end
    end
    -- (hasta que el juego tenga los mapas, se vuelve a mirar)
    if any then zoneIds = ids end
    return ids
end
function HU.ZoneOut(name)
    if type(name) ~= "string" or name == "" then return name end
    local id = ZoneIds()[name]
    return id and ("@" .. id) or name
end
function HU.ZoneIn(text)
    local id = type(text) == "string" and text:match("^@(%d+)$")
    if not id then return text end
    local get = C_Map and C_Map.GetMapInfo
    local ok, info = false, nil
    if get then ok, info = pcall(get, tonumber(id)) end
    local name = ok and type(info) == "table" and info.name or nil
    return (type(name) == "string" and name ~= "" and not HU.Secret(name)) and name or nil
end

-- la zona va como un código corto (#1, #2...) y cada código se explica una
-- sola vez ("#1=Orgrimmar"): con cientos de conectados, las listas ocupan bastante menos
local function CompactZones(entries)
    local out, codes, n = {}, {}, 0
    for _, en in ipairs(entries) do
        local pre, name, cls, lvl, rank, rest = en:match("^([%+]?)([^,]*),(%d*),(%d*),(%d*),?(.*)$")
        if not name or name == "" then
            out[#out + 1] = en
        else
            local zone, flags = rest, ""
            local z, fl = rest:match("^(.-),(%a*)$")
            if z then zone, flags = z, "," .. fl end
            if zone ~= "" then
                local c = codes[zone]
                if not c then
                    n = n + 1
                    c = "#" .. n
                    codes[zone] = c
                    out[#out + 1] = c .. "=" .. zone
                end
                zone = c
            end
            out[#out + 1] = pre .. table.concat({ name, cls, lvl, rank, zone }, ",") .. flags
        end
    end
    return out
end
HU.CompactZones = CompactZones

-- trocear en partes de ~200 bytes
local function Chunk(entries, max)
    max = max or 200
    local chunks, cur, size = {}, {}, 0
    for _, en in ipairs(entries) do
        if size + #en + 1 > max and #cur > 0 then
            chunks[#chunks + 1] = table.concat(cur, ";")
            cur, size = {}, 0
        end
        cur[#cur + 1] = en
        size = size + #en + 1
    end
    if #cur > 0 or #chunks == 0 then chunks[#chunks + 1] = table.concat(cur, ";") end
    return chunks
end

local buildCache = {}
function HU:BuildRosterMessages()
    if not self.myTag then return {} end
    NextSeq()
    local entries, sig = RosterEntries(self)
    -- (los trozos se guardan mientras la lista no cambie: con varias hermandades se rehacían para cada una)
    local chunks
    if buildCache.entries == entries then chunks = buildCache.chunks
    else
        -- (trozos de 170: quien la recibe por susurro la reenvía a su hermandad con su antigüedad, quién la
        -- hizo y el estado detrás, y así siempre cabe. Con 200 a veces no cabía y salía sin quién la hizo)
        chunks = Chunk(CompactZones(entries), 170)
        buildCache.entries, buildCache.chunks = entries, chunks
    end
    local msgs = {}
    for i, chunk in ipairs(chunks) do
        -- (detrás del número, con un punto, cuántos segundos llevo conectado: quien la recibe solo deja
        -- que la lista QUITE gente si la hizo alguien con su lista del juego ya bien cargada, 5 min)
        local up = math.max(0, math.floor(GetTime() - (self.loginT or GetTime())))
        msgs[#msgs + 1] = table.concat({ "RB", self.myTag, HU.B36(seqCounter) .. "." .. HU.B36(up), self.rosterTotal, self.rosterOnline, i, #chunks, chunk }, "~")
    end
    return msgs, seqCounter, sig
end

-- Lo último que se mandó a cada hermandad (para mandar después solo los cambios)
--   [etiqueta] = { seq = n, sig = { nombre = ... }, fullT = cuándo la lista entera, t = último envío }
local rosterState = {}
-- (quien pasa a ser enlace no sabe qué lista tienen ya las otras hermandades: pudo mandarles otra
-- quien lo fue un momento. Se olvida lo enviado y la próxima vuelta manda la lista entera)
function HU.ForgetRosterState() wipe(rosterState) end

function HU:SendRosterTo(target, fast)
    local rn = self:RankNamesMessage()
    if rn then self:Whisper(target, rn) end
    local msgs, seq, sig = self:BuildRosterMessages()
    -- (fast: solo si son pocos trozos, la lista de lanzamiento; una grande no se cuela en el chat)
    if #msgs > 3 then fast = nil end
    local p = self.remote[target:lower()]
    local gtag, dest = p and p.tag, target:lower()
    if gtag then self:DropQueued(gtag, dest) end
    HU.sendGroup = gtag and { tag = gtag, dest = dest } or nil
    for _, m in ipairs(msgs) do self:BulkWhisper(target, m, fast) end
    HU.sendGroup = nil
    if p and p.tag and seq then
        local now = GetTime()
        rosterState[p.tag] = { seq = seq, sig = sig, hash = SigHash(sig), fullT = now, t = now }
    end
end

-- Solo los cambios desde lo último que se mandó:  RC~ETIQ~seqBase~seqNueva~total~conectados~parte~partes~cambios [+ARCHITECTURE.md]
function HU:SendRosterDelta(target, st, fast)
    local list, sig, full = RosterEntries(self)
    local changes = {}
    for name, sg in pairs(sig) do if st.sig[name] ~= sg then changes[#changes + 1] = "+" .. full[name] end end
    for name in pairs(st.sig) do if not sig[name] then changes[#changes + 1] = "-" .. name end end
    if #changes == 0 then return true end
    if #changes > math.max(10, #list * 0.5) then return false end
    NextSeq()
    -- (trozos algo más pequeños: el mensaje lleva además la huella con la que queda la lista)
    local chunks = Chunk(CompactZones(changes), 160)
    local newHash = SigHash(sig)
    if #chunks > 2 then fast = nil end
    local tp = self.remote[target:lower()]
    HU.sendGroup = tp and tp.tag and { tag = tp.tag, dest = target:lower() } or nil
    for i, chunk in ipairs(chunks) do
        -- (al final, quién lo manda y la huella nueva: así cada uno sabe si su copia ha quedado bien)
        self:BulkWhisper(target, table.concat({ "RC", self.myTag, st.hash or SigHash(st.sig), HU.B36(seqCounter), self.rosterTotal, self.rosterOnline, i, #chunks, chunk, self:Short(self:Me() or ""), newHash }, "~"), fast)
    end
    HU.sendGroup = nil
    st.seq, st.sig, st.hash, st.t = seqCounter, sig, newHash, GetTime()
    return true
end
HU.RosterStateFor = function(tag) return rosterState[tag] end

-- Fase de lanzamiento: alguien de la lista de otra hermandad (oficial, enlace o ayudante) acaba de [+ARCHITECTURE.md]
local pushed = {}
local pushMin = { t = 0, n = 0 }
local function PushRoster(name, tries)
    if HU:BulkQueueSize() > 150 then
        if (tries or 0) < 3 then HU.After(30, function() PushRoster(name, (tries or 0) + 1) end) end
        return
    end
    local now = GetTime()
    if now - pushMin.t > 60 then pushMin.t, pushMin.n = now, 0 end
    if pushMin.n >= 20 then return end
    pushMin.n = pushMin.n + 1
    HU:SendRosterTo(name)
end
function HU:OnContactJoined(author)
    if not self.myTag then return end
    local name = author and self:FullName(author)
    if not name then return end
    local k = name:lower()
    for tag, r in pairs(self.remoteRoster) do
        if tag ~= self.myTag and r.byKey and r.byKey[k] then
            if self:HandlesTag(tag) and (not pushed[k] or GetTime() - pushed[k] > 60) then
                pushed[k] = GetTime()
                HU.After(5 + math.random() * 5, function() PushRoster(name) end)
            end
            return
        end
    end
end

-- Recién entrado: si me falta la lista de conectados de alguna hermandad, se la pido a su
-- contacto (si no, tendría que esperar a que la manden entera, cada 30 minutos)
local rfAsked = {}
local rfRetry = {}
function HU:AskMissingRosters()
    if not self.myTag then return end
    -- (la lista son unos pocos nombres: quien no la tiene la pide él mismo)
    -- (una hermandad por fotograma: buscar el contacto de todas las que faltan seguido llegaba a 4 ms)
    local n = 0
    for _, tag in ipairs(self:OtherTags()) do
        if not self.remoteRoster[tag] then
            n = n + 1
            HU.After(0.02 * (n - 1), function() HU:AskMissingRosterTag(tag) end)
        end
    end
end
function HU:AskMissingRosterTag(tag)
    if not self.myTag then return end
    local now = GetTime()
    do
        local p = not self.remoteRoster[tag] and self:BestPeer(tag)
        -- (fase de lanzamiento: la lista son unos pocos nombres; quien no la tiene la pide él mismo.
        -- El enlace que volvía de una desconexión se quedaba sin la de alguna hermandad)
        -- (quien vuelve de una desconexión ha perdido los contactos y el "mejor" puede ser cualquiera [+ARCHITECTURE.md]
        if p and not p.relay then
            rfRetry[tag] = (rfRetry[tag] or 0) + 1
            if rfRetry[tag] <= 4 then
                self:AskPeers({ tag })
                HU.After(8, function() HU:AskMissingRosters() end)
                p = nil
            end
        elseif p then
            rfRetry[tag] = 0
        end
        if p and (not rfAsked[tag] or now - rfAsked[tag] > 60) then
            rfAsked[tag] = now
            self:Whisper(p.name, "RF~" .. self.myTag, true)
        end
    end
end

-- Recién entrado: a los contactos guardados de cada hermandad de la que no tengo lista confirmada les [+ARCHITECTURE.md]
local savedAsked = {}
-- late = la vuelta de los rasos: solo si a esas alturas sigue sin confirmar (lo normal es que antes la
-- haya confirmado y repartido un enlace, ayudante u oficial), y a un solo contacto comprobado
function HU:AskSavedContacts(late)
    if not self.myTag or not IsInGuild() or not self.cfg or not self.db then return end
    local _, onlineNow = GetNumGuildMembers()
    -- (quien puede repartir la lista confirmada a su hermandad pregunta primero; los rasos, después)
    local sharer = self:CanOfficer() or self:IsRelay() or (self:RosterSlot() ~= nil)
    local wide = sharer or (tonumber(onlineNow) or 0) <= 1
    if late == nil and not wide then return end
    if late and wide then return end
    local me = self:MeKey()
    for _, tag in ipairs(self:OtherTags()) do
        local s = HU.RosterStateOf(tag)
        -- Contactos comprobados (no antiguos) de esa hermandad: con ellos cualquiera, también un raso, [+ARCHITECTURE.md]
        local full = {}
        for k, e in pairs((self.db.peers or {})[tag] or {}) do
            if type(e) == "table" and type(e.name) == "string" and k ~= me and not e.old then full[#full + 1] = e end
        end
        -- (idea de Olympus: si otro de mi hermandad la ha pedido o ha pasado por ella hace menos de 30 s,
        -- no la pido a los antiguos: llega a todos por GUILD. Así no se multiplican las peticiones)
        local busy = (#full == 0) and HU.GuildAskedRecently(tag, 30)
        if s ~= "c" and (wide or #full > 0) and not busy and not (self:RosterTrusted(tag)) and (savedAsked[tag] or 0) < 4 then
            local list = {}
            if wide then
                for k, e in pairs((self.db.peers or {})[tag] or {}) do
                    if type(e) == "table" and type(e.name) == "string" and k ~= me then list[#list + 1] = e end
                end
            else
                list = full
            end
            -- (primero los comprobados y luego los antiguos; dentro de cada grupo, los más recientes)
            table.sort(list, function(a, b)
                if (not a.old) ~= (not b.old) then return not a.old end
                return (a.t or 0) > (b.t or 0)
            end)
            if #list > 0 then
                savedAsked[tag] = (savedAsked[tag] or 0) + 1
                for i = 1, math.min(late and 1 or 2, #list) do self:Whisper(list[i].name, "RF~" .. self.myTag .. "~2", true) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- quien acaba de entrar pide primero a SU hermandad lo que le falta [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local nqSeen = {}      -- [R/W..etiqueta] = cuándo las pidió otro de mi hermandad
local rbInGuild = {}   -- [tag] = cuándo pasó por GUILD su lista entera
-- (en una sola tabla: la parte principal del archivo no puede pasar de 200 variables locales) [+ARCHITECTURE.md]
local listSeen = { sig = {}, force = {}, GAP = 10 }
-- need: cuándo entró el último compañero o alguien pidió listas (NQ): lo que pasó antes no le llegó a él
function HU.ListNeeded() listSeen.need = GetTime() end
-- Huella de la copia de una hermandad, guardada en la copia hasta que cambie (número de envío, hora de la
-- última actualización y cuántos son): antes se calculaba dos veces en cada reparto, recorriendo a todos
function listSeen.Sig(r)
    local c = r._sigC
    if c and c.m == r.members and c.n == #r.members and c.u == r.updated and c.s == r.seq then return c.sig end
    local sig = MembersSigHash(r.members)
    r._sigC = { m = r.members, n = #r.members, u = r.updated, s = r.seq, sig = sig }
    return sig
end
-- Id de un trozo de la lista de una hermandad: trozo · número de envío de quien la hizo · huella. Hoy hay [+ARCHITECTURE.md]
local lastNQ, nqTry = -999, 0
local nqAsked = {}
local function Recent(key) return nqSeen[key] and GetTime() - nqSeen[key] < 120 end
-- ¿La ha pedido alguien de mi hermandad (NQ), o ha pasado entera por GUILD, hace menos de secs?
HU.GuildAskedRecently = function(tag, secs)
    local now = GetTime()
    local a, b = nqSeen["R" .. tag], rbInGuild[tag]
    return (a and now - a < secs) or (b and now - b < secs) or false
end
function HU:AskGuildForMissing()
    -- (el primer minuto tras entrar, como mucho cada 5 s: las listas tienen que llegar pronto)
    local brake = (GetTime() - (self.loginT or 0) < 60) and 5 or 20
    if not self.myTag or not IsInGuild() or GetTime() - lastNQ < brake then return end
    local r, w = {}, {}
    local need = self.rosterNeed or {}
    local now = GetTime()
    -- (la misma hermandad, como mucho cada 2 minutos: la respuesta puede tardar en llegar)
    for _, tag in ipairs(self:OtherTags()) do
        if (not self.remoteRoster[tag] or need[tag]) and not Recent("R" .. tag) and (nqTry < 3 or not nqAsked["R" .. tag] or now - nqAsked["R" .. tag] > 120) then
            r[#r + 1] = tag
            nqAsked["R" .. tag] = now
        end
    end
    if #r == 0 and #w == 0 then return end
    lastNQ = GetTime()
    nqTry = nqTry + 1
    -- (cada intento le toca a otro: por si al primero le faltaba también)
    self:Send(HU.Utf8Cut("NQ~" .. nqTry .. "~R:" .. table.concat(r, ",") .. "~W:" .. table.concat(w, ","), 250), "GUILD", nil, true)
end

-- ¿Me toca contestar por esta hermandad? (el enlace y sus ayudantes se las reparten)
function HU:ResponsibleFor(tag, exclude, shift)
    -- (el enlace va el último: su cola va cargada y lo que manda llegaba ~3 s tarde. Si no tiene
    -- ayudantes, se encarga él de todas)
    local pool = {}
    if self:IsRelay() then
        for _, n in ipairs(self.advertisedHelpers or {}) do pool[#pool + 1] = n end
        pool[#pool + 1] = self:Short(self:Me() or "")
    else
        local h = self.relayHelpers
        if not h or GetTime() - h.t > 700 then return false end
        for _, n in ipairs(h.list) do pool[#pool + 1] = n end
        pool[#pool + 1] = self:Short(h.relay or "")
    end
    -- quien pregunta no cuenta (le falta)
    if exclude then
        local ex = self:Short(exclude):lower()
        for i = #pool, 1, -1 do if pool[i]:lower() == ex then table.remove(pool, i) end end
    end
    if #pool == 0 then return false end
    local tags = self:OtherTags()
    table.sort(tags)
    local me = self:Short(self:Me() or ""):lower()
    for j, t in ipairs(tags) do
        if t == tag then return (pool[((j - 1 + (shift or 0)) % #pool) + 1] or ""):lower() == me end
    end
    return false
end

-- La lista de conectados de otra hermandad, tal como la tengo, a toda mi hermandad
function HU:SendStoredRoster(tag, force)
    local r = self.remoteRoster[tag]
    if not r or not r.seq then return end
    -- (la misma lista que acaba de pasar por GUILD no se vuelve a mandar, y con prisa como mucho una vez [+ARCHITECTURE.md]
    local now, mySig = GetTime(), listSeen.Sig(r)
    local seen = listSeen.sig[tag]
    if seen and seen.sig == mySig and now - seen.t < listSeen.GAP and seen.t >= (listSeen.need or 0) then return end
    if force and listSeen.force[tag] and now - listSeen.force[tag] < listSeen.GAP then return end
    -- (la misma lista entera, como mucho cada 10 minutos: los cambios ya llegan al momento. [+ARCHITECTURE.md]
    local gap = 10
    if not force and rbInGuild[tag] and GetTime() - rbInGuild[tag] < gap then return end
    -- (se apunta como mandada solo aquí, cuando de verdad sale)
    if force then listSeen.force[tag] = now end
    listSeen.sig[tag] = { sig = mySig, t = now }
    rbInGuild[tag] = GetTime()
    local entries = {}
    for _, m in ipairs(r.members) do
        -- (la línea de cada uno se guarda en su ficha y solo se rehace si cambia algo)
        local c = m._rb
        if not (c and c.n == m.name and c.c == m.class and c.l == m.level and c.r == (m.rankIndex or m.rankHidden) and c.z == m.zone and c.a == m.afk) then
            local zone = HU.Utf8Cut((tostring(HU.ZoneOut(m.zone) or "")):gsub("[~,;|]", " "), 24)
            c = { n = m.name, c = m.class, l = m.level, r = m.rankIndex or m.rankHidden, z = m.zone, a = m.afk,
                line = table.concat({ (self:Short(m.name):gsub("[~,;|]", " ")), HU.CLASS_INDEX[m.class or ""] or 0,
                    m.level or 0, m.rankIndex or m.rankHidden or "", zone .. (m.afk and ",a" or "") }, ",") }
            m._rb = c
        end
        entries[#entries + 1] = c.line
    end
    local chunks = Chunk(CompactZones(entries))
    -- (al final, cuántos segundos tiene mi copia: quien tenga una más nueva no deja que esta la pise; [+ARCHITECTURE.md]
    local age = math.max(0, math.floor(GetTime() - (r.updated or GetTime())))
    local origin = r.origin and self:Short(r.origin) or ""
    local state = HU.RosterStateOf(r) or "b"
    -- (y la huella de mi copia, al final: dos copias con el mismo número de envío y del mismo origen
    -- pueden no ser iguales, y entonces ninguna pisa a la otra; ver HU.comm.RB. Si no cabe, sin ella)
    local sig = mySig
    for i, c in ipairs(chunks) do
        -- (con los segundos que llevaba conectado quien la hizo, si lo sé: así mi hermandad la trata igual)
        local msg = table.concat({ "RB", tag, HU.B36(r.seq) .. (r.up and ("." .. HU.B36(r.up)) or ""), r.total or 0, r.online or #r.members, i, #chunks, c, age, origin, state }, "~")
        if #msg + #sig + 1 <= 250 then msg = msg .. "~" .. sig end
        self:Send(msg, "GUILD")
    end
end

-- Quien entra suelto tiene que tener las listas de todas las hermandades en 5-10 s. En cuanto el juego [+ARCHITECTURE.md]
local WELCOME_DELAY, WELCOME_GAP = 1, 10
local welcomeAt = {}   -- [tag] = cuándo sale (o salió) el último reparto por bienvenida
function HU:WelcomeGuildmate()
    if not self.myTag or not self.cfg then return end
    local now = GetTime()
    for _, tag in ipairs(self:OtherTags()) do
        local r = self.remoteRoster[tag]
        -- (el enlace, para las que no le tocan, solo de reserva: a los 2 s si aún no ha pasado por GUILD)
        if r and r.seq and not r.weak and self:IsRelay() and not self:ResponsibleFor(tag) then
            HU.After(WELCOME_DELAY + 2, function()
                if not (rbInGuild[tag] and GetTime() - rbInGuild[tag] < 2.5) then HU:SendStoredRoster(tag, true) end
            end)
        elseif r and r.seq and not r.weak and self:ResponsibleFor(tag) then
            local last = welcomeAt[tag]
            -- (si ya hay uno programado que llega a tiempo para este, no se programa otro)
            if not (last and last >= now) then
                -- (fuera de la fase de lanzamiento la lista es de todos los conectados, cientos de nombres:
                -- entonces, como mucho cada 5 minutos)
                local gap = WELCOME_GAP
                local at = math.max(now + WELCOME_DELAY, (last or -999) + gap)
                welcomeAt[tag] = at
                HU.After(at - now + math.random() * 0.5, function() HU:SendStoredRoster(tag, true) end)
            end
        end
    end
end
-- Cuántos «X se ha conectado» he visto en los últimos secs: con pocos es el día a día (se contesta y se
-- pregunta al momento); con muchos, una entrada masiva (se reparte al azar para no mandar cientos a la vez)
local loginTimes = {}
HU.QuietLogins = function(secs)
    local now, n = GetTime(), 0
    for i = #loginTimes, 1, -1 do
        if now - loginTimes[i] > 30 then table.remove(loginTimes, i)
        elseif now - loginTimes[i] <= (secs or 10) then n = n + 1 end
    end
    return n <= 3
end
HU:On("CHAT_MSG_SYSTEM", function(text)
    if type(text) ~= "string" or not HU.PresencePatterns then return end
    for _, p in ipairs(HU.PresencePatterns()) do
        local name = p.on and text:match(p.pat)
        if name and #loginTimes < 400 then loginTimes[#loginTimes + 1] = GetTime() end
        if name and not HU.myTag then return end
        if name then
            name = name:match("^|Hplayer:([^|:]+)") or name
            local k = HU:Key(name)
            if k and k ~= HU:MeKey() and HU.roster[k] then HU:WelcomeGuildmate() end
            return
        end
    end
end)

-- Me falta (o tengo a medias) la lista de conectados de esa hermandad: se pide a mi hermandad
function HU:NeedRoster(tag)
    self.rosterNeed = self.rosterNeed or {}
    self.rosterNeed[tag] = true
    HU.After(1 + math.random() * 8, function() HU:AskGuildForMissing() end)
end

HU:RegisterMessage("NQ", { combat = "req" })
HU.comm.NQ = function(self, sender, f, dist)
    if dist ~= "GUILD" then return end
    -- (alguien pide listas: las que pasaron antes por GUILD no le llegaron a él)
    if self:Key(sender) ~= self:MeKey() then HU.ListNeeded() end
    local try = tonumber(f[1]) or 1
    for _, fld in ipairs(f) do
        local kind, list = fld:match("^(%a):(.*)$")
        for tag in (list or ""):gmatch("[^,]+") do if kind then nqSeen[kind .. tag] = GetTime() end end
    end
    for _, fld in ipairs(f) do
        local kind, list = fld:match("^(%a):(.*)$")
        for tag in (list or ""):gmatch("[^,]+") do
            -- (día a día: quien contesta lleva más de 5 min conectado y tiene la copia confirmada. Entonces [+ARCHITECTURE.md]
            local function quiet(secs) return not (rbInGuild[tag] and GetTime() - rbInGuild[tag] < secs) end
            local fast = GetTime() - (self.loginT or GetTime()) > 300
                and HU.RosterStateOf(self.remoteRoster[tag]) == "c"
            local own = tag ~= self.myTag and self.cfg and self.cfg.byTag[tag]
            if own and self:ResponsibleFor(tag, sender, try - 1) then
                if kind == "R" and self.remoteRoster[tag] then
                    if fast then HU.After(0.1, function() HU:SendStoredRoster(tag, quiet(2)) end)
                    else HU.After(0.5 + math.random() * 2, function() HU:SendStoredRoster(tag) end) end
                end
            elseif kind == "R" and tag ~= self.myTag and self.remoteRoster[tag] and self:IsRelay() then
                -- (si al que le tocaba también le falta, la manda el enlace, que las tiene todas)
                if fast then HU.After(0.6, function() if quiet(0.6) then HU:SendStoredRoster(tag, true) end end)
                else HU.After(8 + math.random() * 4, function() if quiet(15) then HU:SendStoredRoster(tag) end end) end
            elseif fast and own and kind == "R" and self.remoteRoster[tag] and self:ResponsibleFor(tag, sender, try) then
                HU.After(2, function() if quiet(2) then HU:SendStoredRoster(tag, true) end end)
            end
        end
    end
end

-- Lista que alguien de confianza de mi hermandad reparte como confirmada («c»: un oficial con /gu [+ARCHITECTURE.md]
local function PromoteSameOrigin(self, tag, mine, origin, pt, dist)
    if dist ~= "GUILD" or pt.weak or pt.flag ~= "c" or not (mine and origin and mine.origin) then return end
    if mine.origin:lower() ~= origin:lower() or HU.RosterStateOf(mine) == "c" then return end
    self:SetRosterState(tag, "c", "confirmada por mi hermandad")
end

-- Lista confirmada que ya no cuadra con la que llega (ha cambiado quien la lleva: el enlace nuevo no [+ARCHITECTURE.md]
local memberAsked = {}
local function AskListMember(self, tag, exceptK)
    local r = self.remoteRoster[tag]
    if not (self.myTag and r and r.members) or HU.RosterStateOf(r) ~= "c" then return end
    if memberAsked[tag] and GetTime() - memberAsked[tag] < 60 then return end
    local originK = r.origin and self:Key(r.origin)
    local me = self:MeKey()
    local pick, pickRank
    for _, m in ipairs(r.members) do
        local k = m.key or (m.name and m.name:lower())
        if k and k ~= exceptK and k ~= originK and k ~= me then
            local rk = m.rankIndex or 99
            if not pick or rk < pickRank then pick, pickRank = m.name, rk end
        end
    end
    if not pick then return end
    memberAsked[tag] = GetTime()
    self:Whisper(pick, "RF~" .. self.myTag .. "~2", true)
end

local partial = {}  -- [tag] = { seq, parts = {}, got }

-- Índice por nombre de la lista de conectados de otra hermandad (con 20 hermandades,
-- recorrer miles de nombres en cada mensaje del chat era lo que más costaba)
local function IndexRoster(r)
    local byKey = {}
    for _, m in ipairs(r.members) do byKey[m.name:lower()] = m end
    r.byKey = byKey
    return r
end
HU.IndexRoster = IndexRoster

-- Una línea de la lista de conectados -> miembro
-- los códigos de zona que vienen en una lista ("#1=Orgrimmar")
local function ZoneDict(parts, nparts)
    local dict = {}
    for i = 1, nparts do
        for code, zone in (parts[i] or ""):gmatch("(#%d+)=([^;]*)") do dict[code] = zone end
    end
    return dict
end

local function ParseRosterEntry(self, en, tag, dict)
    if en:sub(1, 1) == "#" then return nil end
    local name, cls, lvl, rank, zone = en:match("^([^,]*),(%d*),(%d*),(%d*),?(.*)$")
    if not HU.SafeName(name) then return nil end
    if zone then zone = zone:gsub("[|%c]", "") end
    local afk = false
    if zone then
        local z, flags = zone:match("^(.-),(%a*)$")
        if z then zone, afk = z, flags:find("a", 1, true) ~= nil end
        if dict and dict[zone] then zone = dict[zone] end
        -- (el número de mapa, con el nombre en mi idioma)
        zone = HU.ZoneIn(zone)
    end
    return {
        name = self:FullName(name),
        class = HU.CLASSES[tonumber(cls) or 0],
        level = tonumber(lvl) or 0,
        rankIndex = tonumber(rank),
        zone = zone,
        online = true,
        afk = afk,
        tag = tag,
    }
end
HU.ZoneDict, HU.ParseRosterEntry = ZoneDict, ParseRosterEntry

-- Lo que ya ha llegado de una lista entera que viene en varios trozos: solo para el panel, que va [+ARCHITECTURE.md]
HU.partialRoster = {}
function HU.ShowPartialRoster(self, tag, pt, nparts)
    local dict = ZoneDict(pt.parts, nparts)
    local members = {}
    for i = 1, nparts do
        for en in (pt.parts[i] or ""):gmatch("[^;]+") do
            local m = ParseRosterEntry(self, en, tag, dict)
            if m then
                -- (la zona puede venir en un trozo que aún no ha llegado)
                if m.zone and m.zone:match("^#%d+$") then m.zone = nil end
                members[#members + 1] = m
            end
        end
    end
    local old = HU.partialRoster[tag]
    HU.partialRoster[tag] = { members = members, t = GetTime(), v = (old and old.v or 0) + 1 }
    self:Changed("members")
    -- (si no llega el resto, deja de enseñarse con la lista a medias)
    HU.After(600, function()
        local p = HU.partialRoster[tag]
        if p and GetTime() - p.t >= 590 then HU.partialRoster[tag] = nil; HU:Changed("members") end
    end)
end

-- Un paquete de cambios (+entra / -sale) sobre la copia r de la lista de esa hermandad.
-- Devuelve los nombres que han entrado.
local recentDeltas = {} -- [tag] = los últimos paquetes de cambios recibidos (3 min)
local LATE_FIX_FOR = 30 -- cambios que se vuelven a aplicar sobre una lista repartida con uno de menos (s)
local lateShared = {}   -- [tag] = cuándo repartí yo la lista corregida
local KEEP_FOR = 60     -- lo que una lista no fiable no puede quitar, se queda como mucho esto (s)

-- La huella de la lista sin quien se queda solo por KEEP_FOR: es la que tienen los demás
local function HashNoKept(members)
    local any = false
    for _, m in ipairs(members) do if m.keptT then any = true break end end
    if not any then return MembersSigHash(members) end
    local out = {}
    for _, m in ipairs(members) do if not m.keptT then out[#out + 1] = m end end
    return MembersSigHash(out)
end
HU.HashNoKept = HashNoKept

-- Quita de mi copia a quien se quedó solo porque la última lista no era fiable y ya lleva KEEP_FOR s sin
-- que ninguna lista ni cambio lo vuelva a traer
local function DropKept(self, tag)
    local r = self.remoteRoster[tag]
    if not r or not r.members then return end
    local n = #r.members
    for i = n, 1, -1 do
        local m = r.members[i]
        if m.keptT and GetTime() - m.keptT >= KEEP_FOR then table.remove(r.members, i) end
    end
    if #r.members == n then return end
    IndexRoster(r)
    r.online = math.min(r.online or #r.members, #r.members)
    r.sigHash = nil
    local st = self.bootState[tag]
    if st then st.hash = MembersSigHash(r.members) end
    self:Changed("members")
end
local verifyAsked = {}  -- [tag] = cuándo se pidió la segunda opinión al enlace de esa hermandad
local sigAsked = {}     -- [tag] = cuándo se pidió la entera por dos copias del mismo envío distintas
local earlyRB, earlyWait = {}, false   -- trozos de RB por GUILD que llegan antes de tener configuración
-- st: la hora del servidor del cambio (su número de envío). Cada miembro guarda la de su último cambio [+ARCHITECTURE.md]
function HU.ApplyRosterDelta(self, r, tag, parts, nparts, st)
    local index = {}
    for i, m in ipairs(r.members) do index[self:Short(m.name):lower()] = i end
    local removed, added = {}, {}
    local dict = ZoneDict(parts, nparts)
    for i = 1, nparts do
        for en in (parts[i] or ""):gmatch("[^;]+") do
            local op, rest = en:sub(1, 1), en:sub(2)
            if op == "-" then
                local i2 = index[rest:lower()]
                local cur = i2 and r.members[i2]
                if i2 and not (st and cur and cur.st and cur.st > st) then removed[i2] = true end
            elseif op == "+" then
                local m = ParseRosterEntry(self, rest, tag, dict)
                if m then m.st = st end
                local i2 = m and index[self:Short(m.name):lower()]
                local cur = i2 and r.members[i2]
                if m and st and cur and cur.st and cur.st > st then m = nil end -- (ya sé algo más nuevo de él)
                if m then
                    if i2 then r.members[i2] = m; removed[i2] = nil
                    else r.members[#r.members + 1] = m; index[self:Short(m.name):lower()] = #r.members; added[#added + 1] = m.name end
                    -- (sin confirmar, el que entra queda igual que los demás de la lista y no deja su
                    -- rango guardado)
                    local s = HU.RosterStateOf(r)
                    if s == "b" then m.weak = true end
                    if (s == "b" or s == "m") and m.rankIndex then m.rankHidden, m.rankIndex = m.rankIndex, nil end
                    if s == "c" and m.rankIndex then
                        self.db.rankCache = self.db.rankCache or {}
                        self.db.rankCache[m.name:lower()] = { tag = tag, idx = m.rankIndex, t = time() }
                    end
                end
            end
        end
    end
    if next(removed) then
        local keep = {}
        for i, m in ipairs(r.members) do if not removed[i] then keep[#keep + 1] = m end end
        r.members = keep
    end
    -- (la huella guardada ya no vale: un cambio de rango, nivel o ausente no cambia cuántos son ni la tabla,
    -- y se repartía la huella vieja; los demás veían otra huella con el mismo envío y no tomaban la lista)
    r._sigC, r.sigHash = nil, nil
    return added
end

HU:RegisterMessage("RB", { tagField = 1, bootstrap = true, remoteData = true, queue = "bulk", ttl = 600, combat = "list" })
HU.comm.RB = function(self, sender, f, dist, raw)
    local seqTxt, upTxt = (f[2] or ""):match("^(%w+)%.?(%w*)$")
    local tag, seq, total, online, part, nparts = f[1], tonumber(seqTxt or "", 36), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
    -- (cuántos segundos llevaba conectado quien la hizo; nil si no lo dice)
    local originUp = upTxt and upTxt ~= "" and tonumber(upTxt, 36) or nil
    -- (recién entrado: por GUILD me llega la bienvenida antes de saber mi hermandad o la comunidad. Se
    -- guarda y se aplica en cuanto lo sé, en vez de perderla; como mucho 60 trozos y 30 s)
    if dist == "GUILD" and (not self.myTag or not self.cfg) then
        if #earlyRB < 60 then earlyRB[#earlyRB + 1] = { sender, f, dist, raw } end
        if not earlyWait then
            earlyWait = true
            local tries = 0
            local function retry()
                tries = tries + 1
                if HU.myTag and HU.cfg then
                    local l = earlyRB
                    earlyRB, earlyWait = {}, false
                    -- (por la entrada normal, para que se vuelva a mirar quién la manda: forwarder o débil)
                    for _, e in ipairs(l) do HU:SafeCall("RB", HU.OnAddonMessage, HU.PREFIX, e[4], e[3], e[1]) end
                elseif tries < 60 then HU.After(0.5, retry)
                else earlyRB, earlyWait = {}, false end
            end
            HU.After(0.5, retry)
        end
        return
    end
    if not tag or tag == self.myTag or not self.cfg or not self.cfg.byTag[tag] then return end
    if not (seq and part and nparts) or part < 1 or part > nparts or nparts > 250 then return end
    -- (por GUILD, una lista sin quién la hizo NI estado no se acepta: todos los addons la reenvían con los [+ARCHITECTURE.md]
    if dist == "GUILD" and (f[9] == nil or f[9] == "") and (f[10] == nil or f[10] == "") then return end
    local data = f[7] or ""

    if dist == "GUILD" and part == 1 then
        rbInGuild[tag] = GetTime()
        -- (qué lista ha pasado por GUILD: así nadie manda otra igual en los 10 s siguientes)
        if f[11] and f[11] ~= "" then listSeen.sig[tag] = { sig = f[11], t = GetTime() } end
    end
    local fwdFlag
    -- quien lo recibe por susurro lo reparte a su hermandad
    if dist == "WHISPER" then
        rbInGuild[tag] = GetTime()
        self:SeenPeer(sender, tag)
        local p = self.remote[sender:lower()]
        if p then p.last = GetTime() end
        -- (una lista de alguien comprobado de esa hermandad: el enlace provisional por presentación, si
        -- es otro, deja de guardar el sitio; ver PROV_HOLD)
        local ak = (self.acceptKind[tag] or {})[self:Key(sender) or ""]
        if (ak == "member" or ak == "peer" or ak == "vouched") and HU.ClearProvRelay then HU.ClearProvRelay(tag, sender:lower()) end
        -- (con su antigüedad, 0, quién la hizo, para que mis compañeros puedan comparar números de envío, [+ARCHITECTURE.md]
        local kind = (self.acceptKind[tag] or {})[self:Key(sender) or ""]
        local cs = HU.RosterStateOf(self.remoteRoster[tag])
        fwdFlag = ((kind == "peer" or kind == "vouched") and "c") or (kind == "member" and cs) or "b"
        local full = raw .. "~0~" .. self:Short(sender) .. "~" .. fwdFlag
        local short = raw .. "~0~~" .. fwdFlag
        -- (la lista de lanzamiento, 1-3 trozos, también al momento: es la que llega cuando cambia
        -- quién manda los cambios)
        local fast = (nparts <= 3) or nil
        if #full <= 250 then self:Send(full, "GUILD", nil, nil, nil, fast)
        elseif #short <= 250 then self:Send(short, "GUILD", nil, nil, nil, fast)
        elseif fwdFlag == "c" then self:Send(raw, "GUILD", nil, nil, nil, fast) end
    end

    -- (puede haber dos listas llegando a la vez: cada una se junta por separado) [+ARCHITECTURE.md]
    local pkey = tag .. ":" .. seq .. ":" .. sender:lower()
    local pt = partial[pkey]
    if not pt then
        if not HU.PartialAdmit(partial, sender, dist) then return end
        pt = { seq = seq, parts = {}, got = 0, t = GetTime(), by = sender:lower(), g = (dist == "GUILD") or nil }
        partial[pkey] = pt
        for k, v in pairs(partial) do if GetTime() - (v.last or v.t or 0) > 600 then partial[k] = nil end end
        -- (si a los 40 s sigue a medias, se ha perdido algún trozo: se pide a [+ARCHITECTURE.md]
        local quietMax = 15
        local function check()
            if partial[pkey] ~= pt then return end
            -- (con las colas cargadas los trozos pueden tardar: 2 minutos sin ninguno)
            -- (se pide a la hermandad, pero lo recibido se guarda: puede llegar la rodaja que falta)
            local quiet = GetTime() - (pt.last or pt.t)
            if quiet >= 600 then partial[pkey] = nil
            elseif quiet >= quietMax and not pt.asked then
                pt.asked = true
                HU:NeedRoster(tag)
                if pt.wName then
                    local to = pt.wName
                    HU.After(math.random() * 2, function() HU:Whisper(to, "RF~" .. (HU.myTag or "") .. "~1", true) end)
                end
                HU.After(60, check)
            else HU.After(math.min(30, quietMax), check) end
        end
        HU.After(quietMax + 5, check)
    end
    pt.last = GetTime()
    if not pt.parts[part] then
        pt.parts[part] = data
        pt.got = pt.got + 1
        if HU.weakMsg then pt.weak = true end
    end
    -- (quien me susurró algún trozo decide el estado; los demás toman el que dicen los trozos que
    -- reparte mi hermandad, el más restrictivo si no coinciden)
    if dist == "WHISPER" then
        pt.wFrom, pt.wName = self:Key(sender), sender
        if fwdFlag and (not pt.fwdFlag or HU.STATE_RANK[fwdFlag] < HU.STATE_RANK[pt.fwdFlag]) then pt.fwdFlag = fwdFlag end
    else
        local fl = f[10]
        if fl and HU.STATE_RANK[fl] and (not pt.flag or HU.STATE_RANK[fl] < HU.STATE_RANK[pt.flag]) then pt.flag = fl end
    end
    if pt.got < nparts then
        if not pt.weak then HU.ShowPartialRoster(self, tag, pt, nparts) end
        return
    end
    HU.partialRoster[tag] = nil
    -- (ya está la de verdad: fuera la gris de la última vez)
    self:DropGhost(tag)

    local members = {}
    local dict = ZoneDict(pt.parts, nparts)
    for i = 1, nparts do
        for en in (pt.parts[i] or ""):gmatch("[^;]+") do
            local m = ParseRosterEntry(self, en, tag, dict)
            if m and pt.weak then
                -- (de un compañero cualquiera: sin rango)
                m.rankIndex, m.weak = nil, true
            end
            if m then members[#members + 1] = m end
        end
    end
    partial[pkey] = nil
    -- (una lista débil no pisa una buena)
    if pt.weak and self.remoteRoster[tag] and not self.remoteRoster[tag].weak then return end
    if self.rosterNeed then self.rosterNeed[tag] = nil end
    -- Una lista repartida dentro de mi hermandad dice cuántos segundos tiene. Si la mía es más nueva [+ARCHITECTURE.md]
    local age = (dist == "GUILD") and tonumber(f[8]) or nil
    local mine = self.remoteRoster[tag]
    -- Quién hizo esta lista: quien me la susurra, o el que dice el compañero que la reparte
    local origin
    if dist == "WHISPER" then origin = self:FullName(sender)
    elseif f[9] and f[9] ~= "" then origin = self:FullName(f[9]) end
    -- Del mismo origen y con un número de envío más bajo que la mía: es más vieja (cada origen numera [+ARCHITECTURE.md]
    local theirSig = (dist == "GUILD") and f[11] or nil
    if theirSig and theirSig ~= "" and mine and not mine.weak and mine.members and origin and mine.origin
        and mine.seq == seq and mine.origin:lower() == origin:lower() and HashNoKept(mine.members) ~= theirSig then
        if (self:IsRelay() or self:ResponsibleFor(tag)) and (not sigAsked[tag] or GetTime() - sigAsked[tag] > 60) then
            sigAsked[tag] = GetTime()
            local rp = self:KnownRelay(tag) or self:BestPeer(tag)
            if rp then
                local to = rp.name
                HU.After(1 + math.random() * 2, function() HU:Whisper(to, "RF~" .. (HU.myTag or "") .. "~1", true) end)
            end
        end
        PromoteSameOrigin(self, tag, mine, origin, pt, dist)
        return
    end
    -- (más vieja que la mía, venga de quien venga: el número es la hora del servidor de cuando se hizo, [+ARCHITECTURE.md]
    local older = mine and not mine.weak and mine.seq and seq < mine.seq
    if older and dist == "GUILD" then
        local heard = rbInGuild[tag]
        HU.After(1 + math.random() * 4, function()
            if rbInGuild[tag] ~= heard then return end -- (otro ya la ha corregido)
            HU:SendStoredRoster(tag, true)
        end)
    end
    if age and mine and not mine.weak and mine.updated and (GetTime() - mine.updated) + 5 < age then
        PromoteSameOrigin(self, tag, mine, origin, pt, dist)
        local heard = rbInGuild[tag]
        HU.After(1 + math.random() * 4, function()
            if rbInGuild[tag] ~= heard then return end -- (otro ya la ha corregido)
            HU:SendStoredRoster(tag, true)
        end)
        return
    end
    -- (la huella se calcula cuando haga falta, no ahora: así la lista entera no da un tirón al llegar)
    local nr = { members = members, total = total or 0, online = online or #members, updated = GetTime() - (age or 0), seq = seq, weak = pt.weak or nil, origin = origin, up = originUp }
    -- (cada miembro, con la hora de la lista: un cambio posterior a ella gana, uno anterior no la toca)
    for _, m in ipairs(members) do m.st = seq end
    -- Con qué estado se guarda (ver «Estado de la lista» junto a SeenPeer)
    local state, fwdK
    if pt.wFrom then
        nr.origin = self:FullName(pt.wName) or nr.origin
        IndexRoster(nr)
        state = self:DecideRoster(tag, pt.wFrom, (self.acceptKind[tag] or {})[pt.wFrom], nr)
        if not state then AskListMember(self, tag, pt.wFrom) return end
    elseif not pt.weak then
        state = pt.flag or HU.RosterStateOf({})
        -- (un reenvío tal cual lleva el estado con que lo tomó quien lo reenvía, que puede saber menos que [+ARCHITECTURE.md]
        local cs = mine and not mine.weak and HU.RosterStateOf(mine)
        if cs and pt.flag and HU.STATE_RANK[pt.flag] and HU.STATE_RANK[cs] > HU.STATE_RANK[pt.flag]
            and f[8] == "0" and (f[11] == nil or f[11] == "") then
            IndexRoster(nr)
            if HashNoKept(nr.members) == HashNoKept(mine.members) then state = cs end
        end
        -- (confirmada por alguien de confianza de mi hermandad, p. ej. un oficial con /gu confirmar: si
        -- yo llevaba el reloj de esa hermandad, se para, para que no la vuelva a bajar)
        if pt.flag == "c" then
            self.bootState[tag] = nil
            self.rosterTrust[tag] = GetTime()
        elseif self.bootState[tag] and origin and f[8] == "0" and (f[11] == nil or f[11] == "") then
            -- (yo llevo el reloj de esa hermandad y esta lista es un reenvío tal cual de un compañero de [+ARCHITECTURE.md]
            local ok = self:Key(origin)
            local kind = ok and ok ~= self:MeKey() and self:SenderKind(origin, tag)
            if kind then
                IndexRoster(nr)
                local s2 = self:DecideRoster(tag, ok, kind, nr)
                if s2 then state, fwdK = s2, ok end
            end
        end
    end
    -- Junta con la mía, nombre a nombre (lo pidió Jorge: que no desaparezca nadie). Cada uno lleva la hora [+ARCHITECTURE.md]
    if mine and mine.members and mine ~= nr then
        -- (fiable: confirmada, y quien la hizo sale en MI copia de su hermandad conectado desde hace ≥5 min, [+ARCHITECTURE.md]
        local reliable = false
        local ok = origin and mine.byKey and mine.byKey[(self:FullName(origin) or origin):lower()]
        if state == "c" and ok and not ok.weak and ok.st and (originUp == nil or originUp >= 300) then
            reliable = (HU.ListStampNow() - ok.st) >= 3000
        end
        local inNew = {}
        for i, m in ipairs(nr.members) do if m.name then inNew[m.name:lower()] = i end end
        -- (lo que se queda solo porque la lista no es fiable, se queda KEEP_FOR s como mucho: si no, la copia [+ARCHITECTURE.md]
        local kept = false
        for _, om in ipairs(mine.members) do
            local k = om.name and om.name:lower()
            local i = k and inNew[k]
            if i then
                if om.st and om.st > (nr.members[i].st or 0) then om.keptT = nil; nr.members[i] = om end
            elseif k and om.st and om.st > (nr.seq or 0) then
                om.keptT = nil
                nr.members[#nr.members + 1] = om
                inNew[k] = #nr.members
            elseif k and not reliable and (not om.keptT or GetTime() - om.keptT < KEEP_FOR) then
                om.keptT = om.keptT or GetTime()
                nr.members[#nr.members + 1] = om
                inNew[k] = #nr.members
                kept = true
            end
        end
        if kept then HU.After(KEEP_FOR + 1, function() DropKept(HU, tag) end) end
        if mine.seq and mine.seq > (nr.seq or 0) then nr.seq = mine.seq end
        nr.online = math.max(nr.online or 0, #nr.members)
    end
    if state then HU.ApplyRosterState(nr, state) end
    -- (los cambios que llegaron mientras llegaba esta lista son más nuevos que ella: se vuelven a aplicar. [+ARCHITECTURE.md]
    local before, late = nil, false
    for _, d in ipairs(recentDeltas[tag] or {}) do
        if d.s and d.s > (nr.seq or 0) then
            if d.t < pt.t and not before then before = MembersSigHash(nr.members) end
            HU.ApplyRosterDelta(self, nr, tag, d.parts, d.nparts, d.s)
            if d.t < pt.t then late = true end
        end
    end
    for _, d in ipairs(recentDeltas[tag] or {}) do
        if d.s and d.s > (nr.seq or 0) then nr.seq = d.s end
    end
    -- (y si de verdad le faltaban, la corregida vale como recién hecha y se reparte, para que la arregle [+ARCHITECTURE.md]
    if late and before and MembersSigHash(nr.members) ~= before then
        -- (la corregida no se marca como «recién hecha»: eso hacía que quien la corregía viera como más
        -- viejas las de los demás y las volviera a repartir, en cadena)
        if (self:IsRelay() or (self:ResponsibleFor(tag)))
            and (not lateShared[tag] or GetTime() - lateShared[tag] > LATE_FIX_FOR) then
            lateShared[tag] = GetTime()
            local heard = rbInGuild[tag]
            HU.After(1 + math.random() * 4, function()
                if rbInGuild[tag] ~= heard then return end
                HU:SendStoredRoster(tag)
            end)
        end
    end
    -- Segunda opinión: si pisa la que mandó su enlace hace poco una lista de otro de esa hermandad [+ARCHITECTURE.md]
    if dist == "WHISPER" then
        local rp = self:KnownRelay(tag)
        local fromRelay = rp and rp.name:lower() == sender:lower()
        if fromRelay then nr.relayT = GetTime()
        else
            nr.relayT = mine and mine.relayT
            if rp and nr.relayT and GetTime() - nr.relayT < 120 and (not verifyAsked[tag] or GetTime() - verifyAsked[tag] > 30) then
                verifyAsked[tag] = GetTime()
                local to = rp.name
                HU.After(2 + math.random() * 2, function() HU:Whisper(to, "RF~" .. (HU.myTag or "") .. "~1", true) end)
            end
        end
    else
        nr.relayT = mine and mine.relayT
    end
    self.remoteRoster[tag] = IndexRoster(nr)
    -- (confirmada por mi hermandad: quien la hizo queda como contacto comprobado, para la próxima sesión)
    if pt.flag == "c" and not pt.wFrom and not pt.weak and nr.origin and nr.byKey and nr.byKey[self:Key(nr.origin) or ""] then
        self:RememberPeer(nr.origin, tag)
    end
    if pt.wFrom then
        if state == "c" then
            self.rosterTrust[tag] = GetTime()
            self.bootState[tag] = nil
        else
            self:AfterRosterDecided(tag, pt.wFrom, nr)
        end
        -- (los trozos se repartieron con otro estado del que ha quedado: se reparte otra vez) [+ARCHITECTURE.md]
        if pt.fwdFlag ~= state and (self:IsRelay() or self:HandlesTag(tag) or (state == "c" and (self:CanOfficer() or (self:RosterSlot() ~= nil)))) then self:SendStoredRoster(tag, true) end
    elseif fwdK then
        -- (el reenvío de un compañero que he contado como directo: lo mismo que arriba)
        if state == "c" then
            self.rosterTrust[tag] = GetTime()
            self.bootState[tag] = nil
        else
            self:AfterRosterDecided(tag, fwdK, nr)
        end
        if pt.flag ~= state then Reshare(self, tag) end
    end
    -- se recuerdan los rangos vistos (para comprobar a los oficiales aunque luego se desconecten)
    -- (solo de una lista confirmada: en las demás, el rango lo elige quien la manda)
    self.db.rankCache = self.db.rankCache or {}
    local now = time()
    local rc = self.db.rankCache
    local confirmed = HU.RosterStateOf(nr) == "c"
    for _, m in ipairs(members) do
        if confirmed and m.rankIndex and not m.weak then
            -- (se reutiliza la tabla: con miles de nombres, menos basura y menos tirones)
            local k = m.key or m.name:lower()
            local c = rc[k]
            if c then c.tag, c.idx, c.t = tag, m.rankIndex, now
            else rc[k] = { tag = tag, idx = m.rankIndex, t = now } end
        end
    end
    self:RetryDeferred()
    self:Changed("members")
end

-- Cambios de la lista de conectados de otra hermandad (ver SendRosterDelta)
local dpartial = {}
local fullAsked = {}

-- Me piden la lista entera (tenían otra versión y no les valen los cambios)   RF~SUETIQUETA
local secondAnswered = {}
local rfLater = {}      -- [etiqueta] = envío pendiente para cuando acabe el freno de RF { sender, f }
local SECOND_MAX, SECOND_WIN = 6, 10   -- respuestas a RF~etiq~2 como mucho, en total, cada tanto
local secondWin = { t = 0, n = 0 }
HU:RegisterMessage("RF", { tagField = 1, bootstrap = true, combat = "req" })
HU.comm.RF = function(self, sender, f, dist)
    if dist ~= "WHISPER" then return end
    local tag = f[1]
    if not tag or tag == "" or tag == self.myTag or not self.cfg or not self.cfg.byTag[tag] then return end
    -- (RF~etiq~2: segunda opinión, o alguien de otra hermandad que acaba de entrar y me tiene como [+ARCHITECTURE.md]
    if f[2] == "2" then
        if not (self:RosterSlot() or self:CanOfficer()) then return end
        local k = sender:lower()
        if secondAnswered[k] and GetTime() - secondAnswered[k] < 30 then return end
        local now = GetTime()
        if now - secondWin.t > SECOND_WIN then secondWin.t, secondWin.n = now, 0 end
        if secondWin.n >= SECOND_MAX then return end
        secondWin.n = secondWin.n + 1
        secondAnswered[k] = now
        for _, m in ipairs((self:BuildRosterMessages())) do self:Whisper(sender, m) end
        return
    end
    if not (self:HandlesTag(tag) or self:IsRelay()) then return end
    local st = rosterState[tag]
    -- (RF~etiq~1: «me ha llegado otra lista distinta de la tuya, confírmamela»: vale a los 5 s)
    local gap = (f[2] == "1") and 5 or 30
    -- (dentro del freno no se descarta: se manda cuando acabe, UNA sola vez por hermandad, al último que [+ARCHITECTURE.md]
    if st and GetTime() - st.fullT < gap then
        local pend = rfLater[tag]
        if pend then pend.sender, pend.f = sender, f
        else
            pend = { sender = sender, f = f }
            rfLater[tag] = pend
            HU.After(gap - (GetTime() - st.fullT) + 0.5, function()
                rfLater[tag] = nil
                HU.comm.RF(HU, pend.sender, pend.f, "WHISPER")
            end)
        end
        return
    end
    local p = self.remote[sender:lower()]
    if not p then p = { name = sender, tag = tag, last = GetTime() }; self.remote[sender:lower()] = p end
    p.sentRoster = GetTime()
    self:SendRosterTo(sender)
end
-- (bootstrap: los cambios de la lista de conectados valen igual que la lista entera, que ya se acepta;
-- bfast: van delante de las listas enteras)
HU:RegisterMessage("RC", { tagField = 1, bootstrap = true, remoteData = true, queue = "bfast", ttl = 300 })
HU.comm.RC = function(self, sender, f, dist, raw)
    local tag, base, new = f[1], f[2], tonumber(f[3] or "", 36)
    local total, online, part, nparts = tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7])
    if not tag or tag == self.myTag or not self.cfg or not self.cfg.byTag[tag] then return end
    if not (base and base ~= "" and new and part and nparts) or part < 1 or part > nparts or nparts > 250 then return end
    -- Por susurro, los cambios solo se aplican de alguien comprobado, de alguien de la lista o de quien
    -- ya la respaldaba (sin confirmar); los demás, que manden la lista entera (se discute en HU.comm.RB)
    local sk = dist == "WHISPER" and self:Key(sender)
    local kind = sk and (self.acceptKind[tag] or {})[sk]
    local st = self.bootState[tag]
    if sk and not (kind == "peer" or kind == "vouched" or kind == "member" or (st and st.origins[sk])) then return end
    -- (el «me voy» de quien sale del juego (Presence.lua, Leaving) lleva la huella de base a 0 y su nombre detrás: no es
    -- un contacto que acabe de hablar sino uno que se va. Ni se le da por visto ni se le pide nada: ya no está; y mi
    -- hermandad, que lo recibe de mí, tampoco le susurra) [+ARCHITECTURE.md]
    local bye = base == "0" and f[9] and f[9] ~= "" and self:FullName(f[9])
    if bye and (dist ~= "WHISPER" or self:Key(bye) == sk) then
        self:MarkOffline(bye)
        self:ForgetOffline(bye)
    else
        bye = nil
    end
    if dist == "WHISPER" then
        if not bye then
            self:SeenPeer(sender, tag)
            local p = self.remote[sender:lower()]
            if p then p.last = GetTime() end
        end
        -- (a mi hermandad, con el estado de mi copia al final: la toman igual que yo)
        local fl = HU.RosterStateOf(self.remoteRoster[tag]) or "b"
        local withState = raw .. "~" .. fl
        -- (los cambios pequeños, a mi hermandad al momento y por delante: conectado/desconectado)
        local fast = (nparts <= 2) or nil
        if #withState <= 250 then self:Send(withState, "GUILD", nil, nil, nil, fast) elseif fl == "c" then self:Send(raw, "GUILD", nil, nil, nil, fast) end
    end
    local key = tag .. ":" .. new
    local pt = dpartial[key]
    if not pt then
        if not HU.PartialAdmit(dpartial, sender, dist) then return end
        pt = { parts = {}, got = 0, t = GetTime(), by = sender:lower(), g = (dist == "GUILD") or nil }
        dpartial[key] = pt
        HU.After(120, function() if dpartial[key] == pt then dpartial[key] = nil; HU:NeedRoster(tag) end end)
    end
    if dist == "WHISPER" then pt.from, pt.kind = sender, kind
    elseif f[11] and HU.STATE_RANK[f[11]] then pt.flag = f[11] end
    if f[9] and f[9] ~= "" then pt.origin = self:FullName(f[9]) end
    if not pt.parts[part] then pt.parts[part] = f[8] or ""; pt.got = pt.got + 1 end
    if pt.got < nparts then return end
    dpartial[key] = nil
    for k, v in pairs(dpartial) do if GetTime() - v.t > 120 then dpartial[k] = nil end end
    -- los cambios ("entra" / "sale") se aplican aunque mi copia no sea justo la que esperaban: aplicarlos [+ARCHITECTURE.md]
    local rd = recentDeltas[tag] or {}
    recentDeltas[tag] = rd
    -- (s: la hora del servidor de cuando se hizo el cambio, para compararla con la de las listas. Se
    -- guardan más: una lista vieja puede llegar varios minutos tarde)
    rd[#rd + 1] = { t = GetTime(), s = new, parts = pt.parts, nparts = nparts }
    while #rd > 40 or (rd[1] and GetTime() - rd[1].t > 600) do table.remove(rd, 1) end
    local r = self.remoteRoster[tag]
    if not r then
        self:NeedRoster(tag)
        return
    end
    -- (de mi hermandad: se toma su estado. Si es más bajo que el mío, siempre; si es más alto, solo si
    -- no soy yo quien lleva el reloj de esa hermandad)
    if pt.flag then
        local cs = HU.RosterStateOf(r)
        if HU.STATE_RANK[pt.flag] < HU.STATE_RANK[cs] or (HU.STATE_RANK[pt.flag] > HU.STATE_RANK[cs] and not self.bootState[tag]) then
            HU.ApplyRosterState(r, pt.flag)
        end
    end
    local added = HU.ApplyRosterDelta(self, r, tag, pt.parts, nparts, new)
    -- (el número de la copia es el del cambio más nuevo que le he aplicado: nunca baja)
    r.seq, r.updated = math.max(r.seq or 0, new), GetTime()
    -- (el número de envío pasa a ser el de quien mandó el cambio: ese es ahora el origen de la copia)
    r.origin = pt.origin or (pt.from and self:FullName(pt.from)) or r.origin
    -- (cambios de su enlace: cuenta como que el enlace nos mantiene la lista al día)
    local rp = dist == "WHISPER" and self:KnownRelay(tag)
    if rp and rp.name:lower() == (pt.origin or sender):lower() then r.relayT = GetTime() end
    r.total, r.online = total or r.total, online or #r.members
    IndexRoster(r)
    -- (sin confirmar: la huella que respaldan sus orígenes es la de la copia con estos cambios; y si los
    -- manda un contacto comprobado y la copia queda como la suya, queda confirmada)
    local st2 = self.bootState[tag]
    if dist == "WHISPER" and st2 then
        if st2.origins[sk] then st2.hash = HashNoKept(r.members) end
        local want2 = f[10]
        if (pt.kind == "peer" or pt.kind == "vouched") and want2 and HashNoKept(r.members) == want2 then
            self:SetRosterState(tag, "c", "la confirman los cambios de " .. sender)
        end
    end
    -- (acaba de conectarse alguien de su lista: suele entrar en el canal antes de que llegue este
    -- cambio, así que se le manda la mía ahora, como en OnContactJoined)
    for _, n in ipairs(added) do self:OnContactJoined(n) end
    -- ¿ha quedado como la del que la manda? Si no, lo arregla la presentación de su enlace (si no
    -- coincide dos veces seguidas, se pide la lista entera)
    local want = f[10]
    if want and want ~= "" then
        r.sigHash = MembersSigHash(r.members)
        -- (sin contar a quien guardo de más a propósito unos segundos (keptT): con ellos nunca cuadraba, y
        -- cada cambio pedía la lista entera; banco, continua-4: 20 enteras al mismo enlace en 30 min)
        local h = HashNoKept(r.members)
        r.deltaMiss = (h ~= want) and ((r.deltaMiss or 0) + 1) or 0
        -- (no cuadra: mi copia vino de otro, por ejemplo de quien fue enlace un momento. Se pide la [+ARCHITECTURE.md]
        if h ~= want and dist == "WHISPER" and not bye and (not fullAsked[tag] or GetTime() - fullAsked[tag] > 60) then
            fullAsked[tag] = GetTime()
            local to = pt.origin or sender
            HU.After(1 + math.random() * 2, function() HU:Whisper(to, "RF~" .. (HU.myTag or "") .. "~1", true) end)
        end
    else
        r.sigHash = nil -- (se vuelve a calcular cuando haga falta)
    end
    self:RetryDeferred()
    self:Changed("members")
end

HU:Module("Net/RosterSync", { "Comm", "Config", "Core", "Domain/Trust", "Lists", "Net/Relay", "Net/Security", "Net/Transport", "Protocol", "Ranks", "Roster" })
