-- Metatabla estricta (Core.lua, HU:StrictMode): ninguna prueba de esta ejecución ha leído un campo de
-- HU que no existe y no está en HU.MAYBE_NIL. Va la ÚLTIMA en tests/run.lua para ver lo de todas.
-- Si falla: o es un nombre mal escrito (se arregla), o es estado que empieza vacío (se añade a
-- HU.MAYBE_NIL en Core.lua).
local addon = require("lib.addon")
local A = assert_

describe("Metatabla estricta", function()
    it("ningún campo de HU leído sin existir (fuera de HU.MAYBE_NIL)", function()
        local all = {}
        for _, miss in ipairs(addon.strictMisses) do
            for k, where in pairs(miss) do
                -- (lo que leen las propias pruebas no cuenta: solo el addon)
                if not tostring(where):find("spec", 1, true) then all[tostring(k)] = where end
            end
        end
        local list = {}
        for k, where in pairs(all) do list[#list + 1] = k .. " (" .. tostring(where) .. ")" end
        table.sort(list)
        A.same({}, list, "campos de HU que no existen")
        A.truthy(#addon.strictMisses > 50, "se esperaban muchas copias cargadas y hay " .. #addon.strictMisses)
    end)
end)
