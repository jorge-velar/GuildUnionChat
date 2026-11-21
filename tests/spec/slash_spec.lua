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
    "language es",
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
        -- (solo en qué archivo: el texto del error no es el mismo en Lua 5.1 y 5.4. Hoy son los de UI.lua,
        -- que el WoW de mentira no imita entero)
        local function Where(e) return tostring(tostring(e):match("([%w_]+%.lua):%d+") or "?") end
        if not ok then out[#out + 1] = "ERROR en " .. Where(err) end
        if #a:Errors() > errBefore then out[#out + 1] = "ERROR guardado en " .. Where(a:Errors()[#a:Errors()]) end
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

describe("Comandos /gu: registro", function()
    local a, HU
    before_each(function()
        a = F.Community()
        HU = a.HU
    end)

    it("todo comando y alias registrado está en la referencia (INPUTS)", function()
        local tried = {}
        for _, input in ipairs(INPUTS) do tried[(input:match("^(%S*)") or ""):lower()] = true end
        local missing = {}
        for name in pairs(HU.slashCmds) do if not tried[name] then missing[#missing + 1] = name end end
        table.sort(missing)
        A.same({}, missing, "añádelos a INPUTS y rehaz la referencia")
    end)

    it("rechaza nombres, claves y alias repetidos", function()
        local function Fails(name, spec, what)
            local ok, err = pcall(HU.RegisterSlash, HU, name, spec)
            A.falsy(ok, "debía fallar: " .. what)
            A.truthy(tostring(err):find(what, 1, true), "error: " .. tostring(err))
        end
        Fails("Mayus", { fn = print }, "comando no válido")
        Fails("nuevo", { fn = print, ayuda = "x" }, "clave desconocida")
        Fails("nuevo", { fn = "x" }, "fn tiene que ser function")
        Fails("otro", { aliases = { "status" }, fn = print }, "ya registrado")
    end)

    it("un comando sin lo que necesita (available) da la ayuda, y uno nuevo sale en ella", function()
        local ran = false
        HU:RegisterSlash("sinarchivo", { available = function() return false end, fn = function() ran = true end })
        local before = #a.w.chat
        a.env.SlashCmdList.HERMANDADUNIDA("sinarchivo")
        A.falsy(ran)
        A.truthy(#a.w.chat - before > 30, "la ayuda")
        local got
        HU:RegisterSlash("hola", { aliases = { "hi" }, help = "|cffffd100/gu hola|r  saluda", fn = function(arg, raw, cmd) got = { arg, raw, cmd } end })
        a.env.SlashCmdList.HERMANDADUNIDA("HI  Que Tal")
        A.same({ "que tal", "Que Tal", "hola" }, got)
        a.env.SlashCmdList.HERMANDADUNIDA("ayuda")
        A.matches("/gu hola", tostring(a.w.chat[#a.w.chat].msg))
    end)
end)

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
