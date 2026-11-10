-- Guild Union - eco en /g: el enlace escribe en su /g lo que llega de las otras hermandades y pasa a
-- las demás el /g de los compañeros que no tienen el addon
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

-- (2,5 líneas por segundo en el /g: Forever aguantó 3/s durante 30 s, y así queda margen para el
-- /g del propio enlace y de otros addons)
local ECHO_EVERY = 1 / 2.5
local ECHO_MAX = 10      -- si hay más esperando, se tiran las más viejas y se avisa con «(+N…)»
local ECHO_WAIT = 1.5    -- solo si hay duda de enlace: espera por si otro enlace ya lo escribió
local HANDOVER_EXTRA = 2 -- y 2 s más para el enlace de antes, durante el traspaso
local SILENT_SECS = 15   -- un enlace conectado que lleva esto sin copiar nada: lo copia el suplente
local queue, dropped, dropTag, timer = {}, 0, nil, false
local byOthers, byOthersN = {}, 0      -- líneas de eco que ya escribió otro compañero
local unwrapSeen, unwrapN = {}, 0      -- [ETIQ:E] ya recibidas (por si las mandan dos enlaces)
local shownLines, shownN = {}, 0       -- líneas de otras hermandades que ya he visto por el canal
local relaySeen = {}                   -- [etiq] = { [clave] = GetTime() }: enlaces de las otras
local viaSeen = {}                     -- [etiq] = { [clave] = GetTime() }: portadores vistos en su lista
local echoStar, echoViaLog = {}, {}    -- autores de líneas sin confirmar ("Pepe") y quién las trajo
local watch = {}                       -- (suplente) líneas que el enlace aún no ha copiado
local relayEchoT = -999                -- última línea de eco que he visto escribir al enlace
local deputyOn = false                 -- el enlace está mudo y copio yo

---------------------------------------------------------------------------
-- Reconocer una línea de eco por su CONTENIDO: «[ETIQ] Nombre: texto» en cualquier sitio de la
-- línea (otro addon, como Guild Roster Manager, puede poner algo delante) y sin colores
---------------------------------------------------------------------------
-- (las tablas de «ya visto» se recortan quitando lo viejo, no vaciándolas: en una hora punta se
-- vaciaban enteras y el eco de líneas ya vistas se pintaba otra vez; banco, hora punta)
local function Prune(t, maxAge)
    local now, n, out = GetTime(), 0, {}
    for k, v in pairs(t) do
        if now - v < maxAge then out[k] = v; n = n + 1 end
    end
    if n > 2000 then return {}, 0 end
    return out, n
end

local function Plain(s)
    return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
-- devuelve etiqueta, nombre, texto y la clave para comparar, o nil
local function ParseEcho(msg)
    if type(msg) ~= "string" then return nil end
    -- (el nombre puede llevar un espacio: en Forever sale «Nombre Apellido»)
    local tag, name, text = Plain(msg):match("%[(%w+)%] ([^%s:%[%]]+ ?[^%s:%[%]]*): (.*)$")
    if not tag or not HU.cfg or not HU.cfg.byTag[tag] then return nil end
    -- ("Pepe" = sin confirmar: el nombre de verdad va sin comillas, también para comparar)
    name = name:gsub("^\"(.-)\"$", "%1")
    return tag, name, text, ("[" .. tag .. "] " .. name .. ": " .. text):lower()
end
HU.ParseEcho = ParseEcho

-- Aviso de una vez al encenderse el eco (lo escribe en /g quien hace de eco). Sin emoji: el juego
-- no los pinta
local function Announce() return L("Eco de GuildUnion activado: aquí verás el chat de las otras hermandades.") end
local function IsAnnounce(msg)
    local p = Plain(msg)
    return p == "Eco de GuildUnion activado: aquí verás el chat de las otras hermandades."
        or p == Announce()
end

-- ¿Es una línea de eco que ha escrito en /g un compañero (o yo)?
function HU:IsEchoLine(msg, author)
    if IsAnnounce(msg) then
        local k = author and self:Key(author)
        return k ~= nil and (k == self:MeKey() or (self.guildPeers and self.guildPeers[k]) or (self.roster and self.roster[k])) and true or false
    end
    local tag, _, _, key = ParseEcho(msg)
    if not tag or tag == self.myTag then return false end
    local k = author and self:Key(author)
    if not k then return false end
    if k == self:MeKey() then return true end
    -- (de cualquier compañero, no solo del enlace: si mi addon no cree que sea él, igual es eco)
    if (self.guildPeers and self.guildPeers[k]) or (self.roster and self.roster[k]) then return true end
    local t = shownLines[key]
    return t ~= nil and GetTime() - t < 60
end
---------------------------------------------------------------------------
-- ¿Me toca escribir el eco?
---------------------------------------------------------------------------
-- El enlace. El que entra NUNCA (IsRelay espera 30 s y luego lo dice en su saludo). En el relevo, [+ARCHITECTURE.md]
local lastRelayT = -999
local function EchoRelay(self)
    if self:IsRelay() then lastRelayT = GetTime() return true, false end
    if GetTime() - lastRelayT > 180 or not self.RelayName then return false, false end
    local k = self:Key(self:RelayName() or "")
    local p = k and self.guildPeers and self.guildPeers[k]
    if p and p.relay then return false, false end
    return true, true
end

-- ¿Hay duda de quién es el enlace en mi hermandad? Solo entonces se espera ECHO_WAIT antes de [+ARCHITECTURE.md]
local DOUBT_SECS = 15
local relayChangeT, lastRelayKey, lastIAm = -999, nil, nil
local function NoteRelayState(self)
    local k = self.RelayName and self:Key(self:RelayName() or "")
    local iam = self:IsRelay()
    if k ~= lastRelayKey or iam ~= lastIAm then
        if lastRelayKey ~= nil or lastIAm ~= nil then relayChangeT = GetTime() end
        lastRelayKey, lastIAm = k, iam
    end
    return k
end
local function RelayDoubt(self, handover)
    if handover or deputyOn then return true end
    local now = GetTime()
    if now - (self.loginT or -999) < 60 then return true end
    local rk = NoteRelayState(self)
    if now - relayChangeT < DOUBT_SECS then return true end
    for k, p in pairs(self.guildPeers or {}) do
        -- (su saludo puede ser de hace minutos: vale mientras siga en la lista)
        if p.relay and k ~= rk and now - (p.last or 0) < HU.PEER_TTL then return true end
    end
    return false
end

local function EchoCfgOn(self)
    return not self:IsTest() and self.cfg and self.cfg.echo == true and self.myTag ~= nil and IsInGuild()
end
function HU:EchoEnabled()
    if not EchoCfgOn(self) then return false end
    return (EchoRelay(self))
end

-- El suplente: el primero (por nombre) de los compañeros con addon conectados que no es el enlace.
-- Solo copia si el enlace sigue conectado pero lleva SILENT_SECS sin copiar lo que llega.
local function IsDeputy(self)
    local rk = self.RelayName and self:Key(self:RelayName() or "")
    local me, now = self:MeKey(), GetTime()
    if not me or me == rk then return false end
    local best = me
    for k, p in pairs(self.guildPeers or {}) do
        if k ~= rk and now - (p.last or 0) < HU.PEER_TTL and k < best then best = k end
    end
    return best == me
end

---------------------------------------------------------------------------
-- Escribir en /g: cola a 1 por segundo
---------------------------------------------------------------------------
-- Freno solo: si el juego se traga una línea mía (no vuelve por mi /g en LOST_SECS) o avisa de que [+ARCHITECTURE.md]
local SLOW_EVERY = 1 / 1.5
local SLOWEST_EVERY = 2
local LOST_SECS = 5
local CALM_SECS = 60
local every, lastTroubleT = ECHO_EVERY, -999
local sentLines = {}                    -- { line, low, t, retry }
local confirmedT = -999                 -- última vez que vi volver una línea mía
-- (se compara el principio de la línea, sin colores: si el juego cambia algo al final, sigue valiendo)
local function Low(s) return Plain(s):lower():sub(1, 60) end

local function Slow(why)
    lastTroubleT = GetTime()
    local was = every
    every = math.min(SLOWEST_EVERY, math.max(SLOW_EVERY, every * 1.5))
    if every ~= was then HU:Debug("Eco más lento (" .. tostring(why) .. "):", string.format("%.2f s", every)) end
end
HU.EchoSlow = Slow

local function Calm()
    if every > ECHO_EVERY and GetTime() - lastTroubleT > CALM_SECS then
        every = math.max(ECHO_EVERY, every * 0.8)
        lastTroubleT = GetTime() - CALM_SECS / 2 -- (el siguiente paso, 30 s después)
    end
end

local function SendGuild(line, retry)
    local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not fn then return end
    -- (OnSend no lo toma como algo que yo he escrito: si no, volvería a las otras hermandades)
    HU.echoSending = true
    pcall(fn, line, "GUILD")
    HU.echoSending = nil
    if #sentLines < 50 then
        sentLines[#sentLines + 1] = { line = line, low = Low(line), t = GetTime(), retry = retry }
    end
end

-- Lo que no ha vuelto por mi /g a tiempo: se ha perdido. Devuelve la línea a repetir (una vez), o nil
local function CheckLost()
    local now, again = GetTime(), nil
    -- (si hace 2 min que no veo volver NINGUNA línea mía, no sé comprobarlo en este juego: no freno
    -- ni repito, para no duplicar todo el eco)
    local canCheck = now - confirmedT < 120
    for i = #sentLines, 1, -1 do
        local s = sentLines[i]
        if now - s.t > LOST_SECS and not canCheck then
            table.remove(sentLines, i)
        elseif now - s.t > LOST_SECS then
            table.remove(sentLines, i)
            Slow("línea perdida")
            -- (solo si es reciente: una línea de hace un rato ya no se repite)
            if not s.retry and not again and now - s.t < LOST_SECS * 3 then again = s.line end
        end
    end
    return again
end

HU:On("CHAT_MSG_GUILD", function(msg, author)
    if #sentLines == 0 or not author or HU:Key(author) ~= HU:MeKey() then return end
    local low = Low(msg)
    for i, s in ipairs(sentLines) do
        if s.low == low then table.remove(sentLines, i); confirmedT = GetTime() return end
    end
end)

-- Avisos del juego de que voy demasiado rápido (si este juego los tiene)
HU:On("CHAT_MSG_SYSTEM", function(msg)
    if type(msg) ~= "string" then return end
    for _, k in ipairs({ "ERR_CHAT_THROTTLED", "ERR_USER_SQUELCHED", "ERR_CHAT_RESTRICTED" }) do
        local s = _G[k]
        if type(s) == "string" and s ~= "" and msg == s then Slow(k) return end
    end
end)

local function Flush()
    timer = false
    -- (si he dejado de ser el enlace, lo que ya tenía en la cola se escribe igual, con la espera
    -- larga: si el nuevo lo escribe antes, lo veo y no se repite; si no, no se pierde. Tras 1 min, fuera)
    local on, handover = false, false
    if EchoCfgOn(HU) then on, handover = EchoRelay(HU) end
    if not on and deputyOn and EchoCfgOn(HU) then on, handover = true, false end
    if not on then
        if not queue[1] or GetTime() - queue[1].t > 60 then queue, dropped = {}, 0 return end
        handover = true
    end
    if HU:IsChatLockedDown() then timer = true; HU.After(2, Flush) return end
    Calm()
    local again = CheckLost()
    if again then
        SendGuild(again, true)
        timer = true
        HU.After(every, Flush)
        return
    end
    local it = queue[1]
    if it then
        local wait = it.t + (it.w or 0) + (handover and HANDOVER_EXTRA or 0) - GetTime()
        if wait > 0 then timer = true; HU.After(wait, Flush) return end
        table.remove(queue, 1)
        SendGuild(it.line)
    elseif dropped > 0 and on then
        SendGuild("[" .. (dropTag or "?") .. "] GuildUnion: " .. string.format(L("(+%d mensajes: míralos en el panel de GuildUnion)"), dropped))
        dropped = 0
    else
        dropped = 0
        return
    end
    timer = true
    HU.After(every, Flush)
end

local function Push(line, key, tag)
    local t = byOthers[key]
    if t and GetTime() - t < 10 then return end -- (ya lo escribió otro compañero)
    for _, it in ipairs(queue) do if it.key == key then return end end
    if #queue >= ECHO_MAX then
        table.remove(queue, 1)
        dropped, dropTag = dropped + 1, tag
    end
    local _, handover = EchoRelay(HU)
    queue[#queue + 1] = { line = line, key = key, t = GetTime(), w = RelayDoubt(HU, handover) and ECHO_WAIT or 0 }
    if not timer then timer = true; HU.After(0, Flush) end
end

-- Lo que llega al /g: solo los códigos de los enlaces (lo demás ya viene con las | dobladas)
local function ForGuild(msg)
    return (tostring(msg or ""):gsub("||", ""))
end

---------------------------------------------------------------------------
-- De las otras hermandades a mi /g
---------------------------------------------------------------------------
-- La llama OnUnionChat justo antes de Display. Cortado por espacios y sin partir los enlaces de
-- objeto (HU.SplitMessage), con «[ETIQ] Nombre-Reino: » en cada trozo
function HU:EchoIncoming(kind, tag, author, msg)
    if kind ~= "main" or not tag or tag == self.myTag or not (self.cfg and self.cfg.echo) then return end
    -- (en el /g, el nombre como se lee: en Forever «Nombre Apellido»; con reino si es de otro)
    local head = "[" .. tag .. "] " .. self:EchoStarName(author, self:Nice(self:FullName(author) or author)) .. ": "
    local on = self:EchoEnabled() or deputyOn
    local deputy = not on and EchoCfgOn(self) and IsDeputy(self)
    if shownN > 400 then shownLines, shownN = Prune(shownLines, 90) end
    for _, part in ipairs(HU.SplitMessage(ForGuild(msg), 255 - #head)) do
        local line = head .. part
        local _, _, _, key = ParseEcho(line)
        if key then
            -- (lo apunto aunque no sea el enlace: si el eco de otro me llega luego al /g, lo escondo)
            shownLines[key], shownN = GetTime(), shownN + 1
            if on then Push(line, key, tag)
            elseif deputy then
                -- (si el enlace ya lo ha escrito, que puede llegar antes que el original, nada que vigilar)
                local b = byOthers[key]
                if not (b and GetTime() - b < 30) then watch[key] = { t = GetTime(), line = line, tag = tag } end
            end
        end
    end
end

-- Un compañero ha escrito una línea de eco en /g: no la repito, y si no la había visto por el canal
-- (no me llegó el original), la pinto una vez con el nombre de verdad
local announcePending = false
function HU:EchoSeen(msg, author)
    local k = author and self:Key(author)
    if IsAnnounce(msg) then
        -- (ya lo ha escrito otro: no lo repito)
        if k and k ~= self:MeKey() then
            announcePending = false
            for i = #queue, 1, -1 do if queue[i].key == "announce" then table.remove(queue, i) end end
        end
        return
    end
    local tag, name, text, key = ParseEcho(msg)
    if not k or not key or k == self:MeKey() then return end
    if byOthersN > 300 then byOthers, byOthersN = Prune(byOthers, 30) end
    byOthers[key], byOthersN = GetTime(), byOthersN + 1
    for i = #queue, 1, -1 do
        if queue[i].key == key then table.remove(queue, i) end
    end
    watch[key] = nil
    local rk = self.RelayName and self:Key(self:RelayName() or "")
    if k == rk then relayEchoT = GetTime(); if deputyOn then deputyOn = false end end
    local t = shownLines[key]
    if (not t or GetTime() - t > 60) and tag ~= self.myTag then
        -- (solo si lo escribe un compañero con el addon: si no, cualquiera de mi hermandad podía
        -- poner frases en boca de alguien de otra)
        local p = self.guildPeers and self.guildPeers[k]
        if p and GetTime() - (p.last or 0) < HU.PEER_TTL and not self:IsMuted(name) then
            -- (el eco va al momento y puede llegarme antes que el original: se espera 3 s y solo se
            -- pinta si el original no ha llegado; si no, salía dos veces. Banco eco-2: 18 %)
            local seenT = GetTime()
            HU.After(3, function()
                local s = shownLines[key]
                if s and s >= seenT - 60 then return end
                shownLines[key] = GetTime()
                local full = HU:FullName(name) or name
                HU:Display("main", tag, full, HU.SafeText(text, true))
                HU:AddHistory("main", tag, full, HU.SafeText(text, true))
            end)
        end
    end
end

---------------------------------------------------------------------------
-- De mi /g (compañeros SIN el addon) a las otras hermandades
---------------------------------------------------------------------------
-- (desde un evento no se puede escribir en el canal: va por el respaldo, CW / CG) [+ARCHITECTURE.md]
local OUT_LIMIT = 195          -- (255 menos lo que añaden CW / CG delante)
local OUT_SEP = "\30"
local outHead, outBuf, outLen, outTimer, outLastT = nil, {}, 0, false, -999
local function OutFlush()
    outTimer = false
    if #outBuf == 0 then return end
    local line = outHead .. table.concat(outBuf, OUT_SEP)
    outBuf, outLen = {}, 0
    outLastT = GetTime()
    HU:ChatFallback("m", line)
end
local function OutAdd(head, entry)
    -- (si no cabe con lo que ya espera, sale lo de antes ahora mismo y esta abre otro paquete)
    if #outBuf > 0 and (head ~= outHead or #head + outLen + #OUT_SEP + #entry > OUT_LIMIT) then OutFlush() end
    outHead = head
    outBuf[#outBuf + 1] = entry
    outLen = outLen + #entry + (#outBuf > 1 and #OUT_SEP or 0)
    if not outTimer then
        outTimer = true
        HU.After(math.max(0, outLastT + 1 - GetTime()), OutFlush)
    end
end

function HU:EchoOutgoing(text, author)
    if type(text) ~= "string" or text == "" or not self:EchoEnabled() then return end
    if HU.Secret and HU.Secret(text) then return end
    local full, k = self:FullName(author), self:Key(author)
    if not full or not k or k == self:MeKey() then return end
    local p = self.guildPeers and self.guildPeers[k]
    if p and GetTime() - (p.last or 0) < HU.PEER_TTL then return end -- (tiene el addon: lo manda él)
    if self:IsMuted(full) then return end
    -- (eco de un eco: si el texto ya tiene forma de eco de otra hermandad, venga de quien venga, no
    -- se reenvía; ni si es algo que ya me llegó de fuera)
    if ParseEcho(text) then return end
    local head = "[" .. self.myTag .. ":E] "
    local who = full .. ": "
    for _, part in ipairs(HU.SplitMessage(text, OUT_LIMIT - #head - #who)) do
        OutAdd(head, who .. part)
    end
end

-- Una línea [ETIQ:E] Autor: msg que llega de otra hermandad. Solo vale si la trae su enlace (o un [+ARCHITECTURE.md]
function HU:EchoUnwrap(tag, carrier, msg)
    local inner, text = tostring(msg or ""):match("^([^:]+): (.*)$")
    if not inner or not text or text == "" or not HU.SafeName(inner) then return nil end
    -- (cita algo de mi propia hermandad o de otra: es eco de un eco, se tira)
    if ParseEcho(text) then return nil end
    local ck = self:Key(carrier)
    -- (vale cualquiera que haya sido su enlace en los últimos 15 min: cuando llega el enlace nuevo
    -- se borra la marca del de antes, y el que vuelve se rechazaba hasta anunciarse; banco eco-2)
    local seen = relaySeen[tag] and relaySeen[tag][ck]
    local ok = seen ~= nil and GetTime() - seen < 900
    local cur = self.KnownRelay and self:KnownRelay(tag)
    if cur and cur.name and self:Key(cur.name) == ck then ok = true end
    if not ok and self.TrustedOfficer and self:TrustedOfficer(carrier, tag) == true then ok = true end
    if not ok and self.AnchorValid and ck and self:AnchorValid(tag, ck) then ok = true end
    -- (lo trae alguien de esa hermandad que no sé si es su enlace: no se tira, por si su enlace es un [+ARCHITECTURE.md]
    local via
    if not ok and ck then
        local vs = viaSeen[tag] or {}
        viaSeen[tag] = vs
        if self:MemberOf(carrier, tag) then vs[ck] = GetTime() end
        if vs[ck] and GetTime() - vs[ck] < 900 then ok, via = true, true end
    end
    if not ok then
        self:Debug("Eco rechazado: no lo trae el enlace de <" .. tag .. ">:", tostring(carrier))
        return nil
    end
    -- (en el traspaso pueden mandarlo los dos enlaces: la misma línea de otro enlace en 20 s no
    -- vale; del mismo sí, alguien puede escribir «ok» dos veces)
    local key, now = (inner .. "\0" .. text):lower(), GetTime()
    local s = unwrapSeen[key]
    if s and now - s.t < 20 and s.c ~= ck then return nil end
    if unwrapN > 500 then unwrapSeen, unwrapN = {}, 0 end
    if not s then unwrapN = unwrapN + 1 end
    unwrapSeen[key] = { t = now, c = ck }
    local full = self:FullName(inner)
    -- (sin confirmar: el nombre sale entre comillas, "Pepe"; quién lo trajo se apunta para /gu eco quién)
    if via and full then
        echoStar[full:lower()] = GetTime()
        echoViaLog[#echoViaLog + 1] = { t = time(), tag = tag, author = full, carrier = self:FullName(carrier) or carrier, text = text }
        while #echoViaLog > 30 do table.remove(echoViaLog, 1) end
    end
    return full, text
end

-- ¿La última línea de eco de este autor llegó sin confirmar? (para ponerle comillas)
function HU:IsEchoStar(author)
    local t = author and echoStar[tostring(author):lower()]
    return t ~= nil and GetTime() - t < 5
end
function HU:EchoStarName(author, name)
    if self:IsEchoStar(author) then return "\"" .. name .. "\"" end
    return name
end

---------------------------------------------------------------------------
-- /gu eco · /gu eco quién · /gu eco on|off (el maestro: la línea GU:e:1 en la Información)
---------------------------------------------------------------------------
function HU:EchoCommand(arg)
    arg = HU.Trim(arg or ""):lower()
    local on = self.cfg and self.cfg.echo
    if arg == "quien" or arg == "quién" or arg == "who" then
        local mine = (self:EchoEnabled() or deputyOn) and self:Me() or self:RelayName()
        self:Print(L("Eco en /g: ") .. (on and L("|cff44ff44encendido|r") or L("|cffff4444apagado|r")))
        self:Print("  <" .. tostring(self.myTag) .. "> " .. tostring(mine and self:Short(mine) or "?") .. (deputyOn and L(" (suplente: el enlace no copiaba)") or ""))
        for _, tag in ipairs(self:OtherTags()) do
            local p = self.KnownRelay and self:KnownRelay(tag)
            self:Print("  <" .. tag .. "> " .. (p and p.name and self:Short(p.name) or "?"))
        end
        -- (las líneas sin confirmar, "Pepe": quién las trajo)
        if #echoViaLog > 0 then
            self:Print(L("Últimas líneas sin confirmar (entre comillas) y quién las trajo:"))
            for i = math.max(1, #echoViaLog - 9), #echoViaLog do
                local e = echoViaLog[i]
                self:Print("  " .. date("%H:%M", e.t) .. " <" .. e.tag .. "> \"" .. self:Nice(e.author) .. "\" ← " .. self:Nice(e.carrier) .. ": " .. HU.Utf8Cut(e.text, 60))
            end
        end
        return
    end
    if arg ~= "on" and arg ~= "off" then
        self:Print(L("Eco en /g: ") .. (on and L("|cff44ff44encendido|r") or L("|cffff4444apagado|r"))
            .. (on and (self:IsRelay() and L(" (lo escribes tú, eres el enlace)") or L(" (lo escribe el enlace: ") .. tostring(self:Short(self:RelayName() or "?")) .. ")") or ""))
        self:Print(L("El maestro lo enciende con |cffffd100/gu eco on|r (pone GU:e:1 en la Información de hermandad) y lo apaga con |cffffd100/gu eco off|r."))
        return
    end
    if not self:IsMaster() then return self:Print(L("Solo el maestro de la hermandad puede encender o apagar el eco.")) end
    local old = self:GuildInfoText()
    if not old then return self:Print(L("Ahora el juego no deja leer la Información de hermandad: inténtalo al terminar el combate o la partida.")) end
    local keep = {}
    for line in (old .. "\n"):gmatch("([^\n]*)\n") do
        if not HU.Trim(line):match("^[Gg][Uu]:[Ee]:") then keep[#keep + 1] = line end
    end
    while #keep > 0 and HU.Trim(keep[#keep]) == "" do table.remove(keep) end
    if arg == "on" then keep[#keep + 1] = "GU:e:1" end
    local text = table.concat(keep, "\n")
    if #text > 500 then return self:Print(L("No cabe en la Información de hermandad (máximo 500 letras): borra parte del texto.")) end
    -- (en Forever el juego no deja al addon escribir la Información: se da entera ya preparada para sustituirla)
    if HU.UI and HU.UI.ShowCopy then
        HU.UI:ShowCopy(L("Información de hermandad (J): borra todo lo que hay y pega esto (Ctrl+V)"), text)
        self:Print(arg == "on" and L("Para encender el eco, sustituye la Información de hermandad por el texto de la ventana.")
            or L("Para apagar el eco, sustituye la Información de hermandad por el texto de la ventana."))
    elseif arg == "on" then
        self:Print(L("Añade esta línea a la Información de hermandad:") .. " |cffffd100GU:e:1|r")
    else
        self:Print(L("Quita esta línea de la Información de hermandad:") .. " |cffffd100GU:e:1|r")
    end
end

---------------------------------------------------------------------------
-- Temporizadores
---------------------------------------------------------------------------
local lastGuild
local function Reset()
    queue, dropped, watch, shownLines, shownN, byOthers, byOthersN = {}, 0, {}, {}, 0, {}, 0
    unwrapSeen, unwrapN, relaySeen, deputyOn, relayEchoT, lastRelayT = {}, 0, {}, false, -999, -999
    viaSeen = {}
end
HU:OnStart(function()
    HU.NewTicker(1, function()
        -- (cambio de hermandad sin /reload: el eco empieza de cero)
        local g = IsInGuild() and GetGuildInfo("player") or nil
        if g ~= lastGuild then
            if lastGuild ~= nil then Reset() end
            lastGuild = g
        end
        -- (¿se acaba de encender de verdad? Se mira con la configuración de verdad, no la del arranque [+ARCHITECTURE.md]
        if g and HU.cfg and not HU.cfg.quick and HU.db then
            HU.db.echoState = HU.db.echoState or {}
            local now = HU.cfg.echo == true and "on" or "off"
            if HU.db.echoState[g] == "off" and now == "on" then announcePending = GetTime() end
            HU.db.echoState[g] = now
        end
        if announcePending and GetTime() - announcePending > 60 then announcePending = false end
        if not EchoCfgOn(HU) then deputyOn = false return end
        -- (lo escribe quien hace de eco, una vez; si otro ya lo ha escrito, EchoSeen lo quita)
        if announcePending and HU:EchoEnabled() then
            announcePending = false
            Push(Announce(), "announce", nil)
        end
        NoteRelayState(HU)
        -- (suplente: el enlace sigue conectado pero no copia nada desde hace SILENT_SECS)
        if HU:EchoEnabled() then deputyOn = false; watch = {} return end
        if not IsDeputy(HU) then deputyOn = false; watch = {} return end
        local now = GetTime()
        for key, w in pairs(watch) do
            if now - w.t > SILENT_SECS then
                if now - relayEchoT > SILENT_SECS then
                    if not deputyOn then HU:Debug("El enlace no copia el eco: lo copio yo") end
                    deputyOn = true
                    Push(w.line, key, w.tag)
                end
                watch[key] = nil
            end
        end
    end)
    -- quién es el enlace de cada otra hermandad, apuntado cada 5 s (para EchoUnwrap) [+ARCHITECTURE.md]
    HU.NewTicker(5, function()
        if not (HU.cfg and HU.myTag and HU.KnownRelay) then return end
        local now = GetTime()
        for _, tag in ipairs(HU:OtherTags()) do
            local p = HU:KnownRelay(tag)
            local k = p and p.name and HU:Key(p.name)
            if k then
                relaySeen[tag] = relaySeen[tag] or {}
                relaySeen[tag][k] = now
            end
        end
    end)
    -- (y quien se presenta como enlace en el canal ([ETIQ:R], hace falta la contraseña) y sale en mi [+ARCHITECTURE.md]
    local origRA = HU.OnRelayAnnounce
    if type(origRA) == "function" then
        HU.OnRelayAnnounce = function(self, author, tag, msg, ...)
            local r = origRA(self, author, tag, msg, ...)
            local k = type(author) == "string" and self:Key(author)
            -- (solo si es oficial o maestro de esa hermandad, o su ancla: «[X:R]» lo puede escribir a mano
            -- cualquiera de X, y con eso colaba «[X:E] Fulano: …» a nombre de otro)
            if k and tag and tag ~= self.myTag and ((self.TrustedOfficer and self:TrustedOfficer(author, tag) == true)
                or (self.AnchorValid and self:AnchorValid(tag, k))) then
                relaySeen[tag] = relaySeen[tag] or {}
                relaySeen[tag][k] = GetTime()
            end
            return r
        end
    end
end)
