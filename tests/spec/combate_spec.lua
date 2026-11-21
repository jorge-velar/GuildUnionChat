-- Combate (Combat.lua): dentro de una instancia y en combate, lo que llega con combat = ... en su
-- HU:RegisterMessage se guarda y se trata al salir; lo demás, ya. Caracteriza lo que hacía antes el
-- envoltorio de HU.comm (DEFER_IN), que ahora llama la entrada (HU.CombatDispatch).
local F = require("lib.fixtures")
local A = assert_

local MATE = "Compi-Reino"

describe("Combate", function()
    local a, HU, w
    before_each(function()
        a = F.Community()
        HU, w = a.HU, a.w
    end)
    local function Enter(kind)
        w.instance = kind
        w:Fire("PLAYER_ENTERING_WORLD")
        w.inCombat = true
        w:Fire("PLAYER_REGEN_DISABLED")
    end
    local function Leave()
        w.inCombat = false
        w:Fire("PLAYER_REGEN_ENABLED")
        w:Advance(1)
    end

    it("en una banda, lo aplazable se guarda (una vez cada copia) y se trata al salir", function()
        local hl, pr = F.Spy(HU, "HL"), F.Spy(HU, "PR")
        Enter("raid")
        A.truthy(HU:CombatHold())
        local stored = HU.combatDiag.stored
        w:Receive("HU20B", "HL~x", "GUILD", MATE)
        w:Receive("HU20B", "HL~x", "GUILD", MATE) -- (la misma copia otra vez: no se guarda dos veces)
        w:Receive("HU20", "PR~x", "GUILD", MATE)  -- (PR no se aplaza)
        A.equal(0, #hl)
        A.equal(1, #pr)
        A.equal(stored + 1, HU.combatDiag.stored)
        Leave()
        A.falsy(HU:CombatHold())
        A.equal(1, #hl)
        A.equal("HL~x", hl[1].text)
        A.equal("GUILD", hl[1].dist)
        A.equal("x", hl[1].f[1])
    end)

    it("las peticiones (req) de más de 15 s se tiran al salir; los datos, no", function()
        local nq, hl = F.Spy(HU, "NQ"), F.Spy(HU, "HL")
        Enter("party")
        w:Receive("HU20", "NQ~DOS", "GUILD", MATE)
        w:Receive("HU20B", "HL~y", "GUILD", MATE)
        w:Advance(20)
        Leave()
        A.equal(0, #nq)
        A.equal(1, #hl)
    end)

    it("de cada uno, la última con los mismos dos primeros campos (last)", function()
        local ph = F.Spy(HU, "PH")
        Enter("raid")
        w:Receive("HU20", "PH~DOS~A~1", "GUILD", MATE)
        w:Receive("HU20", "PH~DOS~A~2", "GUILD", MATE)
        w:Receive("HU20", "PH~DOS~B~1", "GUILD", MATE)
        Leave()
        A.equal(2, #ph)
        A.equal("PH~DOS~A~2", ph[1].text)
        A.equal("PH~DOS~B~1", ph[2].text)
    end)

    it("fuera de una instancia, el combate no aplaza nada", function()
        local hl = F.Spy(HU, "HL")
        Enter(nil)
        A.falsy(HU:CombatHold())
        w:Receive("HU20B", "HL~x", "GUILD", MATE)
        A.equal(1, #hl)
    end)
end)
