-- Guild Union - comunicación entre addons (contactos y listas de miembros)
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

HU.guildPeers = {}     -- [clave] = { name, last, mod, ver }  usuarios del addon en mi hermandad
HU.remote = {}         -- [clave] = { name, tag, last, mod, relay, ver }  usuarios de otras hermandades
-- Índice por etiqueta: con miles de contactos, cada BestPeer/KnownRelay/MarkRelay los recorría todos [+ARCHITECTURE.md]
local NO_KEYS = {}
local RK = { idx = {}, inn = {}, t = -999, all = {}, allIn = {}, EVERY = 5, MS = 1 }
local function IdxAdd(idx, inn, tag, k)
    local s = inn[tag]
    if not s then s = {}; inn[tag] = s end
    if s[k] then return end
    s[k] = true
    local l = idx[tag]
    if not l then l = {}; idx[tag] = l end
    l[#l + 1] = k
end
-- (ficha sin etiqueta todavía: avisa cuando se le pone)
RK.watch = { __newindex = function(t, key, val)
    rawset(t, key, val)
    if key == "tag" and val ~= nil then
        local k = rawget(t, "_rk")
        setmetatable(t, nil)
        if k and HU.remote[k] == t then IdxAdd(RK.idx, RK.inn, val, k) end
    end
end }
setmetatable(HU.remote, { __newindex = function(t, k, v)
    rawset(t, k, v)
    if not RK.allIn[k] then RK.allIn[k] = true; RK.all[#RK.all + 1] = k end
    if type(v) ~= "table" then return end
    if v.tag then IdxAdd(RK.idx, RK.inn, v.tag, k)
    elseif getmetatable(v) == nil then rawset(v, "_rk", k); setmetatable(v, RK.watch) end
end })
local function RebuildStep()
    local b = RK.build
    if not b then return end
    local t0, remote, all = debugprofilestop(), HU.remote, RK.all
    while b.i <= #all do
        local k = all[b.i]
        local p = remote[k]
        if p == nil then
            -- (ya no está: se quita de la lista de claves, cambiando su sitio por el último)
            RK.allIn[k] = nil
            all[b.i] = all[#all]
            all[#all] = nil
        else
            if type(p) == "table" and p.tag then IdxAdd(b.idx, b.inn, p.tag, k) end
            b.i = b.i + 1
        end
        if b.i % 64 == 0 and debugprofilestop() - t0 > RK.MS then return HU.After(0, RebuildStep) end
    end
    RK.idx, RK.inn, RK.build = b.idx, b.inn, nil
end
function HU:RemoteKeys(tag)
    if not RK.build and GetTime() - RK.t > RK.EVERY then
        RK.t = GetTime()
        RK.build = { i = 1, idx = {}, inn = {} }
        HU.After(0, RebuildStep)
    end
    return RK.idx[tag] or NO_KEYS
end
HU.remoteRoster = {}   -- [tag] = { members = {...}, total, online, updated }

-- Listas de conectados de las otras hermandades: se guardan al salir y se recuperan tras un /reload
HU:On("PLAYER_LOGOUT", function()
    if not HU.db then return end
    local now, lists = GetTime(), {}
    for tag, r in pairs(HU.remoteRoster) do
        if r.members and #r.members > 0 then
            lists[tag] = { members = r.members, total = r.total, online = r.online, age = now - (r.updated or now) }
        end
    end
    HU.db.rosterCache = next(lists) and { t = time(), tag = HU.myTag, lists = lists } or nil
end)
-- Listas «de la última vez»: SOLO para enseñarlas en el panel, en gris, mientras llegan las de verdad. [+ARCHITECTURE.md]
HU.ghostRoster = {}    -- [tag] = { members = {...}, t, v }
local GHOST_TTL, GHOST_MAX_AGE = 300, 3 * 86400
local function ShowGhosts(self, lists, gone)
    if gone < 0 or gone > GHOST_MAX_AGE then return end
    local others = {}
    for _, tag in ipairs(self:OtherTags()) do others[tag] = true end
    local any = false
    for tag, l in pairs(lists) do
        if others[tag] and type(l.members) == "table" and not (self.remoteRoster[tag] and #(self.remoteRoster[tag].members or {}) > 0) then
            local members = {}
            for _, m in ipairs(l.members) do
                if type(m) == "table" and type(m.name) == "string" then
                    members[#members + 1] = { name = m.name, class = m.class, level = m.level, rankIndex = m.rankIndex or m.rankHidden, zone = "", online = true }
                end
            end
            if #members > 0 then
                self.ghostRoster[tag] = { members = members, t = GetTime(), v = (self.ghostRoster[tag] and self.ghostRoster[tag].v or 0) + 1 }
                any = true
            end
        end
    end
    if not any then return end
    self:Changed("members")
    HU.After(GHOST_TTL, function()
        local ch = false
        for tag, g in pairs(HU.ghostRoster) do
            if GetTime() - g.t >= GHOST_TTL - 1 then HU.ghostRoster[tag] = nil; ch = true end
        end
        if ch then HU:Changed("members") end
    end)
end
function HU:DropGhost(tag)
    if self.ghostRoster[tag] then self.ghostRoster[tag] = nil; self:Changed("members") end
end
function HU:RestoreRosterCache()
    local c = self.db and self.db.rosterCache
    self.db.rosterCache = nil
    if type(c) ~= "table" or type(c.lists) ~= "table" or c.tag ~= self.myTag then return end
    local gone = time() - (tonumber(c.t) or 0)
    -- (más de 10 min fuera: ya no se recupera como lista; se enseña en gris, «la última vez»)
    if gone > 600 then return ShowGhosts(self, c.lists, gone) end
    if gone < 0 then return end
    local others = {}
    for _, tag in ipairs(self:OtherTags()) do others[tag] = true end
    for tag, l in pairs(c.lists) do
        if others[tag] and not self.remoteRoster[tag] and type(l.members) == "table" then
            local members = {}
            for _, m in ipairs(l.members) do if type(m) == "table" and type(m.name) == "string" then members[#members + 1] = m end end
            -- (provisional: «débil», sin número de serie y vieja, para que cualquier lista la sustituya)
            self.remoteRoster[tag] = HU.IndexRoster({ members = members, total = tonumber(l.total) or #members,
                online = tonumber(l.online) or #members, updated = GetTime() - 2000, weak = true, cached = true })
            self:NeedRoster(tag)
        end
    end
    self:Changed("members")
end
HU.comm = {}
local perf = {} -- medidas de este ordenador y su conexión (para elegir el enlace)

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
local BFAST_CMDS = { RC = true } -- (los cambios de las listas van delante de las listas enteras)
local BULK_CMDS = { RB = true }
local BMID_CMDS = { PB = true }
local BLOW_CMDS = { WL = true, OD = true, HL = true }
local MAX_QUEUE = 1500 -- (los que mandan mucho miran antes cuánto hay en cola)
local MAX_LOW = 3000
local CHAT_CMDS = { MU = true, MZ = true, BN = true, CX = true, CP = true, CQ = true, LG = true, PN = true, GK = true,
    CW = true, CG = true, CF = true } -- (CW / CG / CF: el chat por el respaldo, ver Channel.lua)
local MID_CMDS = { OE = true, MQ = true, EM = true } -- (los emoticonos pueden ser 150: sin prisa)
local LOW_CMDS = {}

local function NextQueue()
    if #qChat > 0 then return qChat end
    if #queue > 0 then return queue end
    if #mid > 0 then return mid end
    if #low > 0 then return low end
    return nil
end

-- Cuánto puede esperar cada mensaje en la cola (s): uno que sale tarde confunde más que ayuda
-- (un saludo con un enlace que ya no es, un cambio de una lista vieja...)
local QUEUE_TTL = {
    HI = 60, HR = 60, HY = 60, RA = 60, LP = 60, PL = 60, PH = 60, LN = 60,
    RC = 300, RB = 600,
    PB = 900, OD = 900, WL = 900, HL = 900,
    CX = 600, CP = 600, CQ = 600, LG = 600, PN = 600, GK = 600,
    CW = 60, CG = 60, CF = 60,
}
local QUEUE_TTL_DEFAULT = 300
-- (los silencios y vetos no caducan: quitar un silencio no se vuelve a mandar nunca)
local NEVER_EXPIRE = { MU = true, MZ = true, BN = true }
-- «gana el último»: uno nuevo con la misma orden, vía y destino sustituye al que espera. Solo los
-- que son siempre un único mensaje (LP no: el sondeo manda 3 a propósito)
local LATEST_WINS = { HI = true, HR = true, HY = true, RA = true, LN = true }
local pending = {} -- [orden, vía, destino] = el que espera, de los de LATEST_WINS
-- lo que se ha perdido, para /gu cola y el banco
HU.qStats = { expired = {}, dropped = {}, replaced = 0, offline = 0, lockdown = 0 }
local function Count(t, cmd) t[cmd or "?"] = (t[cmd or "?"] or 0) + 1 end
local function TTL(cmd) if NEVER_EXPIRE[cmd] then return nil end return QUEUE_TTL[cmd] or QUEUE_TTL_DEFAULT end

-- (el juego dice si un mensaje no ha salido por exceso de mensajes o por una restricción: entonces
-- se queda en la cola y se prueba después, hasta que caduque)
local R = Enum and Enum.SendAddonMessageResult or {}
local LOCKDOWN, OFFLINE = R.AddOnMessageLockdown or 11, R.TargetOffline or 12
local THROTTLED = { [R.AddonMessageThrottle or 3] = true, [R.ChannelThrottle or 8] = true, [R.GeneralError or 9] = true, [LOCKDOWN] = true }

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
    -- (el destinatario se ha ido: lo mismo que con el aviso «no hay ningún jugador llamado...»)
    if r == OFFLINE and m[2] == "WHISPER" and type(m[3]) == "string" then
        HU.qStats.offline = HU.qStats.offline + 1
        local who = m[3]
        HU.After(0, function() if HU.ForgetOffline then HU:ForgetOffline(who) end end)
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

-- urgent = true pone el mensaje delante de su cola. Devuelve false si no ha entrado en la cola. [+ARCHITECTURE.md]
function HU:Send(msg, dist, target, urgent, slow, fast)
    if #msg > 255 then msg = HU.Utf8Cut(msg, 255) end
    local cmd = msg:sub(1, 2)
    local isBulk = BFAST_CMDS[cmd] or BULK_CMDS[cmd] or BMID_CMDS[cmd] or BLOW_CMDS[cmd]
    local q = (BFAST_CMDS[cmd] and bfast) or (BULK_CMDS[cmd] and bulk) or (BMID_CMDS[cmd] and bmid) or (BLOW_CMDS[cmd] and blow)
        or (CHAT_CMDS[cmd] and qChat) or (MID_CMDS[cmd] and mid) or (LOW_CMDS[cmd] and low) or queue
    if slow then q = isBulk and blow or mid end
    if fast then q, isBulk, urgent = qChat, nil, true end
    local key = LATEST_WINS[cmd] and (cmd .. "\1" .. tostring(dist) .. "\1" .. tostring(target or "")) or nil
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
            for i = 1, #q do if not NEVER_EXPIRE[q[i].cmd] then drop = i break end end
            if not drop then Count(self.qStats.dropped, cmd) return false end
            local d = table.remove(q, drop)
            if d.key and pending[d.key] == d then pending[d.key] = nil end
            Count(self.qStats.dropped, d.cmd)
        end
        local m = { msg, dist, target, t = GetTime(), cmd = cmd, key = key, gtag = HU.sendGroup and HU.sendGroup.tag, gdest = HU.sendGroup and HU.sendGroup.dest }
        if key then pending[key] = m end
        if urgent then table.insert(q, 1, m) else q[#q + 1] = m end
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
            for _, e in ipairs(l) do
                if now - e.t <= 30 then HU:Whisper(np.name, e.msg, e.urgent) end
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
        if HU.PresenceNotFound then HU:PresenceNotFound(who) end
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

---------------------------------------------------------------------------
-- Contactos
---------------------------------------------------------------------------
local function b(v) return v and "1" or "0" end

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
    if UnitIsAFK and UnitIsAFK("player") then
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
    if IsResting and IsResting() then
        self.restSince = self.restSince or GetTime()
        if GetTime() - self.restSince >= 60 then s = s - 20 end
    else
        self.restSince = nil
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
        if changed and self:LaunchPhase() and self.PresenceSchedule then HU.After(0, function() HU:PresenceSchedule() end) end
        -- (y a mi hermandad enseguida, no en el saludo de dentro de 2-5 minutos: los ayudantes van en [+ARCHITECTURE.md]
        if changed and cmd ~= "HR" then self:HelpersChangedHello() end
    end
    local text = HU.Utf8Cut(table.concat({ cmd or "HI", self.version, self.myTag or "", b(self:AmIModFast()), b(relay),
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
    if HU.IsOfficerName and HU:IsOfficerName(sender) then return true end
    if dist == "GUILD" then return HU:Key(HU:RelayName() or "") == HU:Key(sender) end
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
    if fast and self:SimpleMode() then fast = nil end
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
    local W = self.whitelist[tag]
    -- (solo ayudantes que sigan conectados según la lista de su hermandad, si la tengo)
    local R = self.remoteRoster[tag]
    for _, n in ipairs(h.list) do
        local full = self:FullName(n)
        local online = not (R and R.byKey) or R.byKey[full and full:lower() or ""] ~= nil
        if full and online and full:lower() ~= target:lower() and (not W or self:MemberOf(full, tag)) then pool[#pool + 1] = full end
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

-- Quién puede mandarme la lista de conectados de otra hermandad, y cuánto me fío de ella. [+ARCHITECTURE.md]
local VOUCH_TTL = 900       -- lo que dura el aviso de un enlace comprobado (o de mi hermandad)
local TRUST_FRESH = 900     -- confirmada y al día hace menos de esto: los de arranque ya no entran
local BOOT_MEMBERS = 600    -- de arranque a miembros si en este tiempo nadie la discute
local BOOT_RANKS = 1800     -- de arranque o miembros a rangos provisionales, sin discusión
local DISPUTE_WARN = 600    -- un aviso de disputa por hermandad como mucho cada tanto
local SECOND_EVERY = 120    -- segunda opinión (RF~etiq~2) a otra cuenta, como mucho cada tanto
-- (PL/PH de mi hermandad cuentan como comprobados solo si el enlace que los manda marca enlaces con
-- HU:CheckedOf: entrega «onhello» de Transportes. Sin ella, false)
local FWD_TRUSTED = true
-- (mientras haya versiones viejas, una lista de mi hermandad sin estado se toma como confirmada;
-- cuando todos hayan actualizado, true: sin estado = miembros)
local STATE_STRICT = false
-- (las dos cuentas que respaldaron una lista que llegó a rangos solo por tiempo se guardan como antiguas. [+ARCHITECTURE.md]
local OLD_FROM_TIME = false
local STATE_RANK = { b = 1, m = 2, p = 3, c = 4 }
local STATE_NAME = { b = "arranque", m = "miembros", p = "provisional", c = "confirmada" }
HU.STATE_RANK = STATE_RANK
HU.vouchOf = HU.vouchOf or {}         -- [tag] = { [clave] = cuándo lo anunció un enlace comprobado }
HU.rosterTrust = HU.rosterTrust or {} -- [tag] = cuándo quedó confirmada
HU.bootState = HU.bootState or {}     -- [tag] = { hash, since, origins = {[clave] = tipo}, state, two, pBy }
HU.fwdVouch = HU.fwdVouch or {}       -- [tag] = { [clave] = cuándo lo presentó por GUILD un forwarder mío }
HU.raSeen = HU.raSeen or {}           -- [tag] = { [clave] = cuándo salió en una presentación RA aceptada }
HU.acceptKind = HU.acceptKind or {}   -- [tag] = { [clave] = con qué se le aceptó el último susurro }
local disputeWarned, secondAsked = {}, {}

local function Stamp(tbl, tag, name, now)
    local k = name and HU:Key(name)
    if not k then return end
    local v = tbl[tag] or {}
    tbl[tag] = v
    v[k] = now
end
local function Fresh(tbl, tag, k)
    local v = tbl[tag]
    local t = v and k and v[k]
    return t ~= nil and GetTime() - t < VOUCH_TTL
end

-- Anunciado por un enlace de esa hermandad con la lista confirmada
function HU:VouchedOf(sender, tag)
    return Fresh(self.vouchOf, tag, sender and self:Key(sender))
end

-- Estado de una lista: "b", "m", "p", "c" o nil (sin estado: llegó de una versión vieja de mi
-- hermandad). Vale con la etiqueta o con la lista: HU.RosterStateOf("ETIQ") / HU.RosterStateOf(r)
local function StateOf(r)
    if type(r) == "string" then r = HU.remoteRoster[r] end
    if not r then return nil end
    if r.state then return r.state end
    if r.weak then return "b" end
    return STATE_STRICT and "m" or "c"
end
HU.RosterStateOf = StateOf
HU.RosterStateName = function(s) return STATE_NAME[s] end
-- Para el panel y /gu estado: "arranque", "miembros", "provisional", "confirmada" o nil
-- Miembro de una lista confirmada (lo que vale para darle por enlace «dicho por él»)
function HU:CheckedOf(name, tag)
    return self:MemberOf(name, tag) and StateOf(self.remoteRoster[tag]) == "c"
end

-- Ancla de confianza de cada hermandad: el maestro (u oficial) que aceptó la invitación a la comunidad [+ARCHITECTURE.md]
function HU:AnchorValid(tag, k)
    local a = self.db and self.db.anchors and self.db.anchors[tag]
    if not a or a.dead or not k or self:Key(a.name) ~= k then return false end
    local r = self.remoteRoster[tag]
    if StateOf(r) ~= "c" then return true end
    local m = r.byKey and r.byKey[k]
    if not m then return false end
    if m.rankIndex ~= nil and self:RankRole(tag, m.rankIndex) == nil then
        a.dead = true
        return false
    end
    return true
end

-- Quien lleva esa hermandad en la mía pide la lista a su ancla si aún no la tengo confirmada (y el
-- ancla está conectada: sale en su lista de conectados o en el canal). Contesta con RF~etiq~2.
local anchorAsked = {}
local function AskAnchors(self)
    if not self.myTag or not (self.db and self.db.anchors) then return end
    for _, tag in ipairs(self:OtherTags()) do
        local a = self.db.anchors[tag]
        local r = self.remoteRoster[tag]
        if a and not a.dead and StateOf(r) ~= "c" and (self:IsRelay() or self:HandlesTag(tag) or (self.ResponsibleFor and self:ResponsibleFor(tag)))
            and (not anchorAsked[tag] or GetTime() - anchorAsked[tag] > 60) then
            local k = self:Key(a.name)
            local online = (r and r.byKey and r.byKey[k or ""]) or (self.ChannelHas and self:ChannelHas(a.name) == true)
            if k and online then
                anchorAsked[tag] = GetTime()
                self:Whisper(a.name, "RF~" .. self.myTag .. "~2", true)
            end
        end
    end
end
HU:OnStart(function()
    -- (cada 10 s: con 20 s, el día 1 a veces pasaba del minuto en confirmar; solo pregunta si falta «c»,
    -- y a cada ancla como mucho una vez por minuto)
    HU.NewTicker(10, function() HU:SafeCall("ancla", function() AskAnchors(HU) end) end)
end)

local function PeerEntry(self, tag, k)
    local peers = k and self.db and self.db.peers and self.db.peers[tag]
    return peers and peers[k]
end
-- Contacto comprobado (guardado tras una lista confirmada o dos cuentas con una conocida)
function HU:FullPeer(name, tag)
    local e = PeerEntry(self, tag, name and self:Key(name))
    return e ~= nil and not e.old
end

-- ¿Lista confirmada y al día? Entonces los que solo salieron en una presentación ya no la cambian.
function HU:RosterTrusted(tag)
    local t = self.rosterTrust[tag]
    if t and GetTime() - t < TRUST_FRESH then return true end
    local r = self.remoteRoster[tag]
    if not r or StateOf(r) ~= "c" then return false end
    return GetTime() - math.max(r.updated or 0, r.confirmedT or 0) < TRUST_FRESH
end

-- Con qué me fío de quien me susurra una lista de esa hermandad: "vouched" (lo nombró su enlace [+ARCHITECTURE.md]
function HU:SenderKind(sender, tag)
    local k = sender and self:Key(sender)
    if not k then return nil end
    if self:AnchorValid(tag, k) or self:VouchedOf(sender, tag) then return "vouched" end
    local e = PeerEntry(self, tag, k)
    if (e and not e.old) or (FWD_TRUSTED and Fresh(self.fwdVouch, tag, k)) then return "peer" end
    if self:MemberOf(sender, tag) then return "member" end
    if e then return "old" end
    if Fresh(self.raSeen, tag, k) or Fresh(self.fwdVouch, tag, k) then return "boot" end
    -- (en Forever las presentaciones RA por el canal no llegan: vale también estar en la lista de
    -- miembros del canal, que solo se consigue con la contraseña)
    if self.ChannelHas and self:ChannelHas(sender) == true then return "boot" end
    return nil
end

-- Pone una lista en un estado: weak en arranque, rango aparte en arranque y miembros
local function ApplyState(r, s)
    r.state = s
    local hide, weak = (s == "b" or s == "m"), (s == "b")
    for _, m in ipairs(r.members) do
        m.weak = weak or nil
        if hide then
            if m.rankIndex then m.rankHidden, m.rankIndex = m.rankIndex, nil end
        elseif m.rankHidden then
            m.rankIndex = m.rankIndex or m.rankHidden
            m.rankHidden = nil
        end
    end
end
HU.ApplyRosterState = ApplyState

local function WarnDispute(self, tag, a, b)
    local now = GetTime()
    if disputeWarned[tag] and now - disputeWarned[tag] < DISPUTE_WARN then return end
    disputeWarned[tag] = now
    self:Debug("Lista de", tag, "en disputa:", tostring(a), "/", tostring(b))
    if self:CanOfficer() then
        self:Print(string.format(L("La lista de %s está en disputa: %s dice una cosa y %s otra."),
            tag, self:Short(a or "?"), self:Short(b or "?")))
    end
end

-- Reparte a mi hermandad mi copia con su estado nuevo (solo quien se encarga de esa hermandad)
local function Reshare(self, tag)
    if self:IsRelay() or self:HandlesTag(tag) or (self.ResponsibleFor and self:ResponsibleFor(tag)) then
        self:SendStoredRoster(tag, true)
    end
end

-- Cambia el estado de la lista que tengo de esa hermandad
function HU:SetRosterState(tag, s, why, pBy)
    local r = self.remoteRoster[tag]
    local st = self.bootState[tag]
    if st then st.state, st.pBy = s, pBy or st.pBy end
    if not r then return end
    local before = StateOf(r)
    ApplyState(r, s)
    r.pBy = (s == "p") and (pBy or r.pBy) or nil
    if s == "c" then
        self.rosterTrust[tag] = GetTime()
        self.bootState[tag] = nil
    end
    if before ~= s then
        self:Debug("Lista de", tag, before, "->", s, why or "")
        Reshare(self, tag)
        self:RetryDeferred()
        self:Changed("members")
    end
end

-- Una cuenta conocida de antes (.old) que coincide con otra pasa a contacto comprobado
local function UpgradeOld(self, tag, st, r)
    for k, kind in pairs(st.origins) do
        local m = r.byKey and r.byKey[k]
        if kind == "old" and m then self:RememberPeer(m.name, tag) end
    end
end

-- Lista de arranque nueva: el reloj empieza de cero
local function NewBoot(self, tag, k, kind, h)
    local st = { hash = h, since = GetTime(), origins = { [k] = kind }, state = "b" }
    self.bootState[tag] = st
    HU.After(BOOT_MEMBERS + 1, function()
        if HU.bootState[tag] == st and st.state == "b" then HU:SetRosterState(tag, "m", "sin discusión") end
    end)
    HU.After(BOOT_RANKS + 1, function()
        if HU.bootState[tag] ~= st or STATE_RANK[st.state] >= 3 then return end
        HU:SetRosterState(tag, "p", "sin discusión", "time")
        -- (dos cuentas la respaldaban: se guardan, pero como antiguas)
        local r = HU.remoteRoster[tag]
        if OLD_FROM_TIME and st.two and r and r.byKey then
            for ok in pairs(st.origins) do
                local m = r.byKey[ok]
                if m then HU:RememberPeer(m.name, tag, true) end
            end
        end
    end)
    return "b"
end

-- Ha llegado entera por susurro (o completada con trozos de mi hermandad) una lista de esa hermandad
-- que me mandó k. nr ya está indexada. Devuelve el estado con que se guarda, o nil si se descarta.
-- ¿Se ha ido quien mandó la lista que tengo? (salió del canal después de su último saludo, o lleva
-- 10 min sin dar señales). Las listas son de conectados: si se fue, la del siguiente no le incluye
local function OriginGone(self, k)
    local p = self.remote[k]
    local left = self.chanLeftT and self.chanLeftT[k]
    -- (si no hablé nunca con él, solo cuenta haberle visto salir: si no, cualquier lista reenviada valdría)
    if not p then return left ~= nil end
    if left and left >= (p.last or 0) then return true end
    return GetTime() - (p.last or 0) > 600
end

function HU:DecideRoster(tag, k, kind, nr)
    kind = kind or "boot"
    local cur = self.remoteRoster[tag]
    local cs = StateOf(cur)
    local h = HU.MembersSigHash(nr.members)
    local curK = cur and cur.origin and self:Key(cur.origin)
    -- (la nueva deja fuera a quien hizo la que tengo, y ese sigue conectado: dicen cosas distintas)
    local conflict = cur and curK and curK ~= k and not (nr.byKey and nr.byKey[curK]) and cs ~= "b"
        and not OriginGone(self, curK)
    local inCur = cur and cur.byKey and cur.byKey[k] ~= nil
    local st = self.bootState[tag]
    if kind == "vouched" or kind == "peer" then
        -- (un contacto comprobado que contradice la que tengo sin confirmar: disputa; si la tengo [+ARCHITECTURE.md]
        if conflict and not self:AnchorValid(tag, k) then
            WarnDispute(self, tag, k, cur.origin)
            return NewBoot(self, tag, k, kind, h)
        end
        return "c"
    end
    if cs == "c" then
        if kind == "member" then return "c" end
        -- (confirmada pero sin renovar: un antiguo o alguien de ella puede abrir disputa; otro, solo aviso)
        if conflict then
            WarnDispute(self, tag, k, cur.origin)
            if kind == "old" or inCur then return NewBoot(self, tag, k, kind, h) end
        end
        return nil
    end
    -- sin confirmar (arranque, miembros o provisional)
    if st and st.hash == h then
        if not st.origins[k] then
            st.origins[k] = kind
            st.two = true
            local hasOld = false
            for _, kd in pairs(st.origins) do if kd == "old" then hasOld = true end end
            if hasOld and STATE_RANK[st.state] < 3 then
                st.state, st.pBy, st.upgrade = "p", "old", true
            elseif STATE_RANK[st.state] < 2 then
                st.state = "m"
            end
        end
        return st.state
    end
    -- (otra huella de quien ya la respaldaba, o de alguien que sale en ella: la lista ha cambiado)
    if st and (st.origins[k] or (inCur and kind == "member")) then
        st.hash = h
        st.origins[k] = st.origins[k] or kind
        return st.state
    end
    -- otro origen con otra lista: se discute
    if cur and cs ~= "b" then
        -- (con rangos por dos cuentas, solo la bajan un antiguo o alguien que sale en ella)
        if cs == "p" and cur.pBy == "old" and not (kind == "old" or inCur) then
            WarnDispute(self, tag, k, cur.origin)
            return nil
        end
        WarnDispute(self, tag, k, cur.origin)
    end
    return NewBoot(self, tag, k, kind, h)
end

-- Tras guardar una lista sin confirmar: subir antiguos, enlace provisional y segunda opinión
function HU:AfterRosterDecided(tag, k, r)
    local st = self.bootState[tag]
    if not st then return end
    r.pBy = (r.state == "p") and st.pBy or nil
    if st.upgrade then st.upgrade = nil; UpgradeOld(self, tag, st, r) end
    -- (enlace PROVISIONAL: lo que va para esa hermandad se le manda a quien me mandó la lista, pero sin [+ARCHITECTURE.md]
    if HU.MarkRelay and k then
        local p = self.remote[k]
        local kr = self:KnownRelay(tag)
        if p and p.tag == tag and not (kr and kr.name:lower() ~= p.name:lower()) then HU.MarkRelay(tag, p.name) end
    end
    -- Segunda opinión: se pide la lista a otra cuenta de esa hermandad (de su presentación); si su
    -- huella coincide, son dos cuentas y la lista sube sin esperar al reloj
    local n = 0
    for _ in pairs(st.origins) do n = n + 1 end
    if n >= 2 or (secondAsked[tag] and GetTime() - secondAsked[tag] < SECOND_EVERY) then return end
    local v = self.raSeen[tag]
    if not v then return end
    local best, bestIn
    for ck, t in pairs(v) do
        if ck ~= k and ck ~= self:MeKey() and GetTime() - t < VOUCH_TTL then
            local inList = r.byKey and r.byKey[ck] ~= nil
            if not best or (inList and not bestIn) then best, bestIn = ck, inList end
        end
    end
    if not best then return end
    secondAsked[tag] = GetTime()
    local name = (self.remote[best] and self.remote[best].name) or (r.byKey and r.byKey[best] and r.byKey[best].name) or best
    HU.After(1 + math.random() * 3, function() HU:Whisper(name, "RF~" .. (HU.myTag or "") .. "~2", true) end)
end
-- «/gu confirmar ETIQ»: un oficial da por confirmada la lista que tengo de esa hermandad (para una
-- comunidad nueva, sin contactos comprobados). Devuelve el estado de antes, o nil si no hay lista.
function HU:ConfirmRoster(tag)
    local r = self.remoteRoster[tag]
    if not r or not r.members or #r.members == 0 then return nil end
    local before = StateOf(r)
    if r.weak then r.weak = nil end
    self:SetRosterState(tag, "c", "confirmada a mano")
    if r.origin and self:MemberOf(r.origin, tag) then self:RememberPeer(r.origin, tag) end
    -- (a toda mi hermandad, la confirme quien la confirme: SetRosterState solo la reparte si soy el [+ARCHITECTURE.md]
    r.updated = GetTime()
    r.seq = r.seq or 1
    self:SendStoredRoster(tag, true)
    return before
end
HU.BootPresented = function(tag, name, now) Stamp(HU.raSeen, tag, name, now) end
HU.ForwarderPresented = function(tag, name, now) Stamp(HU.fwdVouch, tag, name, now) end

-- (hasta la 5.4.8 se guardaba como contacto a cualquiera que mandara una lista: lo guardado puede [+ARCHITECTURE.md]
HU:OnStart(function()
    local cdb = HU.cdb
    -- (peersV 3: la 5.4.8 de antes guardaba como comprobado a cualquiera que saludara por susurro;
    -- lo guardado con ella vuelve a ser antiguo)
    if cdb and (tonumber(cdb.peersV) or 1) < 3 then
        for _, list in pairs(cdb.peers or {}) do
            for _, e in pairs(list) do if type(e) == "table" then e.old = true end end
        end
        cdb.peersV = 3
    end
end)

-- ¿Contacto de esa hermandad del que me fío? Sale en su lista (no de arranque), es su ancla, un contacto
-- comprobado o lo nombró su enlace comprobado. Haber hablado en el canal o decir «soy el enlace» no basta
function HU:PeerVerified(name, tag)
    if not name or not tag then return false end
    return self:MemberOf(name, tag) or self:AnchorValid(tag, self:Key(name)) or self:FullPeer(name, tag)
        or self:VouchedOf(name, tag) or false
end
-- El mejor contacto, solo si me fío de él: para lo que lleva contraseñas (canal y canales extra). Antes [+ARCHITECTURE.md]
function HU:SafePeer(tag)
    local p = self:BestPeer(tag)
    if p and self:PeerVerified(p.name, tag) then return p end
    return nil
end

-- (se recuerda durante el fotograma: lo piden varias cosas seguidas para la misma hermandad, y cada vez
-- recorría a todos sus contactos)
local bpMemo = {}
function HU:BestPeer(tag)
    local now = GetTime()
    local m = bpMemo[tag]
    -- (si se ha quitado al elegido en este mismo fotograma, p. ej. «no está conectado», se busca otro) [+ARCHITECTURE.md]
    if m and m.t == now and m.p and self.remote[m.p.name:lower()] == m.p then return m.p end
    local p = self:BestPeerCalc(tag)
    bpMemo[tag] = { t = now, p = p }
    return p
end
function HU:BestPeerCalc(tag)
    local now, best, bestScore = GetTime(), nil, nil
    -- (con lista buena de esa hermandad, quien no sale en ella va detrás de todos los que sí. El [+ARCHITECTURE.md]
    local rr = self.remoteRoster[tag]
    local W = self.whitelist[tag]
    local good = (W and W.set and next(W.set)) or (rr and not rr.boot and not rr.weak)
    local set = W and W.set
    local byKey = rr and rr.byKey
    for _, key in ipairs(self:RemoteKeys(tag)) do
        local p = self.remote[key]
        local age = p and now - p.last
        if p and p.tag == tag and age < 900 then
            -- el enlace primero; entre dos que dicen ser enlace, el que lo dijo más tarde
            local score = (p.relay and (1000 + (p.relayT or 0) / 1000) or 0) - age / 10
            -- (lo que puede restar solo se mira si aún puede ganar: era lo que más costaba, hasta 3,4 ms)
            if not bestScore or score > bestScore then
                -- (su clave se guarda en su ficha: el nombre no cambia)
                local k = p._k
                if not k or p._kn ~= p.name then k = self:Key(p.name); p._k, p._kn = k, p.name end
                local member
                if k and set and set[k] then member = true
                elseif k and byKey then member = byKey[k] ~= nil and not byKey[k].weak
                else member = self:MemberOf(p.name, tag) end
                -- (detrás de todos los de fiar, también sin lista buena: el ancla o un contacto comprobado
                -- ganan a uno que solo dice ser el enlace. Si no hay nadie de fiar, sigue valiendo, para arrancar)
                if not member and not ((not good) and self:PeerVerified(p.name, tag)) then score = score - 3000 end
                if not bestScore or score > bestScore then best, bestScore = p, score end
            end
        end
    end
    return best
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
            if HU:LaunchPhase() and HU.PresenceSchedule and (not old or old.relay ~= sender or table.concat(old.list, ",") ~= f[5]) then
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
            if new and new.lane > HU:ChannelLane() and not HU:IsRelay() and HU.myTag and IsInGuild()
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
            HU.After(0.05, function() HU:SendRosterTo(to); HU:AnnounceList(to) end)
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
    if not self.myTag or self:IsTest() or not self:IsRelay() or not self:IsJoined("main") then return end
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
    local L = self.whitelist[tag]
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
    if ((L and L.set and next(L.set)) or (R and RS ~= "b")) and not (checked or self:MemberOf(author, tag)) then
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
            if r.annMiss >= 2 and self:LaunchPhase() and self.ResponsibleFor and self:ResponsibleFor(tag)
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
HU.comm.PH = function(self, sender, f, dist)
    if dist ~= "GUILD" then return end
    local tag, relay = f[1], f[2]
    if not tag or tag == self.myTag or not self.cfg or not self.cfg.byTag[tag] then return end
    -- Seguridad: de mi enlace, sus ayudantes o un oficial, como antes. De otro compañero, solo si el [+ARCHITECTURE.md]
    local strict = not self:IsTest() and not self:IsGuildForwarder(sender)
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
        local firm = self:IsTest() or self:CheckedOf(relay, tag) or self:FullPeer(relay, tag) or self:VouchedOf(relay, tag)
        MarkRelay(tag, relay, firm and true or nil)
    end
end

-- Un compañero se ha pasado a otro carril del canal (LN~n): el enlace lo comprueba sondeando el [+ARCHITECTURE.md]
local laneProbeT = -999
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
HU.comm.LP = function() end
-- LQ: «¿en qué carril estás?» de otra hermandad. Contesto con mi LN por susurro (a cada uno como [+ARCHITECTURE.md]
do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locales)
local laneAnswerT, laneAnswered, laneAnswerN = -999, {}, 0
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
end
-- LX~carril~gen~hora~ETIQ~contacto: un compañero me pasa el aviso de carril del contacto de otra [+ARCHITECTURE.md]
HU.comm.LX = function(self, sender, f, dist)
    if dist ~= "GUILD" or not self:IsRelay() or not self.OfferLane then return end
    local tag, contact = f[4], f[5]
    if not tag or tag == "" or tag == self.myTag or not self.cfg or not self.cfg.byTag[tag] then return end
    if not contact or not HU.SafeName(contact) or not self:MemberOf(contact, tag) then return end
    self:OfferLane(HU.ParseLane(f[1], f[2], f[3]), contact, "contact")
end
-- «¿Eres de la hermandad?» (PG~nombre) y la respuesta (PA), las dos por la vía GUILD del juego
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
HU.comm.PA = function(self, sender, f, dist)
    if dist ~= "GUILD" then return end
    local k = sender:lower()
    local p = self.guildPeers[k]
    if not p then self.guildPeers[k] = { name = sender, last = GetTime(), score = 0 } else p.last = GetTime() end
    HU.ForgetRelayMemo()
    if self.ReplayHeldChat then self:ReplayHeldChat(k) end
end
HU.comm.HI = function(_, sender, f, dist) OnHello(sender, f, dist, false) end
HU.comm.HR = function(_, sender, f, dist) OnHello(sender, f, dist, true) end

-- Lista de contactos compartida por el enlace dentro de la hermandad
local plSeen = {}
-- También llega por susurro: el enlace de otra hermandad nos presenta a los contactos que
-- conoce de las demás (si no, dos hermandades sin moderadores en el canal no se encontraban)
local plForward = {}
HU.comm.PL = function(self, sender, f, dist, raw)
    if dist ~= "GUILD" and dist ~= "WHISPER" then return end
    -- Seguridad: por susurro solo lo presenta el enlace (o un ayudante u oficial) comprobado de otra [+ARCHITECTURE.md]
    local strict = false
    if not self:IsTest() then
        if dist == "WHISPER" then
            local sp = self.remote[sender:lower()]
            if not (sp and sp.tag and self:IsRemoteForwarder(sender, sp.tag)) then
                if self.Debug then self:Debug("PL por susurro no aceptado:", sender) end
                return
            end
        else
            strict = not self:IsGuildForwarder(sender)
        end
    end
    for pair in (f[1] or ""):gmatch("[^,]+") do
        local tag, name = pair:match("^(%w+):(.+)$")
        if tag then plSeen[tag] = GetTime() end
        local rr = tag and self.remoteRoster[tag]
        local known = tag and (self.whitelist[tag] or (rr and HU.RosterStateOf(rr) ~= "b"))
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
HU.comm.PR = function(self, sender, f, dist)
    if dist ~= "GUILD" then return end
    for tag in (f[1] or ""):gmatch("%w+") do
        local p = self:LaunchPhase() and self:KnownRelay(tag) or (not self:LaunchPhase() and self:BestPeer(tag))
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
    if not self:LaunchPhase() then return nil, "" end
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

local function RosterEntries(self)
    -- (se guarda hasta que cambia la lista: antes se rehacía para cada aviso y cada presentación)
    local v = self.rosterVersion or 0
    local extra, extraKey = SharedExtra(self)
    if reCache.v == v and reCache.src == self.rosterList and reCache.ek == extraKey then return reCache.list, reCache.sig, reCache.full end
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
                    en = table.concat({ short, cls, lvl, rank, Clean(HU.Utf8Cut(e.zone or "", 24)) .. (e.afk and ",a" or "") }, ","),
                    -- lo que importa para avisar de un cambio (la zona cambia sin parar: no cuenta)
                    sig = table.concat({ cls, lvl, rank, e.afk and "a" or "" }, ",") }
                e._re = c
            end
            list[#list + 1] = c.en
            full[c.short] = c.en
            sig[c.short] = c.sig
        end
    end
    reCache = { v = v, src = self.rosterList, ek = extraKey, list = list, sig = sig, full = full }
    return list, sig, full
end
RosterEntriesFn = RosterEntries
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
    if self.RankNamesMessage then
        local rn = self:RankNamesMessage()
        if rn then self:Whisper(target, rn) end
    end
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
do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locales)
local pushed = {}
local pushMin = { t = 0, n = 0 }
local function PushRoster(name, tries)
    if #bulk > 150 then
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
    if not self:LaunchPhase() or not self.myTag then return end
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
end

-- Recién entrado: si me falta la lista de conectados de alguna hermandad, se la pido a su
-- contacto (si no, tendría que esperar a que la manden entera, cada 30 minutos)
do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locales)
local rfAsked = {}
local rfRetry = {}
function HU:AskMissingRosters()
    if not self.myTag then return end
    -- (en cada hermandad lo pide solo quien se encarga de esa otra hermandad;
    -- la lista entera llega por GUILD y les sirve a todos)
    local pooled = self:IsRelay() or (self.relayHelpers and GetTime() - self.relayHelpers.t < 700)
    -- (una hermandad por fotograma: buscar el contacto de todas las que faltan seguido llegaba a 4 ms)
    local n = 0
    for _, tag in ipairs(self:OtherTags()) do
        if not self.remoteRoster[tag] then
            n = n + 1
            HU.After(0.02 * (n - 1), function() HU:AskMissingRosterTag(tag, pooled) end)
        end
    end
end
function HU:AskMissingRosterTag(tag, pooled)
    if not self.myTag then return end
    local now = GetTime()
    do
        local p = not self.remoteRoster[tag] and self:BestPeer(tag)
        -- (fase de lanzamiento: la lista son unos pocos nombres; quien no la tiene la pide él mismo.
        -- El enlace que volvía de una desconexión se quedaba sin la de alguna hermandad)
        if p and pooled and not self:ResponsibleFor(tag) and not self:LaunchPhase() then p = nil end
        -- (quien vuelve de una desconexión ha perdido los contactos y el "mejor" puede ser cualquiera [+ARCHITECTURE.md]
        if p and self:LaunchPhase() and not p.relay then
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
    if not self.myTag or not IsInGuild() or self:IsTest() or not self.cfg or not self.db then return end
    local _, onlineNow = GetNumGuildMembers()
    -- (quien puede repartir la lista confirmada a su hermandad pregunta primero; los rasos, después)
    local sharer = self:CanOfficer() or self:IsRelay() or (self.RosterSlot and self:RosterSlot() ~= nil)
    local wide = sharer or (tonumber(onlineNow) or 0) <= 1
    if late == nil and not wide then return end
    if late and wide then return end
    local me = self:MeKey()
    for _, tag in ipairs(self:OtherTags()) do
        local s = HU.RosterStateOf and HU.RosterStateOf(tag)
        -- Contactos comprobados (no antiguos) de esa hermandad: con ellos cualquiera, también un raso, [+ARCHITECTURE.md]
        local full = {}
        for k, e in pairs((self.db.peers or {})[tag] or {}) do
            if type(e) == "table" and type(e.name) == "string" and k ~= me and not e.old then full[#full + 1] = e end
        end
        -- (idea de Olympus: si otro de mi hermandad la ha pedido o ha pasado por ella hace menos de 30 s,
        -- no la pido a los antiguos: llega a todos por GUILD. Así no se multiplican las peticiones)
        local busy = (#full == 0) and HU.GuildAskedRecently and HU.GuildAskedRecently(tag, 30)
        if s ~= "c" and (wide or #full > 0) and not busy and not (self.RosterTrusted and self:RosterTrusted(tag)) and (savedAsked[tag] or 0) < 4 then
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
do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locales)
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
    if not self.myTag or not IsInGuild() or self:IsTest() or GetTime() - lastNQ < brake then return end
    local r, w = {}, {}
    local need = self.rosterNeed or {}
    local now = GetTime()
    -- (la misma hermandad, como mucho cada 2 minutos: la respuesta puede tardar en llegar)
    for _, tag in ipairs(self:OtherTags()) do
        if (not self.remoteRoster[tag] or need[tag]) and not Recent("R" .. tag) and (nqTry < 3 or not nqAsked["R" .. tag] or now - nqAsked["R" .. tag] > 120) then
            r[#r + 1] = tag
            nqAsked["R" .. tag] = now
        end
        if not self:BigCommunity() and (not self.whitelist[tag] or (self.listNeed and self.listNeed[tag])) and not Recent("W" .. tag) and (nqTry < 3 or not nqAsked["W" .. tag] or now - nqAsked["W" .. tag] > 600) then
            w[#w + 1] = tag
            nqAsked["W" .. tag] = now
        end
    end
    if #r == 0 and #w == 0 then return end
    lastNQ = GetTime()
    nqTry = nqTry + 1
    -- (cada intento le toca a otro: por si al primero le faltaba también)
    self:Send(HU.Utf8Cut("NQ~" .. nqTry .. "~R:" .. table.concat(r, ",") .. "~W:" .. table.concat(w, ","), 250), "GUILD", nil, true)
end
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
    local gap = self:LaunchPhase() and 10 or 600
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
            local zone = HU.Utf8Cut((tostring(m.zone or "")):gsub("[~,;|]", " "), 24)
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
do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locales)
local WELCOME_DELAY, WELCOME_GAP = 1, 10
local welcomeAt = {}   -- [tag] = cuándo sale (o salió) el último reparto por bienvenida
function HU:WelcomeGuildmate()
    if not self.myTag or not self.cfg or self:IsTest() then return end
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
                local gap = self:LaunchPhase() and WELCOME_GAP or 300
                local at = math.max(now + WELCOME_DELAY, (last or -999) + gap)
                welcomeAt[tag] = at
                HU.After(at - now + math.random() * 0.5, function() HU:SendStoredRoster(tag, true) end)
            end
        end
    end
end
end
-- Cuántos «X se ha conectado» he visto en los últimos secs: con pocos es el día a día (se contesta y se
-- pregunta al momento); con muchos, una entrada masiva (se reparte al azar para no mandar cientos a la vez)
do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locales)
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
end

-- Me falta (o tengo a medias) la lista de conectados de esa hermandad: se pide a mi hermandad
function HU:NeedRoster(tag)
    self.rosterNeed = self.rosterNeed or {}
    self.rosterNeed[tag] = true
    HU.After(1 + math.random() * 8, function() HU:AskGuildForMissing() end)
end

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
                and HU.RosterStateOf and HU.RosterStateOf(self.remoteRoster[tag]) == "c"
            local own = tag ~= self.myTag and self.cfg and self.cfg.byTag[tag]
            if own and self:ResponsibleFor(tag, sender, try - 1) then
                if kind == "R" and self.remoteRoster[tag] then
                    if fast then HU.After(0.1, function() HU:SendStoredRoster(tag, quiet(2)) end)
                    else HU.After(0.5 + math.random() * 2, function() HU:SendStoredRoster(tag) end) end
                elseif kind == "W" and self.whitelist[tag] then
                    HU.After(0.5 + math.random() * 2, function() HU:SendList(tag, "GUILD") end)
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
        local fast = (nparts <= 3 and self:LaunchPhase() and not self:SimpleMode()) or nil
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
        local quietMax = HU:LaunchPhase() and 15 or 120
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
    if self.DropGhost then self:DropGhost(tag) end

    local members = {}
    local dict = ZoneDict(pt.parts, nparts)
    local W = pt.weak and self.whitelist[tag]
    for i = 1, nparts do
        for en in (pt.parts[i] or ""):gmatch("[^;]+") do
            local m = ParseRosterEntry(self, en, tag, dict)
            if m and pt.weak then
                -- (de un compañero cualquiera: sin rango, y solo quien esté en su lista de miembros)
                m.rankIndex, m.weak = nil, true
                if W and W.set and not W.set[m.name:lower()] then m = nil end
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
        if (self:IsRelay() or (self.ResponsibleFor and self:ResponsibleFor(tag)))
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
        if pt.fwdFlag ~= state and (self:IsRelay() or self:HandlesTag(tag) or (state == "c" and (self:CanOfficer() or (self.RosterSlot and self:RosterSlot() ~= nil)))) then self:SendStoredRoster(tag, true) end
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
do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locales)
local dpartial = {}
local fullAsked = {}

-- Me piden la lista entera (tenían otra versión y no les valen los cambios)   RF~SUETIQUETA
local secondAnswered = {}
local rfLater = {}      -- [etiqueta] = envío pendiente para cuando acabe el freno de RF { sender, f }
local SECOND_MAX, SECOND_WIN = 6, 10   -- respuestas a RF~etiq~2 como mucho, en total, cada tanto
local secondWin = { t = 0, n = 0 }
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
    local gap = (f[2] == "1") and 5 or (self:LaunchPhase() and 30 or 120)
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
    if dist == "WHISPER" then
        self:SeenPeer(sender, tag)
        local p = self.remote[sender:lower()]
        if p then p.last = GetTime() end
        -- (a mi hermandad, con el estado de mi copia al final: la toman igual que yo)
        local fl = HU.RosterStateOf(self.remoteRoster[tag]) or "b"
        local withState = raw .. "~" .. fl
        -- (los cambios pequeños, a mi hermandad al momento y por delante: conectado/desconectado)
        local fast = (nparts <= 2 and not self:SimpleMode()) or nil
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
        if self.NeedRoster then self:NeedRoster(tag) end
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
        if h ~= want and dist == "WHISPER" and (not fullAsked[tag] or GetTime() - fullAsked[tag] > 60) then
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
end

---------------------------------------------------------------------------
-- Seguridad de los mensajes del addon [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local TAG_FIELD = { HI = 2, HR = 2, WH = 1, WL = 1, WD = 1, RB = 1, RC = 1, RN = 1, PB = 1, OD = 1, OE = 1, RF = 1, RA = 1 }
-- (RA por susurro: la presentación del enlace en Forever, con las mismas reglas que su saludo)
-- (RC: los cambios de la lista de conectados valen igual que la lista entera, que ya se acepta)
local BOOTSTRAP = { HI = true, HR = true, WH = true, WL = true, RB = true, RC = true, RN = true, WQ = true, RF = true, RA = true }

local function AnyListMissing()
    for _, tag in ipairs(HU:OtherTags()) do if not HU.whitelist[tag] then return true end end
    return false
end

-- invitaciones de hermandades nuevas: llegan de gente que aún no está en las listas
-- (cada mensaje comprueba por su cuenta que viene de quien toca)
do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locales)
local OPEN = { GV = true, GA = true, GL = true, CK = true } -- (CK: canal pasado a mano; solo vale de provisional, ver Channels.lua)

-- Por el canal oculto solo van la presentación del enlace y la sonda del carril (el chat va con su [+ARCHITECTURE.md]
local CHANNEL_OK = { RA = true, LP = true }

-- Datos de OTRA hermandad que llegan por la mía: solo los reparten el enlace, sus ayudantes o un
-- oficial (antes, cualquiera de la hermandad podía colar una lista con él de maestro de la otra)
local REMOTE_DATA = { WL = true, WD = true, RB = true, RC = true, RN = true, PB = true, OD = true, OE = true }

-- Quien ha hablado por nuestro canal oculto (hace falta la contraseña): es de la comunidad
HU.chanSeen = HU.chanSeen or {}
-- Lectura de la lista del canal a petición (cuando llega un saludo o una lista de alguien sin avalar): [+ARCHITECTURE.md]
local CHECK_GAP, checkAt = 15, -999
function HU:CheckChannelSoon()
    if GetTime() - checkAt < CHECK_GAP or not self:IsJoined("main") then return end
    if not (self:IsRelay() or self:CanOfficer() or self.chanIAmMod) then return end
    checkAt = GetTime()
    HU.After(0.5, function() HU:GetChannelMembersAsync("main", function() end) end)
end
HU:On("CHAT_MSG_CHANNEL_JOIN", function(_, author, _, fullName, _, _, _, _, baseName)
    if HU:KindOf(baseName, fullName) == "main" and author then HU:MarkChannelSeen(HU:FullName(author)) end
end)
function HU:MarkChannelSeen(sender)
    if not sender then return end
    local k = sender:lower()
    local first = not self.chanSeen[k]
    self.chanSeen[k] = GetTime()
    if first and self.ReplayHeld then self:ReplayHeld(k) end
end

-- ¿Puedo fiarme de que un desconocido es de la comunidad, aunque aún no tenga su lista? [+ARCHITECTURE.md]
function HU:Vouched(sender, tag)
    local k = sender and sender:lower()
    if not k then return false end
    local seen = self.chanSeen[k]
    if seen and GetTime() - seen < 7200 then return true end
    -- (o sale en la lista del canal, que leen el enlace y los oficiales: ver StoreChannelMembers)
    if self.chanRosterKeys and self.chanRosterKeys[k] and GetTime() - (self.chanRosterKeysT or 0) < 900 then return true end
    -- (en Forever lo oculto por el canal no llega: vale estar en la lista de miembros del canal)
    if self.ChannelHas and self:ChannelHas(sender) == true then return true end
    local p = self.remote[k]
    if p and (not tag or p.tag == tag) then return true end
    -- (los ayudantes que su enlace, visto en el canal, ha anunciado en su presentación)
    local now = GetTime()
    for t, h in pairs(self.helpers or {}) do
        if (not tag or t == tag) and h.list and h.t and now - h.t < 900 then
            for _, n in ipairs(h.list) do
                if n:lower() == k or (self:Key(n) or "") == k then return true end
            end
        end
    end
    if tag then
        local peers = self.db and self.db.peers and self.db.peers[tag]
        if peers and peers[k] then return true end
    else
        for _, peers in pairs(self.db and self.db.peers or {}) do if peers[k] then return true end end
    end
    return false
end

function HU:AllowAddonMessage(cmd, sender, f, dist, localID, chanName)
    if dist == "GUILD" then
        if REMOTE_DATA[cmd] then
            local tag = f[TAG_FIELD[cmd]]
            if tag and tag ~= "" and tag ~= self.myTag and self:KnownGuildRelay() then
                if self:IsGuildForwarder(sender) then return true end
                -- (la lista de conectados de un compañero: vale, pero débil; ver HU.comm.RB)
                if cmd == "RB" then return true, true end
                return false
            end
        end
        return true
    end
    if dist == "CHANNEL" then
        return CHANNEL_OK[cmd] == true and self:OurChannelKind(localID, chanName) ~= nil
    end
    if dist ~= "WHISPER" then return false end
    if OPEN[cmd] then return true end
    -- (el chat por el respaldo: de quien es de la comunidad o ha pasado por el canal; el resto lo
    -- mira HU.comm.CW, en Channel.lua)
    if cmd == "CW" then return self:InAnyGuild(sender) or self:Vouched(sender) end
    local tagField = TAG_FIELD[cmd]
    local tag = tagField and f[tagField]
    if tag and tag ~= "" then
        -- nadie de fuera puede mandar datos de mi propia hermandad
        if tag == self.myTag then return false end
        local L = self.whitelist[tag]
        -- Lista de conectados de otra hermandad sin su lista completa (fase de lanzamiento): antes [+ARCHITECTURE.md]
        if (cmd == "RB" or cmd == "RC") and not (L and L.set and next(L.set)) then
            if not (self.cfg and self.cfg.byTag[tag]) then return false end
            local kind = self:SenderKind(sender, tag)
            if not kind then return false end
            if kind == "boot" and self:RosterTrusted(tag) then return false end
            local ak = self.acceptKind[tag] or {}
            self.acceptKind[tag] = ak
            ak[self:Key(sender)] = kind
            return true
        end
        if L and L.set and next(L.set) then
            -- el aviso de "mi lista ha cambiado" vale de cualquiera de esa hermandad (puede ser [+ARCHITECTURE.md]
            if cmd == "WH" or cmd == "RF" then return self:MemberOf(sender, tag) or self:Vouched(sender, tag) end
            return self:MemberOf(sender, tag)
        end
        -- todavía no tenemos la lista de esa hermandad: solo saludos y listas para arrancar, y
        -- solo de quien es de la comunidad
        return BOOTSTRAP[cmd] and self.cfg and self.cfg.byTag[tag] ~= nil and self:Vouched(sender, tag) or false
    end
    if self:InAnyGuild(sender) then return true end
    -- mientras falte alguna lista: pedirla y que me presenten contactos
    return (cmd == "WQ" or cmd == "PL") and AnyListMissing() and self:Vouched(sender)
end
end

---------------------------------------------------------------------------
-- Recepción
---------------------------------------------------------------------------
local held, heldN = {}, 0 -- [remitente..orden] = { sender, text, prefix, t }
function HU:ReplayHeld(who)
    if heldN == 0 then return end
    local now = GetTime()
    for key, e in pairs(held) do
        if now - e.t > 180 then
            held[key] = nil; heldN = heldN - 1
        elseif (not who or e.sender:lower() == who) and self:Vouched(e.sender) then
            held[key] = nil; heldN = heldN - 1
            HU.replaying = true
            HU:SafeCall("arranque", HU.OnAddonMessage, e.prefix, e.text, "WHISPER", e.sender)
            HU.replaying = nil
        end
    end
end
local function Hold(prefix, text, sender, cmd)
    if HU.replaying then return end
    -- (una lista de varios trozos se guarda entera: antes la clave era remitente + orden y cada trozo [+ARCHITECTURE.md]
    local key = sender:lower() .. cmd
    if cmd == "RB" or cmd == "RC" then key = key .. "\1" .. text end
    if not held[key] then
        if heldN >= 100 then return end
        heldN = heldN + 1
    end
    held[key] = { sender = sender, text = text, prefix = prefix, t = GetTime() }
end

-- Seguridad (idea n.º 8 de Olympus): admisión con tope por remitente. De cada uno de fuera de mi [+ARCHITECTURE.md]
local ADMIT_BURST, ADMIT_RATE, ADMIT_MAX = 60, 2, 3000
local TRUST_BURST, TRUST_RATE = 200, 10
local admit, admitN = {}, 0
HU.diagAdmitDrop = { comprobado = 0, otro = 0 }
local function Trusted(k, sender)
    local p = HU.remote[k]
    local tag = p and p.tag
    if not tag then return false end
    if HU.FullPeer and HU:FullPeer(sender, tag) then return true end
    if HU.CheckedOf and HU:CheckedOf(sender, tag) then return true end
    local rp = HU.KnownRelay and HU:KnownRelay(tag)
    return rp ~= nil and rp.name ~= nil and rp.name:lower() == k
end
local function Admit(sender, dist)
    if dist == "GUILD" then return true end
    local k = sender:lower()
    if HU.roster and HU.roster[k] then return true end
    local now = GetTime()
    local b = admit[k]
    if b then
        -- (si es comprobado se mira como mucho cada 10 s: puede pasar a serlo mientras habla)
        if now - (b.trT or 0) > 10 then b.tr, b.trT = Trusted(k, sender), now end
        local burst, rate = b.tr and TRUST_BURST or ADMIT_BURST, b.tr and TRUST_RATE or ADMIT_RATE
        b.n = math.min(burst, b.n + (now - b.t) * rate)
        b.t = now
    else
        if admitN >= ADMIT_MAX then
            -- (los que llevan más de un minuto callados ya tienen el cupo lleno: se pueden olvidar)
            for kk, bb in pairs(admit) do if now - bb.t > 60 then admit[kk] = nil; admitN = admitN - 1 end end
            if admitN >= ADMIT_MAX then local kk = next(admit); admit[kk] = nil; admitN = admitN - 1 end
        end
        local tr = Trusted(k, sender)
        b = { n = tr and TRUST_BURST or ADMIT_BURST, t = now, tr = tr, trT = now }
        admit[k] = b
        admitN = admitN + 1
    end
    if b.n < 1 then
        local d = HU.diagAdmitDrop
        if b.tr then d.comprobado = d.comprobado + 1 else d.otro = d.otro + 1 end
        return false
    end
    b.n = b.n - 1
    return true
end

-- (idea n.º 8, segunda parte) trozos a medio recibir con tope: 4 por remitente de fuera y 400 en total. [+ARCHITECTURE.md]
do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locales)
local PART_PER_SENDER, PART_TOTAL = 4, 400
function HU.PartialAdmit(tbl, sender, dist)
    local sk = (sender or ""):lower()
    local guild = dist == "GUILD"
    local n, mine, by = 0, 0, {}
    for _, v in pairs(tbl) do
        n = n + 1
        if v.by == sk then mine = mine + 1 end
        if v.by and not v.g then by[v.by] = (by[v.by] or 0) + 1 end
    end
    if not guild and mine >= PART_PER_SENDER then return false end
    if n < PART_TOTAL then return true end
    local worst, wn = nil, 0
    for who, c in pairs(by) do if c > wn then worst, wn = who, c end end
    if not worst then return guild end -- (todo es de mi hermandad: lo de fuera no entra)
    local oldK, oldT
    for key, v in pairs(tbl) do
        if v.by == worst and not v.g and (not oldT or (v.t or 0) < oldT) then oldK, oldT = key, v.t or 0 end
    end
    if oldK then tbl[oldK] = nil end
    return true
end
end

function HU.OnAddonMessage(prefix, text, dist, sender, _, _, localID, chanName)
    if (prefix ~= HU.PREFIX and prefix ~= HU.PREFIX_B) or type(text) ~= "string" or not HU.db then return end
    sender = HU:FullName(sender)
    if sender and sender:lower() ~= HU:MeKey() and not Admit(sender, dist) then return end
    if sender and sender:lower() == HU:MeKey() then
        -- mi propio saludo vuelve por la hermandad: cuánto ha tardado (la conexión real)
        if dist == "GUILD" and text:sub(1, 3) == "HI~" and perf.hiSent then
            local d = GetTime() - perf.hiSent
            perf.hiSent = nil
            if d >= 0 and d < 30 then perf.rtt = perf.rtt and (perf.rtt * 0.7 + d * 0.3) or d end
        end
        return
    end
    if not sender then return end
    local cmd, rest = text:match("^(%u%u?)~?(.*)$")
    if cmd then HU.diagRecv = HU.diagRecv or {}; HU.diagRecv[cmd] = (HU.diagRecv[cmd] or 0) + 1 end
    local h = cmd and HU.comm[cmd]
    if not h then return end
    local f = HU.Split(rest, "~")
    local allowed, weak = HU:AllowAddonMessage(cmd, sender, f, dist, localID, chanName)
    if not allowed then
        HU:Debug("Mensaje rechazado (seguridad):", cmd, "de", sender)
        -- (arranque de alguien aún sin avalar: se guarda por si lo avalan enseguida)
        if dist == "WHISPER" and BOOTSTRAP[cmd] then
            Hold(prefix, text, sender, cmd)
            -- (si leo la lista del canal, se mira ya si está en él, en vez de esperar a mi saludo de cada
            -- 2-5 min: si está, queda «visto en el canal» y lo retenido se aplica; ver StoreChannelMembers)
            if HU.CheckChannelSoon then HU:CheckChannelSoon() end
        end
        return
    end
    HU.weakMsg = weak or nil -- (se pone en cada mensaje: nunca se queda de otro)
    if dist == "CHANNEL" then HU:MarkChannelSeen(sender) end
    h(HU, sender, f, dist, text)
end
HU:On("CHAT_MSG_ADDON", HU.OnAddonMessage)

---------------------------------------------------------------------------
-- Ciclos
---------------------------------------------------------------------------
-- (el juego avisa también al mover el canal de número: solo se saluda una vez por minuto)
do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locales)
local lastJoinHello = -999
function HU:OnMainJoined()
    if GetTime() - lastJoinHello < 60 then return end
    lastJoinHello = GetTime()
    HU.After(3, function() HU:HelloCycle() end)
end
end

local plSent = {}
local modHello = {}
function HU:HelloCycle()
    if not self.myTag or not IsInGuild() then return end
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
            local rp = self:LaunchPhase() and self:KnownRelay(tag) or (not self:LaunchPhase() and p)
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
    -- si aún estoy mandando lo anterior, espero (con hermandades enormes son cientos de mensajes)
    if #bulk > 150 then return end -- (las listas de conectados van en su propia cola)
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
    local st = rosterState[tag]
    -- (fase de lanzamiento: la lista entera son 2 mensajes; cada 5 min, por si algún cambio
    -- se perdió por el camino. Con la lista de todos, cada 30 min)
    if not st or now - st.fullT >= (self:LaunchPhase() and 300 or 1800) then
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
    HU.NewTicker(1.0, function()
        btokens = math.min(MAX_TOKENS, btokens + 1)
        tokens = math.min(MAX_TOKENS, tokens + 1)
        -- (si el juego cuenta los dos prefijos juntos, lo que sale primero se lleva el sitio: antes [+ARCHITECTURE.md]
        if #qChat > 0 or (#queue > 0 and #bfast == 0) then
            Flush(); FlushBulk()
        else
            FlushBulk(); Flush()
        end
    end)
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
    for _, d in ipairs({ 30, 60 }) do HU.After(d, function() if HU:LaunchPhase() then HU:AskMissingRosters() end end) end
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
