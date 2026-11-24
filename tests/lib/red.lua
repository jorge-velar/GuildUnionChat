-- Varios jugadores con Guild Union a la vez, unidos por una red de mentira: hermandades (GUILD),
-- canales (CHANNEL) y susurros (WHISPER), con un reloj común. Para probar de punta a punta lo que
-- hoy se prueba en el juego con varias personas (/gu registro).
--
--   local red = require("lib.red")
--   local net = red.New()                          -- la comunidad de prueba (fixtures.INFO): UNO y DOS
--   local a = net:Player("Ana", "UNO", { rankIndex = 1 })
--   local b = net:Player("Bea", "DOS")
--   net:Login(a); net:Login(b)
--   net:Advance(60)                                -- todos a la vez, en pasos de net.step segundos
--   a:Say("hola")                                  -- lo que se escribe en /g
--   net:Advance(5)
--   b.HU.db.history                                -- lo que ha visto Bea
--
-- Lo que manda un jugador llega a los demás en el paso siguiente (net.step, 0,1 s por defecto).
-- Lo propio también vuelve (como en el juego: GUILD y CHANNEL devuelven el eco).
local addon = require("lib.addon")
local wow = require("lib.wow")
local fixtures = require("lib.fixtures")

local R = {}

local Net = {}
Net.__index = Net

-- opts.info: la Información de hermandad (todas la comparten); opts.guilds: { ETIQ = "Nombre", ... }
-- opts.pass: { [canal en minúsculas] = contraseña }; opts.step: segundos por paso
function R.New(opts)
    opts = opts or {}
    local net = setmetatable({
        now = 1000,
        step = opts.step or 0.1,
        info = opts.info or fixtures.INFO,
        guilds = {},
        players = {},          -- en orden de creación
        byKey = {},            -- ["ana-reino"] = jugador
        members = {},          -- [canal en minúsculas] = { [jugador] = true }
        pass = opts.pass,
        line = 0,
        traffic = {},          -- lo que ha salido de cada uno: ver Net:Traffic
        log = {},              -- todos los mensajes de addon enviados: { t, from, prefix, text, dist, target }
    }, Net)
    for tag, name in pairs(opts.guilds or { UNO = "Hermandad Uno", DOS = "Hermandad Dos" }) do
        net:Guild(tag, name)
    end
    wow.Seed(opts.seed or 1) -- (los números al azar del WoW de mentira: iguales en todas las versiones de Lua)
    return net
end

function Net:Guild(tag, name)
    local g = { tag = tag, name = name, members = {} }
    self.guilds[tag] = g
    return g
end

local Player = {}
Player.__index = Player

-- Un jugador de la hermandad `tag`, todavía desconectado (sale en la lista de su hermandad)
-- opts: rankIndex (0 maestro, 1 oficial, 4 miembro), surname, db, charDb, ref (otra versión del
-- addon: una etiqueta de git como "v5.4.41"; ver addon.Load)
function Net:Player(name, tag, opts)
    opts = opts or {}
    local g = assert(self.guilds[tag], "no hay hermandad " .. tostring(tag))
    local surname = opts.surname or "Reino"
    local full = name .. "-" .. surname
    local rankIndex = opts.rankIndex or 4
    local rank = (rankIndex == 0 and "Maestro") or (rankIndex <= 2 and "Oficial") or "Miembro"
    local m = { name = full, rank = rank, rankIndex = rankIndex, online = false }
    g.members[#g.members + 1] = m
    local p = setmetatable({ net = self, name = name, surname = surname, full = full, key = full:lower(),
        tag = tag, guild = g, member = m, opts = opts, online = false }, Player)
    self.players[#self.players + 1] = p
    self.byKey[p.key] = p
    self.traffic[p.key] = { msgs = 0, bytes = 0, byCmd = {} }
    return p
end

-- Carga el addon del jugador y entra al juego (sin avanzar el reloj: eso es Net:Advance)
function Net:Login(p)
    assert(not p.online, p.full .. " ya está conectado")
    local g = p.guild
    -- (lo guardado se conserva entre una entrada y la siguiente, como las SavedVariables del juego)
    local a = addon.Load({
        now = self.now, keepRandom = true,
        player = p.name, surname = p.surname,
        guild = { name = g.name, rank = p.member.rank, rankIndex = p.member.rankIndex, members = g.members },
        guildInfo = self.info,
        db = p.savedDb or p.opts.db, charDb = p.savedCharDb or p.opts.charDb,
        ref = p.opts.ref,
    })
    p.a, p.HU, p.w, p.env = a, a.HU, a.w, a.env
    -- (qué órdenes acepta y rechaza la seguridad de este jugador, sumando todas sus entradas: para la
    -- prueba de ida y vuelta)
    p.accepted, p.refused = p.accepted or {}, p.refused or {}
    local allow = a.HU.AllowAddonMessage
    if allow then
        a.HU.AllowAddonMessage = function(hu, cmd, ...)
            local ok, weak = allow(hu, cmd, ...)
            local t = ok and p.accepted or p.refused
            t[cmd] = (t[cmd] or 0) + 1
            return ok, weak
        end
    end
    p.w.net = self
    p.w.netPlayer = p
    p.online, p.member.online = true, true
    -- (los canales del juego, como General: el addon espera a que estén para entrar al suyo)
    p.w.channels[1] = "General - Ventormenta"
    a.w:Fire("PLAYER_LOGIN")
    a.w:Fire("PLAYER_ENTERING_WORLD", true, false)
    for _, q in ipairs(self:Guildmates(p)) do
        if q ~= p then q.w:Fire("GUILD_ROSTER_UPDATE") end
    end
    return p
end

-- Sale del juego: deja de recibir, sus canales se vacían y su hermandad lo ve desconectado
function Net:Logout(p)
    if not p.online then return end
    -- (el juego guarda las SavedVariables al salir: PLAYER_LOGOUT y lo que haya en las globales)
    p.w:Fire("PLAYER_LOGOUT")
    p.savedDb, p.savedCharDb = p.env.GuildUnionDB, p.env.GuildUnionCharDB
    for name, set in pairs(self.members) do
        if set[p] then
            set[p] = nil
            self:ChannelNotice("CHAT_MSG_CHANNEL_LEAVE", p, name)
        end
    end
    p.online, p.member.online = false, false
    for _, q in ipairs(self:Guildmates(p)) do q.w:Fire("GUILD_ROSTER_UPDATE") end
end

function Net:Online()
    local out = {}
    for _, p in ipairs(self.players) do if p.online then out[#out + 1] = p end end
    return out
end

function Net:Guildmates(p)
    local out = {}
    for _, q in ipairs(self.players) do
        if q.online and q.guild == p.guild then out[#out + 1] = q end
    end
    return out
end

---------------------------------------------------------------------------
-- Lo que pregunta el WoW de cada jugador (tests/lib/wow.lua)
---------------------------------------------------------------------------
function Net:CanJoin(_, name, pass)
    local want = self.pass and self.pass[name:lower()]
    return want == nil or want == pass
end
-- (al entrar o salir alguien, los que ya están lo ven: CHAT_MSG_CHANNEL_JOIN / _LEAVE)
function Net:ChannelNotice(ev, p, name)
    for _, x in ipairs(self:InChannel(name)) do
        if x.q ~= p then x.q.w:Fire(ev, "", p.full, "", x.id .. ". " .. name, "", "", 0, x.id, name) end
    end
end
function Net:Joined(w, name)
    local set = self.members[name:lower()] or {}
    self.members[name:lower()] = set
    self.joinSeq = (self.joinSeq or 0) + 1
    set[w.netPlayer] = self.joinSeq
    self:ChannelNotice("CHAT_MSG_CHANNEL_JOIN", w.netPlayer, name)
end
function Net:Left(w, name)
    local set = self.members[name:lower()]
    if set and set[w.netPlayer] then
        set[w.netPlayer] = nil
        self:ChannelNotice("CHAT_MSG_CHANNEL_LEAVE", w.netPlayer, name)
    end
end
-- Los del canal, en orden de llegada; el primero que sigue dentro es el dueño (como en el juego)
function Net:ChannelMembers(name)
    local list = {}
    for q, seq in pairs(self.members[name:lower()] or {}) do
        if q.online then list[#list + 1] = { q = q, seq = seq } end
    end
    table.sort(list, function(x, y) return x.seq < y.seq end)
    for i, m in ipairs(list) do
        list[i] = { name = m.q.full, owner = i == 1, moderator = i == 1, guid = "Player-1-" .. m.q.key }
    end
    return list
end
function Net:ChannelCount(name)
    local n = 0
    for _ in pairs(self.members[name:lower()] or {}) do n = n + 1 end
    return n
end
-- ¿Sale este mensaje de addon? (0 = sí; 12 = el destinatario no está conectado)
function Net:Check(_, _, _, dist, target)
    if dist == "WHISPER" then
        local q = self:Find(target)
        if not q or not q.online then return 12 end
    end
    -- (net.channelRefuse: el juego rechaza lo del addon por los canales, resultado 7; lo que pasó
    -- en Forever la noche del lanzamiento y por lo que existen los carriles)
    if dist == "CHANNEL" and self.channelRefuse then return 7 end
    return 0
end

-- El jugador por su nombre («Ana-Reino», «Ana Reino», «ana-reino»)
function Net:Find(name)
    if type(name) ~= "string" then return nil end
    return self.byKey[(name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "-")):lower()]
end

---------------------------------------------------------------------------
-- Reparto
---------------------------------------------------------------------------
-- (los que están en el canal `name`, con el número que le da cada uno)
function Net:InChannel(name)
    local out = {}
    for q in pairs(self.members[name:lower()] or {}) do
        if q.online then
            local id = q.env.GetChannelName(name)
            if id and id > 0 then out[#out + 1] = { q = q, id = id } end
        end
    end
    table.sort(out, function(x, y) return x.q.key < y.q.key end)
    return out
end

local function Note(t, prefix, text)
    t.msgs, t.bytes = t.msgs + 1, t.bytes + #prefix + #text
    local cmd = prefix .. " " .. (text:match("^(%u%u?)~") or text:sub(1, 2))
    t.byCmd[cmd] = (t.byCmd[cmd] or 0) + 1
end

function Net:DeliverAddon(p, m)
    if not p.online then return end
    local ev = m.logged and "CHAT_MSG_ADDON_LOGGED" or "CHAT_MSG_ADDON"
    Note(self.traffic[p.key], m.prefix, m.text)
    self.log[#self.log + 1] = { t = self.now, from = p, prefix = m.prefix, text = m.text, dist = m.dist, target = m.target }
    if m.dist == "GUILD" or m.dist == "OFFICER" then
        for _, q in ipairs(self:Guildmates(p)) do
            q.w:Fire(ev, m.prefix, m.text, m.dist, p.full, nil, nil, 0, "")
        end
    elseif m.dist == "CHANNEL" then
        local name = p.w.channels[m.target]
        if not name then return end
        for _, x in ipairs(self:InChannel(name)) do
            x.q.w:Fire(ev, m.prefix, m.text, "CHANNEL", p.full, nil, nil, x.id, name)
        end
    elseif m.dist == "WHISPER" then
        local q = self:Find(m.target)
        if q and q.online then q.w:Fire(ev, m.prefix, m.text, "WHISPER", p.full, nil, nil, 0, "") end
    end
end

function Net:DeliverChat(p, s)
    if not p.online then return end
    self.line = self.line + 1
    local kind = (s.kind or ""):upper()
    local guid = "Player-1-" .. p.key
    if kind == "GUILD" or kind == "OFFICER" then
        for _, q in ipairs(self:Guildmates(p)) do
            q.w:Fire("CHAT_MSG_" .. kind, s.msg, p.full, "", "", "", "", 0, 0, "", 0, self.line, guid)
        end
    elseif kind == "CHANNEL" then
        local name = p.w.channels[tonumber(s.target)]
        if not name then return end
        -- (net.channelTextDown: el texto de los canales no le llega a nadie, ni el eco a quien lo
        -- escribe; lo oculto del addon sí, como lo visto en Forever)
        if self.channelTextDown then return end
        for _, x in ipairs(self:InChannel(name)) do
            x.q.w:Fire("CHAT_MSG_CHANNEL", s.msg, p.full, "", x.id .. ". " .. name, "", "", 0, x.id, name, 0, self.line, guid)
        end
    elseif kind == "WHISPER" then
        local q = self:Find(s.target)
        if q and q.online then
            q.w:Fire("CHAT_MSG_WHISPER", s.msg, p.full, "", "", "", "", 0, 0, "", 0, self.line, guid)
        end
    end
end

-- Reparte lo que han mandado todos desde la última vez
function Net:Route()
    local batch = {}
    for _, p in ipairs(self.players) do
        if p.online then
            local sent, said = p.w:TakeSent(), p.w.said
            p.w.said = {}
            if #sent > 0 or #said > 0 then batch[#batch + 1] = { p = p, sent = sent, said = said } end
        end
    end
    for _, b in ipairs(batch) do
        for _, m in ipairs(b.sent) do self:DeliverAddon(b.p, m) end
        for _, s in ipairs(b.said) do self:DeliverChat(b.p, s) end
    end
    return #batch
end

-- Avanza el reloj de todos `secs` segundos, en pasos de net.step, repartiendo en cada paso
function Net:Advance(secs)
    local n = math.max(1, math.floor(secs / self.step + 0.5))
    for _ = 1, n do
        self.now = self.now + self.step
        for _, p in ipairs(self.players) do
            if p.online then p.w:Advance(self.now - p.w.now) end
        end
        self:Route()
    end
end

-- Avanza hasta que `cond()` se cumpla o pasen `max` segundos. Devuelve los segundos que han hecho falta (o nil)
function Net:AdvanceUntil(cond, max, every)
    local t0 = self.now
    every = every or 1
    while self.now - t0 < max do
        if cond() then return self.now - t0 end
        self:Advance(every)
    end
    if cond() then return self.now - t0 end
    return nil
end

-- Errores del addon de todos (SafeCall), con el nombre de quien los tuvo
function Net:Errors()
    local out = {}
    for _, p in ipairs(self.players) do
        if p.a then for _, e in ipairs(p.a:Errors()) do out[#out + 1] = p.full .. ": " .. e end end
    end
    return out
end

-- Tráfico de addon de cada uno: { msgs, bytes, byCmd = { ["HU20 HI"] = n } }
function Net:Traffic(p) return self.traffic[p.key] end
function Net:ResetTraffic()
    for k in pairs(self.traffic) do self.traffic[k] = { msgs = 0, bytes = 0, byCmd = {} } end
end

---------------------------------------------------------------------------
-- Lo que hace el jugador
---------------------------------------------------------------------------
-- Escribe en el chat (/g por defecto), como desde la caja de texto: pasa por el SendChatMessage del juego
function Player:Say(msg, kind, target)
    self.env.SendChatMessage(msg, kind or "GUILD", nil, target)
end

-- Escribe «/gu texto» y devuelve lo que el addon le ha escrito en el chat
function Player:Gu(text)
    local before = #self.w.chat
    self.env.SlashCmdList.HERMANDADUNIDA(text)
    local out = {}
    for i = before + 1, #self.w.chat do out[#out + 1] = tostring(self.w.chat[i].msg) end
    return table.concat(out, "\n")
end

-- Las líneas que este jugador tiene en el historial del addon de `author` (otro jugador)
function Player:Heard(author, kind)
    local out = {}
    for _, e in ipairs((self.HU.db and self.HU.db.history) or {}) do
        if (not kind or e.k == kind) and e.a and e.a:lower() == author.key then out[#out + 1] = e.m end
    end
    return out
end

return R
