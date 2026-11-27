-- Hermandad sola (Config.lua, HU:IsSolo; Jorge, 27/11): una hermandad sin comunidad, sin líneas GU: en la Información de
-- hermandad, usa Eventos, Comercio, encargos y Oficiales dentro de la hermandad, sin canal. Visto en el juego con una
-- hermandad que usa el addon sola: «Solo los oficiales crean eventos» con un rango de oficial que no se llama así, «No se ha podido
-- crear el evento» al maestro, y «tu hermandad todavía no está en la unión» en los encargos, también en los personales
local red = require("lib.red")
local addon = require("lib.addon")
local F = require("lib.fixtures")
local A = assert_

local GUILD = "Los Valientes del Bosque"
-- (su Información de hermandad: texto suyo, sin ninguna línea GU:)
local INFO = "Bienvenidos a Los Valientes del Bosque.\nRaid los sábados a las 21:00."
-- (las líneas que pega el maestro al crear la comunidad con el asistente)
local COMMUNITY = INFO .. "\nGU:t:Valientes\nGU:p:VDB\nGU:c:CanalVdb:clave\nGU:g:Los Valientes del Bosque:VDB"

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

-- Jaime (maestro), Leo (rango 2, «Capitán», con la casilla «Oficial» del Control de hermandad) y Fina (miembro). Los
-- de `late` no entran todavía
local function Guild(late, info)
    local net = red.New({ step = 0.5, info = info or INFO, guilds = { VB = GUILD } })
    local p = {
        jaime = net:Player("Jaime", "VB", { rankIndex = 0, surname = "Nieve" }),
        leo = net:Player("Leo", "VB", { rankIndex = 2, surname = "Roble" }),
        fina = net:Player("Fina", "VB", { surname = "Brisa" }),
    }
    p.leo.member.rank = "Capitán"
    for _, n in ipairs({ "jaime", "leo", "fina" }) do
        if not (late and late[n]) then net:Login(p[n]) end
    end
    net:Advance(150)
    return net, p
end

-- (la Información nueva le llega a cada uno, como cuando el maestro la cambia)
local function NewInfo(net, p, info)
    net.info = info
    for _, q in pairs(p) do
        if q.online then q.w.guildInfo = info; q.w:Fire("GUILD_ROSTER_UPDATE") end
    end
end

local function Said(q, text)
    for _, l in ipairs(q.w.chat) do if tostring(l.msg):find(text, 1, true) then return true end end
    return false
end

---------------------------------------------------------------------------
-- La sección Eventos de cada uno (como en eventos_spec)
---------------------------------------------------------------------------
local function Click(b, ...) return b:GetScript("OnClick")(b, ...) end
local function Child(q, parent, text)
    for _, f in ipairs(q.w.frames) do
        if f._parent == parent and f._kind == "Button" and f:GetText() == text then return f end
    end
end
-- (la ventana de hermandad del juego, lo justo, una vez por jugador: la sección Eventos y la de Comercio cuelgan de ella.
-- El WoW de mentira no recuerda las casillas marcadas ni los botones apagados: aquí, sí)
local function Communities(q)
    if q.env.CommunitiesFrame then return end
    local meta = q.w.frameMeta
    local base = meta.__index
    local extra = {
        SetChecked = function(self, v) rawset(self, "_checked", v and true or false) end,
        GetChecked = function(self) return rawget(self, "_checked") == true end,
        SetEnabled = function(self, v) rawset(self, "_off", not v) end,
        Enable = function(self) rawset(self, "_off", false) end,
        Disable = function(self) rawset(self, "_off", true) end,
        IsEnabled = function(self) return not rawget(self, "_off") end,
    }
    meta.__index = function(f, k) return extra[k] or base(f, k) end
    local env = q.env
    local f = env.CreateFrame("Frame", "CommunitiesFrame")
    f.Chat, f.GuildInfoTab, f.CommunitiesControlFrame = false, false, false
    f.ChatTab = env.CreateFrame("CheckButton", nil, f)
    f.RosterTab = env.CreateFrame("CheckButton", nil, f)
    f.CommunitiesList = env.CreateFrame("Frame", nil, f)
    f.MemberList = env.CreateFrame("Frame", nil, f)
    f.MemberList.IsVisible = function() return true end
    local chk = env.CreateFrame("CheckButton", nil, f.MemberList)
    f.MemberList.ShowOfflineButton = chk
    chk.IsVisible = function() return true end
    q.w:Fire("ADDON_LOADED", "Blizzard_Communities")
end
local function Open(q)
    Communities(q)
    local env = q.env
    local cover = env.GuildUnionUnionRoster
    local ui = cover.calendar
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
-- Un evento nuevo con la ventana, mañana a las 20:00
local function Create(q, ui, title)
    Click(ui.new)
    local nd = ui.newDlg
    nd.title:SetText(title)
    Click(nd.dayBtn)
    local dp = nd.popups[2]
    local tm = q.env.date("*t", q.env.time() + 86400)
    if tm.month ~= dp.m then Click(Child(q, dp, ">")) end
    for _, c in ipairs(dp.cells) do if c:IsShown() and c.day == tm.day then Click(c) end end
    Click(Child(q, nd, "Crear"))
    A.falsy(nd:IsShown(), "no se ha creado: " .. title)
end

---------------------------------------------------------------------------
-- La sección Comercio de cada uno (como en encargos_spec)
---------------------------------------------------------------------------
local function Visible(f)
    while f do
        if f._shown == false then return false end
        f = f._parent
    end
    return true
end
local function OpenTrade(q)
    Communities(q)
    local tr = q.env.GuildUnionUnionRoster.trade
    tr.IsVisible = function(self) return Visible(self) end
    tr:Show()
    q.tr = tr
    return tr
end
local function Row(tr, text)
    for _, r in ipairs(tr.req.rows) do
        if r:IsShown() and r.entry and r.entry.item:find(text, 1, true) then return r end
    end
end
local function Btn(q, parent, text)
    for _, fr in ipairs(q.w.frames) do if fr._parent == parent and fr:GetText() == text then return fr end end
end
-- (pedir con «+ Nuevo anuncio»: al Tablón o, con `to`, a esa persona)
local function Ask(q, item, to)
    q.tr.OpenNew(to)
    local d = q.env.GuildUnionTradeNew
    d.item:SetText(item)
    Click(Btn(q, d, "Publicar"))
end
local function Req(HU, text)
    for _, r in ipairs(HU:TradeRequests()) do if r.item:find(text, 1, true) then return r end end
end

describe("Hermandad sola: todo funciona sin crear la comunidad", function()
    it("Leo, oficial con un rango que no se llama «Oficial», crea un evento y Fina lo ve al momento; el maestro también crea", function()
        local net, p = Guild()
        local leo, fina, jaime = Open(p.leo), Open(p.fina), Open(p.jaime)
        A.truthy(p.leo.HU:CanMakeEvents(), "Leo es oficial: su rango tiene la casilla «Oficial»")
        A.truthy(leo.new:IsEnabled(), "«+ Nuevo evento», encendido")
        Create(p.leo, leo, "Noche de JcJ")
        net:Advance(2)
        A.same({ "Noche de JcJ" }, Titles(fina), "Fina, al momento")
        A.falsy(fina.new:IsEnabled(), "un miembro no crea")
        Create(p.jaime, jaime, "Pesca en Tuercespina")
        net:Advance(2)
        A.same({ "Noche de JcJ", "Pesca en Tuercespina" }, Titles(fina))
        A.falsy(Said(p.jaime, "No se ha podido crear el evento."))
        A.same({}, net:Errors())
    end)

    it("Leo pide al Tablón y Fina lo ve; un encargo personal a Jaime le llega solo a Jaime", function()
        local net, p = Guild()
        for _, n in ipairs({ "jaime", "leo", "fina" }) do OpenTrade(p[n]) end
        Ask(p.leo, "Cinturón de lino")
        A.falsy(Said(p.leo, "todavía no está en la unión"))
        A.truthy(Row(p.leo.tr, "Cinturón de lino"), "en el Tablón de Leo")
        A.truthy(Until(net, function() return Row(p.fina.tr, "Cinturón de lino") ~= nil end, 120), "no le llega a Fina")
        Ask(p.leo, "Bolsa de lino", "Jaime-Nieve")
        A.falsy(Said(p.leo, "todavía no está en la unión"), "el personal, tampoco")
        A.truthy(Req(p.leo.HU, "Bolsa de lino"))
        A.truthy(Until(net, function() return Req(p.jaime.HU, "Bolsa de lino") ~= nil end, 120), "no le llega a Jaime")
        A.is_nil(Row(p.fina.tr, "Bolsa de lino"), "Fina no ve el personal")
        A.same({}, net:Errors())
    end)

    it("Fina entra tarde y ve lo que se creó antes, aunque quien lo creó ya no esté", function()
        local net, p = Guild({ fina = true })
        Create(p.leo, Open(p.leo), "Raid del sábado")
        net:Advance(5)
        net:Logout(p.leo)
        net:Login(p.fina)
        net:Advance(30)
        local fina = Open(p.fina)
        A.truthy(Until(net, function() return Card(fina, "Raid del sábado") ~= nil end, 300), "no le llega")
        A.same({}, net:Errors())
    end)

    it("sin canal: nadie entra en un canal del addon ni lo pide, y no sale ningún aviso del canal", function()
        local net, p = Guild()
        net:Advance(1800)
        for name, set in pairs(net.members) do A.is_nil(next(set), "alguien en el canal " .. name) end
        for _, m in ipairs(net.log) do
            A.falsy(m.text:match("^CQ"), "pide el canal: " .. m.text)
            A.falsy(m.dist == "CHANNEL", "por un canal: " .. m.text)
        end
        for n, q in pairs(p) do
            for _, l in ipairs(q.w.chat) do A.falsy(tostring(l.msg):lower():find("canal"), n .. ": " .. tostring(l.msg)) end
            A.truthy(q.HU:IsSolo(), n .. ": hermandad sola")
            A.falsy(q.HU:HasCommunity(), n .. ": sin comunidad")
        end
        A.same({}, net:Errors())
    end)

    it("la pestaña lo dice: «Hermandad sola»; el maestro ve «Crear comunidad», y nadie «Invitar» ni «Gestionar»", function()
        local _, p = Guild()
        for _, n in ipairs({ "jaime", "leo" }) do
            local q = p[n]
            q.HU:OpenMainWindow()
            local panel = q.env.GuildUnionReducePanel
            panel:GetScript("OnShow")(panel)
            A.matches("Hermandad sola", panel.status:GetText(), n)
            A.falsy(panel.status:GetText():find("Canal"), n .. ": sin canal")
            A.equal("Crear comunidad", panel.createBtn:GetText(), n)
            A.equal(n == "jaime", panel.createBtn:IsShown() == true, n .. ": «Crear comunidad», solo el maestro")
            A.falsy(panel.manageBtn:IsShown(), n .. ": nada que gestionar")
        end
        A.falsy(p.jaime.HU:CanInvite(), "sin comunidad no se invita")
    end)

    it("la etiqueta sale del nombre: la misma para todos, otra para otra hermandad, y no se enseña", function()
        local net, p = Guild()
        local tag = p.leo.HU.myTag
        A.matches("^S%w%w%w%w%w$", tostring(tag))
        A.equal(tag, p.fina.HU.myTag)
        A.equal(tag, p.leo.HU.SoloTag(GUILD))
        A.equal(tag, p.leo.HU.SoloTag("los valientes del bosque"), "sin mirar mayúsculas")
        A.truthy(tag ~= p.leo.HU.SoloTag("Los Løbos Grises") and p.leo.HU.SoloTag("Los Løbos Grises") ~= p.leo.HU.SoloTag("Los Lôbos Grises"),
            "nombres parecidos, etiquetas distintas: no se mezclan en la misma cuenta")
        A.equal(GUILD, p.leo.HU:GuildName(tag))
        -- (en pantalla, las iniciales: en el chat con etiqueta delante del nombre, <LVDB>, no la huella)
        A.equal("LVDB", p.fina.HU:TagLabel(tag))
        A.equal("UNO", p.fina.HU:TagLabel("UNO"), "las de una comunidad, tal cual")
        p.fina.HU.db.chatMark = "tag"
        local head = p.fina.HU:FormatLineParts("main", tag, "Leo-Roble", "Hola")
        A.truthy(head:find("<LVDB>", 1, true), head)
        A.falsy(head:find("<" .. tag .. ">", 1, true), head)
        A.same({}, net:Errors())
    end)
end)

describe("Hermandad sola: el botón del minimapa y /gu estado", function()
    -- (el recuadro del botón del minimapa, con sus líneas, y su objeto de LibDataBroker)
    local function Tip(q)
        local obj = q.env.LibStub("LibDataBroker-1.1"):GetDataObjectByName("GuildUnion")
        local lines = {}
        obj.OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end })
        return lines, obj
    end
    local function Has(lines, text)
        for _, l in ipairs(lines) do if tostring(l):find(text, 1, true) then return true end end
        return false
    end
    -- (qué abre el clic derecho: la Gestión de hermandades o la ventana de GuildUnion)
    local function RightClick(q, obj)
        local got = {}
        F.Stub(q.HU, "ShowGuildsWindow", function() got[#got + 1] = "hermandades" end)
        F.Stub(q.HU, "OpenMainWindow", function() got[#got + 1] = "guildunion" end)
        obj.OnClick(nil, "RightButton")
        return got
    end

    it("el minimapa dice «Hermandad sola», sin canal ni «Gestión de hermandades»; el clic derecho abre GuildUnion", function()
        local net, p = Guild()
        local lines, obj = Tip(p.leo)
        A.equal(GUILD, lines[1], "de título, el nombre de la hermandad")
        A.truthy(Has(lines, "Hermandad sola (sin comunidad)"))
        A.falsy(Has(lines, "Canal"))
        A.falsy(Has(lines, "Gestión de hermandades"))
        A.same({ "guildunion" }, RightClick(p.leo, obj))
        A.same({}, net:Errors())
    end)

    it("con comunidad, como siempre: el canal, «Gestión de hermandades» y el clic derecho de un oficial la abre", function()
        local net, p = Guild(nil, COMMUNITY)
        local lines, obj = Tip(p.leo)
        A.equal("Valientes", lines[1])
        A.truthy(Has(lines, "Canal"))
        A.truthy(Has(lines, "Gestión de hermandades"))
        A.same({ "hermandades" }, RightClick(p.leo, obj))
        A.same({ "guildunion" }, RightClick(p.fina, select(2, Tip(p.fina))), "un miembro: GuildUnion")
        A.same({}, net:Errors())
    end)

    it("/gu estado: hermandad sola, cuántos tienen el addon y nada del canal", function()
        local net, p = Guild()
        local lines = p.leo.HU:StatusLines()
        A.matches("Los Valientes del Bosque", lines[1])
        A.matches("hermandad sola", lines[1])
        A.truthy(Has(lines, "Crear comunidad"))
        A.truthy(Has(lines, "Con el addon en tu hermandad: 3"))
        A.falsy(Has(lines, "Canal"))
        A.same({}, net:Errors())
    end)
end)

describe("Hermandad sola: al crear la comunidad, o al dejarla, no se pierde nada", function()
    it("el maestro pega las líneas de la comunidad: los eventos y encargos de antes siguen, con la etiqueta nueva", function()
        local net, p = Guild()
        local old = p.fina.HU.myTag
        Create(p.leo, Open(p.leo), "Antes de la comunidad")
        OpenTrade(p.leo)
        Ask(p.leo, "Capa de lana")
        net:Advance(5)
        NewInfo(net, p, COMMUNITY)
        A.truthy(Until(net, function() return p.fina.HU.myTag == "VDB" and p.leo.HU.myTag == "VDB" end, 60), "no ve la comunidad")
        A.falsy(p.fina.HU:IsSolo())
        A.truthy(p.fina.HU:HasCommunity())
        net:Advance(5)
        A.same({ "Antes de la comunidad" }, Titles(Open(p.fina)), "el evento sigue")
        A.truthy(Req(p.fina.HU, "Capa de lana"), "el encargo sigue")
        A.is_nil(next(p.fina.HU.db.wuStore[old] or {}), "lo de la etiqueta de antes, mudado")
        -- (y lo nuevo, ya con la etiqueta de la comunidad, también llega)
        Create(p.jaime, Open(p.jaime), "Ya en comunidad")
        net:Advance(2)
        A.same({ "Antes de la comunidad", "Ya en comunidad" }, Titles(Open(p.fina)))
        -- (Fina vuelve a entrar y el juego tarda en darle la Información: el arranque rápido ya es el de la comunidad)
        net:Logout(p.fina)
        net.info = ""
        net:Login(p.fina)
        net:Advance(2)
        A.equal("VDB", p.fina.HU.myTag, "arranque rápido con la comunidad")
        A.falsy(p.fina.HU:IsSolo())
        A.same({}, net:Errors())
    end)

    it("una hermandad que quita las líneas de la comunidad sigue con sus eventos, ya como hermandad sola", function()
        local net, p = Guild(nil, COMMUNITY)
        A.equal("VDB", p.fina.HU.myTag)
        Create(p.leo, Open(p.leo), "De la comunidad")
        net:Advance(5)
        NewInfo(net, p, INFO)
        A.truthy(Until(net, function() return p.fina.HU:IsSolo() and p.leo.HU:IsSolo() end, 400), "no pasa a hermandad sola")
        net:Advance(5)
        A.same({ "De la comunidad" }, Titles(Open(p.fina)), "el evento sigue")
        -- (se avisa, una vez: puede que alguien haya borrado las líneas sin querer)
        local n = 0
        for _, l in ipairs(p.fina.w.chat) do if tostring(l.msg):find("ya no tiene las líneas de la comunidad", 1, true) then n = n + 1 end end
        A.equal(1, n, "el aviso, una vez")
        net:Logout(p.fina)
        net:Login(p.fina)
        net:Advance(120)
        n = 0
        for _, l in ipairs(p.fina.w.chat) do if tostring(l.msg):find("ya no tiene las líneas de la comunidad", 1, true) then n = n + 1 end end
        A.equal(0, n, "al volver a entrar, ya no")
        A.same({}, net:Errors())
    end)

    it("con la Información vacía, la primera vez espera a que llegue; las siguientes entra ya como hermandad sola", function()
        local net = red.New({ step = 0.5, info = "", guilds = { VB = GUILD } })
        local leo = net:Player("Leo", "VB", { rankIndex = 2 })
        net:Login(leo)
        net:Advance(10)
        A.is_nil(leo.HU.myTag, "espera a la Información: al entrar puede llegar vacía")
        net:Advance(60)
        A.truthy(leo.HU:IsSolo(), "vacía de verdad: hermandad sola")
        net:Logout(leo)
        net:Login(leo)
        net:Advance(2)
        A.truthy(leo.HU:IsSolo(), "la siguiente vez, ya")
        A.same({}, net:Errors())
    end)

    it("quien cambia de hermandad no se lleva lo de la otra", function()
        local a = addon.Load({ guild = { name = GUILD, rank = "Capitán", rankIndex = 2, members = {
            { name = "Tester-Reino", rank = "Capitán", rankIndex = 2 } } }, guildInfo = INFO }):Login(60)
        local HU = a.HU
        HU:RefreshConfig(true)
        local mine = HU.myTag
        A.truthy(HU:ProposeEvent("ab12", { t = a.env.time() + 86400, kind = "pvp", title = "Mío" }))
        -- (se va a otra hermandad sola)
        a.w.guild = { name = "Otra Hermandad", rank = "Miembro", rankIndex = 4, members = {
            { name = "Tester-Reino", rank = "Miembro", rankIndex = 4 } } }
        a.w.guildInfo = "Otra Información"
        HU:RefreshConfig(true)
        A.equal(HU.SoloTag("Otra Hermandad"), HU.myTag)
        A.is_nil(next(HU.db.wuStore[HU.myTag] and HU.db.wuStore[HU.myTag].EV or {}), "nada de la otra hermandad")
        A.truthy(next(HU.db.wuStore[mine].EV), "lo suyo se queda donde estaba")
        A.same({}, a:Errors())
    end)
end)
