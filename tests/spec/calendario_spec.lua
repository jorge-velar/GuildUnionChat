-- Calendario de la unión (UnionCalendar.lua): la sección Calendario de la lista de miembros, con sus eventos,
-- quién se apunta y las raids de cada evento. Todo por la ventana, como lo hace el jugador
local F = require("lib.fixtures")
local A = assert_

-- (lunes 18 de enero de 2027 a las 10:00, hora local: los días no dependen de cuándo ni dónde corran las pruebas)
local MONDAY = os.time({ year = 2027, month = 1, day = 18, hour = 10 })

---------------------------------------------------------------------------
-- El WoW de mentira, con lo que aquí hace falta mirar
---------------------------------------------------------------------------
-- (lo que no guarda: textura, transparencia, activado, ancho, alto y los puntos de cada marco)
local function Observe(a)
    local meta = a.w.frameMeta
    local base = meta.__index
    local extra = {
        SetTexture = function(self, t) rawset(self, "_tex", t) end,
        GetTexture = function(self) return rawget(self, "_tex") end,
        SetAlpha = function(self, v) rawset(self, "_alpha", v) end,
        GetAlpha = function(self) return rawget(self, "_alpha") or 1 end,
        SetEnabled = function(self, v) rawset(self, "_off", not v) end,
        Enable = function(self) rawset(self, "_off", false) end,
        Disable = function(self) rawset(self, "_off", true) end,
        IsEnabled = function(self) return not rawget(self, "_off") end,
        SetWidth = function(self, w) rawset(self, "_w", w) end,
        SetHeight = function(self, h) rawset(self, "_h", h) end,
        ClearAllPoints = function(self) rawset(self, "_pts", {}) end,
        SetPoint = function(self, p, ...)
            local pts = rawget(self, "_pts") or {}
            rawset(self, "_pts", pts)
            pts[p] = { ... }
        end,
    }
    meta.__index = function(f, k) return extra[k] or base(f, k) end
end

-- (y Show / Hide no lanzan OnShow / OnHide: en estos marcos, sí)
local function Live(...)
    for _, f in ipairs({ ... }) do
        local function Set(self, v)
            v = v and true or false
            local was = self._shown
            self._shown = v
            local s = was ~= v and self:GetScript(v and "OnShow" or "OnHide")
            if s then s(self) end
        end
        f.Show = function(self) Set(self, true) end
        f.Hide = function(self) Set(self, false) end
        f.SetShown = function(self, v) Set(self, v) end
    end
end

-- (las listas con barra del juego traen su barra, ScrollBar; esta recuerda dónde está)
local function Bar(a, sf)
    local bar = a.env.CreateFrame("Slider", nil, sf)
    bar.value = 0
    bar.GetValue = function(self) return self.value end
    bar.SetValue = function(self, v) self.value = v end
    sf.ScrollBar = bar
    return bar
end

-- La comunidad de prueba (soy Tester-Reino, oficial de UNO) con el reloj de pared en MONDAY
local function Community(opts)
    local a = F.Community(opts)
    a.w.epoch = MONDAY - math.floor(a.w.now)
    Observe(a)
    return a
end

-- (pasa el tiempo solo para el reloj de pared, time() y date(), sin correr los temporizadores del addon)
local function Later(a, secs) a.w.epoch = a.w.epoch + secs end

---------------------------------------------------------------------------
-- La ventana
---------------------------------------------------------------------------
-- (la ventana de hermandad del juego, lo justo para que salga la nuestra: como en miembros_spec)
local function GuildWindow(a)
    local f = a.env.CreateFrame("Frame", "CommunitiesFrame")
    f.Chat, f.GuildInfoTab, f.CommunitiesControlFrame = false, false, false
    -- (la pestaña de miembros del juego: pulsada en su vista, vuelve a Miembros)
    f.RosterTab = a.env.CreateFrame("CheckButton", nil, f)
    f.CommunitiesList = a.env.CreateFrame("Frame", nil, f)
    f.MemberList = a.env.CreateFrame("Frame", nil, f)
    f.MemberList.IsVisible = function() return true end
    local chk = a.env.CreateFrame("CheckButton", nil, f.MemberList)
    f.MemberList.ShowOfflineButton = chk
    chk.IsVisible = function() return true end
    a.w:Fire("ADDON_LOADED", "Blizzard_Communities")
    return f
end

local function Click(b, ...) return b:GetScript("OnClick")(b, ...) end

-- (abrir una sección como el jugador: Calendario, con su pestaña de la derecha; Miembros, con la pestaña de miembros del
-- juego)
local function Section(a, i)
    if i == 1 then
        local rt = a.env.CommunitiesFrame.RosterTab
        return rt:GetScript("OnClick")(rt)
    end
    for _, b in ipairs(a.env.GuildUnionUnionRoster.side.tabs) do
        if b.tab == i then
            b:GetScript("PreClick")(b)
            return b:GetScript("PostClick")(b)
        end
    end
end

-- La sección Calendario abierta desde su pestaña: devuelve su marco (ui en UnionCalendar.lua) y la lista
local function Open(a)
    GuildWindow(a)
    local cover = a.env.GuildUnionUnionRoster
    local ui = cover.calendar
    local nd = ui.newDlg
    Live(ui, ui.detail, ui.detail.picker, nd, nd.popups[1], nd.popups[2], nd.popups[3])
    Bar(a, ui.scroll)
    Bar(a, a.env.GuildUnionCalendarTimeScroll)
    Bar(a, a.env.GuildUnionCalendarBenchScroll)
    Bar(a, a.env.GuildUnionCalendarDayScroll)
    Section(a, 3)
    return ui, cover
end

-- (los botones hijos de un marco, en el orden en que se crearon; con texto, solo los que lo llevan)
local function Children(a, parent, text)
    local out = {}
    for _, f in ipairs(a.w.frames) do
        if f._parent == parent and f._kind == "Button" and (text == nil or f:GetText() == text) then out[#out + 1] = f end
    end
    return out
end
local function Child(a, parent, text) return Children(a, parent, text)[1] end

-- (¿algo de lo escrito en el chat lleva este texto?)
local function Said(a, text)
    for _, l in ipairs(a.w.chat) do if tostring(l.msg):find(text, 1, true) then return true end end
    return false
end

local function TestMode(a, ui) Click(Child(a, ui, "Modo prueba")) end
-- (lo que sale al pasar el ratón por un botón: el título y las líneas de debajo; nil si no sale nada)
local function Hover(a, b)
    local tip = a.env.GameTooltip
    local lines = {}
    tip:Hide(); tip:SetText("")
    tip.AddLine = function(_, text) lines[#lines + 1] = text end
    b:GetScript("OnEnter")(b)
    if not tip:IsShown() then return nil end
    table.insert(lines, 1, tip:GetText())
    return lines
end
local function Card(ui, title)
    for _, c in ipairs(ui.cards) do if c:IsShown() and c.title:GetText() == title then return c end end
end
local function Titles(ui)
    local out = {}
    for _, c in ipairs(ui.cards) do if c:IsShown() then out[#out + 1] = c.title:GetText() end end
    return out
end
-- (la ficha de un evento, por su tarjeta)
local function Detail(ui, title)
    Click(Card(ui, title).info)
    return ui.detail
end
-- (cuántos van: en la tarjeta, «… 24 van»; en la ficha, en verde)
local function Going(x)
    if x.going then return tonumber(x.going:GetText():match("(%d+) van$")) end
    return tonumber(x.sub:GetText():match("|cff40ff40(%d+)|r"))
end

---------------------------------------------------------------------------
-- Lo que se ve en la ficha
---------------------------------------------------------------------------
-- (el nombre sin apellido: «Arwen-Prueba» -> «Arwen»)
local function First(n) return n and (n:match("^([^-]+)")) end
-- (los nombres de cada grupo de la raid que se ve)
local function Groups(d)
    local out = {}
    for gi, grp in ipairs(d.groups) do
        local g = {}
        for _, s in ipairs(grp.slots) do if s.name then g[#g + 1] = First(s.name) end end
        out[gi] = g
    end
    return out
end
local function InRaid(d)
    local n = 0
    for _, g in ipairs(Groups(d)) do n = n + #g end
    return n
end
local function Bench(d)
    local out = {}
    for _, b in ipairs(d.bench) do if b:IsShown() then out[#out + 1] = First(b.name) end end
    return out
end
local function OnBench(d, name)
    for _, b in ipairs(d.bench) do if b:IsShown() and b.name == name then return true end end
    return false
end
local function SlotOf(d, name)
    for gi, grp in ipairs(d.groups) do
        for si, s in ipairs(grp.slots) do if s.name == name then return s, gi, si end end
    end
end
local function BenchCount(d) return tonumber(d.benchHead:GetText():match("%((%d+)%)")) end

-- (los roles por su icono: «[T] 2   [H] 5   [D] 12» -> { TANK = 2, HEALER = 5, DAMAGER = 12 })
local TC = { TANK = "0:19:22:41", HEALER = "20:39:1:20", DAMAGER = "20:39:22:41" }
local function Roles(text)
    local out = {}
    for role, tc in pairs(TC) do out[role] = tonumber(text:match("64:64:" .. tc .. "|t (%d+)")) end
    return out
end
local function RoleIn(text)
    local tc = text:match("64:64:([%d:]+)|t")
    for role, c in pairs(TC) do if c == tc then return role end end
end

---------------------------------------------------------------------------
-- Menú, arrastrar, raids y eventos nuevos
---------------------------------------------------------------------------
-- (el menú del juego, de mentira: recuerda cada menú abierto con sus botones)
local function Menus(a)
    local opened = {}
    local function Menu()
        local m = { items = {} }
        function m:CreateTitle(t) self.title = t end
        function m:CreateDivider() end
        function m:CreateButton(text, fn)
            local sub = Menu()
            sub.text, sub.fn = text, fn
            self.items[#self.items + 1] = sub
            return sub
        end
        return m
    end
    a.env.MenuUtil = { CreateContextMenu = function(owner, gen)
        local root = Menu()
        gen(owner, root)
        opened[#opened + 1] = root
    end }
    return opened
end
local function Item(menu, text)
    for _, it in ipairs(menu.items) do if it.text:find(text, 1, true) then return it end end
end
local function Texts(menu)
    local out = {}
    for _, it in ipairs(menu.items) do out[#out + 1] = it.text end
    return out
end

-- (arrastrar un nombre y soltarlo encima de `to`; sin `to`, en ninguna parte)
local function Drag(from, to)
    from:GetScript("OnDragStart")(from)
    if to then to.IsMouseOver = function() return true end end
    from:GetScript("OnDragStop")(from)
    if to then to.IsMouseOver = nil end
end
-- (todos al banquillo menos `keep`; si uno no sale, falla en vez de quedarse dando vueltas)
local function BenchAll(d, keep)
    for _ = 1, 40 do
        local s
        for _, grp in ipairs(d.groups) do
            for _, x in ipairs(grp.slots) do if not s and x.name and x.name ~= keep then s = x end end
        end
        if not s then return end
        local name = s.name
        Drag(s, d.benchF)
        if SlotOf(d, name) then error("no ha salido al banquillo: " .. name, 2) end
    end
end
-- (+ Añadir raid: se busca a quien la lleva y se elige el primero de la lista)
local function AddRaid(d, query)
    Click(d.addRaid)
    local pk = d.picker
    if query then
        pk.search:SetText(query)
        pk.search:GetScript("OnTextChanged")(pk.search)
    end
    local who = pk.rows[1].value
    Click(pk.rows[1])
    return who
end

-- Un evento nuevo con la ventana: hoy a las 20:00 si no se elige otro día
local function PickDay(a, nd, y, m, day)
    Click(nd.dayBtn)
    local dp = nd.popups[2]
    local prev, nxt = Child(a, dp, "<"), Child(a, dp, ">")
    for _ = 1, 24 do
        local diff = (y * 12 + m) - (dp.y * 12 + dp.m)
        if diff == 0 then break end
        Click(diff > 0 and nxt or prev)
    end
    A.equal(y * 12 + m, dp.y * 12 + dp.m, "el calendario pequeño no llega a ese mes")
    for _, c in ipairs(dp.cells) do if c:IsShown() and c.day == day then return Click(c) end end
    error("no sale el día " .. day)
end
-- (la hora, en la lista de 15 en 15: se baja la barra hasta ella y se elige la primera de la vista)
local function PickTime(a, nd, h, m)
    Click(nd.hourBtn)
    local tsf = a.env.GuildUnionCalendarTimeScroll
    a.env.FauxScrollFrame_SetOffset(tsf, h * 4 + (m or 0) / 15)
    tsf:GetScript("OnVerticalScroll")(tsf, 0)
    Click(nd.popups[3].rows[1])
end
local function NewEvent(a, ui, title, o)
    o = o or {}
    Click(ui.new)
    local nd = ui.newDlg
    nd.title:SetText(title)
    if o.minLv then nd.minLv:SetText(o.minLv) end
    if o.desc then nd.desc:SetText(o.desc) end
    if o.day then PickDay(a, nd, o.day[1], o.day[2], o.day[3]) end
    if o.hour then PickTime(a, nd, o.hour) end
    Click(Child(a, nd, "Crear"))
end

describe("Calendario: la sección", function()
    it("sale en la pestaña Calendario, en la vista Eventos y sin eventos", function()
        local a = Community()
        local ui, cover = Open(a)
        A.equal("Calendario", cover.side.tabs[2].tooltip, "su pestaña, a la derecha")
        A.truthy(ui:IsShown())
        A.truthy(ui.viewBtns.list.picked)
        A.falsy(ui.viewBtns.month.picked)
        A.truthy(ui.list:IsShown())
        A.falsy(ui.month:IsShown())
        A.falsy(ui.side:IsShown())
        A.truthy(ui.empty:IsShown(), "«No hay eventos próximos»")
        for _, c in ipairs(ui.cards) do A.falsy(c:IsShown()) end
        A.falsy(ui.detail:IsShown())
        A.falsy(ui.newDlg:IsShown())
        A.same({}, a:Errors())
    end)

    it("Eventos y Calendario cambian la vista; al salir de la pestaña se cierra la ficha", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        Click(ui.viewBtns.month)
        A.truthy(ui.viewBtns.month.picked)
        A.falsy(ui.viewBtns.list.picked)
        A.falsy(ui.list:IsShown())
        A.truthy(ui.month:IsShown())
        A.truthy(ui.side:IsShown())
        Click(ui.viewBtns.list)
        A.truthy(ui.list:IsShown())
        A.falsy(ui.month:IsShown())
        Detail(ui, "Núcleo de Magma")
        A.truthy(ui.detail:IsShown())
        Section(a, 1) -- (a Miembros)
        A.falsy(ui:IsShown())
        A.falsy(ui.detail:IsShown())
        Section(a, 3)
        A.truthy(ui:IsShown())
        A.falsy(ui.detail:IsShown(), "al volver, sin ficha abierta")
        A.equal(4, #Titles(ui))
        A.same({}, a:Errors())
    end)

    it("arriba, el modo prueba; debajo, el «+» de nuevo evento a la izquierda (su nombre, al pasar el ratón) y Eventos · Calendario en su fila", function()
        local a = Community()
        local ui = Open(a)
        local new, list, month = ui.new, ui.viewBtns.list, ui.viewBtns.month
        A.equal("+", new:GetText(), "solo el «+»")
        A.same({ ui, "TOPLEFT", 14, -30 }, new._pts.TOPLEFT, "a la izquierda, en la segunda fila")
        A.same({ ui, "TOP", -2, -30 }, list._pts.TOPRIGHT, "Eventos, en el centro de la misma fila")
        A.same({ list, "RIGHT", 4, 0 }, month._pts.LEFT, "Calendario, a su lado")
        A.same({ ui, "TOPRIGHT", -26, -2 }, Child(a, ui, "Modo prueba")._pts.TOPRIGHT, "el modo prueba, arriba")
        -- (la fila mide 24, de -30 a -54: el panel de la sección empieza debajo)
        A.truthy(ui.list:GetParent()._pts.TOPLEFT[4] <= -30 - 24, "el panel no pisa la fila")
        A.same({ "Nuevo evento" }, Hover(a, new))
        new:GetScript("OnLeave")(new)
        A.falsy(a.env.GameTooltip:IsShown())
        Click(new)
        A.truthy(ui.newDlg:IsShown(), "abre la ventana de nuevo evento")
        A.same({}, a:Errors())
    end)
end)

describe("Calendario: quién crea eventos (HU:CanMakeEvents)", function()
    it("por defecto, los oficiales: un miembro lo ve apagado y al pasar el ratón le dice por qué", function()
        local a = Community()
        local ui = Open(a)
        local tip = a.env.GameTooltip
        A.truthy(a.HU:CanMakeEvents(), "soy oficial")
        A.truthy(ui.new:IsEnabled())
        A.same({ "Nuevo evento" }, Hover(a, ui.new), "encendido: su nombre, sin aviso")
        F.Stub(a.HU, "CanPin", false) -- (ya no soy oficial)
        a.HU:Changed("unionCfg")
        A.falsy(a.HU:CanMakeEvents())
        A.falsy(ui.new:IsEnabled())
        A.same({ "Nuevo evento", "Solo los oficiales crean eventos." }, Hover(a, ui.new), "apagado: su nombre y, debajo, el aviso")
        ui.new:GetScript("OnLeave")(ui.new)
        A.falsy(tip:IsShown())
        A.same({}, a:Errors())
    end)

    it("«Maestro»: solo el maestro (o quien prueba como maestro); «Todos»: también los miembros", function()
        local a = Community()
        local ui = Open(a)
        a.HU.db.unionCfg = { calMake = "gm" }
        a.HU:Changed("unionCfg")
        A.falsy(ui.new:IsEnabled(), "un oficial, no")
        a.w.guild.rankIndex = 0 -- (ahora soy la maestra)
        a.HU:Changed("unionCfg")
        A.truthy(ui.new:IsEnabled())
        a.w.guild.rankIndex = 1
        a.HU.db.unionCfg.testGM = true -- («Probar como maestro»)
        a.HU:Changed("unionCfg")
        A.truthy(ui.new:IsEnabled())
        F.Stub(a.HU, "CanPin", false)
        a.HU.db.unionCfg = { calMake = "all" }
        a.HU:Changed("unionCfg")
        A.truthy(ui.new:IsEnabled(), "un miembro, con «Todos»")
        a.HU.db.unionCfg = { calMake = "officers" }
        a.HU:Changed("unionCfg")
        A.falsy(ui.new:IsEnabled(), "un miembro, con «Oficiales»")
        A.same({}, a:Errors())
    end)

    it("un permiso por un tiempo deja crear a un miembro hasta que caduca (el de otro no vale)", function()
        local a = Community()
        local ui = Open(a)
        F.Stub(a.HU, "CanPin", false)
        a.HU.db.unionCfg = { calAllow = { ["compi-reino"] = { name = "Compi-Reino", untilT = a.env.time() + 3600 } } }
        a.HU:Changed("unionCfg")
        A.falsy(ui.new:IsEnabled(), "el permiso es de Compi")
        a.HU.db.unionCfg.calAllow["tester-reino"] = { name = "Tester-Reino", untilT = a.env.time() + 3600 }
        a.HU:Changed("unionCfg")
        A.truthy(ui.new:IsEnabled())
        Later(a, 3599)
        a.HU:Changed("unionCfg")
        A.truthy(ui.new:IsEnabled(), "aún vale")
        Later(a, 1)
        a.HU:Changed("unionCfg")
        A.falsy(ui.new:IsEnabled(), "caducado")
        A.same({}, a:Errors())
    end)

    it("con el modo prueba se puede crear sin permiso; el botón del día elegido va igual que el de arriba", function()
        local a = Community()
        local ui = Open(a)
        F.Stub(a.HU, "CanPin", false)
        a.HU:Changed("unionCfg")
        A.falsy(ui.new:IsEnabled())
        TestMode(a, ui)
        A.truthy(ui.new:IsEnabled())
        Click(ui.viewBtns.month)
        A.falsy(ui.side.new:IsShown(), "sin día elegido, sin botón del día")
        Click(ui.grid.cells[22]) -- (el 18)
        A.truthy(ui.side.new:IsShown())
        A.truthy(ui.side.new:IsEnabled())
        TestMode(a, ui) -- (se apaga)
        A.falsy(ui.new:IsEnabled())
        A.falsy(ui.side.new:IsEnabled())
        A.same({}, a:Errors())
    end)

    it("el aviso dice quién los crea según la configuración: el maestro o los oficiales; con «Todos», ninguno", function()
        local a = Community()
        local ui = Open(a)
        local tip = a.env.GameTooltip
        a.HU.db.unionCfg = { calMake = "gm" }
        a.HU:Changed("unionCfg")
        A.falsy(ui.new:IsEnabled(), "soy oficial, no el maestro")
        A.same({ "Nuevo evento", "Solo el maestro crea eventos." }, Hover(a, ui.new))
        Click(ui.viewBtns.month)
        Click(ui.grid.cells[22])
        A.falsy(ui.side.new:IsEnabled())
        A.same({ "Solo el maestro crea eventos." }, Hover(a, ui.side.new), "el del día, como siempre: solo el aviso")
        ui.side.new:GetScript("OnLeave")(ui.side.new)
        A.falsy(tip:IsShown())
        F.Stub(a.HU, "CanPin", false) -- (ya no soy oficial)
        a.HU.db.unionCfg = { calMake = "officers" }
        a.HU:Changed("unionCfg")
        A.same({ "Nuevo evento", "Solo los oficiales crean eventos." }, Hover(a, ui.new))
        a.HU.db.unionCfg = { calMake = "all" }
        a.HU:Changed("unionCfg")
        A.truthy(ui.new:IsEnabled())
        A.same({ "Nuevo evento" }, Hover(a, ui.new), "puedo crear: sin aviso")
        A.is_nil(Hover(a, ui.side.new), "el del día, encendido: nada")
        A.same({}, a:Errors())
    end)
end)

describe("Calendario: nuevo evento", function()
    it("sin título no se crea; con título sale su tarjeta: tipo, hora, nivel mínimo, quién lo pone y apuntado", function()
        local a = Community()
        local ui = Open(a)
        Click(ui.new)
        local nd = ui.newDlg
        A.truthy(nd:IsShown())
        A.equal("Nuevo evento", nd.titleText:GetText())
        A.equal("", nd.title:GetText())
        A.equal("lun 18/01", nd.dayBtn:GetText(), "hoy")
        A.equal("20:00", nd.hourBtn:GetText())
        local create = Child(a, nd, "Crear")
        Click(create)
        A.truthy(Said(a, "Pon un título al evento."))
        A.truthy(nd:IsShown(), "sigue abierta")
        nd.title:SetText("   ")
        Click(create)
        A.truthy(ui.empty:IsShown(), "solo espacios: tampoco")
        nd.title:SetText("  Noche de Onyxia  ")
        nd.minLv:SetText("58")
        Click(create)
        A.falsy(nd:IsShown())
        A.falsy(ui.empty:IsShown())
        local c = ui.cards[1]
        A.truthy(c:IsShown())
        A.equal("Noche de Onyxia", c.title:GetText())
        A.equal("|cffff8040Banda|r  |cffe6e6ea20:00|r  |cffa0a4adNv. 58+|r", c.kind:GetText())
        A.equal(18, c.num:GetText())
        A.equal("Lunes\nenero", c.date:GetText())
        A.equal("|cffa0a4adpor|r |cff4da6ffTester-Reino|r |cff33ff99<UNO>|r", c.who:GetText(), "el mío, en azul")
        A.equal(1, Going(c))
        A.matches("Apuntado", c.join:GetText(), "quien lo crea va")
        A.truthy(c.join.picked)
        A.falsy(ui.cards[2]:IsShown())
        -- (nivel 1 o vacío: sin nivel mínimo)
        NewEvent(a, ui, "Sin nivel", { minLv = "1" })
        A.equal("|cffff8040Banda|r  |cffe6e6ea20:00|r", Card(ui, "Sin nivel").kind:GetText())
        A.same({}, a:Errors())
    end)

    it("Cancelar cierra la ventana sin crear nada", function()
        local a = Community()
        local ui = Open(a)
        Click(ui.new)
        ui.newDlg.title:SetText("No va")
        Click(Child(a, ui.newDlg, "Cancelar"))
        A.falsy(ui.newDlg:IsShown())
        A.truthy(ui.empty:IsShown())
        A.same({}, a:Errors())
    end)

    it("tipos Banda, JcJ y Social; la imagen sigue al tipo hasta que se elige una de la rejilla", function()
        local a = Community()
        local ui = Open(a)
        Click(ui.new)
        local nd = ui.newDlg
        local kinds = {}
        for k in pairs(nd.kindBtns) do kinds[#kinds + 1] = k end
        table.sort(kinds)
        A.same({ "pvp", "raid", "social" }, kinds)
        A.equal("Banda", nd.kindBtns.raid:GetText())
        A.equal("JcJ", nd.kindBtns.pvp:GetText())
        A.equal("Social", nd.kindBtns.social:GetText())
        A.truthy(nd.kindBtns.raid.picked)
        local preview = nd.iconPrev.tex
        A.equal("Interface\\Icons\\INV_Misc_Head_Dragon_01", preview:GetTexture())
        Click(nd.kindBtns.pvp)
        A.truthy(nd.kindBtns.pvp.picked)
        A.falsy(nd.kindBtns.raid.picked)
        A.equal("Interface\\Icons\\INV_BannerPVP_02", preview:GetTexture(), "la del tipo")
        -- (la rejilla: 8 x 4, con la que hay marcada)
        local grid = nd.popups[1]
        Click(Child(a, nd.content, "Elegir imagen"))
        A.truthy(grid:IsShown())
        A.equal("Interface\\Icons\\INV_Misc_Head_Dragon_01", nd.iconBtns[1].path)
        for k, b in ipairs(nd.iconBtns) do A.equal(k == 10, b.sel:IsShown(), "marcada solo la 10, la del JcJ") end
        -- (con la barra, las de más abajo: son 64)
        local gsf = a.env.GuildUnionCalendarIconScroll
        a.env.FauxScrollFrame_SetOffset(gsf, 4)
        gsf:GetScript("OnVerticalScroll")(gsf, 160)
        A.equal("Interface\\Icons\\Spell_Holy_SealOfMight", nd.iconBtns[1].path)
        A.equal("Interface\\Icons\\INV_Misc_Bomb_04", nd.iconBtns[32].path)
        a.env.FauxScrollFrame_SetOffset(gsf, 0)
        gsf:GetScript("OnVerticalScroll")(gsf, 0)
        Click(nd.iconBtns[3])
        A.falsy(grid:IsShown(), "al elegir, se cierra")
        A.equal("Interface\\Icons\\Spell_Fire_Incinerate", preview:GetTexture())
        Click(nd.kindBtns.social)
        A.equal("Interface\\Icons\\Spell_Fire_Incinerate", preview:GetTexture(), "elegida: ya no cambia con el tipo")
        -- (la vista previa también abre y cierra la rejilla)
        Click(nd.iconPrev)
        A.truthy(grid:IsShown())
        A.truthy(nd.iconBtns[3].sel:IsShown())
        Click(nd.iconPrev)
        A.falsy(grid:IsShown())
        nd.title:SetText("Fogata")
        Click(Child(a, nd, "Crear"))
        local c = Card(ui, "Fogata")
        A.equal("Interface\\Icons\\Spell_Fire_Incinerate", c.icon:GetTexture())
        A.matches("^|cff40ff40Social|r", c.kind:GetText())
        -- (otra vez: vuelve a Banda y a la imagen del tipo)
        Click(ui.new)
        A.truthy(nd.kindBtns.raid.picked)
        A.equal("Interface\\Icons\\INV_Misc_Head_Dragon_01", preview:GetTexture())
        A.same({}, a:Errors())
    end)

    it("el día, en un calendario pequeño: hoy en dorado, el elegido marcado; < y > cambian de mes y de año", function()
        local a = Community()
        local ui = Open(a)
        Click(ui.new)
        local nd = ui.newDlg
        local dp = nd.popups[2]
        Click(nd.dayBtn)
        A.truthy(dp:IsShown())
        A.equal("Enero 2027", dp.title:GetText())
        -- (enero de 2027 empieza en viernes: 4 huecos antes del 1)
        for k = 1, 4 do A.falsy(dp.cells[k]:IsShown()) end
        A.equal("1", dp.cells[5]:GetText())
        A.equal("31", dp.cells[35]:GetText())
        A.falsy(dp.cells[36]:IsShown())
        A.equal("|cffffd10018|r", dp.cells[22]:GetText(), "hoy, en dorado")
        A.truthy(dp.cells[22].picked, "y elegido")
        A.falsy(dp.cells[23].picked)
        local prev, nxt = Child(a, dp, "<"), Child(a, dp, ">")
        Click(nxt)
        A.equal("Febrero 2027", dp.title:GetText())
        A.equal("1", dp.cells[1]:GetText(), "febrero de 2027 empieza en lunes")
        A.falsy(dp.cells[29]:IsShown(), "28 días")
        for _, c in ipairs(dp.cells) do A.falsy(c.picked, "el elegido es de enero") end
        Click(dp.cells[5])
        A.falsy(dp:IsShown())
        A.equal("vie 05/02", nd.dayBtn:GetText())
        Click(nd.dayBtn)
        A.equal("Febrero 2027", dp.title:GetText(), "se abre por el elegido")
        A.truthy(dp.cells[5].picked)
        Click(prev); Click(prev)
        A.equal("Diciembre 2026", dp.title:GetText())
        A.equal("1", dp.cells[2]:GetText(), "diciembre de 2026 empieza en martes")
        Click(nxt)
        A.equal("Enero 2027", dp.title:GetText())
        Click(nd.dayBtn)
        A.falsy(dp:IsShown(), "el botón también lo cierra")
        nd.title:SetText("Viernes de febrero")
        Click(Child(a, nd, "Crear"))
        local c = Card(ui, "Viernes de febrero")
        A.equal(5, c.num:GetText())
        A.equal("Viernes\nfebrero", c.date:GetText())
        A.same({}, a:Errors())
    end)

    it("la hora, de 15 en 15: la lista se abre por la elegida y se elige", function()
        local a = Community()
        local ui = Open(a)
        Click(ui.new)
        local nd = ui.newDlg
        local tp = nd.popups[3]
        local tsf = a.env.GuildUnionCalendarTimeScroll
        local function Shown()
            local out = {}
            for k, b in ipairs(tp.rows) do out[k] = b.text:GetText() end
            return out
        end
        Click(nd.hourBtn)
        A.truthy(tp:IsShown())
        A.equal(78, a.env.FauxScrollFrame_GetOffset(tsf), "las 20:00, la tercera de la vista")
        A.equal(78 * 20, tsf.ScrollBar.value)
        A.same({ "19:30", "19:45", "|cffffd10020:00|r", "20:15", "20:30", "20:45", "21:00", "21:15" }, Shown())
        A.truthy(tp.rows[3].sel:IsShown())
        A.falsy(tp.rows[4].sel:IsShown())
        Click(tp.rows[5])
        A.falsy(tp:IsShown())
        A.equal("20:30", nd.hourBtn:GetText())
        Click(nd.hourBtn)
        A.equal(80, a.env.FauxScrollFrame_GetOffset(tsf))
        -- (desde el principio: 00:00, 00:15, 00:30...)
        a.env.FauxScrollFrame_SetOffset(tsf, 0)
        tsf:GetScript("OnVerticalScroll")(tsf, 0)
        A.same({ "00:00", "00:15", "00:30", "00:45", "01:00", "01:15", "01:30", "01:45" }, Shown())
        -- (la última, 23:45: la lista no pasa del final)
        a.env.FauxScrollFrame_SetOffset(tsf, 88)
        tsf:GetScript("OnVerticalScroll")(tsf, 0)
        A.equal("23:45", tp.rows[8].text:GetText())
        Click(tp.rows[8])
        Click(nd.hourBtn)
        A.equal(88, a.env.FauxScrollFrame_GetOffset(tsf))
        A.truthy(tp.rows[8].sel:IsShown())
        Click(nd.hourBtn)
        A.falsy(tp:IsShown(), "el botón también la cierra")
        nd.title:SetText("Tarde")
        Click(Child(a, nd, "Crear"))
        A.matches("23:45", Card(ui, "Tarde").kind:GetText())
        A.same({}, a:Errors())
    end)

    it("las ventanitas se excluyen: abrir una cierra las otras; pinchar fuera o cerrar la ventana las cierra", function()
        local a = Community()
        local ui = Open(a)
        Click(ui.new)
        local nd = ui.newDlg
        local grid, dp, tp = nd.popups[1], nd.popups[2], nd.popups[3]
        local catcher = Children(a, nd, "")[2] -- (la capa invisible; la primera es la X)
        A.falsy(catcher:IsShown())
        Click(nd.dayBtn)
        A.truthy(dp:IsShown())
        A.truthy(catcher:IsShown(), "abierta una, la capa para pinchar fuera")
        Click(nd.hourBtn)
        A.falsy(dp:IsShown())
        A.truthy(tp:IsShown())
        Click(Child(a, nd.content, "Elegir imagen"))
        A.falsy(tp:IsShown())
        A.truthy(grid:IsShown())
        Click(nd.dayBtn)
        A.falsy(grid:IsShown())
        A.truthy(dp:IsShown())
        Click(catcher)
        A.falsy(dp:IsShown())
        A.falsy(catcher:IsShown(), "cerradas todas, fuera la capa")
        Click(nd.hourBtn)
        nd:Hide()
        A.falsy(tp:IsShown(), "al cerrar la ventana")
        A.falsy(catcher:IsShown())
        A.same({}, a:Errors())
    end)

    it("en un día u hora que ya han pasado no se crea: lo dice y la ventana sigue abierta (ahora mismo, sí)", function()
        local a = Community()
        local ui = Open(a)
        local nd = ui.newDlg
        local past = "Elige un día y una hora que no hayan pasado."
        NewEvent(a, ui, "Prisas", { day = { 2027, 1, 17 } })
        A.truthy(Said(a, past), "ayer")
        A.truthy(nd:IsShown(), "sigue abierta")
        A.truthy(ui.empty:IsShown(), "sin evento")
        PickDay(a, nd, 2027, 1, 18)
        PickTime(a, nd, 9, 45) -- (son las 10:00)
        A.equal("09:45", nd.hourBtn:GetText())
        a.w.chat = {}
        Click(Child(a, nd, "Crear"))
        A.truthy(Said(a, past), "hoy, hace un cuarto de hora")
        A.truthy(nd:IsShown())
        A.truthy(ui.empty:IsShown())
        PickTime(a, nd, 10)
        Click(Child(a, nd, "Crear"))
        A.falsy(nd:IsShown())
        A.equal("|cffff8040Banda|r  |cffe6e6ea10:00|r", Card(ui, "Prisas").kind:GetText())
        A.same({}, a:Errors())
    end)

    it("quien lo crea va con un rol: el último con el que se apuntó o, si no, el primero que hace su clase", function()
        local a = Community()
        local ui = Open(a)
        local menus = Menus(a)
        NewEvent(a, ui, "Guerrero") -- (soy guerrero y no me he apuntado a nada: tanque)
        A.same({ TANK = 1, HEALER = 0, DAMAGER = 0 }, Roles(Card(ui, "Guerrero").roles:GetText()))
        a.env.UnitClass = function() return "Mago", "MAGE" end
        NewEvent(a, ui, "Mago")
        A.same({ TANK = 0, HEALER = 0, DAMAGER = 1 }, Roles(Card(ui, "Mago").roles:GetText()))
        -- (salgo de uno y vuelvo como sanador: el siguiente que creo, de sanador)
        a.env.UnitClass = function() return "Sacerdote", "PRIEST" end
        Click(Card(ui, "Guerrero").join)
        Click(Child(a, a.env.GuildUnionCalendarConfirm, "Sí"))
        Click(Card(ui, "Guerrero").join)
        Item(menus[#menus], "Sanador").fn()
        NewEvent(a, ui, "Sacerdote")
        A.same({ TANK = 0, HEALER = 1, DAMAGER = 0 }, Roles(Card(ui, "Sacerdote").roles:GetText()))
        -- (en la ficha, en el banquillo con el icono de su rol)
        local d = Detail(ui, "Sacerdote")
        A.equal("HEALER", RoleIn(d.bench[1].text:GetText()))
        A.same({}, a:Errors())
    end)
end)

describe("Calendario: Eventos (las tarjetas)", function()
    it("los próximos, por fecha; lo que empezó hace más de 3 horas sale de la lista pero sigue en el calendario", function()
        local a = Community()
        local ui = Open(a)
        NewEvent(a, ui, "Mañana", { day = { 2027, 1, 19 } })
        NewEvent(a, ui, "Hoy")
        A.same({ "Hoy", "Mañana" }, Titles(ui))
        Later(a, 13 * 3600 - 60) -- (las 22:59: «Hoy» empezó a las 20:00)
        Click(ui.viewBtns.list)
        A.same({ "Hoy", "Mañana" }, Titles(ui))
        Later(a, 120) -- (las 23:01)
        Click(ui.viewBtns.list)
        A.same({ "Mañana" }, Titles(ui))
        Click(ui.viewBtns.month)
        A.equal("|cffffd100+1 evento|r", ui.grid.cells[22].ev:GetText(), "el 18 sigue con el suyo")
        A.same({}, a:Errors())
    end)

    it("con más de 4, la barra: la rueda baja una fila y se ven las de abajo; sin barra, el hueco se quita", function()
        local a = Community()
        local ui = Open(a)
        A.equal(-8, ui.cardArea._pts.BOTTOMRIGHT[3], "sin barra")
        TestMode(a, ui)
        A.same({ "Núcleo de Magma", "Profundidades de Roca Negra", "Garganta Grito de Guerra", "Pesca en Tuercespina" }, Titles(ui))
        A.equal(-30, ui.cardArea._pts.BOTTOMRIGHT[3], "con barra, su hueco a la derecha")
        local sf = ui.scroll
        sf:GetScript("OnMouseWheel")(sf, -1)
        A.equal(108, sf.ScrollBar.value, "una fila de tarjetas")
        a.env.FauxScrollFrame_SetOffset(sf, 1)
        sf:GetScript("OnVerticalScroll")(sf, 108)
        A.same({ "Garganta Grito de Guerra", "Pesca en Tuercespina", "Guarida de Onyxia" }, Titles(ui))
        A.equal("|cffff8040Banda|r  |cffe6e6ea21:00|r  |cffa0a4adNv. 60+|r", Card(ui, "Guarida de Onyxia").kind:GetText())
        A.falsy(ui.cards[4]:IsShown())
        a.env.FauxScrollFrame_SetOffset(sf, 0)
        TestMode(a, ui)
        A.equal(-8, ui.cardArea._pts.BOTTOMRIGHT[3])
        A.truthy(ui.empty:IsShown())
        A.same({}, a:Errors())
    end)

    it("«Más información» y el clic en la tarjeta abren la ficha de ese evento; la X la cierra", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        Click(Card(ui, "Profundidades de Roca Negra").info)
        local d = ui.detail
        A.truthy(d:IsShown())
        A.equal("Profundidades de Roca Negra", d.titleText:GetText())
        A.equal("Interface\\Icons\\INV_Misc_Key_03", d.icon:GetTexture(), "la imagen del tipo")
        A.equal("|cff4da6ffMazmorra|r   |cffe6e6eaMartes 19 de enero, 19:30|r   |cffa0a4adpor|r |cffffd100Pepe-Prueba|r |cff33ff99<UNO>|r"
            .. "   |cff40ff401|r |cffe6e6eavan|r", d.sub:GetText())
        Click(Card(ui, "Garganta Grito de Guerra"))
        A.equal("Garganta Grito de Guerra", d.titleText:GetText())
        A.matches("<DOS>", d.sub:GetText(), "de la otra hermandad")
        Click(Child(a, d, ""))
        A.falsy(d:IsShown())
        A.same({}, a:Errors())
    end)

    it("la ficha enseña la descripción bajo el tipo y el día: lo que ocupa baja todo lo demás y la ventana crece", function()
        local a = Community()
        local ui = Open(a)
        local d = ui.detail
        d.desc.GetStringHeight = function() return 24 end -- (dos líneas)
        NewEvent(a, ui, "Sin descripción")
        NewEvent(a, ui, "Con descripción", { desc = "  Traed pociones de fuego.\nSalimos desde Forjaz.  " })
        Detail(ui, "Sin descripción")
        A.falsy(d.desc:IsShown(), "sin descripción, nada")
        A.equal(480, d._h)
        A.same({ 10, -28 }, d.rule._pts.TOPLEFT)
        A.equal(-34, d.addRaid._pts.TOPLEFT[4])
        A.equal(-64, d.benchF._pts.TOPLEFT[2])
        Detail(ui, "Con descripción")
        A.truthy(d.desc:IsShown())
        A.equal("Traed pociones de fuego.\nSalimos desde Forjaz.", d.desc:GetText())
        A.equal(480 + 28, d._h, "crece lo que ocupa (y un margen)")
        A.same({ 10, -56 }, d.rule._pts.TOPLEFT, "la raya, debajo")
        A.equal(-62, d.addRaid._pts.TOPLEFT[4], "las pestañas de raid, debajo de la raya")
        A.equal(-92, d.benchF._pts.TOPLEFT[2])
        A.equal(-92, d.leaderBar._pts.TOPLEFT[2])
        A.equal(-128, d.groupsF._pts.TOPLEFT[2])
        -- (con dos filas de pestañas, se suman: 28 de la descripción y 26 de la fila)
        for _ = 1, 10 do AddRaid(d) end
        A.equal(480 + 28 + 26, d._h)
        A.same({ 12, -62 }, { d.raidTabs[1]._pts.TOPLEFT[3], d.raidTabs[1]._pts.TOPLEFT[4] })
        A.same({ 12, -88 }, { d.addRaid._pts.TOPLEFT[3], d.addRaid._pts.TOPLEFT[4] }, "la segunda fila")
        A.equal(-118, d.leaderBar._pts.TOPLEFT[2])
        -- (otra vez sin descripción: todo vuelve a su sitio)
        Detail(ui, "Sin descripción")
        A.equal(480, d._h)
        A.same({ 10, -28 }, d.rule._pts.TOPLEFT)
        A.same({}, a:Errors())
    end)
end)

describe("Calendario: el mes", function()
    it("las casillas del mes; «+N eventos» en los días que tienen; elegir un día enseña los suyos", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        NewEvent(a, ui, "Antes de Magma")
        Click(ui.viewBtns.month)
        local cells = ui.grid.cells
        A.equal("Enero 2027", ui.monthTitle:GetText())
        for k = 1, 4 do A.falsy(cells[k]:IsShown()) end
        A.equal("2027-01-01", cells[5].key)
        A.equal(1, cells[5].num:GetText())
        A.equal("2027-01-31", cells[35].key)
        A.falsy(cells[36]:IsShown(), "5 semanas")
        A.equal("|cffffd100+2 eventos|r", cells[22].ev:GetText(), "el 18: Magma y el mío")
        A.truthy(cells[22].mark:IsShown())
        A.equal("|cffffd100+1 evento|r", cells[23].ev:GetText())
        A.equal("", cells[21].ev:GetText())
        A.falsy(cells[21].mark:IsShown())
        local side = ui.side
        A.equal("Calendario", side.title:GetText())
        A.equal("Elige un día para ver sus eventos.", side.info:GetText())
        A.falsy(side.new:IsShown())
        Click(cells[22])
        A.equal("Lunes 18 de enero", side.title:GetText())
        A.equal("", side.info:GetText())
        A.equal("Antes de Magma", side.dayBtns[1].text:GetText(), "por la hora: 20:00")
        A.equal("20:00  |cffff8040Banda|r  |cff40ff401|r van", side.dayBtns[1].sub:GetText())
        A.equal("Núcleo de Magma", side.dayBtns[2].text:GetText())
        A.equal("21:00  |cffff8040Banda|r  |cff40ff4024|r van", side.dayBtns[2].sub:GetText())
        A.equal("Interface\\Icons\\INV_Misc_Head_Dragon_01", side.dayBtns[2].icon:GetTexture())
        A.falsy(side.dayBtns[3]:IsShown())
        A.truthy(side.new:IsShown())
        Click(side.dayBtns[2])
        A.truthy(ui.detail:IsShown())
        A.equal("Núcleo de Magma", ui.detail.titleText:GetText())
        Click(cells[21])
        A.equal("Domingo 17 de enero", side.title:GetText())
        A.equal("No hay eventos este día.", side.info:GetText())
        for _, b in ipairs(side.dayBtns) do A.falsy(b:IsShown()) end
        A.same({}, a:Errors())
    end)

    it("las flechas cambian de mes, también de año", function()
        local a = Community()
        local ui = Open(a)
        Click(ui.viewBtns.month)
        local prev, nxt = Children(a, ui.month)[1], Children(a, ui.month)[2]
        Click(prev)
        A.equal("Diciembre 2026", ui.monthTitle:GetText())
        A.falsy(ui.grid.cells[1]:IsShown())
        A.equal("2026-12-01", ui.grid.cells[2].key, "empieza en martes")
        Click(nxt); Click(nxt)
        A.equal("Febrero 2027", ui.monthTitle:GetText())
        A.equal("2027-02-01", ui.grid.cells[1].key)
        A.falsy(ui.grid.cells[29]:IsShown(), "4 semanas justas")
        for _ = 1, 11 do Click(nxt) end
        A.equal("Enero 2028", ui.monthTitle:GetText())
        A.same({}, a:Errors())
    end)

    it("«+ Nuevo evento» con un día elegido abre la ventana en ese día (el de arriba y el del día)", function()
        local a = Community()
        local ui = Open(a)
        Click(ui.side.new) -- (sin día elegido no hace nada)
        A.falsy(ui.newDlg:IsShown())
        Click(ui.viewBtns.month)
        Click(ui.grid.cells[29]) -- (el 25)
        Click(ui.side.new)
        A.truthy(ui.newDlg:IsShown())
        A.equal("lun 25/01", ui.newDlg.dayBtn:GetText())
        A.equal("20:00", ui.newDlg.hourBtn:GetText())
        Click(Child(a, ui.newDlg, "Cancelar"))
        Click(ui.new)
        A.equal("lun 25/01", ui.newDlg.dayBtn:GetText())
        ui.newDlg.title:SetText("El 25")
        Click(Child(a, ui.newDlg, "Crear"))
        A.equal("|cffffd100+1 evento|r", ui.grid.cells[29].ev:GetText())
        A.equal("El 25", ui.side.dayBtns[1].text:GetText())
        A.same({}, a:Errors())
    end)

    it("un día con más de 5 eventos: se ven 5 y la barra llega a los demás; otro día, la lista vuelve arriba", function()
        local a = Community()
        local ui = Open(a)
        for h = 14, 19 do NewEvent(a, ui, "A las " .. h, { day = { 2027, 1, 20 }, hour = h }) end
        Click(ui.viewBtns.month)
        local side, cells = ui.side, ui.grid.cells
        local dsf = a.env.GuildUnionCalendarDayScroll
        local function Shown()
            local out = {}
            for _, b in ipairs(side.dayBtns) do if b:IsShown() then out[#out + 1] = b.text:GetText() end end
            return out
        end
        Click(cells[24]) -- (el 20)
        A.equal("|cffffd100+6 eventos|r", cells[24].ev:GetText())
        A.same({ "A las 14", "A las 15", "A las 16", "A las 17", "A las 18" }, Shown())
        A.equal(-30, side.dayBtns[1]._pts.RIGHT[3], "con barra, las filas le dejan su hueco")
        a.env.FauxScrollFrame_SetOffset(dsf, 1)
        dsf:GetScript("OnVerticalScroll")(dsf, 44)
        A.same({ "A las 15", "A las 16", "A las 17", "A las 18", "A las 19" }, Shown())
        Click(side.dayBtns[5])
        A.equal("A las 19", ui.detail.titleText:GetText(), "el de abajo también se abre")
        dsf.ScrollBar.value = 44
        Click(cells[23]) -- (el 19, sin eventos: sin barra)
        A.equal(0, a.env.FauxScrollFrame_GetOffset(dsf))
        A.equal(0, dsf.ScrollBar.value)
        A.equal(-6, side.dayBtns[1]._pts.RIGHT[3])
        Click(cells[24])
        A.equal("A las 14", side.dayBtns[1].text:GetText(), "desde arriba")
        A.same({}, a:Errors())
    end)
end)

describe("Calendario: apuntarse", function()
    it("el menú ofrece los roles de mi clase (vanilla): tanque guerrero, druida y paladín; sanador sacerdote, druida, paladín y chamán", function()
        local a = Community()
        local ui = Open(a)
        local menus = Menus(a)
        TestMode(a, ui)
        local join = Card(ui, "Profundidades de Roca Negra").join
        local function Offered(class)
            a.env.UnitClass = function() return "?", class end
            Click(join)
            local m = menus[#menus]
            A.equal("¿Con qué rol vas?", m.title)
            A.equal("Cancelar", m.items[#m.items].text)
            local out = {}
            for i = 1, #m.items - 1 do out[i] = m.items[i].text:match("  (.+)$") end
            return out
        end
        A.same({ "Tanque", "Daño" }, Offered("WARRIOR"))
        A.same({ "Tanque", "Sanador", "Daño" }, Offered("DRUID"))
        A.same({ "Tanque", "Sanador", "Daño" }, Offered("PALADIN"))
        A.same({ "Sanador", "Daño" }, Offered("PRIEST"))
        A.same({ "Sanador", "Daño" }, Offered("SHAMAN"))
        for _, class in ipairs({ "MAGE", "ROGUE", "HUNTER", "WARLOCK" }) do A.same({ "Daño" }, Offered(class), class) end
        A.same({ "Tanque", "Sanador", "Daño" }, Offered(nil), "sin saber la clase, todos")
        A.equal("Apuntarme", join:GetText(), "solo mirar el menú no apunta")
        local m = menus[#menus]
        m.items[#m.items].fn() -- (Cancelar)
        A.equal("Apuntarme", join:GetText())
        A.same({}, a:Errors())
    end)

    it("apuntarse con un rol lo cuenta en su rol; sin el menú del juego, con el último rol elegido (o Daño)", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        local garganta = Card(ui, "Garganta Grito de Guerra")
        Click(garganta.join) -- (sin MenuUtil y sin rol elegido antes: Daño)
        A.matches("Apuntado", garganta.join:GetText())
        A.equal(2, Going(garganta))
        A.same({ TANK = 0, HEALER = 0, DAMAGER = 1 }, Roles(garganta.roles:GetText()))
        local menus = Menus(a)
        local brd = Card(ui, "Profundidades de Roca Negra")
        Click(brd.join)
        Item(menus[1], "Tanque").fn()
        A.matches("Apuntado", brd.join:GetText())
        A.same({ TANK = 1, HEALER = 0, DAMAGER = 0 }, Roles(brd.roles:GetText()))
        a.env.MenuUtil = nil
        local pesca = Card(ui, "Pesca en Tuercespina") -- (la mía: ya voy; salgo y vuelvo)
        Click(pesca.join)
        Click(Child(a, a.env.GuildUnionCalendarConfirm, "Sí"))
        A.equal("Apuntarme", pesca.join:GetText())
        Click(pesca.join)
        A.same({ TANK = 1, HEALER = 0, DAMAGER = 0 }, Roles(pesca.roles:GetText()), "con el último rol, Tanque")
        -- (en la ficha, en el banquillo con el icono de su rol: el evento no tiene raids)
        local d = Detail(ui, "Profundidades de Roca Negra")
        A.equal("Sin raid  |cffa0a4ad(2)|r", d.benchHead:GetText())
        A.same({ "Pepe", "Tester" }, Bench(d))
        A.equal("TANK", RoleIn(d.bench[2].text:GetText()))
        A.truthy(d.noRaid:IsShown(), "todavía no hay raids")
        A.falsy(d.groupsF:IsShown())
        A.falsy(d.leaderBar:IsShown())
        A.same({}, a:Errors())
    end)

    it("salir pide confirmación: «No» lo deja igual; «Sí» lo quita del evento y de su raid", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        local cfm = a.env.GuildUnionCalendarConfirm
        A.matches("Apuntado", d.join:GetText())
        Click(d.join)
        A.truthy(cfm:IsShown())
        A.equal("¿Seguro que quieres salir del evento?", cfm.text:GetText())
        Click(Child(a, cfm, "No"))
        A.falsy(cfm:IsShown())
        A.matches("Apuntado", d.join:GetText())
        A.equal(24, Going(d))
        Click(d.join)
        Click(Child(a, cfm, "Sí"))
        A.falsy(cfm:IsShown())
        A.equal("Apuntarme", d.join:GetText())
        A.falsy(d.join.picked)
        A.equal(23, Going(d))
        A.equal("Raid 1 (12)", d.raidTabs[1]:GetText())
        A.falsy(SlotOf(d, "Tester-Reino"), "fuera de la raid")
        A.falsy(OnBench(d, "Tester-Reino"), "y del banquillo")
        -- (la raid se queda sin líder y yo, que no creé el evento, ya no la organizo)
        A.matches("nadie", d.leaderBar.text:GetText())
        A.falsy(d.addRaid:IsShown())
        A.falsy(d.place:IsShown())
        A.equal("", d.hint:GetText())
        -- (al volver, entro en la raid que tiene sitio, al final y sin ser líder)
        Click(d.join)
        A.equal("Raid 1 (13)", d.raidTabs[1]:GetText())
        local _, gi, si = SlotOf(d, "Tester-Reino")
        A.same({ 1, 5 }, { gi, si }, "el grupo 1 tenía un hueco")
        A.matches("nadie", d.leaderBar.text:GetText())
        A.same({}, a:Errors())
    end)

    it("nivel mínimo: con menos no deja apuntarse y lo dice; con el nivel, sí", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        Click(ui.viewBtns.month)
        Click(ui.grid.cells[30]) -- (el 26: Onyxia, nivel 60)
        Click(ui.side.dayBtns[1])
        local d = ui.detail
        A.equal("Guarida de Onyxia", d.titleText:GetText())
        A.matches("Nv%. 60%+", d.sub:GetText())
        a.env.UnitLevel = function() return 59 end
        Click(d.join)
        A.truthy(Said(a, "Este evento pide nivel 60 o más."))
        A.equal("Apuntarme", d.join:GetText())
        A.equal(1, Going(d))
        a.env.UnitLevel = function() return 60 end
        Click(d.join)
        A.matches("Apuntado", d.join:GetText())
        A.equal(2, Going(d))
        A.same({}, a:Errors())
    end)
end)

describe("Calendario: modo prueba", function()
    it("encendido: eventos de mi hermandad y de otra, uno con su raid hecha; apagado: solo quedan los de verdad", function()
        local a = Community()
        local ui = Open(a)
        NewEvent(a, ui, "De verdad", { day = { 2027, 1, 19 } })
        local btn = Child(a, ui, "Modo prueba")
        Click(btn)
        A.truthy(btn.picked)
        A.same({ "Núcleo de Magma", "Profundidades de Roca Negra", "De verdad", "Garganta Grito de Guerra" }, Titles(ui))
        A.equal("|cffa0a4adpor|r |cffffd100Lyra-Prueba|r |cff66b7ff<DOS>|r", Card(ui, "Garganta Grito de Guerra").who:GetText())
        local magma = Card(ui, "Núcleo de Magma")
        A.equal(24, Going(magma))
        A.same({ TANK = 4, HEALER = 11, DAMAGER = 9 }, Roles(magma.roles:GetText()))
        local d = Detail(ui, "Núcleo de Magma")
        A.equal("Raid 1 (13)", d.raidTabs[1]:GetText(), "yo y 12 más")
        A.equal(11, BenchCount(d), "los demás, sin raid")
        A.equal("Tester-Reino", d.groups[1].slots[1].name, "la llevo yo")
        Click(btn)
        A.falsy(btn.picked)
        A.same({ "De verdad" }, Titles(ui))
        A.falsy(ui.detail:IsShown(), "la ficha de prueba, cerrada")
        A.same({}, a:Errors())
    end)

    it("encenderlo o apagarlo no cierra la ficha de un evento de verdad", function()
        local a = Community()
        local ui = Open(a)
        NewEvent(a, ui, "De verdad")
        local d = Detail(ui, "De verdad")
        TestMode(a, ui)
        A.truthy(d:IsShown(), "al encenderlo")
        A.equal("De verdad", d.titleText:GetText())
        TestMode(a, ui)
        A.truthy(d:IsShown(), "al apagarlo")
        A.equal("De verdad", d.titleText:GetText())
        A.same({}, a:Errors())
    end)
end)

describe("Calendario: las raids de un evento", function()
    it("la ficha: una pestaña por raid, el líder arriba y el primero del grupo 1, grupos de 5 y el banquillo", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        A.equal("|cffff8040Banda|r   |cffe6e6eaLunes 18 de enero, 21:00|r   |cffa0a4adpor|r |cffffd100Jandra-Prueba|r"
            .. " |cff33ff99<UNO>|r   |cff40ff4024|r |cffe6e6eavan|r   |cffa0a4adNv. 55+|r", d.sub:GetText())
        A.same({ TANK = 4, HEALER = 11, DAMAGER = 9 }, Roles(d.roles:GetText()))
        A.truthy(d.raidTabs[1]:IsShown())
        A.truthy(d.raidTabs[1].picked)
        for k = 2, 20 do A.falsy(d.raidTabs[k]:IsShown()) end
        A.truthy(d.addRaid:IsShown(), "lo organizo: llevo una raid")
        A.same({ 80, -34 }, { d.addRaid._pts.TOPLEFT[3], d.addRaid._pts.TOPLEFT[4] }, "en el hueco 2")
        A.equal(480, d._h)
        local crown = "UI%-Group%-LeaderIcon"
        A.matches("^Líder de la raid:  |T.-" .. crown .. ".-Tester%-Reino", d.leaderBar.text:GetText())
        A.matches(crown, d.groups[1].slots[1].text:GetText())
        A.falsy(d.groups[1].slots[2].text:GetText():find("LeaderIcon", 1, true))
        local g = Groups(d)
        A.same({ 5, 5, 3, 0, 0, 0, 0, 0 }, { #g[1], #g[2], #g[3], #g[4], #g[5], #g[6], #g[7], #g[8] })
        A.equal("Grupo 1  |cffa0a4ad5/5|r", d.groups[1].label:GetText())
        A.equal("Grupo 3  |cffa0a4ad3/5|r", d.groups[3].label:GetText())
        A.equal("|cff5a5d66Vacío|r", d.groups[3].slots[4].text:GetText())
        local n = { TANK = 0, HEALER = 0, DAMAGER = 0 }
        for _, grp in ipairs(d.groups) do
            for _, s in ipairs(grp.slots) do if s.name then local r = RoleIn(s.text:GetText()); n[r] = n[r] + 1 end end
        end
        A.same(n, Roles(d.leaderBar.roles:GetText()), "arriba, los roles de la raid")
        -- (el banquillo: los 11 sin raid, por nombre; ninguno está en un grupo)
        A.equal("Sin raid  |cffa0a4ad(11)|r", d.benchHead:GetText())
        local bench = Bench(d)
        A.equal(11, #bench)
        local sorted = {}
        for i, x in ipairs(bench) do sorted[i] = x end
        table.sort(sorted)
        A.same(sorted, bench)
        for _, b in ipairs(d.bench) do if b.name then A.falsy(SlotOf(d, b.name)) end end
        A.equal(142, d.bench[1]._w, "caben los 11: sin barra, las filas a todo lo ancho")
        A.truthy(d.place:IsShown())
        A.equal("Colocar en raids (11)", d.place:GetText())
        A.same({}, a:Errors())
    end)

    it("«+ Añadir»: quién la lleva, en una lista con buscador (primero los que no tienen raid); la nueva se abre", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        local pk = d.picker
        local firstBench = d.bench[1].name
        Click(d.addRaid)
        A.truthy(pk:IsShown())
        A.equal("¿Quién lleva la nueva raid?", pk.title:GetText())
        A.equal(firstBench, pk.rows[1].value, "los del banquillo, por nombre")
        A.matches("|cff808080%(Raid 1%)|r$", pk.rows[12].text:GetText(), "luego los que ya tienen raid, con la suya")
        local psf = a.env.GuildUnionCalendarPickerScroll
        a.env.FauxScrollFrame_SetOffset(psf, 12)
        psf:GetScript("OnVerticalScroll")(psf, 0)
        A.equal("Tester-Reino", pk.rows[12].value, "el último de los 24")
        pk.search:SetText("PEPE")
        pk.search:GetScript("OnTextChanged")(pk.search)
        A.equal("Pepe-Prueba", pk.rows[1].value, "sin mirar mayúsculas, y vuelve arriba")
        A.falsy(pk.rows[2]:IsShown())
        A.falsy(pk.empty:IsShown())
        pk.search:SetText("zzz")
        pk.search:GetScript("OnTextChanged")(pk.search)
        A.falsy(pk.rows[1]:IsShown())
        A.truthy(pk.empty:IsShown(), "«Nadie encaja.»")
        Click(Child(a, pk, "Cancelar"))
        A.falsy(pk:IsShown())
        A.falsy(d.raidTabs[2]:IsShown(), "sin raid nueva")
        local leader = AddRaid(d)
        A.equal(firstBench, leader)
        A.falsy(pk:IsShown())
        A.equal("Raid 2 (1)", d.raidTabs[2]:GetText())
        A.truthy(d.raidTabs[2].picked, "se ve la nueva")
        A.falsy(d.raidTabs[1].picked)
        A.equal(leader, d.groups[1].slots[1].name)
        A.matches(First(leader), d.leaderBar.text:GetText())
        A.equal(10, BenchCount(d))
        -- (la nueva la lleva otro: ni invitar ni quitarla; yo sigo organizando por la raid 1)
        A.falsy(d.invite:IsShown())
        A.falsy(d.delRaid:IsShown())
        A.falsy(d.convert:IsShown())
        A.truthy(d.addRaid:IsShown())
        A.matches("^Arrastra", d.hint:GetText())
        Click(d.raidTabs[1])
        A.truthy(d.raidTabs[1].picked)
        A.truthy(d.invite:IsShown())
        A.truthy(d.delRaid:IsShown())
        -- (cerrar la ficha cierra también la lista)
        Click(d.addRaid)
        A.truthy(pk:IsShown())
        Click(Child(a, d, ""))
        A.falsy(pk:IsShown())
        A.same({}, a:Errors())
    end)

    it("hasta 20 raids, en dos filas de 10: «+ Añadir» va en el hueco siguiente y a las 20 ya no sale", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        A.same({ 12, -60 }, { d.raidTabs[11]._pts.TOPLEFT[3], d.raidTabs[11]._pts.TOPLEFT[4] }, "la 11, al principio de la segunda fila")
        for k = 2, 20 do
            AddRaid(d)
            local pt = d.addRaid._pts.TOPLEFT
            if k == 9 then
                A.same({ 624, -34 }, { pt[3], pt[4] }, "9 raids: «+ Añadir», el décimo de la primera fila")
                A.equal(480, d._h)
                A.equal(-64, d.leaderBar._pts.TOPLEFT[2])
            elseif k == 10 then
                A.same({ 12, -60 }, { pt[3], pt[4] }, "10 raids: a la segunda fila")
                A.equal(506, d._h, "la ventana crece una fila")
                A.equal(-90, d.leaderBar._pts.TOPLEFT[2], "y lo de debajo baja")
                A.equal(-90, d.benchF._pts.TOPLEFT[2])
                A.equal(-126, d.groupsF._pts.TOPLEFT[2])
            elseif k == 19 then
                A.same({ 624, -60 }, { pt[3], pt[4] })
                A.truthy(d.addRaid:IsShown())
            end
        end
        A.falsy(d.addRaid:IsShown(), "20: no caben más")
        A.equal(506, d._h)
        for k = 1, 20 do
            A.truthy(d.raidTabs[k]:IsShown())
            A.matches("^Raid " .. k .. " %(%d+%)$", d.raidTabs[k]:GetText())
        end
        A.truthy(d.raidTabs[20].picked)
        Click(d.raidTabs[7])
        A.truthy(d.raidTabs[7].picked)
        A.falsy(d.raidTabs[20].picked)
        A.same({}, a:Errors())
    end)

    it("«Quitar raid»: solo quien la lleva o quien creó el evento; su gente vuelve al banquillo", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        A.equal("Pepe-Prueba", AddRaid(d, "pepe"))
        A.falsy(d.delRaid:IsShown(), "la raid 2 es de Pepe")
        Click(d.raidTabs[1])
        A.truthy(d.delRaid:IsShown(), "la 1 es mía")
        local before, inRaid1 = BenchCount(d), InRaid(d)
        Click(d.delRaid)
        A.falsy(d.raidTabs[2]:IsShown())
        A.equal("Raid 2 (1)", d.raidTabs[1]:GetText(), "queda la de Pepe")
        A.truthy(d.raidTabs[1].picked)
        A.equal(before + inRaid1, BenchCount(d))
        A.equal(23, BenchCount(d))
        A.matches("Pepe", d.leaderBar.text:GetText())
        -- (ya no llevo ninguna raid ni creé el evento: dejo de organizarlo)
        A.falsy(d.addRaid:IsShown())
        A.falsy(d.place:IsShown())
        A.falsy(d.delRaid:IsShown())
        A.equal("", d.hint:GetText())
        A.same({}, a:Errors())
    end)

    it("quien creó el evento quita cualquier raid, también una sin líder", function()
        local a = Community()
        local ui = Open(a)
        NewEvent(a, ui, "Mío")
        local d = Detail(ui, "Mío")
        A.truthy(d.noRaid:IsShown())
        A.equal("Todavía no hay raids. Quien organiza las crea con «+ Añadir raid».", d.noRaid:GetText())
        A.falsy(d.place:IsShown(), "sin raids no se coloca")
        A.equal(12, d.addRaid._pts.TOPLEFT[3], "«+ Añadir», en el hueco 1")
        AddRaid(d)
        A.equal("Raid 1 (1)", d.raidTabs[1]:GetText())
        A.falsy(d.noRaid:IsShown())
        AddRaid(d) -- (otra vez yo: paso a la nueva y la 1 se queda sin líder)
        AddRaid(d)
        A.same({ "Raid 1 (0)", "Raid 2 (0)", "Raid 3 (1)" }, { d.raidTabs[1]:GetText(), d.raidTabs[2]:GetText(), d.raidTabs[3]:GetText() })
        Click(d.raidTabs[1])
        A.matches("nadie %(clic derecho en alguien: «Hacer líder»%)", d.leaderBar.text:GetText())
        A.falsy(d.invite:IsShown(), "sin líder, nadie invita")
        A.truthy(d.delRaid:IsShown(), "la creé yo")
        Click(d.raidTabs[3])
        Click(d.delRaid)
        A.falsy(d.raidTabs[3]:IsShown())
        A.truthy(d.raidTabs[2].picked, "se ve la de antes")
        Click(d.raidTabs[1])
        Click(d.delRaid)
        A.equal("Raid 2 (0)", d.raidTabs[1]:GetText())
        A.falsy(d.raidTabs[2]:IsShown())
        A.truthy(d.addRaid:IsShown(), "sin llevar raid, lo sigo organizando")
        A.same({}, a:Errors())
    end)

    it("al quitar una raid del medio, la siguiente que se crea no repite el nombre de otra: sigue a la más alta", function()
        local a = Community()
        local ui = Open(a)
        NewEvent(a, ui, "Mío")
        local d = Detail(ui, "Mío")
        AddRaid(d); AddRaid(d); AddRaid(d)
        Click(d.raidTabs[2])
        Click(d.delRaid)
        AddRaid(d)
        local seen = {}
        for k = 1, 3 do
            local name = d.raidTabs[k]:GetText():match("^(.-) %(")
            A.falsy(seen[name], "repetido: " .. name)
            seen[name] = true
        end
        A.same({ "Raid 1 (0)", "Raid 3 (0)", "Raid 4 (1)" }, { d.raidTabs[1]:GetText(), d.raidTabs[2]:GetText(), d.raidTabs[3]:GetText() })
        A.same({}, a:Errors())
    end)

    it("«Colocar en raids»: primero tanques, luego sanadores y luego daño, cada uno a la raid con menos de su rol", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        BenchAll(d, "Tester-Reino") -- (la raid 1 solo conmigo, daño)
        A.equal("Raid 1 (1)", d.raidTabs[1]:GetText())
        A.equal(23, BenchCount(d))
        AddRaid(d, "pepe") -- (la raid 2, con Pepe, tanque)
        A.equal("Colocar en raids (22)", d.place:GetText())
        Click(d.place)
        A.truthy(Said(a, "Colocados 22 en raids; 0 se quedan sin raid."))
        A.equal(0, BenchCount(d))
        A.falsy(d.place:IsShown(), "nadie en el banquillo")
        A.same({ { "Pepe", "Jun", "Bea", "Gorm", "Ivo" }, { "Kael", "Quin", "Tamsin", "Celes", "Elian" }, { "Lune", "Nix" },
            {}, {}, {}, {}, {} }, Groups(d), "raid 2")
        A.same({ TANK = 2, HEALER = 6, DAMAGER = 4 }, Roles(d.leaderBar.roles:GetText()))
        Click(d.raidTabs[1])
        A.same({ { "Tester", "Arwen", "Sol", "Borin", "Hela" }, { "Jandra", "Pim", "Rhea", "Dax", "Fyra" }, { "Mora", "Orla" },
            {}, {}, {}, {}, {} }, Groups(d), "raid 1")
        A.same({ TANK = 2, HEALER = 5, DAMAGER = 5 }, Roles(d.leaderBar.roles:GetText()))
        A.same({}, a:Errors())
    end)

    it("hacer líder a alguien del banquillo con el grupo 1 lleno: va el primero y el último del grupo 1 baja", function()
        local a = Community()
        local ui = Open(a)
        local menus = Menus(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        local lastOfG1 = Groups(d)[1][5]
        local who = d.bench[1].name
        Click(d.bench[1])
        Item(menus[#menus], "Hacer líder de la raid").fn()
        local g = Groups(d)
        A.equal(First(who), g[1][1], "el nuevo líder, el primero")
        A.equal("Tester", g[1][2], "el de antes sigue en la raid")
        A.equal(5, #g[1])
        A.equal(lastOfG1, g[3][4], "el último del grupo 1, al primer grupo con sitio")
        A.equal("Raid 1 (14)", d.raidTabs[1]:GetText())
        A.matches(First(who), d.leaderBar.text:GetText())
        -- (yo no creé el evento y ya no llevo la raid: ni invitar ni organizar)
        A.falsy(d.invite:IsShown())
        A.falsy(d.addRaid:IsShown())
        A.same({}, a:Errors())
    end)
end)

describe("Calendario: mover a la gente (clic derecho y arrastrar)", function()
    -- Magma en modo prueba con una raid 2 que lleva alguien del banquillo; se ve la raid 1 (la mía)
    local function TwoRaids(a)
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        local second = AddRaid(d)
        Click(d.raidTabs[1])
        return ui, d, second
    end

    it("el menú de alguien de la raid: hacer líder, mover a otra raid, sacar al banquillo, susurrar e invitar", function()
        local a = Community()
        local menus = Menus(a)
        local tells, invited = {}, {}
        a.env.ChatFrame_SendTell = function(n) tells[#tells + 1] = n end
        a.env.C_PartyInfo = { InviteUnit = function(n) invited[#invited + 1] = n end }
        local _, d = TwoRaids(a)
        local x = d.groups[2].slots[1].name
        Click(d.groups[2].slots[1])
        local m = menus[#menus]
        A.equal(x, m.title)
        A.same({ "Hacer líder de la raid", "Mover a", "Sacar de la raid", "Susurrar", "Invitar al grupo", "Cancelar" }, Texts(m))
        A.same({ "Raid 2  |cffa0a4ad(1)|r" }, Texts(Item(m, "Mover a")))
        Item(m, "Susurrar").fn()
        A.same({ x }, tells)
        Item(m, "Invitar al grupo").fn()
        A.same({ x }, invited)
        Item(m, "Cancelar").fn()
        Item(m, "Mover a").items[1].fn()
        A.equal("Raid 1 (12)", d.raidTabs[1]:GetText())
        A.equal("Raid 2 (2)", d.raidTabs[2]:GetText())
        A.falsy(SlotOf(d, x))
        -- (sacar: al banquillo)
        local y = d.groups[2].slots[1].name
        Click(d.groups[2].slots[1])
        Item(menus[#menus], "Sacar de la raid").fn()
        A.equal("Raid 1 (11)", d.raidTabs[1]:GetText())
        A.truthy(OnBench(d, y))
        -- (el del banquillo: sin «Sacar», y «Mover a» con las dos raids)
        Click(d.bench[1])
        m = menus[#menus]
        A.same({ "Hacer líder de la raid", "Mover a", "Susurrar", "Invitar al grupo", "Cancelar" }, Texts(m))
        A.same({ "Raid 1  |cffa0a4ad(11)|r", "Raid 2  |cffa0a4ad(2)|r" }, Texts(Item(m, "Mover a")))
        -- (el líder: ni «Hacer líder», ni «Mover a», ni «Sacar»: no se mueve)
        Click(d.groups[1].slots[1])
        A.same({ "Susurrar", "Invitar al grupo", "Cancelar" }, Texts(menus[#menus]))
        -- (un hueco vacío no abre menú)
        local n = #menus
        Click(d.groups[8].slots[1])
        A.equal(n, #menus)
        A.same({}, a:Errors())
    end)

    it("sin organizar el evento, el menú solo deja susurrar e invitar", function()
        local a = Community()
        local menus = Menus(a)
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Profundidades de Roca Negra")
        A.falsy(d.addRaid:IsShown(), "lo puso Pepe y no llevo raid")
        A.equal("", d.hint:GetText())
        Click(d.bench[1])
        A.same({ "Susurrar", "Invitar al grupo", "Cancelar" }, Texts(menus[#menus]))
        A.same({}, a:Errors())
    end)

    it("arrastrar a otro hueco los cambia; el hueco del líder es suyo: se va al de al lado", function()
        local a = Community()
        local _, d = TwoRaids(a)
        local g = Groups(d)
        local x, y = g[2][1], g[3][2]
        Drag(d.groups[2].slots[1], d.groups[3].slots[2])
        g = Groups(d)
        A.equal(y, g[2][1])
        A.equal(x, g[3][2])
        local second = g[1][2]
        Drag(d.groups[3].slots[2], d.groups[1].slots[1]) -- (x, al hueco del líder)
        g = Groups(d)
        A.equal("Tester", g[1][1], "el líder no se mueve")
        A.equal(x, g[1][2])
        A.equal(second, g[3][2], "el de ese hueco, al sitio de x")
        A.same({}, a:Errors())
    end)

    it("soltar a alguien del banquillo sobre el último de un grupo: entra y el que estaba sale al banquillo", function()
        local a = Community()
        local _, d = TwoRaids(a)
        local g3 = Groups(d)[3]
        local x, out = d.bench[1].name, d.groups[3].slots[3].name
        Drag(d.bench[1], d.groups[3].slots[3])
        A.same({ g3[1], g3[2], First(x) }, Groups(d)[3])
        A.truthy(OnBench(d, out))
        A.equal("Raid 1 (13)", d.raidTabs[1]:GetText())
        A.same({}, a:Errors())
    end)

    it("arrastrar a un grupo lo pone al final si cabe; a uno lleno, no y lo dice", function()
        local a = Community()
        local _, d = TwoRaids(a)
        local x = Groups(d)[2][1]
        Drag(d.groups[2].slots[1], d.groups[6])
        local g = Groups(d)
        A.same({ x }, g[6])
        A.equal(4, #g[2])
        Drag(d.groups[6].slots[1], d.groups[1])
        A.truthy(Said(a, "Ese grupo está lleno."))
        A.same({ x }, Groups(d)[6], "sigue donde estaba")
        -- (dentro del mismo grupo lleno sí: va al final)
        local second = Groups(d)[1][2]
        Drag(d.groups[1].slots[2], d.groups[1])
        A.equal(second, Groups(d)[1][5])
        A.equal("Tester", Groups(d)[1][1])
        A.same({}, a:Errors())
    end)

    it("arrastrar a la pestaña de otra raid lo pasa a ella; al banquillo, lo saca; a ninguna parte, nada", function()
        local a = Community()
        local _, d, second = TwoRaids(a)
        local x = d.groups[3].slots[1].name
        Drag(d.groups[3].slots[1], d.raidTabs[2])
        A.equal("Raid 1 (12)", d.raidTabs[1]:GetText())
        A.equal("Raid 2 (2)", d.raidTabs[2]:GetText())
        Click(d.raidTabs[2])
        A.same({ First(second), First(x) }, Groups(d)[1])
        Drag(d.groups[1].slots[2], d.raidTabs[2]) -- (a su misma raid: nada)
        A.equal("Raid 2 (2)", d.raidTabs[2]:GetText())
        local bench = BenchCount(d)
        Drag(d.groups[1].slots[2], d.benchF)
        A.equal(bench + 1, BenchCount(d))
        A.equal("Raid 2 (1)", d.raidTabs[2]:GetText())
        local before = Groups(d)
        Drag(d.groups[1].slots[1])
        A.same(before, Groups(d))
        A.matches(First(second), d.groups[1].slots[1].text:GetText(), "y vuelve a verse su nombre")
        A.same({}, a:Errors())
    end)

    it("arrastrar al líder de la raid lo hace líder (el de antes sigue en la raid)", function()
        local a = Community()
        local _, d = TwoRaids(a)
        Click(d.raidTabs[2]) -- (la de otro: sigo llevando la 1, así que la sigo organizando)
        local leader = d.groups[1].slots[1].name
        local x = d.bench[1].name
        Drag(d.bench[1], d.leaderBar)
        local g = Groups(d)
        A.equal(First(x), g[1][1])
        A.equal(First(leader), g[1][2])
        A.matches(First(x), d.leaderBar.text:GetText())
        A.same({}, a:Errors())
    end)

    it("al empezar a arrastrar, el nombre se va con el ratón y su hueco queda vacío", function()
        local a = Community()
        local _, d = TwoRaids(a)
        local s = d.groups[2].slots[1]
        local label = s.text:GetText()
        s:GetScript("OnDragStart")(s)
        A.equal("", s.text:GetText())
        A.equal("", s.status:GetText())
        A.equal(0, s.fill:GetAlpha())
        local ghost
        for _, f in ipairs(a.w.frames) do
            if f._parent == a.env.UIParent and f.text and f._scripts.OnUpdate and f:IsShown() then ghost = f end
        end
        A.truthy(ghost, "el rótulo que sigue al ratón")
        A.equal(label, ghost.text:GetText())
        a.w:Advance(0.1)
        A.truthy(ghost._pts.CENTER, "colocado junto al ratón")
        s:GetScript("OnDragStop")(s)
        A.falsy(ghost:IsShown())
        A.equal(label, s.text:GetText())
        A.equal(1, s.fill:GetAlpha())
        A.same({}, a:Errors())
    end)

    it("sin organizar el evento no se arrastra", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        Click(d.join)
        Click(Child(a, a.env.GuildUnionCalendarConfirm, "Sí")) -- (me voy: la raid 1 se queda sin líder)
        local before = Groups(d)
        local s = d.groups[2].slots[1]
        local label = s.text:GetText()
        Drag(s, d.benchF)
        A.equal(label, s.text:GetText())
        A.same(before, Groups(d))
        A.same({}, a:Errors())
    end)

    it("soltar a alguien del banquillo sobre un hueco ocupado (no el último): solo sale quien estaba en él", function()
        local a = Community()
        local _, d = TwoRaids(a)
        local g2 = Groups(d)[2]
        local x, out = d.bench[1].name, d.groups[2].slots[2].name
        Drag(d.bench[1], d.groups[2].slots[2])
        A.same({ g2[1], First(x), g2[3], g2[4], g2[5] }, Groups(d)[2], "el del hueco 2, al banquillo; el del 3 sigue")
        A.truthy(OnBench(d, out))
        A.equal("Raid 1 (13)", d.raidTabs[1]:GetText(), "entra uno y sale uno")
        A.same({}, a:Errors())
    end)

    it("el líder, arrastrado a otro grupo, sigue siendo el primero del grupo 1", function()
        local a = Community()
        local _, d = TwoRaids(a)
        Drag(d.groups[1].slots[1], d.groups[4]) -- (yo, el líder, a un grupo vacío)
        for gi, grp in ipairs(d.groups) do
            for si, s in ipairs(grp.slots) do
                if s.name and s.text:GetText():find("LeaderIcon", 1, true) then A.same({ 1, 1 }, { gi, si }, "la corona, en el hueco 1 del grupo 1") end
            end
        end
        A.same({}, a:Errors())
    end)

    it("el líder no se mueve de ninguna forma (otro hueco, su grupo, otra raid, el banquillo, el menú): solo con «Hacer líder»", function()
        local a = Community()
        local menus = Menus(a)
        local _, d = TwoRaids(a)
        local lead = d.groups[1].slots[1]
        local before = Groups(d)
        Drag(lead, d.groups[2].slots[3]) -- (sobre otro: no se cambian)
        A.truthy(Said(a, "El líder no se mueve: para cambiarlo, clic derecho en otro y «Hacer líder de la raid»."))
        A.same(before, Groups(d))
        Drag(lead, d.groups[1]) -- (al final de su grupo)
        Drag(lead, d.raidTabs[2])
        Drag(lead, d.benchF)
        A.same(before, Groups(d))
        A.same({ "Raid 1 (13)", "Raid 2 (1)" }, { d.raidTabs[1]:GetText(), d.raidTabs[2]:GetText() })
        A.matches("Tester%-Reino", d.leaderBar.text:GetText(), "sigue siendo el líder")
        A.matches("LeaderIcon", lead.text:GetText(), "y no se ha ido de su hueco")
        Click(lead)
        A.same({ "Susurrar", "Invitar al grupo", "Cancelar" }, Texts(menus[#menus]))
        -- (otro, soltado en el hueco del líder: al de al lado, nunca en el 1)
        local x = d.groups[2].slots[1].name
        Drag(d.groups[2].slots[1], lead)
        A.equal("Tester", Groups(d)[1][1])
        A.equal(First(x), Groups(d)[1][2])
        -- (con «Hacer líder de la raid» sí cambia: el nuevo, el primero; el de antes, al lado)
        Click(d.groups[1].slots[2])
        Item(menus[#menus], "Hacer líder de la raid").fn()
        A.same({ First(x), "Tester" }, { Groups(d)[1][1], Groups(d)[1][2] })
        A.matches(First(x), d.leaderBar.text:GetText())
        A.same({}, a:Errors())
    end)

    it("tras arrastrar a alguien del banquillo, su fila vuelve a tener fondo", function()
        local a = Community()
        local _, d = TwoRaids(a)
        Drag(d.bench[1]) -- (a ninguna parte)
        A.equal(1, d.bench[1].fill:GetAlpha())
        A.same({}, a:Errors())
    end)

    it("el banquillo, con barra si no caben: se ven 12 y la barra llega a los demás, que se arrastran igual", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        A.equal(142, d.bench[1]._w, "11 sin raid: sin barra")
        BenchAll(d, "Tester-Reino") -- (23 al banquillo; la raid 1, solo conmigo)
        A.equal(23, BenchCount(d))
        A.equal(122, d.bench[1]._w, "con barra, las filas le dejan su hueco")
        A.same({ "Arwen", "Bea", "Borin", "Celes", "Dax", "Elian", "Fyra", "Gorm", "Hela", "Ivo", "Jandra", "Jun" }, Bench(d))
        local bsf = a.env.GuildUnionCalendarBenchScroll
        a.env.FauxScrollFrame_SetOffset(bsf, 11)
        bsf:GetScript("OnVerticalScroll")(bsf, 11 * 18)
        A.same({ "Jun", "Kael", "Lune", "Mora", "Nix", "Orla", "Pepe", "Pim", "Quin", "Rhea", "Sol", "Tamsin" }, Bench(d), "hasta el último")
        Drag(d.bench[12], d.groups[2])
        A.same({ "Tamsin" }, Groups(d)[2])
        A.equal(22, BenchCount(d))
        -- (otro evento: su banquillo, desde arriba)
        bsf.ScrollBar.value = 11 * 18
        Detail(ui, "Profundidades de Roca Negra")
        A.equal(0, a.env.FauxScrollFrame_GetOffset(bsf))
        A.equal(0, bsf.ScrollBar.value)
        A.same({ "Pepe" }, Bench(d))
        A.equal(142, d.bench[1]._w)
        A.same({}, a:Errors())
    end)
end)

describe("Calendario: invitar a la raid", function()
    -- (lo del juego que hace falta para invitar: el grupo, quién está en él y los avisos del sistema)
    local function Party(a)
        local p = { invited = {}, converted = 0, inGroup = {}, group = false, raid = false, lead = true }
        a.env.C_PartyInfo = {
            InviteUnit = function(n) p.invited[#p.invited + 1] = n end,
            ConvertToRaid = function() p.converted = p.converted + 1 end,
        }
        a.env.UnitInRaid = function(n) return p.raid and p.inGroup[n] or nil end
        a.env.UnitInParty = function(n) return p.inGroup[n] or nil end
        a.env.IsInGroup = function() return p.group end
        a.env.IsInRaid = function() return p.raid end
        a.env.UnitIsGroupLeader = function() return p.lead end
        return p
    end
    local API = { ERR_DECLINE_GROUP_S = "%s declines your group invitation.", ERR_BAD_PLAYER_NAME_S = "Cannot find player '%s'.",
        ERR_ALREADY_IN_GROUP_S = "%s is already in a group." }
    local WAIT, OK, NO = "ReadyCheck%-Waiting", "ReadyCheck%-Ready", "ReadyCheck%-NotReady"

    it("en grupo pequeño invita a 4 y dice cuántos faltan; reloj al invitar, X si rechaza o tarda, tic al entrar", function()
        local a = Community({ api = API })
        local p = Party(a)
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        local slots = d.groups[1].slots
        A.truthy(d.invite:IsShown(), "llevo la raid")
        A.equal("Invitar a todos (13)", d.invite:GetText())
        local g1 = {}
        for i = 2, 5 do g1[#g1 + 1] = slots[i].name end
        Click(d.invite)
        A.same(g1, p.invited, "los 4 primeros, sin mí")
        A.equal(0, p.converted, "sin grupo, nada que convertir")
        A.truthy(Said(a, "Invitados 4. Cuando acepten, pulsa otra vez para invitar a los 8 que faltan."))
        for i = 2, 5 do A.matches(WAIT, slots[i].status:GetText()) end
        A.equal("", slots[1].status:GetText(), "a mí no")
        -- (uno rechaza, otro no existe, otro entra)
        a.w:Fire("CHAT_MSG_SYSTEM", g1[1] .. " declines your group invitation.")
        A.matches(NO, slots[2].status:GetText())
        a.w:Fire("CHAT_MSG_SYSTEM", "Cannot find player '" .. g1[2] .. "'.")
        A.matches(NO, slots[3].status:GetText())
        a.w:Fire("CHAT_MSG_SYSTEM", g1[3] .. " se ha unido al grupo.") -- (otro aviso: nada)
        A.matches(WAIT, slots[4].status:GetText())
        p.group, p.inGroup[g1[3]] = true, true
        a.w:Fire("GROUP_ROSTER_UPDATE")
        A.matches(OK, slots[4].status:GetText())
        A.matches(WAIT, slots[5].status:GetText())
        a.w:Advance(90)
        A.matches(NO, slots[5].status:GetText(), "a los 90 s, quien no ha entrado")
        A.matches(OK, slots[4].status:GetText())
        -- (en grupo, no en banda: primero se convierte; ya en banda, caben todos)
        Click(d.invite)
        A.equal(1, p.converted)
        p.raid = true
        p.invited = {}
        Click(d.invite)
        A.equal(11, #p.invited, "todos menos yo y quien ya está")
        A.truthy(Said(a, "Invitados 11 a Raid 1."))
        A.same({}, a:Errors())
    end)

    it("sin la función del juego para invitar, no hace nada", function()
        local a = Community()
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        local n = #a.w.chat
        Click(d.invite)
        A.equal(n, #a.w.chat)
        A.same({}, a:Errors())
    end)

    it("«Convertir en banda»: solo quien lleva la raid, si está en grupo (no en banda) y lo lleva él; el aviso en rojo", function()
        local a = Community()
        local p = Party(a)
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        local function Repaint() Click(d.raidTabs[1]) end
        A.truthy(d.convert:IsShown())
        A.falsy(d.convert:IsEnabled(), "sin grupo")
        A.equal("|cffff5050No estás en banda: invita a alguien, pulsa «Convertir en banda» y luego «Invitar a todos».|r", d.hint:GetText())
        p.group = true
        Repaint()
        A.truthy(d.convert:IsEnabled())
        A.equal("|cffff5050Estás en grupo, no en banda: pulsa «Convertir en banda» antes de «Invitar a todos».|r", d.hint:GetText())
        Click(d.convert)
        A.equal(1, p.converted)
        p.lead = false
        Repaint()
        A.falsy(d.convert:IsEnabled(), "el grupo lo lleva otro")
        p.raid = true
        Repaint()
        A.falsy(d.convert:IsEnabled(), "ya en banda")
        A.matches("^Arrastra los nombres", d.hint:GetText())
        AddRaid(d)
        A.falsy(d.convert:IsShown(), "la raid nueva la lleva otro")
        A.same({}, a:Errors())
    end)
end)

describe("Calendario: colores y niveles", function()
    it("cada nombre con el color de su clase y el banquillo con su nivel: mi hermandad manda sobre las listas de otras", function()
        local a = Community()
        a.env.RAID_CLASS_COLORS = { MAGE = { r = 0, g = 1, b = 1 }, PRIEST = { r = 1, g = 1, b = 0 }, DRUID = { r = 0, g = 1, b = 0 },
            WARRIOR = { r = 1, g = 0, b = 0 } }
        table.insert(a.HU.rosterList, { name = "Arwen-Prueba", class = "MAGE", level = 33 })
        a.HU.remoteRoster.DOS = { members = { { name = "Borin-Prueba", class = "MAGE", level = 11 },
            { name = "Bea-Prueba", class = "MAGE", level = 44 } } }
        local ui = Open(a)
        TestMode(a, ui)
        local d = Detail(ui, "Núcleo de Magma")
        Click(d.delRaid) -- (sin raids: los 24 al banquillo, por nombre)
        A.same({ "Arwen", "Bea", "Borin", "Celes", "Dax", "Elian", "Fyra", "Gorm", "Hela", "Ivo", "Jandra", "Jun" }, Bench(d))
        A.matches("^|cffa0a4ad33|r .-|cff00ffffArwen%-Prueba|r$", d.bench[1].text:GetText(), "de mi hermandad: mago, nivel 33")
        A.matches("^|cffa0a4ad44|r .-|cff00ff00Bea%-Prueba|r$", d.bench[2].text:GetText(), "druida; el nivel, de la otra")
        A.matches("^|cffa0a4ad57|r .-|cffffff00Borin%-Prueba|r$", d.bench[3].text:GetText(), "la otra no cambia lo que ya se sabe")
        A.truthy(d.noRaid:IsShown())
        A.falsy(d.groupsF:IsShown())
        A.falsy(d.leaderBar:IsShown())
        A.falsy(d.invite:IsShown())
        A.falsy(d.delRaid:IsShown())
        A.same({}, a:Errors())
    end)
end)
