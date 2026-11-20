-- Textos L("…") del addon que no tienen traducción en LocaleEN.lua (hoy solo se ven dentro del
-- juego, con /gu idioma). Desde la carpeta del addon:
--   lua tests/traducciones.lua            lista los que faltan (no falla)
--   lua tests/traducciones.lua --estricto sale con 1 si falta alguno (para el CI, cuando estén todos)
--
-- Solo mira textos escritos tal cual dentro de L("…") o L('…'). Los que se montan por partes
-- (L("Hola ") .. nombre) cuentan por cada parte; los de tablas con HU.LT no se pueden ver así.
local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "tests"
package.path = here .. "/?.lua;" .. package.path
local addon = require("lib.addon")
local strict = arg and arg[1] == "--estricto"

local HU = addon.Load({}).HU
local files = addon.Toc()

-- (el texto de una cadena de Lua tal cual se escribiría: se evalúa para resolver \n, \", \195...)
local function Literal(q, body)
    local fn = addon.LoadWithEnv("return " .. q .. body .. q, "=literal", {})
    local ok, s = pcall(fn or error)
    return ok and s or nil
end

local missing, total, seen = {}, 0, {}
for _, file in ipairs(files) do
    if file ~= "LocaleEN.lua" and not file:match("^Libs/") then
        local src = addon.ReadFile(addon.root .. "/" .. file) or ""
        local n = 0
        for line in (src .. "\n"):gmatch("([^\n]*)\n") do
            n = n + 1
            -- L("...") / L('...'): sin comillas del mismo tipo dentro salvo escapadas
            for q, body in line:gmatch("%f[%w_]L%(%s*([\"'])(.-[^\\])%1%s*[%),]") do
                local s = Literal(q, body)
                if s and not seen[s] then
                    seen[s] = true
                    total = total + 1
                    if HU.EN[s] == nil then missing[#missing + 1] = file .. ":" .. n .. "  " .. s end
                end
            end
        end
    end
end

print(string.format("Textos con L(): %d distintos, %d sin traducción al inglés", total, #missing))
for _, m in ipairs(missing) do print("  " .. m) end
os.exit((strict and #missing > 0) and 1 or 0)
