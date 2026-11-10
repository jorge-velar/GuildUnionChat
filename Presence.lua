-- Guild Union - conectados al momento: quien entra o sale del juego aparece así en las listas de las
-- otras hermandades (GM, oficiales, enlace y ayudantes: en menos de un segundo, como el chat)
local _, HU = ...

local FAST_WAIT = 0.3  -- conectado/desconectado de los que se comparten: los de ~0,3 s van juntos, un mensaje por hermandad
local WAIT = 3         -- el resto de cambios (fuera de la fase de lanzamiento) se juntan unos segundos
local BUSY_WAIT = 15   -- y con la cola cargada, más
local BUSY_QUEUE = 20
local FAST_ROSTER = 15 -- quien reparte la lista la refresca más a menudo (por si los avisos están apagados)
local FULL_GAP = 10    -- quien acaba de encargarse de una hermandad le manda la lista entera, como mucho cada 10 s

-- avisos del juego para la hermandad: "Fulano se ha conectado" / "Fulano se ha desconectado"
local pats
local function Patterns()
    if pats then return pats end
    pats = {}
    for key, on in pairs({ ERR_FRIEND_ONLINE_SS = true, ERR_FRIEND_OFFLINE_S = false }) do
        local fmt = _G[key]
        if type(fmt) == "string" then
            local tmp = fmt:gsub("%%%d?%$?s", "\001")
            tmp = tmp:gsub("([%(%)%.%-%+%*%?%[%]%^%$|])", "%%%1")
            pats[#pats + 1] = { pat = "^" .. tmp:gsub("\001", "(.-)") .. "$", on = on }
        end
    end
    return pats
end
HU.PresencePatterns = Patterns

local fullSent = {} -- [etiqueta] = cuándo mandé la lista entera desde aquí
-- los que se comparten y acaban de entrar o salir: [nombre corto] = { on, sig, t, sent = {[etiqueta] = true} }
local recent = {}
local RECENT_FOR = 15
local function NoteRecent(e, on)
    local c = e and e._re
    local short = (c and c.short) or (e and HU:Short(e.name or "")) or ""
    if short ~= "" then recent[short] = { on = on, sig = c and c.sig, t = GetTime(), sent = {} } end
end

-- Solo «ha entrado X» / «se ha ido X», enseguida y sin saber qué copia tiene esa hermandad (los cambios [+ARCHITECTURE.md]
local function SendRecent(self, p, tag, fast)
    local now, sig = GetTime(), self.RosterSigNow and self.RosterSigNow()
    if not sig then return false end
    local pseudo, any = { sig = {}, hash = "0" }, false
    for n, sg in pairs(sig) do pseudo.sig[n] = sg end
    for n, g in pairs(recent) do
        if now - g.t > RECENT_FOR then recent[n] = nil
        elseif not g.sent[tag] then
            if g.on and sig[n] then pseudo.sig[n], g.sent[tag], any = nil, true, true
            elseif not g.on and not sig[n] and g.sig then pseudo.sig[n], g.sent[tag], any = g.sig, true, true end
        end
    end
    if any then self:SendRosterDelta(p.name, pseudo, fast) end
    return any
end

-- ¿Soy el suplente de quien lleva esta hermandad? (el del puesto anterior al mío; el primer ayudante lo es [+ARCHITECTURE.md]
local function BacksTag(self, tag)
    local slot, n = self:RosterSlot()
    if not slot or not n or n == 0 then return false end
    local tags = self:OtherTags()
    table.sort(tags)
    for j, t in ipairs(tags) do
        if t == tag then return ((j - 1) % (n + 1)) == ((slot - 1) % (n + 1)) end
    end
    return false
end

-- (una hermandad por fotograma: con varias, mandar los cambios a todas seguido pasaba de 6 ms)
-- (y empezando cada vez por una al azar: por orden alfabético, las últimas esperaban siempre)
function HU:PresenceFlush(fast)
    if not self.myTag or not self:IsJoined("main") or not self:RosterSlot() then return end
    -- (primero las líneas de mi lista, en este fotograma; los cambios para cada hermandad, en los siguientes)
    if self.WarmRosterEntries then self:WarmRosterEntries() end
    local launch = self:LaunchPhase()
    local all = self:OtherTags()
    local start, n = math.random(math.max(1, #all)), 0
    for i = 1, #all do
        local tag = all[((start + i - 2) % #all) + 1]
        if self:HandlesTag(tag) or (fast and launch and BacksTag(self, tag)) then
            n = n + 1
            HU.After(0.02 * n, function() HU:PresenceFlushTag(tag, fast) end)
        end
    end
end
function HU:PresenceFlushTag(tag, fast)
    if not self.myTag or not self:IsJoined("main") or not self:RosterSlot() then return end
    local launch = self:LaunchPhase()
    if not self:HandlesTag(tag) then
        -- (suplente: solo los cambios pequeños, ya)
        if fast and launch and BacksTag(self, tag) then
            local p = self:BestPeer(tag)
            if p then SendRecent(self, p, tag, true) end
        end
        return
    end
    local p = self:BestPeer(tag)
    local st = self.RosterStateFor and self.RosterStateFor(tag)
    if p and st then
        -- (si son muchos cambios, la lista entera)
        if not self:SendRosterDelta(p.name, st, fast) then
            p.sentRoster = GetTime()
            self:SendRosterTo(p.name, fast)
        end
    elseif p and launch and (not fullSent[tag] or GetTime() - fullSent[tag] > FULL_GAP) then
        -- (me acaba de tocar esta hermandad, porque se ha ido quien la llevaba: no sé qué lista tienen. [+ARCHITECTURE.md]
        fullSent[tag] = GetTime()
        p.sentRoster = GetTime()
        local hasRecent = false
        for _, g in pairs(recent) do if not g.sent[tag] and GetTime() - g.t <= RECENT_FOR then hasRecent = true break end end
        self:SendRosterTo(p.name, (not (fast and hasRecent)) and fast or nil)
        if fast then SendRecent(self, p, tag, true) end
    end
end

-- fast: cambio de alguien que se comparte (GM, oficial, enlace, ayudante): sale ya, por delante
local scheduled, scheduledFast = false, false
function HU:PresenceSchedule(fast)
    if not self:RosterSlot() then return end
    fast = fast or self:LaunchPhase()
    -- (modo sencillo: todo por la vuelta normal, cada pocos segundos)
    if self:SimpleMode() then fast = false end
    if fast then
        if scheduledFast then return end
        scheduledFast = true
        HU.After(FAST_WAIT, function() scheduledFast = false; HU:PresenceFlush(true) end)
        return
    end
    if scheduled then return end
    scheduled = true
    local wait = (self:MainQueueSize() > BUSY_QUEUE) and BUSY_WAIT or WAIT
    HU.After(wait, function() scheduled = false; HU:PresenceFlush() end)
end

-- ¿Es el enlace o uno de sus ayudantes? (si se va, otro tiene que encargarse ya)
local function InRelayGroup(self, k)
    local h = self.relayHelpers
    if h then
        if h.relay and self:Key(h.relay) == k then return true end
        for _, n in ipairs(h.list or {}) do if self:Key(n) == k then return true end end
    end
    for _, n in ipairs(self.advertisedHelpers or {}) do if self:Key(n) == k then return true end end
    return false
end

---------------------------------------------------------------------------
-- Favoritos: si cambia uno, el panel se redibuja ya (sin esperar al repintado de cada 1-3 s)
---------------------------------------------------------------------------
local nowDue = false
local function FavNow()
    local UI = HU.UI
    if nowDue or not (UI and UI.frame and UI.frame:IsShown() and (UI.tab == 1 or UI.tab == 2)) then return end
    nowDue = true
    HU.After(0, function()
        nowDue = false
        if UI.MarkDirty then UI:MarkDirty("members") end
        if UI.Refresh then UI:Refresh() end
    end)
end
local function IsFav(name)
    local f = HU.db and HU.db.favorites
    local k = f and name and HU:Key(name)
    return k and f[k] and true or false
end
-- (los cambios que llegan de otras hermandades: si toca a un favorito, al momento)
HU:OnStart(function()
    local orig = HU.ApplyRosterDelta
    if not orig or HU.presenceWrapped then return end
    HU.presenceWrapped = true
    HU.ApplyRosterDelta = function(self, r, tag, parts, nparts, st)
        local added = orig(self, r, tag, parts, nparts, st)
        if HU.db and HU.db.favorites and next(HU.db.favorites) then
            for i = 1, nparts or 0 do
                for en in (parts[i] or ""):gmatch("[^;]+") do
                    local n = en:match("^[%+%-]([^,]+)")
                    if n and IsFav(n) then FavNow() break end
                end
            end
        end
        return added
    end
end)

-- el aviso del juego: se cambia al momento en mi lista (sin esperar a que el juego la refresque)
HU:On("CHAT_MSG_SYSTEM", function(text)
    if type(text) ~= "string" or not HU.myTag then return end
    for _, p in ipairs(Patterns()) do
        local name = text:match(p.pat)
        if name then
            name = name:match("^|Hplayer:([^|:]+)") or name
            local k = HU:Key(name)
            local e = k and HU.roster[k]
            if e and e.online ~= p.on then
                e.online = p.on
                if p.on then e.afk = false end
                NoteRecent(e, p.on)
                -- (acaba de entrar alguien: las listas que pasaron antes por GUILD no le llegaron)
                if p.on and HU.ListNeeded then HU.ListNeeded() end
                HU.rosterVersion = (HU.rosterVersion or 0) + 1
                HU.rosterOnline = math.max(0, (HU.rosterOnline or 0) + (p.on and 1 or -1))
                HU:Changed("members")
                if IsFav(e.name) then FavNow() end
                -- (se ha ido el enlace o un ayudante: el nuevo reparto sale ya, no a los 15 s)
                if not p.on and InRelayGroup(HU, k) and HU:IsRelay() and HU.HelpersChangedHello then HU:HelpersChangedHello(true) end
                local shared = HU.RankRole and HU:RankRole(HU.myTag, e.rankIndex) ~= nil or InRelayGroup(HU, k)
                HU:PresenceSchedule(shared)
                if HU.RequestRoster then HU:RequestRoster() end
            end
            return
        end
    end
end)

---------------------------------------------------------------------------
-- Red de seguridad: susurro a alguien de otra hermandad que sale conectado y el juego dice «no hay [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local PX_OUT_MAX, PX_IN_MAX, PX_WIN = 6, 10, 60  -- avisos que mando / que acepto de cada compañero, por minuto
local pxOut = { t = 0, n = 0 }
local pxName = {}   -- [clave] = cuándo lo avisé (una vez cada 30 s por persona)
local pxIn = {}     -- [remitente] = { t, n }

local function DropRemote(self, tag, k)
    local r = self.remoteRoster[tag]
    if not (r and r.byKey and r.byKey[k]) then return false end
    local keep = {}
    for _, m in ipairs(r.members) do if m.name:lower() ~= k then keep[#keep + 1] = m end end
    r.members = keep
    if HU.IndexRoster then HU.IndexRoster(r) end
    r.online = math.max(0, (r.online or #keep + 1) - 1)
    self:Changed("members")
    if IsFav(k) then FavNow() end
    return true
end

function HU:PresenceNotFound(who)
    if not self.myTag or type(who) ~= "string" then return end
    local full = self:FullName(who)
    if not full then return end
    local k = full:lower()
    if self.roster[k] then return end -- (de mi hermandad: lo dice ya la lista del juego)
    for tag in pairs(self.remoteRoster) do
        if tag ~= self.myTag and DropRemote(self, tag, k) then
            local now = GetTime()
            if now - pxOut.t > PX_WIN then pxOut.t, pxOut.n = now, 0 end
            if pxOut.n < PX_OUT_MAX and (not pxName[k] or now - pxName[k] > 30) and IsInGuild() then
                pxOut.n, pxName[k] = pxOut.n + 1, now
                self:Send("PX~" .. tag .. "~" .. self:Short(full), "GUILD", nil, nil, nil, true)
            end
        end
    end
end

HU.comm.PX = function(self, sender, f, dist)
    if dist ~= "GUILD" then return end
    local tag, name = f[1], f[2]
    if not tag or tag == self.myTag or not HU.SafeName or not HU.SafeName(name) then return end
    local k = sender:lower()
    local now = GetTime()
    local c = pxIn[k]
    if not c or now - c.t > PX_WIN then c = { t = now, n = 0 }; pxIn[k] = c end
    if c.n >= PX_IN_MAX then return end
    c.n = c.n + 1
    local full = self:FullName(name)
    if full then DropRemote(self, tag, full:lower()) end
end

---------------------------------------------------------------------------
-- Salir del juego de forma normal (/camp, /logout, /quit): quien se comparte lo dice a su hermandad [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local leavingPeers, LEAVING_FOR = {}, 60

local function MarkGuildmate(k, on)
    local e = k and HU.roster[k]
    if not e or e.online == on then return end
    e.online = on
    NoteRecent(e, on)
    HU.rosterVersion = (HU.rosterVersion or 0) + 1
    HU.rosterOnline = math.max(0, (HU.rosterOnline or 0) + (on and 1 or -1))
    HU:Changed("members")
    if IsFav(e.name) then FavNow() end
    if not on and InRelayGroup(HU, k) and HU:IsRelay() and HU.HelpersChangedHello then HU:HelpersChangedHello(true) end
    HU:PresenceSchedule(true)
end

HU.comm.PV = function(self, sender, f, dist)
    if dist ~= "GUILD" then return end
    local k = self:Key(sender)
    if not (k and self.roster[k]) or k == self:MeKey() then return end
    leavingPeers[k] = GetTime()
    MarkGuildmate(k, false)
end
HU.comm.PW = function(self, sender, f, dist)
    if dist ~= "GUILD" then return end
    local k = self:Key(sender)
    if not (k and leavingPeers[k]) then return end
    leavingPeers[k] = nil
    MarkGuildmate(k, true)
end

local leaving = false
local function Leaving()
    if leaving or not HU.myTag or not IsInGuild() then return end
    local me = HU:MeKey()
    local e = me and HU.roster[me]
    if not (e and e.online) then return end
    local slot = HU:RosterSlot()
    if not (slot or (HU.RankRole and HU:RankRole(HU.myTag, e.rankIndex))) then return end
    leaving = true
    HU:Send("PV", "GUILD", nil, true, nil, true)
    -- («-yo» sobre cualquier copia: la huella va a 0 y los cambios valen igual)
    local sig = slot and HU.RosterSigNow and HU.RosterSigNow()
    local mine = e._re and e._re.short
    e.online = false
    HU.rosterVersion = (HU.rosterVersion or 0) + 1
    if sig and mine and sig[mine] then
        local pseudo = { sig = {}, hash = "0" }
        for n, sg in pairs(sig) do pseudo.sig[n] = sg end
        -- (una hermandad por fotograma, como PresenceFlush)
        for i, tag in ipairs(HU:OtherTags()) do
            HU.After(0.02 * (i - 1), function()
                local p = HU:BestPeer(tag)
                if p then HU:SendRosterDelta(p.name, { sig = pseudo.sig, hash = "0" }, not HU:SimpleMode()) end
            end)
        end
    end
end
local function Stayed()
    if not leaving then return end
    leaving = false
    HU:Send("PW", "GUILD", nil, true, nil, true)
    local me = HU:MeKey()
    local e = me and HU.roster[me]
    if e and not e.online then
        e.online = true
        HU.rosterVersion = (HU.rosterVersion or 0) + 1
        HU:PresenceSchedule(true)
    end
end
HU:On("PLAYER_CAMPING", Leaving)
HU:On("PLAYER_QUITING", Leaving)
HU:On("LOGOUT_CANCEL", Stayed)
HU:OnStart(function()
    for _, fn in ipairs({ "Logout", "Quit", "ForceQuit" }) do
        if type(_G[fn]) == "function" and hooksecurefunc then pcall(hooksecurefunc, fn, Leaving) end
    end
    if type(_G.CancelLogout) == "function" and hooksecurefunc then pcall(hooksecurefunc, "CancelLogout", Stayed) end
end)

-- y cada vez que el juego refresca la lista de la hermandad (por si alguien no sale en los avisos) [+ARCHITECTURE.md]
function HU:AfterRosterScan()
    local function off(k)
        local e = k and self.roster[k]
        if e and e.online then e.online = false; self.rosterVersion = (self.rosterVersion or 0) + 1 end
    end
    if leaving then off(self:MeKey()) end
    local now = GetTime()
    for k, t in pairs(leavingPeers) do
        if now - t > LEAVING_FOR then leavingPeers[k] = nil else off(k) end
    end
    self:PresenceSchedule()
end


HU:OnStart(function()
    HU.NewTicker(FAST_ROSTER, function()
        if HU:RosterSlot() and HU.RequestRoster then HU:RequestRoster() end
    end)
end)
