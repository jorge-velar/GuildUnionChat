-- Lo guardado (SavedVariables) y sus migraciones (Core.lua, HU:RegisterMigration y HU:RunMigrations):
-- cada ámbito (la cuenta, adb, y cada personaje, cdb) lleva su número de esquema; una versión más
-- vieja que lo guardado no lo toca. Y lo que guarda la última versión publicada, al actualizar, no
-- se pierde (ni al volver atrás).
local F = require("lib.fixtures")
local escenario = require("lib.escenario")
local addon = require("lib.addon")
local A = assert_

local GUILD = "Hermandad Uno"

-- Una copia de lo guardado como la deja el juego (sin funciones ni metatablas)
local function Copy(t, seen)
    if type(t) ~= "table" then return type(t) == "function" and nil or t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local c = {}
    seen[t] = c
    for k, v in pairs(t) do c[k] = Copy(v, seen) end
    return c
end
-- Las claves de old que ya no están en new (hasta dos niveles: «netCfg», «chars.Ana Reino-X.lists»)
local function Lost(old, new, prefix, depth)
    local out = {}
    for k, v in pairs(old) do
        local path = (prefix or "") .. tostring(k)
        if new[k] == nil then out[#out + 1] = path
        elseif depth > 1 and type(v) == "table" and type(new[k]) == "table" then
            for _, p in ipairs(Lost(v, new[k], path .. ".", depth - 1)) do out[#out + 1] = p end
        end
    end
    table.sort(out)
    return out
end

describe("Datos guardados: esquema", function()
    it("instalación nueva: la cuenta en el esquema 0 y el personaje en el 1", function()
        local HU = F.Community().HU
        A.equal(0, HU.adb.schema)
        A.equal(1, HU.cdb.schema)
        A.equal(0, HU.db.schema) -- (db.schema es el de la cuenta)
    end)

    it("lo de la cuenta de una versión de antes pasa al personaje de esa hermandad", function()
        local db = {
            netCfg = { guild = GUILD, text = "GU:o:Ofi:clave" },
            pinned = { text = "hola", t = 1 },
            infoBackup = { guild = "Otra Hermandad", text = "x" },
        }
        local HU = F.Community({ db = db }).HU
        A.equal(db.netCfg, HU.cdb.netCfg)
        A.equal("hola", HU.cdb.pinned and HU.cdb.pinned.text)
        A.is_nil(HU.cdb.infoBackup, "era de otra hermandad")
        A.truthy(HU.cdb.migrated, "lo siguen mirando las versiones de antes")
        A.equal(1, HU.cdb.schema)
    end)

    it("si una versión de antes ya lo pasó (migrated), no se repite", function()
        local HU = F.Community({ db = { netCfg = { guild = GUILD, text = "x" } }, charDb = { migrated = true } }).HU
        A.is_nil(HU.cdb.netCfg)
        A.equal(1, HU.cdb.schema)
    end)

    it("hasta leer la Información, la migración del personaje espera", function()
        local a = addon.Load({ guild = F.Guild(), guildInfo = F.INFO, db = { netCfg = { guild = GUILD, text = "x" } } })
        A.equal(0, a.HU.cdb.schema)
        A.is_nil(a.HU.cdb.netCfg)
        a:Login(60)
        A.equal(1, a.HU.cdb.schema)
        A.truthy(a.HU.cdb.netCfg)
    end)

    it("lo guardado por una versión más nueva no se toca y se avisa en /gu errores", function()
        local a = F.Community({ db = { netCfg = { guild = GUILD, text = "x" } }, charDb = { schema = 9 } })
        A.is_nil(a.HU.cdb.netCfg)
        A.equal(9, a.HU.cdb.schema)
        local errs = table.concat(a:Errors(), "\n")
        A.matches("versión más nueva", errs)
    end)

    it("dos veces seguidas no cambia nada", function()
        local HU = F.Community({ db = { netCfg = { guild = GUILD, text = "x" } } }).HU
        local before = Copy(HU.cdb)
        HU:RunMigrations({ guild = GUILD, text = F.INFO })
        A.same(before, Copy(HU.cdb))
    end)

    it("RegisterMigration: en orden, sin huecos y con un ámbito que existe", function()
        local HU = F.Community().HU
        A.falsy(pcall(HU.RegisterMigration, HU, "char", 3, "salta la 2", function() end))
        A.falsy(pcall(HU.RegisterMigration, HU, "servidor", 1, "no existe", function() end))
        A.truthy(pcall(HU.RegisterMigration, HU, "account", 1, "la primera de la cuenta", function(adb) adb.nueva = true end))
        HU:RunMigrations(nil)
        A.equal(1, HU.adb.schema)
        A.truthy(HU.adb.nueva)
    end)
end)

describe("Datos guardados: lo que declara cada módulo (HU:Saved)", function()
    -- (DEFAULTS y PER_CHAR de Core.lua en la 5.4.41, tal cual)
    local OLD_CHAR = { "history", "pinned", "myRole", "lastSeen", "pvpSince", "netChan", "chatShow", "netCfg",
        "infoBackup", "noteChanSeen", "joinedChans", "extraChans", "chatTab", "chanLane", "netGuilds", "proposals",
        "guildColors", "customEmotes", "lists", "rankCache", "offline", "offlineT", "peers", "chatTabsMade",
        "rosterCache", "remoteRanks", "quickCfg", "managers", "officerRanks", "myOfficerRanks", "laneLock", "laneMig", "wmRows",
        -- (nuevo: la configuración de la unión, de cada personaje)
        "unionCfg",
        -- (nuevo: Comercio, las recetas leídas de cada profesión y la casilla «Solo lo que puedo hacer»)
        "tradeRecipes", "tradeOnlyCraft",
        -- (nuevo, copia 324: Comercio guarda sus solicitudes, los chats con cada persona y lo sin leer)
        "tradeReqs", "tradeChats", "tradeUnread" }
    local OLD_DEFAULTS = { showTag = true, chatMark = "dot", chatGuildColor = false, ownPaint = true, autoGuard = false,
        bans = {}, grace = 120, debug = false, showChannel = false, audit = {}, history = {}, log = {}, profiles = {},
        offline = {}, mutes = {}, extraChans = {}, rankCache = {}, theme = "default", loginHistory = false, peers = {},
        -- (nuevo, copia 324: lo guardado de Comercio y Calendario, que empieza vacío)
        tradeReqs = {}, tradeChats = {}, tradeUnread = {}, calEvents = {} }

    it("da exactamente lo de antes: qué va en el personaje y los valores por defecto", function()
        local HU = F.Community().HU
        local char = {}
        for k in pairs(HU.PER_CHAR) do char[#char + 1] = k end
        table.sort(char)
        local want = {}
        for i, k in ipairs(OLD_CHAR) do want[i] = k end
        table.sort(want)
        A.same(want, char)
        A.same(OLD_DEFAULTS, HU.savedDefaults)
    end)

    it("una clave declarada dos veces o un ámbito que no existe dan error", function()
        local HU = F.Community().HU
        A.falsy(pcall(HU.Saved, HU, { char = { "pinned" } }))
        A.falsy(pcall(HU.Saved, HU, { servidor = { "x" } }))
        A.truthy(pcall(HU.Saved, HU, { account = { nuevaClave = 1 } }))
        A.equal("account", HU.savedScope.nuevaClave)
    end)
end)

describe("Datos guardados: actualizar desde la última versión publicada", function()
    it("no se pierde nada de lo guardado, y volver a la de antes funciona", function()
        local release = addon.LatestRelease()
        A.truthy(release, "sin etiquetas de versión en git (en el CI hace falta fetch-depth: 0)")
        local net, p = escenario.Run({ ana = release, alba = release, bea = release, blas = release })
        local ana = p.ana
        net:Logout(ana)
        local old = Copy(ana.savedDb)
        A.truthy(old.chars and next(old.chars), "la versión publicada guarda por personaje")
        -- (actualiza: la misma cuenta con la versión de la carpeta)
        ana.opts.ref = nil
        net:Login(ana)
        net:Advance(120)
        A.same({}, ana.a:Errors(), "errores al entrar con lo guardado por " .. release)
        A.equal(1, ana.HU.cdb.schema)
        net:Logout(ana)
        A.same({}, Lost(old, ana.savedDb, "", 3), "claves de " .. release .. " que ya no están")
        -- (y vuelve a la publicada: no le estorba lo que ha añadido esta)
        ana.opts.ref = release
        net:Login(ana)
        net:Advance(120)
        A.same({}, ana.a:Errors(), "errores al volver a " .. release)
    end)
end)
