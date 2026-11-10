-- Guild Union - entradas masivas (tras un reinicio del servidor): la bienvenida a los que entran [+ARCHITECTURE.md]
local _, HU = ...

local BCAST = "\0hermandad" -- destino especial: lo que iba por susurro al que entra, va a toda la hermandad
local WAIT = 8               -- se juntan los que entran unos segundos
local GAP = 30               -- entre dos bienvenidas
local EMOTES_GAP = 900       -- los emoticonos (pueden ser 150) como mucho cada 15 minutos
HU.BCAST = BCAST

local sentNow, lastEmotes = nil, -9999
-- (la bienvenida se reparte en varios fotogramas: como mucho WELCOME_MS de trabajo en cada uno. De una vez
-- llegaba a 10 ms en el enlace: silencios, vetos, fijado, canales, colores y hasta 150 emoticonos)
local WELCOME_MS = 1
local co, coN, coT = nil, 0, 0
local clock = debugprofilestop or function() return GetTime() * 1000 end
local origWhisper = HU.Whisper
HU.Whisper = function(self, target, msg, urgent)
    if target ~= BCAST then return origWhisper(self, target, msg, urgent) end
    if type(msg) ~= "string" or not sentNow or sentNow[msg] then return end
    if msg:sub(1, 3) == "EM~" then
        if GetTime() - lastEmotes < EMOTES_GAP then return end
        sentNow.emotes = true
    end
    sentNow[msg] = true
    self:Send(msg, "GUILD")
    coN = coN + 1
    if co and clock() - coT > WELCOME_MS and coroutine.running() == co then coroutine.yield() end
end

-- el mensaje fijado que pasa por la hermandad (para que los oficiales no lo repitan)
local lastPN = -999
local origPN = HU.comm.PN
HU.comm.PN = function(self, sender, f, dist, raw)
    if dist == "GUILD" then lastPN = GetTime() end
    return origPN(self, sender, f, dist, raw)
end

local inner = HU.comm.PQ
local pending, lastWelcome, myPN = false, -999, -999

local function Finish()
    if sentNow and sentNow.emotes then lastEmotes = GetTime() end
    sentNow, co = nil, nil
end
local function Step()
    coT = clock()
    local ok, err = coroutine.resume(co)
    if not ok then
        co = nil
        -- (no se pudo partir, por ejemplo una pausa dentro de una llamada protegida: lo que falta sale de una
        -- vez, como antes, sin repetir lo ya mandado)
        if type(err) == "string" and err:find("yield", 1, true) then
            HU:SafeCall("bienvenida", inner, HU, BCAST, {}, "GUILD", "PQ")
        else
            HU:RecordError(err, "bienvenida")
        end
        return Finish()
    end
    if coroutine.status(co) == "dead" then return Finish() end
    HU.After(0, Step)
end
local function Welcome()
    pending = false
    lastWelcome = GetTime()
    sentNow, coN = {}, 0
    co = coroutine.create(function() inner(HU, BCAST, {}, "GUILD", "PQ") end)
    Step()
end

HU.comm.PQ = function(self, sender, f, dist, raw)
    -- (por susurro, como siempre: es una sola persona)
    if dist ~= "GUILD" then return inner(self, sender, f, dist, raw) end
    if self:IsRelay() then
        if pending then return end
        pending = true
        HU.After(math.max(WAIT, lastWelcome + GAP - GetTime()), Welcome)
        return
    end
    -- si el enlace no tiene el mensaje fijado (p. ej. acaba de entrar en la hermandad), lo pasa un
    -- oficial que lo tenga, una sola vez y solo si nadie lo ha pasado ya
    if self.db.pinned and self:CanPin() and GetTime() - myPN > 60 then
        myPN = GetTime()
        HU.After(20 + math.random() * 10, function()
            if GetTime() - lastPN > 25 and not co then
                sentNow = {}
                HU:SharePinned(BCAST)
                sentNow = nil
            end
        end)
    end
end

-- Quién es el enlace se recuerda 1 s: con cientos de saludos y peticiones a la vez, recorrer a los
-- 1.000 compañeros en cada una era lo que más costaba
local relayT, relayV, nameT, nameV = -1, nil, -1, nil
local origIsRelay, origRelayName = HU.IsRelay, HU.RelayName
HU.IsRelay = function(self)
    local now = GetTime()
    if now - relayT >= 1 then
        local was = relayV
        relayT, relayV = now, origIsRelay(self)
        -- (acabo de pasar a ser el enlace: me quedo un rato con los ayudantes del anterior)
        if relayV and was == false and self.InheritHelpers then self:InheritHelpers() end
    end
    return relayV
end
HU.RelayName = function(self)
    local now = GetTime()
    if now - nameT >= 1 then nameT, nameV = now, origRelayName(self) end
    return nameV
end
