-- Guild Union - Seguridad y recepción de los mensajes del addon (antes en Comm.lua)
local _, HU = ...
local perf = HU.netPerf -- (Comm.lua)
local NO_SPEC = {}

---------------------------------------------------------------------------
-- Seguridad de los mensajes del addon [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- Las marcas de seguridad de cada orden las declara su HU:RegisterMessage (Protocol.lua): [+ARCHITECTURE.md]
--   tagField   : en qué campo va la etiqueta de la hermandad de la que habla el mensaje
--   bootstrap  : con la etiqueta de otra hermandad, vale de quien es de la comunidad (saludos y
--                listas para arrancar); sin avalar, se retiene (Hold)
--   open       : invitaciones de hermandades nuevas: llegan de gente que aún no está en las listas
--                (cada mensaje comprueba por su cuenta que viene de quien toca)
--   channel    : puede llegar por el canal oculto (solo la presentación del enlace y la sonda del carril)
--   remoteData : datos de OTRA hermandad que llegan por la mía: solo los reparten el enlace, sus
--                ayudantes o un oficial

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
    -- (copia 117: me ha llegado algo por el canal, de quien sea: el canal no está muerto; ver
    -- ChannelSendResult en Channel.lua)
    HU.chanInT = GetTime()
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
    if self:ChannelHas(sender) == true then return true end
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
    local spec = self.msgs[cmd] or NO_SPEC
    if dist == "GUILD" then
        if spec.remoteData then
            local tag = f[spec.tagField]
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
        return spec.channel == true and self:OurChannelKind(localID, chanName) ~= nil
    end
    if dist ~= "WHISPER" then return false end
    if spec.open then return true end
    -- (el chat por el respaldo: de quien es de la comunidad o ha pasado por el canal; el resto lo
    -- mira HU.comm.CW, en Channel.lua)
    if cmd == "CW" then return self:InAnyGuild(sender) or self:Vouched(sender) end
    local tag = spec.tagField and f[spec.tagField]
    if tag and tag ~= "" then
        -- nadie de fuera puede mandar datos de mi propia hermandad
        if tag == self.myTag then return false end
        -- Lista de conectados de otra hermandad sin su lista completa (fase de lanzamiento): antes [+ARCHITECTURE.md]
        -- (las listas completas, WL/WH/WD/WQ, ya no existen desde ReduceClean: siempre es este caso)
        if cmd == "RB" or cmd == "RC" then
            if not (self.cfg and self.cfg.byTag[tag]) then return false end
            local kind = self:SenderKind(sender, tag)
            if not kind then return false end
            if kind == "boot" and self:RosterTrusted(tag) then return false end
            local ak = self.acceptKind[tag] or {}
            self.acceptKind[tag] = ak
            ak[self:Key(sender)] = kind
            return true
        end
        -- lo demás con la etiqueta de otra hermandad: solo saludos y listas para arrancar, y solo de
        -- quien es de la comunidad
        return spec.bootstrap and self.cfg and self.cfg.byTag[tag] ~= nil and self:Vouched(sender, tag) or false
    end
    if self:InAnyGuild(sender) then return true end
    -- (que me presenten contactos de las otras hermandades: PL, de quien es de la comunidad)
    return cmd == "PL" and #self:OtherTags() > 0 and self:Vouched(sender)
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
        elseif (not who or e.sender:lower() == who) and (self:Vouched(e.sender) or (e.chat and self:InAnyGuild(e.sender))) then
            if e.chat then HU.diagChat.heldOK = HU.diagChat.heldOK + 1 end
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
    -- (el chat del respaldo, CW: cada línea es un mensaje distinto)
    if cmd == "CW" then key = key .. "|" .. text end
    if not held[key] then
        if heldN >= 100 then
            if cmd == "CW" then HU.ChatDrop("respaldo: demasiados mensajes retenidos a la vez", sender) end
            return
        end
        heldN = heldN + 1
    end
    held[key] = { sender = sender, text = text, prefix = prefix, t = GetTime(), chat = (cmd == "CW") or nil }
end

-- Chat por el respaldo (CW) de alguien que aún no reconozco como de la comunidad: antes se tiraba, y
-- con él lo perdía toda mi hermandad si yo era su contacto (visto en el juego el 15/11). Ahora se
-- retiene (Hold, hasta 180 s) y se comprueba por dos vías; con la primera que lo confirme, se enseña:
-- (a) que esté en el canal, donde solo entra quien tiene la contraseña (lectura a trozos, como mucho
-- cada 20 s); (b) preguntando a su hermandad si es suyo (la guardia: MQ / MA). [+ARCHITECTURE.md]
local verifyReadT = -999
function HU:VerifyChatSender(sender, f)
    local k = sender:lower()
    if self.GetChannelMembersAsync and self:IsJoined("main") and GetTime() - verifyReadT > 20 then
        verifyReadT = GetTime()
        self:GetChannelMembersAsync("main", function() HU:ReplayHeld() end)
    end
    local tag = table.concat(f, "~", 3):match("^%[(%w+)")
    if tag and tag ~= self.myTag and self.cfg and self.cfg.byTag[tag] and self.GuardAsk then
        self:GuardAsk({ [k] = sender }, { tag })
    end
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
    if HU:FullPeer(sender, tag) then return true end
    if HU:CheckedOf(sender, tag) then return true end
    local rp = HU:KnownRelay(tag)
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
    local spec = HU.msgs[cmd] or NO_SPEC
    local f = HU.Split(rest, "~")
    if spec.meta then setmetatable(f, spec.meta) end
    local allowed, weak = HU:AllowAddonMessage(cmd, sender, f, dist, localID, chanName)
    if not allowed then
        -- (para el chat del respaldo se dice si era eco o un mensaje de verdad: Jorge, 15/11)
        local eco = cmd == "CW" and table.concat(f, "~", 3):match("^%[%w+:E%] ") ~= nil
        if cmd == "CW" and not eco and dist == "WHISPER" then
            -- (no es un rechazo: se retiene y se comprueba; ver VerifyChatSender)
            HU:Debug("Chat del respaldo de alguien que aún no reconozco: se retiene y se comprueba. De", sender)
        else
            HU:Debug("Mensaje rechazado (seguridad):", eco and "CW (eco de versión vieja)" or cmd, "de", sender)
        end
        -- (arranque de alguien aún sin avalar: se guarda por si lo avalan enseguida)
        if dist == "WHISPER" and spec.bootstrap then
            Hold(prefix, text, sender, cmd)
            -- (si leo la lista del canal, se mira ya si está en él, en vez de esperar a mi saludo de cada
            -- 2-5 min: si está, queda «visto en el canal» y lo retenido se aplica; ver StoreChannelMembers)
            HU:CheckChannelSoon()
        elseif dist == "WHISPER" and cmd == "CW" and not HU.replaying then
            -- (un paquete de eco de una versión vieja, «[ETIQ:E] …»: se descartaría de todos modos. Se
            -- cuenta aparte para no confundirlo con un mensaje perdido, y no se retiene ni se comprueba)
            if table.concat(f, "~", 3):match("^%[%w+:E%] ") then
                HU.ChatDrop("eco de una versión vieja (no es un mensaje perdido)", sender)
            else
                HU.diagChat.held = HU.diagChat.held + 1
                Hold(prefix, text, sender, cmd)
                HU:VerifyChatSender(sender, f)
            end
        end
        return
    end
    HU.weakMsg = weak or nil -- (se pone en cada mensaje: nunca se queda de otro)
    if dist == "CHANNEL" then HU:MarkChannelSeen(sender) end
    HU.curCmd = cmd -- (para los avisos de depuración: qué orden se estaba tratando)
    -- (lo que en combate se guarda para después: Combat.lua)
    if spec.combat and HU.CombatDispatch then HU.CombatDispatch(h, cmd, sender, f, dist, text)
    else h(HU, sender, f, dist, text) end
    HU.curCmd = nil
end
HU:On("CHAT_MSG_ADDON", HU.OnAddonMessage)

HU:Module("Net/Security", { "Channel", "Combat", "Config", "Core", "Domain/Trust", "Guard", "Lists", "Net/Relay", "Roster" })
