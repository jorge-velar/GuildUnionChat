-- Guild Union - Paquete TR: las solicitudes de Comercio de toda la unión, como propuestas (WU) [+ARCHITECTURE.md]
--   o<id>  la solicitud, de quien la pide: «estado,cant,mats,propina,pública,para quién,objeto» (estado o/g)
--   a<id>  la respuesta, de quien la hace o de para quien es: t (la acepto), d (hecha), r (la rechazo); sin datos, la suelto
local _, HU = ...

local DAY = 86400
local ID_MAX, DATA_MAX = 20, 180
-- (la línea entera del paquete, «Nombre,clave,hora,datos», no puede pasar de 200 (PART, Net/Packs.lua): si no, no se
-- publica y no llega a las otras hermandades. La hora, en base 36, son 6 letras hasta 2038: se cuentan 7)
local LINE_MAX, LINE_EXTRA = 200, 3 + 7
local ANSWERS = { t = true, d = true, r = true }

-- (lo que no puede ir en los datos de una propuesta: ~ ; | ni saltos ni otros códigos de control)
local function Clean(s) return HU.Trim((tostring(s or ""):gsub("[~;|%c]", ""))) end
local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")) end

-- Lo que se pide, para la red: i<objeto>:<nombre> (un enlace de objeto), s<hechizo>:<nombre> (de hechizo o
-- encantamiento) o t:<texto> (escrito a mano)
local function ItemCode(item)
    item = tostring(item or "")
    local kind, id, name = item:match("|H(%a+):(%d+)[^|]*|h%[(.-)%]|h")
    if kind == "item" then return "i" .. id .. ":" .. Clean(name) end
    if kind == "spell" or kind == "enchant" then return "s" .. id .. ":" .. Clean(name) end
    return "t:" .. Clean(Plain(item))
end

-- Los datos de la línea o<id> de una solicitud { id, who, state, qty, mats, tip, pub, to, item }: lo que se pide se recorta
-- para que quepan en la propuesta y en la línea del paquete
function HU.TradeOrderData(r)
    local head = table.concat({ r.state == "gone" and "g" or "o",
        string.format("%.0f", math.max(1, math.min(999, math.floor(tonumber(r.qty) or 1)))),
        r.mats and "1" or "0",
        tonumber(r.tip) and string.format("%.0f", math.max(0, math.floor(tonumber(r.tip)))) or "-",
        r.pub and "1" or "0",
        (not r.pub and r.to) and (Clean(r.to):gsub(",", "")) or "-" }, ",")
    local room = math.min(DATA_MAX, LINE_MAX - LINE_EXTRA - #tostring(r.who or HU:Me() or "") - #("o" .. tostring(r.id or "")))
    return head .. "," .. HU.Utf8Cut(ItemCode(r.item), room - #head - 1)
end

-- (los datos de una o<id>, o nil si no tienen su forma)
local function ParseOrder(d)
    local st, qty, mats, tip, pub, to, code = tostring(d or ""):match("^([og]),(%d+),([01]),([^,]+),([01]),([^,]+),(.+)$")
    if not st or #qty > 3 or tonumber(qty) < 1 then return nil end
    if tip ~= "-" and (#tip > 10 or not tip:match("^%d+$")) then return nil end
    -- (pública, sin a quién; privada, con a quién)
    if (pub == "1") ~= (to == "-") or (to ~= "-" and not HU.SafeName(to)) then return nil end
    if not (code:match("^[is]%d+:") or code:match("^t:.")) or code:find("%c") then return nil end
    return { st = st, qty = tonumber(qty), mats = mats == "1", tip = tip ~= "-" and tonumber(tip) or nil, pub = pub == "1",
        to = to ~= "-" and to or nil, code = code }
end

HU:RegisterPackSet("TR", {
    chunks = 16, proposals = true, keep = 30 * DAY,
    validate = function(_, key, data)
        local kind, id = key:match("^([oa])(%w+)$")
        if not kind or #id > ID_MAX then return false end
        if kind == "a" then return ANSWERS[data] == true end
        return ParseOrder(data) ~= nil
    end,
    onChange = function() HU:Changed("trade") end,
})

-- El enlace de lo que se pide: el del juego si lo tiene; si no, uno con su nombre (como los de prueba). Lo escrito a mano,
-- tal cual
local links = {} -- [código] = el enlace que ha dado el juego
local function ItemLink(code)
    if links[code] then return links[code] end
    local kind, id, name = code:match("^([is])(%d+):(.*)$")
    if not kind then return (code:gsub("^t:", "")) end
    local ok, link
    if kind == "i" then
        local _
        ok, _, link = pcall(C_Item and C_Item.GetItemInfo, tonumber(id))
    else
        ok, link = pcall(C_Spell and C_Spell.GetSpellLink, tonumber(id))
    end
    if ok and type(link) == "string" and not HU.Secret(link) and link:find("|H", 1, true) then
        links[code] = link
        return link
    end
    if kind == "i" then return "|cffffffff|Hitem:" .. id .. "::::::::60:::::::|h[" .. name .. "]|h|r" end
    return "|cff71d5ff|Hspell:" .. id .. "|h[" .. name .. "]|h|r"
end

-- El estado de una solicitud con sus respuestas, en este orden: cancelada; hecha por alguien; aceptada (gana la más
-- antigua); rechazada (una privada, por para quien es); abierta. En las públicas cuentan las de cualquiera menos quien la
-- pide; en las privadas, solo las de para quien es [+ARCHITECTURE.md]
local function Resolve(r, answers)
    r.state = r.st == "g" and "gone" or "open"
    if r.state == "gone" then return end
    local who, to, best = r.who:lower(), r.to and r.to:lower(), {}
    for _, a in ipairs(answers or {}) do
        local n, b = a.n:lower(), best[a.d]
        if n ~= who and (r.pub or n == to) and (not b or a.t < b.t or (a.t == b.t and n < b.n:lower())) then best[a.d] = a end
    end
    if best.d then r.state, r.taker, r.takenAt = "done", best.d.n, best.d.t
    elseif best.t then r.state, r.taker, r.takenAt = "taken", best.t.n, best.t.t
    elseif not r.pub and best.r then r.state = "gone" end
end

-- (dos solicitudes con el mismo número: vale la de quien sale en él, NewId empieza por su huella; si no, la más antigua)
local function Owns(name, id) return HU.Hash(name):sub(1, 4) == id:sub(1, 4) end
local function Better(e, old, id)
    local a, b = Owns(e.n, id), Owns(old.who, id)
    if a ~= b then return a end
    return e.t < old.t
end

-- Las solicitudes de toda la unión que puedo ver (las públicas, y las privadas que pido, me piden o hago), de la más
-- antigua a la más nueva: { id, who, tag, t, item, qty, mats, tip, pub, to, state, taker, takenAt, data }
function HU:TradeRequests()
    local me = self:MeKey() or "?"
    local orders, answers = {}, {}
    for _, e in ipairs(self:Proposals("TR")) do
        local kind, id = e.k:sub(1, 1), e.k:sub(2)
        if kind == "a" then
            answers[id] = answers[id] or {}
            table.insert(answers[id], e)
        else
            local r = ParseOrder(e.d)
            local old = orders[id]
            if r and (not old or Better(e, old, id)) then
                r.id, r.who, r.tag, r.t, r.data, r.item = id, e.n, e.tag, e.t, e.d, ItemLink(r.code)
                orders[id] = r
            end
        end
    end
    local out = {}
    for id, r in pairs(orders) do
        Resolve(r, answers[id])
        if r.pub or r.who:lower() == me or (r.to and r.to:lower() == me) or (r.taker and r.taker:lower() == me) then
            out[#out + 1] = r
        end
    end
    table.sort(out, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end)
    return out
end

-- Pedir (o volver a mandar) una solicitud mía; cancelarla (la misma, con estado «g»); mi respuesta a una («t», «d», «r»;
-- «» la suelta). Devuelven si ha podido
function HU:TradeOrder(r) return self:Propose("TR", "o" .. tostring(r.id), HU.TradeOrderData(r)) end
function HU:TradeCancel(r) return self:Propose("TR", "o" .. tostring(r.id), "g" .. (r.data or HU.TradeOrderData(r)):sub(2)) end
function HU:TradeAnswer(id, what) return self:Propose("TR", "a" .. tostring(id), what or "") end

HU:Module("Packs/Trade", { "Core", "Lists", "Net/Packs" })
