-- Formato de los mensajes de red, con un rato de juego fijo (tests/lib/escenario.lua):
--   1. Referencia: la FORMA de cada mensaje (cuántos campos y de qué tipo) no cambia sin querer.
--      Está en tests/golden/formato.txt; si un cambio es a propósito, se rehace con
--        lua tests/run.lua Formato --actualizar
--      y el cambio queda a la vista en el diff de la PR.
--   2. Ida y vuelta: todo lo que manda una copia del addon lo acepta la seguridad de alguna otra.
--   3. Versiones mezcladas: la de la carpeta y la última publicada (etiqueta de git) se entienden.
local runner = require("lib.runner")
local escenario = require("lib.escenario")
local addon = require("lib.addon")
local A = assert_

local GOLDEN = runner.here .. "/golden/formato.txt"
local TAGS = { UNO = true, DOS = true }

-- Órdenes que hoy ninguna otra copia acepta en el escenario, con el motivo. Una orden nueva que no
-- acepta nadie hace fallar la prueba: o es un fallo, o se apunta aquí con su motivo.
local NOBODY_ACCEPTS = {
    -- (raza y profesiones: sale a la vez que la primera lista, cuando quien la recibe todavía no se
    -- fía del remitente; no se retiene como RB y no se repite en un buen rato. Hallazgo del 21/11/2026,
    -- pendiente de decidir si se retiene o se manda después de la lista)
    PB = "sale con la primera lista, antes de que el otro se fíe; no se retiene",
}

---------------------------------------------------------------------------
-- La forma de un mensaje
---------------------------------------------------------------------------
-- Cada trozo entre separadores pasa a su tipo: <ver> versión, <n> número, <x> huella o marca de
-- tiempo, <nombre> jugador, <etiq> hermandad. El texto libre (motivos, chat) se queda tal cual.
local function Token(t)
    if t == "" then return t end
    if t:match("^%d+%.%d+%.%d+$") then return "<ver>" end
    if t:match("^%-?[%d%.]+$") then return "<n>" end
    if TAGS[t] then return "<etiq>" end
    local sign, name = t:match("^([%+%-]?)(%u%l+%-%u%l+)$")
    if name then return sign .. "<nombre>" end
    if #t >= 6 and t:match("^[%l%d%.]+$") and t:match("%d") and t:match("%l") then return "<x>" end
    return t
end
local function Shape(text)
    local s = text:gsub("[^~,;:#%s%[%]]+", Token)
    -- (las listas valen con cualquier número de elementos y en cualquier orden: cada elemento distinto
    -- una vez, ordenados)
    s = s:gsub("[^~]+", function(field)
        if not field:find(";", 1, true) then return field end
        local seen, items = {}, {}
        for it in (field .. ";"):gmatch("([^;]*);") do
            if not seen[it] then seen[it] = true; items[#items + 1] = it end
        end
        table.sort(items)
        return table.concat(items, ";")
    end)
    repeat local n; s, n = s:gsub("<nombre>,<nombre>", "<nombre>") until n == 0
    return s
end

-- Todas las formas del escenario: { ["HU20 HI GUILD  HI~<ver>~…"] = true }
local function Shapes(net)
    local set = {}
    for _, m in ipairs(net.log) do
        local cmd = m.text:match("^(%u%u?)~?") or "?"
        set[string.format("%-5s %-2s %-7s %s", m.prefix, cmd, m.dist, Shape(m.text))] = true
    end
    return set
end

local function ReadGolden()
    local f = io.open(GOLDEN, "rb")
    if not f then return nil end
    local set = {}
    for line in f:lines() do
        line = line:gsub("\r$", "")
        if line ~= "" and not line:match("^#") then set[line] = true end
    end
    f:close()
    return set
end
local function WriteGolden(set)
    local list = {}
    for k in pairs(set) do list[#list + 1] = k end
    table.sort(list)
    local f = assert(io.open(GOLDEN, "wb"))
    f:write("# Forma de cada mensaje de red del escenario de tests/lib/escenario.lua (prefijo, orden, vía).\n")
    f:write("# <ver> versión, <n> número, <x> huella o marca de tiempo, <nombre> jugador, <etiq> hermandad;\n")
    f:write("# las listas (;) con cada elemento distinto una vez. Se rehace con:\n")
    f:write("#   lua tests/run.lua Formato --actualizar\n")
    for _, k in ipairs(list) do f:write(k, "\n") end
    f:close()
end

-- Órdenes de HU20/HU20B que alguien manda y nadie más acepta
local function NobodyAccepts(net, players)
    local sent = {}
    for _, m in ipairs(net.log) do
        if m.prefix == "HU20" or m.prefix == "HU20B" then
            local cmd = m.text:match("^(%u%u?)~?")
            if cmd then sent[cmd] = sent[cmd] or {}; sent[cmd][m.from] = true end
        end
    end
    local out = {}
    for cmd, from in pairs(sent) do
        local ok = false
        for _, p in pairs(players) do
            -- (lo acepta alguien que no sea el único que lo manda)
            if (p.accepted[cmd] or 0) > 0 and not (from[p] and next(from, next(from)) == nil and next(from) == p) then ok = true end
        end
        if not ok then out[#out + 1] = cmd end
    end
    table.sort(out)
    return out
end

local function Missing(net, players)
    local out = {}
    for _, cmd in ipairs(NobodyAccepts(net, players)) do
        if not NOBODY_ACCEPTS[cmd] then out[#out + 1] = cmd end
    end
    return out
end

-- (el escenario tarda: se pasa una vez y lo comparten las pruebas de este archivo)
local cache
local function Scenario()
    if not cache then cache = { escenario.Run() } end
    return cache[1], cache[2]
end

describe("Formato de los mensajes", function()
    it("el escenario termina sin errores", function()
        local net = Scenario()
        A.same({}, net:Errors(), "errores")
    end)

    -- (solo falla una forma NUEVA: es lo que delata un cambio de formato. Que una forma no salga en
    -- una ejecución no lo es: los retrasos al azar del addon dan otro recorrido con otra versión de
    -- Lua (5.1 y 5.4 sacan otros números), y algún mensaje sale en una y no en la otra. Por eso
    -- --actualizar AÑADE lo nuevo y no quita nada: la referencia junta lo visto con las dos. Una forma
    -- vieja que ya no debe existir se borra a mano del archivo)
    it("ninguna forma de mensaje nueva fuera de tests/golden/formato.txt", function()
        local now = Shapes((Scenario()))
        local golden = ReadGolden()
        local new = {}
        for k in pairs(now) do if not (golden and golden[k]) then new[#new + 1] = k end end
        table.sort(new)
        if runner.update or not golden then
            local all = golden or {}
            for _, k in ipairs(new) do all[k] = true end
            WriteGolden(all)
            print("\n(formato: " .. #new .. " formas nuevas guardadas en " .. GOLDEN .. ")")
            return
        end
        if #new > 0 then
            error("el formato de los mensajes ha cambiado. Formas nuevas:\n    " .. table.concat(new, "\n    ")
                .. "\n  Si es a propósito: lua tests/run.lua Formato --actualizar (y quita a mano las formas viejas"
                .. " que ya no deban existir)", 0)
        end
    end)

    it("todo lo que se manda lo acepta alguien (ida y vuelta)", function()
        local net, p = Scenario()
        A.same({}, Missing(net, p), "órdenes que nadie acepta (si es a propósito, a NOBODY_ACCEPTS con el motivo)")
    end)

    it("las excepciones siguen siéndolo (si una ya se acepta, se quita de NOBODY_ACCEPTS)", function()
        local net, p = Scenario()
        local still = {}
        for _, cmd in ipairs(NobodyAccepts(net, p)) do still[cmd] = true end
        for cmd in pairs(NOBODY_ACCEPTS) do A.truthy(still[cmd], cmd .. " ya lo acepta alguien") end
    end)

    it("el chat, las listas y el silencio llegan a todos", function()
        local _, p = Scenario()
        A.same({ "hola desde UNO" }, p.bea:Heard(p.ana), "Bea oye a Ana")
        A.same({ "hola desde DOS" }, p.alba:Heard(p.blas), "Alba oye a Blas")
        for _, x in pairs(p) do
            local other = x.tag == "UNO" and "DOS" or "UNO"
            A.truthy(x.HU.remoteRoster[other], x.full .. " tiene la lista de " .. other)
            A.truthy(x.HU:IsMuted(p.blas.full), x.full .. " ve a Blas silenciado")
        end
    end)
end)

describe("Formato con versiones mezcladas", function()
    local ref = addon.LatestRelease()
    if not ref then
        pending("no hay etiquetas de versión en git (en el CI hace falta fetch-depth: 0)")
        return
    end
    local mixed
    local function Mixed()
        -- (Ana y Blas con la versión publicada; Alba y Bea con la de la carpeta)
        if not mixed then mixed = { escenario.Run({ ana = ref, blas = ref }) } end
        return mixed[1], mixed[2]
    end

    it(ref .. " y la de la carpeta: sin errores en ninguna", function()
        local net = Mixed()
        A.same({}, net:Errors(), "errores")
    end)

    it(ref .. " y la de la carpeta: el chat llega en los dos sentidos", function()
        local _, p = Mixed()
        A.same({ "hola desde UNO" }, p.bea:Heard(p.ana), "Bea (nueva) oye a Ana (" .. ref .. ")")
        A.same({ "hola desde DOS" }, p.alba:Heard(p.blas), "Alba (nueva) oye a Blas (" .. ref .. ")")
    end)

    it(ref .. " y la de la carpeta: las listas y el silencio llegan a todos", function()
        local _, p = Mixed()
        for _, x in pairs(p) do
            local other = x.tag == "UNO" and "DOS" or "UNO"
            A.truthy(x.HU.remoteRoster[other], x.full .. " tiene la lista de " .. other)
            A.truthy(x.HU:IsMuted(p.blas.full), x.full .. " ve a Blas silenciado")
        end
    end)

    it(ref .. " y la de la carpeta: todo lo que se manda lo acepta alguien", function()
        local net, p = Mixed()
        A.same({}, Missing(net, p), "órdenes que nadie acepta")
    end)
end)
