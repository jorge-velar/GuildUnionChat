-- Carga Guild Union entero en un WoW de mentira (tests/lib/wow.lua), en el orden del .toc.
--
--   local addon = require("lib.addon")
--   local a = addon.Load({ guild = {...} })   -- carga los archivos y lanza ADDON_LOADED
--   a:Login()                                 -- PLAYER_LOGIN + PLAYER_ENTERING_WORLD + unos segundos
--   a.HU, a.w                                 -- el espacio del addon y el mundo (reloj, mensajes...)
--
--   addon.Load({ ref = "v5.4.41" })           -- la versión publicada de esa etiqueta de git, leída
--                                             -- con «git show» (sin sacarla a ninguna carpeta)
local wow = require("lib.wow")

local M = {}
local ADDON_NAME = "GuildUnion"

-- (la carpeta del addon: la de arriba de tests/)
M.root = (arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$")) or "."

local function ReadFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end
M.ReadFile = ReadFile

-- Un archivo del addon: del disco o, con `ref`, de esa versión en git
local gitCache = {}
local function Git(args)
    local p = io.popen('git -C "' .. M.root .. '" ' .. args .. (package.config:sub(1, 1) == "\\" and " 2>NUL" or " 2>/dev/null"))
    if not p then return nil end
    local s = p:read("*a")
    p:close()
    return s
end
M.Git = Git
-- (todos los .lua, .xml y .toc de esa versión de una vez: un «git show» por archivo tardaba ~0,4 s
-- cada uno en Windows. git cat-file --batch los da todos con una sola llamada)
local function LoadRef(ref)
    local files = {}
    for path in (Git('ls-tree -r --name-only "' .. ref .. '"') or ""):gmatch("[^\r\n]+") do
        local low = path:lower()
        if low:match("%.lua$") or low:match("%.xml$") or low:match("%.toc$") then files[#files + 1] = path end
    end
    local list = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp") .. "/gu-pruebas-" .. tostring(os.time()) .. "-" .. tostring(files):gsub("%W", "") .. ".txt"
    -- (sin math.random: cambiaría la secuencia del escenario, que tiene que ser siempre la misma)
    local f = assert(io.open(list, "wb"))
    for _, path in ipairs(files) do f:write(ref, ":", path, "\n") end
    f:close()
    local p = assert(io.popen('git -C "' .. M.root .. '" cat-file --batch < "' .. list .. '"', "r"))
    local out = p:read("*a")
    p:close()
    os.remove(list)
    local pos = 1
    for _, path in ipairs(files) do
        local hEnd = out:find("\n", pos, true)
        if not hEnd then break end
        local size = tonumber(out:sub(pos, hEnd - 1):match("^%x+ blob (%d+)$"))
        if size then
            gitCache[ref .. ":" .. path] = out:sub(hEnd + 1, hEnd + size)
            pos = hEnd + size + 2
        else
            gitCache[ref .. ":" .. path] = ""
            pos = hEnd + 1
        end
    end
    gitCache[ref] = true
end
local function Source(file, ref)
    if not ref then return ReadFile(M.root .. "/" .. file) end
    if not gitCache[ref] then LoadRef(ref) end
    local s = gitCache[ref .. ":" .. file]
    return s ~= "" and s or nil
end

-- La versión publicada más nueva (la etiqueta vX.Y.Z más alta), o nil si no hay etiquetas
-- (en el CI hace falta fetch-depth: 0)
function M.LatestRelease()
    local out = Git("tag --list \"v*\" --sort=-v:refname") or ""
    return out:match("^(v[%d%.]+)")
end

-- Archivos y metadatos del .toc
function M.Toc(ref)
    local text = assert(Source(ADDON_NAME .. ".toc", ref), "no encuentro " .. ADDON_NAME .. ".toc" .. (ref and (" en " .. ref) or ""))
    local files, meta = {}, {}
    for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local k, v = line:match("^##%s*([^:]+):%s*(.-)%s*$")
        if k then
            meta[k] = v
        elseif line:match("%S") and not line:match("^#") then
            files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
        end
    end
    return files, meta
end

-- Compila un archivo con `env` como variables globales (Lua 5.1 y 5.2+)
local function LoadWithEnv(src, name, env)
    if setfenv and loadstring then
        local fn, err = loadstring(src, name)
        if not fn then return nil, err end
        return setfenv(fn, env)
    end
    return load(src, name, "t", env)
end
M.LoadWithEnv = LoadWithEnv

-- (compilar el addon entero cuesta ~0,3 s y las pruebas de red cargan muchas copias: cada archivo
-- se compila una vez y luego se carga ya compilado, con los números de línea intactos)
local compiled = {}
local function LoadFile(file, env, ref)
    local key = (ref or "") .. ":" .. file
    local bc = compiled[key]
    if not bc then
        local src = assert(Source(file, ref), "no encuentro " .. file .. (ref and (" en " .. ref) or ""))
        local fn, err = LoadWithEnv(src, "@" .. (ref and (ref .. "/") or "") .. file, env)
        if not fn then return nil, err end
        compiled[key] = string.dump(fn)
        return fn
    end
    local name = "@" .. (ref and (ref .. "/") or "") .. file
    if setfenv and loadstring then
        return setfenv(assert(loadstring(bc, name)), env)
    end
    return assert(load(bc, name, "b", env))
end

-- Un .xml del .toc (p. ej. Libs/LibDBIcon-1.0/lib.xml): solo importan sus <Script file> e
-- <Include file>, en orden y relativos a la carpeta del .xml. Los marcos en XML no se crean.
local function XmlFiles(path, out, ref)
    out = out or {}
    local src = assert(Source(path, ref), "no encuentro " .. path)
    local dir = path:match("^(.*)/[^/]+$")
    for tag, file in src:gmatch("<%s*(%a+)%s+[^>]-file%s*=%s*\"([^\"]+)\"") do
        local full = (dir and dir .. "/" or "") .. file:gsub("\\", "/")
        if tag == "Script" then
            out[#out + 1] = full
        elseif tag == "Include" then
            XmlFiles(full, out, ref)
        end
    end
    return out
end

-- Los .lua que carga el .toc, con los de cada .xml en su sitio
function M.LuaFiles(ref)
    local out = {}
    for _, file in ipairs((M.Toc(ref))) do
        if file:lower():match("%.xml$") then
            for _, f in ipairs(XmlFiles(file, nil, ref)) do out[#out + 1] = f end
        else
            out[#out + 1] = file
        end
    end
    return out
end

-- opts: lo de wow.New (player, realm, guild, guildInfo, locale...) y además
--   db / charDb : lo guardado (GuildUnionDB / GuildUnionCharDB) antes de cargar
--   only        : lista de archivos que cargar en vez de todo el .toc (pruebas de un módulo suelto)
--   ref         : etiqueta o commit de git: carga esa versión en vez de la de la carpeta
function M.Load(opts)
    opts = opts or {}
    local ref = opts.ref
    local _, meta = M.Toc(ref)
    local files = M.LuaFiles(ref)
    opts.metadata = opts.metadata or meta
    local w = wow.New(opts)
    w.env.GuildUnionDB = opts.db
    w.env.GuildUnionCharDB = opts.charDb
    local HU = {}
    for _, file in ipairs(opts.only or files) do
        local fn, err = LoadFile(file, w.env, ref)
        if not fn then error("no compila " .. file .. ": " .. tostring(err), 0) end
        local ok, e = pcall(fn, ADDON_NAME, HU)
        if not ok then error("falla al cargar " .. file .. ": " .. tostring(e), 0) end
    end
    w:Fire("ADDON_LOADED", ADDON_NAME)
    local a = { HU = HU, w = w, env = w.env, ref = ref }
    function a:Login(secs)
        self.w:Fire("PLAYER_LOGIN")
        self.w:Fire("PLAYER_ENTERING_WORLD", true, false)
        self.w:Advance(secs or 30)
        return self
    end
    -- Errores que el addon ha guardado (SafeCall) desde que arrancó
    function a:Errors()
        local out = {}
        for _, e in ipairs(self.HU.errors or {}) do out[#out + 1] = "[" .. tostring(e.where) .. "] " .. tostring(e.msg) end
        return out
    end
    return a
end

return M
