-- Guild Union - canal oculto y puente del chat de hermandad
local ADDON_NAME, HU = ...
local L = HU.L

HU.chan = { main = {}, off = {} }   -- main = chat de hermandad, off = chat de oficiales, "x:Nombre" = canales extra

function HU.IsExtra(kind) return type(kind) == "string" and kind:sub(1, 2) == "x:" end
function HU.ExtraName(kind) return kind:sub(3) end

---------------------------------------------------------------------------
-- Funciones del juego que cambian de nombre entre versiones
---------------------------------------------------------------------------
local function RawSend(msg, chatType, lang, target)
    local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    -- (en pausa por la versión mínima: el addon no reenvía nada al canal)
    if not fn or HU.paused or HU:IsChatLockedDown() then return false end
    local ok, err = pcall(fn, msg, chatType, lang, target)
    if not ok then HU:RecordError(err, "send " .. tostring(chatType)) end
    return ok
end
HU.RawSend = RawSend -- (para Blacklist.lua: el aviso en el chat de oficiales)

local function RemoveChannelFromFrame(frame, name)
    if ChatFrame_RemoveChannel then
        pcall(ChatFrame_RemoveChannel, frame, name)
    elseif frame.RemoveChannel then
        pcall(frame.RemoveChannel, frame, name)
    end
end

---------------------------------------------------------------------------
-- Unirse y salir
---------------------------------------------------------------------------
HU.ready = false  -- (medio segundo tras entrar: ver el OnStart de abajo)

function HU:ApplyChannels()
    if not self.ready then return end
    local want = {}
    if self.cfg and self.cfg.ok and self.myTag then
        want.main = { name = self:LaneName(self.cfg.channel), pass = self.cfg.password }
        if self.offCfg and self:CanOfficer() then
            want.off = { name = self.offCfg.channel, pass = self.offCfg.password }
        end
        -- canales extra creados por los oficiales
        for _, x in pairs(self.db.extraChans or {}) do
            if not x.del then want["x:" .. x.name] = { name = x.name, pass = x.pass } end
        end
    end
    -- canales del addon en los que sigo de antes (el juego te deja dentro aunque recargues o te
    -- echen de la hermandad): si ya no tocan, se sale
    self.db.joinedChans = self.db.joinedChans or {}
    local wanted = {}
    for _, w in pairs(want) do if w.name then wanted[w.name:lower()] = true end end
    -- (al entrar al juego, la hermandad tarda en cargar: no se sale de nada los primeros 30 s [+ARCHITECTURE.md]
    local settled = (self.cfg ~= nil and not self.cfg.quick) or (GetTime() - (HU.loginT or 0) > 30)
    for name in pairs(self.db.joinedChans) do
        if settled and not wanted[name] then
            if LeaveChannelByName and GetChannelName and (GetChannelName(name) or 0) > 0 then pcall(LeaveChannelByName, name) end
            self.db.joinedChans[name] = nil
        end
    end
    for name in pairs(wanted) do self.db.joinedChans[name] = true end
    if not settled and not HU.staleCheck then
        HU.staleCheck = true
        HU.After(31, function() HU.staleCheck = nil; HU:ApplyChannels() end)
    end
    local kinds = {}
    for k in pairs(self.chan) do kinds[k] = true end
    for k in pairs(want) do kinds[k] = true end
    for kind in pairs(kinds) do
        self.chan[kind] = self.chan[kind] or {}
        local cur, w = self.chan[kind], want[kind]
        if cur.name and (not w or w.name:lower() ~= cur.name:lower()) then
            if LeaveChannelByName then pcall(LeaveChannelByName, cur.name) end
            self:Debug("Has salido del canal", cur.name)
            self.chan[kind] = (kind == "main" or kind == "off") and {} or nil
            cur = self.chan[kind] or {}
        end
        if w then
            self.chan[kind] = cur
            if cur.pass ~= w.pass then cur.backoff = nil; cur.lastTry = nil end
            cur.name, cur.pass = w.name, w.pass
            self:EnsureJoined(kind)
        elseif kind ~= "main" and kind ~= "off" then
            self.chan[kind] = nil
        end
    end
    self:Changed("channel")
end

function HU:ChannelId(kind)
    local c = self.chan[kind]
    if not c or not c.name then return nil end
    local id = GetChannelName(c.name)
    if id and id > 0 then return id end
    return nil
end

function HU:IsJoined(kind)
    return self:ChannelId(kind) ~= nil
end

-- La lista de miembros de un canal se le pide al juego con la POSICIÓN del canal en la ventana [+ARCHITECTURE.md]
local rosterSel, rosterDirty = {}, {}
-- (alguien ha entrado o salido del canal: la próxima lectura pide la lista de nuevo)
function HU:ChannelRosterChanged(kind)
    rosterDirty[kind] = true
    if self.ForgetChannelMembers then self:ForgetChannelMembers() end
end
-- ¿Necesito leer la lista entera del canal por mi cuenta? Solo el enlace (busca moderadores a los [+ARCHITECTURE.md]
function HU:NeedsChannelList()
    if self:IsTest() or self.chanIAmMod == true or self:IsRelay() then return true end
    local idx = self.MyRankIndex and self:MyRankIndex()
    return idx ~= nil and self.myTag ~= nil and self:RankRole(self.myTag, idx) ~= nil
end

function HU:ChannelRoster(kind)
    local id = self:ChannelId(kind)
    if not id then return nil end
    local info = C_ChatInfo and C_ChatInfo.GetChannelRosterInfo
    if not info then return nil end
    if GetNumDisplayChannels and GetChannelDisplayInfo then
        local n, mine, other = GetNumDisplayChannels() or 0, nil, nil
        for i = 1, n do
            local _, header, _, localID, count = GetChannelDisplayInfo(i)
            if not header and localID == id then mine = { i = i, count = tonumber(count) or 0 }
            elseif not header and localID and localID > 0 and not other then other = i end
            if mine and other then break end
        end
        if not mine then return nil end
        -- (con la ventana de canales de Blizzard abierta no se le cambia el canal que mira: si mira [+ARCHITECTURE.md]
        local cf = ChannelFrame
        if cf and cf.IsShown and cf:IsShown() then
            local list = cf.GetList and cf:GetList()
            local b = list and list.GetSelectedChannelButton and list:GetSelectedChannelButton()
            local sel = b and b.GetChannelID and b:GetChannelID()
            if sel ~= mine.i then return nil end
            return mine.i, mine.count, info, id
        end
        local s = rosterSel[kind]
        if SetSelectedDisplayChannel and (not s or s.i ~= mine.i or rosterDirty[kind] or GetTime() - s.t > 30) then
            rosterSel[kind], rosterDirty[kind] = { i = mine.i, t = GetTime() }, nil
            -- (volver a seleccionar el mismo canal no hace que el juego pida la lista otra vez: se
            -- pasa un momento por otro canal y se vuelve, y así la pide de nuevo)
            if other and s and s.i == mine.i then pcall(SetSelectedDisplayChannel, other) end
            pcall(SetSelectedDisplayChannel, mine.i)
        end
        return mine.i, mine.count, info, id
    end
    local num = GetNumChannelMembers and GetNumChannelMembers(id)
    return id, num or 0, info, id
end

-- ¿De qué canal mío viene un mensaje de addon? (localID y channelName son los argumentos 7 y 8 de [+ARCHITECTURE.md]
function HU:OurChannelKind(localID, chanName)
    -- (por número: el más fiable, si el cliente lo da)
    if type(localID) == "number" and localID > 0 then
        for kind, c in pairs(self.chan) do
            if c.name and self:ChannelId(kind) == localID then return kind end
        end
    end
    local name = type(chanName) == "string" and chanName ~= "" and chanName or nil
    if not name and type(localID) == "number" and localID > 0 then
        local _, n = GetChannelName(localID)
        name = n
    end
    if not name then return true end
    -- (el juego puede dar el nombre como «7. Canal»: se quita el número)
    name = name:lower():gsub("^%d+%.%s*", "")
    for kind, c in pairs(self.chan) do
        if c.name and c.name:lower() == name then return kind end
    end
    -- (número dado pero de un canal que no es nuestro, y el nombre tampoco: no es nuestro)
    return nil
end

-- ¿Se puede intentar entrar a un canal ahora? En un campo de batalla o una arena (y desde que se
-- acepta la partida) el juego lo bloquea, y cada intento bloqueado cuenta para su aviso de
-- «tus addons están dando muchos problemas» [+ARCHITECTURE.md]
local PVP_ZONE = { pvp = true, arena = true }
local JOIN_BLOCKED_WAIT = 60
-- ¿Dentro de una partida, o ya aceptada (botón «Entrar») aunque siga la pantalla de carga?
function HU:InPvpNow()
    if IsInInstance then
        local inInst, kind = IsInInstance()
        if inInst and PVP_ZONE[kind] then return true end
    end
    if GetBattlefieldStatus then
        local n = (GetMaxBattlefieldID and tonumber(GetMaxBattlefieldID())) or 3
        for i = 1, n do
            local ok, status = pcall(GetBattlefieldStatus, i)
            if ok and not HU.Secret(status) and status == "active" then return true end
        end
    end
    return false
end
function HU:CanJoinNow()
    return not self:IsChatLockedDown() and not self:InPvpNow()
end

function HU:EnsureJoined(kind)
    local c = self.chan[kind]
    if not c.name then return end
    if self:ChannelId(kind) then
        if not c.joined then
            c.joined = true
            c.backoff = nil
            self:HideChannel(c.name)
        end
        return
    end
    c.joined = false
    local now = GetTime()
    if c.blockedT and now - c.blockedT < JOIN_BLOCKED_WAIT then return end
    if not self:CanJoinNow() then return end
    -- (los primeros 20 s tras entrar se reintenta cada segundo: el chat tiene que ir enseguida)
    -- (y en ese rato la espera larga no crece: si no, al acabar se esperaban 5 minutos)
    local fast = now - (HU.loginT or -1e9) < 20
    local wait = fast and 1 or (c.backoff or 10)
    if c.lastTry and now - c.lastTry < wait then return end
    c.lastTry = now
    if not fast then c.backoff = math.min((c.backoff or 5) * 2, 300) end
    self:Debug("Uniéndose a", c.name)
    local join = JoinTemporaryChannel or (C_ChatInfo and C_ChatInfo.JoinTemporaryChannel)
    if not join then return end
    -- (bloqueado donde no se esperaba: nada de reintentos seguidos, se espera un minuto)
    HU.expectBlock, HU.joinBlockedNow = "join", nil
    pcall(join, c.name, c.pass)
    HU.expectBlock = nil
    if HU.joinBlockedNow then c.blockedT = now end
end

-- Al cambiar de zona (salir de la partida): se vuelve a mirar enseguida, sin esperar al ciclo
local function RejoinSoon()
    HU.After(2, function()
        if not HU.ready then return end
        for kind, c in pairs(HU.chan) do
            c.lastTry, c.blockedT = nil, nil
            HU:EnsureJoined(kind)
        end
    end)
end
HU:On("PLAYER_ENTERING_WORLD", RejoinSoon)
HU:On("ZONE_CHANGED_NEW_AREA", RejoinSoon)

-- ¿Es un canal del juego? («General - Elwynn», «Comercio (Servicios) - Ventormenta»...)
local function IsGameChannel(fullName)
    if type(fullName) ~= "string" or not HU.GAME_CHANNELS then return false end
    local n = fullName:lower():gsub("%s+%-%s+.*$", ""):gsub("%b()", ""):gsub("[%s%-_]", "")
    return HU.GAME_CHANNELS[n] == true
end

-- Si el nuestro está delante de un canal del juego, se cambian de sitio (uno cada vez). [+ARCHITECTURE.md]
-- Solo funciona desde algo que hace el jugador: clic, Intro (probado por Jorge el 10/11)
local function MisplacedChannel()
    for _, c in pairs(HU.chan or {}) do
        local id = c.name and GetChannelName(c.name)
        if id and id > 0 then
            for g = id + 1, (MAX_WOW_CHAT_CHANNELS or 10) do
                local other, otherName = GetChannelName(g)
                if other and other > 0 and IsGameChannel(otherName) then return id, g end
            end
        end
    end
end

local orderFrame = CreateFrame("Frame")
local orderT = -1
-- Los clics solo se escuchan mientras el orden está mal
function HU:WatchChannelOrder()
    if MisplacedChannel() then orderFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
    else orderFrame:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
end
function HU:FixChannelOrder()
    local fn = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
    local now = GetTime()
    if not fn or now - orderT < 0.5 then return end
    local id, g = MisplacedChannel()
    if not id then return end
    orderT = now
    pcall(fn, id, g)
    HU.After(0.5, function() HU:WatchChannelOrder() end)
end
orderFrame:SetScript("OnEvent", function(_, event)
    if event == "GLOBAL_MOUSE_DOWN" then HU:SafeCall("orden de canales", HU.FixChannelOrder, HU)
    else HU:SafeCall("orden de canales", HU.WatchChannelOrder, HU) end
end)
orderFrame:RegisterEvent("CHANNEL_UI_UPDATE")
orderFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")

function HU:HideChannel(name)
    if self.db and self.db.showChannel then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local f = _G["ChatFrame" .. i]
        if f then RemoveChannelFromFrame(f, name) end
    end
end

function HU:KindOf(baseName, fullName)
    local n = baseName
    if (not n or n == "") and type(fullName) == "string" then
        n = fullName:match("^%d+%.%s*(.+)$") or fullName
    end
    if type(n) ~= "string" or n == "" then return nil end
    n = n:lower()
    for kind, c in pairs(self.chan) do
        if c.name and c.name:lower() == n then return kind end
    end
    return nil
end

-- Al entrar: medio segundo después ya se entra al canal (con la configuración guardada si la de [+ARCHITECTURE.md]
-- (se espera a que el juego meta sus canales, General y compañía, para no quitarle el /1 a nadie:
-- con medio segundo, en un PC lento el nuestro entraba antes y se quedaba con el /1; como mucho 15 s)
local START_WAIT = 15
HU:OnStart(function()
    local t0 = GetTime()
    local function Start()
        HU.ready = true
        HU:RefreshConfig(true)
        if not HU.cfg then HU:QuickConfig() end
        HU:ApplyChannels()
    end
    local function AnyGameChannel()
        for i = 1, (MAX_WOW_CHAT_CHANNELS or 10) do
            local id, name = GetChannelName(i)
            if id and id > 0 and IsGameChannel(name) then return true end
        end
        return false
    end
    local function TryStart()
        if AnyGameChannel() or GetTime() - t0 >= START_WAIT then
            Start()
            HU.After(2, function() HU:WatchChannelOrder() end)
            return
        end
        HU.After(0.5, TryStart)
    end
    HU.After(0.5, TryStart)
    -- (y otra vez a los 10 s, por si la Información de hermandad tardó)
    HU.After(10, function() HU:RefreshConfig(true) end)
    HU.NewTicker(1, function()
        for kind in pairs(HU.chan) do HU:EnsureJoined(kind) end
    end, 20)
    HU.NewTicker(10, function()
        for kind in pairs(HU.chan) do HU:EnsureJoined(kind) end
    end)
end)

HU:On("CHAT_MSG_CHANNEL_NOTICE", function(notice, _, _, fullName, _, _, _, _, baseName)
    local kind = HU:KindOf(baseName, fullName)
    if not kind then return end
    local c = HU.chan[kind]
    if notice == "YOU_JOINED" or notice == "YOU_CHANGED" then
        c.joined, c.backoff = true, nil
        HU.After(0.5, function() HU:HideChannel(c.name) end)
        HU:Debug("Conectado al canal", c.name, kind)
        if kind == "main" and HU.OnMainJoined then HU:OnMainJoined() end
    elseif notice == "YOU_LEFT" then
        c.joined = false
    elseif notice == "WRONG_PASSWORD" then
        HU:Print(L("|cffff4444Contraseña incorrecta|r para el canal ") .. c.name .. L(". Revisa la línea HU:")
            .. (kind == "off" and "o" or "c") .. L(" de la configuración."))
    elseif notice == "BANNED" then
        HU:Print(L("|cffff4444Estás vetado|r del canal ") .. c.name .. L(". Pide a un moderador que te quite el veto."))
    end
    HU:Changed("channel")
end)

HU:On("CHAT_MSG_CHANNEL_NOTICE_USER", function(notice, _, _, fullName, _, _, _, _, baseName)
    if HU:KindOf(baseName, fullName) and HU.OnChannelRolesChanged then
        HU:OnChannelRolesChanged(notice)
    end
end)

-- entradas y salidas del canal: solo las usa quien lee la lista del canal (enlace, oficiales, [+ARCHITECTURE.md]
local needsT, needsV = -999, false
local function NeedsChannelListCached()
    local now = GetTime()
    if now - needsT > 1 then needsT, needsV = now, HU:NeedsChannelList() end
    return needsV
end
for _, ev in ipairs({ "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE", "CHAT_MSG_CHANNEL_NOTICE_USER" }) do
    HU:On(ev, function(_, author, _, fullName, _, _, _, _, baseName)
        if not NeedsChannelListCached() then return end
        local kind = HU:KindOf(baseName, fullName)
        if not kind then return end
        HU:ChannelRosterChanged(kind)
        if kind ~= "main" then return end
        if ev == "CHAT_MSG_CHANNEL_JOIN" and HU.OnSomeoneJoined then HU:OnSomeoneJoined(author)
        elseif ev == "CHAT_MSG_CHANNEL_LEAVE" and HU.OnSomeoneLeft then HU:OnSomeoneLeft(author) end
    end)
end

---------------------------------------------------------------------------
-- Partir mensajes largos sin romper enlaces de objetos
---------------------------------------------------------------------------
function HU.SplitMessage(msg, max)
    if #msg <= max then return { msg } end
    local atoms, i, n = {}, 1, #msg
    while i <= n do
        local a, b = msg:find("^|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r", i)
        if not a then a, b = msg:find("^|H.-|h.-|h", i) end
        if a then
            atoms[#atoms + 1] = msg:sub(a, b)
            i = b + 1
        else
            local c = msg:byte(i)
            local len = (c >= 240 and 4) or (c >= 224 and 3) or (c >= 192 and 2) or 1
            atoms[#atoms + 1] = msg:sub(i, i + len - 1)
            i = i + len
        end
    end

    local parts, cur, size, lastSpace = {}, {}, 0, nil
    local function flush(upto)
        local keep = {}
        upto = upto or #cur
        for k = upto + 1, #cur do keep[#keep + 1] = cur[k] end
        local text = HU.Trim(table.concat(cur, "", 1, upto))
        if text ~= "" then parts[#parts + 1] = text end
        cur, size, lastSpace = {}, 0, nil
        for _, at in ipairs(keep) do
            cur[#cur + 1] = at
            size = size + #at
            if at == " " then lastSpace = #cur end
        end
    end
    for _, at in ipairs(atoms) do
        if size + #at > max then
            if lastSpace and lastSpace > 1 then flush(lastSpace) else flush() end
        end
        cur[#cur + 1] = at
        size = size + #at
        if at == " " then lastSpace = #cur end
    end
    flush()
    return parts
end

---------------------------------------------------------------------------
-- Enviar: copiamos al canal lo que se escribe en /g y /o
---------------------------------------------------------------------------
local lastSig, lastTime = nil, 0

function HU:Forward(kind, msg)
    if not self.myTag then return end
    -- antes de enviar: comprobar que de verdad estoy en mi hermandad (y que es una de las unidas)
    if not self:IsTest() then
        -- (recién entrado con la configuración guardada, el juego aún puede no dar la hermandad ni la [+ARCHITECTURE.md]
        local quick = self.cfg and self.cfg.quick
        local gameGuild = IsInGuild() and GetGuildInfo("player")
        local gname = gameGuild or (IsInGuild() and quick and self.guildName)
        local rosterKnown = self.rosterList and #self.rosterList > 0
        if not gname or not self.cfg or not self.cfg.byName[gname:lower()] or (rosterKnown and not self.roster[self:MeKey()]) or (not rosterKnown and not quick and not gameGuild) then
            self:Debug("No se envía: no estás (todavía) en una de las hermandades unidas")
            return
        end
    end
    if kind ~= "off" and self.IsMuted and self:IsMuted(self:Me()) then
        self:Print(L("|cffff4444Estás silenciado en el chat de ") .. HU:Title() .. "|r (" .. (self:MuteLeftText(self:Me()) or "") .. L("): tu mensaje no ha llegado a las otras hermandades."))
        return
    end
    local sub = ""
    local id = self:ChannelId(kind == "off" and "off" or (HU.IsExtra(kind) and kind or "main"))
    if kind == "off" and not id and self:IsTest() then
        -- en modo prueba no hay canal de oficiales: va por el canal de prueba marcado
        id, sub = self:ChannelId("main"), ":O"
    end
    -- (todavía no estoy en el canal, recién entrado: antes se perdía; ahora va por el respaldo)
    if not id and kind ~= "off" and not HU.IsExtra(kind) and self.cfg and not self:IsTest() then
        local prefix0 = "[" .. self.myTag .. sub .. "] "
        for _, part in ipairs(HU.SplitMessage(msg, 255 - #prefix0 - 1 - 60)) do self:ChatFallback("m", prefix0 .. part) end
        return
    end
    if not id then return end
    local prefix = "[" .. self.myTag .. sub .. "] "
    local chanKind = (kind == "off" and id ~= self:ChannelId("main")) and "off" or (HU.IsExtra(kind) and kind or "main")
    local token = (chanKind == "main" and "m") or (chanKind == "off" and "o") or chanKind
    -- (por si hay que mandarlo por el respaldo: "CG~canal~autor~" delante, que también tiene que caber)
    for _, part in ipairs(HU.SplitMessage(msg, 255 - #prefix - #token - 60)) do
        local line = prefix .. part
        if self:TextChatOK() then
            HU.expectBlock, HU.chatBlockedNow = "chat", nil
            local ok = RawSend(line, "CHANNEL", nil, id)
            HU.expectBlock = nil
            if HU.chatBlockedNow or not ok then
                self:TextChatFailed("bloqueado")
                self:ChatFallback(token, line)
            else
                self:WatchEcho(chanKind, token, line)
            end
        else
            self:ChatFallback(token, line)
        end
    end
end

---------------------------------------------------------------------------
-- Si el texto no sale por el canal. En Forever, lo oculto del addon por un canal el juego lo acepta [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- (el eco suele volver en ~0,2 s. La primera vez que falla, 5 min por susurro; si al volver a
-- probar falla otra vez en la misma sesión, 15 min)
local ECHO_WAIT = 1
local TEXT_RETRY, TEXT_RETRY_AGAIN = 300, 900
local textDeadT, textFails = nil, 0
local echoWait = {} -- [línea] = { t, token }
local function TextRetry() return textFails >= 2 and TEXT_RETRY_AGAIN or TEXT_RETRY end
function HU:TextChatOK() return not (textDeadT and GetTime() - textDeadT < TextRetry()) end
function HU:TextChatFailed(why)
    if not self:TextChatOK() then return end
    textDeadT, textFails = GetTime(), textFails + 1
    self:Debug("El texto del canal no llega (" .. tostring(why) .. "): el chat va por susurro " .. TextRetry() .. " s")
end
function HU:WatchEcho(chanKind, token, line)
    local k = HU.Trim(line)
    echoWait[k] = { t = GetTime(), token = token, kind = chanKind }
    HU.After(ECHO_WAIT, function()
        local w = echoWait[k]
        if not w then return end
        echoWait[k] = nil
        HU:TextChatFailed("sin eco")
        HU:ChatFallback(w.token, line)
    end)
end
-- (mi propia línea ha vuelto por el canal: ha llegado)
function HU:GotEcho(text)
    if type(text) == "string" then echoWait[HU.Trim(text)] = nil end
end

-- Formatos:  CW~canal~autor~[ETIQ] msg  (susurro a un contacto de otra hermandad) [+ARCHITECTURE.md]
local MAX_OFF_TARGETS = 15
local FEW_DIRECT = 4
local function SendCW(self, tag, token, author, line)
    local p = self:BestPeer(tag)
    if p and p.name then self:Whisper(p.name, "CW~" .. token .. "~" .. author .. "~" .. line, true) end
end
function HU:ChatFallback(token, line)
    if not self.myTag or not self.cfg then return end
    local me = self:Me()
    if not me then return end
    if token == "o" then
        -- (lo de oficiales nunca va por GUILD: a cada oficial conectado de las otras hermandades)
        local n = 0
        for tag, r in pairs(self.remoteRoster or {}) do
            if tag ~= self.myTag then
                for _, m in ipairs(r.members or {}) do
                    if n >= MAX_OFF_TARGETS then break end
                    if m.name and not m.weak and self:RankRole(tag, m.rankIndex) then
                        n = n + 1
                        self:Whisper(m.name, "CW~o~" .. me .. "~" .. line, true)
                    end
                end
            end
        end
        return
    end
    local tags = self:OtherTags()
    if #tags > FEW_DIRECT and self:KnownGuildRelay() then
        -- (mi propio CF no me vuelve: si estoy en el equipo, mis hermandades las mando yo)
        self:Send("CF~" .. token .. "~" .. line, "GUILD", nil, true)
        for _, tag in ipairs(tags) do
            if self:HandlesTag(tag) then SendCW(self, tag, token, me, line) end
        end
        return
    end
    for _, tag in ipairs(tags) do SendCW(self, tag, token, me, line) end
end

-- Una línea mía del respaldo que se ha caducado en la cola sin salir (lo llama Comm.lua)
local lostCWT = -999
function HU:OnChatLost(raw)
    if type(raw) ~= "string" then return end
    local mine = raw:sub(1, 3) == "CF~"
    if not mine and raw:sub(1, 3) == "CW~" then
        local author = raw:match("^CW~[^~]*~([^~]*)~")
        mine = author and author:lower() == (self:MeKey() or "")
    end
    if not mine then return end
    self.qStats = self.qStats or {}
    self.qStats.chatLost = (self.qStats.chatLost or 0) + 1
    if GetTime() - lostCWT < 30 then return end
    lostCWT = GetTime()
    self:Print("|cffff8800" .. L("Tu mensaje no ha llegado a alguna de las otras hermandades: el juego no dejaba enviarlo a tiempo.") .. "|r")
end

-- (cada remitente: 6 de golpe y luego uno cada 1,2 s, como Olympus; así nadie inunda mi hermandad)
local cwBucket, cwKeys = {}, 0
-- (burst de golpe y luego rate por segundo)
local function CWAllowedN(key, burst, rate)
    local k, now = key:lower(), GetTime()
    local b = cwBucket[k]
    if not b then
        if cwKeys > 3000 then cwBucket, cwKeys = {}, 0 end
        b = { n = burst, t = now }; cwBucket[k] = b; cwKeys = cwKeys + 1
    end
    b.n = math.min(burst, b.n + (now - b.t) * rate)
    b.t = now
    if b.n < 1 then return false end
    b.n = b.n - 1
    return true
end
local function CWAllowed(key) return CWAllowedN(key, 6, 1 / 1.2) end
-- (y uno por quien lo trae, sea quien sea el autor: si no, cambiando de autor en cada línea no
-- tenía límite. 40 de golpe y 2 por segundo, más de lo que reparte un contacto de verdad)
local function CarrierAllowed(key) return CWAllowedN(key, 40, 2) end
-- Registro: «X reenvió por la hermandad un mensaje de Y». Solo en mi registro (no se reparte) y una
-- vez cada 10 min por reenviador y autor: si todo el chat va por el respaldo, no llena el registro
local auditedCG = {}
function HU:AuditRelayedLine(sender, author, line)
    if not self.AddAudit then return end
    local k, now = (sender .. "\0" .. author):lower(), GetTime()
    if auditedCG[k] and now - auditedCG[k] < 600 then return end
    auditedCG[k] = now
    local tag = line:match("^%[(%w+)")
    self:AddAudit({ tag = self.myTag, actor = sender,
        text = L("reenvió por la hermandad un mensaje de ") .. self:Short(author) .. (tag and (" <" .. tag .. ">") or "")
            .. ": «" .. HU.Utf8Cut(HU.SafeText(line:gsub("^%[[^%]]*%]%s*", ""), false), 60) .. "»" })
end

local function TokenKind(token)
    if token == "m" then return "main" end
    if token == "o" then return "off" end
    if type(token) == "string" and token:sub(1, 2) == "x:" then return token end
    return nil
end
-- (Comm.lua crea HU.comm después de cargar este archivo: las órdenes se ponen al empezar)
HU:OnStart(function()
    -- CW~canal~autor~[ETIQ] mensaje : por susurro, del autor o de un compañero suyo que lo reparte
    HU.comm.CW = function(self, sender, f, dist)
        if dist ~= "WHISPER" or not self.myTag or not self.cfg then return end
        local kind = TokenKind(f[1])
        local author = HU.SafeName(f[2]) and self:FullName(f[2])
        local line = table.concat(f, "~", 3)
        local tag = line:match("^%[(%w+)")
        if not kind or not author or not tag or tag == self.myTag or not self.cfg.byTag[tag] then return end
        -- (quien lo trae tiene que ser de esa hermandad, si ya tengo su lista; el autor lo mira [+ARCHITECTURE.md]
        if not self:MemberOf(sender, tag) then
            local W = self.whitelist[tag]
            if W and time() - (W.t or 0) < 86400 then return end
            if W or self.remoteRoster[tag] then
                local g = self.guardKnown and self.guardKnown[self:Key(sender) or ""]
                if (self.GuardVerdict and self:GuardVerdict(sender) == true)
                    or (g ~= nil and g.tag ~= tag and self:GuardKnown(sender)) then return end
            end
        end
        -- (el tope es por quien lo trae y autor: un compañero que reparte lo de toda su hermandad [+ARCHITECTURE.md]
        local inner = line:match("^%[%w+:E%] ([^:]+): ")
        if not CWAllowed(sender .. "|" .. author .. (inner and (">" .. inner) or "")) or not CarrierAllowed("w:" .. sender) then return end
        if kind == "off" then
            -- (lo de oficiales solo directo del autor, que tiene que ser oficial)
            if author:lower() ~= sender:lower() then return end
            if not self:CanOfficer() or self:TrustedOfficer(sender, tag) ~= true then return end
            return self:OnUnionChat("off", line, sender, nil, "w")
        end
        -- (a mi hermandad, y a mí. Si nadie más de mi hermandad tiene el addon, no se reparte: era un
        -- mensaje por línea para nadie, y basura en la cola; 08/11, prueba de 2 personas)
        local now, peers = GetTime(), false
        for _, p in pairs(self.guildPeers or {}) do
            if now - (p.last or 0) < (HU.PEER_TTL or 700) then peers = true break end
        end
        if peers then self:Send("CG~" .. f[1] .. "~" .. author .. "~" .. line, "GUILD", nil, true) end
        self:OnUnionChat(kind, line, author, nil, "w")
    end
    -- CF~canal~[ETIQ] mensaje : por GUILD, de un compañero cuyo texto no sale por el canal
    HU.comm.CF = function(self, sender, f, dist)
        if dist ~= "GUILD" or not self.myTag or not self.cfg then return end
        if not self:IsTest() and not self.roster[self:Key(sender) or ""] then return end
        if f[1] == "o" or not TokenKind(f[1]) then return end
        local line = table.concat(f, "~", 2)
        if line:match("^%[(%w+)") ~= self.myTag then return end
        if not CWAllowed("f:" .. sender) then return end
        for _, tag in ipairs(self:OtherTags()) do
            if self:HandlesTag(tag) then SendCW(self, tag, f[1], sender, line) end
        end
    end
    -- CG~canal~autor~[ETIQ] mensaje : por GUILD, de un compañero que lo recibió por susurro [+ARCHITECTURE.md]
    HU.comm.CG = function(self, sender, f, dist)
        if dist ~= "GUILD" or not self.myTag then return end
        if not self:IsTest() and not self.roster[self:Key(sender) or ""] then return end
        local kind = TokenKind(f[1])
        if not kind or kind == "off" then return end
        if HU.IsExtra(kind) and not self:IsJoined(kind) then return end
        local author = HU.SafeName(f[2]) and self:FullName(f[2])
        if not author then return end
        local line = table.concat(f, "~", 3)
        local inner = line:match("^%[%w+:E%] ([^:]+): ")
        if not CWAllowed("g:" .. sender .. "|" .. author .. (inner and (">" .. inner) or "")) or not CarrierAllowed("gs:" .. sender) then return end
        if self:OnUnionChat(kind, line, author, nil, "w") then self:AuditRelayedLine(sender, author, line) end
    end
end)

---------------------------------------------------------------------------
-- Carriles del canal (lo que le pasó a Olympus la noche del lanzamiento de Forever): el juego puede [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local LANE_AFTER, LANE_MAX = 3, 9
local LANE_TTL = 6 * 3600      -- un carril alto caduca a las 6 h de subirse (a la vez para todos)
local LANE_CONFIRM = 10        -- segundo sondeo antes de mudarse por rechazos
local LANE_PROBE_EVERY = 10    -- el enlace sondea si lleva esto sin mandar nada al canal
local LANE_ADOPT_GAP = 120     -- como mucho un cambio cada 2 min por lo que digan otros
local LANE_GEN_STEP = 1        -- la generación de otro solo vale si es como mucho 1 más que la mía
local LANE_GEN_MAX = 99999
HU.LANE_TTL = LANE_TTL
local laneRefused, laneConfirmT, laneAdoptT = 0, nil, -999
local lastChannelSend = -999 -- (último envío del addon al canal principal, con el resultado que fuera)
local function ServerNow() return (GetServerTime and GetServerTime()) or time() end

-- Estado del carril de la comunidad: { lane, gen, t }. Se guarda en la cuenta, por canal de la [+ARCHITECTURE.md]
function HU:LaneState()
    local old = self.db and tonumber(self.db.chanLane) or 0
    if old ~= old or old < 0 or old > LANE_MAX then old = 0 end
    old = math.floor(old)
    local key = self.db and self.cfg and type(self.cfg.channel) == "string" and self.cfg.channel ~= "" and self.cfg.channel:lower()
    if not key then return { lane = old, gen = 0, t = ServerNow() } end
    self.db.lanes = self.db.lanes or {}
    local st = self.db.lanes[key]
    if type(st) ~= "table" then
        st = { lane = old, gen = 0, t = ServerNow() }
        self.db.lanes[key] = st
    elseif (st.gen or 0) == 0 and old > (st.lane or 0) then
        -- (un personaje que se quedó más arriba antes de la 5.4.8)
        st.lane, st.t = old, ServerNow()
    end
    st.lane, st.gen, st.t = tonumber(st.lane) or 0, tonumber(st.gen) or 0, tonumber(st.t) or ServerNow()
    return st
end
function HU:ChannelLane()
    local n = self:LaneState().lane
    if n ~= n or n < 0 or n > LANE_MAX then return 0 end
    return math.floor(n)
end
-- Lo que llega en un saludo o en LN. nil si no tiene sentido (hora del futuro, números raros...)
function HU.ParseLane(lane, gen, t)
    lane, gen = tonumber(lane), tonumber(gen ~= "" and gen or 0)
    if not lane or lane ~= lane or lane < 0 or lane > LANE_MAX or not gen or gen ~= gen or gen < 0 or gen > LANE_GEN_MAX then return nil end
    local now = ServerNow()
    t = tonumber(t ~= "" and t or nil)
    if t == nil then t = now
    elseif t ~= t or t > now + 60 or t < 1577836800 then return nil end
    return { lane = math.floor(lane), gen = math.floor(gen), t = math.floor(t) }
end
-- ¿a es mejor que b? Generación más alta; luego carril más alto; luego la hora más antigua
local function LaneBetter(a, b)
    if a.gen ~= b.gen then return a.gen > b.gen end
    if a.lane ~= b.lane then return a.lane > b.lane end
    return a.lane > 0 and a.t < b.t
end
-- spread: "all" = mi hermandad y el enlace de cada otra; "guild" = solo mi hermandad
local function SpreadLane(self, st, spread)
    local msg = "LN~" .. st.lane .. "~" .. st.gen .. "~" .. st.t
    if self.myTag and IsInGuild() then self:Send(msg, "GUILD") end
    if spread == "all" and self.OtherTags then
        for _, tag in ipairs(self:OtherTags()) do
            local p = self.KnownRelay and self:KnownRelay(tag) or (self.BestPeer and self:BestPeer(tag))
            if p then self:Whisper(p.name, msg, true) end
        end
    end
end
function HU:SetLaneState(new, why, spread)
    if not self.db then return false end
    local st = self:LaneState()
    local moved = new.lane ~= st.lane
    st.lane, st.gen, st.t = new.lane, new.gen, new.t
    self.db.chanLane = st.lane
    laneRefused, laneConfirmT = 0, nil
    if moved then
        HU.laneMoves = (HU.laneMoves or 0) + 1
        self:Log(L("Carril del canal: ") .. st.lane .. " (" .. tostring(why) .. ")")
        self:ApplyChannels()
        HU.After(5, function() if HU.HelloCycle then HU:HelloCycle() end end)
    end
    if spread then SpreadLane(self, st, spread) end
    return true
end
-- Otro dice en qué carril está la comunidad: se sigue el más alto, pero solo si lo dice alguien [+ARCHITECTURE.md]
local laneWeakProbeT, laneContactT = -999, -999
local LANE_CONTACT_GAP = 600
function HU:OfferLane(new, from, strong)
    if not new or not self.db or not self.cfg then return false end
    local now = ServerNow()
    if new.lane > 0 and now - new.t > LANE_TTL then return false end -- (ya caducado: él también vuelve)
    local st = self:LaneState()
    if not LaneBetter(new, st) then return false end
    -- (el contacto de otra hermandad, sin comprobar: solo el enlace de mi hermandad le hace caso, y solo [+ARCHITECTURE.md]
    if strong == "contact" then
        if self:IsRelay() and new.gen == st.gen and new.lane == st.lane + 1
            and GetTime() - laneContactT > LANE_CONTACT_GAP and GetTime() - laneAdoptT >= LANE_ADOPT_GAP then
            laneContactT, laneAdoptT = GetTime(), GetTime()
            return self:SetLaneState(new, L("según ") .. tostring(from), "guild")
        end
        strong = false
    end
    if not strong then
        if new.lane > st.lane and GetTime() - laneWeakProbeT > 20 then
            laneWeakProbeT = GetTime()
            self:ProbeLane()
        end
        return false
    end
    if new.gen > st.gen + LANE_GEN_STEP then return false end
    if new.gen == st.gen and new.lane == st.lane then
        st.t = new.t -- (solo la hora: se iguala sin mudarse)
        return true
    end
    if GetTime() - laneAdoptT < LANE_ADOPT_GAP then return false end
    laneAdoptT = GetTime()
    return self:SetLaneState(new, L("según ") .. tostring(from), self:IsRelay() and "guild" or nil)
end
-- /gu carril reiniciar (oficiales): todos al canal principal, con una generación nueva
function HU:ResetLane()
    local st = self:LaneState()
    return self:SetLaneState({ lane = 0, gen = math.min(LANE_GEN_MAX, st.gen + 1), t = ServerNow() },
        L("reinicio de ") .. tostring(self:Me()), "all")
end
-- 5 letras fijas para cada carril (las mismas para todos los que tengan el mismo canal y contraseña)
local function LaneSuffix(base, pass, n)
    local s = base:lower() .. "\0" .. (pass or "") .. "\0" .. n
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 16777213 end
    local out = {}
    for i = 1, 5 do
        out[i] = string.char(97 + h % 26)
        h = math.floor(h / 26) + (n * 7919 + i * 104729) % 16777213
    end
    return table.concat(out)
end
HU.LaneSuffix = LaneSuffix
function HU:LaneName(base)
    local n = self:ChannelLane()
    if not base or n == 0 then return base end
    return base .. LaneSuffix(base, self.cfg and self.cfg.password, n)
end
-- Subir de carril porque a mí me rechazan: lo digo a mi hermandad y, si soy el enlace, al enlace
-- de cada otra hermandad por susurro (que sigue funcionando). Ellos lo siguen sin sondear.
function HU:MoveLane(n, why)
    n = tonumber(n)
    local st = self.db and self:LaneState()
    if not st or not n or n ~= n or n <= st.lane or n > LANE_MAX then return false end
    return self:SetLaneState({ lane = math.floor(n), gen = st.gen, t = ServerNow() },
        L("el canal no aceptaba mensajes: ") .. tostring(why), self:IsRelay() and "all" or "guild")
end
-- Sondeo: un mensaje pequeño al canal (n, si se pide más); si el juego lo rechaza, ChannelSendResult [+ARCHITECTURE.md]
function HU:ProbeLane(n)
    local id = self:ChannelId("main")
    if not id then return end
    for _ = 1, n or 1 do self:Send("LP~" .. self:ChannelLane(), "CHANNEL", id) end
end
-- (el enlace sondea cada LANE_PROBE_EVERY s si no ha mandado nada al canal en ese tiempo: así un canal
-- que deja de funcionar se nota en segundos aunque nadie escriba, no cuando toque la presentación)
HU:OnStart(function()
    HU.NewTicker(LANE_PROBE_EVERY, function()
        -- (con wasRelay, lo que salió en mi último saludo, y no IsRelay: este repasa a todos los [+ARCHITECTURE.md]
        if HU.wasRelay and GetTime() - lastChannelSend > LANE_PROBE_EVERY - 0.5 and HU:IsJoined("main") then
            HU.After(0, function() HU:ProbeLane() end)
        end
    end)
    HU.NewTicker(60, function()
        -- (caducidad: todos tienen la misma hora de subida, así que vuelven al 0 a la vez; si el 0
        -- sigue roto, los rechazos los vuelven a subir)
        local st = HU.cfg and HU.db and HU:LaneState()
        if st and st.lane > 0 and ServerNow() - st.t > LANE_TTL then
            HU:SetLaneState({ lane = 0, gen = math.min(LANE_GEN_MAX, st.gen + 1), t = ServerNow() }, L("el carril ha caducado"))
        end
    end)
end)
-- Resultado de cada envío del addon al canal principal: rechazos seguidos por «canal no válido»
-- (7) mientras sigo dentro = cambio de carril
function HU:ChannelSendResult(id, r)
    if not id or id ~= self:ChannelId("main") then return end
    lastChannelSend = GetTime()
    if r == 7 then
        laneRefused = laneRefused + 1
        -- (primer rechazo: los que faltan para los 3, ya; con el canal bien solo sale uno por minuto)
        if laneRefused == 1 and not laneConfirmT then HU.After(0, function() HU:ProbeLane(LANE_AFTER - 1) end) end
        if laneRefused >= LANE_AFTER then
            laneRefused = 0
            -- (un tropiezo de un momento da los 3 rechazos de golpe, porque el sondeo los manda
            -- juntos: se confirma con otro sondeo a los LANE_CONFIRM s antes de mudarse)
            local now = GetTime()
            if not laneConfirmT or now - laneConfirmT > 120 then
                laneConfirmT = now
                HU.After(LANE_CONFIRM, function() HU:ProbeLane(LANE_AFTER) end)
                return
            end
            if now - laneConfirmT < LANE_CONFIRM - 1 then return end
            laneConfirmT = nil
            if self:IsRelay() or not (self.KnownGuildRelay and self:KnownGuildRelay()) then
                self:MoveLane(self:ChannelLane() + 1, (LANE_AFTER * 2) .. L(" rechazos"))
            elseif GetTime() - (HU.laneAskT or -999) > 60 then
                HU.laneAskT = GetTime()
                laneRefused = 0
                if self.myTag and IsInGuild() then self:Send("LN~" .. (self:ChannelLane() + 1), "GUILD") end
            end
        end
    elseif r == nil or r == true or r == 0 then
        laneRefused, laneConfirmT = 0, nil
    end
end

-- ¿El juego ha bloqueado que el addon escriba en el canal? (lo mira Forward; ver TextChatOK)
for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    HU:On(ev, function(addon)
        if addon ~= ADDON_NAME then return end
        if HU.expectBlock == "chat" then HU.chatBlockedNow = true
        elseif HU.expectBlock == "join" then HU.joinBlockedNow = true end
    end)
end
-- (versiones de antes guardaban el bloqueo para siempre, en toda la cuenta: se borra)
HU:OnStart(function() if HU.db then HU.db.chatByAddon = nil end end)
-- (el chat lento ya no existe: se borra lo que guardaron versiones de antes. Un SL~ que llegue de
-- una versión vieja no tiene orden que lo lea: se ignora sin más)
HU:OnStart(function()
    if HU.db then HU.db.slow = nil end
    if HU.cdb then HU.cdb.slow = nil end
    if HU.adb then HU.adb.slow = nil end
end)

-- lo que escribo en /g estando silenciado o vetado: los
-- demás (con el addon) no lo ven, así que tampoco me sale a mí (si no, parece que ha llegado)
local ownHidden = {}
local function HideOwn(msg)
    ownHidden[msg] = GetTime()
    -- (por si el juego ya lo había devuelto: se quita del historial)
    local h, me = HU.db and HU.db.history, HU:MeKey()
    if not h then return end
    for i = #h, math.max(1, #h - 5), -1 do
        local e = h[i]
        if e.m == msg and e.a and e.a:lower() == me and e.k == "main" and time() - (e.t or 0) < 15 then
            table.remove(h, i)
            if HU.UI and HU.UI.FillChat then HU.UI:FillChat() end
            break
        end
    end
end
function HU:IsOwnHidden(msg)
    local t = type(msg) == "string" and ownHidden[msg]
    if t and GetTime() - t < 15 then return true end
    return false
end

local function OnSend(msg, chatType)
    -- (el eco que escribe el enlace en /g no es suyo: no se reenvía, o haría un bucle)
    if HU.echoSending then return end
    if type(msg) ~= "string" or msg == "" or type(chatType) ~= "string" then return end
    chatType = chatType:upper()
    if chatType ~= "GUILD" and chatType ~= "OFFICER" then return end
    local now = GetTime()
    local sig = chatType .. msg
    if sig == lastSig and now - lastTime < 0.2 then return end -- evita duplicados si se enganchan las dos funciones
    lastSig, lastTime = sig, now
    -- silenciado o vetado: no llega a nadie con el addon (ni a mí)
    if chatType == "GUILD" and HU.IsMuted and HU:IsMuted(HU:Me()) then HideOwn(msg) end
    HU:Forward(chatType == "OFFICER" and "off" or "main", msg)
end

if SendChatMessage then hooksecurefunc("SendChatMessage", OnSend) end
if C_ChatInfo and C_ChatInfo.SendChatMessage then hooksecurefunc(C_ChatInfo, "SendChatMessage", OnSend) end

-- Retail: lo que se escribe en el chat de la ventana de la hermandad del juego (Comunidades) no [+ARCHITECTURE.md]
if C_Club and C_Club.SendMessage and C_Club.GetGuildClubId then
    hooksecurefunc(C_Club, "SendMessage", function(clubId, streamId, msg)
        if type(msg) ~= "string" or HU.Secret(msg) then return end
        local ok, guildClub = pcall(C_Club.GetGuildClubId)
        if not ok or not guildClub or clubId ~= guildClub then return end
        local ok2, info = pcall(C_Club.GetStreamInfo, clubId, streamId)
        local st = ok2 and info and info.streamType
        local T = Enum and Enum.ClubStreamType
        if T and st == T.Officer then OnSend(msg, "OFFICER")
        elseif not T or st == T.Guild then OnSend(msg, "GUILD") end
    end)
end

---------------------------------------------------------------------------
-- Recibir
---------------------------------------------------------------------------
-- Color de clase. El chamán, en azul como en Retail (en Classic sale rosa, como el paladín).
local SHAMAN_BLUE = { r = 0.0, g = 0.44, b = 0.87 }
function HU.ClassRGB(class)
    if class == "SHAMAN" then return SHAMAN_BLUE.r, SHAMAN_BLUE.g, SHAMAN_BLUE.b end
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return nil
end

-- Clase por nombre sacada de las listas que ya tiene el addon (se rehace como mucho cada 30 s)
local classByKey, classByKeyT = {}, -999
function HU:ClassOfName(name)
    if not name then return nil end
    local now = GetTime()
    if now - classByKeyT > 30 then
        classByKey, classByKeyT = {}, now
        for i = 1, (GetNumGuildMembers and GetNumGuildMembers() or 0) do
            local n, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
            if n and class then classByKey[self:Key(n) or ""] = class end
        end
        for _, r in pairs(self.remoteRoster or {}) do
            for _, m in ipairs(r.members or {}) do
                if m.name and m.class then classByKey[self:Key(m.name) or ""] = m.class end
            end
        end
    end
    return classByKey[self:Key(name) or ""]
end

-- Memoria de clases: la clase de cada nombre se apunta la primera vez que se sabe y se guarda entre
-- sesiones, para que el mismo jugador no cambie de color según por dónde llegue su mensaje [+ARCHITECTURE.md]
local MEMO_GEN = 1500
local memoCount
local function RememberClass(key, class)
    local db, idx = HU.db, HU.CLASS_INDEX and HU.CLASS_INDEX[class or ""]
    if not (db and key and key ~= "" and idx) then return end
    local cur = db.classMemo
    if type(cur) ~= "table" then cur = {}; db.classMemo = cur; memoCount = 0 end
    if cur[key] == idx then return end
    if not memoCount then
        memoCount = 0
        for _ in pairs(cur) do memoCount = memoCount + 1 end
    end
    if cur[key] == nil then
        -- (llena: pasa a ser la vieja y se empieza otra; lo que se vuelva a usar de la vieja se rescata)
        if memoCount >= MEMO_GEN then
            cur, memoCount = {}, 0
            db.classMemoOld, db.classMemo = db.classMemo, cur
        end
        memoCount = memoCount + 1
    end
    cur[key] = idx
end
local function RecallClass(key)
    local db = HU.db
    if not (db and key) then return nil end
    local cur, old = db.classMemo, db.classMemoOld
    local idx = type(cur) == "table" and cur[key] or nil
    if not idx and type(old) == "table" and old[key] then
        idx = old[key]
        RememberClass(key, HU.CLASSES[idx])
    end
    return idx and HU.CLASSES[idx] or nil
end

-- (si no se sabe la clase, el nombre sale en naranja; Jorge, 08/11)
local function ClassColored(name, guid, tag, author)
    local class
    if guid and GetPlayerInfoByGUID then class = select(2, GetPlayerInfoByGUID(guid)) end
    if not class then class = HU:ClassOfName(author or name) end
    local key = HU:Key(author or name)
    if class then RememberClass(key, class) else class = RecallClass(key) end
    local r, g, b = HU.ClassRGB(class)
    if r then
        return "|cff" .. string.format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)) .. name .. "|r", class
    end
    if tag then return "|cffff9933" .. name .. "|r", nil end
    return name, nil
end

function HU:KindColor(kind)
    if kind == "lfg" then return 1, 0.62, 0.28 end
    if HU.IsExtra(kind) then return 0.78, 0.62, 1 end
    local info = ChatTypeInfo and ChatTypeInfo[kind == "off" and "OFFICER" or "GUILD"]
    if info then return info.r, info.g, info.b end
    return 0.25, 1, 0.25
end

-- Punto del color de la hermandad (Media\dot.tga, un círculo blanco que se tiñe). Va dentro del
-- mismo enlace que la etiqueta, así que al pasar el ratón sale el recuadro de la hermandad
-- (grey: en gris, para un compañero de mi hermandad que no tiene el addon)
function HU:DotText(tag, grey)
    local r, g, b = 0.5, 0.5, 0.5
    if not grey then r, g, b = self:GuildColor(tag) end
    local dot = ("|TInterface\\AddOns\\%s\\Media\\dot:0:0:0:0:16:16:0:16:0:16:%d:%d:%d|t"):format(
        ADDON_NAME, math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    if tag:find("[|:]") then return dot end
    return "|Haddon:GuildUnion:tag:" .. tag .. ":|h" .. dot .. "|h"
end

-- Lo que va delante del nombre en una línea del chat del juego: la marca de mención, el punto o la
-- etiqueta (db.chatMark) y el icono de rango. Lo usan las líneas de las otras hermandades
-- (FormatLineParts) y las de la mía (ChatPaint.lua). [+ARCHITECTURE.md]
-- (has: si ese compañero tiene el addon; false lo pinta en gris, nil no se dice)
function HU:NamePrefix(tag, author, mark, has)
    local s = mark or ""
    if tag then
        if self.db.chatMark == "tag" then
            s = s .. self:TagText(tag, has == false and HU.NO_ADDON_HEX or nil, has)
        else
            s = s .. self:DotText(tag, has == false)
        end
    end
    local rTag, rIdx = self:RankInfoOf(author)
    return s .. self:RoleIcon(self:RoleOf(author, rTag or tag, rIdx))
end

-- El trozo «[Hermandad]» en el color de la hermandad, si el jugador lo ha elegido (db.chatGuildColor)
function HU:GuildColored(text, tag)
    if not (self.db.chatGuildColor and tag) or text == "" then return text end
    return "|cff" .. self:GuildColorHex(tag) .. text .. "|r"
end

function HU:FormatLine(kind, tag, author, msg, guid, mark)
    local head, body, chatType = self:FormatLineParts(kind, tag, author, msg, guid, nil, nil, mark)
    return head .. body, chatType
end

-- Igual, pero por separado: la cabecera (canal, hermandad, nombre) y el mensaje [+ARCHITECTURE.md]
local KIND_SHORT = { main = "H", off = "O" }
-- (mark: lo que va justo delante de la etiqueta, p. ej. la exclamación de una mención; mismo sitio
-- que en las líneas de mi hermandad, que pinta el juego)
function HU:FormatLineParts(kind, tag, author, msg, guid, compact, showKind, mark)
    local chatType = (kind == "off") and "OFFICER" or "GUILD"
    mark = mark or ""
    if compact then
        local name = self:Nice(author)
        local rTag, rIdx = self:RankInfoOf(author)
        local icon = self:RoleIcon(self:RoleOf(author, rTag or tag, rIdx))
        local nameLink = icon .. "|Hplayer:" .. author .. "|h[" .. ClassColored(name, guid, tag, author) .. "]|h"
        local tagText = mark .. ((self.db.showTag and tag) and self:TagText(tag) or "")
        local label = ""
        if showKind then
            local s = KIND_SHORT[kind] or (HU.IsExtra(kind) and HU.Utf8Cut(HU.ExtraName(kind) or "?", 4)) or "?"
            label = "[" .. s .. "] "
        end
        return label .. tagText .. nameLink .. ": ", self:Emotes(msg), chatType
    end
    local colored = ClassColored(self:Nice(author), guid, tag, author)
    -- Formato de texto (Ajustes): punto o etiqueta delante del nombre, y [Hermandad] en color [+ARCHITECTURE.md]
    local name = self:NamePrefix(tag, author, mark) .. "|Hplayer:" .. author .. "|h[" .. colored .. "]|h"
    local pattern = (kind == "off") and CHAT_OFFICER_GET or CHAT_GUILD_GET
    local pre, post = (pattern or ""):match("^(.-)(%%s.*)$")
    local head
    if HU.IsExtra(kind) then
        head = "[" .. HU.ExtraName(kind) .. "] " .. name .. ": "
    elseif pre then
        head = (self:GuildColored(pre, tag) .. post):format(name)
    else
        head = self:GuildColored("[" .. (kind == "off" and L("Oficial") or L("Hermandad")) .. "] ", tag) .. name .. ": "
    end
    return head, self:Emotes(msg), chatType
end

---------------------------------------------------------------------------
-- Emoticonos: caras propias del addon (carpeta Media). Se escriben como siempre: :) :D xD ;) ...
---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
HU.EMOTES = HU.LT({
    { code = ":)",  file = "smile",     name = "Sonrisa" },
    { code = ":D",  file = "grin",      name = "Risa" },
    { code = "xD",  file = "laugh",     name = "Carcajada" },
    { code = ";)",  file = "wink",      name = "Guiño" },
    { code = ":P",  file = "tongue",    name = "Lengua" },
    { code = ":(",  file = "sad",       name = "Triste" },
    { code = ":'(", file = "cry",       name = "Llorar" },
    { code = ":O",  file = "surprised", name = "Sorpresa" },
    { code = ":@",  file = "angry",     name = "Enfado" },
    { code = "B)",  file = "cool",      name = "Gafas" },
    { code = "<3",  file = "heart",     name = "Corazón" },
})
local EMOTE_BY_CODE = {}
for _, e in ipairs(HU.EMOTES) do EMOTE_BY_CODE[e.code] = e.file end
-- variantes
EMOTE_BY_CODE[":-)"], EMOTE_BY_CODE[":-D"], EMOTE_BY_CODE["XD"], EMOTE_BY_CODE[";-)"] = "smile", "grin", "laugh", "wink"
EMOTE_BY_CODE[":p"], EMOTE_BY_CODE[":-P"], EMOTE_BY_CODE[":-("], EMOTE_BY_CODE[":o"] = "tongue", "tongue", "sad", "surprised"

function HU.EmoteIcon(file, size) return "|T" .. MEDIA .. file .. ":" .. (size or 0) .. "|t" end

-- Enlaces web (https://..., www....): se vuelven clicables en el panel del addon. [+ARCHITECTURE.md]
local customByCode, customMaxLen, customFirstPat
function HU:ResetEmoteCache() customByCode = nil end
local function CustomMap()
    if customByCode then return customByCode, customMaxLen end
    customByCode, customMaxLen = {}, 0
    local db = HU.db
    if db and not db.customEmotesOff then
        for code, e in pairs(db.customEmotes or {}) do
            if e.p and e.p ~= "" then
                customByCode[code] = e.p
                if #code > customMaxLen then customMaxLen = #code end
            end
        end
    end
    -- (con qué letra empieza alguno de la comunidad, para el atajo de HU:Emotes)
    local cfirst, cchars = {}, {}
    for code in pairs(customByCode) do if code ~= "" then cfirst[code:sub(1, 1)] = true end end
    for ch in pairs(cfirst) do cchars[#cchars + 1] = ch:match("%w") and ch or ("%" .. ch) end
    customFirstPat = #cchars > 0 and ("[" .. table.concat(cchars) .. "]") or nil
    return customByCode, customMaxLen
end

function HU:Emotes(msg)
    if type(msg) ~= "string" or msg == "" then return msg end
    if HU.db and HU.db.emotesOff then return msg end
    local custom, cmax = CustomMap()
    -- (atajo: casi ningún mensaje lleva emoticonos. Sin códigos «|», sin ninguno de los emoticonos [+ARCHITECTURE.md]
    if not msg:find("|", 1, true) then
        local any = false
        for code in pairs(EMOTE_BY_CODE) do
            if msg:find(code, 1, true) then any = true break end
        end
        if not any and (cmax == 0 or not customFirstPat or not msg:find(customFirstPat)) then return msg end
    end
    local out, i, n = {}, 1, #msg
    while i <= n do
        local c = msg:sub(i, i)
        if c == "|" then
            -- copia tal cual los códigos de color, enlaces y texturas
            local nx = msg:sub(i + 1, i + 1)
            local j
            if nx == "H" then j = select(2, msg:find("|h.-|h", i + 2))
            elseif nx == "T" then j = select(2, msg:find("|t", i + 2, true))
            elseif nx == "c" then j = i + 9
            else j = i + 1 end
            j = j or n
            out[#out + 1] = msg:sub(i, j)
            i = j + 1
        else
            local prev = (i == 1) and " " or msg:sub(i - 1, i - 1)
            local hit
            if (prev:match("%s") or i == 1) and cmax > 0 then
                for len = math.min(cmax, n - i + 1), 2, -1 do
                    local code = msg:sub(i, i + len - 1)
                    local nextc = msg:sub(i + len, i + len)
                    if custom[code] and (nextc == "" or nextc:match("[%s%.,!%?]")) then hit = code break end
                end
                if hit then
                    out[#out + 1] = "|T" .. custom[hit] .. ":0|t"
                    i = i + #hit
                end
            end
            if hit then
                -- ya puesto (emoticono de la comunidad)
            elseif prev:match("%s") or i == 1 then
                for len = 3, 2, -1 do
                    local code = msg:sub(i, i + len - 1)
                    local nextc = msg:sub(i + len, i + len)
                    if EMOTE_BY_CODE[code] and (nextc == "" or nextc:match("[%s%.,!%?]")) then hit = code break end
                end
            end
            if hit and not custom[hit] then
                out[#out + 1] = HU.EmoteIcon(EMOTE_BY_CODE[hit])
                i = i + #hit
            elseif not hit then
                out[#out + 1] = c
                i = i + 1
            end
        end
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Menciones con @Nombre
---------------------------------------------------------------------------
local function IsWordByte(b) return b and (b >= 48 and b <= 57 or b >= 65 and b <= 90 or b >= 97 and b <= 122 or b >= 128) end

-- @everyone (o @todos): aviso a toda la comunidad. Solo cuenta si lo escribe alguien con rango de
-- mando (maestro, oficial...: los mismos que pueden destacar un mensaje); de cualquier otro es texto
HU.EVERYONE = { everyone = true, todos = true }
HU.EVERYONE_COLOR = "|cffff4040"
-- Lo que va delante de la línea según el tipo de mención: exclamación si es a mí, altavoz si es a todos
HU.MENTION_MARK = {
    me = "|TInterface\\GossipFrame\\AvailableQuestIcon:14:14|t ",
    all = "|A:voicechat-icon-speaker:14:14|a ",
}
function HU:MentionsEveryone(msg, author, tag)
    if type(msg) ~= "string" or not author or not msg:find("@", 1, true) then return false end
    local hit = false
    for word in msg:gmatch("@(%a+)") do
        if HU.EVERYONE[word:lower()] then hit = true break end
    end
    if not hit then return false end
    if author:lower() == (self:MeKey() or "") then return self:CanPin() and true or false end
    return self:TrustedOfficer(author, tag) == true
end

-- ¿Este mensaje me menciona? Devuelve "all" (un @everyone que vale), "me" (a mí) o false.
-- A mí, solo con nombre y apellido (@Nombre Apellido o @Nombre-Apellido: con el nombre solo avisaba
-- a todos los que se llaman igual. Jorge, 10/11), sin importar mayúsculas ni acentos (@nazo vale
-- para «Ñazo»). author y tag: quién lo escribe, para saber si su @everyone vale
function HU:MentionsMe(msg, author, tag)
    if type(msg) ~= "string" or not msg:find("@", 1, true) then return false end
    if author and self:MentionsEveryone(msg, author, tag) then return "all" end
    local low = HU.Fold(msg)
    local forms = { "@" .. HU.Fold(self:Short(self:Me() or "")) }
    forms[#forms + 1] = "@" .. HU.Fold(self:Nice(self:Me() or ""))
    for _, me in ipairs(forms) do
        local i = 1
        while #me > 1 do
            local a, b = low:find(me, i, true)
            if not a then break end
            if not IsWordByte(low:byte(b + 1)) and low:sub(b + 1, b + 1) ~= "-" then return "me" end
            i = b + 1
        end
    end
    return false
end

-- Colorea las menciones con nombre y apellido («@Unmercy Sadance» o «@Unmercy-Sadance»): la mía en
-- naranja, la de otro de la comunidad en azul claro. Con el nombre solo, no es mención: se deja igual
function HU:HighlightMentions(msg, author, tag)
    if type(msg) ~= "string" or not msg:find("@", 1, true) then return msg end
    local me = HU.Fold(self:Short(self:Me() or ""))
    if author and self:MentionsEveryone(msg, author, tag) then
        msg = msg:gsub("@(%a+)", function(word)
            if HU.EVERYONE[word:lower()] then return HU.EVERYONE_COLOR .. "@" .. word .. "|r" end
        end)
    end
    return (msg:gsub("@([^%s@|,%.:;!%?]+)(%s*)([^%s@|,%.:;!%?]*)", function(name, sp, nxt)
        local full, used
        if name:find("-", 1, true) then full, used = name, "@" .. name
        elseif sp ~= "" and nxt ~= "" then full, used = name .. "-" .. nxt, "@" .. name .. sp .. nxt end
        if not full then return nil end
        local rest = (used == "@" .. name) and (sp .. nxt) or ""
        if HU.Fold(full) == me then return "|cffff9a1f" .. used .. "|r" .. rest end
        if (self.InAnyGuild and self:InAnyGuild(full)) or HU.SpokeLately(full) then return "|cff7fd4ff" .. used .. "|r" .. rest end
        return nil
    end))
end

-- Quién ha hablado hace poco por el chat unido. Las listas completas de las otras hermandades no
-- viajan, así que a un miembro normal de otra hermandad solo se le conoce por haberle leído
do
    local SEEN_TTL, SEEN_MAX = 3600, 400
    local seen, names, count = {}, {}, 0
    function HU.NoteSpeaker(author)
        if not author or HU.Secret(author) then return end
        local full = HU:Short(author)
        local k = HU.Fold(full)
        local now = GetTime()
        if not seen[k] then
            count = count + 1
            if count > SEEN_MAX then
                for name, t in pairs(seen) do
                    if now - t > SEEN_TTL then seen[name], names[name] = nil, nil count = count - 1 end
                end
            end
        end
        seen[k], names[k] = now, full
    end
    -- (para rellenar menciones: fn(nombre completo) por cada uno que aún cuenta)
    function HU.EachRecentSpeaker(fn)
        local now = GetTime()
        for k, t in pairs(seen) do
            if now - t < SEEN_TTL then fn(names[k]) end
        end
    end
    function HU.SpokeLately(full)
        local t = seen[HU.Fold(full)]
        return t ~= nil and GetTime() - t < SEEN_TTL
    end
end

-- ¿Tiene el addon este compañero de mi hermandad? Sí, si ha saludado (HU.guildPeers) o se le ha
-- visto en el canal unido, donde solo entra quien lo tiene (HU.chanSeen, que rellena cada lectura
-- del canal). Si no consta, se pide una lectura del canal (a trozos, como mucho cada 2 min) y la
-- respuesta vale para su siguiente línea
HU.NO_ADDON_HEX = "808080"
HU.addonAskT = -999
function HU:MateHasAddon(full)
    local k = full and full:lower()
    if not k then return false end
    if k == self:MeKey() or (self.guildPeers and self.guildPeers[k]) then return true end
    local seen = self.chanSeen and self.chanSeen[k]
    if seen and GetTime() - seen < 7200 then return true end
    if self.GetChannelMembersAsync and GetTime() - HU.addonAskT > 120 then
        HU.addonAskT = GetTime()
        self:GetChannelMembersAsync("main", function() end)
    end
    return false
end

-- La etiqueta <ETIQ> del chat, con su color y un espacio detrás. Es un enlace de addon
-- (|Haddon:GuildUnion:tag:ETIQ:x|h, x = 1 tiene el addon, 0 no, vacío no se dice): al pasar el ratón
-- sale un recuadro con el nombre de la hermandad y cuánta gente tiene. [+ARCHITECTURE.md]
function HU:TagText(tag, hex, addon)
    hex = hex or self:GuildColorHex(tag)
    if tag:find("[|:]") then return "|cff" .. hex .. "<" .. tag .. ">|r " end
    local flag = (addon == true and "1") or (addon == false and "0") or ""
    return "|cff" .. hex .. "|Haddon:GuildUnion:tag:" .. tag .. ":" .. flag .. "|h<" .. tag .. ">|h|r "
end

do
    local shown = false
    local function OnTagEnter(_, frame, link)
        if type(link) ~= "string" or HU.Secret(link) then return end
        local tag, addon = link:match("^addon:GuildUnion:tag:([^:]+):(%d?)")
        if not tag or not GameTooltip then return end
        GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
        GameTooltip:AddLine(HU:GuildName(tag), 1, 0.82, 0)
        -- (mi hermandad: lo que dice el juego ahora; las otras: lo que vino con su última lista)
        -- (sin «conectados»: de las otras hermandades solo viaja la lista corta, y ese número eran
        -- los de esa lista, no los conectados de verdad: «1000 (5 online)». Jorge, 12/11)
        local total, age
        if tag == HU.myTag then
            total = HU.rosterTotal
        else
            local r = HU.remoteRoster and HU.remoteRoster[tag]
            if r then total, age = tonumber(r.total), r.updated and (GetTime() - r.updated) end
        end
        if total and total > 0 then
            GameTooltip:AddLine(string.format(L("Miembros: %d"), total), 1, 1, 1)
        else
            GameTooltip:AddLine(L("Miembros: sin datos todavía"), 0.6, 0.6, 0.6)
            age = nil
        end
        if addon == "1" then GameTooltip:AddLine(L("Tiene Guild Union"), 0.3, 1, 0.3)
        elseif addon == "0" then GameTooltip:AddLine(L("No tiene Guild Union"), 0.6, 0.6, 0.6) end
        -- (abajo del todo, en gris: de cuándo son los números de otra hermandad. Jorge, 12/11)
        if age then
            local mins = math.floor(age / 60)
            GameTooltip:AddLine(mins < 1 and L("Actualizado: ahora mismo") or string.format(L("Actualizado: hace %d min"), mins), 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
        shown = true
    end
    local function OnTagLeave()
        if shown then
            shown = false
            GameTooltip:Hide()
        end
    end
    -- (los dos avisos los da el juego para cualquier enlace del chat)
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", function(...) HU:SafeCall("etiqueta", OnTagEnter, ...) end, HU)
        EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", OnTagLeave, HU)
    end
end

-- (kind: lo que devolvió MentionsMe; un @everyone suena como mucho una vez cada EVERYONE_GAP s,
-- por si alguien abusa)
local lastPing = 0
HU.EVERYONE_GAP, HU.everyoneT = 30, -999
function HU:PingMention(_, kind)
    local now = GetTime()
    if now - lastPing < 2 then return end
    if kind == "all" then
        if now - HU.everyoneT < HU.EVERYONE_GAP then return end
        HU.everyoneT = now
    end
    lastPing = now
    if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081) end
    if FlashClientIcon then pcall(FlashClientIcon) end
end

function HU:Display(kind, tag, author, msg, guid)
    HU.NoteSpeaker(author)
    local mentioned = author and author:lower() ~= (self:MeKey() or "") and self:MentionsMe(msg, author, tag)
    local line = self:FormatLine(kind, tag, author, self:HighlightMentions(msg, author, tag), guid, HU.MENTION_MARK[mentioned])
    if mentioned then self:PingMention(author, mentioned) end
    local r, g, b = self:KindColor(kind)
    for _, f in ipairs(self:FramesFor(kind)) do
        f:AddMessage(line, r, g, b)
    end
end

-- Aviso en el chat de la hermandad (chat lento, silencios, vetos...): sale en el chat del
-- juego donde se ve la hermandad y en el chat del panel
function HU:ChatNotice(text)
    local h = self.db.history
    local e = { t = time(), k = "main", sys = true, m = text }
    h[#h + 1] = e
    while #h > 3000 do table.remove(h, 1) end
    for _, fr in ipairs(self.FramesFor and self:FramesFor("main") or { DEFAULT_CHAT_FRAME }) do
        fr:AddMessage("|cffffd100[" .. self:Title() .. "]|r " .. text, 1, 0.82, 0)
    end
    if self.UI and self.UI.OnChat then self.UI:OnChat(e) end
end

-- Mensaje destacado de un oficial: empieza por "» " (lo ven así también quienes no tienen el
-- addon). En el panel sale con un fondo como el de lo seleccionado.
HU.HL_MARK = "\194\187 "
function HU:IsHighlighted(msg, author, tag)
    if type(msg) ~= "string" or msg:sub(1, #HU.HL_MARK) ~= HU.HL_MARK or not author then return false end
    if author:lower() == (self:MeKey() or "") then return self:CanPin() end
    local ok = self:TrustedOfficer(author, tag)
    return ok == true
end

-- Entradas del chat guardado en formato compacto: lista por posiciones en vez de campos con [+ARCHITECTURE.md]
local ENTRY_IDX = { t = 1, k = 2, tag = 3, a = 4, m = 5, g = 6, hl = 7, late = 8 }
local EntryMeta = {
    __index = function(e, key)
        local i = ENTRY_IDX[key]
        if not i then return nil end
        local v = rawget(e, i)
        if v == false then return nil end
        return v
    end,
    __newindex = function(e, key, v)
        local i = ENTRY_IDX[key]
        if not i then return rawset(e, key, v) end
        if v == nil then v = false end
        rawset(e, i, v)
    end,
}
HU.HistEntryMeta = EntryMeta

-- (al cargar lo guardado, el juego no conserva la metatabla: se vuelve a poner)
HU:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME or not HU.db then return end
    for _, e in ipairs(HU.db.history or {}) do
        if type(e) == "table" and rawget(e, 1) ~= nil then setmetatable(e, EntryMeta) end
    end
end)

function HU:AddHistory(kind, tag, author, msg, guid)
    local h = self.db.history
    local hl = self:IsHighlighted(msg, author, tag) and true or false
    local entry = setmetatable({ time(), kind or false, tag or false, author or false, msg or false, guid or false, hl }, EntryMeta)
    h[#h + 1] = entry
    while #h > 3000 do table.remove(h, 1) end
    if self.UI and self.UI.OnChat then self.UI:OnChat(entry) end
end

-- Todo lo que ha escrito un personaje (busca por nombre, con o sin reino) [+ARCHITECTURE.md]
local held = {}
function HU:HoldUnionChat(k, kind, text, author, guid)
    local l = held[k]
    if not l then l = {}; held[k] = l end
    while l[1] and (GetTime() - l[1].t > 90 or #l >= 10) do table.remove(l, 1) end
    l[#l + 1] = { t = GetTime(), kind = kind, text = text, author = author, guid = guid }
end
function HU:ReplayHeldChat(k)
    local l = held[k]
    if not l then return end
    held[k] = nil
    for _, m in ipairs(l) do
        if GetTime() - m.t <= 90 then self:OnUnionChat(m.kind, m.text, m.author, m.guid) end
    end
end
function HU:DropHeldChat(k) held[k] = nil end

-- (la misma línea puede llegar por el canal y por el respaldo: solo cuenta una vez. Por la misma
-- vía sí se deja repetir: alguien puede escribir «ok» dos veces)
local seenLine, seenN = {}, 0
local function Duplicate(author, text, via)
    local k, now = author:lower() .. "\0" .. text, GetTime()
    local s = seenLine[k]
    if s and now - s.t < 60 and s.via ~= via then return true end
    if seenN > 2000 then seenLine, seenN = {}, 0 end
    if not s then seenN = seenN + 1 end
    seenLine[k] = { t = now, via = via }
    return false
end

-- via: "c" por el canal (texto o el CM~ de versiones anteriores), "w" por el respaldo (CW / CG)
function HU:OnUnionChat(kind, text, author, guid, via)
    if not kind or type(text) ~= "string" or type(author) ~= "string" then return end
    local tag, sub, msg = text:match("^%[(%w+):?(%a?)%] (.*)$")
    if not tag or not HU.cfg or not HU.cfg.byTag[tag] then return end
    author = HU:FullName(author)
    if not author or author:lower() == HU:MeKey() then return end
    -- («[ETIQ:E] …» era el eco de las versiones hasta la 5.4.31: ya no existe y se descarta)
    if sub == "E" then return end
    msg = HU.SafeText(msg, true)
    if sub ~= "R" and Duplicate(author, text, via or "c") then return end
    -- seguridad: quien escribe tiene que estar de verdad en la hermandad de la etiqueta [+ARCHITECTURE.md]
    if tag == HU.myTag and not HU:IsTest() and not HU:MemberOf(author, tag) and not (HU.GuildVerified and HU:GuildVerified(author:lower())) then
        -- (no está en mi lista ni ha hablado por la hermandad: se le pregunta por la vía GUILD del
        -- juego y el mensaje queda retenido hasta la respuesta; ver Guard.lua)
        if HU.CheckImpostor then HU:CheckImpostor(author) end
        HU:HoldUnionChat(author:lower(), kind, text, author, guid)
        return
    end
    if not HU:IsTest() and not HU:MemberOf(author, tag) then
        -- (una lista completa guardada de hace más de un día no cuenta: le faltarían los nuevos)
        local W, reject = HU.whitelist[tag], nil
        if W and time() - (W.t or 0) < 86400 then
            reject = true
        elseif W or HU.remoteRoster[tag] then
            local g = HU.guardKnown and HU.guardKnown[HU:Key(author) or ""]
            reject = (HU.GuardVerdict and HU:GuardVerdict(author) == true)
                or (g ~= nil and g.tag ~= tag and HU:GuardKnown(author))
        end
        if reject then
            HU:Debug(L("Mensaje rechazado: ") .. tostring(author) .. L(" no está en <") .. tag .. ">")
            return
        end
    end
    if HU.SeenPeer then HU:SeenPeer(author, tag) end
    -- (ha escrito en nuestro canal con esa etiqueta: vale como una presentación RA para arrancar su
    -- lista, que en Forever no llegan por el canal)
    if tag ~= HU.myTag and HU.BootPresented then HU.BootPresented(tag, author, GetTime()) end
    -- aviso del enlace de una hermandad (no es chat): "[ETIQ:R] ayudante,ayudante"
    if sub == "R" then
        if tag ~= HU.myTag and HU.OnRelayAnnounce then HU:OnRelayAnnounce(author, tag, msg) end
        return
    end
    if HU:IsMuted(author) and sub ~= "O" then return end -- silenciado: no se muestra
    if HU.IsExtra(kind) then
        -- canal extra: se ve tal cual, también lo de tu propia hermandad
    elseif sub == "B" then
        return -- «Buscar grupo» de una versión vieja: ya no existe, no se muestra
    elseif sub == "O" then
        if not HU:IsTest() then return end
        kind = "off"
    elseif tag == HU.myTag and not HU:IsTest() then
        return -- los de mi hermandad ya lo vieron en /g
    end
    HU:Display(kind, tag, author, msg, guid)
    HU:AddHistory(kind, tag, author, msg, guid)
    return true -- (se ha mostrado)
end

-- Fluidez (meta: ningún fotograma de más de 1,85 ms): las líneas del canal van a una cola que se [+ARCHITECTURE.md]
local chanQ, chanHead, chanTail, chanBusy = {}, 1, 0, false
local function ChanPush(it) chanTail = chanTail + 1; chanQ[chanTail] = it end
local function ChanLine(it)
    if it.hist then
        local h = it.hist
        return HU:AddHistory(h[1], h[2], h[3], h[4], h[5])
    end
    local kind = it.kind
    if HU.MarkChannelSeen then HU:MarkChannelSeen(HU:FullName(it.author)) end
    -- (mi propia línea de vuelta: el texto del canal funciona)
    local full = HU:FullName(it.author)
    if full and full:lower() == HU:MeKey() then HU:GotEcho(it.text) end
    -- (lo que OnUnionChat guardaría en el historial se deja para otro paso de la cola)
    local realAdd = HU.AddHistory
    HU.AddHistory = function(_, k, tag, author, msg, guid)
        ChanPush({ hist = { k, tag, author, msg, guid } })
    end
    local ok, err = pcall(HU.OnUnionChat, HU, kind, it.text, it.author, it.guid)
    HU.AddHistory = realAdd
    if not ok then geterrorhandler()(err) end
end
-- (el tope es por FOTOGRAMA, no por llamada: las líneas suelen llegar de una en una, cada una con [+ARCHITECTURE.md]
local CHAN_FRAME_MS = 0.8
local frameT, frameSpent, frameCount = -1, 0, 0
local ChanStep
local function ChanNext() ChanStep(true) end
function ChanStep(fromTimer)
    chanBusy = true
    local clock = debugprofilestop
    local now = GetTime()
    if now ~= frameT then frameT, frameSpent, frameCount = now, 0, 0 end
    -- (desde el temporizador ya es otro fotograma: al menos una línea sale siempre, para que la
    -- cola nunca se quede parada aunque el reloj no haya avanzado)
    local first = fromTimer
    while chanQ[chanHead] do
        -- (ya se ha gastado lo de este fotograma: al siguiente)
        if not first then
            if clock and frameSpent >= CHAN_FRAME_MS then break end
            if not clock and frameCount >= 2 then break end
        end
        first = false
        local it = chanQ[chanHead]
        chanQ[chanHead] = nil
        chanHead = chanHead + 1
        local t0 = clock and clock()
        -- (si una línea da error, la cola sigue: si no, el chat se pararía)
        local ok, err = pcall(ChanLine, it)
        if not ok then geterrorhandler()(err) end
        frameCount = frameCount + 1
        if t0 then frameSpent = frameSpent + (clock() - t0) end
    end
    if chanQ[chanHead] then
        HU.After(0, ChanNext)
    else
        chanQ, chanHead, chanTail, chanBusy = {}, 1, 0, false
    end
end
HU:On("CHAT_MSG_CHANNEL", function(text, author, _, fullName, _, _, _, _, baseName, _, _, guid)
    local kind = HU:KindOf(baseName, fullName)
    if not kind then return end -- (canales del juego y de otros addons: nada que hacer)
    ChanPush({ kind = kind, text = text, author = author, guid = guid })
    if not chanBusy then ChanStep() end
end)

-- El chat como mensaje oculto del addon:  CM~canal~[ETIQ] mensaje   (canal: m, o, o x:Nombre)
HU.PREFIX_C = "HU20C"
local function OnHiddenChat(prefix, text, dist, sender, _, _, localID, chanName)
    if prefix ~= HU.PREFIX_C or dist ~= "CHANNEL" or type(text) ~= "string" then return end
    local k, body = text:match("^CM~([^~]+)~(.*)$")
    if not k then return end
    local kind = (k == "m" and "main") or (k == "o" and "off") or (k:sub(1, 2) == "x:" and k) or nil
    -- (solo de los canales en los que estoy)
    if not kind or not HU.chan[kind] or not HU:IsJoined(kind) then return end
    -- (y que venga de verdad de ese canal: antes valía desde cualquier canal compartido, como el
    -- de otro addon; en modo prueba el de oficiales va por el principal)
    local from = HU:OurChannelKind(localID, chanName)
    if from ~= true and from ~= kind and not (kind == "off" and from == "main" and HU:IsTest()) then return end
    if HU.MarkChannelSeen then HU:MarkChannelSeen(HU:FullName(sender)) end
    HU:OnUnionChat(kind, body, sender, nil)
end
-- (por la vía registrada, que es la que usa esta versión, y por la normal, de versiones anteriores)
HU:On("CHAT_MSG_ADDON_LOGGED", OnHiddenChat)
HU:On("CHAT_MSG_ADDON", OnHiddenChat)
HU:OnStart(function()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(HU.PREFIX_C) end
end)

local function NativeMention(text, author)
    author = HU:FullName(author)
    local mentioned = author and author:lower() ~= HU:MeKey() and HU:MentionsMe(text, author, HU.myTag)
    if mentioned then HU:PingMention(author, mentioned) end
end
HU:On("CHAT_MSG_GUILD", NativeMention)
HU:On("CHAT_MSG_OFFICER", NativeMention)

-- los silenciados tampoco se ven en el /g normal (para quien tiene el addon),
function HU:GuildLineHidden(msg, author)
    local full = author and HU:FullName(author)
    if full and full:lower() == HU:MeKey() and HU:IsOwnHidden(msg) then return true end
    if HU.IsMuted and full and full:lower() ~= HU:MeKey() and HU:IsMuted(full) then return true end
    return false
end

HU:On("CHAT_MSG_GUILD", function(text, author, _, _, _, _, _, _, _, _, _, guid)
    if HU:GuildLineHidden(text, author) then return end
    if HU.myTag then HU:AddHistory("main", HU.myTag, HU:FullName(author), text, guid) end
end)

HU:On("CHAT_MSG_OFFICER", function(text, author, _, _, _, _, _, _, _, _, _, guid)
    if HU.myTag then HU:AddHistory("off", HU.myTag, HU:FullName(author), text, guid) end
end)
