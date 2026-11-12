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

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
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

---------------------------------------------------------------------------
-- Errores: se guardan para poder copiarlos (/gu errores) y mandarlos
---------------------------------------------------------------------------
HU.errors = {}
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
    if #self.errors == 1 and self.CanOfficer and self:CanOfficer() then
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
    local got = self.ReceivedErrorsText and self:ReceivedErrorsText()
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

-- (offInPvp: el filtro se quita dentro de campos de batalla y arenas; ver HU:SyncChatFilters) [+ARCHITECTURE.md]
HU.chatFilters = {}
local function SetChatFilter(e, on)
    if e.on == on then return end
    local f
    if on then
        f = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    else
        f = ChatFrame_RemoveMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter)
    end
    if f then f(e.event, e.fn); e.on = on end
end

function HU.AddChatFilter(event, fn, offInPvp)
    local function safe(frame, ev, ...)
        -- (CUALQUIER dato secreto, no solo el texto o el nombre: en un campo de batalla el texto se
        -- lee pero el identificador de quien escribe es secreto. Si el filtro devuelve los datos, el
        -- juego los da por manchados y falla al pintar la línea; se contesta «nada» y no se toca)
        if AnySecret(...) then return false end
        -- (se devuelven TODOS los datos del mensaje: si se recortan, el chat normal lo oculta)
        local r = { pcall(fn, frame, ev, ...) }
        if not r[1] then
            if HU.RecordError then HU:RecordError(r[2], "filter " .. tostring(ev)) end
            return false
        end
        return unpack(r, 2, select("#", ...) + 2)
    end
    local e = { event = event, fn = safe, offInPvp = offInPvp and true or false, on = false }
    HU.chatFilters[#HU.chatFilters + 1] = e
    SetChatFilter(e, true)
end

-- Dentro de un campo de batalla o una arena los filtros marcados se quitan: con solo pasar por un
-- addon, el juego ya no se fía del mensaje y da error al pintarlo si lleva algo secreto
function HU:SyncChatFilters()
    local pvp = false
    if IsInInstance then
        local inInst, kind = IsInInstance()
        pvp = (inInst and (kind == "pvp" or kind == "arena")) and true or false
    end
    -- (se quitan y se ponen todos a la vez y en su orden, para que entre ellos no cambie)
    for _, e in ipairs(HU.chatFilters) do
        if e.offInPvp then SetChatFilter(e, false) end
    end
    if pvp then return end
    for _, e in ipairs(HU.chatFilters) do
        if e.offInPvp then SetChatFilter(e, true) end
    end
end

-- Temporizadores que nunca rompen: si la función falla, el error se guarda (como los eventos)
function HU.After(delay, fn)
    return C_Timer.After(delay, function() HU:SafeCall("timer", fn) end)
end
function HU.NewTicker(delay, fn, n)
    return C_Timer.NewTicker(delay, function(t) HU:SafeCall("ticker", fn, t) end, n)
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
            if HU.RefreshConfig then HU:RefreshConfig() end
        end
    end)
end)
HU:On("PLAYER_REGEN_ENABLED", function()
    if HU.infoPending then HU.After(1, function()
        if HU.infoPending and not HU:Restricted() then HU.infoPending = nil; if HU.RefreshConfig then HU:RefreshConfig() end end
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

function HU:Debug(...)
    if self.db and self.db.debug then
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        DEFAULT_CHAT_FRAME:AddMessage("|cff888888HU:|r " .. table.concat(parts, " "))
    end
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
function HU:SimpleMode() return false end

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

function HU:Changed(what)
    if self.UI and self.UI.MarkDirty then self.UI:MarkDirty(what) end
end

---------------------------------------------------------------------------
-- Base de datos
---------------------------------------------------------------------------
-- (lo que se guarda por personaje y no para toda la cuenta)
HU.PER_CHAR = { history = true, pinned = true, myRole = true, lastSeen = true, pvpSince = true, netChan = true,
    chatShow = true, netCfg = true, infoBackup = true, noteChanSeen = true, joinedChans = true, extraChans = true, chatTab = true,
    -- (eran de la cuenta y los heredaba un personaje de otra comunidad: un carril, unas listas o unas
    -- hermandades añadidas que no eran las suyas)
    chanLane = true, netGuilds = true, proposals = true, guildColors = true, customEmotes = true, lists = true,
    rankCache = true, offline = true, offlineT = true, peers = true, chatTabsMade = true, rosterCache = true, remoteRanks = true,
    quickCfg = true, managers = true, officerRanks = true, myOfficerRanks = true }

local DEFAULTS = {
    showTag = true,       -- mostrar <ETIQUETA> en los mensajes de otras hermandades
    autoGuard = false,    -- expulsar automáticamente a intrusos
    bans = {},            -- vetados del chat: [clave] = { name, on, by, tag, t }
    grace = 120,          -- segundos de margen antes de considerar a alguien intruso
    debug = false,
    showChannel = false,  -- mostrar el canal oculto (depuración)
    showLFG = false,      -- "Buscar grupo" solo en su pestaña
    audit = {},
    history = {},
    log = {},
    profiles = {},        -- fichas: [clave] = { race, r (rol), s (rama), p (profesiones), t }
    offline = {},         -- desconectados de otras hermandades: [tag] = { [clave] = { c, l, s } }
    mutes = {},           -- silenciados en el chat de la comunidad: [clave] = { name, u (hasta), by, tag, t }
    extraChans = {},
    rankCache = {},
    netChan = nil,        -- canal y contraseña repartidos desde la nota de oficial: { channel, pass, t, by, tag }       -- rangos vistos de otras hermandades: [clave] = { tag, idx, t }      -- canales extra: [nombre] = { name, pass, del, by, tag, t }
    theme = "default",    -- apariencia: default, classic, modern
    loginHistory = false, -- al entrar, escribir en el chat del juego el historial y lo de "mientras no estabas"
    peers = {},           -- contactos de otras hermandades vistos antes: [tag] = {[clave] = {name, t}}
    point = nil,
}

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
    -- (sin elegir a mano: el idioma del juego; castellano solo si el juego está en español)
    if not HU.db.lang or not HU.db.langChosen then
        local loc = GetLocale and GetLocale() or ""
        HU.db.lang = (loc == "esES" or loc == "esMX") and "es" or "en"
    end
    HU:ApplyLanguage(HU.db.lang)
    -- opciones quitadas del panel: se dejan con su valor normal
    if not HU.db.debug then HU.db.showChannel = false end   -- el canal oculto no se ve en el chat
    HU.db.showLFG = false                                      -- Buscar Grupo solo en su pestaña, nunca en el chat normal
end)

HU:On("PLAYER_LOGIN", function()
    if HU.oldAddon then
        -- el addon viejo sigue cargado en esta sesión: no arrancamos dos a la vez
        HU:Print(L("|cffff6060Tienes otra versión de Guild Union activada a la vez (Guild Union 20 o We Love PvP).|r Desactívala en la lista de AddOns y recarga (/reload)."))
        return
    end
    HU.loginT = GetTime()
    if HU.badEvents then HU:Debug("Eventos que este cliente no tiene:", table.concat(HU.badEvents, ", ")) end
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

local HELP = HU.LT({
    "|cffffd100/gu|r  abre o cierra el panel",
    "|cffffd100/gu estado|r  muestra el estado del canal, los contactos y la guardia",
    "|cffffd100/gu config|r  explica cómo configurar las hermandades",
    "|cffffd100/hg mensaje|r  escribe en el chat de hermandad unido (en modo prueba sustituye a /g)",
    "|cffffd100/glf mensaje|r  escribe en Buscar grupo (lo ven todas las hermandades)",
    "|cffffd100/gu pestañas|r  crea las pestañas Hermandad, Buscar grupo y Oficiales en el chat",
    "|cffffd100/gu fijar texto|r  maestro u oficial: fija un mensaje arriba del chat de la ventana de hermandad, para toda la comunidad  (|cffffd100/gu fijar borrar|r para quitarlo)",
    "|cffffd100/gu canal|r  lista quién está en el canal (propietario y moderadores)",
    "|cffffd100/gu carril|r  en qué carril del canal está la comunidad (|cffffd100reiniciar|r: oficiales, todos al principal)",
    "|cffffd100/gu recargar|r  vuelve a leer la configuración",
    "|cffffd100/gu notacanal|r  oficiales: la línea GU:c (canal y contraseña) para volver a ponerla en la nota de oficial",
    "|cffffd100/gu eco on/off|r  maestro: el enlace escribe en el /g el chat de las otras hermandades (para quien no tiene el addon)",
    "|cffffd100/gu hermandad|r  abre la ventana de hermandad del juego (ahí se edita la Información). La J abre GuildUnion; /gu tecla off la devuelve a la ventana del juego",
    "|cffffd100/gu etiqueta on/off|r  muestra la etiqueta de la hermandad en los mensajes",
    "|cffffd100/gu guardia revisar|r  maestro u oficial: busca en el canal a quien no es de ninguna hermandad (tú decides a quién echar)",
    "|cffffd100/gu margen <segundos>|r  espera antes de echar a quien no está en ninguna hermandad",
    "|cffffd100/gu rol tanque/sanador/dps/auto|r  tu rol en tu ficha (por defecto, según tus talentos)",
    "|cffffd100/gu minimapa on/off|r  muestra u oculta el botón del minimapa",
    "|cffffd100/gu debug on/off|r  mensajes de depuración y canal visible",
    "|cffffd100/gu errores|r  muestra los errores guardados del addon  (|cffffd100/gu errores borrar|r: los borra;  |cffffd100/gu errores pedir contraseña|r: oficiales, pide a todos los suyos)",
    "|cffffd100/gu diag|r  diagnóstico del chat (qué llega del juego y qué guarda el addon)",
    "|cffffd100/gu memoria|r  memoria que usa el addon y mensajes en cola",
    "|cffffd100/gu cola|r  mensajes del addon pendientes de enviar  (|cffffd100/gu cola vaciar|r para vaciarla)",
    "|cffffd100/gu buscar Nombre [texto]|r  oficiales: qué ha dicho alguien en los últimos 30 días (también lo que pasó mientras no estabas)",
    "|cffffd100/gu historial|r  oficiales: ventana del historial  (|cffffd100/gu historial off|r / |cffffd100on|r para apagarlo o encenderlo)",
    "|cffffd100/gu registro on [quien dirige]|r  registro de pruebas (apagado por defecto)  ·  |cffffd100/gu nota texto|r  apunta una nota con los números del momento",
    "|cffffd100/gu idioma en/es|r  cambia el idioma (English / Español)",
    "|cffffd100/gu confirmar ETIQUETA|r  oficiales: da por buena la lista de otra hermandad (sus rangos cuentan ya)",
    "|cffffd100/gu asistente|r  crear la comunidad o invitar paso a paso  (|cffffd100/gu asistente prueba|r: verlo sin tocar nada)",
    "|cffffd100/gu hermandades|r  ventana de Gestión de hermandades (principal, gestores e invitaciones)",
    "|cffffd100/gu invitar Nombre ETIQ|r  maestro de la principal y gestores: invita a una hermandad (al maestro u oficial que pueda editar su Información)",
    "|cffffd100/gu gestor Nombre|r  /  |cffffd100/gu gestor quitar Nombre|r  maestro de la principal: quién puede invitar  ·  |cffffd100/gu gestores|r  los ve",
    "|cffffd100/gu pasarcanal Nombre|r  le pasa el canal a quien lo está esperando (de tu hermandad o de la comunidad), sin enseñar la contraseña",
})

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
    -- comandos en inglés (los de español siguen valiendo)
    local ALIAS = { tabs = "pestañas", list = "lista", channel = "canal",
        tag = "etiqueta", guard = "guardia", margin = "margen", role = "rol", minimap = "minimapa",
        estado = "status", recargar = "reload", queue = "cola", memory = "memoria",
        search = "buscar", history = "historial", lane = "carril" }
    cmd = ALIAS[cmd] or cmd
    if cmd == "perf" and HU.PerfCommand then return HU:PerfCommand(arg) end
    if (cmd == "notacanal" or cmd == "channelnote") and HU.ShowChannelNoteLine then return HU:ShowChannelNoteLine() end
    if (cmd == "pasarcanal" or cmd == "sendchannel") and HU.PassChannelTo then return HU:PassChannelTo(rawArg) end
    -- gestión de hermandades: principal, gestores e invitaciones (Community.lua)
    if cmd == "invitar" or cmd == "invite" then
        local who, tag = rawArg:match("^(.-)%s+(%S+)$")
        if not who or who == "" then return HU:Print(L("Uso: /gu invitar Nombre del maestro (u oficial) ETIQ")) end
        local ok, why = HU:InviteGuild(who, tag)
        if not ok and why then HU:Print("|cffff6060" .. why .. "|r") end
        return
    end
    if cmd == "gestor" or cmd == "manager" then
        local add, who = true, rawArg
        local q = rawArg:match("^[Qq]uitar%s+(.+)$") or rawArg:match("^[Rr]emove%s+(.+)$")
        if q then add, who = false, q end
        if HU.Trim(who) == "" then return HU:Print(L("Uso: /gu gestor Nombre  ·  /gu gestor quitar Nombre")) end
        local ok, why = HU:SetManager(who, add)
        if ok then HU:Print((add and L("Gestor añadido: ") or L("Gestor quitado: ")) .. HU:Short(HU:FullName(who) or who))
        elseif why then HU:Print("|cffff6060" .. why .. "|r") end
        return
    end
    if cmd == "gestores" or cmd == "managers" then
        local list = HU:Managers()
        HU:Print(L("Hermandad principal: ") .. (HU:PrincipalTag() and ("<" .. HU:PrincipalTag() .. ">") or "?")
            .. L("  ·  Gestores: ") .. (#list > 0 and table.concat(list, ", ") or L("ninguno")))
        return
    end
    if cmd == "quitarhermandad" or cmd == "removeguild" then
        local ok, why = HU:RemoveNetGuild(rawArg)
        if ok then HU:Print(L("Hermandad quitada de la comunidad: <") .. HU.Trim(rawArg):upper() .. ">")
        elseif why then HU:Print("|cffff6060" .. why .. "|r") end
        return
    end
    if (cmd == "hermandades" or cmd == "guilds") and HU.ShowGuildsWindow then return HU:ShowGuildsWindow() end
    -- asistente «Crear comunidad» (y modo prueba, que no toca nada: /gu asistente prueba)
    if (cmd == "asistente" or cmd == "wizard" or cmd == "crear" or cmd == "create") and HU.OpenWizard then
        return HU:OpenWizard(arg == "prueba" or arg == "test")
    end
    if (cmd == "eco" or cmd == "echo") and HU.EchoCommand then return HU:EchoCommand(arg) end
    -- (la ventana de hermandad del juego: por si la J abre GuildUnion; ahí se edita la Información)
    if cmd == "hermandad" or cmd == "guild" then
        -- (no se abre desde el addon: el juego bloquearía luego cambiar rangos y notas; ver BlizzTab.lua)
        HU:Print(L("Pulsa J (o el botón de Hermandad) para abrir la ventana de hermandad."))
        return
    end
    -- (la J abre la ventana de hermandad del juego en el chat; /gu tecla on hace que abra GuildUnion)
    if cmd == "tecla" or cmd == "key" then
        if arg == "off" then HU.db.keyJ = nil elseif arg == "on" then HU.db.keyJ = true end
        if HU.ApplyKeyJ then HU:ApplyKeyJ() end
        HU:Print(not HU.db.keyJ and L("La J abre la ventana de hermandad del juego en su pestaña de siempre (/gu tecla on para que se abra en la pestaña GuildUnion).")
            or L("La J abre la ventana de hermandad del juego en la pestaña GuildUnion (/gu tecla off para que se abra como siempre)."))
        return
    end
    if cmd == "rol" then
        local R = { tank = "tanque", healer = "sanador" }
        arg = R[arg] or arg
    end
    if cmd == "" or cmd == "panel" or cmd == "lista" then
        HU.UI:Toggle()
    elseif cmd == "pestañas" or cmd == "pestanas" then
        HU:CreateChatTabs(false)
    elseif cmd == "test" then
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
    elseif cmd == "fijar" or cmd == "pin" then
        if arg == "" then
            local p = HU.db.pinned
            HU:Print((p and (p.text or "") ~= "") and (L("Mensaje fijado: ") .. p.text) or L("No hay mensaje fijado. Oficiales: /gu fijar texto"))
        elseif arg == "borrar" or arg == "clear" then
            HU:SetPinned("")
        else
            HU:SetPinned(rawArg)
        end
    elseif cmd == "canal" then
        HU:PrintChannelRoster()
    elseif cmd == "carril" then
        if arg == "reiniciar" or arg == "reset" then
            local officer = (HU.IsOfficerName and HU:IsOfficerName(HU:Me())) or HU:CanOfficer()
            if not officer or not HU.cfg then
                HU:Print(L("Solo los maestros y oficiales de una hermandad unida pueden reiniciar el carril."))
            else
                HU:ResetLane()
                HU:Print(L("Carril reiniciado: toda la comunidad vuelve al canal principal."))
            end
        else
            local st = HU:LaneState()
            local left = st.lane > 0 and math.max(0, math.ceil((st.t + HU.LANE_TTL - ((GetServerTime and GetServerTime()) or time())) / 60)) or nil
            HU:Print(L("Carril del canal: ") .. st.lane .. L(" (generación ") .. st.gen .. ")"
                .. (left and (L(". Vuelve al principal en ") .. left .. " min") or ""))
        end
    elseif cmd == "estado" or cmd == "status" then
        HU:PrintStatus()
    elseif cmd == "config" then
        for _, l in ipairs(EXAMPLE) do HU:Print(l) end
    elseif cmd == "recargar" or cmd == "reload" then
        HU:RequestRoster(true)
        HU:RefreshConfig(true)
        HU:Print(L("Configuración recargada."))
    elseif cmd == "etiqueta" then
        HU.db.showTag = onoff(arg, HU.db.showTag)
        HU:Print(L("Etiqueta de hermandad: ") .. (HU.db.showTag and "sí" or "no"))
    elseif cmd == "guardia" and (arg == "revisar" or arg == "review") then
        HU:GuardReview()
    elseif cmd == "guardia" then
        HU.db.autoGuard = onoff(arg, HU.db.autoGuard)
        HU:Print(L("Expulsión automática: ") .. (HU.db.autoGuard and "activada" or "desactivada"))
        HU:Changed("guard")
    elseif cmd == "margen" then
        local n = tonumber(arg)
        if n and n >= 30 and n <= 1800 then
            HU.db.grace = n
            HU:Print(L("Margen: ") .. n .. " s")
        else
            HU:Print(L("Indica un número de segundos entre 30 y 1800."))
        end
    elseif cmd == "diag" then
        -- (primero, si el juego tiene bloqueados /ginvite, /gpromote…)
        if HU.OrdersDiag then HU:OrdersDiag() end
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
            .. "  cola: " .. (HU.QueueSize and HU:QueueSize() or 0)
        local pin = HU.db.pinned
        lines[#lines + 1] = "fijado: " .. (pin and ((pin.text or "") ~= "" and ("sí, de " .. tostring(pin.author) .. " " .. HU.SafeDate("%d/%m %H:%M", pin.t)) or "vacío") or "no ha llegado")
        local rec = {}
        for k in pairs(HU.diagRecv or {}) do rec[#rec + 1] = k .. "=" .. HU.diagRecv[k] end
        table.sort(rec)
        lines[#lines + 1] = "recibido: " .. table.concat(rec, " ")
        for i = math.max(1, #h - 2), #h do
            local e = h[i]
            if e then lines[#lines + 1] = "  [" .. tostring(e.k) .. "] " .. tostring(e.a) .. ": " .. tostring(type(e.m)) .. " " .. tostring(e.m and #tostring(e.m)) .. " letras" end
        end
        if HU.UI and HU.UI.ShowCopy then HU.UI:ShowCopy("Guild Union - diagnóstico", table.concat(lines, "\n"))
        else for _, l in ipairs(lines) do HU:Print(l) end end
    elseif cmd == "memoria" then
        -- cuánta memoria usa el addon (para ver que no crece sin parar en sesiones largas)
        local upd = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
        local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
        if upd and get then
            pcall(upd)
            local ok, kb = pcall(get, ADDON_NAME)
            if ok and kb then
                HU.memPeak = math.max(HU.memPeak or 0, kb)
                HU:Print(string.format(L("Memoria del addon: %.1f MB (máximo en esta sesión: %.1f MB). Cola: %d mensajes."), kb / 1024, HU.memPeak / 1024, HU.QueueSize and HU:QueueSize() or 0))
            end
        end
    elseif cmd == "cola" then
        if arg == "vaciar" or arg == "clear" or arg == "limpiar" then
            local n = HU:ClearQueue()
            HU:Print(L("Cola de envío vaciada (") .. n .. L(" mensajes). Lo pendiente se volverá a pedir y mandar solo."))
        else
            HU:Print(HU:QueueText() .. L("   (/gu cola vaciar para vaciarla)"))
        end
        if HU.UI and HU.UI.UpdateOfficers then HU.UI:UpdateOfficers() end
    elseif (cmd == "errores" or cmd == "errors") and (arg:match("^pedir") or arg:match("^ask")) and not HU:CanOfficer() then
        HU:Print(L("Solo los oficiales pueden pedir los errores de todos."))
    elseif (cmd == "errores" or cmd == "errors") and (arg:match("^pedir") or arg:match("^ask")) then
        -- pedir a todos sus errores guardados (con la contraseña del chat unido)
        local pass = rawArg:match("^%S+%s+(.+)$")
        local ok, why = HU:AskErrors(pass and HU.Trim(pass))
        HU:Print(ok and L("Errores pedidos a todos. Irán llegando en el próximo medio minuto (/gu errores para verlos).")
            or (L("No se pueden pedir los errores: ") .. tostring(why) .. L("   (uso: /gu errores pedir contraseña)")))
    elseif (cmd == "errores" or cmd == "errors") and (arg == "borrar" or arg == "clear") then
        HU:ClearAllErrors()
    elseif cmd == "errores" or cmd == "errors" then
        HU:ShowErrors()
    elseif cmd == "ordenes" or cmd == "órdenes" then
        -- ¿tiene el juego bloqueados /ginvite, /gpromote…? (los bloquea si un addon toca la caja del chat)
        HU:OrdersDiag()
    elseif cmd == "idioma" or cmd == "lang" or cmd == "language" then
        if arg == "en" or arg == "english" or arg == "ingles" or arg == "inglés" then return HU:SetLang("en") end
        if arg == "es" or arg == "español" or arg == "espanol" or arg == "spanish" then return HU:SetLang("es") end
        local miss = {}
        for k in pairs(HU.missingEN) do miss[#miss + 1] = k end
        table.sort(miss)
        HU:Print(HU:LangName() .. "  -  /gu idioma en | es")
        if HU.lang == "en" then
            HU.UI:ShowCopy("Untranslated texts seen so far: " .. #miss, #miss > 0 and table.concat(miss, "\n") or "None.")
        end
    elseif cmd == "rol" then
        local map = { tanque = "T", sanador = "H", healer = "H", dps = "D", feral = "F" }
        if arg == "auto" or arg == "" then HU.db.myRole = nil
        elseif map[arg] then HU.db.myRole = map[arg]
        else return HU:Print(L("Uso: /gu rol tanque | sanador | dps | feral | auto")) end
        HU:UpdateMyProfile(true)
        HU:Print(L("Tu rol: ") .. (HU.db.myRole and HU.ROLES[HU.db.myRole].name or L("automático (por tus talentos)")))
    elseif cmd == "minimapa" then
        local show = onoff(arg, not HU.db.minimapHidden)
        HU:ShowMinimapButton(show)
        HU:Print(L("Botón del minimapa: ") .. (show and "visible" or "oculto"))
    elseif cmd == "nota" or cmd == "registro" then
        HU:TestLogCommand(cmd, rawArg)
    elseif cmd == "fase" or cmd == "phase" then
        -- (para probar: launch = solo oficiales entre hermandades; full = todos los conectados)
        -- (versión solo chat: no se puede cambiar)
        if HU.CHAT_ONLY then
            HU.db.phase = nil
            return HU:Print(L("Esta versión es solo de chat: las listas completas no se pueden activar."))
        end
        if arg == "full" or arg == "completa" then HU.db.phase = "full"
        elseif arg == "launch" or arg == "lanzamiento" then HU.db.phase = nil end
        HU:Print(L("Fase: ") .. (HU:LaunchPhase() and L("lanzamiento") or L("completa")) .. "   (/gu fase lanzamiento | completa)")
    elseif cmd == "buscar" or cmd == "historial" then
        HU:HistCommand(cmd, rawArg)
    elseif cmd == "debug" then
        HU.db.debug = onoff(arg, HU.db.debug)
        HU.db.showChannel = HU.db.debug
        HU:Print(L("Depuración: ") .. (HU.db.debug and L("activada (canal visible)") or "desactivada"))
    elseif cmd == "confirmar" or cmd == "confirm" then
        -- (un oficial da por buena la lista que tengo de otra hermandad: el ancla de una comunidad
        -- nueva, sin contactos comprobados todavía. Ver «Estado de la lista» en Comm.lua)
        if not HU:CanOfficer() and not HU:IsTest() then
            return HU:Print(L("Solo los oficiales pueden confirmar la lista de otra hermandad."))
        end
        local tag = HU.Trim(rawArg or "")
        if HU.cfg and not HU.cfg.byTag[tag] and HU.cfg.byTag[tag:upper()] then tag = tag:upper() end
        if tag == "" or tag == HU.myTag or not (HU.cfg and HU.cfg.byTag[tag]) then
            return HU:Print(L("Uso: /gu confirmar ETIQUETA   (la de otra hermandad de la comunidad)"))
        end
        local before = HU.ConfirmRoster and HU:ConfirmRoster(tag)
        if not before then
            return HU:Print(string.format(L("Aún no tengo la lista de <%s>: espera a que llegue y vuelve a probar."), tag))
        end
        HU:Print(string.format(L("Lista de <%s> confirmada (antes: %s). Sus rangos ya cuentan."), tag, L(HU.RosterStateName(before) or "?")))
    else
        for _, l in ipairs(HELP) do HU:Print(l) end
    end
end

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

-- /buscargrupo mensaje : escribe en "Buscar grupo" de todas las hermandades
-- (sin /bg: es el chat de campo de batalla del juego)
-- /glf es el corto (Jorge, 12/11); /glf a secas deja la caja escribiendo en Buscar grupo
SLASH_WELOVEPVPLFG1 = "/glf"
SLASH_WELOVEPVPLFG2 = "/buscargrupo"
SlashCmdList.WELOVEPVPLFG = function(input, editBox)
    input = HU.Trim(input or "")
    if input == "" then
        if editBox and HU.SetLFGMode and HU:SetLFGMode(editBox) then return end
        HU:Print(L("Uso: /glf mensaje   (ej.: /glf LFM Scholomance, falta sanador)"))
        return
    end
    HU:SendLFG(input)
end

-- /hg mensaje : escribe en el chat de hermandad unido (útil en modo prueba, donde no hay /g)
SLASH_WELOVEPVPGUILD1 = "/hg"
SlashCmdList.WELOVEPVPGUILD = function(input)
    input = HU.Trim(input or "")
    if input == "" then return HU:Print(L("Uso: /hg mensaje")) end
    local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    fn(input, "GUILD")
end
