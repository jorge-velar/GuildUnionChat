-- Oficios (OF, Packs/Professions.lua): las profesiones, su nivel y las recetas de cada uno, en toda la unión. Cada uno
-- manda lo suyo como propuesta (WU) al abrir la ventana de una profesión, al subir de nivel y al entrar; las otras
-- hermandades lo reciben con el paquete de su enlace. «Quién lo hace» (Trade.lua) y la ficha (UnionRoster.lua) lo
-- enseñan, también de los desconectados. Jorge, 24/11: «al menos tener un registro de cada uno»
local red = require("lib.red")
local F = require("lib.fixtures")
local A = assert_

---------------------------------------------------------------------------
-- El WoW de mentira, con lo que aquí hace falta
---------------------------------------------------------------------------
-- Mis profesiones en el juego, { [número] = nivel } (como en comercio_spec)
local function Professions(a, list)
    local idx = {}
    for skill, rank in pairs(list) do idx[#idx + 1] = { skill = skill, rank = rank } end
    table.sort(idx, function(x, y) return x.skill < y.skill end)
    a.env.GetProfessions = function()
        return idx[1] and 1 or nil, idx[2] and 2 or nil, idx[3] and 3 or nil, nil, idx[4] and 4 or nil
    end
    a.env.GetProfessionInfo = function(i)
        local p = idx[i]
        if p then return "Profesión " .. p.skill, "icono", p.rank, 300, 2, 0, p.skill, 0, 0, 0, "Profesión" end
    end
end

-- La ventana de una profesión mía, abierta y con la lista entera: made = { [receta] = objeto que crea }, todas aprendidas
local function Window(a, skill, made)
    local ids = {}
    for id in pairs(made) do ids[#ids + 1] = id end
    table.sort(ids)
    a.env.C_TradeSkillUI = {
        IsTradeSkillReady = function() return true end,
        GetChildProfessionInfo = function() return { professionID = skill } end,
        GetAllRecipeIDs = function() return ids end,
        GetRecipeInfo = function(id) return { recipeID = id, learned = true } end,
        GetRecipeSchematic = function(id) return { recipeID = id, outputItemID = made[id] } end,
        GetTradeSkillDisplayName = function(id) return id == 164 and "Herrería" or nil end,
    }
    a.w:Fire("TRADE_SKILL_SHOW")
end

-- Los nombres de los objetos, como los da el juego (los demás, «Objeto n»)
local function ItemLink(id, name) return "|cffffffff|Hitem:" .. id .. "::::::::60:::::::|h[" .. name .. "]|h|r" end
local function Names(a, names)
    a.env.C_Item.GetItemInfo = function(id)
        if type(id) ~= "number" then return nil end
        local name = names[id] or ("Objeto " .. id)
        return name, ItemLink(id, name)
    end
end

-- La sección Comercio a la vista (como en encargos_spec)
local function Visible(f)
    while f do
        if f._shown == false then return false end
        f = f._parent
    end
    return true
end
local function GuildWindow(a)
    local meta = a.w.frameMeta
    local base = meta.__index
    local extra = {
        SetChecked = function(self, v) rawset(self, "_checked", v and true or false) end,
        GetChecked = function(self) return rawget(self, "_checked") == true end,
    }
    meta.__index = function(f, k) return extra[k] or base(f, k) end
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
    return f
end
local function OpenTrade(a)
    GuildWindow(a)
    local tr = a.env.GuildUnionUnionRoster.trade
    tr.IsVisible = function(self) return Visible(self) end
    tr:Show()
    a.tr = tr
    return tr
end
local function Search(tr, text)
    tr.search:SetText(text)
    tr.search:GetScript("OnTextChanged")(tr.search)
end
-- (lo que enseña «Quién lo hace»: «Nombre ETIQ nivel», con ✓ si sabe la receta)
local function Found(tr)
    local out = {}
    for _, r in ipairs(tr.found.rows) do
        if r:IsShown() and r.entry then
            out[#out + 1] = r.entry.name:match("^([^-]+)") .. " " .. r.entry.tag .. " " .. (r.cells[4]:GetText():gsub(" |T.-|t", " ✓"))
        end
    end
    return out
end

-- Las líneas de OF que ve un jugador, «Nombre:profesión:datos», ordenadas (de `who`, si se da)
local function Lines(p, who)
    local out = {}
    for _, e in ipairs(p.HU:Proposals("OF")) do
        local n = e.n:match("^([^-]+)")
        if not who or n == who then out[#out + 1] = n .. ":" .. e.k .. ":" .. e.d end
    end
    table.sort(out)
    return out
end
-- Los WU de OF que ha mandado alguien desde i0: «profesión=datos»
local function Sent(net, who, i0)
    local out = {}
    for i = (i0 or 0) + 1, #net.log do
        local m = net.log[i]
        local k, d = m.text:match("^WU~%u+~OF~(%w+)~%d+~(.*)$")
        if k and m.from.name == who then out[#out + 1] = k .. "=" .. d end
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

-- UNO: Ana y Alba; DOS: Bea (oficial) y Blas; TRES: Tere (oficial). `lead`: quién es la oficial de UNO (el enlace)
local function Union(lead)
    local net = red.New({ step = 0.5, info = table.concat({ F.INFO, "GU:g:Hermandad Tres:TRES" }, "\n"),
        guilds = { UNO = "Hermandad Uno", DOS = "Hermandad Dos", TRES = "Hermandad Tres" } })
    lead = lead or "Ana"
    local p = {
        ana = net:Player("Ana", "UNO", { rankIndex = lead == "Ana" and 1 or 4 }),
        alba = net:Player("Alba", "UNO", { rankIndex = lead == "Alba" and 1 or 4 }),
        bea = net:Player("Bea", "DOS", { rankIndex = 1 }),
        blas = net:Player("Blas", "DOS"),
        tere = net:Player("Tere", "TRES", { rankIndex = 1 }),
    }
    for _, n in ipairs({ "ana", "alba", "bea", "blas", "tere" }) do net:Login(p[n]) end
    net:Advance(150)
    return net, p
end

---------------------------------------------------------------------------
-- Las listas y las recetas en letras
---------------------------------------------------------------------------
describe("Oficios (OF): las listas y las recetas en letras", function()
    it("cada profesión, su lista en orden de nivel (los objetos antes que los encantamientos); Encantamiento, 219; ninguna pasa de 86 letras", function()
        local HU = F.Community().HU
        local T = HU.ProfessionsForTests
        local l = T.list(333)
        A.equal(219, l.n, "54 objetos y 165 encantamientos")
        A.equal((#HU.CRAFT_ITEMS[333] + #HU.CRAFT_SPELLS[333]) / 2, l.n)
        for i = 2, l.n do
            local x, y = l[i - 1], l[i]
            A.truthy(x.lv < y.lv or (x.lv == y.lv and (not x.spell or y.spell)), "en orden: " .. i)
        end
        -- (la clave de cada cosa, la de Trade.lua: el objeto o "s" .. hechizo)
        local last = l[l.n]
        A.equal(l.n, l.pos[last.spell and ("s" .. last.id) or last.id])
        local most = 0
        for skill in pairs(HU.CRAFT_ITEMS) do most = math.max(most, T.list(skill).chars) end
        A.equal(86, most, "la más larga, Peletería: 511")
        A.equal(0, T.list(182).n, "Herboristería no fabrica nada")
    end)

    it("las recetas: un bit por cosa, 6 por letra y sin los ceros del final; saber una es mirar una letra", function()
        local T = F.Community().HU.ProfessionsForTests
        local l = T.list(333)
        local function Rec(pos)
            local rec = { items = {}, spells = {} }
            for _, i in ipairs(pos) do
                local e = l[i]
                if e.spell then rec.spells[e.id] = true else rec.items[e.id] = true end
            end
            return rec
        end
        A.equal("", T.encode(l, Rec({})), "ninguna: nada")
        A.equal("B", T.encode(l, Rec({ 1 })))
        A.equal("/", T.encode(l, Rec({ 1, 2, 3, 4, 5, 6 })))
        A.equal("AB", T.encode(l, Rec({ 7 })), "los ceros de delante sí van")
        local want = { 1, 6, 7, 100, l.n }
        local bits = T.encode(l, Rec(want))
        A.equal(l.chars, #bits, "con la última, todas las letras")
        local set = {}
        for _, i in ipairs(want) do set[i] = true end
        for i = 1, l.n do A.equal(set[i] == true, T.known(bits, i), "cosa " .. i) end
        A.falsy(T.known("", 1))
        A.falsy(T.known("B", 7), "más allá de las letras, no")
    end)

    it("la huella de la lista: 3 letras, igual en otro PC con la misma lista y distinta si cambia el orden", function()
        local h = F.Community().HU.ProfessionsForTests.list(164).hash
        A.truthy(h:match("^%w%w%w$"), h)
        A.equal(h, F.Community().HU.ProfessionsForTests.list(164).hash)
        -- (otra versión del addon: las dos primeras de Herrería, con el nivel cambiado)
        local HU = F.Community().HU
        local list = HU.CRAFT_ITEMS[164]
        list[2], list[4] = list[4], list[2]
        A.truthy(HU.ProfessionsForTests.list(164).hash ~= h)
    end)
end)

---------------------------------------------------------------------------
-- Qué se acepta
---------------------------------------------------------------------------
describe("Oficios (OF): qué se acepta", function()
    it("profesión conocida, nivel de 1 a 450, huella de 3 letras y recetas con su alfabeto y su largo; lo raro ni se propone", function()
        local HU = F.Community().HU
        local T = HU.ProfessionsForTests
        local l = T.list(164)
        local other = l.hash == "zzz" and "yyy" or "zzz"
        local function ok(k, d) return T.parse(k, d) ~= nil end
        A.truthy(ok("164", "300"))
        A.truthy(ok("164", "300," .. l.hash .. "," .. string.rep("/", l.chars)))
        A.truthy(ok("164", "300," .. l.hash .. ","), "leída entera y sin ninguna")
        A.truthy(ok("182", "275"), "Herboristería: el nivel")
        A.truthy(ok("164", "280," .. other .. "," .. string.rep("A", 86)), "con otra lista, hasta 86")
        A.falsy(ok("164", "280," .. other .. "," .. string.rep("A", 87)))
        A.falsy(ok("164", "300," .. l.hash .. "," .. string.rep("A", l.chars + 1)), "más letras que su lista")
        A.falsy(ok("356", "100"), "Pesca no")
        A.falsy(ok("0164", "300"))
        A.falsy(ok("164", "0"))
        A.falsy(ok("164", "451"))
        A.falsy(ok("164", "mucho"))
        A.falsy(ok("164", "300,"))
        A.falsy(ok("164", "300,ab,AB"))
        A.falsy(ok("164", "300," .. l.hash .. ",A-B"))
        A.falsy(HU:Propose("OF", "164", "300,ab,AB"), "lo raro no se propone")
        A.truthy(HU:Propose("OF", "164", "300"))
    end)

    it("el enlace solo publica a los que siguen en mi hermandad", function()
        local a = F.Community()
        local HU = a.HU
        local now = HU.StampNow()
        a.w:Receive("HU20B", "WU~UNO~OF~164~" .. now .. "~250", "GUILD", "Compi-Reino")
        a.w:Receive("HU20B", "WU~UNO~OF~164~" .. now .. "~260", "GUILD", "Fuera-Reino")
        A.equal(2, #HU:Proposals("OF"), "las dos, guardadas")
        local names = {}
        for _, e in ipairs(HU.packSets.OF.source()) do names[#names + 1] = e.n end
        A.same({ "Compi-Reino" }, names, "la de quien se fue, no")
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
-- Lo mío, a mi hermandad
---------------------------------------------------------------------------
describe("Oficios (OF): lo mío, a mi hermandad", function()
    it("al abrir la herrería sale su línea (nivel, lista y recetas) y la de Minería con su nivel; dos subidas seguidas, en una tanda a los 5 min; sin cambios, nada", function()
        local net, p = Union()
        local ana, alba = p.ana, p.alba
        local l = ana.HU.ProfessionsForTests.list(164)
        Professions(ana.a, { [164] = 300, [186] = 250 })
        local i0 = #net.log
        Window(ana.a, 164, { [9001] = l[1].id, [9002] = l[3].id })
        net:Advance(10)
        local mine = "300," .. l.hash .. ",F"
        A.same({ "164=" .. mine, "186=250" }, Sent(net, "Ana", i0))
        A.same({ "Ana:164:" .. mine, "Ana:186:250" }, Lines(alba))
        -- (sube dos puntos seguidos: una tanda, a los 5 min de la anterior, con lo último)
        local i1 = #net.log
        Professions(ana.a, { [164] = 301, [186] = 250 })
        ana.w:Fire("SKILL_LINES_CHANGED")
        net:Advance(10)
        Professions(ana.a, { [164] = 302, [186] = 250 })
        ana.w:Fire("SKILL_LINES_CHANGED")
        net:Advance(120)
        A.same({}, Sent(net, "Ana", i1), "espera a los 5 min")
        net:Advance(200)
        A.same({ "164=302," .. l.hash .. ",F" }, Sent(net, "Ana", i1))
        A.same({ "Ana:164:302," .. l.hash .. ",F", "Ana:186:250" }, Lines(alba))
        -- (otra vez la ventana, sin cambios: nada)
        local i2 = #net.log
        Window(ana.a, 164, { [9001] = l[1].id, [9002] = l[3].id })
        net:Advance(400)
        A.same({}, Sent(net, "Ana", i2))
        A.same({}, net:Errors())
    end)

    it("la profesión que ya no tengo se borra en mi hermandad; si el juego no da ninguna, no se borra nada", function()
        local net, p = Union()
        local ana, alba = p.ana, p.alba
        Professions(ana.a, { [164] = 300, [186] = 250 })
        ana.w:Fire("SKILL_LINES_CHANGED")
        net:Advance(40)
        A.same({ "Ana:164:300", "Ana:186:250" }, Lines(alba))
        Professions(ana.a, { [164] = 300 })
        ana.w:Fire("SKILL_LINES_CHANGED")
        net:Advance(320)
        A.same({ "Ana:164:300" }, Lines(alba), "Minería, borrada")
        local i0 = #net.log
        Professions(ana.a, {})
        ana.w:Fire("SKILL_LINES_CHANGED")
        net:Advance(320)
        A.same({}, Sent(net, "Ana", i0))
        A.same({ "Ana:164:300" }, Lines(alba))
        A.same({}, net:Errors())
    end)

    it("al entrar, lo de más de una semana se renueva; con el reenvío de WU a la vez, al enlace le llega todo", function()
        local net, p = Union()
        local ana, alba = p.ana, p.alba
        local four = { [129] = 200, [164] = 300, [185] = 150, [186] = 250 }
        Professions(alba.a, four)
        alba.w:Fire("SKILL_LINES_CHANGED")
        net:Advance(40)
        A.equal(4, #Lines(ana, "Alba"))
        -- (como si las hubiera mandado hace 8 días: en lo guardado de las dos)
        local old = ana.HU.StampNow() - 8 * 86400
        for _, q in ipairs({ ana, alba }) do
            for _, e in pairs(q.HU.db.wuStore.UNO.OF) do e.t = old end
        end
        net:Logout(alba)
        net:Login(alba)
        Professions(alba.a, four)
        net:Advance(200)
        local renewed = 0
        for _, e in pairs(ana.HU.db.wuStore.UNO.OF) do
            if e.n == "Alba-Reino" and e.t > old then renewed = renewed + 1 end
        end
        A.equal(4, renewed, "las 4, renovadas en el enlace")
        A.equal(4, #Lines(ana, "Alba"))
        A.same({}, net:Errors())
    end)
end)

---------------------------------------------------------------------------
-- Buscar y la ficha
---------------------------------------------------------------------------
describe("Oficios (OF): buscar", function()
    -- (lo que ha mandado alguien de mi hermandad, como si lo oyera por GUILD)
    local function Setup()
        local a = F.Community()
        local HU = a.HU
        a.env.C_TradeSkillUI = {
            GetTradeSkillDisplayName = function(id) return id == 164 and "Herrería" or nil end,
            GetTradeSkillTexture = function(id) return "icono" .. id end,
        }
        local now = HU.StampNow()
        local function Hear(who, key, data, t)
            a.w:Receive("HU20B", "WU~UNO~OF~" .. key .. "~" .. (t or now) .. "~" .. data, "GUILD", who)
        end
        return a, HU, HU.ProfessionsForTests.list(164), Hear, now
    end
    local function Rows(HU, q, items, needs)
        local out = {}
        for _, r in ipairs(HU:UnionCrafters(q, items, needs)) do
            out[#out + 1] = r.name:match("^([^-]+)") .. " " .. r.rank .. (r.knows and " ✓" or "")
        end
        return out
    end

    it("un objeto: solo quien se sabe la receta (su línea lo confirma); quien solo tiene la profesión, con otra lista o sin saberse, fuera (Jorge, 25/11)", function()
        local a, HU, l, Hear = Setup()
        local other = l.hash == "zzz" and "yyy" or "zzz"
        Hear("Compi-Reino", "164", "250," .. l.hash .. ",E")   -- (sabe la 3 de la lista)
        Hear("Jefa-Reino", "164", "300," .. l.hash .. ",B")    -- (sabe solo la 1)
        Hear("Otro-Reino", "164", "280," .. other .. ",E")     -- (otra lista: no se sabe qué recetas tiene)
        Hear("Nueva-Reino", "164", "100")                      -- (solo la profesión, sin recetas)
        -- (el objeto 3: solo Compi, que lo sabe; Jefa sabe otra receta, Otro y Nueva no se sabe: fuera)
        local third = l[3]
        A.same({ "Compi 250 ✓" }, Rows(HU, "algo", { [third.id] = true }, { [164] = third.lv }))
        -- (el objeto 1: solo Jefa; aunque Otro (280) y Nueva (100) tengan nivel de sobra, no se sabe que lo sepan)
        A.same({ "Jefa 300 ✓" }, Rows(HU, "algo", { [l[1].id] = true }, { [164] = l[1].lv }))
        -- (por el nombre de la profesión, sí salen todos, por nivel)
        A.same({ "Jefa 300", "Otro 280", "Compi 250", "Nueva 100" }, Rows(HU, "herreria"))
        A.same({}, Rows(HU, "sastreria"))
        local r = HU:UnionCrafters("herreria")[1]
        A.same({ "UNO", 164, "Herrería", "icono164" }, { r.tag, r.skill, r.prof, r.icon })
        A.same({}, a:Errors())
    end)

    it("el índice se hace al mirar y solo se rehace cuando OF cambia: al recibir no se descifra nada", function()
        local _, HU, _, Hear, now = Setup()
        Hear("Compi-Reino", "164", "250")
        local calls, real = 0, HU.Proposals
        HU.Proposals = function(...) calls = calls + 1; return real(...) end
        HU:UnionCrafters("herreria")
        HU:UnionCrafters("herreria")
        HU:UnionProfessionsOf("Compi-Reino")
        A.equal(1, calls, "mirar tres veces: una")
        Hear("Compi-Reino", "164", "251", now + 1)
        A.equal(1, calls, "al recibir, nada")
        A.equal(251, HU:UnionProfessionsOf("Compi-Reino")[1].rank)
        A.equal(2, calls)
    end)

    it("las profesiones de cualquiera, primero las principales; de quien no tiene línea, nada", function()
        local _, HU, l, Hear = Setup()
        Hear("Compi-Reino", "185", "150")
        Hear("Compi-Reino", "186", "200")
        Hear("Compi-Reino", "164", "250," .. l.hash .. ",E")
        local got = {}
        for _, pr in ipairs(HU:UnionProfessionsOf("compi-reino")) do got[#got + 1] = pr.id .. " " .. pr.rank end
        A.same({ "164 250", "186 200", "185 150" }, got)
        A.is_nil(HU:UnionProfessionsOf("Nadie-Reino"))
    end)

    it("pedir OF: de todas (la mía también, por lo que me perdí) o de una", function()
        local HU = F.Community().HU
        local asked = {}
        F.Stub(HU, "PackNeed", function(_, tag, id) asked[#asked + 1] = tag .. "|" .. id end)
        HU:NeedUnionProfessions()
        HU:NeedUnionProfessions("DOS")
        A.same({ "UNO|OF", "DOS|OF", "DOS|OF" }, asked)
    end)
end)

describe("Oficios (OF): la ficha y Comercio", function()
    -- (el paquete OF de DOS, ya comprobado, con estas líneas «Nombre,profesión,datos»)
    local function PackOf(HU, tag, list)
        local lines, t = {}, HU.B36(HU.StampNow())
        for _, x in ipairs(list) do
            local n, k, d = x:match("^([^,]+),([^,]+),(.*)$")
            lines[#lines + 1] = n .. "," .. k .. "," .. t .. "," .. d
        end
        HU.db.packs = HU.db.packs or {}
        HU.db.packs[tag] = { OF = { h = { "h1" }, ok = { "h1" }, t = { lines } } }
        HU.packSets.OF.onChange(tag)
    end
    local function Club(a)
        a.env.C_Club = {
            GetGuildClubId = function() return 9 end,
            GetClubMembers = function() return { 1, 2, 3 } end,
            GetMemberInfo = function(_, id)
                if id == 1 then return { name = "Tester", isSelf = true } end
                if id == 2 then return { name = "Compi", profession1ID = 164, profession1Name = "Herrería", profession1Rank = 1 } end
                return { name = "Jefa", profession1ID = 197, profession1Name = "Sastrería", profession1Rank = 1 }
            end,
        }
        a.env.C_TradeSkillUI = {
            GetTradeSkillDisplayName = function(id) return ({ [164] = "Herrería", [185] = "Cocina" })[id] end,
            GetTradeSkillTexture = function(id) return "icono" .. id end,
        }
    end

    it("la ficha de alguien de otra hermandad: sus profesiones con su nivel, sin «Ver recetas», y pide su OF; la de mi hermandad, el nivel que el juego no da", function()
        local a = F.Community()
        local HU = a.HU
        Club(a)
        local asked = {}
        F.Stub(HU, "PackNeed", function(_, tag, id) asked[#asked + 1] = tag .. "|" .. id end)
        a.w:Receive("HU20B", "WU~UNO~OF~164~" .. HU.StampNow() .. "~250", "GUILD", "Compi-Reino")
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        HU.remoteRoster.DOS = { members = {
            { name = "Bea-Reino", online = true, rankIndex = 1, rank = "Oficial", class = "MAGE", level = 60, zone = "Ventormenta" },
        } }
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        local card
        local function Row(name)
            for _, r in ipairs(cover.rows) do
                if r.entry and r.entry.name:match("^([^-]+)") == name then return r end
            end
        end
        -- (lo que enseña la ficha: el nivel de cada profesión, con «+» si tiene «Ver recetas»)
        local function Profs()
            local out = {}
            for k = 1, 2 do
                if card.recipes.icons[k]:IsShown() then
                    out[#out + 1] = card.recipes.levels[k]:GetText() .. (card.recipes.btns[k]:IsShown() and " +" or "")
                end
            end
            return out
        end
        local function Open(name)
            local r = Row(name)
            r:GetScript("OnClick")(r, "LeftButton")
            card = a.env.GuildUnionMemberCard
        end
        Open("Compi")
        A.same({ "250 +" }, Profs(), "el juego la da sin nivel: el de su línea")
        Open("Compi")
        Open("Bea")
        A.same({}, Profs(), "aún sin su paquete")
        A.equal("—", card.lines[5]:GetText())
        -- (la ficha de cada uno pide lo de oficios de su hermandad: de la mía, lo que me perdí estando fuera, para saber si
        -- tiene sus recetas)
        A.same({ "UNO|OF", "DOS|OF" }, asked, "lo pide a su hermandad")
        -- (llega el paquete de DOS con la ficha abierta: se repinta)
        local l = HU.ProfessionsForTests.list(164)
        PackOf(HU, "DOS", { "Bea-Reino,185,100", "Bea-Reino,164,275," .. l.hash .. ",E" })
        a.w:Advance(3)
        -- (sin «Ver recetas»: el juego no da las de otra hermandad. Su cocina no sale en la ficha, pero sí cuenta para
        -- «Quién lo hace»: Jorge, 25/11, «que no salga en las profesiones de alguien normal, pero sí para tener la data»)
        A.same({ "275" }, Profs(), "sin «Ver recetas» y sin la cocina")
        local cooks = {}
        for _, r in ipairs(HU:UnionCrafters("cocina")) do cooks[#cooks + 1] = r.name .. " " .. r.skill .. " " .. r.rank end
        A.same({ "Bea-Reino 185 100" }, cooks)
        A.same({}, a:Errors())
    end)

    it("«Quién lo hace» enseña a los de toda la unión, con su nivel y el tic si saben la receta; los de mi hermandad sin línea, como antes; nadie dos veces", function()
        local a = F.Community()
        local HU = a.HU
        Club(a)
        local l = HU.ProfessionsForTests.list(164)
        local sword = l[3]
        Names(a, { [sword.id] = "Espada de prueba" })
        local asked = {}
        local need = HU.PackNeed
        F.Stub(HU, "PackNeed", function(self, tag, id) asked[#asked + 1] = tag .. "|" .. id; return need(self, tag, id) end)
        a.w:Receive("HU20B", "WU~UNO~OF~164~" .. HU.StampNow() .. "~250," .. l.hash .. ",E", "GUILD", "Compi-Reino")
        PackOf(HU, "DOS", { "Bea-Reino,164,275," .. l.hash .. ",E", "Blas-Reino,164,290," .. l.hash .. ",B" })
        local tr = OpenTrade(a)
        a.w:Advance(40) -- (los nombres de los objetos, poco a poco; y lo de la red, 5 s después de abrir)
        local got = {}
        for _, x in ipairs(asked) do if x:match("|OF$") then got[#got + 1] = x end end
        A.same({ "UNO|OF", "DOS|OF" }, got, "al abrir, lo de oficios de todas")
        Search(tr, "espada de prueba")
        A.same({ "Bea DOS 275 ✓", "Compi UNO 250 ✓" }, Found(tr), "Blas no la sabe; Compi, una vez")
        Search(tr, "herreria")
        A.same({ "Blas DOS 290", "Bea DOS 275", "Compi UNO 250" }, Found(tr))
        Search(tr, "sastreria")
        A.same({ "Jefa UNO —" }, Found(tr), "sin línea: lo que da el juego")
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
-- Tres hermandades: el criterio de las specs
---------------------------------------------------------------------------
describe("Oficios (OF): tres hermandades", function()
    it("Ana (UNO) abre su herrería y se va; Bea (DOS) abre Comercio y la ve con su nivel y la receta, y sus profesiones; Ana sube de nivel y a DOS le llega solo eso", function()
        local net, p = Union("Alba")
        local ana, bea, tere = p.ana, p.bea, p.tere
        local l = ana.HU.ProfessionsForTests.list(164)
        local sword = l[3]
        Professions(ana.a, { [164] = 300, [186] = 250 })
        Window(ana.a, 164, { [9001] = l[1].id, [9002] = sword.id })
        net:Advance(10)
        net:Logout(ana)
        -- (Bea abre Comercio y busca la espada)
        Names(bea.a, { [sword.id] = "Espada de prueba" })
        local tr = OpenTrade(bea.a)
        A.truthy(Until(net, function()
            Search(tr, "espada de prueba")
            return Found(tr)[1] == "Ana UNO 300 ✓"
        end, 400), "no llega a DOS")
        local profs = {}
        for _, pr in ipairs(bea.HU:UnionProfessionsOf("Ana-Reino")) do profs[#profs + 1] = pr.id .. " " .. pr.rank end
        A.same({ "164 300", "186 250" }, profs, "la ficha de Ana, en DOS")
        -- (Tere, de TRES, también, al mirar)
        A.truthy(Until(net, function()
            tere.HU:NeedUnionProfessions()
            return #(tere.HU:UnionProfessionsOf("Ana-Reino") or {}) == 2
        end, 400), "no llega a TRES")
        -- (Ana vuelve y sube un punto: a DOS le llega solo ese cambio, sin volver a pedir el paquete)
        net:Login(ana)
        Professions(ana.a, { [164] = 301, [186] = 250 })
        ana.w:Fire("SKILL_LINES_CHANGED")
        local i0 = #net.log
        A.truthy(Until(net, function()
            local pr = bea.HU:UnionProfessionsOf("Ana-Reino")
            return pr ~= nil and pr[1].rank == 301
        end, 900), "el cambio no llega a DOS")
        local wd, wt = 0, 0
        for i = i0 + 1, #net.log do
            local m = net.log[i]
            if m.text:match("^WD~UNO~OF~") then wd = wd + 1 end
            if m.text:match("^WT~UNO~OF~") then wt = wt + 1 end
        end
        A.truthy(wd > 0, "con la diferencia (WD)")
        A.equal(0, wt, "sin trozos enteros")
        A.same({}, net:Errors())
    end)
end)
