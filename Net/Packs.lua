-- Guild Union - Paquetes con huella: los datos de cada hermandad, en trozos con huella, bajo demanda [+ARCHITECTURE.md]
--   WM~etiq~conj~n~h1,…,hn                 cómo es ahora (la huella de cada trozo); lo anuncia el enlace dueño
--   WD~etiq~conj~trozo~antes~después~ops   un cambio pequeño en un trozo: «-línea;+línea»
--   WP~deEtiq~etiq~conj~turno~3,7|m        pedir trozos («m»: el anuncio). Por GUILD, al porteador de mi
--                                          hermandad; por susurro, del porteador al equipo dueño
--   WT~etiq~conj~trozo~parte~partes~datos  un trozo, en partes de líneas enteras
-- No hay número de versión: la huella es la versión, y gana el último anuncio de quien puede hacerlo.
-- Este archivo no sabe qué hay dentro: cada conjunto se declara con HU:RegisterPackSet (Packs/*.lua)
local _, HU = ...

-- (se crea al llegar el primero: [etiq][conj] = { h = { huellas }, t = { [trozo] = { líneas } }, ok = { [trozo] = huella } })
HU:Saved({ account = { "packs" } })

local PART = 200            -- letras de datos por mensaje (el mensaje entero no pasa de 255)
local MAX_CHUNKS = 32
local MAX_PARTS = 24        -- un trozo de más partes que esto no se acepta
local HASH_LEN = 12         -- dos huellas de 6 letras en base 36
local ASK_MIN, ASK_MAX = 0.5, 2 -- espera al azar antes de pedir (si otro de mi hermandad pide lo mismo, no repito)
local RETRY = 6             -- si no llega en esto, se pide al siguiente del equipo
local SEEN_FOR = 15         -- lo pedido o servido que se ha visto vale para no repetirlo durante esto
local PUBLISH_WAIT = 60     -- el enlace junta los cambios de este rato en un anuncio
local ANNOUNCE_EVERY = 600  -- y lo repite cada tanto aunque no cambie
local FORWARD_GAP = 60      -- lo que me llega por susurro se repite por GUILD, una vez en este rato
local SERVE_MAX = 60        -- mensajes por minuto que sirvo por susurro a cada hermandad
local QUIET_MAX = 120       -- en una entrada masiva se espera a que se calme, como mucho esto
local TEAM_TTL = 700        -- los ayudantes que anunció el enlace valen esto (como en Net/Relay.lua)

HU.packSets = {} -- [conjunto] = { chunks, key, encode, source, onChange }

---------------------------------------------------------------------------
-- Huella: dos funciones de 32 bits distintas (×33 y ×65599) sobre las líneas ordenadas, en base 36
---------------------------------------------------------------------------
local TWO32 = 4294967296
local MOD6 = 2176782336 -- 36^6: cada huella cabe en 6 letras
-- (multiplicar módulo 2^32 sin perder cifras: en Lua 5.1 los números son de 53 bits)
local function Mul32(h, m)
    local lo, hi = h % 65536, math.floor(h / 65536)
    return (lo * m + ((hi * m) % 65536) * 65536) % TWO32
end
local function B36Pad(n, len)
    local s = HU.B36(n)
    return string.rep("0", len - #s) .. s
end
local function Hash2(s)
    local a, b = 5381, 0
    for i = 1, #s do
        local c = s:byte(i)
        a = (Mul32(a, 33) + c) % TWO32
        b = (Mul32(b, 65599) + c) % TWO32
    end
    return B36Pad(a % MOD6, 6) .. B36Pad(b % MOD6, 6)
end
local function HashSorted(lines) return Hash2(table.concat(lines, "\n")) end
local EMPTY = HashSorted({}) -- (la huella de un trozo vacío: ese no hace falta pedirlo)
-- La huella de un trozo: sus líneas, ordenadas (el orden de llegada no cuenta)
function HU.PackHash(lines)
    local copy = {}
    for i = 1, #lines do copy[i] = lines[i] end
    table.sort(copy)
    return HashSorted(copy)
end
-- En qué trozo cae una entrada: siempre el mismo para la misma clave (sin mayúsculas)
function HU.PackChunkOf(key, n)
    local h = 5381
    key = tostring(key or ""):lower()
    for i = 1, #key do h = (Mul32(h, 33) + key:byte(i)) % TWO32 end
    return h % n + 1
end

---------------------------------------------------------------------------
-- Conjuntos y lo guardado
---------------------------------------------------------------------------
function HU:RegisterPackSet(id, def)
    if type(id) ~= "string" or not id:match("^%u%u$") then error("RegisterPackSet: nombre de 2 mayúsculas", 2) end
    if self.packSets[id] then error("RegisterPackSet: " .. id .. " repetido", 2) end
    if type(def.chunks) ~= "number" or def.chunks < 1 or def.chunks > MAX_CHUNKS then error("RegisterPackSet: chunks", 2) end
    self.packSets[id] = def
end

local function Get(tag, id)
    local all = HU.db and HU.db.packs
    return all and all[tag] and all[tag][id]
end
local function Put(tag, id, p)
    HU.db.packs = HU.db.packs or {}
    HU.db.packs[tag] = HU.db.packs[tag] or {}
    HU.db.packs[tag][id] = p
end
local function Changed(id, tag)
    local def = HU.packSets[id]
    if def and def.onChange then def.onChange(tag) end
end
-- (un trozo vale si se comprobó con la huella que dice ahora el anuncio: no se vuelve a calcular)
local function Valid(p, i) return p and p.t and p.t[i] ~= nil and p.ok and p.h and p.ok[i] == p.h[i] end
local function Missing(p)
    local out = {}
    for i = 1, #(p and p.h or {}) do if not Valid(p, i) then out[#out + 1] = i end end
    return out
end
local function SameHashes(a, b)
    if not (a and b) or #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

function HU:PackGet(tag, id) return Get(tag, id) end
-- Las líneas ya comprobadas de un conjunto de una hermandad, y si está completo
function HU:PackLines(tag, id)
    local p = Get(tag, id)
    local out = {}
    if not (p and p.h) then return out, false end
    for i = 1, #p.h do
        if Valid(p, i) then for _, l in ipairs(p.t[i]) do out[#out + 1] = l end end
    end
    return out, #Missing(p) == 0
end
-- Trozos comprobados y total (nil si de esa hermandad no ha llegado ningún anuncio)
function HU:PackProgress(tag, id)
    local p = Get(tag, id)
    if not (p and p.h) then return nil end
    return #p.h - #Missing(p), #p.h
end

---------------------------------------------------------------------------
-- Los equipos: el enlace y sus ayudantes, ordenados por nombre (igual en todos los ordenadores)
---------------------------------------------------------------------------
local function Sorted(names)
    local seen, out = {}, {}
    for _, n in ipairs(names) do
        local full = type(n) == "string" and HU:FullName(n)
        local k = full and full:lower()
        if k and not seen[k] then seen[k] = true; out[#out + 1] = full end
    end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end
local function MyTeam()
    local names = {}
    local relay = HU:RelayName()
    if relay then names[#names + 1] = relay end
    local list
    if HU:IsRelay() then
        list = HU.advertisedHelpers
    else
        local rh = HU.relayHelpers
        list = rh and rh.t and GetTime() - rh.t < TEAM_TTL and rh.list
    end
    for _, n in ipairs(list or {}) do names[#names + 1] = n end
    return Sorted(names)
end
local function TeamOf(tag)
    local names = {}
    local rp = HU:KnownRelay(tag)
    if rp and rp.name then names[#names + 1] = rp.name end
    local h = HU.helpers[tag]
    if h and h.list and h.t and GetTime() - h.t < 900 then
        for _, n in ipairs(h.list) do names[#names + 1] = n end
    end
    return Sorted(names)
end
-- (a quién se le pide algo de esa hermandad: su equipo; si todavía no se conoce, los mejores contactos
-- de esa hermandad que se han oído, como para el chat)
local function PoolOf(tag)
    local team = TeamOf(tag)
    if #team > 0 then return team end
    local names = {}
    for _, peer in ipairs(HU:BestPeers(tag, 3)) do names[#names + 1] = peer.name end
    return Sorted(names)
end
-- (el sitio de una etiqueta entre todas las de la unión: el mismo para todos)
local function TagIndex(tag)
    local all = {}
    for _, g in ipairs(HU.cfg and HU.cfg.guilds or {}) do all[#all + 1] = g.tag end
    table.sort(all)
    for i, t in ipairs(all) do if t == tag then return i end end
    return 1
end
local function Pick(team, idx, shift)
    if #team == 0 then return nil end
    return team[(idx + shift - 1) % #team + 1]
end
local function IsMe(name) return name ~= nil and HU:Key(name) == HU:MeKey() end
local function InMyTeam()
    for _, n in ipairs(MyTeam()) do if IsMe(n) then return true end end
    return false
end
HU.PackTeams = { Mine = MyTeam, Of = TeamOf } -- (para las pruebas)

---------------------------------------------------------------------------
-- Mi hermandad: la leen del juego el enlace y su equipo, solo lo que cambia
---------------------------------------------------------------------------
local mine = {} -- [conj] = { lineOf = { [clave] = línea }, chunkOf = { [clave] = i }, chunks = { [i] = { líneas } }, h = { huellas }, v }
local function Refresh(id)
    local def = HU.packSets[id]
    local m = mine[id]
    -- (si la lista del juego no ha cambiado desde la última vez, nada que hacer)
    if m and m.v == HU.rosterVersion then return m end
    local list = def and def.source and def.source()
    if not list then return nil end
    local n = def.chunks
    if not m then
        m = { lineOf = {}, chunkOf = {}, chunks = {}, h = {} }
        mine[id] = m
    end
    m.v = HU.rosterVersion
    local seen, dirty = {}, {}
    for _, e in ipairs(list) do
        local line = def.encode(e)
        local key = def.key(e)
        if line and key and line ~= "" and #line <= PART and not line:find("[~;\n|]") then
            local k = tostring(key):lower()
            seen[k] = true
            if m.lineOf[k] ~= line then
                local i = m.chunkOf[k] or HU.PackChunkOf(k, n)
                m.lineOf[k], m.chunkOf[k] = line, i
                dirty[i] = true
            end
        end
    end
    for k in pairs(m.lineOf) do
        if not seen[k] then
            dirty[m.chunkOf[k]] = true
            m.lineOf[k], m.chunkOf[k] = nil, nil
        end
    end
    if not m.built then
        for i = 1, n do dirty[i] = true end
        m.built = true
    end
    -- (solo los trozos que han cambiado: se rehacen de una pasada y se les calcula la huella)
    if next(dirty) then
        local c = {}
        for i in pairs(dirty) do c[i] = {} end
        for k, line in pairs(m.lineOf) do
            local t = c[m.chunkOf[k]]
            if t then t[#t + 1] = line end
        end
        for i, lines in pairs(c) do
            table.sort(lines)
            m.chunks[i], m.h[i] = lines, HashSorted(lines)
        end
    end
    return m
end
HU.PackRefresh = Refresh -- (para las pruebas)

---------------------------------------------------------------------------
-- Enviar
---------------------------------------------------------------------------
local function ManifestText(tag, id, hs) return "WM~" .. tag .. "~" .. id .. "~" .. #hs .. "~" .. table.concat(hs, ",") end
-- Un trozo en partes de líneas enteras (un nombre con tilde nunca se parte)
local function Parts(lines)
    local out, cur = {}, {}
    local len = 0
    for _, l in ipairs(lines or {}) do
        if len > 0 and len + 1 + #l > PART then
            out[#out + 1] = table.concat(cur, ";")
            cur, len = {}, 0
        end
        cur[#cur + 1] = l
        len = len + (len > 0 and 1 or 0) + #l
    end
    if #cur > 0 or #out == 0 then out[#out + 1] = table.concat(cur, ";") end
    return out
end
local function SendChunk(tag, id, lines, i, dist, target)
    local parts = Parts(lines)
    if #parts > MAX_PARTS then return 0 end
    for k, part in ipairs(parts) do
        local msg = "WT~" .. tag .. "~" .. id .. "~" .. i .. "~" .. k .. "~" .. #parts .. "~" .. part
        if dist == "WHISPER" then HU:Whisper(target, msg) else HU:Send(msg, "GUILD") end
    end
    return #parts
end
-- (lo que llega por susurro se repite por GUILD a mi hermandad, una sola vez en un rato)
local forwarded = {}
local function Forward(raw)
    local now = GetTime()
    if forwarded[raw] and now - forwarded[raw] < FORWARD_GAP then return end
    forwarded[raw] = now
    HU:Send(raw, "GUILD")
end
-- (a cada otra hermandad, una vez: a su enlace; si no se conoce, al primero de su equipo o a su mejor
-- contacto. Si ese no puede repartirlo en su hermandad, los demás lo piden al mirar: «m»)
local function Receiver(tag)
    local rp = HU:KnownRelay(tag)
    local to = (rp and rp.name) or TeamOf(tag)[1]
    if not to then
        local bp = HU:BestPeer(tag)
        to = bp and bp.name
    end
    return to
end
-- (devuelve las hermandades a las que no ha podido llegar: todavía no se conoce a nadie de ellas)
local function ToEachGuild(text, only)
    local unsent = {}
    for _, tag in ipairs(only or HU:OtherTags()) do
        local to = Receiver(tag)
        if to then HU:Whisper(to, text) else unsent[#unsent + 1] = tag end
    end
    return unsent
end

---------------------------------------------------------------------------
-- El enlace publica: las diferencias pequeñas y el anuncio (lo que cambia en un minuto, junto)
---------------------------------------------------------------------------
local published = {} -- [conj] = { h = { huellas }, t = { [i] = { líneas } }, at = GetTime() }
local pendingT = {}   -- [conj] = desde cuándo hay cambios sin publicar
local function Diff(old, new)
    local a, b, ops = {}, {}, {}
    for _, l in ipairs(old or {}) do a[l] = true end
    for _, l in ipairs(new or {}) do b[l] = true end
    for _, l in ipairs(old or {}) do if not b[l] then ops[#ops + 1] = "-" .. l end end
    for _, l in ipairs(new or {}) do if not a[l] then ops[#ops + 1] = "+" .. l end end
    return ops
end
local function Publish(id, m)
    local pub = published[id]
    local texts = {}
    if pub then
        for i = 1, #m.h do
            if pub.h[i] ~= m.h[i] then
                local ops = table.concat(Diff(pub.t[i], m.chunks[i]), ";")
                if ops ~= "" and #ops <= PART then
                    texts[#texts + 1] = "WD~" .. HU.myTag .. "~" .. id .. "~" .. i .. "~" .. pub.h[i] .. "~" .. m.h[i] .. "~" .. ops
                end
            end
        end
    end
    texts[#texts + 1] = ManifestText(HU.myTag, id, m.h)
    local unsent
    for _, t in ipairs(texts) do unsent = ToEachGuild(t) end
    local copyH, copyT = {}, {}
    for i = 1, #m.h do copyH[i], copyT[i] = m.h[i], m.chunks[i] end
    -- (las hermandades a las que no se ha podido llegar se reintentan en cada vuelta, solo con el anuncio)
    published[id] = { h = copyH, t = copyT, at = GetTime(), unsent = unsent }
    pendingT[id] = nil
end

local function Tick()
    if not HU.myTag or not HU.db then return end
    local relay = HU:IsRelay()
    local team = relay or InMyTeam()
    for id, def in pairs(HU.packSets) do
        if not relay then published[id], pendingT[id] = nil, nil end
        if def.source and team then
            local m = Refresh(id)
            if relay and m then
                local pub = published[id]
                local now = GetTime()
                if not pub then
                    Publish(id, m) -- (acabo de ser enlace: lo anuncio ya)
                elseif not SameHashes(pub.h, m.h) then
                    pendingT[id] = pendingT[id] or now
                    if now - pendingT[id] >= PUBLISH_WAIT then Publish(id, m) end
                elseif now - pub.at >= ANNOUNCE_EVERY then
                    Publish(id, m)
                elseif pub.unsent and #pub.unsent > 0 then
                    pub.unsent = ToEachGuild(ManifestText(HU.myTag, id, pub.h), pub.unsent)
                end
            end
        end
    end
end
HU.PackTick = Tick -- (para las pruebas)

---------------------------------------------------------------------------
-- Pedir lo que falta (bajo demanda: lo llama la interfaz al mirar)
---------------------------------------------------------------------------
local askSeen, wtSeen, asking = {}, {}, {}
local function K(tag, id, i) return tag .. "|" .. id .. "|" .. tostring(i) end
local function Recent(t, k) return t[k] ~= nil and GetTime() - t[k] < SEEN_FOR end
local function ParseListOf(s)
    local out = {}
    for x in s:gmatch("%d+") do out[#out + 1] = tonumber(x) end
    return out
end

local Ask, Carry, Watch
local function Retry(tag, id)
    local key = tag .. "|" .. id
    local st = asking[key]
    if not st then return end
    local p = Get(tag, id)
    if p and p.h and #Missing(p) == 0 then asking[key] = nil; return end
    st.shift = st.shift + 1
    -- (se ha preguntado a todo el equipo: se deja; se vuelve a intentar al mirar otra vez)
    if st.shift > #MyTeam() then asking[key] = nil; return end
    Ask(tag, id)
end
Ask = function(tag, id)
    local key = tag .. "|" .. id
    local st = asking[key]
    if not st then return end
    -- (en una entrada masiva, primero que se calme: el chat y los conectados van antes)
    if not HU.QuietLogins(10) and GetTime() - st.t < QUIET_MAX then
        HU.After(10, function() Ask(tag, id) end)
        return
    end
    local p = Get(tag, id)
    local list
    if not (p and p.h) then
        list = "m"
    else
        local miss = Missing(p)
        if #miss == 0 then asking[key] = nil; return end
        -- (lo que otro de mi hermandad acaba de pedir o de recibir no se repite: llega por GUILD a todos)
        local want = {}
        for _, i in ipairs(miss) do
            if not Recent(askSeen, K(tag, id, i)) and not Recent(wtSeen, K(tag, id, i)) then want[#want + 1] = i end
        end
        list = #want > 0 and table.concat(want, ",") or nil
    end
    if list then
        -- (si el porteador de este turno soy yo, mi propio mensaje no me llega: lo traigo directamente; y si
        -- no conozco a nadie de esa hermandad, al siguiente del equipo sin esperar)
        if IsMe(Pick(MyTeam(), TagIndex(tag), st.shift)) then
            if not Carry(tag, id, list == "m" and "m" or ParseListOf(list), st.shift) then return Retry(tag, id) end
        else
            HU:Send("WP~" .. HU.myTag .. "~" .. tag .. "~" .. id .. "~" .. st.shift .. "~" .. list, "GUILD")
        end
    end
    Watch(tag, id)
end
-- (si en un rato no llega nada, al siguiente del equipo; mientras siga llegando algo, se espera. Solo
-- cuenta el último aviso, no uno viejo)
Watch = function(tag, id)
    local key = tag .. "|" .. id
    local st = asking[key]
    if not st then return end
    st.seq = (st.seq or 0) + 1
    local seq = st.seq
    HU.After(RETRY, function()
        local s = asking[key]
        if not (s and s.seq == seq) then return end
        if s.lastT and GetTime() - s.lastT < RETRY then Watch(tag, id) else Retry(tag, id) end
    end)
end

-- Quiero ver este conjunto de esa hermandad completo (Members con desconectados, una búsqueda...)
function HU:PackNeed(tag, id)
    if not (self.myTag and tag and tag ~= self.myTag and self.packSets[id]) then return end
    local key = tag .. "|" .. id
    if asking[key] then return end
    local p = Get(tag, id)
    if p and p.h and #Missing(p) == 0 then return end
    asking[key] = { shift = 0, t = GetTime() }
    HU.After(ASK_MIN + math.random() * (ASK_MAX - ASK_MIN), function() Ask(tag, id) end)
end

---------------------------------------------------------------------------
-- El porteador de mi hermandad para esa hermandad: lo da si lo tiene; si no, lo trae
---------------------------------------------------------------------------
-- (devuelve si ha podido preguntar: no lo hace si no conozco a nadie de esa hermandad)
local function UpAsk(tag, id, list, shift)
    local server = Pick(PoolOf(tag), TagIndex(HU.myTag), shift)
    if not server then return false end
    HU:Whisper(server, "WP~" .. HU.myTag .. "~" .. tag .. "~" .. id .. "~" .. shift .. "~" .. list)
    return true
end
-- (devuelve si ha hecho algo: dar lo que tenía o preguntar a esa hermandad)
Carry = function(tag, id, want, shift)
    local p = Get(tag, id)
    if want == "m" then
        if p and p.h then HU:Send(ManifestText(tag, id, p.h), "GUILD"); return true end
        return UpAsk(tag, id, "m", shift)
    end
    local need, did = {}, false
    for _, i in ipairs(want) do
        if Valid(p, i) then
            local k = K(tag, id, i)
            if not Recent(wtSeen, k) then wtSeen[k] = GetTime(); SendChunk(tag, id, p.t[i], i, "GUILD") end
            did = true
        else
            need[#need + 1] = i
        end
    end
    if #need > 0 then did = UpAsk(tag, id, table.concat(need, ","), shift) or did end
    return did
end

-- Otra hermandad pide algo de la mía (lo leo del juego, como el enlace: lo que sirvo cuadra con lo que leo)
local served = {} -- [etiqueta que pide] = { t, n }
local function ServeWhisper(sender, from, id, want)
    local m = Refresh(id)
    if not m then return end
    local w = served[from]
    if not w or GetTime() - w.t > 60 then w = { t = GetTime(), n = 0 }; served[from] = w end
    if want == "m" then
        if w.n < SERVE_MAX then w.n = w.n + 1; HU:Whisper(sender, ManifestText(HU.myTag, id, m.h)) end
        return
    end
    for _, i in ipairs(want) do
        local n = #Parts(m.chunks[i])
        if w.n + n > SERVE_MAX then break end
        w.n = w.n + SendChunk(HU.myTag, id, m.chunks[i], i, "WHISPER", sender)
    end
end

---------------------------------------------------------------------------
-- Recibir
---------------------------------------------------------------------------
local function ParseList(s, n)
    if s == "m" then return "m" end
    local out = {}
    for x in tostring(s or ""):gmatch("[^,]+") do
        local i = tonumber(x)
        if not (i and i >= 1 and i <= n and i == math.floor(i)) or #out >= MAX_CHUNKS then return nil end
        out[#out + 1] = i
    end
    return #out > 0 and out or nil
end
local function ParseHashes(s, n)
    local hs = {}
    for h in tostring(s or ""):gmatch("[^,]+") do
        if #h ~= HASH_LEN or h:find("[^0-9a-z]") then return nil end
        hs[#hs + 1] = h
    end
    return #hs == n and hs or nil
end
-- (anuncios y cambios: por susurro, de alguien comprobado de esa hermandad (lo que dice lo lee del juego,
-- igual que su enlace); por GUILD, de quien reparte en la mía. Lo de mi propia hermandad lo leo yo)
local function Trusted(self, sender, tag, dist)
    if tag == self.myTag then return false end
    if dist == "WHISPER" then return self:Vouched(sender, tag) end
    if dist == "GUILD" then return self:IsGuildForwarder(sender) end
    return false
end

HU:RegisterMessage("WM", { tagField = 1, bootstrap = true, remoteData = true, queue = "blow", ttl = 300, combat = "last" })
HU.comm.WM = function(self, sender, f, dist, raw)
    local tag, id, n = f[1], f[2], tonumber(f[3])
    local def = id and self.packSets[id]
    if not (tag and def and n == def.chunks) then return end
    local hs = ParseHashes(f[4], n)
    if not hs or not Trusted(self, sender, tag, dist) then return end
    local p = Get(tag, id)
    if not (p and SameHashes(p.h, hs)) then
        -- (cómo es ahora: se quedan los trozos que no han cambiado)
        local np = { h = hs, t = {}, ok = {} }
        for i = 1, n do
            if hs[i] == EMPTY then
                np.t[i], np.ok[i] = {}, EMPTY
            elseif Valid(p, i) and p.h[i] == hs[i] then
                np.t[i], np.ok[i] = p.t[i], hs[i]
            end
        end
        Put(tag, id, np)
        Changed(id, tag)
    end
    if dist == "WHISPER" and raw then Forward(raw) end
end

HU:RegisterMessage("WD", { tagField = 1, bootstrap = true, remoteData = true, fields = { "tag", "id", "i", "from", "to", "ops*" },
    queue = "blow", ttl = 300, combat = "data" })
HU.comm.WD = function(self, sender, f, dist, raw)
    local tag, id, i, from, to = f[1], f[2], tonumber(f[3]), f[4], f[5]
    local def = id and self.packSets[id]
    if not (tag and def and i and i >= 1 and i <= def.chunks and from and to and #to == HASH_LEN) then return end
    if not Trusted(self, sender, tag, dist) then return end
    if dist == "WHISPER" and raw then Forward(raw) end
    local p = Get(tag, id)
    -- (solo si mi trozo estaba como dice «antes»; si no, ya lo arreglará el anuncio)
    if not (p and p.h and p.h[i] == from) then return end
    if Valid(p, i) then
        local set = {}
        for _, l in ipairs(p.t[i]) do set[l] = true end
        for op in (f.ops or ""):gmatch("[^;]+") do
            local sign, line = op:sub(1, 1), op:sub(2)
            if sign == "+" then set[line] = true elseif sign == "-" then set[line] = nil end
        end
        local lines = {}
        for l in pairs(set) do lines[#lines + 1] = l end
        table.sort(lines)
        if HashSorted(lines) == to then p.t[i], p.ok[i] = lines, to else p.t[i], p.ok[i] = nil, nil end
    end
    p.h[i] = to
    Changed(id, tag)
end

HU:RegisterMessage("WP", { tagField = 1, bootstrap = true, queue = "blow", ttl = 60, combat = "req" })
HU.comm.WP = function(self, sender, f, dist)
    local from, tag, id, shift = f[1], f[2], f[3], tonumber(f[4])
    local def = id and self.packSets[id]
    if not (from and tag and def and shift and shift >= 0 and shift < 64) then return end
    local want = ParseList(f[5], def.chunks)
    if not want then return end
    if dist == "GUILD" then
        if from ~= self.myTag or tag == self.myTag then return end
        if want ~= "m" then for _, i in ipairs(want) do askSeen[K(tag, id, i)] = GetTime() end end
        if IsMe(Pick(MyTeam(), TagIndex(tag), shift)) then Carry(tag, id, want, shift) end
    elseif dist == "WHISPER" and tag == self.myTag and from ~= self.myTag then
        ServeWhisper(sender, from, id, want)
    end
end

local assembling = {} -- [etiq|conj|trozo|quien] = { parts, got, n, t }
local badChunks = 0
function HU.PackBadCount() return badChunks end
HU:RegisterMessage("WT", { tagField = 1, bootstrap = true, fields = { "tag", "id", "i", "k", "n", "data*" },
    queue = "blow", ttl = 120, combat = "data" })
HU.comm.WT = function(self, sender, f, dist)
    local tag, id, i, k, n = f[1], f[2], tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    local def = id and self.packSets[id]
    if not (tag and def and i and k and n and i >= 1 and i <= def.chunks and k >= 1 and k <= n and n <= MAX_PARTS) then return end
    if tag == self.myTag then return end
    wtSeen[K(tag, id, i)] = GetTime()
    -- (sigue llegando: quien lo está esperando no pasa todavía al siguiente del equipo)
    local st = asking[tag .. "|" .. id]
    if st then st.lastT = GetTime() end
    local p = Get(tag, id)
    if not (p and p.h and p.h[i]) or Valid(p, i) then return end
    -- (las partes de cada uno, aparte: no se mezclan las de dos que sirven a la vez)
    local akey = K(tag, id, i) .. "|" .. tostring(sender):lower()
    local a = assembling[akey]
    if not a or a.n ~= n or GetTime() - a.t > 120 then a = { parts = {}, got = 0, n = n }; assembling[akey] = a end
    a.t = GetTime()
    if not a.parts[k] then a.parts[k], a.got = f.data or "", a.got + 1 end
    if a.got < n then return end
    assembling[akey] = nil
    local lines = {}
    for kk = 1, n do
        for l in a.parts[kk]:gmatch("[^;]+") do lines[#lines + 1] = l end
    end
    table.sort(lines)
    -- (se comprueba con la huella del anuncio: si no cuadra, se tira y se pide al siguiente del equipo)
    if HashSorted(lines) ~= p.h[i] then
        badChunks = badChunks + 1
        if asking[tag .. "|" .. id] then Retry(tag, id) end
        return
    end
    p.t = p.t or {}
    p.ok = p.ok or {}
    p.t[i], p.ok[i] = lines, p.h[i]
    -- (me lo han traído por susurro: a toda mi hermandad de una vez)
    if dist == "WHISPER" then SendChunk(tag, id, lines, i, "GUILD") end
    Changed(id, tag)
end

---------------------------------------------------------------------------
-- Cada 30 s: el equipo lee su hermandad y el enlace publica lo que haya cambiado
---------------------------------------------------------------------------
HU:OnStart(function()
    HU:Every(30, "paquetes", Tick, { pauseInCombat = true })
end)

HU:Module("Net/Packs", { "Config", "Core", "Domain/Trust", "Lists", "Net/Relay", "Net/RosterSync", "Net/Security", "Net/Transport", "Protocol" })
