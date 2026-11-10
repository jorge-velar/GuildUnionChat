-- Guild Union - lista de miembros de la hermandad propia
local _, HU = ...

HU.roster = {}          -- [clave] = entrada
HU.rosterList = {}
HU.rosterTotal = 0
HU.rosterOnline = 0

-- (las de Retail van al final, para que los números de las de Classic no cambien)
HU.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
               "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }
HU.CLASS_INDEX = {}
for i, c in ipairs(HU.CLASSES) do HU.CLASS_INDEX[c] = i end

-- La lista se lee por trozos (SLICE miembros cada STEP s) y como mucho cada MIN_GAP s; si alguien
-- la pide con prisa (force: guardia, rangos, altas y bajas), cada SOON_GAP s.
local SLICE = 200
local STEP = 0.02
local MIN_GAP = 30
local SOON_GAP = 3
local START_GAP, START_FOR = 10, 180  -- al entrar, la lista aún se llena: los 3 primeros minutos, cada 10 s
local OFF_EVERY = 900   -- «última conexión» de un desconectado: se vuelve a leer como mucho cada 15 min

local lastRequest = 0
local soon = false
function HU:RequestRoster(force)
    if not IsInGuild() then return end
    local now = GetTime()
    if not force and now - lastRequest < 15 then return end
    lastRequest = now
    if force then soon = true end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
end

function HU:CanOfficer()
    if C_GuildInfo and C_GuildInfo.CanViewOfficerNote then
        return C_GuildInfo.CanViewOfficerNote() and true or false
    end
    return false
end

local scan              -- la lectura en curso (nil si no hay)
local lastScan = -1e9   -- cuándo empezó la última
local dirty = false     -- el juego avisó de cambios mientras se leía
local due, token = nil, 0
local nameCache, nameCount = {}, 0   -- nombre que da el juego -> { completo, clave }

local function ReadOne(self, s, i, now)
    local name, rankName, rankIndex, level, _, zone, _, officerNote, isOnline, status, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)
    if not name then return end
    local c = nameCache[name]
    if not c then
        local full = self:FullName(name)
        if not full then return end
        c = { full, full:lower() }
        nameCache[name], nameCount = c, nameCount + 1
    end
    local full, key = c[1], c[2]
    -- (repetido: la lista se movió mientras se leía por trozos)
    if s.map[key] then return end
    -- (se reutiliza la ficha de la vez anterior: con 1.000 miembros, menos basura y menos tirones)
    local e = s.old[key]
    if not e then e, s.newNames = {}, true end
    local wasOnline = e.online
    e.name, e.rank, e.rankIndex, e.level, e.class, e.zone = full, rankName, rankIndex, level, class, zone
    e.guid = guid -- (para la raza en la ventana, si no hay ficha)
    e.online = isOnline and true or false
    e.afk = isOnline and (status == 1 or status == 2 or (type(status) == "string" and status ~= "")) or false
    if e.online then
        e.offSecs, e.offAt = nil, nil
    elseif GetGuildRosterLastOnline and (wasOnline ~= false or not e.offAt or now - e.offAt > OFF_EVERY) then
        e.offAt, e.offSecs = now, nil
        local y, m, d, h = GetGuildRosterLastOnline(i)
        if y or m or d or h then
            e.offSecs = ((((y or 0) * 365 + (m or 0) * 30 + (d or 0)) * 24) + (h or 0)) * 3600
        end
    end
    s.map[key] = e
    s.list[#s.list + 1] = e
    if e.online then s.online = s.online + 1 end
    if s.canOff then
        -- (las notas de oficial solo se vuelven a leer si han cambiado)
        if e.noteSeen ~= officerNote then
            e.noteSeen = officerNote
            e.noteOff1, e.noteOff2 = HU.ParseOfficerNote(officerNote)
            e.noteChan1, e.noteChan2, e.noteChanBad = HU.ParseChannelNote(officerNote)
            e.noteCfg = HU.NoteConfigLine and HU.NoteConfigLine(officerNote) or nil
        end
        if not s.offName and e.noteOff1 then s.offName, s.offPass = e.noteOff1, e.noteOff2 end
        -- canal y contraseña en una nota de oficial (gana la del rango más alto)
        if e.noteChanBad then s.chanBad = true end
        if e.noteChan1 and (not s.chanRank or (rankIndex or 99) < s.chanRank) then
            s.chanName, s.chanPass, s.chanRank = e.noteChan1, e.noteChan2, rankIndex or 99
        end
        -- líneas de la comunidad guardadas en notas de oficial
        if e.noteCfg then s.cfgNotes[#s.cfgNotes + 1] = { r = rankIndex or 99, n = full, l = e.noteCfg } end
    end
end

local function Finish(self, s)
    scan = nil
    -- Si la lista viene vacía (aún cargando) no borramos la anterior
    if not (#s.list == 0 and #self.rosterList > 0) then
        local canOff = s.canOff
        -- (¿ha entrado o salido alguien? si no, la huella de los nombres sigue valiendo: Lists.lua)
        if s.newNames or #s.list ~= #self.rosterList or not self.rosterNamesV then
            self.rosterNamesV = (self.rosterNamesV or 0) + 1
        end
        self.roster, self.rosterList = s.map, s.list
        self.rosterTotal, self.rosterOnline = s.total, s.online
        self.rosterVersion = (self.rosterVersion or 0) + 1
        if s.chanName and self.OnChannelNote then self:OnChannelNote(s.chanName, s.chanPass)
        elseif canOff and #s.list > 0 and self.OnChannelNoteMissing then self:OnChannelNoteMissing(s.chanBad) end
        if canOff and self.OnNoteConfig then
            local cfgNotes = s.cfgNotes
            table.sort(cfgNotes, function(a, b) if a.r ~= b.r then return a.r < b.r end return a.n < b.n end)
            local ls = {}
            for _, c in ipairs(cfgNotes) do ls[#ls + 1] = c.l end
            local txt = table.concat(ls, "\n")
            if txt ~= (self.noteCfgText or "") then
                self:OnNoteConfig(ls)
                if self.RefreshConfig then self:RefreshConfig() end
            end
        end

        local prev = self.offCfg
        if s.offName then
            if not prev or prev.channel ~= s.offName or prev.password ~= s.offPass then
                self.offCfg = { channel = s.offName, password = s.offPass }
                self:ApplyChannels()
            end
        elseif prev and canOff then
            self.offCfg = nil
            self:ApplyChannels()
        end
        self:Changed("members")
        -- (lo que viene después, en los fotogramas siguientes)
        HU.After(0, function() if HU.AfterRosterScan then HU:AfterRosterScan() end end)
        HU.After(0.02, function() HU:RefreshConfig() end)
    end
    if dirty then dirty = false; self:QueueScan() end
end

-- (cada trozo, como mucho SLICE miembros y BUDGET_MS de trabajo; el final, en su propio fotograma: los
-- 200 de golpe y el final juntos llegaban a 2,6 ms)
local BUDGET_MS, MIN_SLICE = 1, 20
local clock = debugprofilestop or function() return GetTime() * 1000 end
local function Step(self, s)
    if scan ~= s then return end
    if not IsInGuild() then scan = nil; self:ScanRoster(); return end
    if s.i > s.total then return Finish(self, s) end
    local now, t0 = GetTime(), clock()
    local last = math.min(s.total, s.i + SLICE - 1)
    local i = s.i
    while i <= last do
        ReadOne(self, s, i, now)
        i = i + 1
        if i - s.i >= MIN_SLICE and clock() - t0 > BUDGET_MS then break end
    end
    s.i = i
    HU.After(s.i > s.total and 0 or STEP, function() Step(self, s) end)
end

function HU:ScanRoster()
    if not IsInGuild() then
        scan = nil
        wipe(self.roster); wipe(self.rosterList)
        self.rosterTotal, self.rosterOnline = 0, 0
        return
    end
    lastScan = GetTime()
    local total = GetNumGuildMembers() or 0
    if nameCount > 3 * total + 200 then wipe(nameCache); nameCount = 0 end
    local s = { total = total, i = 1, map = {}, list = {}, online = 0, old = self.roster or {},
        canOff = self:CanOfficer(), cfgNotes = {} }
    scan = s
    Step(self, s)
end

-- Próxima lectura: no antes de MIN_GAP s desde la anterior (SOON_GAP si se pidió con prisa)
function HU:QueueScan()
    if scan then dirty = true; return end
    local now = GetTime()
    local gap = soon and SOON_GAP or ((now - (HU.rosterStartT or now) < START_FOR) and START_GAP or MIN_GAP)
    local at = math.max(now + 1, lastScan + gap)
    if due and due <= at + 0.5 then return end
    due, token = at, token + 1
    local mine = token
    HU.After(at - now, function()
        if mine ~= token then return end
        due = nil
        if scan then dirty = true; return end
        soon = false
        HU:ScanRoster()
    end)
end

HU:On("GUILD_ROSTER_UPDATE", function() HU:QueueScan() end)

HU:On("PLAYER_GUILD_UPDATE", function()
    HU:RequestRoster(true)
    HU.After(2, function() HU:RefreshConfig() end)
end)

HU:OnStart(function()
    HU.rosterStartT = GetTime()
    HU:RequestRoster(true)
    HU.NewTicker(60, function() HU:RequestRoster() end)
end)

function HU:InMyGuild(name)
    local k = self:Key(name)
    return k and self.roster[k] ~= nil
end
