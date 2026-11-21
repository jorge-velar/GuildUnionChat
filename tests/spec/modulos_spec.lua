-- Módulos (Core.lua, HU:Module y HU:CheckModules) y avisos entre módulos (HU:Listen y HU:Fire).
-- Cada archivo acaba declarando qué otros necesita: los que definen las funciones de HU que llama
-- (tests/lib/modulos.lua). Una dependencia nueva hay que declararla, y así se ve en la PR.
local runner = require("lib.runner")
local modulos = require("lib.modulos")
local F = require("lib.fixtures")
local A = assert_

describe("Módulos", function()
    it("cada archivo acaba con su HU:Module y lo que necesita de verdad", function()
        local files, need, src = modulos.Compute(runner.here .. "/..")
        local wrong = {}
        for _, f in ipairs(files) do
            local last = src[f]:match("([^\n]*)\n*$")
            local want = modulos.Line(f, need[f])
            if last ~= want then wrong[#wrong + 1] = f .. "\n      está: " .. last .. "\n   debería: " .. want end
        end
        A.same({}, wrong, "rehazlas con el cálculo de tests/lib/modulos.lua")
        A.truthy(#files > 40)
    end)

    it("al entrar han cargado todos, y lo comprueba el núcleo", function()
        local a = F.Community()
        local HU = a.HU
        local files = modulos.Compute(runner.here .. "/..")
        local n = 0
        for _ in pairs(HU.modules) do n = n + 1 end
        A.equal(#files, n)
        A.truthy(HU:CheckModules())
        A.same({}, a:Errors())
    end)

    it("si un archivo no ha cargado entero, lo dice en /gu errores con quién lo necesita", function()
        local a = F.Community()
        local HU = a.HU
        HU.modules.Guard = nil
        A.falsy(HU:CheckModules())
        local errs = table.concat(a:Errors(), "\n")
        A.matches("Guard%.lua no ha cargado entero", errs)
        A.matches("Net/Security", errs)
        A.falsy(pcall(HU.Module, HU, "Core", {}), "un módulo repetido es un error")
    end)
end)

describe("Avisos entre módulos (HU:Listen / HU:Fire)", function()
    it("llegan a todos los que escuchan, en orden y con sus datos; un fallo no para a los demás", function()
        local HU = F.Community().HU
        local got = {}
        HU:Listen("PRUEBA", function(x, y) got[#got + 1] = "1:" .. x .. y end)
        HU:Listen("PRUEBA", function() error("mal") end)
        HU:Listen("PRUEBA", function(x) got[#got + 1] = "3:" .. x end)
        HU:Fire("PRUEBA", "a", "b")
        HU:Fire("NADIE_ESCUCHA", 1)
        A.same({ "1:ab", "3:a" }, got)
    end)

    it("HU:Changed avisa con CHANGED (lo escucha la interfaz)", function()
        local HU = F.Community().HU
        local got
        HU:Listen("CHANGED", function(what) got = what end)
        HU:Changed("members")
        A.equal("members", got)
    end)
end)
