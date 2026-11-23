-- Un WoW de mentira para las pruebas: reloj, temporizadores, eventos, marcos, mensajes de addon,
-- jugador y hermandad. Cada prueba crea el suyo con wow.New(): no comparten nada.
--
-- Lo que no está aquí no existe (igual que en un cliente que no tiene esa función): el addon ya
-- comprueba casi todo con «if X and X.Y then». Si una prueba falla por una función del juego que
-- falta, se añade aquí con el valor más neutro posible.
local wow = {}

local unpack = unpack or table.unpack

-- Números al azar propios (Park-Miller), iguales con Lua 5.1 y 5.4: el math.random de cada versión
-- da otros números, el addon los usa para repartir saludos y retrasos, y el mismo escenario seguía
-- otro camino en el CI (5.1) que en local (5.4). Lo comparten todos los mundos, como el del juego.
local seed = 1
function wow.Seed(n)
    seed = math.floor(tonumber(n) or 1) % 2147483646 + 1
end
local function Random(m, n)
    seed = seed * 16807 % 2147483647 -- (cabe entero en un double: < 2^53)
    local r = (seed - 1) / 2147483646
    if m == nil then return r end
    if n == nil then m, n = 1, m end
    m, n = math.floor(m), math.floor(n)
    if n < m then error("bad argument #2 to 'random' (interval is empty)", 2) end
    return m + math.floor(r * (n - m + 1))
end
local mathEnv = setmetatable({ random = Random, randomseed = wow.Seed }, { __index = math })

---------------------------------------------------------------------------
-- Marcos
---------------------------------------------------------------------------
-- (lo que devuelven los «Get…» que el addon usa al montar la interfaz)
local GETTERS = {
    GetWidth = 0, GetHeight = 0, GetText = "", GetNumLines = 0, GetStringWidth = 0, GetStringHeight = 0,
    GetFrameLevel = 1, GetValue = 0, GetChecked = false, GetAlpha = 1, GetScale = 1, GetEffectiveScale = 1,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetHorizontalScroll = 0, GetNumMessages = 0,
    GetNumPoints = 0, GetCursorPosition = 0, GetNumChildren = 0, GetTop = 0, GetBottom = 0, GetLeft = 0,
    GetRight = 0, GetFrameStrata = "MEDIUM", GetMaxLines = 0, GetScrollOffset = 0, GetNumRegions = 0,
    IsMouseOver = false, HasFocus = false, IsVisible = false, IsMouseEnabled = false, IsEnabled = true,
    IsAtBottom = true, IsAtTop = true, IsProtected = false, IsForbidden = false, IsDragging = false,
}

local function NewFrame(w, kind, name, parent)
    local f = { _kind = kind or "Frame", _name = name, _parent = parent, _scripts = {}, _events = {}, _shown = true }
    w.frames[#w.frames + 1] = f
    if name then w.env[name] = f end
    return setmetatable(f, w.frameMeta)
end

local function FrameMethods(w)
    local M = {}
    function M:SetScript(what, fn) self._scripts[what] = fn end
    function M:GetScript(what) return self._scripts[what] end
    function M:HookScript(what, fn)
        local old = self._scripts[what]
        self._scripts[what] = old and function(...) old(...); fn(...) end or fn
    end
    function M:HasScript() return true end
    function M:RegisterEvent(ev) self._events[ev] = true end
    function M:RegisterUnitEvent(ev) self._events[ev] = true end
    function M:UnregisterEvent(ev) self._events[ev] = nil end
    function M:IsEventRegistered(ev) return self._events[ev] == true end
    function M:RegisterAllEvents() self._allEvents = true end
    function M:UnregisterAllEvents() self._events, self._allEvents = {}, nil end
    -- (como en el juego: OnShow / OnHide cuando el marco pasa a verse o deja de verse, mirando sus padres;
    -- p. ej. Hide() nada más crearlo, que nace visible, ya llama a su OnHide)
    local function Visible(f)
        while f do
            if f._shown == false then return false end
            f = f._parent
        end
        return true
    end
    local function SetShownState(self, v)
        local was = Visible(self)
        self._shown = v
        local now = Visible(self)
        if was ~= now then
            local s = self._scripts[now and "OnShow" or "OnHide"]
            if s then s(self) end
        end
    end
    function M:Show() SetShownState(self, true) end
    function M:Hide() SetShownState(self, false) end
    function M:SetShown(v) SetShownState(self, v and true or false) end
    function M:IsShown() return self._shown end
    function M:GetName() return self._name end
    function M:GetParent() return self._parent end
    function M:GetObjectType() return self._kind end
    function M:IsObjectType(k) return self._kind == k end
    function M:GetChildren() return end
    function M:GetRegions() return end
    function M:GetPoint() return end
    function M:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function M:GetTextColor() return 1, 1, 1, 1 end
    function M:GetSize() return 0, 0 end
    function M:GetCenter() return 0, 0 end
    function M:GetMinMaxValues() return 0, 0 end
    function M:SetText(t) self._text = t end
    function M:AddMessage(msg, ...) w.chat[#w.chat + 1] = { frame = self._name, msg = msg } end
    return M
end

local function FrameMeta(w)
    local M = FrameMethods(w)
    return {
        __index = function(f, k)
            local m = M[k]
            if m then return m end
            if k == "GetText" then return function(self) return self._text or "" end end
            local g = GETTERS[k]
            if g ~= nil then return function() return g end end
            -- (CreateTexture, CreateFontString, CreateAnimationGroup...: un marco nuevo)
            if type(k) == "string" and k:sub(1, 6) == "Create" then
                return function(self, name) return NewFrame(w, k:sub(7), name, self) end
            end
            -- (un campo del addon que aún no se ha puesto, en minúscula: nada, como en el juego)
            if type(k) ~= "string" or not k:match("^%u") then return nil end
            -- (cualquier otro método: no hace nada, como un «Set…» del juego)
            return function() end
        end,
    }
end

---------------------------------------------------------------------------
-- Mundo
---------------------------------------------------------------------------
function wow.New(opts)
    opts = opts or {}
    local w = {
        now = opts.now or 1000,     -- GetTime() (la red, tests/lib/red.lua, arranca a todos con su reloj)
        epoch = 1800000000,         -- time() = epoch + now
        timers = {}, frames = {}, chat = {}, sent = {}, said = {},
        who = {}, whoSent = {}, -- (/who: lo que devuelve, w.who = { {fullName, fullGuildName, level, filename, area} }, y lo buscado)
        channels = {},              -- [número] = nombre de los canales en los que estoy
        net = nil,                  -- la red (tests/lib/red.lua): decide si un susurro llega o el canal deja entrar
        player = opts.player or "Tester",
        surname = opts.surname or "Reino",
        realm = opts.realm or "Reino",
        guild = opts.guild,         -- { name = "...", rank = "...", rankIndex = n, members = { {name, rank, rankIndex, level, class, zone, note, officerNote, online} } }
        guildInfo = opts.guildInfo or "",
        locale = opts.locale or "esES",
        metadata = opts.metadata or {},
        failSend = nil,             -- función (prefix, text, dist, target) -> resultado, para simular saturación
    }
    local env = {}
    w.env = env
    if not opts.keepRandom then
        wow.Seed(opts.seed or 1) -- (el addon usa math.random para repartir saludos: que sea siempre igual)
    end
    w.frameMeta = FrameMeta(w)

    -- Reloj y temporizadores ------------------------------------------------
    local seq = 0
    local function AddTimer(delay, fn, interval, n)
        seq = seq + 1
        local t = { at = w.now + math.max(0, delay or 0), fn = fn, interval = interval, n = n, seq = seq }
        function t:Cancel() self.cancelled = true end
        function t:IsCancelled() return self.cancelled == true end
        w.timers[#w.timers + 1] = t
        return t
    end
    -- Avanza el reloj `secs` segundos y ejecuta los temporizadores que tocan, en orden
    function w:Advance(secs)
        local target = self.now + (secs or 0)
        while true do
            local best, bi
            for i, t in ipairs(self.timers) do
                if not t.cancelled and t.at <= target and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then
                    best, bi = t, i
                end
            end
            if not best then break end
            table.remove(self.timers, bi)
            self.now = math.max(self.now, best.at)
            if best.interval then
                best.fn(best)
                best.n = best.n and best.n - 1
                if not best.cancelled and (not best.n or best.n > 0) then
                    best.at = self.now + best.interval
                    seq = seq + 1
                    best.seq = seq
                    self.timers[#self.timers + 1] = best
                end
            else
                best.fn()
            end
        end
        self.now = target
        -- (de paso, un fotograma: los OnUpdate que haya)
        for _, f in ipairs(self.frames) do
            local s = f._scripts.OnUpdate
            if s and f._shown then s(f, secs or 0) end
        end
    end

    -- Eventos ---------------------------------------------------------------
    function w:Fire(event, ...)
        for _, f in ipairs(self.frames) do
            local s = f._scripts.OnEvent
            if s and (f._events[event] or f._allEvents) then s(f, event, ...) end
        end
    end
    -- Un mensaje de addon que llega de otro jugador
    function w:Receive(prefix, text, dist, sender, localID, chanName)
        self:Fire("CHAT_MSG_ADDON", prefix, text, dist, sender, nil, nil, localID or 0, chanName or "")
    end
    -- Lo mandado desde la última vez (y se vacía)
    function w:TakeSent()
        local s = self.sent
        self.sent = {}
        return s
    end

    -- API del juego ---------------------------------------------------------
    local api = {}
    api.GetTime = function() return w.now end
    api.time = function(t) if t then return os.time(t) end return w.epoch + math.floor(w.now) end
    api.date = function(fmt, t) return os.date(fmt, t or api.time()) end
    api.GetServerTime = api.time
    api.debugprofilestop = function() return w.now * 1000 end
    -- (como el del juego: «Archivo.lua:123: in function …» de quien está `level` por encima)
    api.debugstack = function(level)
        local info = debug.getinfo((level or 1) + 1, "Sl")
        if not info then return "" end
        return info.short_src .. ":" .. tostring(info.currentline) .. ": in function"
    end
    api.geterrorhandler = function() return function(e) error(e, 0) end end
    api.securecall = function(fn, ...) if type(fn) == "function" then return fn(...) end end
    api.hooksecurefunc = function(a, b, c)
        local tbl, name, fn = a, b, c
        if type(a) == "string" then tbl, name, fn = env, a, b end
        local old = tbl[name]
        if type(old) ~= "function" then return end
        tbl[name] = function(...) local r = { old(...) }; fn(...); return unpack(r) end
    end
    api.issecurevariable = function() return true, nil end

    api.C_Timer = {
        After = function(d, fn) AddTimer(d, fn) end,
        NewTimer = function(d, fn) return AddTimer(d, fn) end,
        NewTicker = function(d, fn, n) return AddTimer(d, fn, d, n) end,
    }

    api.CreateFrame = function(kind, name, parent, template)
        local f = NewFrame(w, kind, name, parent)
        -- (las piezas que traen las plantillas del juego y que el addon toca: el fondo de InsetFrameTemplate)
        if type(template) == "string" and template:find("InsetFrameTemplate", 1, true) then f.Bg = NewFrame(w, "Texture", nil, f) end
        -- (y las tres piezas del botón rojo, UIPanelButtonTemplate: DJStyle.lua las oscurece al elegirlo)
        if type(template) == "string" and template:find("UIPanelButtonTemplate", 1, true) then
            for _, k in ipairs({ "Left", "Middle", "Right" }) do f[k] = NewFrame(w, "Texture", nil, f) end
        end
        -- (el texto gris de ayuda de los buscadores, SearchBoxTemplate)
        if type(template) == "string" and template:find("SearchBoxTemplate", 1, true) then
            f.Instructions = NewFrame(w, "FontString", nil, f)
        end
        -- (el texto de al lado de las casillas, UICheckButtonTemplate)
        if type(template) == "string" and template:find("UICheckButtonTemplate", 1, true) then
            f.Text = NewFrame(w, "FontString", nil, f)
        end
        return f
    end
    -- (las listas con barra de la interfaz del juego: solo recuerdan por dónde van)
    api.FauxScrollFrame_Update = function() end
    api.FauxScrollFrame_GetOffset = function(f) return f and f._offset or 0 end
    api.FauxScrollFrame_SetOffset = function(f, n) if f then f._offset = n end end
    api.FauxScrollFrame_OnVerticalScroll = function(_, _, _, fn) if fn then fn() end end
    -- (las pestañas de la interfaz del juego: solo recuerdan cuál está elegida)
    api.PanelTemplates_SetNumTabs = function(f, n) if f then f.numTabs = n end end
    api.PanelTemplates_SetTab = function(f, id) if f then f.selectedTab = id end end
    api.PanelTemplates_TabResize = function() end
    api.CreateFont = function(name) return NewFrame(w, "Font", name) end
    api.UIParent = NewFrame(w, "Frame", "UIParent")
    api.DEFAULT_CHAT_FRAME = NewFrame(w, "ScrollingMessageFrame", "ChatFrame1")
    api.NUM_CHAT_WINDOWS = 10
    for i = 2, 10 do NewFrame(w, "ScrollingMessageFrame", "ChatFrame" .. i) end
    -- (lo que enseña cada ventana: la 1 lo de siempre, las demás nada)
    for i = 1, 10 do
        local f = w.env["ChatFrame" .. i]
        f.messageTypeList = i == 1 and { "SAY", "GUILD", "OFFICER", "WHISPER", "SYSTEM" } or {}
        f.channelList, f.zoneChannelList = {}, {}
    end
    api.GameTooltip = NewFrame(w, "GameTooltip", "GameTooltip")
    api.Minimap = NewFrame(w, "Minimap", "Minimap")
    api.ChatFontNormal = NewFrame(w, "Font", "ChatFontNormal")
    api.GameFontNormal = NewFrame(w, "Font", "GameFontNormal")
    api.GameFontNormalSmall = NewFrame(w, "Font", "GameFontNormalSmall")
    api.GameFontHighlightSmall = NewFrame(w, "Font", "GameFontHighlightSmall")
    api.SlashCmdList = {}
    api.StaticPopupDialogs = {}
    api.UISpecialFrames = {}
    api.ChatTypeInfo = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
    api.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1, colorStr = "ffffffff" } end })
    api.LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k end })
    api.CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 1, 0, 1 } end })
    api.MAX_WOW_CHAT_CHANNELS = 20
    api.WOW_PROJECT_ID = 1
    api.WOW_PROJECT_MAINLINE = 1

    -- Jugador y hermandad
    -- (en Forever la segunda parte es el apellido: «Tester», «Reino» -> Tester-Reino)
    api.UnitName = function(unit) if unit == "player" then return w.player, w.surname end end
    api.UnitClass = function() return "Guerrero", "WARRIOR", 1 end
    api.UnitRace = function() return "Humano", "Human" end
    api.UnitLevel = function() return 60 end
    api.UnitIsAFK = function() return false end
    api.GetRealmName = function() return w.realm end
    api.GetNormalizedRealmName = function() return w.realm end
    api.GetLocale = function() return w.locale end
    api.GetBuildInfo = function() return "1.60.1", "00000", "Nov 1 2026", 16001 end
    api.IsInGuild = function() return w.guild ~= nil end
    api.GetGuildInfo = function(unit)
        if unit == "player" and w.guild then return w.guild.name, w.guild.rank or "Miembro", w.guild.rankIndex or 4 end
    end
    api.GetGuildInfoText = function() return w.guildInfo end
    api.GetNumGuildMembers = function()
        local n = w.guild and #(w.guild.members or {}) or 0
        return n, n, n
    end
    api.GetGuildRosterInfo = function(i)
        local m = w.guild and w.guild.members and w.guild.members[i]
        if not m then return end
        return m.name, m.rank or "Miembro", m.rankIndex or 4, m.level or 60, m.class or "Guerrero", m.zone or "",
            m.note or "", m.officerNote or "", m.online ~= false, 0, m.classFile or "WARRIOR"
    end
    -- (pedir la lista de la hermandad: el servidor contesta un momento después con GUILD_ROSTER_UPDATE;
    -- varias peticiones seguidas, una sola respuesta)
    local rosterAsked = false
    api.GuildRoster = function()
        if rosterAsked or not w.guild then return end
        rosterAsked = true
        AddTimer(0.5, function()
            rosterAsked = false
            w:Fire("GUILD_ROSTER_UPDATE")
        end)
    end
    api.IsGuildLeader = function() return w.guild and w.guild.rankIndex == 0 or false end
    api.CanEditOfficerNote = function() return false end
    -- (los oficiales, rangos 0 a 2, ven las notas de oficial: lo mismo que su casilla «Oficial»)
    api.CanViewOfficerNote = function() return w.guild ~= nil and (w.guild.rankIndex or 4) <= 2 end
    api.CanEditGuildInfo = function() return false end
    api.InCombatLockdown = function() return w.inCombat == true end
    -- (w.instance = "raid", "party", "pvp"...: dentro de una instancia de ese tipo)
    api.IsInInstance = function() if w.instance then return true, w.instance end return false, "none" end
    api.IsInGroup = function() return false end
    api.IsInRaid = function() return false end
    api.GetNumGroupMembers = function() return 0 end
    api.GetZoneText = function() return "Ventormenta" end
    -- Canales: GetChannelName(número o nombre) -> número, nombre
    api.GetChannelName = function(x)
        if type(x) == "number" then
            local n = w.channels[x]
            if n then return x, n end
            return 0
        end
        if type(x) == "string" then
            for id, n in pairs(w.channels) do
                if n:lower() == x:lower() then return id, n end
            end
        end
        return 0
    end
    -- (como el juego: se entra un momento después y llega el aviso YOU_JOINED, o WRONG_PASSWORD)
    api.JoinTemporaryChannel = function(name, pass)
        if type(name) ~= "string" or api.GetChannelName(name) > 0 then return end
        AddTimer(0.2, function()
            if api.GetChannelName(name) > 0 then return end
            local ok = not w.net or w.net:CanJoin(w, name, pass)
            local id = 1
            while w.channels[id] do id = id + 1 end
            if not ok then
                return w:Fire("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", id .. ". " .. name, "", "", 0, id, name)
            end
            w.channels[id] = name
            if w.net then w.net:Joined(w, name) end
            w:Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "", "", id .. ". " .. name, "", "", 0, id, name)
        end)
    end
    api.LeaveChannelByName = function(name)
        local id = api.GetChannelName(name)
        if id == 0 then return end
        w.channels[id] = nil
        if w.net then w.net:Left(w, name) end
        w:Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_LEFT", "", "", id .. ". " .. name, "", "", 0, id, name)
    end
    api.GetNumChannelMembers = function(id)
        local n = w.channels[id]
        return n and w.net and w.net:ChannelCount(n) or 0
    end
    -- La ventana de canales del juego: una fila por canal, en orden de número (sin cabeceras)
    local function DisplayIds()
        local ids = {}
        for id in pairs(w.channels) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end
    api.GetNumDisplayChannels = function() return #DisplayIds() end
    -- -> nombre, cabecera, plegado, número, miembros, activo, categoría, tipo
    api.GetChannelDisplayInfo = function(i)
        local id = DisplayIds()[i]
        if not id then return end
        return w.channels[id], false, false, id, api.GetNumChannelMembers(id), true, "CHANNEL_CATEGORY_CUSTOM", 0
    end
    api.SetSelectedDisplayChannel = function(i) w.selectedChannel = i end
    -- (los miembros del canal de esa fila: nombre, dueño, moderador, guid. Solo los da la red)
    local function ChannelRosterInfo(i, j)
        local id = DisplayIds()[i]
        local list = id and w.net and w.net:ChannelMembers(w.channels[id])
        local m = list and list[j]
        if m then return m.name, m.owner, m.moderator, m.guid end
    end
    -- (los marcos que escuchan un evento, como el del juego)
    api.GetFramesRegisteredForEvent = function(ev)
        local out = {}
        for _, f in ipairs(w.frames) do if f._events[ev] then out[#out + 1] = f end end
        return unpack(out)
    end
    -- (/who: se apunta lo buscado y la respuesta la pone la prueba en w.who, con w:Fire("WHO_LIST_UPDATE"))
    api.C_FriendList = {
        SendWho = function(filter) w.whoSent[#w.whoSent + 1] = filter end,
        SetWhoToUi = function() end,
        GetNumWhoResults = function() return #w.who, w.whoTotal or #w.who end,
        GetWhoInfo = function(i) return w.who[i] end,
    }
    api.GetFramerate = function() return 60 end
    api.GetNetStats = function() return 0, 0, 50, 50 end
    api.IsShiftKeyDown = function() return false end
    api.IsControlKeyDown = function() return false end
    api.PlaySound = function() end
    api.ClearOverrideBindings = function() end
    api.SetOverrideBinding = function() end
    api.FlashClientIcon = function() end
    api.GetCurrentKeyBoardFocus = function() end
    api.GetCursorPosition = function() return 0, 0 end
    api.IsResting = function() return true end
    -- (ventanas de chat: solo la 1, la General, como en un cliente recién instalado)
    api.GetChatWindowInfo = function(i)
        if i == 1 then return "General", 14, 1, 1, 1, 1, true, false, 1, false end
        return "", 14, 1, 1, 1, 1, false, false, nil, false
    end
    api.SOUNDKIT = setmetatable({}, { __index = function() return 0 end })
    api.SendChatMessage = function(msg, kind, lang, target) w.said[#w.said + 1] = { msg = msg, kind = kind, target = target } end
    api.Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8,
        GeneralError = 9, AddOnMessageLockdown = 11, TargetOffline = 12 } }

    local function SendAddon(prefix, text, dist, target, logged)
        if w.failSend then
            local r = w.failSend(prefix, text, dist, target)
            if r ~= nil then return r end
        end
        -- (la red dice si sale: el susurro a quien no está conectado da TargetOffline, el juego saturado...)
        if w.net then
            local r = w.net:Check(w, prefix, text, dist, target)
            if r ~= 0 then return r end
        end
        w.sent[#w.sent + 1] = { prefix = prefix, text = text, dist = dist, target = target, logged = logged }
        return 0
    end
    api.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        IsAddonMessagePrefixRegistered = function() return true end,
        SendAddonMessage = function(prefix, text, dist, target) return SendAddon(prefix, text, dist, target) end,
        SendAddonMessageLogged = function(prefix, text, dist, target) return SendAddon(prefix, text, dist, target, true) end,
        GetChannelRosterInfo = ChannelRosterInfo,
        InChatMessagingLockdown = function() return w.lockdown == true end,
    }
    api.C_AddOns = {
        GetAddOnMetadata = function(_, key) return w.metadata[key] end,
        IsAddOnLoaded = function() return false end,
        GetAddOnMemoryUsage = function() return 0 end,
        UpdateAddOnMemoryUsage = function() end,
    }
    api.GetAddOnMemoryUsage = api.C_AddOns.GetAddOnMemoryUsage
    api.UpdateAddOnMemoryUsage = api.C_AddOns.UpdateAddOnMemoryUsage
    -- Rangos: 0 maestro, 1-2 oficiales (casilla «Oficial», la 22, marcada), 3-4 miembros.
    -- GuildControlGetRankFlags recibe el rango + 1, como en el juego
    local RANK_NAMES = { "Maestro", "Oficial", "Oficial", "Veterano", "Miembro" }
    api.C_GuildInfo = {
        GuildRoster = function() return api.GuildRoster() end,
        CanViewOfficerNote = function() return api.CanViewOfficerNote() end,
        GuildControlGetRankFlags = function(i)
            local flags = {}
            for k = 1, 24 do flags[k] = false end
            flags[22] = type(i) == "number" and i >= 1 and i <= 3
            return flags
        end,
    }
    api.GuildControlGetNumRanks = function() return #RANK_NAMES end
    api.GuildControlGetRankName = function(i) return RANK_NAMES[i] end

    -- Utilidades que WoW añade a Lua 5.1
    api.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    api.tinsert, api.tremove = table.insert, table.remove
    api.unpack = unpack
    api.math = mathEnv
    api.random = Random
    api.strmatch, api.strfind, api.strlower, api.strupper = string.match, string.find, string.lower, string.upper
    api.strlen, api.strsub, api.strrep, api.format, api.gsub = string.len, string.sub, string.rep, string.format, string.gsub
    api.floor, api.ceil, api.abs, api.max, api.min = math.floor, math.ceil, math.abs, math.max, math.min
    api.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    api.strsplit = function(sep, s, limit)
        local out, pos = {}, 1
        while true do
            if limit and #out == limit - 1 then break end
            local a, b = s:find("[" .. sep .. "]", pos)
            if not a then break end
            out[#out + 1] = s:sub(pos, a - 1)
            pos = b + 1
        end
        out[#out + 1] = s:sub(pos)
        return unpack(out)
    end
    api.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    api.tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
    api.CopyTable = function(t)
        local function copy(x) if type(x) ~= "table" then return x end local c = {} for k, v in pairs(x) do c[k] = copy(v) end return c end
        return copy(t)
    end
    api.Mixin = function(o, ...) for _, m in ipairs({ ... }) do for k, v in pairs(m) do o[k] = v end end return o end
    api.CreateFromMixins = function(...) return api.Mixin({}, ...) end

    for k, v in pairs(opts.api or {}) do api[k] = v end

    -- El entorno de los archivos del addon: lo del juego, luego lo de Lua
    local lua = setmetatable(api, { __index = _G })
    setmetatable(env, { __index = lua })
    env._G = env
    w.api = api
    return w
end

return wow
