-- Guild Union - Paquete EV: los eventos de la sección Eventos (UnionCalendar.lua) y quién se apunta, de todas las hermandades [+ARCHITECTURE.md]
--   e<id>  del creador: «hora en base 36,tipo,formato,nivel mínimo,icono,título,descripción»; formato, en una banda (tipo
--          raid), su tamaño (10, 20 o 40) y «i» si es por invitación; en los demás, vacío (editarlo: otra vez; eliminarlo: vacío)
--   s<id>  de quien se apunta: su rol, «T», «H» o «D» (desapuntarse: datos vacíos)
--   p<id>  del creador: «1», fijado arriba en Eventos para todos (quitarlo: vacío). De otro que no sea el creador, no cuenta
-- Son propuestas (Net/Packs.lua): cada uno manda lo suyo y lo de las otras hermandades llega con su paquete
local _, HU = ...

local DAY = 86400
-- (el evento vive en la red hasta 30 días después de su hora: el mes del calendario lo enseña hasta entonces, y las raids
-- de quien organiza se guardan lo mismo, UnionCalendar.lua. Lo apuntado, 45 días desde que se propuso. Un evento borrado,
-- 90: tiene que durar más que el evento, o una copia vieja de quien estuvo fuera lo resucitaría al volver; así vale para
-- eventos puestos hasta 60 días antes)
local EVENT_LIVES, SIGNUP_LIVES, DELETED_LIVES = 30 * DAY, 45 * DAY, 90 * DAY
HU.EVENT_LIVES = EVENT_LIVES
local ID_MAX, TITLE_MAX, DESC_MAX, ICON_MAX = 20, 40, 90, 40
-- (lo que cabe: los datos de una propuesta y su línea del paquete, «Nombre-Reino,clave,hora,datos»: DATA_MAX y PART de
-- Net/Packs.lua. Una línea más larga no se publicaría a las otras hermandades)
local DATA_MAX, LINE_MAX = 180, 200
local KINDS = { raid = true, dungeon = true, pvp = true, social = true, other = true }
-- (los tamaños de banda de Forever: DifficultyUtil.ID.RaidClassic10Normal, RaidClassic20Normal y Raid40)
local SIZES = { [10] = true, [20] = true, [40] = true }
local ROLE_CODE = { TANK = "T", HEALER = "H", DAMAGER = "D" }
local CODE_ROLE = { T = "TANK", H = "HEALER", D = "DAMAGER" }
local ICONS = "Interface\\Icons\\"

-- (los datos de un evento con su forma: hora, tipo, nivel, icono, título, descripción y, en una banda, su tamaño y si es
-- por invitación; nil si no la tienen)
local function Parse(d)
    local t36, kind, size, inv, lv, icon, title, desc = d:match("^([0-9a-z]+),(%l+),(%d*)(i?),(%d%d?),([%w_]*),([^,]+),(.*)$")
    local t, level, n = t36 and #t36 <= 8 and tonumber(t36, 36), tonumber(lv), tonumber(size)
    local band = kind == "raid"
    if not (t and KINDS[kind] and level <= 60 and #icon <= ICON_MAX and #title <= TITLE_MAX and #desc <= DESC_MAX
        and (band and SIZES[n] or (not band and size == "" and inv == ""))) then return nil end
    return t, kind, level, icon, title, desc, band and n or nil, inv == "i"
end

HU:RegisterPackSet("EV", {
    chunks = 16,
    proposals = true,
    validate = function(_, key, d)
        local what, id = key:match("^([esp])(%w+)$")
        if not id or #id > ID_MAX then return false end
        if what == "s" then return CODE_ROLE[d] ~= nil end
        if what == "p" then return d == "1" end
        return Parse(d) ~= nil
    end,
    -- (vivo: el evento, hasta 30 días después de su hora; uno borrado, 90 días desde que se borró; lo apuntado (y lo
    -- desapuntado) y el fijado, 45 desde que se propuso)
    alive = function(_, key, d, t, now)
        local isEvent = key:sub(1, 1) == "e"
        local at = isEvent and tonumber(d:match("^(%w+),") or "", 36)
        if at then return at + EVENT_LIVES >= now end
        if isEvent and d == "" then return t + DELETED_LIVES >= now end
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

-- Mi evento, a la red: { t, kind, minLevel, icon (la ruta entera), title, desc } y, en una banda, size (10, 20 o 40; si
-- no, 40) e invite (por invitación). Lo que no cabe de la descripción (y, si hiciera falta, del título) se corta. Editarlo
-- es proponerlo otra vez con el mismo id. Devuelve si ha podido
function HU:ProposeEvent(id, e)
    id = tostring(id or "")
    local key, me = "e" .. id, self:Me()
    if not (me and id:match("^%w+$") and #id <= ID_MAX) then return false end
    local icon = tostring(e.icon or "")
    icon = icon:sub(1, #ICONS):lower() == ICONS:lower() and icon:sub(#ICONS + 1) or ""
    if #icon > ICON_MAX or icon:find("[^%w_]") then icon = "" end
    local lv = math.max(0, math.min(60, math.floor(tonumber(e.minLevel) or 0)))
    local kind = KINDS[e.kind] and e.kind or "other"
    local fmt = kind == "raid" and ((SIZES[e.size] and e.size or 40) .. (e.invite and "i" or "")) or ""
    local head = HU.B36(e.t) .. "," .. kind .. "," .. fmt .. "," .. lv .. "," .. icon .. ","
    local room = math.min(DATA_MAX, LINE_MAX - #me - #key - #HU.B36(HU.StampNow()) - 3) - #head - 1
    local title = Cut(Clean(e.title), math.min(TITLE_MAX, room))
    local desc = Cut(Clean(e.desc, true), math.min(DESC_MAX, room - #title))
    return self:Propose("EV", key, head .. title .. "," .. desc)
end

-- Elimino mi evento: su línea, vacía (borrada con su hora: no vuelve con una más vieja). Lo apuntado se queda hasta que
-- caduca: sin el evento no se ve. Devuelve si ha podido
function HU:ProposeEventDelete(id)
    id = tostring(id or "")
    return id:match("^%w+$") ~= nil and #id <= ID_MAX and self:Propose("EV", "e" .. id, "")
end

-- Me apunto a un evento con mi rol (TANK, HEALER o DAMAGER) o, sin rol, me desapunto. Devuelve si ha podido
function HU:ProposeSignup(id, role)
    return self:Propose("EV", "s" .. tostring(id or ""), role and (ROLE_CODE[role] or "D") or "")
end

-- Fijo arriba mi evento para todos, o lo quito (Jorge, 25/11: «para todos»). Devuelve si ha podido
function HU:ProposeEventPin(id, on)
    id = tostring(id or "")
    return id:match("^%w+$") ~= nil and #id <= ID_MAX and self:Propose("EV", "p" .. id, on and "1" or "")
end

-- Lo que hay en la red, de todas las hermandades: los eventos { id, tag, who, pt (cuándo se propuso), t, kind, minLevel,
-- icon, title, desc, pinned, size, invite } y quién se apunta { id, tag, who, role }. Fijado: solo si lo fijó su creador
function HU:PackedEvents()
    local evs, signs, pins = {}, {}, {}
    for _, p in ipairs(self:Proposals("EV")) do
        local what, id = p.k:match("^([esp])(%w+)$")
        local t, kind, lv, icon, title, desc, size, invite = Parse(what == "e" and p.d or "")
        if t then
            evs[#evs + 1] = { id = id, tag = p.tag, who = p.n, pt = p.t, t = t, kind = kind, minLevel = lv > 1 and lv or nil,
                icon = icon ~= "" and (ICONS .. icon) or nil, title = title, desc = desc, size = size, invite = invite or nil }
        end
        if what == "s" then signs[#signs + 1] = { id = id, tag = p.tag, who = p.n, role = CODE_ROLE[p.d] } end
        if what == "p" then pins[id .. "|" .. p.n] = true end
    end
    for _, e in ipairs(evs) do e.pinned = pins[e.id .. "|" .. e.who] end
    return evs, signs
end

HU:Module("Packs/Events", { "Core", "Net/Packs", "Net/RosterSync" })
