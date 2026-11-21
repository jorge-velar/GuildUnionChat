-- Cobertura de las pruebas: qué líneas del addon pasan por alguna prueba (tests/run.lua).
--
--   lua tests/cobertura.lua                       informe, y para si un archivo baja de su mínimo
--   lua tests/cobertura.lua --base origin/main    y además: las líneas nuevas o cambiadas desde main
--                                                 tienen que estar probadas (NUEVAS_MIN)
--   lua tests/cobertura.lua --actualizar          guarda los valores de ahora como mínimos (solo con
--                                                 Lua 5.1; si no, el artefacto «cobertura-minima» del CI)
--   lua tests/cobertura.lua --al-dia ruta.txt     escribe los valores de ahora en otro archivo (CI)
--
-- Se mide SIN lo que se ejecuta al cargar el addon (definir funciones, llenar tablas): eso pasa sin
-- ninguna prueba y era casi la mitad de lo «cubierto». Una línea que tiene a la vez algo de carga y
-- algo de dentro de una función (p. ej. «function HU:X() return 1 end») tampoco cuenta.
--
-- Las líneas ejecutables las da luac (-l): las que tienen alguna instrucción. Se usa luac5.1 con
-- Lua 5.1 y luac con los demás; se puede cambiar con la variable LUAC.
local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "tests"
package.path = here .. "/?.lua;" .. package.path

-- Mínimo para lo nuevo de cada PR (en %)
local NUEVAS_MIN = 70
-- Margen para los mínimos por archivo (en puntos). Los mínimos se miden con Lua 5.1 (el del CI y el de
-- WoW). Con otra versión, luac reparte las instrucciones por líneas de otra forma y un archivo sale
-- hasta 1,2 puntos arriba o abajo (medido el 21/11/2026): en local (5.4) el margen es mayor
local LUA51 = _VERSION == "Lua 5.1"
local MARGEN = LUA51 and 1.0 or 2.0
-- Archivos solo de interfaz (el WoW de mentira no pinta nada): fuera de la regla de lo nuevo
local SOLO_INTERFAZ = {
    ["BlizzTab.lua"] = true, ["WMPanel.lua"] = true, ["ListWindow.lua"] = true,
    ["UIWindows.lua"] = true, ["Wizard.lua"] = true,
}
local MINIMOS = here .. "/cobertura-minima.txt"

local opts = {}
do
    local i = 1
    while arg and arg[i] do
        local a = arg[i]
        if a == "--base" or a == "--al-dia" then opts[a:sub(3)] = arg[i + 1]; i = i + 1
        elseif a == "--actualizar" then opts.actualizar = true
        elseif a == "--forzar" then opts.forzar = true end
        i = i + 1
    end
end

local addon = require("lib.addon")
local root = addon.root

---------------------------------------------------------------------------
-- Medir
---------------------------------------------------------------------------
local hits
local getinfo = debug.getinfo
local function Hook(_, line)
    local s = getinfo(2, "S").source
    local h = hits[s]
    if not h then h = {}; hits[s] = h end
    h[line] = true
end
local function Measure(fn)
    hits = {}
    debug.sethook(Hook, "l")
    local ok, err = pcall(fn)
    debug.sethook()
    return hits, ok, err
end

-- 1) solo cargar: lo que se ejecuta sin ninguna prueba
local loadHits = Measure(function() addon.Load({}) end)

-- 2) todas las pruebas (sin que tests/run.lua termine el proceso)
-- (a propósito se cambian os.exit y arg mientras tanto: luacheck no tiene que avisar)
-- luacheck: push ignore 121 122
local exitCode
local realExit = os.exit
os.exit = function(c) exitCode = c; error("__fin__", 0) end
local savedArg = arg
arg = { [0] = here .. "/run.lua" }
local testHits, _, err = Measure(function() dofile(here .. "/run.lua") end)
arg = savedArg
os.exit = realExit
-- luacheck: pop
if err and err ~= "__fin__" then print("Las pruebas no han terminado: " .. tostring(err)) end
local testsOk = exitCode == 0 or exitCode == true

-- Líneas ejecutables de un archivo (luac), sin las de carga
local LUAC = os.getenv("LUAC") or (_VERSION == "Lua 5.1" and "luac5.1" or "luac")
local function Executable(file)
    local p = assert(io.popen(LUAC .. ' -l -l -p "' .. root .. "/" .. file .. '"'))
    local exe, load = {}, loadHits["@" .. file] or {}
    for l in p:lines() do
        local n = tonumber(l:match("^%s+%d+%s+%[(%d+)%]"))
        if n and not load[n] then exe[n] = true end
    end
    p:close()
    return exe
end

local rows, byFile, total, covered = {}, {}, 0, 0
for _, file in ipairs(addon.LuaFiles()) do
    if not file:match("^Libs/") then
        local exe = Executable(file)
        local h = testHits["@" .. file] or {}
        local t, c = 0, 0
        for n in pairs(exe) do
            t = t + 1
            if h[n] then c = c + 1 end
        end
        if t > 0 then
            local r = { file = file, t = t, c = c, pct = 100 * c / t, exe = exe, hits = h }
            rows[#rows + 1] = r
            byFile[file] = r
            total, covered = total + t, covered + c
        end
    end
end
table.sort(rows, function(a, b) return a.t > b.t end)
local totalPct = 100 * covered / math.max(1, total)

---------------------------------------------------------------------------
-- Mínimos por archivo
---------------------------------------------------------------------------
local function Round(x) return math.floor(x * 10) / 10 end
local function WriteMins(path)
    local f = assert(io.open(path, "wb"))
    f:write("# Cobertura mínima de cada archivo (%), sin lo que se ejecuta al cargar. No puede bajar.\n")
    f:write("# Se rehace con Lua 5.1:  lua5.1 tests/cobertura.lua --actualizar   (o con el artefacto del CI)\n")
    local sorted = {}
    for _, r in ipairs(rows) do sorted[#sorted + 1] = r end
    table.sort(sorted, function(a, b) return a.file < b.file end)
    for _, r in ipairs(sorted) do f:write(string.format("%s %.1f\n", r.file, Round(r.pct))) end
    f:close()
end

local mins = {}
do
    local f = io.open(MINIMOS, "rb")
    if f then
        for line in f:lines() do
            local file, v = line:gsub("\r$", ""):match("^([^#%s]+)%s+([%d%.]+)")
            if file then mins[file] = tonumber(v) end
        end
        f:close()
    end
end

local below, above = {}, {}
for _, r in ipairs(rows) do
    local m = mins[r.file]
    if m and r.pct < m - MARGEN then below[#below + 1] = r end
    if m and r.pct > m + MARGEN then above[#above + 1] = r end
end

---------------------------------------------------------------------------
-- Lo nuevo o cambiado desde --base
---------------------------------------------------------------------------
local function Git(cmd)
    local p = io.popen("git -C \"" .. root .. "\" " .. cmd .. " 2>&1")
    local out = p:read("*a")
    p:close()
    return out
end

local diff -- { n = líneas nuevas ejecutables, c = probadas, missing = { [archivo] = { líneas } } }
if opts.base then
    local mb = Git("merge-base " .. opts.base .. " HEAD"):match("^(%x+)")
    if not mb then
        print("No encuentro " .. opts.base .. " (en el CI hace falta fetch-depth: 0): no se mira lo nuevo.")
    else
        diff = { n = 0, c = 0, missing = {}, files = 0 }
        local file
        for line in Git("diff -U0 " .. mb .. " -- \"*.lua\""):gmatch("[^\n]+") do
            local f = line:match("^%+%+%+ b/(.+)$")
            if f then
                file = byFile[f] and not SOLO_INTERFAZ[f] and f or nil
                if file then diff.files = diff.files + 1 end
            elseif file then
                local start, count = line:match("^@@ %-%S+ %+(%d+),?(%d*) @@")
                if start then
                    start, count = tonumber(start), tonumber(count ~= "" and count or "1")
                    local r = byFile[file]
                    for n = start, start + count - 1 do
                        if r.exe[n] then
                            diff.n = diff.n + 1
                            if r.hits[n] then diff.c = diff.c + 1
                            else
                                local m = diff.missing[file] or {}
                                diff.missing[file] = m
                                m[#m + 1] = n
                            end
                        end
                    end
                end
            end
        end
    end
end

-- 12, 13, 14, 20 -> «12-14, 20»
local function Ranges(list)
    table.sort(list)
    local out, a, b = {}, nil, nil
    for _, n in ipairs(list) do
        if a and n == b + 1 then b = n
        else
            if a then out[#out + 1] = a == b and tostring(a) or (a .. "-" .. b) end
            a, b = n, n
        end
    end
    if a then out[#out + 1] = a == b and tostring(a) or (a .. "-" .. b) end
    return table.concat(out, ", ")
end

---------------------------------------------------------------------------
-- Informe
---------------------------------------------------------------------------
local out = {}
local function P(s) out[#out + 1] = s or "" end
P(string.format("## Cobertura de las pruebas: %.1f %%", totalPct))
P()
P(string.format("%d de %d líneas, sin contar lo que se ejecuta solo al cargar el addon (%s).",
    covered, total, _VERSION))
if not testsOk then P(); P("**Ojo: alguna prueba falla; la cobertura puede salir más baja.**") end
P()
if diff then
    local pct = diff.n > 0 and 100 * diff.c / diff.n or 100
    P(string.format("### Lo nuevo o cambiado desde %s: %s", opts.base,
        diff.n == 0 and "sin líneas de código que medir" or string.format("%d de %d líneas probadas (%.0f %%, mínimo %d %%)", diff.c, diff.n, pct, NUEVAS_MIN)))
    local files = {}
    for f in pairs(diff.missing) do files[#files + 1] = f end
    table.sort(files)
    if #files > 0 then
        P()
        P("Sin probar:")
        for _, f in ipairs(files) do P("- `" .. f .. "`: " .. Ranges(diff.missing[f])) end
    end
    P()
end
if #below > 0 then
    P("### Archivos por debajo de su mínimo")
    for _, r in ipairs(below) do P(string.format("- `%s`: %.1f %% (mínimo %.1f %%)", r.file, r.pct, mins[r.file])) end
    P()
end
if #above > 0 then
    P("Han subido " .. #above .. " archivos: rehaz los mínimos (`lua tests/cobertura.lua --actualizar` o el artefacto `cobertura-minima` del CI) para que no vuelvan a bajar.")
    P()
end
P("| Archivo | Líneas probadas | % | Mínimo |")
P("|---|---:|---:|---:|")
for _, r in ipairs(rows) do
    local m = mins[r.file]
    P(string.format("| %s%s | %d / %d | %.1f | %s |", r.file, SOLO_INTERFAZ[r.file] and " (interfaz)" or "",
        r.c, r.t, r.pct, m and string.format("%.1f", m) or "-"))
end
local report = table.concat(out, "\n")
print(report)

local summary = os.getenv("GITHUB_STEP_SUMMARY")
if summary and summary ~= "" then
    local f = io.open(summary, "ab")
    if f then f:write(report, "\n"); f:close() end
end

if opts.actualizar then
    if not LUA51 and not opts.forzar then
        print("\nLos mínimos se guardan con Lua 5.1 (el del CI): con " .. _VERSION .. " saldrían otros y el CI fallaría."
            .. "\nUsa lua5.1, o descarga el artefacto «cobertura-minima» del CI y cópialo a " .. MINIMOS
            .. " (--forzar para guardarlos igualmente).")
        realExit(1)
    end
    WriteMins(MINIMOS)
    print("\nMínimos guardados en " .. MINIMOS)
    realExit(0)
end
if opts["al-dia"] then WriteMins(opts["al-dia"]) end

local fail = false
if not next(mins) then
    print("\nNo hay mínimos (" .. MINIMOS .. "): créalos con --actualizar.")
end
if #below > 0 then fail = true end
if diff and diff.n > 0 and 100 * diff.c / diff.n < NUEVAS_MIN then
    print(string.format("\nLo nuevo está probado al %.0f %% y el mínimo es %d %%: añade pruebas en tests/spec/ para las líneas de arriba.",
        100 * diff.c / diff.n, NUEVAS_MIN))
    fail = true
end
realExit(fail and 1 or 0)
