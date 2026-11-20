-- El addon entero se carga y arranca sin errores en un WoW de mentira
local addon = require("lib.addon")
local A = assert_

local GUILD = { name = "Hermandad Uno", rank = "Oficial", rankIndex = 1, members = {
    { name = "Tester-Reino", rankIndex = 1 },
    { name = "Compi-Reino", rankIndex = 4 },
} }

describe("Carga", function()
    it("todos los archivos del .toc se cargan", function()
        local a = addon.Load({ guild = GUILD })
        A.truthy(a.HU.comm, "HU.comm")
        A.truthy(a.HU.db, "HU.db tras ADDON_LOADED")
    end)

    it("arranca (PLAYER_LOGIN) y pasa un minuto sin errores guardados", function()
        local a = addon.Load({ guild = GUILD }):Login(60)
        A.same({}, a:Errors(), "errores en /gu errores")
    end)

    it("las órdenes del protocolo tienen manejador", function()
        local a = addon.Load({ guild = GUILD })
        local n = 0
        for cmd, fn in pairs(a.HU.comm) do
            A.matches("^%u%u?$", cmd, "nombre de orden")
            A.equal("function", type(fn), cmd)
            n = n + 1
        end
        A.truthy(n > 30, "se esperaban más de 30 órdenes y hay " .. n)
    end)

    it("CW, CG y CF se registran al entrar al juego, no al cargar (orden del .toc)", function()
        -- (diagnóstico #4: Channel.lua va antes que Comm.lua, que crea HU.comm. Al arreglarlo, esta
        -- prueba cambia: entonces deben estar ya al cargar)
        local a = addon.Load({ guild = GUILD })
        A.is_nil(a.HU.comm.CW)
        a:Login(5)
        A.equal("function", type(a.HU.comm.CW))
    end)
end)
