-- Guild Union - guardia por encargo (decisión de Jorge, 07/11) [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L

local KEEPER_SCAN = 600  -- el canal principal se recorre para saber quién manda y echar vetados, cada 10 min
local KEEPER_TTL = 1200  -- lo sabido de propietario y moderadores vale este tiempo
local OFF_EVERY = 120    -- el chat de oficiales se revisa cada 2 min (y al entrar alguien)
local OFF_GRACE = 60     -- no oficial visto dos veces con al menos esto entre medias: fuera
local REVIEW_TTL = 600   -- una revisión a petición sigue al día (con las respuestas que lleguen) este tiempo
local REVIEW_ASK = 3     -- preguntas a las hermandades por cada revisión (unos 15 nombres cada una)

local leaders = {}       -- [kind] = { t, owner, mods = {clave = true}, iAmOwner, iAmMod, banned, members }
local lastMainScan, lastOffScan = -999, -999
local offSeen = {}       -- [clave] = cuándo se le vio por primera vez sin ser oficial
local review             -- revisión a petición: { t, untilT, suspects = {clave = nombre}, total, union, shown }

-- ¿Sé que tiene el addon? (yo, un compañero que ha saludado, o un contacto de otra hermandad)
local function HasAddon(self, k)
    if k == self:MeKey() then return true end
    local p = self.guildPeers[k]
    if p and GetTime() - (p.last or 0) < self.PEER_TTL then return true end
    local r = self.remote[k]
    return r ~= nil and GetTime() - (r.last or 0) < 900
end

-- Una pasada por la lista del juego: propietario, moderadores y vetados presentes (y, en el chat de [+ARCHITECTURE.md]
local SCAN_SLICE = 200
local scanning = {} -- [kind] = lectura en curso
local function ScanLeaders(self, kind, done)
    local id, num, info = self:ChannelRoster(kind)
    local me = self:MeKey()
    if not id or num == 0 or not me then return done(nil) end
    if scanning[kind] and GetTime() - scanning[kind].started < 60 then return end -- (ya hay una)
    local meSpace = me:gsub("%-", " ", 1)
    local Ld = { t = GetTime(), mods = {}, banned = {}, members = (kind == "off") and {} or nil }
    local anyBan = next(self.db.bans or {}) ~= nil
    local job = { started = GetTime(), i = 1 }
    scanning[kind] = job
    local slice = (kind == "main") and SCAN_SLICE or num
    local function Step()
        if scanning[kind] ~= job then return end
        local last = math.min(num, job.i + slice - 1)
        for i = job.i, last do
            local name, owner, mod = info(id, i)
            if name then
                local full = self:FullName(name) or name
                local k = full:lower()
                local isMe = k == me or name:lower() == meSpace
                if isMe then k = me end
                local m = (owner or mod) and true or false
                if owner then Ld.owner = k end
                if m then Ld.mods[k] = true end
                if isMe then Ld.iAmOwner, Ld.iAmMod = owner and true or false, m end
                if not isMe then
                    if anyBan and self:IsBanned(full) then Ld.banned[#Ld.banned + 1] = full end
                    if Ld.members then Ld.members[#Ld.members + 1] = { name = full, k = k, mod = m } end
                end
            end
        end
        job.i = last + 1
        if job.i <= num then return HU.After(0, Step) end
        scanning[kind] = nil
        Ld.t = GetTime()
        leaders[kind] = Ld
        done(Ld)
    end
    Step()
end

-- ¿Soy yo el encargado de la guardia de ese canal? nil si no lo sé todavía
function HU:IsGuardKeeper(kind)
    local Ld = leaders[kind]
    if not Ld or GetTime() - Ld.t > KEEPER_TTL then return nil end
    if not Ld.iAmMod then return false end
    if Ld.iAmOwner then return true end
    if Ld.owner and HasAddon(self, Ld.owner) then return false end
    local me = self:MeKey()
    local myH = HU.Hash(me)
    for k in pairs(Ld.mods) do
        if k ~= me and HasAddon(self, k) and HU.Hash(k) < myH then return false end
    end
    return true
end

local function ChanAction(self, kind, name, ban, why)
    local c = self.chan[kind]
    if not c or not c.name or not name then return false end
    local fn
    if ban then fn = ChannelBan or (C_ChatInfo and C_ChatInfo.ChannelBan)
    else fn = ChannelKick or (C_ChatInfo and C_ChatInfo.ChannelKick) end
    if not fn then return false end
    local k = name:lower()
    if self.kicked[k] and GetTime() - self.kicked[k] < 60 then return false end
    pcall(fn, c.name, self:Short(name))
    self.kicked[k] = GetTime()
    self:AddAudit({ tag = self.myTag, actor = self:Me(), text = (ban and L("vetó a ") or L("echó a ")) .. self:Short(name) .. why }, "all")
    return true
end

---------------------------------------------------------------------------
-- Vetados del canal principal: solo el encargado
---------------------------------------------------------------------------
local function MainBans(self, now)
    if not self:IsJoined("main") then return end
    if self.NeedsChannelList and not self:NeedsChannelList() then return end
    if now - lastMainScan < KEEPER_SCAN then return end
    lastMainScan = now
    ScanLeaders(self, "main", function(Ld)
        if not Ld or not HU:IsGuardKeeper("main") then return end
        for _, name in ipairs(Ld.banned) do ChanAction(HU, "main", name, true, L(" del canal")) end
    end)
end

---------------------------------------------------------------------------
-- Chat de oficiales: guardia automática del encargado
---------------------------------------------------------------------------
-- ¿Tengo al día las listas (de oficiales) de todas las hermandades, y ninguna está sin confirmar?
-- Si no, a quien no sale en ninguna no se le puede echar: podría ser un oficial de esa hermandad
local function ListsFirm(self)
    if #self:MissingLists() > 0 then return false end
    local stateOf = HU.RosterStateOf
    if not stateOf then return true end
    for _, tag in ipairs(self:OtherTags()) do
        local s = stateOf(self.remoteRoster[tag])
        if s ~= nil and s ~= "c" and s ~= "p" then return false end
    end
    return true
end

local function OfficerGuard(self, now, force)
    if self:IsTest() or not self:IsJoined("off") or not self:CanOfficer() then return end
    if not force and now - lastOffScan < OFF_EVERY then return end
    lastOffScan = now
    -- (el chat de oficiales es pequeño: se lee de una vez y done se llama enseguida)
    local Ld
    ScanLeaders(self, "off", function(x) Ld = x end)
    if not Ld or not self:IsGuardKeeper("off") then return end
    local firm = ListsFirm(self)
    local present, out = {}, {}
    for _, name in ipairs(Ld.banned) do
        if ChanAction(self, "off", name, true, L(" del chat de oficiales (vetado)")) then out[#out + 1] = self:Short(name) end
    end
    for _, m in ipairs(Ld.members) do
        present[m.k] = true
        if not m.mod and not self:IsBanned(m.name) then
            local ok, why = self:TrustedOfficer(m.name)
            if ok or why == "unknown" or not (self:InAnyGuild(m.name) or firm) then
                offSeen[m.k] = nil -- (es oficial, o aún no se puede saber)
            elseif not offSeen[m.k] then
                offSeen[m.k] = now
                HU.After(OFF_GRACE + 1, function() HU:GuardOfficersNow() end)
            elseif now - offSeen[m.k] >= OFF_GRACE then
                offSeen[m.k] = nil
                if ChanAction(self, "off", m.name, false, L(" del chat de oficiales (no es oficial)")) then out[#out + 1] = self:Short(m.name) end
            end
        end
    end
    for k in pairs(offSeen) do if not present[k] then offSeen[k] = nil end end
    if #out > 0 then self:Print(L("Guardia del chat de oficiales: fuera ") .. table.concat(out, ", ")) end
end
function HU:GuardOfficersNow() OfficerGuard(self, GetTime(), true) end

---------------------------------------------------------------------------
-- Revisión del canal principal a petición: /gu guardia revisar
---------------------------------------------------------------------------
local function ReviewEvaluate(self, ask)
    local r = review
    if not r or not r.suspects then return end
    local missing = self:MissingLists()
    local full = #missing == 0
    for _, t in ipairs(self:OtherTags()) do if not self:ListFresh(t) then full = false end end
    local found, toAsk, pending = {}, {}, 0
    for k, name in pairs(r.suspects) do
        local v = self:GuardVerdict(name)
        if self:InAnyGuild(name) or v == false then
            r.suspects[k] = nil
        elseif full or v == true then
            found[#found + 1] = { name = name, since = r.t }
        else
            pending = pending + 1
            toAsk[k] = name
        end
    end
    table.sort(found, function(a, b) return a.name < b.name end)
    self.intruders = found
    if ask and next(toAsk) then
        local tags = self:OtherTags()
        if #tags > 0 then for _ = 1, REVIEW_ASK do self:GuardAsk(toAsk, tags) end end
    end
    r.pending = pending
    if ask or #found ~= (r.shown or -1) then
        r.shown = #found
        local names = {}
        for i = 1, math.min(#found, 10) do names[#names + 1] = self:Short(found[i].name) end
        self:Print(string.format(L("Revisión del canal: %d personas, %d de las hermandades. Intrusos: %d%s. Sin confirmar: %d."),
            r.total, r.union, #found, (#names > 0) and (" (" .. table.concat(names, ", ") .. (#found > 10 and "..." or "") .. ")") or "", pending))
        if ask and pending > 0 then
            self:Print(L("A los que faltan se les pregunta a sus hermandades por partes: repite /gu guardia revisar para seguir. Para echar a uno, abre la ventana de intrusos."))
        end
    end
    self:Changed("guard")
end

function HU:GuardReview()
    if not self:CanPin() then return self:Print(L("Solo el maestro y los oficiales pueden revisar el canal.")) end
    if not self:IsJoined("main") then return self:Print(L("No estás en el canal.")) end
    if review and review.reading and GetTime() - review.t < 30 then return self:Print(L("La revisión ya está en marcha.")) end
    -- (repetirla en poco tiempo: sigue preguntando por los que faltan, sin volver a leer el canal)
    if review and review.suspects and GetTime() < review.untilT and GetTime() - review.t < 120 then
        return ReviewEvaluate(self, true)
    end
    self:Print(L("Revisando el canal (por partes, puede tardar unos segundos)..."))
    review = { reading = true, t = GetTime() }
    self:GetChannelMembersAsync("main", function(list)
        local r = review
        if not r then return end
        r.reading = nil
        if not list then
            review = nil
            return HU:Print(L("La lista del canal no está disponible (abre Social > Chat una vez)"))
        end
        local known = HU.GuardKnownSet and HU.GuardKnownSet(HU) or {}
        local me = HU:MeKey()
        r.suspects, r.total, r.union, r.untilT = {}, #list, 0, GetTime() + REVIEW_TTL
        for _, m in ipairs(list) do
            local k = m.name and m.name:lower()
            if k and k ~= me then
                if m.mod or known[k] or HU:InAnyGuild(m.name) then r.union = r.union + 1
                else r.suspects[k] = m.name end
            end
        end
        ReviewEvaluate(HU, true)
    end)
end

---------------------------------------------------------------------------
-- Lo que antes hacía la revisión periódica (GuardTick la manda aquí)
---------------------------------------------------------------------------
function HU:GuardRedirect()
    local now = GetTime()
    -- (llegan respuestas de las hermandades a la revisión a petición: se actualiza la lista)
    if review and review.suspects and now < (review.untilT or 0) then ReviewEvaluate(self, false) end
    MainBans(self, now)
    OfficerGuard(self, now)
    local keeper = self:IsGuardKeeper("main")
    self.guardStatus = L("A petición (/gu guardia revisar). Vetados: ")
        .. ((keeper == true) and L("los echas tú (encargado)") or L("los echa el encargado"))
        .. ((self:IsGuardKeeper("off") == true) and L(". Chat de oficiales: lo vigilas tú") or "")
end

-- Al entrar alguien: si es un vetado del canal principal, lo echa el encargado ya; si es el chat de
-- oficiales, se revisa enseguida
HU:On("CHAT_MSG_CHANNEL_JOIN", function(_, author, _, fullName, _, _, _, _, baseName)
    local kind = HU:KindOf(baseName, fullName)
    if not kind or not author then return end
    local name = HU:FullName(author)
    if not name then return end
    if kind == "main" then
        if HU:IsBanned(name) and HU:IsGuardKeeper("main") then ChanAction(HU, "main", name, true, L(" del canal")) end
    elseif kind == "off" then
        HU.After(5, function() HU:GuardOfficersNow() end)
    end
end)
