-- Medidas, para encontrar picos y no para crearlos: la CPU del addon según el juego y los FPS, siempre (Perf.lua);
-- quién de mi hermandad no tiene el addon (/gu sinaddon, preguntando a cada uno) y la carga de los enlaces (/gu carga, UQ y UR; Report.lua)
local red = require("lib.red")
local F = require("lib.fixtures")
local A = assert_
local unpack = table.unpack or unpack

-- Lo que el addon enseña en la ventana de copiar (la última vez)
local function Capture(HU)
    local c = { text = "" }
    HU.UI.ShowCopy = function(_, title, text, opts) c.title, c.text, c.opts = title, text, opts end
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

describe("Medidas: quién de mi hermandad no tiene el addon (/gu sinaddon, preguntando a cada uno)", function()
    -- UNO: Ana (oficial, la que mira), Alba (con la 5.4.43 de CurseForge) y Aitor (desconectado); conectados sin el
    -- addon: Abel (en Orgrimmar), Bruno (en un campo de batalla), Carla (se va a mitad), Dani (con el móvil) y Eli (en
    -- Núcleo de Magma). DOS: Bea, que no cuenta
    local function Union()
        local net = red.New({ step = 0.5 })
        local p = {
            ana = net:Player("Ana", "UNO", { rankIndex = 1 }),
            alba = net:Player("Alba", "UNO", { ref = "v5.4.43" }),
            aitor = net:Player("Aitor", "UNO"),
            bea = net:Player("Bea", "DOS", { rankIndex = 1 }),
        }
        local g, extra = net.guilds.UNO, {}
        for _, x in ipairs({ { "Abel", "Orgrimmar" }, { "Bruno", "Garganta Grito de Guerra" }, { "Carla", "Durotar" },
            { "Dani", "", true }, { "Eli", "Núcleo de Magma" } }) do
            local m = { name = x[1] .. "-Reino", rank = "Miembro", rankIndex = 4, online = true, zone = x[2], mobile = x[3] }
            g.members[#g.members + 1] = m
            extra[x[1]] = m
        end
        for _, n in ipairs({ "ana", "alba", "bea" }) do net:Login(p[n]) end
        net:Advance(150)
        return net, p, extra
    end
    -- (las preguntas que he mandado, por nombre, con su hora)
    local function Asked(net, from)
        local out = {}
        for _, m in ipairs(net.log) do
            local who = m.from == from and m.dist == "GUILD" and m.text:match("^PG~(.+)$")
            if who then out[who] = out[who] or {}; table.insert(out[who], m.t) end
        end
        return out
    end

    it("a cada conectado, tres preguntas, una cuando ha salido la anterior; «sin addon», solo quien no contesta a ninguna; «no se sabe», quien se va, está en una instancia o con el móvil", function()
        local net, p, extra = Union()
        local HU = p.ana.HU
        -- (el nombre de Núcleo de Magma, el que da el juego por su número)
        p.ana.w.zoneNames = { [409] = "Núcleo de Magma" }
        -- (Alba no me ha saludado: lo sé porque contesta a la pregunta, también con la 5.4.43)
        HU.guildPeers["alba-reino"] = nil
        local c = Capture(HU)
        A.equal("Sin addon: sin mirar (/gu sinaddon, unos 5 minutos).", HU:WithoutAddonLine())
        -- (cuándo entra cada pregunta en la cola: una, solo cuando ha salido la anterior y ha pasado 1 s)
        local enq, send = {}, HU.Send
        HU.Send = function(hu, msg, ...)
            if msg:match("^PG~") then enq[#enq + 1] = p.ana.env.GetTime() end
            return send(hu, msg, ...)
        end
        local t0 = net.now
        Has(p.ana:Gu("sinaddon"), "les pregunto a los 6 conectados, uno a uno y tres veces. Tarda unos 3 minutos; te aviso al acabar.")
        Has(p.ana:Gu("sinaddon"), "Ya lo estoy mirando: faltan unos 3 minutos.")
        A.equal("Sin addon: lo estoy mirando (/gu sinaddon).", HU:WithoutAddonLine())
        -- (a mitad, Carla se va)
        net:Advance(60)
        extra.Carla.online = false
        p.ana.w:Fire("GUILD_ROSTER_UPDATE")
        local took = net:AdvanceUntil(function() return c.text ~= "" end, 400, 1)
        A.truthy(took, "no acaba")
        A.truthy(net.now - t0 >= 120 and net.now - t0 <= 400, "lo que tarda: " .. tostring(net.now - t0))
        -- (Abel, tres preguntas, separadas; Alba contestó a la primera; a Carla, ya ida, no se le pregunta más)
        local asked = Asked(net, p.ana)
        A.equal(3, #asked["Abel-Reino"], "Abel, tres veces")
        local ab = asked["Abel-Reino"]
        A.truthy(ab[2] - ab[1] >= 60 and ab[3] - ab[2] >= 60, "una vuelta tras otra")
        A.truthy(#(asked["Alba-Reino"] or {}) <= 1, "Alba contesta a la primera")
        A.truthy(#asked["Carla-Reino"] < 3, "a Carla, ida, no se le pregunta más")
        A.is_nil(asked["Aitor-Reino"], "a los desconectados, nada")
        A.is_nil(asked["Bea-Reino"], "a los de otras hermandades, nada")
        A.equal(15, #enq, "6 + 5 + 4 preguntas")
        for i = 2, #enq do A.truthy(enq[i] - enq[i - 1] >= 1 - 1e-6, "uno a uno, al ritmo de la cola: " .. tostring(enq[i] - enq[i - 1])) end
        HU.Send = send
        local pa = false
        for _, m in ipairs(net.log) do if m.from == p.alba and m.text:match("^PA$") then pa = true end end
        A.truthy(pa, "la 5.4.43 de Alba contesta con PA")
        -- (el resultado: la línea en el chat y el detalle en la ventana de copiar)
        local now = p.ana.env.date("%H:%M", p.ana.env.time())
        local line = "Sin addon en <UNO> (mirado a las " .. now .. "): 1 de 6 conectados · no se sabe 4"
        A.equal(line, HU:WithoutAddonLine())
        Has(c.text, "<UNO>: 6 conectados · con addon 1 · sin addon 1 · no se sabe 4\n\nSin addon: no han contestado a ninguna de las tres preguntas")
        Has(c.text, ":\n  Abel Reino  ·  Orgrimmar\n\nNo se sabe (vuelve a mirarlo más tarde):\n"
            .. "  Bruno Reino: en Garganta Grito de Guerra: ahí no le deja contestar\n"
            .. "  Carla Reino: se ha desconectado\n"
            .. "  Dani Reino: con la aplicación del móvil\n"
            .. "  Eli Reino: en Núcleo de Magma: ahí no le deja contestar")
        Lacks(c.text, "Alba")
        Lacks(c.text, "Aitor")
        Lacks(c.text, "Bea")
        -- (y en /gu informe, la línea corta en «== POR HERMANDAD ==»)
        HU:FullReport()
        net:Advance(5)
        Has(c.text:match("== POR HERMANDAD ==(.-)\n==") or "", line)
        A.same({}, net:Errors())
    end)

    it("con la cola llena (recién entrado al juego), las preguntas esperan a salir: no se amontonan y nadie que lo tiene sale «sin addon»", function()
        local net, p = Union()
        local HU = p.ana.HU
        HU.guildPeers["alba-reino"] = nil
        -- (40 mensajes delante: la cola manda uno por segundo, así que la primera pregunta sale a los ~35 s)
        for i = 1, 40 do HU:Send("ZZ~" .. i, "GUILD") end
        local c = Capture(HU)
        local t0 = net.now
        p.ana:Gu("sinaddon")
        A.truthy(net:AdvanceUntil(function() return c.text ~= "" end, 600, 1), "no acaba")
        local asked = Asked(net, p.ana)
        local first = math.huge
        for _, ts in pairs(asked) do first = math.min(first, ts[1]) end
        A.truthy(first - t0 >= 30, "la primera, tras los 40 de delante: " .. tostring(first - t0))
        A.equal(1, #(asked["Alba-Reino"] or {}), "a Alba, una vez: contestó")
        A.equal(3, #asked["Abel-Reino"], "Abel, tres veces")
        -- (aquí Carla no se va y Núcleo de Magma no está en los mapas: Carla y Eli, también «sin addon»)
        Has(c.text, "<UNO>: 6 conectados · con addon 1 · sin addon 3 · no se sabe 2")
        Has(c.text, ":\n  Abel Reino  ·  Orgrimmar\n  Carla Reino  ·  Durotar\n  Eli Reino  ·  Núcleo de Magma\n\n")
        A.same({}, net:Errors())
    end)

    it("una pregunta que no llega a salir no cuenta: quien no ha recibido las tres sale en «no se sabe», nunca en «sin addon»", function()
        local a = F.Community()
        local HU = a.HU
        local c = Capture(HU)
        Has(Gu(a, "sinaddon"), "les pregunto a los 2 conectados")
        -- (desde aquí el juego no deja salir nada: lo que entra en la cola se pierde)
        local send = a.env.C_ChatInfo.SendAddonMessage
        a.env.C_ChatInfo.SendAddonMessage = function() error("no sale") end
        a.w:Advance(1000)
        a.env.C_ChatInfo.SendAddonMessage = send
        Has(HU:WithoutAddonLine(), "0 de 2 conectados · no se sabe 2")
        Has(c.text, "  Compi Reino: no le he podido preguntar las tres veces\n  Jefa Reino: no le he podido preguntar las tres veces")
        A.same({}, a:Errors())
    end)

    -- Lo que escribe en el chat desde i0
    local function Said(a, i0)
        local out = {}
        for i = i0 + 1, #a.w.chat do out[#out + 1] = tostring(a.w.chat[i].msg) end
        return table.concat(out, "\n")
    end

    it("seguro o nada: con GU:v puesto, en un campo de batalla o sin hermandad no mira; si a mitad entro en uno, para", function()
        local a = F.Community()
        local HU = a.HU
        HU.guildMin = "5.4.40"
        Has(Gu(a, "sinaddon"), "Así no es seguro: la Información de la hermandad tiene GU:v:5.4.40 y el addon de quien tenga una versión anterior está en pausa y no contesta.")
        HU.guildMin = nil
        a.w.lockdown = true
        Has(Gu(a, "sinaddon"), "Ahora no se puede: el juego no deja mandar nada (campo de batalla). Prueba al salir.")
        a.w.lockdown = false
        Has(Gu(a, "sinaddon"), "les pregunto a los 2 conectados")
        a.w:Advance(30)
        local i0 = #a.w.chat
        a.w.lockdown = true
        a.w:Advance(120)
        Has(Said(a, i0), "He parado de mirar quién tiene el addon: ahora el juego no deja mandar nada (campo de batalla).")
        A.equal("Sin addon: sin mirar (/gu sinaddon, unos 5 minutos).", HU:WithoutAddonLine(), "sin resultado")
        -- (al salir, otra vez; y si me quedo sin nadie más conectado o sin hermandad, lo dice)
        a.w.lockdown = false
        Has(Gu(a, "sinaddon"), "les pregunto a los 2 conectados")
        for _, m in ipairs(a.w.guild.members) do if m.name ~= "Tester-Reino" then m.online = false end end
        a.w:Fire("GUILD_ROSTER_UPDATE")
        a.w:Advance(400)
        Has(HU:WithoutAddonLine(), "0 de 2 conectados · no se sabe 2")
        a.w:Fire("GUILD_ROSTER_UPDATE")
        a.w:Advance(5)
        Has(Gu(a, "sinaddon"), "No hay nadie más de tu hermandad conectado.")
        a.w.guild = nil
        Has(Gu(a, "sinaddon"), "No estás en una hermandad.")
        A.same({}, a:Errors())
    end)

    it("sin nadie que conteste, todos «sin addon», con su zona; un nombre que el juego da para cualquier número no es una instancia; sin la ventana de copiar, al chat", function()
        local a = F.Community()
        local HU = a.HU
        for _, m in ipairs(a.w.guild.members) do if m.name == "Compi-Reino" then m.zone = "Orgrimmar" end end
        a.w:Fire("GUILD_ROSTER_UPDATE")
        a.w:Advance(5)
        a.w.zoneNames = setmetatable({}, { __index = function() return "Orgrimmar" end })
        HU.UI.ShowCopy = nil
        Has(Gu(a, "sinaddon"), "les pregunto a los 2 conectados")
        local i0 = #a.w.chat
        a.w:Advance(400)
        local out = Said(a, i0)
        Has(out, "Sin addon en <UNO> (mirado a las ")
        Has(out, "): 2 de 2 conectados · no se sabe 0")
        Has(out, "|r:   Compi Reino  ·  Orgrimmar")
        Has(out, "|r:   Jefa Reino")
        Lacks(out, "No se sabe (vuelve")
        A.same({}, a:Errors())
    end)

    it("las mazmorras del mapa del juego, también las nuevas de Forever, son instancias; las zonas, no", function()
        local a = F.Community()
        local HU = a.HU
        a.w.maps = { { mapID = 1429, name = "Elwynn Forest", mapType = 3 }, { mapID = 2207, name = "Cripta Nueva", mapType = 4 } }
        for _, m in ipairs(a.w.guild.members) do
            if m.name == "Compi-Reino" then m.zone = "Cripta Nueva" elseif m.name == "Jefa-Reino" then m.zone = "Elwynn Forest" end
        end
        a.w:Fire("GUILD_ROSTER_UPDATE")
        a.w:Advance(5)
        local c = Capture(HU)
        Gu(a, "sinaddon")
        a.w:Advance(400)
        Has(c.text, "<UNO>: 2 conectados · con addon 0 · sin addon 1 · no se sabe 1")
        Has(c.text, ":\n  Jefa Reino  ·  Elwynn Forest\n")
        Has(c.text, "  Compi Reino: en Cripta Nueva: ahí no le deja contestar")
        A.same({}, a:Errors())
    end)

    it("el botón «Echar (N)»: a los «sin addon» que mi rango deja, nunca a los de «no se sabe», y por tandas con su «Sí»", function()
        local g = F.Guild()
        for i = 1, 11 do g.members[#g.members + 1] = { name = "Personaje" .. i .. "-Apellidolargo", rank = "Miembro", rankIndex = 4 } end
        g.members[#g.members + 1] = { name = "Dani-Reino", rank = "Miembro", rankIndex = 4, mobile = true }
        local a = F.Community({ guild = g })
        local HU = a.HU
        a.env.CanGuildRemove = function() return true end
        local c = Capture(HU)
        Gu(a, "sinaddon")
        a.w:Advance(900)
        -- (Jefa es la maestra: no la puedo echar; Dani, con el móvil, es «no se sabe»)
        A.equal("Echar (12)", c.opts and c.opts.button)
        local jobs = {}
        HU.RunOrders = function(_, j) jobs[#jobs + 1] = j end
        local i0 = #a.w.chat
        c.opts.onClick()
        A.truthy(#jobs >= 2, "por tandas")
        local all = {}
        for _, j in ipairs(jobs) do
            A.truthy(#table.concat(j.lines, "\n") <= 250, "cada tanda cabe en una macro")
            A.truthy(j.quiet, "sin el aviso de la cola en cada tanda")
            for _, l in ipairs(j.lines) do all[#all + 1] = l end
        end
        A.equal(12, #all)
        local text = table.concat(all, "\n")
        Has(text, "/gremove Compi Reino")
        Has(text, "/gremove Personaje11 Apellidolargo")
        Lacks(text, "Jefa")
        Lacks(text, "Dani")
        Has(Said(a, i0), "Son 12: te lo pregunto en " .. #jobs .. " tandas; pulsa «Sí» en cada una.")
        -- (ya echados, el botón no tiene a nadie)
        for k = #a.w.guild.members, 1, -1 do
            if a.w.guild.members[k].rankIndex == 4 then table.remove(a.w.guild.members, k) end
        end
        a.w:Fire("GUILD_ROSTER_UPDATE")
        a.w:Advance(60)
        local i1, n = #a.w.chat, #jobs
        c.opts.onClick()
        Has(Said(a, i1), "No queda nadie de la lista que puedas echar.")
        A.equal(n, #jobs, "ninguna tanda más")
        A.same({}, a:Errors())
    end)

    it("«Echar a varios» (Oficiales): los nombres pegados; de lo copiado de /gu sinaddon, solo los «sin addon»; solo los de la hermandad que mi rango deja", function()
        local g = F.Guild()
        for _, n in ipairs({ "Abel", "Bruno", "Carla" }) do g.members[#g.members + 1] = { name = n .. "-Reino", rank = "Miembro", rankIndex = 4 } end
        local a = F.Community({ guild = g })
        local HU = a.HU
        a.env.CanGuildRemove = function() return true end
        local jobs = {}
        HU.RunOrders = function(_, j) jobs[#jobs + 1] = j end
        -- (lo que se copia de la ventana de /gu sinaddon, con Jefa (la maestra), Zoe (no está) y Abel dos veces)
        local pasted = table.concat({
            "Guild Union 5.4.43.336 - quién no tiene el addon - 25/11/2026 18:29",
            "<UNO>: 6 conectados · con addon 1 · sin addon 4 · no se sabe 1",
            "",
            "Sin addon: no han contestado a ninguna de las tres preguntas (el addon contesta solo):",
            "  Abel Reino  ·  Orgrimmar",
            "  Carla-Reino",
            "  Jefa Reino  ·  Ventormenta",
            "  Zoe Reino  ·  Durotar",
            "  Abel Reino",
            "",
            "No se sabe (vuelve a mirarlo más tarde):",
            "  Bruno Reino: se ha desconectado",
        }, "\r\n")
        local i0 = #a.w.chat
        HU:MassKick(pasted)
        local said = Said(a, i0)
        A.equal(1, #jobs, "una tanda")
        A.same({ "/gremove Abel Reino", "/gremove Carla Reino" }, jobs[1].lines)
        Has(said, "No están en la hermandad: Zoe Reino")
        Has(said, "Tu rango no deja echarlos: Jefa Reino")
        Lacks(said, "Bruno")
        -- (la ventana: se puede escribir en ella y «Echar» lo manda)
        HU:ShowMassKick()
        local f = HU.UI.copyFrame
        A.equal("Echar", f.extra:GetText())
        f.edit:SetText("Bruno Reino")
        f.edit:GetScript("OnTextChanged")(f.edit, true)
        A.equal("Bruno Reino", f.edit:GetText(), "lo escrito se queda")
        f.onExtra(f)
        A.same({ "/gremove Bruno Reino" }, jobs[2].lines)
        -- (la de copiar de siempre no se deja cambiar)
        HU.UI:ShowCopy("t", "fijo")
        f.edit:SetText("otro")
        f.edit:GetScript("OnTextChanged")(f.edit, true)
        A.equal("fijo", f.edit:GetText())
        -- (sin nadie que se pueda echar, o sin permiso, lo dice)
        local i1 = #a.w.chat
        HU:MassKick("Zoe Reino")
        Has(Said(a, i1), "No hay nadie que puedas echar en esa lista.")
        a.env.CanGuildRemove = function() return false end
        local i2 = #a.w.chat
        HU:MassKick("Abel Reino")
        Has(Said(a, i2), "No tienes permiso para expulsar de la hermandad.")
        A.equal(2, #jobs, "sin permiso, nada")
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
