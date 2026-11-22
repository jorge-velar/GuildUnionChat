-- Pruebas de Guild Union. Desde la carpeta del addon:
--   lua tests/run.lua                         todas
--   lua tests/run.lua Comm                    solo las que llevan «Comm» en el nombre
--   lua tests/run.lua Formato --actualizar    rehace las referencias (tests/golden/) en vez de compararlas
-- El CI las pasa con Lua 5.1, que es el Lua de WoW (ver .github/workflows/ci.yml).
local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "tests"
package.path = here .. "/?.lua;" .. package.path

local runner = require("lib.runner")
for _, a in ipairs(arg or {}) do
    if a == "--actualizar" then runner.update = true
    elseif not runner.filter then runner.filter = a end
end
runner.here = here

-- (las globales que usan los archivos de pruebas, como en busted)
describe, it, before_each, pending, assert_ = runner.describe, runner.it, runner.before_each, runner.pending, runner.assert

local SPECS = {
    "spec/carga_spec",
    "spec/utilidades_spec",
    "spec/seguridad_spec",
    "spec/cola_spec",
    "spec/red_spec",
    "spec/formato_spec",
    "spec/chat_spec",
    "spec/listas_spec",
    "spec/comandos_spec",
    "spec/slash_spec",
    "spec/registro_spec",
    "spec/combate_spec",
    "spec/datos_spec",
    "spec/escenarios_spec",
    "spec/planificador_spec",
    "spec/guardas_spec",
    "spec/modulos_spec",
    "spec/protocolo_spec",
    "spec/strict_spec", -- (la última: mira lo que han leído todas las demás)
}
for _, name in ipairs(SPECS) do
    local fn, err = loadfile(here .. "/" .. name .. ".lua")
    if not fn then
        runner.results.fail = runner.results.fail + 1
        runner.failures[#runner.failures + 1] = { name = name, err = "no compila: " .. tostring(err) }
    else
        local ok, e = pcall(fn)
        if not ok then
            runner.results.fail = runner.results.fail + 1
            runner.failures[#runner.failures + 1] = { name = name, err = tostring(e) }
        end
    end
end

os.exit(runner.report() and 0 or 1)
