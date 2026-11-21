-- Listas de las hermandades (Lists.lua) y la raza y profesiones de los demás (PB, Social.lua).
-- Pruebas de caracterización: fijan lo de hoy, sin las listas completas (HU.whitelist) que quitó
-- ReduceClean.
local F = require("lib.fixtures")
local A = assert_

local a, HU
local function Fresh()
    a = F.Community()
    HU = a.HU
end

-- Una lista de conectados de DOS con estos nombres, como la deja una RB ya aplicada
local function RosterDOS(names)
    local members, byKey = {}, {}
    for _, n in ipairs(names) do
        local m = { name = n, rankIndex = 4 }
        members[#members + 1] = m
        byKey[n:lower()] = m
    end
    HU.remoteRoster.DOS = { members = members, byKey = byKey, total = #members, online = #members, updated = a.w.now }
end

describe("Listas: de quién se sabe que es de una hermandad", function()
    before_each(Fresh)

    it("la lista completa solo existe para mi hermandad", function()
        A.truthy(HU:ListFresh("UNO"), "la mía, de la lista de la hermandad")
        A.falsy(HU:ListFresh("DOS"), "de las otras no hay")
        A.is_nil(HU:ListFor("DOS"))
    end)

    it("InAnyGuild y MemberOf: los de mi hermandad y los conectados de las otras", function()
        A.truthy(HU:InAnyGuild("Compi-Reino"))
        A.falsy(HU:InAnyGuild("Bea-Reino"))
        RosterDOS({ "Bea-Reino" })
        A.truthy(HU:InAnyGuild("Bea-Reino"))
        A.truthy(HU:MemberOf("Bea-Reino", "DOS"))
        A.falsy(HU:MemberOf("Bea-Reino", "UNO"), "es de DOS, no de UNO")
    end)

    it("oficial o maestro de otra hermandad que aún no conozco: «unknown» (se espera a tener su lista)", function()
        local ok, why = HU:TrustedOfficer("Bea-Reino", "DOS")
        A.falsy(ok)
        A.equal("unknown", why)
        ok, why = HU:TrustedMaster("Bea-Reino", "DOS")
        A.falsy(ok)
        A.equal("unknown", why)
    end)

    it("de una hermandad que no es de la comunidad: no, sin esperar", function()
        local ok, why = HU:TrustedOfficer("Otro-Reino", "TRES")
        A.falsy(ok)
        A.is_nil(why)
    end)

    it("en mi hermandad, por su rango", function()
        A.truthy(HU:TrustedOfficer("Jefa-Reino", "UNO"), "la maestra")
        A.truthy(HU:TrustedMaster("Jefa-Reino", "UNO"))
        A.falsy(HU:TrustedOfficer("Compi-Reino", "UNO"), "un miembro")
    end)
end)

describe("PB: raza y profesiones de otra hermandad", function()
    before_each(Fresh)

    it("sin su lista de conectados, se guarda la de cualquiera que venga", function()
        HU.comm.PB(HU, "Bea-Reino", { "DOS", "Bea-Reino:Human:1:2:Herrería" }, "GUILD", "PB~DOS~Bea-Reino:Human:1:2:Herrería")
        local p = HU.db.profiles["bea-reino"]
        A.truthy(p, "guardado")
        A.equal("Human", p.race)
        A.equal("Herrería", p.p)
    end)

    it("con su lista, solo la de quien sale en ella", function()
        RosterDOS({ "Bea-Reino" })
        HU.comm.PB(HU, "Bea-Reino", { "DOS", "Bea-Reino:Human:::;Intruso-Reino:Orc:::" }, "GUILD", "")
        A.truthy(HU.db.profiles["bea-reino"])
        A.is_nil(HU.db.profiles["intruso-reino"])
    end)

    it("de mi propia hermandad o de una que no es de la comunidad: nada", function()
        HU.comm.PB(HU, "Bea-Reino", { "UNO", "Bea-Reino:Human:::" }, "GUILD", "")
        HU.comm.PB(HU, "Bea-Reino", { "TRES", "Otro-Reino:Human:::" }, "GUILD", "")
        A.is_nil(HU.db.profiles["bea-reino"])
        A.is_nil(HU.db.profiles["otro-reino"])
    end)
end)
