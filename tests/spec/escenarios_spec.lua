-- Escenarios de red (tests/lib/red.lua) que hoy se prueban en el juego con varias personas: el canal
-- que falla, muchas hermandades, el enlace que se va. Fijan lo que ve cada jugador.
local red = require("lib.red")
local A = assert_

-- Una comunidad con `n` hermandades (G1..Gn) y `per` jugadores en cada una (el primero, oficial)
local function Community(n, per)
    local lines, guilds = { "GU:t:Comunidad de prueba", "GU:c:CanalPrueba:clave" }, {}
    for i = 1, n do
        lines[#lines + 1] = "GU:g:Hermandad " .. i .. ":G" .. i
        guilds["G" .. i] = "Hermandad " .. i
    end
    local net = red.New({ info = table.concat(lines, "\n"), guilds = guilds })
    local by = {}
    for i = 1, n do
        for j = 1, per do
            local name = "J" .. string.char(96 + i) .. string.char(96 + j) -- (Jaa, Jab, Jba…)
            local p = net:Player(name, "G" .. i, { rankIndex = j == 1 and 1 or 4 })
            -- (el canal de oficiales va en la nota de oficial de un miembro de cada hermandad)
            if j == 1 then p.member.officerNote = "GU:o:CanalOfi:clave2" end
            by[#by + 1] = p
        end
    end
    for _, p in ipairs(by) do net:Login(p) end
    net:Advance(90)
    -- (los oficiales confirman las listas de las demás, como al montar una comunidad)
    for _, p in ipairs(by) do
        if p.member.rankIndex == 1 then
            for i = 1, n do
                if "G" .. i ~= p.tag then p.HU:ConfirmRoster("G" .. i) end
            end
        end
    end
    net:Advance(30)
    return net, by
end

local function Count(list, text)
    local n = 0
    for _, m in ipairs(list) do if m == text then n = n + 1 end end
    return n
end

describe("Escenarios: el texto del canal no llega", function()
    it("el chat de hermandad y el de oficiales llegan por el respaldo, una vez", function()
        local net, p = Community(2, 2)
        local jaa, jba, jbb = p[1], p[3], p[4]
        net.channelTextDown = true
        jaa:Say("uno sin canal")
        net:Advance(5)
        jaa:Say("dos sin canal")
        net:Advance(5)
        jaa:Say("para oficiales", "OFFICER")
        net:Advance(10)
        A.equal(1, Count(jbb:Heard(jaa, "main"), "uno sin canal"), "Jbb, de la otra hermandad")
        A.equal(1, Count(jba:Heard(jaa, "main"), "dos sin canal"))
        A.equal(1, Count(jba:Heard(jaa, "off"), "para oficiales"), "Jba, oficial de la otra")
        A.equal(0, #jbb:Heard(jaa, "off"), "Jbb no es oficial")
        A.falsy(jaa.HU:TextChatOK(), "dos ecos seguidos sin volver: el canal se da por roto")
        A.same({}, net:Errors())
    end)

    it("pasados 5 minutos se vuelve a probar el canal", function()
        local net, p = Community(2, 1)
        local jaa, jba = p[1], p[2]
        net.channelTextDown = true
        jaa:Say("a"); net:Advance(3)
        jaa:Say("b"); net:Advance(3)
        A.falsy(jaa.HU:TextChatOK())
        net.channelTextDown = false
        net:Advance(301)
        A.truthy(jaa.HU:TextChatOK())
        jaa:Say("vuelve el canal")
        net:Advance(5)
        A.equal(1, Count(jba:Heard(jaa, "main"), "vuelve el canal"))
    end)
end)

describe("Escenarios: seis hermandades", function()
    it("con más de 4 hermandades el chat se reparte entre los de mi hermandad (CF) y llega a todas", function()
        local net, p = Community(6, 2)
        local author = p[1]
        net.channelTextDown = true
        author:Say("hola a las seis")
        net:Advance(10)
        for _, q in ipairs(p) do
            if q.tag ~= author.tag then
                A.equal(1, Count(q:Heard(author, "main"), "hola a las seis"), q.full)
            end
        end
        local cf = 0
        for _, m in ipairs(net.log) do if m.text:sub(1, 3) == "CF~" then cf = cf + 1 end end
        A.truthy(cf > 0, "se ha repartido con CF")
        A.same({}, net:Errors())
    end)
end)

describe("Escenarios: el enlace se va", function()
    it("otro de su hermandad toma el relevo y la otra hermandad lo sabe", function()
        local net, p = Community(2, 3)
        local relay
        for i = 1, 3 do if p[i].HU:IsRelay() then relay = p[i] end end
        A.truthy(relay, "G1 tiene enlace")
        net:Logout(relay)
        local new
        A.truthy(net:AdvanceUntil(function()
            for i = 1, 3 do if p[i] ~= relay and p[i].HU:IsRelay() then new = p[i] return true end end
        end, 400), "nadie ha tomado el relevo")
        local seen = net:AdvanceUntil(function()
            local r = p[4].HU:KnownRelay("G1")
            return r and r.name and r.name:lower() == new.key
        end, 400)
        A.truthy(seen, "G2 no se ha enterado del enlace nuevo")
        -- (y el chat sigue llegando)
        p[5]:Say("sigue funcionando")
        net:Advance(5)
        A.equal(1, Count(new:Heard(p[5], "main"), "sigue funcionando"))
        A.same({}, net:Errors())
    end)
end)
