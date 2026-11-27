-- Eventos entre hermandades (Packs/Events.lua, conjunto EV, y UnionCalendar.lua, la sección Eventos): lo que crea uno lo ve
-- su hermandad al momento y las otras al abrir la sección; quién se apunta viaja igual, y todo sigue tras /reload. Lo que
-- su creador edita o elimina, igual. Todo por la ventana, como lo hace cada jugador
local red = require("lib.red")
local F = require("lib.fixtures")
local A = assert_

-- Avanza de 5 en 5 s hasta que se cumpla; devuelve los segundos o nil
local function Until(net, cond, max)
    local t = 0
    while t < max do
        if cond() then return t end
        net:Advance(5)
        t = t + 5
    end
    return cond() and t or nil
end

-- UNO: Ana (oficial) y Alba; DOS: Bea (oficial) y Blas; TRES: Tere (oficial) y Toni. Los de `late` no entran todavía
local function Union(late)
    local net = red.New({ step = 0.5, info = table.concat({ F.INFO, "GU:g:Hermandad Tres:TRES" }, "\n"),
        guilds = { UNO = "Hermandad Uno", DOS = "Hermandad Dos", TRES = "Hermandad Tres" } })
    local p = {
        ana = net:Player("Ana", "UNO", { rankIndex = 1 }),
        alba = net:Player("Alba", "UNO"),
        bea = net:Player("Bea", "DOS", { rankIndex = 1 }),
        blas = net:Player("Blas", "DOS"),
        tere = net:Player("Tere", "TRES", { rankIndex = 1 }),
        toni = net:Player("Toni", "TRES"),
    }
    for _, n in ipairs({ "ana", "alba", "bea", "blas", "tere", "toni" }) do
        if not (late and late[n]) then net:Login(p[n]) end
    end
    net:Advance(150)
    return net, p
end

---------------------------------------------------------------------------
-- La ventana de cada uno
---------------------------------------------------------------------------
local function Click(b, ...) return b:GetScript("OnClick")(b, ...) end
local function Child(p, parent, text)
    for _, f in ipairs(p.w.frames) do
        if f._parent == parent and f._kind == "Button" and f:GetText() == text then return f end
    end
end

-- La sección Eventos abierta como lo hace el jugador: la ventana de hermandad del juego (lo justo) y su pestaña. Al
-- abrirla se lanza su OnShow, como en el juego
local function Open(p)
    local env = p.env
    local f = env.CreateFrame("Frame", "CommunitiesFrame")
    f.Chat, f.GuildInfoTab, f.CommunitiesControlFrame = false, false, false
    f.RosterTab = env.CreateFrame("CheckButton", nil, f)
    f.CommunitiesList = env.CreateFrame("Frame", nil, f)
    f.MemberList = env.CreateFrame("Frame", nil, f)
    f.MemberList.IsVisible = function() return true end
    local chk = env.CreateFrame("CheckButton", nil, f.MemberList)
    f.MemberList.ShowOfflineButton = chk
    chk.IsVisible = function() return true end
    p.w:Fire("ADDON_LOADED", "Blizzard_Communities")
    local cover = env.GuildUnionUnionRoster
    local ui = cover.calendar
    -- (las listas con barra del juego traen su barra; esta solo recuerda dónde está)
    for _, sf in ipairs({ ui.scroll, env.GuildUnionCalendarBenchScroll, env.GuildUnionCalendarDayScroll, env.GuildUnionCalendarTimeScroll }) do
        local bar = env.CreateFrame("Slider", nil, sf)
        bar.value = 0
        bar.GetValue = function(self) return self.value end
        bar.SetValue = function(self, v) self.value = v end
        sf.ScrollBar = bar
    end
    ui.SetShown = function(self, v)
        local was = self._shown
        self._shown = v and true or false
        local s = was ~= self._shown and self:GetScript(v and "OnShow" or "OnHide")
        if s then s(self) end
    end
    for _, b in ipairs(cover.side.tabs) do
        if b.tab == 3 then b:GetScript("PreClick")(b); b:GetScript("PostClick")(b) end
    end
    return ui
end

local function Card(ui, title)
    for _, c in ipairs(ui.cards) do if c:IsShown() and c.title:GetText() == title then return c end end
end
local function Titles(ui)
    local out = {}
    for _, c in ipairs(ui.cards) do if c:IsShown() then out[#out + 1] = c.title:GetText() end end
    table.sort(out)
    return out
end
-- (cuántos van, en la tarjeta: «… 2 van»)
local function Going(c) return c and tonumber(c.going:GetText():match("(%d+) van$")) end
-- (quién está en el banquillo de la ficha)
local function Bench(d)
    local out = {}
    for _, b in ipairs(d.bench) do if b:IsShown() then out[#out + 1] = b.name end end
    return out
end
-- (el menú del clic derecho del juego, de mentira: recuerda los que se abren, con sus botones)
local function Menus(p)
    local opened = {}
    local function Menu()
        local m = { items = {} }
        function m:CreateTitle(t) self.title = t end
        function m:CreateButton(text, fn)
            local sub = Menu()
            sub.text, sub.fn = text, fn
            self.items[#self.items + 1] = sub
            return sub
        end
        return m
    end
    p.env.MenuUtil = { CreateContextMenu = function(owner, gen)
        local root = Menu()
        gen(owner, root)
        opened[#opened + 1] = root
    end }
    return opened
end
local function Item(menu, text)
    for _, it in ipairs(menu.items) do if it.text == text then return it end end
end

-- Un evento nuevo con la ventana, mañana a las 20:00
local function Create(p, ui, title)
    Click(ui.new)
    local nd = ui.newDlg
    nd.title:SetText(title)
    Click(nd.dayBtn)
    local dp = nd.popups[2]
    local tm = p.env.date("*t", p.env.time() + 86400)
    if tm.month ~= dp.m then Click(Child(p, dp, ">")) end
    for _, c in ipairs(dp.cells) do if c:IsShown() and c.day == tm.day then Click(c) end end
    Click(Child(p, nd, "Crear"))
    A.falsy(nd:IsShown(), "no se ha creado: " .. title)
end

describe("Eventos entre hermandades (EV)", function()
    it("lo que crea Ana lo ve Alba (UNO) al momento y Bea (DOS) y Tere (TRES) al abrir el calendario; Bea se apunta y Ana la ve", function()
        local net, p = Union({ bea = true, tere = true })
        local ui = { ana = Open(p.ana), alba = Open(p.alba) }
        Create(p.ana, ui.ana, "Noche de Onyxia")
        A.same({ "Noche de Onyxia" }, Titles(ui.ana))
        net:Advance(2)
        A.same({ "Noche de Onyxia" }, Titles(ui.alba), "Alba, al momento")
        A.equal("|cffa0a4adpor|r |cffffd100Ana-Reino|r |cff33ff99<UNO>|r", Card(ui.alba, "Noche de Onyxia").who:GetText())
        -- (Bea y Tere entran después, sin nada de UNO: al abrir el calendario lo piden y les llega con el paquete de UNO)
        net:Advance(120)
        net:Login(p.bea)
        net:Login(p.tere)
        net:Advance(30)
        A.is_nil(p.bea.HU:PackGet("UNO", "EV"), "Bea no tiene nada de UNO")
        ui.bea, ui.tere = Open(p.bea), Open(p.tere)
        -- (el evento y el apuntado de Ana van en líneas aparte, y pueden caer en trozos distintos: se espera a los dos)
        A.truthy(Until(net, function()
            return Going(Card(ui.bea, "Noche de Onyxia")) == 1 and Going(Card(ui.tere, "Noche de Onyxia")) == 1
        end, 300), "no llega a DOS y TRES, con Ana apuntada")
        A.matches("Ana%-Reino|r |cff%x+<UNO>|r$", Card(ui.bea, "Noche de Onyxia").who:GetText(), "de UNO")
        A.matches("Ana%-Reino|r |cff%x+<UNO>|r$", Card(ui.tere, "Noche de Onyxia").who:GetText())
        -- (Bea se apunta: le llega a Ana con el paquete de DOS; con el calendario abierto, Ana pide lo que le falte)
        Click(Card(ui.bea, "Noche de Onyxia").join)
        A.matches("Apuntado", Card(ui.bea, "Noche de Onyxia").join:GetText())
        A.equal(2, Going(Card(ui.bea, "Noche de Onyxia")))
        A.truthy(Until(net, function() return Going(Card(ui.ana, "Noche de Onyxia")) == 2 end, 400), "Ana no ve a Bea")
        Click(Card(ui.ana, "Noche de Onyxia").info)
        A.same({ "Ana-Reino", "Bea-Reino" }, Bench(ui.ana.detail), "en la ficha de Ana, las dos")
        A.same({}, net:Errors())
    end)

    it("tras /reload de Alba sigue; y lo que Ana crea con Alba desconectada, Alba lo ve al abrir el calendario", function()
        local net, p = Union()
        local ui = Open(p.ana)
        Create(p.ana, ui, "Primero")
        net:Advance(2)
        net:Logout(p.alba)
        net:Login(p.alba)
        net:Advance(30)
        A.same({ "Primero" }, Titles(Open(p.alba)), "tras /reload")
        -- (Alba se va; Ana crea otro; Alba vuelve y abre el calendario)
        net:Logout(p.alba)
        Create(p.ana, ui, "Mientras no estabas")
        net:Advance(5)
        net:Login(p.alba)
        net:Advance(30)
        local alba = Open(p.alba)
        A.same({ "Primero" }, Titles(alba), "no lo oyó")
        -- (el evento y el apuntado de Ana van en líneas aparte, y pueden caer en trozos distintos: se espera a los dos)
        A.truthy(Until(net, function() return Going(Card(alba, "Mientras no estabas")) == 1 end, 300), "no le llega, con Ana apuntada")
        A.same({ "Mientras no estabas", "Primero" }, Titles(alba))
        A.same({}, net:Errors())
    end)

    it("Ana organiza: pone a Bea (DOS) en su raid y, cuando Bea sale del evento, sale también de la raid", function()
        local net, p = Union()
        local ana, bea = Open(p.ana), Open(p.bea)
        Create(p.ana, ana, "Banda")
        A.truthy(Until(net, function() return Card(bea, "Banda") end, 300), "no llega a DOS")
        Click(Card(bea, "Banda").join)
        A.truthy(Until(net, function() return Going(Card(ana, "Banda")) == 2 end, 400), "Ana no ve a Bea")
        -- (la raid la lleva Ana; «Colocar en raids» mete a Bea)
        Click(Card(ana, "Banda").info)
        local d = ana.detail
        Click(d.addRaid)
        A.equal("Ana-Reino", d.picker.rows[1].value)
        Click(d.picker.rows[1])
        Click(d.place)
        A.equal("Raid 1 (2)", d.raidTabs[1]:GetText())
        -- (Bea sale: en cuanto Ana tiene lo de DOS al día, ya no está en la raid ni en el banquillo)
        Click(Card(bea, "Banda").join)
        Click(Child(p.bea, p.bea.env.GuildUnionCalendarConfirm, "Sí"))
        A.equal(1, Going(Card(bea, "Banda")))
        A.truthy(Until(net, function() return d.raidTabs[1]:GetText() == "Raid 1 (1)" end, 400), "Bea sigue en la raid de Ana")
        A.equal(1, Going(Card(ana, "Banda")))
        A.same({}, Bench(d))
        A.same({}, net:Errors())
    end)

    it("Ana edita su evento y luego lo elimina (clic derecho): Alba (UNO) lo ve al momento y Bea (DOS), cambiado y con las dos apuntadas, y luego borrado; a Bea, el de Ana no le da menú", function()
        local net, p = Union()
        local ana, alba, bea = Open(p.ana), Open(p.alba), Open(p.bea)
        Create(p.ana, ana, "Noche de Onyxia")
        A.truthy(Until(net, function() return Card(bea, "Noche de Onyxia") end, 300), "no llega a DOS")
        Click(Card(bea, "Noche de Onyxia").join)
        A.truthy(Until(net, function() return Going(Card(ana, "Noche de Onyxia")) == 2 end, 400), "Ana no ve a Bea")
        -- (Bea, en el de Ana: el clic derecho no le saca nada)
        local beaMenus = Menus(p.bea)
        Click(Card(bea, "Noche de Onyxia"), "RightButton")
        A.equal(0, #beaMenus, "no es suyo")
        -- (Ana lo edita: otro título y otra hora)
        local menus = Menus(p.ana)
        Click(Card(ana, "Noche de Onyxia"), "RightButton")
        Item(menus[#menus], "Editar evento").fn()
        local nd = ana.newDlg
        A.equal("Editar evento", nd.titleText:GetText())
        A.equal("Noche de Onyxia", nd.title:GetText())
        nd.title:SetText("Noche de Ragnaros")
        -- (la hora, en su lista de 15 en 15: bajando hasta las 21:30)
        Click(nd.hourBtn)
        local tsf = p.ana.env.GuildUnionCalendarTimeScroll
        p.ana.env.FauxScrollFrame_SetOffset(tsf, 21 * 4 + 2)
        tsf:GetScript("OnVerticalScroll")(tsf, 0)
        Click(nd.popups[3].rows[1])
        A.equal("21:30", nd.hourBtn:GetText())
        Click(Child(p.ana, nd, "Guardar"))
        A.falsy(nd:IsShown())
        A.same({ "Noche de Ragnaros" }, Titles(ana))
        A.equal(2, Going(Card(ana, "Noche de Ragnaros")))
        net:Advance(2)
        A.same({ "Noche de Ragnaros" }, Titles(alba), "Alba, al momento")
        A.truthy(Until(net, function() return Card(bea, "Noche de Ragnaros") ~= nil end, 400), "a Bea no le llega cambiado")
        A.same({ "Noche de Ragnaros" }, Titles(bea), "el mismo evento, no otro")
        local c = Card(bea, "Noche de Ragnaros")
        A.matches("21:30", c.kind:GetText())
        A.equal(2, Going(c), "Ana y Bea, apuntadas")
        A.matches("Apuntado", c.join:GetText())
        -- (Ana lo elimina)
        Click(Card(ana, "Noche de Ragnaros"), "RightButton")
        Item(menus[#menus], "Eliminar").fn()
        Click(Child(p.ana, p.ana.env.GuildUnionCalendarConfirm, "Sí"))
        A.same({}, Titles(ana))
        net:Advance(2)
        A.same({}, Titles(alba), "Alba, al momento")
        A.truthy(Until(net, function() return #Titles(bea) == 0 end, 400), "a Bea no le llega borrado")
        A.truthy(bea.empty:IsShown(), "«No hay eventos próximos»")
        A.same({}, net:Errors())
    end)
    it("Ana fija su evento para todos (Jorge, 25/11): Bea (DOS) lo ve arriba con la estrella; el fijado de quien no lo creó no cuenta; Ana lo quita y en DOS vuelve sin estrella", function()
        local net, p = Union()
        local ana, bea = Open(p.ana), Open(p.bea)
        Create(p.ana, ana, "Primero")
        Create(p.ana, ana, "Segundo")
        local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14:14|t "
        local function Top(ui) local c = ui.cards[1]; return c:IsShown() and c.title:GetText() or nil end
        A.truthy(Until(net, function() return Card(bea, "Primero") and Card(bea, "Segundo") end, 300), "no llegan a DOS")
        -- (Ana fija «Segundo»: arriba, con la estrella, para ella al momento y para Bea en cuanto le llega)
        local menus = Menus(p.ana)
        Click(Card(ana, "Segundo"), "RightButton")
        Item(menus[#menus], "Fijar arriba para todos").fn()
        net:Advance(1)
        A.equal(STAR .. "Segundo", Top(ana))
        A.truthy(Until(net, function() return Top(bea) == STAR .. "Segundo" end, 400), "DOS no lo ve fijado")
        -- (Bea fija «Primero», que no es suyo, por la red: no cuenta, ni para ella ni para Ana)
        A.truthy(p.bea.HU:ProposeEventPin(Card(bea, "Primero").id, true))
        net:Advance(120)
        A.equal(STAR .. "Segundo", Top(bea))
        A.truthy(Card(bea, "Primero"), "sin estrella en DOS")
        A.truthy(Card(ana, "Primero"), "sin estrella en UNO")
        -- (en el de Ana, Bea no tiene menú)
        local beaMenus = Menus(p.bea)
        Click(Card(bea, STAR .. "Segundo"), "RightButton")
        A.equal(0, #beaMenus, "no es suyo")
        -- (Ana lo quita: en DOS vuelve sin estrella)
        Click(Card(ana, STAR .. "Segundo"), "RightButton")
        Item(menus[#menus], "Quitar de arriba").fn()
        A.truthy(Until(net, function() return Card(bea, "Segundo") ~= nil end, 400), "DOS lo sigue viendo fijado")
        A.truthy(Card(ana, "Segundo"))
        A.same({}, net:Errors())
    end)
end)

describe("Raids entre hermandades (EV): bandas de 10, 20 o 40", function()
    -- (una banda nueva de Ana, de `size`, desde Raids, mañana a las 20:00)
    local function NewBand(p, ui, title, size)
        Click(ui.viewBtns.raids)
        Click(ui.new)
        local nd = ui.newDlg
        for _, b in ipairs(nd.sizeBtns) do if b.size == size then Click(b) end end
        nd.title:SetText(title)
        Click(nd.dayBtn)
        local dp = nd.popups[2]
        local tm = p.env.date("*t", p.env.time() + 86400)
        if tm.month ~= dp.m then Click(Child(p, dp, ">")) end
        for _, c in ipairs(dp.cells) do if c:IsShown() and c.day == tm.day then Click(c) end end
        Click(Child(p, nd, "Crear"))
        A.falsy(nd:IsShown(), "no se ha creado: " .. title)
    end
    -- (alguien de UNO que no se conecta: lo que manda su addon por GUILD les llega a los de UNO conectados)
    local function FromUno(net, p, name, key, data)
        for _, q in ipairs(net:Guildmates(p)) do
            q.w:Receive("HU20B", "WU~UNO~EV~" .. key .. "~" .. q.HU.StampNow() .. "~" .. data, "GUILD", name)
        end
    end

    it("la banda de 10 de Ana se llena con su hermandad: en DOS sale «10/10 · Completo» y Bea se apunta de reserva; Ana la ve en la reserva, la sube a la raid y en DOS Bea ya va", function()
        local net, p = Union()
        local ana, bea = Open(p.ana), Open(p.bea)
        NewBand(p.ana, ana, "Banda de diez", 10)
        local id
        for _, e in pairs(p.ana.HU.db.wuStore.UNO.EV) do if e.k:sub(1, 1) == "e" then id = e.k:sub(2) end end
        for k = 1, 9 do FromUno(net, p.ana, "Uno" .. string.char(96 + k) .. "-Reino", "s" .. id, "D") end
        net:Advance(1)
        Click(bea.viewBtns.raids)
        A.truthy(Until(net, function()
            local c = Card(bea, "Banda de diez")
            return c and c.going:GetText() == "10/10 · Completo"
        end, 400), "a DOS no le llega completa")
        local c = Card(bea, "Banda de diez")
        A.equal("Ir de reserva", c.join:GetText())
        A.matches("Banda de 10", c.kind:GetText())
        local menus = Menus(p.bea)
        Click(c.join)
        for _, it in ipairs(menus[#menus].items) do if it.text:find("Daño", 1, true) then it.fn() end end
        A.matches("Reserva", c.join:GetText())
        A.equal("Dr", p.bea.HU.db.wuStore.DOS.EV["bea-reino,s" .. id].d, "de reserva, a la red")
        -- (Ana, en su ficha: Bea en la reserva, aparte)
        local d
        A.truthy(Until(net, function()
            local ac = Card(ana, "Banda de diez")
            if not ac then return false end
            Click(ac.info)
            d = ana.detail
            for _, b in ipairs(d.bench) do if b:IsShown() and b.name == "Bea-Reino" then return true end end
            return false
        end, 400), "Ana no ve a Bea")
        local header
        for _, b in ipairs(d.bench) do if b:IsShown() and not b.name then header = b.text:GetText() end end
        A.equal("|cffffb040Reserva|r  |cffa0a4ad(1)|r", header)
        -- (Ana la sube a la raid: en DOS, Bea ya va)
        local row
        for _, b in ipairs(d.bench) do if b:IsShown() and b.name == "Bea-Reino" then row = b end end
        row:GetScript("OnDragStart")(row)
        d.groups[1].IsMouseOver = function() return true end
        row:GetScript("OnDragStop")(row)
        d.groups[1].IsMouseOver = nil
        A.equal("Raid 1 (2)", d.raidTabs[1]:GetText())
        A.truthy(Until(net, function() return Card(bea, "Banda de diez").join:GetText():find("Apuntado", 1, true) ~= nil end, 400),
            "en DOS, Bea sigue de reserva")
        A.equal("|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t 11/10 · Completo", Card(bea, "Banda de diez").going:GetText())
        A.same({}, net:Errors())
    end)

    it("por invitación: Ana invita a 40 (su lista, en 7 líneas que salen de poco en poco), entre ellos a Bea (DOS) y Tere (TRES), las últimas: ellas la ven y Alba, Blas y Toni no; Ana quita a Tere y Tere deja de verla", function()
        local net, p = Union()
        local ui = {}
        for _, n in ipairs({ "ana", "alba", "bea", "blas", "tere", "toni" }) do
            ui[n] = Open(p[n])
            Click(ui[n].viewBtns.raids)
        end
        -- (38 de nombre largo, que van antes que Bea y Tere: 6 por línea)
        Click(ui.ana.new)
        local nd = ui.ana.newDlg
        Click(nd.accessBtns[2])
        for k = 1, 38 do nd.invBox:SetText(string.format("Aaaaaaaaaa%02d-Apellidolargo", k)); Click(nd.invAdd) end
        for _, n in ipairs({ "Bea-Reino", "Tere-Reino" }) do nd.invBox:SetText(n); Click(nd.invAdd) end
        A.equal("Invitados (40/40):", nd.invLabel:GetText())
        nd.title:SetText("Solo invitados")
        Click(nd.dayBtn)
        local dp = nd.popups[2]
        local tm = p.ana.env.date("*t", p.ana.env.time() + 86400)
        if tm.month ~= dp.m then Click(Child(p.ana, dp, ">")) end
        for _, c in ipairs(dp.cells) do if c:IsShown() and c.day == tm.day then Click(c) end end
        Click(Child(p.ana, nd, "Crear"))
        A.falsy(nd:IsShown())
        local parts = 0
        for _, e in pairs(p.ana.HU.db.wuStore.UNO.EV) do if e.k:match("^i") then parts = parts + 1 end end
        A.equal(3, parts, "3 líneas ya")
        A.truthy(Card(ui.ana, "Solo invitados"), "quien la crea, siempre")
        A.truthy(Until(net, function() return Card(ui.bea, "Solo invitados") and Card(ui.tere, "Solo invitados") end, 600),
            "Bea y Tere no la ven")
        parts = 0
        for _, e in pairs(p.ana.HU.db.wuStore.UNO.EV) do if e.k:match("^i") then parts = parts + 1 end end
        A.equal(7, parts, "las 7")
        net:Advance(120)
        for _, n in ipairs({ "alba", "blas", "toni" }) do A.is_nil(Card(ui[n], "Solo invitados"), n .. " la ve") end
        Click(ui.alba.viewBtns.month)
        for _, c in ipairs(ui.alba.grid.cells) do A.equal("", c.ev:GetText(), "ni en el mes de Alba") end
        A.matches("Por invitación", Card(ui.bea, "Solo invitados").kind:GetText())
        -- (Ana quita a Tere)
        local menus = Menus(p.ana)
        Click(Card(ui.ana, "Solo invitados"), "RightButton")
        for _, it in ipairs(menus[#menus].items) do if it.text == "Editar evento" then it.fn() end end
        A.equal("Invitados (40/40):", nd.invLabel:GetText(), "con sus invitados")
        -- (Tere, la última: con la barra abajo del todo)
        local isf = p.ana.env.GuildUnionCalendarInviteScroll
        p.ana.env.FauxScrollFrame_SetOffset(isf, 35)
        isf:GetScript("OnVerticalScroll")(isf, 35 * 16)
        A.equal("Tere-Reino", nd.invRows[5].name)
        Click(nd.invRows[5])
        A.equal("Invitados (39/40):", nd.invLabel:GetText())
        Click(Child(p.ana, nd, "Guardar"))
        A.truthy(Until(net, function() return Card(ui.tere, "Solo invitados") == nil end, 600), "Tere la sigue viendo")
        A.truthy(Card(ui.bea, "Solo invitados"), "Bea, sí")
        A.same({}, net:Errors())
    end)
end)

describe("Eventos (EV): cuánto vive cada cosa", function()
    it("un evento borrado vive 90 días (más que el evento: una copia vieja no lo resucita); lo desapuntado, 45", function()
        local HU = F.Community().HU
        local alive, DAY, t0 = HU.packSets.EV.alive, 86400, 1800000000
        A.truthy(alive("Ana-Reino", "eabc", "", t0, t0 + 89 * DAY), "borrado: a los 89 días, sigue")
        A.falsy(alive("Ana-Reino", "eabc", "", t0, t0 + 91 * DAY), "a los 91, fuera")
        A.truthy(alive("Ana-Reino", "sabc", "", t0, t0 + 44 * DAY), "desapuntado: 45 días")
        A.falsy(alive("Ana-Reino", "sabc", "", t0, t0 + 46 * DAY))
    end)
end)
