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
        for _, cmd in ipairs({ "RB", "RC", "PB", "WL", "OD", "HL" }) do
            HU:Send(cmd .. "~DOS~x", "WHISPER", DEST)
        end
        w:Advance(3)
        local s = ToDest()
        A.equal(6, #s)
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

    it("en pausa (versión mínima): lo que sale de la cola se pierde", function()
        -- (comportamiento de hoy: SendOne devuelve false sin mandar y el mensaje no vuelve a la cola)
        HU.paused = true
        HU:Send("CW~a~hola", "WHISPER", DEST)
        HU.paused = nil
        w:Advance(3)
        A.equal(0, #ToDest())
    end)
end)

-- (el formato de los mensajes se prueba en formato_spec.lua)
