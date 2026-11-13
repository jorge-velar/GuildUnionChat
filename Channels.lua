-- Guild Union - canales extra que crean el maestro y los oficiales (además del de hermandad)
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

local MAX_EXTRA = 3
-- Canales del juego: un canal extra con su nombre los escondía del chat
HU.GAME_CHANNELS = { general = true, trade = true, comercio = true, localdefense = true, defensalocal = true,
    lookingforgroup = true, buscargrupo = true, worlddefense = true, defensamundial = true, world = true, mundo = true,
    guildrecruitment = true, reclutamientodehermandad = true, newcomers = true, novatos = true, services = true,
    servicios = true, lfg = true }

local function Clean(s) return (tostring(s or ""):gsub("[~\r\n]", "")) end

function HU:ExtraChannels()
    local out = {}
    for _, x in pairs(self.db.extraChans) do if not x.del then out[#out + 1] = x end end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

local function Msg(x)
    return table.concat({ "CX", x.name, Clean(x.pass), x.del and "1" or "0", x.by or "", x.tag or "", x.t or 0 }, "~")
end

function HU:ShareExtra(x, target)
    local msg = Msg(x)
    if target then return self:Whisper(target, msg) end
    if self.myTag and IsInGuild() then self:Send(msg, "GUILD") end
    for _, tag in ipairs(self:OtherTags()) do
        local peer = self:SafePeer(tag)
        if peer then self:Whisper(peer.name, msg) end
    end
end

-- Devuelve true o false y el motivo
HU.comm.CX = function(self, sender, f, dist, raw)
    local name, pass, del, by, tag, t = f[1], f[2], f[3] == "1", f[4], f[5], HU.NetT(f[6])
    if not name or not name:match("^%w+$") or #name > 25 or not t then return end
    if HU.GAME_CHANNELS[name:lower()] then return end
    if not self:CheckOfficerFirm(by ~= "" and by or sender, tag, function() HU.comm.CX(self, sender, f, dist, raw) end, sender, dist) then return end
    local k = name:lower()
    local cur = self.db.extraChans[k]
    if cur and (cur.t or 0) >= t then return end
    -- (como mucho los que se pueden crear: antes llegaban los que mandara cualquiera)
    if not del and not (cur and not cur.del) and #self:ExtraChannels() >= MAX_EXTRA then return end
    self.db.extraChans[k] = { name = name, pass = (pass ~= "") and pass or nil, del = del or nil, by = by, tag = (tag ~= "" and tag) or nil, t = t }
    if dist == "WHISPER" then self:Send(raw, "GUILD") end
    self:Print((del and L("Canal quitado: ") or L("Nuevo canal: ")) .. name .. " (" .. self:Short(by) .. ")")
    self:ApplyChannels()
    self:Changed("channel")
end

-- quien entra recibe la lista de canales (el enlace la manda junto al mensaje fijado) [+ARCHITECTURE.md]
function HU:MaySendSecrets(who)
    -- (la bienvenida va a toda mi hermandad, HU.BCAST: es de mi hermandad. Antes se buscaba ese nombre
    -- especial entre los conocidos, no se encontraba y se rehacía el mapa de nombres: 5-12 ms cada vez)
    if who == HU.BCAST then return true end
    local k = who and self:Key(who)
    if not k then return false end
    if self.roster[k] then return true end
    local p = self.remote[k]
    return (p and p.tag and self:PeerVerified(who, p.tag)) and true or false
end

local origPQ = HU.comm.PQ
HU.comm.PQ = function(self, sender, ...)
    if origPQ then origPQ(self, sender, ...) end
    if not self:IsRelay() or not self:MaySendSecrets(sender) then return end
    for _, x in pairs(self.db.extraChans) do self:ShareExtra(x, sender) end
end

HU:OnStart(function()
    HU.NewTicker(300, function()
        if not HU.myTag or not HU:IsRelay() then return end
        for _, x in pairs(HU.db.extraChans) do
            for _, tag in ipairs(HU:OtherTags()) do
                local peer = HU:SafePeer(tag)
                if peer then HU:ShareExtra(x, peer.name) end
            end
        end
    end)
end)

---------------------------------------------------------------------------
-- Canal y contraseña desde la nota de oficial [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local function CPMsg(n) return table.concat({ "CP", n.channel, n.pass or "", n.t or 0, n.by or "", n.tag or "" }, "~") end

function HU:ShareNetChan(target)
    local n = self.db.netChan
    if not n or n.prov then return end -- (uno provisional no se reparte)
    if target then return self:Whisper(target, CPMsg(n)) end
    if self.myTag and IsInGuild() then self:Send(CPMsg(n), "GUILD") end
    for _, tag in ipairs(self:OtherTags()) do
        local peer = self:SafePeer(tag)
        if peer then self:Whisper(peer.name, CPMsg(n)) end
    end
end

-- /gu pasarcanal Nombre: cualquiera con el canal bueno se lo manda a uno que lo espera, por mensaje
-- oculto (la contraseña no se escribe ni se ve). Solo a alguien de mi hermandad o de las listas de la
-- comunidad. Quien lo recibe lo usa como provisional (no lo reparte ni pisa uno bueno); si alguien se
-- cuela con él, la guardia lo echa (Jorge, 10/11)
function HU:PassChannelTo(name)
    local n = self.db.netChan
    if not n or n.prov then return self:Print(L("No tienes el canal (o es provisional): no lo puedes pasar.")) end
    name = HU.Trim(name or "")
    if name == "" then return self:Print(L("Uso: /gu pasarcanal Nombre del jugador")) end
    local full = self:FullName(name)
    local k = full and self:Key(full)
    if not k then return self:Print(L("No encuentro a ese jugador.")) end
    if k == self:MeKey() then return end
    local where
    if self.roster and self.roster[k] then where = self.myTag
    else
        for _, tag in ipairs(self:OtherTags()) do
            if self:MemberOf(full, tag) then where = tag; break end
        end
    end
    if not where then
        return self:Print(string.format(L("%s no está en tu hermandad ni en las listas de la comunidad: no se le pasa el canal."), self:Short(full)))
    end
    self:Whisper(full, table.concat({ "CK", n.channel, n.pass or "", n.t or 0, n.by or "", n.tag or "" }, "~"))
    self:Print(string.format(L("Canal pasado a %s (por mensaje oculto). Le llega si está conectado."), self:Short(full)))
end

-- Si soy el propietario del canal y la contraseña ha cambiado, la cambio en el canal
local function ApplyChannelPassword(n)
    local c = HU.chan.main
    if not c or not c.name or not n or c.name:lower() ~= (HU:LaneName(n.channel) or n.channel):lower() then return end
    local members = HU:GetChannelMembers("main")
    if not members then return end
    local me = HU:MeKey()
    for _, m in ipairs(members) do
        if m.name:lower() == me and m.owner then
            local fn = SetChannelPassword or (C_ChatInfo and C_ChatInfo.SetChannelPassword)
            if fn then
                pcall(fn, c.name, n.pass or "")
                HU:Print(L("Contraseña del canal cambiada (eres su propietario)."))
            end
            return
        end
    end
end

local function Adopt(self, n)
    local old = self.db.netChan
    self.db.netChan = n
    self:RefreshConfig(true)
    if old and old.channel:lower() == n.channel:lower() and old.pass ~= n.pass then
        HU.After(1, function() ApplyChannelPassword(n) end)
    end
    self:Changed("config")
end

-- Me pasan el canal a mano (/gu pasarcanal): solo si no tengo uno bueno, y como provisional (el de mi
-- hermandad lo sustituye)
HU.comm.CK = function(self, sender, f, dist)
    if dist ~= "WHISPER" then return end
    local cur = self.db.netChan
    if cur and not cur.prov then return end
    local channel, pass, t = f[1], f[2], HU.NetStamp(f[3])
    if not channel or not channel:match("^%w+$") or #channel > 31 or not t then return end
    if cur and (cur.t or 0) >= t then return end
    Adopt(self, { channel = channel, pass = (pass ~= "" and pass) or nil, t = t, by = f[4] ~= "" and f[4] or nil,
        tag = (f[5] ~= "" and f[5]) or nil, prov = true })
    self:Print(string.format(L("%s te ha pasado el canal de la comunidad (provisional hasta que lo confirme tu hermandad)."), self:Short(sender)))
end

-- Lo llama la lista de la hermandad cuando un oficial ve la línea en una nota de oficial
function HU:OnChannelNote(channel, pass)
    if self:IsTest() or not self.myTag then return end
    local n = self.db.netChan
    if n and n.channel == channel and (n.pass or nil) == (pass or nil) then return end
    -- Solo cuenta como cambio si la nota cambia después de haberla visto. La primera vez que un
    -- oficial la ve (addon recién instalado) no pisa lo que ya repartió otra hermandad.
    local seen = self.db.noteChanSeen
    if seen and seen.channel == channel and (seen.pass or nil) == (pass or nil) then return end
    self.db.noteChanSeen = { channel = channel, pass = pass }
    if not seen and n then return end
    local new = { channel = channel, pass = pass, t = math.max(HU.StampNow(), (n and n.t or 0) + 1), by = self:Me(), tag = self.myTag }
    Adopt(self, new)
    self:ShareNetChan()
    self:AddAudit({ tag = self.myTag, actor = self:Me(), text = L("cambió el canal o la contraseña del chat (") .. channel .. ")" }, "all")
end

-- Ningún oficial tiene ya la línea GU:c en su nota (EPGP, CEPGP, DKP o Guild Roster Manager [+ARCHITECTURE.md]
local noteMissT, noteMissWarned
-- (bad: la línea está, pero con algo pegado detrás que no cuadra; tampoco se usa ni se reparte)
function HU:OnChannelNoteMissing(bad)
    if self:IsTest() or not self.myTag or noteMissWarned then return end
    local n = self.db.netChan
    -- (solo si en esta hermandad la línea estuvo: si el canal llegó de otra, aquí no falta nada)
    if not n or n.prov or not self.db.noteChanSeen then return end
    local now = GetTime()
    if not noteMissT then noteMissT = now return end
    if now - noteMissT < 60 then return end
    noteMissWarned = true
    -- (la contraseña no sale en el chat, que se ve en directo o en capturas: va en /gu notacanal)
    if bad then
        self:Print(L("|cffff8800La línea de GuildUnion de la nota de oficial no se puede leer: otro addon ha escrito pegado a ella (¿EPGP, CEPGP o Guild Roster Manager?).|r No se usa; seguís conectados con la última configuración. Para arreglarla: |cffffd100/gu notacanal|r te enseña la línea buena; ponla sola en la nota de oficial del maestro (o de un oficial)."))
    else
        self:Print(L("|cffff8800La línea de GuildUnion de la nota de oficial ha desaparecido (¿EPGP, CEPGP o Guild Roster Manager?).|r Seguís conectados con la última configuración. Para ponerla otra vez: |cffffd100/gu notacanal|r te enseña la línea; cópiala en la nota de oficial del maestro (o de un oficial)."))
    end
    self:Print(L("Si ese addon usa todas las notas de oficial, ponla en la de un personaje que no use (un alter del maestro, por ejemplo)."))
end

-- La línea GU:c con el canal y la contraseña guardados, para pegarla a mano en una nota de oficial
function HU:ShowChannelNoteLine()
    if not self:CanOfficer() then return self:Print(L("Solo para quien puede ver las notas de oficial.")) end
    local n = self.db.netChan
    if not n or not n.channel then return self:Print(L("No hay canal guardado todavía.")) end
    local line = "GU:c:" .. n.channel .. (n.pass and (":" .. n.pass) or "")
    if HU.UI and HU.UI.ShowCopy then
        HU.UI:ShowCopy(L("Copia esto (Ctrl+C) en la nota de oficial del maestro"), line)
    else
        self:Print("|cffffd100" .. line .. "|r")
    end
end

local origOnChannelNote = HU.OnChannelNote
function HU:OnChannelNote(...)
    noteMissT = nil
    return origOnChannelNote(self, ...)
end

-- Respuestas a mi CQ de compañeros que no son oficial, enlace ni ayudante: cualquiera podía mandarme [+ARCHITECTURE.md]
local cqVotes = {} -- [canal~clave~t] = { [compañero] = true }
local CQ_FALLBACK = 20
local function CQVote(self, sender, n)
    if not self.db.netChan or self.db.netChan.prov then
        local key = table.concat({ n.channel:lower(), n.pass or "", n.t }, "~")
        local v = cqVotes[key] or {}
        cqVotes[key] = v
        v[sender:lower()] = true
        local count, kinds = 0, 0
        for _ in pairs(v) do count = count + 1 end
        for _ in pairs(cqVotes) do kinds = kinds + 1 end
        if count >= 2 then
            cqVotes = {}
            n.prov = nil
            return Adopt(self, n)
        end
        if count == 1 and kinds == 1 then
            HU.After(CQ_FALLBACK, function()
                local only = next(cqVotes)
                if only == key and next(cqVotes, only) == nil and (not HU.db.netChan or HU.db.netChan.prov) then
                    cqVotes = {}
                    n.prov = true
                    Adopt(HU, n)
                end
            end)
        end
    end
end

-- Canal de otra hermandad cuya lista aún no está confirmada: antes esperaba 15 min y se perdía (la [+ARCHITECTURE.md]
local pendingCP, pendingN = {}, 0
local PENDING_MAX, PENDING_TTL, CONFIRM_EVERY = 40, 86400, 120
local confirmAsked = {}
local CPCore

local function AskConfirm(self, tag)
    if not self.myTag or (confirmAsked[tag] and GetTime() - confirmAsked[tag] < CONFIRM_EVERY) then return end
    local r = self.remoteRoster[tag]
    local origin = r and r.origin and self:Key(r.origin)
    local pick, pickChecked
    for _, key in ipairs(self:RemoteKeys(tag)) do
        local p = self.remote[key]
        if p and p.tag == tag and key ~= origin and GetTime() - (p.last or 0) < 900 then
            local checked = self:CheckedOf(p.name, tag)
            if not pick or (checked and not pickChecked) then pick, pickChecked = p.name, checked end
        end
    end
    if not pick then return end
    confirmAsked[tag] = GetTime()
    self:Whisper(pick, "RF~" .. self.myTag .. "~2", true)
end

local function KeepPendingCP(self, sender, f, dist, raw, carrier, author, tag, t)
    local k = self:Key(author)
    if not k or not self:MayCarry(author, carrier, dist, tag) then return end
    local aTag = self:RankInfoOf(author) or ((tag ~= "") and tag) or nil
    if not aTag or aTag == self.myTag or not self:MemberOf(author, aTag) then return end
    local n = self.db.netChan
    if n and not n.prov and (n.t or 0) >= t then return end
    local cur = pendingCP[k]
    if cur and cur.t >= t then return end
    if not cur then
        if pendingN >= PENDING_MAX then return end
        pendingN = pendingN + 1
    end
    pendingCP[k] = { sender = sender, f = f, dist = dist, raw = raw, t = t, at = GetTime() }
    AskConfirm(self, aTag)
end

local function RetryPendingCP(self)
    if pendingN == 0 then return end
    for k, p in pairs(pendingCP) do
        local n = self.db.netChan
        if (n and not n.prov and (n.t or 0) >= p.t) or GetTime() - p.at > PENDING_TTL then
            pendingCP[k] = nil; pendingN = pendingN - 1
        else
            CPCore(self, p.sender, p.f, p.dist, p.raw, true)
        end
    end
end

HU:OnStart(function()
    local orig = HU.RetryDeferred
    if not orig then return end
    HU.RetryDeferred = function(self, ...)
        orig(self, ...)
        RetryPendingCP(self)
    end
end)

CPCore = function(self, sender, f, dist, raw, fromPending)
    local channel, pass, t, by, tag = f[1], f[2], HU.NetStamp(f[3]), f[4], f[5]
    if not channel or not channel:match("^%w+$") or not t then return end
    -- (de un compañero de mi hermandad por susurro: es la respuesta a mi CQ al entrar. Solo vale [+ARCHITECTURE.md]
    local carrier = sender
    local viaCQ = false
    if dist == "WHISPER" and self.myTag and self:MemberOf(sender, self.myTag) then
        if self:IsGuildForwarder(sender) then carrier = nil
        elseif HU.cqAskedT and GetTime() - HU.cqAskedT < 60 then carrier, viaCQ = nil, true end
    end
    local author = (by and by ~= "") and by or sender
    local retry = not fromPending and function() HU.comm.CP(self, sender, f, dist, raw) end or nil
    if not self:CheckOfficerFirm(author, tag, retry, carrier, dist) then
        if not viaCQ then KeepPendingCP(self, sender, f, dist, raw, carrier, author, tag or "", t) end
        return
    end
    local cur = self.db.netChan
    if viaCQ and not self:IsTest() then
        if cur and not cur.prov then return end
        return CQVote(self, sender, { channel = channel, pass = (pass ~= "") and pass or nil, t = t, by = by, tag = (tag ~= "" and tag) or nil })
    end
    if cur and (cur.t or 0) >= t and not cur.prov then return end
    Adopt(self, { channel = channel, pass = (pass ~= "") and pass or nil, t = t, by = by, tag = (tag ~= "" and tag) or nil })
    if dist == "WHISPER" then self:Send(raw, "GUILD") end
end
HU.comm.CP = function(self, sender, f, dist, raw) return CPCore(self, sender, f, dist, raw) end

-- Al entrar, quien no tenga el canal lo pide (contesta el primero conectado que lo tenga)
HU.comm.CQ = function(self, sender, f, dist)
    -- (con un canal provisional no se contesta: contaría como un segundo voto para el siguiente)
    if dist ~= "GUILD" or not self.db.netChan or self.db.netChan.prov then return end
    -- en hermandades grandes contestan solo unos pocos (al azar), no todos
    if math.random() > math.min(1, 8 / math.max(1, self:PeerCount())) then return end
    HU.After(math.random() * 3, function()
        if HU.cpAnswered and GetTime() - HU.cpAnswered < 5 then return end
        HU:ShareNetChan(sender)
    end)
end

local origCP = HU.comm.CP
HU.comm.CP = function(self, sender, f, dist, raw)
    self.cpAnswered = GetTime()
    return origCP(self, sender, f, dist, raw)
end

local origPQ3 = HU.comm.PQ
HU.comm.PQ = function(self, sender, ...)
    if origPQ3 then origPQ3(self, sender, ...) end
    if self:IsRelay() and self.db.netChan and self:MaySendSecrets(sender) then self:ShareNetChan(sender) end
end

HU:OnStart(function()
    HU.StampFix(HU.db.netChan)
    for _, s in ipairs({ 11, 25 }) do
        HU.After(s, function()
            if HU.myTag and IsInGuild() and not HU.db.netChan then HU.cqAskedT = GetTime(); HU:Send("CQ", "GUILD") end
        end)
    end
    -- (sin canal, o con uno provisional: se sigue pidiendo cada minuto, así llega en cuanto se conecte
    -- alguien de la hermandad que lo tenga, sin /reload)
    HU.NewTicker(60, function()
        local n = HU.db.netChan
        if not (HU.myTag and IsInGuild()) or (n and not n.prov) then return end
        HU.cqAskedT = GetTime(); HU:Send("CQ", "GUILD")
    end)
    -- el enlace lo pasa a las otras hermandades de vez en cuando
    HU.NewTicker(300, function()
        if HU.myTag and HU:IsRelay() and HU.db.netChan then
            for _, tag in ipairs(HU:OtherTags()) do
                local peer = HU:SafePeer(tag)
                if peer then HU:ShareNetChan(peer.name) end
            end
        end
    end)
end)
