-- Guild Union - registro de las órdenes de red (prefijos HU20 y HU20B) [+ARCHITECTURE.md]
local _, HU = ...

-- [orden] = lo declarado con HU:RegisterMessage. Lo leen la seguridad (Net/Security.lua, AllowAddonMessage),
-- la cola (HU:Send), el combate (Combat.lua) y /gu diag
HU.msgs = {}

-- Colas de envío (Net/Transport.lua): las de HU20, de más a menos prisa, y las de HU20B (datos grandes)
local QUEUES = { chat = "HU20", normal = "HU20", mid = "HU20", low = "HU20",
    bfast = "HU20B", bulk = "HU20B", bmid = "HU20B", blow = "HU20B" }
-- Lo que se hace en combate con lo que llega (Combat.lua): "list" = listas de conectados, "req" =
-- peticiones (las viejas se tiran), "data" = datos, "last" = de cada uno, la última
local COMBAT = { list = true, req = true, data = true, last = true }
local KEYS = {
    fields = "table", handler = "function",
    -- seguridad (AllowAddonMessage): las marcas de siempre
    tagField = "number", bootstrap = "boolean", open = "boolean", channel = "boolean", remoteData = "boolean",
    -- cola y caducidad (HU:Send); ttl = false: no caduca nunca
    queue = "string", ttl = "number", latestWins = "boolean", skipLocked = "boolean",
    combat = "string",
}

-- Campos con nombre: m.autor es f[2] sin crear otra tabla; el campo con «*» es el resto, ~ incluidas
local function FieldMeta(cmd, fields)
    local idx, star = {}, nil
    for i, name in ipairs(fields) do
        if type(name) ~= "string" or name == "" then error(cmd .. ": campo " .. i .. " sin nombre", 3) end
        local base, isStar = name:match("^([%a_][%w_]*)(%*?)$")
        if not base then error(cmd .. ": nombre de campo no válido: " .. name, 3) end
        if star then error(cmd .. ": el campo con * tiene que ser el último", 3) end
        if idx[base] then error(cmd .. ": campo repetido: " .. base, 3) end
        idx[base] = i
        if isStar == "*" then star = i end
    end
    return { __index = function(f, k)
        local i = idx[k]
        if not i then return nil end
        if i == star then return table.concat(f, "~", i) end
        return rawget(f, i)
    end }
end

-- Declara una orden: todo lo suyo en un sitio. Ver ARCHITECTURE.md, «Registro de órdenes» [+ARCHITECTURE.md]
function HU:RegisterMessage(cmd, spec)
    if type(cmd) ~= "string" or not cmd:match("^%u%u?$") then error("orden no válida: " .. tostring(cmd), 2) end
    if HU.msgs[cmd] then error(cmd .. ": orden ya registrada", 2) end
    spec = spec or {}
    for k, v in pairs(spec) do
        local want = KEYS[k]
        if not want then error(cmd .. ": clave desconocida: " .. tostring(k), 2) end
        if type(v) ~= want and not (k == "ttl" and v == false) then
            error(cmd .. ": " .. k .. " tiene que ser " .. want, 2)
        end
    end
    if spec.queue and not QUEUES[spec.queue] then error(cmd .. ": cola desconocida: " .. spec.queue, 2) end
    if spec.combat and not COMBAT[spec.combat] then error(cmd .. ": combate desconocido: " .. spec.combat, 2) end
    if (spec.bootstrap or spec.remoteData) and not spec.tagField then
        error(cmd .. ": bootstrap y remoteData necesitan tagField", 2)
    end
    if spec.fields then spec.meta = FieldMeta(cmd, spec.fields) end
    spec.cmd = cmd
    spec.prefix = QUEUES[spec.queue or "normal"]
    HU.msgs[cmd] = spec
    if spec.handler then HU.comm[cmd] = spec.handler end
    return spec
end

-- El prefijo por el que sale una orden (HU20B para los datos grandes)
function HU:MessagePrefix(cmd)
    local spec = HU.msgs[cmd]
    return spec and spec.prefix == "HU20B" and HU.PREFIX_B or HU.PREFIX
end

HU:Module("Protocol", { })
