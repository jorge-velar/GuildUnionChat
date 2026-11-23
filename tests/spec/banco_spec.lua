-- Banco de la unión (UnionBank.lua): la sección Banco de la lista de miembros. Quién lo ve y quién pide
-- (UnionConfig.lua), las tres vistas, pedir, solicitudes, registro, sacar en el banco del juego y el modo prueba
local F = require("lib.fixtures")
local A = assert_

local OPEN, CLOSED, OFFICERS = "Clic en un objeto: pedirlo.", "Pedir está cerrado por el maestro.", "Solo los oficiales pueden pedir."
local UNSEEN = "Tu banco: ábrelo una vez en el juego (en un banquero) para verlo aquí."
local NO_MATCH = "Nada coincide con la búsqueda."

-- (la ventana de hermandad del juego, lo justo, como en miembros_spec)
local function GuildWindow(a)
    local f = a.env.CreateFrame("Frame", "CommunitiesFrame")
    f.Chat, f.GuildInfoTab, f.CommunitiesControlFrame = false, false, false
    f.CommunitiesList = a.env.CreateFrame("Frame", nil, f)
    f.MemberList = a.env.CreateFrame("Frame", nil, f)
    f.MemberList.IsVisible = function() return true end
    local chk = a.env.CreateFrame("CheckButton", nil, f.MemberList)
    f.MemberList.ShowOfflineButton = chk
    chk.visible = true
    chk.IsVisible = function(self) return self.visible end
    a.w:Fire("ADDON_LOADED", "Blizzard_Communities")
    return f
end

local function Click(b, ...) return b:GetScript("OnClick")(b, ...) end
local function Hover(f) return f:GetScript("OnEnter")(f) end

-- (un botón por su texto, de los que cuelgan de parent)
local function Btn(a, parent, text)
    for _, f in ipairs(a.w.frames) do
        if f._parent == parent and f._kind == "Button" and f:GetText() == text then return f end
    end
    error("no hay botón «" .. text .. "»", 2)
end

-- (yo, Tester-Reino de UNO, con ese rango: 0 maestro, 1 oficial (el de siempre), 4 miembro)
local function Community(rank, opts)
    opts = opts or {}
    opts.guild = opts.guild or F.Guild()
    if rank then opts.guild.rankIndex, opts.guild.members[1].rankIndex = rank, rank end
    return F.Community(opts)
end

-- La sección Banco abierta (el WoW de mentira no lanza OnShow al enseñarla: se lanza a mano)
local function OpenBank(a)
    a.env.IsModifiedClick = a.env.IsModifiedClick or function() return false end -- (falta en el WoW de mentira)
    GuildWindow(a)
    local cover = a.env.GuildUnionUnionRoster
    Click(cover.tabs.Tabs[4])
    local bank = cover.bank
    bank:GetScript("OnShow")(bank)
    return bank
end

local function TestMode(a, bank) Click(Btn(a, bank, "Modo prueba")) end
local function View(bank, key) Click(bank.viewBtns[key]) end
local function Search(bank, text)
    bank.search:SetText(text)
    bank.search:GetScript("OnTextChanged")(bank.search)
end
-- (la rejilla con alto para n filas de huecos: 37 cada una y 4 entre ellas)
local function Rows(bank, n)
    bank.scroll.GetHeight = function() return n * 41 - 4 end
    bank.scroll:GetScript("OnSizeChanged")(bank.scroll)
end
local function Scroll(a, bank, rows)
    a.env.FauxScrollFrame_SetOffset(bank.scroll, rows)
    bank.scroll:GetScript("OnVerticalScroll")(bank.scroll, rows * 41)
end

-- (lo que enseña la rejilla: el objeto de cada hueco a la vista)
local function Slots(bank)
    local out = {}
    for _, b in ipairs(bank.slots) do if b:IsShown() then out[#out + 1] = b.it end end
    return out
end
local function TagsShown(bank)
    local t = {}
    for _, x in ipairs(Slots(bank)) do t[x.tag] = true end
    return t
end
local function IdsShown(bank)
    local t = {}
    for _, x in ipairs(Slots(bank)) do t[#t + 1] = x.id end
    table.sort(t)
    return t
end

-- (un menú de mentira: guarda cada casilla con su texto, si está marcada y qué hace al elegirla)
local function Menu(a, btn)
    local root = { items = {} }
    function root:CreateCheckbox(text, isSel, onSel) self.items[#self.items + 1] = { text = text, isSel = isSel, onSel = onSel } end
    function root:CreateDivider() end
    a.env.MenuUtil = { CreateContextMenu = function(owner, gen) gen(owner, root) end }
    Click(btn)
    return root
end
local function Texts(menu)
    local t = {}
    for i, e in ipairs(menu.items) do t[i] = e.text end
    return t
end
local function Pick(menu, text)
    for _, e in ipairs(menu.items) do
        if e.text:find(text, 1, true) then return e.onSel() end
    end
    error("no hay «" .. text .. "» en el menú", 2)
end

-- (el tooltip: su título y sus líneas)
local function Tip(a)
    local tip = { lines = {} }
    a.env.GameTooltip.SetText = function(_, t) tip.title = t end
    a.env.GameTooltip.AddLine = function(_, t) tip.lines[#tip.lines + 1] = t end
    return tip
end

-- (las líneas del registro, que el WoW de mentira no guarda)
local function LogLines(bank)
    local lines = {}
    bank.logMsgs.Clear = function() for i = #lines, 1, -1 do lines[i] = nil end end
    bank.logMsgs.AddMessage = function(_, text) lines[#lines + 1] = text end
    return lines
end

-- (lo escrito en el chat con HU:Print)
local function Said(a, text)
    for _, m in ipairs(a.w.chat) do
        if m.frame == "ChatFrame1" and tostring(m.msg):find(text, 1, true) then return m.msg end
    end
end

local function Has(sub, s, msg)
    if type(s) ~= "string" or not s:find(sub, 1, true) then
        error((msg and msg .. ": " or "") .. string.format("%q", tostring(s)) .. " no contiene " .. string.format("%q", sub), 2)
    end
end

local function Tag(a, tag) return "|cff" .. a.HU:GuildColorHex(tag) .. tag .. "|r" end
local function Where(a, tag, tab) return Tag(a, tag) .. "  |cffb0b0b0pestaña " .. tab .. "|r" end
-- (un nombre a color: en el WoW de mentira todas las clases son blancas)
local function W(name) return "|cffffffff" .. name .. "|r" end
local function When(t) return os.date("%d/%m %H:%M", t) end

local NAMES = { [2589] = "Paño de lino", [4306] = "Paño de seda", [13446] = "Poción de sanación mayor", [14047] = "Paño rúnico" }
local function Link(id) return "|cffffffff|Hitem:" .. id .. "|h[" .. NAMES[id] .. "]|h|r" end
-- (GetItemInfo de mentira: nombre, enlace y calidad de los de NAMES; los demás, aún sin cargar)
local function KnownItems(a, quality)
    a.env.GetItemInfo = function(id)
        if NAMES[id] then return NAMES[id], Link(id), quality and quality[id] or 1 end
    end
end

-- (C_Container de mentira: { [bolsa] = { { id, cantidad }, ... } }; {} es un hueco vacío y la bolsa que no está, cerrada)
local function Containers(a, bags)
    a.env.C_Container = {
        GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
        GetContainerItemInfo = function(bag, slot)
            local s = bags[bag] and bags[bag][slot]
            if s and s[1] then return { itemID = s[1], stackCount = s[2] } end
        end,
    }
end

-- (el reloj a mediodía, hora local: «Hoy» y «Ayer» salen igual corran a la hora que corran las pruebas)
local function Noon(a)
    local d = os.date("*t", a.env.time())
    a.w.epoch = os.time({ year = d.year, month = d.month, day = d.day, hour = 12 }) - math.floor(a.w.now)
    return a.env.time()
end

-- (una solicitud de verdad al banco de esa hermandad: la ventana de pedir se abre en el modo prueba y se pide ya apagado)
local function RealAsk(a, bank, tag)
    TestMode(a, bank)
    Pick(Menu(a, bank.tagBtn), tag)
    Click(bank.slots[1])
    TestMode(a, bank)
    Click(Btn(a, bank.ask, "Pedir"))
end

-- (la fila de Solicitudes con la solicitud de quien la pidió y de ese banco)
local function ReqRow(bank, who, tag)
    for _, r in ipairs(bank.reqRows) do
        if r:IsShown() and r.r and (not who or r.r.who == who) and (not tag or r.r.tag == tag) then return r end
    end
end
local function ShownRows(rows)
    local n = 0
    for _, r in ipairs(rows) do if r:IsShown() then n = n + 1 end end
    return n
end

describe("Banco: quién lo ve (unionCfg.bankView) y quién puede pedir (bankRequest)", function()
    it("un oficial lo ve; un miembro ve el aviso hasta que el maestro lo abre a todos", function()
        local o = Community()
        local ob = OpenBank(o)
        A.truthy(ob.body:IsShown(), "el oficial")
        A.falsy(ob.locked:IsShown())
        local a = Community(4)
        local bank = OpenBank(a)
        A.falsy(bank.body:IsShown(), "un miembro, de entrada")
        A.truthy(bank.locked:IsShown())
        Has("Solo los oficiales pueden ver el banco", bank.locked:GetText())
        -- (cambia la configuración: el banco abierto se repinta al momento)
        a.HU.db.unionCfg = { bankView = "all" }
        a.HU:Changed("unionCfg")
        A.truthy(bank.body:IsShown(), "abierto a todos")
        A.falsy(bank.locked:IsShown())
        a.HU.db.unionCfg.bankView = "officers"
        a.HU:Changed("unionCfg")
        A.falsy(bank.body:IsShown(), "otra vez solo los oficiales")
        A.same({}, o:Errors())
        A.same({}, a:Errors())
    end)

    it("el maestro lo ve aunque sea solo para oficiales", function()
        local a = Community(0)
        local bank = OpenBank(a)
        A.truthy(bank.body:IsShown())
        A.falsy(bank.locked:IsShown())
        A.same({}, a:Errors())
    end)

    it("pedir: «Todos» (lo de siempre), «Oficiales» o «Nadie»; lo dice la ayuda de arriba", function()
        local function Hint(rank, request)
            local a = Community(rank)
            a.HU.db.unionCfg = { bankView = "all", bankRequest = request }
            local bank = OpenBank(a)
            A.same({}, a:Errors())
            return bank.hint:GetText()
        end
        A.equal(OPEN, Hint(4, nil), "sin elegir: todos")
        A.equal(OPEN, Hint(4, "all"))
        A.equal(OFFICERS, Hint(4, "officers"), "un miembro, con «Oficiales»: no está cerrado, es solo para oficiales")
        A.equal(OPEN, Hint(1, "officers"), "un oficial, con «Oficiales»")
        A.equal(OPEN, Hint(0, "officers"), "el maestro, con «Oficiales»")
        A.equal(CLOSED, Hint(1, "none"), "«Nadie»: tampoco un oficial")
        A.equal(CLOSED, Hint(0, "none"), "ni el maestro")
    end)

    it("con «Nadie», un clic en un objeto no abre la ventana de pedir ni el ratón lo ofrece (tampoco en el modo prueba)", function()
        local a = Community()
        a.HU.db.unionCfg = { bankRequest = "none" }
        local bank = OpenBank(a)
        TestMode(a, bank)
        local b = bank.slots[1]
        local tip = Tip(a)
        Hover(b)
        A.equal("Cantidad: " .. b.it.count, tip.lines[2])
        for _, l in ipairs(tip.lines) do A.falsy(l:find("pedirlo", 1, true), "sin «Clic: pedirlo.»") end
        Click(b)
        A.falsy(bank.ask:IsShown())
        A.equal(CLOSED, bank.hint:GetText())
        A.same({}, a:Errors())
    end)

    it("el modo prueba deja a un miembro ver el banco y pedir aunque sea para oficiales; apagado, vuelve el aviso", function()
        local a = Community(4)
        a.HU.db.unionCfg = { bankRequest = "officers" }
        local bank = OpenBank(a)
        A.falsy(bank.body:IsShown())
        TestMode(a, bank)
        A.truthy(bank.body:IsShown(), "en el modo prueba, lo ve")
        A.equal(OPEN, bank.hint:GetText())
        Click(bank.slots[1])
        A.truthy(bank.ask:IsShown(), "y puede pedir")
        TestMode(a, bank)
        A.falsy(bank.body:IsShown())
        A.truthy(bank.locked:IsShown())
        A.same({}, a:Errors())
    end)

    it("Configuración → Banco (UnionConfig.lua), probando como maestro: «Todos», «Nadie» y «Oficiales» cambian el banco al momento", function()
        local a = Community(4)
        local bank = OpenBank(a)
        local box = a.HU:BuildUnionConfig(a.env.CreateFrame("Frame"))
        -- («Probar como maestro (solo en este PC)», la casilla de abajo)
        local testCb
        for _, f in ipairs(a.w.frames) do if f._parent == box and f._kind == "CheckButton" then testCb = f end end
        testCb.GetChecked = function() return true end
        Click(testCb)
        -- (la página Banco: «Quién puede ver el banco» y debajo «Quién puede pedir sacar algo»)
        local page
        for _, f in ipairs(a.w.frames) do
            if f._kind == "Button" and f:GetText() == "Nadie" and f._parent and f._parent._parent == box then page = f._parent end
        end
        local function Opt(text)
            for _, f in ipairs(a.w.frames) do
                if f._parent == page and f._kind == "Button" and f:GetText() == text then return f end
            end
        end
        Click(Opt("Todos"))
        A.equal("all", a.HU.db.unionCfg.bankView)
        A.truthy(bank.body:IsShown(), "lo ve el miembro")
        A.equal(OPEN, bank.hint:GetText())
        Click(Opt("Nadie"))
        A.equal("none", a.HU.db.unionCfg.bankRequest)
        A.equal(CLOSED, bank.hint:GetText())
        Click(Opt("Oficiales"))
        A.equal("officers", a.HU.db.unionCfg.bankView)
        A.falsy(bank.body:IsShown())
        A.same({}, a:Errors())
    end)
end)

describe("Banco: las tres vistas", function()
    it("Bancos de hermandad (con el filtro), Banco propio (Todo · Banco · Bolsas) y Solicitudes (con el registro)", function()
        local a = Community()
        local bank = OpenBank(a)
        local v = bank.viewBtns
        A.truthy(v.guild.picked, "empieza en Bancos de hermandad")
        A.falsy(v.own.picked); A.falsy(v.reqs.picked)
        A.truthy(bank.gridF:IsShown()); A.falsy(bank.reqF:IsShown()); A.falsy(bank.logF:IsShown())
        A.truthy(bank.tagBtn:IsShown()); A.falsy(bank.ownBtn:IsShown()); A.falsy(bank.logBtn:IsShown())
        A.equal("Todas las hermandades", bank.tagBtn:GetText())
        A.equal(OPEN, bank.hint:GetText())
        A.truthy(bank.empty:IsShown())
        Has("prueba el modo prueba", bank.empty:GetText())
        A.equal("", bank.seen:GetText())
        View(bank, "own")
        A.truthy(v.own.picked); A.falsy(v.guild.picked)
        A.truthy(bank.gridF:IsShown()); A.falsy(bank.tagBtn:IsShown()); A.truthy(bank.ownBtn:IsShown())
        A.equal("Todo", bank.ownBtn:GetText())
        A.equal("", bank.hint:GetText(), "del banco propio no se pide")
        Has("ábrelo una vez en el juego", bank.empty:GetText())
        View(bank, "reqs")
        A.truthy(v.reqs.picked); A.falsy(v.own.picked)
        A.falsy(bank.gridF:IsShown()); A.truthy(bank.reqF:IsShown()); A.falsy(bank.logF:IsShown())
        A.falsy(bank.tagBtn:IsShown()); A.falsy(bank.ownBtn:IsShown())
        A.truthy(bank.logBtn:IsShown()); A.equal("Ver registro", bank.logBtn:GetText())
        A.falsy(bank.simBtn:IsShown(), "abrir el banco de mentira, solo en el modo prueba")
        A.truthy(bank.reqEmpty:IsShown())
        A.equal("No hay solicitudes.", bank.reqEmpty:GetText())
        A.equal("Solicitudes", v.reqs:GetText(), "sin pendientes, sin número")
        Has("al abrirlo sale lo pedido", bank.hint:GetText())
        View(bank, "guild")
        A.truthy(v.guild.picked)
        A.truthy(bank.gridF:IsShown()); A.falsy(bank.reqF:IsShown())
        A.same({}, a:Errors())
    end)
end)

describe("Banco: bancos de hermandad (filtro y buscador)", function()
    it("sin filtro, todos los bancos en orden de hermandad, pestaña y objeto, con la etiqueta y la cantidad en cada hueco", function()
        local a = Community()
        local bank = OpenBank(a)
        TestMode(a, bank)
        Rows(bank, 6)
        local shown = Slots(bank)
        A.equal(13 * 6, #shown, "seis filas de 13, llenas")
        for i = 2, #shown do
            local p, c = shown[i - 1], shown[i]
            A.truthy(p.tag < c.tag or (p.tag == c.tag and (p.tab < c.tab or (p.tab == c.tab and p.id <= c.id))), "en orden en el hueco " .. i)
        end
        A.same({ DOS = true, OTRA = true, UNO = true }, TagsShown(bank))
        for i, b in ipairs(bank.slots) do
            A.equal(Tag(a, b.it.tag), b.tag:GetText(), "la etiqueta del hueco " .. i)
            A.equal(b.it.count > 1 and b.it.count or "", b.count:GetText(), "la cantidad, solo si hay más de uno")
        end
        A.falsy(bank.empty:IsShown())
        -- (con la barra, una fila más abajo: el primer hueco enseña el objeto 14)
        Scroll(a, bank, 1)
        A.same(shown[14], Slots(bank)[1])
        A.same({}, a:Errors())
    end)

    it("cuántas filas caben: según el alto de la rejilla, de 1 a 6", function()
        local a = Community()
        local bank = OpenBank(a)
        TestMode(a, bank)
        A.equal(13 * 5, #Slots(bank), "de entrada, 5 filas")
        Rows(bank, 3)
        A.equal(13 * 3, #Slots(bank))
        Rows(bank, 9)
        A.equal(13 * 6, #Slots(bank), "como mucho 6")
        Rows(bank, 0)
        A.equal(13 * 6, #Slots(bank), "sin alto todavía, como estaba")
        bank.scroll.GetHeight = function() return 10 end
        bank.scroll:GetScript("OnSizeChanged")(bank.scroll)
        A.equal(13, #Slots(bank), "al menos una")
        A.same({}, a:Errors())
    end)

    it("el filtro: una hermandad quita la etiqueta de los huecos, varias la ponen y «Todas» lo quita", function()
        local a = Community()
        local bank = OpenBank(a)
        TestMode(a, bank)
        Rows(bank, 6)
        local m = Menu(a, bank.tagBtn)
        A.same({ "Todas", Tag(a, "DOS"), Tag(a, "OTRA"), Tag(a, "UNO") }, Texts(m), "una casilla por banco, en orden")
        A.truthy(m.items[1].isSel(), "de entrada, todas")
        Pick(m, "DOS")
        A.same({ DOS = true }, TagsShown(bank))
        A.equal("", bank.slots[1].tag:GetText(), "una sola hermandad: sin etiqueta")
        A.equal(Tag(a, "DOS"), bank.tagBtn:GetText())
        m = Menu(a, bank.tagBtn)
        A.falsy(m.items[1].isSel()); A.truthy(m.items[2].isSel()); A.falsy(m.items[4].isSel())
        Pick(m, "UNO")
        A.same({ DOS = true, UNO = true }, TagsShown(bank))
        A.equal(Tag(a, "DOS"), bank.slots[1].tag:GetText(), "dos: con etiqueta")
        A.equal(Tag(a, "DOS") .. ", " .. Tag(a, "UNO"), bank.tagBtn:GetText())
        Pick(m, "OTRA")
        A.equal("3 hermandades", bank.tagBtn:GetText())
        Pick(m, "UNO")
        A.same({ DOS = true, OTRA = true }, TagsShown(bank), "otro clic la quita")
        Pick(m, "Todas")
        A.equal("Todas las hermandades", bank.tagBtn:GetText())
        A.same({ DOS = true, OTRA = true, UNO = true }, TagsShown(bank))
        A.truthy(Menu(a, bank.tagBtn).items[1].isSel())
        A.same({}, a:Errors())
    end)

    it("sin MenuUtil (un juego viejo), el filtro no hace nada", function()
        local a = Community()
        local bank = OpenBank(a)
        Click(bank.tagBtn)
        Click(bank.ownBtn)
        A.equal("Todas las hermandades", bank.tagBtn:GetText())
        A.same({}, a:Errors())
    end)

    it("el buscador, por el nombre del objeto y sin mirar mayúsculas; lo que aún no tiene nombre no sale", function()
        local a = Community()
        KnownItems(a)
        local bank = OpenBank(a)
        TestMode(a, bank)
        Scroll(a, bank, 2)
        Search(bank, "  LINO ")
        A.equal(0, a.env.FauxScrollFrame_GetOffset(bank.scroll), "al buscar, vuelve arriba")
        local ids = IdsShown(bank)
        A.truthy(#ids > 0, "algún paño de lino")
        for _, id in ipairs(ids) do A.equal(2589, id) end
        Search(bank, "paño de")
        local set = {}
        for _, id in ipairs(IdsShown(bank)) do set[id] = true end
        A.same({ [2589] = true, [4306] = true }, set, "lino y seda, no el rúnico")
        Search(bank, "nada así")
        A.same({}, Slots(bank))
        A.truthy(bank.empty:IsShown())
        A.equal(NO_MATCH, bank.empty:GetText(), "hay bancos: es que nada se llama así")
        Search(bank, "")
        A.equal(13 * 5, #Slots(bank), "sin buscar, todo")
        A.same({}, a:Errors())
    end)

    it("el aro de color, solo en los objetos poco comunes o mejores", function()
        local a = Community()
        KnownItems(a, { [2589] = 2 })
        a.env.ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0, g = 1, b = 0 } }
        local bank = OpenBank(a)
        TestMode(a, bank)
        Rows(bank, 6)
        local rings = 0
        for _, b in ipairs(bank.slots) do
            A.equal(b.it.id == 2589, b.ring:IsShown(), "objeto " .. b.it.id)
            if b.ring:IsShown() then rings = rings + 1 end
        end
        A.truthy(rings > 0, "algún paño de lino a la vista")
        A.same({}, a:Errors())
    end)

    it("al pasar el ratón: cantidad, banco y pestaña, y «Clic: pedirlo.»; un hueco vacío no dice nada", function()
        local a = Community()
        local bank = OpenBank(a)
        local tip = Tip(a)
        local b = bank.slots[1]
        Hover(b)
        Click(b)
        A.same({}, tip.lines, "sin nada en el hueco")
        A.falsy(bank.ask:IsShown())
        TestMode(a, bank)
        Hover(b)
        A.same({ " ", "Cantidad: " .. b.it.count, "Banco: " .. Where(a, b.it.tag, b.it.tab), "Clic: pedirlo." }, tip.lines)
        b:GetScript("OnLeave")(b)
        A.same({}, a:Errors())
    end)

    it("Mayús+clic en un objeto pone su enlace en el chat, sin abrir la ventana de pedir", function()
        local a = Community()
        KnownItems(a)
        local bank = OpenBank(a)
        TestMode(a, bank)
        Search(bank, "lino")
        local linked = {}
        a.env.ChatFrameUtil = { InsertLink = function(l) linked[#linked + 1] = l end }
        a.env.IsModifiedClick = function(what) return what == "CHATLINK" end
        Click(bank.slots[1])
        A.same({ Link(2589) }, linked)
        A.falsy(bank.ask:IsShown())
        -- (un objeto aún sin nombre: no hay enlace que poner)
        Search(bank, "")
        for _, b in ipairs(bank.slots) do
            if b:IsShown() and not NAMES[b.it.id] then Click(b); break end
        end
        A.equal(1, #linked)
        A.falsy(bank.ask:IsShown())
        A.same({}, a:Errors())
    end)
end)

describe("Banco: banco propio (bolsas y banco del personaje)", function()
    it("lee las bolsas y, abierto en el juego, el banco; cerrado, enseña lo último que se vio y cuándo", function()
        local a = Community()
        Containers(a, { [0] = { { 2589, 3 }, {} }, [-1] = { { 4306, 10 } }, [7] = { { 14047, 1 } } })
        local bank = OpenBank(a)
        View(bank, "own")
        A.same({ 2589 }, IdsShown(bank), "sin haber abierto el banco: solo las bolsas")
        a.w:Fire("BANKFRAME_OPENED")
        A.same({ 2589, 4306, 14047 }, IdsShown(bank), "el banco (y sus bolsas) y las bolsas")
        for _, x in ipairs(Slots(bank)) do A.equal("UNO", x.tag) end
        A.equal("", bank.slots[1].tag:GetText(), "sin etiqueta de hermandad")
        A.equal("", bank.seen:GetText(), "abierto: lo de ahora, sin fecha")
        local t0 = a.env.time()
        A.same({ items = { { 4306, 10 }, { 14047, 1 } }, t = t0 }, a.HU.db.myBankSnap)
        -- (se cierra el banco una hora después: el juego ya no da sus huecos)
        a.w.epoch = a.w.epoch + 3600
        a.w:Fire("BANKFRAME_CLOSED")
        Containers(a, { [0] = { { 2589, 3 } } })
        View(bank, "own")
        A.same({ 2589, 4306, 14047 }, IdsShown(bank), "lo último que se vio")
        A.equal("Visto por última vez: " .. When(t0 + 3600), bank.seen:GetText(), "cuando se cerró")
        A.same({}, a:Errors())
    end)

    it("la foto del banco se hace al abrirlo en el juego (sin abrir la sección) y con cada cambio; cerrado, ya no", function()
        local a = Community()
        local bags = { [-1] = { { 4306, 10 } } }
        Containers(a, bags)
        a.w:Fire("BANKFRAME_OPENED")
        local t0 = a.env.time()
        A.same({ items = { { 4306, 10 } }, t = t0 }, a.HU.db.myBankSnap, "sin la ventana de hermandad abierta")
        -- (mete algo: el juego avisa con PLAYERBANKSLOTS_CHANGED, o con BAG_UPDATE en una bolsa del banco)
        a.w:Advance(5)
        bags[-1][2] = { 2589, 3 }
        a.w:Fire("PLAYERBANKSLOTS_CHANGED", 2)
        A.same({ items = { { 4306, 10 }, { 2589, 3 } }, t = t0 + 5 }, a.HU.db.myBankSnap)
        bags[7] = { { 14047, 1 } }
        a.w:Fire("BAG_UPDATE", 7)
        A.equal(3, #a.HU.db.myBankSnap.items)
        a.w:Fire("BANKFRAME_CLOSED")
        -- (cerrado, el juego ya no da el banco: lo que llegue después no toca la foto)
        Containers(a, {})
        a.w:Fire("BAG_UPDATE", 7)
        a.w:Fire("PLAYERBANKSLOTS_CHANGED", 1)
        a.w:Fire("BANKFRAME_CLOSED")
        A.equal(3, #a.HU.db.myBankSnap.items)
        A.same({}, a:Errors())
    end)

    it("el menú: Banco, Bolsas o Todo (las dos marcadas también es Todo); la fecha, solo con el banco", function()
        local a = Community()
        Containers(a, { [0] = { { 2589, 3 } } })
        local bank = OpenBank(a)
        -- (lo visto en otra sesión, con el banco ya cerrado)
        local seen = a.env.time() - 86400
        a.HU.db.myBankSnap = { items = { { 4306, 10 } }, t = seen }
        View(bank, "own")
        local m = Menu(a, bank.ownBtn)
        A.same({ "Todo", "Banco", "Bolsas" }, Texts(m))
        A.truthy(m.items[1].isSel())
        A.same({ 2589, 4306 }, IdsShown(bank))
        A.equal("Visto por última vez: " .. When(seen), bank.seen:GetText())
        Pick(m, "Banco")
        A.equal("Banco", bank.ownBtn:GetText())
        A.same({ 4306 }, IdsShown(bank))
        A.falsy(m.items[1].isSel()); A.truthy(m.items[2].isSel()); A.falsy(m.items[3].isSel())
        Pick(m, "Banco")
        Pick(m, "Bolsas")
        A.equal("Bolsas", bank.ownBtn:GetText())
        A.same({ 2589 }, IdsShown(bank))
        A.equal("", bank.seen:GetText(), "solo bolsas: sin fecha")
        Pick(m, "Banco")
        A.equal("Todo", bank.ownBtn:GetText(), "las dos")
        A.same({ 2589, 4306 }, IdsShown(bank))
        Pick(m, "Todo")
        A.truthy(m.items[1].isSel()); A.falsy(m.items[2].isSel()); A.falsy(m.items[3].isSel())
        A.equal("Todo", bank.ownBtn:GetText())
        -- (el buscador vale también aquí)
        KnownItems(a)
        Search(bank, "seda")
        A.same({ 4306 }, IdsShown(bank))
        Search(bank, "nada así")
        A.equal(NO_MATCH, bank.empty:GetText())
        A.same({}, a:Errors())
    end)

    it("con el banco abierto y vacío, no enseña lo que se vio antes: la foto, vacía, con su fecha al cerrarlo", function()
        local a = Community()
        Containers(a, { [-1] = { { 4306, 10 } } })
        local bank = OpenBank(a)
        a.w:Fire("BANKFRAME_OPENED")
        a.w:Fire("BANKFRAME_CLOSED")
        View(bank, "own")
        A.same({ 4306 }, IdsShown(bank))
        -- (al día siguiente lo ha vaciado: lo abre y no hay nada)
        a.w.epoch = a.w.epoch + 86400
        Containers(a, { [-1] = { {}, {} } })
        a.w:Fire("BANKFRAME_OPENED")
        A.same({}, IdsShown(bank), "nada de lo de antes")
        A.same({ items = {}, t = a.env.time() }, a.HU.db.myBankSnap)
        A.equal("", bank.seen:GetText(), "abierto: sin fecha")
        A.truthy(bank.empty:IsShown())
        A.equal("No hay nada en tu banco ni en tus bolsas.", bank.empty:GetText())
        Pick(Menu(a, bank.ownBtn), "Banco")
        A.equal("No hay nada en tu banco.", bank.empty:GetText())
        -- (cerrado: la foto vacía, con la hora)
        a.w:Fire("BANKFRAME_CLOSED")
        A.same({}, IdsShown(bank))
        A.equal("Visto por última vez: " .. When(a.env.time()), bank.seen:GetText())
        A.equal("No hay nada en tu banco.", bank.empty:GetText(), "ya no «ábrelo una vez»: se ha visto, vacío")
        A.same({}, a:Errors())
    end)

    it("las bolsas del banco: las de Enum.BagIndex si el juego las tiene; si no, detrás de las bolsas y la de componentes", function()
        -- (sin Enum.BagIndex y con bolsa de componentes (la 5): el banco es la -1 y de la 6 a la 12)
        local a = Community()
        a.env.NUM_REAGENTBAG_SLOTS = 1
        Containers(a, { [-1] = { { 4306, 1 } }, [5] = { { 2589, 1 } }, [12] = { { 14047, 1 } }, [13] = { { 13446, 1 } } })
        local bank = OpenBank(a)
        a.w:Fire("BANKFRAME_OPENED")
        View(bank, "own")
        Pick(Menu(a, bank.ownBtn), "Banco")
        A.same({ 4306, 14047 }, IdsShown(bank))
        A.same({}, a:Errors())
        -- (con Enum.BagIndex: sus números, aunque no sigan a las bolsas)
        local b = Community()
        b.env.Enum.BagIndex = { Bank = -1, BankBag_1 = 30, BankBag_2 = 31 }
        Containers(b, { [-1] = { { 4306, 1 } }, [6] = { { 2589, 1 } }, [31] = { { 14047, 1 } } })
        local bank2 = OpenBank(b)
        b.w:Fire("BANKFRAME_OPENED")
        View(bank2, "own")
        Pick(Menu(b, bank2.ownBtn), "Banco")
        A.same({ 4306, 14047 }, IdsShown(bank2))
        A.same({}, b:Errors())
        -- (Forever, como el juego de hoy: el banco es Characterbanktab (-2) y sus pestañas, de la 6 en adelante; el -1
        -- es el llavero y no sale)
        local c = Community()
        c.env.Enum.BagIndex = { Keyring = -1, Characterbanktab = -2, Backpack = 0, CharacterBankTab_1 = 6, CharacterBankTab_2 = 7 }
        Containers(c, { [-2] = { { 4306, 1 } }, [-1] = { { 5396, 1 } }, [7] = { { 14047, 1 } }, [0] = { { 2589, 1 } } })
        local bank3 = OpenBank(c)
        c.w:Fire("BANKFRAME_OPENED")
        View(bank3, "own")
        Pick(Menu(c, bank3.ownBtn), "Banco")
        A.same({ 4306, 14047 }, IdsShown(bank3), "ni el llavero ni las bolsas")
        A.same({}, c:Errors())
    end)

    it("sin nada: el aviso de abrir el banco una vez; con solo Bolsas y vacías, «No hay nada en tus bolsas.»", function()
        local a = Community()
        local bank = OpenBank(a)
        View(bank, "own")
        A.truthy(bank.empty:IsShown())
        A.equal(UNSEEN, bank.empty:GetText())
        A.equal("", bank.seen:GetText())
        Pick(Menu(a, bank.ownBtn), "Bolsas")
        A.equal("No hay nada en tus bolsas.", bank.empty:GetText())
        A.same({}, a:Errors())
    end)

    it("del banco propio no se pide: el clic no abre la ventana y el ratón solo dice la cantidad", function()
        local a = Community()
        Containers(a, { [0] = { { 2589, 3 } } })
        local bank = OpenBank(a)
        View(bank, "own")
        local b = bank.slots[1]
        local tip = Tip(a)
        Hover(b)
        A.same({ " ", "Cantidad: 3" }, tip.lines)
        Click(b)
        A.falsy(bank.ask:IsShown())
        A.same({}, a:Errors())
    end)

    it("lo visto del banco es de cada personaje: otro de la misma cuenta no hereda el de Tester", function()
        local a = Community()
        a.HU.db.myBankSnap = { items = { { 4306, 10 } }, t = a.env.time() }
        -- (Otra, de la misma cuenta: entra con el GuildUnionDB de Tester)
        local b = Community(nil, { player = "Otra", db = a.env.GuildUnionDB })
        local bank = OpenBank(b)
        View(bank, "own")
        A.is_nil(b.HU.db.myBankSnap)
        A.same({}, IdsShown(bank))
        A.equal(UNSEEN, bank.empty:GetText())
        A.equal("", bank.seen:GetText())
        -- (y Tester, al volver, sigue con el suyo)
        local c = Community(nil, { db = a.env.GuildUnionDB })
        A.same({ { 4306, 10 } }, c.HU.db.myBankSnap and c.HU.db.myBankSnap.items)
        A.same({}, b:Errors())
        A.same({}, c:Errors())
    end)
end)

describe("Banco: pedir (cantidad y nota)", function()
    it("un clic en un objeto abre la ventana con su nombre, el banco y la pestaña, y lo que hay", function()
        local a = Community()
        KnownItems(a)
        local bank = OpenBank(a)
        TestMode(a, bank)
        Search(bank, "seda")
        local item = bank.slots[1].it
        Click(bank.slots[1])
        local ask = bank.ask
        A.truthy(ask:IsShown())
        A.equal("Pedir al banco", ask.titleText:GetText())
        A.equal(Link(4306), ask.name:GetText())
        A.equal("Banco: " .. Where(a, item.tag, item.tab), ask.from:GetText())
        A.equal("1", ask.qty:GetText())
        A.equal("(hay " .. item.count .. ")", ask.max:GetText())
        A.equal("", ask.note:GetText())
        -- (un objeto aún sin nombre: su número)
        Search(bank, "")
        local other
        for _, b in ipairs(bank.slots) do if b:IsShown() and not NAMES[b.it.id] then other = b; break end end
        Click(other)
        A.equal("#" .. other.it.id, ask.name:GetText())
        -- (y el aviso del chat, también con su número: no «1 x ?.»)
        Click(Btn(a, ask, "Pedir"))
        Has("Pedido al banco de " .. other.it.tag .. ": 1 x #" .. other.it.id .. ".", Said(a, "Pedido al banco"))
        A.same({}, a:Errors())
    end)

    it("si deja de poder pedir con la ventana abierta, «Pedir» no guarda nada", function()
        local a = Community()
        KnownItems(a)
        local bank = OpenBank(a)
        TestMode(a, bank)
        Search(bank, "seda")
        Click(bank.slots[1])
        A.truthy(bank.ask:IsShown())
        -- (el maestro cierra «pedir» y se apaga el modo prueba, con la ventana todavía abierta)
        a.HU:UnionCfg().bankRequest = "none"
        TestMode(a, bank)
        Click(Btn(a, bank.ask, "Pedir"))
        A.falsy(bank.ask:IsShown())
        A.is_nil(Said(a, "Pedido al banco"), "no se pide")
        A.same({}, a:Errors())
    end)

    it("«Pedir»: no más de lo que hay ni menos de 1, la nota sin espacios; queda pendiente, arriba en Solicitudes, y se avisa", function()
        local a = Community()
        KnownItems(a)
        local bank = OpenBank(a)
        TestMode(a, bank)
        Search(bank, "seda")
        local item = bank.slots[1].it
        Click(bank.slots[1])
        bank.ask.qty:SetText("999")
        bank.ask.note:SetText("  para la raid  ")
        Click(Btn(a, bank.ask, "Pedir"))
        A.falsy(bank.ask:IsShown())
        Has("Pedido al banco de " .. item.tag .. ": " .. item.count .. " x Paño de seda.", Said(a, "Pedido al banco"))
        A.equal("Solicitudes (3)", bank.viewBtns.reqs:GetText(), "las dos de prueba y la mía")
        View(bank, "reqs")
        local row = bank.reqRows[1]
        A.equal(item.count .. " x " .. Link(4306), row.item:GetText(), "como mucho, lo que hay")
        A.equal("Tester-Reino", row.who:GetText())
        A.equal(Where(a, item.tag, item.tab), row.tag:GetText())
        A.equal("Pendiente", row.state:GetText())
        local tip = Tip(a)
        Hover(row)
        A.equal("Nota: para la raid", tip.lines[#tip.lines])
        -- (0 o nada: uno)
        for _, qty in ipairs({ "0", "" }) do
            View(bank, "guild")
            Click(bank.slots[1])
            bank.ask.qty:SetText(qty)
            Click(Btn(a, bank.ask, "Pedir"))
            View(bank, "reqs")
            A.equal(Link(4306), bank.reqRows[1].item:GetText(), "con «" .. qty .. "», uno")
        end
        A.equal("Solicitudes (5)", bank.viewBtns.reqs:GetText())
        A.same({}, a:Errors())
    end)

    it("«Cancelar» cierra sin pedir nada", function()
        local a = Community()
        local bank = OpenBank(a)
        TestMode(a, bank)
        Click(bank.slots[1])
        A.truthy(bank.ask:IsShown())
        Click(Btn(a, bank.ask, "Cancelar"))
        A.falsy(bank.ask:IsShown())
        A.equal("Solicitudes (2)", bank.viewBtns.reqs:GetText())
        A.falsy(Said(a, "Pedido al banco"))
        A.same({}, a:Errors())
    end)
end)

describe("Banco: solicitudes", function()
    it("la lista: pendientes, sacadas (en verde, con quién) y rechazadas (en rojo, y al registro)", function()
        local a = Community(0)
        local bank = OpenBank(a)
        TestMode(a, bank)
        View(bank, "reqs")
        A.equal(3, ShownRows(bank.reqRows))
        A.falsy(bank.reqEmpty:IsShown())
        local done = ReqRow(bank, "Bea-Prueba")
        A.equal("10 x #3928", done.item:GetText())
        A.equal("Bea-Prueba", done.who:GetText())
        A.equal(Where(a, "UNO", 3), done.tag:GetText())
        A.equal("|cff40ff40Sacado por Jandra-Prueba|r", done.state:GetText())
        A.equal("Pendiente", ReqRow(bank, "Pepe-Prueba").state:GetText())
        A.equal("Pendiente", ReqRow(bank, "Tester-Reino").state:GetText())
        Click(ReqRow(bank, "Pepe-Prueba").no)
        A.equal("|cffff5050Rechazada|r", ReqRow(bank, "Pepe-Prueba").state:GetText())
        A.equal("Solicitudes (1)", bank.viewBtns.reqs:GetText())
        local lines = LogLines(bank)
        Click(bank.logBtn)
        Has(W("Tester-Reino") .. " rechaza 5 x #13446 (pedido por " .. W("Pepe-Prueba") .. ")", lines[#lines])
        A.same({}, a:Errors())
    end)

    it("con más de 10, la barra enseña las de más abajo (las más nuevas, arriba)", function()
        local a = Community()
        local bank = OpenBank(a)
        TestMode(a, bank)
        for _ = 1, 9 do
            Click(bank.slots[1])
            Click(Btn(a, bank.ask, "Pedir"))
        end
        View(bank, "reqs")
        A.equal(10, ShownRows(bank.reqRows), "12 solicitudes, 10 a la vista")
        A.equal("Tester-Reino", bank.reqRows[1].r.who, "arriba, la última que he pedido")
        a.env.FauxScrollFrame_SetOffset(bank.reqScroll, 2)
        bank.reqScroll:GetScript("OnVerticalScroll")(bank.reqScroll, 2 * 20)
        A.equal(10, ShownRows(bank.reqRows))
        A.equal("Bea-Prueba", bank.reqRows[10].r.who, "abajo del todo, la más vieja (la de ayer, de prueba)")
        A.same({}, a:Errors())
    end)

    it("por fecha, la más nueva arriba: en el modo prueba, la de ayer abajo del todo; una nueva, arriba", function()
        local a = Community()
        local bank = OpenBank(a)
        TestMode(a, bank)
        View(bank, "reqs")
        -- (quién la pidió y hace cuántos segundos)
        local function Order()
            local out = {}
            for _, row in ipairs(bank.reqRows) do
                if row:IsShown() then out[#out + 1] = row.r.who .. " " .. (a.env.time() - row.r.t) end
            end
            return out
        end
        A.same({ "Tester-Reino 600", "Pepe-Prueba 3600", "Bea-Prueba 86400" }, Order(), "hace 10 min, hace 1 h y ayer")
        View(bank, "guild")
        Click(bank.slots[1])
        Click(Btn(a, bank.ask, "Pedir"))
        View(bank, "reqs")
        A.same({ "Tester-Reino 0", "Tester-Reino 600", "Pepe-Prueba 3600", "Bea-Prueba 86400" }, Order())
        A.same({}, a:Errors())
    end)

    it("«Rechazar», solo el maestro (o quien prueba como maestro) y solo en las pendientes", function()
        local o = Community()
        local ob = OpenBank(o)
        TestMode(o, ob)
        View(ob, "reqs")
        for i = 1, 3 do A.falsy(ob.reqRows[i].no:IsShown(), "un oficial no rechaza") end
        local g = Community(0)
        local bank = OpenBank(g)
        TestMode(g, bank)
        View(bank, "reqs")
        A.truthy(ReqRow(bank, "Pepe-Prueba").no:IsShown(), "lo pedido a mi banco")
        A.truthy(ReqRow(bank, "Tester-Reino").no:IsShown(), "en el modo prueba, también lo pedido a otra hermandad")
        A.falsy(ReqRow(bank, "Bea-Prueba").no:IsShown(), "ya sacada")
        Click(ReqRow(bank, "Pepe-Prueba").no)
        A.falsy(ReqRow(bank, "Pepe-Prueba").no:IsShown(), "ya rechazada")
        -- (un oficial que prueba como maestro, UnionConfig.lua)
        local t = Community()
        t.HU.db.unionCfg = { testGM = true }
        local tb = OpenBank(t)
        TestMode(t, tb)
        View(tb, "reqs")
        A.truthy(ReqRow(tb, "Pepe-Prueba").no:IsShown())
        A.same({}, o:Errors())
        A.same({}, g:Errors())
        A.same({}, t:Errors())
    end)

    it("fuera del modo prueba, el maestro rechaza y saca solo lo pedido al banco de su hermandad", function()
        local a = Community(0)
        local bank = OpenBank(a)
        RealAsk(a, bank, "DOS")
        RealAsk(a, bank, "UNO")
        View(bank, "reqs")
        A.equal(2, ShownRows(bank.reqRows))
        A.equal("Solicitudes (2)", bank.viewBtns.reqs:GetText())
        A.truthy(ReqRow(bank, nil, "UNO").no:IsShown(), "lo pedido a UNO, mi hermandad")
        A.falsy(ReqRow(bank, nil, "DOS").no:IsShown(), "lo pedido a DOS lo rechaza su maestro")
        a.w:Fire("GUILDBANKFRAME_OPENED")
        local w = a.env.GuildUnionBankWithdraw
        A.equal("UNO", w.rows[1].r.tag, "en mi banco del juego, solo lo pedido a UNO")
        A.falsy(w.rows[2]:IsShown())
        A.same({}, a:Errors())
    end)

    it("al pasar el ratón: quién la pidió y cuándo, el banco, quién la sacó o la rechazó y la nota", function()
        local a = Community(0)
        local bank = OpenBank(a)
        local now = Noon(a)
        TestMode(a, bank)
        View(bank, "reqs")
        local tip = Tip(a)
        Hover(ReqRow(bank, "Bea-Prueba"))
        A.equal("Registro", tip.title)
        A.same({ "Pedido por Bea-Prueba el " .. When(now - 86400), "Banco: " .. Where(a, "UNO", 3),
            "Sacado por Jandra-Prueba el " .. When(now - 80000) }, tip.lines)
        Click(ReqRow(bank, "Pepe-Prueba").no)
        tip = Tip(a)
        Hover(ReqRow(bank, "Pepe-Prueba"))
        A.same({ "Pedido por Pepe-Prueba el " .. When(now - 3600), "Banco: " .. Where(a, "UNO", 2),
            "Rechazada por Tester-Reino el " .. When(now), "Nota: Para la raid del jueves." }, tip.lines)
        -- (una fila vacía no dice nada)
        tip = Tip(a)
        Hover(bank.reqRows[4])
        bank.reqRows[4]:GetScript("OnLeave")(bank.reqRows[4])
        A.same({}, tip.lines)
        A.same({}, a:Errors())
    end)
end)

describe("Banco: registro", function()
    it("«Ver registro» cambia la lista por lo que ha pasado y «Volver a solicitudes» vuelve; cambiar de vista, también", function()
        local a = Community()
        local bank = OpenBank(a)
        View(bank, "reqs")
        Click(bank.logBtn)
        A.truthy(bank.logF:IsShown()); A.falsy(bank.reqF:IsShown())
        A.equal("Volver a solicitudes", bank.logBtn:GetText())
        A.truthy(bank.logEmpty:IsShown())
        A.equal("Todavía no ha pasado nada.", bank.logEmpty:GetText())
        Click(bank.logBtn)
        A.falsy(bank.logF:IsShown()); A.truthy(bank.reqF:IsShown())
        A.equal("Ver registro", bank.logBtn:GetText())
        Click(bank.logBtn)
        View(bank, "guild")
        A.falsy(bank.logF:IsShown()); A.falsy(bank.logBtn:IsShown())
        View(bank, "reqs")
        A.falsy(bank.logF:IsShown(), "al volver a Solicitudes, la lista")
        A.truthy(bank.reqF:IsShown())
        A.same({}, a:Errors())
    end)

    it("por días: la fecha, «Ayer» y «Hoy», cada cosa con su hora; lo más nuevo, abajo", function()
        local a = Community()
        local bank = OpenBank(a)
        local now = Noon(a)
        TestMode(a, bank)
        -- (al día siguiente: lo de ayer en el modo prueba es de anteayer)
        a.w.epoch = a.w.epoch + 86400
        local item = bank.slots[1].it
        Click(bank.slots[1])
        Click(Btn(a, bank.ask, "Pedir"))
        View(bank, "reqs")
        local lines = LogLines(bank)
        Click(bank.logBtn)
        A.falsy(bank.logEmpty:IsShown())
        A.same({
            "|cffffd100— " .. os.date("%d/%m/%Y", now - 86400) .. " —|r",
            "|cffb0b0b012:00|r  " .. W("Bea-Prueba") .. " pide 10 x #3928 a " .. Where(a, "UNO", 3),
            "|cffb0b0b013:46|r  " .. W("Jandra-Prueba") .. " saca 10 x #3928 de " .. Where(a, "UNO", 3) .. " para " .. W("Bea-Prueba"),
            " ",
            "|cffffd100— Ayer —|r",
            "|cffb0b0b011:00|r  " .. W("Pepe-Prueba") .. " pide 5 x #13446 a " .. Where(a, "UNO", 2),
            "|cffb0b0b011:50|r  " .. W("Tester-Reino") .. " pide 20 x #14047 a " .. Where(a, "DOS", 1),
            " ",
            "|cffffd100— Hoy —|r",
            "|cffb0b0b012:00|r  " .. W("Tester-Reino") .. " pide #" .. item.id .. " a " .. Where(a, item.tag, item.tab),
        }, lines)
        A.same({}, a:Errors())
    end)

    it("los nombres, a color: el de su clase si está en la lista de la hermandad; si no, uno fijo para ese nombre", function()
        -- (colores de clase con 0 y 1: «%02x» los acepta igual con Lua 5.1 y 5.4)
        local COLORS = { WARRIOR = { r = 1, g = 0, b = 0 }, PALADIN = { r = 1, g = 0, b = 1 }, HUNTER = { r = 0, g = 1, b = 0 },
            ROGUE = { r = 1, g = 1, b = 0 }, PRIEST = { r = 1, g = 1, b = 1 }, SHAMAN = { r = 0, g = 0, b = 1 },
            MAGE = { r = 0, g = 1, b = 1 }, WARLOCK = { r = 0, g = 0, b = 0 }, DRUID = { r = 1, g = 1, b = 0 } }
        local HEX = {}
        for _, c in pairs(COLORS) do HEX[string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)] = true end
        local g = F.Guild()
        g.members[1].classFile = "MAGE" -- (Tester, en la lista de la hermandad)
        local a = F.Community({ guild = g })
        a.env.RAID_CLASS_COLORS = COLORS
        local bank = OpenBank(a)
        TestMode(a, bank)
        View(bank, "reqs")
        local lines = LogLines(bank)
        Click(bank.logBtn)
        local function ColorOf(name)
            local found = {}
            for _, l in ipairs(lines) do
                local c = l:match("|cff(%x%x%x%x%x%x)" .. name:gsub("%-", "%%-") .. "|r")
                if c then found[#found + 1] = c end
            end
            return found
        end
        A.same({ "00ffff" }, ColorOf("Tester-Reino"), "Tester, de mago (lo dice la lista)")
        local bea = ColorOf("Bea-Prueba")
        A.equal(2, #bea, "Bea sale dos veces: pide y se le saca")
        A.equal(bea[1], bea[2], "siempre del mismo color")
        A.truthy(HEX[bea[1]], "uno de los de clase")
        A.truthy(HEX[ColorOf("Pepe-Prueba")[1]])
        A.truthy(HEX[ColorOf("Jandra-Prueba")[1]])
        A.same({}, a:Errors())
    end)

    it("la rueda del ratón mueve el registro y un clic en un objeto abre su ficha del juego", function()
        local a = Community()
        local bank = OpenBank(a)
        local m = bank.logMsgs
        local moved = {}
        m.ScrollUp = function() moved[#moved + 1] = "arriba" end
        m.ScrollDown = function() moved[#moved + 1] = "abajo" end
        m:GetScript("OnMouseWheel")(m, 1)
        m:GetScript("OnMouseWheel")(m, -1)
        A.same({ "arriba", "abajo" }, moved)
        local refs = {}
        a.env.SetItemRef = function(link, text, button) refs[#refs + 1] = { link, text, button } end
        m:GetScript("OnHyperlinkClick")(m, "item:2589", "[Paño de lino]", "LeftButton")
        A.same({ { "item:2589", "[Paño de lino]", "LeftButton" } }, refs)
        A.same({}, a:Errors())
    end)
end)

describe("Banco: sacar en el banco de hermandad del juego", function()
    it("al abrir el banco de hermandad, sale la ventanita solo si hay algo pedido a mi hermandad; al cerrarlo se va", function()
        local a = Community(0)
        a.w:Fire("GUILDBANKFRAME_CLOSED") -- (sin abrirla nunca: nada)
        a.w:Fire("GUILDBANKFRAME_OPENED")
        A.is_nil(a.env.GuildUnionBankWithdraw, "sin abrir antes la sección Banco: no hay nada pedido")
        local bank = OpenBank(a)
        RealAsk(a, bank, "DOS")
        a.w:Fire("GUILDBANKFRAME_OPENED")
        A.is_nil(a.env.GuildUnionBankWithdraw, "lo pedido a DOS se saca en el banco de DOS")
        RealAsk(a, bank, "UNO")
        a.w:Fire("GUILDBANKFRAME_OPENED")
        local w = a.env.GuildUnionBankWithdraw
        A.truthy(w:IsShown())
        A.equal("Lo pedido a tu hermandad", w.titleText:GetText())
        A.equal(1, ShownRows(w.rows))
        A.falsy(w.empty:IsShown())
        -- (sacado lo último, sigue abierta con el aviso)
        Click(Btn(a, w.rows[1], "Sacar"))
        A.equal(0, ShownRows(w.rows))
        A.truthy(w.empty:IsShown())
        A.equal("No hay nada pedido.", w.empty:GetText())
        a.w:Fire("GUILDBANKFRAME_CLOSED")
        A.falsy(w:IsShown())
        -- (la próxima vez, sin nada pendiente, ya no sale)
        a.w:Fire("GUILDBANKFRAME_OPENED")
        A.falsy(w:IsShown())
        A.same({}, a:Errors())
    end)

    it("solo a quien puede ver el banco; si lo pierde con ella abierta, «Sacar» no hace nada y se cierra", function()
        local a = Community(4)
        a.HU.db.unionCfg = { bankView = "all" }
        local bank = OpenBank(a)
        RealAsk(a, bank, "UNO")
        -- (el banco, solo para oficiales: un miembro no la ve aunque haya algo pedido a su hermandad)
        a.HU.db.unionCfg.bankView = "officers"
        a.w:Fire("GUILDBANKFRAME_OPENED")
        A.is_nil(a.env.GuildUnionBankWithdraw)
        -- (abierto a todos: sí)
        a.HU.db.unionCfg.bankView = "all"
        a.w:Fire("GUILDBANKFRAME_OPENED")
        local w = a.env.GuildUnionBankWithdraw
        A.truthy(w:IsShown())
        A.equal(1, ShownRows(w.rows))
        -- (el maestro lo vuelve a dejar para oficiales con ella abierta)
        a.HU.db.unionCfg.bankView = "officers"
        local r = w.rows[1].r
        Click(Btn(a, w.rows[1], "Sacar"))
        A.equal("open", r.state, "sin permiso, «Sacar» no la marca")
        A.falsy(Said(a, "Sacado para"))
        a.HU:Changed("unionCfg")
        A.falsy(w:IsShown(), "al repintar, se cierra")
        A.same({}, a:Errors())
    end)

    it("si pierde el permiso con la ventanita abierta y la sección Banco no se ve, también se cierra", function()
        local a = Community(4)
        a.HU.db.unionCfg = { bankView = "all" }
        local bank = OpenBank(a)
        RealAsk(a, bank, "UNO")
        a.w:Fire("GUILDBANKFRAME_OPENED")
        local w = a.env.GuildUnionBankWithdraw
        A.truthy(w:IsShown())
        -- (está en otra sección de la ventana de hermandad, o la tiene cerrada)
        bank:Hide()
        a.HU.db.unionCfg.bankView = "officers"
        a.HU:Changed("unionCfg")
        A.falsy(w:IsShown())
        A.same({}, a:Errors())
    end)

    it("con más de 8 pendientes, la barra enseña las de más abajo; «Sacar» saca la de su fila", function()
        local a = Community()
        local bank = OpenBank(a)
        TestMode(a, bank)
        Pick(Menu(a, bank.tagBtn), "UNO")
        for _ = 1, 8 do
            Click(bank.slots[1])
            Click(Btn(a, bank.ask, "Pedir"))
        end
        a.w:Fire("GUILDBANKFRAME_OPENED")
        local w = a.env.GuildUnionBankWithdraw
        A.equal(8, ShownRows(w.rows), "10 pendientes, 8 a la vista")
        A.equal("para Pepe-Prueba   " .. Where(a, "UNO", 2), w.rows[1].sub:GetText(), "arriba, la primera")
        local sf = a.env.GuildUnionBankWithdrawScroll
        A.truthy(sf, "la barra")
        a.env.FauxScrollFrame_SetOffset(sf, 2)
        sf:GetScript("OnVerticalScroll")(sf, 2 * 34)
        A.equal(8, ShownRows(w.rows))
        A.equal("para Tester-Reino   " .. Where(a, "UNO", bank.slots[1].it.tab), w.rows[8].sub:GetText(), "abajo, la última")
        local last = w.rows[8].r
        Click(Btn(a, w.rows[8], "Sacar"))
        A.equal("done", last.state)
        A.same({}, a:Errors())
    end)

    it("lo pedido, con para quién y de qué pestaña; «Sacar» lo marca como sacado por mí, avisa y lo apunta", function()
        local a = Community()
        local bank = OpenBank(a)
        TestMode(a, bank)
        a.w:Fire("GUILDBANKFRAME_OPENED")
        local w = a.env.GuildUnionBankWithdraw
        A.falsy(w.empty:IsShown())
        A.equal(2, ShownRows(w.rows), "las dos pendientes; la sacada, no")
        A.equal("5 x #13446", w.rows[1].text:GetText())
        A.equal("para Pepe-Prueba   " .. Where(a, "UNO", 2), w.rows[1].sub:GetText())
        A.equal("20 x #14047", w.rows[2].text:GetText())
        Click(Btn(a, w.rows[3], "Sacar")) -- (una fila vacía: nada)
        A.equal(2, ShownRows(w.rows))
        Click(Btn(a, w.rows[1], "Sacar"))
        A.equal(1, ShownRows(w.rows))
        A.equal("20 x #14047", w.rows[1].text:GetText())
        Has("Sacado para Pepe-Prueba: envíaselo por correo.", Said(a, "Sacado para"))
        A.equal("Solicitudes (1)", bank.viewBtns.reqs:GetText())
        View(bank, "reqs")
        A.equal("|cff40ff40Sacado por Tester-Reino|r", ReqRow(bank, "Pepe-Prueba").state:GetText())
        local lines = LogLines(bank)
        Click(bank.logBtn)
        Has(W("Tester-Reino") .. " saca 5 x #13446 de " .. Where(a, "UNO", 2) .. " para " .. W("Pepe-Prueba"), lines[#lines])
        A.same({}, a:Errors())
    end)

    it("al lado del banco de hermandad del juego si está abierto; si no, en el centro", function()
        local a = Community()
        TestMode(a, OpenBank(a))
        a.w:Fire("GUILDBANKFRAME_OPENED")
        local w = a.env.GuildUnionBankWithdraw
        local pts = {}
        w.SetPoint = function(_, ...) pts[#pts + 1] = { ... } end
        local gb = a.env.CreateFrame("Frame", "GuildBankFrame")
        a.w:Fire("GUILDBANKFRAME_OPENED")
        A.same({ "TOPLEFT", gb, "TOPRIGHT", 6, 0 }, pts[1])
        gb:Hide()
        a.w:Fire("GUILDBANKFRAME_OPENED")
        A.same({ "CENTER", a.env.UIParent, "CENTER", 0, 0 }, pts[2])
        A.same({}, a:Errors())
    end)

    it("en el modo prueba, «Probar: abrir el banco de hermandad» la abre sin estar en el banco", function()
        local a = Community()
        local bank = OpenBank(a)
        TestMode(a, bank)
        View(bank, "reqs")
        A.truthy(bank.simBtn:IsShown())
        Click(bank.simBtn)
        local w = a.env.GuildUnionBankWithdraw
        A.truthy(w:IsShown())
        A.equal(2, ShownRows(w.rows))
        A.same({}, a:Errors())
    end)
end)

describe("Banco: modo prueba", function()
    it("encendido: el banco de mi hermandad, el de la otra y «OTRA», dos pendientes y una sacada, y su registro", function()
        local a = Community()
        local bank = OpenBank(a)
        local btn = Btn(a, bank, "Modo prueba")
        Click(btn)
        A.truthy(btn.picked, "el botón, elegido")
        A.same({ "Todas", Tag(a, "DOS"), Tag(a, "OTRA"), Tag(a, "UNO") }, Texts(Menu(a, bank.tagBtn)))
        A.equal("Solicitudes (2)", bank.viewBtns.reqs:GetText())
        View(bank, "reqs")
        A.equal(3, ShownRows(bank.reqRows))
        A.truthy(bank.simBtn:IsShown())
        local lines = LogLines(bank)
        Click(bank.logBtn)
        local n = 0
        for _, l in ipairs(lines) do if l:find("|cffb0b0b0", 1, true) == 1 then n = n + 1 end end
        A.equal(4, n, "tres pedidos y una sacada")
        A.same({}, a:Errors())
    end)

    it("apagado: fuera los bancos, las solicitudes, el registro y el filtro de prueba", function()
        local a = Community()
        local bank = OpenBank(a)
        local btn = Btn(a, bank, "Modo prueba")
        Click(btn)
        Pick(Menu(a, bank.tagBtn), "DOS")
        Click(btn)
        A.falsy(btn.picked)
        A.same({}, Slots(bank))
        A.truthy(bank.empty:IsShown())
        A.equal("Todas las hermandades", bank.tagBtn:GetText())
        A.equal("Solicitudes", bank.viewBtns.reqs:GetText())
        View(bank, "reqs")
        A.truthy(bank.reqEmpty:IsShown())
        A.falsy(bank.simBtn:IsShown())
        Click(bank.logBtn)
        A.truthy(bank.logEmpty:IsShown())
        -- (y otra vez encendido: sin el filtro de antes)
        View(bank, "guild")
        Click(btn)
        A.equal("Todas las hermandades", bank.tagBtn:GetText())
        A.same({}, a:Errors())
    end)

    it("con tres hermandades en la comunidad, los tres bancos son los suyos (sin «OTRA»)", function()
        local a = F.Community({ guildInfo = F.INFO .. "\nGU:g:Hermandad Tres:TRES" })
        local bank = OpenBank(a)
        TestMode(a, bank)
        A.same({ "Todas", Tag(a, "DOS"), Tag(a, "TRES"), Tag(a, "UNO") }, Texts(Menu(a, bank.tagBtn)))
        A.same({}, a:Errors())
    end)
end)
