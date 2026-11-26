-- Estadísticas de la hermandad (GuildStats.lua), para oficiales y el maestro: miembros, rangos, niveles, clases, razas,
-- profesiones y actividad (activos, alts, inactivos), con gráficos en el juego y texto para copiar a Discord o un archivo
local F = require("lib.fixtures")
local A = assert_

local DAY = 86400
local function Has(text, s) A.truthy(tostring(text):find(s, 1, true), "falta «" .. s .. "» en:\n" .. tostring(text)) end
local function Lacks(text, s) A.falsy(tostring(text):find(s, 1, true), "sobra «" .. s .. "» en:\n" .. tostring(text)) end
local function Said(a, i0)
    local out = {}
    for i = i0 + 1, #a.w.chat do out[#out + 1] = tostring(a.w.chat[i].msg) end
    return table.concat(out, "\n")
end

-- (una hermandad de prueba, con niveles, clases, rangos, conectados, inactivos, un par de alts y razas por GUID)
local function Stats(a)
    local HU = a.HU
    local now = a.env.time()
    HU.rosterList = {
        { name = "Jefa-Reino", rank = "Maestra", rankIndex = 0, level = 60, class = "Druida", online = true, guid = "g1" },
        { name = "Tester-Reino", rank = "Oficial", rankIndex = 1, level = 60, class = "Mago", online = true, guid = "g2" },
        { name = "Compi-Reino", rank = "Miembro", rankIndex = 4, level = 45, class = "Mago", online = false, offSecs = 10 * DAY, guid = "g3" },
        { name = "Nuevo-Reino", rank = "Miembro", rankIndex = 4, level = 15, class = "Guerrero", online = true, mobile = true, guid = "g4" },
        { name = "Viejo-Reino", rank = "Miembro", rankIndex = 4, level = 60, class = "Druida", online = false, offSecs = 40 * DAY, guid = "g5" },
        { name = "Mula-Reino", rank = "Alt", rankIndex = 5, level = 60, class = "Pícaro", online = true, guid = "g6" },
        { name = "Dobleuno-Reino", rank = "Miembro", rankIndex = 4, level = 30, class = "Pícaro", online = false, offSecs = 5 * DAY, note = "alt de Jefa", guid = "g7" },
    }
    HU.db.inviteLog = { ["Hermandad Uno"] = {
        { t = now - 1 * DAY }, { t = now - 3 * DAY }, { t = now - 20 * DAY }, { t = now - 50 * DAY },
    } }
    HU.db.leaveLog = { ["Hermandad Uno"] = { { t = now - 2 * DAY }, { t = now - 40 * DAY } } }
    -- (las razas, por el GUID)
    local race = { g1 = "Elfa de la noche", g2 = "Humano", g3 = "Humano", g4 = "Enano", g5 = "Elfa de la noche", g6 = "No-muerto", g7 = "Humano" }
    a.env.GetPlayerInfoByGUID = function(guid) return "x", "X", race[guid] end
    -- (las profesiones de la hermandad, de lo que da el juego: fijadas para la prueba)
    F.Stub(HU, "GuildProfessionCounts", function() return { { name = "Alquimia", n = 3 }, { name = "Sastrería", n = 2 } } end)
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
        A.same({ { name = "Alquimia", n = 3 }, { name = "Sastrería", n = 2 } }, s.professions)
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

    it("fuera de una hermandad, lo dice y no revienta", function()
        local a = F.Community()
        a.w.guild = nil
        A.is_nil(a.HU:GuildStats())
        A.equal("No estás en una hermandad.", a.HU:GuildStatsText())
        A.same({}, a:Errors())
    end)
end)
