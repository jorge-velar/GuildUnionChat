-- Guild Union - historial de oficiales: 30 días de chat para buscar qué dijo alguien y ver el contexto
local _, HU = ...
local L = HU.L

local DAYS = 30
-- tope de lo guardado de mi comunidad si soy oficial (se borran los días más viejos y, si hoy solo [+ARCHITECTURE.md]
local MAX_BYTES = 8 * 1024 * 1024
local OTHER_BYTES = 3 * 1024 * 1024 -- las otras comunidades de la cuenta (otros personajes)
local LINE_RAM = 40 -- lo que ocupa de más en memoria cada línea del día abierto (texto suelto + sitio en la lista)
-- (los miembros guardan solo 2 días del chat de hermandad, para contestar a los oficiales cuando
-- no haya otro oficial conectado; nunca el chat de oficiales)
local MEMBER_DAYS = 2
local MEMBER_BYTES = 1024 * 1024
local SEP = "\31"
local KIND_CODE = { main = "g", lfg = "b", off = "o" }
local CODE_KIND = { g = "main", b = "lfg", o = "off" }
local MAX_LOCAL = 300   -- resultados de una búsqueda en el propio PC
local MAX_REMOTE = 40   -- resultados que contesta cada oficial
local CONTEXT = 12      -- líneas antes y después en "ver en el chat"
local SLICE = 2500      -- líneas revisadas por fotograma al buscar (unos 10 ms)
local DIGEST_SLICE = 300 -- líneas por fotograma al calcular huellas (la huella recorre cada letra)
-- tope de trabajo por fotograma, mirado cada SUB líneas (en una tabla: la parte principal del archivo no
-- puede pasar de 200 variables locales)
local DIGEST_CAP = { MS = 0.8, SUB = 20, clock = debugprofilestop or function() return GetTime() * 1000 end }
HU.HPREFIX = "HU20H"

---------------------------------------------------------------------------
-- Estado
---------------------------------------------------------------------------
local failures, disabled = 0, false
local idxCache = setmetatable({}, { __mode = "k" }) -- [día] = { [nombre en minúsculas] = id }
-- los días ya cerrados se guardan en bloques de 200 mensajes (un texto suelto por mensaje ocupa
-- mucha más memoria; y un solo texto enorme por día es lento de recorrer)
local CHUNK = 200
local splitCache = setmetatable({}, { __mode = "kv" })
local function SplitChunk(s)
    local c = splitCache[s]
    if not c then
        c = {}
        for l in (s .. "\n"):gmatch("([^\n]*)\n") do c[#c + 1] = l end
        splitCache[s] = c
    end
    return c
end
local function DayLines(day)
    if day.lines then return day.lines end
    local out = {}
    for _, ch in ipairs(day.chunks or {}) do
        for _, l in ipairs(SplitChunk(ch)) do out[#out + 1] = l end
    end
    return out
end
local function Compact(day)
    if day.lines then
        local chunks = {}
        for i = 1, #day.lines, CHUNK do
            chunks[#chunks + 1] = table.concat(day.lines, "\n", i, math.min(#day.lines, i + CHUNK - 1))
        end
        day.chunks = chunks
        day.lines = nil
    end
end

local function Store()
    local adb = HU.adb
    if not adb then return nil end
    adb.hist = adb.hist or {}
    return adb.hist
end

-- Una comunidad, un almacén (los personajes de la cuenta lo comparten, pero solo lo ve quien
-- sea oficial ahora de esa comunidad)
local function CommunityKey()
    if not HU.cfg or not HU.myTag then return nil end
    return (HU:Title() or "?"):lower()
end

local function Community(create)
    local s, key = Store(), CommunityKey()
    if not s or not key then return nil end
    local c = s[key]
    if not c and create then
        c = { days = {} }
        s[key] = c
    end
    return c
end

function HU:HistEnabled()
    return not disabled and self.db ~= nil and not self.db.histOff
end

local officerT, officerV = -100, false
local function IAmOfficer()
    local now = GetTime()
    if now - officerT > 30 then officerT, officerV = now, HU:CanPin() and true or false end
    return officerV
end

-- Si el historial falla muchas veces, se apaga solo en esta sesión (nunca debe romper el resto)
local function Guarded(where, fn, ...)
    if disabled then return end
    local ok, err = pcall(fn, ...)
    if ok then return end
    failures = failures + 1
    if HU.RecordError then HU:RecordError(err, "historial " .. where) end
    if failures >= 10 and not disabled then
        disabled = true
        if HU:CanPin() then HU:Print(L("El historial de oficiales ha dado errores y se ha apagado hasta que recargues (/gu errores para verlos).")) end
    end
end

local function DayKey(t) return date("%Y%m%d", t) end
local function DayStart(t)
    local d = date("*t", t)
    return time({ year = d.year, month = d.month, day = d.day, hour = 0, min = 0, sec = 0 })
end

local function Clean(s)
    return (tostring(s or ""):gsub("[%c\31~]", " "))
end

-- Texto de otro, listo para guardar o enseñar. SafeText dobla cada | suelta; aplicado otra vez a un [+ARCHITECTURE.md]
local function SafeRemote(s)
    return HU.SafeText((tostring(s or ""):gsub("|+", "|")), true)
end

-- Lo que se compara de un texto (huellas y repetidos): con las | sin doblar y solo el principio,
-- porque al viajar se corta el final de los mensajes largos (la cabecera ocupa parte de los 255)
local KEY_LEN = 120
local function MatchText(s)
    s = s or ""
    if s:find("|", 1, true) then s = s:gsub("|+", "|") end
    return HU.Utf8Cut(s, KEY_LEN)
end

local function DayIndex(day)
    local idx = idxCache[day]
    if not idx then
        idx = {}
        for i, n in ipairs(day.names) do idx[n:lower()] = i end
        idxCache[day] = idx
    end
    return idx
end

local function SortedDays(c)
    local keys = {}
    for k in pairs(c.days) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function KeepDays() return IAmOfficer() and DAYS or MEMBER_DAYS end
local function MaxBytes() return IAmOfficer() and MAX_BYTES or MEMBER_BYTES end

-- Lo que ocupa una comunidad en memoria: lo guardado y lo de más del día abierto (hoy)
local function Cost(c)
    local d = c.days[DayKey(HU.StampNow())]
    return (c.bytes or 0) + ((d and d.lines) and #d.lines * LINE_RAM or 0)
end

---------------------------------------------------------------------------
-- Huellas del relleno de huecos (ver «Rellenar huecos solos», más abajo). Se leen las líneas [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local HASH_MOD = 2147483647
local BUCKET = 600
local B_SEP, B_BAR, B_OFF = 31, 124, 111
local nameHash = setmetatable({}, { __mode = "k" })    -- [día] = { [id] = suma de "autor\1" }
local digestCache = setmetatable({}, { __mode = "k" }) -- [día] = { n, base, lo, hi, cn = {}, ch = {} }

local function NameHash(day, id)
    local t = nameHash[day]
    if not t then t = {}; nameHash[day] = t end
    local h = t[id]
    if not h then
        h = 5381
        local s = (day.names[id] or "?"):lower()
        for i = 1, #s do h = (h * 33 + s:byte(i)) % HASH_MOD end
        h = (h * 33 + 1) % HASH_MOD
        t[id] = h
    end
    return h
end

local function IsDigit(b) return b and b >= 48 and b <= 57 end
local function IsLetter(b) return b and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122)) end

-- La línea de s que va de p a e (sin e): su momento y su huella; nil si es del chat de oficiales o está rota
local function LineDigest(day, s, p, e)
    local b = s:byte(p)
    if not IsDigit(b) then return nil end
    local sec = 0
    while IsDigit(b) do sec = sec * 10 + b - 48; p = p + 1; b = s:byte(p) end
    if b ~= B_SEP then return nil end
    local code = s:byte(p + 1)
    if not IsLetter(code) or code == B_OFF or s:byte(p + 2) ~= B_SEP then return nil end
    p = p + 3
    b = s:byte(p)
    while b and b ~= B_SEP and p < e do p = p + 1; b = s:byte(p) end
    if b ~= B_SEP then return nil end
    p = p + 1
    b = s:byte(p)
    if not IsDigit(b) then return nil end
    local id = 0
    while IsDigit(b) do id = id * 10 + b - 48; p = p + 1; b = s:byte(p) end
    if b ~= B_SEP then return nil end
    p = p + 1
    local h0 = NameHash(day, id)
    local h = h0
    -- (lo que se compara: los primeros KEY_LEN bytes sin partir una letra, como hace Utf8Cut)
    local cut = e - p
    if cut > KEY_LEN then
        cut = KEY_LEN
        while cut > 0 do
            local c = s:byte(p + cut)
            if c < 128 or c >= 192 then break end
            cut = cut - 1
        end
    end
    for i = p, p + cut - 1 do
        local c = s:byte(i)
        if c == B_BAR then
            -- (con | por medio, MatchText las junta: caso raro, se hace como antes)
            local m = MatchText(s:sub(p, e - 1))
            h = h0
            for j = 1, #m do h = (h * 33 + m:byte(j)) % HASH_MOD end
            break
        end
        h = (h * 33 + c) % HASH_MOD
    end
    return day.s + sec, h
end

local function DigestAdd(dc, t, h)
    local j = math.floor(t / BUCKET) - dc.base
    local n = dc.cn[j]
    if n then
        dc.cn[j] = n + 1
        dc.ch[j] = (dc.ch[j] + h) % HASH_MOD
    else
        dc.cn[j], dc.ch[j] = 1, h
    end
    if t < dc.lo then dc.lo = t end
    if t > dc.hi then dc.hi = t end
end

-- Antes de sumar una línea al día (day.n aún sin subir). appended: va al final (HistRecord); si se
-- mete por medio mientras se está recorriendo el día, la suma ya no vale y se rehará
local function DigestOnAdd(day, line, appended)
    local dc = digestCache[day]
    if not dc then return end
    if dc.n ~= day.n or (dc.building and not appended) then dc.n = -1 return end
    local t, h = LineDigest(day, line, 1, #line + 1)
    if t then DigestAdd(dc, t, h) end
    dc.n = day.n + 1
end

-- Quita lo más viejo de un día (solo hoy, cuando ya no cabe ni él solo). Devuelve lo liberado
local function TrimDay(day, want)
    if not day.lines then day.lines = DayLines(day); day.chunks = nil end
    local lines = day.lines
    local n = #lines
    local r, freed, bytes = 0, 0, 0
    while r < n and freed < want do
        r = r + 1
        bytes = bytes + #lines[r] + 8
        freed = freed + #lines[r] + 8 + LINE_RAM
    end
    if r == 0 then return 0 end
    for i = 1, n - r do lines[i] = lines[i + r] end
    for i = n, n - r + 1, -1 do lines[i] = nil end
    day.n = math.max(0, (day.n or 0) - r)
    day.b = math.max(0, (day.b or 0) - bytes)
    digestCache[day] = nil
    return freed, bytes
end

-- Borra lo de más de 30 días (2 si no soy oficial) y, si se pasa del tope, los días más viejos; si
-- hoy solo ya no cabe, lo más viejo de hoy (antes se borraba hoy entero)
function HU:HistPrune()
    local s = Store()
    if not s then return end
    local mine = CommunityKey()
    if not mine then return end -- (aún no sé de qué comunidad soy ni mi rango: no se borra nada)
    local today = DayKey(HU.StampNow())
    for key, c in pairs(s) do
        local keepDays, cap = DAYS, OTHER_BYTES
        if key == mine then keepDays, cap = KeepDays(), MaxBytes() end
        local oldest = DayKey(HU.StampNow() - keepDays * 86400)
        local bytes = 0
        for k, d in pairs(c.days) do
            if k < oldest then c.days[k] = nil
            else
                if k ~= today then Compact(d) end
                bytes = bytes + (d.b or 0)
            end
        end
        c.bytes = bytes
        local total = Cost(c)
        if total > cap then
            for _, k in ipairs(SortedDays(c)) do
                if total <= cap * 0.9 then break end
                local d = c.days[k]
                if k == today then
                    local freed, b = TrimDay(d, total - cap * 0.9)
                    total = total - freed
                    c.bytes = c.bytes - (b or 0)
                    break
                end
                total = total - (d.b or 0)
                c.bytes = c.bytes - (d.b or 0)
                c.days[k] = nil
            end
        end
    end
end

-- Para el tope de memoria (MemGuard.lua): soltar lo que se puede rehacer y borrar el día más viejo
function HU:HistDropCaches()
    for k in pairs(splitCache) do splitCache[k] = nil end
    for k in pairs(idxCache) do idxCache[k] = nil end
    for k in pairs(digestCache) do digestCache[k] = nil end
    for k in pairs(nameHash) do nameHash[k] = nil end
end
function HU:HistDropOldestDay()
    local c = Community(false)
    if not c then return false end
    local keys = SortedDays(c)
    if #keys == 0 then return false end
    local d = c.days[keys[1]]
    if #keys == 1 then
        -- (solo queda hoy: se quita su cuarta parte más vieja, pero no baja de 2.000 líneas)
        if not d or (d.n or 0) <= 2000 then return false end
        local _, b = TrimDay(d, ((d.b or 0) + (d.n or 0) * LINE_RAM) * 0.25)
        c.bytes = math.max(0, (c.bytes or 0) - (b or 0))
        return true
    end
    c.bytes = math.max(0, (c.bytes or 0) - ((d and d.b) or 0))
    c.days[keys[1]] = nil
    return true
end

---------------------------------------------------------------------------
-- Guardar: todo lo que llega al historial del chat, si soy oficial
---------------------------------------------------------------------------
function HU:HistRecord(kind, tag, author, msg)
    if not self:HistEnabled() or not author or not msg then return end
    local code = KIND_CODE[kind]
    if not code then return end
    -- (quien no es oficial guarda solo el chat de hermandad y buscar grupo, 2 días)
    if not IAmOfficer() and code == "o" then return end
    local c = Community(true)
    if not c then return end
    local now = HU.StampNow()
    local dk = DayKey(now)
    local day = c.days[dk]
    if not day then
        day = { s = DayStart(now), n = 0, b = 0, names = {}, lines = {} }
        c.days[dk] = day
        -- (día nuevo: los anteriores se cierran en un solo texto)
        for k, d in pairs(c.days) do if k ~= dk then Compact(d) end end
    end
    if not day.lines then day.lines = DayLines(day); day.chunks = nil end
    local idx = DayIndex(day)
    local key = author:lower()
    local id = idx[key]
    if not id then
        id = #day.names + 1
        day.names[id] = author
        idx[key] = id
    end
    local line = table.concat({ now - day.s, code, tag or "", id, HU.Utf8Cut(Clean(msg), 255) }, SEP)
    DigestOnAdd(day, line, true)
    day.lines[#day.lines + 1] = line
    day.n = day.n + 1
    day.b = day.b + #line + 8
    c.bytes = (c.bytes or 0) + #line + 8
    if c.bytes + #day.lines * LINE_RAM > MaxBytes() then self:HistPrune() end
end

-- Mete un mensaje recibido de otro (relleno de huecos) en su día y en su sitio por hora; si ya
-- está (mismo autor y texto a menos de 2 min), no se repite. Devuelve true si se ha añadido.
function HU:HistInsert(e)
    if not self:HistEnabled() or not e or not e.a or not e.m or not e.t then return false end
    local code = KIND_CODE[e.k or "main"]
    if not code or code == "o" then return false end
    if e.t < HU.StampNow() - KeepDays() * 86400 or e.t > HU.StampNow() + 300 then return false end
    local c = Community(true)
    if not c then return false end
    local dk = DayKey(e.t)
    -- (ya no cabe más: no se rellenan días más viejos que el más viejo que guardo, que se
    -- borrarían enseguida y se volverían a pedir)
    if Cost(c) >= MaxBytes() * 0.85 then
        local first = SortedDays(c)[1]
        if first and dk <= first then return false end
    end
    local day = c.days[dk]
    if not day then
        day = { s = DayStart(e.t), n = 0, b = 0, names = {}, lines = {} }
        c.days[dk] = day
    end
    if not day.lines then day.lines = DayLines(day); day.chunks = nil end
    local idx = DayIndex(day)
    local key = e.a:lower()
    local id = idx[key]
    if not id then
        id = #day.names + 1
        day.names[id] = e.a
        idx[key] = id
    end
    local sec = e.t - day.s
    local msg = HU.Utf8Cut(Clean(e.m), 255)
    -- Las líneas van ordenadas por segundo: el sitio se busca por bisección y los repetidos se miran [+ARCHITECTURE.md]
    local lines = day.lines
    local n = #lines
    local key = MatchText(msg)
    local function secAt(i) return tonumber(lines[i]:match("^(%d+)")) or 0 end
    local lo, hi = 1, n + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if secAt(mid) > sec then hi = mid else lo = mid + 1 end
    end
    local pos = lo -- (primera línea con segundo mayor: detrás de las del mismo segundo)
    local function same(i)
        local s2, lid, m2 = lines[i]:match("^(%d+)\31%a\31[^\31]*\31(%d+)\31(.*)$")
        s2 = tonumber(s2) or 0
        if math.abs(s2 - sec) > 120 then return nil, s2 end
        return (tonumber(lid) == id and (m2 == msg or MatchText(m2) == key)), s2
    end
    local i = pos - 1
    while i >= 1 do
        local dup = same(i)
        if dup == nil then break end
        if dup then return false end
        i = i - 1
    end
    i = pos
    while i <= n do
        local dup = same(i)
        if dup == nil then break end
        if dup then return false end
        i = i + 1
    end
    local line = table.concat({ sec, code, e.tag or "", id, msg }, SEP)
    DigestOnAdd(day, line, pos > n)
    table.insert(lines, pos, line)
    day.n = day.n + 1
    day.b = day.b + #line + 8
    c.bytes = (c.bytes or 0) + #line + 8
    if Cost(c) > MaxBytes() then self:HistPrune() end
    return true
end

local function ParseLine(day, line)
    local sec, code, tag, id, msg = line:match("^(%d+)\31(%a)\31([^\31]*)\31(%d+)\31(.*)$")
    if not sec then return nil end
    return { t = day.s + tonumber(sec), k = CODE_KIND[code] or "main", tag = (tag ~= "" and tag) or nil,
        a = day.names[tonumber(id)] or "?", m = msg }
end

---------------------------------------------------------------------------
-- Buscar en mi PC (por trozos, para no dar tirones con 30 días) [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local function NameMatcher(name)
    if not name or name == "" then return nil end
    local full = (HU:FullName(name) or name):lower()
    local first = name:lower():match("^([^%-%s]+)")
    return function(n)
        local k = n:lower()
        if k == full then return true end
        -- solo el nombre (sin apellido ni reino): vale si coincide la primera parte
        return not name:find("[%-%s]") and k:match("^([^%-]+)") == first
    end
end

-- Recorre las líneas de un día en orden (día abierto: su lista; día cerrado: bloque a bloque)
local function EachLine(day, fn)
    if day.lines then
        for i, l in ipairs(day.lines) do if fn(i, l) then return end end
        return
    end
    local i = 0
    for _, ch in ipairs(day.chunks or {}) do
        for _, l in ipairs(SplitChunk(ch)) do
            i = i + 1
            if fn(i, l) then return end
        end
    end
end

function HU:HistSearchLocal(opts, done)
    local c = Community(false)
    local out = {}
    if not c then return done(out) end
    local match = NameMatcher(opts.name)
    local text = opts.text and opts.text ~= "" and HU.Fold(opts.text) or nil
    local sinceKey = opts.since and DayKey(opts.since) or "0"
    local keys = SortedDays(c)
    local di = #keys
    local day, ids, li, ci, cl
    local function test(line, i)
        local id = line:match("^%d+\31%a\31[^\31]*\31(%d+)\31")
        if ids and not ids[id] then return nil end
        local e = ParseLine(day, line)
        if e and (not opts.since or e.t >= opts.since) and (not text or HU.Fold(e.m):find(text, 1, true))
            and (not opts.kinds or opts.kinds[e.k]) then
            e.day, e.i = day, i
            return e
        end
    end
    local function step()
        local budget = SLICE
        while budget > 0 do
            if not day then
                if di < 1 or keys[di] < sinceKey or #out >= MAX_LOCAL then return done(out) end
                day = c.days[keys[di]]
                di = di - 1
                ids = nil
                if match then
                    ids = {}
                    for i, n in ipairs(day.names) do if match(n) then ids[tostring(i)] = true end end
                    if not next(ids) then day = nil end
                end
                if day then
                    if day.lines then li = #day.lines else ci, cl = #(day.chunks or {}), nil end
                end
            elseif day.lines then
                -- día abierto: de la más nueva a la más vieja
                if li < 1 then day = nil
                else
                    local e = test(day.lines[li], li)
                    if e then
                        out[#out + 1] = e
                        if #out >= MAX_LOCAL then return done(out) end
                    end
                    li = li - 1
                    budget = budget - 1
                end
            else
                -- día cerrado: bloque a bloque, del último al primero
                if not cl then
                    if ci < 1 then day = nil
                    else cl = SplitChunk(day.chunks[ci]); li = #cl end
                elseif li < 1 then
                    cl = nil
                    ci = ci - 1
                else
                    local e = test(cl[li], (ci - 1) * CHUNK + li)
                    if e then
                        out[#out + 1] = e
                        if #out >= MAX_LOCAL then return done(out) end
                    end
                    li = li - 1
                    budget = budget - 1
                end
            end
        end
        C_Timer.After(0, function() Guarded("buscar", step) end)
    end
    step()
end

-- Las líneas de alrededor de un mensaje guardado en mi PC
function HU:HistContextLocal(day, i, n)
    local out = {}
    n = n or CONTEXT
    EachLine(day, function(j, line)
        if j > i + n then return true end
        if j >= i - n then
            local e = ParseLine(day, line)
            if e then e.focus = (j == i); out[#out + 1] = e end
        end
    end)
    return out
end

-- Busca un mensaje por hora y autor (para dar el contexto a otro oficial)
local function FindLine(t, author)
    local c = Community(false)
    if not c then return nil end
    local day = c.days[DayKey(t)]
    if not day then return nil end
    local id = DayIndex(day)[author:lower()]
    if not id then return nil end
    local best, bestD
    local want = t - day.s
    EachLine(day, function(i, line)
        local sec, lid = line:match("^(%d+)\31%a\31[^\31]*\31(%d+)\31")
        if tonumber(lid) == id then
            local d = math.abs(tonumber(sec) - want)
            if not bestD or d < bestD then best, bestD = i, d end
        end
    end)
    if best and bestD <= 120 then return day, best end
    return nil
end

---------------------------------------------------------------------------
-- Envío propio (su propio prefijo y su propia cola: nunca frena las listas ni el chat)
---------------------------------------------------------------------------
local hq, htokens = {}, 8
local HQ_MAX = 400
local HQ_RESERVE = 20 -- plazas solo para los cierres: una respuesta nunca se queda sin su final
-- (cada mensaje caduca: una comparación o una búsqueda de hace minutos ya no le sirve a nadie)
local TTL_SYNC, TTL_ASK = 300, 60
local CMD_TTL = { V = TTL_SYNC, v = TTL_SYNC, w = TTL_SYNC, S = TTL_SYNC, D = TTL_SYNC, F = TTL_SYNC,
    Q = TTL_ASK, R = TTL_ASK, E = TTL_ASK, X = TTL_ASK, Y = TTL_ASK, Z = TTL_ASK }
local CLOSER = { w = true, F = true, E = true, Z = true }
-- lo que el juego contesta cuando va saturado (como en Comm.lua): el mensaje se vuelve a probar
local THROTTLED = {}
if Enum and Enum.SendAddonMessageResult then
    for _, k in ipairs({ "AddonMessageThrottle", "ChannelThrottle", "GeneralError" }) do
        if Enum.SendAddonMessageResult[k] then THROTTLED[Enum.SendAddonMessageResult[k]] = true end
    end
end

-- Contadores (/gu y el banco): lo enviado, lo que no cupo, lo caducado, los reintentos por
-- saturación, las respuestas que no se mandaron por no caber enteras y los trozos que llegaron cojos
local function Stats()
    HU.qStats = HU.qStats or {}
    local s = HU.qStats.hist
    if not s then
        s = { sent = 0, dropped = 0, expired = 0, throttled = 0, refused = 0, short = 0 }
        HU.qStats.hist = s
    end
    return s
end

local function Expired(m, now) return now - m.t >= (CMD_TTL[m.cmd] or TTL_SYNC) end
local function Sweep()
    local now, j = GetTime(), 0
    for i = 1, #hq do
        local m = hq[i]
        if Expired(m, now) then Stats().expired = Stats().expired + 1
        else j = j + 1; hq[j] = m end
    end
    for i = #hq, j + 1, -1 do hq[i] = nil end
end

-- ¿Caben n mensajes más (y su cierre, que va en la reserva)?
local function HasRoom(n)
    if #hq + n > HQ_MAX then Sweep() end
    return #hq + n <= HQ_MAX
end

local function HSend(msg, target)
    local cmd = msg:match("^(%a)")
    local cap = HQ_MAX + (CLOSER[cmd] and HQ_RESERVE or 0)
    if #hq >= cap then Sweep() end
    if #hq >= cap then
        Stats().dropped = Stats().dropped + 1
        return false
    end
    hq[#hq + 1] = { HU.Utf8Cut(msg, 255), target, cmd = cmd, t = GetTime() }
    return true
end
local function HFlush()
    if HU:IsChatLockedDown() then return end
    local now = GetTime()
    while htokens >= 1 and #hq > 0 do
        local m = table.remove(hq, 1)
        if Expired(m, now) then
            Stats().expired = Stats().expired + 1
        else
            -- (en pausa por la versión mínima: no sale nada del addon)
            if HU.paused then htokens = htokens - 1 break end
            if HU.MarkPinged then HU:MarkPinged(m[2]) end
            local ok, r = pcall(C_ChatInfo.SendAddonMessage, HU.HPREFIX, m[1], "WHISPER", m[2])
            htokens = htokens - 1
            if ok and (r == false or (type(r) == "number" and THROTTLED[r])) then
                -- (saturado: vuelve el primero y se espera a la vuelta siguiente; hasta que caduque)
                Stats().throttled = Stats().throttled + 1
                table.insert(hq, 1, m)
                break
            end
            if ok then Stats().sent = Stats().sent + 1 else Stats().dropped = Stats().dropped + 1 end
        end
    end
end
local function Pack(cmd, ...)
    local t = { cmd }
    for i = 1, select("#", ...) do t[#t + 1] = Clean(select(i, ...)) end
    return table.concat(t, "~")
end

---------------------------------------------------------------------------
-- Pedir a otros oficiales lo que no vi
---------------------------------------------------------------------------
-- Oficiales conectados de todas las hermandades (primero los de la mía)
function HU:HistOfficersOnline(limit)
    local me, out, seen = self:MeKey(), {}, {}
    local function add(name, tag, rank)
        local k = name and name:lower()
        if not k or k == me or seen[k] or not self:RankRole(tag, rank) then return end
        seen[k] = true
        out[#out + 1] = name
    end
    for _, e in ipairs(self.rosterList or {}) do
        if e.online then add(e.name, self.myTag, e.rankIndex) end
    end
    local others = {}
    for tag, r in pairs(self.remoteRoster) do
        for _, m in ipairs(r.members or {}) do
            if self:RankRole(tag, m.rankIndex) then others[#others + 1] = { m.name, tag, m.rankIndex } end
        end
    end
    -- (de las otras hermandades, unos cuantos al azar)
    for i = #others, 2, -1 do
        local j = math.random(i)
        others[i], others[j] = others[j], others[i]
    end
    for _, o in ipairs(others) do add(o[1], o[2], o[3]) end
    while #out > (limit or 8) do table.remove(out) end
    return out
end

-- Compañeros de mi hermandad con el addon conectados (no oficiales), unos cuantos al azar
function HU:HistMembersOnline(limit)
    local me, out = self:MeKey(), {}
    for k, p in pairs(self.guildPeers or {}) do
        local r = self.roster[k]
        if k ~= me and GetTime() - p.last < HU.PEER_TTL and (not r or r.online) and not (r and self:RankRole(self.myTag, r.rankIndex)) then
            out[#out + 1] = p.name
        end
    end
    for i = #out, 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    while #out > (limit or 6) do table.remove(out) end
    return out
end

local pending = {}  -- [id] = { results, onResult, onDone, waiting }
local function NewId() return tostring(math.random(100000, 999999)) end

-- results: lista; cada resultado { t, k, tag, a, m, from = { nombre = true } }
function HU:HistSearchRemote(opts, onUpdate, onDone)
    local id = NewId()
    local targets = self:HistOfficersOnline(8)
    -- (pocos oficiales conectados: también a unos compañeros con el addon, que guardan 2 días)
    if #targets < 2 then
        for _, n in ipairs(self:HistMembersOnline(6)) do targets[#targets + 1] = n end
    end
    local p = { results = {}, onUpdate = onUpdate, onDone = onDone, waiting = {}, n = 0 }
    pending[id] = p
    local nAsked = 0
    for _, name in ipairs(targets) do
        -- (si no cabe en la cola, a ese no se le espera)
        if HSend(Pack("Q", id, opts.name or "", opts.since or 0, opts.text or ""), name) then
            p.waiting[name:lower()] = true
            nAsked = nAsked + 1
        end
    end
    HFlush()
    local function finish()
        if pending[id] ~= p then return end
        pending[id] = nil
        if p.onDone then p.onDone(p.results, #targets) end
    end
    if nAsked == 0 then return finish() end
    HU.After(45, finish)
    p.finish = finish
    return #targets
end

-- dos copias del mismo mensaje: mismo autor y texto con menos de 2 minutos de diferencia
local function SameMsg(a, b)
    return a.a:lower() == b.a:lower() and MatchText(a.m) == MatchText(b.m) and math.abs(a.t - b.t) < 120
end
local function MsgKey(e) return (e.a or ""):lower() .. "\1" .. MatchText(e.m) end
function HU:HistMerge(list, e, from)
    -- (índice por autor y texto, guardado en la propia lista: se crea la primera vez)
    local idx = list.__idx
    if not idx then
        idx = {}
        for _, r in ipairs(list) do
            local k = MsgKey(r)
            local b = idx[k]
            if not b then b = {}; idx[k] = b end
            b[#b + 1] = r
        end
        list.__idx = idx
    end
    local k = MsgKey(e)
    local b = idx[k]
    if b then
        for _, r in ipairs(b) do
            if SameMsg(r, e) then
                if from then r.from = r.from or {}; r.from[from:lower()] = true end
                return false
            end
        end
    else
        b = {}
        idx[k] = b
    end
    if from then e.from = { [from:lower()] = true } end
    list[#list + 1] = e
    b[#b + 1] = e
    return true
end

local function Answer(sender, id, name, since, text)
    HU:HistSearchLocal({ name = name, since = since > 0 and since or nil, text = text, kinds = { main = true, lfg = true } }, function(res)
        -- (entera o nada: con la cola llena no se contesta y quien pregunta se queda con lo demás)
        if not HasRoom(math.min(#res, MAX_REMOTE)) then Stats().refused = Stats().refused + 1 return end
        local n = 0
        for _, e in ipairs(res) do
            if n >= MAX_REMOTE then break end
            if HSend(Pack("R", id, e.t, e.k, e.tag or "", e.a, e.m), sender) then n = n + 1 end
        end
        HSend(Pack("E", id, n), sender)
        HFlush()
    end)
end

local function AnswerContext(sender, id, t, author)
    local day, i = FindLine(t, author)
    local lines = day and HU:HistContextLocal(day, i, CONTEXT) or {}
    local want = 0
    for _, e in ipairs(lines) do if e.k ~= "off" then want = want + 1 end end
    if not HasRoom(want) then Stats().refused = Stats().refused + 1 return end
    local n = 0
    for _, e in ipairs(lines) do
        if e.k ~= "off" then
            HSend(Pack("Y", id, e.t, e.k, e.tag or "", e.a, e.m, e.focus and "1" or ""), sender)
            n = n + 1
        end
    end
    HSend(Pack("Z", id, n), sender)
    HFlush()
end

-- Pide a otro oficial las líneas de alrededor de un mensaje que me dio él
function HU:HistContextRemote(e, onDone)
    local from = e.from and next(e.from)
    if not from then return onDone(nil) end
    local id = NewId()
    local p = { lines = {}, onDone = onDone, ctx = true }
    pending[id] = p
    if not HSend(Pack("X", id, e.t, e.a), from) then pending[id] = nil; return onDone(nil) end
    HFlush()
    HU.After(30, function()
        if pending[id] == p then pending[id] = nil; onDone(p.lines) end
    end)
end

-- Quién puede preguntar: un oficial de una de las hermandades (se comprueba en cada petición).
-- Contesta cualquiera con el addon (los miembros, con sus 2 días de chat de hermandad)
local asked = {} -- [quien..petición] = último momento
local perMin = {} -- [quien] = { t, n }
local function Allowed(sender, cmd, key)
    local ok = HU:TrustedOfficer(sender)
    if ok ~= true then return false end
    local who, now = sender:lower(), GetTime()
    local r = perMin[who]
    if not r or now - r.t > 60 then r = { t = now, n = 0 }; perMin[who] = r end
    r.n = r.n + 1
    if r.n > 60 then return false end
    local k = who .. cmd .. (key or "")
    if asked[k] and now - asked[k] < 10 then return false end -- (la misma petición, una cada 10 s)
    asked[k] = now
    -- (que la tabla no crezca sin límite)
    if r.n == 1 then for key2, t in pairs(asked) do if now - t > 60 then asked[key2] = nil end end end
    return true
end

---------------------------------------------------------------------------
-- Rellenar huecos solos (idea de GuildManagement, probada en Forever). Cada 5 minutos, un oficial [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local SYNC_EVERY = 300
local SYNC_TIMEOUT = 30
local SYNC_MAX_STEPS = 24   -- peticiones por compañero y vuelta
local SYNC_MAX_LINES = 400  -- líneas que se piden como mucho por trozo
local SYNC_PULLED_TTL = 3600 -- un trozo ya traído no se vuelve a pedir en una hora (aunque su huella no cuadre)
local SYNC_AGAIN = 30       -- quedó trabajo (tope de pasos) o se calló el compañero: otra vuelta enseguida
local SYNC_MAX_FAST = 10    -- vueltas seguidas así como mucho; luego, a las 5 min de siempre
local sync                  -- la comparación en curso { peer, id, steps, queue, cur, lines }
local pulled = {}           -- [k:tam:huella] = cuándo llegaron sus líneas (no cuándo se pidió)
local lastSync = -1e9
local fastRounds = 0

-- Recorre las líneas de un día sin crear textos: fn(s, p, e) con la línea de s entre p y e (sin e). [+ARCHITECTURE.md]
local function DayScanner(day, fn)
    local lines, chunks = day.lines, day.chunks
    local last = lines and #lines or 0
    local li, ci, pos = 0, 1, 1
    return function(budget)
        if lines then
            while budget > 0 do
                li = li + 1
                local s = li <= last and lines[li]
                if not s then return true, budget end
                fn(s, 1, #s + 1)
                budget = budget - 1
            end
            return false, budget
        end
        while budget > 0 do
            local ch = chunks and chunks[ci]
            if not ch then return true, budget end
            local e = ch:find("\n", pos, true) or (#ch + 1)
            fn(ch, pos, e)
            budget = budget - 1
            if e > #ch then ci, pos = ci + 1, 1 else pos = e + 1 end
        end
        return false, budget
    end
end

-- Huellas de [a, b): [k] = { n, h } (solo trozos con algo; sin el chat de oficiales). [+ARCHITECTURE.md]
local function DigestsAsync(a, b, size, done)
    local c = Community(false)
    local out = {}
    if not c then return done(out) end
    local dk0, dk1 = DayKey(a), DayKey(b)
    local keys = {}
    for _, dk in ipairs(SortedDays(c)) do if dk >= dk0 and dk <= dk1 then keys[#keys + 1] = dk end end
    local function put(t, n, h)
        local k = math.floor(t / size)
        local d = out[k]
        if not d then d = { n = 0, h = 0 }; out[k] = d end
        d.n = d.n + n
        d.h = (d.h + h) % HASH_MOD
    end
    local di, day, dc, part, scan, building = 0, nil, nil, nil, nil, false
    -- (los tramos enteros dentro de [a, b) van de golpe; true si queda alguno a medias)
    local function apply()
        part = nil
        for j, n in pairs(dc.cn) do
            local bs = (dc.base + j) * BUCKET
            local lo, hi = math.max(bs, dc.lo), math.min(bs + BUCKET - 1, dc.hi)
            if lo >= a and hi < b then put(bs, n, dc.ch[j])
            elseif hi >= a and lo < b then part = part or {}; part[j] = true end
        end
        return part ~= nil
    end
    local function exact(s, p, e)
        local t, h = LineDigest(day, s, p, e)
        if t and t >= a and t < b and (not part or part[math.floor(t / BUCKET) - dc.base]) then put(t, 1, h) end
    end
    local function build(s, p, e)
        local t, h = LineDigest(day, s, p, e)
        if t then DigestAdd(dc, t, h) end
    end
    local tick
    local function step()
        -- (en combate en banda o mazmorra se espera: ver Combat.lua)
        if HU.CombatHold and HU:CombatHold() then C_Timer.After(0.5, tick) return end
        local budget = DIGEST_SLICE
        -- (y como mucho DIGEST_CAP.MS de trabajo, mirado cada DIGEST_CAP.SUB líneas: 300 líneas eran 4-10 ms en un
        -- fotograma, y se notaba al acabar cada pull, cuando el relleno vuelve a arrancar)
        local clock = DIGEST_CAP.clock
        local t0 = clock()
        while budget > 0 and clock() - t0 < DIGEST_CAP.MS do
            if scan then
                local finished, left
                local sub = math.min(budget, DIGEST_CAP.SUB)
                finished, left = scan(sub)
                budget = budget - sub + left
                if finished then
                    scan = nil
                    if building then
                        building = false
                        dc.building = nil
                        if apply() then scan = DayScanner(day, exact) else day = nil end
                    else
                        day = nil
                    end
                end
            elseif day then
                day = nil
            else
                di = di + 1
                local dk = keys[di]
                if not dk then return done(out) end
                day = c.days[dk]
                dc, part = digestCache[day], nil
                if not day then
                    -- (borrado mientras tanto)
                elseif dc and dc.building then
                    -- (otra cuenta lo está sumando ahora mismo: este día, línea a línea)
                    scan = DayScanner(day, exact)
                elseif dc and dc.n == day.n then
                    budget = budget - 10
                    if apply() then scan = DayScanner(day, exact) else day = nil end
                else
                    dc = { n = day.n, base = math.floor(day.s / BUCKET), lo = math.huge, hi = -math.huge, cn = {}, ch = {}, building = true }
                    digestCache[day] = dc
                    building = true
                    scan = DayScanner(day, build)
                end
            end
        end
        -- (un paso cada 30 ms, no cada fotograma: así el rellenado no se come 170 ms de un mismo segundo)
        C_Timer.After(0.03, tick)
    end
    tick = function() Guarded("huellas", step) end
    -- (también el primer trozo en otro fotograma: así quien lo pide no carga con él)
    C_Timer.After(0.03, tick)
end

-- las líneas de un trozo (para contestar S). Las líneas van por hora: se para al pasar el trozo
local function ChunkLines(k, size, limit)
    local c = Community(false)
    local out = {}
    if not c then return out end
    local a, b = k * size, (k + 1) * size
    local ka, kb = DayKey(a), DayKey(b)
    for _, dk in ipairs(SortedDays(c)) do
        if dk >= ka and dk <= kb then
            local day = c.days[dk]
            local lo, hi = a - day.s, b - day.s
            local past = false
            local scan = DayScanner(day, function(s, p, e)
                if past or #out >= limit then return end
                -- (primero solo el segundo, leído sin crear texto: no se analiza entera cada línea)
                local sec, q = 0, p
                local ch = s:byte(q)
                while IsDigit(ch) do sec = sec * 10 + ch - 48; q = q + 1; ch = s:byte(q) end
                if q == p then return end
                if sec >= hi then past = true
                elseif sec >= lo then
                    local ev = ParseLine(day, s:sub(p, e - 1))
                    if ev and ev.k ~= "off" then out[#out + 1] = ev end
                end
            end)
            repeat local finished = scan(500) until finished or past or #out >= limit
            if #out >= limit then break end
        end
    end
    return out
end

local function SendDigestTable(target, id, size, dg)
    local parts, cur, curLen = {}, {}, 0
    local head = #("v~" .. id .. "~" .. size .. "~")
    local keys = {}
    for k in pairs(dg) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local item = k .. ":" .. dg[k].n .. ":" .. dg[k].h
        if #cur > 0 and head + curLen + 1 + #item > 250 then
            parts[#parts + 1] = table.concat(cur, ",")
            cur, curLen = {}, 0
        end
        curLen = curLen + (#cur > 0 and 1 or 0) + #item
        cur[#cur + 1] = item
    end
    if #cur > 0 then parts[#parts + 1] = table.concat(cur, ",") end
    -- (unas huellas a medias harían creer que lo que falta está bien: enteras o nada)
    if not HasRoom(#parts) then Stats().refused = Stats().refused + 1 return end
    for _, p in ipairs(parts) do HSend(Pack("v", id, size, p), target) end
    HSend(Pack("w", id), target)
    HFlush()
end
local function SendDigests(target, id, size, a, b)
    DigestsAsync(a, b, size, function(dg) SendDigestTable(target, id, size, dg) end)
end

local function SyncNext()
    if not sync then return end
    local s = sync
    if s.steps >= SYNC_MAX_STEPS or #s.queue == 0 then
        if s.lines > 0 then HU:Debug("Historial: " .. s.lines .. " líneas rellenadas de " .. HU:Short(s.peer)) end
        sync = nil
        -- (se acabaron los pasos con cosas en la cola: un hueco grande. Se sigue con el mismo [+ARCHITECTURE.md]
        local wantLines = #s.queue > 0 and s.lines > 0
        for _, q in ipairs(s.queue) do if q.kind == "S" then wantLines = true break end end
        if wantLines and fastRounds < SYNC_MAX_FAST then
            fastRounds = fastRounds + 1
            HU.After(SYNC_AGAIN, function() Guarded("rellenar", HU.HistStartSync, HU, true, s.peer) end)
        end
        return
    end
    s.steps = s.steps + 1
    local q = table.remove(s.queue, 1)
    s.cur = q
    s.theirs = {}
    s.got = 0
    s.startedAt = GetTime()
    -- (la cola del historial está llena: esta vuelta se deja y sigue la de dentro de 5 minutos;
    -- pulled no se toca, así lo pendiente se vuelve a pedir entonces)
    local function Full() if sync == s then sync = nil end end
    if q.kind == "V" then
        -- (las huellas se calculan por trozos y fotogramas: con 20.000 líneas de golpe eran 130-300 ms)
        DigestsAsync(q.a, q.b, q.size, function(dg)
            if sync ~= s or s.cur ~= q then return end
            s.mine = dg
            if not HSend(Pack("V", s.id, q.size, q.a, q.b), s.peer) then return Full() end
            HFlush()
        end)
    else
        if not HSend(Pack("S", s.id, q.k, q.size), s.peer) then return Full() end
        HFlush()
    end
    local function Watch()
        HU.After(SYNC_TIMEOUT, function()
            if sync ~= s or s.cur ~= q then return end
            if GetTime() - (s.lastHeard or s.startedAt) < SYNC_TIMEOUT then return Watch() end
            sync = nil -- (se ha callado: se prueba enseguida con otro, si lo hay)
            if fastRounds < SYNC_MAX_FAST then
                fastRounds = fastRounds + 1
                HU.After(2, function() Guarded("rellenar", HU.HistStartSync, HU, true, nil, s.peer) end)
            end
        end)
    end
    Watch()
end

-- Compara mis huellas con las suyas: lo distinto baja un nivel (día → hora → 10 min → líneas)
local function SyncCompare()
    local s = sync
    local q = s.cur
    local keys = {}
    for k in pairs(s.mine) do keys[k] = true end
    for k in pairs(s.theirs) do keys[k] = true end
    local list = {}
    for k in pairs(keys) do list[#list + 1] = k end
    table.sort(list, function(a, b) return a > b end) -- (lo más reciente primero)
    for _, k in ipairs(list) do
        local m, t = s.mine[k], s.theirs[k]
        -- (solo lo que él tiene y yo no, o distinto: se tira, no se empuja)
        if t and (not m or m.n ~= t.n or m.h ~= t.h) then
            local a, b = k * q.size, (k + 1) * q.size
            if q.size > 600 then
                s.queue[#s.queue + 1] = { kind = "V", size = (q.size == 86400) and 3600 or 600, a = a, b = b }
            else
                -- (se marca al llegar sus líneas, en F: si el compañero se calla o se acaban los
                -- pasos, se vuelve a pedir en la vuelta siguiente)
                local pk = k .. ":" .. q.size .. ":" .. t.h
                local got = pulled[pk]
                if not (got and GetTime() - got < SYNC_PULLED_TTL) then
                    s.queue[#s.queue + 1] = { kind = "S", k = k, size = q.size, pk = pk }
                end
            end
        end
    end
end

-- Con quién comparar: un oficial conectado o, si no hay, un compañero con el addon (2 días)
-- (want: seguir con ese compañero si sigue conectado; skip: no ese, que se acaba de callar)
local syncTurn = 0
function HU:HistStartSync(force, want, skip)
    if not self:HistEnabled() or not IAmOfficer() or sync or self:IsTest() then return false end
    if not force and GetTime() - lastSync < SYNC_EVERY * 0.9 then return false end
    lastSync = GetTime()
    -- (una vuelta normal, no de seguida: se vuelven a permitir las rápidas)
    if not want and not skip then fastRounds = 0 end
    -- (lo traído hace más de una hora se olvida: así la lista no crece sin fin)
    for pk, got in pairs(pulled) do
        if lastSync - got >= SYNC_PULLED_TTL then pulled[pk] = nil end
    end
    local peers = self:HistOfficersOnline(4)
    local memberDays = false
    if #peers == 0 then peers, memberDays = self:HistMembersOnline(3), true end
    if skip then
        local rest = {}
        for _, p in ipairs(peers) do if p:lower() ~= skip:lower() then rest[#rest + 1] = p end end
        peers = rest
    end
    if #peers == 0 then return false end
    syncTurn = syncTurn + 1
    local peer = peers[(syncTurn % #peers) + 1]
    if want then
        for _, p in ipairs(peers) do if p:lower() == want:lower() then peer = p break end end
    end
    local now = HU.StampNow()
    local from = now - (memberDays and MEMBER_DAYS or DAYS) * 86400
    -- (si ya no cabe más, solo desde el día más viejo que guardo: lo de antes se borraría enseguida)
    local c = Community(false)
    if c and Cost(c) >= MaxBytes() * 0.85 then
        local first = SortedDays(c)[1]
        if first and c.days[first].s > from then from = c.days[first].s end
    end
    sync = { peer = peer, id = NewId(), steps = 0, lines = 0, queue = { { kind = "V", size = 86400, a = from, b = now + 60 } } }
    SyncNext()
    return true
end

local function OnSyncMessage(cmd, f, sender)
    if cmd == "V" then
        if not Allowed(sender, cmd, table.concat({ f[1] or "", f[2] or "", f[3] or "" }, ":")) then return end
        local size, a, b = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
        if not (size and a and b) or (size ~= 86400 and size ~= 3600 and size ~= 600) or b - a > 32 * 86400 then return end
        SendDigests(sender, f[1], size, a, b)
    elseif cmd == "S" then
        if not Allowed(sender, cmd, (f[1] or "") .. ":" .. (f[2] or "")) then return end
        local k, size = tonumber(f[2]), tonumber(f[3])
        if not (k and size) or size ~= 600 then return end
        local lines = ChunkLines(k, size, SYNC_MAX_LINES)
        if not HasRoom(#lines) then Stats().refused = Stats().refused + 1 return end
        for _, e in ipairs(lines) do HSend(Pack("D", f[1], e.t, e.k, e.tag or "", e.a, e.m), sender) end
        HSend(Pack("F", f[1], #lines), sender)
        HFlush()
    elseif cmd == "v" or cmd == "w" or cmd == "D" or cmd == "F" then
        local s = sync
        if not s or f[1] ~= s.id or sender:lower() ~= s.peer:lower() or not s.cur then return end
        s.lastHeard = GetTime()
        if cmd == "v" then
            for item in (f[3] or ""):gmatch("[^,]+") do
                local k, n, h = item:match("^(%d+):(%d+):(%d+)$")
                if k then s.theirs[tonumber(k)] = { n = tonumber(n), h = tonumber(h) } end
            end
        elseif cmd == "w" then
            if s.cur.kind == "V" then SyncCompare() end
            s.cur = nil
            SyncNext()
        elseif cmd == "D" then
            s.got = (s.got or 0) + 1
            local e = { t = HU.NetT(f[2]) or 0, k = f[3] or "main", tag = (f[4] ~= "" and f[4]) or nil, a = HU.SafeName(f[5]) or "?", m = SafeRemote(f[6]) }
            -- (de alguien que no es oficial solo vale el chat de hermandad: el de oficiales no lo
            -- puede tener, y antes un raso colaba lo que quisiera en los 30 días de los oficiales)
            local trusted = HU:TrustedOfficer(sender) == true
            if trusted or e.k == "main" or e.k == "lfg" then
                if not trusted then e.src = sender end
                if HU:HistInsert(e) then s.lines = s.lines + 1 end
            end
        elseif cmd == "F" then
            -- (si se perdieron líneas por el camino, ese trozo no cuenta como traído: se vuelve a pedir)
            local n = tonumber(f[2])
            if n and (s.got or 0) < n then Stats().short = Stats().short + 1
            elseif s.cur.pk then pulled[s.cur.pk] = GetTime() end
            s.cur = nil
            SyncNext()
        end
    end
end

local function OnMessage(text, sender)
    local f = HU.Split(text, "~")
    local cmd = table.remove(f, 1)
    if cmd == "V" or cmd == "v" or cmd == "w" or cmd == "S" or cmd == "D" or cmd == "F" then
        OnSyncMessage(cmd, f, sender)
    elseif cmd == "Q" then
        if not Allowed(sender, cmd) then return end
        Answer(sender, f[1], f[2] or "", tonumber(f[3]) or 0, f[4] or "")
    elseif cmd == "X" then
        if not Allowed(sender, cmd) then return end
        local t = tonumber(f[2])
        if t and f[3] then AnswerContext(sender, f[1], t, f[3]) end
    elseif cmd == "R" or cmd == "E" or cmd == "Y" or cmd == "Z" then
        local p = pending[f[1]]
        if not p then return end
        -- (las respuestas de búsqueda solo valen para una búsqueda, y las de contexto para un contexto)
        if (cmd == "Y" or cmd == "Z") ~= (p.ctx == true) then return end
        -- (solo valen respuestas de un oficial, o de un compañero al que se preguntó; de este, solo
        -- el chat de hermandad, nunca el de oficiales)
        local officer = HU:TrustedOfficer(sender) == true
        if not officer and not (p.waiting and p.waiting[sender:lower()]) then return end
        if not officer and (cmd == "R" or cmd == "Y") and f[3] == "off" then return end
        if cmd == "R" then
            local e = { t = HU.NetT(f[2]) or 0, k = f[3] or "main", tag = (f[4] ~= "" and f[4]) or nil, a = HU.SafeName(f[5]) or "?", m = SafeRemote(f[6]) }
            if HU:HistMerge(p.results, e, sender) and p.onUpdate then p.onUpdate(p.results) end
        elseif cmd == "E" then
            p.waiting[sender:lower()] = nil
            if p.finish and not next(p.waiting) then p.finish() end
        elseif cmd == "Y" then
            p.lines[#p.lines + 1] = { t = HU.NetT(f[2]) or 0, k = f[3] or "main", tag = (f[4] ~= "" and f[4]) or nil, a = HU.SafeName(f[5]) or "?", m = SafeRemote(f[6]), focus = f[7] == "1" }
        elseif cmd == "Z" then
            pending[f[1]] = nil
            table.sort(p.lines, function(a, b) return a.t < b.t end)
            p.onDone(p.lines)
        end
    end
end

HU:On("CHAT_MSG_ADDON", function(prefix, text, dist, sender)
    if prefix ~= HU.HPREFIX or dist ~= "WHISPER" or type(text) ~= "string" or not HU:HistEnabled() then return end
    sender = HU:FullName(sender)
    if not sender or sender:lower() == HU:MeKey() then return end
    Guarded("mensaje", OnMessage, text, sender)
end)

---------------------------------------------------------------------------
-- Ventana: buscar, ver resultados y "ver en el chat"
---------------------------------------------------------------------------
local W
local OpenContext, Render

-- clase de cada nombre: lista del juego de mi hermandad y listas que ya tiene el addon de las otras
local classOf = {}
local function RefreshClasses()
    classOf = {}
    for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
        local name, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
        if name and class then classOf[HU:Key(name) or ""] = class end
    end
    for _, r in pairs(HU.remoteRoster or {}) do
        for _, m in ipairs(r.members or {}) do
            if m.name and m.class then classOf[HU:Key(m.name) or ""] = m.class end
        end
    end
end

-- (si no se sabe la clase, en naranja, como en el chat)
local function NameColored(name)
    local r, g, b = HU.ClassRGB(classOf[HU:Key(name) or ""])
    local hex = r and string.format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)) or "ff9933"
    return "|cff" .. hex .. HU:Nice(name) .. "|r"
end

-- Dónde está lo buscado en un trozo de texto sin códigos (sin mirar mayúsculas ni acentos): añade a
-- out los pares { primer byte, último byte } en el texto original, sumándoles base
local function SpansPlain(s, q, base, out)
    local starts, folded, fpos = {}, {}, {}
    local bpos, pos = 1, 1
    for c in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        starts[#starts + 1] = bpos
        fpos[#fpos + 1] = pos
        local f = HU.Fold(c)
        folded[#folded + 1] = f
        pos = pos + #f
        bpos = bpos + #c
    end
    starts[#starts + 1] = bpos
    local F = table.concat(folded)
    local byF = {}
    for i, p in ipairs(fpos) do byF[p] = i end
    byF[#F + 1] = #fpos + 1
    local from = 1
    while true do
        local a, b = F:find(q, from, true)
        if not a then break end
        local ci, cj = byF[a], byF[b + 1]
        if ci and cj then out[#out + 1] = { base + starts[ci], base + starts[cj] - 1 } end
        from = b + 1
    end
end

-- Igual, en un mensaje que puede llevar códigos del juego (colores, enlaces, iconos): esos se saltan
function HU.QuerySpans(text, query)
    local out = {}
    local q = query and HU.Fold(HU.Trim(query)) or ""
    if q == "" or type(text) ~= "string" then return out end
    local pos = 1
    while pos <= #text do
        local a = text:find("|", pos, true)
        if not a then SpansPlain(text:sub(pos), q, pos - 1, out); break end
        if a > pos then SpansPlain(text:sub(pos, a - 1), q, pos - 1, out) end
        local nxt = text:sub(a + 1, a + 1)
        local e
        if nxt == "c" and text:sub(a + 2, a + 2) == "n" then e = text:find(":", a + 3, true)
        elseif nxt == "c" then e = a + 9
        elseif nxt == "H" then e = select(2, text:find("|h", a + 2, true))
        elseif nxt == "T" then e = select(2, text:find("|t", a + 2, true))
        elseif nxt == "A" then e = select(2, text:find("|a", a + 2, true))
        else e = a + 1 end
        pos = (e or #text) + 1
    end
    return out
end

-- Una línea de la lista: { texto, bytes antes del mensaje, mensaje } (lo buscado se marca en Show)
local function Line(e, focus, before)
    local when = HU.SafeDate("%d/%m %H:%M", e.t)
    local tag = e.tag and ("<" .. e.tag .. "> ") or ""
    local where = (e.k == "off" and L("[Oficiales] ")) or (e.k == "lfg" and L("[Buscar grupo] ")) or ""
    local head = (before or "") .. (focus and "|cffffffff" or "|cff999999") .. when .. "|r " .. where .. tag .. NameColored(e.a) .. ": "
    return { head .. e.m, #head, e.m }
end

local LIST_W, ROW_GAP = 580, 1
local function Row(i)
    local r = W.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, W.content)
    r:SetHyperlinksEnabled(true)
    r:SetScript("OnHyperlinkClick", function(_, link)
        local what = link:match("^guhist:(.+)$")
        if what == "back" then HU.HistBack()
        elseif what then OpenContext(tonumber(what)) end
    end)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetPoint("TOPLEFT", -4, 1)
    r.hl:SetPoint("BOTTOMRIGHT", 4, -1)
    r.hl:SetColorTexture(0.27, 1, 0.27, 0.18)
    r.text = r:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    r.text:SetPoint("TOPLEFT")
    r.text:SetWidth(LIST_W)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(true)
    r.marks = {}
    W.rows[i] = r
    return r
end

-- Fondo de «texto seleccionado» detrás de lo buscado (como al seleccionar con el ratón en el chat:
-- CalculateScreenAreaFromCharacterSpan, lo mismo que usa el chat de Blizzard)
local function MarkRow(r, spans)
    for _, t in ipairs(r.marks) do t:Hide() end
    if not (spans and #spans > 0 and r.text.CalculateScreenAreaFromCharacterSpan) then return end
    local n = 0
    for _, sp in ipairs(spans) do
        local ok, areas = pcall(r.text.CalculateScreenAreaFromCharacterSpan, r.text, sp[1], sp[2] + 1)
        if ok and type(areas) == "table" then
            for _, a in ipairs(areas) do
                n = n + 1
                local t = r.marks[n]
                if not t then
                    t = r:CreateTexture(nil, "ARTWORK")
                    t:SetColorTexture(0.2, 0.45, 1, 0.55)
                    r.marks[n] = t
                end
                t:ClearAllPoints()
                t:SetPoint("BOTTOMLEFT", r.text, "BOTTOMLEFT", a.left, a.bottom)
                t:SetPoint("TOPRIGHT", r.text, "BOTTOMLEFT", a.left + a.width, a.bottom + a.height)
                t:Show()
            end
        end
    end
end

-- Pinta la lista de arriba abajo; focus = número de la línea a remarcar y dejar en el centro
local function Show(lines, header, focus, keep)
    local all = {}
    local was = keep and W.scroll:GetVerticalScroll() or nil
    if header then all[1] = "|cffffd100" .. header .. "|r" end
    local first = #all
    for _, l in ipairs(lines) do all[#all + 1] = l end
    local y, focusY, focusH = 0, nil, nil
    for i, l in ipairs(all) do
        local r = Row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetWidth(LIST_W)
        -- (una línea de mensaje es { texto, bytes antes del mensaje, mensaje }; lo demás, texto)
        local text, spans = l, nil
        if type(l) == "table" then
            text = l[1]
            local ok, s = pcall(HU.QuerySpans, l[3], W.query)
            if ok then
                spans = s
                for _, sp in ipairs(spans) do sp[1], sp[2] = sp[1] + l[2], sp[2] + l[2] end
            end
        end
        r.text:SetText(text)
        local h = math.max(14, r.text:GetStringHeight() or 14)
        r:SetHeight(h)
        pcall(MarkRow, r, spans)
        local isFocus = focus ~= nil and i == focus + first
        r.hl:SetShown(isFocus)
        if isFocus then focusY, focusH = y, h end
        r:Show()
        y = y + h + ROW_GAP
    end
    for i = #all + 1, #W.rows do W.rows[i]:Hide() end
    W.content:SetHeight(math.max(y, 1))
    W.scroll:UpdateScrollChildRect()
    local view = W.scroll:GetHeight() or 0
    local maxS = math.max(0, y - view)
    -- (keep: llegan más resultados de la misma búsqueda; la lista se queda donde estabas)
    -- (la línea elegida, a un tercio de arriba: antes en el centro, y Jorge la quería más arriba)
    local to = focusY and math.min(maxS, math.max(0, focusY + focusH / 2 - view / 3)) or (was and math.min(maxS, was)) or 0
    W.scroll:SetVerticalScroll(to)
end

-- Del contexto a la lista, justo donde la dejaste (botón «Volver» o el enlace de arriba)
function HU.HistBack()
    if not (W and W.inContext) then return end
    W.keepScroll, W.inContext = false, false
    Render()
    if W.listScroll then W.scroll:SetVerticalScroll(math.min(W.listScroll, W.scroll:GetVerticalScrollRange() or 0)) end
end

Render = function()
    -- (viendo el contexto de un mensaje: lo que siga llegando se guarda y se pinta al volver)
    if W.inContext then return end
    if W.backBtn then W.backBtn:Hide() end
    RefreshClasses()
    local rows = {}
    local all = {}
    for _, e in ipairs(W.localRes or {}) do all[#all + 1] = e end
    for _, e in ipairs(W.remoteRes or {}) do HU:HistMerge(all, e) end
    table.sort(all, function(a, b) return a.t > b.t end)
    W.shown = all
    for i, e in ipairs(all) do
        local src = e.day and "" or ("|cff66bbff" .. L(" (de otro oficial)") .. "|r")
        local l = Line(e)
        l[1] = l[1] .. src .. "  |cff44ff44|Hguhist:" .. i .. "|h[" .. L("ver") .. "]|h|r"
        rows[#rows + 1] = l
    end
    local head = string.format(L("%d mensajes"), #all) .. (W.waitingRemote and L(" · preguntando a otros oficiales...") or "")
    if #all == 0 and not W.waitingRemote then head = L("No hay mensajes con esa búsqueda.") end
    Show(rows, head, nil, W.keepScroll)
    W.keepScroll = true
end

OpenContext = function(i)
    local e = W.shown and W.shown[i]
    if not e then return end
    W.listScroll = W.scroll:GetVerticalScroll()
    W.inContext = true
    if W.backBtn then W.backBtn:Show() end
    local function show(lines)
        if not W:IsShown() then return end
        RefreshClasses()
        local rows, focus = {}, nil
        for _, x in ipairs(lines or {}) do
            local isFocus = not focus and (x.focus or (x.t == e.t and x.a == e.a))
            rows[#rows + 1] = Line(x, isFocus, isFocus and "|cff44ff44»|r " or nil)
            if isFocus then focus = #rows end
        end
        if #rows == 0 then rows[1] = L("No se ha podido traer el contexto (el oficial que lo tenía ya no contesta).") end
        Show(rows, L("Contexto  ") .. "|cff44ff44|Hguhist:back|h[" .. L("« volver") .. "]|h|r", focus)
    end
    if e.day then show(HU:HistContextLocal(e.day, e.i, CONTEXT))
    else
        Show({}, L("Pidiendo el contexto..."))
        HU:HistContextRemote(e, show)
    end
end

function HU:HistSearch(name, text)
    if not self:CanPin() then return self:Print(L("El historial solo lo pueden consultar los oficiales.")) end
    if not self:HistEnabled() then return self:Print(L("El historial está apagado (/gu historial on).")) end
    self:HistWindow(true)
    W.nameBox:SetText(name or "")
    W.textBox:SetText(text or "")
    W.query = text
    W.keepScroll, W.inContext = false, false
    W.localRes, W.remoteRes, W.waitingRemote = nil, nil, true
    local since = HU.StampNow() - DAYS * 86400
    local opts = { name = name, text = text, since = since }
    Show({}, L("Buscando..."))
    self:HistSearchLocal(opts, function(res) W.localRes = res; Render() end)
    local asked = self:HistSearchRemote(opts, function(res)
            W.remoteRes = res
            -- (llegan de uno en uno: se repinta como mucho cada 0,2 s)
            if W.renderSoon then return end
            W.renderSoon = true
            HU.After(0.2, function() W.renderSoon = nil; Render() end)
        end,
        function(res) W.remoteRes = res; W.waitingRemote = false; Render() end)
    if asked == 0 then W.waitingRemote = false end
end

function HU:HistWindow(show)
    if not W then
        W = CreateFrame("Frame", "GuildUnionHistoryFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        W:SetSize(640, 420)
        W:SetPoint("CENTER")
        -- (por encima de la ventana propia de GuildUnion, que va en DIALOG: en HIGH salía detrás)
        W:SetFrameStrata("FULLSCREEN_DIALOG")
        W:SetMovable(true)
        W:EnableMouse(true)
        W:RegisterForDrag("LeftButton")
        W:SetScript("OnDragStart", W.StartMoving)
        W:SetScript("OnDragStop", W.StopMovingOrSizing)
        if W.SetBackdrop then
            W:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
                insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            W:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        end
        tinsert(UISpecialFrames, "GuildUnionHistoryFrame")
        local title = W:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText(L("Historial de oficiales (30 días)"))
        local close = CreateFrame("Button", nil, W, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        local function box(label, x, w)
            local fs = W:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", x, -36)
            fs:SetText(label)
            local eb = CreateFrame("EditBox", nil, W, "InputBoxTemplate")
            eb:SetSize(w, 20)
            eb:SetPoint("TOPLEFT", fs, "TOPRIGHT", 8, 4)
            eb:SetAutoFocus(false)
            eb:SetScript("OnEnterPressed", function() HU:HistSearch(HU.Trim(W.nameBox:GetText()), HU.Trim(W.textBox:GetText())) end)
            eb:SetScript("OnEscapePressed", eb.ClearFocus)
            return eb
        end
        W.nameBox = box(L("Jugador:"), 14, 150)
        W.textBox = box(L("Texto:"), 250, 170)
        local go = CreateFrame("Button", nil, W, "UIPanelButtonTemplate")
        go:SetSize(90, 22)
        go:SetPoint("TOPRIGHT", -14, -32)
        go:SetText(L("Buscar"))
        go:SetScript("OnClick", function() HU:HistSearch(HU.Trim(W.nameBox:GetText()), HU.Trim(W.textBox:GetText())) end)
        -- («Volver», arriba en el centro: solo viendo el contexto de un mensaje)
        local back = CreateFrame("Button", nil, W, "UIPanelButtonTemplate")
        back:SetSize(100, 20)
        back:SetPoint("TOP", 0, -6)
        back:SetText(L("« Volver"))
        back:SetScript("OnClick", function() HU.HistBack() end)
        back:Hide()
        W.backBtn = back
        -- (lista normal que empieza arriba, con barra; antes era la pieza del chat, que llena desde abajo)
        local sf = CreateFrame("ScrollFrame", "GuildUnionHistoryScroll", W, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 14, -64)
        sf:SetPoint("BOTTOMRIGHT", -32, 12)
        local content = CreateFrame("Frame", nil, sf)
        content:SetSize(LIST_W, 1)
        sf:SetScrollChild(content)
        W.scroll, W.content, W.rows = sf, content, {}
        -- (elegir un nombre de las sugerencias ya busca, como Intro)
        if HU.NameSuggest then HU:NameSuggest(W.nameBox, function(s) s:ClearFocus(); go:Click() end) end
        W:Hide()
    end
    if show == nil then show = not W:IsShown() end
    if show then W:Show() else W:Hide() end
end

-- /gu historial [on|off]   /gu buscar Nombre [texto]
function HU:HistCommand(cmd, arg)
    if cmd == "buscar" then
        local name, text = (arg or ""):match("^(%S*)%s*(.-)$")
        -- en Forever todos tienen nombre y apellido: las dos primeras palabras son el nombre
        local a, b, rest = (arg or ""):match("^(%S+)%s+(%S+)%s*(.-)$")
        if a then name, text = a .. " " .. b, rest end
        if name == "" then return self:Print(L("Uso: /gu buscar Nombre [texto]")) end
        return self:HistSearch(name, text)
    end
    local a = (arg or ""):lower()
    if a == "off" or a == "on" then
        self.db.histOff = (a == "off")
        return self:Print(L("Historial de oficiales: ") .. (self.db.histOff and L("apagado") or L("encendido")))
    end
    if not self:CanPin() then return self:Print(L("El historial solo lo pueden consultar los oficiales.")) end
    if a == "rellenar" or a == "sync" then
        local ok = self:HistStartSync(true)
        return self:Print(ok and L("Comparando el historial con un compañero para rellenar huecos…") or L("No hay nadie conectado con quien comparar (o ya se está haciendo)."))
    end
    local c = Community(false)
    local days, n, bytes = 0, 0, 0
    if c then for _, d in pairs(c.days) do days = days + 1; n = n + d.n; bytes = bytes + (d.b or 0) end end
    self:Print(string.format(L("Historial de oficiales: %d mensajes de %d días (%.1f MB). Cola: %d."), n, days, bytes / 1048576, #hq))
    self:HistWindow(true)
end

---------------------------------------------------------------------------
-- Enganches
---------------------------------------------------------------------------
local origAddHistory = HU.AddHistory
HU.AddHistory = function(self, kind, tag, author, msg, guid)
    origAddHistory(self, kind, tag, author, msg, guid)
    Guarded("guardar", HU.HistRecord, self, kind, tag, author, msg)
end

HU:OnStart(function()
    C_ChatInfo.RegisterAddonMessagePrefix(HU.HPREFIX)
    Guarded("limpiar", HU.HistPrune, HU)
    -- (y otra vez cuando ya se sabe el rango: al entrar todavía no)
    HU.After(120, function() Guarded("limpiar", HU.HistPrune, HU) end)
    HU.NewTicker(3600, function() Guarded("limpiar", HU.HistPrune, HU) end)
    -- el juego deja 10 seguidos y luego 1 por segundo en cada prefijo: aquí, 8 y 1 cada 1,1 s
    HU.NewTicker(1.1, function()
        htokens = math.min(8, htokens + 1)
        HFlush()
    end)
    -- rellenar huecos: al entrar y cada 5 minutos (solo los oficiales piden)
    HU.After(25 + math.random() * 20, function() Guarded("rellenar", HU.HistStartSync, HU) end)
    HU.NewTicker(SYNC_EVERY, function() Guarded("rellenar", HU.HistStartSync, HU) end)
end)
