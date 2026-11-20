-- Compara los avisos de luacheck con los ya conocidos (tests/luacheck-conocidos.txt) y falla solo si
-- hay alguno NUEVO. Así el CI para con lo nuevo sin tener que arreglar antes los avisos de siempre.
--
--   luacheck . -q --formatter=plain --codes | lua tests/luacheck_nuevos.lua
--   luacheck . -q --formatter=plain --codes | lua tests/luacheck_nuevos.lua --actualizar
--
-- Un aviso se identifica por archivo + código + texto, SIN el número de línea (cambia con cada
-- edición). Si en un archivo hay más avisos iguales que los conocidos, los de más son nuevos.
-- Al arreglar avisos, se pasa --actualizar para que la lista baje y no vuelvan a colarse.
local here = (arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$")) or "tests"
local FILE = here .. "/luacheck-conocidos.txt"
local update = arg and arg[1] == "--actualizar"

local function Key(line)
    -- Comm.lua:123:5: (W211) unused variable 'x'
    local file, rest = line:match("^(.-):%d+:%d+: (.*)$")
    if not file then return nil end
    return file:gsub("\\", "/"):gsub("^%./", "") .. ": " .. rest
end

local function Count(lines)
    local n, order = {}, {}
    for _, l in ipairs(lines) do
        local k = Key(l) or l
        if not n[k] then order[#order + 1] = k end
        n[k] = (n[k] or 0) + 1
    end
    table.sort(order)
    return n, order
end

local now = {}
for line in io.lines() do
    line = line:gsub("\r$", "")
    if line:match("^.-:%d+:%d+: ") then now[#now + 1] = line end
end
local nowN, nowOrder = Count(now)

if update then
    local f = assert(io.open(FILE, "wb"))
    f:write("# Avisos de luacheck que ya había (no paran el CI). Se rehace con:\n")
    f:write("#   luacheck . -q --formatter=plain --codes | lua tests/luacheck_nuevos.lua --actualizar\n")
    for _, k in ipairs(nowOrder) do
        for _ = 1, nowN[k] do f:write(k, "\n") end
    end
    f:close()
    print("Guardados " .. #now .. " avisos en " .. FILE)
    os.exit(0)
end

local known = {}
local kf = io.open(FILE, "rb")
if not kf then
    print("No hay lista de avisos conocidos (" .. FILE .. "): no se para el CI.")
    print("Para crearla, en un equipo con luacheck:")
    print("  luacheck . -q --formatter=plain --codes | lua tests/luacheck_nuevos.lua --actualizar")
    print("Avisos de ahora (" .. #now .. "):")
    for _, l in ipairs(now) do print("  " .. l) end
    os.exit(0)
end
for line in kf:lines() do
    line = line:gsub("\r$", "")
    if line ~= "" and not line:match("^#") then known[#known + 1] = line end
end
kf:close()
local knownN = Count(known)

-- (los conocidos ya llevan la clave sin línea; Count les aplica Key y, al no casar, usa la línea tal cual)
local fresh = {}
local seen = {}
for _, l in ipairs(now) do
    local k = Key(l)
    seen[k] = (seen[k] or 0) + 1
    if seen[k] > (knownN[k] or 0) then fresh[#fresh + 1] = l end
end

local fixed = 0
for k, n in pairs(knownN) do fixed = fixed + math.max(0, n - (nowN[k] or 0)) end

print(string.format("luacheck: %d avisos, %d conocidos, %d nuevos, %d arreglados", #now, #known, #fresh, fixed))
if fixed > 0 then
    print("(hay avisos arreglados: rehaz la lista con --actualizar para que no vuelvan a colarse)")
end
if #fresh > 0 then
    print("\nAvisos NUEVOS:")
    for _, l in ipairs(fresh) do print("  " .. l) end
    os.exit(1)
end
os.exit(0)
