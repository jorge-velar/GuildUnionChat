-- Varios jugadores a la vez (tests/lib/red.lua): lo que hoy se prueba en el juego con /gu registro
local red = require("lib.red")
local A = assert_

-- Dos hermandades, dos jugadores en cada una (un oficial y un miembro), todos conectados y en marcha
local function TwoGuilds(secs)
    local net = red.New()
    local p = {
        ana = net:Player("Ana", "UNO", { rankIndex = 1 }),
        alba = net:Player("Alba", "UNO"),
        bea = net:Player("Bea", "DOS", { rankIndex = 1 }),
        blas = net:Player("Blas", "DOS"),
    }
    for _, name in ipairs({ "ana", "alba", "bea", "blas" }) do net:Login(p[name]) end
    net:Advance(secs or 60)
    return net, p
end

describe("Red", function()
    it("cuatro jugadores de dos hermandades arrancan sin errores", function()
        local net, p = TwoGuilds(60)
        A.same({}, net:Errors(), "errores")
        for _, x in pairs(p) do
            A.equal(x.tag, x.HU.myTag, x.full .. ": su etiqueta")
            A.truthy(x.HU:IsJoined("main"), x.full .. ": en el canal de la comunidad")
        end
    end)

    it("el chat de /g llega a la otra hermandad, una sola vez", function()
        local net, p = TwoGuilds(60)
        p.ana:Say("hola desde UNO")
        net:Advance(5)
        A.same({ "hola desde UNO" }, p.bea:Heard(p.ana), "Bea")
        A.same({ "hola desde UNO" }, p.blas:Heard(p.ana), "Blas")
        A.same({}, net:Errors(), "errores")
    end)

    it("y de vuelta: lo de DOS llega a UNO", function()
        local net, p = TwoGuilds(60)
        p.ana:Say("hola desde UNO")
        net:Advance(2)
        p.blas:Say("hola desde DOS")
        net:Advance(5)
        A.same({ "hola desde DOS" }, p.ana:Heard(p.blas), "Ana")
        A.same({ "hola desde DOS" }, p.alba:Heard(p.blas), "Alba")
    end)

    it("lo de mi hermandad no sale repetido por el addon (ya está en /g)", function()
        local net, p = TwoGuilds(60)
        p.ana:Say("solo una vez")
        net:Advance(5)
        -- (Alba lo ve en /g, que el addon guarda en el historial: una entrada, no dos)
        A.same({ "solo una vez" }, p.alba:Heard(p.ana), "Alba")
    end)

    it("varias líneas seguidas llegan todas y en orden", function()
        local net, p = TwoGuilds(60)
        local lines = {}
        for i = 1, 5 do
            lines[i] = "línea " .. i
            p.ana:Say(lines[i])
        end
        net:Advance(10)
        A.same(lines, p.bea:Heard(p.ana), "Bea")
    end)

    it("cada uno tiene la lista de la otra hermandad antes de 90 s (el «listas» de /gu registro)", function()
        local net = red.New()
        local ps = {
            net:Player("Ana", "UNO", { rankIndex = 1 }), net:Player("Alba", "UNO"),
            net:Player("Bea", "DOS", { rankIndex = 1 }), net:Player("Blas", "DOS"),
        }
        for _, p in ipairs(ps) do net:Login(p) end
        local function AllLists()
            for _, p in ipairs(ps) do
                local other = p.tag == "UNO" and "DOS" or "UNO"
                local r = p.HU.remoteRoster[other]
                if not r or #(r.members or {}) ~= 2 then return false end
            end
            return true
        end
        local secs = net:AdvanceUntil(AllLists, 300)
        A.truthy(secs, "en 5 minutos no han llegado todas las listas")
        A.truthy(secs <= 90, "las listas han tardado " .. tostring(secs) .. " s")
        A.same({}, net:Errors(), "errores")
    end)

    it("quien entra tarde también recibe el chat", function()
        local net = red.New()
        local ana = net:Player("Ana", "UNO", { rankIndex = 1 })
        local bea = net:Player("Bea", "DOS", { rankIndex = 1 })
        local blas = net:Player("Blas", "DOS")
        net:Login(ana); net:Login(bea)
        net:Advance(60)
        net:Login(blas)
        net:Advance(60)
        ana:Say("hola, Blas")
        net:Advance(5)
        A.same({ "hola, Blas" }, blas:Heard(ana), "Blas")
        A.same({}, net:Errors(), "errores")
    end)
end)
