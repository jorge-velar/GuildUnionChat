-- Miembros de la unión (UnionMembers.lua): todos los conectados de otra hermandad, que se piden al
-- mirarlos (MP) y llegan en trozos (ML), solo para verlos
local red = require("lib.red")
local F = require("lib.fixtures")
local runner = require("lib.runner")
local A = assert_
local unpack = table.unpack or unpack

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

-- (la ventana de hermandad del juego, lo justo: su lista de miembros con la casilla de desconectados)
local function GuildWindow(a, withChat, setup)
    local f = a.env.CreateFrame("Frame", "CommunitiesFrame")
    -- (con withChat, también el chat del juego, para la vista de chat)
    if withChat then
        f.Chat = a.env.CreateFrame("Frame", nil, f)
        f.Chat.visible = false
        f.Chat.IsVisible = function(self) return self.visible end
    else
        f.Chat = false
    end
    f.GuildInfoTab = false -- (sin pestañas: la de GuildUnion, BlizzTab.lua, no se monta)
    -- (las pestañas Chat y Miembros de la derecha: la de Miembros, pulsada en su vista, vuelve a Miembros)
    f.ChatTab = a.env.CreateFrame("CheckButton", nil, f)
    f.RosterTab = a.env.CreateFrame("CheckButton", nil, f)
    f.CommunitiesControlFrame = false -- (sin «Ajustes de hermandad»: los botones de abajo, en su prueba)
    f.CommunitiesList = a.env.CreateFrame("Frame", nil, f) -- (la columna de comunidades: la fila se ata a ella)
    f.MemberList = a.env.CreateFrame("Frame", nil, f)
    f.MemberList.IsVisible = function() return true end
    local chk = a.env.CreateFrame("CheckButton", nil, f.MemberList)
    f.MemberList.ShowOfflineButton = chk
    chk.visible = true
    chk.IsVisible = function(self) return self.visible end
    -- (setup: más piezas de la ventana del juego, antes de que el addon la monte)
    if setup then setup(f) end
    a.w:Fire("ADDON_LOADED", "Blizzard_Communities")
    return f
end

-- Abrir una sección como el jugador: Comercio y Eventos, con su pestaña de la derecha (el botón seguro pulsa la
-- pestaña de miembros del juego: aquí, ya en esa vista, la abre su PostClick); Miembros, con la pestaña de miembros del
-- juego
local function Section(a, i)
    local cover = a.env.GuildUnionUnionRoster
    if i == 1 then
        local rt = a.env.CommunitiesFrame.RosterTab
        return rt:GetScript("OnClick")(rt)
    end
    for _, b in ipairs(cover.side.tabs) do
        if b.tab == i then
            b:GetScript("PreClick")(b)
            return b:GetScript("PostClick")(b)
        end
    end
    error("sin pestaña para la sección " .. i)
end

-- Lo escrito en el chat desde la línea `from`
local function Chat(a, from)
    local out = {}
    for i = (from or 0) + 1, #a.w.chat do out[#out + 1] = tostring(a.w.chat[i].msg) end
    return table.concat(out, "\n")
end

-- Un menú de clic derecho de mentira (el del juego, MenuUtil): recuerda sus botones
local function FakeMenu()
    local m = { items = {} }
    function m:CreateButton(text, fn) local sub = FakeMenu(); sub.text, sub.fn = text, fn; self.items[#self.items + 1] = sub; return sub end
    function m:CreateTitle() end
    function m:CreateDivider() end
    return m
end
-- (el botón de ese menú cuyo texto lleva `text`)
local function MenuItem(m, text)
    for _, it in ipairs(m.items) do if it.text and it.text:find(text, 1, true) then return it end end
end

describe("«Unión» en la lista de miembros del juego (UnionRoster.lua)", function()
    local BEA = { fullName = "Bea-Reino", fullGuildName = "Hermandad Dos", level = 30, filename = "MAGE", area = "Ventormenta" }
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
        local mine, cover = a.env.GuildUnionRosterMine, a.env.GuildUnionUnionRoster
        A.falsy(a.env.GuildUnionRosterCheck, "sin casilla «GuildUnion»: lo nuestro siempre puesto")
        A.truthy(mine and mine:IsShown(), "«Solo mi hermandad», en Miembros")
        A.truthy(cover:IsShown(), "al principio, Miembros")
        A.equal(1, cover.tabs.selectedTab)
        A.same({ "Profesiones y comercio", "Eventos" }, { cover.side.tabs[1].tooltip, cover.side.tabs[2].tooltip },
            "Comercio y Eventos (hasta el 25/11, Calendario), pestañas de la derecha")
        A.same({ a.env.GuildUnionTradeTab, a.env.GuildUnionCalendarTab }, cover.side.tabs)
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
        -- («Solo mi hermandad»: lo nuestro fuera y la lista del juego a la vista —su ficha guarda las notas—; se
        -- recuerda; quitada, vuelve lo nuestro con toda la unión)
        mine.GetChecked = function() return true end
        Click("GuildUnionRosterMine", a)
        A.truthy(a.HU.db.unionRosterMine, "se recuerda")
        A.falsy(cover:IsShown(), "la lista del juego, sin tapar")
        A.truthy(mine:IsShown(), "la casilla sigue, para volver")
        mine.GetChecked = function() return false end
        Click("GuildUnionRosterMine", a)
        A.falsy(a.HU.db.unionRosterMine)
        A.truthy(cover:IsShown(), "lo nuestro, otra vez")
        A.matches("Bea", cover.rows[4].cells.name:GetText(), "con los de las otras hermandades")
        A.same({}, a:Errors())
    end)

    it("«Solo mi hermandad» se recuerda: Miembros abre con la lista del juego; Comercio, con lo nuestro", function()
        local a = F.Community()
        a.HU.db.unionRosterMine = true
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        A.falsy(cover:IsShown(), "Miembros: la lista del juego")
        A.truthy(a.env.GuildUnionRosterMine:IsShown())
        A.same({}, a:Errors())
    end)

    it("la lista entera se rehace solo si cambia algo (o cada 30 s); cada 2 s, solo las filas (Jorge, 24/11: «hasta un 5 % de procesador»)", function()
        local a = F.Community()
        local HU = a.HU
        local f = GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        local built, orig = 0, HU.UnionRosterEntries
        HU.UnionRosterEntries = function(...) built = built + 1; return orig(...) end
        local tick = cover:GetScript("OnUpdate")
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        tick(cover, 2.1) -- (lo que se pide al mirarla ya está pedido)
        built = 0
        for _ = 1, 5 do tick(cover, 2.1) end
        A.equal(0, built, "sin cambios, cada 2 s solo se pintan las filas")
        A.matches("Jefa", cover.rows[1].cells.name:GetText())
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        A.equal(1, built, "cambia la lista del juego")
        HU:Changed("unionMembers")
        A.equal(2, built, "llega algo de otra hermandad")
        HU.rosterVersion = (HU.rosterVersion or 0) + 1
        tick(cover, 2.1)
        A.equal(3, built, "alguien de mi hermandad entra o sale")
        f.MemberList.ShowOfflineButton.GetChecked = function() return true end
        tick(cover, 2.1)
        A.equal(4, built, "«Mostrar desconectados»")
        -- (y cada 30 s se rehace igual, por lo que caduca con el tiempo; luego, sin cambios, otra vez nada)
        a.w:Advance(31)
        tick(cover, 2.1)
        A.truthy(built >= 5)
        local n = built
        for _ = 1, 3 do tick(cover, 2.1) end
        A.equal(n, built)
        A.same({}, a:Errors())
    end)

    it("las notas de nuestra ficha solo se leen: un clic en ellas no hace nada (antes llevaba a la ficha del juego)", function()
        local a = F.Community()
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        local row = cover.rows[3]
        A.matches("Compi", row.cells.name:GetText())
        row:GetScript("OnClick")(row, "LeftButton")
        local card = a.env.GuildUnionMemberCard
        A.truthy(card and card:IsShown(), "nuestra ficha")
        for _, fr in ipairs(a.w.frames) do
            if fr._parent == card then A.falsy(fr:GetScript("OnMouseUp"), "ningún recuadro de la ficha se pincha") end
        end
        A.falsy(a.HU.db.unionRosterMine, "sigue lo nuestro")
        A.same({}, a:Errors())
    end)

    it("en la vista de chat, un clic en la lista de la derecha deja la ficha del juego (no se cambia por la nuestra)", function()
        local a = F.Community()
        local detail, opened = nil, 0
        -- (la ficha del juego y su función de abrirla, de antes de que el addon monte lo suyo: si la enganchara, se vería)
        local f = GuildWindow(a, true, function(w)
            detail = a.env.CreateFrame("Frame", nil, w)
            w.GuildMemberDetailFrame = detail
            w.OpenGuildMemberDetailFrame = function() opened = opened + 1; detail:Show() end
        end)
        f.MemberList.ShowOfflineButton.visible = false
        f.Chat.visible = true
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        detail:Hide()
        f:OpenGuildMemberDetailFrame(1, { name = "Compi-Reino" })
        A.equal(1, opened)
        A.truthy(detail:IsShown(), "la del juego, abierta")
        A.falsy(a.env.GuildUnionMemberCard and a.env.GuildUnionMemberCard:IsShown(), "sin la nuestra")
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
        F.Stub(HU, "TypeLines", function(_, macro, title, ask) sent[#sent + 1] = { macro = macro, title = title, ask = ask } end)
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
        A.equal("¿Seguro que quieres pasar a Compi Reino a «Veterano»?", sent[1].ask, "pregunta con el rango nuevo")
        kick.fn()
        A.matches("/gremove Compi", sent[2].macro)
        A.same({}, a:Errors())
    end)

    it("en la vista de chat: solo la franja de arriba; Comercio y Eventos, desde su pestaña, pasan a la vista de miembros con esa sección", function()
        local a = F.Community()
        local f = GuildWindow(a, true)
        local cover = a.env.GuildUnionUnionRoster
        f.MemberList.ShowOfflineButton.visible = false
        f.Chat.visible = true
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        A.truthy(cover:IsShown(), "la franja de arriba")
        A.equal(0, cover.tabs.selectedTab, "en Chat")
        A.falsy(cover.hdr:IsShown(), "sin lista: se ve el chat del juego")
        A.falsy(a.env.GuildUnionRosterMine:IsShown(), "«Solo mi hermandad», solo en la vista de miembros")
        -- (Comercio, en su pestaña: el botón seguro apunta la sección y el juego pasa a la vista de miembros)
        local trade, cal = cover.side.tabs[1], cover.side.tabs[2]
        for _, b in ipairs({ trade, cal, f.RosterTab }) do b.SetChecked = function(self, v) self._checked = v end end
        A.equal("Profesiones y comercio", trade.tooltip)
        trade:GetScript("PreClick")(trade)
        f.Chat.visible = false
        f.MemberList.ShowOfflineButton.visible = true
        f.MemberList.ShowOfflineButton:GetScript("OnShow")()
        a.w:Advance(0.1)
        trade:GetScript("PostClick")(trade)
        A.equal(2, cover.tabs.selectedTab, "abre Comercio")
        A.truthy(cover.trade:IsShown())
        A.same({ true, false, false }, { trade._checked, cal._checked, f.RosterTab._checked },
            "su pestaña, marcada; la de miembros del juego, no")
        A.falsy(a.env.GuildUnionRosterMine:IsShown(), "en Comercio, sin «Solo mi hermandad»")
        -- (la pestaña de miembros del juego, pulsada en esa vista: a Miembros)
        Section(a, 1)
        A.equal(1, cover.tabs.selectedTab)
        A.same({ false, false, true }, { trade._checked, cal._checked, f.RosterTab._checked })
        A.same({}, a:Errors())
    end)

    it("en combate no se toca si se pulsa la casilla «Mostrar desconectados» del juego (de ella cuelgan botones seguros: el juego lo bloqueaba, Jorge, 25/11); al salir del combate, sí", function()
        local a = F.Community()
        GuildWindow(a)
        local chk = a.env.CommunitiesFrame.MemberList.ShowOfflineButton
        local calls, fight = {}, true
        a.env.InCombatLockdown = function() return fight end
        chk.EnableMouse = function(_, v)
            if fight then error("EnableMouse en combate") end
            calls[#calls + 1] = v
        end
        Section(a, 2)
        A.same({}, calls, "en combate, sin tocarla")
        fight = false
        a.w:Fire("PLAYER_REGEN_ENABLED")
        a.w:Advance(0.1)
        A.same({ false }, calls, "al salir del combate, en Comercio no se pulsa")
        Section(a, 1)
        A.same({ false, true }, calls, "en Miembros, otra vez")
        A.same({}, a:Errors())
    end)

    it("en Comercio, lo gris de arriba llega hasta su panel y el fondo oscuro empieza debajo, sin taparlo", function()
        local a = F.Community()
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        cover.rock.SetHeight = function(self, h) self._h = h end
        cover.dark.SetPoint = function(self, p, _, _, _, y) if p == "TOPLEFT" then self._top = y end end
        Section(a, 2)
        A.same({ 72, -72 }, { cover.rock._h, cover.dark._top }, "Comercio: hasta su panel (72)")
        Section(a, 1)
        A.same({ 58, -58 }, { cover.rock._h, cover.dark._top }, "Miembros: hasta los títulos (58)")
        A.same({}, a:Errors())
    end)

    it("al pasar de Chat a Miembros, la pestaña de chat del juego queda sin marcar aunque se le haya quedado marcada", function()
        local a = F.Community()
        local f = GuildWindow(a, true)
        f.ChatTab.SetChecked = function(self, v) self._checked = v end
        f.MemberList.ShowOfflineButton.visible = false
        f.Chat.visible = true
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        A.equal(true, f.ChatTab._checked, "en Chat, marcada")
        f.Chat.visible = false
        f.MemberList.ShowOfflineButton.visible = true
        f.MemberList.ShowOfflineButton:GetScript("OnShow")()
        a.w:Advance(0.1)
        A.equal(false, f.ChatTab._checked, "en Miembros, sin marcar")
        A.same({}, a:Errors())
    end)

    it("una pestaña de la derecha pulsada en la vista de chat y soltada fuera no deja nada apuntado", function()
        local a = F.Community()
        local f = GuildWindow(a, true)
        local cover = a.env.GuildUnionUnionRoster
        f.MemberList.ShowOfflineButton.visible = false
        f.Chat.visible = true
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        local trade = cover.side.tabs[1]
        trade.SetChecked = function(self, v) self._checked = v end
        -- (el juego no llega a cambiar de vista: PreClick y PostClick, sin más)
        trade:GetScript("PreClick")(trade)
        trade:GetScript("PostClick")(trade)
        A.equal(0, cover.tabs.selectedTab, "sigue en Chat")
        A.equal(false, trade._checked, "y sin marcar")
        -- (luego, la pestaña de miembros del juego: Miembros, no Comercio)
        f.Chat.visible = false
        f.MemberList.ShowOfflineButton.visible = true
        f.MemberList.ShowOfflineButton:GetScript("OnShow")()
        a.w:Advance(0.1)
        A.equal(1, cover.tabs.selectedTab)
        A.same({}, a:Errors())
    end)

    it("Comercio (Trade.lua): solicitudes públicas y privadas, mías en azul, con modo prueba", function()
        local a = F.Community()
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        Section(a, 2)
        local tr = cover.trade
        A.truthy(tr:IsShown(), "la sección Comercio")
        a.HU:TradeTest(true)
        local function Count(lst)
            local n = 0
            for _, r in ipairs((lst or tr.req).rows) do if r:IsShown() and r.entry then n = n + 1 end end
            return n
        end
        A.equal(4, Count(), "Público: las 4 públicas (3 abiertas y 1 aceptada hace poco)")
        local mine
        for _, r in ipairs(tr.req.rows) do if r.entry and r.entry.who == a.HU:Me() then mine = r end end
        A.matches("4da6ff", mine.cells[1]:GetText(), "la mía, en azul")
        A.falsy(mine.accept:IsShown(), "la mía: sin Aceptar")
        A.truthy(mine.cancel:IsShown(), "la mía: Cancelar")
        local priv = tr.viewBtns.priv
        priv:GetScript("OnClick")(priv)
        A.equal(4, Count(), "Privado: las 2 que me piden y las 2 mías (la pública mía sin aceptar, solo en Público)")
        -- (Aceptar una pública de otro: sigue en Público con mi nombre, y sale en mi Privado)
        local pub = tr.viewBtns.pub
        pub:GetScript("OnClick")(pub)
        local other
        for _, r in ipairs(tr.req.rows) do if r.entry and r.entry.state == "open" and r.entry.who ~= a.HU:Me() then other = r end end
        A.truthy(other.accept:IsShown())
        other.accept:GetScript("OnClick")(other.accept)
        A.equal(4, Count(), "sigue en Público")
        A.truthy(other.actText:IsShown(), "con el nombre de quien la aceptó")
        priv:GetScript("OnClick")(priv)
        A.equal(5, Count(), "y en mi Privado")
        pub:GetScript("OnClick")(pub)
        -- (al buscar: arriba, lo publicado que encaja; abajo, quién lo hace (en el WoW de mentira, nadie))
        tr.search:SetText("Poción")
        tr.search:GetScript("OnTextChanged")(tr.search)
        A.equal(1, Count(), "la poción pública de Jandra")
        A.equal(0, Count(tr.found))
        A.truthy(tr.found.empty:IsShown())
        A.falsy(tr.chat:IsShown(), "sin chat al buscar")
        -- (el modo prueba se apaga y quita lo de prueba)
        tr.search:SetText("")
        tr.search:GetScript("OnTextChanged")(tr.search)
        a.HU:TradeTest(false)
        A.equal(0, Count(), "sin lo de prueba")
        A.same({}, a:Errors())
    end)

    it("arriba, lo del juego en su sitio: el desplegable «Guild» (en la vista de chat, a la derecha), los cascos y la casilla de desconectados (a la derecha)", function()
        local a = F.Community()
        -- (dónde se pide cada pieza del juego; antes de que el addon monte lo suyo, para que sus enganches sigan)
        local function Track(b) b.SetPoint = function(self, ...) self._pt = { ... } end end
        local dd, headset
        local f = GuildWindow(a, true, function(w)
            dd = a.env.CreateFrame("Frame", nil, w); w.StreamDropdown = dd; Track(dd)
            headset = a.env.CreateFrame("Frame", nil, w); w.VoiceChatHeadset = headset; Track(headset)
            Track(w.MemberList.ShowOfflineButton)
        end)
        f.MemberList.ShowOfflineButton.visible = false
        f.Chat.visible = true
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        A.same({ "TOPRIGHT", -14, -31 }, { dd._pt[1], dd._pt[4], dd._pt[5] }, "en la vista de chat, el desplegable a la derecha, donde los cascos")
        A.same({ "TOPRIGHT", -180, -26 }, { headset._pt[1], headset._pt[4], headset._pt[5] })
        local chk = f.MemberList.ShowOfflineButton
        -- (a la derecha, delante de «Solo mi hermandad»: 120 + 14 de hueco + su texto (110 si no se sabe) + 26 de la casilla)
        A.same({ "BOTTOMLEFT", "TOPRIGHT", -120 - 14 - 110 - 26, 26 }, { chk._pt[1], chk._pt[3], chk._pt[4], chk._pt[5] },
            "la casilla, a la derecha")
        -- (el juego lo vuelve a colocar al agrandar la ventana: sigue en su sitio)
        dd:SetPoint("TOPLEFT", 195, -31)
        A.same({ "TOPRIGHT", -14, -31 }, { dd._pt[1], dd._pt[4], dd._pt[5] })
        A.same({}, a:Errors())
    end)

    it("en la vista de chat, sin «Guild» (el buscador a su sitio) y con la piedra hasta el chat y su lista, sin rayas; las barras de la izquierda y del chat, arriba", function()
        local a = F.Community()
        local dd, inset, edge, listBar, chatBar, headset, count
        local stream = { streamId = 1, streamType = 1 }   -- (el canal de la hermandad: Enum.ClubStreamType.Guild)
        local function Track(fr) fr.SetPoint = function(self, ...) self._pt = { ... } end end
        local function Alpha(fr) fr.SetAlpha = function(self, v) self._alpha = v end; return fr end
        -- (el borde de un cuadro del juego, con sus piezas de arriba)
        local tops = {}
        local function Box(w, box)
            box.InsetFrame = a.env.CreateFrame("Frame", nil, box)
            local ns = a.env.CreateFrame("Frame", nil, box.InsetFrame)
            box.InsetFrame.NineSlice = ns
            for _, k in ipairs({ "TopEdge", "TopLeftCorner", "TopRightCorner" }) do
                ns[k] = Alpha(a.env.CreateFrame("Frame", nil, ns)); tops[#tops + 1] = ns[k]
            end
        end
        local function Tops()
            local out = {}
            for i, t in ipairs(tops) do out[i] = t._alpha end
            return out
        end
        local f = GuildWindow(a, true, function(w)
            dd = Alpha(a.env.CreateFrame("Frame", nil, w)); w.StreamDropdown = dd
            dd.EnableMouse = function(self, v) self._mouse = v end
            Track(dd)
            -- (los cascos del chat de voz y el «N/M en línea» de la lista de la derecha)
            headset = Alpha(a.env.CreateFrame("Button", nil, w)); w.VoiceChatHeadset = headset
            headset.EnableMouse = function(self, v) self._mouse = v end
            count = Alpha(a.env.CreateFrame("Frame", nil, w.MemberList)); w.MemberList.MemberCount = count
            inset = a.env.CreateFrame("Frame", nil, w); w.Inset = inset
            edge = a.env.CreateFrame("Frame", nil, inset); inset.NineSlice = edge
            -- (la piedra de abajo: dónde se pide y cuánto mide)
            edge.CreateTexture = function(self, _, layer)
                local t = a.env.CreateFrame("Frame", nil, self)
                t._layer = layer
                t.SetPoint = function(s, ...) s._pts = s._pts or {}; s._pts[#s._pts + 1] = { ... } end
                t.SetHeight = function(s, h) s._h = h end
                return t
            end
            -- (las barras con flechas: la de la columna de comunidades y la del chat)
            listBar = a.env.CreateFrame("Frame", nil, w.CommunitiesList); w.CommunitiesList.ScrollBar = listBar; Track(listBar)
            listBar.SetFrameStrata = function(self, v) self._strata = v end
            chatBar = a.env.CreateFrame("Frame", nil, w.Chat); w.Chat.ScrollBar = chatBar; Track(chatBar)
            Track(w.Chat)
            Box(w, w.Chat); Box(w, w.MemberList)
            w.GetSelectedClubId = function() return 7 end
            w.GetSelectedStreamForClub = function() return stream end
            w.SelectStream = function() end
        end)
        local cover = a.env.GuildUnionUnionRoster
        cover.rock.SetHeight = function(self, h) self._h = h end
        -- (la piedra de abajo, en el borde del fondo del juego: encima de él y debajo de lo suyo; desde la franja de la izquierda)
        local band = cover.band
        A.same({ edge, "OVERLAY" }, { band:GetParent(), band._layer })
        A.same({ "TOPLEFT", cover, "TOPLEFT", -4, 0 }, band._pts[1], "desde donde acaba la franja oscura, como la de la fila")
        A.equal(34 + 3, band._h, "la franja y el borde de arriba del fondo del juego: ahí empiezan el chat y su lista")
        -- (en la vista de miembros: ni la piedra de abajo ni el desplegable; la barra de las comunidades, arriba del todo y encima)
        A.falsy(band:IsShown())
        A.same({ 1, true }, { dd._alpha, dd._mouse }, "el desplegable, como lo pone el juego")
        A.same({ 1, true, 1 }, { headset._alpha, headset._mouse, count._alpha }, "los cascos y el «en línea», como siempre")
        A.same({ "TOPLEFT", f.CommunitiesList, "TOPRIGHT", 6, -3 }, listBar._pt, "la barra de las comunidades, arriba del todo")
        A.same({ "HIGH", 312 }, { listBar._strata, listBar:GetFrameLevel() }, "por encima de la piedra")
        -- (a la vista de chat)
        f.MemberList.ShowOfflineButton.visible = false
        f.Chat.visible = true
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        A.truthy(band:IsShown(), "la piedra baja hasta el chat")
        A.falsy(cover.rock:IsShown(), "la de lo nuestro, no: taparía los cascos y el «en línea»")
        A.same({ 1, true }, { dd._alpha, dd._mouse }, "«Guild», a la vista y con clics, para cambiar a oficiales")
        A.same({ "TOPRIGHT", f, "TOPRIGHT", -14, -31 }, dd._pt, "a la derecha, donde los cascos")
        A.same({ 0, false, 0 }, { headset._alpha, headset._mouse, count._alpha }, "sin cascos ni el «N/M en línea» de mi hermandad")
        A.same({ "TOPLEFT", cover, "BOTTOMLEFT", 6, -3 - 7 }, f.Chat._pt, "el borde del chat, donde acaba la piedra")
        A.same({ 0, 0, 0, 0, 0, 0 }, Tops(), "sin la raya de arriba del chat ni de la lista")
        A.same({ "TOPLEFT", f.Chat, "TOPRIGHT", 15, 1 }, chatBar._pt, "la barra del chat, arriba aunque haya mensaje fijado")
        A.same({ "TOPLEFT", f.CommunitiesList, "TOPRIGHT", 6, -3 }, listBar._pt)
        -- (de vuelta a la vista de miembros: como siempre)
        f.Chat.visible = false
        f.MemberList.ShowOfflineButton.visible = true
        f.MemberList.ShowOfflineButton:GetScript("OnShow")()
        a.w:Advance(0.1)
        A.falsy(band:IsShown())
        A.truthy(cover.rock:IsShown())
        A.same({ 1, true }, { dd._alpha, dd._mouse })
        A.same({ 1, 1, 1, 1, 1, 1 }, Tops(), "los bordes, como los pone el juego")
        A.same({ 1, true, 1 }, { headset._alpha, headset._mouse, count._alpha }, "de vuelta, los cascos y el «en línea»")
        A.same({ "TOPLEFT", f, "TOPLEFT", 195, -31 }, dd._pt, "el desplegable, en su sitio de siempre")
        -- (en otra vista del juego, sin lo nuestro: la piedra de abajo se va y la barra de las comunidades vuelve a su sitio)
        f.MemberList.ShowOfflineButton.visible = false
        f.MemberList.ShowOfflineButton:GetScript("OnHide")()
        a.w:Advance(0.1)
        A.falsy(cover:IsShown())
        A.falsy(band:IsShown())
        A.same({ "TOPLEFT", f.CommunitiesList, "TOPRIGHT", 6, -45 }, listBar._pt)
        A.same({ "MEDIUM", 1 }, { listBar._strata, listBar:GetFrameLevel() }, "con su capa y su nivel")
        A.same({}, a:Errors())
    end)

    it("las imágenes de los botones redondos están en Media: .tga de 64x64 sin comprimir y con transparencia", function()
        -- (las dibuja Tools/botones_redondos.py; el juego solo lee .tga de lados potencia de 2)
        for _, name in ipairs({ "boton-calendario", "boton-circulo", "boton-brillo", "boton-sombra" }) do
            local fh = io.open(runner.here .. "/../Media/" .. name .. ".tga", "rb")
            A.truthy(fh, name)
            local head = fh:read(18)
            fh:close()
            A.same({ 2, 64, 64, 32, 8 }, { head:byte(3), head:byte(13) + head:byte(14) * 256,
                head:byte(15) + head:byte(16) * 256, head:byte(17), head:byte(18) % 16 }, name)
        end
    end)

    it("Comercio y Eventos: cada uno su sección, sin la lista de miembros; a Miembros, con la pestaña del juego", function()
        local a = F.Community()
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        for i, key in ipairs({ "trade", "calendar" }) do
            Section(a, i + 1)
            A.equal(i + 1, cover.tabs.selectedTab)
            A.truthy(cover[key]:IsShown(), key)
            A.falsy(cover.hdr:IsShown(), "sin los títulos de Miembros")
        end
        Section(a, 1)
        A.truthy(cover.hdr:IsShown())
        A.same({}, a.w.whoSent, "cambiar de sección no pide /who (el juego lo bloqueó al volver a Miembros)")
        A.falsy(cover.trade:IsShown()); A.falsy(cover.calendar:IsShown())
        A.same({}, a:Errors())
    end)

    it("la columna de profesiones: solo el icono de las de mi hermandad, que las da el juego por su comunidad", function()
        local a = F.Community()
        a.env.C_Club = {
            GetGuildClubId = function() return 9 end,
            GetClubMembers = function() return { 1, 2 } end,
            GetMemberInfo = function(_, id)
                if id == 1 then
                    return { name = "Compi", profession1ID = 164, profession1Name = "Herrería", profession1Rank = 300,
                        profession2ID = 186, profession2Name = "Minería", profession2Rank = 275 }
                end
                return { name = "Jefa" }
            end,
        }
        a.env.C_TradeSkillUI = { GetTradeSkillTexture = function(id) return "icono" .. id end }
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        local byName = {}
        for _, r in ipairs(cover.rows) do if r.entry then byName[r.entry.name:match("^([^-]+)")] = r end end
        local p = byName.Compi.cells.prof
        A.same({ true, true }, { p[1]:IsShown(), p[2]:IsShown() }, "sus dos iconos (sin nivel: Jorge, 24/11)")
        -- (sin profesiones, los huecos vacíos)
        local q = byName.Jefa.cells.prof
        A.same({ false, false }, { q[1]:IsShown(), q[2]:IsShown() })
        A.same({}, a:Errors())
    end)

    it("profesiones con la comunidad de Forever, que da siempre nivel 1: en la ficha, las mías con el nivel de mi personaje; las de los demás, sin número", function()
        local a = F.Community()
        -- (lo que dio el juego de Jorge, 24/11: su personaje, Herboristería 195 y Minería 111; la comunidad, 1 y 1)
        a.env.C_Club = {
            GetGuildClubId = function() return 9 end,
            GetClubMembers = function() return { 1, 2 } end,
            GetMemberInfo = function(_, id)
                if id == 1 then
                    return { name = "Tester", isSelf = true, profession1ID = 182, profession1Name = "Herbalism", profession1Rank = 1,
                        profession2ID = 186, profession2Name = "Mining", profession2Rank = 1 }
                end
                return { name = "Compi", profession1ID = 186, profession1Name = "Mining", profession1Rank = 1 }
            end,
        }
        a.env.C_TradeSkillUI = { GetTradeSkillTexture = function(id) return "icono" .. id end }
        a.env.GetProfessions = function() return 1, 2, nil, nil, 3 end
        a.env.GetProfessionInfo = function(i)
            if i == 1 then return "Herbalism", "icono", 195, 225, 1, 0, 182 end
            if i == 2 then return "Mining", "icono", 111, 150, 2, 0, 186 end
            if i == 3 then return "Cooking", "icono", 61, 75, 1, 0, 185 end
        end
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        local byName = {}
        for _, r in ipairs(cover.rows) do if r.entry then byName[r.entry.name:match("^([^-]+)")] = r end end
        local function Levels(name)
            local row = byName[name]
            row:GetScript("OnClick")(row, "LeftButton")
            local card = a.env.GuildUnionMemberCard
            local lv = {}
            for k = 1, 2 do
                local fs = card.recipes.levels[k]
                lv[k] = fs:IsShown() and fs:GetText() or "(sin)"
            end
            row:GetScript("OnClick")(row, "LeftButton")
            return lv
        end
        A.same({ "195", "111" }, Levels("Tester"), "las mías, de mi personaje")
        A.same({ "", "(sin)" }, Levels("Compi"), "la de otro, sin número")
        A.same({}, a:Errors())
    end)

    it("«Ver recetas» en la ficha: las mías abren mi profesión; las de otro se piden por su GUID; las de recoger, sin botón", function()
        local a = F.Community()
        -- (el WoW de mentira, recordando si un botón está apagado)
        local meta = a.w.frameMeta
        local base = meta.__index
        meta.__index = function(f, k)
            if k == "SetEnabled" then return function(self, v) rawset(self, "_off", not v) end end
            if k == "IsEnabled" then return function(self) return not rawget(self, "_off") end end
            return base(f, k)
        end
        local opened, asked = {}, {}
        a.env.C_Club = {
            GetGuildClubId = function() return 9 end,
            GetClubMembers = function() return { 1, 2, 3 } end,
            GetMemberInfo = function(_, id)
                if id == 1 then
                    return { name = "Tester", isSelf = true, guid = "Player-1-AAA", profession1ID = 182, profession1Name = "Herbalism",
                        profession1Rank = 1, profession2ID = 186, profession2Name = "Mining", profession2Rank = 1 }
                end
                if id == 2 then return { name = "Compi", guid = "Player-1-BBB", profession1ID = 164, profession1Name = "Blacksmithing", profession1Rank = 1 } end
                return { name = "Jefa", profession1ID = 197, profession1Name = "Tailoring", profession1Rank = 1 }
            end,
        }
        a.env.C_TradeSkillUI = {
            GetTradeSkillTexture = function(id) return "icono" .. id end,
            OpenTradeSkill = function(id) opened[#opened + 1] = id; return true end,
        }
        a.env.C_GuildInfo = { QueryGuildMemberRecipes = function(guid, id) asked[#asked + 1] = guid .. "/" .. id end }
        -- (Compi ha abierto su herrería con el addon: su línea de oficios trae recetas)
        local HU = a.HU
        local l = HU.ProfessionsForTests.list(164)
        a.w:Receive("HU20B", "WU~UNO~OF~164~" .. HU.StampNow() .. "~250," .. l.hash .. ",E", "GUILD", "Compi-Reino")
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        local byName = {}
        for _, r in ipairs(cover.rows) do if r.entry then byName[r.entry.name:match("^([^-]+)")] = r end end
        local function Card(name)
            local row = byName[name]
            row:GetScript("OnClick")(row, "LeftButton")
            return a.env.GuildUnionMemberCard.recipes, row
        end
        -- (como el juego: un botón apagado no se pulsa)
        local function Press(b) if b:IsEnabled() then b:GetScript("OnClick")(b) end end
        -- (las mías: Herboristería, de recoger, sin botón; Minería abre mi ventana de la profesión)
        local rows, row = Card("Tester")
        A.same({ false, true }, { rows.btns[1]:IsShown(), rows.btns[2]:IsShown() })
        -- (el botón rojo del juego otra vez, con letra pequeña: Jorge, 25/11, «pasarlo a rojo de nuevo»)
        A.same({ "UIPanelButtonTemplate", "UIPanelButtonTemplate" }, { rows.btns[1]._template, rows.btns[2]._template })
        Press(rows.btns[2])
        A.same({ 186 }, opened)
        A.same({}, asked)
        row:GetScript("OnClick")(row, "LeftButton")
        -- (si el juego no la abre, se piden por mi GUID)
        a.env.C_TradeSkillUI.OpenTradeSkill = function() return false end
        rows, row = Card("Tester")
        Press(rows.btns[2])
        A.same({ "Player-1-AAA/186" }, asked)
        row:GetScript("OnClick")(row, "LeftButton")
        -- (las de otro, por su GUID)
        rows, row = Card("Compi")
        Press(rows.btns[1])
        A.same({ "Player-1-AAA/186", "Player-1-BBB/164" }, asked)
        row:GetScript("OnClick")(row, "LeftButton")
        -- (sin GUID, ni en la comunidad ni en la lista del juego: apagado)
        rows = Card("Jefa")
        A.truthy(rows.btns[1]:IsShown())
        A.falsy(rows.btns[1]:IsEnabled())
        A.same({}, a:Errors())
    end)

    it("«Ver recetas» de otro, apagado y con su porqué al pasar el ratón: sin su línea de oficios, sin GuildUnion (o no ha llegado); con ella sin recetas, no ha abierto esa ventana; las mías, siempre", function()
        local a = F.Community()
        local HU = a.HU
        local meta = a.w.frameMeta
        local base = meta.__index
        meta.__index = function(f, k)
            if k == "SetEnabled" then return function(self, v) rawset(self, "_off", not v) end end
            if k == "IsEnabled" then return function(self) return not rawget(self, "_off") end end
            return base(f, k)
        end
        a.env.C_Club = {
            GetGuildClubId = function() return 9 end,
            GetClubMembers = function() return { 1, 2 } end,
            GetMemberInfo = function(_, id)
                if id == 1 then
                    return { name = "Tester", isSelf = true, guid = "Player-1-AAA", profession1ID = 164, profession1Name = "Herrería", profession1Rank = 1 }
                end
                return { name = "Compi", guid = "Player-1-BBB", profession1ID = 164, profession1Name = "Herrería", profession1Rank = 1 }
            end,
        }
        a.env.C_TradeSkillUI = { GetTradeSkillTexture = function(id) return "icono" .. id end }
        local asked = {}
        local need = HU.PackNeed
        F.Stub(HU, "PackNeed", function(self, tag, id) asked[#asked + 1] = tag .. "|" .. id; return need(self, tag, id) end)
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        local tip = a.env.GameTooltip
        -- (el botón de la ficha de esa persona: si se ve, si está encendido y lo que dice al pasar el ratón)
        local function Recipes(name)
            local row
            for _, r in ipairs(cover.rows) do if r.entry and r.entry.name:match("^([^-]+)") == name then row = r end end
            row:GetScript("OnClick")(row, "LeftButton")
            local b = a.env.GuildUnionMemberCard.recipes.btns[1]
            tip:Hide(); tip:SetText("")
            b:GetScript("OnEnter")(b)
            local said = tip:IsShown() and tip:GetText() or false
            b:GetScript("OnLeave")(b)
            row:GetScript("OnClick")(row, "LeftButton")
            return { b:IsShown(), b:IsEnabled(), said }
        end
        local function Hear(data)
            a.w:Advance(1.1) -- (cada línea con su hora: la de la misma hora no pisa a la de antes)
            a.w:Receive("HU20B", "WU~UNO~OF~164~" .. HU.StampNow() .. "~" .. data, "GUILD", "Compi-Reino")
        end
        A.same({ true, true, false }, Recipes("Tester"), "las mías, siempre, aunque no haya llegado mi línea")
        A.same({ true, false, "No tiene GuildUnion (o aún no ha llegado lo suyo)" }, Recipes("Compi"), "sin su línea")
        A.equal("UNO|OF", asked[#asked], "y se pide lo de mi hermandad que me perdí estando fuera")
        Hear("250")
        A.same({ true, false, "Aún no ha abierto su ventana de Herrería" }, Recipes("Compi"), "con su línea, sin recetas")
        local l = HU.ProfessionsForTests.list(164)
        Hear("251," .. l.hash .. ",E")
        A.same({ true, true, false }, Recipes("Compi"), "con recetas: encendido y sin aviso")
        -- (con las de otra versión del addon también: las ha abierto, aunque yo no pueda leerlas)
        Hear("252," .. (l.hash == "zzz" and "yyy" or "zzz") .. ",E")
        A.same({ true, true, false }, Recipes("Compi"))
        local en = F.Community({ locale = "enUS" }).HU
        A.equal("They don't have GuildUnion (or their data hasn't arrived yet)", en.L("No tiene GuildUnion (o aún no ha llegado lo suyo)"))
        A.equal("They haven't opened their Blacksmithing window yet", string.format(en.L("Aún no ha abierto su ventana de %s"), "Blacksmithing"))
        A.same({}, a:Errors())
    end)

    it("la casilla «Mostrar desconectados» solo en Miembros: en Comercio y Eventos no se ve ni se pulsa", function()
        local a = F.Community()
        local box, label
        local f = GuildWindow(a, false, function(w)
            local chk = w.MemberList.ShowOfflineButton
            box, label = a.env.CreateFrame("Frame", nil, chk), a.env.CreateFrame("Frame", nil, chk)
            for _, r in ipairs({ box, label }) do r.SetAlpha = function(self, v) self._alpha = v end end
            chk.GetRegions = function() return box, label end
            chk.EnableMouse = function(self, v) self._mouse = v end
        end)
        local chk = f.MemberList.ShowOfflineButton
        Section(a, 2)
        A.same({ 0, 0, false }, { box._alpha, label._alpha, chk._mouse }, "en Comercio")
        Section(a, 3)
        A.same({ 0, 0, false }, { box._alpha, label._alpha, chk._mouse }, "en Eventos")
        Section(a, 1)
        A.same({ 1, 1, true }, { box._alpha, label._alpha, chk._mouse }, "en Miembros")
        A.same({}, a:Errors())
    end)

    it("el buscador (BlizzTab.lua): en Miembros, donde el desplegable «Guild»; en la vista de chat, quien ve el historial busca en el chat", function()
        local a = F.Community()
        -- (lo que traen las plantillas del juego: la pestaña, su icono; el buscador, su texto de ayuda)
        local create = a.env.CreateFrame
        a.env.CreateFrame = function(kind, name, parent, template, ...)
            local fr = create(kind, name, parent, template, ...)
            if type(template) == "string" and template:find("CommunitiesFrameTabTemplate", 1, true) then
                fr.Icon = create("Frame", nil, fr)
            elseif type(template) == "string" and template:find("SearchBoxTemplate", 1, true) then
                fr.Instructions = create("Frame", nil, fr)
            end
            return fr
        end
        local dd
        local f = GuildWindow(a, true, function(w)
            w.GuildInfoTab = create("CheckButton", nil, w)
            dd = create("Frame", nil, w); w.StreamDropdown = dd
            dd.IsVisible = function() return w.Chat.visible end
        end)
        local box = a.env.GuildUnionReduceSearch
        A.truthy(box, "el buscador")
        box.SetPoint = function(self, ...) self._pt = { ... } end
        a.HU.SyncCharSearch(); a.w:Advance(0.1)
        local spot = a.HU.chatSearchSpot
        A.same({ "LEFT", spot, "LEFT", 0, 0 }, box._pt, "en Miembros, donde iba el desplegable: las casillas van a la derecha")
        A.falsy(box.forChat)
        -- (vista de chat, sin el desplegable, y con permiso para ver el historial)
        local searched
        a.HU.CanPin = function() return true end
        a.HU.HistEnabled = function() return true end
        a.HU.HistSearch = function(_, name, text) searched = { name, text } end
        f.MemberList.ShowOfflineButton.visible = false
        f.Chat.visible = true
        a.HU.SyncCharSearch(); a.w:Advance(0.1)
        A.same({ "LEFT", spot, "LEFT", 0, 0 }, box._pt, "en la vista de chat, en el mismo sitio (el desplegable, a la derecha)")
        A.truthy(box.forChat, "busca en el chat")
        A.equal("Buscar en el chat", box.Instructions:GetText())
        box:SetText("  mazmorra ")
        box:GetScript("OnEnterPressed")(box)
        A.same({ nil, "mazmorra" }, searched, "lo busca en el historial")
        -- (sin permiso, personajes, como antes)
        a.HU.CanPin = function() return false end
        a.HU.SyncCharSearch(); a.w:Advance(0.1)
        A.same({ "LEFT", spot, "LEFT", 0, 0 }, box._pt, "en el mismo sitio")
        A.falsy(box.forChat)
        A.equal("Buscar personaje", box.Instructions:GetText())
    end)

    it("Comercio y Eventos, pestañas de la derecha: justo debajo de la de miembros, con las del juego debajo; desde ellas, la hermandad vuelve al chat", function()
        local a = F.Community()
        -- (lo que trae la plantilla de las pestañas del juego: su icono. La de GuildUnion, BlizzTab.lua, la usa)
        local create = a.env.CreateFrame
        a.env.CreateFrame = function(kind, name, parent, template, ...)
            local fr = create(kind, name, parent, template, ...)
            if type(template) == "string" and template:find("CommunitiesFrameTabTemplate", 1, true) then fr.Icon = create("Frame", nil, fr) end
            -- (las nuestras: dónde se atan)
            if name == "GuildUnionTradeTab" or name == "GuildUnionCalendarTab" then fr.SetPoint = function(self, ...) self._pt = { ... } end end
            return fr
        end
        local club, info, prefs
        local f = GuildWindow(a, true, function(w)
            -- (las pestañas del juego: Información y la de preferencias de juego, a la vista. Al ponerlas al día, el juego
            -- marca la de miembros en su vista y, sin Beneficios, ata Información a la de miembros)
            info = create("CheckButton", nil, w); w.GuildInfoTab = info
            prefs = create("CheckButton", nil, w); w.GuildPreferredPlaySettingsTab = prefs
            info.SetPoint = function(self, ...) self._pt = { ... } end
            w.UpdateCommunitiesTabs = function(self)
                self.RosterTab:SetChecked(true)
                self.GuildInfoTab:SetPoint("TOPLEFT", self.RosterTab, "BOTTOMLEFT", 0, -20)
            end
            -- (lo que no hay en esta prueba: así la de GuildUnion se monta entera)
            w.GuildBenefitsTab, w.StreamDropdown, w.InviteButton, w.Chat.MessageFrame = false, false, false, false
            -- (la lista del juego, con la hermandad)
            local cl = w.CommunitiesList
            club = create("Button", nil, cl)
            local sb = create("Frame", nil, cl)
            sb.ForEachFrame = function(_, fn) fn(club, { clubInfo = { clubType = 2 } }) end
            cl.ScrollBox = sb
        end)
        local side = a.env.GuildUnionUnionRoster.side
        local trade, cal = side.tabs[1], side.tabs[2]
        for _, b in ipairs({ trade, cal, f.RosterTab }) do b.SetChecked = function(self, v) self._checked = v end end
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        A.same({ "TOPLEFT", f.RosterTab, "BOTTOMLEFT", 0, -20 }, trade._pt, "justo debajo de la de miembros")
        A.same({ "TOPLEFT", trade, "BOTTOMLEFT", 0, -20 }, cal._pt)
        A.truthy(trade:IsShown() and cal:IsShown())
        A.same({ "TOPLEFT", cal, "BOTTOMLEFT", 0, -20 }, info._pt, "Información, debajo de las nuestras")
        -- (el juego la vuelve a atar a la de miembros al poner al día sus pestañas: se vuelve a bajar)
        f:UpdateCommunitiesTabs()
        A.same({ "TOPLEFT", cal, "BOTTOMLEFT", 0, -20 }, info._pt)
        A.equal(prefs, a.env.GuildUnionReduceTab.anchoredTo, "la de GuildUnion, debajo de la última del juego")
        -- (con Beneficios a la vista, baja esa: Información va atada a ella)
        local benefits = create("CheckButton", nil, f)
        benefits.SetPoint = function(self, ...) self._pt = { ... } end
        f.GuildBenefitsTab = benefits
        f:UpdateCommunitiesTabs()
        A.same({ "TOPLEFT", cal, "BOTTOMLEFT", 0, -20 }, benefits._pt, "Beneficios, debajo de las nuestras")
        f.GuildBenefitsTab = false
        -- (con el panel de GuildUnion abierto, solo su pestaña se ve marcada: las demás, sin su brillo de marcada)
        local looks = {}
        for _, b in ipairs({ f.ChatTab, f.RosterTab, info, prefs, trade, cal }) do
            local look = { SetAlpha = function(self, v) self.alpha = v end }
            looks[#looks + 1] = look
            b.GetCheckedTexture = function() return look end
        end
        local gu = a.env.GuildUnionReduceTab
        gu:GetScript("OnClick")(gu)
        for i, look in ipairs(looks) do A.equal(0, look.alpha, "marca " .. i .. ", apagada") end
        gu:GetScript("OnClick")(gu)
        for i, look in ipairs(looks) do A.equal(1, look.alpha, "marca " .. i .. ", de vuelta") end
        -- (Comercio con mensajes sin leer: su pestaña lleva el puntito con cuántos chats los tienen; leídos, se va)
        local unread = 2
        a.HU.TradeUnreadChats = function() return unread end
        a.HU:Changed("tradeUnread")
        A.same({ true, true, "2" }, { trade.badge.dot:IsShown(), trade.badge.num:IsShown(), trade.badge.num:GetText() },
            "el puntito, con el número de chats")
        unread = 0
        a.HU:Changed("tradeUnread")
        A.same({ false, false }, { trade.badge.dot:IsShown(), trade.badge.num:IsShown() })
        -- (sin la hermandad elegida —sin Información—, no salen)
        info:Hide()
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        A.falsy(trade:IsShown() or cal:IsShown())
        info:Show()
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        -- (Comercio: su pestaña, marcada, y la de miembros del juego no, aunque el juego la vuelva a marcar)
        side.home.SetAllPoints = function(self, fr) self._on = fr end
        Section(a, 2)
        A.same({ true, false, false }, { trade._checked, cal._checked, f.RosterTab._checked })
        f:UpdateCommunitiesTabs()
        A.equal(false, f.RosterTab._checked, "el juego la vuelve a marcar: se le quita otra vez")
        -- (y un clic en la entrada de la hermandad vuelve al chat: un botón seguro encima de ella; en Miembros, no)
        A.truthy(side.home:IsShown(), "en Comercio")
        A.equal(club, side.home._on, "encima de la entrada de la hermandad")
        Section(a, 1)
        A.falsy(side.home:IsShown(), "en Miembros, el clic es de la entrada")
        A.same({ false, false, true }, { trade._checked, cal._checked, f.RosterTab._checked })
        A.same({}, a:Errors())
    end)

    it("fuera de la vista de miembros no sale nada; al volver, Miembros (también si se había quitado)", function()
        local a = F.Community()
        local f = GuildWindow(a)
        f.MemberList.ShowOfflineButton.visible = false
        f.MemberList.ShowOfflineButton:GetScript("OnHide")()
        a.w:Advance(0.1)
        A.falsy(a.env.GuildUnionRosterMine:IsShown())
        A.falsy(a.env.GuildUnionUnionRoster:IsShown())
        -- (quien la tenía quitada con la casilla «GuildUnion» de antes: ya no hay casilla, sale igual)
        a.HU.db.unionRosterOff = true
        f.MemberList.ShowOfflineButton.visible = true
        f:GetScript("OnShow")(f)
        a.w:Advance(0.1)
        A.truthy(a.env.GuildUnionUnionRoster:IsShown(), "siempre puesta")
        A.falsy(a.HU.db.unionRosterOff, "y lo viejo, borrado")
        A.same({}, a:Errors())
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

    it("el contador de conectados de la unión, solo en la vista de chat y en nuestras pestañas (en Información, no)", function()
        local a = F.Community()
        local f = GuildWindow(a, true)
        local counts = a.env.GuildUnionUnionCounts
        A.truthy(counts:IsShown(), "en Miembros")
        A.matches("conectados", counts.text:GetText())
        -- (Información: ni la casilla de desconectados ni el chat a la vista)
        f.MemberList.ShowOfflineButton.visible = false
        f.MemberList.ShowOfflineButton:GetScript("OnHide")()
        a.w:Advance(4)
        A.falsy(a.env.GuildUnionUnionRoster:IsShown())
        A.falsy(counts:IsShown(), "en Información, no")
        f.Chat.visible = true
        f.Chat:GetScript("OnShow")()
        a.w:Advance(0.1)
        A.truthy(counts:IsShown(), "en la vista de chat, sí")
        A.same({}, a:Errors())
    end)

    it("«Solo mi hermandad» puesta: el buscador va a la lista del juego (nuestra lista no está a la vista)", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "IsGuildForwarder", true)
        GuildWindow(a)
        a.w:Receive("HU20B", "ML~DOS~id1~1~1~Blas,1,60,4,Ventormenta", "GUILD", "Compi-Reino")
        local blas
        for _, e in ipairs(HU:UnionRosterEntries()) do if e.name:match("^Blas") then blas = e end end
        A.truthy(blas, "Blas, conectado en DOS")
        local mine = a.env.GuildUnionRosterMine
        mine.GetChecked = function() return true end
        Click("GuildUnionRosterMine", a)
        A.falsy(HU.UnionRosterPick({ name = blas.name, tag = "DOS", online = true }), "lo lleva BlizzTab.lua")
        A.same({}, a:Errors())
    end)

    it("el /who, solo con lo que hace el jugador (la rueda, la barra y sus flechas), no al moverse la lista sola", function()
        local a = F.Community()
        -- (la barra de la lista y su flecha de bajar, de la plantilla del juego: el WoW de mentira no las crea)
        local bar = a.env.CreateFrame("Slider", "GuildUnionUnionRosterScrollScrollBar")
        local down = a.env.CreateFrame("Button", "GuildUnionUnionRosterScrollScrollBarScrollDownButton", bar)
        GuildWindow(a)
        local sf = a.env.GuildUnionUnionRosterScroll
        -- (la lista se recoloca o cambia de tamaño: salta OnVerticalScroll sin ningún clic)
        sf:GetScript("OnVerticalScroll")(sf, 18)
        A.same({}, a.w.whoSent, "sin clic, el juego bloquearía el /who")
        sf:GetScript("OnMouseWheel")(sf, -1)
        A.same({ 'g-"Hermandad Dos"' }, a.w.whoSent, "con la rueda, sí")
        a.w:Advance(61)
        bar:GetScript("OnMouseDown")(bar, "LeftButton")
        A.equal(2, #a.w.whoSent, "al pinchar la barra")
        a.w:Advance(61)
        down:GetScript("OnClick")(down, "LeftButton")
        A.equal(3, #a.w.whoSent, "con su flecha")
        A.same({}, a:Errors())
    end)

    it("echar, solo a quien mi rango deja: a la maestra ni el menú ni la ficha; con varios, solo los que puedo", function()
        local a = F.Community()
        local HU = a.HU
        GuildWindow(a)
        F.Stub(HU, "CanPromote", true); F.Stub(HU, "CanDemote", true); F.Stub(HU, "CanKickGuild", true)
        local sent = {}
        F.Stub(HU, "TypeLines", function(_, macro) sent[#sent + 1] = macro end)
        local extra
        HU.PlayerMenu = function(_, _, fn) extra = fn end
        local cover = a.env.GuildUnionUnionRoster
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        local jefa, compi = cover.rows[1], cover.rows[3]
        A.matches("Jefa", jefa.cells.name:GetText())
        A.matches("Compi", compi.cells.name:GetText())
        -- (yo soy oficial (rango 1) y ella, maestra (0): la orden fallaría)
        jefa:GetScript("OnClick")(jefa, "RightButton")
        local root = FakeMenu()
        extra(root)
        A.truthy(MenuItem(root, "Cambiar rango"))
        A.falsy(MenuItem(root, "Echar de la hermandad"), "sin «Echar» para la maestra")
        -- (su ficha: «Echar» no manda nada y dice por qué)
        jefa:GetScript("OnClick")(jefa, "LeftButton")
        local card = a.env.GuildUnionMemberCard
        A.matches("Jefa", card.title:GetText())
        local n0 = #a.w.chat
        card.remove:GetScript("OnClick")(card.remove)
        A.same({}, sent, "nada a la ventana de órdenes")
        A.matches("rango igual o superior", Chat(a, n0))
        -- (la maestra y Compi elegidos: el menú de los dos echa solo a Compi)
        a.env.IsControlKeyDown = function() return true end
        compi:GetScript("OnClick")(compi, "LeftButton")
        a.env.IsControlKeyDown = function() return false end
        local multi = FakeMenu()
        a.env.MenuUtil = { CreateContextMenu = function(_, gen) gen(nil, multi) end }
        compi:GetScript("OnClick")(compi, "RightButton")
        local kick = MenuItem(multi, "Echar de la hermandad")
        A.truthy(kick, "con Compi, sí")
        kick.fn()
        A.equal(1, #sent)
        A.matches("/gremove Compi", sent[1])
        A.falsy(sent[1]:find("Jefa", 1, true), "la maestra, no")
        A.same({}, a:Errors())
    end)

    it("en combate no se mueven la lista ni el chat del juego (llevan botones seguros: el juego lo bloquea); al salir, sí", function()
        -- (visto en el juego el 23/11, copia 287: ADDON_ACTION_BLOCKED en Frame:SetPoint() dentro de Sync)
        local a = F.Community()
        local f = GuildWindow(a, true)
        local ml, chat = f.MemberList, f.Chat
        local cover = a.env.GuildUnionUnionRoster
        -- (lo que se les mueve desde aquí; gameSetPoint, el SetPoint con el que el juego coloca su lista)
        local moved = {}
        local function Spy(fr)
            local set, clear = fr.SetPoint, fr.ClearAllPoints
            fr.SetPoint = function(self, ...) moved[#moved + 1] = { self, ... }; return set(self, ...) end
            fr.ClearAllPoints = function(self) moved[#moved + 1] = { self, "ClearAllPoints" }; return clear(self) end
            return set
        end
        local gameSetPoint = Spy(ml)
        Spy(chat)
        a.w.inCombat = true
        -- (en combate: a la vista de chat; el juego recoloca su lista; y otra vez a la de miembros)
        ml.ShowOfflineButton.visible = false
        chat.visible = true
        chat:GetScript("OnShow")()
        a.w:Advance(0.1)
        A.equal(0, cover.tabs.selectedTab, "en la vista de chat")
        gameSetPoint(ml, "TOPLEFT", f, "TOPRIGHT", -165, -63)
        chat.visible = false
        ml.ShowOfflineButton.visible = true
        ml.ShowOfflineButton:GetScript("OnShow")()
        a.w:Advance(0.1)
        A.equal(1, cover.tabs.selectedTab, "en la de miembros")
        A.equal(0, #moved, "en combate no se tocan")
        -- (al salir del combate, cada uno a su sitio)
        a.w.inCombat = false
        a.w:Fire("PLAYER_REGEN_ENABLED")
        a.w:Advance(0.1)
        local back
        for _, m in ipairs(moved) do
            if m[1] == ml and m[2] == "TOPLEFT" and m[3] == f.CommunitiesList and m[5] == 26 and m[6] == -60 then back = true end
        end
        A.truthy(back, "la lista, otra vez en su sitio del juego")
        A.same({}, a:Errors())
    end)

    it("si la ventana del juego se carga en pleno combate, lo nuestro se monta al salir (los botones seguros no se crean en combate)", function()
        local a = F.Community()
        a.w.inCombat = true
        GuildWindow(a)
        A.is_nil(rawget(a.env, "GuildUnionUnionRoster"), "en combate, nada")
        a.w.inCombat = false
        a.w:Fire("PLAYER_REGEN_ENABLED")
        A.truthy(rawget(a.env, "GuildUnionUnionRoster"), "al salir del combate, montado")
        A.same({}, a:Errors())
    end)

    it("pedir a otra hermandad que eche a alguien: el aviso nombra «Peticiones de oficiales», como el botón", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "CanOfficer", true)
        F.Stub(HU, "BestPeer", { name = "Bea-Reino", tag = "DOS" })
        local n0 = #a.w.chat
        HU:AskGuildKick("Blas-Reino", "DOS")
        A.matches("«Peticiones de oficiales»", Chat(a, n0))
        A.same({}, a:Errors())
    end)

    -- (el sistema de menús del juego, lo justo: OpenMenu apunta dónde se ata; el menú se cierra con Close (también el
    -- clic fuera de él, que el juego hace con cualquier clic) y entonces avisa a quien lo abrió)
    local function Menus(a)
        local m = { opened = 0 }
        a.env.MenuVariants = { GetDefaultContextMenuMixin = function() return "contexto" end }
        a.env.MenuUtil = { CreateRootMenuDescription = function()
            local root = { items = {} }
            function root:CreateButton(text, fn) self.items[#self.items + 1] = { text = text, fn = fn } end
            return root
        end }
        a.env.CreateAnchor = function(...) return { ... } end
        local manager = { OpenMenu = function(_, owner, desc, anchor)
            m.opened = m.opened + 1
            local menu = { owner = owner, items = desc.items, anchor = anchor }
            function menu:SetClosedCallback(fn) self.onClose = fn end
            function menu:Close() if m.open == self then m.open = nil; if self.onClose then self.onClose(self) end end end
            m.open = menu
            return menu
        end }
        a.env.Menu = { PopulateDescription = function(gen, owner, desc) gen(owner, desc) end, GetManager = function() return manager end }
        -- (un clic del jugador en el botón: gameFirst, el juego cierra el menú abierto antes de que el botón se entere)
        function m.Press(b, gameFirst)
            if gameFirst and m.open then m.open:Close() end
            b:GetScript("OnMouseDown")(b, "LeftButton")
            b:GetScript("OnClick")(b, "LeftButton")
        end
        return m
    end

    it("«Oficiales», en la vista de miembros y en la de chat: un desplegable encima con «Peticiones de oficiales» y «Ver registro»; con peticiones, el número y encendido; otro clic lo cierra", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "CanKickGuild", true)
        local m = Menus(a)
        local meta = a.w.frameMeta
        local base = meta.__index
        meta.__index = function(f, k)
            if k == "LockHighlight" then return function(self) rawset(self, "_lit", true) end end
            if k == "UnlockHighlight" then return function(self) rawset(self, "_lit", false) end end
            return base(f, k)
        end
        local create = a.env.CreateFrame
        a.env.CreateFrame = function(kind, name, parent, template, ...)
            local fr = create(kind, name, parent, template, ...)
            if type(template) == "string" and template:find("CommunitiesFrameTabTemplate", 1, true) then fr.Icon = create("Frame", nil, fr) end
            return fr
        end
        -- (las dos vistas: la de miembros, con «Ajustes de hermandad» y el «Invitar miembro» del juego; la de chat, con la
        -- pestaña de Información, para que se monte la de GuildUnion)
        GuildWindow(a, true, function(w)
            w.InviteButton = create("Button", nil, w)
            w.CommunitiesControlFrame = { GuildControlButton = create("Button", nil, w) }
            w.GuildInfoTab = create("CheckButton", nil, w)
            w.GuildPreferredPlaySettingsTab = create("CheckButton", nil, w)
            w.StreamDropdown, w.GuildBenefitsTab, w.Chat.MessageFrame = false, false, false
        end)
        for _, name in ipairs({ "GuildUnionRosterOfficers", "GuildUnionChatOfficers" }) do
            local b = a.env[name]
            A.truthy(b, name)
            A.same({ "Oficiales", false }, { b:GetText(), b._lit }, name .. ": sin peticiones")
            -- (abre su desplegable, atado encima del botón: siempre en el mismo sitio)
            m.Press(b)
            A.truthy(m.open, name .. ": abierto")
            A.same({ "BOTTOMLEFT", b, "TOPLEFT", 0, 2 }, m.open.anchor)
            A.same({ "Peticiones de oficiales", "Ver registro", "|cffff4040Echar a varios|r" },
                { m.open.items[1].text, m.open.items[2].text, m.open.items[3].text })
            -- (otro clic lo cierra, lo cierre antes el juego o el botón; y el siguiente lo vuelve a abrir)
            m.Press(b, true)
            A.falsy(m.open, name .. ": cerrado por el juego, no se vuelve a abrir")
            a.w:Advance(1)
            m.Press(b)
            A.truthy(m.open)
            m.Press(b)
            A.falsy(m.open, name .. ": cerrado por el botón")
            A.equal(2, m.opened, name .. ": abierto dos veces")
            m.opened = 0
            a.w:Advance(1)
        end
        -- (las dos opciones: sus ventanas)
        local b = a.env.GuildUnionRosterOfficers
        m.Press(b)
        m.open.items[1].fn()
        A.truthy(a.env.GuildUnionRequestsFrame:IsShown(), "Peticiones de oficiales")
        m.open:Close()
        a.w:Advance(1)
        m.Press(b)
        m.open.items[2].fn()
        A.truthy(a.env.GuildUnionInviteLogFrame:IsShown(), "Ver registro")
        m.open:Close()
        a.w:Advance(1)
        m.Press(b)
        m.open.items[3].fn()
        A.truthy(a.env.HermandadUnidaCopy:IsShown(), "Echar a varios")
        A.equal("Echar a varios de la hermandad", HU.UI.copyFrame.title:GetText())
        m.open:Close()
        -- (una petición que puedo hacer: los dos, con el número y encendidos; el desplegable, también con él)
        HU:AddKickRequest({ id = "k1", target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = a.env.time() })
        for _, name in ipairs({ "GuildUnionRosterOfficers", "GuildUnionChatOfficers" }) do
            A.same({ "Oficiales (1)", true }, { a.env[name]:GetText(), a.env[name]._lit }, name)
        end
        a.w:Advance(1)
        m.Press(b)
        A.equal("Peticiones de oficiales (1)", m.open.items[1].text)
        m.open:Close()
        HU:RemoveKickRequest("k1")
        A.same({ "Oficiales", false }, { b:GetText(), b._lit }, "contestada: como antes")
        -- (en inglés, «Officers»)
        local en = F.Community({ locale = "enUS" })
        A.equal("Officers", en.HU.L("Oficiales"))
        A.same({}, a:Errors())
    end)

    it("Comercio con chats sin leer: el botón de hermandad del menú del juego lleva el puntito con su número, en un marco nuestro (lo suyo no se toca)", function()
        local a = F.Community()
        local HU = a.HU
        local mb = a.env.CreateFrame("Button", "GuildMicroButton")
        local onClick = function() end
        mb:SetScript("OnClick", onClick)
        -- (lo nuestro, colgado del botón: el puntito y el número)
        local function Badge()
            local holder = a.env.GuildUnionMicroUnread
            if not holder then return nil end
            local out = { holder = holder }
            for _, fr in ipairs(a.w.frames) do
                if fr._parent == holder and fr._kind == "Texture" then out.dot = fr end
                if fr._parent == holder and fr._kind == "FontString" then out.num = fr end
            end
            return out
        end
        A.falsy(Badge(), "sin nada sin leer, ni se monta")
        HU:TradeChatLine("Lyra-Prueba", "Lyra-Prueba", "¿Lo tienes?")
        local b = Badge()
        A.truthy(b and b.holder._parent == mb, "colgado del botón del juego")
        A.same({ true, true, "1" }, { b.dot:IsShown(), b.num:IsShown(), b.num:GetText() })
        HU:TradeChatLine("Lyra-Prueba", "Lyra-Prueba", "¿Hola?")
        A.equal("1", b.num:GetText(), "dos líneas del mismo chat: uno")
        HU:TradeChatLine("Pepe-Prueba", "Pepe-Prueba", "Te la hago")
        A.equal("2", b.num:GetText(), "dos chats")
        F.Stub(HU, "TradeUnreadChats", 0)
        HU:Changed("tradeUnread")
        A.same({ false, false }, { b.dot:IsShown(), b.num:IsShown() }, "leídos, se va")
        A.equal(onClick, mb:GetScript("OnClick"), "sus scripts, como estaban")
        local scripts = {}
        for k in pairs(mb._scripts) do scripts[#scripts + 1] = k end
        A.same({ "OnClick" }, scripts)
        A.same({}, a:Errors())
    end)

    it("el título de la columna de profesiones, «Prof», sin punto (también en inglés)", function()
        for _, locale in ipairs({ "esES", "enUS" }) do
            local a = F.Community({ locale = locale })
            GuildWindow(a)
            local hdr, titles = a.env.GuildUnionUnionRoster.hdr, {}
            for _, fr in ipairs(a.w.frames) do if fr._parent == hdr then titles[fr:GetText()] = true end end
            A.truthy(titles.Prof, locale)
            A.falsy(titles["Prof."], locale)
            A.same({}, a:Errors())
        end
    end)
end)

describe("Comercio (Trade.lua)", function()
    local function Click(b, ...) return b:GetScript("OnClick")(b, ...) end
    -- (la ventana de hermandad del juego, en la sección Comercio)
    local function OpenTrade(a)
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        Section(a, 2)
        return cover.trade
    end
    -- (las filas de la lista de solicitudes que se ven, en orden; la de un objeto; el título de una columna)
    local function Rows(tr)
        local out = {}
        for _, r in ipairs(tr.req.rows) do if r:IsShown() and r.entry then out[#out + 1] = r end end
        return out
    end
    local function Row(tr, text)
        for _, r in ipairs(Rows(tr)) do if r.entry.item:find(text, 1, true) then return r end end
    end
    local function Header(tr, key)
        for _, h in ipairs(tr.req.hdrCells) do if h:IsShown() and h.key == key then return h end end
    end
    local function Titles(tr)
        local out = {}
        for _, h in ipairs(tr.req.hdrCells) do if h:IsShown() then out[#out + 1] = h:GetText() end end
        return out
    end
    -- (el botón de `parent` con ese texto)
    local function Btn(a, parent, text)
        for _, fr in ipairs(a.w.frames) do if fr._parent == parent and fr:GetText() == text then return fr end end
    end
    -- (pedir con la ventana «Nuevo anuncio»; en el WoW de mentira las casillas no se marcan: privada, para Bea)
    local function Ask(a, tr, item)
        tr.OpenNew(nil)
        local d = a.env.GuildUnionTradeNew
        d.item:SetText(item); d.to:SetText("Bea-Reino")
        Click(Btn(a, d, "Publicar"))
    end
    local function CtrlClick(a, row)
        a.env.IsControlKeyDown = function() return true end
        Click(row, "LeftButton")
        a.env.IsControlKeyDown = function() return false end
    end

    it("arriba, los botones Tablón · Mis encargos; debajo, el buscador a la izquierda y «Solo lo que puedo hacer» a la derecha; abajo, «+ Nuevo anuncio» y «Eliminar (N)» a su lado; sin modo prueba", function()
        local a = F.Community()
        -- (dónde se pide cada marco: el último sitio de cada punto)
        local meta = a.w.frameMeta
        local base = meta.__index
        local function SetPoint(self, p, ...)
            local pts = rawget(self, "_pts") or {}
            rawset(self, "_pts", pts)
            pts[p] = { ... }
        end
        meta.__index = function(f, k) if k == "SetPoint" then return SetPoint end return base(f, k) end
        local tr = OpenTrade(a)
        local new = tr.new
        A.equal("+ Nuevo encargo", new:GetText(), "con su texto: «Nuevo encargo»")
        A.same({ tr, "TOP", 0, -4 }, tr.switch._pts.TOP, "los botones, arriba en el centro")
        A.same({ "Tablón", "Mis encargos" }, { tr.viewBtns.pub:GetText(), tr.viewBtns.priv:GetText() }, "sus dos botones")
        A.same({ tr, "TOPLEFT", 23, -39 }, tr.search._pts.TOPLEFT, "el buscador, debajo a la izquierda")
        A.same({ tr, "TOPRIGHT", -168, -50 }, tr.onlyCraft._pts.LEFT, "«Solo lo que puedo hacer», a la derecha")
        A.same({ tr, "BOTTOM", 0, 8 }, new._pts.BOTTOM, "«+ Nuevo anuncio», abajo en el centro")
        A.same({ new, "RIGHT", 6, 0 }, tr.delBtn._pts.LEFT, "«Eliminar (N)», junto a él")
        A.is_nil(tr.testBtn, "sin modo prueba")
        -- (las filas acaban en -72: la lista empieza debajo y acaba encima del botón, que llega a 8 + 24)
        A.truthy(tr.body._pts.TOPLEFT[4] <= -44 - 28, "la lista no pisa las filas")
        A.truthy(tr.body._pts.BOTTOMRIGHT[4] >= 8 + 24, "ni el botón")
        Click(new)
        A.truthy(a.env.GuildUnionTradeNew:IsShown(), "abre la ventana de pedir")
        A.same({}, a:Errors())
    end)

    it("apagado por el maestro: solo el aviso; ni pestañas, ni buscador, ni modo prueba, ni el «+» de pedir, y no se guarda nada", function()
        local a = F.Community()
        local tr = OpenTrade(a)
        -- (la ventana de pedir, abierta de antes)
        tr.OpenNew(nil)
        local d = a.env.GuildUnionTradeNew
        A.truthy(d:IsShown())
        d.item:SetText("Algo"); d.to:SetText("Bea-Reino")
        a.HU:UnionCfg().tradeOff = true
        Click(Btn(a, d, "Publicar"))
        A.falsy(d:IsShown(), "se cierra")
        a.HU:Changed("unionCfg")
        A.truthy(tr.offMsg:IsShown(), "el aviso")
        A.falsy(tr.body:IsShown())
        for i, w in ipairs({ tr.new, tr.search, tr.switch, tr.onlyCraft }) do A.falsy(w:IsShown(), "fuera, " .. i) end
        tr.OpenNew(nil)
        A.falsy(d:IsShown(), "la ventana de pedir no se abre")
        -- (encendido otra vez: todo de vuelta, y no se había guardado nada)
        a.HU:UnionCfg().tradeOff = nil
        a.HU:Changed("unionCfg")
        A.falsy(tr.offMsg:IsShown())
        for i, w in ipairs({ tr.body, tr.new, tr.search, tr.switch, tr.onlyCraft }) do A.truthy(w:IsShown(), "de vuelta, " .. i) end
        Click(tr.viewBtns.priv)
        A.equal(0, #Rows(tr), "no se había guardado")
        A.same({}, a:Errors())
    end)

    it("sin propinas, la columna Propina no sale (ni su título ni sus casillas) en Público, Privado ni al buscar", function()
        local a = F.Community()
        a.HU:UnionCfg().tipsOff = true
        local tr = OpenTrade(a)
        a.HU:TradeTest(true)
        local function NoTips()
            for _, r in ipairs(Rows(tr)) do
                for _, c in ipairs(r.cells) do
                    local t = c:IsShown() and c:GetText() or ""
                    A.falsy(t:find("MoneyFrame", 1, true) or t:find("negociar", 1, true), t)
                end
            end
        end
        A.same({ "Quién", "Receta / objeto", "Cant.", "Mats", "Estado", "Acción" }, Titles(tr))
        NoTips()
        Click(tr.viewBtns.priv)
        A.same({ "Con quién", "Receta / objeto", "Cant.", "Estado" }, Titles(tr))
        NoTips()
        tr.search:SetText("Poción")
        tr.search:GetScript("OnTextChanged")(tr.search)
        A.equal(1, #Rows(tr), "la poción pública de Jandra")
        A.same({ "Quién", "Receta / objeto", "Cant.", "Mats", "Estado", "Acción" }, Titles(tr))
        NoTips()
        -- (con propinas otra vez, vuelve)
        tr.search:SetText("")
        tr.search:GetScript("OnTextChanged")(tr.search)
        a.HU:UnionCfg().tipsOff = nil
        a.HU:Changed("unionCfg")
        A.truthy(Header(tr, "tip"), "con propinas, su columna")
        A.same({}, a:Errors())
    end)

    it("una mía aceptada y luego eliminada de mi lista ya no cuenta para el tope de 5", function()
        local a = F.Community()
        local tr = OpenTrade(a)
        -- (el modo prueba trae 3 mías sin terminar: la capa pública, la espada que hace Pepe y la poción para Jandra)
        a.HU:TradeTest(true)
        Click(tr.viewBtns.priv)
        local espada = Row(tr, "espada")
        A.equal("taken", espada.entry.state)
        CtrlClick(a, espada)
        Click(tr.delBtn)
        A.falsy(Row(tr, "espada"), "fuera de mi lista")
        -- (quedan 2: caben 3 más, y la sexta no)
        local n0 = #a.w.chat
        for i = 1, 3 do Ask(a, tr, "Encargo " .. i) end
        A.falsy(Chat(a, n0):find("Ya tienes", 1, true), Chat(a, n0))
        A.truthy(Row(tr, "Encargo 3"), "la tercera, guardada")
        Ask(a, tr, "Encargo 4")
        A.matches("Ya tienes 5 solicitudes abiertas", Chat(a, n0))
        A.same({}, a:Errors())
    end)

    it("Privado: Ctrl+clic justo después de un clic marca las dos (antes la primera se quedaba fuera)", function()
        local a = F.Community()
        local tr = OpenTrade(a)
        a.HU:TradeTest(true)
        Click(tr.viewBtns.priv)
        local rows = Rows(tr)
        local first, second = rows[1].entry, rows[2].entry
        Click(rows[1], "LeftButton")
        CtrlClick(a, rows[2])
        A.equal("Eliminar (2)", tr.delBtn:GetText())
        A.truthy(rows[1].pickTex:IsShown()); A.truthy(rows[2].pickTex:IsShown())
        Click(tr.delBtn)
        for _, r in ipairs(Rows(tr)) do A.truthy(r.entry ~= first and r.entry ~= second, "las dos, fuera") end
        A.same({}, a:Errors())
    end)

    it("el orden por una columna que la otra vista no tiene (Mats) se quita al cambiar; por una que tienen las dos (Propina), se queda", function()
        local a = F.Community()
        local tr = OpenTrade(a)
        a.HU:TradeTest(true)
        Click(Header(tr, "mats"))
        A.equal("Mats ^", Header(tr, "mats"):GetText())
        Click(tr.viewBtns.priv)
        -- (en Privado, primero los chats con algo sin leer —la cofia de Lyra, la espada de Pepe y el elixir de Bea— y luego
        -- la poción para Jandra)
        local mats = {}
        for _, r in ipairs(Rows(tr)) do mats[#mats + 1] = r.entry.mats end
        A.same({ true, true, false, false }, mats, "sin ordenar por Mats, que aquí no está")
        for _, t in ipairs(Titles(tr)) do A.falsy(t:find(" [%^v]$"), t) end
        Click(tr.viewBtns.pub)
        A.equal("Mats", Header(tr, "mats"):GetText(), "al volver a Público, tampoco")
        Click(Header(tr, "tip"))
        Click(tr.viewBtns.priv)
        A.equal("Propina ^", Header(tr, "tip"):GetText(), "Propina está en las dos: se queda")
        A.same({}, a:Errors())
    end)

    it("«Hecha»: solo quien la hace y solo si está aceptada (ni en una abierta ni en una mía que hace otro)", function()
        local a = F.Community()
        local tr = OpenTrade(a)
        a.HU:TradeTest(true)
        Click(tr.viewBtns.priv)
        local function RowMenu(row)
            local m = FakeMenu()
            a.env.MenuUtil = { CreateContextMenu = function(_, gen) gen(nil, m) end }
            Click(row, "RightButton")
            return m
        end
        -- (abierta, me la pide Lyra: nadie la ha aceptado)
        local cofia = Row(tr, "Cofia")
        Click(cofia, "LeftButton")
        A.falsy(tr.doneBtn:IsShown(), "abierta: sin «Hecha»")
        Click(tr.doneBtn)
        A.equal("open", cofia.entry.state)
        A.falsy(MenuItem(RowMenu(cofia), "Marcar como hecha"))
        -- (mía y aceptada por Pepe: la hace él, no yo)
        local espada = Row(tr, "espada")
        Click(espada, "LeftButton")
        A.falsy(tr.doneBtn:IsShown(), "la hace Pepe")
        A.falsy(MenuItem(RowMenu(espada), "Marcar como hecha"))
        -- (la de Bea, aceptada por mí con el tic: ahora sí)
        Click(Row(tr, "Elixir").yes)
        local elixir = Row(tr, "Elixir")
        A.equal("taken", elixir.entry.state)
        Click(elixir, "LeftButton")
        A.truthy(tr.doneBtn:IsShown())
        A.truthy(MenuItem(RowMenu(elixir), "Marcar como hecha"))
        Click(tr.doneBtn)
        A.equal("done", Row(tr, "Elixir").entry.state)
        A.same({}, a:Errors())
    end)

    it("dos solicitudes en el mismo segundo llevan id distinto aunque el azar repita, con la huella de quien pide", function()
        local a = F.Community()
        local tr = OpenTrade(a)
        -- (un azar que da siempre lo mismo)
        a.env.math = setmetatable({ random = function() return 7 end }, { __index = math })
        Ask(a, tr, "Uno")
        Ask(a, tr, "Dos")
        a.env.math = nil
        local rows = Rows(tr)
        A.equal(2, #rows)
        local id1, id2 = rows[1].entry.id, rows[2].entry.id
        A.truthy(id1 ~= id2, "iguales: " .. tostring(id1))
        local mark = a.HU.Hash(a.HU:Me()):sub(1, 4)
        A.equal(mark, id1:sub(1, 4)); A.equal(mark, id2:sub(1, 4))
        A.truthy(#id1 <= 16, "corto: " .. id1)
        A.same({}, a:Errors())
    end)

    it("las sugerencias de objetos son las mejores de todos: el nombre exacto, luego los que empiezan así, por nombre", function()
        local a = F.Community()
        -- (el juego conoce todos los fabricables: casi todos «Paño de lino N» y tres que empiezan por «Lino»)
        local ids, seen = {}, {}
        for _, list in pairs(a.HU.CRAFT_ITEMS) do
            for i = 1, #list - 1, 2 do if not seen[list[i]] then seen[list[i]] = true; ids[#ids + 1] = list[i] end end
        end
        table.sort(ids)
        local special = { [ids[#ids]] = "Lino grueso", [ids[#ids - 1]] = "Lino", [ids[#ids - 2]] = "Lino fino" }
        a.env.C_Item.GetItemInfo = function(id)
            if type(id) ~= "number" then return nil end
            local name = special[id] or ("Paño de lino " .. id)
            return name, "|cffffffff|Hitem:" .. id .. "::::::::60:::::::|h[" .. name .. "]|h|r"
        end
        local tr = OpenTrade(a)
        a.w:Advance(60) -- (los nombres se piden poco a poco: 30 cada medio segundo)
        tr.search:SetText("lino")
        tr.search:GetScript("OnTextChanged")(tr.search, true)
        -- (los botones de la lista de sugerencias, la que cuelga del buscador)
        local list
        for _, fr in ipairs(a.w.frames) do if fr._parent == tr.search and fr._kind == "Frame" then list = fr end end
        local shown = {}
        for _, fr in ipairs(a.w.frames) do
            if fr._parent == list and fr._kind == "Button" and fr:IsShown() then shown[#shown + 1] = fr.text:GetText():match("%[(.-)%]") end
        end
        A.equal(6, #shown)
        A.same({ "Lino", "Lino fino", "Lino grueso" }, { shown[1], shown[2], shown[3] })
        A.same({}, a:Errors())
    end)

    it("los encantamientos (hechizos, no objetos) salen en las sugerencias con su enlace, en el idioma del juego", function()
        local a = F.Community()
        local list = a.HU.CRAFT_SPELLS[333]
        local first = list[1]
        A.truthy(#list >= 200, "los de vanilla, con su nivel")
        local link = "|cff71d5ff|Hspell:" .. first .. ":0|h[Encantar brazales: salud inferior]|h|r"
        a.env.C_Spell = {
            GetSpellName = function(id) if id == first then return "Encantar brazales: salud inferior" end end,
            GetSpellLink = function(id) if id == first then return link end end,
        }
        local tr = OpenTrade(a)
        a.w:Advance(1)
        tr.search:SetText("brazales")
        tr.search:GetScript("OnTextChanged")(tr.search, true)
        local box
        for _, fr in ipairs(a.w.frames) do if fr._parent == tr.search and fr._kind == "Frame" then box = fr end end
        local shown = {}
        for _, fr in ipairs(a.w.frames) do
            if fr._parent == box and fr._kind == "Button" and fr:IsShown() then shown[#shown + 1] = fr.text:GetText() end
        end
        A.same({ link }, shown)
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

    it("las líneas de las otras hermandades, cada una en su chat de la ventana: las de oficiales, en el de oficiales", function()
        local a = F.Community()
        local HU = a.HU
        local f = a.env.CreateFrame("Frame", "CommunitiesFrame")
        f.Chat = a.env.CreateFrame("Frame", nil, f)
        f.Chat.MessageFrame = a.env.CreateFrame("Frame", nil, f.Chat)
        local got = {}
        f.Chat.MessageFrame.AddMessage = function(_, line) got[#got + 1] = line end
        local stream = 1   -- (1: el de la hermandad; 2: el de oficiales, Enum.ClubStreamType)
        f.GetSelectedClubId = function() return 7 end
        f.GetSelectedStreamId = function() return stream end
        a.env.C_Club = { GetClubInfo = function() return { clubType = 2 } end, GetStreamInfo = function(_, id) return { streamType = id } end }
        HU:Display("off", "DOS", "Bea-Reino", "hola oficiales")
        HU:Display("main", "DOS", "Bea-Reino", "hola todos")
        A.equal(1, #got, "en el chat general, solo la general")
        A.truthy(got[1]:find("hola todos", 1, true))
        stream, got = 2, {}
        HU:Display("off", "DOS", "Bea-Reino", "otra de oficiales")
        HU:Display("main", "DOS", "Bea-Reino", "otra general")
        A.equal(1, #got, "en el de oficiales, solo la de oficiales (Jorge, 24/11: «tiene que ser de todos»)")
        A.truthy(got[1]:find("otra de oficiales", 1, true))
        A.same({}, a:Errors())
    end)

    it("con «Nivel» en Ajustes (db.chatLevel), el nivel de quien escribe delante de su nombre, si se sabe", function()
        local a = F.Community()
        local HU = a.HU
        HU.remoteRoster.DOS = { members = { { name = "Bea-Reino", level = 42 } } }
        local head = HU:FormatLineParts("main", "DOS", "Bea-Reino", "hola", nil, "blizz")
        A.falsy(head:find("|cffaaaaaa42|r", 1, true), "sin la opción, nada")
        HU.db.chatLevel = true
        head = HU:FormatLineParts("main", "DOS", "Bea-Reino", "hola", nil, "blizz")
        A.truthy(head:find("|cffaaaaaa42|r ", 1, true), "su nivel, en gris")
        A.truthy(HU:FormatLine("main", "DOS", "Bea-Reino", "hola"):find("|cffaaaaaa42|r ", 1, true), "también en el chat del addon")
        A.falsy(HU:FormatLine("main", "DOS", "Nadie-Reino", "hola"):find("|cffaaaaaa", 1, true), "sin nivel sabido, nada")
        A.same({}, a:Errors())
    end)

    it("el nivel, de todos los de las otras hermandades: también de sus listas completas (MB), con un índice que solo se rehace si cambian (Jorge, 25/11)", function()
        local a = F.Community()
        local HU = a.HU
        HU.db.chatLevel = true
        -- (la lista completa de DOS, ya comprobada: un trozo con su huella)
        local function Pack(hash, lines)
            HU.db.packs = HU.db.packs or {}
            HU.db.packs.DOS = { MB = { h = { hash }, ok = { hash }, t = { lines } } }
            HU.packSets.MB.onChange("DOS")
        end
        Pack("h1", { "Bea-Reino,8,37,1", "Blas-Reino,1,12,4", "Nuevo-Reino,1,0,4" })
        local built, real = 0, HU.PackedMembers
        HU.PackedMembers = function(...) built = built + 1; return real(...) end
        A.truthy(HU:FormatLine("main", "DOS", "Blas-Reino", "hola"):find("|cffaaaaaa12|r ", 1, true), "de su lista completa")
        A.equal(37, HU:LevelOf("Bea-Reino"))
        A.is_nil(HU:LevelOf("Nuevo-Reino"), "nivel 0: no se sabe")
        A.equal(1, built, "el índice, una vez")
        for _ = 1, 50 do HU:LevelOf("Blas-Reino") end
        A.equal(1, built, "cada línea del chat, solo mira el índice")
        -- (llega algo de Miembros, no de su lista completa: el índice no se rehace)
        HU:Changed("unionMembers")
        A.equal(12, HU:LevelOf("Blas-Reino"))
        A.equal(1, built)
        -- (cambia su lista completa: se rehace, una vez)
        Pack("h2", { "Bea-Reino,8,38,1", "Blas-Reino,1,12,4" })
        A.equal(38, HU:LevelOf("Bea-Reino"))
        A.equal(12, HU:LevelOf("Blas-Reino"))
        A.equal(2, built)
        -- (la lista ligera, RB, va antes: está más al día; y lo de mi hermandad, de la lista del juego)
        HU.remoteRoster.DOS = { members = { { name = "Bea-Reino", level = 39 } } }
        A.equal(39, HU:LevelOf("Bea-Reino"))
        A.is_nil(HU:LevelOf("Nadie-Reino"))
        A.same({}, a:Errors())
    end)

    it("al poner «Nivel» en Ajustes se piden las listas completas de las otras hermandades (de ahí sale el nivel); al quitarlo, no", function()
        local a = F.Community()
        local HU = a.HU
        local asked = {}
        F.Stub(HU, "PackNeed", function(_, tag, id) asked[#asked + 1] = tag .. "|" .. id end)
        HU:OpenMainWindow()
        local cb = a.env.GuildUnionReducePanel.levelCheck
        cb.GetChecked = function() return true end
        cb:GetScript("OnClick")(cb)
        A.truthy(HU.db.chatLevel)
        A.same({ "DOS|MB" }, asked)
        cb.GetChecked = function() return false end
        cb:GetScript("OnClick")(cb)
        A.is_nil(HU.db.chatLevel)
        A.same({ "DOS|MB" }, asked)
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
        HU:AddKickRequest({ id = "k1", target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = a.env.time() })
        HU:AddKickRequest({ id = "k1", target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = a.env.time() })
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
        HU:AddKickRequest({ id = "r1", kind = "rank", rank = 1, target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = a.env.time() })
        A.equal(0, HU:KickRequestCount(), "a oficial: no la puedo dar")
        HU:AddKickRequest({ id = "r2", kind = "rank", rank = 3, target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = a.env.time() })
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
        -- (en el filtro de echar: el tic y la X quitan dos)
        local tk = win.tabs.kick
        tk:GetScript("OnClick")(tk)
        win.rows[1].yes:GetScript("OnClick")(win.rows[1].yes)
        A.equal(4, HU:KickRequestCount())
        win.Refresh()
        win.rows[1].no:GetScript("OnClick")(win.rows[1].no)
        A.equal(3, HU:KickRequestCount())
        -- (el filtro de rango enseña solo las 2 de rango)
        local tr = win.tabs.rank
        tr:GetScript("OnClick")(tr)
        local shown = {}
        for _, row in ipairs(win.rows) do if row:IsShown() and row.entry then shown[#shown + 1] = row.entry.target end end
        table.sort(shown)
        A.same({ "Prueba-Cinco", "Prueba-Cuatro" }, shown)
        -- (y una de prueba se quita con el tic aunque yo no pueda cambiar rangos: no manda nada)
        win.rows[1].yes:GetScript("OnClick")(win.rows[1].yes)
        A.equal(2, HU:KickRequestCount())
        A.equal(0, sent, "las de prueba no mandan nada")
        A.same({}, a:Errors())
    end)
end)
