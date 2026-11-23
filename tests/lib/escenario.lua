-- Un rato de juego fijo con la red (tests/lib/red.lua): dos hermandades de dos jugadores, chat de
-- hermandad y de oficiales, un silencio, una búsqueda en el historial y alguien que sale y vuelve.
-- Es siempre igual, así que lo que se mandan sirve de referencia (pruebas de formato).
--
--   local net, p = escenario.Run()                     -- todos con la versión de la carpeta
--   local net, p = escenario.Run({ ana = "v5.4.41" })  -- Ana con la versión publicada
local red = require("lib.red")

local E = {}

-- refs: { ana = ref, alba = ref, bea = ref, blas = ref } (nil = la versión de la carpeta)
function E.Run(refs)
    refs = refs or {}
    local net = red.New()
    local p = {
        ana = net:Player("Ana", "UNO", { rankIndex = 1, ref = refs.ana }),
        alba = net:Player("Alba", "UNO", { ref = refs.alba }),
        bea = net:Player("Bea", "DOS", { rankIndex = 1, ref = refs.bea }),
        blas = net:Player("Blas", "DOS", { ref = refs.blas }),
    }
    for _, name in ipairs({ "ana", "alba", "bea", "blas" }) do net:Login(p[name]) end
    net:Advance(90)
    -- (los oficiales confirman la lista de la otra hermandad, «/gu confirmar ETIQ», como al montar
    -- una comunidad de verdad: sin eso no hay contactos comprobados y la seguridad rechaza los
    -- susurros de la otra hermandad)
    p.ana.HU:ConfirmRoster("DOS")
    p.bea.HU:ConfirmRoster("UNO")
    net:Advance(30)
    -- chat de hermandad en los dos sentidos y de oficiales
    p.ana:Say("hola desde UNO")
    net:Advance(3)
    p.blas:Say("hola desde DOS")
    net:Advance(3)
    p.ana:Say("solo oficiales", "OFFICER")
    net:Advance(10)
    -- un silencio de Ana (oficial de UNO) a Blas
    p.ana.HU:SetMute(p.blas.full, 600, "spam")
    net:Advance(20)
    -- una búsqueda en el historial
    p.bea.HU:HistSearchRemote({ text = "hola" }, function() end, function() end)
    net:Advance(30)
    -- Alba sale y vuelve
    net:Logout(p.alba)
    net:Advance(60)
    net:Login(p.alba)
    net:Advance(300)
    return net, p
end

return E
