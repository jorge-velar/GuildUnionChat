-- Escenarios de red (tests/lib/red.lua) que hoy se prueban en el juego con varias personas: el canal
-- que falla, muchas hermandades, el enlace que se va. Fijan lo que ve cada jugador.
local red = require("lib.red")
local A = assert_

-- Una comunidad con `n` hermandades (G1..Gn) y `per` jugadores en cada una (los `officers` primeros,
-- oficiales: 1 si no se dice). extra: más líneas para la Información
local function Community(n, per, officers, extra)
    officers = officers or 1
    local lines, guilds = { "GU:t:Comunidad de prueba", "GU:c:CanalPrueba:clave", extra }, {}
    for i = 1, n do
        lines[#lines + 1] = "GU:g:Hermandad " .. i .. ":G" .. i
        guilds["G" .. i] = "Hermandad " .. i
    end
    local net = red.New({ info = table.concat(lines, "\n"), guilds = guilds })
    local by = {}
    for i = 1, n do
        for j = 1, per do
            local name = "J" .. string.char(96 + i) .. string.char(96 + j) -- (Jaa, Jab, Jba…)
            local p = net:Player(name, "G" .. i, { rankIndex = j <= officers and 1 or 4 })
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

-- En qué sala está cada uno: { [jugador] = carril }, y si están todos en la misma
local function Lanes(p)
    local out, first, same = {}, nil, true
    for _, q in ipairs(p) do
        if q.online then
            out[q.name] = q.HU:ChannelLane()
            first = first or out[q.name]
            if out[q.name] ~= first then same = false end
        end
    end
    return out, same and first or nil
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

-- Lo que el addon le ha escrito en el chat a un jugador, todo junto
local function ChatOf(q)
    local t = {}
    for _, c in ipairs(q.w.chat) do t[#t + 1] = tostring(c.msg) end
    return table.concat(t, "\n")
end
local function LanesText(p)
    local t = {}
    for k, v in pairs((Lanes(p))) do t[#t + 1] = k .. "=" .. v end
    table.sort(t)
    return table.concat(t, " ")
end

describe("Escenarios: menciones", function()
    it("@Nombre-Apellido avisa a esa persona; @todos solo vale de un oficial", function()
        local net, p = Community(2, 2)
        local jaa, jab, jba, jbb = p[1], p[2], p[3], p[4]
        local function Marked(q, mark)
            for _, c in ipairs(q.w.chat) do
                if tostring(c.msg):find(q.HU.MENTION_MARK[mark], 1, true) then return true end
            end
            return false
        end
        jbb:Say("@Jaa-Reino mira esto")
        net:Advance(5)
        A.truthy(Marked(jaa, "me"), "a Jaa la mencionan")
        A.falsy(Marked(jab, "me"), "a Jab no")
        A.equal("me", jaa.HU:MentionsMe("hola @jaa reino", "Jbb-Reino", "G2"))
        A.falsy(jaa.HU:MentionsMe("hola @Jaa", "Jbb-Reino", "G2"), "solo con el nombre no")
        jbb:Say("@todos de un miembro")
        net:Advance(5)
        A.falsy(Marked(jab, "all"), "un miembro no puede llamar a todos")
        jba:Say("@todos de un oficial")
        net:Advance(5)
        A.truthy(Marked(jab, "all"), "un oficial sí")
        -- (y el color de una mención de otro de la comunidad)
        A.matches("|cff7fd4ff@Jbb%-Reino|r", jaa.HU:HighlightMentions("hola @Jbb-Reino", "Jba-Reino", "G2"))
        A.same({}, net:Errors())
    end)
end)

describe("Escenarios: sonda del canal (/gu sonda)", function()
    it("cada uno dice cuántos mensajes de la sonda le han llegado", function()
        local net, p = Community(2, 2)
        A.matches("Sonda: mandando 5", p[1]:Gu("sonda 5"))
        net:Advance(30)
        A.matches("Sonda terminada: el juego aceptó 5 de 5", ChatOf(p[1]))
        A.matches("te han llegado 5 de 5", ChatOf(p[3]))
        A.matches("La sonda solo la pueden mandar", p[2]:Gu("sonda 5"))
        A.same({}, net:Errors())
    end)

    it("si el juego rechaza el canal, la sonda lo dice", function()
        local net, p = Community(2, 1)
        net.channelRefuse = true
        p[1]:Gu("sonda 3")
        net:Advance(15)
        A.matches("aceptó 0 de 3", ChatOf(p[1]))
        A.falsy(ChatOf(p[2]):find("te han llegado", 1, true))
    end)
end)

describe("Escenarios: salas del canal (carriles)", function()
    it("subir a mano: un oficial lo propone, otro lo confirma y se muda toda la comunidad", function()
        local net, p = Community(2, 3, 2)
        local ofi1, ofi2 = p[1], p[2]
        A.matches("Propuesta enviada", ofi1:Gu("carril subir"))
        net:Advance(2)
        A.matches("carril confirmar", ChatOf(ofi2))
        A.matches("Carril subido", ofi2:Gu("carril confirmar"))
        local all = net:AdvanceUntil(function() local _, same = Lanes(p) return same == 1 end, 300)
        A.truthy(all, "no se ha mudado todo el mundo: " .. LanesText(p))
        -- (en la sala nueva el chat sigue llegando)
        net:Advance(60)
        p[5]:Say("desde la sala 1")
        net:Advance(5)
        A.equal(1, Count(p[3]:Heard(p[5], "main"), "desde la sala 1"))
        A.matches("Carril del canal: 1", p[4]:Gu("carril"))
        A.same({}, net:Errors())
    end)

    it("sin otro oficial que confirme, «confirmar» no hace nada", function()
        local net, p = Community(2, 2, 1)
        A.matches("No hay ninguna propuesta", p[1]:Gu("carril confirmar"))
        A.matches("Solo los maestros y oficiales", p[2]:Gu("carril subir"))
        net:Advance(5)
        local _, same = Lanes(p)
        A.equal(0, same)
    end)

    it("reiniciar (escrito dos veces por un oficial) devuelve a todos a la sala principal", function()
        local net, p = Community(2, 2, 2)
        p[1]:Gu("carril subir"); net:Advance(2); p[2]:Gu("carril confirmar")
        A.truthy(net:AdvanceUntil(function() local _, s = Lanes(p) return s == 1 end, 300), LanesText(p))
        net:Advance(130) -- (como mucho un cambio cada 2 min por lo que digan otros)
        A.matches("otra vez", p[3]:Gu("carril reiniciar"))
        A.matches("Carril reiniciado", p[3]:Gu("carril reiniciar"))
        A.truthy(net:AdvanceUntil(function() local _, s = Lanes(p) return s == 0 end, 300), "no han vuelto todos a la 0: " .. LanesText(p))
        A.same({}, net:Errors())
    end)

    it("con la sala fijada en la Información (GU:l:2) todos van a la 2 y no se puede cambiar", function()
        local net, p = Community(2, 2, 2, "GU:l:2")
        local _, same = Lanes(p)
        A.equal(2, same, LanesText(p))
        A.matches("fijada", p[1]:Gu("carril subir"))
        net:Advance(5)
        p[3]:Say("en la sala fijada")
        net:Advance(5)
        A.equal(1, Count(p[1]:Heard(p[3], "main"), "en la sala fijada"))
        A.same({}, net:Errors())
    end)

    it("si el canal lo rechaza todo 5 minutos y lo confirma el enlace de la otra hermandad, se sube solo", function()
        local net, p = Community(2, 2, 2)
        net:Advance(600) -- (los rechazos no cuentan hasta 10 min después de la pantalla de carga)
        net.channelRefuse = true
        local moved = net:AdvanceUntil(function() local _, s = Lanes(p) return s == 1 end, 900, 5)
        A.truthy(moved, "no se ha subido de sala: " .. LanesText(p))
        net.channelRefuse = false
        A.same({}, net:Errors())
    end)
end)
