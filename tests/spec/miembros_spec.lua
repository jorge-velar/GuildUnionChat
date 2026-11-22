-- Miembros de la unión (UnionMembers.lua): todos los conectados de otra hermandad, que se piden al
-- mirarlos (MP) y llegan en trozos (ML), solo para verlos
local red = require("lib.red")
local F = require("lib.fixtures")
local A = assert_

-- Los nombres (cortos) de una lista de filas
local function Names(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = (e.name:match("^([^-]+)")) end
    table.sort(out)
    return out
end

-- Lo que han mandado los de esa hermandad desde i0: los ML por susurro, { [destino] = n }, y sus ids
local function SentML(net, tag, i0)
    local byTarget, ids, n = {}, {}, 0
    for i = i0 or 1, #net.log do
        local m = net.log[i]
        if m.from.tag == tag and m.dist == "WHISPER" and m.text:match("^ML~") then
            n = n + 1
            local k = m.target:lower()
            byTarget[k] = (byTarget[k] or 0) + 1
            ids[m.text:match("^ML~[^~]*~([^~]*)")] = true
        end
    end
    return n, byTarget, ids
end

-- La ventana abierta: cada 2 s pide lo que haga falta (como la pestaña)
local function Look(net, p, tag, cond, max)
    local t = 0
    while t < (max or 120) do
        p.HU:WantUnionMembers(tag)
        if cond() then return t end
        net:Advance(2)
        t = t + 2
    end
    return cond() and t or nil
end

-- UNO: Ana (oficial) y Alba; DOS: Bea (oficial) y tres miembros, con zona y nivel; Beto, desconectado
local function Union(opts)
    opts = opts or {}
    local net = red.New()
    local p = {
        ana = net:Player("Ana", "UNO", { rankIndex = 1, ref = opts.unoRef }),
        alba = net:Player("Alba", "UNO"),
        bea = net:Player("Bea", "DOS", { rankIndex = 1, ref = opts.dosRef }),
        blas = net:Player("Blas", "DOS", { ref = opts.dosRef }),
        bruno = net:Player("Bruno", "DOS", { ref = opts.dosRef }),
        berta = net:Player("Berta", "DOS", { ref = opts.dosRef }),
        beto = net:Player("Beto", "DOS"),
    }
    for i, n in ipairs({ "bea", "blas", "bruno", "berta" }) do
        p[n].member.zone = "Zona " .. i
        p[n].member.level = 20 + i
    end
    for _, n in ipairs({ "ana", "alba", "bea", "blas", "bruno", "berta" }) do net:Login(p[n]) end
    net:Advance(opts.secs or 90)
    return net, p
end

describe("Miembros de la unión", function()
    it("quien mira ve a todos los conectados de la otra hermandad, y su hermandad también", function()
        local net, p = Union()
        local function Got(x) return #x.HU:UnionMemberEntries("DOS") == 4 end
        A.truthy(Look(net, p.alba, "DOS", function() return Got(p.alba) and Got(p.ana) end, 120), "no ha llegado la lista")
        A.same({ "Bea", "Berta", "Blas", "Bruno" }, Names(p.alba.HU:UnionMemberEntries("DOS")), "sin Beto, que no está")
        local blas
        for _, e in ipairs(p.ana.HU:UnionMemberEntries("DOS")) do if e.name:match("^Blas") then blas = e end end
        A.equal("Zona 2", blas.zone)
        A.equal(22, blas.level)
        A.equal(4, blas.ri)
        A.equal("Bea", Names(p.alba.HU:UnionMemberEntries("DOS"))[1], "el oficial, el primero")
        A.matches("^hace %d+ s$", p.alba.HU:UnionMembersStatus("DOS"))
        A.same({}, net:Errors(), "errores")
    end)

    it("dos que miran a la vez: la otra hermandad la manda una sola vez", function()
        local net, p = Union()
        local i0 = #net.log + 1
        local function Both()
            return #p.ana.HU:UnionMemberEntries("DOS") == 4 and #p.alba.HU:UnionMemberEntries("DOS") == 4
        end
        local t = 0
        while t < 120 and not Both() do
            p.ana.HU:WantUnionMembers("DOS"); p.alba.HU:WantUnionMembers("DOS")
            net:Advance(2); t = t + 2
        end
        A.truthy(Both(), "no ha llegado a los dos")
        local _, byTarget, ids = SentML(net, "DOS", i0)
        local targets, nids = 0, 0
        for _ in pairs(byTarget) do targets = targets + 1 end
        for _ in pairs(ids) do nids = nids + 1 end
        A.equal(1, targets, "una sola lista, a uno de UNO")
        A.equal(1, nids)
    end)

    it("«todas»: de una en una, y llegan todas", function()
        local net, p = Union()
        A.truthy(Look(net, p.alba, nil, function() return #p.alba.HU:UnionMemberEntries() == 4 end, 120))
        A.same({}, net:Errors(), "errores")
    end)

    it("la otra hermandad con la versión de antes: no contesta y no rompe nada", function()
        local net, p = Union({ dosRef = "v5.4.41" })
        local done = Look(net, p.alba, "DOS", function() return p.alba.HU:UnionMembersStatus("DOS"):find("no contesta", 1, true) ~= nil end, 300)
        A.truthy(done, "estado: " .. p.alba.HU:UnionMembersStatus("DOS"))
        A.same({}, p.alba.HU:UnionMemberEntries("DOS"))
        A.same({}, net:Errors(), "errores")
    end)

    it("en la otra hermandad solo la tiene su maestro, que no es su enlace: se le acaba preguntando", function()
        -- (lo visto en el juego el 22/11: en WLP3 el enlace y sus ayudantes, contactos con la 5.4.43,
        -- iban siempre los primeros; el maestro, con la copia nueva, nunca llegaba a preguntarse)
        local net = red.New()
        local p = {
            ana = net:Player("Ana", "UNO", { rankIndex = 1 }),
            alba = net:Player("Alba", "UNO"),
            boss = net:Player("Boss", "DOS", { rankIndex = 0 }),
        }
        local old = {}
        for i, n in ipairs({ "Blas", "Bruno", "Berta", "Bego", "Benito" }) do
            old[i] = net:Player(n, "DOS", { rankIndex = 4, ref = "v5.4.43" })
        end
        for _, x in ipairs({ p.ana, p.alba }) do net:Login(x) end
        for _, x in ipairs(old) do net:Login(x) end
        net:Login(p.boss)
        -- (el maestro no es el enlace: como si estuviera en un campo de batalla)
        p.boss.HU.RelayScore = function() return -500 end
        net:Advance(120)
        A.falsy(p.boss.HU:IsRelay(), "el maestro no tiene que ser el enlace")
        -- (y Alba los tiene de contactos, con su versión, como en el juego)
        for _, x in ipairs(old) do
            p.alba.HU.remote[x.key] = { name = x.full, tag = "DOS", ver = "5.4.43", last = p.alba.env.GetTime() }
        end
        A.truthy(Look(net, p.alba, "DOS", function() return #p.alba.HU:UnionMemberEntries("DOS") == 6 end, 180),
            "estado: " .. p.alba.HU:UnionMembersStatus("DOS"))
        A.same({}, net:Errors(), "errores")
    end)

    it("el enlace de mi hermandad con la versión de antes: la pido yo y me llega", function()
        local net, p = Union({ unoRef = "v5.4.41" })
        A.truthy(Look(net, p.alba, "DOS", function() return #p.alba.HU:UnionMemberEntries("DOS") == 4 end, 150),
            "estado: " .. p.alba.HU:UnionMembersStatus("DOS"))
        A.same({}, net:Errors(), "errores")
    end)
end)

describe("Miembros de la unión: seguridad y topes", function()
    -- MP por susurro a Bea (DOS), como si lo mandara `from`
    local function Ask(net, p, from)
        p.bea.w:Fire("CHAT_MSG_ADDON", "HU20", "MP~UNO~DOS", "WHISPER", from, nil, nil, 0, "")
        net:Advance(5)
    end

    it("a un desconocido no se le contesta; a uno de la comunidad, sí", function()
        local net, p = Union()
        local i0 = #net.log + 1
        Ask(net, p, "Extraño-Reino")
        A.equal(0, (SentML(net, "DOS", i0)))
        Ask(net, p, p.alba.full)
        local _, byTarget = SentML(net, "DOS", i0)
        A.truthy(byTarget[p.alba.key], "a Alba sí")
    end)

    it("a cada uno, una lista por minuto; y como mucho 3 por minuto en total", function()
        local net, p = Union()
        -- (cuatro que piden, conectados: a un desconectado el susurro no sale)
        p.bea.HU.Vouched = function() return true end
        local one, two, three, four = p.ana, p.alba, p.blas, p.bruno
        local i0 = #net.log + 1
        Ask(net, p, one.full)
        Ask(net, p, one.full)
        local _, byTarget = SentML(net, "DOS", i0)
        A.equal(1, byTarget[one.key], "la segunda, no")
        Ask(net, p, two.full); Ask(net, p, three.full); Ask(net, p, four.full)
        _, byTarget = SentML(net, "DOS", i0)
        A.truthy(byTarget[two.key] and byTarget[three.key], "la 2.ª y la 3.ª")
        A.equal(nil, byTarget[four.key], "la 4.ª en el mismo minuto, no")
        net:Advance(61)
        Ask(net, p, four.full)
        _, byTarget = SentML(net, "DOS", i0)
        A.truthy(byTarget[four.key], "pasado el minuto, sí")
    end)

    it("una lista que no he pedido no se guarda", function()
        local net, p = Union()
        p.alba.w:Fire("CHAT_MSG_ADDON", "HU20B", "ML~DOS~zz~1~1~Falso,1,60,4,", "WHISPER", p.bea.full, nil, nil, 0, "")
        net:Advance(1)
        A.same({}, p.alba.HU:UnionMemberEntries("DOS"))
    end)

    it("por GUILD, con enlace conocido, solo de quien reparte por mi hermandad", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "KnownGuildRelay", true)
        F.Stub(HU, "IsGuildForwarder", false)
        a.w:Receive("HU20B", "ML~DOS~zz~1~1~Falso,1,60,4,", "GUILD", "Compi-Reino")
        A.same({}, HU:UnionMemberEntries("DOS"))
        F.Stub(HU, "IsGuildForwarder", true)
        a.w:Receive("HU20B", "ML~DOS~zz~1~1~Falso,1,60,4,", "GUILD", "Compi-Reino")
        A.same({ "Falso" }, Names(HU:UnionMemberEntries("DOS")))
        -- (ni de mi propia hermandad ni de una que no es de la comunidad)
        a.w:Receive("HU20B", "ML~UNO~zz~1~1~Otro,1,60,4,", "GUILD", "Compi-Reino")
        a.w:Receive("HU20B", "ML~TRES~zz~1~1~Otro,1,60,4,", "GUILD", "Compi-Reino")
        A.same({}, HU:UnionMemberEntries("UNO"))
        A.same({}, a:Errors())
    end)
end)

describe("Miembros de la unión: trozos", function()
    local function Lines(n)
        local out = {}
        for i = 1, n do
            -- (zonas de hasta 24 letras, unas repetidas; algunos ausentes)
            local zone = (i % 7 == 0) and "" or ("Zona larguísima núm " .. (i % 13))
            out[i] = table.concat({ "Personaje" .. i, i % 12, 1 + i % 60, i % 10, zone }, ",") .. (i % 5 == 0 and ",a" or "")
        end
        return out
    end

    it("200 conectados: cada mensaje cabe, y llegan todos con su zona", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "IsGuildForwarder", true)
        local chunks = HU.PackMembers(Lines(200))
        A.truthy(#chunks > 5)
        for i, c in ipairs(chunks) do
            local msg = table.concat({ "ML", "DOS", "abcdefg", i, #chunks, c }, "~")
            A.truthy(#msg <= 255, "trozo " .. i .. ": " .. #msg .. " bytes")
        end
        -- (sin el trozo 2: lo que llega se enseña ya, cada uno con su zona)
        for i, c in ipairs(chunks) do
            if i ~= 2 then a.w:Receive("HU20B", table.concat({ "ML", "DOS", "id1", i, #chunks, c }, "~"), "GUILD", "Compi-Reino") end
        end
        local partial = HU:UnionMemberEntries("DOS")
        A.truthy(#partial > 150 and #partial < 200)
        for _, e in ipairs(partial) do A.falsy(e.zone and e.zone:match("^#"), e.name .. ": " .. tostring(e.zone)) end
        A.matches("^llegando %d+/%d+$", HU:UnionMembersStatus("DOS"))
        a.w:Receive("HU20B", table.concat({ "ML", "DOS", "id1", 2, #chunks, chunks[2] }, "~"), "GUILD", "Compi-Reino")
        local all = HU:UnionMemberEntries("DOS")
        A.equal(200, #all)
        local byName = {}
        for _, e in ipairs(all) do byName[e.name:match("^([^-]+)")] = e end
        A.equal("Zona larguísima núm 1", byName.Personaje1.zone)
        A.equal(true, byName.Personaje5.afk)
        A.equal("", byName.Personaje7.zone or "")
    end)

    it("una lista vacía es un trozo vacío, y una vieja deja de enseñarse a los 10 min", function()
        local a = F.Community()
        local HU = a.HU
        A.same({ "" }, HU.PackMembers({}))
        F.Stub(HU, "IsGuildForwarder", true)
        a.w:Receive("HU20B", "ML~DOS~id1~1~1~Uno,1,60,4,", "GUILD", "Compi-Reino")
        A.equal(1, #HU:UnionMemberEntries("DOS"))
        a.w:Advance(601)
        A.same({}, HU:UnionMemberEntries("DOS"))
    end)
end)

describe("Miembros de la unión: con /who", function()
    local function Who(a, rows, total)
        a.w.who, a.w.whoTotal = rows, total
        a.w:Fire("WHO_LIST_UPDATE")
    end
    local BEA = { fullName = "Bea-Reino", fullGuildName = "Hermandad Dos", level = 30, filename = "MAGE", area = "Ventormenta" }

    it("busca por el nombre de la hermandad y enseña los que son de ella", function()
        local a = F.Community()
        local HU = a.HU
        A.truthy(HU:WhoUnionMembers("DOS"))
        A.same({ 'g-"Hermandad Dos"' }, a.w.whoSent)
        A.equal("buscando con /who…", HU:UnionMembersStatus("DOS"))
        Who(a, { BEA, { fullName = "Otro-Reino", fullGuildName = "Hermandad Dosmil", level = 10, filename = "ROGUE", area = "" } })
        local list = HU:UnionMemberEntries("DOS")
        A.same({ "Bea" }, Names(list), "solo los de Hermandad Dos")
        A.equal(30, list[1].level)
        A.equal("MAGE", list[1].class)
        A.equal("Ventormenta", list[1].zone)
        A.equal("", list[1].rank, "el /who no trae el rango")
        A.matches("^con /who, hace %d+ s$", HU:UnionMembersStatus("DOS"))
        A.same({}, a:Errors())
    end)

    it("si el juego no los da todos, lo dice", function()
        local a = F.Community()
        a.HU:WhoUnionMembers("DOS")
        Who(a, { BEA }, 80)
        A.matches("%(1 de 80%)", a.HU:UnionMembersStatus("DOS"))
    end)

    it("un /who que no he pedido yo (o que llega tarde) no se toma", function()
        local a = F.Community()
        Who(a, { BEA })
        A.same({}, a.HU:UnionMemberEntries("DOS"))
        a.HU:WhoUnionMembers("DOS")
        a.w:Advance(20)
        Who(a, { BEA })
        A.same({}, a.HU:UnionMemberEntries("DOS"))
    end)

    it("ni de mi hermandad ni de una que no es de la comunidad", function()
        local a = F.Community()
        A.falsy(a.HU:WhoUnionMembers("UNO"))
        A.falsy(a.HU:WhoUnionMembers("TRES"))
        A.same({}, a.w.whoSent)
    end)

    it("si llega la lista de Miembros, se enseña esa (trae los rangos)", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "IsGuildForwarder", true)
        HU:WhoUnionMembers("DOS")
        Who(a, { BEA })
        a.w:Receive("HU20B", "ML~DOS~id1~1~1~Blas,1,60,4,", "GUILD", "Compi-Reino")
        A.same({ "Blas" }, Names(HU:UnionMemberEntries("DOS")))
        A.matches("^hace %d+ s$", HU:UnionMembersStatus("DOS"))
    end)
end)

describe("Miembros de la unión: la pestaña", function()
    local function Click(b, ...) return b:GetScript("OnClick")(b, ...) end

    it("«Miembros» pide la lista, la enseña al llegar y vuelve a «Oficiales»", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "IsGuildForwarder", true)
        HU:OpenMainWindow()
        local panel = a.env.GuildUnionReducePanel
        A.truthy(panel:IsShown())
        Click(panel.memBtn)
        A.truthy(panel.memPick:IsShown())
        A.equal("Todas", panel.memPick:GetText())
        A.falsy(panel.whoBtn:IsShown(), "con «Todas» no hay /who")
        -- (sin el menú del juego, cada clic elige la siguiente hermandad)
        Click(panel.memPick)
        A.equal("DOS", panel.memPick:GetText())
        A.truthy(panel.whoBtn:IsShown())
        a.w:Receive("HU20B", "ML~DOS~id1~1~1~Blas,1,60,4,Ventormenta", "GUILD", "Compi-Reino")
        A.matches("Blas", panel.offRows[1].name:GetText())
        A.matches("DOS", panel.memStatus:GetText())
        panel.offRows[1]:GetScript("OnEnter")(panel.offRows[1])
        -- (cada 2 s se mira si toca pedirla otra vez)
        panel:GetScript("OnUpdate")(panel, 3)
        Click(panel.whoBtn)
        A.same({ 'g-"Hermandad Dos"' }, a.w.whoSent)
        Click(panel.offBtn)
        A.falsy(panel.memPick:IsShown())
        A.same({}, a:Errors())
    end)
    it("solo se enseñan las filas que caben en la ventana (antes las últimas se salían por debajo)", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "IsGuildForwarder", true)
        HU:OpenMainWindow()
        local panel = a.env.GuildUnionReducePanel
        Click(panel.memBtn)
        local rows = {}
        for i = 1, 10 do rows[i] = "Uno" .. string.char(96 + i) .. ",1,60,4," end
        a.w:Receive("HU20B", "ML~DOS~id1~1~1~" .. table.concat(rows, ";"), "GUILD", "Compi-Reino")
        -- (la lista mide lo que caben 5 filas y un poco)
        panel.offScroll.GetHeight = function() return 5 * 18 + 7 end
        panel.offScroll:GetScript("OnSizeChanged")(panel.offScroll)
        local shown = 0
        for i, row in ipairs(panel.offRows) do
            if row:IsShown() then shown = shown + 1; A.truthy(i <= 5, "la fila " .. i .. " no cabe") end
        end
        A.equal(5, shown)
        A.same({}, a:Errors())
    end)
end)

describe("Miembros de la unión: /who al hacer clic y sin la ventana del juego", function()
    local BEA = { fullName = "Bea-Reino", fullGuildName = "Hermandad Dos", level = 30, filename = "MAGE", area = "Ventormenta" }
    -- (una ventana del juego que escucha el /who, como la de búsqueda)
    local function GameWindow(a)
        local win = { opened = 0 }
        win.f = a.env.CreateFrame("Frame", "VentanaDeBusqueda")
        win.f:RegisterEvent("WHO_LIST_UPDATE")
        win.f:SetScript("OnEvent", function() win.opened = win.opened + 1 end)
        return win
    end

    it("un clic busca con /who la hermandad que no tiene lista; no más de uno cada 5 s", function()
        local a = F.Community()
        local HU = a.HU
        A.truthy(HU:UnionWhoTick(nil))
        A.same({ 'g-"Hermandad Dos"' }, a.w.whoSent)
        a.w.who = { BEA }
        a.w:Fire("WHO_LIST_UPDATE")
        A.falsy(HU:UnionWhoTick(nil), "con un /who reciente, no")
        a.w:Advance(61)
        A.truthy(HU:UnionWhoTick("DOS"), "pasado el minuto, otra vez")
        A.falsy(HU:UnionWhoTick("DOS"), "pero no dos seguidos")
    end)

    it("con la lista de Miembros no hace falta /who", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "IsGuildForwarder", true)
        a.w:Receive("HU20B", "ML~DOS~id1~1~1~Blas,1,60,4,", "GUILD", "Compi-Reino")
        A.falsy(HU:UnionWhoTick(nil))
        A.same({}, a.w.whoSent)
    end)

    it("la ventana del juego no se entera de MI /who, y luego vuelve a escuchar", function()
        local a = F.Community()
        local HU = a.HU
        local win = GameWindow(a)
        HU:WhoUnionMembers("DOS")
        A.falsy(win.f._events.WHO_LIST_UPDATE, "mientras espero, no escucha")
        A.truthy(HU.eventFrame._events.WHO_LIST_UPDATE, "el addon sí")
        a.w.who = { BEA }
        a.w:Fire("WHO_LIST_UPDATE")
        A.equal(0, win.opened, "no se ha abierto")
        A.same({ "Bea" }, Names(HU:UnionMemberEntries("DOS")))
        a.w:Advance(0.1)
        A.truthy(win.f._events.WHO_LIST_UPDATE, "vuelve a escuchar")
        -- (un /who escrito a mano: la ventana se abre como siempre)
        a.w:Fire("WHO_LIST_UPDATE")
        A.equal(1, win.opened)
    end)

    it("si la respuesta no llega, la ventana vuelve a escuchar a los 15 s", function()
        local a = F.Community()
        local win = GameWindow(a)
        a.HU:WhoUnionMembers("DOS")
        A.falsy(win.f._events.WHO_LIST_UPDATE)
        a.w:Advance(16)
        A.truthy(win.f._events.WHO_LIST_UPDATE)
    end)

    it("en la pestaña basta con abrir «Miembros»: busca sola con /who", function()
        local a = F.Community()
        local HU = a.HU
        HU:OpenMainWindow()
        local panel = a.env.GuildUnionReducePanel
        panel.memBtn:GetScript("OnClick")(panel.memBtn)
        A.same({ 'g-"Hermandad Dos"' }, a.w.whoSent)
        a.w.who = { BEA }
        a.w:Fire("WHO_LIST_UPDATE")
        A.matches("Bea", panel.offRows[1].name:GetText())
        -- (un clic en la lista, pasado el minuto, la refresca)
        a.w:Advance(61)
        panel:GetScript("OnMouseDown")(panel)
        A.equal(2, #a.w.whoSent)
        A.same({}, a:Errors())
    end)
end)

describe("«Unión» en la lista de miembros del juego (UnionRoster.lua)", function()
    local BEA = { fullName = "Bea-Reino", fullGuildName = "Hermandad Dos", level = 30, filename = "MAGE", area = "Ventormenta" }
    -- (la ventana de hermandad del juego, lo justo: su lista de miembros con la casilla de desconectados)
    local function GuildWindow(a)
        local f = a.env.CreateFrame("Frame", "CommunitiesFrame")
        f.GuildInfoTab = false -- (sin pestañas: la de GuildUnion, BlizzTab.lua, no se monta)
        f.MemberList = a.env.CreateFrame("Frame", nil, f)
        local chk = a.env.CreateFrame("CheckButton", nil, f.MemberList)
        f.MemberList.ShowOfflineButton = chk
        chk.visible = true
        chk.IsVisible = function(self) return self.visible end
        a.w:Fire("ADDON_LOADED", "Blizzard_Communities")
        return f
    end
    local function Click(name, a) local b = a.env[name]; return b:GetScript("OnClick")(b, "LeftButton") end

    it("todos juntos: primero mi hermandad, por rango, y luego las otras", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "IsGuildForwarder", true)
        a.w:Receive("HU20B", "ML~DOS~id1~1~1~Blas,1,60,4,Ventormenta", "GUILD", "Compi-Reino")
        local list = HU:UnionRosterEntries()
        local names = {}
        for i, e in ipairs(list) do names[i] = e.name:match("^([^-]+)") .. "/" .. e.tag end
        A.same({ "Jefa/UNO", "Tester/UNO", "Compi/UNO", "Blas/DOS" }, names)
        A.truthy(list[1].own)
        A.falsy(list[4].own)
    end)

    it("el interruptor sale en la vista de miembros; «Unión» tapa la lista del juego con la de todos", function()
        local a = F.Community()
        local HU = a.HU
        GuildWindow(a)
        local switch, cover = a.env.GuildUnionRosterSwitch, a.env.GuildUnionUnionRoster
        A.truthy(switch and switch:IsShown(), "el interruptor")
        A.falsy(cover:IsShown(), "al principio, la del juego")
        Click("GuildUnionRosterUnion", a)
        A.truthy(cover:IsShown())
        A.matches("Jefa", cover.rows[1].cells[1]:GetText())
        A.matches("Hermandad Uno", cover.rows[1].cells[5]:GetText())
        -- (el clic ha buscado con /who la hermandad que no tiene lista)
        A.same({ 'g-"Hermandad Dos"' }, a.w.whoSent)
        a.w.who = { BEA }
        a.w:Fire("WHO_LIST_UPDATE")
        A.matches("Bea", cover.rows[4].cells[1]:GetText())
        A.equal("30", cover.rows[4].cells[2]:GetText())
        A.equal("Ventormenta", cover.rows[4].cells[3]:GetText())
        A.matches("4 conectados", cover.status:GetText())
        cover.rows[1]:GetScript("OnClick")(cover.rows[1], "LeftButton")
        Click("GuildUnionRosterGuild", a)
        A.falsy(cover:IsShown(), "«Mi hermandad»: la del juego, tal cual")
        A.same({}, a:Errors())
    end)

    it("fuera de la vista de miembros no sale nada", function()
        local a = F.Community()
        local f = GuildWindow(a)
        Click("GuildUnionRosterUnion", a)
        f.MemberList.ShowOfflineButton.visible = false
        f.MemberList.ShowOfflineButton:GetScript("OnHide")()
        a.w:Advance(0.1)
        A.falsy(a.env.GuildUnionRosterSwitch:IsShown())
        A.falsy(a.env.GuildUnionUnionRoster:IsShown())
        -- (y al volver, sigue en «Unión»)
        f.MemberList.ShowOfflineButton.visible = true
        f.MemberList.ShowOfflineButton:GetScript("OnShow")()
        a.w:Advance(0.1)
        A.truthy(a.env.GuildUnionUnionRoster:IsShown())
    end)
end)
