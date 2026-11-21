-- Guild Union - Confianza en las listas de otras hermandades: estados, anclas y contactos comprobados (antes en Comm.lua)
local _, HU = ...

-- Quién puede mandarme la lista de conectados de otra hermandad, y cuánto me fío de ella. [+ARCHITECTURE.md]
local VOUCH_TTL = 900       -- lo que dura el aviso de un enlace comprobado (o de mi hermandad)
HU.VOUCH_TTL = VOUCH_TTL     -- (también lo usa Net/Relay.lua)
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
    HU:Every(10, "anclas", function() HU:SafeCall("ancla", function() AskAnchors(HU) end) end)
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
    -- (copia 118: ya no sale en el chat de los oficiales; «son mensajes que sobran», Jorge 15/11)
    self:Debug("Lista de", tag, "en disputa:", tostring(a), "/", tostring(b))
end

-- Reparte a mi hermandad mi copia con su estado nuevo (solo quien se encarga de esa hermandad)
local function Reshare(self, tag)
    if self:IsRelay() or self:HandlesTag(tag) or (self.ResponsibleFor and self:ResponsibleFor(tag)) then
        self:SendStoredRoster(tag, true)
    end
end
HU.ReshareRoster = Reshare -- (también lo usa Net/RosterSync.lua)

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
    local good = rr and not rr.boot and not rr.weak
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
                if k and byKey then member = byKey[k] ~= nil and not byKey[k].weak
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

-- (copia 114) Los n mejores contactos de esa hermandad para el chat del respaldo. Como BestPeer (el
-- enlace primero, luego el oído más recientemente; quien no es de fiar, detrás de todos), pero
-- devuelve varios y pone delante a quien tiene una versión que ya no tira el respaldo de un
-- desconocido (5.4.33 o posterior: la versión de cada contacto viene en su saludo). Se recuerda 5 s
-- por hermandad: con miles de contactos, recorrerlos en cada línea se notaba.
local bpsMemo = {}
function HU:BestPeers(tag, n)
    local now = GetTime()
    local m = bpsMemo[tag]
    if m and now - m.t < 5 and m.n == n then
        local ok = true
        for _, p in ipairs(m.list) do if self.remote[p.name:lower()] ~= p then ok = false break end end
        if ok then return m.list end
    end
    local cands = {}
    for _, key in ipairs(self:RemoteKeys(tag)) do
        local p = self.remote[key]
        local age = p and now - (p.last or 0)
        if p and p.tag == tag and p.name and age < 900 then
            local score = (p.relay and 1000 or 0) - age / 10
            if type(p.ver) == "string" and p.ver:match("^[%d%.]+$") and not HU.VersionGreater("5.4.33", p.ver) then score = score + 2000 end
            -- (copia 151: y antes que nadie, los de la 5.4.40, que reparten aunque ya lo hayan leído)
            if type(p.ver) == "string" and p.ver:match("^[%d%.]+$") and not HU.VersionGreater("5.4.40", p.ver) then score = score + 1500 end
            if not self:MemberOf(p.name, tag) and not self:PeerVerified(p.name, tag) then score = score - 5000 end
            cands[#cands + 1] = { p = p, s = score }
        end
    end
    table.sort(cands, function(x, y) return x.s > y.s end)
    local list = {}
    for i = 1, math.min(n or 1, #cands) do list[i] = cands[i].p end
    bpsMemo[tag] = { t = now, n = n, list = list }
    return list
end
