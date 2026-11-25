-- Guild Union - Cola de envío, prefijos y susurros a desconectados (antes en Comm.lua)
local _, HU = ...
local L = HU.L
local perf = HU.netPerf -- (Comm.lua)

---------------------------------------------------------------------------
-- Cola de envío (el juego limita los mensajes de addon por prefijo)
---------------------------------------------------------------------------
-- cuatro colas, por orden de importancia (sale siempre lo de la primera que [+ARCHITECTURE.md]
local qChat, queue, mid, low = {}, {}, {}, {}
local tokens = 6
local MAX_TOKENS = 6
-- los datos grandes (listas de conectados y sus cambios, fichas, listas completas, historial) salen
-- por otro prefijo: el juego limita cada prefijo por separado, así no le quitan sitio al resto
HU.PREFIX_B = "HU20B"
local bfast, bulk, bmid, blow = {}, {}, {}, {}
local btokens = 6
local MAX_QUEUE = 1500 -- (los que mandan mucho miran antes cuánto hay en cola)
local MAX_LOW = 3000
-- (la cola de cada orden la declara su HU:RegisterMessage, Protocol.lua: queue = "chat", "bulk"...;
-- sin declarar, "normal". Los cambios de las listas, "bfast", van delante de las listas enteras)
local QUEUE_OF = { chat = qChat, normal = queue, mid = mid, low = low, bfast = bfast, bulk = bulk, bmid = bmid, blow = blow }
local NO_SPEC = {}

local function NextQueue()
    if #qChat > 0 then return qChat end
    if #queue > 0 then return queue end
    if #mid > 0 then return mid end
    if #low > 0 then return low end
    return nil
end

-- Cuánto puede esperar cada mensaje en la cola (s): uno que sale tarde confunde más que ayuda
-- (un saludo con un enlace que ya no es, un cambio de una lista vieja...). Lo declara cada orden
-- (ttl; false = no caduca nunca, como los silencios y vetos) y «gana el último» (latestWins: uno
-- nuevo con la misma orden, vía y destino sustituye al que espera; solo los que son siempre un único
-- mensaje). Sin declarar, QUEUE_TTL_DEFAULT
local QUEUE_TTL_DEFAULT = 300
local pending = {} -- [orden, vía, destino] = el que espera, de los de latestWins
-- lo que se ha perdido, para /gu cola y el banco
HU.qStats = { expired = {}, dropped = {}, replaced = 0, offline = 0, lockdown = 0, skipped = 0 }
local function Count(t, cmd) t[cmd or "?"] = (t[cmd or "?"] or 0) + 1 end
local function TTL(cmd)
    local ttl = (HU.msgs[cmd] or NO_SPEC).ttl
    if ttl == false then return nil end
    return ttl or QUEUE_TTL_DEFAULT
end

-- (el juego dice si un mensaje no ha salido por exceso de mensajes o por una restricción: entonces
-- se queda en la cola y se prueba después, hasta que caduque)
local SEND_RESULT = Enum and Enum.SendAddonMessageResult or {}
local LOCKDOWN, OFFLINE = SEND_RESULT.AddOnMessageLockdown or 11, SEND_RESULT.TargetOffline or 12
local THROTTLED = { [SEND_RESULT.AddonMessageThrottle or 3] = true, [SEND_RESULT.ChannelThrottle or 8] = true, [SEND_RESULT.GeneralError or 9] = true, [LOCKDOWN] = true }

-- Un silencio que ha esperado en la cola dura menos: se le restan los segundos esperados (los
-- «segs» se calculan al montar el mensaje y quien lo recibe hace fin = ahora + segs)
local function Older(secs, waited)
    local s = tonumber(secs)
    if not s or s <= 0 then return secs end -- (0 = para siempre, -1 = quitar)
    return tostring(math.max(1, math.floor(s - waited)))
end
local function AgeMutes(msg, waited)
    waited = math.floor(waited)
    if waited < 1 then return msg end
    if msg:sub(1, 3) == "MU~" then
        return (msg:gsub("^(MU~[^~]*~)([^~]*)", function(a, s) return a .. Older(s, waited) end, 1))
    end
    if msg:sub(1, 3) ~= "MZ~" then return msg end
    local out = {}
    for en in msg:sub(4):gmatch("[^;]+") do
        out[#out + 1] = (en:gsub("^([^,]*,)([^,]*)", function(a, s) return a .. Older(s, waited) end, 1))
    end
    return "MZ~" .. table.concat(out, ";")
end

-- Saca el siguiente de q que no haya caducado (los caducados se tiran y se cuentan)
local function Pop(q)
    local now = GetTime()
    while q[1] do
        local m = table.remove(q, 1)
        if m.key and pending[m.key] == m then pending[m.key] = nil end
        local ttl = TTL(m.cmd)
        if ttl and now - (m.t or now) > ttl then
            Count(HU.qStats.expired, m.cmd)
            -- (una línea del chat por el respaldo que no ha salido: que lo sepa quien la escribió)
            if (m.cmd == "CW" or m.cmd == "CF") and HU.OnChatLost then HU:OnChatLost(m[1]) end
        else
            -- (siempre desde el texto de cuando entró: si vuelve a la cola, no se resta dos veces)
            if m.cmd == "MU" or m.cmd == "MZ" then m.orig = m.orig or m[1]; m[1] = AgeMutes(m.orig, now - (m.t or now)) end
            return m
        end
    end
    return nil
end

-- Manda m. Devuelve true si el juego va saturado (m vuelve delante de su cola y se espera)
local function SendOne(prefix, q, m)
    -- (en pausa por la versión mínima de mi hermandad: no sale nada del addon; ver Popup.lua SetGuildMin)
    if HU.paused then return false end
    if prefix == HU.PREFIX and m[2] == "GUILD" and m[1]:sub(1, 3) == "HI~" then perf.hiSent = GetTime() end
    local ok, r = pcall(C_ChatInfo.SendAddonMessage, prefix, m[1], m[2], m[3])
    if not ok then Count(HU.qStats.dropped, m.cmd) return false end
    if m[2] == "CHANNEL" and HU.ChannelSendResult then HU:ChannelSendResult(m[3], r) end
    if r == false or (type(r) == "number" and THROTTLED[r]) then
        if r == LOCKDOWN then HU.qStats.lockdown = HU.qStats.lockdown + 1 end
        -- (si mientras tanto ha entrado uno más nuevo del mismo tipo, este sobra)
        if m.key and pending[m.key] then HU.qStats.replaced = HU.qStats.replaced + 1 return true end
        if m.key then pending[m.key] = m end
        table.insert(q, 1, m)
        return true
    end
    perf.sentN = perf.sentN + 1
    -- (quien lo mandó quiere saber cuándo sale de verdad: /gu sinaddon, Report.lua)
    if m.onSent then local fn = m.onSent; m.onSent = nil; HU.After(0, fn) end
    -- (el destinatario se ha ido: lo mismo que con el aviso «no hay ningún jugador llamado...»)
    if r == OFFLINE and m[2] == "WHISPER" and type(m[3]) == "string" then
        HU.qStats.offline = HU.qStats.offline + 1
        local who = m[3]
        HU.After(0, function() HU:ForgetOffline(who) end)
    end
    return false
end

local function Flush()
    if HU:IsChatLockedDown() then return end
    -- (el chat y los silencios no esperan al segundo siguiente aunque el addon haya gastado su cupo:
    -- el juego deja 10 seguidos y el addon se guarda 6, así que hay margen para 3 más)
    while tokens >= 1 or (tokens > -3 and #qChat > 0) do
        local q = NextQueue()
        if not q then return end
        local m = Pop(q)
        if m then
            tokens = tokens - 1
            if SendOne(HU.PREFIX, q, m) then tokens = 0 return end
        end
    end
end

local bTurn = false
local function NextBulk()
    -- (los cambios y las listas enteras, por turnos: ninguno se queda sin salir)
    if #bfast > 0 and #bulk > 0 then bTurn = not bTurn; return bTurn and bfast or bulk end
    if #bfast > 0 then return bfast end
    if #bulk > 0 then return bulk end
    if #bmid > 0 then return bmid end
    if #blow > 0 then return blow end
    return nil
end
local function FlushBulk()
    if HU:IsChatLockedDown() then return end
    while btokens >= 1 do
        local q = NextBulk()
        if not q then return end
        local m = Pop(q)
        if m then
            btokens = btokens - 1
            if SendOne(HU.PREFIX_B, q, m) then btokens = 0 return end
        end
    end
end

-- urgent = true pone el mensaje delante de su cola; onSent, si lo hay, se llama cuando sale de verdad (no si caduca
-- o se tira). Devuelve false si no ha entrado en la cola. [+ARCHITECTURE.md]
function HU:Send(msg, dist, target, urgent, slow, fast, onSent)
    if #msg > 255 then msg = HU.Utf8Cut(msg, 255) end
    local cmd = msg:sub(1, 2)
    local spec = HU.msgs[cmd] or NO_SPEC
    -- (con el chat bloqueado por el juego, los saludos y presentaciones no se guardan: caducan a los 60 s
    -- y solo llenaban la cola. Al acabar el bloqueo se saluda de nuevo: Combat.lua)
    if spec.skipLocked and self:IsChatLockedDown() then
        self.qStats.skipped = (self.qStats.skipped or 0) + 1
        return false
    end
    local isBulk = spec.prefix == "HU20B"
    local q = QUEUE_OF[spec.queue or "normal"]
    if slow then q = isBulk and blow or mid end
    if fast then q, isBulk, urgent = qChat, nil, true end
    local key = spec.latestWins and (cmd .. "\1" .. tostring(dist) .. "\1" .. tostring(target or "")) or nil
    local old = key and pending[key]
    if old then
        -- (ya espera uno igual: se le pone el texto nuevo y sale en su sitio)
        old[1], old.t = msg, GetTime()
        self.qStats.replaced = self.qStats.replaced + 1
    else
        local cap = (q == mid or q == low or q == bmid or q == blow) and MAX_LOW or MAX_QUEUE
        if #q >= cap and not urgent then
            -- (llena: sale el más viejo que pueda caducar; si todos son silencios o vetos, el nuevo no entra)
            local drop
            for i = 1, #q do if TTL(q[i].cmd) then drop = i break end end
            if not drop then Count(self.qStats.dropped, cmd) return false end
            local d = table.remove(q, drop)
            if d.key and pending[d.key] == d then pending[d.key] = nil end
            Count(self.qStats.dropped, d.cmd)
        end
        local m = { msg, dist, target, t = GetTime(), cmd = cmd, key = key, gtag = HU.sendGroup and HU.sendGroup.tag, gdest = HU.sendGroup and HU.sendGroup.dest, onSent = onSent }
        if key then pending[key] = m end
        if urgent and (cmd == "CW" or cmd == "CG" or cmd == "CF") then
            -- (copia 150) El chat del respaldo se ponía SIEMPRE el primero: con varios esperando, el
            -- último pasaba delante, salían al revés y los primeros caducaban. Ahora va detrás del
            -- último de chat que ya espera, y todos ellos delante del resto.
            local pos = 0
            for i = 1, #q do if q[i].chatU then pos = i end end
            m.chatU = true
            table.insert(q, pos + 1, m)
        elseif urgent then table.insert(q, 1, m) else q[#q + 1] = m end
    end
    if isBulk then FlushBulk() else Flush() end
    return true
end

-- Lo nuevo ocupa el sitio de lo viejo (idea de Olympus): una lista entera nueva para una hermandad [+ARCHITECTURE.md]
function HU:DropQueued(tag, dest)
    local n = 0
    for _, q in ipairs({ qChat, bfast, bulk, bmid, blow }) do
        for i = #q, 1, -1 do
            local m = q[i]
            -- (solo los trozos de listas enteras: los cambios (RC) se quedan. Son pequeños, aplicarlos dos veces [+ARCHITECTURE.md]
            if m.gtag == tag and m.gdest == dest and m.cmd == "RB" then table.remove(q, i); n = n + 1 end
        end
    end
    if n > 0 then self.qStats.replaced = self.qStats.replaced + n end
    return n
end

function HU:QueueSize() return #qChat + #queue + #mid + #low + #bfast + #bulk + #bmid + #blow end
-- (las listas de conectados enteras que esperan: los que mandan listas no añaden más si hay muchas)
function HU:BulkQueueSize() return #bulk end
-- Cada segundo (el temporizador lo pone Net/Relay.lua al arrancar): recupera el cupo y manda
function HU.QueueTick()
    btokens = math.min(MAX_TOKENS, btokens + 1)
    tokens = math.min(MAX_TOKENS, tokens + 1)
    -- (si el juego cuenta los dos prefijos juntos, lo que sale primero se lleva el sitio: antes [+ARCHITECTURE.md]
    if #qChat > 0 or (#queue > 0 and #bfast == 0) then
        Flush(); FlushBulk()
    else
        FlushBulk(); Flush()
    end
end
function HU:MainQueueSize() return #qChat + #queue + #bfast + #bulk end
-- Vaciar la cola (lo pendiente se vuelve a pedir y mandar solo más adelante)
function HU:ClearQueue()
    local n = self:QueueSize()
    for _, q in ipairs({ qChat, queue, mid, low, bfast, bulk, bmid, blow }) do for i = #q, 1, -1 do q[i] = nil end end
    for k in pairs(pending) do pending[k] = nil end
    return n
end
-- Lo perdido desde que entraste: «» si nada
local function SumOf(t) local n = 0 for _, v in pairs(t) do n = n + v end return n end
function HU:QueueLossText()
    local s = self.qStats
    local dropped, expired = SumOf(s.dropped), SumOf(s.expired)
    local chat = s.chatLost or 0
    if dropped + expired + s.offline + chat == 0 then return "" end
    return L("   ·   perdidos: ") .. dropped .. L(" (cola llena), ") .. expired .. L(" caducados, ") .. s.offline .. L(" a desconectados")
        .. (chat > 0 and (", " .. chat .. L(" de chat")) or "")
end
function HU:QueueText()
    local n = self:QueueSize()
    if n == 0 then return L("Cola de envío: |cff44ff44vacía|r") .. self:QueueLossText() end
    -- el juego deja 1 mensaje por segundo en cada prefijo (y hay dos)
    local mins = math.ceil(math.max(#qChat + #queue + #mid + #low, #bfast + #bulk + #bmid + #blow) / 60)
    return L("Cola de envío: ") .. (n > 150 and "|cffff8800" or "|cffffd100") .. n .. "|r" .. L(" mensajes (unos ") .. mins .. L(" min)")
        .. self:QueueLossText()
end

---------------------------------------------------------------------------
-- Susurros a jugadores desconectados: ocultamos el aviso "no hay ningún jugador llamado..."
---------------------------------------------------------------------------
local pinged = {}
local notFoundPattern

-- para otros prefijos (el mapa): que también se oculte el aviso si está desconectado
function HU:MarkPinged(target) pinged[self:Short(target):lower()] = GetTime() end

local lastSent = {} -- [contacto] = lo que se le ha susurrado en los últimos 30 s (como mucho 20)
function HU:Whisper(target, msg, urgent, slow, fast)
    local k, now = self:Short(target):lower(), GetTime()
    pinged[k] = now
    local l = lastSent[k]
    if not l then l = {}; lastSent[k] = l end
    while l[1] and (now - l[1].t > 30 or #l >= 20) do table.remove(l, 1) end
    l[#l + 1] = { msg = msg, t = now, urgent = urgent }
    return self:Send(msg, "WHISPER", target, urgent, slow, fast)
end
-- (el contacto k no está: lo que se le mandó hace poco va al siguiente de su hermandad)
local function Resend(k, tags)
    local l = lastSent[k]
    lastSent[k] = nil
    if not l then return end
    local now = GetTime()
    for tag in pairs(tags) do
        local np = HU:BestPeer(tag)
        if np and HU:Short(np.name):lower() ~= k then
            -- (copia 151: lo que ese contacto ya recibió de mí no se le manda otra vez. Con el respaldo
            -- a dos contactos, el «siguiente» suele ser el otro, que ya la tiene: la pintaba dos veces
            -- y la repartía dos veces a toda su hermandad)
            local had = {}
            for _, x in ipairs(lastSent[HU:Short(np.name):lower()] or {}) do had[x.msg] = true end
            for _, e in ipairs(l) do
                if now - e.t <= 30 and not had[e.msg] then HU:Whisper(np.name, e.msg, e.urgent) end
            end
        end
    end
end

local function SystemFilter(_, _, text)
    if type(text) ~= "string" or not ERR_CHAT_PLAYER_NOT_FOUND_S then return false end
    if not notFoundPattern then
        local p = ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%(%)%.%-%+%*%?%[%]%^%$])", "%%%1")
        p = p:gsub("%%s", "(.+)")
        notFoundPattern = "^" .. p .. "$"
    end
    local who = text:match(notFoundPattern)
    if who then
        HU:PresenceNotFound(who)
        local k = HU:Short(who):lower()
        if pinged[k] and GetTime() - pinged[k] < 30 then
            HU:ForgetOffline(who)
            return true
        end
    end
    return false
end

-- Un contacto se ha desconectado (aviso del juego, o el envío contestó TargetOffline): fuera de
-- los contactos, lo que se le mandó hace poco va al siguiente de su hermandad
function HU:ForgetOffline(who)
    local k = self:Short(who):lower()
    local tags = {}
    for key, p in pairs(self.remote) do
        if self:Short(p.name):lower() == k then
            if p.tag then tags[p.tag] = true end
            self.remote[key] = nil
        end
    end
    if next(tags) then HU.After(0.5, function() Resend(k, tags) end) end
    -- (y fuera del reparto de trozos: si no, los trozos de las listas que le tocaban se
    -- perdían hasta el siguiente saludo de su enlace y la lista entera nunca se juntaba)
    for _, h in pairs(self.helpers) do
        for i = #h.list, 1, -1 do if self:Short(h.list[i]):lower() == k then table.remove(h.list, i) end end
    end
end

HU.AddChatFilter("CHAT_MSG_SYSTEM", SystemFilter)

HU:Module("Net/Transport", { "Channel", "Core", "Domain/Trust", "Presence" })
