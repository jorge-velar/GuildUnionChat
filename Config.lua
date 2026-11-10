-- Guild Union - lectura de la configuración desde la Información de hermandad
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

HU.ADDON_TITLE = "Guild Union"

function HU.CleanTitle(t)
    t = HU.Trim((tostring(t or "")):gsub("[%%|~:\r\n]", ""))
    if #t > 40 then t = HU.Utf8Cut(t, 40) end
    return t
end

-- Título de la comunidad: la línea GU:t:Nombre, o si no, la primera hermandad de la lista
function HU:Title()
    local cfg = self.cfg
    if cfg then
        if cfg.title and cfg.title ~= "" then return cfg.title end
        if cfg.guilds and cfg.guilds[1] then return HU.CleanTitle(cfg.guilds[1].name) end
    end
    return HU.ADDON_TITLE
end

-- GU:v:5.4.8 en la Información de la hermandad: versión mínima del addon (solo cifras y puntos)
function HU.ParseMinVersion(text)
    for raw in (text or ""):gmatch("[^\r\n]+") do
        local v = HU.Trim(raw):match("^[Gg][Uu]:[Vv]:%s*([%d%.]+)%s*$")
        if v and #v < 12 then return v end
    end
    return nil
end

-- Líneas GU: pegadas («GU:t:NombreGU:g:...», p. ej. de una nota de oficial cortada): cada una en la suya
function HU.SplitGlued(text)
    return (tostring(text or ""):gsub("([^\r\n])[ \t]*([Gg][Uu]:%a:)", "%1\n%2"))
end

-- Función pura (sin API del juego) para poder probarla fuera del juego
function HU.ParseConfigText(text)
    local cfg = { guilds = {}, byTag = {}, byName = {}, errors = {} }
    local exact = {}
    local found = false
    local function err(msg) table.insert(cfg.errors, msg) end

    for raw in HU.SplitGlued(text):gmatch("[^\r\n]+") do
        local line = HU.Trim(raw)
        -- vale "GU:c:..." y también el formato antiguo "HU:c:..."
        local kind, rest = line:match("^[Gg][Uu]:(%a):(.*)$")
        if not kind then kind, rest = line:match("^[Ww][Ll][Pp]:(%a):(.*)$") end
        if not kind then kind, rest = line:match("^[Hh][Uu]:(%a):(.*)$") end
        if kind then
            found = true
            kind = kind:lower()
            if kind == "c" then
                local name, pass = rest:match("^([^:]*):?(.*)$")
                name, pass = HU.Trim(name), HU.Trim(pass)
                if name == "" then
                    err(L("Falta el nombre del canal en la línea GU:c"))
                elseif not name:match("^[%w]+$") then
                    err(L("El nombre del canal solo puede tener letras y números: ") .. name)
                elseif #name > 26 then
                    -- (el juego admite 31 letras y el carril le añade 5: LaneSuffix en Channel.lua)
                    err(L("El nombre del canal es demasiado largo (como mucho 26 letras)"))
                else
                    cfg.channel = name
                    cfg.password = (pass ~= "") and pass or nil
                end
            elseif kind == "t" then
                -- nombre de la comunidad (título del panel). Si no está, el de la primera hermandad
                local t = HU.CleanTitle(rest)
                if t ~= "" then cfg.title = t end
            elseif kind == "e" then
                -- eco en /g (Echo.lua): GU:e:1 lo enciende para esta hermandad
                cfg.echo = HU.Trim(rest) == "1"
            elseif kind == "n" then
                -- cuántas líneas de la comunidad hay en notas de oficial (para pedirlas)
                cfg.noteLines = tonumber(rest:match("^(%d+)"))
            elseif kind == "r" then
                local tag, n = rest:match("^(%w+):(%d+)$")
                if tag and tonumber(n) then
                    cfg.officerMax = cfg.officerMax or {}
                    cfg.officerMax[tag:upper()] = tonumber(n)
                else
                    err(L("Línea GU:r no válida (ej.: GU:r:HU1:2): ") .. line)
                end
            elseif kind == "g" then
                local gname, tag = rest:match("^(.*):([^:]*)$")
                gname, tag = HU.Trim(gname), HU.Trim(tag):upper()
                if gname == "" or tag == "" then
                    err(L("Línea GU:g incompleta: ") .. line)
                elseif not tag:match("^%w+$") or #tag > 6 then
                    err(L("Etiqueta no válida (hasta 6 letras o números): ") .. tag)
                elseif cfg.byTag[tag] then
                    err(L("Etiqueta repetida: ") .. tag)
                elseif exact[gname] then
                    err(L("Hermandad repetida: ") .. gname)
                else
                    local g = { name = gname, tag = tag }
                    table.insert(cfg.guilds, g)
                    cfg.byTag[tag] = g
                    cfg.byName[gname:lower()] = g
                    exact[gname] = true
                end
            end
        end
    end

    if not found then return nil end
    if not cfg.channel then
        cfg.missingChannel = true
        err(L("Falta el canal: pon GU:c:Canal:clave en la nota de oficial del maestro"))
    end
    if #cfg.guilds == 0 then err(L("Falta al menos una línea GU:g:Nombre:ETIQ")) end
    cfg.ok = (#cfg.errors == 0)
    return cfg
end

-- GU:c:Canal:clave en una nota de oficial (así la contraseña no la ve cualquiera) [+ARCHITECTURE.md]
function HU.ParseChannelNote(note)
    if type(note) ~= "string" then return nil end
    local name, pass, e = note:match("[Gg][Uu]:[Cc]:(%w+):?(%w*)()")
    if not name then name, pass, e = note:match("[Ww][Ll][Pp]:[Cc]:(%w+):?(%w*)()") end
    if not name then
        if note:find("[Gg][Uu]:[Cc]:") or note:find("[Ww][Ll][Pp]:[Cc]:") then return nil, nil, true end
        return nil
    end
    local after = note:sub(e, e)
    if after ~= "" and not after:match("%s") then return nil, nil, true end
    return name, (pass ~= "" and pass or nil)
end

function HU.ParseOfficerNote(note)
    if type(note) ~= "string" then return nil end
    local name, pass = note:match("[Gg][Uu]:[Oo]:(%w+):?(%S*)")
    if not name then name, pass = note:match("[Ww][Ll][Pp]:[Oo]:(%w+):?(%S*)") end
    if not name then name, pass = note:match("[Hh][Uu]:[Oo]:(%w+):?(%S*)") end
    if not name then return nil end
    return name, (pass ~= "" and pass or nil)
end

local lastKey
local lastErrors
local INFO_WAIT, infoRetry = 45, false

-- El canal y la contraseña: los reparte el addon desde la nota de oficial (lo más nuevo manda).
-- Si alguien los sigue teniendo en la Información de hermandad, valen hasta que llegue lo de la nota.
local function UseNetChannel(cfg, net)
    cfg.chanInInfo = cfg.channel ~= nil
    if not (net and net.channel) then return end
    cfg.channel, cfg.password = net.channel, net.pass
    cfg.chanFromNote = true
    if cfg.missingChannel then
        for i = #cfg.errors, 1, -1 do
            if cfg.errors[i]:find(L("Falta el canal"), 1, true) then table.remove(cfg.errors, i) end
        end
        cfg.ok = (#cfg.errors == 0)
    end
end

-- Arranque rápido: al entrar, el juego tarda unos segundos en dar la Información de hermandad y la [+ARCHITECTURE.md]
function HU:QuickConfig()
    if self:IsTest() or self.cfg or not IsInGuild() then return false end
    local q = self.db.quickCfg
    if type(q) ~= "table" or type(q.text) ~= "string" or type(q.guild) ~= "string" then return false end
    -- (si el juego ya dice la hermandad y no es la de entonces, no vale. Si es la misma, vale [+ARCHITECTURE.md]
    local gname = GetGuildInfo("player")
    if gname and gname ~= q.guild then return false end
    if not gname and time() - (tonumber(q.t) or 0) > 7 * 86400 then return false end
    local cfg = HU.ParseConfigText(q.text)
    if not cfg then return false end
    if self.MergeNetGuilds then self:MergeNetGuilds(cfg) end
    UseNetChannel(cfg, self.db.netChan)
    local mine = cfg.byName[q.guild:lower()]
    if not cfg.ok or not cfg.channel or not mine then return false end
    cfg.quick = true
    self.cfg, self.myTag, self.guildName = cfg, mine.tag, q.guild
    self:Debug("Arranque rápido con la configuración guardada. Canal:", cfg.channel)
    self:ApplyChannels()
    self:Changed("config")
    return true
end

function HU:RefreshConfig(force)
    if not IsInGuild() then
        self:Debug("Sin hermandad")
        if self.SetGuildMin then self:SetGuildMin(nil) end
        self.cfg, self.myTag, self.guildName = nil, nil, nil
        lastKey = nil
        self:ApplyChannels()
        self:Changed("config")
        return
    end

    local gname = GetGuildInfo("player")
    if not gname then return end -- todavía no ha cargado
    local text = self:GuildInfoText()
    if not text then return end -- (restricción del juego: se mantiene lo que había)
    -- al entrar, el juego da la Información vacía unos segundos: se espera a que llegue (antes se tiraba
    -- de la copia guardada o recibida, que podía ser vieja, y salían errores falsos que luego se iban)
    if not text:find("%S") and GetTime() - (HU.loginT or GetTime()) < INFO_WAIT then
        if not infoRetry then
            infoRetry = true
            HU.After(3, function() infoRetry = false; HU:RefreshConfig() end)
        end
        return
    end
    -- (versión mínima: solo de la Información de MI hermandad, tal cual, antes de juntarle nada)
    if self.SetGuildMin then self:SetGuildMin(HU.ParseMinVersion(text)) end
    -- (versiones de antes guardaban esto para toda la cuenta: pasa a este personaje solo si es
    -- de su hermandad)
    local cdb, adb = self.cdb, self.adb
    if cdb and adb and not cdb.migrated then
        cdb.migrated = true
        if adb.netCfg and adb.netCfg.guild == gname then cdb.netCfg = adb.netCfg end
        if adb.infoBackup and adb.infoBackup.guild == gname then cdb.infoBackup = adb.infoBackup end
        local c0 = HU.ParseConfigText(text)
        if adb.netChan and c0 and c0.byName[gname:lower()] and c0.byTag[adb.netChan.tag or ""] then cdb.netChan = adb.netChan end
        if adb.pinned and c0 and c0.byName[gname:lower()] then cdb.pinned = adb.pinned end
        if type(adb.extraChans) == "table" and next(adb.extraChans) and c0 then cdb.extraChans = adb.extraChans end
    end
    -- recién unida a la comunidad: el juego puede tardar en devolver la Información nueva
    if self.joinedText and not HU.ParseConfigText(text) then text = self.joinedText end
    -- más líneas de la comunidad en las notas de oficial (las leen los oficiales y las reparten)
    -- (copia de lo que el juego no dejó escribir en la Información: ver CheckInfoWritten)
    local bk = self.db.infoBackup
    if bk and bk.guild == gname and not text:find("[Gg][Uu]:[Gg]:") then text = bk.text end
    local nc = self.db.netCfg
    if nc and nc.guild and nc.guild ~= gname then nc = nil end -- (era de otra hermandad)
    local extra = self.noteCfgText or (nc and nc.text)
    if extra and HU.MergeConfigText then text = HU.MergeConfigText(text, extra) end
    local net = self.db.netChan
    local key = gname .. "\0" .. text .. "\0" .. (net and (net.channel .. (net.pass or "") .. (net.t or 0)) or "")
        .. "\0" .. (self.NetGuildsKey and self:NetGuildsKey() or "")
    if not force and key == lastKey then return end
    lastKey = key

    self.guildName = gname
    local cfg = HU.ParseConfigText(text)
    if cfg and self.MergeNetGuilds then self:MergeNetGuilds(cfg) end
    if not cfg then
        -- (recién entrado con la configuración guardada: la Información de hermandad aún puede venir
        -- vacía. No se sale del canal por eso en los primeros 30 s)
        if self.cfg and self.cfg.quick and GetTime() - (HU.loginT or 0) < 30 then return end
        self.cfg, self.myTag = nil, nil
        self:Debug("Sin configuración HU en la Información de hermandad")
        self:ApplyChannels()
        self:Changed("config")
        return
    end

    UseNetChannel(cfg, net)

    local mine = cfg.byName[gname:lower()]
    if not mine then
        table.insert(cfg.errors, L("Tu hermandad (") .. gname .. L(") no aparece en ninguna línea GU:g"))
        cfg.ok = false
    end
    self.cfg = cfg
    self.myTag = mine and mine.tag or nil

    -- solo falta el canal: no es un error, llegará de un oficial conectado
    local onlyWaiting = cfg.missingChannel and not cfg.chanFromNote and #cfg.errors == 1
    if onlyWaiting then
        self:Debug("Esperando a que un oficial pase el canal")
    elseif not cfg.ok then
        local errText = table.concat(cfg.errors, " | ")
        if errText ~= lastErrors then
            lastErrors = errText
            self:Print(L("|cffff4444Hay errores en la configuración:|r"))
            for _, e in ipairs(cfg.errors) do self:Print("  - " .. e) end
        end
    else
        lastErrors = nil
        self:Debug("Config OK. Canal:", cfg.channel, "Hermandades:", #cfg.guilds, "Mi etiqueta:", self.myTag)
        -- (para el arranque rápido de la próxima vez; solo se escribe si ha cambiado)
        local q = self.db.quickCfg
        if mine and cfg.channel and (type(q) ~= "table" or q.text ~= text or q.guild ~= gname or time() - (q.t or 0) > 86400) then
            self.db.quickCfg = { guild = gname, text = text, t = time() }
        end
    end
    self:ApplyChannels()
    self:Changed("config")
end

function HU:OtherTags()
    local out = {}
    if not self.cfg then return out end
    for _, g in ipairs(self.cfg.guilds) do
        if g.tag ~= self.myTag then out[#out + 1] = g.tag end
    end
    return out
end

---------------------------------------------------------------------------
-- Nombre y color de cada hermandad (para el chat y el panel)
---------------------------------------------------------------------------
local GUILD_COLORS = {
    { 0.20, 1.00, 0.60 }, { 0.40, 0.72, 1.00 }, { 1.00, 0.70, 0.30 },
    { 0.90, 0.50, 0.95 }, { 1.00, 0.90, 0.40 }, { 0.45, 1.00, 0.95 },
    { 1.00, 0.50, 0.50 }, { 0.70, 0.90, 0.40 },
}

function HU:GuildColor(tag)
    -- color elegido por los oficiales (se reparte a todos)
    local c = tag and self.db and self.db.guildColors and self.db.guildColors[tag]
    if c and c.hex then
        local r, g, b = tonumber(c.hex:sub(1, 2), 16), tonumber(c.hex:sub(3, 4), 16), tonumber(c.hex:sub(5, 6), 16)
        if r and g and b then return r / 255, g / 255, b / 255 end
    end
    if self.cfg and tag then
        for i, g in ipairs(self.cfg.guilds) do
            if g.tag == tag then
                local c = GUILD_COLORS[((i - 1) % #GUILD_COLORS) + 1]
                return c[1], c[2], c[3]
            end
        end
    end
    return 0.8, 0.8, 0.8
end

function HU:GuildColorHex(tag)
    local r, g, b = self:GuildColor(tag)
    return string.format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

function HU:GuildName(tag)
    local g = self.cfg and tag and self.cfg.byTag[tag]
    return g and g.name or (tag or "")
end

---------------------------------------------------------------------------
-- Maestro y oficiales
---------------------------------------------------------------------------
-- Rangos de oficial: del 1 al N (por defecto solo el 1). Se cambia con GU:r:ETIQ:N
function HU:OfficerMax(tag)
    return (self.cfg and self.cfg.officerMax and tag and self.cfg.officerMax[tag]) or 1
end

-- "gm", "officer" o nil
function HU:RankRole(tag, rankIndex)
    if rankIndex == nil then return nil end
    if rankIndex == 0 then return "gm" end
    if rankIndex <= self:OfficerMax(tag) then return "officer" end
    return nil
end

-- maestro: corona; oficiales: dos espadas cruzadas; moderadores del canal: las espadas en rojo [+ARCHITECTURE.md]
HU.ICON_GM = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:15:15:0:-1|t"
HU.ICON_OFFICER = "|TInterface\\CharacterFrame\\UI-StateIcon:16:16:0:-1:64:64:34:62:2:30|t"
HU.ICON_MOD = "|TInterface\\CharacterFrame\\UI-StateIcon:16:16:0:-1:64:64:34:62:2:30:255:70:60|t"
HU.MOD_COLOR = { 1, 0.27, 0.24 }
HU.SWORDS_COORDS = { 34 / 64, 62 / 64, 2 / 64, 30 / 64 }

function HU:RoleIcon(role)
    if role == "gm" then return self.ICON_GM end
    if role == "mod" then return self.ICON_MOD end
    if role == "officer" then return self.ICON_OFFICER end
    return ""
end

-- ¿Es moderador del canal del chat unido? (lo dice su addon al saludar, o lo veo en el canal)
function HU:IsChannelMod(name)
    local k = self:Key(name)
    if not k then return false end
    -- (la forma rápida: la completa monta la lista entera del canal, y esto se mira al pintar)
    if k == self:MeKey() then return self.AmIModFast and self:AmIModFast() or false end
    if self.chanMods and self.chanMods[k] then return true end
    local p = (self.guildPeers and self.guildPeers[k]) or (self.remote and self.remote[k])
    return p and p.mod and true or false
end

-- "gm", "mod" (oficial y moderador del canal), "officer" o nil, para un jugador concreto
function HU:RoleOf(name, tag, rankIndex)
    local role = self:RankRole(tag, rankIndex)
    if role ~= "gm" and name and self:IsChannelMod(name) then return "mod" end
    return role
end

-- Pone la corona o las espadas en una textura (las filas de la lista) [+ARCHITECTURE.md]
local rankMemo, rankMemoN, RANK_MEMO_SECS = {}, 0, 5
local RankInfoSlow
function HU:RankInfoOf(name)
    local k = self:Key(name)
    if not k then return nil end
    local e = self.roster[k]
    if e then return self.myTag, e.rankIndex end
    local now = GetTime()
    local m = rankMemo[k]
    if m and now - m.t < RANK_MEMO_SECS then return m.tag, m.idx end
    local tag, idx = RankInfoSlow(self, k)
    if rankMemoN > 2000 then rankMemo, rankMemoN = {}, 0 end
    if not m then rankMemoN = rankMemoN + 1 end
    rankMemo[k] = { t = now, tag = tag, idx = idx }
    return tag, idx
end
function RankInfoSlow(self, k)
    for tag, r in pairs(self.remoteRoster) do
        local m = r.byKey and r.byKey[k]
        if m and not m.weak then return tag, m.rankIndex end
        if not r.byKey then
            for _, m2 in ipairs(r.members) do
                if m2.name:lower() == k and not m2.weak then return tag, m2.rankIndex end
            end
        end
    end
    -- rangos vistos antes (se guardan entre sesiones, valen 7 días)
    local c = self.db and self.db.rankCache and self.db.rankCache[k]
    if c and time() - (c.t or 0) < 7 * 86400 and self.whitelist[c.tag] and self.whitelist[c.tag].set[k] then
        return c.tag, c.idx
    end
    return nil
end
