-- Comandos /gu (Core.lua) y algunas comprobaciones de oficial. Pruebas de caracterización: fijan lo
-- de hoy (el paso 2 de la propuesta pasará los comandos a un registro y estas pruebas lo vigilan).
local F = require("lib.fixtures")
local A = assert_

local a, HU
local function Fresh()
    a = F.Community()
    HU = a.HU
end

-- Ejecuta «/gu …» y devuelve lo que el addon ha escrito en el chat
local function Gu(text)
    local before = #a.w.chat
    a.env.SlashCmdList.HERMANDADUNIDA(text)
    local out = {}
    for i = before + 1, #a.w.chat do out[#out + 1] = tostring(a.w.chat[i].msg) end
    return table.concat(out, "\n")
end

describe("Comandos /gu", function()
    before_each(Fresh)

    it("/gu fase: ya no hay fases, solo lo dice y borra la guardada", function()
        HU.db.phase = "full"
        local out = Gu("fase completa")
        A.matches("solo de chat", out)
        A.is_nil(HU.db.phase)
    end)

    it("/gu confirmar ETIQ: solo un oficial", function()
        F.Stub(HU, "CanOfficer", false)
        A.matches("Solo los oficiales", Gu("confirmar DOS"))
    end)

    it("/gu confirmar sin lista de esa hermandad: no confirma nada", function()
        F.Stub(HU, "CanOfficer", true)
        local before = HU.remoteRoster.DOS
        Gu("confirmar DOS")
        A.equal(before, HU.remoteRoster.DOS)
        A.same({}, a:Errors(), "errores")
    end)
end)

describe("Comprobaciones de oficial y maestro «firmes» (acciones que se quedan)", function()
    before_each(Fresh)

    it("de mi hermandad: el rango manda", function()
        A.truthy(HU:CheckOfficerFirm("Jefa-Reino", "UNO"))
        A.truthy(HU:CheckMasterFirm("Jefa-Reino", "UNO"))
        A.falsy(HU:CheckOfficerFirm("Compi-Reino", "UNO"))
        A.falsy(HU:CheckMasterFirm("Tester-Reino", "UNO"), "oficial, no maestro")
    end)

    it("faltan las listas de conectados de las otras hermandades al empezar", function()
        A.same({ "DOS" }, HU:MissingLists())
    end)
end)

describe("PL: contactos presentados por otro", function()
    before_each(Fresh)

    it("por susurro, de alguien que no es el enlace comprobado de su hermandad: no se acepta", function()
        HU.comm.PL(HU, "Bea-Reino", { "DOS:Bea-Reino" }, "WHISPER", "PL~DOS:Bea-Reino")
        A.is_nil(HU.remote["bea-reino"])
    end)
end)
