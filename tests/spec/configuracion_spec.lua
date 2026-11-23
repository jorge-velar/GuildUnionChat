-- Configuración de la hermandad (UnionConfig.lua, la mitad derecha de la pestaña GuildUnion), la lista
-- negra (Blacklist.lua), el registro de invitaciones y salidas (InviteLog.lua) y las solicitudes que
-- llegan de otras hermandades: echar (GK, Social.lua) y cambiar de rango (GP, Ranks.lua)
local F = require("lib.fixtures")
local red = require("lib.red")
local A = assert_

---------------------------------------------------------------------------
-- Ayudas
---------------------------------------------------------------------------
-- (¿se ve? Él y todos los de encima, mostrados)
local function Visible(f)
    while f do
        if not f._shown then return false end
        f = f._parent
    end
    return true
end

-- El WoW de mentira no recuerda si un botón está apagado o una casilla marcada, ni dónde se colocó, y
-- IsVisible da siempre falso: los marcos que se creen desde aquí lo recuerdan, como en el juego
local function Live(a)
    local create = a.env.CreateFrame
    a.env.CreateFrame = function(...)
        local f = create(...)
        f.SetEnabled = function(self, on) self._off = not on end
        f.Enable = function(self) self._off = false end
        f.Disable = function(self) self._off = true end
        f.IsEnabled = function(self) return not self._off end
        f.SetChecked = function(self, on) self._checked = on and true or false end
        f.GetChecked = function(self) return self._checked == true end
        f.IsVisible = Visible
        f.SetPoint = function(self, ...) self._points = self._points or {}; self._points[#self._points + 1] = { ... } end
        f.SetBackdropColor = function(self, r, g, b) self._color = { r, g, b } end
        return f
    end
end

-- Los hijos de un marco, en el orden en que se crearon (kind: "Button", "FontString"...)
local function Kids(a, parent, kind)
    local out = {}
    for _, f in ipairs(a.w.frames) do
        if f._parent == parent and (not kind or f._kind == kind) then out[#out + 1] = f end
    end
    return out
end
local function WithText(a, parent, text)
    for _, f in ipairs(Kids(a, parent)) do if f:GetText() == text then return f end end
end

-- Pulsar como en el juego: solo si se ve y está encendido; una casilla cambia antes de avisar
local function Click(b, ...)
    if not Visible(b) or not b:IsEnabled() then return false end
    if b._kind == "CheckButton" then b:SetChecked(not b:GetChecked()) end
    b:GetScript("OnClick")(b, ...)
    return true
end

-- Lo que el addon me ha escrito en el chat desde `from`, lo dicho en /o y lo mandado por la red
local function Chat(a, from)
    local out = {}
    for i = (from or 0) + 1, #a.w.chat do out[#out + 1] = tostring(a.w.chat[i].msg) end
    return table.concat(out, "\n")
end
local function Officer(a)
    local out = {}
    for _, s in ipairs(a.w.said) do if s.kind == "OFFICER" then out[#out + 1] = s.msg end end
    return out
end
local function Sent(a, pattern)
    local out = {}
    for _, m in ipairs(a.w.sent) do if m.text:find(pattern) then out[#out + 1] = m end end
    return out
end

-- La hermandad de las pruebas con mi rango cambiado (0 maestro, 4 miembro)
local function GuildAs(rankIndex)
    local g = F.Guild()
    local rank = rankIndex == 0 and "Maestra" or "Miembro"
    g.rank, g.rankIndex = rank, rankIndex
    g.members[1].rank, g.members[1].rankIndex = rank, rankIndex
    if rankIndex == 0 then g.members[3].rank, g.members[3].rankIndex = "Oficial", 1 end
    return g
end

-- La configuración montada en un marco cualquiera, con sus piezas a mano
local function Config(a)
    Live(a)
    local panel = a.env.CreateFrame("Frame")
    local box = a.HU:BuildUnionConfig(panel)
    local c = { box = box, tab = {} }
    for _, b in ipairs(Kids(a, box, "Button")) do c.tab[b:GetText()] = b end
    local p = Kids(a, box, "Frame")
    c.trade, c.black, c.bank, c.calendar, c.guild = p[1], p[2], p[3], p[4], p[5]
    c.testCb = Kids(a, box, "CheckButton")[1]
    c.who = Kids(a, box, "FontString")[2]
    -- (lo que solo toca el maestro)
    c.controls = {}
    local function Add(list) for _, w in ipairs(list) do c.controls[#c.controls + 1] = w end end
    Add(Kids(a, c.bank, "Button")); Add(Kids(a, c.trade, "CheckButton"))
    Add(Kids(a, c.calendar, "Button")); Add(Kids(a, c.calendar, "EditBox"))
    c.pick = Kids(a, c.guild, "Button")[2]
    Add({ c.pick })
    return c
end
local function Reopen(c) c.box:GetScript("OnShow")() end
local RED, WHITE, GRAY = "|cffff4444", "|cffffffff", "|cff808080"

---------------------------------------------------------------------------
describe("Configuración de la hermandad (UnionConfig.lua): pestañas y quién la cambia", function()
    it("cinco pestañas en dos filas; cada una enseña su página y solo esa (de entrada, Comercio)", function()
        local a = F.Community()
        local c = Config(a)
        -- (tres arriba y dos debajo)
        local where = { { "Comercio", 8, -32 }, { "Lista negra", 95, -32 }, { "Banco", 182, -32 },
            { "Calendario", 8, -56 }, { "Hermandad", 95, -56 } }
        for _, w in ipairs(where) do
            local p = c.tab[w[1]]._points[1]
            A.same({ "TOPLEFT", w[2], w[3] }, { p[1], p[2], p[3] }, w[1])
        end
        local pages = { Comercio = c.trade, ["Lista negra"] = c.black, Banco = c.bank, Calendario = c.calendar, Hermandad = c.guild }
        local function Only(name)
            for n, page in pairs(pages) do
                A.equal(n == name, page:IsShown(), "página " .. n)
                A.equal(n == name, c.tab[n].picked, "pestaña " .. n)
            end
        end
        Only("Comercio")
        for _, w in ipairs(where) do
            A.truthy(Click(c.tab[w[1]]), "las pestañas las pulsa cualquiera")
            Only(w[1])
        end
        A.same({}, a:Errors())
    end)

    it("un oficial la ve apagada; «Probar como maestro» la enciende y se recuerda", function()
        local a = F.Community()
        local HU = a.HU
        local c = Config(a)
        A.equal(14, #c.controls)
        A.equal("Solo el maestro la cambia", c.who:GetText())
        for i, w in ipairs(c.controls) do A.falsy(w:IsEnabled(), "control " .. i) end
        local trade = Kids(a, c.trade, "CheckButton")[1]
        A.falsy(Click(trade), "apagada: no se puede pulsar")
        A.is_nil(HU.db.unionCfg.tradeOff)
        Click(c.tab["Hermandad"])
        A.falsy(Click(c.pick), "ni elegir el color")
        -- (la casilla de abajo: probar la ventana como si fuera el maestro)
        A.falsy(c.testCb:GetChecked())
        A.truthy(Click(c.testCb))
        A.truthy(HU.db.unionCfg.testGM)
        A.equal("|cff40ff40Puedes cambiarla|r", c.who:GetText())
        for i, w in ipairs(c.controls) do A.truthy(w:IsEnabled(), "control " .. i) end
        -- (al abrirla otra vez sigue puesta; quitada, vuelve a estar apagada)
        Reopen(c)
        A.truthy(c.testCb:GetChecked())
        Click(c.testCb)
        A.is_nil(HU.db.unionCfg.testGM)
        A.equal("Solo el maestro la cambia", c.who:GetText())
        for i, w in ipairs(c.controls) do A.falsy(w:IsEnabled(), "control " .. i) end
        A.same({}, a:Errors())
    end)

    it("el maestro de verdad (IsGuildLeader) la cambia sin la casilla", function()
        local a = F.Community({ guild = GuildAs(0) })
        local c = Config(a)
        A.falsy(c.testCb:GetChecked())
        A.equal("|cff40ff40Puedes cambiarla|r", c.who:GetText())
        for i, w in ipairs(c.controls) do A.truthy(w:IsEnabled(), "control " .. i) end
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
describe("Configuración: Comercio y Banco", function()
    it("Comercio: quitar «activo» o «propinas» apunta tradeOff o tipsOff; volver a ponerlas lo borra", function()
        local a = F.Community({ guild = GuildAs(0) })
        local HU = a.HU
        local c = Config(a)
        local checks = Kids(a, c.trade, "CheckButton")
        local active, tips = checks[1], checks[2]
        A.truthy(active:GetChecked(), "de entrada, comercio activo")
        A.truthy(tips:GetChecked(), "y con propinas")
        Click(active)
        A.truthy(HU.db.unionCfg.tradeOff)
        A.falsy(active:GetChecked())
        Click(tips)
        A.truthy(HU.db.unionCfg.tipsOff)
        A.falsy(tips:GetChecked())
        Click(active); Click(tips)
        A.is_nil(HU.db.unionCfg.tradeOff)
        A.is_nil(HU.db.unionCfg.tipsOff)
        -- (lo guardado se enseña al abrirla)
        HU.db.unionCfg.tipsOff = true
        Reopen(c)
        A.truthy(active:GetChecked())
        A.falsy(tips:GetChecked())
        A.same({}, a:Errors())
    end)

    it("Banco: quién lo ve (oficiales o todos) y quién puede pedir (todos, oficiales o nadie); el elegido, oscuro", function()
        local a = F.Community({ guild = GuildAs(0) })
        local HU = a.HU
        local c = Config(a)
        Click(c.tab["Banco"])
        local b = Kids(a, c.bank, "Button")
        local labels = {}
        for i, x in ipairs(b) do labels[i] = x:GetText() end
        A.same({ "Oficiales", "Todos", "Todos", "Oficiales", "Nadie" }, labels)
        local function Picked()
            local out = {}
            for i, x in ipairs(b) do out[i] = x.picked and true or false end
            return out
        end
        -- (de entrada: lo ven los oficiales y pueden pedir todos)
        A.same({ true, false, true, false, false }, Picked())
        Click(b[2])
        A.equal("all", HU.db.unionCfg.bankView)
        A.same({ false, true, true, false, false }, Picked())
        Click(b[5])
        A.equal("none", HU.db.unionCfg.bankRequest)
        A.same({ false, true, false, false, true }, Picked())
        Click(b[4])
        A.equal("officers", HU.db.unionCfg.bankRequest)
        Click(b[1])
        A.equal("officers", HU.db.unionCfg.bankView)
        A.same({ true, false, false, true, false }, Picked())
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
describe("Configuración: Calendario (quién crea eventos y permisos por un tiempo)", function()
    it("quién crea eventos: el maestro, los oficiales (de entrada) o todos; HU:CanMakeEvents lo sigue", function()
        local a = F.Community({ guild = GuildAs(0) })
        local HU = a.HU
        local c = Config(a)
        Click(c.tab["Calendario"])
        local b = Kids(a, c.calendar, "Button")
        A.same({ "Maestro", "Oficiales", "Todos", "Dar" }, { b[1]:GetText(), b[2]:GetText(), b[3]:GetText(), b[4]:GetText() })
        A.truthy(b[2].picked, "de entrada, los oficiales")
        Click(b[1])
        A.equal("gm", HU.db.unionCfg.calMake)
        A.truthy(b[1].picked); A.falsy(b[2].picked)
        A.truthy(HU:CanMakeEvents(), "el maestro, siempre")
        Click(b[3])
        A.equal("all", HU.db.unionCfg.calMake)
        A.truthy(b[3].picked); A.falsy(b[1].picked)
        -- (un oficial: de entrada, sí; con «Maestro», no, salvo probándola como maestro)
        local ao = F.Community()
        local o = ao.HU
        A.truthy(o:CanMakeEvents())
        o.db.unionCfg = { calMake = "gm" }
        A.falsy(o:CanMakeEvents())
        o.db.unionCfg.testGM = true
        A.truthy(o:CanMakeEvents())
        -- (un miembro: solo con «Todos»)
        local am = F.Community({ guild = GuildAs(4) })
        local m = am.HU
        A.falsy(m:CanMakeEvents())
        m.db.unionCfg = { calMake = "all" }
        A.truthy(m:CanMakeEvents())
        A.same({}, a:Errors())
        A.same({}, ao:Errors())
        A.same({}, am:Errors())
    end)

    it("permiso por un tiempo: nombre y horas (24 de entrada, al menos 1); la lista dice «hasta …», por orden de fin", function()
        local a = F.Community()
        local HU = a.HU
        HU.db.unionCfg = { testGM = true } -- (probándola como maestro)
        local c = Config(a)
        Click(c.tab["Calendario"])
        local boxes = Kids(a, c.calendar, "EditBox")
        local name, hours = boxes[1], boxes[2]
        local give = WithText(a, c.calendar, "Dar")
        local rows = Kids(a, c.calendar, "Frame")
        local none = WithText(a, c.calendar, "Nadie tiene permiso por un tiempo.")
        A.equal(5, #rows)
        A.equal("24", hours:GetText())
        A.truthy(none:IsShown())
        for _, r in ipairs(rows) do A.falsy(r:IsShown()) end
        local now = a.env.time()
        name:SetText("Compi"); hours:SetText("2")
        A.truthy(Click(give))
        A.same({ name = "Compi-Reino", untilT = now + 7200, by = "Tester-Reino" }, HU.db.unionCfg.calAllow["compi-reino"])
        A.equal("", name:GetText(), "el nombre se borra")
        A.equal("2", hours:GetText(), "las horas se quedan")
        A.falsy(none:IsShown())
        A.equal("Compi-Reino", rows[1].name:GetText())
        A.equal("hasta " .. a.env.date("%d/%m %H:%M", now + 7200), rows[1].till:GetText())
        A.truthy(rows[1].del:IsShown(), "la X, para el maestro")
        -- (0 horas es 1, lo mínimo; vacío, 24; más de 999, 999)
        name:SetText("Jefa-Reino"); hours:SetText("0"); Click(give)
        name:SetText("Nuevo-Reino"); hours:SetText(""); Click(give)
        name:SetText("Alba-Reino"); hours:SetText("5000"); Click(give)
        local allow = HU.db.unionCfg.calAllow
        A.equal(now + 3600, allow["jefa-reino"].untilT)
        A.equal(now + 86400, allow["nuevo-reino"].untilT)
        A.equal(now + 999 * 3600, allow["alba-reino"].untilT)
        A.same({ "Jefa-Reino", "Compi-Reino", "Nuevo-Reino" }, { rows[1].name:GetText(), rows[2].name:GetText(), rows[3].name:GetText() })
        -- (sin nombre, nada)
        name:SetText("   "); Click(give)
        local n = 0
        for _ in pairs(allow) do n = n + 1 end
        A.equal(4, n)
        A.same({}, a:Errors())
    end)

    it("solo salen las filas que caben; la X quita el permiso y los que se acaban se van solos", function()
        local a = F.Community()
        local HU = a.HU
        local now = a.env.time()
        HU.db.unionCfg = { testGM = true, calAllow = {} }
        for i, n in ipairs({ "Uno", "Dos", "Tres", "Cuatro", "Cinco", "Seis" }) do
            HU.db.unionCfg.calAllow[n:lower() .. "-reino"] = { name = n .. "-Reino", untilT = now + i * 60, by = "Tester-Reino" }
        end
        local c = Config(a)
        Click(c.tab["Calendario"])
        local rows = Kids(a, c.calendar, "Frame")
        local function Shown()
            local out = {}
            for _, r in ipairs(rows) do if r:IsShown() then out[#out + 1] = r.name:GetText() end end
            return out
        end
        -- (sin saber aún el alto de la página, 3; luego las que quepan, hasta 5)
        A.same({ "Uno-Reino", "Dos-Reino", "Tres-Reino" }, Shown())
        c.calendar.GetHeight = function() return 100 + 4 * 18 end
        Reopen(c)
        A.same({ "Uno-Reino", "Dos-Reino", "Tres-Reino", "Cuatro-Reino" }, Shown())
        c.calendar.GetHeight = function() return 400 end
        Reopen(c)
        A.equal(5, #Shown(), "como mucho 5")
        -- (la X)
        A.truthy(Click(rows[2].del))
        A.is_nil(HU.db.unionCfg.calAllow["dos-reino"])
        A.same({ "Uno-Reino", "Tres-Reino", "Cuatro-Reino", "Cinco-Reino", "Seis-Reino" }, Shown())
        -- (pasan 3 min y medio: los de 1, 2 y 3 min se han acabado, y se borran de lo guardado)
        a.w:Advance(210)
        Reopen(c)
        A.same({ "Cuatro-Reino", "Cinco-Reino", "Seis-Reino" }, Shown())
        A.is_nil(HU.db.unionCfg.calAllow["uno-reino"])
        A.is_nil(HU.db.unionCfg.calAllow["tres-reino"])
        -- (quien no es el maestro ve la lista, sin la X)
        Click(c.testCb)
        A.same({ "Cuatro-Reino", "Cinco-Reino", "Seis-Reino" }, Shown())
        A.falsy(Click(rows[1].del))
        A.truthy(HU.db.unionCfg.calAllow["cuatro-reino"])
        -- (y cuando se acaban todos, el aviso)
        a.w:Advance(180)
        Reopen(c)
        A.same({}, Shown())
        A.truthy(WithText(a, c.calendar, "Nadie tiene permiso por un tiempo."):IsShown())
        A.same({}, a:Errors())
    end)

    it("con permiso por un tiempo, quien no es oficial crea eventos hasta que se acaba", function()
        local a = F.Community({ guild = GuildAs(4) })
        local HU = a.HU
        A.falsy(HU:CanMakeEvents())
        HU.db.unionCfg = { calMake = "gm",
            calAllow = { ["tester-reino"] = { name = "Tester-Reino", untilT = a.env.time() + 120, by = "Jefa-Reino" } } }
        A.truthy(HU:CanMakeEvents())
        a.w:Advance(121)
        A.falsy(HU:CanMakeEvents())
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
describe("Configuración: el color de la hermandad", function()
    it("el maestro lo elige con el selector del juego: se guarda en guildColors y se ve en la muestra; Cancelar deja el de antes", function()
        local a = F.Community({ guild = GuildAs(0) })
        local HU = a.HU
        local c = Config(a)
        Click(c.tab["Hermandad"])
        local swatch = Kids(a, c.guild, "Button")[1]
        local label = Kids(a, c.guild, "FontString")[2]
        local before = HU:GuildColorHex("UNO")
        local r0, g0, b0 = HU:GuildColor("UNO")
        A.equal("UNO", label:GetText())
        A.same({ r0, g0, b0 }, swatch._color)
        -- (sin el selector del juego, no hace nada)
        A.truthy(Click(c.pick))
        A.is_nil(HU.db.guildColors and HU.db.guildColors.UNO)
        -- (con él: se abre con el color de ahora; al elegir otro, se guarda y se pinta)
        local info
        a.env.ColorPickerFrame = { SetupColorPickerAndShow = function(_, i) info = i end, GetColorRGB = function() return 1, 0, 0 end }
        Click(c.pick)
        A.same({ r0, g0, b0 }, { info.r, info.g, info.b })
        info.swatchFunc()
        A.same({ hex = "ff0000", by = "Tester-Reino", byTag = "UNO", t = a.env.time() }, HU.db.guildColors.UNO)
        A.same({ 1, 0, 0 }, swatch._color, "la muestra, en rojo")
        A.equal("ff0000", HU:GuildColorHex("UNO"), "y lo usa todo el addon")
        -- (Cancelar: el de antes)
        info.cancelFunc()
        A.equal(before, HU.db.guildColors.UNO.hex)
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
describe("Configuración: la lista negra, en su pestaña", function()
    -- (la página, con sus piezas)
    local function Black(a)
        local c = Config(a)
        Click(c.tab["Lista negra"])
        local b = { c = c, list = Kids(a, c.black, "Frame")[1] }
        b.rows = Kids(a, b.list, "Button")
        b.empty = WithText(a, b.list, "No hay nadie en la lista negra.")
        local boxes = Kids(a, c.black, "EditBox")
        b.name, b.why = boxes[1], boxes[2]
        b.add, b.del, b.check = WithText(a, c.black, "Añadir"), WithText(a, c.black, "Quitar"), WithText(a, c.black, "Comprobar ahora")
        b.labels = { WithText(a, c.black, "Nombre"), WithText(a, c.black, "Motivo") }
        return b
    end
    local function Names(b)
        local out = {}
        for _, r in ipairs(b.rows) do if r:IsShown() then out[#out + 1] = r.name:GetText() end end
        return out
    end

    it("en rojo quien está en mi hermandad; quién lo vetó, con su hermandad en su color; vacía, el aviso", function()
        local a = F.Community()
        local HU = a.HU
        local b = Black(a)
        A.equal(14, #b.rows)
        A.truthy(b.empty:IsShown())
        A.same({}, Names(b))
        HU.db.bans = {
            ["compi-reino"] = { name = "Compi-Reino", on = true, by = "Jefa-Reino", tag = "UNO", why = "insulta", t = 1 },
            ["malo-reino"] = { name = "Malo-Reino", on = true, by = "Bea-Reino", tag = "DOS", why = "estafa", t = 2 },
            ["viejo-reino"] = { name = "Viejo-Reino", on = false, by = "Jefa-Reino", tag = "UNO", t = 3 },
        }
        Reopen(b.c)
        A.falsy(b.empty:IsShown())
        A.same({ RED .. "Compi-Reino|r", WHITE .. "Malo-Reino|r" }, Names(b), "por orden; el readmitido no sale")
        A.equal("Jefa-Reino |cff" .. HU:GuildColorHex("UNO") .. "<UNO>|r", b.rows[1].by:GetText())
        A.equal("Bea-Reino |cff" .. HU:GuildColorHex("DOS") .. "<DOS>|r", b.rows[2].by:GetText())
        -- (un veto que llega de otro oficial sale enseguida, con la pestaña abierta)
        a.w:Receive("HU20", "BN~Nuevo-Reino~1~Jefa-Reino~UNO~" .. a.env.time() .. "~spam", "GUILD", "Jefa-Reino")
        A.same({ RED .. "Compi-Reino|r", WHITE .. "Malo-Reino|r", WHITE .. "Nuevo-Reino|r" }, Names(b))
        A.same({}, a:Errors())
    end)

    it("con muchos vetados, la lista baja con la barra (sin alto todavía, 8 filas; con alto, las que quepan)", function()
        local a = F.Community()
        local HU = a.HU
        HU.db.bans = {}
        for i = 1, 10 do
            local n = string.format("Vetado%02d-Reino", i)
            HU.db.bans[n:lower()] = { name = n, on = true, by = "Jefa-Reino", tag = "UNO", why = "x", t = i }
        end
        local b = Black(a)
        local names = Names(b)
        A.equal(8, #names)
        A.equal(WHITE .. "Vetado01-Reino|r", names[1])
        local scroll = a.env.GuildUnionCfgBlackScroll
        a.env.FauxScrollFrame_SetOffset(scroll, 2)
        scroll:GetScript("OnVerticalScroll")(scroll, 2 * 16)
        names = Names(b)
        A.equal(WHITE .. "Vetado03-Reino|r", names[1])
        A.equal(WHITE .. "Vetado10-Reino|r", names[8])
        scroll.GetHeight = function() return 20 * 16 end
        a.env.FauxScrollFrame_SetOffset(scroll, 0)
        Reopen(b.c)
        A.equal(10, #Names(b))
        A.same({}, a:Errors())
    end)

    it("al pasar el ratón, quién lo vetó y el motivo; al pulsar, el nombre queda abajo para quitarlo", function()
        local a = F.Community()
        local HU = a.HU
        HU.db.bans = {
            ["malo-reino"] = { name = "Malo-Reino", on = true, by = "Bea-Reino", tag = "DOS", why = "estafa", t = 2 },
            ["solo-reino"] = { name = "Solo-Reino", on = true, t = 1 }, -- (de una versión vieja: sin quién ni motivo)
        }
        local b = Black(a)
        local tip, lines = a.env.GameTooltip, {}
        tip.AddLine = function(_, text) lines[#lines + 1] = text end
        tip:Hide()
        local row = b.rows[1]
        A.equal(WHITE .. "Malo-Reino|r", row.name:GetText())
        row:GetScript("OnEnter")(row)
        A.same({ "Malo-Reino", "Lo vetó: Bea-Reino", "estafa" }, lines)
        A.truthy(tip:IsShown())
        row:GetScript("OnLeave")(row)
        A.falsy(tip:IsShown())
        lines = {}
        b.rows[2]:GetScript("OnEnter")(b.rows[2])
        A.same({ "Solo-Reino" }, lines)
        A.equal("", b.rows[2].by:GetText())
        A.equal("", b.name:GetText())
        A.truthy(Click(row))
        A.equal("Malo-Reino", b.name:GetText())
        A.same({}, a:Errors())
    end)

    it("Añadir (con motivo) y Quitar, el maestro y los oficiales; Quitar olvida el aviso que ya se dio en /o", function()
        local a = F.Community()
        local HU = a.HU
        local b = Black(a)
        for _, w in ipairs({ b.name, b.why, b.add, b.del, b.labels[1], b.labels[2] }) do A.truthy(w:IsShown()) end
        -- (sin motivo no se veta: se queda escrito para ponerlo)
        b.name:SetText("Compi-Reino")
        Click(b.add)
        A.falsy(HU:IsBanned("Compi-Reino"))
        A.equal("Compi-Reino", b.name:GetText())
        A.matches("Escribe el motivo del veto", Chat(a))
        -- (con motivo: vetado, las cajas vacías, sale en la lista y, como está en mi hermandad, se avisa en /o)
        b.why:SetText("insulta")
        Click(b.add)
        A.truthy(HU:IsBanned("Compi-Reino"))
        A.equal("", b.name:GetText())
        A.equal("", b.why:GetText())
        A.same({ RED .. "Compi-Reino|r" }, Names(b))
        a.w:Advance(13)
        local said = Officer(a)
        A.equal(1, #said)
        A.equal("[Guild Union] Lista negra: Compi-Reino está en la hermandad. Lo vetó Tester-Reino <UNO>. Motivo: insulta", said[1])
        A.truthy(HU.db.blackSaid["compi-reino"])
        -- (el repaso de cada minuto no lo repite)
        a.w:Advance(75)
        A.equal(1, #Officer(a))
        -- (Quitar a quien no está en la lista: nada)
        b.name:SetText("Nadie-Reino")
        Click(b.del)
        A.equal("Nadie-Reino", b.name:GetText())
        -- (Quitar: readmitido, fuera de la lista y sin el recuerdo del aviso)
        b.name:SetText("Compi-Reino")
        Click(b.del)
        A.falsy(HU:IsBanned("Compi-Reino"))
        A.equal("", b.name:GetText())
        A.same({}, Names(b))
        A.truthy(b.empty:IsShown())
        A.is_nil(HU.db.blackSaid["compi-reino"])
        -- (vetado otra vez: se vuelve a avisar)
        b.name:SetText("Compi-Reino"); b.why:SetText("otra vez")
        Click(b.add)
        a.w:Advance(13)
        A.equal(2, #Officer(a))
        A.matches("Motivo: otra vez$", Officer(a)[2])
        A.same({}, a:Errors())
    end)

    it("Comprobar ahora: me dice quién de la lista está en mi hermandad y quién lo invitó (o que no hay nadie)", function()
        local a = F.Community()
        local HU = a.HU
        local b = Black(a)
        local n0 = #a.w.chat
        A.truthy(Click(b.check))
        A.matches("nadie de la lista está en tu hermandad", Chat(a, n0))
        HU.db.bans = { ["compi-reino"] = { name = "Compi-Reino", on = true, by = "Bea-Reino", tag = "DOS", why = "estafa", t = 1 } }
        HU.db.inviteLog = { ["Hermandad Uno"] = { { t = a.env.time() - 60, by = "Jefa-Reino", who = "Compi-Reino" } } }
        n0 = #a.w.chat
        Click(b.check)
        local text = Chat(a, n0)
        A.matches("Compi%-Reino|r está en tu hermandad%.", text)
        A.matches("Lo vetó Bea%-Reino <DOS>%.", text)
        A.matches("Motivo: estafa", text)
        A.matches("Lo invitó Jefa%-Reino%.", text)
        a.w:Advance(13)
        A.same({}, Officer(a), "a mano, solo me lo dice a mí")
        A.same({}, a:Errors())
    end)

    it("un miembro ve la lista, pero no puede añadir ni quitar (y Comprobar ahora no le dice nada)", function()
        local a = F.Community({ guild = GuildAs(4) })
        local HU = a.HU
        HU.db.bans = { ["malo-reino"] = { name = "Malo-Reino", on = true, by = "Bea-Reino", tag = "DOS", why = "estafa", t = 2 } }
        local b = Black(a)
        A.same({ WHITE .. "Malo-Reino|r" }, Names(b))
        for _, w in ipairs({ b.name, b.why, b.add, b.del, b.labels[1], b.labels[2] }) do A.falsy(w:IsShown()) end
        A.falsy(Click(b.add))
        Click(b.rows[1])
        A.equal("", b.name:GetText(), "pulsar una fila no deja nada abajo")
        local n0 = #a.w.chat
        A.truthy(Click(b.check), "el botón sí se ve")
        A.equal(n0, #a.w.chat)
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
describe("Configuración: la ventana de la lista negra (Blacklist.lua)", function()
    it("Quitar readmite y olvida el aviso dado (HU:Unban): si lo vetan otra vez, se vuelve a avisar en /o", function()
        local a = F.Community()
        local HU = a.HU
        Live(a)
        HU:SetBan("Compi-Reino", true, "insulta")
        HU:BlacklistCheck()
        a.w:Advance(13)
        A.equal(1, #Officer(a))
        HU:BlacklistCheck()
        a.w:Advance(13)
        A.equal(1, #Officer(a), "una vez")
        HU:ShowBlacklist()
        local win = a.env.GuildUnionBlacklistFrame
        A.truthy(win:IsShown())
        win.Refresh() -- (el OnShow, que el WoW de mentira no lanza)
        local cells = win.rows[1].cells
        A.equal(RED .. "Compi-Reino|r", cells[1]:GetText())
        A.equal("Tester-Reino |cff" .. HU:GuildColorHex("UNO") .. "<UNO>|r", cells[2]:GetText())
        A.equal("insulta", cells[3]:GetText())
        A.truthy(Click(win.rows[1]))
        A.equal("Compi-Reino", win.nameBox:GetText())
        A.truthy(Click(WithText(a, win, "Quitar")))
        A.falsy(HU:IsBanned("Compi-Reino"))
        A.equal("", win.nameBox:GetText())
        A.falsy(win.rows[1]:IsShown())
        A.truthy(win.empty:IsShown())
        A.is_nil(HU.db.blackSaid["compi-reino"])
        HU:SetBan("Compi-Reino", true, "otra vez")
        HU:BlacklistCheck()
        a.w:Advance(13)
        A.equal(2, #Officer(a))
        A.same({}, a:Errors())
    end)

    it("un miembro la ve sin poder cambiarla", function()
        local a = F.Community({ guild = GuildAs(4) })
        Live(a)
        a.HU:ShowBlacklist()
        local win = a.env.GuildUnionBlacklistFrame
        win.Refresh()
        A.equal(6, #win.editParts)
        for _, w in ipairs(win.editParts) do A.falsy(w:IsShown()) end
        A.equal("Solo el maestro y los oficiales pueden cambiar la lista.", win.who:GetText())
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
describe("Configuración: registro de invitaciones y salidas (InviteLog.lua)", function()
    local function Log(a)
        Live(a)
        a.HU:ShowInviteLog()
        local win = a.env.GuildUnionInviteLogFrame
        win.Refresh()
        return win
    end
    -- (hermandad, quién y a quién/cómo de cada fila que se ve)
    local function Rows(win)
        local out = {}
        for _, r in ipairs(win.rows) do
            if r:IsShown() then out[#out + 1] = { r.cells[2]:GetText(), r.cells[3]:GetText(), r.cells[4]:GetText() } end
        end
        return out
    end
    local function Search(win, text)
        win.search:SetText(text)
        win.search:GetScript("OnTextChanged")(win.search)
    end

    it("Invitaciones: lo más nuevo arriba, con fecha y hermandad; el buscador mira los nombres y la hermandad", function()
        local a = F.Community()
        local HU = a.HU
        local now = a.env.time()
        HU.db.inviteLog = {
            ["Hermandad Uno"] = { { t = now - 7200, by = "Jefa-Reino", who = "Compi-Reino" }, { t = now - 3600, by = "Tester-Reino", who = "Ido-Reino" } },
            ["Hermandad Dos"] = { { t = now - 60, by = "Bea-Reino", who = "Blas-Reino" } },
            ["Los Antiguos"] = { { t = now - 86400, by = "Viejo-Reino", who = "Nadie-Reino" } }, -- (ya no es de la comunidad)
        }
        local win = Log(a)
        local uno, dos = "|cff" .. HU:GuildColorHex("UNO") .. "UNO|r", "|cff" .. HU:GuildColorHex("DOS") .. "DOS|r"
        -- (en blanco quien sigue en mi hermandad; en gris quien no)
        A.same({
            { dos, "Bea-Reino", GRAY .. "Blas-Reino|r" },
            { uno, "Tester-Reino", GRAY .. "Ido-Reino|r" },
            { uno, "Jefa-Reino", WHITE .. "Compi-Reino|r" },
            { "|cff9a8f78Los Antigu|r", "Viejo-Reino", GRAY .. "Nadie-Reino|r" },
        }, Rows(win))
        A.equal("|cff9a8f78" .. a.env.date("%d/%m/%y %H:%M", now - 60) .. "|r", win.rows[1].cells[1]:GetText())
        A.equal("Invitó", win.hdrCells[3]:GetText())
        A.equal("A quién", win.hdrCells[4]:GetText())
        A.matches("^Quién invitó a quién a tus hermandades%.", win.who:GetText())
        A.matches(GRAY .. "4|r$", win.who:GetText(), "cuántas hay guardadas")
        A.truthy(win.tabs.inviteLog.djPicked)
        A.falsy(win.tabs.leaveLog.djPicked)
        A.falsy(win.empty:IsShown())
        Search(win, "BEA")
        A.same({ { dos, "Bea-Reino", GRAY .. "Blas-Reino|r" } }, Rows(win), "por quien invitó, sin mirar mayúsculas")
        Search(win, "ido")
        A.same({ { uno, "Tester-Reino", GRAY .. "Ido-Reino|r" } }, Rows(win), "por a quién")
        Search(win, "hermandad uno")
        A.equal(2, #Rows(win), "por la hermandad")
        Search(win, "zzz")
        A.same({}, Rows(win))
        A.truthy(win.empty:IsShown())
        Search(win, "")
        A.equal(4, #Rows(win))
        -- (el botón del registro, otra vez: se cierra)
        HU:ShowInviteLog()
        A.falsy(win:IsShown())
        A.same({}, a:Errors())
    end)

    it("Salidas: quién se fue y a quién echaron, y si fue por una solicitud, quién la pidió; en rojo, la lista negra", function()
        local a = F.Community()
        local HU = a.HU
        local now = a.env.time()
        HU.db.leaveLog = { ["Hermandad Uno"] = {
            { t = now - 100, who = "Ido-Reino" },
            { t = now - 50, by = "Tester-Reino", who = "Malo-Reino", req = "Bea-Reino", reqTag = "DOS" },
            { t = now - 10, by = "Jefa-Reino", who = "Compi-Reino" },
        } }
        HU.db.bans = { ["malo-reino"] = { name = "Malo-Reino", on = true, by = "Tester-Reino", tag = "UNO", why = "estafa", t = 1 } }
        local win = Log(a)
        A.same({}, Rows(win), "de entrada, Invitaciones: no hay")
        A.equal("Todavía no hay invitaciones guardadas.", win.empty:GetText())
        A.truthy(win.empty:IsShown())
        A.truthy(Click(win.tabs.leaveLog))
        local uno = "|cff" .. HU:GuildColorHex("UNO") .. "UNO|r"
        A.same({
            { uno, WHITE .. "Compi-Reino|r", "Echado por Jefa-Reino" },
            { uno, RED .. "Malo-Reino|r", "Echado por Tester-Reino  |cff9a8f78pedido por Bea-Reino <DOS>|r" },
            { uno, GRAY .. "Ido-Reino|r", "|cff9a8f78Se fue|r" },
        }, Rows(win))
        A.equal("Quién", win.hdrCells[3]:GetText())
        A.equal("Cómo", win.hdrCells[4]:GetText())
        A.matches("^Quién se fue de tus hermandades o fue echado%.", win.who:GetText())
        A.matches(GRAY .. "3|r$", win.who:GetText())
        A.truthy(win.tabs.leaveLog.djPicked)
        A.falsy(win.tabs.inviteLog.djPicked)
        Search(win, "zzz")
        A.equal("Todavía no hay salidas guardadas.", win.empty:GetText())
        Search(win, "")
        Click(win.tabs.inviteLog)
        A.equal("Invitó", win.hdrCells[3]:GetText())
        A.same({}, Rows(win))
        A.same({}, a:Errors())
    end)

    it("al echar por una solicitud: si el juego ya lo apuntó, se le añade quién la pidió; si no, se apunta y luego no se repite", function()
        local g = F.Guild()
        g.members[#g.members + 1] = { name = "Malo-Reino", rank = "Miembro", rankIndex = 4 }
        g.members[#g.members + 1] = { name = "Ido-Reino", rank = "Miembro", rankIndex = 4 }
        local a = F.Community({ guild = g })
        local HU = a.HU
        local EV = { { "remove", "Tester", "Compi", nil, 0, 0, 0, 0 } }
        a.env.GetNumGuildEvents = function() return #EV end
        a.env.GetGuildEventInfo = function(i) local e = EV[i]; return e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8] end
        a.w:Fire("GUILD_EVENT_LOG_UPDATE")
        local out = HU.db.leaveLog["Hermandad Uno"]
        A.equal(1, #out)
        HU:LogRequestedKick({ target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS" })
        A.equal(1, #out, "la misma salida, no otra")
        A.equal("Bea-Reino", out[1].req)
        A.equal("DOS", out[1].reqTag)
        -- (una salida de hace 3 h no es esta: se apunta aparte)
        EV = { { "remove", "Tester", "Malo", nil, 0, 0, 0, 3 } }
        a.w:Fire("GUILD_EVENT_LOG_UPDATE")
        A.equal(2, #out)
        HU:LogRequestedKick({ target = "Malo-Reino", requester = "Bea-Reino", reqTag = "DOS" })
        A.equal(3, #out)
        local function Of(who, withReq)
            for _, e in ipairs(out) do if e.who == who and (e.req ~= nil) == withReq then return e end end
        end
        A.same({ t = a.env.time(), by = "Tester-Reino", who = "Malo-Reino", req = "Bea-Reino", reqTag = "DOS" }, Of("Malo-Reino", true))
        A.is_nil(Of("Malo-Reino", false).req, "la vieja, sin tocar")
        -- (al revés: apuntada al aceptar; cuando la trae el juego, es la misma)
        HU:LogRequestedKick({ target = "Ido-Reino", requester = "Bea-Reino", reqTag = "DOS" })
        A.equal(4, #out)
        EV = { { "remove", "Tester", "Ido", nil, 0, 0, 0, 0 } }
        a.w:Fire("GUILD_EVENT_LOG_UPDATE")
        A.equal(4, #out)
        A.equal("Bea-Reino", Of("Ido-Reino", true).req)
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
describe("Configuración: «Solicitudes» de otras hermandades (InviteLog.lua)", function()
    local function Requests(a)
        Live(a)
        a.HU:ShowRequests()
        local win = a.env.GuildUnionRequestsFrame
        win.Refresh()
        return win
    end
    -- (las que se ven, por id; con * las elegidas)
    local function Ids(win)
        local out = {}
        for _, r in ipairs(win.rows) do
            if r:IsShown() and r.entry then out[#out + 1] = r.entry.id .. (r.pickTex:IsShown() and "*" or "") end
        end
        return out
    end
    local function Stored(HU)
        local out = {}
        for _, r in ipairs(HU.db.kickRequests or {}) do out[#out + 1] = r.id end
        table.sort(out)
        return out
    end
    local function WithKeys(a, ctrl, shift)
        a.env.IsControlKeyDown = function() return ctrl end
        a.env.IsShiftKeyDown = function() return shift end
    end

    it("Ctrl suma o quita una, Mayús elige de la última a esta; Aceptar varias manda sus órdenes y contesta las que han salido", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "CanKickGuild", true); F.Stub(HU, "CanPromote", true); F.Stub(HU, "CanDemote", true)
        local job
        F.Stub(HU, "RunOrders", function(_, j) job = j end)
        local now = a.env.time()
        HU:AddKickRequest({ id = "k1", target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = now - 30 })
        HU:AddKickRequest({ id = "r1", kind = "rank", rank = 3, target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = now - 20 })
        HU:AddKickRequest({ id = "r2", kind = "rank", rank = 2, target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = now - 10 })
        local win = Requests(a)
        A.same({ "r2", "r1", "k1" }, Ids(win), "lo último, arriba")
        A.matches("Rango: Oficial", win.rows[1].cells[4]:GetText())
        A.matches("Rango: Veterano", win.rows[2].cells[4]:GetText())
        A.matches("Echar", win.rows[3].cells[4]:GetText())
        A.falsy(win.accept:IsEnabled())
        A.falsy(win.reject:IsEnabled())
        Click(win.rows[1])
        A.same({ "r2*", "r1", "k1" }, Ids(win))
        A.equal("Aceptar", win.accept:GetText())
        A.truthy(win.accept:IsEnabled())
        A.truthy(win.reject:IsEnabled())
        WithKeys(a, true, false)
        Click(win.rows[3])
        A.same({ "r2*", "r1", "k1*" }, Ids(win), "Ctrl suma")
        A.equal("Aceptar (2)", win.accept:GetText())
        A.equal("Rechazar (2)", win.reject:GetText())
        WithKeys(a, false, true)
        Click(win.rows[1])
        A.same({ "r2*", "r1*", "k1*" }, Ids(win), "Mayús: de la última elegida (k1) hasta esta")
        A.equal("Aceptar (3)", win.accept:GetText())
        WithKeys(a, true, false)
        Click(win.rows[2])
        A.same({ "r2*", "r1", "k1*" }, Ids(win), "Ctrl sobre una elegida: la quita")
        Click(win.rows[2])
        WithKeys(a, false, false)
        A.same({ "r2*", "r1*", "k1*" }, Ids(win))
        -- (entretanto Compi ha subido a Oficial (2): esa ya no se puede; las otras dos, sí)
        a.w.guild.members[2].rankIndex = 2
        local n0 = #a.w.chat
        a.w:TakeSent()
        A.truthy(Click(win.accept))
        A.matches("Compi%-Reino: ya tiene ese rango", Chat(a, n0))
        A.equal("Solicitudes", job.title)
        A.equal("Compi-Reino (+1)", job.text)
        A.same({ "/gdemote Compi Reino", "/gremove Compi Reino" }, job.lines)
        -- (solo ha salido la primera orden: se contesta esa y se quita; la de echar sigue)
        job.onDone(1)
        a.w:Advance(2)
        A.equal(1, #Sent(a, "^RD~r1$"))
        local rr = Sent(a, "^RR~")
        A.equal(1, #rr)
        A.equal("RR~r1~ok~Tester-Reino~Compi-Reino~", rr[1].text)
        A.equal("Bea-Reino", rr[1].target)
        A.same({}, Sent(a, "^GR~"), "la de echar, sin contestar")
        A.same({ "k1", "r2" }, Stored(HU))
        A.same({}, a:Errors())
    end)

    it("Rechazar las elegidas: a cada uno le contesta «no», se apunta en el registro de oficiales y se quitan", function()
        local a = F.Community()
        local HU = a.HU
        F.Stub(HU, "CanKickGuild", true); F.Stub(HU, "CanPromote", true)
        local now = a.env.time()
        HU:AddKickRequest({ id = "k1", target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = now - 20 })
        HU:AddKickRequest({ id = "r1", kind = "rank", rank = 3, target = "Compi-Reino", requester = "Bruno-Reino", reqTag = "DOS", t = now - 10 })
        local win = Requests(a)
        Click(win.rows[1])
        WithKeys(a, true, false)
        Click(win.rows[2])
        WithKeys(a, false, false)
        a.w:TakeSent()
        A.truthy(Click(win.reject))
        a.w:Advance(2)
        local gr, rr = Sent(a, "^GR~")[1], Sent(a, "^RR~")[1]
        A.equal("GR~k1~no~Tester-Reino~Compi-Reino~rechazado", gr.text)
        A.equal("Bea-Reino", gr.target)
        A.equal("RR~r1~no~Tester-Reino~Compi-Reino~rechazado", rr.text)
        A.equal("Bruno-Reino", rr.target)
        A.equal(1, #Sent(a, "^GD~k1$"))
        A.equal(1, #Sent(a, "^RD~r1$"))
        A.same({}, Stored(HU))
        A.same({}, Ids(win))
        A.truthy(win.empty:IsShown())
        local texts = {}
        for _, e in ipairs(HU.db.audit) do texts[e.text] = true end
        A.truthy(texts["rechazó echar a Compi-Reino (lo pidió Bea-Reino)"])
        A.truthy(texts["rechazó la petición de Bruno-Reino (Compi-Reino como Veterano)"])
        -- (y la X de una sola fila, igual)
        HU:AddKickRequest({ id = "k2", target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = now })
        A.same({ "k2" }, Ids(win))
        a.w:TakeSent()
        A.truthy(Click(win.rows[1].no))
        a.w:Advance(2)
        A.equal("GR~k2~no~Tester-Reino~Compi-Reino~rechazado", Sent(a, "^GR~")[1].text)
        A.same({}, Stored(HU))
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
describe("Configuración: peticiones de otra hermandad, echar (GK, Social.lua) y cambiar de rango (GP, Ranks.lua)", function()
    -- (Bea, oficial de DOS, y Blas, miembro, conectados: mi addon los conoce por la lista de DOS)
    local function KnowDOS(a)
        local members = { { name = "Bea-Reino", rankIndex = 1, online = true }, { name = "Blas-Reino", rankIndex = 4, online = true } }
        a.HU.remoteRoster.DOS = a.HU.IndexRoster({ members = members, total = 2, online = 2, updated = a.w.now })
    end
    local function Stored(HU)
        local out = {}
        for _, r in ipairs(HU.db.kickRequests or {}) do out[#out + 1] = r.id end
        table.sort(out)
        return out
    end

    it("GK: la de una oficial de DOS va a «Solicitudes» y se reparte a mi hermandad; contestada por otro oficial, se quita", function()
        local a = F.Community()
        local HU = a.HU
        KnowDOS(a)
        F.Stub(HU, "CanKickGuild", true)
        a.w:TakeSent()
        local msg = "GK~k1~UNO~Compi-Reino~Bea-Reino~DOS"
        a.w:Receive("HU20", msg, "WHISPER", "Bea-Reino")
        A.same({ id = "k1", target = "Compi-Reino", requester = "Bea-Reino", reqTag = "DOS", t = a.env.time() }, HU.db.kickRequests[1])
        A.equal(1, HU:KickRequestCount())
        a.w:Advance(2)
        local fwd = Sent(a, "^GK~")
        A.equal(1, #fwd)
        A.equal(msg, fwd[1].text)
        A.equal("GUILD", fwd[1].dist)
        -- (otra vez la misma: ni se apunta ni se reparte)
        a.w:Receive("HU20", msg, "WHISPER", "Bea-Reino")
        a.w:Advance(2)
        A.same({ "k1" }, Stored(HU))
        A.equal(1, #Sent(a, "^GK~"))
        -- (otro oficial la ha contestado: GD por la hermandad)
        a.w:Receive("HU20", "GD~k1", "GUILD", "Jefa-Reino")
        A.same({}, Stored(HU))
        A.same({}, a:Errors())
    end)

    it("GK: no valen las de otra hermandad, las firmadas o traídas por quien no es de la comunidad, las que trae otro, ni más de 3 por minuto", function()
        local a = F.Community()
        local HU = a.HU
        KnowDOS(a)
        F.Stub(HU, "CanKickGuild", true)
        local function GK(id, tag, target, requester, sender)
            a.w:Receive("HU20", table.concat({ "GK", id, tag, target, requester, "DOS" }, "~"), "WHISPER", sender or requester)
        end
        GK("k1", "DOS", "Blas-Reino", "Bea-Reino") -- (para su propia hermandad)
        GK("k2", "UNO", "Compi-Reino", "Intruso-Reino", "Bea-Reino") -- (firmada por alguien de fuera)
        GK("k3", "UNO", "Compi-Reino", "Bea-Reino", "Blas-Reino") -- (la trae Blas, que no reparte por DOS)
        GK("k4", "UNO", "Nadie-Reino", "Bea-Reino") -- (no es de mi hermandad)
        GK("k5", "UNO", "Compi-Reino", "Intruso-Reino") -- (de alguien de fuera)
        A.same({}, Stored(HU))
        GK("k6", "UNO", "Compi-Reino", "Bea-Reino")
        A.same({ "k6" }, Stored(HU))
        -- (Bea lleva 2 este minuto, k4 y k6: una más vale, la cuarta no)
        GK("k7", "UNO", "Compi-Reino", "Bea-Reino")
        GK("k8", "UNO", "Compi-Reino", "Bea-Reino")
        A.same({ "k6", "k7" }, Stored(HU))
        -- (pasado el minuto vuelve a valer; sin permiso para echar, no)
        a.w:Advance(61)
        F.Stub(HU, "CanKickGuild", false)
        GK("k9", "UNO", "Compi-Reino", "Bea-Reino")
        A.same({ "k6", "k7" }, Stored(HU))
        F.Stub(HU, "CanKickGuild", true)
        GK("k10", "UNO", "Compi-Reino", "Bea-Reino")
        A.same({ "k10", "k6", "k7" }, Stored(HU))
        A.same({}, a:Errors())
    end)

    it("GP: el cambio de rango que pide una oficial de DOS va a «Solicitudes»; sin permiso para cambiar rangos, no", function()
        local a = F.Community()
        local HU = a.HU
        KnowDOS(a)
        F.Stub(HU, "CanPromote", true)
        a.w:TakeSent()
        local msg = "GP~r1~UNO~Compi-Reino~3~Bea-Reino~DOS"
        a.w:Receive("HU20", msg, "WHISPER", "Bea-Reino")
        A.same({ id = "r1", kind = "rank", target = "Compi-Reino", rank = 3, requester = "Bea-Reino", reqTag = "DOS", t = a.env.time() },
            HU.db.kickRequests[1])
        A.equal(1, HU:KickRequestCount())
        a.w:Advance(2)
        local fwd = Sent(a, "^GP~")
        A.equal(1, #fwd)
        A.equal("GUILD", fwd[1].dist, "se reparte a mi hermandad")
        -- (repetida, con un rango que no es un número, o para otra hermandad: nada)
        a.w:Receive("HU20", msg, "WHISPER", "Bea-Reino")
        a.w:Receive("HU20", "GP~r2~UNO~Compi-Reino~x~Bea-Reino~DOS", "WHISPER", "Bea-Reino")
        a.w:Receive("HU20", "GP~r3~DOS~Blas-Reino~3~Bea-Reino~DOS", "WHISPER", "Bea-Reino")
        A.same({ "r1" }, Stored(HU))
        -- (contestada por otro oficial: RD)
        a.w:Receive("HU20", "RD~r1", "GUILD", "Jefa-Reino")
        A.same({}, Stored(HU))
        -- (sin permiso para ascender ni degradar, o para alguien que no es de mi hermandad: no me sale)
        F.Stub(HU, "CanPromote", false)
        a.w:Receive("HU20", "GP~r4~UNO~Compi-Reino~3~Bea-Reino~DOS", "WHISPER", "Bea-Reino")
        F.Stub(HU, "CanPromote", true)
        a.w:Receive("HU20", "GP~r5~UNO~Nadie-Reino~3~Bea-Reino~DOS", "WHISPER", "Bea-Reino")
        A.same({}, Stored(HU))
        A.same({}, a:Errors())
    end)

    it("pedirlo a otra hermandad: solo los oficiales y con alguien de ella conectado; la respuesta dice si se hizo", function()
        local a = F.Community()
        local HU = a.HU
        KnowDOS(a)
        a.w:TakeSent()
        local n0 = #a.w.chat
        HU:AskGuildKick("Compi-Reino", "UNO") -- (a mi propia hermandad, no)
        HU:AskGuildRank("Compi-Reino", "UNO", 3)
        HU:AskGuildRank("Blas-Reino", "DOS", nil)
        A.equal(n0, #a.w.chat)
        -- (nadie de DOS con el addon conectado)
        HU:AskGuildKick("Blas-Reino", "DOS")
        A.matches("Ahora no hay nadie de <DOS> con el addon conectado: prueba más tarde%.", Chat(a, n0))
        n0 = #a.w.chat
        HU:AskGuildRank("Blas-Reino", "DOS", 3)
        A.matches("Ahora no hay nadie de <DOS> con el addon conectado", Chat(a, n0))
        a.w:Advance(2)
        A.same({}, Sent(a, "^G[KP]~"))
        -- (con Bea conectada: se le susurra a ella)
        F.Stub(HU, "BestPeer", { name = "Bea-Reino", tag = "DOS" })
        HU.remoteRanks.DOS = { "Maestro", "Oficial", "Oficial", "Veterano", "Miembro" }
        n0 = #a.w.chat
        HU:AskGuildKick("Blas-Reino", "DOS")
        A.matches("Pedido a <DOS> que eche a Blas%-Reino: lo verán sus oficiales en «Solicitudes»%.", Chat(a, n0))
        n0 = #a.w.chat
        HU:AskGuildRank("Blas-Reino", "DOS", 3)
        A.matches("Pedido a <DOS> que Blas%-Reino pase a Veterano: lo verán sus oficiales en «Solicitudes»%.", Chat(a, n0))
        a.w:Advance(2)
        local gk, gp = Sent(a, "^GK~")[1], Sent(a, "^GP~")[1]
        A.equal("Bea-Reino", gk.target)
        A.equal("WHISPER", gk.dist)
        A.equal("Bea-Reino", gp.target)
        local kid = gk.text:match("^GK~([^~]+)~DOS~Blas%-Reino~Tester%-Reino~UNO$")
        local rid = gp.text:match("^GP~([^~]+)~DOS~Blas%-Reino~3~Tester%-Reino~UNO$")
        A.truthy(kid, gk.text)
        A.truthy(rid, gp.text)
        -- (las respuestas: hecho, o no y por qué)
        n0 = #a.w.chat
        a.w:Receive("HU20", "GR~" .. kid .. "~ok~Bea-Reino~Blas-Reino~", "WHISPER", "Bea-Reino")
        A.matches("Hecho:|r Blas%-Reino ya no está en Hermandad Dos %(lo echó Bea%-Reino%)%.", Chat(a, n0))
        n0 = #a.w.chat
        a.w:Receive("HU20", "RR~" .. rid .. "~no~Bea-Reino~Blas-Reino~tiene un rango igual o superior al tuyo", "WHISPER", "Bea-Reino")
        A.matches("No aplicado:|r Blas%-Reino %(Bea%-Reino: tiene un rango igual o superior al tuyo%)%.", Chat(a, n0))
        -- (la misma respuesta otra vez, o una que no he pedido: nada)
        n0 = #a.w.chat
        a.w:Receive("HU20", "GR~" .. kid .. "~ok~Bea-Reino~Blas-Reino~", "WHISPER", "Bea-Reino")
        a.w:Receive("HU20", "RR~zzzz~ok~Bea-Reino~Blas-Reino~", "WHISPER", "Bea-Reino")
        A.equal(n0, #a.w.chat)
        -- (quien no es oficial no puede pedirlo)
        F.Stub(HU, "CanOfficer", false)
        n0 = #a.w.chat
        HU:AskGuildKick("Blas-Reino", "DOS")
        HU:AskGuildRank("Blas-Reino", "DOS", 3)
        local said = Chat(a, n0)
        A.matches("Solo los oficiales pueden pedir echar a alguien de otra hermandad%.", said)
        A.matches("Solo los oficiales pueden pedir cambios de rango a otra hermandad%.", said)
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
describe("Configuración: peticiones entre hermandades, de punta a punta (red)", function()
    -- (UNO: Ana, oficial, y Alba; DOS: Bea y Bruno, oficiales, y Blas y Berta)
    local function Union()
        local net = red.New()
        local p = {
            ana = net:Player("Ana", "UNO", { rankIndex = 1 }),
            alba = net:Player("Alba", "UNO"),
            bea = net:Player("Bea", "DOS", { rankIndex = 1 }),
            bruno = net:Player("Bruno", "DOS", { rankIndex = 2 }),
            blas = net:Player("Blas", "DOS"),
            berta = net:Player("Berta", "DOS"),
        }
        for _, n in ipairs({ "ana", "alba", "bea", "bruno", "blas", "berta" }) do net:Login(p[n]) end
        -- (los oficiales de DOS pueden echar y cambiar rangos: el WoW de mentira no trae esos permisos)
        for _, n in ipairs({ "bea", "bruno" }) do
            p[n].env.CanGuildRemove = function() return true end
            p[n].env.CanGuildPromote = function() return true end
            p[n].env.CanGuildDemote = function() return true end
        end
        net:Advance(90)
        -- (los oficiales confirman la lista de la otra hermandad, «/gu confirmar ETIQ»: sin eso la
        -- seguridad no acepta los susurros de la otra hermandad, como en escenario.lua)
        p.ana.HU:ConfirmRoster("DOS")
        p.bea.HU:ConfirmRoster("UNO")
        net:Advance(30)
        return net, p
    end
    -- (Bea la acepta en su «Solicitudes»: el tic de la primera; la ventana de órdenes lo manda todo)
    local function Accept(q)
        Live(q.a)
        local job
        F.Stub(q.HU, "RunOrders", function(_, j) job = j end)
        q.HU:ShowRequests()
        local win = q.env.GuildUnionRequestsFrame
        win.Refresh()
        A.truthy(Click(win.rows[1].yes))
        job.onDone(#job.lines)
        return job
    end

    it("echar (GK): Ana pide echar a Blas; les sale a los oficiales de DOS; Bea acepta, a Bruno se le quita y a Ana le llega «Hecho»", function()
        local net, p = Union()
        local n0 = #p.ana.w.chat
        p.ana.HU:AskGuildKick("Blas-Reino", "DOS")
        A.matches("Pedido a <DOS> que eche a Blas%-Reino", Chat(p.ana.a, n0))
        net:Advance(5)
        A.equal(1, p.bea.HU:KickRequestCount())
        A.equal(1, p.bruno.HU:KickRequestCount())
        A.equal(0, p.berta.HU:KickRequestCount(), "Berta no puede echar")
        local r = p.bea.HU.db.kickRequests[1]
        A.equal("Ana-Reino", r.requester)
        A.equal("UNO", r.reqTag)
        A.equal("Blas-Reino", r.target)
        A.same({ "/gremove Blas Reino" }, Accept(p.bea).lines)
        n0 = #p.ana.w.chat
        net:Advance(5)
        A.equal(0, p.bea.HU:KickRequestCount())
        A.equal(0, p.bruno.HU:KickRequestCount(), "a Bruno se le quita: ya está contestada")
        A.matches("Hecho:|r Blas%-Reino ya no está en Hermandad Dos %(lo echó Bea%-Reino%)", Chat(p.ana.a, n0))
        -- (y en las Salidas de Bea, con quién lo pidió)
        local out
        for _, l in pairs(p.bea.HU.db.leaveLog or {}) do out = l end
        A.equal("Ana-Reino", out and out[1] and out[1].req)
        A.same({}, net:Errors())
    end)

    it("rango (GP): Ana pide que Berta pase a Veterano; Bea acepta con su /gpromote y a Ana le llega «Hecho»", function()
        local net, p = Union()
        p.ana.HU:AskGuildRank("Berta-Reino", "DOS", 3)
        net:Advance(5)
        A.equal(1, p.bea.HU:KickRequestCount())
        A.equal(1, p.bruno.HU:KickRequestCount())
        local r = p.bea.HU.db.kickRequests[1]
        A.equal("rank", r.kind)
        A.equal(3, r.rank)
        A.equal("Berta-Reino", r.target)
        A.same({ "/gpromote Berta Reino" }, Accept(p.bea).lines)
        local n0 = #p.ana.w.chat
        net:Advance(5)
        A.equal(0, p.bea.HU:KickRequestCount())
        A.equal(0, p.bruno.HU:KickRequestCount(), "a Bruno se le quita (RD)")
        -- (el nombre del rango, el de DOS: le llegó con su lista de rangos, RN)
        A.matches("Hecho:|r Berta%-Reino ahora es Veterano %(lo aplicó Bea%-Reino%)", Chat(p.ana.a, n0))
        A.same({}, net:Errors())
    end)
end)
