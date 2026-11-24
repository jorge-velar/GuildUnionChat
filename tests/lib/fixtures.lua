-- Comunidades de prueba ya montadas, para no repetirlo en cada archivo de pruebas
local addon = require("lib.addon")

local F = {}

-- Dos hermandades: UNO (la mía) y DOS. Yo soy Tester-Reino, oficial de UNO.
F.INFO = table.concat({
    "GU:t:Comunidad de prueba",
    "GU:c:CanalPrueba:clave",
    "GU:g:Hermandad Uno:UNO",
    "GU:g:Hermandad Dos:DOS",
}, "\n")

function F.Guild()
    return { name = "Hermandad Uno", rank = "Oficial", rankIndex = 1, members = {
        { name = "Tester-Reino", rank = "Oficial", rankIndex = 1 },
        { name = "Compi-Reino", rank = "Miembro", rankIndex = 4 },
        { name = "Jefa-Reino", rank = "Maestra", rankIndex = 0 },
    } }
end

-- Addon cargado, con la comunidad leída de la Información de hermandad y ya en marcha
function F.Community(opts)
    opts = opts or {}
    opts.guild = opts.guild or F.Guild()
    opts.guildInfo = opts.guildInfo or F.INFO
    local a = addon.Load(opts):Login(opts.secs or 60)
    a.HU:RefreshConfig(true)
    assert(a.HU.myTag == "UNO", "la comunidad de prueba no se ha montado (myTag = " .. tostring(a.HU.myTag) .. ")")
    return a
end

-- Sustituye HU[name] por fn mientras dura la prueba (el addon es nuevo en cada prueba: no hace falta deshacerlo)
function F.Stub(HU, name, value)
    if type(value) ~= "function" then
        local v = value
        value = function() return v end
    end
    HU[name] = value
end

-- Cuenta las llamadas a HU.comm[cmd] (sin llamar al de verdad)
function F.Spy(HU, cmd)
    local calls = {}
    HU.comm[cmd] = function(_, sender, f, dist, text) calls[#calls + 1] = { sender = sender, f = f, dist = dist, text = text } end
    return calls
end

return F
