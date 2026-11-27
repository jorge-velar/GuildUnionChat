-- Guild Union - Paquete TR: los anuncios de Comercio de toda la unión, como propuestas (WU) [+ARCHITECTURE.md]
--   o<id>  el anuncio, de quien lo pone: «estado,tipo,cant,mats,propina,pública,para quién,caduca,objeto» (estado o/g/s;
--          tipo p pedir, v vender; caduca, la hora en base 36 o «-»)
--   a<id>  la respuesta, de quien la hace, de para quien es o, en una venta, de cada interesado: t (la acepto / me
--          interesa), d (hecha), r (la rechazo); sin datos, la suelto
local _, HU = ...

local DAY = 86400
local KEEP = 30 * DAY
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

-- Los datos de la línea o<id> de un anuncio { id, who, state, sale, qty, mats, tip, pub, to, exp, item }: una venta va
-- siempre al tablón y sin materiales; lo que se pide se recorta para que quepan en la propuesta y en la línea del paquete
function HU.TradeOrderData(r)
    local pub = r.pub or r.sale
    local head = table.concat({ (r.state == "gone" and "g") or (r.state == "sold" and r.sale and "s") or "o",
        r.sale and "v" or "p",
        string.format("%.0f", math.max(1, math.min(999, math.floor(tonumber(r.qty) or 1)))),
        (r.mats and not r.sale) and "1" or "0",
        tonumber(r.tip) and string.format("%.0f", math.max(0, math.floor(tonumber(r.tip)))) or "-",
        pub and "1" or "0",
        (not pub and r.to) and (Clean(r.to):gsub(",", "")) or "-",
        tonumber(r.exp) and HU.B36(r.exp) or "-" }, ",")
    local room = math.min(DATA_MAX, LINE_MAX - LINE_EXTRA - #tostring(r.who or HU:Me() or "") - #("o" .. tostring(r.id or "")))
    return head .. "," .. HU.Utf8Cut(ItemCode(r.item), room - #head - 1)
end

-- (los datos de una o<id>, o nil si no tienen su forma)
local function ParseOrder(d)
    local st, kind, qty, mats, tip, pub, to, exp, code = tostring(d or "")
        :match("^([ogs]),([pv]),(%d+),([01]),([^,]+),([01]),([^,]+),([^,]+),(.+)$")
    if not st or #qty > 3 or tonumber(qty) < 1 then return nil end
    if tip ~= "-" and (#tip > 10 or not tip:match("^%d+$")) then return nil end
    -- (pública, sin a quién; privada, con a quién. Una venta, siempre al tablón; «vendida», solo una venta)
    if (pub == "1") ~= (to == "-") or (to ~= "-" and not HU.SafeName(to)) then return nil end
    local sale = kind == "v"
    if (sale and pub ~= "1") or (st == "s" and not sale) then return nil end
    if exp ~= "-" and not (#exp <= 7 and exp:match("^[%da-z]+$")) then return nil end
    if not (code:match("^[is]%d+:") or code:match("^t:.")) or code:find("%c") then return nil end
    return { st = st, sale = sale, qty = tonumber(qty), mats = mats == "1", tip = tip ~= "-" and tonumber(tip) or nil,
        pub = pub == "1", to = to ~= "-" and to or nil, exp = exp ~= "-" and tonumber(exp, 36) or nil, code = code }
end

-- (la hora a la que caduca un anuncio, de sus datos; nil si no caduca: las privadas y las ya aceptadas)
local function ExpiryOf(d)
    local exp = d:match("^[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,([%da-z]+),")
    return exp and tonumber(exp, 36)
end

HU:RegisterPackSet("TR", {
    chunks = 16, proposals = true, keep = KEEP,
    validate = function(_, key, data)
        local kind, id = key:match("^([oa])(%w+)$")
        if not kind or #id > ID_MAX then return false end
        if kind == "a" then return ANSWERS[data] == true end
        return ParseOrder(data) ~= nil
    end,
    -- (vivo: 30 días desde su hora y, un anuncio con caducidad, hasta esa hora: luego ni se ve ni se publica)
    alive = function(_, key, data, t, now)
        if t < now - KEEP then return false end
        if key:sub(1, 1) ~= "o" or data == "" then return true end
        local exp = ExpiryOf(data)
        return not exp or now < exp
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
-- pide; en las privadas, solo las de para quien es. Una venta: abierta, vendida o eliminada, y quiénes la quieren
-- [+ARCHITECTURE.md]
local function Resolve(r, answers)
    r.state = (r.st == "g" and "gone") or (r.st == "s" and "sold") or "open"
    local who = r.who:lower()
    if r.sale then
        local list = {}
        for _, a in ipairs(answers or {}) do
            if a.d == "t" and a.n:lower() ~= who then list[#list + 1] = a end
        end
        table.sort(list, function(x, y)
            if x.t ~= y.t then return x.t < y.t end
            return x.n:lower() < y.n:lower()
        end)
        r.buyers = {}
        for i, a in ipairs(list) do r.buyers[i] = a.n end
        if r.state == "sold" then r.soldAt = r.t end
        return
    end
    if r.state == "gone" then return end
    local to, best = r.to and r.to:lower(), {}
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

-- Los anuncios de toda la unión que puedo ver (los del tablón, y las privadas que pido, me piden o hago), del más
-- antiguo al más nuevo: { id, who, tag, t, item, sale, qty, mats, tip, pub, to, exp, state, taker, takenAt, buyers,
-- soldAt, data }
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

-- Poner (o volver a mandar) un anuncio mío; el mismo con otro estado (g, cancelado o eliminado; s, vendido: solo una
-- venta) o sin caducidad (una del tablón ya aceptada: que no se borre a medias); mi respuesta a uno («t», «d», «r»; «»
-- la suelta). Devuelven si han podido
local function Again(r, d) return HU:Propose("TR", "o" .. tostring(r.id), d) end
local function Data(r) return r.data or HU.TradeOrderData(r) end
function HU:TradeOrder(r) return self:Propose("TR", "o" .. tostring(r.id), HU.TradeOrderData(r)) end
function HU:TradeCancel(r) return Again(r, "g" .. Data(r):sub(2)) end
function HU:TradeSold(r) return r.sale == true and Again(r, "s" .. Data(r):sub(2)) end
function HU:TradeKeep(r)
    return Again(r, (Data(r):gsub("^([^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*),[^,]*,", "%1,-,", 1)))
end
function HU:TradeAnswer(id, what) return self:Propose("TR", "a" .. tostring(id), what or "") end

HU:Module("Packs/Trade", { "Core", "Lists", "Net/Packs", "Net/RosterSync" })
