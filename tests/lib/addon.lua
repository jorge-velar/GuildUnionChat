-- Carga Guild Union entero en un WoW de mentira (tests/lib/wow.lua), en el orden del .toc.
--
--   local addon = require("lib.addon")
--   local a = addon.Load({ guild = {...} })   -- carga los archivos y lanza ADDON_LOADED
--   a:Login()                                 -- PLAYER_LOGIN + PLAYER_ENTERING_WORLD + unos segundos
--   a.HU, a.w                                 -- el espacio del addon y el mundo (reloj, mensajes...)
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

-- Archivos y metadatos del .toc
function M.Toc()
    local text = assert(ReadFile(M.root .. "/" .. ADDON_NAME .. ".toc"), "no encuentro " .. ADDON_NAME .. ".toc")
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
local function LoadFile(file, env)
    local bc = compiled[file]
    if not bc then
        local src = assert(ReadFile(M.root .. "/" .. file), "no encuentro " .. file)
        local fn, err = LoadWithEnv(src, "@" .. file, env)
        if not fn then return nil, err end
        compiled[file] = string.dump(fn)
        return fn
    end
    if setfenv and loadstring then
        return setfenv(assert(loadstring(bc, "@" .. file)), env)
    end
    return assert(load(bc, "@" .. file, "b", env))
end

-- Un .xml del .toc (p. ej. Libs/LibDBIcon-1.0/lib.xml): solo importan sus <Script file> e
-- <Include file>, en orden y relativos a la carpeta del .xml. Los marcos en XML no se crean.
local function XmlFiles(path, out)
    out = out or {}
    local src = assert(ReadFile(M.root .. "/" .. path), "no encuentro " .. path)
    local dir = path:match("^(.*)/[^/]+$")
    for tag, file in src:gmatch("<%s*(%a+)%s+[^>]-file%s*=%s*\"([^\"]+)\"") do
        local full = (dir and dir .. "/" or "") .. file:gsub("\\", "/")
        if tag == "Script" then
            out[#out + 1] = full
        elseif tag == "Include" then
            XmlFiles(full, out)
        end
    end
    return out
end

-- Los .lua que carga el .toc, con los de cada .xml en su sitio
function M.LuaFiles()
    local out = {}
    for _, file in ipairs((M.Toc())) do
        if file:lower():match("%.xml$") then
            for _, f in ipairs(XmlFiles(file)) do out[#out + 1] = f end
        else
            out[#out + 1] = file
        end
    end
    return out
end

-- opts: lo de wow.New (player, realm, guild, guildInfo, locale...) y además
--   db / charDb : lo guardado (GuildUnionDB / GuildUnionCharDB) antes de cargar
--   only        : lista de archivos que cargar en vez de todo el .toc (pruebas de un módulo suelto)
function M.Load(opts)
    opts = opts or {}
    local _, meta = M.Toc()
    local files = M.LuaFiles()
    opts.metadata = opts.metadata or meta
    local w = wow.New(opts)
    w.env.GuildUnionDB = opts.db
    w.env.GuildUnionCharDB = opts.charDb
    local HU = {}
    for _, file in ipairs(opts.only or files) do
        local fn, err = LoadFile(file, w.env)
        if not fn then error("no compila " .. file .. ": " .. tostring(err), 0) end
        local ok, e = pcall(fn, ADDON_NAME, HU)
        if not ok then error("falla al cargar " .. file .. ": " .. tostring(e), 0) end
    end
    w:Fire("ADDON_LOADED", ADDON_NAME)
    local a = { HU = HU, w = w, env = w.env }
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
