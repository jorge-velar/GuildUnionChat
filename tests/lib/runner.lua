-- Ejecutor de pruebas mínimo, sin dependencias (vale en Lua 5.1 y 5.4).
-- Imita lo básico de busted: describe / it / before_each y unas comprobaciones.
local R = { results = { pass = 0, fail = 0, skip = 0 }, failures = {}, filter = nil }

local stack, befores = {}, {}

local function fullName(name)
    local parts = {}
    for i = 1, #stack do parts[#parts + 1] = stack[i] end
    parts[#parts + 1] = name
    return table.concat(parts, " > ")
end

function R.describe(name, fn)
    stack[#stack + 1] = name
    befores[#befores + 1] = false
    fn()
    befores[#befores] = nil
    stack[#stack] = nil
end

function R.before_each(fn) befores[#befores] = fn end

function R.it(name, fn)
    local full = fullName(name)
    if R.filter and not full:find(R.filter, 1, true) then return end
    local ok, err = pcall(function()
        for i = 1, #befores do if befores[i] then befores[i]() end end
        fn()
    end)
    if ok then
        R.results.pass = R.results.pass + 1
        io.write(".")
    else
        R.results.fail = R.results.fail + 1
        R.failures[#R.failures + 1] = { name = full, err = tostring(err) }
        io.write("F")
    end
end

-- (para marcar algo que se quiere probar pero aún no está hecho)
function R.pending(name)
    R.results.skip = R.results.skip + 1
    io.write("-")
    R.failures[#R.failures + 1] = { name = fullName(name), err = nil }
end

---------------------------------------------------------------------------
-- Comprobaciones
---------------------------------------------------------------------------
local function show(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

local function deepEq(a, b, seen)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for k, v in pairs(a) do if not deepEq(v, b[k], seen) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function dump(v, indent)
    if type(v) ~= "table" then return show(v) end
    indent = indent or ""
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = indent .. "  [" .. show(k) .. "] = " .. dump(v[k], indent .. "  ") end
    return "{\n" .. table.concat(out, ",\n") .. "\n" .. indent .. "}"
end

local A = {}
function A.equal(expected, actual, msg)
    if expected ~= actual then
        error((msg and msg .. ": " or "") .. "se esperaba " .. show(expected) .. " y ha salido " .. show(actual), 2)
    end
end
function A.same(expected, actual, msg)
    if not deepEq(expected, actual) then
        error((msg and msg .. ": " or "") .. "se esperaba\n" .. dump(expected) .. "\ny ha salido\n" .. dump(actual), 2)
    end
end
function A.truthy(v, msg) if not v then error((msg or "se esperaba verdadero") .. " (ha salido " .. show(v) .. ")", 2) end end
function A.falsy(v, msg) if v then error((msg or "se esperaba falso") .. " (ha salido " .. show(v) .. ")", 2) end end
function A.is_nil(v, msg) if v ~= nil then error((msg or "se esperaba nil") .. " (ha salido " .. show(v) .. ")", 2) end end
function A.matches(pattern, s, msg)
    if type(s) ~= "string" or not s:find(pattern) then
        error((msg and msg .. ": " or "") .. show(s) .. " no casa con " .. show(pattern), 2)
    end
end
function A.has_error(fn, msg)
    if pcall(fn) then error(msg or "se esperaba un error", 2) end
end
R.assert = A

function R.report()
    io.write("\n\n")
    for _, f in ipairs(R.failures) do
        if f.err then
            io.write("FALLA  ", f.name, "\n        ", (f.err:gsub("\n", "\n        ")), "\n\n")
        else
            io.write("PENDIENTE  ", f.name, "\n")
        end
    end
    local r = R.results
    io.write(string.format("%d bien, %d mal, %d pendientes  (%s)\n", r.pass, r.fail, r.skip, _VERSION))
    return r.fail == 0
end

return R
