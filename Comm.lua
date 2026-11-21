-- Guild Union - comunicación entre addons (contactos y listas de miembros)
local _, HU = ...

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
-- (HU.comm, los manejadores de las órdenes, lo crea Core.lua)
-- medidas de este ordenador y su conexión (para elegir el enlace): las usan Net/Transport.lua,
-- Net/Relay.lua y Net/Security.lua
HU.netPerf = {}
