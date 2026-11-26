-- Estadísticas de la hermandad (GuildStats.lua), para oficiales y el maestro: miembros, rangos, niveles, clases y
-- actividad, en una ventana para copiar y pegar en Discord o en un archivo
local F = require("lib.fixtures")
local A = assert_

local function Has(text, s) A.truthy(tostring(text):find(s, 1, true), "falta «" .. s .. "» en:\n" .. tostring(text)) end
local function Lacks(text, s) A.falsy(tostring(text):find(s, 1, true), "sobra «" .. s .. "» en:\n" .. tostring(text)) end
-- (lo que el addon escribe en el chat desde i0)
local function Said(a, i0)
    local out = {}
    for i = i0 + 1, #a.w.chat do out[#out + 1] = tostring(a.w.chat[i].msg) end
    return table.concat(out, "\n")
end

-- (una hermandad de prueba con niveles, clases, rangos, conectados e inactivos a mano, y altas/bajas en el registro)
local function Stats(a)
    local HU = a.HU
    local now = a.env.time()
    HU.rosterList = {
        { name = "Jefa-Reino", rank = "Maestra", rankIndex = 0, level = 60, class = "Druida", online = true },
        { name = "Tester-Reino", rank = "Oficial", rankIndex = 1, level = 60, class = "Mago", online = true },
        { name = "Compi-Reino", rank = "Miembro", rankIndex = 4, level = 45, class = "Mago", online = false, offSecs = 10 * 86400 },
        { name = "Nuevo-Reino", rank = "Miembro", rankIndex = 4, level = 15, class = "Guerrero", online = true, mobile = true },
        { name = "Viejo-Reino", rank = "Miembro", rankIndex = 4, level = 60, class = "Druida", online = false, offSecs = 40 * 86400 },
    }
    HU.db.inviteLog = { ["Hermandad Uno"] = {
        { t = now - 1 * 86400, who = "A-Reino" }, { t = now - 3 * 86400, who = "B-Reino" },
        { t = now - 20 * 86400, who = "C-Reino" }, { t = now - 50 * 86400, who = "D-Reino" },
    } }
    HU.db.leaveLog = { ["Hermandad Uno"] = {
        { t = now - 2 * 86400, who = "X-Reino" }, { t = now - 40 * 86400, who = "Y-Reino" },
    } }
    return HU
end

describe("Estadísticas de la hermandad (GuildStats.lua)", function()
    it("cuenta miembros, rangos, niveles, clases, altas/bajas e inactivos", function()
        local a = F.Community()
        local HU = Stats(a)
        local s = HU:GuildStats()
        A.equal("Hermandad Uno", s.guild)
        A.same({ 5, 3, 1 }, { s.total, s.online, s.mobile }, "total, conectados, móvil")
        -- (rangos, del más alto al más bajo, con cuántos conectados)
        A.same({ { name = "Maestra", total = 1, online = 1 }, { name = "Oficial", total = 1, online = 1 },
            { name = "Miembro", total = 3, online = 1 } }, s.byRank)
        -- (niveles: máximo, media y tramos)
        A.same({ 60, 48 }, { s.maxLevel, s.avgLevel }, "máximo y media")
        A.same({ { "1-19", 1 }, { "20-39", 0 }, { "40-59", 1 }, { "60", 3 } }, s.levelBuckets)
        -- (clases, de más a menos; empate por nombre)
        A.same({ { name = "Druida", n = 2 }, { name = "Mago", n = 2 }, { name = "Guerrero", n = 1 } }, s.byClass)
        -- (altas y bajas, de los últimos 7 y 30 días; lo de hace 50 y 40 días no cuenta)
        A.same({ 2, 3, 1, 1 }, { s.joined7, s.joined30, s.left7, s.left30 })
        -- (inactivos: Compi 10 días y Viejo 40 días pasan de 7; solo Viejo pasa de 30)
        A.same({ 2, 1 }, { s.inactive7, s.inactive30 })
        A.same({}, a:Errors())
    end)

    it("el texto es llano (sin colores), con sus secciones, listo para Discord o un archivo", function()
        local a = F.Community()
        local HU = Stats(a)
        local text = HU:GuildStatsText()
        Has(text, "Guild Union - Estadísticas de Hermandad Uno - ")
        Has(text, "Miembros: 5  ·  conectados: 3  ·  con el móvil: 1")
        Has(text, "Por rango:")
        Has(text, "Maestra")
        Has(text, "Niveles: máximo 60  ·  media 48.0  ·  al 60: 3")
        Has(text, "Clases:")
        Has(text, "Druida")
        Has(text, "Altas: 2 (7 días)  ·  3 (30 días)")
        Has(text, "Bajas: 1 (7 días)  ·  1 (30 días)")
        Has(text, "Sin conectarse: 2 (más de 7 días)  ·  1 (más de 30 días)")
        -- (nada de códigos de color del juego: se pega limpio)
        Lacks(text, "|cff")
        Lacks(text, "|r")
        A.same({}, a:Errors())
    end)

    it("la ventana para copiar; solo la ven los oficiales y el maestro", function()
        local a = F.Community()
        local HU = Stats(a)
        local c = {}
        HU.UI.ShowCopy = function(_, title, text, opts) c.title, c.text, c.opts = title, text, opts end
        -- (Tester es oficial: ve la ventana)
        A.truthy(HU:CanSeeStats())
        HU:ShowGuildStats()
        A.equal("Estadísticas de la hermandad", c.title)
        Has(c.text, "Miembros: 5")
        Has(c.opts.hint, "pégalo en Discord o en un archivo de texto")
        -- (un miembro de a pie, no: se le dice)
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
