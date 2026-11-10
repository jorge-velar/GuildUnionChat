-- Guild Union - fichas (profesiones, rol, raza), desconectados, silenciar, expulsar,
-- historial de lo escrito mientras no estabas y recetas
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

local function Clean(s) return (tostring(s or ""):gsub("[~:;,%.|\r\n]", " ")) end

---------------------------------------------------------------------------
-- Profesiones
---------------------------------------------------------------------------
HU.PROFS = HU.LT({
    ALC  = { name = "Alquimia",          icon = "Interface\\Icons\\Trade_Alchemy" },
    BS   = { name = "Herrería",          icon = "Interface\\Icons\\Trade_BlackSmithing" },
    ENC  = { name = "Encantamiento",     icon = "Interface\\Icons\\Trade_Engraving" },
    ENG  = { name = "Ingeniería",        icon = "Interface\\Icons\\Trade_Engineering" },
    HERB = { name = "Herboristería",     icon = "Interface\\Icons\\Spell_Nature_NatureTouchGrow" },
    LW   = { name = "Peletería",         icon = "Interface\\Icons\\Trade_LeatherWorking" },
    MIN  = { name = "Minería",           icon = "Interface\\Icons\\Trade_Mining" },
    TAIL = { name = "Sastrería",         icon = "Interface\\Icons\\Trade_Tailoring" },
    SKIN = { name = "Desuello",          icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
    COOK = { name = "Cocina",            icon = "Interface\\Icons\\INV_Misc_Food_15", secondary = true },
    FA   = { name = "Primeros auxilios", icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", secondary = true },
    FISH = { name = "Pesca",             icon = "Interface\\Icons\\Trade_Fishing", secondary = true },
})

local NAME2KEY = {
    ["alquimia"] = "ALC", ["alchemy"] = "ALC",
    ["herrería"] = "BS", ["herreria"] = "BS", ["blacksmithing"] = "BS",
    ["encantamiento"] = "ENC", ["enchanting"] = "ENC",
    ["ingeniería"] = "ENG", ["ingenieria"] = "ENG", ["engineering"] = "ENG",
    ["herboristería"] = "HERB", ["herboristeria"] = "HERB", ["herbalism"] = "HERB",
    ["peletería"] = "LW", ["peleteria"] = "LW", ["marroquinería"] = "LW", ["leatherworking"] = "LW",
    ["minería"] = "MIN", ["mineria"] = "MIN", ["mining"] = "MIN",
    ["sastrería"] = "TAIL", ["sastreria"] = "TAIL", ["tailoring"] = "TAIL",
    ["desuello"] = "SKIN", ["desollar"] = "SKIN", ["skinning"] = "SKIN",
    ["cocina"] = "COOK", ["cooking"] = "COOK",
    ["primeros auxilios"] = "FA", ["first aid"] = "FA",
    ["pesca"] = "FISH", ["fishing"] = "FISH",
}
HU.PROF_BY_NAME = NAME2KEY
do -- (las mismas, sin tildes: así no depende de cómo trate las tildes el cliente)
    local folded = {}
    for n, k in pairs(NAME2KEY) do folded[HU.Fold(n)] = k end
    for n, k in pairs(folded) do NAME2KEY[n] = k end
end
local function ProfKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    return NAME2KEY[name:lower()] or NAME2KEY[HU.Fold(name)] or NAME2KEY[HU.Fold(HU.Trim(name))]
end
HU.ProfKey = ProfKey

function HU:ScanProfessions()
    local out, seen = {}, {}
    -- juego moderno (Forever): GetProfessions / GetProfessionInfo, por número de habilidad
    if GetProfessions and GetProfessionInfo then
        local BY_ID = { [171] = "ALC", [164] = "BS", [333] = "ENC", [202] = "ENG", [182] = "HERB", [165] = "LW",
                        [186] = "MIN", [197] = "TAIL", [393] = "SKIN", [185] = "COOK", [129] = "FA", [356] = "FISH" }
        for _, idx in ipairs({ GetProfessions() }) do
            if idx then
                local ok, name, _, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, idx)
                local key = ok and (BY_ID[tonumber(skillLine) or 0] or ProfKey(name))
                if key and not seen[key] then seen[key] = true; out[#out + 1] = { key = key, rank = tonumber(rank) or 0, max = tonumber(maxRank) or 0 } end
            end
        end
    end
    return out
end

-- "ALC300.HERB275" -> { {key="ALC", rank=300}, ... }  (primero las principales)
---------------------------------------------------------------------------
-- Rol (por la especialización, o el que elijas con /gu rol)
---------------------------------------------------------------------------
-- (clases que pueden hacer algo más que daño)
local MULTI_ROLE = { WARRIOR = true, PALADIN = true, PRIEST = true, SHAMAN = true, DRUID = true }
HU.ROLES = HU.LT({
    T = { name = "Tanque",  icon = "Interface\\Icons\\Ability_Defend" },
    H = { name = "Sanador", icon = "Interface\\Icons\\Spell_Holy_FlashHeal" },
    D = { name = "DPS",     icon = "Interface\\Icons\\Ability_DualWield" },
    F = { name = "Tanque o DPS (feral)", icon = "Interface\\Icons\\Ability_Racial_BearForm" },
})

-- (en Forever la especialización ya dice el rol)
function HU:DetectRole()
    if self.db.myRole then return self.db.myRole, nil end
    local _, class = UnitClass("player")
    if GetSpecialization and GetSpecializationInfo then
        local ok, idx = pcall(GetSpecialization)
        if ok and idx then
            local ok2, _, sname, _, _, role = pcall(GetSpecializationInfo, idx)
            if ok2 then
                local r = (role == "TANK" and "T") or (role == "HEALER" and "H") or (role == "DAMAGER" and "D") or nil
                if not r and not MULTI_ROLE[class] then r = "D" end
                return r, sname
            end
        end
    end
    if not MULTI_ROLE[class] then return "D", nil end -- clases que solo hacen daño
    return nil, nil
end

---------------------------------------------------------------------------
-- Fichas
---------------------------------------------------------------------------
-- Razas: en la ficha va la del juego en inglés ("Orc", "Scourge"...), así se ve bien en
-- cualquier idioma y se puede filtrar. (Si llega un nombre, en español o inglés, también vale.)
HU.RACE_ORDER = { "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Scourge", "Tauren", "Troll" }
HU.RACE_NAMES = {
    Human = { es = "Humano", en = "Human" }, Dwarf = { es = "Enano", en = "Dwarf" },
    NightElf = { es = "Elfo de la noche", en = "Night Elf" }, Gnome = { es = "Gnomo", en = "Gnome" },
    Orc = { es = "Orco", en = "Orc" }, Scourge = { es = "No-muerto", en = "Undead" },
    Tauren = { es = "Tauren", en = "Tauren" }, Troll = { es = "Trol", en = "Troll" },
}
-- Raza de alguien: la de su ficha (los que tienen el addon) o, si es de mi hermandad, la que dice el juego
-- por su identificador (GUID de la lista de hermandad)
local function ProfileMsgFields(p)
    return Clean(p.race), p.r or "", Clean(p.s), p.p or ""
end

function HU:MyProfile()
    local raceName, raceFile
    if UnitRace then raceName, raceFile = UnitRace("player") end
    local race = (raceFile and HU.RACE_NAMES[raceFile] and raceFile) or raceName or ""
    local role, spec = self:DetectRole()
    local profs = {}
    for _, p in ipairs(self:ScanProfessions()) do profs[#profs + 1] = p.key .. p.rank end
    return { race = race or "", r = role or "", s = spec or "", p = table.concat(profs, "."), t = time() }
end

function HU:UpdateMyProfile(force)
    local k = self:MeKey()
    if not k then return end
    local p = self:MyProfile()
    local old = self.db.profiles[k]
    local same = old and old.race == p.race and old.r == p.r and old.s == p.s and old.p == p.p
    if same then p.t = old.t end
    self.db.profiles[k] = p
    if (not same or force) and IsInGuild() and not self:IsTest() then
        local race, r, s, profs = ProfileMsgFields(p)
        self:Send(table.concat({ "PF", race, r, s, profs }, "~"), "GUILD")
    end
    if not same then self:Changed("members") end
end

HU.comm.PF = function(self, sender, f)
    self.db.profiles[sender:lower()] = { race = f[1] or "", r = f[2] or "", s = f[3] or "", p = f[4] or "", t = time() }
    self:Changed("members")
end

-- El enlace pasa a las otras hermandades las fichas de la suya
local PROFILE_STEP = 150
function HU:SendProfilesTo(target, since)
    if not self.myTag then return end
    -- (la hermandad entera, por trozos de PROFILE_STEP en fotogramas seguidos: de golpe pasaba de 4 ms)
    local keys = {}
    for k in pairs(self.roster) do keys[#keys + 1] = k end
    local entries, i = {}, 1
    local function Step()
        if not self.myTag then return end
        -- (fase de lanzamiento: solo las de quien sale en las listas que ven las otras hermandades)
        local extra = self.SharedExtraSet and self:SharedExtraSet()
        local last = math.min(#keys, i + PROFILE_STEP - 1)
        for j = i, last do
            local k = keys[j]
            local e, p = self.roster[k], self.db.profiles[k]
            -- (solo las de los conectados; la de un desconectado se pide al abrirlo)
            if e and p and e.online and (not since or (p.t or 0) >= since) and self:SharedWithOthers(e, extra) then
                local race, r, s, profs = ProfileMsgFields(p)
                entries[#entries + 1] = table.concat({ Clean(self:Short(e.name)), race, r, s, profs }, ":")
            end
        end
        i = last + 1
        if i <= #keys then HU.After(0, Step) else self:SendProfileEntries(target, entries) end
    end
    Step()
end

function HU:SendProfileEntries(target, entries)
    local cur, size = {}, 0
    local function flush()
        if #cur > 0 then self:BulkWhisper(target, "PB~" .. self.myTag .. "~" .. table.concat(cur, ";")) end
        cur, size = {}, 0
    end
    for _, en in ipairs(entries) do
        if size + #en + 1 > 200 then flush() end
        cur[#cur + 1] = en
        size = size + #en + 1
    end
    flush()
end

HU.comm.PB = function(self, sender, f, dist, raw)
    local tag = f[1]
    if not tag or tag == self.myTag or not self.cfg or not self.cfg.byTag[tag] then return end
    for en in (f[2] or ""):gmatch("[^;]+") do
        local name, race, r, s, profs = en:match("^([^:]*):([^:]*):([^:]*):([^:]*):?(.*)$")
        local known = self.whitelist[tag] or self.remoteRoster[tag]
        if HU.SafeName(name) and (not known or self:MemberOf(name, tag)) then
            local function c(v) return (v:gsub("[|%c]", "")) end
            self.db.profiles[self:Key(name)] = { race = c(race), r = c(r), s = c(s), p = c(profs), t = time() }
        end
    end
    if dist == "WHISPER" then self:Send(raw, "GUILD") end
    self:Changed("members")
end

---------------------------------------------------------------------------
-- Desconectados de las otras hermandades (nivel, clase y cuánto llevan fuera)
---------------------------------------------------------------------------
HU.demoOffline = nil

function HU:SendOfflineTo(target, urgent)
    if not self.myTag then return end
    local entries = {}
    -- (fase de lanzamiento: de las otras hermandades solo se ven maestro y oficiales, así que de
    -- inactivos también van solo ellos; antes iban cientos de nombres en decenas de mensajes)
    local onlyOff = self.LaunchPhase and self:LaunchPhase()
    for _, e in ipairs(self.rosterList) do
        if not e.online and (not onlyOff or self:RankRole(self.myTag, e.rankIndex)) then
            local hours = e.offSecs and math.floor(e.offSecs / 3600) or ""
            entries[#entries + 1] = table.concat({ Clean(self:Short(e.name)), HU.CLASS_INDEX[e.class or ""] or 0, e.level or 0, hours }, ",")
        end
    end
    local cur, size = {}, 0
    local function flush()
        -- (OE: lo mismo, pero lo ha pedido alguien que lo está mirando: va en la cola normal)
        if #cur > 0 then self:BulkWhisper(target, (urgent and "OE~" or "OD~") .. self.myTag .. "~" .. table.concat(cur, ";")) end
        cur, size = {}, 0
    end
    for _, en in ipairs(entries) do
        if size + #en + 1 > 210 then flush() end
        cur[#cur + 1] = en
        size = size + #en + 1
    end
    flush()
end

HU.comm.OD = function(self, sender, f, dist, raw)
    local tag = f[1]
    if not tag or tag == self.myTag or not self.cfg or not self.cfg.byTag[tag] then return end
    if dist == "WHISPER" and not self:IsTest() and not self:IsRemoteForwarder(sender, tag) then return end
    local list = self.db.offline[tag] or {}
    self.db.offline[tag] = list
    local now = time()
    for en in (f[2] or ""):gmatch("[^;]+") do
        local name, cls, lvl, hours = en:match("^([^,]*),(%d*),(%d*),(%d*)$")
        if HU.SafeName(name) then
            list[self:Key(name)] = { n = name, c = HU.CLASSES[tonumber(cls) or 0], l = tonumber(lvl) or 0,
                s = tonumber(hours) and (now - tonumber(hours) * 3600) or nil }
        end
    end
    if dist == "WHISPER" then self:Send(raw, "GUILD") end
    self.db.offlineT = self.db.offlineT or {}
    self.db.offlineT[tag] = now
    HU.offlineVer = (HU.offlineVer or 0) + 1
    self:Changed("members")
end
HU.comm.OE = function(...) return HU.comm.OD(...) end

-- Al mandar la lista de conectados, el enlace añade las fichas y (de vez en cuando) los desconectados
local origSendRoster = HU.SendRosterTo
-- (por hermandad, no por contacto: el contacto cambia y la hermandad ya lo tiene)
local profilesSent = {}
function HU:SendRosterTo(target)
    origSendRoster(self, target)
    local p = self.remote[target:lower()]
    if not p or not p.tag then return end
    local now = time()
    -- (desde el último envío a esa hermandad, no desde el último completo: antes cada lista volvía a [+ARCHITECTURE.md]
    local ps = profilesSent[p.tag]
    local full = not ps or now - ps.full > 3600
    local since = (not full) and ps.last or nil
    if full then ps = { full = now }; profilesSent[p.tag] = ps end
    ps.last = now
    -- (las fichas, en el fotograma siguiente: lista y fichas juntas pasaban de 5 ms)
    HU.After(0, function() HU:SendProfilesTo(target, since) end)
    -- (los desconectados ya no se mandan solos; se piden con OQ)
end

---------------------------------------------------------------------------
-- lo de los desconectados y las fichas, a petición [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local oqAsked = {}
-- urgent = alguien lo está mirando (ha elegido Inactivos o Todos): se pide ya y llega antes
function HU:WantOfflineInfo(tag, urgent)
    if not tag or tag == self.myTag or self:IsTest() then return end
    local t = self.db.offlineT and self.db.offlineT[tag]
    if t and time() - t < 12 * 3600 then return end
    if oqAsked[tag] and GetTime() - oqAsked[tag] < (urgent and 60 or 120) then return end
    local p = self:BestPeer(tag)
    if not p then return end
    oqAsked[tag] = GetTime()
    -- (a uno al azar entre su enlace y sus ayudantes: si no, el enlace de cada hermandad tenía
    -- que mandar sus inactivos a las 19 hermandades él solo)
    local pool = { p.name }
    local h = self.helpers and self.helpers[tag]
    if h and GetTime() - h.t < 900 then for _, n in ipairs(h.list) do pool[#pool + 1] = self:FullName(n) end end
    self:Whisper(pool[math.random(#pool)], "OQ~" .. (self.myTag or "") .. "~" .. tag .. "~" .. (urgent and "1" or "0"), true)
end

-- ¿Faltan aún los inactivos de alguna hermandad? (para el aviso "cargando" de la lista) [+ARCHITECTURE.md]
HU:OnStart(function()
    -- (solo el enlace, una hermandad cada 2 minutos y solo si no tiene nada urgente que mandar) [+ARCHITECTURE.md]
    HU.After(math.random() * 120, function() HU.NewTicker(120, function()
        if not HU.myTag or HU:IsTest() or not HU:IsRelay() then return end
        if HU.MainQueueSize and HU:MainQueueSize() > 30 then return end
        for _, tag in ipairs(HU:OtherTags()) do
            local t = HU.db.offlineT and HU.db.offlineT[tag]
            if (not t or time() - t > 12 * 3600) and HU:BestPeer(tag) then
                HU:WantOfflineInfo(tag, false)
                return -- una por vuelta
            end
        end
    end) end)
end)

HU.comm.OQ = function(self, sender, f, dist)
    if dist ~= "WHISPER" or f[2] ~= self.myTag then return end
    -- a cada hermandad, como mucho una vez cada 10 minutos
    self.db.offlineSent = self.db.offlineSent or {}
    local key = f[1] or sender:lower()
    local o = self.db.offlineSent[key]
    if o and time() - o < 600 then return end
    self.db.offlineSent[key] = time()
    self:SendOfflineTo(sender, f[3] == "1")
end

-- "hace 3 h", "hace 2 d"...
---------------------------------------------------------------------------
-- Silenciar en el chat de la comunidad
---------------------------------------------------------------------------
function HU:MuteEntry(name)
    local k = self:Key(name)
    local m = k and self.db.mutes[k]
    if not m or m.u == -1 then return nil end
    if m.u ~= 0 and m.u <= time() then return nil end
    return m
end

function HU:IsMuted(name) return self:MuteEntry(name) ~= nil or self:IsBanned(name) end

-- Texto con lo que le queda: "8 min", "para siempre"
function HU:MuteLeftText(name)
    local m = self:MuteEntry(name)
    if not m then return nil end
    if m.u == 0 then return L("para siempre") end
    local s = m.u - time()
    if s >= 3600 then return math.floor(s / 3600) .. " h " .. math.floor((s % 3600) / 60) .. " min" end
    return math.max(1, math.ceil(s / 60)) .. " min"
end

-- Hora de los silencios y vetos (decide cuál es el más nuevo): la del servidor, igual para todos. [+ARCHITECTURE.md]
local FUTURE_MAX = HU.STAMP_FUTURE
local StampNow, NetStamp = HU.StampNow, HU.NetStamp

-- motivo: sin "~" ni saltos de línea, como mucho 120 letras
function HU.CleanReason(r) return HU.Utf8Cut(HU.Trim((tostring(r or "")):gsub("[~\r\n|]", " ")), 120) end

local function MuteMsg(k, m)
    local secs = (m.u == -1 and -1) or (m.u == 0 and 0) or math.max(1, m.u - time())
    return table.concat({ "MU", m.name or k, secs, m.by or "", m.tag or "", m.t or 0, m.why or "" }, "~")
end

local function ChannelMuteCall(name, on)
    local c = HU.chan.main
    if not c or not c.name or not HU:AmIModFast() then return end
    local fn = C_ChatInfo and (on and C_ChatInfo.ChannelMute or C_ChatInfo.ChannelUnmute)
    if fn then pcall(fn, c.name, HU:Short(name)) end
end

-- Varios silencios seguidos van juntos en un solo mensaje por destino (MZ): con uno por silencio [+ARCHITECTURE.md]
local pendingMutes, muteFlushPlanned = {}, false

local function SendMutes(self, msg)
    -- (con prioridad; la de mi hermandad, la última en meterse y por eso la primera en salir)
    for _, tag in ipairs(self:OtherTags()) do
        local peer = self:BestPeer(tag)
        if peer then self:Whisper(peer.name, msg, true) end
    end
    if self.myTag and IsInGuild() then self:Send(msg, "GUILD", nil, true) end
end

-- un silencio dentro de un MZ:  nombre,segs,autor,etiq,t,motivo
local function MuteEntryText(k, m)
    local secs = (m.u == -1 and -1) or (m.u == 0 and 0) or math.max(1, m.u - time())
    return table.concat({ m.name or k, secs, m.by or "", m.tag or "", m.t or 0,
        (tostring(m.why or ""):gsub("[,;~]", " ")) }, ",")
end
-- varios silencios en los menos MZ posibles (cada uno cabe en un mensaje)
local function PackMutes(entries)
    local out, cur = {}, ""
    for _, en in ipairs(entries) do
        if cur ~= "" and #cur + #en + 4 > 240 then out[#out + 1] = "MZ~" .. cur; cur = "" end
        cur = (cur == "") and en or (cur .. ";" .. en)
    end
    if cur ~= "" then out[#out + 1] = "MZ~" .. cur end
    return out
end

local function FlushMutes()
    muteFlushPlanned = false
    local list = pendingMutes
    pendingMutes = {}
    if #list == 0 then return end
    if #list == 1 then return SendMutes(HU, MuteMsg(list[1].k, list[1].m)) end
    local entries = {}
    for _, it in ipairs(list) do entries[#entries + 1] = MuteEntryText(it.k, it.m) end
    for _, msg in ipairs(PackMutes(entries)) do SendMutes(HU, msg) end
end

function HU:ShareMute(k, m, target)
    if target then return self:Whisper(target, MuteMsg(k, m)) end
    pendingMutes[#pendingMutes + 1] = { k = k, m = m }
    if not muteFlushPlanned then
        muteFlushPlanned = true
        -- (casi al momento: cada décima cuenta frente a un spammer que escribe cada medio segundo;
        -- varios silencios seguidos en el mismo instante se siguen juntando en un mensaje)
        HU.After(0.05, FlushMutes)
    end
end

HU.comm.MZ = function(self, sender, f, dist, raw)
    for en in (f[1] or ""):gmatch("[^;]+") do
        local p = HU.Split(en, ",")
        -- (cada uno como un MU; el reenvío a mi hermandad va una vez, abajo) [+ARCHITECTURE.md]
        HU.comm.MU(self, sender, { p[1], p[2], p[3], p[4], p[5], p[6] }, dist, false)
    end
    if dist == "WHISPER" and raw then self:Send(raw, "GUILD", nil, true) end
end

-- seconds: 0 = para siempre, nil o -1 = quitar el silencio
-- seconds: 0 = para siempre, nil o -1 = quitar el silencio. reason: obligatorio al silenciar
function HU:SetMute(name, seconds, reason)
    if not self:CanPin() then
        self:Print(L("Solo el maestro y los oficiales pueden silenciar."))
        return
    end
    reason = HU.CleanReason(reason)
    if seconds and seconds >= 0 and reason == "" then
        return self:Print(L("Escribe el motivo del silencio."))
    end
    local full = self:FullName(name)
    local k = self:Key(name)
    if not k then return end
    -- (a uno mismo se le puede QUITAR el silencio, no ponerlo)
    if k == self:MeKey() then
        if seconds and seconds >= 0 then return self:Print(L("No puedes silenciarte a ti mismo.")) end
        if not self:MuteEntry(full) then return self:Print(L("No estás silenciado.")) end
    end
    local now, st = time(), StampNow()
    local m = { name = full, by = self:Me(), tag = self.myTag, t = st, why = (reason ~= "") and reason or nil }
    if seconds and seconds >= 0 then
        m.u = (seconds == 0) and 0 or (now + seconds)
    else
        m.u = -1
    end
    -- que el siguiente cambio no empate con este
    local old = self.db.mutes[k]
    if old and (old.t or 0) >= st then m.t = old.t + 1 end
    self.db.mutes[k] = m
    self:ShareMute(k, m)
    ChannelMuteCall(full, m.u ~= -1)
    -- (lo que frena al silenciado va ya; el registro, el aviso y la oferta de castigo, en las
    -- imágenes siguientes, una cosa por imagen: todo junto pasaba de 8 ms)
    local what
    if m.u == -1 then what = L("quitó el silencio a ") .. self:Short(full)
    else what = L("silenció a ") .. self:Short(full) .. L(" en el chat ") .. (m.u == 0 and L("para siempre") or (L("durante ") .. HU.DurationText(seconds))) .. L(". Motivo: ") .. reason end
    local me, myTag = self:Me(), self.myTag
    HU.After(0.02, function() HU:AddAudit({ tag = myTag, actor = me, text = what }, "all") end)
    HU.After(0.04, function() HU:MuteNotice(me, full, m.u == -1 and -1 or (seconds or 0), reason) end)
    if m.u > 0 then
        local stamp = m.t
        HU.After(seconds + 1, function()
            local cur = HU.db.mutes[k]
            if cur and cur.t == stamp then
                ChannelMuteCall(full, false); HU:Changed("members")
                if HU.OfferRestoreRank and not HU:IsMuted(full) then HU:OfferRestoreRank(full) end
            end
        end)
    end
    -- rango de castigo (si la hermandad tiene uno llamado "Castigado")
    HU.After(0.06, function()
        if m.u == -1 then
            if HU.OfferRestoreRank and not HU:IsMuted(full) then HU:OfferRestoreRank(full) end
        elseif HU.OfferPunish then
            HU:OfferPunish(full)
        end
    end)
    self:Changed("members")
end

-- Avisos en el chat de la hermandad cuando se silencia o se veta a alguien
function HU:MuteNotice(by, name, secs, why)
    local who, target = self:Short(by or "?"), self:Short(name or "?")
    if secs == -1 then
        self:ChatNotice(who .. L(" ha quitado el silencio a ") .. target .. ".")
    else
        self:ChatNotice(who .. L(" ha silenciado a ") .. target .. " " .. (secs == 0 and L("para siempre") or (L("durante ") .. HU.DurationText(secs)))
            .. "." .. ((why and why ~= "") and (L(" Motivo: ") .. why) or ""))
    end
end
function HU:BanNotice(by, name, on, why)
    local who, target = self:Short(by or "?"), self:Short(name or "?")
    if on then
        self:ChatNotice(who .. L(" ha vetado del chat a ") .. target .. "." .. ((why and why ~= "") and (L(" Motivo: ") .. why) or ""))
    else
        self:ChatNotice(who .. L(" ha readmitido en el chat a ") .. target .. ".")
    end
end

function HU.DurationText(secs)
    if not secs or secs <= 0 then return L("para siempre") end
    if secs % 86400 == 0 then local d = secs / 86400; return d .. (d == 1 and L(" día") or L(" días")) end
    if secs % 3600 == 0 then local h = secs / 3600; return h .. (h == 1 and L(" hora") or L(" horas")) end
    return math.floor(secs / 60 + 0.5) .. " min"
end

HU.comm.MU = function(self, sender, f, dist, raw)
    local name, secs, by, tag, t = f[1], tonumber(f[2]), f[3], f[4], NetStamp(f[5])
    local why = HU.CleanReason(f[6])
    if not name or name == "" or not secs or not t then return end
    -- lo tiene que mandar un maestro u oficial (si sabemos su rango)
    if not self:CheckOfficer(by ~= "" and by or sender, tag, function() HU.comm.MU(self, sender, f, dist, raw) end, sender, dist) then return end
    local k = self:Key(name)
    local cur = self.db.mutes[k]
    if cur and (cur.t or 0) >= t then return end
    local now = time()
    self.db.mutes[k] = { name = self:FullName(name), by = by, tag = (tag ~= "" and tag) or nil, t = t,
        u = (secs == -1 and -1) or (secs == 0 and 0) or (now + secs), why = (why ~= "") and why or nil }
    if dist == "WHISPER" and raw then self:Send(raw, "GUILD", nil, true) end
    -- aviso en el chat (solo si es de ahora, no al entrar al juego)
    if math.abs(StampNow() - t) < 300 then self:MuteNotice(by, name, secs, why) end
    if k == self:MeKey() then
        if secs == -1 then self:Print(L("|cff44ff44Ya puedes volver a escribir en el chat de ") .. HU:Title() .. ".|r")
        else self:Print("|cffff4444" .. self:Short(by) .. L(" te ha silenciado en el chat de ") .. HU:Title() .. " " .. (secs == 0 and L("para siempre") or (L("durante ") .. HU.DurationText(secs))) .. "."
            .. (why ~= "" and (L(" Motivo: ") .. why) or "") .. "|r") end
    end
    self:Changed("members")
end

---------------------------------------------------------------------------
-- Vetar del chat: no puede volver a entrar aunque esté en la hermandad o tenga la contraseña [+ARCHITECTURE.md]
---------------------------------------------------------------------------
function HU:IsBanned(name)
    local k = self:Key(name)
    local b = k and self.db.bans and self.db.bans[k]
    return b ~= nil and b.on == true
end

local function ChannelBanCall(name, on)
    local c = HU.chan.main
    if not c or not c.name or not HU:AmIMod() then return false end
    local fn = on and (ChannelBan or (C_ChatInfo and C_ChatInfo.ChannelBan)) or (ChannelUnban or (C_ChatInfo and C_ChatInfo.ChannelUnban))
    if fn then pcall(fn, c.name, HU:Short(name)) return true end
    return false
end

local function BanMsg(k, b)
    return table.concat({ "BN", b.name or k, b.on and "1" or "0", b.by or "", b.tag or "", b.t or 0, b.why or "" }, "~")
end

function HU:ShareBan(k, b, target)
    local msg = BanMsg(k, b)
    if target then return self:Whisper(target, msg) end
    if self.myTag and IsInGuild() then self:Send(msg, "GUILD") end
    for _, tag in ipairs(self:OtherTags()) do
        local peer = self:BestPeer(tag)
        if peer then self:Whisper(peer.name, msg) end
    end
end

function HU:SetBan(name, on, reason)
    if not self:CanPin() then return self:Print(L("Solo el maestro y los oficiales pueden vetar.")) end
    reason = HU.CleanReason(reason)
    if on and reason == "" then return self:Print(L("Escribe el motivo del veto.")) end
    local k = self:Key(name)
    if not k then return end
    if k == self:MeKey() then return self:Print(L("No puedes vetarte a ti mismo.")) end
    self.db.bans = self.db.bans or {}
    local old = self.db.bans[k]
    local b = { name = self:FullName(name), on = on and true or false, by = self:Me(), tag = self.myTag,
                t = math.max(StampNow(), (old and old.t or 0) + 1), why = (on and reason ~= "") and reason or nil }
    self.db.bans[k] = b
    self:ShareBan(k, b)
    if on then
        ChannelBanCall(name, true)
        HU.After(0.5, function() HU:KickPlayer(b.name, true, true) end)
    else
        ChannelBanCall(name, false)
    end
    self:AddAudit({ tag = self.myTag, actor = self:Me(),
        text = (on and L("vetó del chat a ") or L("readmitió en el chat a ")) .. self:Short(name) .. (on and (L(". Motivo: ") .. reason) or "") }, "all")
    self:BanNotice(self:Me(), name, on, reason)
    if on and self.KillStreak then self:KillStreak("ban", name) end
    if on and self.OfferPunish then self:OfferPunish(name)
    elseif not on and self.OfferRestoreRank and not self:IsMuted(name) then self:OfferRestoreRank(name) end
    self:Changed("members")
end

HU.comm.BN = function(self, sender, f, dist, raw)
    local name, on, by, tag, t = f[1], f[2] == "1", f[3], f[4], NetStamp(f[5])
    local why = HU.CleanReason(f[6])
    if not name or name == "" or not t then return end
    if not self:CheckOfficer(by ~= "" and by or sender, tag, function() HU.comm.BN(self, sender, f, dist, raw) end, sender, dist) then return end
    self.db.bans = self.db.bans or {}
    local k = self:Key(name)
    local cur = self.db.bans[k]
    if cur and (cur.t or 0) >= t then return end
    self.db.bans[k] = { name = self:FullName(name), on = on, by = by, tag = (tag ~= "" and tag) or nil, t = t, why = (why ~= "") and why or nil }
    if dist == "WHISPER" then self:Send(raw, "GUILD") end
    if math.abs(StampNow() - t) < 300 then self:BanNotice(by, name, on, why) end
    -- si soy moderador del canal, lo aplico yo también
    ChannelBanCall(name, on)
    if k == self:MeKey() then
        self:Print(on and (L("|cffff4444Te han vetado del chat de ") .. HU:Title() .. "." .. (why ~= "" and (L(" Motivo: ") .. why) or "") .. "|r")
            or L("|cff44ff44Te han readmitido en el chat de ") .. HU:Title() .. ".|r")
    end
    self:Changed("members")
end

-- quien entra recibe los silencios activos (junto con el mensaje fijado)
local origPQ = HU.comm.PQ
HU.comm.PQ = function(self, sender, ...)
    if origPQ then origPQ(self, sender, ...) end
    if not self:IsRelay() then return end
    -- (los silencios, juntos en MZ: antes un susurro por cada uno)
    local entries = {}
    for k, m in pairs(self.db.mutes) do
        if self:MuteEntry(k) then entries[#entries + 1] = MuteEntryText(k, m) end
    end
    for _, msg in ipairs(PackMutes(entries)) do self:Whisper(sender, msg) end
    for k, b in pairs(self.db.bans or {}) do self:ShareBan(k, b, sender) end
end

---------------------------------------------------------------------------
-- Echar de la hermandad (y del chat)
---------------------------------------------------------------------------
local seenKicks, myKicks = {}, {}

function HU:CanKickGuild()
    return IsInGuild() and CanGuildRemove and CanGuildRemove() and true or false
end

-- Echar de la hermandad es una acción "protegida": un addon no puede hacerlo por su cuenta [+ARCHITECTURE.md]
function HU.GuildCmd(cmd, name)
    -- "=Nombre": tal cual (el reintento de una invitación con la otra forma del nombre)
    if type(name) == "string" and name:sub(1, 1) == "=" then return "/" .. cmd .. " " .. name:sub(2) end
    -- como se ve en el juego: "Nombre Apellido"
    return "/" .. cmd .. " " .. (HU:Nice(name) or name)
end

-- ¿Puedo echar a este de mi hermandad? (permiso y rango)
function HU:CanKickMember(name)
    if not self:CanKickGuild() then return false, L("No tienes permiso para expulsar de la hermandad.") end
    local _, idx = self:RankInfoOf(name)
    local mine = self:MyRankIndex() or 0
    if idx and idx <= mine then return false, L("No puedes echar a alguien con un rango igual o superior al tuyo.") end
    return true
end

-- después de echarlo de una hermandad, también del canal
function HU:AfterGuildKick(name)
    local k = self:Key(name)
    if self.roster[k] then self.roster[k] = nil end
    for _, W in pairs(self.whitelist) do
        if W.set then W.set[k] = nil end
    end
    HU.After(1, function() HU:KickPlayer(name, false, true) end)
    self:Changed("members")
end

HU.Dialogs["WELOVEPVP_GKICK"] = HU.LT({
    text = "%s",
    button1 = "Aceptar",
    button2 = "Rechazar",
    secure = function(data)
        if data and not HU:IsTest() and HU:CanKickMember(data.target) then return HU.GuildCmd("gremove", data.target) end
    end,
    OnAccept = function(_, data) HU:AnswerKick(data, true) end,
    OnCancel = function(_, data, reason) if reason == "clicked" then HU:AnswerKick(data, false) end end,
    timeout = 300,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
})

-- Echar a varios a la vez (pide confirmación con la lista de nombres)
HU.comm.GK = function(self, sender, f, dist, raw)
    local id, tag, target, requester, reqTag = f[1], f[2], f[3], f[4], f[5]
    if not (id and tag and target and requester) then return end
    if tag ~= self.myTag or seenKicks[id] then return end
    if not self:IsTest() and not self:InAnyGuild(requester) then return end
    -- (antes, cualquiera ponía el nombre de otro como solicitante: ahora lo tiene que traer él o
    -- quien reparte, la etiqueta es la suya de verdad y como mucho 3 peticiones por minuto)
    if not self:MayCarry(requester, sender, dist, reqTag) or not HU.RequestRate(requester) then return end
    reqTag = (self:RankInfoOf(requester)) or reqTag
    seenKicks[id] = true
    if dist == "WHISPER" then self:Send(raw, "GUILD") end
    if not self:CanKickGuild() or not self:InMyGuild(target) then return end
    local text = string.format("|cff33ff99" .. HU:Title() .. L("|r\n\n%s <%s> pide |cffff4444echar de la hermandad|r a |cffffd100%s|r.\n¿Aceptar?"),
        self:Short(requester), reqTag or "?", target)
    HU:ShowDialog("WELOVEPVP_GKICK", text, nil, { id = id, target = target, requester = requester, reqTag = reqTag })
end

function HU:AnswerKick(data, accept)
    if not data then return end
    local ok, why = false, "rechazado"
    if accept then
        local can, why2 = self:CanKickMember(data.target)
        if not can then
            why = why2
        else
            -- (ya lo ha hecho el botón del juego: /gremove)
            ok = true
            self:AfterGuildKick(self:FullName(data.target))
        end
        if not ok then self:Print(L("No se pudo echar a ") .. data.target .. ": " .. why) end
    end
    self:Send("GD~" .. data.id, "GUILD", nil, true)
    self:Whisper(data.requester, table.concat({ "GR", data.id, ok and "ok" or "no", self:Me(), data.target, ok and "" or why }, "~"), true)
    if not accept then
        self:AddAudit({ tag = self.myTag, actor = self:Me(), text = L("rechazó echar a ") .. data.target .. L(" (lo pidió ") .. self:Short(data.requester) .. ")" }, "all")
    end
end

HU.comm.GD = function(self, _, f)
    local id = f[1]
    if not id then return end
    seenKicks[id] = true
    HU:HideDialogs("WELOVEPVP_GKICK", function(d) return d and d.id == id end)
end

HU.comm.GR = function(self, _, f)
    local id, result, who, target, why = f[1], f[2], f[3], f[4], f[5]
    local req = id and myKicks[id]
    if not req then return end
    myKicks[id] = nil
    if result == "ok" then
        self:Print(L("|cff44ff44Hecho:|r ") .. (target or "?") .. L(" ya no está en ") .. self:GuildName(req.tag) .. L(" (lo echó ") .. self:Short(who or "?") .. ").")
        self:AfterGuildKick(req.name)
    else
        self:Print(L("|cffff4444No aplicado:|r ") .. (target or "?") .. " (" .. self:Short(who or "?") .. ": " .. ((why and why ~= "") and why or "rechazado") .. ").")
    end
end

---------------------------------------------------------------------------
-- Historial: lo que se escribió mientras no estabas
---------------------------------------------------------------------------
local HL_MAX = 80
local HL_OFF_MAX = 30
local lateCount, lateTimer = 0, nil

-- Si entran cientos a la vez (reinicio del servidor), contestar a cada uno por separado atascaba [+ARCHITECTURE.md]
local HQ_WAIT = 8      -- segundos que se esperan peticiones antes de mandar
local HQ_GAP = 120     -- entre dos envíos míos a la hermandad
local hqBatch          -- peticiones juntadas: { since, started, off = { [nombre] = desde } }
local lastSent = -999  -- cuándo mandé yo el historial a la hermandad
local lastHeard = -999 -- cuándo pasó por la hermandad el historial de otro
local hashOf = {}

-- Contesta uno solo para toda la hermandad (el mismo para todos los que preguntan). Nunca el [+ARCHITECTURE.md]
local function ResponderBusy(self)
    local busy = {}
    local relay = self:RelayName()
    if relay then busy[relay:lower()] = true end
    local h = self.relayHelpers
    for _, n in ipairs((h and h.list) or self.advertisedHelpers or {}) do
        local k = self:Key(n)
        if k then busy[k] = true end
    end
    return busy
end
local function ResponderRank(k, busy)
    local hv = hashOf[k]
    if not hv then hv = HU.Hash(k); hashOf[k] = hv end
    return busy[k] and 1 or 0, hv
end
-- ¿va (aB, aH) antes que (bB, bH)?
local function RanksBefore(aB, aH, bB, bH)
    return aB < bB or (aB == bB and aH < bH)
end
-- compañeros que cuentan para elegir quién contesta (además de uno mismo)
local function ResponderCandidate(self, k, p, now)
    local r = self.roster[k]
    return now - (p.last or 0) < HU.PEER_TTL and (not r or r.online)
end

-- Los dos mejores (si pregunta el primero, contesta el segundo). Con cientos de compañeros [+ARCHITECTURE.md]
local RESP_EVERY = 2
local respT, respBest, respSecond = -1, nil, nil
local respScan -- { keys, i, busy, best, bestB, bestH, second, secondB, secondH, me, now }
local function RespConsider(s, k)
    local b, hv = ResponderRank(k, s.busy)
    if not s.best or RanksBefore(b, hv, s.bestB, s.bestH) then
        s.second, s.secondB, s.secondH = s.best, s.bestB, s.bestH
        s.best, s.bestB, s.bestH = k, b, hv
    elseif not s.second or RanksBefore(b, hv, s.secondB, s.secondH) then
        s.second, s.secondB, s.secondH = k, b, hv
    end
end
local function RespStart(self)
    local me = self:MeKey()
    if not me then return nil end
    local keys = {}
    for k in pairs(self.guildPeers) do keys[#keys + 1] = k end
    local s = { keys = keys, i = 1, busy = ResponderBusy(self), me = me, now = GetTime() }
    RespConsider(s, me)
    return s
end
-- un trozo; devuelve true al acabar
local function RespStep(self, s, slice)
    local keys, n = s.keys, #s.keys
    local last = slice and math.min(n, s.i + slice - 1) or n
    for i = s.i, last do
        local k = keys[i]
        local p = self.guildPeers[k]
        if p and ResponderCandidate(self, k, p, s.now) then RespConsider(s, k) end
    end
    s.i = last + 1
    if s.i <= n then return false end
    respT, respBest, respSecond = GetTime(), s.best, s.second
    return true
end
-- (cada trozo, como mucho RESP_BUDGET_MS; el primer paso solo prepara la lista, también fuera del
-- HQ: con 500 compañeros, hacer la lista dentro del HQ costaba casi 0,6 ms. Banco, continua-4)
local RESP_BUDGET_MS = 0.4
local function RespTick()
    if respScan == true then
        respScan = RespStart(HU)
        if not respScan then return end
        return HU.After(0, RespTick)
    end
    if not respScan then return end
    local clock = debugprofilestop
    local t0 = clock and clock()
    repeat
        if RespStep(HU, respScan, 20) then respScan = nil return end
    until not t0 or clock() - t0 > RESP_BUDGET_MS
    HU.After(0, RespTick)
end
local function IsResponder(self, sender)
    local me, skip, now = self:MeKey(), sender:lower(), GetTime()
    if not me then return false end
    if not respBest then
        -- (la primera vez, de una vez)
        local s = RespStart(self)
        if not s then return false end
        RespStep(self, s, nil)
    elseif now - respT >= RESP_EVERY and not respScan then
        -- (se vuelve a calcular por trozos; mientras tanto vale el anterior)
        respScan = true
        HU.After(0, RespTick)
    end
    if respBest ~= skip then return respBest == me end
    return respSecond == me
end

-- Seguridad: ¿puede este compañero mandarme por la hermandad lo de «mientras no estabas»? [+ARCHITECTURE.md]
local hqSeenT = -999
local HL_WINDOW = 300
local HL_RANK_MARGIN = 3
local hlVerdict = {} -- [clave] = { t, ok }  (llegan hasta 80 líneas seguidas del mismo)
local hqAskers = {}  -- [clave] = cuándo pidió el historial (quien pregunta nunca contesta)
-- Con el mismo orden que IsResponder: cuántos van por delante del que manda. No cuentan ni
-- uno mismo ni los que acaban de preguntar (IsResponder se los salta).
local function HLRankOK(self, sk)
    local now = GetTime()
    local busy = ResponderBusy(self)
    local sB, sH = ResponderRank(sk, busy)
    local me, above = self:MeKey(), 0
    for k, p in pairs(self.guildPeers) do
        if k ~= sk and k ~= me and ResponderCandidate(self, k, p, now)
            and not (hqAskers[k] and now - hqAskers[k] < HL_WINDOW) then
            local b, hv = ResponderRank(k, busy)
            if RanksBefore(b, hv, sB, sH) then
                above = above + 1
                if above >= HL_RANK_MARGIN then return false end
            end
        end
    end
    return true
end
local function HLSourceOK(self, sender)
    if GetTime() - hqSeenT > HL_WINDOW then return false end
    local sk = self:Key(sender)
    if not sk then return false end
    local v = hlVerdict[sk]
    if v and GetTime() - v.t < 10 then return v.ok end
    local ok = self:IsGuildForwarder(sender) or HLRankOK(self, sk)
    hlVerdict[sk] = { t = GetTime(), ok = ok }
    return ok
end
function HU:NoteHistoryAsked() hqSeenT = GetTime() end

local function HLLine(e)
    local head = table.concat({ "HL", e.t, e.k or "main", e.tag or "", e.a or "" }, "~") .. "~"
    return head .. HU.Utf8Cut((e.m or ""):gsub("[\r\n]", " "), 255 - #head)
end

function HU:FlushHistoryBatch()
    local b = hqBatch
    hqBatch = nil
    if not b then return end
    -- si otro ya lo mandó a la hermandad después de llegar estas peticiones, les ha llegado a todos
    local skipMain = lastHeard > b.started
    local main, off = {}, {}
    for _, e in ipairs(self.db.history) do
        if (e.t or 0) > b.since and e.a then
            if e.k == "off" then off[#off + 1] = e
            elseif not skipMain then main[#main + 1] = e end
        end
    end
    if #main > 0 then
        lastSent = GetTime()
        for i = math.max(1, #main - HL_MAX + 1), #main do self:Send(HLLine(main[i]), "GUILD") end
    end
    -- lo de oficiales nunca va por la hermandad: solo a cada oficial que lo pidió
    for name, since in pairs(b.off) do
        local list = {}
        for _, e in ipairs(off) do
            if e.t > since and e.a:lower() ~= name:lower() then list[#list + 1] = e end
        end
        for i = math.max(1, #list - HL_OFF_MAX + 1), #list do self:Whisper(name, HLLine(list[i])) end
    end
end

HU.comm.HQ = function(self, sender, f, dist)
    if dist ~= "GUILD" then return end
    local since = tonumber(f[1])
    if not since then return end
    hqSeenT = GetTime()
    local ak = self:Key(sender)
    if ak then hqAskers[ak] = hqSeenT end
    if not IsResponder(self, sender) then return end
    local b = hqBatch
    if not b then
        local now = GetTime()
        b = { since = since, started = now, off = {} }
        hqBatch = b
        HU.After(math.max(HQ_WAIT, lastSent + HQ_GAP - now), function() HU:FlushHistoryBatch() end)
    end
    if since < b.since then b.since = since end
    -- (lo de oficiales, solo si quien lo pide es oficial: antes se miraba solo al que contesta, y
    -- un raso recibía 30 líneas del chat de oficiales)
    local re = self.roster[self:Key(sender) or ""]
    if f[2] == "1" and self:CanOfficer() and re and self:RankRole(self.myTag, re.rankIndex) then
        b.off[sender] = math.min(b.off[sender] or since, since)
    end
end

-- Texto de otro, listo para guardar: se juntan antes las | seguidas, así sale igual aunque llegue
-- ya limpio (SafeText dobla cada | suelta, y en cada salto la línea cambiaba)
local function SafeRemote(s)
    return HU.SafeText((tostring(s or ""):gsub("|+", "|")), true)
end
-- Lo que se compara para ver si ya la tengo: las | sin doblar y solo el principio (al viajar se
-- corta el final de los mensajes largos)
local HL_KEY_LEN = 120
local function MatchText(s)
    s = s or ""
    if s:find("|", 1, true) then s = s:gsub("|+", "|") end
    return HU.Utf8Cut(s, HL_KEY_LEN)
end

-- (antes solo se miraban las 400 últimas: con mucho chat, una línea de hace 10-20 min ya estaba más [+ARCHITECTURE.md]
local function HasEntry(h, t, a, m)
    local key
    local lo, hi = 1, #h
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if (h[mid].t or 0) <= t + 180 then lo = mid else hi = mid - 1 end
    end
    for i = hi, 1, -1 do
        local e = h[i]
        local et = e.t or 0
        if et < t - 180 then break end
        if e.a == a and et <= t + 180 then
            if e.m == m then return true end
            key = key or MatchText(m)
            if MatchText(e.m) == key then return true end
        end
    end
    return false
end

HU.comm.HL = function(self, sender, f, dist)
    -- llega a toda la hermandad (lo de todos) o por susurro (lo de oficiales)
    if dist ~= "WHISPER" and dist ~= "GUILD" then return end
    -- solo lo manda alguien de mi hermandad (contesta a la petición de alguien al entrar)
    local sk = self:Key(sender)
    if not (sk and self.roster[sk]) then return end
    if dist == "GUILD" and not self:IsTest() and not HLSourceOK(self, sender) then
        if self.Debug then self:Debug("Historial rechazado (no le toca contestar):", sender) end
        return
    end
    if dist == "GUILD" then lastHeard = GetTime() end
    local t, k, tag, a = HU.NetT(f[1]), f[2], f[3], f[4]
    if not t or not a or a == "" then return end
    if k ~= "main" and k ~= "lfg" and k ~= "off" then return end
    if k == "off" and dist == "GUILD" then return end
    if k == "off" and not self:CanOfficer() then return end
    if k == "off" and not self:RankRole(self.myTag, self.roster[sk].rankIndex) then return end
    a = HU.SafeName(a) and self:FullName(a)
    if not a then return end
    -- el mensaje puede llevar "~": se vuelve a juntar
    local m = SafeRemote(table.concat(f, "~", 5))
    local h = self.db.history
    if HasEntry(h, t, a, m) or self:IsMuted(a) then return end
    local entry = { t = t, k = k, tag = (tag ~= "" and tag) or nil, a = a, m = m, late = true }
    local pos = #h + 1
    while pos > 1 and (h[pos - 1].t or 0) > t do pos = pos - 1 end
    table.insert(h, pos, entry)
    while #h > 3000 do table.remove(h, 1) end
    lateCount = lateCount + 1
    if lateTimer then return end
    lateTimer = true
    HU.After(3, function()
        lateTimer = nil
        local n = lateCount
        lateCount = 0
        HU:ShowLate(n)
    end)
end

-- Escribe en las pestañas del chat del juego lo que llegó mientras no estabas
function HU:ShowLate(n)
    if n <= 0 then return end
    local shown = {}
    local h = self.db.history
    for i = math.max(1, #h - 400), #h do
        local e = h[i]
        if e.late then
            e.late = nil
            shown[#shown + 1] = e
        end
    end
    -- en el chat del juego solo si se ha activado la opción; en el panel se ve siempre
    if not self.db.loginHistory then
        if self.UI and self.UI.FillChat then self.UI:FillChat() end
        return
    end
    local header = {}
    for _, e in ipairs(shown) do
        for _, fr in ipairs(self:FramesFor(e.k)) do
            if not header[fr] then
                header[fr] = true
                fr:AddMessage(L("|cff9a8f78— Mientras no estabas (") .. n .. ") —|r")
            end
            local r, g, b = self:KindColor(e.k)
            fr:AddMessage("|cff9a8f78" .. date("%H:%M", e.t) .. "|r " .. self:FormatLine(e.k, e.tag, e.a, self:HighlightMentions(e.m or "")), r, g, b)
        end
    end
    if self.UI and self.UI.FillChat then self.UI:FillChat() end
end

-- Al entrar: el chat no sale en blanco, se ve lo último que se escribió
function HU:RestoreChat()
    if not self.db.loginHistory then return end
    local h = self.db.history
    local per, count, shown = 15, {}, {}
    for i = #h, 1, -1 do
        local e = h[i]
        local k = e.k or "main"
        if (k ~= "off" or self:CanOfficer() or self:IsTest()) and (count[k] or 0) < per then
            count[k] = (count[k] or 0) + 1
            table.insert(shown, 1, e)
        end
        if (count.main or 0) >= per and (count.lfg or 0) >= per and (count.off or 0) >= per then break end
    end
    if #shown == 0 then return end
    local header = {}
    for _, e in ipairs(shown) do
        for _, fr in ipairs(self:FramesFor(e.k)) do
            if not header[fr] then
                header[fr] = true
                fr:AddMessage(L("|cff9a8f78— Historial del chat de ") .. HU:Title() .. " —|r")
            end
            local r, g, b = self:KindColor(e.k)
            if e.sys then
                fr:AddMessage("|cff9a8f78" .. HU.SafeDate("%d/%m %H:%M", e.t) .. "|r |cffffd100" .. (e.m or "") .. "|r")
            else
                fr:AddMessage("|cff9a8f78" .. HU.SafeDate("%d/%m %H:%M", e.t) .. "|r " .. self:FormatLine(e.k, e.tag, e.a or "?", self:HighlightMentions(e.m or "")), r * 0.8, g * 0.8, b * 0.8)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Arranque
---------------------------------------------------------------------------
HU:OnStart(function()
    local since = HU.db.lastSeen
    HU.db.lastSeen = time()
    HU.NewTicker(30, function() HU.db.lastSeen = time() end)
    -- limpiar lo viejo (así lo guardado no crece sin parar y el juego carga más rápido al entrar)
    local now = time()
    local db, adb = HU.db, HU.adb or {}
    adb.history, adb.myRecipes, db.myRecipes, db.recipes = nil, nil, nil, nil -- (de versiones de antes)
    for k, p in pairs(db.profiles or {}) do if now - (p.t or 0) > 30 * 86400 then db.profiles[k] = nil end end
    for k, c in pairs(db.rankCache or {}) do if now - (c.t or 0) > 14 * 86400 then db.rankCache[k] = nil end end
    for tag, t in pairs(db.offlineT or {}) do
        if now - (t or 0) > 2 * 86400 then db.offline[tag] = nil; db.offlineT[tag] = nil end
    end
    -- limpiar vetos levantados hace más de 30 días (antes se guardaban y se reenviaban para siempre) [+ARCHITECTURE.md]
    local sNow = StampNow()
    for k, b in pairs(HU.db.bans or {}) do
        if (b.t or 0) > sNow + FUTURE_MAX then b.t = sNow end
        if not b.on and sNow - (b.t or 0) > 30 * 86400 then HU.db.bans[k] = nil end
    end
    -- limpiar silencios caducados
    for k, m in pairs(HU.db.mutes) do
        if (m.t or 0) > sNow + FUTURE_MAX then m.t = sNow end
        if (m.u == -1 and sNow - (m.t or 0) > 86400 * 3) or (m.u and m.u > 0 and m.u < time() - 86400) then HU.db.mutes[k] = nil end
    end
    HU.After(6, function() HU:RestoreChat() end)
    HU.After(12, function() HU:UpdateMyProfile(true) end)
    HU.NewTicker(120, function() HU:UpdateMyProfile() end)
    -- lo escrito mientras no estabas (si hace más de un minuto)
    HU.After(25, function()
        if since and time() - since > 60 and HU.myTag and IsInGuild() then
            HU:NoteHistoryAsked()
            HU:Send(table.concat({ "HQ", since, HU:CanOfficer() and "1" or "0" }, "~"), "GUILD")
        end
    end)
    -- el enlace repasa con las otras hermandades los silencios y vetos de la suya cada 5 min. Con [+ARCHITECTURE.md]
    local resync = {} -- [etiqueta] = { sig, peer, t }
    HU.NewTicker(300, function()
        if not HU.myTag or not HU:IsRelay() then return end
        -- (solo los de oficiales de mi hermandad: los de otra los reparte su enlace, que es de quien
        -- los aceptan las demás; y de los vetos, los vigentes o levantados hace menos de 3 días)
        local entries, bans, sig = {}, {}, {}
        for k, m in pairs(HU.db.mutes) do
            if HU:MuteEntry(k) and (not m.tag or m.tag == HU.myTag) then
                entries[#entries + 1] = MuteEntryText(k, m)
                sig[#sig + 1] = k .. ":" .. tostring(m.u) .. ":" .. tostring(m.t)
            end
        end
        for k, b in pairs(HU.db.bans or {}) do
            if (not b.tag or b.tag == HU.myTag) and (b.on or StampNow() - (b.t or 0) < 3 * 86400) then
                bans[#bans + 1] = BanMsg(k, b)
                sig[#sig + 1] = "~" .. k .. ":" .. tostring(b.on) .. ":" .. tostring(b.t)
            end
        end
        if #sig == 0 then return end
        table.sort(sig)
        local s = table.concat(sig, ",")
        local msgs = PackMutes(entries)
        for _, tag in ipairs(HU:OtherTags()) do
            local peer = HU:BestPeer(tag)
            local r = resync[tag]
            if peer and (not r or r.sig ~= s or r.peer ~= peer.name:lower() or GetTime() - r.t > 1800) then
                resync[tag] = { sig = s, peer = peer.name:lower(), t = GetTime() }
                for _, msg in ipairs(msgs) do HU:Whisper(peer.name, msg, false, true) end
                for _, msg in ipairs(bans) do HU:Whisper(peer.name, msg, false, true) end
            end
        end
    end)
end)

HU:On("PLAYER_LOGOUT", function() if HU.db then HU.db.lastSeen = time() end end)
HU:On("CHARACTER_POINTS_CHANGED", function() HU.After(1, function() HU:UpdateMyProfile() end) end)
HU:On("SKILL_LINES_CHANGED", function() HU.After(2, function() HU:UpdateMyProfile() end) end)

---------------------------------------------------------------------------
-- Órdenes que escribes tú
---------------------------------------------------------------------------
-- Comandos (de una o varias líneas: echar, ascender, degradar) que tienes que escribir tú en el [+ARCHITECTURE.md]
function HU:TypeLines(macro, title)
    local lines = {}
    for line in tostring(macro or ""):gmatch("[^\r\n]+") do
        line = HU.Trim(line)
        if line ~= "" then lines[#lines + 1] = line end
    end
    if #lines == 0 then return end
    self:RunOrders({ title = title or L("Órdenes de hermandad"), text = lines[1] .. (#lines > 1 and (" (+" .. (#lines - 1) .. ")") or ""), lines = lines })
end
