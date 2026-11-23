-- Zonas en el idioma de cada uno (Net/RosterSync.lua): en las listas de miembros la zona viaja como el número
-- de su mapa («@1429») y cada uno pone el nombre de su juego; la que no está en el mapa va tal cual
local F = require("lib.fixtures")
local A = assert_

-- (el mismo mapa en dos idiomas)
local ES = { { mapID = 1429, name = "Bosque de Elwynn" }, { mapID = 1453, name = "Ventormenta" } }
local EN = { { mapID = 1429, name = "Elwynn Forest" }, { mapID = 1453, name = "Stormwind City" } }

describe("Zonas en el idioma de cada uno", function()
    it("mi lista sale con el número del mapa; la zona que no está en el mapa, tal cual", function()
        local a = F.Community()
        a.w.maps = ES
        a.w.guild.members[1].zone = "Bosque de Elwynn"
        a.w.guild.members[2].zone = "Bastión Krol'dok"
        a.w:Fire("GUILD_ROSTER_UPDATE")
        a.w:Advance(2)
        local lines = table.concat(a.HU:OnlineEntries(), "\n")
        A.matches(",@1429", lines, "por número")
        A.is_nil(lines:find("Bosque de Elwynn", 1, true), "sin el nombre en español")
        A.matches("Bastión Krol'dok", lines, "la que el mapa no tiene, tal cual")
        A.same({}, a:Errors())
    end)

    it("al llegar, el nombre de mi juego (también con el código corto de la lista); un número que no conozco, sin zona", function()
        local a = F.Community()
        a.w.maps = EN
        local HU = a.HU
        A.equal("Elwynn Forest", HU.ParseRosterEntry(HU, "Ana,1,60,4,@1429", "DOS", {}).zone)
        A.equal("Stormwind City", HU.ParseRosterEntry(HU, "Ana,1,60,4,#1,a", "DOS", { ["#1"] = "@1453" }).zone)
        A.equal("Ventormenta", HU.ParseRosterEntry(HU, "Ana,1,60,4,Ventormenta", "DOS", {}).zone, "de antes: tal cual")
        A.is_nil(HU.ParseRosterEntry(HU, "Ana,1,60,4,@9999", "DOS", {}).zone)
        A.same({}, a:Errors())
    end)

    it("una lista de otra hermandad, de un juego en español, sale en inglés en uno en inglés", function()
        local a = F.Community()
        a.w.maps = EN
        local HU = a.HU
        F.Stub(HU, "IsGuildForwarder", true)
        a.w:Receive("HU20B", "ML~DOS~id1~1~1~#1=@1429;Blas,1,60,4,#1", "GUILD", "Compi-Reino")
        local blas
        for _, e in ipairs(HU:UnionRosterEntries()) do if e.name:match("^Blas") then blas = e end end
        A.truthy(blas, "Blas, de DOS")
        A.equal("Elwynn Forest", blas.zone)
        A.same({}, a:Errors())
    end)
end)
