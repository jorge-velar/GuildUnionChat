-- Medidas, para encontrar picos y no para crearlos: la CPU del addon según el juego y los FPS, siempre (Perf.lua);
-- quién de los conectados no tiene el addon (/gu sinaddon) y la carga de los enlaces (/gu carga, UQ y UR; Report.lua)
local red = require("lib.red")
local F = require("lib.fixtures")
local A = assert_
local unpack = table.unpack or unpack

-- Lo que el addon enseña en la ventana de copiar (la última vez)
local function Capture(HU)
    local c = { text = "" }
    HU.UI.ShowCopy = function(_, title, text) c.title, c.text = title, text end
    return c
end
local function Has(text, s, msg)
    A.truthy(tostring(text):find(s, 1, true), (msg or ("falta «" .. s .. "»")) .. " en:\n" .. tostring(text) .. "\n")
end
local function Lacks(text, s) A.falsy(tostring(text):find(s, 1, true), "sobra «" .. s .. "» en:\n" .. tostring(text) .. "\n") end
-- Lo que el addon escribe en el chat con un /gu
local function Gu(a, input)
    local i0 = #a.w.chat
    a.env.SlashCmdList.HERMANDADUNIDA(input)
    local out = {}
    for i = i0 + 1, #a.w.chat do out[#out + 1] = tostring(a.w.chat[i].msg) end
    return table.concat(out, "\n")
end
local function Near(want, got, msg) A.truthy(type(got) == "number" and math.abs(want - got) < 1e-6, (msg or "") .. " " .. tostring(got)) end

describe("Medidas: CPU del addon según el juego y FPS (Perf.lua)", function()
    it("siempre, una muestra cada 5 s; sin medidor del juego lo dice, y los FPS se miden igual", function()
        local a = F.Community()
        local HU = a.HU
        A.truthy(HU.tasks["cpu-fps"] and HU.tasks["cpu-fps"].n >= 10, "una muestra cada 5 s desde que entró")
        local c = Capture(HU)
        HU:PerfCommand("")
        Has(c.text, "CPU de GuildUnion: sin medidor del juego.")
        Has(c.text, "FPS: ahora 60 · los más bajos en 10 min: 60 (")
        Has(HU:PerfSessionLine(), "CPU del addon según el juego: sin medidor del juego · FPS: ahora 60")
        -- (sin C_AddOnProfiler, lo mismo, aunque el juego tuviera datos)
        a.env.C_AddOnProfiler = false
        a.w.profiler = { app = 20, all = 5, mine = 1 }
        a.w:Advance(5)
        A.is_nil((HU:PerfNow()))
        A.same({}, a:Errors())
    end)

    it("la CPU como la lista de addons del juego: la de ahora, la más alta con su hora y las muestras de 3 % o más", function()
        local a = F.Community()
        local HU = a.HU
        -- (lo del addon frente al juego entero sin los otros addons: 0,42 de 20 - 6 + 0,42 = 2,9 %)
        a.w.profiler = { app = 20, all = 6, mine = 0.42, peak = 12.5, over5 = 7, over10 = 2 }
        a.w:Advance(5)
        Near(100 * 0.42 / 14.42, (HU:PerfNow()), "ahora")
        a.w.profiler.mine = 1
        a.w:Advance(5)
        local peakAt = a.env.date("%H:%M:%S", a.env.time())
        a.w.profiler.mine = 0.2
        a.w:Advance(5)
        local now, max = HU:PerfNow()
        Near(100 * 0.2 / 14.2, now, "ahora")
        Near(100 / 15, max, "la más alta")
        local c = Capture(HU)
        HU:PerfCommand("")
        Has(c.text, "como la lista de addons del juego: ahora 1.4 % · la más alta 6.7 % (" .. peakAt .. ") · muestras de 3 % o más: 1 de 3")
        Has(c.text, "el fotograma más lento del addon 12.5 ms · fotogramas de más de 5 ms: 7 · de más de 10 ms: 2")
        Has(HU:PerfSessionLine(), "según el juego: ahora 1.4 % · la más alta 6.7 % (" .. peakAt .. ") · 1 de 3 muestras de 3 % o más")
        -- (con el medidor de tirones encendido, también)
        HU.Perf.Start()
        Has(HU.Perf.Report(), "la más alta 6.7 % (" .. peakAt .. ")")
        HU.Perf.Stop()
        -- (un dato del juego que no vale, NaN o negativo, no cuenta)
        a.w.profiler = { app = 0 / 0, all = 2, mine = 1 }
        a.w:Advance(5)
        A.is_nil((HU:PerfNow()), "con NaN")
        a.w.profiler = { app = 10, all = 2, mine = -1 }
        a.w:Advance(5)
        A.is_nil((HU:PerfNow()), "con un negativo")
        -- (si el juego apaga su medidor, se dice; lo que ya se ha medido se queda)
        a.w.profiler = nil
        a.w:Advance(5)
        now, max = HU:PerfNow()
        A.is_nil(now)
        Near(100 / 15, max, "la más alta, aún")
        Has(HU:PerfSessionLine(), "según el juego: sin medidor del juego")
        A.same({}, a:Errors())
    end)

    it("los FPS más bajos de los últimos 10 min y de la sesión, con su hora, y la media", function()
        local a = F.Community() -- (12 muestras a 60, en el primer minuto)
        local HU = a.HU
        a.w.fps = 20
        a.w:Advance(5)
        local lowAt = a.env.date("%H:%M:%S", a.env.time())
        a.w.fps = 50
        a.w:Advance(60)
        local _, _, fps, low = HU:PerfNow()
        A.equal(50, fps)
        A.equal(20, low, "el bajón, dentro de los 10 min")
        a.w:Advance(600)
        low = select(4, HU:PerfNow())
        A.equal(50, low, "ya fuera de los 10 min")
        local c = Capture(HU)
        HU:PerfCommand("")
        -- (12 de 60, una de 20 y 132 de 50: 7340 / 145 = 50,6)
        Has(c.text, "FPS: ahora 50 · los más bajos en 10 min: 50 (")
        Has(c.text, " · en la sesión: 20 (" .. lowAt .. ") · media 51")
        A.same({}, a:Errors())
    end)

    it("los mensajes del addon por minuto: los que salen y los que llegan de otros (no los míos de vuelta)", function()
        local a = F.Community()
        local HU = a.HU
        local _, _, _, _, out0 = HU:PerfNow()
        A.truthy(out0, "ya sale algo en el primer minuto (los saludos)")
        for i = 1, 24 do a.w:Receive("HU20", "QZ~" .. i, "GUILD", "Compi-Reino") end
        a.w:Receive("HU20", "QZ~mio", "GUILD", "Tester-Reino")
        for i = 1, 5 do HU:Send("QZ~" .. i, "GUILD") end
        a.w:Advance(60)
        local _, _, _, _, out, inn = HU:PerfNow()
        A.equal(24, inn, "en el último minuto, los 24 de Compi")
        A.truthy(out >= 5, "y salen los míos: " .. tostring(out))
        a.w:Advance(60)
        _, _, _, _, _, inn = HU:PerfNow()
        A.equal(0, inn, "un minuto después, ya no")
        A.same({}, a:Errors())
    end)

    it("en /gu informe, una línea en «== SESIÓN ==»", function()
        local a = F.Community()
        local HU = a.HU
        a.w.profiler = { app = 10, all = 2, mine = 2 }
        a.w.fps = 40
        a.w:Advance(5)
        local c = Capture(HU)
        HU:FullReport()
        a.w:Advance(5)
        local s = c.text:match("== SESIÓN ==(.-)\n==") or ""
        Has(s, "CPU del addon según el juego: ahora 20.0 % · la más alta 20.0 % (")
        Has(s, "FPS: ahora 40 · mín. 10 min 40 (")
        A.same({}, a:Errors())
    end)
end)

describe("Medidas: quién no tiene el addon (/gu sinaddon)", function()
    -- UNO: Ana (oficial) y Alba, Abel (conectado, sin addon) y Aitor (desconectado). DOS: Bea (oficial) y Blas, Bruno
    -- (conectado, sin addon) y Beto (desconectado)
    local function Union()
        local net = red.New({ step = 0.5 })
        local p = {
            ana = net:Player("Ana", "UNO", { rankIndex = 1 }),
            alba = net:Player("Alba", "UNO"),
            aitor = net:Player("Aitor", "UNO"),
            bea = net:Player("Bea", "DOS", { rankIndex = 1 }),
            blas = net:Player("Blas", "DOS"),
            beto = net:Player("Beto", "DOS"),
        }
        -- (conectados sin el addon: salen en la lista de su hermandad, pero no juegan en la red)
        for _, x in ipairs({ { "UNO", "Abel-Reino" }, { "DOS", "Bruno-Reino" } }) do
            local g = net.guilds[x[1]]
            g.members[#g.members + 1] = { name = x[2], rank = "Miembro", rankIndex = 4, online = true }
        end
        for _, n in ipairs({ "ana", "alba", "bea", "blas" }) do net:Login(p[n]) end
        net:Advance(150)
        return net, p
    end

    it("de mi hermandad, los conectados sin el addon; de la otra, lo que veo de sus listas; nunca los desconectados", function()
        local net, p = Union()
        local HU = p.ana.HU
        -- (la lista de todos los conectados de DOS, la de Miembros de la unión: como al mirarla)
        local function Members() HU:WantUnionMembers("DOS"); return #HU:UnionMemberEntries("DOS") == 3 end
        A.truthy(net:AdvanceUntil(Members, 120, 2), "no llega la lista de Miembros de DOS")
        local function ByTag()
            local list, by = HU:WithoutAddon(), {}
            for _, r in ipairs(list) do by[r.tag] = r end
            return by, list
        end
        local by, list = ByTag()
        A.equal("UNO", list[1].tag, "la mía, la primera")
        A.equal(3, by.UNO.online, "Ana, Alba y Abel; Aitor no está")
        A.equal(2, by.UNO.with, "Ana (yo) y Alba")
        A.same({ "Abel Reino" }, by.UNO.without)
        A.equal(3, by.DOS.online, "Bea, Blas y Bruno; Beto no está")
        -- (con las listas sin confirmar, de DOS solo sé de Bea, que me saluda: Blas sale como «sin addon o sin saberlo»)
        A.same({ "Blas Reino", "Bruno Reino" }, by.DOS.without)
        -- (los oficiales confirman las listas, como al montar la comunidad: el saludo de Bea ya vale y nombra a su ayudante)
        p.ana.HU:ConfirmRoster("DOS")
        p.bea.HU:ConfirmRoster("UNO")
        A.truthy(net:AdvanceUntil(function() Members(); return HU.helpers.DOS ~= nil end, 400, 5), "no llega quién ayuda a Bea")
        by = ByTag()
        A.equal(3, by.DOS.online)
        A.equal(2, by.DOS.with, "su enlace y su ayudante")
        A.same({ "Bruno Reino" }, by.DOS.without)
        -- (el comando: la línea corta en el chat y el detalle, con los límites, en la ventana de copiar)
        local c = Capture(HU)
        Has(p.ana:Gu("sinaddon"), "Sin addon, de los conectados que conozco: <UNO> 1 de 3 · <DOS> 1 de 3")
        Has(c.text, "Límites:")
        Has(c.text, "<UNO> (la mía): 3 conectados · con addon 2 · sin addon 1\n  Abel Reino")
        Has(c.text, "<DOS>: 3 conectados que veo · con addon 2 · sin addon o sin saberlo 1\n  Bruno Reino")
        Lacks(c.text, "Aitor")
        Lacks(c.text, "Beto")
        -- (y en /gu informe, la línea corta en «== POR HERMANDAD ==»)
        HU:FullReport()
        net:Advance(5)
        Has(c.text:match("== POR HERMANDAD ==(.-)\n==") or "", "Sin addon, de los conectados que conozco: <UNO> 1 de 3 · <DOS> 1 de 3")
        A.same({}, net:Errors())
    end)

    it("los nombres, ordenados y de ocho en ocho; sin comunidad, lo dice", function()
        local g = F.Guild()
        for _, n in ipairs({ "Zoe", "bruno", "Ana", "Mario", "Luz", "Eva", "Iker", "Olga", "Pau", "Raul" }) do
            g.members[#g.members + 1] = { name = n .. "-Reino", rank = "Miembro", rankIndex = 4 }
        end
        local a = F.Community({ guild = g })
        local c = Capture(a.HU)
        Has(Gu(a, "sinaddon"), "<UNO> 12 de 13")
        Has(c.text, "\n  Ana Reino, bruno Reino, Compi Reino, Eva Reino, Iker Reino, Jefa Reino, Luz Reino, Mario Reino\n"
            .. "  Olga Reino, Pau Reino, Raul Reino, Zoe Reino")
        -- (sin la ventana de copiar, al chat)
        a.HU.UI.ShowCopy = nil
        Has(Gu(a, "sinaddon"), "|r:   Olga Reino, Pau Reino, Raul Reino, Zoe Reino")
        a.HU.cfg = nil
        Has(Gu(a, "sinaddon"), "Aún no hay comunidad")
        A.same({}, a:Errors())
    end)
end)

describe("Medidas: la carga de los enlaces (/gu carga, UQ y UR)", function()
    local INFO3 = table.concat({ F.INFO, "GU:g:Hermandad Tres:TRES" }, "\n")
    local GUILDS3 = { UNO = "Hermandad Uno", DOS = "Hermandad Dos", TRES = "Hermandad Tres" }
    -- UNO: Ana (oficial) y Alba; DOS: Bea (oficial) y Blas; TRES: Tere (oficial) y Toni. low: ese no será el enlace
    local function Union(low)
        local net = red.New({ step = 0.5, info = INFO3, guilds = GUILDS3 })
        local p = {}
        for _, x in ipairs({ { "ana", "Ana", "UNO", 1 }, { "alba", "Alba", "UNO", 4 }, { "bea", "Bea", "DOS", 1 },
            { "blas", "Blas", "DOS", 4 }, { "tere", "Tere", "TRES", 1 }, { "toni", "Toni", "TRES", 4 } }) do
            p[x[1]] = net:Player(x[2], x[3], { rankIndex = x[4] })
        end
        for _, n in ipairs({ "ana", "alba", "bea", "blas", "tere", "toni" }) do
            net:Login(p[n])
            -- (como si estuviera en un campo de batalla: no es el enlace)
            if n == low then p[n].HU.RelayScore = function() return -500 end end
        end
        net:Advance(150)
        return net, p
    end
    -- Los UR que ha mandado ese jugador desde el índice i0 del registro de la red
    local function URs(net, who, i0)
        local out = {}
        for i = (i0 or 0) + 1, #net.log do
            local m = net.log[i]
            if m.from == who and m.text:match("^UR~") then out[#out + 1] = m end
        end
        return out
    end
    local function Row(text, tag) return text:match("\n<" .. tag .. ">[^\n]*") or "" end

    it("un oficial pregunta y los enlaces de las tres hermandades contestan con sus números, sin nombres", function()
        local net, p = Union()
        local HU = p.ana.HU
        A.truthy(HU:IsRelay(), "Ana es el enlace de UNO")
        -- (los oficiales confirman las listas de las otras, como al montar la comunidad: así se sabe de primera mano quién
        -- es el enlace de cada una)
        for _, x in ipairs({ { p.ana, "DOS", "TRES" }, { p.bea, "UNO", "TRES" }, { p.tere, "UNO", "DOS" } }) do
            x[1].HU:ConfirmRoster(x[2])
            x[1].HU:ConfirmRoster(x[3])
        end
        A.truthy(net:AdvanceUntil(function() return HU:KnownRelay("DOS") and HU:KnownRelay("TRES") end, 400, 5),
            "Ana no llega a saber quiénes son los enlaces de DOS y TRES")
        -- (Bea: 20 % de CPU según el juego y 45 FPS; Tere, sin medidor del juego)
        p.bea.w.profiler = { app = 10, all = 2, mine = 2 }
        p.bea.w.fps = 45
        net:Advance(6)
        local c = Capture(HU)
        local i0 = #net.log
        Has(p.ana:Gu("carga"), "preguntado a 2")
        net:Advance(12)
        Has(Row(c.text, "UNO"), "<UNO>  Ana Reino · enlace " .. HU.version .. " · ")
        Has(Row(c.text, "DOS"), "<DOS>  Bea Reino · enlace " .. HU.version .. " · ")
        Has(Row(c.text, "DOS"), " · CPU 20.0 % (pico 20.0 %) · FPS 45 (mín. 10 min 45) · cola ")
        A.truthy(Row(c.text, "DOS"):match("mensajes por minuto: salen %d+, entran %d+$"), Row(c.text, "DOS"))
        Has(Row(c.text, "TRES"), "<TRES>  Tere Reino · enlace " .. HU.version .. " · ")
        Has(Row(c.text, "TRES"), " · CPU sin medidor (pico sin medidor) · FPS 60 (mín. 10 min 60) · ")
        Has(c.text, "Carga de los enlaces: han contestado 3 de 3.")
        -- (las respuestas: una de cada enlace, por susurro, solo números y la versión)
        local urs = {}
        for _, x in ipairs({ p.bea, p.tere }) do
            for _, m in ipairs(URs(net, x, i0)) do urs[#urs + 1] = m end
        end
        A.equal(2, #urs)
        for _, m in ipairs(urs) do
            A.equal("WHISPER", m.dist)
            A.truthy(m.text:match("^UR~%u+~%w+~[%d%.]+~e~%d+~[%d%-]+~[%d%-]+~%d+~%d+~%d+~%d+~%d+$"), m.text)
        end
        A.same({}, net:Errors())
    end)

    it("con las listas sin confirmar no sé de primera mano quién es su enlace: se pregunta a mi mejor contacto", function()
        local net, p = Union()
        local HU = p.ana.HU
        A.is_nil(HU:KnownRelay("DOS"), "sin confirmar")
        local c = Capture(HU)
        Has(p.ana:Gu("carga"), "preguntado a 2")
        net:Advance(12)
        Has(Row(c.text, "DOS"), "<DOS>  Bea Reino · enlace ")
        Has(Row(c.text, "TRES"), "<TRES>  Tere Reino · enlace ")
        A.same({}, net:Errors())
    end)

    it("si el enlace de mi hermandad es otro, también se le pregunta a él", function()
        local net, p = Union("ana")
        local HU = p.ana.HU
        A.falsy(HU:IsRelay(), "Ana no es el enlace")
        A.truthy(p.alba.HU:IsRelay(), "lo es Alba")
        local c = Capture(HU)
        local i0 = #net.log
        p.ana:Gu("carga")
        net:Advance(12)
        Has(Row(c.text, "UNO"), "<UNO>  Alba Reino · enlace ")
        A.equal(1, #URs(net, p.alba, i0), "Alba contesta, una vez")
        A.same({}, net:Errors())
    end)

    it("contesta el enlace o un ayudante; quien no es ninguno de los dos, no", function()
        local net, p = Union()
        local toni = p.toni.HU
        local function InTeam()
            for _, n in ipairs(toni.PackTeams.Mine()) do if toni:Key(n) == toni:MeKey() then return true end end
            return false
        end
        A.falsy(toni:IsRelay())
        A.truthy(InTeam(), "en una hermandad pequeña, Toni es ayudante")
        local i0 = #net.log
        p.toni.w:Receive("HU20", "UQ~UNO~prueba1", "WHISPER", p.ana.full)
        net:Advance(2)
        local got = URs(net, p.toni, i0)
        A.equal(1, #got, "el ayudante contesta")
        A.truthy(got[1].text:match("^UR~TRES~prueba1~[%d%.]+~a~"), got[1].text)
        -- (deja de ser ayudante: ya no contesta, tampoco a otro oficial)
        toni.relayHelpers = nil
        A.falsy(InTeam())
        i0 = #net.log
        p.toni.w:Receive("HU20", "UQ~DOS~prueba2", "WHISPER", p.bea.full)
        net:Advance(2)
        A.equal(0, #URs(net, p.toni, i0))
        A.same({}, net:Errors())
    end)

    it("solo de alguien de la unión y por susurro; a cada uno, una vez cada 30 s, y a todos, con tope", function()
        local g = F.Guild()
        for i = 1, 22 do g.members[#g.members + 1] = { name = "Socio" .. i .. "-Reino", rank = "Miembro", rankIndex = 4 } end
        local a = F.Community({ guild = g }) -- (Tester, el único con el addon: el enlace de UNO)
        local HU = a.HU
        A.truthy(HU:IsRelay())
        local function Answers()
            local out = {}
            for _, m in ipairs(a.w:TakeSent()) do if m.text:match("^UR~") then out[#out + 1] = m end end
            return out
        end
        Answers()
        a.w:Receive("HU20", "UQ~UNO~uno", "WHISPER", "Extra-Reino")   -- (de fuera)
        a.w:Receive("HU20", "UQ~ZZZ~uno", "WHISPER", "Compi-Reino")   -- (una etiqueta que no es de la unión)
        a.w:Receive("HU20", "UQ~DOS~uno", "WHISPER", "Compi-Reino")   -- (de mi hermandad, diciendo ser de DOS)
        a.w:Receive("HU20", "UQ~UNO~uno", "GUILD", "Compi-Reino")     -- (por GUILD)
        a.w:Receive("HU20", "UQ~UNO~a,b", "WHISPER", "Compi-Reino")   -- (un id raro)
        a.w:Advance(1)
        A.equal(0, #Answers(), "ninguna de esas")
        -- (los números no pasan de lo que acepta quien los recibe: 1500 FPS van como 999)
        a.w.fps = 1500
        a.w:Advance(5)
        Answers()
        a.w:Receive("HU20", "UQ~UNO~uno", "WHISPER", "Compi-Reino")
        a.w:Receive("HU20", "UQ~UNO~dos", "WHISPER", "Compi-Reino")
        a.w:Advance(1)
        local got = Answers()
        A.equal(1, #got, "a Compi, una vez")
        A.equal("Compi-Reino", got[1].target)
        -- (sin medidor del juego, la CPU con «-»; los FPS más bajos de los 10 min, los 60 de antes)
        A.truthy(got[1].text:match("^UR~UNO~uno~[%d%.]+~e~%d+~%-~%-~999~60~%d+~%d+~%d+$"), got[1].text)
        a.w:Advance(30)
        a.w:Receive("HU20", "UQ~UNO~tres", "WHISPER", "Compi-Reino")
        a.w:Advance(1)
        A.equal(1, #Answers(), "pasados 30 s, otra vez")
        -- (de 22 a la vez: como mucho 20 en 30 s)
        a.w:Advance(30)
        for i = 1, 22 do a.w:Receive("HU20", "UQ~UNO~s" .. i, "WHISPER", "Socio" .. i .. "-Reino") end
        a.w:Advance(25)
        A.equal(20, #Answers(), "el tope de todos juntos")
        A.same({}, a:Errors())
    end)

    it("quien pregunta: solo los oficiales, una pregunta cada vez y no otra antes de 30 s", function()
        local a = F.Community()
        local HU = a.HU
        local c = Capture(HU)
        a.w.lockdown = true
        Has(Gu(a, "carga"), "Ahora no se pueden mandar mensajes del addon")
        a.w.lockdown = nil
        -- (de UNO, el enlace soy yo: mis números, sin mensajes; de DOS no sé quién es su enlace)
        Has(Gu(a, "carga"), "preguntado a 0")
        Has(Gu(a, "load"), "Ya estás midiendo")
        a.w:Advance(11)
        Has(c.text, "\n<UNO>  Tester Reino · enlace " .. HU.version .. " · ")
        Has(c.text, "\n<DOS>  no sé quién es su enlace")
        Has(c.text, "han contestado 1 de 1.")
        Has(Gu(a, "carga"), "Espera 19 s")
        a.w:Advance(20)
        Has(Gu(a, "carga"), "preguntado a 0")
        -- (sin la ventana de copiar, al chat)
        HU.UI.ShowCopy = nil
        local i0 = #a.w.chat
        a.w:Advance(11)
        local chat = {}
        for i = i0 + 1, #a.w.chat do chat[#chat + 1] = tostring(a.w.chat[i].msg) end
        Has(table.concat(chat, "\n"), "<UNO>  Tester Reino · enlace ")
        a.w:Advance(31)
        local cfg = HU.cfg
        HU.cfg = nil
        Has(Gu(a, "carga"), "Aún no hay comunidad")
        HU.cfg = cfg
        F.Stub(HU, "CanOfficer", false)
        F.Stub(HU, "IsOfficerName", false)
        Has(Gu(a, "carga"), "Solo los oficiales")
        A.same({}, a:Errors())
    end)

    it("solo vale de a quien se preguntó, en esa pregunta y con números que valen: uno raro no entra", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "KnownRelay", function(_, tag) if tag == "DOS" then return { name = "Bea-Reino", tag = "DOS" } end end)
        local c = Capture(HU)
        local function Asked()
            local id
            for _, m in ipairs(a.w:TakeSent()) do id = (m.target == "Bea-Reino" and m.text:match("^UQ~UNO~(%w+)$")) or id end
            return id
        end
        HU:AskRelayLoad()
        local id = Asked()
        A.truthy(id, "ha preguntado a Bea")
        -- versión, papel, minutos, CPU, CPU pico, FPS, FPS más bajos, cola, salen y entran
        local good = { HU.version, "e", "12", "200", "250", "60", "45", "3", "10", "40" }
        local function Reply(i, v, who, tag, rid)
            local f = { unpack(good) }
            if i then f[i] = v end
            a.w:Receive("HU20", "UR~" .. (tag or "DOS") .. "~" .. (rid or id) .. "~" .. table.concat(f, "~"), "WHISPER", who or "Bea-Reino")
        end
        -- (letras, negativos, decimales, hexadecimal, notación científica, de más, vacíos y códigos)
        for _, bad in ipairs({ { 4, "abc" }, { 4, "-5" }, { 4, "2.5" }, { 4, "0x1F" }, { 4, "1e3" }, { 4, "1001" },
            { 6, "1000" }, { 3, "999999" }, { 3, "" }, { 10, "nan" }, { 2, "x" }, { 1, "5.4|cff" } }) do
            Reply(bad[1], bad[2])
        end
        -- (las buenas, pero de quien no se ha preguntado, con la etiqueta de otra hermandad o de otra pregunta)
        Reply(nil, nil, "Blas-Reino")
        Reply(nil, nil, nil, "UNO")
        Reply(nil, nil, nil, nil, "otra")
        a.w:Advance(11)
        Has(Row(c.text, "DOS"), "<DOS>  Bea Reino  ha contestado con números que no valen")
        Has(c.text, "han contestado 1 de 2.")
        -- (la próxima vez, con números buenos, salen tal cual)
        a.w:Advance(30)
        HU:AskRelayLoad()
        id = Asked()
        Reply()
        Reply(4, "999") -- (la segunda ya no cuenta)
        a.w:Advance(11)
        Has(Row(c.text, "DOS"), "<DOS>  Bea Reino · enlace " .. HU.version
            .. " · 12 min · CPU 20.0 % (pico 25.0 %) · FPS 60 (mín. 10 min 45) · cola 3 · mensajes por minuto: salen 10, entran 40")
        -- (y si no contesta, se dice; si no sé quién es su enlace y pregunto a mi mejor contacto, también)
        a.w:Advance(30)
        HU:AskRelayLoad()
        a.w:Advance(11)
        Has(Row(c.text, "DOS"), "<DOS>  Bea Reino  NO HA CONTESTADO")
        F.Stub(HU, "KnownRelay", nil)
        F.Stub(HU, "BestPeer", function(_, tag) if tag == "DOS" then return { name = "Blas-Reino", tag = "DOS" } end end)
        a.w:Advance(30)
        HU:AskRelayLoad()
        a.w:Advance(11)
        Has(Row(c.text, "DOS"), "<DOS>  Blas Reino (un contacto: no sé si es su enlace)  NO HA CONTESTADO")
        A.same({}, a:Errors())
    end)
end)
