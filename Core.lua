-- Guild Union - núcleo: eventos, utilidades, base de datos y comandos
local ADDON_NAME, HU = ...
_G.HermandadUnida = HU

---------------------------------------------------------------------------
-- Idioma: inglés (por defecto) o español. Los textos del addon están en español
-- y L() los traduce (diccionario en LocaleEN.lua). Cambiarlo pide recargar.
---------------------------------------------------------------------------
HU.lang = "es" -- hasta que se cargan los ajustes
HU.EN = {}
HU.missingEN = {} -- textos que faltan por traducir (se ven con /gu idioma)
local function L(s)
    if HU.lang == "en" then
        local e = HU.EN[s]
        if e then return e end
        if type(s) == "string" and s:find("[\195\194]") then HU.missingEN[s] = true end -- tiene tildes o ñ
    end
    return s
end
HU.L = L
-- tablas con textos que se crean al cargar el addon (antes de saber el idioma)
local translatable = {}
function HU.LT(t) translatable[#translatable + 1] = t; return t end
function HU:ApplyLanguage(lang)
    HU.lang = lang
    if lang ~= "en" then return end
    local seen = {}
    local function walk(t)
        if seen[t] then return end
        seen[t] = true
        for k, v in pairs(t) do
            if type(v) == "string" then
                local e = HU.EN[v]
                if e then t[k] = e end
            elseif type(v) == "table" then
                walk(v)
            end
        end
    end
    for _, t in ipairs(translatable) do walk(t) end
end
function HU:LangName() return HU.lang == "en" and "English" or "Español" end
function HU:SetLang(v)
    HU.db.langChosen = true
    if v == HU.lang then return end
    HU.db.lang = v
    HU:ShowDialog("GU_LANG")
end

local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata
HU.version = (GetMeta and GetMeta(ADDON_NAME, "Version")) or "5.2.1"
-- GuildUnion Reduce: numeración propia para enseñar; por dentro sigue la de GuildUnion (el saludo
-- la lleva y así se entiende con quien tenga GuildUnion normal)
HU.REDUCE_VERSION = GetMeta and GetMeta(ADDON_NAME, "X-Reduce-Version") or nil
-- La versión más vieja que sigue funcionando con esta (va en el saludo). La sube ADMIN en cada versión
-- importante: quien tenga una más vieja recibe el aviso de «actualización IMPORTANTE» (Popup.lua)
-- (fija en la de CurseForge mientras la nueva no esté allí: si no, a todos los de la 5.4.11 les salía
-- «actualiza» sin tener de dónde. Jorge, 10/11. Se sube cuando CurseForge tenga la nueva)
HU.MIN_VERSION = "5.4.11"
HU.PREFIX = "HU20"
-- (copia 154: puerta para Guild Union Measure, el addon de pruebas aparte. Solo lee) [+ARCHITECTURE.md]
_G.GuildUnionInternal = HU

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
-- (el del addon: lo que silencia las ventanas del juego no lo toca a él, UnionMembers.lua)
HU.eventFrame = eventFrame
local handlers = {}

function HU:On(event, fn)
    if not handlers[event] then
        -- si el juego no conoce ese evento (cambia entre versiones), se ignora sin romper la carga
        local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            HU.badEvents = HU.badEvents or {}
            table.insert(HU.badEvents, event)
            return
        end
        handlers[event] = {}
    end
    table.insert(handlers[event], fn)
end

-- Avisos entre módulos (bus interno), con nombres que no son eventos del juego [+ARCHITECTURE.md]
local listeners = {}
function HU:Listen(name, fn)
    listeners[name] = listeners[name] or {}
    table.insert(listeners[name], fn)
end
function HU:Fire(name, ...)
    local list = listeners[name]
    if not list then return end
    for i = 1, #list do HU:SafeCall(name, list[i], ...) end
end

-- Módulos: cada archivo acaba con HU:Module(nombre, { los que necesita }). Como va al final, solo
-- consta si el archivo ha cargado entero; al entrar se comprueba que está todo lo necesitado [+ARCHITECTURE.md]
HU.modules = {} -- [nombre] = { needs }
function HU:Module(name, needs)
    if HU.modules[name] then error("módulo repetido: " .. tostring(name), 2) end
    HU.modules[name] = { needs = needs or {} }
end
function HU:CheckModules()
    local missing = {}
    for name, m in pairs(HU.modules) do
        for _, n in ipairs(m.needs) do
            if not HU.modules[n] then
                missing[n] = missing[n] or {}
                table.insert(missing[n], name)
            end
        end
    end
    for n, by in pairs(missing) do
        table.sort(by)
        HU:RecordError({ msg = "El archivo " .. n .. ".lua no ha cargado entero (lo necesitan " .. table.concat(by, ", ") .. "): mira el primer error de Lua al entrar o reinstala el addon.", stack = "" }, "módulos")
    end
    return next(missing) == nil
end

---------------------------------------------------------------------------
-- Errores: se guardan para poder copiarlos (/gu errores) y mandarlos
---------------------------------------------------------------------------
HU.errors = {}
-- Manejadores de las órdenes de red: HU.comm[orden] = function(self, sender, f, dist, raw). Se crea
-- aquí, en el primer archivo, para que cualquier archivo pueda registrar las suyas al cargarse
HU.comm = {}
local function Trace(err)
    local stack = debugstack and debugstack(2, 12, 0) or ""
    return { msg = tostring(err), stack = stack }
end
function HU:RecordError(e, where)
    e = type(e) == "table" and e or { msg = tostring(e), stack = "" }
    for _, old in ipairs(self.errors) do
        if old.msg == e.msg then old.n = (old.n or 1) + 1 return end
    end
    e.where, e.t, e.n = where, time(), 1
    table.insert(self.errors, e)
    if self.db then
        self.db.lastErrors = self.db.lastErrors or {}
        table.insert(self.db.lastErrors, 1, { msg = e.msg, stack = e.stack, where = where, t = e.t, v = self.version })
        while #self.db.lastErrors > 10 do table.remove(self.db.lastErrors) end
    end
    -- (solo los oficiales ven los errores del addon; a los demás no se les dice nada)
    if #self.errors == 1 and self:CanOfficer() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444" .. HU.ADDON_TITLE .. ": " .. L("ha habido un error.") .. "|r " .. L("Queda guardado (/gu errores para verlo)."))
    end
end
-- Recargar la interfaz: en Forever el juego bloquea el /reload de un addon, también desde su propia
-- ventana de aviso (probado el 08/11). Va a la ventana de órdenes para que lo mandes tú.
function HU:Reload()
    HU:TypeLines("/reload", L("Recargar la interfaz"))
end
-- (si xpcall acepta datos de más, como en Forever, no se crea una tabla y una función por llamada)
local XPCALL_ARGS = select(2, xpcall(function(a) return a end, function() end, true)) == true
function HU:SafeCall(where, fn, ...)
    local ok, err
    if XPCALL_ARGS then
        ok, err = xpcall(fn, Trace, ...)
    else
        local args, n = { ... }, select("#", ...)
        ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, Trace)
    end
    if not ok then self:RecordError(err, where) end
    return ok
end
function HU:ErrorReport()
    local lines = { HU.ADDON_TITLE .. " " .. tostring(self.version) .. "  -  " .. (GetBuildInfo and table.concat({ GetBuildInfo() }, " ", 1, 2) or "?")
        .. "  -  " .. tostring(self.lang) .. "  -  " .. date("%d/%m/%Y %H:%M") }
    local list = #self.errors > 0 and self.errors or (self.db and self.db.lastErrors) or {}
    if #list == 0 then lines[#lines + 1] = L("No hay errores guardados.") end
    for i, e in ipairs(list) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = i .. ") [" .. tostring(e.where or "?") .. "] x" .. (e.n or 1) .. "  " .. e.msg
        if e.stack and e.stack ~= "" then lines[#lines + 1] = e.stack end
    end
    local got = self:ReceivedErrorsText()
    if got then lines[#lines + 1] = got end
    return table.concat(lines, "\n")
end
-- Borra los míos (de esta sesión y los guardados de antes) y los que me han mandado otros
function HU:ClearAllErrors()
    local mine = #self.errors + (self.db and self.db.lastErrors and #self.db.lastErrors or 0)
    wipe(self.errors)
    if self.db then self.db.lastErrors = nil end
    self:Print(L("Errores borrados: ") .. mine .. L(" tuyos y ") .. self:ClearReceivedErrors() .. L(" recibidos."))
end
function HU:ShowErrors()
    self.UI:ShowCopy(L("Errores del addon"), self:ErrorReport(), {
        hint = L("Ctrl+A selecciona todo  ·  Ctrl+C copia  ·  mándaselo a quien lleva el addon"),
        button = L("Borrar"),
        onClick = function() HU:ClearAllErrors(); HU:ShowErrors() end,
    })
end

HU.evCount, HU.evSecret = {}, {}
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    -- textos o nombres secretos (en mazmorras, en Forever / Midnight): no se tocan
    HU.evCount[event] = (HU.evCount[event] or 0) + 1
    if issecretvalue then
        local a, b = ...
        if issecretvalue(a) or issecretvalue(b) then HU.evSecret[event] = (HU.evSecret[event] or 0) + 1 return end
    end
    -- (los mensajes de otros addons, como DBM o WeakAuras, no se reparten: todos los nuestros empiezan por HU20)
    if event == "CHAT_MSG_ADDON" then
        local prefix = ...
        if type(prefix) ~= "string" or prefix:sub(1, 4) ~= "HU20" then return end
    end
    for i = 1, #list do HU:SafeCall(event, list[i], ...) end
end)

-- Filtro del chat del juego (con nombre nuevo o viejo según la versión) que nunca toca
-- mensajes secretos y no rompe el chat si falla
local function AnySecret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

-- (solo se usa para los mensajes del sistema, Net/Transport.lua: en los chats de jugadores no hay filtros,
-- porque intervenir ahí hacía que el juego no pintara la línea con el chat bloqueado) [+ARCHITECTURE.md]
function HU.AddChatFilter(event, fn)
    local function safe(frame, ev, ...)
        if AnySecret(...) then return end -- (sin devolver nada, ni `false`)
        -- (se devuelven TODOS los datos del mensaje: si se recortan, el chat normal lo oculta)
        local r = { pcall(fn, frame, ev, ...) }
        if not r[1] then
            HU:RecordError(r[2], "filter " .. tostring(ev))
            return false
        end
        return unpack(r, 2, select("#", ...) + 2)
    end
    local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if add then add(event, safe) end
end

-- Temporizadores que nunca rompen: si la función falla, el error se guarda (como los eventos)
function HU.After(delay, fn)
    return C_Timer.After(delay, function() HU:SafeCall("timer", fn) end)
end

-- Planificador: todo lo que se repite pasa por HU:Every, con un nombre [+ARCHITECTURE.md]
-- opts: times (cuántas veces; sin él, siempre), pauseInCombat (no se hace mientras HU:CombatHold()),
-- maxFailures (tras tantos fallos se para, como el cortacircuitos de History). Devuelve el
-- temporizador del juego (:Cancel() lo para)
local taskClock = debugprofilestop or function() return GetTime() * 1000 end
HU.tasks = {} -- [nombre] = { every, n (veces), ms (en total), max, fails, skipped, off }
function HU:Every(secs, name, fn, opts)
    if type(name) ~= "string" or name == "" then error("HU:Every: falta el nombre", 2) end
    if type(fn) ~= "function" then error("HU:Every " .. name .. ": falta la función", 2) end
    opts = opts or {}
    local task = HU.tasks[name]
    if not task then
        task = { name = name, n = 0, ms = 0, max = 0, fails = 0, skipped = 0 }
        HU.tasks[name] = task
    end
    task.every, task.off = secs, nil
    local ticker
    ticker = C_Timer.NewTicker(secs, function()
        if opts.pauseInCombat and HU:CombatHold() then task.skipped = task.skipped + 1 return end
        local t0 = taskClock()
        local ok = HU:SafeCall(name, fn)
        local ms = taskClock() - t0
        task.n, task.ms = task.n + 1, task.ms + ms
        if ms > task.max then task.max = ms end
        if not ok then
            task.fails = task.fails + 1
            if opts.maxFailures and task.fails >= opts.maxFailures then
                task.off = true
                ticker:Cancel()
                HU:Debug("Tarea parada por fallar", task.fails, "veces:", name)
            end
        end
    end, opts.times)
    return ticker
end
-- Las tareas, de la que más tiempo se lleva a la que menos (para /gu perf)
function HU:TaskLines()
    local list = {}
    for _, t in pairs(HU.tasks) do list[#list + 1] = t end
    table.sort(list, function(a, b) if a.ms ~= b.ms then return a.ms > b.ms end return a.name < b.name end)
    local out = {}
    for _, t in ipairs(list) do
        out[#out + 1] = string.format("%-24s cada %gs  %dx  %.1f ms (peor %.1f)%s%s%s", t.name, t.every or 0, t.n, t.ms, t.max,
            t.fails > 0 and ("  fallos " .. t.fails) or "", t.skipped > 0 and ("  en combate " .. t.skipped) or "", t.off and "  PARADA" or "")
    end
    return out
end

-- La X de nuestras ventanas. La plantilla del juego cierra con HideUIPanel, que pasa por su gestor
-- de ventanas: desde un addon puede no hacer nada (en combate lo bloquea). Aquí, Hide() directo.
function HU.CloseButton(frame)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetScript("OnClick", function() frame:Hide() end)
    return close
end

-- Si el juego bloquea algo que intenta el addon, se guarda en /gu errores (qué función era)
for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    HU:On(ev, function(addon, func)
        -- (los bloqueos esperados, que el addon ya resuelve por otra vía, no se guardan como error)
        if addon == ADDON_NAME and not HU.expectBlock then HU:RecordError({ msg = ev .. ": " .. tostring(func), stack = debugstack and debugstack(3) or "" }, "bloqueado") end
    end)
end

-- Restricciones del juego (combate, jefe, mítica+, partida PvP, mapa...): mientras duran, el juego
-- bloquea funciones como leer la Información de hermandad y la lectura sale vacía
function HU:Restricted()
    local R = C_RestrictedActions
    local types = Enum and Enum.AddOnRestrictionType
    if R and R.IsAddOnRestrictionActive and types then
        for _, v in pairs(types) do
            local ok, on = pcall(R.IsAddOnRestrictionActive, v)
            if ok and on then return true end
        end
        return false
    end
    return InCombatLockdown and InCombatLockdown() or false
end

-- Información de hermandad, o nil si ahora no se puede leer (se reintenta al acabar la restricción)
function HU:GuildInfoText()
    if self:Restricted() then
        HU.infoPending = true
        return nil
    end
    return (GetGuildInfoText and GetGuildInfoText()) or ""
end

HU:On("ADDON_RESTRICTION_STATE_CHANGED", function()
    if not HU.infoPending then return end
    -- (el evento llega justo antes de activarse o justo después de acabar: se mira un poco después)
    HU.After(1, function()
        if HU.infoPending and not HU:Restricted() then
            HU.infoPending = nil
            HU:RefreshConfig()
        end
    end)
end)
HU:On("PLAYER_REGEN_ENABLED", function()
    if HU.infoPending then HU.After(1, function()
        if HU.infoPending and not HU:Restricted() then HU.infoPending = nil; HU:RefreshConfig() end
    end) end
end)

-- Funciones que cada módulo quiere ejecutar al entrar al juego
HU.startFns = {}
function HU:OnStart(fn) table.insert(self.startFns, fn) end

---------------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------------
function HU:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. HU:Title() .. "|r: " .. tostring(msg))
end

-- El nombre del canal, tapado (dos letras y puntos): los avisos de depuración se pegan en capturas
-- y el nombre del canal no debe salir de la comunidad (copia 113; como ya hacía /gu diag)
function HU.MaskChannel(name)
    if type(name) ~= "string" or name == "" then return "nil" end
    return name:sub(1, 2) .. "····"
end

function HU:Debug(...)
    if self.db and self.db.debug then
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        DEFAULT_CHAT_FRAME:AddMessage("|cff888888HU:|r " .. table.concat(parts, " "))
    end
end

---------------------------------------------------------------------------
-- Metatabla estricta (propuesta C): con /gu debug, leer un campo de HU que no existe y no está en
-- MAYBE_NIL se apunta en HU.strictMiss (con dónde) y se avisa una vez: suele ser un nombre mal
-- escrito. Las pruebas la llevan siempre encendida y fallan con cualquier campo nuevo.
---------------------------------------------------------------------------
-- El estado de HU que empieza vacío: nil quiere decir «todavía no» o «no hay»
HU.MAYBE_NIL = {
    -- quién soy y en qué estado está el addon
    me = true, myTag = true, cfg = true, paused = true, mustUpdate = true, guildMin = true,
    replaying = true, weakMsg = true, diagRecv = true, oldAddon = true, badEvents = true,
    presenceWrapped = true, staleCheck = true,
    newerWarned = true, -- (ya se ha dicho que hay una versión más nueva: Net/Relay.lua)
    infoPending = true, keyJPending = true, combatReplay = true, -- (Core, UI y Combat: esperan al fin del combate)
    -- el canal
    chanRosterKeys = true, chanRosterKeysT = true, chanIAmMod = true, chanLeftT = true, laneMoves = true,
    applyPending = true, joinBlockedNow = true, chatBlockedNow = true, alsoChan = true, alsoChanN = true,
    offCfg = true, chatServerUpT = true, -- (cuándo volvió el servidor de chat: Channel.lua)
    hlHeard = true, -- (cuántas respuestas de «mientras no estabas» han llegado: Social.lua)
    chanMembersSeen = true, -- (la lista del canal, la primera vez que se lee: Guard.lua)
    -- la configuración de la comunidad
    joinedText = true, noteCfgText = true,
    -- enlace, ayudantes y listas
    wasRelay = true, aloneRelay = true, myAdvScore = true, advertisedHelpers = true, relayHelpers = true,
    relayMissing = true, relayRetryT = true, restSince = true, lastSharedPL = true, sendGroup = true,
    rosterNeed = true, rosterNamesV = true, rosterVersion = true,
}
HU.strictMiss = {}
local function StrictIndex(_, k)
    if HU.MAYBE_NIL[k] or HU.strictMiss[k] then return nil end
    local where = debugstack and (debugstack(2, 1, 0) or ""):match("([%w_]+%.lua:%d+)") or "?"
    HU.strictMiss[k] = where or "?"
    HU:Debug("Campo de HU que no existe:", tostring(k), where or "?")
end
function HU:StrictMode(on)
    setmetatable(HU, on and { __index = StrictIndex } or nil)
end

-- (copia 175) Avisos de fallos que ya no salen en el chat: se guardan (los 30 últimos de la sesión) y
-- se ven en /gu informe, para cuando alguien pregunte. Jorge, 19/11: «que se tengan que preguntar»
HU.notices = {}
function HU:Notice(text)
    local n = self.notices
    if #n >= 30 then table.remove(n, 1) end
    n[#n + 1] = { t = time(), text = tostring(text) }
    self:Debug("Aviso guardado:", text)
end

-- Solo WoW Forever: los personajes tienen nombre y apellido, y el apellido va donde en los demás [+ARCHITECTURE.md]

-- ¿Es un valor secreto? (desde Midnight / Forever, el juego oculta algunos datos a los addons)
function HU.Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) and true or false
end

-- Devuelve siempre "Nombre-Apellido"
function HU:FullName(name)
    if type(name) ~= "string" or name == "" or HU.Secret(name) then return nil end
    if name:find("-", 1, true) then return name end
    -- "Nombre Apellido" -> "Nombre-Apellido"
    local a, b = name:match("^%s*(%S+)%s+(%S+)%s*$")
    if a then return a .. "-" .. b end
    -- solo el nombre (lo escribe alguien, o viene así de un aviso del juego): si solo hay
    -- un conocido con ese nombre, es él
    return self:ResolveFirstName(name) or name
end

-- Forever: "Pepe" -> "Pepe-Garcia" si solo hay un Pepe entre los que conocemos [+ARCHITECTURE.md]
local NAME_MAP_EVERY, NAME_MISS_FOR, NAME_MISS_MAX, NAME_MAP_MS = 30, 30, 500, 1
local firstMap, firstMapT, firstMapV = nil, -100, nil
local nameMiss, nameMissN = {}, 0
local nameBuild -- la corrutina que rehace el mapa (nil si no hay ninguna en marcha)
local clockMs = debugprofilestop or function() return GetTime() * 1000 end
local function NameSources(self)
    -- (los contactos se copian antes: pueden entrar nuevos mientras se rehace el mapa por trozos)
    local remoteNames, tags = {}, {}
    for _, p in pairs(self.remote or {}) do remoteNames[#remoteNames + 1] = p.name end
    for _, rr in pairs(self.remoteRoster or {}) do tags[#tags + 1] = rr end
    return remoteNames, tags
end
local function BuildMap(self, budget)
    local map, n, t0 = {}, 0, clockMs()
    local function add(full)
        if type(full) ~= "string" then return end
        local f = full:match("^([^%-]+)%-")
        if not f then return end
        f = f:lower()
        if map[f] == nil then map[f] = full elseif map[f] and map[f]:lower() ~= full:lower() then map[f] = false end
        n = n + 1
        if budget and n % 50 == 0 and clockMs() - t0 > NAME_MAP_MS then coroutine.yield(); t0 = clockMs() end
    end
    local remoteNames, rosters = NameSources(self)
    if self.me then add(self.me) end
    for _, e in ipairs(self.rosterList or {}) do add(e.name) end
    for _, rr in ipairs(rosters) do for _, m in ipairs(rr.members or {}) do add(m.name) end end
    for _, name in ipairs(remoteNames) do add(name) end
    for _, m in ipairs(self.chanMembersSeen or {}) do add(m) end
    return map
end
local function StartNameBuild(self)
    if nameBuild then return end
    local v = self.rosterNamesV
    nameBuild = coroutine.create(function() return BuildMap(self, true) end)
    local function step()
        local ok, map = coroutine.resume(nameBuild)
        if not ok then nameBuild = nil; return self:RecordError(map, "mapa de nombres") end
        if coroutine.status(nameBuild) ~= "dead" then return HU.After(0, step) end
        nameBuild = nil
        firstMap, firstMapT, firstMapV = map, GetTime(), v
        wipe(nameMiss); nameMissN = 0
    end
    step()
end
function HU:ResolveFirstName(first)
    first = HU.Trim(first):lower()
    -- (ni caracteres de control: ningún jugador los lleva, y un nombre así rehacía el mapa entero)
    if first == "" or first == "?" or first:find("[%s%-%p%c]") then return nil end
    local now = GetTime and GetTime() or 0
    -- (la primera vez, de una: al entrar hay pocos nombres)
    if not firstMap then firstMap, firstMapT, firstMapV = BuildMap(self, false), now, self.rosterNamesV end
    local r = firstMap[first]
    if r ~= nil then return r or nil end
    -- (no está: si ya se buscó hace poco, no se vuelve a mirar)
    local miss = nameMiss[first]
    if miss and now - miss < NAME_MISS_FOR then return nil end
    if nameMissN >= NAME_MISS_MAX then wipe(nameMiss); nameMissN = 0 end
    if not miss then nameMissN = nameMissN + 1 end
    nameMiss[first] = now
    if now - firstMapT > NAME_MAP_EVERY or firstMapV ~= self.rosterNamesV then StartNameBuild(self) end
    return nil
end

-- Clave para comparar nombres
function HU:Key(name)
    local full = self:FullName(name)
    return full and full:lower() or nil
end

-- Nombre completo (lo de detrás del guion es el apellido: es parte del nombre)
function HU:Short(name)
    if not name or HU.Secret(name) then return "?" end
    return self:FullName(name) or name
end

-- Para enseñar: "Nombre Apellido" (con espacio)
function HU:Nice(name)
    return (self:Short(name):gsub("%-", " ", 1))
end

function HU:Me()
    if not self.me then
        local n, second = UnitName("player")
        -- la segunda parte es el apellido
        if type(second) == "string" and second ~= "" and n and not n:find("-", 1, true) then
            n = n .. "-" .. second
        end
        self.me = self:FullName(n)
    end
    return self.me
end

-- Nombre bonito a partir de lo guardado ("Solitario") y su clave ("solitario-garcia")
-- ¿Es la misma persona? (en Forever vale también solo el nombre, si una de las dos lo trae así)
function HU:SameName(a, b)
    local ka, kb = self:Key(a), self:Key(b)
    if not ka or not kb then return false end
    if ka == kb then return true end
    local fa, fb = ka:match("^([^%-]+)"), kb:match("^([^%-]+)")
    if (not ka:find("-", 1, true) or not kb:find("-", 1, true)) and fa == fb then return true end
    return false
end

function HU:MeKey()
    local me = self:Me()
    return me and me:lower()
end

function HU.Split(text, sep)
    local out = {}
    sep = sep or "~"
    if text == nil or text == "" then return out end
    local pattern = "([^" .. sep .. "]*)" .. sep
    for field in (text .. sep):gmatch(pattern) do out[#out + 1] = field end
    return out
end

-- Midnight: el juego no deja mandar mensajes de chat ni de addon en algunas mazmorras y [+ARCHITECTURE.md]

-- Dato del juego que puede llegar secreto (combate, jefe, mítica+): secreto → el valor que se pida
function HU.SafeBool(v, ifSecret)
    if issecretvalue and issecretvalue(v) then return ifSecret end
    return v and true or false
end

function HU:IsChatLockedDown()
    local fn = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not fn then return false end
    local ok, locked = pcall(fn)
    -- (si no se puede saber, se da por bloqueado: mejor esperar que intentar mandar)
    return ok and HU.SafeBool(locked, true) or false
end

-- Un momento (time()) que viene de otro addon: número de verdad y razonable, o nil
function HU.Time(v)
    v = tonumber(v)
    if not v or v ~= v or v < 0 or v > time() + 7 * 86400 then return nil end
    return math.floor(v)
end

-- Momento de una acción que llega por la red, para «gana la más nueva»: como mucho dentro de 5 [+ARCHITECTURE.md]
function HU.NetT(v)
    v = tonumber(v)
    if not v or v ~= v or v < 0 or v == math.huge then return nil end
    return math.floor(math.min(v, time() + 300))
end

-- Hora para decidir qué cambio es el más nuevo (silencios, vetos, canal y contraseña, configuración):
-- la del servidor, igual para todos, no la del PC. Lo que llega más de 5 min por delante no vale.
HU.STAMP_FUTURE = 300
function HU.StampNow() return (GetServerTime and GetServerTime()) or time() end
function HU.NetStamp(v)
    v = tonumber(v)
    if not v or v ~= v or v < 0 or v > HU.StampNow() + HU.STAMP_FUTURE then return nil end
    return math.floor(v)
end
-- (lo guardado con una hora del futuro, de un PC adelantado, se deja en la de ahora)
function HU.StampFix(e)
    if e and (e.t or 0) > HU.StampNow() + HU.STAMP_FUTURE then e.t = HU.StampNow() end
end

-- Texto que llega de otro addon (chat oculto, fijado, notas, historial...): sin saltos de línea ni [+ARCHITECTURE.md]
local LINK_OK = { item = true, spell = true, quest = true, achievement = true, enchant = true, talent = true,
    trade = true, currency = true, battlepet = true, mount = true, transmogillusion = true, transmogappearance = true,
    conduit = true, azessence = true, keystone = true, journal = true, instancelock = true }
function HU.SafeText(s, links)
    if type(s) ~= "string" then return "" end
    s = s:gsub("[%c]", " ")
    if not s:find("|", 1, true) then return s end
    if not links then return (s:gsub("|", "||")) end
    local out, pos = {}, 1
    while true do
        local a, b, ltype = s:find("|c[^|]+|H(%a+):[^|]*|h%[[^|]*%]|h|r", pos)
        if not a then break end
        out[#out + 1] = (s:sub(pos, a - 1):gsub("|", "||"))
        out[#out + 1] = LINK_OK[ltype] and s:sub(a, b) or (s:sub(a, b):gsub("|", "||"))
        pos = b + 1
    end
    out[#out + 1] = (s:sub(pos):gsub("|", "||"))
    return table.concat(out)
end

-- Nombre que llega de otro addon: nil si trae códigos o caracteres de control
function HU.SafeName(n)
    if type(n) ~= "string" or n == "" or n:find("[|%c]") then return nil end
    return n
end

-- date() que nunca falla (si la hora que llega de otro addon no vale, usa la de ahora)
function HU.SafeDate(fmt, t)
    local ok, r = pcall(date, fmt, HU.Time(t) or time())
    return (ok and r) or ""
end

-- Número de otro addon: finito y dentro de [lo, hi], o nil
-- 75 -> "1:15", 8 -> "0:08"
function HU.Trim(s)
    if not s then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Para buscar: minúsculas y sin acentos (letras latinas de dos bytes, U+00C0..U+00FF)
local FOLD = {}
do
    local map = {
        a = "\192\193\194\195\196\197\224\225\226\227\228\229", c = "\199\231", e = "\200\201\202\203\232\233\234\235",
        i = "\204\205\206\207\236\237\238\239", n = "\209\241", o = "\210\211\212\213\214\216\242\243\244\245\246\248",
        u = "\217\218\219\220\249\250\251\252", y = "\221\253\255",
    }
    for base, cps in pairs(map) do
        for k = 1, #cps do
            local cp = cps:byte(k)
            FOLD[string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)] = base
        end
    end
end
function HU.Fold(s)
    if not s then return "" end
    return (s:gsub("[\195][\128-\191]", FOLD):lower())
end

-- Recorta un texto a n bytes sin partir caracteres UTF-8
function HU.Utf8Cut(s, n)
    if not s or #s <= n then return s end
    local cut = n
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 128 or b >= 192 then break end
        cut = cut - 1
    end
    return s:sub(1, cut)
end

-- "0.1.10" > "0.1.9"
function HU.VersionGreater(a, b)
    local pa, pb = HU.Split(a or "0", "."), HU.Split(b or "0", ".")
    for i = 1, math.max(#pa, #pb) do
        local x, y = tonumber(pa[i]) or 0, tonumber(pb[i]) or 0
        if x ~= y then return x > y end
    end
    return false
end

function HU:Log(msg)
    if not self.db then return end
    local line = date("%d/%m %H:%M") .. "  " .. msg
    table.insert(self.db.log, line)
    while #self.db.log > 200 do table.remove(self.db.log, 1) end
    if self.UI and self.UI.OnLog then self.UI:OnLog(line) end
end

-- Algo ha cambiado (miembros, canal, guardia...): lo escucha la interfaz (UI.lua) para redibujar
function HU:Changed(what) self:Fire("CHANGED", what) end

---------------------------------------------------------------------------
-- Base de datos
---------------------------------------------------------------------------
-- Lo que se guarda: cada módulo declara sus claves con HU:Saved, al principio de su archivo [+ARCHITECTURE.md]
--   HU:Saved({ account = { grace = 120, "otraClave" }, char = { history = {}, "pinned" } })
-- account: para toda la cuenta; char: para cada personaje (eran de la cuenta y los heredaba un
-- personaje de otra comunidad: un carril, unas listas o unas hermandades añadidas que no eran las
-- suyas). «clave = valor» le da un valor por defecto (una tabla nueva para cada uno si es una tabla);
-- la clave sola, sin valor por defecto. Una clave declarada dos veces es un error.
HU.PER_CHAR = {}      -- [clave] = true: va en el personaje
HU.savedScope = {}    -- [clave] = "account" | "char"
local DEFAULTS = {}   -- [clave] = valor por defecto
HU.savedDefaults = DEFAULTS
function HU:Saved(spec)
    for scope, t in pairs(spec) do
        if scope ~= "account" and scope ~= "char" then error("HU:Saved: ámbito desconocido: " .. tostring(scope), 2) end
        for k, v in pairs(t) do
            local key, def = k, v
            if type(k) == "number" then key, def = v, nil end
            if HU.savedScope[key] then error("HU:Saved: «" .. tostring(key) .. "» ya está declarada", 2) end
            HU.savedScope[key] = scope
            if scope == "char" then HU.PER_CHAR[key] = true end
            if def ~= nil then DEFAULTS[key] = def end
        end
    end
end
-- Las de Core.lua (las demás, en su módulo)
HU:Saved({
    account = {
        autoGuard = false,    -- expulsar automáticamente a intrusos
        grace = 120,          -- segundos de margen antes de considerar a alguien intruso
        debug = false,
        showChannel = false,  -- mostrar el canal oculto (depuración)
        log = {},
        ownPaint = true,      -- adornar las líneas de mi hermandad al escribirlas en la ventana (/gu pintar)
        -- (restos sin uso: ver docs/fallos-conocidos.md. «theme» se sigue guardando como siempre)
        theme = "default",
    },
    char = {
        "myRole",
        -- (restos sin uso: ver docs/fallos-conocidos.md)
        "chatTab", "chatTabsMade", "proposals",
    },
})

---------------------------------------------------------------------------
-- Migraciones de lo guardado: adb.schema (la cuenta) y cdb.schema (cada personaje) [+ARCHITECTURE.md]
---------------------------------------------------------------------------
HU.migrations = { account = {}, char = {} }
-- n: su número, en orden y sin huecos. fn(adb, cdb, info) hace el cambio (dos veces seguidas no
-- estropea nada) y devuelve false si aún no puede: info es la de RefreshConfig (Config.lua),
-- { guild, text }, y al cargar el addon todavía no la hay. Se vuelve a probar en la siguiente.
function HU:RegisterMigration(scope, n, name, fn)
    local list = HU.migrations[scope]
    if not list then error("migración: ámbito desconocido: " .. tostring(scope), 2) end
    if n ~= #list + 1 then error("migración " .. scope .. " " .. tostring(n) .. ": toca la " .. (#list + 1), 2) end
    list[n] = { name = name, fn = fn }
end
function HU:RunMigrations(info)
    local adb, cdb = HU.adb, HU.cdb
    if not (adb and cdb) then return end
    for _, scope in ipairs({ "account", "char" }) do
        local list, db = HU.migrations[scope], scope == "account" and adb or cdb
        local cur = tonumber(db.schema) or 0
        if cur > #list then
            -- (lo guardado es de una versión más nueva: no se toca nada; se avisa en /gu errores)
            HU:RecordError({ msg = string.format("Lo guardado (%s) es de una versión más nueva del addon (esquema %d; esta entiende hasta el %d): no se cambia nada. Actualiza el addon.",
                scope == "account" and "cuenta" or "personaje", cur, #list), stack = "" }, "migraciones")
        else
            for i = cur + 1, #list do
                if list[i].fn(adb, cdb, info) == false then break end
                db.schema = i
            end
            db.schema = db.schema or cur
        end
    end
end

HU:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    -- la versión de pruebas "Guild Union 20" (o el viejo We Love PvP) no pueden ir a la vez:
    -- usan los mismos comandos y el mismo canal
    local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if IsLoaded and (IsLoaded("GuildUnion20") or IsLoaded("WeLovePvP")) then HU.oldAddon = true end
    GuildUnionDB = GuildUnionDB or {}
    for k, v in pairs(DEFAULTS) do
        if GuildUnionDB[k] == nil and not HU.PER_CHAR[k] then
            GuildUnionDB[k] = (type(v) == "table") and {} or v
        end
    end
    -- Lo de cada personaje va aparte (si no, un personaje de otra hermandad, o al que han echado, [+ARCHITECTURE.md]
    local adb = GuildUnionDB
    adb.chars = adb.chars or {}
    local pn, second = UnitName("player")
    if type(second) == "string" and second ~= "" then pn = tostring(pn) .. " " .. second end -- (apellido)
    local ck = tostring(pn or "?") .. "-" .. tostring(GetRealmName and GetRealmName() or "?")
    local cdb = adb.chars[ck]
    if not cdb then
        cdb = (type(GuildUnionCharDB) == "table" and next(GuildUnionCharDB)) and GuildUnionCharDB or {}
        adb.chars[ck] = cdb
    end
    GuildUnionCharDB = nil
    for k in pairs(HU.PER_CHAR) do
        if cdb[k] == nil and type(DEFAULTS[k]) == "table" then cdb[k] = {} end
    end
    HU.adb, HU.cdb = adb, cdb
    HU.db = setmetatable({}, {
        __index = function(_, k) if HU.PER_CHAR[k] then return cdb[k] end return adb[k] end,
        __newindex = function(_, k, v) if HU.PER_CHAR[k] then cdb[k] = v else adb[k] = v end end,
    })
    -- (las que no necesitan nada del juego, ya; las demás, cuando se lea la Información)
    HU:RunMigrations(nil)
    -- (sin elegir a mano: el idioma del juego; castellano solo si el juego está en español)
    if not HU.db.lang or not HU.db.langChosen then
        local loc = GetLocale and GetLocale() or ""
        HU.db.lang = (loc == "esES" or loc == "esMX") and "es" or "en"
    end
    HU:ApplyLanguage(HU.db.lang)
    -- opciones quitadas del panel: se dejan con su valor normal
    if not HU.db.debug then HU.db.showChannel = false end   -- el canal oculto no se ve en el chat
    HU:StrictMode(HU.db.debug)
end)

HU:On("PLAYER_LOGIN", function()
    if HU.oldAddon then
        -- el addon viejo sigue cargado en esta sesión: no arrancamos dos a la vez
        HU:Print(L("|cffff6060Tienes otra versión de Guild Union activada a la vez (Guild Union 20 o We Love PvP).|r Desactívala en la lista de AddOns y recarga (/reload)."))
        return
    end
    HU.loginT = GetTime()
    if HU.badEvents then HU:Debug("Eventos que este cliente no tiene:", table.concat(HU.badEvents, ", ")) end
    HU:CheckModules()
    for _, fn in ipairs(HU.startFns) do HU:SafeCall("inicio", fn) end
end)

---------------------------------------------------------------------------
-- Comandos
---------------------------------------------------------------------------
local function onoff(v, current)
    if v == "on" or v == "si" or v == "sí" then return true end
    if v == "off" or v == "no" then return false end
    return not current
end

local EXAMPLE = HU.LT({
    "Pon estas líneas en la |cffffd100Información de hermandad|r de CADA hermandad (las mismas en todas):",
    "   GU:g:Nombre Hermandad Uno:HU1",
    "   GU:g:Nombre Hermandad Dos:HU2",
    "Canal y contraseña, en la |cffffd100nota de oficial|r del maestro (máx. 31 letras; nadie más la ve):",
    "   GU:c:Canal:clave",
    "El addon los reparte solo a todos. Para el chat de oficiales, en la nota de oficial de otro miembro:",
    "   GU:o:CanalOfi:clave2",
    "El canal solo admite letras y números. Las etiquetas, hasta 6 letras o números.",
})

-- Registro de los comandos /gu: cada uno con sus alias, su ayuda y lo que hace [+ARCHITECTURE.md]
HU.slashCmds = {} -- [nombre o alias] = lo registrado
HU.slashList = {} -- lo registrado, en orden: la ayuda sale en este orden
local SLASH_KEYS = { aliases = "table", help = true, fn = "function", available = "function" }
function HU:RegisterSlash(name, spec)
    if type(name) ~= "string" or name ~= name:lower() then error("comando no válido: " .. tostring(name), 2) end
    spec = spec or {}
    for k, v in pairs(spec) do
        local want = SLASH_KEYS[k]
        if not want then error("/gu " .. name .. ": clave desconocida: " .. tostring(k), 2) end
        if want ~= true and type(v) ~= want then error("/gu " .. name .. ": " .. k .. " tiene que ser " .. want, 2) end
    end
    if spec.help then spec.help = HU.LT(type(spec.help) == "table" and spec.help or { spec.help }) end
    spec.name = name
    -- (sin fn solo es una línea de la ayuda: /hg, que es otro comando)
    if spec.fn then
        local names = { name }
        for _, a in ipairs(spec.aliases or {}) do names[#names + 1] = a end
        for _, n in ipairs(names) do
            if HU.slashCmds[n] then error("/gu " .. n .. ": ya registrado", 2) end
            HU.slashCmds[n] = spec
        end
    end
    HU.slashList[#HU.slashList + 1] = spec
    return spec
end
local function PrintHelp()
    for _, spec in ipairs(HU.slashList) do
        for _, l in ipairs(spec.help or {}) do HU:Print(l) end
    end
end

SLASH_HERMANDADUNIDA1 = "/gu"
SLASH_HERMANDADUNIDA2 = "/guildunion"
SLASH_HERMANDADUNIDA3 = "/wlp"        -- los de antes siguen valiendo
SLASH_HERMANDADUNIDA4 = "/welovepvp"
SlashCmdList.HERMANDADUNIDA = function(input)
    if HU.oldAddon then return HU:Print(L("|cffff6060Tienes otra versión de Guild Union activada a la vez (Guild Union 20 o We Love PvP).|r Desactívala en la lista de AddOns y recarga (/reload).")) end
    input = HU.Trim(input or "")
    local cmd, rawArg = input:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local arg = rawArg:lower()
    local spec = HU.slashCmds[cmd]
    -- (available: el comando depende de un archivo que puede no estar; sin él, la ayuda)
    if spec and (not spec.available or spec.available()) then return spec.fn(arg, rawArg, spec.name) end
    PrintHelp()
end

-- Los comandos, en el orden de la ayuda (los que no tienen ayuda, al final)
HU:RegisterSlash("panel", { aliases = { "", "lista", "list" },
    help = "|cffffd100/gu|r  abre o cierra el panel",
    fn = function() HU.UI:Toggle() end })
HU:RegisterSlash("estado", { aliases = { "status" },
    help = "|cffffd100/gu estado|r  muestra el estado del canal, los contactos y la guardia",
    fn = function() HU:PrintStatus() end })
HU:RegisterSlash("config", {
    help = "|cffffd100/gu config|r  explica cómo configurar las hermandades",
    fn = function() for _, l in ipairs(EXAMPLE) do HU:Print(l) end end })
HU:RegisterSlash("/hg", { help = "|cffffd100/hg mensaje|r  escribe en el chat de hermandad unido (en modo prueba sustituye a /g)" })
HU:RegisterSlash("fijar", { aliases = { "pin" },
    help = "|cffffd100/gu fijar texto|r  maestro u oficial: fija un mensaje arriba del chat de la ventana de hermandad, para toda la comunidad  (|cffffd100/gu fijar borrar|r para quitarlo)",
    fn = function(arg, rawArg)
        if arg == "" then
            local p = HU.db.pinned
            HU:Print((p and (p.text or "") ~= "") and (L("Mensaje fijado: ") .. p.text) or L("No hay mensaje fijado. Oficiales: /gu fijar texto"))
        elseif arg == "borrar" or arg == "clear" then
            HU:SetPinned("")
        else
            HU:SetPinned(rawArg)
        end
    end })
HU:RegisterSlash("canal", { aliases = { "channel" },
    help = "|cffffd100/gu canal|r  lista quién está en el canal (propietario y moderadores)",
    fn = function() HU:PrintChannelRoster() end })
HU:RegisterSlash("carril", { aliases = { "lane" },
    help = "|cffffd100/gu carril|r  en qué carril del canal está la comunidad (|cffffd100reiniciar|r: oficiales, todos al principal)",
    fn = function(arg)
        -- (copia 118: subir y reiniciar mueven a toda la comunidad: hace falta que lo confirme otro
        -- oficial, o el maestro escribiéndolo dos veces; ver HU:ProposeLane en Channel.lua)
        local officer = (HU:IsOfficerName(HU:Me())) or HU:CanOfficer()
        local act = ((arg == "reiniciar" or arg == "reset") and "reset") or ((arg == "subir" or arg == "up") and "up")
            or ((arg == "juntar" or arg == "aqui" or arg == "here" or arg == "gather") and "here") or nil
        if act or arg == "confirmar" or arg == "confirm" then
            if HU:LaneLock() then
                HU:Print(string.format(L("La sala está fijada en la %d por la Información de hermandad (línea GU:l). Mientras esté esa línea no se puede cambiar."), HU:LaneLock()))
            elseif not officer or not HU.cfg then
                HU:Print(L("Solo los maestros y oficiales de una hermandad unida pueden cambiar el carril."))
            elseif act then
                HU:ProposeLane(act)
            else
                HU:ConfirmLane()
            end
        else
            local st = HU:LaneState()
            local left = st.lane > 0 and math.max(0, math.ceil((st.t + HU.LANE_TTL - ((GetServerTime and GetServerTime()) or time())) / 60)) or nil
            HU:Print(L("Carril del canal: ") .. st.lane .. L(" (generación ") .. st.gen .. ")"
                .. (left and (L(". Vuelve al principal en ") .. left .. " min") or ""))
            if HU.LaneStatusText and HU.cfg then HU:Print(HU:LaneStatusText()) end
        end
    end })
HU:RegisterSlash("recargar", { aliases = { "reload" },
    help = "|cffffd100/gu recargar|r  vuelve a leer la configuración",
    fn = function()
        HU:RequestRoster(true)
        HU:RefreshConfig(true)
        HU:Print(L("Configuración recargada."))
    end })
HU:RegisterSlash("notacanal", { aliases = { "channelnote" },
    help = "|cffffd100/gu notacanal|r  oficiales: la línea GU:c (canal y contraseña) para volver a ponerla en la nota de oficial",
    available = function() return HU.ShowChannelNoteLine ~= nil end,
    fn = function() return HU:ShowChannelNoteLine() end })
-- (la ventana de hermandad del juego: por si la J abre GuildUnion; ahí se edita la Información)
HU:RegisterSlash("hermandad", { aliases = { "guild" },
    help = "|cffffd100/gu hermandad|r  abre la ventana de hermandad del juego (ahí se edita la Información). La J abre GuildUnion; /gu tecla off la devuelve a la ventana del juego",
    fn = function()
        -- (no se abre desde el addon: el juego bloquearía luego cambiar rangos y notas; ver BlizzTab.lua)
        HU:Print(L("Pulsa J (o el botón de Hermandad) para abrir la ventana de hermandad."))
    end })
HU:RegisterSlash("etiqueta", { aliases = { "tag" },
    help = "|cffffd100/gu etiqueta on/off|r  muestra la etiqueta de la hermandad en los mensajes",
    fn = function(arg)
        -- (lo mismo que el botón de Ajustes: etiqueta en vez de punto)
        HU.db.chatMark = onoff(arg, HU.db.chatMark == "tag") and "tag" or "dot"
        HU:Print(L("Etiqueta de hermandad: ") .. (HU.db.chatMark == "tag" and "sí" or "no"))
    end })
HU:RegisterSlash("visto", { aliases = { "seen" },
    help = "|cffffd100/gu visto Nombre|r  cuántas líneas de ese jugador te han llegado por el canal y cuántas se te han enseñado",
    fn = function(arg, rawArg) HU:PrintSeen(rawArg ~= "" and rawArg or arg) end })
HU:RegisterSlash("sonda", { aliases = { "probe" },
    help = "|cffffd100/gu sonda 30|r  oficiales: manda 30 mensajes ocultos de prueba por el canal; cada uno ve cuántos le llegan",
    fn = function(arg) HU:SendProbe(tonumber(arg) or 30) end })
-- (una línea más de la ayuda de /gu carril, en su sitio de siempre)
HU:RegisterSlash("carril juntar", { help = "|cffffd100/gu carril|r  en qué sala del canal estás y si hay gente en otra · oficiales: /gu carril juntar (todos a tu sala)" })
HU:RegisterSlash("version", { aliases = { "versión" },
    help = "|cffffd100/gu version Nombre|r  qué versión del addon tiene ese jugador, si se sabe",
    fn = function(_, rawArg)
        if rawArg == "" then return PrintHelp() end
        -- (copia 114: la versión del addon de otro jugador. Solo se sabe de quien me ha saludado: los
        -- compañeros de mi hermandad con el addon y mis contactos de las otras)
        local k = HU:Key(rawArg)
        local p = k and ((HU.guildPeers and HU.guildPeers[k]) or (HU.remote and HU.remote[k]))
        if p and p.ver then HU:Print(HU:Nice(rawArg) .. ": " .. L("versión ") .. tostring(p.ver))
        else HU:Print(HU:Nice(rawArg) .. ": " .. L("no sé su versión. Solo la conozco de quien me ha saludado con el addon: los de mi hermandad y mis contactos de las otras. Pídele que mire el título de su pestaña de GuildUnion.")) end
    end })
HU:RegisterSlash("guardia", { aliases = { "guard" },
    help = "|cffffd100/gu guardia revisar|r  maestro u oficial: busca en el canal a quien no es de ninguna hermandad (tú decides a quién echar)",
    fn = function(arg)
        if arg == "revisar" or arg == "review" then return HU:GuardReview() end
        HU.db.autoGuard = onoff(arg, HU.db.autoGuard)
        HU:Print(L("Expulsión automática: ") .. (HU.db.autoGuard and "activada" or "desactivada"))
        HU:Changed("guard")
    end })
HU:RegisterSlash("margen", { aliases = { "margin" },
    help = "|cffffd100/gu margen <segundos>|r  espera antes de echar a quien no está en ninguna hermandad",
    fn = function(arg)
        local n = tonumber(arg)
        if n and n >= 30 and n <= 1800 then
            HU.db.grace = n
            HU:Print(L("Margen: ") .. n .. " s")
        else
            HU:Print(L("Indica un número de segundos entre 30 y 1800."))
        end
    end })
HU:RegisterSlash("rol", { aliases = { "role" },
    help = "|cffffd100/gu rol tanque/sanador/dps/auto|r  tu rol en tu ficha (por defecto, según tus talentos)",
    fn = function(arg)
        arg = ({ tank = "tanque", healer = "sanador" })[arg] or arg
        local map = { tanque = "T", sanador = "H", healer = "H", dps = "D", feral = "F" }
        if arg == "auto" or arg == "" then HU.db.myRole = nil
        elseif map[arg] then HU.db.myRole = map[arg]
        else return HU:Print(L("Uso: /gu rol tanque | sanador | dps | feral | auto")) end
        HU:UpdateMyProfile(true)
        HU:Print(L("Tu rol: ") .. (HU.db.myRole and HU.ROLES[HU.db.myRole].name or L("automático (por tus talentos)")))
    end })
HU:RegisterSlash("minimapa", { aliases = { "minimap" },
    help = "|cffffd100/gu minimapa on/off|r  muestra u oculta el botón del minimapa",
    fn = function(arg)
        local show = onoff(arg, not HU.db.minimapHidden)
        HU:ShowMinimapButton(show)
        HU:Print(L("Botón del minimapa: ") .. (show and "visible" or "oculto"))
    end })
HU:RegisterSlash("debug", {
    help = "|cffffd100/gu debug on/off|r  mensajes de depuración y canal visible",
    fn = function(arg)
        HU.db.debug = onoff(arg, HU.db.debug)
        HU.db.showChannel = HU.db.debug
        HU:StrictMode(HU.db.debug)
        HU:Print(L("Depuración: ") .. (HU.db.debug and L("activada (canal visible)") or "desactivada"))
    end })
HU:RegisterSlash("errores", { aliases = { "errors" },
    help = "|cffffd100/gu errores|r  muestra los errores guardados del addon  (|cffffd100/gu errores borrar|r: los borra;  |cffffd100/gu errores pedir contraseña|r: oficiales, pide a todos los suyos)",
    fn = function(arg, rawArg)
        if arg:match("^pedir") or arg:match("^ask") then
            if not HU:CanOfficer() then return HU:Print(L("Solo los oficiales pueden pedir los errores de todos.")) end
            -- pedir a todos sus errores guardados (con la contraseña del chat unido)
            local pass = rawArg:match("^%S+%s+(.+)$")
            local ok, why = HU:AskErrors(pass and HU.Trim(pass))
            HU:Print(ok and L("Errores pedidos a todos. Irán llegando en el próximo medio minuto (/gu errores para verlos).")
                or (L("No se pueden pedir los errores: ") .. tostring(why) .. L("   (uso: /gu errores pedir contraseña)")))
        elseif arg == "borrar" or arg == "clear" then
            HU:ClearAllErrors()
        else
            HU:ShowErrors()
        end
    end })
HU:RegisterSlash("diag", {
    help = "|cffffd100/gu diag|r  diagnóstico del chat (qué llega del juego y qué guarda el addon)",
    fn = function()
        -- (primero, si el juego tiene bloqueados /ginvite, /gpromote…)
        HU:OrdersDiag()
        local lines = HU:DiagLines()
        if HU.UI and HU.UI.ShowCopy then HU.UI:ShowCopy("Guild Union - diagnóstico", table.concat(lines, "\n"))
        else for _, l in ipairs(lines) do HU:Print(l) end end
    end })
HU:RegisterSlash("memoria", { aliases = { "memory" },
    help = "|cffffd100/gu memoria|r  memoria que usa el addon y mensajes en cola",
    fn = function()
        -- cuánta memoria usa el addon (para ver que no crece sin parar en sesiones largas)
        local upd = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
        local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
        if upd and get then
            pcall(upd)
            local ok, kb = pcall(get, ADDON_NAME)
            if ok and kb then
                HU.memPeak = math.max(HU.memPeak or 0, kb)
                HU:Print(string.format(L("Memoria del addon: %.1f MB (máximo en esta sesión: %.1f MB). Cola: %d mensajes."), kb / 1024, HU.memPeak / 1024, HU:QueueSize() or 0))
            end
        end
    end })
HU:RegisterSlash("cola", { aliases = { "queue" },
    help = "|cffffd100/gu cola|r  mensajes del addon pendientes de enviar  (|cffffd100/gu cola vaciar|r para vaciarla)",
    fn = function(arg)
        if arg == "vaciar" or arg == "clear" or arg == "limpiar" then
            local n = HU:ClearQueue()
            HU:Print(L("Cola de envío vaciada (") .. n .. L(" mensajes). Lo pendiente se volverá a pedir y mandar solo."))
        else
            HU:Print(HU:QueueText() .. L("   (/gu cola vaciar para vaciarla)"))
        end
        if HU.UI and HU.UI.UpdateOfficers then HU.UI:UpdateOfficers() end
    end })
HU:RegisterSlash("buscar", { aliases = { "search" },
    help = "|cffffd100/gu buscar Nombre [texto]|r  oficiales: qué ha dicho alguien en los últimos 30 días (también lo que pasó mientras no estabas)",
    fn = function(_, rawArg, cmd) HU:HistCommand(cmd, rawArg) end })
HU:RegisterSlash("historial", { aliases = { "history" },
    help = "|cffffd100/gu historial|r  oficiales: ventana del historial  (|cffffd100/gu historial off|r / |cffffd100on|r para apagarlo o encenderlo)",
    fn = function(_, rawArg, cmd) HU:HistCommand(cmd, rawArg) end })
HU:RegisterSlash("registro", {
    help = "|cffffd100/gu registro on [quien dirige]|r  registro de pruebas (apagado por defecto)  ·  |cffffd100/gu nota texto|r  apunta una nota con los números del momento",
    fn = function(_, rawArg, cmd) HU:TestLogCommand(cmd, rawArg) end })
HU:RegisterSlash("idioma", { aliases = { "lang", "language" },
    help = "|cffffd100/gu idioma en/es|r  cambia el idioma (English / Español)",
    fn = function(arg)
        if arg == "en" or arg == "english" or arg == "ingles" or arg == "inglés" then return HU:SetLang("en") end
        if arg == "es" or arg == "español" or arg == "espanol" or arg == "spanish" then return HU:SetLang("es") end
        local miss = {}
        for k in pairs(HU.missingEN) do miss[#miss + 1] = k end
        table.sort(miss)
        HU:Print(HU:LangName() .. "  -  /gu idioma en | es")
        if HU.lang == "en" then
            HU.UI:ShowCopy("Untranslated texts seen so far: " .. #miss, #miss > 0 and table.concat(miss, "\n") or "None.")
        end
    end })
HU:RegisterSlash("confirmar", { aliases = { "confirm" },
    help = "|cffffd100/gu confirmar ETIQUETA|r  oficiales: da por buena la lista de otra hermandad (sus rangos cuentan ya)",
    fn = function(_, rawArg)
        -- (un oficial da por buena la lista que tengo de otra hermandad: el ancla de una comunidad
        -- nueva, sin contactos comprobados todavía. Ver «Estado de la lista» en Domain/Trust.lua)
        if not HU:CanOfficer() then
            return HU:Print(L("Solo los oficiales pueden confirmar la lista de otra hermandad."))
        end
        local tag = HU.Trim(rawArg or "")
        if HU.cfg and not HU.cfg.byTag[tag] and HU.cfg.byTag[tag:upper()] then tag = tag:upper() end
        if tag == "" or tag == HU.myTag or not (HU.cfg and HU.cfg.byTag[tag]) then
            return HU:Print(L("Uso: /gu confirmar ETIQUETA   (la de otra hermandad de la comunidad)"))
        end
        local before = HU:ConfirmRoster(tag)
        if not before then
            return HU:Print(string.format(L("Aún no tengo la lista de <%s>: espera a que llegue y vuelve a probar."), tag))
        end
        HU:Print(string.format(L("Lista de <%s> confirmada (antes: %s). Sus rangos ya cuentan."), tag, L(HU.RosterStateName(before) or "?")))
    end })
-- asistente «Crear comunidad» (y modo prueba, que no toca nada: /gu asistente prueba)
HU:RegisterSlash("asistente", { aliases = { "wizard", "crear", "create" },
    help = "|cffffd100/gu asistente|r  crear la comunidad o invitar paso a paso  (|cffffd100/gu asistente prueba|r: verlo sin tocar nada)",
    available = function() return HU.OpenWizard ~= nil end,
    fn = function(arg) return HU:OpenWizard(arg == "prueba" or arg == "test") end })
HU:RegisterSlash("hermandades", { aliases = { "guilds" },
    help = "|cffffd100/gu hermandades|r  ventana de Gestión de hermandades (principal, gestores e invitaciones)",
    available = function() return HU.ShowGuildsWindow ~= nil end,
    fn = function() return HU:ShowGuildsWindow() end })
-- gestión de hermandades: principal, gestores e invitaciones (Community.lua)
HU:RegisterSlash("invitar", { aliases = { "invite" },
    help = "|cffffd100/gu invitar Nombre ETIQ|r  maestro de la principal y gestores: invita a una hermandad (al maestro u oficial que pueda editar su Información)",
    fn = function(_, rawArg)
        local who, tag = rawArg:match("^(.-)%s+(%S+)$")
        if not who or who == "" then return HU:Print(L("Uso: /gu invitar Nombre del maestro (u oficial) ETIQ")) end
        local ok, why = HU:InviteGuild(who, tag)
        if not ok and why then HU:Print("|cffff6060" .. why .. "|r") end
    end })
HU:RegisterSlash("gestor", { aliases = { "manager" },
    help = "|cffffd100/gu gestor Nombre|r  /  |cffffd100/gu gestor quitar Nombre|r  maestro de la principal: quién puede invitar  ·  |cffffd100/gu gestores|r  los ve",
    fn = function(_, rawArg)
        local add, who = true, rawArg
        local q = rawArg:match("^[Qq]uitar%s+(.+)$") or rawArg:match("^[Rr]emove%s+(.+)$")
        if q then add, who = false, q end
        if HU.Trim(who) == "" then return HU:Print(L("Uso: /gu gestor Nombre  ·  /gu gestor quitar Nombre")) end
        local ok, why = HU:SetManager(who, add)
        if ok then HU:Print((add and L("Gestor añadido: ") or L("Gestor quitado: ")) .. HU:Short(HU:FullName(who) or who))
        elseif why then HU:Print("|cffff6060" .. why .. "|r") end
    end })
HU:RegisterSlash("pasarcanal", { aliases = { "sendchannel" },
    help = "|cffffd100/gu pasarcanal Nombre|r  le pasa el canal a quien lo está esperando (de tu hermandad o de la comunidad), sin enseñar la contraseña",
    available = function() return HU.PassChannelTo ~= nil end,
    fn = function(_, rawArg) return HU:PassChannelTo(rawArg) end })

-- (sin ayuda)
HU:RegisterSlash("perf", { available = function() return HU.PerfCommand ~= nil end,
    fn = function(arg) return HU:PerfCommand(arg) end })
HU:RegisterSlash("gestores", { aliases = { "managers" },
    fn = function()
        local list = HU:Managers()
        HU:Print(L("Hermandad principal: ") .. (HU:PrincipalTag() and ("<" .. HU:PrincipalTag() .. ">") or "?")
            .. L("  ·  Gestores: ") .. (#list > 0 and table.concat(list, ", ") or L("ninguno")))
    end })
HU:RegisterSlash("quitarhermandad", { aliases = { "removeguild" },
    fn = function(_, rawArg)
        local ok, why = HU:RemoveNetGuild(rawArg)
        if ok then HU:Print(L("Hermandad quitada de la comunidad: <") .. HU.Trim(rawArg):upper() .. ">")
        elseif why then HU:Print("|cffff6060" .. why .. "|r") end
    end })
-- (la J abre la ventana de hermandad del juego en el chat; /gu tecla on hace que abra GuildUnion)
HU:RegisterSlash("tecla", { aliases = { "key" },
    fn = function(arg)
        if arg == "off" then HU.db.keyJ = nil elseif arg == "on" then HU.db.keyJ = true end
        HU:ApplyKeyJ()
        HU:Print(not HU.db.keyJ and L("La J abre la ventana de hermandad del juego en su pestaña de siempre (/gu tecla on para que se abra en la pestaña GuildUnion).")
            or L("La J abre la ventana de hermandad del juego en la pestaña GuildUnion (/gu tecla off para que se abra como siempre)."))
    end })
HU:RegisterSlash("test", {
    fn = function(arg, rawArg)
        -- franja de prueba del mensaje fijado, solo en mi ventana (no se manda ni se guarda)
        if arg == "off" then
            HU.pinPreview = nil
            HU:Print(L("Prueba del mensaje fijado quitada."))
        else
            local text = rawArg ~= "" and rawArg or L("Esto es un mensaje fijado de prueba: así se verá arriba del chat de la hermandad.")
            HU.pinPreview = { text = text, author = HU:Me(), tag = HU.myTag, t = HU.StampNow() }
            HU:Print(L("Prueba del mensaje fijado: abre la ventana de hermandad (J) en el chat. /gu test off la quita."))
        end
        if HU.UI and HU.UI.UpdatePinned then HU.UI:UpdatePinned() end
    end })
HU:RegisterSlash("invitaciones", { aliases = { "invites" },
    fn = function() HU:ShowInviteLog() end })
HU:RegisterSlash("listanegra", { aliases = { "blacklist" },
    fn = function() HU:ShowBlacklist() end })
HU:RegisterSlash("prat", {
    fn = function(arg)
        -- (copia 121, de prueba: usar o no el formato de Prat, y cómo va)
        if arg == "on" or arg == "off" or arg == "si" or arg == "no" then HU.db.pratOff = (arg == "off" or arg == "no") or nil end
        local st = HU.pratStats or {}
        HU:Print("Formato de Prat: " .. (HU.db.pratOff and "apagado" or "encendido")
            .. " · Prat: " .. ((HU.UsingPrat()) and "cargado" or "no está")
            .. " · enganchado: " .. ((HU.PratActive()) and "sí" or "no")
            .. " · líneas de otras hermandades con su formato: " .. (st.ok or 0)
            .. " · con el de siempre: " .. (st.fallback or 0)
            .. " · de mi hermandad adornadas: " .. (st.own or 0)
            .. " · con nivel sabido: " .. (st.level or 0)
            .. " · nombres con color de clase: " .. (st.class or 0)
            .. " · fallos: " .. (st.err or 0) .. (st.last and (" (" .. st.last .. ")") or ""))
    end })
HU:RegisterSlash("wm", {
    -- (copia 125, de prueba: cómo va la pestaña dentro de Whisper Messenger)
    fn = function() HU:Print(HU:WMStatus() or "sin pestaña de Whisper Messenger") end })
HU:RegisterSlash("pintar", { aliases = { "paint" },
    fn = function(arg)
        -- (copia 94, de prueba: enciende o apaga el adorno de las líneas de mi hermandad)
        HU.db.ownPaint = onoff(arg, HU.db.ownPaint)
        HU:Print("Adorno de mi hermandad: " .. (HU.db.ownPaint and "sí" or "no"))
    end })
-- (copia 148: ¿le llega a esa persona mi texto por el canal?)
HU:RegisterSlash("prueba", { fn = function(_, rawArg) HU:TextProbe(rawArg) end })
-- (copia 147: el número del canal en mi juego frente a lo que dice el servidor)
HU:RegisterSlash("ids", { fn = function() HU:PrintChannelIds() end })
-- (copia 147: todo lo que sabe el addon, en una ventana para copiar)
HU:RegisterSlash("todo", { aliases = { "informe", "all", "report" },
    fn = function() HU:FullReport() end })
-- ¿tiene el juego bloqueados /ginvite, /gpromote…? (los bloquea si un addon toca la caja del chat)
HU:RegisterSlash("ordenes", { aliases = { "órdenes" }, fn = function() HU:OrdersDiag() end })
HU:RegisterSlash("nota", { fn = function(_, rawArg, cmd) HU:TestLogCommand(cmd, rawArg) end })
HU:RegisterSlash("fase", { aliases = { "phase" },
    fn = function()
        -- (versión solo chat: ya no hay fases; se borra la que pudiera haber guardada)
        HU.db.phase = nil
        HU:Print(L("Esta versión es solo de chat: las listas completas no se pueden activar."))
    end })

function HU:PrintStatus()
    for _, line in ipairs(self:StatusLines()) do self:Print(line) end
    -- (listas de otras hermandades que aún no están confirmadas: sus rangos no cuentan, o cuentan solo
    -- de forma provisional)
    if not self.cfg or not self.RosterStateOf then return end
    for _, tag in ipairs(self:OtherTags()) do
        local s = self.RosterStateOf(tag)
        if s and s ~= "c" then
            self:Print(string.format(L("|cffff8800Lista de <%s> sin confirmar|r (%s). Un oficial puede confirmarla con /gu confirmar %s"),
                tag, L(self.RosterStateName(s) or "?"), tag))
        end
    end
end

-- /hg mensaje : escribe en el chat de hermandad unido (útil en modo prueba, donde no hay /g)
SLASH_WELOVEPVPGUILD1 = "/hg"
SlashCmdList.WELOVEPVPGUILD = function(input)
    input = HU.Trim(input or "")
    if input == "" then return HU:Print(L("Uso: /hg mensaje")) end
    local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    fn(input, "GUILD")
end

-- Las líneas de /gu diag (copia 147: sacadas de la orden para que las use también /gu todo)
function HU:DiagLines()
        -- diagnóstico del chat: qué llega del juego y qué guarda el addon
        local h = HU.db.history or {}
        local by = {}
        for _, e in ipairs(h) do by[e.k or "?"] = (by[e.k or "?"] or 0) + 1 end
        local kinds = {}
        for k, v in pairs(by) do kinds[#kinds + 1] = k .. "=" .. v end
        local evs = {}
        for _, ev in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL", "CHAT_MSG_ADDON" }) do
            evs[#evs + 1] = ev:gsub("CHAT_MSG_", "") .. "=" .. (HU.evCount[ev] or 0) .. ((HU.evSecret[ev] or 0) > 0 and ("(ocultos " .. HU.evSecret[ev] .. ")") or "")
        end
        local lines = {
            "Guild Union " .. tostring(HU.version) .. " - " .. (GetBuildInfo and table.concat({ GetBuildInfo() }, " ", 1, 2) or "?"),
            "yo: " .. tostring(HU:Me()) .. "  en lista: " .. tostring(HU.roster[HU:MeKey() or ""] ~= nil) .. "  etiqueta: " .. tostring(HU.myTag) .. "  oficial: " .. tostring(HU:CanOfficer()),
            -- (el nombre del canal, tapado: este texto se pega en Discord)
            "canal: " .. tostring(HU:IsJoined("main")) .. " (" .. ((HU.cfg and type(HU.cfg.channel) == "string") and (HU.cfg.channel:sub(1, 2) .. "····") or "nil") .. ")  oficiales: " .. tostring(HU:IsJoined("off")) .. "  bloqueo del chat: " .. tostring(HU:IsChatLockedDown()),
            "historial: " .. #h .. "  (" .. table.concat(kinds, " ") .. ")",
            "eventos: " .. table.concat(evs, "  "),
            -- (presencia por el canal: avisos de salida del canal que han llegado, y cuántos han quitado a alguien)
            "canal: salidas " .. tostring(HU.chanLeaveN or 0) .. "  quitados por salida: " .. tostring(HU.chanLeaveDropN or 0),
            "issecretvalue: " .. tostring(issecretvalue ~= nil) .. "  filtros: " .. tostring(ChatFrame_AddMessageEventFilter ~= nil) .. "/" .. tostring(ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter ~= nil),
        }
        local np, rel = 0, {}
        for _, p in pairs(HU.guildPeers or {}) do np = np + 1; if p.relay then rel[#rel + 1] = p.name end end
        lines[#lines + 1] = "addon en mi hermandad: " .. np .. "  enlace: " .. (HU:IsRelay() and "yo" or (table.concat(rel, ",") ~= "" and table.concat(rel, ",") or "?"))
            .. "  cola: " .. (HU:QueueSize() or 0)
        local pin = HU.db.pinned
        lines[#lines + 1] = "fijado: " .. (pin and ((pin.text or "") ~= "" and ("sí, de " .. tostring(pin.author) .. " " .. HU.SafeDate("%d/%m %H:%M", pin.t)) or "vacío") or "no ha llegado")
        -- (las órdenes, del registro: HU:RegisterMessage, Protocol.lua. Las que no conoce esta versión, con ?)
        local rec, none, seen, total = {}, {}, HU.diagRecv or {}, 0
        for k in pairs(HU.msgs) do
            total = total + 1
            if seen[k] then rec[#rec + 1] = k .. "=" .. seen[k] else none[#none + 1] = k end
        end
        for k, n in pairs(seen) do if not HU.msgs[k] then rec[#rec + 1] = k .. "?=" .. n end end
        table.sort(rec)
        table.sort(none)
        lines[#lines + 1] = "recibido: " .. table.concat(rec, " ")
        lines[#lines + 1] = "sin recibir (de " .. total .. " órdenes): " .. table.concat(none, " ")
        -- (copia 109: el carril y el chat, por dónde sale y por dónde llega)
        local dc = HU.diagChat
        if dc then
            local st = HU:LaneState()
            local ls = HU.laneStats or {}
            lines[#lines + 1] = "carril: " .. tostring(st and st.lane) .. "  generación: " .. tostring(st and st.gen)
                .. "   rechazos del canal: " .. (ls.refused or 0) .. " (sin contar por acabar de entrar: " .. (ls.ignored or 0) .. ")"
            lines[#lines + 1] = "chat enviado: canal " .. dc.chan .. "  respaldo " .. dc.fallback .. "  (bloqueado " .. dc.blocked .. ", sin eco " .. dc.noEcho .. ")  texto del canal: " .. (HU:TextChatOK() and "bien" or "dado por roto")
            lines[#lines + 1] = "chat recibido: canal " .. dc.inChan .. "  respaldo " .. dc.inFallback .. "  retenidos de desconocidos " .. dc.held .. " (confirmados " .. dc.heldOK .. ")  repetidos por dos caminos " .. (dc.dup or 0)
            if HU.probeLog and #HU.probeLog > 0 then lines[#lines + 1] = "sondas recibidas: " .. table.concat(HU.probeLog, " · ") end
            local dr = {}
            for why, n in pairs(dc.drops or {}) do dr[#dr + 1] = "   " .. n .. " × " .. why end
            table.sort(dr)
            lines[#lines + 1] = "chat descartado: " .. (#dr == 0 and "nada" or "")
            for _, l in ipairs(dr) do lines[#lines + 1] = l end
            -- (copia 117: lo que caduca esperando en la cola y lo que rechaza el tope de admisión)
            local ex, ad = (HU.qStats and HU.qStats.expired) or {}, HU.diagAdmitDrop or {}
            lines[#lines + 1] = "chat caducado en la cola: CW " .. (ex.CW or 0) .. "  CG " .. (ex.CG or 0) .. "  CF " .. (ex.CF or 0)
                .. "   rechazados por tope de admisión: " .. ((ad.comprobado or 0) + (ad.otro or 0))
        end
        for i = math.max(1, #h - 2), #h do
            local e = h[i]
            if e then lines[#lines + 1] = "  [" .. tostring(e.k) .. "] " .. tostring(e.a) .. ": " .. tostring(type(e.m)) .. " " .. tostring(e.m and #tostring(e.m)) .. " letras" end
        end
        return lines
end

HU:Module("Core", { "Blacklist", "BlizzTab", "Channel", "Channels", "Combat", "Community", "Config", "Domain/Trust", "ErrorShare", "Guard", "GuardKeeper", "History", "InviteLog", "Minimap", "Net/Relay", "Net/Transport", "Orders", "Perf", "Pinned", "Popup", "PratBridge", "Report", "Roster", "Social", "TestLog", "UI", "WMPanel", "Wizard" })
