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

-- opts: lo de wow.New (player, realm, guild, guildInfo, locale...) y además
--   db / charDb : lo guardado (GuildUnionDB / GuildUnionCharDB) antes de cargar
--   only        : lista de archivos que cargar en vez de todo el .toc (pruebas de un módulo suelto)
function M.Load(opts)
    opts = opts or {}
    local files, meta = M.Toc()
    opts.metadata = opts.metadata or meta
    local w = wow.New(opts)
    w.env.GuildUnionDB = opts.db
    w.env.GuildUnionCharDB = opts.charDb
    local HU = {}
    for _, file in ipairs(opts.only or files) do
        local src = assert(ReadFile(M.root .. "/" .. file), "no encuentro " .. file)
        local fn, err = LoadWithEnv(src, "@" .. file, w.env)
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
