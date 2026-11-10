-- Guild Union - añadir y quitar hermandades de la comunidad desde el panel de oficiales
local _, HU = ...
local L = HU.L

-- (descripción del protocolo y detalles: ARCHITECTURE.md)

local pending = {}   -- invitaciones que he mandado: [id] = { contact, tag, t }
local joining        -- invitación que he aceptado: { id, from, tag, parts = {}, t }

local function CleanName(n) return HU.Trim((tostring(n or "")):gsub("[~;:|]", "")) end

---------------------------------------------------------------------------
-- Lista de la comunidad: las de la Información de hermandad + las añadidas desde el panel
---------------------------------------------------------------------------
function HU:NetGuilds()
    self.db.netGuilds = self.db.netGuilds or {}
    return self.db.netGuilds
end

function HU:NetGuildsKey()
    local parts = {}
    for tag, g in pairs(self:NetGuilds()) do parts[#parts + 1] = tag .. (g.on and "1" or "0") .. (g.t or 0) end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- La llama RefreshConfig: añade a la configuración las hermandades que entraron desde el panel
function HU:MergeNetGuilds(cfg)
    for _, g in ipairs(cfg.guilds) do g.info = true end
    local list = {}
    for tag, g in pairs(self:NetGuilds()) do
        if g.on and not cfg.byTag[tag] and not cfg.byName[g.name:lower()] then list[#list + 1] = g end
    end
    table.sort(list, function(a, b) return (a.t or 0) < (b.t or 0) end)
    for _, g in ipairs(list) do
        local e = { name = g.name, tag = g.tag, net = true, by = g.by }
        table.insert(cfg.guilds, e)
        cfg.byTag[g.tag] = e
        cfg.byName[g.name:lower()] = e
    end
end

-- Ancla de confianza de cada hermandad (ver HU:AnchorValid en Comm.lua): quien aceptó su invitación,
-- o quien invitó a la mía. Va en la invitación (GA/GL) y, para las demás, en NG (campo 8).
function HU:Anchors()
    self.db.anchors = self.db.anchors or {}
    return self.db.anchors
end
-- (una vez puesta, solo la cambia una invitación nueva o un oficial de esa misma hermandad: así un
-- oficial de otra no puede cambiar a quién se cree en una hermandad ya unida)
function HU:SetAnchor(tag, name, force)
    if not tag or tag == self.myTag or not HU.SafeName(name) then return end
    local full = self:FullName(name)
    if not full then return end
    local cur = self:Anchors()[tag]
    if cur and not force then return end
    self:Anchors()[tag] = { name = full, t = time() }
    -- (al que puso el nombre: si a los 10 min no ha llegado su lista o no sale en ella de maestro u
    -- oficial, que lo mire: puede estar mal escrito)
    if force == "mine" then
        HU.After(600, function()
            local a = HU:Anchors()[tag]
            if not a or a.name ~= full then return end
            local ok = HU.RosterStateOf(tag) == "c" and HU:AnchorValid(tag, HU:Key(full))
            if not ok then
                HU:Print(string.format(L("|cffff8800No llega la lista de <%s> de %s|r (o no sale en ella de maestro u oficial). ¿Está bien escrito el nombre?"), tag, HU:Short(full)))
            end
        end)
    end
end

local function NGMsg(g)
    local a = HU:Anchors()[g.tag]
    return table.concat({ "NG", g.tag, g.name, g.on and "1" or "0", g.by or "", g.byTag or "", g.t or 0, (g.on and a and not a.dead and a.name) or "" }, "~")
end

function HU:ShareNetGuild(g, target)
    if target then return self:Whisper(target, NGMsg(g)) end
    if self.myTag and IsInGuild() then self:Send(NGMsg(g), "GUILD") end
    for _, tag in ipairs(self:OtherTags()) do
        local peer = self:BestPeer(tag)
        if peer then self:Whisper(peer.name, NGMsg(g)) end
    end
end

local function ShareAllTo(target)
    for _, g in pairs(HU:NetGuilds()) do HU:ShareNetGuild(g, target) end
end

local function SetNetGuild(g)
    HU:NetGuilds()[g.tag] = g
    HU:RefreshConfig(true)
    if HU.UI and HU.UI.UpdateGuildsWindow then HU.UI:UpdateGuildsWindow() end
end

HU.comm.NG = function(self, sender, f, dist, raw)
    local tag, name, on, by, byTag, t = f[1], CleanName(f[2]), f[3] == "1", f[4], f[5], HU.NetT(f[6])
    if not tag or not tag:match("^%w+$") or #tag > 6 or name == "" or not t then return end
    tag = tag:upper()
    if not self:CheckOfficerFirm(by ~= "" and by or sender, byTag, function() HU.comm.NG(self, sender, f, dist, raw) end, sender, dist) then return end
    local cur = self:NetGuilds()[tag]
    if cur and (cur.t or 0) >= t then return end
    SetNetGuild({ tag = tag, name = name, on = on, by = by, byTag = byTag, t = t })
    -- (el ancla: si no la tenía, si la hermandad vuelve a entrar o si lo dice un oficial de ella misma)
    local anchor = f[7]
    if on and anchor and anchor ~= "" then
        self:SetAnchor(tag, anchor, ((cur and not cur.on) or byTag == tag) and true or nil)
    elseif not on then
        self:Anchors()[tag] = nil
    end
    if dist == "WHISPER" then
        self:Send(raw, "GUILD")
    elseif self:IsRelay() then
        -- lo cambió alguien de mi hermandad: como enlace, lo paso a las demás
        for _, ot in ipairs(self:OtherTags()) do
            local peer = self:BestPeer(ot)
            if peer then self:Whisper(peer.name, raw) end
        end
    end
    self:Print((on and L("Nueva hermandad en la comunidad: ") or L("Hermandad quitada de la comunidad: "))
        .. "|cffffd100" .. name .. "|r <" .. tag .. "> (" .. self:Short(by) .. ")")
end

-- Quitar una hermandad (solo las añadidas desde el panel; las de la Información se quitan de ahí)
---------------------------------------------------------------------------
-- Invitar a una hermandad nueva
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Propuestas: un oficial propone, otro de otra hermandad aprueba
--   GP~id~ETIQ~contacto~autor~etiqAutor~t~estado~quienResuelve~etiqQuien
---------------------------------------------------------------------------
function HU:Proposals()
    self.db.proposals = self.db.proposals or {}
    return self.db.proposals
end

local function GPMsg(p)
    return table.concat({ "GP", p.id, p.tag, p.contact, p.by or "", p.byTag or "", p.t or 0, p.state or "open", p.res or "", p.resTag or "" }, "~")
end

function HU:ShareProposal(p, target)
    if target then return self:Whisper(target, GPMsg(p)) end
    if self.myTag and IsInGuild() then self:Send(GPMsg(p), "GUILD") end
    for _, tag in ipairs(self:OtherTags()) do
        local peer = self:BestPeer(tag)
        if peer then self:Whisper(peer.name, GPMsg(p)) end
    end
end

-- propuestas abiertas (de los últimos 3 días)
function HU:OpenProposals()
    local out = {}
    for _, p in pairs(self:Proposals()) do
        if p.state == "open" and time() - (p.t or 0) < 3 * 86400 then out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return out
end

function HU:CanApprove(p)
    return self:CanPin() and not self:IsTest() and self.myTag ~= nil and p.byTag ~= self.myTag
end

HU.comm.GP = function(self, sender, f, dist, raw)
    local id, tag, contact, by, byTag, t, state, res, resTag = f[1], (f[2] or ""):upper(), f[3], f[4], f[5], HU.NetT(f[6]), f[7], f[8], f[9]
    if not id or not tag:match("^%w+$") or #tag > 6 or not HU.SafeName(contact) or not t then return end
    if state ~= "open" and state ~= "ok" and state ~= "no" then return end
    -- quien la abre y quien la resuelve tienen que ser maestros u oficiales (y de hermandades distintas)
    local who, whoTag = by, byTag
    if state ~= "open" then
        who, whoTag = res, resTag
        if resTag == byTag then return end
    end
    if not self:CheckOfficerFirm(who ~= "" and who or sender, whoTag, function() HU.comm.GP(self, sender, f, dist, raw) end, sender, dist) then return end
    local cur = self:Proposals()[id]
    if cur and (cur.state ~= "open" or state == "open") then return end -- ya la tengo (o ya está resuelta)
    local p = { id = id, tag = tag, contact = contact, by = by, byTag = byTag, t = t, state = state, res = res, resTag = resTag }
    self:Proposals()[id] = p
    if dist == "WHISPER" then
        self:Send(raw, "GUILD")
    elseif self:IsRelay() then
        for _, ot in ipairs(self:OtherTags()) do
            local peer = self:BestPeer(ot)
            if peer then self:Whisper(peer.name, raw) end
        end
    end
    if state == "open" and self:CanApprove(p) then
        self:Print("|cffffd100" .. self:Short(by) .. "|r <" .. (byTag or "?") .. L("> propone añadir una hermandad a la comunidad (contacto ") .. self:Short(contact) .. ", <" .. tag .. ">). "
            .. L("Apruébalo o recházalo en Oficiales > Opciones > Hermandades."))
    elseif state ~= "open" and byTag == self.myTag then
        self:Print((state == "ok" and L("|cff44ff44Propuesta aprobada|r por ") or L("|cffff6060Propuesta rechazada|r por ")) .. self:Short(res) .. ": <" .. tag .. ">")
    end
    if self.UI and self.UI.UpdateGuildsWindow then self.UI:UpdateGuildsWindow() end
end

-- Respuesta a mi invitación
HU.comm.GA = function(self, sender, f, dist)
    if dist ~= "WHISPER" then return end
    local id, ok, info = f[1], f[2] == "1", f[3]
    local p = id and pending[id]
    if not p or not self:SameName(p.contact, sender) then return end
    pending[id] = nil
    if not ok then
        self.inviteStatus = "|cffff6060" .. self:Short(sender) .. L(" no se ha unido:|r ") .. (info or "")
        self:Print(self.inviteStatus)
        if self.UI and self.UI.UpdateGuildsWindow then self.UI:UpdateGuildsWindow() end
        return
    end
    local name = CleanName(info)
    if name == "" or not self.cfg then return end
    if self.cfg.byName[name:lower()] then
        self.inviteStatus = "|cffff6060" .. name .. L(" ya está en la comunidad.|r")
        if self.UI and self.UI.UpdateGuildsWindow then self.UI:UpdateGuildsWindow() end
        return
    end
    if self.cfg.byTag[p.tag] then
        local base = p.tag:sub(1, 5)
        for i = 2, 9 do
            if not self.cfg.byTag[base .. i] then p.tag = base .. i; break end
        end
        if self.cfg.byTag[p.tag] then
            self.inviteStatus = "|cffff6060" .. L("No queda ninguna etiqueta libre para ") .. name .. ".|r"
            if self.UI and self.UI.UpdateGuildsWindow then self.UI:UpdateGuildsWindow() end
            return
        end
    end
    local g = { tag = p.tag, name = name, on = true, by = self:Me(), byTag = self.myTag, t = math.max(time(), ((self:NetGuilds()[p.tag] or {}).t or 0) + 1) }
    -- (quien ha aceptado es el ancla de esa hermandad: lo dice el juego, es quien me contesta)
    self:SetAnchor(p.tag, sender, "mine")
    SetNetGuild(g)
    self:ShareNetGuild(g)
    self:AddAudit({ tag = self.myTag, actor = self:Me(), text = L("añadió la hermandad ") .. name .. " <" .. p.tag .. L("> a la comunidad") }, "all")
    self.inviteStatus = "|cff44ff44" .. name .. " <" .. p.tag .. L("> se ha unido a la comunidad.|r")
    self:Print(self.inviteStatus)
    -- le paso la configuración: la lista de hermandades, el título y el canal
    local items = {}
    if self.cfg.title then items[#items + 1] = "t=" .. self.cfg.title end
    for _, cg in ipairs(self.cfg.guilds) do items[#items + 1] = "g=" .. CleanName(cg.name) .. ":" .. cg.tag end
    local ch = self.db.netChan or (self.cfg.channel and { channel = self.cfg.channel, pass = self.cfg.password })
    if ch and ch.channel then items[#items + 1] = "c=" .. ch.channel .. ":" .. (ch.pass or "") end
    -- (las anclas: yo para la mía, y las que tengo de las demás)
    items[#items + 1] = "a=" .. self.myTag .. ":" .. (self:Me() or "")
    for at, a in pairs(self:Anchors()) do
        if not a.dead and at ~= p.tag then items[#items + 1] = "a=" .. at .. ":" .. a.name end
    end
    local chunks, cur = {}, ""
    for _, it in ipairs(items) do
        if #cur + #it + 1 > 200 and cur ~= "" then chunks[#chunks + 1] = cur; cur = "" end
        cur = (cur == "") and it or (cur .. ";" .. it)
    end
    if cur ~= "" then chunks[#chunks + 1] = cur end
    for i, c in ipairs(chunks) do
        self:Whisper(sender, table.concat({ "GL", id, i, #chunks, c }, "~"), true)
    end
    -- y las hermandades añadidas antes desde el panel
    ShareAllTo(sender)
    if self.UI and self.UI.UpdateGuildsWindow then self.UI:UpdateGuildsWindow() end
end

-- Me llega la configuración después de aceptar
HU.comm.GL = function(self, sender, f, dist)
    if dist ~= "WHISPER" or not joining or not self:SameName(sender, joining.from) or f[1] ~= joining.id then return end
    local i, n = tonumber(f[2]), tonumber(f[3])
    if not i or not n or n > 20 then return end
    joining.parts[i] = f[4] or ""
    for k = 1, n do if not joining.parts[k] then return end end
    local j = joining
    joining = nil
    HU:ApplyJoin(j, table.concat(j.parts, ";", 1, n))
end

function HU:ApplyJoin(j, data)
    local guilds, title, chan, pass, anchors = {}, nil, nil, nil, {}
    for it in data:gmatch("[^;]+") do
        local k, v = it:match("^(%a)=(.*)$")
        if k == "a" then
            local at, an = v:match("^(%w+):(.+)$")
            if at then anchors[#anchors + 1] = { tag = at:upper(), name = an } end
        elseif k == "g" then
            local name, tag = v:match("^(.-):(%w+)$")
            if name and name ~= "" then guilds[#guilds + 1] = { name = name, tag = tag:upper() } end
        elseif k == "t" then title = HU.CleanTitle(v)
        elseif k == "c" then chan, pass = v:match("^(%w+):?(.*)$")
        end
    end
    local myGuild = GetGuildInfo("player")
    if not myGuild or #guilds == 0 then return self:Print(L("|cffff6060No se pudo completar la unión (faltan datos).|r")) end
    local mine = false
    for _, g in ipairs(guilds) do if g.name:lower() == myGuild:lower() then mine = true end end
    if not mine then guilds[#guilds + 1] = { name = myGuild, tag = j.tag } end
    -- Información de hermandad: se quitan las líneas viejas de configuración y se ponen las nuevas
    local keep = {}
    local old = self:GuildInfoText()
    -- (sin poder leerla se borraría lo que el maestro tenga escrito en ella)
    if not old then
        -- (se termina la unión cuando acabe el combate o la partida)
        if not j.waitInfo then j.waitInfo = true; self:Print(L("La unión se completará al terminar el combate o la partida.")) end
        HU.After(5, function() HU:ApplyJoin(j, data) end)
        return
    end
    for line in (old .. "\n"):gmatch("([^\n]*)\n") do
        local l = HU.Trim(line)
        if not (l:match("^[Gg][Uu]:%a:") or l:match("^[Ww][Ll][Pp]:%a:") or l:match("^[Hh][Uu]:%a:")) then keep[#keep + 1] = line end
    end
    while #keep > 0 and HU.Trim(keep[#keep]) == "" do table.remove(keep) end
    -- (con muchas hermandades no caben todas en la Información (máx. 500 letras): [+ARCHITECTURE.md]
    local lines = {}
    if title then lines[#lines + 1] = "GU:t:" .. title end
    table.sort(guilds, function(a, b)
        local am, bm = a.name:lower() == myGuild:lower(), b.name:lower() == myGuild:lower()
        if am ~= bm then return am end
        return false
    end)
    local base = table.concat(keep, "\n")
    local overflow = {}
    -- el título y mi hermandad van siempre en la Información (así el addon funciona aunque no [+ARCHITECTURE.md]
    local others, byLine = {}, {}
    for _, g in ipairs(guilds) do
        local line = "GU:g:" .. g.name .. ":" .. g.tag
        if g.name:lower() == myGuild:lower() then lines[#lines + 1] = line
        else others[#others + 1] = line; byLine[line] = g end
    end
    local inNotes = 0
    if self.WriteCommunityConfig and #others > 0 then
        local written, left = self:WriteCommunityConfig(others)
        inNotes = #written
        others = left
    end
    for _, line in ipairs(others) do
        local try = (base ~= "" and (base .. "\n") or "") .. table.concat(lines, "\n") .. "\n" .. line
        if #try <= 480 then lines[#lines + 1] = line
        else overflow[#overflow + 1] = byLine[line] end
    end
    if inNotes > 0 then
        lines[#lines + 1] = "GU:n:" .. inNotes
        self:Print(L("Hermandades guardadas en notas de oficial: ") .. inNotes .. L(" (solo las ven los oficiales; el addon se las pasa a los demás)."))
        if self:IsMaster() and self.MakeOfficerNotesPrivate then self:MakeOfficerNotesPrivate(j.tag) end
    end
    for _, g in ipairs(overflow) do
        local cur = self:NetGuilds()[g.tag]
        if not (cur and cur.on) then
            self:NetGuilds()[g.tag] = { tag = g.tag, name = g.name, on = true, by = j.from, byTag = "", t = time() }
        end
    end
    local text = table.concat(keep, "\n")
    text = (text ~= "" and (text .. "\n") or "") .. table.concat(lines, "\n")
    if #text > 500 then
        self:Print(L("|cffff6060La Información de hermandad no tiene sitio para las líneas de la comunidad (máximo 500 letras).|r Borra parte del texto y vuelve a pedir la invitación."))
        return
    end
    -- (en Forever el juego no deja al addon escribir la Información: se da entera ya preparada para sustituirla)
    if HU.UI and HU.UI.ShowCopy then
        HU.UI:ShowCopy(L("Información de hermandad (J): borra todo lo que hay y pega esto (Ctrl+V)"), text)
        self:Print(L("Sustituye la Información de hermandad por el texto de la ventana para unirte a la comunidad."))
    else
        self:Print(L("Copia estas líneas en la Información de hermandad:"))
        for _, l in ipairs(lines) do self:Print("  " .. l) end
    end
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    self.joinedText = text -- por si el juego tarda en devolver el texto nuevo
    self:CheckInfoWritten(lines)
    self:RefreshConfig(true)
    -- anclas de confianza de las demás hermandades: las que me pasa quien me ha invitado (el juego dice
    -- que es él; mi maestro aceptó su invitación)
    for _, a in ipairs(anchors) do
        if a.tag ~= j.tag and a.tag ~= self.myTag then self:SetAnchor(a.tag, a.name, true) end
    end
    -- canal y contraseña: los guardo y los paso a mi hermandad
    if chan and chan ~= "" then
        self.db.netChan = { channel = chan, pass = (pass ~= "" and pass) or nil, t = HU.StampNow(), by = self:Me(), tag = self.myTag }
        self:RefreshConfig(true)
        if self.ShareNetChan then self:ShareNetChan() end
    end
    self:AddAudit({ tag = self.myTag, actor = self:Me(), text = L("unió la hermandad a la comunidad ") .. (title or "") }, "all")
    self:Print(L("|cff44ff44Tu hermandad ya forma parte de ") .. self:Title() .. L(".|r Los miembros con el addon se conectarán solos."))
end

-- el enlace recuerda las hermandades añadidas cada 30 minutos (Guild Union 20) y a quien entra
HU:OnStart(function()
    -- (una hermandad cada 0,2 s: todas a la vez pasaba de 8 ms con muchas hermandades)
    HU.NewTicker(1800, function()
        if not HU.myTag or not HU:IsRelay() then return end
        for i, tag in ipairs(HU:OtherTags()) do
            HU.After(i * 0.2, function()
                if not HU.myTag or not HU:IsRelay() then return end
                local peer = HU:BestPeer(tag)
                if peer then
                    ShareAllTo(peer.name)
                    for _, p in ipairs(HU:OpenProposals()) do HU:ShareProposal(p, peer.name) end
                end
            end)
        end
    end)
end)

local origPQ = HU.comm.PQ
HU.comm.PQ = function(self, sender, ...)
    if origPQ then origPQ(self, sender, ...) end
    if self:IsRelay() and next(self:NetGuilds()) then ShareAllTo(sender) end
    if self:IsRelay() then for _, p in ipairs(self:OpenProposals()) do self:ShareProposal(p, sender) end end
end

---------------------------------------------------------------------------
-- Crear una comunidad nueva (asistente): escribe las líneas GU: en la Información de
-- hermandad y el canal con su contraseña en la nota de oficial del que la crea.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Colores de las hermandades (los elige un maestro u oficial, para todos)
--   GC~ETIQ~rrggbb~autor~etiqAutor~t      (rrggbb vacío = el de siempre)
---------------------------------------------------------------------------
HU.GUILD_PALETTE = HU.LT({
    { "Verde", "33ff99" }, { "Azul", "66b8ff" }, { "Naranja", "ffb34d" }, { "Morado", "e680f2" },
    { "Amarillo", "ffe666" }, { "Turquesa", "73fff2" }, { "Rojo", "ff7373" }, { "Lima", "b3e666" },
    { "Rosa", "ff8cc6" }, { "Dorado", "ffd100" }, { "Blanco", "f2f2f2" }, { "Cian", "33ccff" },
})

local function GCMsg(tag, c) return table.concat({ "GC", tag, c.hex or "", c.by or "", c.byTag or "", c.t or 0 }, "~") end

HU.comm.GC = function(self, sender, f, dist, raw)
    local tag, hex, by, byTag, t = f[1], f[2], f[3], f[4], HU.NetT(f[5])
    if not tag or not t or (hex ~= "" and not hex:match("^%x%x%x%x%x%x$")) then return end
    if not self:CheckOfficerFirm(by ~= "" and by or sender, byTag, function() HU.comm.GC(self, sender, f, dist, raw) end, sender, dist) then return end
    self.db.guildColors = self.db.guildColors or {}
    local cur = self.db.guildColors[tag]
    if cur and (cur.t or 0) >= t then return end
    self.db.guildColors[tag] = { hex = hex ~= "" and hex or nil, by = by, byTag = byTag, t = t }
    if dist == "WHISPER" then
        self:Send(raw, "GUILD")
    elseif self:IsRelay() then
        for _, ot in ipairs(self:OtherTags()) do
            local peer = self:BestPeer(ot)
            if peer then self:Whisper(peer.name, raw) end
        end
    end
    self:Changed("config")
    if self.UI and self.UI.UpdateGuildsWindow then self.UI:UpdateGuildsWindow() end
end

-- quien entra recibe los colores del enlace
local origPQc = HU.comm.PQ
HU.comm.PQ = function(self, sender, ...)
    if origPQc then origPQc(self, sender, ...) end
    if self:IsRelay() then
        for tag, c in pairs(self.db.guildColors or {}) do self:Whisper(sender, GCMsg(tag, c)) end
    end
end

---------------------------------------------------------------------------
-- Emoticonos de la comunidad (los importa un maestro u oficial, para todos)
--   EM~codigo~ruta~autor~etiqAutor~t      (ruta vacía = borrado)
---------------------------------------------------------------------------
local EM_MAX = 150 -- (los de un canal de Twitch pueden ser muchos)

local function EMMsg(code, e) return table.concat({ "EM", code, e.p or "", e.by or "", e.byTag or "", e.t or 0 }, "~") end

local function ValidCode(code) return type(code) == "string" and #code >= 2 and #code <= 20 and not code:find("[%s~|]") end
local function ValidPath(p)
    return type(p) == "string" and #p <= 160 and p:lower():find("^interface[\\/]") ~= nil and not p:find("[~|:%c]")
end
HU.ValidEmoteCode, HU.ValidEmotePath = ValidCode, ValidPath

-- Lista (ordenada) de los emoticonos activos: { {code=, path=}, ... } [+ARCHITECTURE.md]
local emPending, emBy = {}, nil
local function AnnounceAdded(code, path, by)
    emPending[#emPending + 1] = "|T" .. path .. ":0|t " .. code
    emBy = by
    if #emPending > 1 then return end
    HU.After(2, function()
        local list = emPending
        emPending = {}
        if #list == 0 then return end
        HU:Print((emBy and emBy ~= "" and (HU:Short(emBy) .. " ") or "") .. (#list == 1 and L("ha añadido el emoticono: ") or L("ha añadido los emoticonos: "))
            .. table.concat(list, "   "))
    end)
end
HU.AnnounceEmote = AnnounceAdded

HU.comm.EM = function(self, sender, f, dist, raw)
    local code, path, by, byTag, t = f[1], f[2] or "", f[3], f[4], HU.NetT(f[5])
    if not ValidCode(code) or not t or (path ~= "" and not ValidPath(path)) then return end
    if not self:CheckMasterFirm(by ~= "" and by or sender, byTag, function() HU.comm.EM(self, sender, f, dist, raw) end, sender, dist) then return end
    self.db.customEmotes = self.db.customEmotes or {}
    local cur = self.db.customEmotes[code]
    if cur and (cur.t or 0) >= t then return end
    local count = 0
    for _, e in pairs(self.db.customEmotes) do if e.p and e.p ~= "" then count = count + 1 end end
    if path ~= "" and not (cur and cur.p ~= "") and count >= EM_MAX then return end
    local isNew = path ~= "" and not (cur and cur.p == path)
    self.db.customEmotes[code] = { p = path, by = by, byTag = byTag, t = t }
    -- solo si es reciente (al entrar te llegan todos los de antes y no se avisa de ellos)
    if isNew and math.abs(time() - t) < 600 then AnnounceAdded(code, path, by) end
    if dist == "WHISPER" then
        self:Send(raw, "GUILD")
    elseif self:IsRelay() then
        for _, ot in ipairs(self:OtherTags()) do
            local peer = self:BestPeer(ot)
            if peer then self:Whisper(peer.name, raw) end
        end
    end
    if self.ResetEmoteCache then self:ResetEmoteCache() end
end

-- quien entra recibe los emoticonos
local origPQe = HU.comm.PQ
HU.comm.PQ = function(self, sender, ...)
    if origPQe then origPQe(self, sender, ...) end
    if self:IsRelay() then
        for code, e in pairs(self.db.customEmotes or {}) do self:Whisper(sender, EMMsg(code, e)) end
    end
end
