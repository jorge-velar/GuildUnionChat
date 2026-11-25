-- Comercio con la red (Trade.lua y Packs/Trade.lua): el Tablón y Mis encargos llegan a todas las hermandades con el
-- conjunto TR (propuestas, WU) y siguen tras /reload; el chat de cada encargo llega a la otra persona por susurro (TC) y,
-- si no está conectada, espera a que entre. Jorge, 24/11: «mis orders no se ven entre guild», «¿los chats del my orders
-- se guardan?»
local red = require("lib.red")
local F = require("lib.fixtures")
local A = assert_

---------------------------------------------------------------------------
-- La ventana de Comercio de cada jugador (como en comercio_spec)
---------------------------------------------------------------------------
-- (¿se ve? él y todos los de encima, como IsVisible en el juego)
local function Visible(f)
    while f do
        if f._shown == false then return false end
        f = f._parent
    end
    return true
end
-- (el WoW de mentira no recuerda las casillas marcadas: aquí, sí)
local function Checks(a)
    local meta = a.w.frameMeta
    local base = meta.__index
    local extra = {
        SetChecked = function(self, v) rawset(self, "_checked", v and true or false) end,
        GetChecked = function(self) return rawget(self, "_checked") == true end,
    }
    meta.__index = function(f, k) return extra[k] or base(f, k) end
end
-- La sección Comercio a la vista, con la ventana de hermandad del juego, lo justo
local function OpenTrade(a)
    Checks(a)
    local f = a.env.CreateFrame("Frame", "CommunitiesFrame")
    f.Chat, f.GuildInfoTab, f.CommunitiesControlFrame = false, false, false
    f.ChatTab = a.env.CreateFrame("CheckButton", nil, f)
    f.RosterTab = a.env.CreateFrame("CheckButton", nil, f)
    f.CommunitiesList = a.env.CreateFrame("Frame", nil, f)
    f.MemberList = a.env.CreateFrame("Frame", nil, f)
    f.MemberList.IsVisible = function() return true end
    local chk = a.env.CreateFrame("CheckButton", nil, f.MemberList)
    f.MemberList.ShowOfflineButton = chk
    chk.IsVisible = function() return true end
    a.w:Fire("ADDON_LOADED", "Blizzard_Communities")
    local tr = a.env.GuildUnionUnionRoster.trade
    tr.IsVisible = function(self) return Visible(self) end
    tr:Show()
    a.tr = tr
    return tr
end

local function Click(b, ...) return b:GetScript("OnClick")(b, ...) end
-- (las filas de la lista que se ven; la de un objeto)
local function Rows(tr)
    local out = {}
    for _, r in ipairs(tr.req.rows) do if r:IsShown() and r.entry then out[#out + 1] = r end end
    return out
end
local function Row(tr, text)
    for _, r in ipairs(Rows(tr)) do if r.entry.item:find(text, 1, true) then return r end end
end
local function Btn(a, parent, text)
    for _, fr in ipairs(a.w.frames) do if fr._parent == parent and fr:GetText() == text then return fr end end
end
-- (pedir con «+ Nueva solicitud»: al Tablón o, con `to`, a esa persona)
local function Ask(a, item, to)
    a.tr.OpenNew(to)
    local d = a.env.GuildUnionTradeNew
    d.item:SetText(item)
    Click(Btn(a, d, "Pedir"))
end
-- (escribir en el chat del encargo que se ve)
local function Say(a, text)
    a.tr.chatInput:SetText(text)
    a.tr.chatInput:GetScript("OnEnterPressed")(a.tr.chatInput)
end
-- (la solicitud que ve un jugador, por lo que pide)
local function Req(HU, text)
    for _, r in ipairs(HU:TradeRequests()) do if r.item:find(text, 1, true) then return r end end
end
-- (los TC mandados desde i0: { de, a, texto })
local function TCs(net, i0)
    local out = {}
    for i = (i0 or 0) + 1, #net.log do
        local m = net.log[i]
        if m.text:match("^TC~") then out[#out + 1] = { m.from.name, m.target, m.text:sub(4), m.dist } end
    end
    return out
end

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

-- UNO: Ana (oficial) y Alba; DOS: Bea (oficial) y Blas; TRES: Tere (oficial)
local function Union()
    local net = red.New({ step = 0.5, info = table.concat({ F.INFO, "GU:g:Hermandad Tres:TRES" }, "\n"),
        guilds = { UNO = "Hermandad Uno", DOS = "Hermandad Dos", TRES = "Hermandad Tres" } })
    local p = {
        ana = net:Player("Ana", "UNO", { rankIndex = 1 }),
        alba = net:Player("Alba", "UNO"),
        bea = net:Player("Bea", "DOS", { rankIndex = 1 }),
        blas = net:Player("Blas", "DOS"),
        tere = net:Player("Tere", "TRES", { rankIndex = 1 }),
    }
    for _, n in ipairs({ "ana", "alba", "bea", "blas", "tere" }) do net:Login(p[n]) end
    net:Advance(150)
    return net, p
end

local LINO = "|cffffffff|Hitem:2589::::::::60:::::::|h[Paño de lino]|h|r"

describe("Comercio con la red: tres hermandades", function()
    it("el Tablón llega a todas; Bea (DOS) acepta, escribe y la marca hecha, y Ana (UNO) lo ve; una privada solo la ven los dos; tras /reload, todo sigue", function()
        local net, p = Union()
        local ana, bea, blas, tere = p.ana, p.bea, p.blas, p.tere
        for _, q in ipairs({ ana, bea, blas, tere }) do OpenTrade(q.a) end
        -- (Ana pide algo al Tablón: en el suyo, ya)
        Ask(ana.a, LINO)
        A.truthy(Row(ana.a.tr, "Paño de lino"), "en el Tablón de Ana")
        -- (Bea, de DOS, y Tere, de TRES, lo ven en el suyo)
        A.truthy(Until(net, function() return Row(bea.a.tr, "Paño de lino") ~= nil end, 400), "no llega a DOS")
        A.truthy(Until(net, function() return Row(tere.a.tr, "Paño de lino") ~= nil end, 400), "no llega a TRES")
        local row = Row(bea.a.tr, "Paño de lino")
        A.equal("Ana-Reino", row.entry.who)
        A.equal("UNO", row.entry.tag)
        -- (Bea la acepta: en su Tablón, ya con su nombre; Ana la ve aceptada por Bea)
        A.truthy(row.accept:IsShown())
        Click(row.accept)
        A.equal("taken", Row(bea.a.tr, "Paño de lino").entry.state)
        A.truthy(Until(net, function()
            local r = Row(ana.a.tr, "Paño de lino")
            return r ~= nil and r.entry.state == "taken"
        end, 400), "Ana no la ve aceptada")
        A.equal("Bea-Reino", Row(ana.a.tr, "Paño de lino").entry.taker)
        -- (Bea escribe en el chat del encargo, en Mis encargos: a Ana le llega por susurro, sin leer)
        local i0 = #net.log
        Click(bea.a.tr.viewBtns.priv)
        Click(Row(bea.a.tr, "Paño de lino"), "LeftButton")
        Say(bea.a, "Te lo hago esta noche")
        A.truthy(Until(net, function() return ana.HU:TradeUnread() == 1 end, 30), "no le llega la línea")
        A.same({ { "Bea", "Ana-Reino", "Te lo hago esta noche", "WHISPER" } }, TCs(net, i0))
        A.matches("Te lo hago esta noche", ana.HU.db.tradeChats["Bea-Reino"][1])
        -- (Bea la marca hecha; Ana lo ve en Mis encargos)
        A.truthy(bea.a.tr.doneBtn:IsShown())
        Click(bea.a.tr.doneBtn)
        A.equal("done", Row(bea.a.tr, "Paño de lino").entry.state)
        Click(ana.a.tr.viewBtns.priv)
        A.truthy(Until(net, function()
            local r = Row(ana.a.tr, "Paño de lino")
            return r ~= nil and r.entry.state == "done"
        end, 400), "Ana no la ve hecha")
        -- (una privada de Ana para Blas, de DOS: solo la ven ellos. Bea y Alba tienen sus datos, pero no la ven)
        Ask(ana.a, "Escudo a medida", "Blas-Reino")
        A.truthy(Req(ana.HU, "Escudo a medida"))
        A.truthy(Until(net, function() return Req(blas.HU, "Escudo a medida") ~= nil end, 400), "no le llega a Blas")
        local function HasLine(HU, tag)
            for _, l in ipairs((HU:PackLines(tag, "TR"))) do if l:find("Escudo a medida", 1, true) then return true end end
            return false
        end
        A.truthy(Until(net, function() return HasLine(bea.HU, "UNO") end, 400), "Bea no tiene los datos")
        A.truthy(HasLine(p.alba.HU, "UNO"), "Alba, de UNO, los tiene en su almacén")
        A.is_nil(Req(bea.HU, "Escudo a medida"), "Bea no la ve")
        A.is_nil(Req(p.alba.HU, "Escudo a medida"), "Alba tampoco")
        A.is_nil(Req(tere.HU, "Escudo a medida"), "ni Tere")
        -- (a Blas, como no la tiene en pantalla, le cuenta como sin leer, con su aviso en el chat con Ana)
        A.truthy(Until(net, function() return blas.HU:TradeUnread() == 1 end, 10))
        A.matches("Escudo a medida", blas.HU.db.tradeChats["Ana-Reino"][1])
        Click(blas.a.tr.viewBtns.priv)
        A.truthy(Row(blas.a.tr, "Escudo a medida"), "en Mis encargos de Blas")
        -- (tras /reload, todo sigue: solicitudes, estados, chats y lo sin leer)
        for _, q in ipairs({ ana, bea, blas }) do net:Logout(q); net:Login(q) end
        net:Advance(30)
        for _, q in ipairs({ ana, bea, blas }) do OpenTrade(q.a); Click(q.a.tr.viewBtns.priv) end
        local mine = Row(ana.a.tr, "Paño de lino")
        A.truthy(mine, "la de Ana, tras /reload")
        A.same({ "done", "Bea-Reino" }, { mine.entry.state, mine.entry.taker })
        A.truthy(Row(ana.a.tr, "Escudo a medida"), "y su privada")
        A.equal(1, ana.HU:TradeUnread(), "la línea de Bea, sin leer")
        A.same({ "done", "Bea-Reino" }, { Row(bea.a.tr, "Paño de lino").entry.state, Row(bea.a.tr, "Paño de lino").entry.taker })
        A.truthy(Row(blas.a.tr, "Escudo a medida"), "la privada, en Mis encargos de Blas")
        A.equal(1, blas.HU:TradeUnread())
        A.same({}, net:Errors())
    end)

    it("lo escrito a quien no está conectado espera, también tras /reload, y le llega al entrar", function()
        local net, p = Union()
        local ana, alba = p.ana, p.alba
        OpenTrade(ana.a)
        Ask(ana.a, "Botas de prueba", "Alba-Reino")
        net:Advance(3)
        A.truthy(Req(alba.HU, "Botas de prueba"), "de mi hermandad, le llega ya por GUILD")
        Click(ana.a.tr.viewBtns.priv)
        Click(Row(ana.a.tr, "Botas de prueba"), "LeftButton")
        -- (Alba se va. Al momento, la lista de mi hermandad aún dice que está: se manda, el juego dice que no estaba y vuelve
        -- a esperar)
        net:Logout(alba)
        local i0 = #net.log
        Say(ana.a, "uno")
        net:Advance(1)
        A.equal("uno", ana.HU.db.tradePending["Alba-Reino"][1].m, "no estaba: espera")
        -- (cuando la lista ya dice que no está, ni se prueba)
        A.truthy(Until(net, function()
            for _, e in ipairs(ana.HU.rosterList) do if e.name == "Alba-Reino" then return e.online == false end end
        end, 120), "la lista no se pone al día")
        Say(ana.a, "dos")
        net:Advance(1)
        A.same({ "uno", "dos" }, { ana.HU.db.tradePending["Alba-Reino"][1].m, ana.HU.db.tradePending["Alba-Reino"][2].m })
        A.same({}, TCs(net, i0), "no le ha llegado nada")
        -- (tras /reload, sigue esperando; al entrar Alba, le llega todo, en orden)
        net:Logout(ana); net:Login(ana)
        net:Advance(40)
        A.equal(2, #ana.HU.db.tradePending["Alba-Reino"], "tras /reload, sigue esperando")
        net:Login(alba)
        A.truthy(Until(net, function() return #TCs(net, i0) == 2 end, 120), "no se le manda al entrar")
        net:Advance(2)
        A.is_nil(ana.HU.db.tradePending["Alba-Reino"])
        local chat = alba.HU.db.tradeChats["Ana-Reino"]
        A.same({ "uno", "dos" }, { chat[#chat - 1]:match(": (.*)$"), chat[#chat]:match(": (.*)$") })
        A.same({}, net:Errors())
    end)
end)

---------------------------------------------------------------------------
-- Sin red: lo que hay dentro de una propuesta TR y cómo sale el estado de cada solicitud
---------------------------------------------------------------------------
-- (una línea de TR de un compañero de mi hermandad, como llega por GUILD)
local function WU(a, from, key, data, t)
    a.w:Receive("HU20B", "WU~UNO~TR~" .. key .. "~" .. (t or a.HU.StampNow()) .. "~" .. data, "GUILD", from)
end
-- (un número como los de NewId: la huella de quien la pide delante)
local function Id(HU, who, n) return HU.Hash(who):sub(1, 4) .. string.format("%012d", n) end

describe("Comercio con la red: el paquete TR (Packs/Trade.lua)", function()
    it("los datos de una solicitud: estado, cantidad, materiales, propina, pública, para quién y lo que pide", function()
        local HU = F.Community().HU
        A.equal("o,2,1,15000,1,-,i2589:Paño de lino", HU.TradeOrderData({ qty = 2, mats = true, tip = 15000, pub = true, item = LINO }))
        A.equal("o,1,0,-,0,Bea-Reino,t:Cosa rara", HU.TradeOrderData({ pub = false, to = "Bea-Reino", item = "Cosa rara" }))
        A.equal("g,999,0,0,0,Bea-Reino,s7418:Encantar 7418", HU.TradeOrderData({ state = "gone", qty = 5000, tip = 0, to = "Bea-Reino",
            item = "|cff71d5ff|Henchant:7418|h[Encantar 7418]|h|r" }))
        A.equal("o,1,0,-,1,-,s7418:Encantar", HU.TradeOrderData({ pub = true, item = "|cff71d5ff|Hspell:7418:0|h[Encantar]|h|r" }))
        A.equal("o,1,0,-,1,-,t:abcd", HU.TradeOrderData({ pub = true, item = "a~b;c|d\n" }), "sin lo que no puede viajar")
        local long = HU.TradeOrderData({ pub = true, item = string.rep("é", 120) })
        A.truthy(#long <= 180 and not long:find("[\195]$"), "cabe y no parte letras: " .. #long)
        -- (y la línea del paquete, con mi nombre, la clave y la hora, cabe en los 200 de Net/Packs.lua: si no, no se publica)
        local lid = Id(HU, "Tester-Reino", 9)
        A.truthy(HU:TradeOrder({ id = lid, who = HU:Me(), pub = true, item = string.rep("é", 150) }))
        local m = HU.PackRefresh("TR")
        A.truthy(m and m.lineOf["tester-reino,o" .. lid], "sale para las otras hermandades")
        A.truthy(#m.lineOf["tester-reino,o" .. lid] <= 200)
        -- (lo que no tiene su forma no se propone)
        for _, bad in ipairs({ "o,0,1,-,1,-,t:x", "o,1,2,-,1,-,t:x", "o,1,1,abc,1,-,t:x", "o,1,1,-,1,Bea-Reino,t:x",
            "o,1,1,-,0,-,t:x", "x,1,1,-,1,-,t:x", "o,1,1,-,1,-,z:x", "o,1,1,-,1,-,t:", "o,1000,1,-,1,-,t:x" }) do
            A.falsy(HU:Propose("TR", "o12", bad), bad)
        end
        A.falsy(HU:Propose("TR", "a12", "z"), "respuesta que no existe")
        A.falsy(HU:Propose("TR", "q12", "t"), "clave que no es o ni a")
        A.falsy(HU:Propose("TR", "o" .. string.rep("1", 21), "o,1,1,-,1,-,t:x"), "número de más de 20")
        A.truthy(HU:Propose("TR", "a12", "t"))
        A.equal(30 * 86400, HU.packSets.TR.keep, "30 días")
    end)

    it("el estado: aceptada por la más antigua, hecha, rechazada (solo por para quien es), cancelada; las privadas de otros, no se ven", function()
        local a = F.Community()
        local HU = a.HU
        local t = HU.StampNow()
        -- (Compi pide algo al Tablón y Jefa y yo lo aceptamos: gana Jefa, que fue antes; lo que dice Compi de la suya, no cuenta)
        local id = Id(HU, "Compi-Reino", 1)
        WU(a, "Compi-Reino", "o" .. id, "o,3,1,500,1,-,i2589:Paño de lino", t - 50)
        A.equal("open", Req(HU, "Paño de lino").state)
        A.equal("Compi-Reino", Req(HU, "Paño de lino").who)
        A.same({ 3, true, 500, true }, { Req(HU, "Paño").qty, Req(HU, "Paño").mats, Req(HU, "Paño").tip, Req(HU, "Paño").pub })
        A.matches("|Hitem:2589:", Req(HU, "Paño").item)
        WU(a, "Compi-Reino", "a" .. id, "t", t - 40)
        A.equal("open", Req(HU, "Paño").state, "quien la pide no se la acepta")
        HU:TradeAnswer(id, "t")
        WU(a, "Jefa-Reino", "a" .. id, "t", t - 30)
        A.same({ "taken", "Jefa-Reino", t - 30 }, { Req(HU, "Paño").state, Req(HU, "Paño").taker, Req(HU, "Paño").takenAt })
        WU(a, "Jefa-Reino", "a" .. id, "d", t - 20)
        A.same({ "done", "Jefa-Reino" }, { Req(HU, "Paño").state, Req(HU, "Paño").taker })
        -- (con el enlace del juego, si lo tiene)
        a.env.C_Item = { GetItemInfo = function(n) return "Linen Cloth", "|cffffffff|Hitem:" .. n .. "::::::::60:::::::|h[Linen Cloth]|h|r" end }
        A.matches("Linen Cloth", Req(HU, "Linen").item)
        -- (una privada de Compi para mí: la de Jefa no cuenta; mi «r» la rechaza)
        local id2 = Id(HU, "Compi-Reino", 2)
        WU(a, "Compi-Reino", "o" .. id2, "o,1,0,-,0,Tester-Reino,t:Botas raras", t - 10)
        A.equal("open", Req(HU, "Botas raras").state)
        WU(a, "Jefa-Reino", "a" .. id2, "t", t - 9)
        A.equal("open", Req(HU, "Botas raras").state, "solo para quien es")
        HU:TradeAnswer(id2, "r")
        A.equal("gone", Req(HU, "Botas raras").state, "rechazada")
        -- (una de Compi para Jefa: no la veo)
        WU(a, "Compi-Reino", "o" .. Id(HU, "Compi-Reino", 3), "o,1,0,-,0,Jefa-Reino,t:Secreto", t - 8)
        A.truthy(HU:PackLines("UNO", "TR")[1], "la tengo guardada")
        A.is_nil(Req(HU, "Secreto"), "pero no la veo")
        -- (Compi cancela la suya)
        WU(a, "Compi-Reino", "o" .. id, "g,3,1,500,1,-,i2589:Paño de lino", t - 5)
        A.equal("gone", Req(HU, "Linen").state)
        -- (otra con el mismo número, de otro: vale la de quien sale en él)
        WU(a, "Jefa-Reino", "o" .. id, "o,1,1,-,1,-,t:Falsa", t - 60)
        A.equal("Compi-Reino", Req(HU, "Linen").who)
        A.is_nil(Req(HU, "Falsa"))
        -- (un encantamiento: su enlace de hechizo, el del juego si lo tiene)
        WU(a, "Jefa-Reino", "o" .. Id(HU, "Jefa-Reino", 4), "o,1,0,-,1,-,s7418:Encantar brazales", t - 4)
        A.equal("|cff71d5ff|Hspell:7418|h[Encantar brazales]|h|r", Req(HU, "Encantar brazales").item)
        a.env.C_Spell = { GetSpellLink = function(n) return "|cff71d5ff|Hspell:" .. n .. ":0|h[Enchant Bracer]|h|r" end }
        A.matches("Enchant Bracer", Req(HU, "Enchant Bracer").item)
        -- (el mismo número, que no es de ninguno de los dos: la más antigua. Cada uno ya ha mandado 5 seguidas: se espera)
        a.w:Advance(13)
        WU(a, "Compi-Reino", "o12345", "o,1,0,-,1,-,t:Nueva", t - 3)
        WU(a, "Jefa-Reino", "o12345", "o,1,0,-,1,-,t:Vieja", t - 70)
        A.truthy(Req(HU, "Vieja"))
        A.is_nil(Req(HU, "Nueva"))
        A.same({}, a:Errors())
    end)

    it("sin la unión no se puede pedir, y se dice", function()
        local a = F.Community()
        local HU = a.HU
        local tr = OpenTrade(a)
        HU.myTag = nil
        local n0 = #a.w.chat
        Ask(a, "Algo")
        A.matches("todavía no está en la unión", tostring(a.w.chat[n0 + 1] and a.w.chat[n0 + 1].msg))
        A.truthy(a.env.GuildUnionTradeNew:IsShown(), "la ventana sigue abierta")
        A.equal(0, #Rows(tr))
        A.same({}, a:Errors())
    end)

    it("lo guardado viejo o roto se quita al salir: lo quitado y lo avisado de hace más de un mes, lo que espera de prueba o viejo", function()
        local a = F.Community()
        local HU = a.HU
        local now, old = a.env.time(), a.env.time() - 31 * 86400
        HU.db.tradeClosed.nuevo, HU.db.tradeClosed.viejo, HU.db.tradeClosed.roto = now, old, "x"
        HU.db.tradeSeen.nuevo, HU.db.tradeSeen.viejo = now, old
        HU.db.tradePending["Bea-Reino"] = { { m = "vieja", t = old }, { m = "buena", t = now }, "rota" }
        HU.db.tradePending["Pepe-Prueba"] = { { m = "de prueba", t = now } }
        HU.db.tradePending["Lyra-Reino"] = { { m = "vieja", t = old } }
        HU.db.tradePending["Raro-Reino"] = "no es una lista"
        a.w:Fire("PLAYER_LOGOUT")
        A.same({ nuevo = now }, HU.db.tradeClosed)
        A.same({ nuevo = now }, HU.db.tradeSeen)
        A.same({ ["Bea-Reino"] = { { m = "buena", t = now } } }, HU.db.tradePending)
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
-- Sin red: la ventana con las de la red
---------------------------------------------------------------------------
describe("Comercio con la red: la ventana", function()
    it("aceptar, rechazar, cancelar, eliminar (y soltar la que hago) y «Hecha» pasan por las propuestas; lo quitado de mi lista se guarda", function()
        local a = F.Community()
        local HU = a.HU
        local tr = OpenTrade(a)
        local t = HU.StampNow()
        local pub, priv = Id(HU, "Compi-Reino", 1), Id(HU, "Compi-Reino", 2)
        WU(a, "Compi-Reino", "o" .. pub, "o,1,1,-,1,-,t:Capa verde", t)
        WU(a, "Compi-Reino", "o" .. priv, "o,2,0,-,0,Tester-Reino,t:Guantes", t)
        a.w:Advance(2)
        -- (el Tablón se pinta solo al llegar; la privada para mí, en Mis encargos y con su aviso sin leer)
        A.truthy(Row(tr, "Capa verde"), "en el Tablón, sin tocar nada")
        A.equal(1, HU:TradeUnread())
        A.matches("Guantes.* x2", HU.db.tradeChats["Compi-Reino"][1])
        A.truthy(HU.db.tradeSeen[priv], "avisada una vez")
        -- (acepto la del Tablón: mi respuesta, en mis propuestas)
        Click(Row(tr, "Capa verde").accept)
        A.same({ "taken", "Tester-Reino" }, { Row(tr, "Capa verde").entry.state, Row(tr, "Capa verde").entry.taker })
        A.equal("t", HU.db.wuStore.UNO.TR["tester-reino,a" .. pub].d)
        -- (en Mis encargos: «Hecha»; y su chat, el de Compi, en pantalla: el aviso, leído)
        Click(tr.viewBtns.priv)
        Click(Row(tr, "Capa verde"), "LeftButton")
        A.truthy(tr.doneBtn:IsShown() and tr.doneBtn:IsEnabled())
        A.equal(0, HU:TradeUnread())
        -- (la privada: la X la rechaza)
        Click(Row(tr, "Guantes").no)
        A.is_nil(Row(tr, "Guantes"), "rechazada, fuera")
        A.equal("r", HU.db.wuStore.UNO.TR["tester-reino,a" .. priv].d)
        -- (eliminar la que hago sin hacer: fuera de mi lista, guardado, y la suelto: vuelve a estar abierta)
        local m = {}
        a.env.MenuUtil = { CreateContextMenu = function(_, gen)
            gen(nil, { CreateTitle = function() end, CreateButton = function(_, text, fn) m[text] = fn end })
        end }
        Click(Row(tr, "Capa verde"), "RightButton")
        m["Eliminar"]()
        A.is_nil(Row(tr, "Capa verde"))
        A.truthy(HU.db.tradeClosed[pub])
        A.equal("", HU.db.wuStore.UNO.TR["tester-reino,a" .. pub].d, "la suelto")
        Click(tr.viewBtns.pub)
        A.equal("open", Row(tr, "Capa verde").entry.state, "abierta otra vez para los demás")
        -- (una mía: Cancelar en el Tablón la cancela para todos)
        Ask(a, "Yelmo azul")
        A.truthy(Row(tr, "Yelmo azul").cancel:IsShown())
        Click(Row(tr, "Yelmo azul").cancel)
        A.is_nil(Row(tr, "Yelmo azul"))
        local mine
        for k, e in pairs(HU.db.wuStore.UNO.TR) do if k:find("^tester%-reino,o") and e.d:find("Yelmo", 1, true) then mine = e end end
        A.matches("^g,", mine.d, "cancelada, con su estado")
        -- (una mía sin aceptar, eliminada de Mis encargos: también se cancela)
        Ask(a, "Peto", "Compi-Reino")
        Click(Row(tr, "Peto"), "RightButton")
        m["Eliminar"]()
        A.equal("gone", Req(HU, "Peto").state)
        A.is_nil(Row(tr, "Peto"))
        -- (lo quitado de mi lista sigue quitado tras /reload, y el aviso no se repite)
        a.w:Fire("PLAYER_LOGOUT")
        local b = F.Community({ db = a.env.GuildUnionDB })
        local tr2 = OpenTrade(b)
        Click(tr2.viewBtns.pub)
        A.truthy(Row(tr2, "Capa verde"), "en el Tablón sigue")
        Click(tr2.viewBtns.priv)
        A.is_nil(Row(tr2, "Capa verde"), "pero no en mi lista")
        A.equal(0, b.HU:TradeUnread())
        A.equal(1, #b.HU.db.tradeChats["Compi-Reino"])
        A.same({}, a:Errors())
        A.same({}, b:Errors())
    end)

    it("una línea del chat que llega antes que su solicitud espera; sin solicitud entre los dos, se tira; por GUILD, nada", function()
        local a = F.Community()
        local HU = a.HU
        OpenTrade(a)
        a.w:Receive("HU20", "TC~hola, ¿me la haces?", "WHISPER", "Compi-Reino")
        a.w:Receive("HU20", "TC~por GUILD no", "GUILD", "Compi-Reino")
        a.w:Receive("HU20", "TC~   ", "WHISPER", "Compi-Reino")
        A.is_nil(HU.db.tradeChats["Compi-Reino"], "sin solicitud: espera")
        -- (llega su solicitud: ya está en su chat, detrás del aviso)
        WU(a, "Compi-Reino", "o" .. Id(HU, "Compi-Reino", 7), "o,1,0,-,0,Tester-Reino,t:Anillo", HU.StampNow())
        a.w:Advance(2)
        local chat = HU.db.tradeChats["Compi-Reino"]
        A.equal(2, #chat)
        A.matches("Anillo", chat[1])
        A.matches("Compi%-Reino|r: hola, ¿me la haces%?", chat[2])
        A.equal(2, HU:TradeUnread())
        -- (de quien no tiene nada conmigo: a los 10 min, fuera)
        a.w:Receive("HU20", "TC~spam", "WHISPER", "Jefa-Reino")
        a.w:Advance(620)
        WU(a, "Jefa-Reino", "o" .. Id(HU, "Jefa-Reino", 1), "o,1,0,-,0,Tester-Reino,t:Tarde", HU.StampNow())
        a.w:Advance(40)
        A.equal(1, #HU.db.tradeChats["Jefa-Reino"], "solo el aviso de su solicitud")
        A.same({}, a:Errors())
    end)

    it("si el juego dice que no estaba, lo mandado vuelve a esperar; si no se sabe si está, se vuelve a probar a los 5 min", function()
        local a = F.Community()
        local HU = a.HU
        local tr = OpenTrade(a)
        local function Sent()
            local out = {}
            for _, m in ipairs(a.w.sent) do if m.text:match("^TC~") then out[#out + 1] = m.target .. ":" .. m.text:sub(4) end end
            return out
        end
        -- (Bea, de otra hermandad: no se sabe si está conectada, así que se prueba)
        Ask(a, "Cinturón", "Bea-Reino")
        Click(Row(tr, "Cinturón"), "LeftButton")
        Say(a, "uno")
        A.same({ "Bea-Reino:uno" }, Sent())
        A.is_nil(HU.db.tradePending["Bea-Reino"])
        -- (el juego avisa de que no está: vuelve a esperar; lo siguiente, también, hasta que se pruebe otra vez)
        HU:ForgetOffline("Bea-Reino")
        A.equal("uno", HU.db.tradePending["Bea-Reino"][1].m)
        Say(a, "dos")
        A.equal(2, #HU.db.tradePending["Bea-Reino"])
        A.equal(1, #Sent())
        a.w:Advance(340)
        A.same({ "Bea-Reino:uno", "Bea-Reino:uno", "Bea-Reino:dos" }, Sent(), "otra vez, en orden")
        A.is_nil(HU.db.tradePending["Bea-Reino"])
        -- (un aviso del juego de mucho después no devuelve nada)
        a.w:Advance(60)
        HU:ForgetOffline("Bea-Reino")
        A.is_nil(HU.db.tradePending["Bea-Reino"])
        -- (si me escribe, está conectada: lo que le esperaba sale ya)
        Say(a, "tres")
        HU:ForgetOffline("Bea-Reino")
        A.equal(1, #HU.db.tradePending["Bea-Reino"])
        a.w:Receive("HU20", "TC~ya estoy", "WHISPER", "Bea-Reino")
        A.is_nil(HU.db.tradePending["Bea-Reino"])
        A.equal("Bea-Reino:tres", Sent()[#Sent()])
        A.same({}, a:Errors())
    end)

    it("lo de la copia 324 (mis solicitudes en el personaje) se propone una vez y la lista se vacía; los chats se quedan", function()
        local key
        for k in pairs(F.Community().HU.adb.chars) do key = k end
        local old = {
            { id = "abcd0123456789ef", who = "Tester-Reino", item = LINO, qty = 2, mats = true, tip = 15000, state = "open", pub = true, t = 1 },
            { id = "abcd0123456789aa", who = "Tester-Reino", item = "Cosa vieja", qty = 1, state = "gone", pub = false, to = "Bea-Reino", t = 1 },
            { id = "abcd0123456789bb", who = "Lyra-Prueba", item = "De prueba", state = "open", pub = true, test = true, t = 1 },
            { id = "mal id!", who = "Tester-Reino", item = "Rara", state = "open", pub = true, t = 1 },
        }
        local a = F.Community({ db = { chars = { [key] = { tradeReqs = old, tradeChats = { ["Bea-Reino"] = { "hola" } },
            tradeUnread = { ["Bea-Reino"] = 1 } } } } })
        local HU = a.HU
        A.equal(0, #HU.db.tradeReqs, "vacía")
        local list = HU:TradeRequests()
        A.equal(1, #list, "solo la abierta, que es mía")
        A.same({ "abcd0123456789ef", 2, true, 15000, true, "open" }, { list[1].id, list[1].qty, list[1].mats, list[1].tip, list[1].pub, list[1].state })
        A.matches("Paño de lino", list[1].item)
        A.equal(1, HU:TradeUnread(), "lo sin leer se queda")
        A.same({ "hola" }, HU.db.tradeChats["Bea-Reino"])
        -- (una vez: otra lectura de la Información no la repite)
        local n0 = #a.w.sent
        HU:RefreshConfig(true)
        for i = n0 + 1, #a.w.sent do A.falsy(a.w.sent[i].text:find("^WU~UNO~TR~"), a.w.sent[i].text) end
        A.same({}, a:Errors())
    end)
end)
