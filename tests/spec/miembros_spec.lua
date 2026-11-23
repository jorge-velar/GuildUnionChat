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
    local function GuildWindow(a, withChat)
        local f = a.env.CreateFrame("Frame", "CommunitiesFrame")
        -- (con withChat, también el chat del juego, para la vista de chat)
        if withChat then
            f.Chat = a.env.CreateFrame("Frame", nil, f)
            f.Chat.visible = false
            f.Chat.IsVisible = function(self) return self.visible end
        end
        f.GuildInfoTab = false -- (sin pestañas: la de GuildUnion, BlizzTab.lua, no se monta)
        f.MemberList = a.env.CreateFrame("Frame", nil, f)
        f.MemberList.IsVisible = function() return true end
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

    it("Miembros sale de entrada y tapa la lista del juego: por rango y nivel, con hermandad y nota", function()
        local a = F.Community()
        a.w.guild.members[2].note = "tanque" -- (Compi)
        GuildWindow(a)
        local check, cover = a.env.GuildUnionRosterCheck, a.env.GuildUnionUnionRoster
        A.truthy(check and check:IsShown(), "la casilla «GuildUnion»")
        A.truthy(cover:IsShown(), "al principio, Miembros")
        A.equal(1, cover.tabs.selectedTab)
        A.equal(4, cover.tabs.numTabs)
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        A.matches("Jefa", cover.rows[1].cells.name:GetText())
        A.matches("UNO", cover.rows[1].cells.guild:GetText())
        A.matches("Compi", cover.rows[3].cells.name:GetText())
        A.equal("tanque", cover.rows[3].cells.note:GetText())
        -- (corona para la maestra, espadas para el oficial, nada para el miembro)
        A.truthy(cover.rows[1].cells.rankIcon:IsShown())
        A.truthy(cover.rows[2].cells.rankIcon:IsShown())
        A.falsy(cover.rows[3].cells.rankIcon:IsShown())
        -- (el clic en una fila ha buscado con /who la hermandad que no tiene lista)
        cover.rows[1]:GetScript("OnClick")(cover.rows[1], "LeftButton")
        A.same({ 'g-"Hermandad Dos"' }, a.w.whoSent)
        a.w.who = { BEA }
        a.w:Fire("WHO_LIST_UPDATE")
        A.matches("Bea", cover.rows[4].cells.name:GetText())
        A.equal("30", cover.rows[4].cells.level:GetText())
        A.equal("Ventormenta", cover.rows[4].cells.zone:GetText())
        A.matches("DOS", cover.rows[4].cells.guild:GetText())
        A.matches("4 conectados", cover.status:GetText())
        Click("GuildUnionRosterCheck", a)
        A.falsy(cover:IsShown(), "casilla quitada: la del juego, tal cual")
        A.truthy(a.HU.db.unionRosterOff, "y se recuerda")
        Click("GuildUnionRosterCheck", a)
        A.truthy(cover:IsShown(), "puesta otra vez: Miembros")
        A.falsy(a.HU.db.unionRosterOff)
        A.same({}, a:Errors())
    end)

    it("un clic en un título ordena por esa columna; otro, al revés; el tercero, como al principio", function()
        local a = F.Community()
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        local name = cover.hdr -- (los títulos no tienen nombre: se buscan por el texto)
        local byName
        for _, fr in ipairs(a.w.frames) do
            if fr._parent == name and fr:GetText() == "Nombre" then byName = fr end
        end
        A.truthy(byName, "el título «Nombre»")
        byName:GetScript("OnClick")(byName)
        A.matches("Compi", cover.rows[1].cells.name:GetText())
        byName:GetScript("OnClick")(byName)
        A.matches("Tester", cover.rows[1].cells.name:GetText())
        byName:GetScript("OnClick")(byName)
        A.matches("Jefa", cover.rows[1].cells.name:GetText())
        A.same({}, a:Errors())
    end)

    it("los oficiales de las otras hermandades salen con su rango (la lista que mandan solas, RB)", function()
        local a = F.Community()
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        a.HU.remoteRoster.DOS = { members = {
            { name = "Lord-Reino", online = true, rankIndex = 1, rank = "Oficial", class = "MAGE", level = 60, zone = "Ventormenta" },
            { name = "Fuera-Reino", online = false, rankIndex = 1, rank = "Oficial", class = "MAGE", level = 60 },
        } }
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        -- (Jefa 0; luego los de rango 1, por nombre: Lord antes que Tester; el desconectado no sale)
        A.matches("Lord", cover.rows[2].cells.name:GetText())
        A.equal("Oficial", cover.rows[2].cells.rank:GetText())
        A.matches("DOS", cover.rows[2].cells.guild:GetText())
        A.truthy(cover.rows[2].cells.rankIcon:IsShown())
        for i = 1, 6 do A.falsy((cover.rows[i].cells.name:GetText() or ""):find("Fuera", 1, true)) end
        A.same({}, a:Errors())
    end)

    it("clic izquierdo: la ficha (nuestra) con hermandad, rango, nota y profesiones; otro clic la cierra", function()
        local a = F.Community()
        a.w.guild.members[2].note = "tanque" -- (Compi)
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        local row = cover.rows[3]
        A.matches("Compi", row.cells.name:GetText())
        row:GetScript("OnClick")(row, "LeftButton")
        local card = a.env.GuildUnionMemberCard
        A.truthy(card and card:IsShown(), "la ficha")
        A.matches("Compi", card.title:GetText())
        A.matches("UNO", card.lines[1]:GetText())
        A.equal("Miembro", card.lines[3]:GetText())
        A.equal("—", card.lines[5]:GetText(), "sin profesiones que dé el juego")
        A.equal("tanque", card.lines[6]:GetText())
        row:GetScript("OnClick")(row, "LeftButton")
        A.falsy(card:IsShown())
        A.same({}, a:Errors())
    end)

    it("varios a la vez: Ctrl suma uno, Mayús elige del último al de ahora", function()
        local a = F.Community()
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        local r = cover.rows
        r[1]:GetScript("OnClick")(r[1], "LeftButton")
        A.truthy(r[1].selTex:IsShown()); A.falsy(r[2].selTex:IsShown())
        a.env.IsControlKeyDown = function() return true end
        r[3]:GetScript("OnClick")(r[3], "LeftButton")
        A.truthy(r[1].selTex:IsShown()); A.falsy(r[2].selTex:IsShown()); A.truthy(r[3].selTex:IsShown())
        a.env.IsControlKeyDown = function() return false end
        a.env.IsShiftKeyDown = function() return true end
        r[1]:GetScript("OnClick")(r[1], "LeftButton")
        A.truthy(r[1].selTex:IsShown()); A.truthy(r[2].selTex:IsShown()); A.truthy(r[3].selTex:IsShown())
        A.same({}, a:Errors())
    end)

    it("clic derecho en uno de mi hermandad: cambiar rango y echar, por la ventana de órdenes", function()
        local a = F.Community()
        local HU = a.HU
        GuildWindow(a)
        F.Stub(HU, "CanPromote", true); F.Stub(HU, "CanDemote", true); F.Stub(HU, "CanKickGuild", true)
        local sent = {}
        F.Stub(HU, "TypeLines", function(_, macro, title) sent[#sent + 1] = { macro = macro, title = title } end)
        local extra
        HU.PlayerMenu = function(_, _, fn) extra = fn end
        local cover = a.env.GuildUnionUnionRoster
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        local row = cover.rows[3]
        A.matches("Compi", row.cells.name:GetText())
        row:GetScript("OnClick")(row, "RightButton")
        A.truthy(extra, "el menú trae las opciones de hermandad")
        -- (un menú de mentira que recuerda sus botones)
        local function Menu()
            local m = { items = {} }
            function m:CreateButton(text, fn) local sub = Menu(); sub.text, sub.fn = text, fn; self.items[#self.items + 1] = sub; return sub end
            function m:CreateTitle() end
            function m:CreateDivider() end
            return m
        end
        local root = Menu()
        extra(root)
        local rankMenu, kick = root.items[1], root.items[2]
        A.equal("Cambiar rango", rankMenu.text)
        rankMenu.items[4].fn() -- (Veterano: índice 3, Compi está en el 4)
        A.matches("/gpromote Compi", sent[1].macro)
        kick.fn()
        A.matches("/gremove Compi", sent[2].macro)
        A.same({}, a:Errors())
    end)

    it("en la vista de chat: Chat primero; Members…Bank pasan a la vista de miembros con esa sección", function()
        local a = F.Community()
        local f = GuildWindow(a, true)
        local cover = a.env.GuildUnionUnionRoster
        f.MemberList.ShowOfflineButton.visible = false
        f.Chat.visible = true
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        A.truthy(cover:IsShown(), "la fila de botones")
        A.equal(0, cover.tabs.selectedTab, "empieza en Chat")
        A.truthy(cover.tabs.chatBtn:IsShown())
        A.falsy(cover.hdr:IsShown(), "sin lista: se ve el chat del juego")
        A.falsy(cover.tabs.Tabs[1]:IsShown(), "los nuestros, fuera: van los seguros")
        A.falsy(a.env.GuildUnionRosterCheck:IsShown(), "la casilla solo en la vista de miembros")
        -- (pulsar Trade en el chat: el botón seguro apunta la sección y el juego pasa a la vista de miembros)
        local trade = cover.tabs.chatModeBtns[2]
        trade:GetScript("PreClick")(trade)
        f.Chat.visible = false
        f.MemberList.ShowOfflineButton.visible = true
        f.MemberList.ShowOfflineButton:GetScript("OnShow")()
        a.w:Advance(0.1)
        A.equal(2, cover.tabs.selectedTab, "abre Trade")
        A.truthy(cover.trade:IsShown())
        A.truthy(cover.tabs.Tabs[1]:IsShown())
        A.falsy(cover.tabs.chatBtn:IsShown())
        -- (en la vista de miembros, «Chat» es el botón seguro que pulsa el icono del chat del juego)
        A.truthy(cover.tabs.chatSecure:IsShown())
        local check = a.env.GuildUnionRosterCheck
        check:GetScript("OnClick")(check)
        A.falsy(cover.tabs.chatSecure:IsShown(), "con la casilla quitada, fuera")
        A.same({}, a:Errors())
    end)

    it("la ficha enseña la nota de oficial, pero no las líneas de configuración del addon", function()
        local a = F.Community()
        a.w.guild.members[2].officerNote = "tanque principal"
        a.w.guild.members[3].officerNote = "vieja GU:zz secreta"
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        local function Card(i)
            local row = cover.rows[i]
            row:GetScript("OnClick")(row, "LeftButton")
            return a.env.GuildUnionMemberCard
        end
        A.equal("tanque principal", Card(3).lines[7]:GetText())
        local c = Card(1)
        A.matches("Jefa", c.title:GetText())
        A.falsy(c.lines[7]:GetText():find("secreta", 1, true))
        A.same({}, a:Errors())
    end)

    it("Comercio (Trade.lua): solicitudes públicas y privadas, mías en azul, con modo prueba", function()
        local a = F.Community()
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        local t2 = cover.tabs.Tabs[2]
        t2:GetScript("OnClick")(t2)
        local tr = cover.trade
        A.truthy(tr:IsShown(), "la sección Comercio")
        tr.testBtn:GetScript("OnClick")(tr.testBtn)
        local function Count()
            local n = 0
            for _, r in ipairs(tr.rows) do if r:IsShown() and r.entry then n = n + 1 end end
            return n
        end
        A.equal(4, Count(), "públicas: 4")
        local mine
        for _, r in ipairs(tr.rows) do if r.entry and r.entry.who == a.HU:Me() then mine = r end end
        A.matches("4da6ff", mine.cells[1]:GetText(), "la mía, en azul")
        A.falsy(mine.accept:IsShown(), "la mía: sin Aceptar")
        A.truthy(mine.cancel:IsShown(), "la mía: Cancelar")
        local priv = tr.viewBtns.priv
        priv:GetScript("OnClick")(priv)
        A.equal(3, Count(), "en Privado: la que me piden y las dos mías")
        -- (Aceptar una pública de otro: sigue en Público con mi nombre, y sale en mi Privado)
        local pub = tr.viewBtns.pub
        pub:GetScript("OnClick")(pub)
        local other
        for _, r in ipairs(tr.rows) do if r.entry and r.entry.state == "open" and r.entry.who ~= a.HU:Me() then other = r end end
        A.truthy(other.accept:IsShown())
        other.accept:GetScript("OnClick")(other.accept)
        A.equal(4, Count(), "sigue en Público")
        A.truthy(other.actText:IsShown(), "con el nombre de quien la aceptó")
        priv:GetScript("OnClick")(priv)
        A.equal(4, Count(), "y en mi Privado")
        pub:GetScript("OnClick")(pub)
        -- (al buscar, la lista pasa a ser la de quién lo tiene: en el WoW de mentira, nadie)
        tr.search:SetText("Alquimia")
        tr.search:GetScript("OnTextChanged")(tr.search)
        A.equal(0, Count())
        A.truthy(tr.empty:IsShown())
        A.falsy(tr.chat:IsShown(), "sin chat al buscar")
        A.same({}, a:Errors())
    end)

    it("Comercio, Calendario y Banco: «próximamente», sin lista", function()
        local a = F.Community()
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        local t2 = cover.tabs.Tabs[3]
        t2:GetScript("OnClick")(t2)
        A.equal(3, cover.tabs.selectedTab)
        A.truthy(cover.soon:IsShown())
        A.falsy(cover.hdr:IsShown())
        A.matches("Próximamente", cover.soon:GetText())
        local t1 = cover.tabs.Tabs[1]
        t1:GetScript("OnClick")(t1)
        A.falsy(cover.soon:IsShown())
        A.truthy(cover.hdr:IsShown())
        A.same({}, a:Errors())
    end)

    it("fuera de la vista de miembros no sale nada; al volver, la casilla manda", function()
        local a = F.Community()
        local f = GuildWindow(a)
        f.MemberList.ShowOfflineButton.visible = false
        f.MemberList.ShowOfflineButton:GetScript("OnHide")()
        a.w:Advance(0.1)
        A.falsy(a.env.GuildUnionRosterCheck:IsShown())
        A.falsy(a.env.GuildUnionUnionRoster:IsShown())
        f.MemberList.ShowOfflineButton.visible = true
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        A.truthy(a.env.GuildUnionUnionRoster:IsShown(), "por defecto, puesta")
        Click("GuildUnionRosterCheck", a)
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        A.falsy(a.env.GuildUnionUnionRoster:IsShown(), "quitada, sigue quitada al volver a abrir")
    end)

    it("sin separar por hermandad: los del /who, sin rango, se mezclan por nivel con el rango más bajo", function()
        local a = F.Community()
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        cover.rows[1]:GetScript("OnClick")(cover.rows[1], "LeftButton")
        a.w.who = { { fullName = "Alta-Reino", fullGuildName = "Hermandad Dos", level = 61, filename = "MAGE", area = "Ventormenta" } }
        a.w:Fire("WHO_LIST_UPDATE")
        -- (Jefa 0, Tester 1, y en el rango más bajo, Alta (61) antes que Compi (60))
        A.matches("Alta", cover.rows[3].cells.name:GetText())
        A.matches("Compi", cover.rows[4].cells.name:GetText())
        A.same({}, a:Errors())
    end)
end)

describe("El chat de la ventana de hermandad del juego sigue el formato de Ajustes (BlizzTab.lua)", function()
    it("punto o etiqueta, como diga db.chatMark", function()
        local a = F.Community()
        local HU = a.HU
        HU.db.chatMark = "dot"
        local head = HU:FormatLineParts("main", "DOS", "Bea-Reino", "hola", nil, "blizz")
        A.truthy(head:find("dot:0:0", 1, true), "el punto")
        HU.db.chatMark = "tag"
        head = HU:FormatLineParts("main", "DOS", "Bea-Reino", "hola", nil, "blizz")
        A.falsy(head:find("dot:0:0", 1, true), "sin punto")
        A.truthy(head:find("DOS", 1, true), "la etiqueta")
        A.same({}, a:Errors())
    end)
end)

describe("Registro (InviteLog.lua): invitaciones y salidas", function()
    it("guarda quién se fue y a quién echaron, aparte de las invitaciones", function()
        local a = F.Community()
        local HU = a.HU
        local EV = {
            { "invite", "Jefa", "Nuevo", nil, 0, 0, 1, 0 },
            { "quit", "Viejo", nil, nil, 0, 0, 2, 0 },
            { "remove", "Jefa", "Malo", nil, 0, 0, 0, 3 },
        }
        a.env.GetNumGuildEvents = function() return #EV end
        a.env.GetGuildEventInfo = function(i) return unpack(EV[i]) end
        a.w:Fire("GUILD_EVENT_LOG_UPDATE")
        local inv, out
        for _, l in pairs(HU.db.inviteLog or {}) do inv = l end
        for _, l in pairs(HU.db.leaveLog or {}) do out = l end
        A.equal(1, #inv)
        A.equal(2, #out)
        local byWho = {}
        for _, e in ipairs(out) do byWho[e.who:match("^([^-]+)")] = e end
        A.falsy(byWho.Viejo.by, "se fue él")
        A.matches("Jefa", byWho.Malo.by, "lo echó la Jefa")
        -- (otra vez lo mismo: no se repite)
        a.w:Fire("GUILD_EVENT_LOG_UPDATE")
        A.equal(2, #out)
        A.same({}, a:Errors())
    end)
end)

describe("Solicitudes (InviteLog.lua): otra hermandad pide echar a alguien de la mía", function()
    it("se guardan, se cuentan, y aceptar abre la ventana de órdenes con el /gremove", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "CanKickGuild", true)
        HU:AddKickRequest({ id = "k1", target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = time() })
        HU:AddKickRequest({ id = "k1", target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = time() })
        A.equal(1, HU:KickRequestCount(), "sin repetidas")
        local job, answered
        F.Stub(HU, "RunOrders", function(_, j) job = j end)
        F.Stub(HU, "AnswerKick", function(_, r, ok) answered = { r = r, ok = ok } end)
        HU:ShowRequests()
        local win = a.env.GuildUnionRequestsFrame
        win.Refresh()
        win.rows[1]:GetScript("OnClick")(win.rows[1])
        win.accept:GetScript("OnClick")(win.accept)
        A.matches("/gremove Compi", job.lines[1])
        job.onDone(1)
        A.truthy(answered.ok)
        A.equal(0, HU:KickRequestCount(), "contestada: fuera de la lista")
        -- (y queda en el registro de salidas, con quién lo pidió)
        local out
        for _, l in pairs(HU.db.leaveLog or {}) do out = l end
        A.truthy(out and out[1], "apuntada en Salidas")
        A.equal("Bea-Reino", out[1].req)
        A.same({}, a:Errors())
    end)

    it("solo salen las que puedo hacer: subir a oficial, no, si yo soy oficial", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "CanPromote", true); F.Stub(HU, "CanDemote", true)
        -- (yo, Tester, soy oficial (rango 1); Compi es miembro (4))
        HU:AddKickRequest({ id = "r1", kind = "rank", rank = 1, target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = time() })
        A.equal(0, HU:KickRequestCount(), "a oficial: no la puedo dar")
        HU:AddKickRequest({ id = "r2", kind = "rank", rank = 3, target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = time() })
        A.equal(1, HU:KickRequestCount(), "a veterano: sí")
        A.same({}, a:Errors())
    end)

    it("modo prueba: solicitudes de mentira; el tic y la X las quitan sin mandar nada", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "CanKickGuild", true)
        local sent = 0
        F.Stub(HU, "RunOrders", function() sent = sent + 1 end)
        F.Stub(HU, "AnswerKick", function() sent = sent + 1 end)
        HU:ShowRequests()
        local win = a.env.GuildUnionRequestsFrame
        win.test:GetScript("OnClick")(win.test)
        A.equal(5, HU:KickRequestCount(), "3 de echar y 2 de rango")
        win.Refresh()
        win.rows[1].yes:GetScript("OnClick")(win.rows[1].yes)
        A.equal(4, HU:KickRequestCount())
        win.Refresh()
        win.rows[1].no:GetScript("OnClick")(win.rows[1].no)
        A.equal(3, HU:KickRequestCount())
        -- (el filtro de rango enseña solo las 2 de rango)
        local tr = win.tabs.rank
        tr:GetScript("OnClick")(tr)
        A.matches("Cuatro", win.rows[1].cells[3]:GetText() .. win.rows[2].cells[3]:GetText())
        A.equal(0, sent, "las de prueba no mandan nada")
        A.same({}, a:Errors())
    end)
end)
