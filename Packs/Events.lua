-- Guild Union - Paquete EV: los eventos del Calendario (UnionCalendar.lua) y quién se apunta, de todas las hermandades [+ARCHITECTURE.md]
--   e<id>  del creador: «hora en base 36,tipo,nivel mínimo,icono,título,descripción»
--   s<id>  de quien se apunta: su rol, «T», «H» o «D» (desapuntarse: datos vacíos)
-- Son propuestas (Net/Packs.lua): cada uno manda lo suyo y lo de las otras hermandades llega con su paquete
local _, HU = ...

local DAY = 86400
local EVENT_LIVES, SIGNUP_LIVES = 7 * DAY, 45 * DAY
local ID_MAX, TITLE_MAX, DESC_MAX, ICON_MAX = 20, 40, 90, 40
-- (lo que cabe: los datos de una propuesta y su línea del paquete, «Nombre-Reino,clave,hora,datos»: DATA_MAX y PART de
-- Net/Packs.lua. Una línea más larga no se publicaría a las otras hermandades)
local DATA_MAX, LINE_MAX = 180, 200
local KINDS = { raid = true, dungeon = true, pvp = true, social = true, other = true }
local ROLE_CODE = { TANK = "T", HEALER = "H", DAMAGER = "D" }
local CODE_ROLE = { T = "TANK", H = "HEALER", D = "DAMAGER" }
local ICONS = "Interface\\Icons\\"

-- (los datos de un evento con su forma: hora, tipo, nivel, icono, título y descripción; nil si no la tienen)
local function Parse(d)
    local t36, kind, lv, icon, title, desc = d:match("^([0-9a-z]+),(%l+),(%d%d?),([%w_]*),([^,]+),(.*)$")
    local t, level = t36 and #t36 <= 8 and tonumber(t36, 36), tonumber(lv)
    if not (t and KINDS[kind] and level <= 60 and #icon <= ICON_MAX and #title <= TITLE_MAX and #desc <= DESC_MAX) then return nil end
    return t, kind, level, icon, title, desc
end

HU:RegisterPackSet("EV", {
    chunks = 16,
    proposals = true,
    validate = function(_, key, d)
        local what, id = key:match("^([es])(%w+)$")
        if not id or #id > ID_MAX then return false end
        if what == "s" then return CODE_ROLE[d] ~= nil end
        return Parse(d) ~= nil
    end,
    -- (vivo: el evento, hasta 7 días después de su hora; lo apuntado y lo borrado, 45 días desde que se propuso)
    alive = function(_, key, d, t, now)
        local at = key:sub(1, 1) == "e" and tonumber(d:match("^(%w+),") or "", 36)
        if at then return at + EVENT_LIVES >= now end
        return t + SIGNUP_LIVES >= now
    end,
    onChange = function() HU:Changed("calendar") end,
})

-- (sin lo que no puede ir en una propuesta: ~ ; | ni saltos de línea; en el título, tampoco comas)
local function Clean(s, commas)
    s = tostring(s or ""):gsub("[~;|%c]", " ")
    if not commas then s = s:gsub(",", " ") end
    return HU.Trim((s:gsub("%s%s+", " ")))
end
local function Cut(s, n) return HU.Trim(HU.Utf8Cut(s, math.max(0, n))) end

-- Mi evento, a la red: { t, kind, minLevel, icon (la ruta entera), title, desc }. Lo que no cabe de la descripción (y, si
-- hiciera falta, del título) se corta. Devuelve si ha podido
function HU:ProposeEvent(id, e)
    id = tostring(id or "")
    local key, me = "e" .. id, self:Me()
    if not (me and id:match("^%w+$") and #id <= ID_MAX) then return false end
    local icon = tostring(e.icon or "")
    icon = icon:sub(1, #ICONS):lower() == ICONS:lower() and icon:sub(#ICONS + 1) or ""
    if #icon > ICON_MAX or icon:find("[^%w_]") then icon = "" end
    local lv = math.max(0, math.min(60, math.floor(tonumber(e.minLevel) or 0)))
    local head = HU.B36(e.t) .. "," .. (KINDS[e.kind] and e.kind or "other") .. "," .. lv .. "," .. icon .. ","
    local room = math.min(DATA_MAX, LINE_MAX - #me - #key - #HU.B36(HU.StampNow()) - 3) - #head - 1
    local title = Cut(Clean(e.title), math.min(TITLE_MAX, room))
    local desc = Cut(Clean(e.desc, true), math.min(DESC_MAX, room - #title))
    return self:Propose("EV", key, head .. title .. "," .. desc)
end

-- Me apunto a un evento con mi rol (TANK, HEALER o DAMAGER) o, sin rol, me desapunto. Devuelve si ha podido
function HU:ProposeSignup(id, role)
    return self:Propose("EV", "s" .. tostring(id or ""), role and (ROLE_CODE[role] or "D") or "")
end

-- Lo que hay en la red, de todas las hermandades: los eventos { id, tag, who, pt (cuándo se propuso), t, kind, minLevel,
-- icon, title, desc } y quién se apunta { id, tag, who, role }
function HU:PackedEvents()
    local evs, signs = {}, {}
    for _, p in ipairs(self:Proposals("EV")) do
        local what, id = p.k:match("^([es])(%w+)$")
        local t, kind, lv, icon, title, desc = Parse(what == "e" and p.d or "")
        if t then
            evs[#evs + 1] = { id = id, tag = p.tag, who = p.n, pt = p.t, t = t, kind = kind, minLevel = lv > 1 and lv or nil,
                icon = icon ~= "" and (ICONS .. icon) or nil, title = title, desc = desc }
        end
        if what == "s" then signs[#signs + 1] = { id = id, tag = p.tag, who = p.n, role = CODE_ROLE[p.d] } end
    end
    return evs, signs
end

HU:Module("Packs/Events", { "Core", "Net/Packs", "Net/RosterSync" })
