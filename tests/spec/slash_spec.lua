-- Comandos /gu, uno por uno: a qué funciones de HU llama cada uno y qué escribe en el chat. Es la
-- referencia para pasar el if/elseif de Core.lua a un registro (paso 2, F) sin que cambie ninguno.
-- Está en tests/golden/comandos.txt; si un cambio es a propósito, se rehace con
--   lua tests/run.lua Comandos --actualizar
-- y el cambio queda a la vista en el diff de la PR.
local runner = require("lib.runner")
local F = require("lib.fixtures")
local A = assert_

local GOLDEN = runner.here .. "/golden/comandos.txt"
local unpack = table.unpack or unpack

-- Todos los comandos y alias de hoy, con argumentos de ejemplo; se ejecutan en este orden sobre la
-- misma copia del addon (lo que cambia uno lo ve el siguiente)
local INPUTS = {
    "", "panel", "lista", "list", "ayuda", "help", "loquesea",
    "estado", "status", "config", "recargar", "reload",
    "canal", "channel", "carril", "lane", "carril reiniciar", "carril subir", "carril juntar", "carril confirmar",
    "fijar", "pin", "fijar Hola a todos", "fijar borrar", "test", "test Prueba de fijado", "test off",
    "etiqueta on", "tag off", "pintar on", "paint off", "guardia revisar", "guard review", "guardia off", "guardia on",
    "margen 120", "margin 5", "margen", "rol tank", "role healer", "rol dps", "rol auto", "rol nada",
    "minimapa off", "minimap on", "debug on", "debug off",
    "errores", "errors", "errores borrar", "errores pedir", "errores pedir clave",
    "diag", "memoria", "memory", "cola", "queue", "cola vaciar",
    "ordenes", "órdenes", "idioma", "lang en", "idioma es",
    "buscar", "search Compi", "historial", "history off", "historial on",
    "registro", "nota algo", "fase", "phase completa",
    "confirmar", "confirm DOS", "confirmar UNO", "confirmar dos",
    "version", "version Compi-Reino", "versión Nadie-Reino",
    "sonda 5", "probe", "visto Compi", "seen", "prat", "prat off", "wm",
    "prueba Compi", "ids", "todo", "informe", "all", "report",
    "invitaciones", "invites", "listanegra", "blacklist",
    "hermandad", "guild", "tecla on", "key off", "hermandades", "guilds",
    "asistente", "wizard prueba", "crear", "create",
    "invitar", "invitar Jefa-Reino TRES", "invite Nadie",
    "gestor", "gestor Compi-Reino", "manager remove Compi-Reino", "gestores", "managers",
    "quitarhermandad", "removeguild TRES",
    "notacanal", "channelnote", "pasarcanal", "sendchannel Compi-Reino", "perf",
}

-- Y otra vez, ahora como oficial (CanOfficer), los que tienen una rama para oficiales
local AS_OFFICER = {
    "errores pedir", "errores pedir clave", "confirmar", "confirm DOS", "confirmar UNO", "confirmar dos",
    "carril", "carril reiniciar", "carril confirmar", "sonda 5", "fijar Hola", "guardia revisar",
}

-- Envuelve las funciones de HU (y de HU.UI) para apuntar las que llama el comando directamente
-- (las de dentro de esas, no: dependen de cómo esté hecha cada una por dentro)
local function Spy(HU)
    local log, depth = {}, 0
    local function Wrap(t, prefix)
        for k, v in pairs(t) do
            if type(v) == "function" and type(k) == "string" then
                t[k] = function(...)
                    if depth == 0 then log[#log + 1] = prefix .. k end
                    depth = depth + 1
                    local r = { pcall(v, ...) }
                    depth = depth - 1
                    if not r[1] then error(r[2], 0) end
                    return unpack(r, 2)
                end
            end
        end
    end
    Wrap(HU, "")
    if type(HU.UI) == "table" then Wrap(HU.UI, "UI.") end
    return log
end

local function Run(inputs, officer, out)
    local a = F.Community()
    local HU, w = a.HU, a.w
    if officer then
        F.Stub(HU, "CanOfficer", true)
        F.Stub(HU, "IsOfficerName", true)
        out[#out + 1] = "======== como oficial ========"
    end
    local log = Spy(HU)
    for _, input in ipairs(inputs) do
        for i = #log, 1, -1 do log[i] = nil end
        local before = #w.chat
        local errBefore = #a:Errors()
        local ok, err = pcall(a.env.SlashCmdList.HERMANDADUNIDA, input)
        out[#out + 1] = "== /gu " .. input
        -- (sin repetidos seguidos: Print tres veces es lo mismo que dos para esta prueba)
        local calls, last = {}, nil
        for _, c in ipairs(log) do if c ~= last then calls[#calls + 1] = c; last = c end end
        out[#out + 1] = "llama: " .. table.concat(calls, " ")
        for i = before + 1, #w.chat do out[#out + 1] = "dice: " .. tostring(w.chat[i].msg) end
        if not ok then out[#out + 1] = "ERROR: " .. tostring(err):gsub("^[^:]+:%d+: ", "") end
        if #a:Errors() > errBefore then out[#out + 1] = "ERROR guardado: " .. tostring(a:Errors()[#a:Errors()]) end
        w:Advance(1)
    end
    return out
end
local function RunAll()
    local out = Run(INPUTS, false, {})
    return Run(AS_OFFICER, true, out)
end

local function ReadGolden()
    local f = io.open(GOLDEN, "rb")
    if not f then return nil end
    local lines = {}
    for line in f:lines() do
        line = line:gsub("\r$", "")
        if not line:match("^#") then lines[#lines + 1] = line end
    end
    f:close()
    return lines
end
local function WriteGolden(lines)
    local f = assert(io.open(GOLDEN, "wb"))
    f:write("# Qué hace cada /gu (tests/spec/slash_spec.lua): a qué funciones de HU llama directamente y qué\n")
    f:write("# escribe en el chat, en orden. Se rehace con:  lua tests/run.lua Comandos --actualizar\n")
    for _, l in ipairs(lines) do f:write(l, "\n") end
    f:close()
end

describe("Comandos /gu: referencia", function()
    it("cada comando hace lo mismo que en tests/golden/comandos.txt", function()
        local now = RunAll()
        local golden = ReadGolden()
        if runner.update or not golden then
            WriteGolden(now)
            print("\n(comandos: referencia guardada en " .. GOLDEN .. ")")
            return
        end
        for i = 1, math.max(#now, #golden) do
            if now[i] ~= golden[i] then
                local cmd
                for j = i, 1, -1 do cmd = (now[j] or ""):match("^== (.*)$") if cmd then break end end
                A.equal(golden[i], now[i], "en «" .. tostring(cmd) .. "» (línea " .. i .. ")")
            end
        end
    end)
end)
