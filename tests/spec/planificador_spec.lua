-- Planificador (Core.lua, HU:Every): todo lo que se repite pasa por él, con nombre y su cuenta de
-- tiempo para /gu perf. Fija que hace lo mismo que el HU.NewTicker de antes (cada cuánto, cuántas
-- veces, un error no lo rompe) y lo que añade (pausa en combate, tope de fallos).
local F = require("lib.fixtures")
local A = assert_

describe("Planificador (HU:Every)", function()
    local a, HU, w
    before_each(function()
        a = F.Community()
        HU, w = a.HU, a.w
    end)

    it("cada cuánto y cuántas veces, como el temporizador del juego", function()
        local n = 0
        HU:Every(2, "prueba", function() n = n + 1 end)
        w:Advance(7)
        A.equal(3, n)
        local m = 0
        HU:Every(1, "prueba-veces", function() m = m + 1 end, { times = 2 })
        w:Advance(5)
        A.equal(2, m)
        A.equal(6, n, "la primera ha seguido: 12 s, cada 2")
        A.equal(n, HU.tasks.prueba.n)
    end)

    it("un error no lo para (se guarda con el nombre de la tarea), salvo con maxFailures", function()
        local n = 0
        HU:Every(1, "falla", function() n = n + 1; error("mal") end)
        w:Advance(3)
        A.equal(3, n)
        A.equal(3, HU.tasks.falla.fails)
        A.matches("%[falla%]", table.concat(a:Errors(), "\n"))
        local k = 0
        HU:Every(1, "falla-tope", function() k = k + 1; error("mal") end, { maxFailures = 2 })
        w:Advance(5)
        A.equal(2, k)
        A.truthy(HU.tasks["falla-tope"].off)
    end)

    it("pauseInCombat: no se hace mientras dura el combate", function()
        local n, hold = 0, false
        F.Stub(HU, "CombatHold", function() return hold end)
        HU:Every(1, "fuera-de-combate", function() n = n + 1 end, { pauseInCombat = true })
        w:Advance(2)
        hold = true
        w:Advance(3)
        hold = false
        w:Advance(1)
        A.equal(3, n)
        A.equal(3, HU.tasks["fuera-de-combate"].skipped)
    end)

    it("devuelve el temporizador: :Cancel() lo para", function()
        local n = 0
        local t = HU:Every(1, "cancelable", function() n = n + 1 end)
        w:Advance(2)
        t:Cancel()
        w:Advance(3)
        A.equal(2, n)
    end)

    it("sin nombre o sin función, error", function()
        A.falsy(pcall(HU.Every, HU, 1, nil, function() end))
        A.falsy(pcall(HU.Every, HU, 1, "sin-funcion"))
    end)

    it("al entrar están las tareas del addon, y /gu perf las enseña", function()
        for _, name in ipairs({ "cola-cupo", "listas-ciclo", "guardia", "lista-hermandad", "canal-entrar", "historial-cupo" }) do
            A.truthy(HU.tasks[name], name)
        end
        A.truthy(HU.tasks["cola-cupo"].n > 30, "la cola recupera cupo cada segundo")
        local lines = table.concat(HU:TaskLines(), "\n")
        A.matches("cola%-cupo%s+cada 1s", lines)
        HU.Perf.Start()
        A.matches("Tareas que se repiten", HU.Perf.Report())
        HU.Perf.Stop()
    end)
end)
