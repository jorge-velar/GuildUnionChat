-- Guild Union - presencia por el canal (idea de GreenWall Revived): si alguien de OTRA hermandad que está [+ARCHITECTURE.md]
local _, HU = ...

local WAIT = 10        -- segundos que se espera a que vuelva al canal o dé señales
local LANE_QUIET = 60  -- sin esto desde el último cambio de carril (mío o suyo) o mío de canal
local pending = {}     -- [clave] = { t, st, tag, name }
local lastLaneT, lastMineT = -999, -999
HU.chanLeaveN, HU.chanLeaveDropN = 0, 0

-- (cambio de carril o de generación: mío, o que me cuenta otro; y cuando entro, salgo o cambio yo de canal)
HU:OnStart(function()
    local function wrap(name)
        local orig = HU[name]
        if type(orig) ~= "function" then return end
        HU[name] = function(...)
            lastLaneT = GetTime()
            return orig(...)
        end
    end
    wrap("SetLaneState")
    wrap("OfferLane")
end)

-- ¿Está en el grupo compartido de su hermandad (maestro, oficial, enlace o ayudante)?
local function SharedOf(self, k)
    for tag, r in pairs(self.remoteRoster or {}) do
        local m = r.byKey and r.byKey[k]
        if m and tag ~= self.myTag then
            local idx = m.rankIndex or m.rankHidden
            if idx and self.RankRole and self:RankRole(tag, idx) then return tag, m end
            local p = self.remote and self.remote[k]
            if p and p.relay then return tag, m end
            local h = self.helpers and self.helpers[tag]
            if h and h.list then
                for _, n in ipairs(h.list) do
                    if (self:Key(n) or "") == k then return tag, m end
                end
            end
        end
    end
    return nil
end

local function Check(k, p)
    if pending[k] ~= p then return end
    pending[k] = nil
    local self = HU
    -- (mudanza de carril en curso, o soy yo quien acaba de cambiar de canal: no cuenta)
    if GetTime() - lastLaneT < LANE_QUIET or GetTime() - lastMineT < LANE_QUIET then return end
    -- (ha dado señales después de salir: ha hablado en el canal o me ha llegado algo suyo)
    local seen = self.chanSeen and self.chanSeen[k]
    if seen and seen > p.t then return end
    local rp = self.remote and self.remote[k]
    if rp and rp.last and rp.last > p.t then return end
    local r = self.remoteRoster and self.remoteRoster[p.tag]
    local m = r and r.byKey and r.byKey[k]
    if not m then return end
    -- (una conexión suya más nueva que la salida: no se toca. Lo hace también ApplyRosterDelta, por miembro)
    if m.st and m.st >= p.st then return end
    if not HU.ApplyRosterDelta then return end
    local before = #r.members
    HU.ApplyRosterDelta(self, r, p.tag, { "-" .. self:Short(m.name) }, 1, p.st)
    if #r.members < before then
        HU.chanLeaveDropN = HU.chanLeaveDropN + 1
        if HU.IndexRoster then HU.IndexRoster(r) end
        r.online = math.max(0, (r.online or before) - 1)
        self:Changed("members")
        self:Debug("Presencia por el canal: fuera", m.name, "<" .. p.tag .. ">")
    end
end

HU:On("CHAT_MSG_CHANNEL_LEAVE", function(_, author, _, fullName, _, _, _, _, baseName)
    if HU:KindOf(baseName, fullName) ~= "main" or type(author) ~= "string" then return end
    HU.chanLeaveN = HU.chanLeaveN + 1
    local full = HU:FullName(author)
    local k = full and full:lower()
    if not k or k == HU:MeKey() then return end
    -- (cuándo salió: si mandó una lista y se va, que la del siguiente no le incluya no es disputa)
    HU.chanLeftT = HU.chanLeftT or {}
    HU.chanLeftT[k] = GetTime()
    local tag = SharedOf(HU, k)
    if not tag then return end
    local p = { t = GetTime(), st = HU.ListStampNow and HU.ListStampNow() or 0, tag = tag }
    pending[k] = p
    HU.After(WAIT, function() Check(k, p) end)
end)

-- (vuelve a entrar al canal: solo cancela el aviso; no añade a nadie)
HU:On("CHAT_MSG_CHANNEL_JOIN", function(_, author, _, fullName, _, _, _, _, baseName)
    if HU:KindOf(baseName, fullName) ~= "main" or type(author) ~= "string" then return end
    local full = HU:FullName(author)
    if full then pending[full:lower()] = nil end
end)

HU:On("CHAT_MSG_CHANNEL_NOTICE", function(notice, _, _, fullName, _, _, _, _, baseName)
    if HU:KindOf(baseName, fullName) == "main" and (notice == "YOU_JOINED" or notice == "YOU_LEFT" or notice == "YOU_CHANGED") then
        lastMineT = GetTime()
    end
end)
