-- Guild Union - Paquete EV: los eventos de la sección Eventos (UnionCalendar.lua) y quién se apunta, de todas las hermandades [+ARCHITECTURE.md]
--   e<id>  del creador: «hora en base 36,tipo,formato,nivel mínimo,icono,título,descripción»; formato, en una banda (tipo
--          raid), su tamaño (10, 20 o 40) y «i» si es por invitación; en los demás, vacío (editarlo: otra vez; eliminarlo: vacío)
--   s<id>  de quien se apunta: su rol, «T», «H» o «D», y «r» detrás si va de reserva (desapuntarse: datos vacíos)
--   p<id>  del creador: «1», fijado arriba en Eventos para todos (quitarlo: vacío). De otro que no sea el creador, no cuenta
--   u<id>_<n>  del creador de una banda: quién de la reserva ha subido a la raid, «Nombre-Reino,…», en hasta 8 líneas
--   i<id>_<n>  del creador de una banda por invitación: a quién invita, igual
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
-- (las listas de nombres del creador, u e i: hasta 8 líneas; cada nombre, sin comas ni espacios y de 48 como mucho. Al
-- mandarlas, 3 ya y el resto de una en una cada 7 s: quien las recibe tira lo que pase de 5 seguidas o de 10 por minuto
-- (WU_BURST, WU_RATE de Net/Packs.lua), y el evento y el apuntado salen a la vez) [+ARCHITECTURE.md]
local LIST_PARTS, NAME_MAX = 8, 48
local SEND_NOW, SEND_STEP = 3, 7

-- (una lista de nombres con su forma: «Nombre-Reino,Nombre-Reino,…»)
local function GoodNames(d)
    for n in (d .. ","):gmatch("([^,]*),") do
        if n == "" or #n > NAME_MAX or n:find("[%s%c]") then return false end
    end
    return true
end

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
        if not what then
            local lid = key:match("^[iu](%w+)_[1-8]$")
            return lid ~= nil and #lid <= ID_MAX and GoodNames(d)
        end
        if #id > ID_MAX then return false end
        if what == "s" then return CODE_ROLE[d:sub(1, 1)] ~= nil and (#d == 1 or d:sub(2) == "r") end
        if what == "p" then return d == "1" end
        return Parse(d) ~= nil
    end,
    -- (vivo: el evento, hasta 30 días después de su hora; uno borrado, 90 días desde que se borró; lo apuntado (y lo
    -- desapuntado), el fijado y las listas, 45 desde que se propuso)
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

-- Me apunto a un evento con mi rol (TANK, HEALER o DAMAGER), de reserva si reserve, o, sin rol, me desapunto. Devuelve si
-- ha podido
function HU:ProposeSignup(id, role, reserve)
    return self:Propose("EV", "s" .. tostring(id or ""), role and ((ROLE_CODE[role] or "D") .. (reserve and "r" or "")) or "")
end

-- Una lista de nombres de mi evento (letra u o i), a la red: limpios, sin repetir y por orden, en las líneas que hagan falta
-- (lo que quepa en cada una); solo las que cambian, y las que sobran, vacías. Sin pasarse del tope de quien las recibe:
-- SEND_NOW ya y las demás cada SEND_STEP s; si mientras tanto la lista cambia otra vez, las que esperaban ya no salen
-- (la nueva compara con lo que hay y manda lo que falte). Devuelve si ha podido [+ARCHITECTURE.md]
local listGen = {}
local function ProposeList(self, letter, id, names)
    id = tostring(id or "")
    local me = self:Me()
    if not (me and self.myTag and id:match("^%w+$") and #id <= ID_MAX) then return false end
    local list, seen = {}, {}
    for _, n in ipairs(names or {}) do
        n = type(n) == "string" and HU.SafeName(HU.Trim(n)) or nil
        if n and not seen[n:lower()] and #n <= NAME_MAX and not n:find("[%s,]") then seen[n:lower()] = true; list[#list + 1] = n end
    end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    -- (cada línea, «Nombre-Reino,clave,hora,datos», en LINE_MAX; los datos, en DATA_MAX)
    local room = math.min(DATA_MAX, LINE_MAX - #me - #(letter .. id .. "_1") - #HU.B36(HU.StampNow()) - 3)
    local parts = { "" }
    for _, n in ipairs(list) do
        local d = parts[#parts]
        if d ~= "" and #d + 1 + #n > room then parts[#parts + 1] = n else parts[#parts] = d == "" and n or (d .. "," .. n) end
    end
    if #parts > LIST_PARTS then return false end
    local cur = {}
    for _, p in ipairs(self:Proposals("EV")) do
        local l, lid, k = p.k:match("^([iu])(%w+)_(%d)$")
        if l == letter and lid == id and p.tag == self.myTag and p.n == me then cur[tonumber(k)] = p.d end
    end
    local todo = {}
    for k = 1, LIST_PARTS do
        if (parts[k] or "") ~= (cur[k] or "") then todo[#todo + 1] = { letter .. id .. "_" .. k, parts[k] or "" } end
    end
    local g = letter .. id
    listGen[g] = (listGen[g] or 0) + 1
    local gen = listGen[g]
    for k, p in ipairs(todo) do
        if k <= SEND_NOW then
            if not self:Propose("EV", p[1], p[2]) then return false end
        else
            HU.After((k - SEND_NOW) * SEND_STEP, function() if listGen[g] == gen then self:Propose("EV", p[1], p[2]) end end)
        end
    end
    return true
end

-- De mi banda: quién de la reserva ha subido a la raid (lo decide quien la organiza; Jorge, 25/11: «reserva, decide el
-- líder»). Devuelve si ha podido
function HU:ProposeEventPromoted(id, names) return ProposeList(self, "u", id, names) end
-- De mi banda por invitación: a quién invito (Jorge, 25/11: «opción a hacer público para todos o por invite»; quien no
-- está invitado no la ve). Vacía, la quita. Devuelve si ha podido
function HU:ProposeEventInvites(id, names) return ProposeList(self, "i", id, names) end

-- Fijo arriba mi evento para todos, o lo quito (Jorge, 25/11: «para todos»). Devuelve si ha podido
function HU:ProposeEventPin(id, on)
    id = tostring(id or "")
    return id:match("^%w+$") ~= nil and #id <= ID_MAX and self:Propose("EV", "p" .. id, on and "1" or "")
end

-- (los nombres de una lista, sus líneas en orden: las que falten, aún no han llegado)
local function Names(parts)
    local out = {}
    for k = 1, LIST_PARTS do
        for n in ((parts and parts[k]) or ""):gmatch("[^,]+") do out[#out + 1] = n end
    end
    return out
end

-- Lo que hay en la red, de todas las hermandades: los eventos { id, tag, who, pt (cuándo se propuso), t, kind, minLevel,
-- icon, title, desc, pinned, size, invite, invites, promoted } y quién se apunta { id, tag, who, role, reserve }. Fijado y
-- listas (invites, a quién invita; promoted, quién ha subido de la reserva): solo si son de su creador
function HU:PackedEvents()
    local evs, signs, pins, lists = {}, {}, {}, {}
    for _, p in ipairs(self:Proposals("EV")) do
        local what, id = p.k:match("^([esp])(%w+)$")
        local t, kind, lv, icon, title, desc, size, invite = Parse(what == "e" and p.d or "")
        if t then
            evs[#evs + 1] = { id = id, tag = p.tag, who = p.n, pt = p.t, t = t, kind = kind, minLevel = lv > 1 and lv or nil,
                icon = icon ~= "" and (ICONS .. icon) or nil, title = title, desc = desc, size = size, invite = invite or nil }
        end
        if what == "s" then
            signs[#signs + 1] = { id = id, tag = p.tag, who = p.n, role = CODE_ROLE[p.d:sub(1, 1)], reserve = p.d:sub(2) == "r" or nil }
        end
        if what == "p" then pins[id .. "|" .. p.n] = true end
        local l, lid, k = p.k:match("^([iu])(%w+)_(%d)$")
        if l then
            local key = lid .. "|" .. p.n
            lists[key] = lists[key] or { i = {}, u = {} }
            lists[key][l][tonumber(k)] = p.d
        end
    end
    for _, e in ipairs(evs) do
        local key = e.id .. "|" .. e.who
        e.pinned = pins[key]
        e.invites, e.promoted = Names(lists[key] and lists[key].i), Names(lists[key] and lists[key].u)
    end
    return evs, signs
end

HU:Module("Packs/Events", { "Core", "Net/Packs", "Net/RosterSync" })
