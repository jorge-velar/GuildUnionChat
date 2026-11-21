-- Comprobaciones de que una función de HU existe antes de llamarla («HU.X and HU:X(», «if HU.X then
-- HU:X() end», lo mismo con self): todos los archivos del .toc se cargan siempre, en orden, y
-- Core.lua comprueba al arrancar que han cargado todos los módulos (HU:Module). Si X se define a nivel
-- superior de algún archivo, la comprobación sobra, y además esconde los nombres mal escritos (la
-- llamada no se hace nunca, sin avisar). Solo valen las de JUSTIFIED, con su motivo.
local runner = require("lib.runner")
local addon = require("lib.addon")
local A = assert_

local JUSTIFIED = {
    -- (la crea BlizzTab.lua cuando el juego carga su ventana de hermandad: antes no existe)
    SyncCharSearch = true,
}

local function Read(path)
    local f = assert(io.open(runner.here .. "/../" .. path, "rb"))
    local s = f:read("*a"); f:close()
    return (s:gsub("\r\n", "\n"))
end

describe("Comprobaciones de funciones de HU", function()
    it("ninguna sobre una función que siempre existe (salvo las justificadas)", function()
        local files = {}
        for _, f in ipairs(addon.LuaFiles()) do if not f:match("^Libs/") then files[#files + 1] = f end end
        local src, always = {}, {}
        for _, f in ipairs(files) do
            src[f] = Read(f)
            for l in (src[f] .. "\n"):gmatch("([^\n]*)\n") do
                local x = l:match("^function HU[:.]([%w_]+)") or l:match("^HU%.([%w_]+)%s*=%s*function")
                    or l:match("^HU%.([%w_]+)%s*=%s*[%a_][%w_]*%s*$")
                if x then always[x] = true end
            end
        end
        local found = {}
        for _, f in ipairs(files) do
            local n = 0
            for l in (src[f] .. "\n"):gmatch("([^\n]*)\n") do
                n = n + 1
                local code = l:gsub("%-%-.*$", "")
                for r1, x, r2 in code:gmatch("(%f[%w_]%a+)%.([%u][%w_]*) and (%a+)[:.]%2%(") do
                    if (r1 == "HU" or r1 == "self") and r1 == r2 and always[x] and not JUSTIFIED[x] then
                        found[#found + 1] = f .. ":" .. n .. " " .. x
                    end
                end
                -- (solo si la misma línea la llama: «if HU.UI then» mira una tabla, no una función)
                for r, x in code:gmatch("if (%a+)%.([%u][%w_]*) then") do
                    local calls = code:find(r .. ":" .. x .. "(", 1, true) or code:find(r .. "." .. x .. "(", 1, true)
                    if (r == "HU" or r == "self") and calls and always[x] and not JUSTIFIED[x] then
                        found[#found + 1] = f .. ":" .. n .. " " .. x
                    end
                end
            end
        end
        A.same({}, found, "llama directamente (o justifícala en JUSTIFIED)")
        A.truthy(always.Send and always.RegisterMessage and always.Every, "no se han leído las definiciones")
    end)
end)
