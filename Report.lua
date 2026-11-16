-- Guild Union - informe completo (/gu todo) y comprobación de los números de canal (/gu ids).
-- Copia 147. [+ARCHITECTURE.md]
local ADDON, HU = ...

---------------------------------------------------------------------------
-- Los números de canal, tal como los ve ESTE jugador
---------------------------------------------------------------------------
-- (los nombres de canales que no son del juego salen tapados: este texto se pega en Discord)
function HU:ChannelSlotLines()
    local get = _G.GetChannelName
    if not get then return { "  el juego no da la lista de canales" } end
    local out, mine = {}, self:ChannelId("main")
    for i = 1, (_G.MAX_WOW_CHAT_CHANNELS or 20) do
        local id, name = get(i)
        if id and id > 0 and type(name) == "string" and not HU.Secret(name) then
            local kind = self:KindOf(name, name)
            local what
            if id == mine then what = "COMUNIDAD (sala " .. tostring(self:ChannelLane()) .. ")"
            elseif kind then what = "nuestro (" .. tostring(kind) .. ")"
            elseif HU.IsGameChannel and HU.IsGameChannel(name) then what = "del juego: " .. name
            else what = "otro: " .. HU.MaskChannel(name) end
            out[#out + 1] = "  /" .. id .. "  " .. what
        end
    end
    if #out == 0 then out[1] = "  ningún canal" end
    return out
end

---------------------------------------------------------------------------
-- Lo que dice el SERVIDOR de ese número (lo mismo que /chatlist N)
---------------------------------------------------------------------------
-- El chat se envía al canal por su número. Si el número que tiene el juego del jugador no es el que
-- tiene el servidor, lo enviado va a otro canal. Aquí se le pregunta al servidor quién hay en el
-- número de la comunidad y se compara con la gente que el addon conoce.
local check
HU:On("CHAT_MSG_CHANNEL_LIST", function(text, _, _, fullName, _, _, _, num, base)
    local c = check
    if not c then return end
    c.events = c.events + 1
    if type(text) ~= "string" or HU.Secret(text) then c.secret = true return end
    if type(num) == "number" then c.num = num end
    if type(base) == "string" and base ~= "" then c.base = base
    elseif type(fullName) == "string" and fullName ~= "" then c.base = fullName end
    for raw in text:gmatch("[^,]+") do
        local name = HU.Trim(raw):gsub("^[%*@]+", "")
        if name ~= "" then c.names[#c.names + 1] = name end
    end
end)

local function Known(self, key)
    return (self.roster and self.roster[key] ~= nil) or (self.chanSeen and self.chanSeen[key] ~= nil)
        or (self.guildPeers and self.guildPeers[key] ~= nil) or (self.remote and self.remote[key] ~= nil) or false
end

-- fn(res): res.err, o res.events / total / known / me / sameNum / sameName
function HU:ChannelCheck(fn)
    if check then return fn({ err = "ya hay una comprobación en marcha" }) end
    local id = self:ChannelId("main")
    if not id then return fn({ err = "no estás en el canal de la comunidad" }) end
    local ask = _G.ListChannelByName
    if not ask then return fn({ err = "este juego no deja preguntar al servidor por un canal", id = id }) end
    if self:ChannelApiBlocked() then return fn({ err = "ahora el juego no deja preguntar por el canal (campo de batalla, arena o jefe)", id = id }) end
    check = { names = {}, events = 0, id = id }
    local ok = pcall(ask, tostring(id))
    if not ok then check = nil; return fn({ err = "el juego ha rechazado la pregunta", id = id }) end
    HU.After(3, function()
        local c = check
        check = nil
        if not c then return end
        local res = { id = c.id, events = c.events, secret = c.secret, total = #c.names, known = 0, me = false, t = time(), set = {} }
        local meKey = self:MeKey()
        local meFirst = meKey and meKey:match("^[^%-]+")
        for _, name in ipairs(c.names) do
            local k = self:Key(name)
            if k then
                res.set[k] = true
                if k == meKey or k == meFirst then res.me = true end
                if k == meKey or Known(self, k) then res.known = res.known + 1 end
            end
        end
        if c.num then res.sameNum = (c.num == c.id) end
        if c.base then res.sameName = (self:KindOf(c.base, c.base) == "main") end
        HU.lastChannelCheck = res
        fn(res)
    end)
end

function HU:ChannelCheckLines(res)
    if not res then return { "  sin comprobar" } end
    if res.err then return { "  servidor: " .. res.err } end
    if res.events == 0 then
        return { "  servidor: no ha contestado en 3 s a la pregunta por el /" .. tostring(res.id) .. " (puede que Forever no conteste a esto)" }
    end
    if res.secret then return { "  servidor: ha contestado, pero el juego no deja leer la respuesta ahora" } end
    local yn = function(v) return v == nil and "no lo dice" or (v and "SÍ" or "NO") end
    local out = {
        "  servidor, sobre el /" .. tostring(res.id) .. ": mismo número: " .. yn(res.sameNum) .. " · mismo canal: " .. yn(res.sameName),
        "  nombra a " .. res.total .. " personas · conocidas por el addon: " .. res.known .. " · estoy yo: " .. yn(res.me),
    }
    local bad = (res.sameName == false) or (res.sameNum == false) or (res.total >= 5 and res.known * 4 < res.total) or (res.total > 0 and not res.me)
    out[#out + 1] = bad and "  >>> NO CUADRA: ese número, para el servidor, no parece el canal de la comunidad"
        or "  cuadra: ese número es el canal de la comunidad también para el servidor"
    return out
end

function HU:ChannelIdLines(res)
    local out = { "canal de la comunidad: " .. (self:ChannelId("main") and ("/" .. self:ChannelId("main")) or "fuera")
        .. " · intercambio de canales: " .. (HU.swapChannels and "encendido" or "apagado en esta versión") }
    for _, l in ipairs(self:ChannelSlotLines()) do out[#out + 1] = l end
    -- (copia 151) En qué copia del mundo estoy: lo dice el número del canal de Comercio. Sospecha del
    -- 16/11, sin confirmar: el canal de la comunidad no cruza bien entre copias distintas.
    local shard
    local get = _G.GetChannelName
    for i = 1, (get and (_G.MAX_WOW_CHAT_CHANNELS or 20) or 0) do
        local id, name = get(i)
        if id and id > 0 and type(name) == "string" and not HU.Secret(name) and HU.IsGameChannel and HU.IsGameChannel(name) then
            local n = name:match("(%d+)%s*$")
            if n then shard = n break end
        end
    end
    out[#out + 1] = "  copia del mundo (número del canal de Comercio): " .. (shard or "no se ve desde aquí (solo en ciudades)")
    local _, num = self:ChannelRoster("main")
    out[#out + 1] = "  gente dentro según el juego: " .. tostring(num or "?")
    for _, l in ipairs(self:ChannelCheckLines(res)) do out[#out + 1] = l end
    return out
end

-- /gu ids
function HU:PrintChannelIds()
    self:Print("Preguntando al servidor por el canal (3 s)...")
    self:ChannelCheck(function(res)
        for _, l in ipairs(self:ChannelIdLines(res)) do self:Print(l) end
    end)
end

---------------------------------------------------------------------------
-- /gu todo: todo lo que sabe el addon, en una ventana para copiar
---------------------------------------------------------------------------
local function Ago(t)
    if not t then return "-" end
    local s = math.max(0, math.floor(GetTime() - t))
    if s < 90 then return s .. " s" end
    return math.floor(s / 60) .. " min"
end

local function LaneLines(self, add)
    add("== SALA DEL CANAL ==")
    local st = self.LaneState and self:LaneState()
    add("sala " .. tostring(st and st.lane) .. " · generación " .. tostring(st and st.gen) .. " · cambios en esta sesión: " .. tostring(HU.laneMoves or 0))
    add("sala fijada por la Información de hermandad (GU:l): " .. tostring((HU.LaneLock and HU:LaneLock()) or "no"))
    local ls = HU.laneStats or {}
    add("rechazos del canal: " .. (ls.refused or 0) .. " · sin contar por acabar de entrar: " .. (ls.ignored or 0)
        .. " · órdenes de versiones viejas sin obedecer: " .. (ls.oldIgnored or 0))
    local raised = self.db and tonumber(self.db.laneRaisedT)
    add("última subida de sala: " .. (raised and HU.SafeDate("%d/%m %H:%M", raised) or "ninguna apuntada"))
    local strays = self.LaneStrays and self:LaneStrays() or {}
    add("en otra sala (oídos en los últimos 10 min): " .. #strays)
    for i = 1, math.min(#strays, 25) do
        local e = strays[i]
        local k = type(e.name) == "string" and e.name:lower()
        local p = k and ((self.guildPeers and self.guildPeers[k]) or (self.remote and self.remote[k]))
        add("  " .. tostring(e.name) .. ": sala " .. tostring(e.lane) .. " gen " .. tostring(e.gen) .. " · hace " .. Ago(e.t)
            .. " · versión " .. tostring(p and p.ver or "?") .. ((p and p.relay) and " · ENLACE" or ""))
    end
end

local function VersionLines(self, add)
    add("== VERSIONES (de quien me ha saludado) ==")
    local by, old, relays = {}, {}, {}
    local function note(p, tag)
        if type(p) ~= "table" then return end
        local v = (type(p.ver) == "string" and p.ver ~= "") and p.ver or "?"
        by[v] = (by[v] or 0) + 1
        if p.relay then relays[#relays + 1] = "<" .. tostring(tag) .. "> " .. tostring(p.name) .. " " .. v end
        if v ~= "?" and v:match("^[%d%.]+$") and HU.VersionGreater("5.4.35", v) then
            old[#old + 1] = "<" .. tostring(tag) .. "> " .. tostring(p.name) .. " " .. v .. (p.relay and " · ENLACE" or "")
        end
    end
    for _, p in pairs(self.guildPeers or {}) do note(p, self.myTag) end
    for _, p in pairs(self.remote or {}) do note(p, p.tag) end
    local vs = {}
    for v, n in pairs(by) do vs[#vs + 1] = v .. " × " .. n end
    table.sort(vs)
    add(#vs > 0 and table.concat(vs, "   ") or "nadie")
    table.sort(relays)
    add("enlaces: " .. (self:IsRelay() and ("<" .. tostring(self.myTag) .. "> yo " .. tostring(HU.version) .. "   ") or "")
        .. (#relays > 0 and table.concat(relays, "   ") or ""))
    table.sort(old)
    add("anteriores a la 5.4.35 (las que suben de sala solas): " .. #old)
    for i = 1, math.min(#old, 30) do add("  " .. old[i]) end
end

local function AuthorLines(self, add)
    add("== POR AUTOR, desde mi último /reload ==")
    add("(llegadas = líneas suyas que el juego me ha dado por el canal; enseñadas = las que he pintado, por la vía que sea)")
    local keys, set = {}, {}
    for _, t in ipairs({ HU.chanRaw or {}, HU.chanShown or {} }) do
        for k in pairs(t) do if not set[k] then set[k] = true; keys[#keys + 1] = k end end
    end
    local function last(k)
        local r, s = HU.chanRaw[k], HU.chanShown[k]
        return math.max(r and r.t or 0, s and s.t or 0)
    end
    table.sort(keys, function(a, b) return last(a) > last(b) end)
    if #keys == 0 then add("  nadie todavía") end
    local onlyFallback, total = 0, 0
    for i, k in ipairs(keys) do
        local r, s = HU.chanRaw[k], HU.chanShown[k]
        local rn, sn = r and r.n or 0, s and s.n or 0
        local mate = self.roster and self.roster[k] ~= nil
        local flag = ""
        if mate then flag = "  (mi hermandad: se ve por /g)"
        elseif sn > 0 and rn == 0 then flag = "  <- SOLO por el respaldo: su texto del canal no me llega"
        elseif rn > 0 and sn == 0 then flag = "  <- llega y no se enseña"
        elseif rn > 0 and sn > rn then flag = "  <- parte solo por el respaldo" end
        if not mate then
            total = total + 1
            if sn > 0 and rn == 0 then onlyFallback = onlyFallback + 1 end
        end
        if i <= 60 then add("  " .. k .. ": llegadas " .. rn .. " · enseñadas " .. sn .. flag) end
    end
    add("de otras hermandades: " .. total .. " autores · solo por el respaldo: " .. onlyFallback)
end

local function ExtraLines(self, add)
    add("== PRAT Y WHISPER MESSENGER ==")
    local ps, parts = HU.pratStats or {}, {}
    for k, v in pairs(ps) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(parts)
    add("Prat: " .. ((HU.PratActive and HU.PratActive()) and "en uso" or "no") .. "  " .. table.concat(parts, " "))
    add(tostring(self.WMStatus and self:WMStatus() or "Whisper Messenger: sin pestaña"))
    add("== COLA DE ENVÍO ==")
    local q, qp = HU.qStats or {}, {}
    for k, v in pairs(q) do if type(v) ~= "table" then qp[#qp + 1] = tostring(k) .. "=" .. tostring(v) end end
    table.sort(qp)
    add("en cola: " .. tostring(self.QueueSize and self:QueueSize() or 0) .. "  " .. table.concat(qp, " "))
end

function HU:FullReport()
    self:Print("Preparando el informe completo (3 s)...")
    self:ChannelCheck(function(res)
        local lines = self.DiagLines and self:DiagLines() or {}
        local function add(l) lines[#lines + 1] = l end
        local function section(name, fn, ...)
            local ok, err = pcall(fn, self, ...)
            if not ok then add("(" .. name .. ": error al prepararlo: " .. tostring(err) .. ")") end
        end
        add("")
        add("== NÚMEROS DE CANAL ==")
        section("canales", function() for _, l in ipairs(self:ChannelIdLines(res)) do add(l) end end)
        add("")
        section("sala", LaneLines, add)
        add("")
        section("versiones", VersionLines, add)
        add("")
        section("autores", AuthorLines, add)
        add("")
        section("extras", ExtraLines, add)
        if HU.ReportMore then HU.ReportMore(self, add, section, res) end
        if self.UI and self.UI.ShowCopy then self.UI:ShowCopy("Guild Union - informe completo", table.concat(lines, "\n"))
        else for _, l in ipairs(lines) do self:Print(l) end end
    end)
end

---------------------------------------------------------------------------
-- (copia 148) Más medidas para /gu todo, y la prueba entre dos personas (/gu prueba Nombre)
---------------------------------------------------------------------------
local function Clock(t) return HU.SafeDate("%H:%M:%S", t) end

-- Entradas y salidas MÍAS del canal de la comunidad en esta sesión (se mira cada 5 s)
local chanTrack = { outs = 0, outSecs = 0, log = {} }
HU:OnStart(function()
    HU.NewTicker(5, function()
        if not HU.ready then return end
        local now, inside = GetTime(), HU:IsJoined("main")
        if chanTrack.state == nil then chanTrack.state, chanTrack.since = inside, now return end
        if inside == chanTrack.state then return end
        if inside then chanTrack.outSecs = chanTrack.outSecs + (now - chanTrack.since) else chanTrack.outs = chanTrack.outs + 1 end
        local l = chanTrack.log
        l[#l + 1] = Clock(time()) .. (inside and " dentro" or " FUERA")
        if #l > 12 then table.remove(l, 1) end
        chanTrack.state, chanTrack.since = inside, now
    end)
end)

local VIA = { c = "canal", w = "respaldo" }
local function ChatLogLines(_, add)
    add("== ÚLTIMOS MENSAJES DE OTRAS HERMANDADES (hasta 60) ==")
    local l = HU.chatLog or {}
    if #l == 0 then add("  ninguno todavía") end
    for _, e in ipairs(l) do
        add("  " .. Clock(e.t) .. "  " .. tostring(e.a or "?") .. "  [" .. (VIA[e.via] or tostring(e.via or "-"))
            .. (e.by and (" de " .. tostring(e.by)) or "") .. "]  " .. tostring(e.what)
            .. (e.n and ("  (" .. e.n .. " letras: «" .. tostring(e.head) .. "»)") or ""))
    end
end

local function SendLines(_, add)
    add("== MIS ÚLTIMOS ENVÍOS (hasta 15) ==")
    local l = HU.sendLog or {}
    if #l == 0 then add("  ninguno todavía") end
    for _, e in ipairs(l) do
        local how
        if e.via ~= "canal" then how = "directo por el respaldo (sin pasar por el canal)"
        elseif e.echo then how = string.format("mi línea volvió en %.2f s", e.echo)
        elseif e.noEcho then how = "SIN ECO en 1 s -> también por el respaldo"
        else how = "esperando el eco" end
        add("  " .. Clock(e.t) .. "  " .. tostring(e.via) .. "  " .. tostring(e.n) .. " letras  " .. how)
    end
    local es = HU.echoStats or { n = 0, sum = 0, max = 0 }
    add("eco de mis líneas: " .. es.n .. " veces · media " .. (es.n > 0 and string.format("%.2f", es.sum / es.n) or "-")
        .. " s · máximo " .. string.format("%.2f", es.max) .. " s")
end

local function LaneLogLines(self, add)
    add("== HISTORIA DE CAMBIOS DE SALA (guardada, hasta 30) ==")
    local l = self.db and self.db.laneLog or {}
    if #l == 0 then add("  ninguno desde que tengo esta versión") end
    for _, e in ipairs(l) do
        add("  " .. HU.SafeDate("%d/%m %H:%M:%S", e.t) .. "  sala " .. tostring(e.from) .. " -> " .. tostring(e.to)
            .. "  (gen " .. tostring(e.g0) .. " -> " .. tostring(e.g1) .. ")  " .. tostring(e.why))
    end
end

local function MissingLines(self, add, res)
    add("== QUIÉN FALTA EN EL CANAL ==")
    if not (res and res.set and (res.total or 0) > 0) then return add("  sin lista del servidor: no se puede comparar") end
    -- (copia 149: solo CONECTADOS. En la 148 salía quien había saludado en los últimos 15 min aunque
    -- ya se hubiera desconectado: Mago-Caquita, 16/11. De mi hermandad se sabe por la lista del juego;
    -- de las otras no, así que solo cuentan los que han saludado en los últimos 5 min, y se dice)
    add("(con el addon, CONECTADOS, y a los que el servidor NO nombra dentro del canal)")
    add("(de mi hermandad: conectados según la lista del juego · de las otras: han saludado en los últimos 5 min, puede que alguno ya no esté)")
    local now, out = GetTime(), {}
    local function look(p, tag, own)
        if type(p) ~= "table" or type(p.name) ~= "string" then return end
        local k = self:Key(p.name)
        if not k or res.set[k] then return end
        local ago = now - (p.last or 0)
        if own then
            local e = self.roster and self.roster[k]
            if not (e and e.online) then return end
        elseif ago > 300 then
            return
        end
        out[#out + 1] = "  <" .. tostring(tag) .. "> " .. p.name .. "  versión " .. tostring(p.ver or "?") .. (p.relay and "  ENLACE" or "")
            .. "  · último saludo hace " .. Ago(p.last)
    end
    for _, p in pairs(self.guildPeers or {}) do look(p, self.myTag, true) end
    for _, p in pairs(self.remote or {}) do look(p, p.tag, false) end
    table.sort(out)
    add("faltan: " .. #out .. " · en el canal sin que el addon los conozca: " .. math.max(0, (res.total or 0) - (res.known or 0)))
    for i = 1, math.min(#out, 40) do add(out[i]) end
end

local function GuildLines(self, add, res)
    add("== POR HERMANDAD ==")
    if not self.cfg then return add("  sin configuración") end
    for _, g in ipairs(self.cfg.guilds or {}) do
        local tag = g.tag
        local inChan = 0
        if res and res.set then
            for k in pairs(res.set) do if self:MemberOf(k, tag) then inChan = inChan + 1 end end
        end
        if tag == self.myTag then
            -- (copia 149: «con addon» contaba a todo el que había saludado en la sesión, también a los
            -- ya desconectados; ahora se separan los conectados, que son los comparables con el canal)
            local np, on, onIn = 0, 0, 0
            for k in pairs(self.guildPeers or {}) do
                np = np + 1
                local e = self.roster and self.roster[k]
                if e and e.online then
                    on = on + 1
                    if res and res.set and res.set[k] then onIn = onIn + 1 end
                end
            end
            add("<" .. tostring(tag) .. "> (la mía): en mi lista " .. tostring(self.rosterList and #self.rosterList or "?")
                .. " · conectados " .. tostring(self.rosterOnline or "?") .. " · con addon en esta sesión " .. np
                .. " · con addon y conectados AHORA " .. on .. " · de esos, dentro del canal " .. onIn
                .. " · de mi hermandad dentro del canal en total " .. inChan)
        else
            local r = self.remoteRoster and self.remoteRoster[tag]
            local contacts = {}
            for _, p in ipairs((self.BestPeers and self:BestPeers(tag, 2)) or {}) do
                contacts[#contacts + 1] = tostring(p.name) .. " " .. tostring(p.ver or "?") .. (p.relay and " (enlace)" or "")
            end
            add("<" .. tostring(tag) .. ">: conectados que conozco " .. tostring(r and r.members and #r.members or 0)
                .. " · dentro del canal " .. inChan .. " · mis contactos para el respaldo: "
                .. (#contacts > 0 and table.concat(contacts, ", ") or "NINGUNO"))
        end
    end
end

-- (una huella corta: sirve para comparar dos informes sin enseñar el dato)
local function Finger(s, mod)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 16777213 end
    return h % mod
end
local function ConfigLines(self, add)
    add("== CONFIGURACIÓN (huellas: iguales en dos informes = misma configuración) ==")
    local cfg = self.cfg
    if not cfg then return add("  sin configuración") end
    local gs = {}
    for _, g in ipairs(cfg.guilds or {}) do gs[#gs + 1] = tostring(g.tag) .. "=" .. tostring(g.name):lower() end
    table.sort(gs)
    add("hermandades: " .. #gs .. " · huella " .. string.format("%04x", Finger(table.concat(gs, "|"), 65536)))
    add("canal y contraseña: huella " .. string.format("%03x", Finger(tostring(cfg.channel):lower() .. "\0" .. tostring(cfg.password or ""), 4096)))
    add("en pausa por versión mínima: " .. tostring(HU.paused and true or false))
end

local function SessionLines(self, add)
    add("== SESIÓN ==")
    local now = GetTime()
    local inInst, kind = false, nil
    if IsInInstance then inInst, kind = IsInInstance() end
    add("desde que entré: " .. math.floor((now - (HU.loginT or now)) / 60) .. " min · última pantalla de carga hace "
        .. math.floor((now - (HU.laneLoadT or now)) / 60) .. " min · en instancia: " .. tostring(inInst and kind or "no")
        .. " · bloqueo del chat: " .. tostring(self:IsChatLockedDown()))
    add("fuera del canal en esta sesión: " .. chanTrack.outs .. " veces · " .. math.floor(chanTrack.outSecs) .. " s en total · ahora: "
        .. (self:IsJoined("main") and "dentro" or "FUERA"))
    if #chanTrack.log > 0 then add("  " .. table.concat(chanTrack.log, " · ")) end
    local upd = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
    local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
    if upd and get then
        pcall(upd)
        local ok, kb = pcall(get, ADDON)
        if ok and type(kb) == "number" then add(string.format("memoria del addon: %.1f MB", kb / 1024)) end
    end
    local errs = self.errors or {}
    add("errores del addon en esta sesión: " .. #errs)
    for i = math.max(1, #errs - 2), #errs do
        local e = errs[i]
        if e then add("  " .. tostring(e.n or 1) .. " × [" .. tostring(e.where) .. "] " .. HU.Utf8Cut(tostring(e.msg), 160)) end
    end
end

local function ProbeLines(_, add)
    add("== PRUEBAS ENTRE DOS (/gu prueba Nombre) ==")
    local l = HU.textProbes or {}
    if #l == 0 then add("  ninguna en esta sesión") end
    for _, s in ipairs(l) do add("  " .. s) end
end

function HU.ReportMore(self, add, section, res)
    add("")
    section("mensajes", ChatLogLines, add)
    add("")
    section("envíos", SendLines, add)
    add("")
    section("historia de salas", LaneLogLines, add)
    add("")
    section("quién falta", MissingLines, add, res)
    add("")
    section("por hermandad", GuildLines, add, res)
    add("")
    section("configuración", ConfigLines, add)
    add("")
    section("sesión", SessionLines, add)
    add("")
    section("pruebas", ProbeLines, add)
end

---------------------------------------------------------------------------
-- /gu prueba Nombre Apellido: ¿le llega a esa persona MI texto por el canal?
---------------------------------------------------------------------------
-- Manda 5 líneas de texto numeradas al canal (con un formato que no es chat: nadie las ve, y las
-- versiones anteriores las ignoran) y un aviso oculto. El addon del otro cuenta las que le llegan y
-- contesta por el canal, en oculto. Mide justo lo que falla: el texto del canal de una persona a otra.
local PROBE_N = 3 -- (copia 151: el juego solo deja pasar 3 líneas seguidas de texto al canal; visto el 16/11)
HU.textProbes = {}
local out          -- mi prueba en marcha: { run, target, echo }
local inc = {}     -- [remitente .. tanda] = { got = {}, hidden }
local lastFrom = {}

local function ProbeNote(s)
    local l = HU.textProbes
    l[#l + 1] = Clock(time()) .. " " .. s
    if #l > 10 then table.remove(l, 1) end
    HU:Print(s)
end

function HU:TextProbe(name)
    name = HU.Trim(name or "")
    local tk = name ~= "" and self:Key(name)
    if not tk or tk:find("%s") then return self:Print("Uso: /gu prueba Nombre Apellido") end
    if tk == self:MeKey() then return self:Print("La prueba es con otro jugador.") end
    local id = self:ChannelId("main")
    if not id then return self:Print("No estás en el canal de la comunidad: no se puede hacer la prueba.") end
    if out then return self:Print("Ya hay una prueba tuya en marcha.") end
    local sendText = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local sendHidden = C_ChatInfo and (C_ChatInfo.SendAddonMessageLogged or C_ChatInfo.SendAddonMessage)
    if not sendText or not sendHidden or HU.paused or self:IsChatLockedDown() then return self:Print("Ahora mismo no se puede enviar.") end
    local run = tostring(math.random(1000, 9999))
    out = { run = run, target = tk, echo = 0, sent = 0 }
    pcall(sendHidden, HU.PREFIX_C, table.concat({ "TQ", run, tk, PROBE_N }, "~"), "CHANNEL", id)
    for i = 1, PROBE_N do
        if pcall(sendText, "#GUT " .. run .. " " .. i .. " " .. tk, "CHANNEL", nil, id) then out.sent = out.sent + 1 end
    end
    self:Print("Prueba con " .. self:Nice(tk) .. ": enviadas " .. out.sent .. " líneas por el canal. Resultado en unos 10 s...")
    HU.After(14, function()
        local o = out
        if not o or o.run ~= run then return end
        out = nil
        ProbeNote("Prueba -> " .. HU:Nice(tk) .. ": SIN RESPUESTA en 14 s (mi eco: " .. o.echo .. "/" .. PROBE_N
            .. "). O no tiene esta versión, o no le llega nada mío por el canal, ni lo oculto.")
    end)
end

local function Expect(sk, run)
    local last = lastFrom[sk]
    if last and GetTime() - last < 20 then return nil end
    lastFrom[sk] = GetTime()
    local p = { got = {} }
    inc[sk .. run] = p
    HU.After(7, function()
        inc[sk .. run] = nil
        local n, list = 0, {}
        for i = 1, PROBE_N do if p.got[i] then n = n + 1; list[#list + 1] = i end end
        ProbeNote("Prueba <- " .. HU:Nice(sk) .. ": me han llegado " .. n .. "/" .. PROBE_N .. " líneas de texto por el canal"
            .. (p.hidden and "" or " · su aviso oculto NO me llegó"))
        local id = HU:ChannelId("main")
        local sendHidden = C_ChatInfo and (C_ChatInfo.SendAddonMessageLogged or C_ChatInfo.SendAddonMessage)
        if id and sendHidden and not HU.paused then
            pcall(sendHidden, HU.PREFIX_C, table.concat({ "TR", run, sk, n, table.concat(list, "."), p.hidden and "1" or "0" }, "~"), "CHANNEL", id)
        end
    end)
    return p
end

-- una línea «#GUT tanda n destinatario» que ha llegado como texto por el canal de la comunidad
function HU.OnTextProbe(text, author)
    local run, i, tk = text:match("^#GUT (%d+) (%d+) (%S+)%s*$")
    i = tonumber(i)
    local full = HU:FullName(author)
    if not (run and i and full) or i < 1 or i > PROBE_N then return end
    local sk = full:lower()
    if sk == HU:MeKey() then
        if out and out.run == run then out.echo = out.echo + 1 end
        return
    end
    if tk ~= HU:MeKey() then return end
    local p = inc[sk .. run] or Expect(sk, run)
    if p then p.got[i] = true end
end

-- el aviso (TQ) y la respuesta (TR), ocultos, por el canal
function HU.OnTextProbeMsg(text, sender, localID, chanName)
    if HU:OurChannelKind(localID, chanName) == nil then return end
    local full = HU:FullName(sender)
    if not full then return end
    local sk = full:lower()
    if sk == HU:MeKey() then return end
    local f = HU.Split(text, "~")
    if f[1] == "TQ" then
        if f[3] ~= HU:MeKey() or not (f[2] and f[2]:match("^%d+$")) then return end
        local p = inc[sk .. f[2]] or Expect(sk, f[2])
        if p then p.hidden = true end
    elseif f[1] == "TR" then
        local o = out
        if not o or f[2] ~= o.run or f[3] ~= HU:MeKey() or sk ~= o.target then return end
        out = nil
        local n = tonumber(f[4])
        ProbeNote("Prueba -> " .. HU:Nice(sk) .. ": le han llegado " .. tostring(n or "?") .. "/" .. PROBE_N
            .. " líneas de texto" .. ((f[5] and f[5] ~= "") and (" (" .. f[5]:gsub("%.", ", ") .. ")") or "")
            .. " · mi eco: " .. o.echo .. "/" .. PROBE_N .. (f[6] == "0" and " · mi aviso oculto no le llegó" or ""))
    end
end
