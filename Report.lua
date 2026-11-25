-- Guild Union - informe completo (/gu todo) y comprobación de los números de canal (/gu ids).
-- Copia 147. [+ARCHITECTURE.md]
-- También: quién de mi hermandad no tiene el addon (/gu sinaddon) y la carga de los enlaces (/gu carga).
local ADDON, HU = ...
local L = HU.L

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
            elseif HU.IsGameChannel(name) then what = "del juego: " .. name
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
    -- (copia 162: sin repetidos. La respuesta tardía a una pregunta anterior se sumaba a esta y salía
    -- «nombra a 320 personas» con 160 dentro)
    for raw in text:gmatch("[^,]+") do
        local name = HU.Trim(raw):gsub("^[%*@]+", "")
        local k = name:lower()
        if name ~= "" and not c.seen[k] then
            c.seen[k] = true
            c.names[#c.names + 1] = name
        end
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
    check = { names = {}, seen = {}, events = 0, id = id }
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
        if id and id > 0 and type(name) == "string" and not HU.Secret(name) and HU.IsGameChannel(name) then
            local n = name:match("(%d+)%s*$")
            if n then shard = n break end
        end
    end
    out[#out + 1] = "  copia del mundo (número del canal de Comercio): " .. (shard or "no se ve desde aquí (solo en ciudades)")
    local _, num = self:ChannelRoster("main")
    out[#out + 1] = "  gente dentro según el juego: " .. tostring(num or "?")
    -- (copia 162: si el canal tiene número pero no sale en la lista, es un canal fantasma)
    local mainId = self:ChannelId("main")
    if mainId and HU.ChannelListed then
        local listed = HU.ChannelListed(mainId)
        local c = self.chan.main or {}
        out[#out + 1] = "  en la lista de canales: " .. (listed == true and "SÍ" or listed == false and "NO (canal fantasma)" or "no se sabe (grupo plegado)")
            .. " · reentradas: " .. tostring(c.rejoinN or 0)
    end
    -- (copia 167: la última caída del servidor de chat del juego)
    if HU.chatServerDownT then
        local down = math.floor((GetTime() - HU.chatServerDownT) / 60)
        local up = HU.chatServerUpT and HU.chatServerUpT >= HU.chatServerDownT and math.floor((GetTime() - HU.chatServerUpT) / 60)
        out[#out + 1] = "  servidor de chat del juego: caído hace " .. down .. " min" .. (up and (", vuelto hace " .. up .. " min") or ", sin volver")
    end
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
    local st = self:LaneState()
    add("sala " .. tostring(st and st.lane) .. " · generación " .. tostring(st and st.gen) .. " · cambios en esta sesión: " .. tostring(HU.laneMoves or 0))
    add("sala fijada por la Información de hermandad (GU:l): " .. tostring((HU:LaneLock()) or "no"))
    local ls = HU.laneStats or {}
    add("rechazos del canal: " .. (ls.refused or 0) .. " · sin contar por acabar de entrar: " .. (ls.ignored or 0)
        .. " · órdenes de versiones viejas sin obedecer: " .. (ls.oldIgnored or 0))
    local raised = self.db and tonumber(self.db.laneRaisedT)
    add("última subida de sala: " .. (raised and HU.SafeDate("%d/%m %H:%M", raised) or "ninguna apuntada"))
    local strays = self:LaneStrays() or {}
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
    add("Prat: " .. ((HU.PratActive()) and "en uso" or "no") .. "  " .. table.concat(parts, " "))
    add(tostring(self:WMStatus() or "Whisper Messenger: sin pestaña"))
    add("== COLA DE ENVÍO ==")
    local q, qp = HU.qStats or {}, {}
    for k, v in pairs(q) do if type(v) ~= "table" then qp[#qp + 1] = tostring(k) .. "=" .. tostring(v) end end
    table.sort(qp)
    add("en cola: " .. tostring(self:QueueSize() or 0) .. "  " .. table.concat(qp, " "))
end

function HU:FullReport()
    self:Print("Preparando el informe completo (3 s)...")
    self:ChannelCheck(function(res)
        local lines = self:DiagLines() or {}
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
        HU.ReportMore(self, add, section, res)
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
    HU:Every(5, "informe-canal", function()
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
            for _, p in ipairs((self:BestPeers(tag, 2)) or {}) do
                contacts[#contacts + 1] = tostring(p.name) .. " " .. tostring(p.ver or "?") .. (p.relay and " (enlace)" or "")
            end
            add("<" .. tostring(tag) .. ">: conectados que conozco " .. tostring(r and r.members and #r.members or 0)
                .. " · dentro del canal " .. inChan .. " · mis contactos para el respaldo: "
                .. (#contacts > 0 and table.concat(contacts, ", ") or "NINGUNO"))
        end
    end
    -- (quién no tiene el addon, por hermandad: el detalle, en /gu sinaddon)
    add(self:WithoutAddonLine())
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

-- (copia 175) Los avisos de fallos que ya no salen en el chat (HU:Notice, Core.lua)
local function NoticeLines(self, add)
    add("== AVISOS DE ESTA SESIÓN (no se enseñan en el chat) ==")
    local n = self.notices or {}
    if #n == 0 then return add("  ninguno") end
    for _, e in ipairs(n) do add("  " .. date("%H:%M:%S", e.t) .. "  " .. e.text) end
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
    -- (y por qué: los avisos del servidor y lo que hago yo con el canal, Channel.lua)
    local ev = self.chanEvents
    if #ev > 0 then
        local parts = {}
        for i = math.max(1, #ev - 11), #ev do parts[#parts + 1] = Clock(ev[i].t) .. " " .. ev[i].what end
        add("  canal: " .. table.concat(parts, " · "))
    end
    local upd = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
    local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
    if upd and get then
        pcall(upd)
        local ok, kb = pcall(get, ADDON)
        if ok and type(kb) == "number" then add(string.format("memoria del addon: %.1f MB", kb / 1024)) end
    end
    -- (la CPU del addon según el juego y los FPS, que se miden siempre: Perf.lua)
    add(self:PerfSessionLine())
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
    section("avisos", NoticeLines, add)
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

---------------------------------------------------------------------------
-- Quién de mi hermandad no tiene el addon (/gu sinaddon): se le pregunta a cada uno, tres veces [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local ASKS = 3            -- veces que se le pregunta a cada uno (Jorge, 25/11: «preguntando 1 a 1 (que tarde 5 mins)»)
local STEP = 1            -- entre una pregunta que ya ha salido y la siguiente: la cola manda una por segundo
local SENT_WAIT = 90      -- lo que se espera a que salga una pregunta (con la cola llena); si no sale, no cuenta
local ROUND_GAP = 60      -- entre una vuelta y la siguiente: a cada uno, sus preguntas separadas al menos esto
local LAST_WAIT = 30      -- tras la última, lo que se espera a las respuestas que tardan (en combate, Combat.lua)
local MAP_IDS = 3000      -- los mapas del juego que se miran, por si son mazmorras o bandas
-- (las instancias de Forever por su número, y el nombre, el del juego: en un campo de batalla el juego no deja
-- contestar, y en mazmorras y bandas, en combate, el addon aplaza las preguntas. Y las de Forever por su nombre: los
-- campos de batalla y las mazmorras nuevas que no son de vanilla, Jorge, 25/11)
local INSTANCE_IDS = { 30, 489, 529, 33, 34, 36, 43, 47, 48, 70, 90, 109, 129, 189, 209, 229, 230, 289, 329, 349, 389,
    429, 249, 309, 409, 469, 509, 531, 533 }
local INSTANCE_NAMES = { "Valle de Alterac", "Garganta Grito de Guerra", "Cuenca de Arathi", "Alterac Valley",
    "Warsong Gulch", "Arathi Basin", "Alcaz Prison", "The Drowned City" }
local instanceNames
local addonRun, addonLast   -- la comprobación en marcha y la última acabada

local function InstanceZone(zone)
    if type(zone) ~= "string" or zone == "" then return false end
    if not instanceNames then
        instanceNames = {}
        for _, n in ipairs(INSTANCE_NAMES) do instanceNames[n:lower()] = true end
        -- (un nombre que sale con varios números no es el de una instancia: es lo que da el juego sin saberlo)
        local seen = {}
        for _, id in ipairs(INSTANCE_IDS) do
            local ok, n = pcall(GetRealZoneText, id)
            if ok and type(n) == "string" and n ~= "" then seen[n:lower()] = (seen[n:lower()] or 0) + 1 end
        end
        for n, c in pairs(seen) do if c == 1 then instanceNames[n] = true end end
        -- (y las mazmorras y bandas del mapa del juego, también las nuevas de Forever)
        local dungeon = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
        local get = C_Map and C_Map.GetMapInfo
        for id = 1, get and MAP_IDS or 0 do
            local ok, info = pcall(get, id)
            if ok and type(info) == "table" and info.mapType == dungeon and type(info.name) == "string" and info.name ~= ""
                and not HU.Secret(info.name) then instanceNames[info.name:lower()] = true end
        end
    end
    return instanceNames[zone:lower()] == true
end

-- (tiene el addon: me ha saludado, o contestado, por la hermandad; HI, HR y PA, Net/Relay.lua)
local function HasAddon(self, k) return k == self:MeKey() or self.guildPeers[k] ~= nil end

-- (le pregunto a uno «¿eres de la hermandad?» (PG, por GUILD): su addon contesta solo con PA, en cualquier versión
-- desde la 5.4.12. Solo cuenta cuando sale de verdad de la cola: en la copia 334 contaba al entrar y, con 200
-- conectados recién entrado al juego, muchas no llegaron a salir. Y apunto si está en una instancia o con el móvil.
-- Devuelve la espera de esta pregunta, o nil si no la hay)
local function Ask(self, r, row)
    if HasAddon(self, row.key) then return nil end
    local e = self.roster[row.key]
    if not (e and e.online) then row.gone = true return nil end
    if e.mobile then row.mobile = true end
    if InstanceZone(e.zone) then row.inst = e.zone end
    local wait = { t = GetTime() }
    local queued = self:Send("PG~" .. row.name, "GUILD", nil, nil, nil, nil, function()
        row.asked = row.asked + 1
        wait.sent = GetTime()
    end)
    return queued and wait or nil
end

local function Stop(self, r)
    if addonRun ~= r then return end
    addonRun = nil
    self:Print(L("He parado de mirar quién tiene el addon: ahora el juego no deja mandar nada (campo de batalla). Vuelve a probar al salir."))
end

local function Finish(self, r)
    if addonRun ~= r then return end
    if self:IsChatLockedDown() then return Stop(self, r) end
    addonRun = nil
    local res = { t = time(), tag = r.tag, total = #r.rows, with = 0, without = {}, unknown = {} }
    for _, row in ipairs(r.rows) do
        if HasAddon(self, row.key) then
            res.with = res.with + 1
        else
            local e, why = self.roster[row.key], nil
            if row.gone or not (e and e.online) then why = L("se ha desconectado")
            elseif row.mobile or e.mobile then why = L("con la aplicación del móvil")
            elseif row.inst or InstanceZone(e.zone) then why = string.format(L("en %s: ahí no le deja contestar"), row.inst or e.zone)
            elseif row.asked < ASKS then why = L("no le he podido preguntar las tres veces") end
            local item = { name = self:Nice(row.name), full = row.name, zone = e and e.zone, why = why }
            if why then res.unknown[#res.unknown + 1] = item else res.without[#res.without + 1] = item end
        end
    end
    local function ByName(a, b) return a.name:lower() < b.name:lower() end
    table.sort(res.without, ByName)
    table.sort(res.unknown, ByName)
    addonLast = res
    self:ShowAddonCheck()
end

-- (una vuelta: a los que aún no han contestado, uno detrás de otro, y cada pregunta cuando ya ha salido la
-- anterior; tras la última, la espera y el resultado)
local function Round(self, r)
    if addonRun ~= r then return end
    r.round = r.round + 1
    local todo = {}
    for _, row in ipairs(r.rows) do if not row.gone and not HasAddon(self, row.key) then todo[#todo + 1] = row end end
    if #todo == 0 then return Finish(self, r) end
    self:RequestRoster()
    local i = 0
    local function Next()
        if addonRun ~= r then return end
        if self:IsChatLockedDown() then return Stop(self, r) end
        -- (la anterior: hasta que sale, como mucho SENT_WAIT, y luego STEP más)
        local w, now = r.waiting, GetTime()
        if w and not w.sent and now - w.t < SENT_WAIT then return HU.After(0.5, Next) end
        if w and w.sent and now - w.sent < STEP then return HU.After(STEP - (now - w.sent), Next) end
        r.waiting = nil
        i = i + 1
        if not todo[i] then
            if r.round < ASKS then return HU.After(ROUND_GAP, function() Round(self, r) end) end
            return HU.After(LAST_WAIT, function() Finish(self, r) end)
        end
        r.waiting = Ask(self, r, todo[i])
        HU.After(r.waiting and STEP or 0, Next)
    end
    Next()
end

-- (cuánto tarda, más o menos, con n conectados que preguntar: cada pregunta, al ritmo de la cola, y uno de cada tres
-- que no contesta a la primera, otra vez en las dos vueltas siguientes)
local function Eta(n) return n * (STEP + 0.5) * (1 + 2 / 3) + 2 * ROUND_GAP + LAST_WAIT end

-- La línea corta, para el chat y /gu informe
function HU:WithoutAddonLine()
    if addonRun then return L("Sin addon: lo estoy mirando (/gu sinaddon).") end
    local r = addonLast
    if not r then return L("Sin addon: sin mirar (/gu sinaddon, unos 5 minutos).") end
    return string.format(L("Sin addon en <%s> (mirado a las %s): %d de %d conectados · no se sabe %d"), r.tag,
        date("%H:%M", r.t), #r.without, r.total, #r.unknown)
end

local function AddonCheckText(self, r)
    local lines = { HU.ADDON_TITLE .. " " .. tostring(HU.version) .. " - " .. L("quién no tiene el addon") .. " - " .. date("%d/%m/%Y %H:%M", r.t) }
    local function add(s) lines[#lines + 1] = s end
    add(string.format(L("<%s>: %d conectados · con addon %d · sin addon %d · no se sabe %d"), r.tag, r.total, r.with, #r.without, #r.unknown))
    add("")
    add(L("Sin addon: no han contestado a ninguna de las tres preguntas (el addon contesta solo, en cualquier versión desde la 5.4.12):"))
    for _, x in ipairs(r.without) do add("  " .. x.name .. ((x.zone and x.zone ~= "") and ("  ·  " .. x.zone) or "")) end
    if #r.without == 0 then add("  -") end
    if #r.unknown > 0 then
        add("")
        add(L("No se sabe (vuelve a mirarlo más tarde):"))
        for _, x in ipairs(r.unknown) do add("  " .. x.name .. ": " .. x.why) end
    end
    return table.concat(lines, "\n")
end

-- (los «sin addon» de la última que aún están en la hermandad y mi rango deja echar; nunca los de «no se sabe»)
local function Kickable(self, r)
    local names = {}
    for _, x in ipairs(r and r.without or {}) do
        if self.roster[self:Key(x.full) or ""] and self:CanKickMember(x.full) then names[#names + 1] = x.full end
    end
    return names
end

-- Echar a los «sin addon» de la última (Jorge, 25/11: «quiero un botón de mass echar»): por tandas, cada una con su
-- pregunta y su «Sí» (HU:KickNames, Social.lua)
function HU:KickWithoutAddon()
    local names = Kickable(self, addonLast)
    if #names == 0 then return self:Print(L("No queda nadie de la lista que puedas echar.")) end
    self:KickNames(names)
end

-- El resultado de la última: la línea corta en el chat y el detalle en la ventana de copiar, con el botón de echar
function HU:ShowAddonCheck()
    local r = addonLast
    if not r then return end
    self:Print(self:WithoutAddonLine())
    local text = AddonCheckText(self, r)
    local n = #Kickable(self, r)
    local opts = n > 0 and { button = string.format(L("Echar (%d)"), n), onClick = function() HU:KickWithoutAddon() end } or nil
    if self.UI and self.UI.ShowCopy then self.UI:ShowCopy(L("Quién no tiene el addon (Ctrl+C para copiarlo)"), text, opts)
    else for l in text:gmatch("[^\n]+") do self:Print(l) end end
end

-- /gu sinaddon: solo mi hermandad, y seguro (Jorge, 25/11: «que sea seguro los que no tienen addon, porque los echaré
-- de la guild»). Con GU:v puesto no se mira: el addon de quien tenga una versión anterior está en pausa y no contesta
function HU:ShowWithoutAddon()
    if addonRun then
        local left = math.floor((addonRun.eta - GetTime()) / 60 + 0.5)
        if left < 2 then return self:Print(L("Ya lo estoy mirando: falta poco.")) end
        return self:Print(string.format(L("Ya lo estoy mirando: faltan unos %d minutos."), left))
    end
    if not IsInGuild() then return self:Print(L("No estás en una hermandad.")) end
    if self.guildMin then
        return self:Print(string.format(L("Así no es seguro: la Información de la hermandad tiene GU:v:%s y el addon de quien tenga una versión anterior está en pausa y no contesta. Quítalo, espera un minuto y vuelve a probar."), tostring(self.guildMin)))
    end
    if self:IsChatLockedDown() then return self:Print(L("Ahora no se puede: el juego no deja mandar nada (campo de batalla). Prueba al salir.")) end
    local me = self:MeKey()
    local r = { t0 = GetTime(), round = 0, rows = {}, tag = self.myTag or (GetGuildInfo("player")) or "?" }
    for _, e in ipairs(self.rosterList) do
        local k = self:Key(e.name)
        if e.online and k and k ~= me then r.rows[#r.rows + 1] = { name = e.name, key = k, asked = 0 } end
    end
    if #r.rows == 0 then return self:Print(L("No hay nadie más de tu hermandad conectado.")) end
    addonRun = r
    -- (los que ya sé que lo tienen no se preguntan: con ellos, el cálculo)
    local ask = 0
    for _, row in ipairs(r.rows) do if not HasAddon(self, row.key) then ask = ask + 1 end end
    r.eta = r.t0 + Eta(ask)
    self:Print(string.format(L("Miro quién tiene el addon en tu hermandad: les pregunto a los %d conectados, uno a uno y tres veces. Tarda unos %d minutos; te aviso al acabar."),
        #r.rows, math.max(1, math.floor(Eta(ask) / 60 + 0.5))))
    Round(self, r)
end

---------------------------------------------------------------------------
-- La carga de los enlaces (/gu carga): cada enlace dice sus números, sin nombres [+ARCHITECTURE.md]
--   UQ~etiq~id                                                         un oficial pregunta, por susurro
--   UR~etiq~id~ver~papel~min~cpu~cpuPico~fps~fpsMín~cola~salen~entran  la respuesta (CPU en décimas de %; «-»: no lo sé)
---------------------------------------------------------------------------
local LOAD_WAIT = 10    -- quien pregunta junta las respuestas este rato
local LOAD_GAP = 30     -- cada uno contesta a cada uno una vez en este rato, y quien pregunta no repite antes
local LOAD_MAX = 20     -- y, a todos juntos, como mucho tantas respuestas en ese rato
-- (los topes de lo que llega: minutos, CPU y su pico en décimas de %, FPS, FPS más bajos, cola, salen y entran)
local LOAD_LIMITS = { 99999, 1000, 1000, 999, 999, 99999, 99999, 99999 }
local loadRun           -- mi pregunta en marcha: { id, rows = { { tag, name, data, bad } }, byKey = { [clave] = fila } }
local loadAskT = -999

-- (minutos conectado desde que entró al juego: un /reload no los pone a cero, como el Uptime de Net/Relay.lua)
local function Minutes(self)
    local st = self.cdb and tonumber(self.cdb.sessionStart)
    local secs = st and (time() - st) or (GetTime() - (self.loginT or GetTime()))
    return math.max(0, math.floor(secs / 60))
end
-- (entero, sin pasar del tope que acepta quien lo recibe; «-» si no lo sé)
local function Field(x, i, scale)
    if not x then return "-" end
    return tostring(math.min(LOAD_LIMITS[i], math.floor(x * (scale or 1) + 0.5)))
end

-- ¿Soy el enlace («e») o un ayudante («a») de mi hermandad? nil si ninguno (el equipo de Net/Packs.lua)
local function MyRole(self)
    if self:IsRelay() then return "e" end
    local me = self:MeKey()
    for _, n in ipairs(HU.PackTeams.Mine()) do if self:Key(n) == me then return "a" end end
    return nil
end

-- Mis números como van en UR, sin la orden: etiqueta, id, versión, papel y los ocho de LOAD_LIMITS
local function LoadFields(self, id, role)
    local cpu, cpuMax, fps, fpsLow, sent, got = self:PerfNow()
    return { self.myTag, id, tostring(HU.version), role, Field(Minutes(self), 1), Field(cpu, 2, 10), Field(cpuMax, 3, 10),
        Field(fps, 4), Field(fpsLow, 5), Field(self:QueueSize(), 6), Field(sent, 7), Field(got, 8) }
end

-- (un número que llega: entero de 0 a max; «-» es que no lo sabe (false); cualquier otra cosa no vale (nil))
local function Int(s, max)
    if s == "-" then return false end
    if type(s) ~= "string" or #s > 6 or not s:match("^%d+$") then return nil end
    local n = tonumber(s)
    if not n or n > max then return nil end
    return n
end
-- Los datos de un UR (f[1] etiqueta, f[2] id, f[3] versión, f[4] papel y los números), o nil si algo no vale
local function ParseLoad(f)
    local ver, role = f[3], f[4]
    if type(ver) ~= "string" or #ver > 16 or not ver:match("^[%w%.%-]+$") then return nil end
    if role ~= "e" and role ~= "a" then return nil end
    local d = { ver = ver, role = role }
    for i, max in ipairs(LOAD_LIMITS) do
        local v = Int(f[4 + i], max)
        if v == nil then return nil end
        d[i] = v
    end
    return d
end

-- Contestar: solo el enlace o un ayudante, solo a alguien de la unión y con topes
local answered, answeredN, winT, winN = {}, 0, -999, 0
-- (abierta: lo que vale lo mira el manejador. Por susurro, de una etiqueta de la configuración y de quien está en la
-- lista de esa hermandad o, si es de otra, la comunidad lo avala; además, el tope por remitente de Net/Security.lua)
HU:RegisterMessage("UQ", { open = true, ttl = 15, combat = "req" })
HU.comm.UQ = function(self, sender, f, dist)
    local tag, id = f[1], f[2]
    if dist ~= "WHISPER" or not (self.cfg and self.myTag and tag and self.cfg.byTag[tag]) then return end
    if type(id) ~= "string" or #id > 8 or not id:match("^%w+$") then return end
    if not (self:MemberOf(sender, tag) or (tag ~= self.myTag and self:Vouched(sender, tag))) then return end
    local role = MyRole(self)
    if not role then return end
    local k, now = sender:lower(), GetTime()
    if answered[k] and now - answered[k] < LOAD_GAP then return end
    if now - winT >= LOAD_GAP then winT, winN = now, 0 end
    if winN >= LOAD_MAX then return end
    if not answered[k] then answeredN = answeredN + 1 end
    answered[k], winN = now, winN + 1
    if answeredN > 200 then
        for key, t in pairs(answered) do if now - t >= LOAD_GAP then answered[key] = nil; answeredN = answeredN - 1 end end
    end
    self:Whisper(sender, "UR~" .. table.concat(LoadFields(self, id, role), "~"), true)
end

-- (solo de a quien se lo he preguntado, con la etiqueta de su hermandad y en esta pregunta; cada número se mira)
HU:RegisterMessage("UR", { open = true, ttl = 15 })
HU.comm.UR = function(self, sender, f, dist)
    local run = loadRun
    if dist ~= "WHISPER" or not run or f[2] ~= run.id then return end
    local row = run.byKey[sender:lower()]
    if not row or row.tag ~= f[1] or row.data then return end
    local d = ParseLoad(f)
    if not d then
        row.bad = true
        return self:Debug("Carga de los enlaces: números que no valen de", sender)
    end
    row.data = d
end

local ROLE = { e = "enlace", a = "ayudante" }
local function LoadPct(x) if x == false then return L("sin medidor") end return string.format("%.1f %%", x / 10) end
local function LoadNum(x) if x == false then return "?" end return tostring(x) end
local function LoadRow(self, row)
    local head = "<" .. tostring(row.tag) .. ">  "
    if not row.name then return head .. L("no sé quién es su enlace (aún no se ha presentado)") end
    local who, d = self:Nice(row.name), row.data
    if not d then
        return head .. who .. (row.guess and L(" (un contacto: no sé si es su enlace)") or "") .. "  "
            .. (row.bad and L("ha contestado con números que no valen") or L("NO HA CONTESTADO"))
    end
    return head .. string.format(L("%s · %s %s · %s min · CPU %s (pico %s) · FPS %s (mín. 10 min %s) · cola %s · mensajes por minuto: salen %s, entran %s"),
        who, L(ROLE[d.role]), d.ver, LoadNum(d[1]), LoadPct(d[2]), LoadPct(d[3]), LoadNum(d[4]), LoadNum(d[5]), LoadNum(d[6]),
        LoadNum(d[7]), LoadNum(d[8]))
end

local function ShowLoad(self, run)
    if loadRun ~= run then return end
    loadRun = nil
    local lines = { HU.ADDON_TITLE .. " " .. tostring(HU.version) .. " - " .. L("carga de los enlaces") .. " - " .. date("%d/%m/%Y %H:%M"),
        L("Cada enlace dice de sí mismo solo números: minutos conectado, CPU de GuildUnion según el juego (ahora y la más alta de su sesión), FPS (ahora y los más bajos de sus últimos 10 min), mensajes en su cola de envío y mensajes del addon por minuto que le salen y le entran."),
        "" }
    local known, got = 0, 0
    for _, row in ipairs(run.rows) do
        lines[#lines + 1] = LoadRow(self, row)
        if row.name then known = known + 1 end
        if row.data then got = got + 1 end
    end
    local summary = string.format(L("Carga de los enlaces: han contestado %d de %d."), got, known)
    lines[#lines + 1] = ""
    lines[#lines + 1] = summary
    self:Print(summary)
    if self.UI and self.UI.ShowCopy then
        self.UI:ShowCopy(L("Carga de los enlaces (Ctrl+C y mándaselo a quien lleva el addon)"), table.concat(lines, "\n"))
    else
        for _, l in ipairs(lines) do self:Print(l) end
    end
end

-- /gu carga (oficiales): pregunta al enlace de cada hermandad, la mía incluida, y a los 10 s enseña lo que ha llegado
function HU:AskRelayLoad()
    if not (self:CanOfficer() or (self:IsOfficerName(self:Me()))) then
        return self:Print(L("Solo los oficiales pueden medir la carga de los enlaces."))
    end
    if not (self.cfg and self.myTag) then return self:Print(L("Aún no hay comunidad: no hay enlaces que medir.")) end
    if loadRun then return self:Print(L("Ya estás midiendo: el resultado sale en unos segundos.")) end
    local wait = math.ceil(LOAD_GAP - (GetTime() - loadAskT))
    if wait > 0 then
        return self:Print(string.format(L("Espera %d s: cada enlace contesta como mucho una vez cada %d s."), wait, LOAD_GAP))
    end
    if HU.paused or self:IsChatLockedDown() then
        return self:Print(L("Ahora no se pueden mandar mensajes del addon (el juego bloquea el chat): prueba en un rato."))
    end
    loadAskT = GetTime()
    local run = { id = HU.B36(time()), rows = {}, byKey = {} }
    loadRun = run
    HU.After(LOAD_WAIT, function() ShowLoad(HU, run) end)
    local tags, asked = { self.myTag }, 0
    for _, t in ipairs(self:OtherTags()) do tags[#tags + 1] = t end
    for _, tag in ipairs(tags) do
        local name, guess
        if tag == self.myTag then
            name = self:RelayName()
        else
            -- (su enlace, si lo ha dicho él; si no, mi mejor contacto de esa hermandad, que suele serlo: con las listas
            -- sin confirmar todavía no se sabe de primera mano)
            local rp = self:KnownRelay(tag)
            if not rp then rp, guess = self:BestPeer(tag), true end
            name = rp and rp.name
        end
        local row = { tag = tag, name = name, guess = guess }
        run.rows[#run.rows + 1] = row
        local k = name and self:Key(name)
        if k and k == self:MeKey() then
            -- (el enlace de mi hermandad soy yo: mis números, sin mensajes)
            row.data = ParseLoad(LoadFields(self, run.id, MyRole(self) or "e"))
        elseif k then
            run.byKey[k] = row
            asked = asked + 1
            self:Whisper(name, "UQ~" .. self.myTag .. "~" .. run.id, true)
        end
    end
    self:Print(string.format(L("Midiendo la carga de los enlaces: preguntado a %d. El resultado, en %d s."), asked, LOAD_WAIT))
end

-- textos en inglés
local E = HU.EN
if E then
    E["Sin addon, de los conectados que conozco: "] = "Without the addon, of the online players I know: "
    E["<%s> %d de %d"] = "<%s> %d of %d"
    E["quién no tiene el addon"] = "who doesn't have the addon"
    E["Límites:"] = "Limits:"
    E["- Solo los conectados: de quien no está conectado no se puede saber."] = "- Online players only: there's no way to know about those who are offline."
    E["- De las otras hermandades, solo los conectados que veo en sus listas: la de Miembros de la unión y su lista corta (maestro, oficiales, enlace y ayudantes)."] = "- From the other guilds, only the online players I see in their lists: the Union members one and their short list (guild master, officers, relay and helpers)."
    E["- «Con addon» = me ha saludado el addon en esta sesión. De las otras hermandades casi solo me saludan su enlace y sus ayudantes: ahí «sin addon» puede ser también «no lo sé»."] = "- \"With the addon\" = their addon has greeted me this session. From the other guilds almost only their relay and helpers greet me: there \"without the addon\" can also mean \"I don't know\"."
    E["<%s> (la mía): %d conectados · con addon %d · sin addon %d"] = "<%s> (mine): %d online · with the addon %d · without it %d"
    E["<%s>: %d conectados que veo · con addon %d · sin addon o sin saberlo %d"] = "<%s>: %d online that I see · with the addon %d · without it or unknown %d"
    E["Aún no hay comunidad: no sé qué hermandades mirar."] = "No community yet: I don't know which guilds to look at."
    E["Quién no tiene el addon (Ctrl+C para copiarlo)"] = "Who doesn't have the addon (Ctrl+C to copy it)"
    E["enlace"] = "relay"
    E["ayudante"] = "helper"
    E["sin medidor"] = "no profiler"
    E["no sé quién es su enlace (aún no se ha presentado)"] = "I don't know who their relay is (not introduced yet)"
    E[" (un contacto: no sé si es su enlace)"] = " (a contact: I don't know if they're the relay)"
    E["ha contestado con números que no valen"] = "answered with numbers that aren't valid"
    E["NO HA CONTESTADO"] = "DID NOT ANSWER"
    E["%s · %s %s · %s min · CPU %s (pico %s) · FPS %s (mín. 10 min %s) · cola %s · mensajes por minuto: salen %s, entran %s"] = "%s · %s %s · %s min · CPU %s (peak %s) · FPS %s (10 min low %s) · queue %s · messages per minute: out %s, in %s"
    E["carga de los enlaces"] = "relay load"
    E["Cada enlace dice de sí mismo solo números: minutos conectado, CPU de GuildUnion según el juego (ahora y la más alta de su sesión), FPS (ahora y los más bajos de sus últimos 10 min), mensajes en su cola de envío y mensajes del addon por minuto que le salen y le entran."] = "Each relay reports only numbers about itself: minutes online, GuildUnion CPU according to the game (now and its session high), FPS (now and its lowest in the last 10 min), messages in its send queue and addon messages per minute going out and coming in."
    E["Carga de los enlaces: han contestado %d de %d."] = "Relay load: %d of %d answered."
    E["Carga de los enlaces (Ctrl+C y mándaselo a quien lleva el addon)"] = "Relay load (Ctrl+C and send it to the addon's maintainer)"
    E["Solo los oficiales pueden medir la carga de los enlaces."] = "Only officers can measure the relays' load."
    E["Aún no hay comunidad: no hay enlaces que medir."] = "No community yet: there are no relays to measure."
    E["Ya estás midiendo: el resultado sale en unos segundos."] = "Already measuring: the result comes in a few seconds."
    E["Espera %d s: cada enlace contesta como mucho una vez cada %d s."] = "Wait %d s: each relay answers at most once every %d s."
    E["Ahora no se pueden mandar mensajes del addon (el juego bloquea el chat): prueba en un rato."] = "Addon messages can't be sent right now (the game is blocking chat): try again in a while."
    E["Midiendo la carga de los enlaces: preguntado a %d. El resultado, en %d s."] = "Measuring the relays' load: asked %d. The result in %d s."
end

HU:Module("Report", { "Channel", "Config", "Core", "Domain/Trust", "Guard", "Lists", "Net/Relay", "Net/RosterSync", "Net/Security", "Net/Transport", "Perf", "PratBridge", "Protocol", "Roster", "Social", "WMPanel" })
