-- Guild Union - registro de pruebas: notas a mano y tiempos que se apuntan solos (apagado por defecto)
--   /gu registro on [Nombre Apellido del que dirige]   /gu registro off   /gu nota texto
local _, HU = ...
local L = HU.L
HU.TPREFIX = "HU20T"
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, HU.TPREFIX) end
local MAX = 3000

local function DB()
    local adb = HU.adb
    if not adb then return nil end
    adb.testLog = adb.testLog or { on = false, entries = {} }
    return adb.testLog
end
local function On() local d = DB(); return d and d.on end
local function Now() return (GetServerTime and GetServerTime()) or time() end
local function Clean(s) return (tostring(s or ""):gsub("[%c~]", " ")) end

-- los números del momento
local function Snapshot()
    local parts = {}
    for _, tag in ipairs(HU:OtherTags()) do
        local r = HU.remoteRoster[tag]
        parts[#parts + 1] = tag .. " " .. (r and #r.members or 0)
    end
    local _, _, home, world = GetNetStats()
    -- (memoria de Lua de todos los addons, que no cuesta nada; medir solo la del addon daba tirones de 50-110 ms)
    local mem = collectgarbage("count") / 1024
    return string.format("listas: %s · mía %d · cola %d · errores %d · Lua %.0f MB · %d fps · ping %d",
        table.concat(parts, ", "), HU.rosterOnline or 0, HU:QueueSize(), #HU.errors, mem,
        math.floor(GetFramerate() + 0.5), math.max(home or 0, world or 0))
end

local function Add(kind, text, who, t, snap)
    local d = DB()
    if not d or not d.on then return end
    local e = { t = t or Now(), who = who or HU:Me(), v = HU.version, k = kind, x = Clean(text), s = snap }
    d.entries[#d.entries + 1] = e
    while #d.entries > MAX do table.remove(d.entries, 1) end
    -- (lo de los demás llega al que dirige la prueba)
    if d.leader and not who and not HU.paused and HU:Key(d.leader) ~= HU:MeKey() then
        if HU.MarkPinged then HU:MarkPinged(d.leader) end
        pcall(C_ChatInfo.SendAddonMessage, HU.TPREFIX,
            HU.Utf8Cut(table.concat({ e.t, kind, e.x, snap or "" }, "~"), 255), "WHISPER", d.leader)
    end
end
HU.TestLogAdd = Add

HU:On("CHAT_MSG_ADDON", function(prefix, text, dist, sender)
    if prefix ~= HU.TPREFIX or dist ~= "WHISPER" or not On() then return end
    local f = HU.Split(text, "~")
    Add(f[2] or "?", f[3] or "", HU:FullName(sender), tonumber(f[1]), f[4] ~= "" and f[4] or nil)
end)

function HU:TestLogCommand(cmd, arg)
    local d = DB()
    if not d then return end
    if cmd == "nota" then
        if not d.on then return self:Print(L("El registro de pruebas está apagado (/gu registro on).")) end
        Add("nota", arg, nil, nil, Snapshot())
        return self:Print(L("Nota guardada."))
    end
    local a, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    if a == "on" then
        d.on, d.leader = true, (rest ~= "" and rest) or nil
        Add("inicio", "registro encendido", nil, nil, Snapshot())
        self:Print(L("Registro de pruebas encendido") .. (d.leader and (L(": se manda a ") .. d.leader) or L(" (lo recibes tú)")) .. L(". Haz /reload al acabar para que se guarde."))
    elseif a == "off" or a == "pasar" then
        -- (al apagarlo: se abre en una ventana para copiarlo y pasarlo, y se borra del addon para que no ocupe)
        if a == "off" then
            Add("fin", "registro apagado", nil, nil, Snapshot())
            d.on = false
        end
        local lines = {}
        for _, e in ipairs(d.entries) do
            lines[#lines + 1] = date("%d/%m %H:%M:%S", e.t or 0) .. "  " .. tostring(e.k) .. "  " .. HU:Nice(e.who or "?") .. "  " .. tostring(e.x or "") .. ((e.s and e.s ~= "") and ("  [" .. e.s .. "]") or "")
        end
        if #lines > 0 and HU.UI and HU.UI.ShowCopy then
            HU.UI:ShowCopy(L("Registro de pruebas (Ctrl+A, Ctrl+C y pásalo)"), HU.ADDON_TITLE .. " " .. tostring(HU.version) .. "\n" .. table.concat(lines, "\n"))
        end
        if a == "off" then
            d.entries = {}
            self:Print(L("Registro de pruebas apagado: está en la ventana para copiarlo y pasarlo, y ya no ocupa en el addon."))
        else
            self:Print(L("Registro de pruebas en la ventana para copiarlo (/gu registro off lo apaga y lo borra)."))
        end
    elseif a == "borrar" then
        d.entries = {}
        self:Print(L("Registro de pruebas borrado."))
    else
        self:Print(string.format(L("Registro de pruebas: %s, %d apuntes. /gu registro on [quien dirige] | pasar | off | borrar"), d.on and "on" or "off", #d.entries))
    end
end

---------------------------------------------------------------------------
-- Lo que se apunta solo (solo con el registro encendido)
---------------------------------------------------------------------------
-- errores del addon
local origErr = HU.RecordError
HU.RecordError = function(self, e, where)
    origErr(self, e, where)
    if On() then Add("error", tostring(where) .. ": " .. (type(e) == "table" and tostring(e.msg) or tostring(e))) end
end

-- conexiones de mi hermandad (el aviso del juego) y cambios que llegan de las otras
HU:On("CHAT_MSG_SYSTEM", function(text)
    if not On() or type(text) ~= "string" or not HU.PresencePatterns then return end
    for _, p in ipairs(HU.PresencePatterns()) do
        local name = text:match(p.pat)
        if name then
            name = name:match("^|Hplayer:([^|:]+)") or name
            if HU.roster[HU:Key(name) or ""] then Add(p.on and "conecta" or "desconecta", name) end
            return
        end
    end
end)
local origRC = HU.comm.RC
HU.comm.RC = function(self, sender, f, dist, raw)
    origRC(self, sender, f, dist, raw)
    if On() and f[1] and f[8] then
        for op, n in f[8]:gmatch("([%+%-])([^,;]+)") do Add(op == "+" and "lista_conecta" or "lista_desconecta", f[1] .. " " .. n) end
    end
end

-- chat entre hermandades: lo que mando y lo que me llega
hooksecurefunc(HU, "Forward", function(_, kind, msg) if On() then Add("envio", tostring(kind) .. ": " .. tostring(msg)) end end)
HU:On("CHAT_MSG_CHANNEL", function(text, author, _, fullName, _, _, _, _, baseName)
    if On() and HU:KindOf(baseName, fullName) == "main" and type(text) == "string" and not text:find("^%[%w+:R%]") then
        Add("recibo", tostring(author) .. ": " .. text)
    end
end)

-- al entrar: cuándo están todas las listas; entradas masivas; cada 5 min, los números; peor fotograma
local loginT, listsDone, hiCount, hiT, worst = nil, false, 0, 0, 0
HU:On("CHAT_MSG_ADDON", function(prefix, text, dist)
    if not On() or prefix ~= HU.PREFIX or dist ~= "GUILD" or type(text) ~= "string" or text:sub(1, 3) ~= "HI~" then return end
    local now = GetTime()
    if now - hiT > 60 then hiT, hiCount = now, 0 end
    hiCount = hiCount + 1
    if hiCount == 50 then Add("masiva", "50 saludos de la hermandad en menos de 1 min", nil, nil, Snapshot()) end
end)
local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function(_, el)
    if not On() then return end
    if el > worst then worst = el end
end)
HU:OnStart(function()
    loginT = GetTime()
    if On() then Add("entra", "entra al juego", nil, nil, Snapshot()) end
    HU.NewTicker(5, function()
        if not On() then return end
        if not listsDone then
            local all = #HU:OtherTags() > 0
            for _, tag in ipairs(HU:OtherTags()) do if not HU.remoteRoster[tag] then all = false end end
            if all then listsDone = true; Add("listas", string.format("todas las listas a los %d s de entrar", GetTime() - loginT), nil, nil, Snapshot()) end
        end
    end)
    HU.NewTicker(300, function()
        if not On() then return end
        Add("foto", string.format("peor fotograma en 5 min: %d ms", worst * 1000), nil, nil, Snapshot())
        worst = 0
    end)
end)
