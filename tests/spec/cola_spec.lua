-- Pruebas de CARACTERIZACIÓN de la cola de envío (Comm.lua: HU:Send, Flush, Pop). Fijan prefijos,
-- prioridades, caducidad y «gana el último» antes de pasarlos al registro de mensajes.
local F = require("lib.fixtures")
local A = assert_

local THROTTLE = 3 -- (Enum.SendAddonMessageResult.AddonMessageThrottle)
local DEST = "Destino-Reino"

local a, HU, w
-- Lo que ha salido hacia DEST (lo demás es del propio addon: saludos, listas...)
local function ToDest()
    local out = {}
    for _, s in ipairs(w:TakeSent()) do if s.target == DEST then out[#out + 1] = s end end
    return out
end
local function Saturate() w.failSend = function() return THROTTLE end end
local function Release() w.failSend = nil end

describe("Cola de envío", function()
    before_each(function()
        a = F.Community()
        HU, w = a.HU, a.w
        w:Advance(10) -- (que se llene el cupo)
        w:TakeSent()
    end)

    it("el chat sale enseguida por HU20", function()
        A.truthy(HU:Send("CW~a~hola", "WHISPER", DEST))
        local s = ToDest()
        A.equal(1, #s)
        A.equal("HU20", s[1].prefix)
        A.equal("CW~a~hola", s[1].text)
    end)

    it("los datos grandes salen por HU20B", function()
        for _, cmd in ipairs({ "RB", "RC", "PB", "OD", "HL" }) do
            HU:Send(cmd .. "~DOS~x", "WHISPER", DEST)
        end
        w:Advance(3)
        local s = ToDest()
        A.equal(5, #s)
        for _, m in ipairs(s) do A.equal("HU20B", m.prefix, m.text) end
    end)

    it("más de 255 bytes se corta sin partir letras", function()
        HU:Send("CW~" .. string.rep("ñ", 200), "WHISPER", DEST)
        local s = ToDest()
        A.equal(255, #s[1].text) -- (3 + 126 eñes de 2 bytes)
        HU:Send("CW~x" .. string.rep("ñ", 200), "WHISPER", DEST) -- (4 + 2k: no cabe la eñe que haría 256)
        A.equal(254, #ToDest()[1].text)
    end)

    it("con el juego saturado, el mensaje espera y sale después", function()
        Saturate()
        HU:Send("CW~a~hola", "WHISPER", DEST)
        A.equal(0, #ToDest())
        Release()
        w:Advance(2)
        A.equal(1, #ToDest())
    end)

    it("con el chat bloqueado (lockdown) no sale nada hasta que acaba", function()
        w.lockdown = true
        HU:Send("CW~a~hola", "WHISPER", DEST)
        w:Advance(5)
        A.equal(0, #ToDest())
        w.lockdown = false
        w:Advance(2)
        A.equal(1, #ToDest())
    end)

    it("el chat sale antes que lo normal", function()
        Saturate()
        HU:Send("ZZ~normal", "WHISPER", DEST)
        HU:Send("CW~a~chat", "WHISPER", DEST)
        Release()
        w:Advance(3)
        local s = ToDest()
        A.equal(2, #s)
        A.equal("CW~a~chat", s[1].text)
        A.equal("ZZ~normal", s[2].text)
    end)

    it("«gana el último» (HI): el nuevo sustituye al que espera", function()
        Saturate()
        HU:Send("HI~1", "WHISPER", DEST)
        HU:Send("HI~2", "WHISPER", DEST)
        A.equal(1, HU.qStats.replaced)
        Release()
        w:Advance(3)
        local s = ToDest()
        A.equal(1, #s)
        A.equal("HI~2", s[1].text)
    end)

    it("un mensaje que no es de «gana el último» no se sustituye", function()
        Saturate()
        HU:Send("LP~1", "WHISPER", DEST)
        HU:Send("LP~2", "WHISPER", DEST)
        Release()
        w:Advance(3)
        A.equal(2, #ToDest())
    end)

    it("caducidad: una línea de chat que no sale en 60 s se tira y se avisa", function()
        local lost = {}
        HU.OnChatLost = function(_, msg) lost[#lost + 1] = msg end
        Saturate()
        HU:Send("CW~a~hola", "WHISPER", DEST)
        w:Advance(62)
        Release()
        w:Advance(2)
        A.equal(0, #ToDest())
        A.equal(1, HU.qStats.expired.CW)
        A.same({ "CW~a~hola" }, lost)
    end)

    it("los silencios no caducan, pero se les resta lo que han esperado", function()
        Saturate()
        HU:Send("MU~Alguien-Reino~600~x", "WHISPER", DEST)
        w:Advance(700)
        Release()
        w:Advance(2)
        local s = ToDest()
        A.equal(1, #s)
        A.equal("MU~Alguien-Reino~1~x", s[1].text) -- (600 - 700 s: como mínimo 1)
    end)

    it("con la cola llena sale el más viejo que pueda caducar; si todos son silencios, el nuevo no entra", function()
        Saturate()
        HU:Send("CW~a~viejo", "WHISPER", DEST)
        local accepted = 0
        for i = 1, 2000 do
            if not HU:Send("MU~Alguien" .. i .. "-Reino~0~x", "WHISPER", DEST) then break end
            accepted = accepted + 1
        end
        A.equal(1, HU.qStats.dropped.CW) -- (el único que podía caducar)
        A.equal(1, HU.qStats.dropped.MU) -- (el que ya no ha entrado)
        A.truthy(accepted >= 1499 and accepted < 2000, "entraron " .. accepted)
        A.truthy(HU:Send("MU~Urgente-Reino~0~x", "WHISPER", DEST, true)) -- (urgente: entra igual)
    end)

    it("en pausa (versión mínima): lo que sale de la cola se pierde", function()
        -- (comportamiento de hoy: SendOne devuelve false sin mandar y el mensaje no vuelve a la cola)
        HU.paused = true
        HU:Send("CW~a~hola", "WHISPER", DEST)
        HU.paused = nil
        w:Advance(3)
        A.equal(0, #ToDest())
    end)
end)

-- Jorge, 27/11: «cada vez que desloguea le llega eso a alguien… no revisa si está conectado». Un oficial sale del juego y
-- a otro le salen varios «No player named 'X' is currently playing.»: el addon le seguía susurrando (Net/Transport.lua)
describe("A quien ya no está no se le susurra", function()
    local NOT_FOUND = "No player named '%s' is currently playing."
    local function Offline(n) return string.format(NOT_FOUND, n) end
    before_each(function()
        a = F.Community()
        HU, w = a.HU, a.w
        a.env.ERR_CHAT_PLAYER_NOT_FOUND_S = NOT_FOUND
        w:Advance(10)
        w:TakeSent()
    end)

    it("si sé que se ha ido, ni entra en la cola; y lo que esperaba para él se tira, sin gastar cupo", function()
        local q0 = HU.qStats.offline
        -- (cinco esperando con el juego bloqueando el chat, como en un jefe; mientras, se va)
        w.lockdown = true
        for i = 1, 5 do A.truthy(HU:Whisper(DEST, "CW~a~linea" .. i)) end
        HU:MarkOffline(DEST)
        A.falsy(HU:Whisper(DEST, "CW~a~otra"), "ni entra en la cola")
        A.truthy(HU:Send("CW~a~guild", "GUILD"))
        w.lockdown = nil
        w:Advance(3)
        A.equal(0, #ToDest(), "nada le sale")
        A.equal(q0 + 6, HU.qStats.offline)
        -- (y lo de los demás sale como siempre)
        A.truthy(HU:Whisper("Otro-Reino", "CW~a~hola"))
        w:Advance(1)
        local other = 0
        for _, s in ipairs(w:TakeSent()) do if s.target == "Otro-Reino" then other = other + 1 end end
        A.equal(1, other)
        A.same({}, a:Errors())
    end)

    it("vuelve a recibir en cuanto le oigo (cualquier mensaje suyo) o pasados 10 minutos", function()
        HU:MarkOffline("Bea-Reino")
        A.truthy(HU:KnownOffline("Bea Reino"), "con espacio o con guion, es la misma")
        w:Receive("HU20", "ZQ~algo", "WHISPER", "Bea-Reino")
        A.falsy(HU:KnownOffline("Bea-Reino"), "le he oído")
        HU:MarkOffline("Bea-Reino")
        w:Advance(599)
        A.truthy(HU:KnownOffline("Bea-Reino"))
        w:Advance(2)
        A.falsy(HU:KnownOffline("Bea-Reino"), "a los 10 minutos se le vuelve a probar")
        A.falsy(HU:KnownOffline(nil))
        -- (con muchos apuntados, los viejos se olvidan)
        for i = 1, 300 do HU:MarkOffline("Viejo" .. i .. "-Reino") end
        w:Advance(601)
        for i = 1, 201 do HU:MarkOffline("Nuevo" .. i .. "-Reino") end
        A.falsy(HU:KnownOffline("Viejo1-Reino"))
        A.truthy(HU:KnownOffline("Nuevo1-Reino"))
        A.same({}, a:Errors())
    end)

    it("el aviso del juego se oculta si el susurro es mío aunque esperase en la cola, y le apunta como ido siempre", function()
        local Filter = HU.SystemFilterForTests
        -- (el susurro entra en la cola y espera 40 s, con el chat bloqueado; sale, y entonces llega el aviso: antes se
        -- miraba desde que entró y, pasados 30 s, se veía)
        w.lockdown = true
        HU:Whisper(DEST, "CW~a~hola")
        w:Advance(40)
        w.lockdown = nil
        w:Advance(1)
        A.equal(1, #ToDest(), "ha salido ahora")
        A.truthy(Filter(nil, "CHAT_MSG_SYSTEM", Offline("Destino Reino")), "mío y recién salido: se oculta")
        A.truthy(HU:KnownOffline(DEST), "y ya no se le susurra")
        -- (de alguien a quien no he susurrado yo, p. ej. quien juega: se ve, pero también le apunto como ido)
        A.falsy(Filter(nil, "CHAT_MSG_SYSTEM", Offline("Bea Reino")))
        A.truthy(HU:KnownOffline("Bea-Reino"))
        A.falsy(Filter(nil, "CHAT_MSG_SYSTEM", "Otro aviso cualquiera"))
        A.same({}, a:Errors())
    end)

    it("si el juego contesta que no está conectado, le apunta como ido y no le manda el resto", function()
        w.failSend = function(_, _, dist, target) if dist == "WHISPER" and target == DEST then return 12 end end
        w.lockdown = true
        for i = 1, 3 do HU:Whisper(DEST, "CW~a~linea" .. i) end
        w.lockdown = nil
        local tries = 0
        local fail = w.failSend
        w.failSend = function(p, t, dist, target)
            if dist == "WHISPER" and target == DEST then tries = tries + 1 end
            return fail(p, t, dist, target)
        end
        w:Advance(3)
        A.equal(1, tries, "solo el primero lo intenta")
        A.truthy(HU:KnownOffline(DEST))
        A.same({}, a:Errors())
    end)

    it("si un compañero avisa de que alguien de otra hermandad no está (PX), tampoco se le susurra (Presence.lua)", function()
        A.falsy(HU:KnownOffline("Bea-Reino"))
        w:Receive("HU20", "PX~DOS~Bea-Reino", "GUILD", "Compi-Reino")
        A.truthy(HU:KnownOffline("Bea-Reino"))
        A.falsy(HU:Whisper("Bea-Reino", "CW~a~hola"))
        A.same({}, a:Errors())
    end)

    it("el historial tampoco le manda el resto a quien se ha ido (History.lua)", function()
        local send = HU.HistoryForTests.send
        local hist = function() return HU.qStats.hist or { sent = 0, offline = 0 } end
        local s0, o0 = hist().sent, hist().offline
        -- (el primero sale y el juego dice que no está; el resto ya no sale)
        w.failSend = function(prefix, _, dist, target) if prefix == "HU20H" and dist == "WHISPER" and target == DEST then return 12 end end
        for i = 1, 3 do send("R~1~x~" .. i, DEST) end
        w:Advance(3)
        A.equal(o0 + 3, hist().offline, "los tres, como «no está»")
        A.equal(s0, hist().sent, "ninguno como enviado")
        A.truthy(HU:KnownOffline(DEST))
        -- (y a otro sí)
        w.failSend = nil
        send("R~1~x~4", "Otro-Reino")
        w:Advance(2)
        A.equal(s0 + 1, hist().sent)
        A.same({}, a:Errors())
    end)
end)

-- (el formato de los mensajes se prueba en formato_spec.lua)
