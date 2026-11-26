-- Listas de las hermandades (Lists.lua) y la raza y profesiones de los demás (PB, Social.lua).
-- Pruebas de caracterización: fijan lo de hoy, sin las listas completas (HU.whitelist) que quitó
-- ReduceClean.
local F = require("lib.fixtures")
local red = require("lib.red")
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

-- Jorge, 27/11: «cada vez que desloguea le llega eso a alguien… no revisa si está conectado». Un oficial (o el GM) sale
-- del juego y a alguien de otra hermandad le salen varios «No player named…». Su «me voy» (RC con la huella de base a
-- 0, Presence.lua) le dejaba como contacto recién visto y, si la copia del otro no cuadraba, se le pedía la lista
-- entera (RF) cuando ya no estaba (Net/RosterSync.lua)
describe("El «me voy» de quien sale del juego", function()
    it("nadie le susurra después, aunque su copia no cuadre; toda la unión le da por ido, y al volver se le oye", function()
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
        for _, x in ipairs({ { p.ana, "DOS", "TRES" }, { p.bea, "UNO", "TRES" }, { p.tere, "UNO", "DOS" } }) do
            x[1].HU:ConfirmRoster(x[2])
            x[1].HU:ConfirmRoster(x[3])
        end
        net:Advance(300)
        -- (la copia de DOS que tiene Ana no cuadra: le falta Blas. Así, al llegar el «me voy», antes se le pedía a Bea)
        local r = p.ana.HU.remoteRoster.DOS
        for i = #r.members, 1, -1 do if r.members[i].name == "Blas-Reino" then table.remove(r.members, i) end end
        -- (lo que intentan mandarle por susurro: el RF, y lo que de verdad sale hacia ella)
        local rf, sent = 0, 0
        local others = { "ana", "alba", "blas", "tere", "toni" }
        for _, n in ipairs(others) do
            local q = p[n]
            local real = q.HU.Whisper
            q.HU.Whisper = function(self, target, msg, ...)
                if type(target) == "string" and target:lower():find("^bea") and msg:match("^RF~") then rf = rf + 1 end
                return real(self, target, msg, ...)
            end
            q.w.failSend = function(_, _, dist, target)
                if dist == "WHISPER" and type(target) == "string" and target:lower():find("^bea") and not p.bea.online then
                    sent = sent + 1
                end
            end
        end
        local i0 = #net.log
        p.bea.w:Fire("PLAYER_QUITING")
        net:Advance(1)
        -- (su «me voy» ha salido hacia Ana y Tere, y a Ana su copia no le ha cuadrado)
        local byes = {}
        for i = i0 + 1, #net.log do
            local m = net.log[i]
            if m.from == p.bea and m.text:match("^RC~DOS~0~") then byes[#byes + 1] = m.target end
        end
        table.sort(byes)
        A.same({ "Ana-Reino", "Tere-Reino" }, byes)
        A.truthy((r.deltaMiss or 0) > 0, "la copia de Ana no cuadraba")
        net:Logout(p.bea)
        net:Advance(60)
        A.equal(0, rf, "no se le pide la lista entera a quien se va")
        A.equal(0, sent, "nada le sale cuando ya no está")
        -- (le dan por ido las otras hermandades (el «me voy», y su reenvío a cada hermandad) y la suya (PV))
        for _, n in ipairs(others) do A.truthy(p[n].HU:KnownOffline("Bea-Reino"), n) end
        -- (vuelve: en cuanto le oyen, se le vuelve a susurrar)
        net:Login(p.bea)
        net:Advance(120)
        A.falsy(p.ana.HU:KnownOffline("Bea-Reino"))
        A.same({}, net:Errors())
    end)
end)
