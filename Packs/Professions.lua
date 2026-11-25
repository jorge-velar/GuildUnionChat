-- Guild Union - Paquete OF: las profesiones, su nivel y las recetas de cada uno en toda la unión, como propuestas (WU) [+ARCHITECTURE.md]
--   <profesión>  la de cada uno: «nivel» (recolección, o sin su lista leída entera) o «nivel,huella,recetas»
local _, HU = ...
local L = HU.L

local DAY = 86400
-- (las que van, con su nombre por si el juego no lo da; Pesca no: no fabrica nada)
local PROFS = { [129] = "Primeros auxilios", [164] = "Herrería", [165] = "Peletería", [171] = "Alquimia",
    [182] = "Herboristería", [185] = "Cocina", [186] = "Minería", [197] = "Sastrería", [202] = "Ingeniería",
    [333] = "Encantamiento", [393] = "Desuello" }
local SECONDARY = { [129] = true, [185] = true }
local LEVEL_MAX = 450
local BITS_MAX = 86         -- letras de recetas de una lista que no es la mía (la más larga, Peletería: 511 → 86)
local LINE_MAX = 200        -- la línea entera del paquete, «Nombre-Reino,clave,hora,datos» (PART, Net/Packs.lua)
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VAL = {}
for i = 1, #B64 do VAL[B64:byte(i)] = i - 1 end

---------------------------------------------------------------------------
-- Las listas de fabricables y las recetas en letras [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- (de cada profesión, lo de CraftItems.lua en orden de nivel para aprenderlo, los objetos antes que los encantamientos y
-- por número: n, [i] = { id, lv, spell }, pos[clave] = i (la clave de Trade.lua: el objeto o "s" .. hechizo), hash
-- (3 letras, cambia si cambia el orden) y chars (letras de recetas, como mucho). Se monta la primera vez)
local lists = {}
local function ListOf(skill)
    local l = lists[skill]
    if l then return l end
    local all = {}
    for kind = 1, 2 do
        local src = kind == 1 and HU.CRAFT_ITEMS or HU.CRAFT_SPELLS
        local list = type(src) == "table" and src[skill] or {}
        for i = 1, #list - 1, 2 do all[#all + 1] = { id = list[i], lv = list[i + 1], spell = kind == 2 } end
    end
    table.sort(all, function(a, b)
        if a.lv ~= b.lv then return a.lv < b.lv end
        if a.spell ~= b.spell then return b.spell end
        return a.id < b.id
    end)
    l = { n = #all, pos = {}, chars = math.ceil(#all / 6) }
    local parts = {}
    for i, e in ipairs(all) do
        l[i] = e
        local k = e.spell and ("s" .. e.id) or e.id
        if not l.pos[k] then l.pos[k] = i end
        parts[i] = i .. (e.spell and "s" or "i") .. e.id
    end
    l.hash = HU.PackHash(parts):sub(-3)
    lists[skill] = l
    return l
end

-- (las recetas que sé de una lista: un bit por cosa, 6 por letra, sin los ceros del final. rec: tradeRecipes[profesión])
local function Encode(l, rec)
    local items = type(rec.items) == "table" and rec.items or {}
    local spells = type(rec.spells) == "table" and rec.spells or {}
    local out, v, b = {}, 0, 1
    for i = 1, l.n do
        local e = l[i]
        if (e.spell and spells or items)[e.id] then v = v + b end
        if b == 32 or i == l.n then
            out[#out + 1] = B64:sub(v + 1, v + 1)
            v, b = 0, 1
        else
            b = b * 2
        end
    end
    return (table.concat(out):gsub("A+$", ""))
end
-- (¿sabe la cosa i de la lista? Una letra y un bit, sin leer lo demás)
local function Known(bits, i)
    local v = VAL[bits:byte(math.floor((i - 1) / 6) + 1) or 0]
    return v ~= nil and math.floor(v / 2 ^ ((i - 1) % 6)) % 2 == 1
end

-- Los datos de una línea: profesión, nivel, huella y recetas (estas dos, nil si no van); nil si no tienen su forma
local function Parse(key, data)
    local skill = tonumber(key)
    if not (skill and PROFS[skill] and tostring(skill) == key and type(data) == "string") then return nil end
    local lv, hash, bits = data:match("^(%d+),(%w%w%w),([%w%+/]*)$")
    lv = tonumber(lv or data:match("^(%d+)$"))
    if not lv or lv < 1 or lv > LEVEL_MAX then return nil end
    if hash then
        local l = ListOf(skill)
        if #bits > ((hash == l.hash and l.n > 0) and l.chars or BITS_MAX) then return nil end
    end
    return skill, lv, hash, bits
end

local index -- lo de HU:Proposals("OF") por profesión y por nombre; nil: se rehace al mirarlo
HU:RegisterPackSet("OF", {
    chunks = 16, proposals = true, keep = 30 * DAY,
    validate = function(_, key, data) return Parse(key, data) ~= nil end,
    -- (el equipo solo publica a los que siguen en mi hermandad; con la lista aún sin leer, a todos)
    publish = function(name) return next(HU.roster) == nil or HU:MemberOf(name, HU.myTag) end,
    onChange = function()
        index = nil
        HU:Changed("professions")
    end,
})

---------------------------------------------------------------------------
-- Lo mío, a mi hermandad: al entrar, al subir de nivel y al abrir la ventana de una profesión [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local SEND_GAP = 300        -- una tanda cada 5 min como mucho
local RENEW = 7 * DAY       -- lo de más de una semana se vuelve a mandar (caduca a los 30 días)
local BATCH = 4             -- líneas por tanda: caben en la ráfaga de 5 de quien las recibe
local QUIET_MAX = 120       -- en combate o en una entrada masiva se espera, como mucho esto

local function Pack(...) return { n = select("#", ...), ... } end
-- (mis profesiones del juego: [número] = nivel; nil si el juego no las da)
local function MyRanks()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil end
    local res = Pack(pcall(GetProfessions))
    if not res[1] then return nil end
    local out = {}
    for i = 2, res.n do
        if type(res[i]) == "number" then
            -- (nombre, icono, nivel, máximo, hechizos, desplazamiento, número de profesión…)
            local ok, _, _, rank, _, _, _, skill = pcall(GetProfessionInfo, res[i])
            if ok and type(skill) == "number" and not HU.Secret(skill) and PROFS[skill] and type(rank) == "number"
                and not HU.Secret(rank) and rank >= 1 then
                out[skill] = math.min(math.floor(rank), LEVEL_MAX)
            end
        end
    end
    return out
end

-- (lo que mandaría de cada profesión, [clave] = datos: las recetas, si su lista se leyó entera y la línea cabe)
local function MyData()
    local ranks, me = MyRanks(), HU:Me()
    if not (ranks and me) then return nil end
    local recs = HU.db.tradeRecipes or {}
    local out = {}
    for skill, rank in pairs(ranks) do
        local key, l, rec = tostring(skill), ListOf(skill), recs[skill]
        local d = tostring(rank)
        if l.n > 0 and type(rec) == "table" and rec.full then
            local full = d .. "," .. l.hash .. "," .. Encode(l, rec)
            -- (la hora, en base 36, son 6 letras hasta 2038: se cuentan 7)
            if #me + #key + #full + 3 + 7 <= LINE_MAX then d = full end
        end
        out[key] = d
    end
    return out
end

-- (lo mío de esa profesión que ya está en el almacén de propuestas, Net/Packs.lua)
local function Stored(key)
    local st = HU.db.wuStore and HU.db.wuStore[HU.myTag]
    st = st and st.OF
    return st and st[HU:MeKey() .. "," .. key]
end

-- Lo que toca mandar, en este orden: lo que ha cambiado, lo que ya no tengo y lo de más de una semana: { { clave, datos } }
local function Due()
    local mine = HU.myTag and MyData()
    if not mine then return {} end
    local now, fresh, gone, old = HU.StampNow(), {}, {}, {}
    for skill in pairs(PROFS) do
        local key = tostring(skill)
        local e, d = Stored(key), mine[key]
        if d and not (e and e.d == d) then fresh[#fresh + 1] = { key, d }
        elseif d and now - e.t >= RENEW then old[#old + 1] = { key, d }
        -- (sin ninguna profesión no se borra nada: puede que el juego aún no las dé)
        elseif not d and e and e.d ~= "" and next(mine) then gone[#gone + 1] = { key, "" } end
    end
    local out = {}
    for _, list in ipairs({ fresh, gone, old }) do
        table.sort(list, function(a, b) return a[1] < b[1] end)
        for _, x in ipairs(list) do out[#out + 1] = x end
    end
    return out
end

local lastSent = -SEND_GAP  -- GetTime de la última tanda
local wantAt, armedAt       -- cuándo mirar (el último aviso lo retrasa) y desde cuándo se espera
local Check
local function Arm(delay)
    local now = GetTime()
    wantAt = math.max(wantAt or 0, now + delay)
    if armedAt then return end
    armedAt = now
    HU.After(delay, Check)
end
local function SendDue()
    local due = Due()
    for i = 1, math.min(BATCH, #due) do HU:Propose("OF", due[i][1], due[i][2]) end
    if #due > 0 then lastSent = GetTime() end
    -- (lo que no cabe en esta tanda, en la siguiente)
    if #due > BATCH then Arm(SEND_GAP) end
end
Check = function()
    local now = GetTime()
    local at = math.max(wantAt, lastSent + SEND_GAP)
    -- (en combate o en una entrada masiva, un poco después: el chat va antes)
    if now >= at and now - armedAt < QUIET_MAX and (HU:CombatHold() or not HU.QuietLogins(10)) then at = now + 10 end
    if now < at then
        HU.After(at - now, Check)
        return
    end
    wantAt, armedAt = nil, nil
    SendDue()
end

-- (al entrar, cuando WU ya ha vuelto a mandar lo mío (2 min y unos segundos que salen del nombre, para no ir todos a la
-- vez); al subir de nivel o cambiar de profesión, 30 s después del último aviso; al abrir la ventana de una profesión,
-- 5 s después, cuando Trade.lua ya ha guardado sus recetas)
HU:OnStart(function() Arm(120 + HU.PackChunkOf(HU:Me() or "", 30)) end)
HU:On("SKILL_LINES_CHANGED", function() Arm(30) end)
HU:On("TRADE_SKILL_SHOW", function() Arm(5) end)
HU:On("TRADE_SKILL_LIST_UPDATE", function() Arm(5) end)

---------------------------------------------------------------------------
-- Buscar: un índice que se rehace solo cuando OF cambia, y solo al mirarlo [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local names, icons = {}, {}
local function TS(fn, skill)
    local f = C_TradeSkillUI and C_TradeSkillUI[fn]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, skill)
    if ok and v ~= nil and v ~= "" and not HU.Secret(v) then return v end
    return nil
end
-- (su nombre y su icono, los del juego, como en su lista de miembros, y se recuerdan; si no los da, el nuestro y sin
-- icono, y se vuelve a preguntar la próxima vez)
local function ProfName(skill)
    if not names[skill] then
        local n = TS("GetTradeSkillDisplayName", skill)
        names[skill] = type(n) == "string" and n or nil
    end
    return names[skill] or L(PROFS[skill])
end
local function ProfIcon(skill)
    icons[skill] = icons[skill] or TS("GetTradeSkillTexture", skill)
    return icons[skill]
end

-- (bySkill[profesión] y byName[clave]: filas { name, key, tag, skill, rank, t, bits, recipes }; bits, solo con mi misma
-- lista; recipes, si su línea trae recetas, de la lista que sea (ha abierto esa ventana con el addon). Si alguien sale en
-- dos hermandades (se cambió), la más nueva)
local function Index()
    if index then return index end
    local seen = {}
    for _, e in ipairs(HU:Proposals("OF")) do
        local skill, rank, hash, bits = Parse(e.k, e.d)
        local k = skill and HU:Key(e.n)
        if k then
            local l = ListOf(skill)
            local r = { name = e.n, key = k, tag = e.tag, skill = skill, rank = rank, t = e.t,
                bits = (hash == l.hash and l.n > 0) and bits or nil, recipes = hash ~= nil }
            local old = seen[k .. "|" .. skill]
            if not old or old.t < r.t then seen[k .. "|" .. skill] = r end
        end
    end
    index = { bySkill = {}, byName = {} }
    for _, r in pairs(seen) do
        local s, n = index.bySkill[r.skill] or {}, index.byName[r.key] or {}
        s[#s + 1], n[#n + 1] = r, r
        index.bySkill[r.skill], index.byName[r.key] = s, n
    end
    return index
end

-- «Quién lo hace» en toda la unión (Trade.lua): los que tienen la profesión que se busca por su nombre (q) o pueden hacer
-- algo de `items` ([clave] = true, las de Trade.lua: el objeto o "s" .. hechizo; `needs`: el nivel que pide, por
-- profesión). Filas { name, tag, skill, prof, icon, rank, knows }: knows, true si sabe la receta; quien seguro que no la
-- sabe no sale. Primero quien la sabe y luego por nivel [+ARCHITECTURE.md]
function HU:UnionCrafters(q, items, needs)
    local out = {}
    for skill, rows in pairs(Index().bySkill) do
        local l, prof = ListOf(skill), ProfName(skill)
        local byName = type(q) == "string" and q ~= "" and HU.TextRank(prof, q) ~= nil
        local where = {}
        for k in pairs(items or {}) do if l.pos[k] then where[#where + 1] = l.pos[k] end end
        local need = needs and needs[skill]
        if byName or #where > 0 then
            for _, r in ipairs(rows) do
                local knows
                if #where > 0 and r.bits then
                    knows = false
                    for _, i in ipairs(where) do if Known(r.bits, i) then knows = true; break end end
                end
                if byName or knows or (knows == nil and (not need or r.rank >= need)) then
                    out[#out + 1] = { name = r.name, tag = r.tag, skill = skill, prof = prof, icon = ProfIcon(skill),
                        rank = r.rank, knows = knows or nil }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.knows == true) ~= (b.knows == true) then return a.knows == true end
        if a.rank ~= b.rank then return a.rank > b.rank end
        if a.name ~= b.name then return a.name < b.name end
        return a.skill < b.skill
    end)
    return out
end

-- Las profesiones de alguien de la unión, de sus líneas de OF: { id, name, icon, rank, secondary, recipes }, primero las
-- principales; nil si no hay (sin el addon o sin su paquete todavía). Cocina y Primeros auxilios van marcadas
-- (`secondary`): la ficha no las enseña, pero cuentan para «Quién lo hace» (Jorge, 25/11: «que no salga en las
-- profesiones de alguien normal, pero sí para tener la data»). `recipes`: su línea trae recetas («Ver recetas» de la
-- ficha, UnionRoster.lua)
function HU:UnionProfessionsOf(name)
    local rows = Index().byName[self:Key(name) or ""]
    if not rows then return nil end
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { id = r.skill, name = ProfName(r.skill), icon = ProfIcon(r.skill), rank = r.rank,
            secondary = SECONDARY[r.skill] or nil, recipes = r.recipes }
    end
    table.sort(out, function(a, b)
        if (SECONDARY[a.id] == true) ~= (SECONDARY[b.id] == true) then return not SECONDARY[a.id] end
        return a.id < b.id
    end)
    return out
end

-- Pedir OF de `tag` o, sin él, de todas (de la mía, lo que me perdí estando fuera): al abrir Comercio (Trade.lua) y la
-- ficha de alguien de otra hermandad (UnionRoster.lua). HU:PackNeed no repite lo que ya está completo o pedido
function HU:NeedUnionProfessions(tag)
    if not self.myTag then return end
    if tag then return self:PackNeed(tag, "OF") end
    self:PackNeed(self.myTag, "OF")
    for _, t in ipairs(self:OtherTags()) do self:PackNeed(t, "OF") end
end

-- (para las pruebas)
HU.ProfessionsForTests = { list = ListOf, encode = Encode, known = Known, parse = Parse, due = Due }

HU:Module("Packs/Professions", { "Combat", "Config", "Core", "Lists", "Net/Packs", "Net/RosterSync" })
