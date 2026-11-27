-- Estadísticas de la hermandad (GuildStats.lua), para oficiales y el maestro: miembros, rangos, niveles, clases, razas,
-- profesiones y actividad (activos, alts, inactivos), con gráficos en el juego y texto para copiar a Discord o un archivo;
-- y el informe de la unión (SQ y SR): los números de cada hermandad, que da uno de sus oficiales, sumados
local red = require("lib.red")
local F = require("lib.fixtures")
local A = assert_
local unpack = table.unpack or unpack

local DAY = 86400
local function Has(text, s) A.truthy(tostring(text):find(s, 1, true), "falta «" .. s .. "» en:\n" .. tostring(text)) end
local function Lacks(text, s) A.falsy(tostring(text):find(s, 1, true), "sobra «" .. s .. "» en:\n" .. tostring(text)) end
local function Said(a, i0)
    local out = {}
    for i = i0 + 1, #a.w.chat do out[#out + 1] = tostring(a.w.chat[i].msg) end
    return table.concat(out, "\n")
end

-- (una hermandad de prueba, con niveles, clases (la clave del juego, como la da la lista de la hermandad), rangos,
-- conectados, inactivos, un par de alts y razas por GUID)
local function Stats(a)
    local HU = a.HU
    local now = a.env.time()
    HU.rosterList = {
        { name = "Jefa-Reino", rank = "Maestra", rankIndex = 0, level = 60, class = "DRUID", online = true, guid = "g1" },
        { name = "Tester-Reino", rank = "Oficial", rankIndex = 1, level = 60, class = "MAGE", online = true, guid = "g2" },
        { name = "Compi-Reino", rank = "Miembro", rankIndex = 4, level = 45, class = "MAGE", online = false, offSecs = 10 * DAY, guid = "g3" },
        { name = "Nuevo-Reino", rank = "Miembro", rankIndex = 4, level = 15, class = "WARRIOR", online = true, mobile = true, guid = "g4" },
        { name = "Viejo-Reino", rank = "Miembro", rankIndex = 4, level = 60, class = "DRUID", online = false, offSecs = 40 * DAY, guid = "g5" },
        { name = "Mula-Reino", rank = "Alt", rankIndex = 5, level = 60, class = "ROGUE", online = true, guid = "g6" },
        { name = "Dobleuno-Reino", rank = "Miembro", rankIndex = 4, level = 30, class = "ROGUE", online = false, offSecs = 5 * DAY, note = "alt de Jefa", guid = "g7" },
    }
    -- (los nombres de las clases, como los da el juego en castellano)
    a.env.LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druida", MAGE = "Mago", WARRIOR = "Guerrero", ROGUE = "Pícaro" }
    HU.db.inviteLog = { ["Hermandad Uno"] = {
        { t = now - 1 * DAY }, { t = now - 3 * DAY }, { t = now - 20 * DAY }, { t = now - 50 * DAY },
    } }
    HU.db.leaveLog = { ["Hermandad Uno"] = { { t = now - 2 * DAY }, { t = now - 40 * DAY } } }
    -- (las razas, por el GUID: el nombre que da el juego y su clave)
    local race = { g1 = "Elfa de la noche", g2 = "Humano", g3 = "Humano", g4 = "Enano", g5 = "Elfa de la noche", g6 = "No-muerto", g7 = "Humano" }
    local raceKey = { g1 = "NightElf", g2 = "Human", g3 = "Human", g4 = "Dwarf", g5 = "NightElf", g6 = "Scourge", g7 = "Human" }
    a.env.GetPlayerInfoByGUID = function(guid) return "x", "X", race[guid], raceKey[guid] end
    -- (las profesiones de la hermandad, de lo que da el juego, con su número: fijadas para la prueba)
    F.Stub(HU, "GuildProfessionCounts", function()
        return { { name = "Alquimia", n = 3, id = 171 }, { name = "Sastrería", n = 2, id = 197 } }
    end)
    return HU
end

describe("Estadísticas de la hermandad (GuildStats.lua)", function()
    it("miembros, rangos, niveles, clases, razas, profesiones, actividad e inactivos", function()
        local a = F.Community()
        local HU = Stats(a)
        local s = HU:GuildStats()
        A.equal("Hermandad Uno", s.guild)
        A.same({ 7, 4, 1 }, { s.total, s.online, s.mobile }, "total, conectados, móvil")
        A.same({ { name = "Maestra", total = 1, online = 1 }, { name = "Oficial", total = 1, online = 1 },
            { name = "Miembro", total = 4, online = 1 }, { name = "Alt", total = 1, online = 1 } }, s.byRank)
        A.equal(60, s.maxLevel)
        A.same({ { "1-19", 1 }, { "20-39", 1 }, { "40-59", 1 }, { "60", 4 } }, s.levelBuckets)
        A.same({ { name = "Druida", n = 2 }, { name = "Mago", n = 2 }, { name = "Pícaro", n = 2 }, { name = "Guerrero", n = 1 } }, s.byClass)
        A.same({ { name = "Humano", n = 3 }, { name = "Elfa de la noche", n = 2 }, { name = "Enano", n = 1 }, { name = "No-muerto", n = 1 } }, s.byRace)
        A.same({ { name = "Alquimia", n = 3, id = 171 }, { name = "Sastrería", n = 2, id = 197 } }, s.professions)
        A.same({ 2, 3, 1, 1 }, { s.joined7, s.joined30, s.left7, s.left30 })
        A.same({ 2, 1 }, { s.inactive7, s.inactive30 })
        A.same({}, a:Errors())
    end)

    it("activos (vistos en 30 días), alts (por rango o nota) y % activa sin contar alts", function()
        local a = F.Community()
        local HU = Stats(a)
        local s = HU:GuildStats()
        -- (activos: los 4 conectados + Compi (10 días) y Dobleuno (5 días); Viejo (40 días), no. 6 de 7)
        A.equal(6, s.active)
        A.equal(86, math.floor(s.activePct + 0.5))
        -- (alts: Mula (rango «Alt») y Dobleuno (nota «alt»). 2 de 7)
        A.equal(2, s.alts)
        A.equal(29, math.floor(s.altsPct + 0.5))
        -- (sin los 2 alts quedan 5; de ellos activos 4 (los 3 conectados que no son alt + Compi): 80 %)
        A.equal(80, math.floor(s.activeNoAltPct + 0.5))
        A.same({}, a:Errors())
    end)

    it("el texto es llano (sin colores), con todas las secciones, listo para Discord o un archivo", function()
        local a = F.Community()
        local HU = Stats(a)
        local text = HU:GuildStatsText()
        Has(text, "Guild Union - Estadísticas de Hermandad Uno - ")
        Has(text, "Miembros: 7  ·  conectados: 4  ·  con el móvil: 1")
        Has(text, "Activos (vistos en 30 días): 6 (86%)  ·  sin contar alts: 80%")
        Has(text, "Alts: 2 (29%)")
        Has(text, "Por rango:")
        Has(text, "Niveles: máximo 60")
        Has(text, "Clases:")
        Has(text, "Razas:")
        Has(text, "Humano")
        Has(text, "Profesiones:")
        Has(text, "Alquimia")
        Has(text, "Altas: 2 (7 días)  ·  3 (30 días)")
        Has(text, "Sin conectarse: 2 (más de 7 días)  ·  1 (más de 30 días)")
        Lacks(text, "|cff")
        Lacks(text, "|r")
        A.same({}, a:Errors())
    end)

    it("la ventana con gráficos; «Exportar» abre el texto para copiar; solo la ven oficiales y el maestro", function()
        local a = F.Community()
        local HU = Stats(a)
        -- (Tester es oficial: se abre la ventana de gráficos)
        A.truthy(HU:CanSeeStats())
        HU:ShowGuildStats()
        A.truthy(a.env.GuildUnionStats and a.env.GuildUnionStats:IsShown(), "la ventana de estadísticas")
        -- («Exportar» abre la ventana de copiar, con el texto)
        local c = {}
        HU.UI.ShowCopy = function(_, title, text, opts) c.title, c.text, c.opts = title, text, opts end
        HU:ExportGuildStats()
        A.equal("Estadísticas de la hermandad", c.title)
        Has(c.text, "Miembros: 7")
        Has(c.opts.hint, "pégalo en Discord o en un archivo de texto")
        -- (un miembro de a pie, no)
        F.Stub(HU, "CanOfficer", false)
        A.falsy(HU:CanSeeStats())
        local i0 = #a.w.chat
        HU:ShowGuildStats()
        Has(Said(a, i0), "Las estadísticas son solo para oficiales.")
        A.same({}, a:Errors())
    end)

    it("HU:GuildProfessionCounts: cuenta las profesiones principales de la hermandad, de lo que da el juego (sin addon)", function()
        local a = F.Community()
        local HU = a.HU
        a.env.C_Club = {
            GetGuildClubId = function() return 1 end,
            GetClubMembers = function() return { 1, 2, 3 } end,
            GetMemberInfo = function(_, id) return ({
                [1] = { name = "Jefa-Reino", profession1Name = "Alquimia", profession1ID = 171 },
                [2] = { name = "Tester-Reino", profession1Name = "Alquimia", profession1ID = 171, profession2Name = "Sastrería", profession2ID = 197 },
                [3] = { name = "Compi-Reino", profession1Name = "Sastrería", profession1ID = 197 },
            })[id] end,
        }
        local out = {}
        for _, r in ipairs(HU:GuildProfessionCounts()) do out[#out + 1] = { name = r.name, n = r.n } end
        A.same({ { name = "Alquimia", n = 2 }, { name = "Sastrería", n = 2 } }, out)
        A.same({}, a:Errors())
    end)

    it("fuera de una hermandad, lo dice y no revienta", function()
        local a = F.Community()
        a.w.guild = nil
        A.is_nil(a.HU:GuildStats())
        A.equal("No estás en una hermandad.", a.HU:GuildStatsText())
        A.same({}, a:Errors())
    end)
end)

describe("Estadísticas de la unión (GuildStats.lua, SQ y SR)", function()
    -- Lo que el addon enseña en la ventana de copiar (la última vez)
    local function Capture(HU)
        local c = { text = "" }
        HU.UI.ShowCopy = function(_, title, text, opts) c.title, c.text, c.opts = title, text, opts end
        return c
    end
    local function Row(text, tag) return text:match("\n<" .. tag .. ">[^\n]*") or "" end
    -- (los SR que me han salido desde la última vez que se miró)
    local function SRs(a)
        local out = {}
        for _, m in ipairs(a.w:TakeSent()) do if m.text:match("^SR~") then out[#out + 1] = m end end
        return out
    end
    -- (los números de la hermandad de prueba (Stats) como van en SR: miembros, conectados, móvil, activos, alts, activos
    -- sin alts, sin alts, nivel máximo, suma de niveles, con nivel, tramos 1-19/20-39/40-59/60, altas de 7 y 30 días,
    -- bajas de 7 y 30 y sin conectarse más de 7 y de 30 días; luego, cuántos de cada clase (WARRIOR, PALADIN, HUNTER,
    -- ROGUE, PRIEST, SHAMAN, MAGE, WARLOCK, DRUID), raza (Human, Dwarf, NightElf, Gnome, Orc, Scourge, Tauren, Troll) y
    -- profesión (171, 164, 333, 202, 182, 165, 186, 393, 197))
    local MINE = "7~4~1~6~2~4~5~60~330~7~1~1~1~4~2~3~1~1~2~1~1.0.0.2.0.0.2.0.2~3.1.2.0.0.1.0.0~3.0.0.0.0.0.0.0.2"

    it("clases, razas y profesiones también por su clave del juego (no dependen del idioma), y la suma de niveles", function()
        local a = F.Community()
        local HU = Stats(a)
        local s = HU:GuildStats()
        A.same({ DRUID = 2, MAGE = 2, WARRIOR = 1, ROGUE = 2 }, s.byClassKey)
        A.same({ NightElf = 2, Human = 3, Dwarf = 1, Scourge = 1 }, s.byRaceKey)
        A.same({ [171] = 3, [197] = 2 }, s.byProfID)
        A.same({ 7, 330, 7 }, { s.total, s.levelSum, s.levelN })
        -- (si el juego falla al dar la raza, no la cuenta y no revienta)
        a.env.GetPlayerInfoByGUID = function() error("sin datos") end
        s = HU:GuildStats()
        A.same({}, s.byRace)
        A.same({}, s.byRaceKey)
        A.same({}, a:Errors())
    end)

    it("un oficial de la unión me pregunta por susurro y le contesto con los números de mi hermandad, sin nombres", function()
        local a = F.Community()
        local HU = Stats(a)
        SRs(a)
        -- (Jefa es la maestra de mi hermandad)
        a.w:Receive("HU20", "SQ~UNO~abc", "WHISPER", "Jefa-Reino")
        a.w:Advance(1)
        local got = SRs(a)
        A.equal(1, #got)
        A.equal("Jefa-Reino", got[1].target)
        A.equal("WHISPER", got[1].dist)
        A.equal("SR~UNO~abc~" .. HU.version .. "~" .. MINE, got[1].text)
        A.same({}, a:Errors())
    end)

    it("en un campo de batalla (el juego bloquea el chat) no sale nada mientras dure", function()
        local a = F.Community()
        local HU = Stats(a)
        SRs(a)
        a.w.lockdown = true
        a.w:Receive("HU20", "SQ~UNO~abc", "WHISPER", "Jefa-Reino")
        a.w:Advance(10)
        A.equal(0, #SRs(a), "con el chat bloqueado no sale")
        -- (y quien pregunta tampoco puede: lo dice y no manda nada)
        local i0 = #a.w.chat
        HU:AskUnionStats()
        Has(Said(a, i0), "Ahora no se pueden mandar mensajes del addon")
        a.w:Advance(10)
        local sq = 0
        for _, m in ipairs(a.w:TakeSent()) do if m.text:match("^S[QR]~") then sq = sq + 1 end end
        A.equal(0, sq)
        A.same({}, a:Errors())
    end)

    it("no contesto: por GUILD, de fuera, a quien no es oficial, si yo no lo soy o sin mi lista; y con topes", function()
        local g = F.Guild()
        for i = 1, 22 do g.members[#g.members + 1] = { name = "Socio" .. i .. "-Reino", rank = "Oficial", rankIndex = 1 } end
        local a = F.Community({ guild = g })
        local HU = Stats(a)
        SRs(a)
        a.w:Receive("HU20", "SQ~UNO~uno", "GUILD", "Jefa-Reino")      -- (por GUILD)
        a.w:Receive("HU20", "SQ~UNO~uno", "WHISPER", "Extra-Reino")   -- (de fuera)
        a.w:Receive("HU20", "SQ~ZZZ~uno", "WHISPER", "Jefa-Reino")    -- (una etiqueta que no es de la unión)
        a.w:Receive("HU20", "SQ~DOS~uno", "WHISPER", "Jefa-Reino")    -- (de mi hermandad, diciendo ser de DOS)
        a.w:Receive("HU20", "SQ~UNO~a,b", "WHISPER", "Jefa-Reino")    -- (un id raro)
        a.w:Receive("HU20", "SQ~UNO~uno", "WHISPER", "Compi-Reino")   -- (no es oficial)
        a.w:Advance(1)
        A.equal(0, #SRs(a), "ninguna de esas")
        -- (yo no soy oficial)
        F.Stub(HU, "CanSeeStats", false)
        a.w:Receive("HU20", "SQ~UNO~uno", "WHISPER", "Jefa-Reino")
        a.w:Advance(1)
        A.equal(0, #SRs(a), "si yo no soy oficial")
        F.Stub(HU, "CanSeeStats", true)
        -- (sin mi lista todavía: diría que somos 0)
        local list = HU.rosterList
        HU.rosterList = {}
        a.w:Receive("HU20", "SQ~UNO~uno", "WHISPER", "Jefa-Reino")
        a.w:Advance(1)
        HU.rosterList = list
        A.equal(0, #SRs(a), "sin la lista")
        -- (a cada uno, una vez cada 30 s)
        a.w:Receive("HU20", "SQ~UNO~uno", "WHISPER", "Jefa-Reino")
        a.w:Receive("HU20", "SQ~UNO~dos", "WHISPER", "Jefa-Reino")
        a.w:Advance(1)
        A.equal(1, #SRs(a), "a Jefa, una vez")
        a.w:Advance(30)
        a.w:Receive("HU20", "SQ~UNO~tres", "WHISPER", "Jefa-Reino")
        a.w:Advance(1)
        A.equal(1, #SRs(a), "pasados 30 s, otra vez")
        -- (de 22 a la vez: como mucho 20 en 30 s; y mis números se cuentan una vez, no veinte)
        a.w:Advance(30)
        local calls, real = 0, HU.GuildStats
        F.Stub(HU, "GuildStats", function(self) calls = calls + 1; return real(self) end)
        for i = 1, 22 do a.w:Receive("HU20", "SQ~UNO~s" .. i, "WHISPER", "Socio" .. i .. "-Reino") end
        a.w:Advance(25)
        A.equal(20, #SRs(a), "el tope de todos juntos")
        A.equal(1, calls, "mis números, una vez")
        A.same({}, a:Errors())
    end)

    it("con más de 200 que han preguntado, se olvida a los de hace más de 30 s y se sigue contestando igual", function()
        local g = F.Guild()
        for i = 1, 220 do g.members[#g.members + 1] = { name = "Socio" .. i .. "-Reino", rank = "Oficial", rankIndex = 1 } end
        local a = F.Community({ guild = g })
        Stats(a)
        SRs(a)
        local n = 0
        -- (11 tandas de 20 distintos, una cada 31 s: en la 11.ª ya van más de 200)
        for w = 0, 10 do
            for i = 1, 20 do a.w:Receive("HU20", "SQ~UNO~t" .. w .. "s" .. i, "WHISPER", "Socio" .. (w * 20 + i) .. "-Reino") end
            a.w:Advance(31)
            n = n + #SRs(a)
        end
        A.equal(220, n, "20 en cada tanda, también pasados los 200")
        A.same({}, a:Errors())
    end)

    it("quien pide: solo oficiales, con comunidad, una pregunta cada vez y no otra antes de 30 s", function()
        local a = F.Community()
        local HU = Stats(a)
        local c = Capture(HU)
        a.w.lockdown = true
        local i0 = #a.w.chat
        HU:AskUnionStats()
        Has(Said(a, i0), "Ahora no se pueden mandar mensajes del addon")
        a.w.lockdown = nil
        -- (de DOS no conozco a nadie: solo la mía, sin mensajes)
        i0 = #a.w.chat
        HU:AskUnionStats()
        Has(Said(a, i0), "preguntado a 0")
        i0 = #a.w.chat
        HU:AskUnionStats()
        Has(Said(a, i0), "Ya estás pidiendo")
        a.w:Advance(11)
        Has(Row(c.text, "UNO"), "<UNO>  (la mía)  7 miembros · conectados 4 · activos 6 (86%) · alts 2 (29%) · nivel medio 47.1 (máx. 60)")
        Has(Row(c.text, "DOS"), "<DOS>  no conozco a nadie suyo conectado con el addon")
        Has(c.text, "Estadísticas de la unión: han contestado 1 de 1.")
        A.equal("Estadísticas de la unión", c.title)
        Has(c.opts.hint, "pégalo en Discord")
        i0 = #a.w.chat
        HU:AskUnionStats()
        Has(Said(a, i0), "Espera 19 s")
        a.w:Advance(20)
        -- (sin la ventana de copiar, al chat)
        HU.UI.ShowCopy = nil
        i0 = #a.w.chat
        HU:AskUnionStats()
        a.w:Advance(11)
        Has(Said(a, i0), "<UNO>  (la mía)  ")
        a.w:Advance(31)
        local cfg = HU.cfg
        HU.cfg = nil
        i0 = #a.w.chat
        HU:AskUnionStats()
        Has(Said(a, i0), "Aún no hay comunidad")
        HU.cfg = cfg
        F.Stub(HU, "CanSeeStats", false)
        i0 = #a.w.chat
        HU:AskUnionStats()
        Has(Said(a, i0), "Las estadísticas son solo para oficiales.")
        A.same({}, a:Errors())
    end)

    it("solo vale la respuesta de a quien pregunté, en esa pregunta, y con números que valen y cuadran entre sí", function()
        local a = F.Community()
        local HU = Stats(a)
        F.Stub(HU, "KnownRelay", function(_, tag) if tag == "DOS" then return { name = "Bea-Reino", tag = "DOS" } end end)
        local c = Capture(HU)
        local function Asked()
            local id
            for _, m in ipairs(a.w:TakeSent()) do id = (m.target == "Bea-Reino" and m.text:match("^SQ~UNO~(%w+)$")) or id end
            return id
        end
        HU:AskUnionStats()
        local id = Asked()
        A.truthy(id, "ha preguntado a Bea (su enlace: no sé si es oficial)")
        -- (DOS: 10 miembros, 3 conectados, 0 con el móvil, 8 activos, 2 alts, 7 activos sin alts, 8 sin alts, nivel máximo
        -- 60, suma de niveles 400 de 10 con nivel, tramos 1, 2, 3 y 4, altas 1 y 2, bajas 0 y 1, sin conectarse 2 y 1;
        -- clases 2-1-1-2-1-0-1-1-1, razas 4-2-2-2-0-0-0-0 y profesiones 3-2-2-1-2-1-3-2-2)
        local good = { "10", "3", "0", "8", "2", "7", "8", "60", "400", "10", "1", "2", "3", "4", "1", "2", "0", "1", "2", "1",
            "2.1.1.2.1.0.1.1.1", "4.2.2.2.0.0.0.0", "3.2.2.1.2.1.3.2.2" }
        local function Reply(i, v, who, tag, rid, extra)
            local f = { unpack(good) }
            if i then f[i] = v end
            a.w:Receive("HU20", "SR~" .. (tag or "DOS") .. "~" .. (rid or id) .. "~" .. HU.version .. "~"
                .. table.concat(f, "~") .. (extra or ""), "WHISPER", who or "Bea-Reino")
        end
        -- (letras, negativos, decimales, de más del tope, vacíos, y números que no cuadran entre sí)
        for _, bad in ipairs({ { 1, "abc" }, { 1, "-5" }, { 2, "2.5" }, { 1, "10000" }, { 8, "101" }, { 3, "" },
            { 2, "11" },  -- (más conectados que miembros)
            { 5, "3" },   -- (alts y sin alts no suman los miembros)
            { 6, "9" },   -- (más activos sin alts que activos)
            { 11, "2" },  -- (los tramos no suman los que tienen nivel)
            { 9, "601" }, -- (más niveles de los que caben: 10 × 60)
            { 20, "3" },  -- (más sin conectarse de 30 días que de 7)
            { 15, "3" },  -- (más altas en 7 días que en 30)
            { 17, "2" },  -- (más bajas en 7 días que en 30)
            { 21, "1.2" },                 -- (clases: faltan)
            { 21, "1.1.1.1.1.1.1.1.1.1" }, -- (clases: sobran)
            { 21, "a.1.1.1.1.1.1.1.1" },   -- (letras)
            { 21, "5.5.0.0.0.0.0.0.1" },   -- (más clases que miembros)
            { 22, "3.3.3.3.0.0.0.0" },     -- (más razas que miembros)
            { 23, "9.9.9.0.0.0.0.0.0" },   -- (más de dos profesiones por cabeza)
            { 22, "" },                    -- (vacía)
            { 23, "1..1.1.1.1.1.1.1" } }) do -- (un hueco)
            Reply(bad[1], bad[2])
        end
        Reply(nil, nil, nil, nil, nil, "~9") -- (un número de más)
        -- (las buenas, pero de quien no se ha preguntado, con la etiqueta de otra hermandad o de otra pregunta)
        Reply(nil, nil, "Blas-Reino")
        Reply(nil, nil, nil, "UNO")
        Reply(nil, nil, nil, nil, "otra")
        a.w:Advance(11)
        Has(Row(c.text, "DOS"), "<DOS>  Bea Reino (no sé si es oficial)  ha contestado con números que no valen")
        Has(c.text, "han contestado 1 de 2.")
        -- (la próxima vez, con números buenos: salen tal cual y se suman a los de la mía)
        a.w:Advance(30)
        Stats(a)
        HU:AskUnionStats()
        id = Asked()
        Reply()
        Reply(1, "99") -- (la segunda ya no cuenta)
        a.w:Advance(11)
        Has(Row(c.text, "DOS"), "<DOS>  Bea Reino  10 miembros · conectados 3 · activos 8 (80%) · alts 2 (20%) · nivel medio 40.0 (máx. 60)")
        Has(c.text, "han contestado 2 de 2.")
        Has(c.text, "\nToda la unión, sumando las que han contestado:\n")
        Has(c.text, "\n  Miembros: 17  ·  conectados: 7  ·  con el móvil: 1\n")
        Has(c.text, "\n  Activos (vistos en 30 días): 14 (82%)  ·  sin contar alts: 85%\n")
        Has(c.text, "\n  Alts: 4 (24%)\n")
        Has(c.text, "\n  Niveles: máximo 60  ·  media 42.9  ·  al 60: 8\n")
        A.truthy(c.text:find("\n    1%-19 +2\n    20%-39 +3\n    40%-59 +4\n    60 +8\n"), c.text)
        Has(c.text, "\n    Altas: 3 (7 días)  ·  5 (30 días)\n")
        Has(c.text, "\n    Bajas: 1 (7 días)  ·  2 (30 días)\n")
        Has(c.text, "\n    Sin conectarse: 4 (más de 7 días)  ·  2 (más de 30 días)\n")
        -- (clases, razas y profesiones de las dos sumadas, con su nombre y de más a menos)
        A.truthy(c.text:find("\n  Clases:\n    Pícaro +4\n    Druida +3\n    Guerrero +3\n    Mago +3\n    HUNTER +1\n"
            .. "    PALADIN +1\n    PRIEST +1\n    WARLOCK +1\n"), c.text)
        A.truthy(c.text:find("\n  Razas:\n    Humano +7\n    Elfo de la noche +4\n    Enano +3\n    Gnomo +2\n    No%-muerto +1\n"), c.text)
        A.truthy(c.text:find("\n  Profesiones:\n    Alquimia +6\n    Sastrería +4\n    Minería +3\n    Desuello +2\n"
            .. "    Encantamiento +2\n    Herboristería +2\n    Herrería +2\n    Ingeniería +1\n    Peletería +1\n"), c.text)
        -- (y si no contesta, se dice)
        a.w:Advance(30)
        HU:AskUnionStats()
        a.w:Advance(11)
        Has(Row(c.text, "DOS"), "<DOS>  Bea Reino (no sé si es oficial)  NO HA CONTESTADO")
        -- (si de DOS conozco a un oficial con el addon y conectado, se le pregunta a él y no a su enlace)
        a.w:Advance(30)
        local remoteKeys, isOfficer = HU.RemoteKeys, HU.IsOfficerName
        HU.remote["blas-reino"] = { name = "Blas-Reino", tag = "DOS", last = a.env.GetTime() }
        F.Stub(HU, "RemoteKeys", function(self, tag) if tag == "DOS" then return { "blas-reino" } end return remoteKeys(self, tag) end)
        F.Stub(HU, "IsOfficerName", function(self, name) if name == "Blas-Reino" then return true, 1 end return isOfficer(self, name) end)
        a.w:TakeSent()
        HU:AskUnionStats()
        HU.remote["blas-reino"], HU.RemoteKeys = nil, remoteKeys
        local to
        for _, m in ipairs(a.w:TakeSent()) do if m.text:match("^SQ~") then to = m.target end end
        A.equal("Blas-Reino", to, "al oficial, no a su enlace")
        a.w:Advance(11)
        Has(Row(c.text, "DOS"), "<DOS>  Blas Reino  NO HA CONTESTADO")
        A.same({}, a:Errors())
    end)

    it("la ventana de /gu stats tiene «Pedir a la unión», que pide el informe", function()
        local a = F.Community()
        local HU = Stats(a)
        HU:ShowGuildStats()
        local btn = a.env.GuildUnionStats.union
        A.truthy(btn, "el botón")
        local called = 0
        F.Stub(HU, "AskUnionStats", function() called = called + 1 end)
        btn:GetScript("OnClick")(btn)
        A.equal(1, called)
        A.same({}, a:Errors())
    end)

    it("de punta a punta: un oficial pide y el oficial de cada hermandad contesta; se suma todo", function()
        local INFO3 = table.concat({ F.INFO, "GU:g:Hermandad Tres:TRES" }, "\n")
        local GUILDS3 = { UNO = "Hermandad Uno", DOS = "Hermandad Dos", TRES = "Hermandad Tres" }
        local net = red.New({ step = 0.5, info = INFO3, guilds = GUILDS3 })
        local p = {}
        -- (UNO: Ana (oficial) y Alba; DOS: Bea (oficial) y Blas; TRES: Tere (oficial) y Toni)
        for _, x in ipairs({ { "ana", "Ana", "UNO", 1 }, { "alba", "Alba", "UNO", 4 }, { "bea", "Bea", "DOS", 1 },
            { "blas", "Blas", "DOS", 4 }, { "tere", "Tere", "TRES", 1 }, { "toni", "Toni", "TRES", 4 } }) do
            p[x[1]] = net:Player(x[2], x[3], { rankIndex = x[4] })
        end
        for _, n in ipairs({ "ana", "alba", "bea", "blas", "tere", "toni" }) do net:Login(p[n]) end
        net:Advance(150)
        -- (los oficiales confirman las listas de las otras, como al montar la comunidad)
        for _, x in ipairs({ { p.ana, "DOS", "TRES" }, { p.bea, "UNO", "TRES" }, { p.tere, "UNO", "DOS" } }) do
            x[1].HU:ConfirmRoster(x[2])
            x[1].HU:ConfirmRoster(x[3])
        end
        net:Advance(60)
        local HU = p.ana.HU
        local c = Capture(HU)
        local i0 = #net.log
        HU:AskUnionStats()
        net:Advance(12)
        Has(Row(c.text, "UNO"), "<UNO>  (la mía)  2 miembros")
        Has(Row(c.text, "DOS"), "<DOS>  Bea Reino  2 miembros")
        Has(Row(c.text, "TRES"), "<TRES>  Tere Reino  2 miembros")
        Has(c.text, "han contestado 3 de 3.")
        Has(c.text, "\n  Miembros: 6  ·  conectados: 6\n")
        -- (las respuestas: de los dos oficiales, por susurro y solo números)
        local srs = {}
        for i = i0 + 1, #net.log do
            local m = net.log[i]
            if m.text:match("^SR~") then srs[#srs + 1] = m end
        end
        A.equal(2, #srs)
        for _, m in ipairs(srs) do
            A.equal("WHISPER", m.dist)
            A.truthy(m.text:match("^SR~%u+~%w+~[%d%.]+" .. ("~%d+"):rep(20) .. ("~[%d%.]+"):rep(3) .. "$"), m.text)
        end
        for _, sec in ipairs({ "Clases:", "Razas:", "Profesiones:" }) do Has(c.text, "\n  " .. sec .. "\n") end
        A.same({}, net:Errors())
    end)
end)
