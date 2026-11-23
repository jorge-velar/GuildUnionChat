-- Qué módulos necesita cada archivo del addon: los archivos que definen (a nivel superior) las
-- funciones de HU que llama. Lo usan tests/spec/modulos_spec.lua, que exige que cada archivo lo
-- declare al final con HU:Module, y quien rehace esas líneas.
local M = {}

local function ReadFile(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"); f:close()
    return (s:gsub("\r\n", "\n"))
end

-- El nombre del módulo: la ruta sin «.lua» («Net/Relay»)
function M.Name(file) return (file:gsub("%.lua$", "")) end

-- La línea que tiene que cerrar el archivo
function M.Line(file, needs)
    local q = {}
    for i, n in ipairs(needs) do q[i] = '"' .. n .. '"' end
    return 'HU:Module("' .. M.Name(file) .. '", { ' .. table.concat(q, ", ") .. (#q > 0 and " " or "") .. "})"
end

-- root: la carpeta del addon. Devuelve los archivos (en el orden del .toc) y [archivo] = { módulos }
function M.Compute(root)
    local files = {}
    for l in (ReadFile(root .. "/GuildUnion.toc") .. "\n"):gmatch("([^\n]*)\n") do
        l = l:gsub("%s+$", ""):gsub("\\", "/")
        if l:match("%.lua$") and not l:match("^Libs/") then files[#files + 1] = l end
    end
    local src, owner = {}, {}
    for _, f in ipairs(files) do
        src[f] = ReadFile(root .. "/" .. f)
        for l in (src[f] .. "\n"):gmatch("([^\n]*)\n") do
            local x = l:match("^function HU[:.]([%w_]+)") or l:match("^HU%.([%w_]+)%s*=%s*function")
            if x and not owner[x] then owner[x] = f end
        end
    end
    local need = {}
    for _, f in ipairs(files) do
        local uses = {}
        local code = src[f]:gsub("%-%-[^\n]*", ""):gsub("\nHU:Module%b()%s*$", "\n")
        for x in code:gmatch("HU[:.]([%u][%w_]*)%(") do if owner[x] and owner[x] ~= f then uses[M.Name(owner[x])] = true end end
        for x in code:gmatch("self:([%u][%w_]*)%(") do if owner[x] and owner[x] ~= f then uses[M.Name(owner[x])] = true end end
        local list = {}
        for k in pairs(uses) do list[#list + 1] = k end
        table.sort(list)
        need[f] = list
    end
    return files, need, src
end

return M
