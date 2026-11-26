-- Guild Union - estadísticas de la hermandad, para oficiales y el maestro (Jorge, 26/11) [+ARCHITECTURE.md]
-- Miembros, rangos, niveles, clases, razas, profesiones y actividad (activos, alts, inactivos), con gráficos de barras
-- en el juego (como los addons de estadísticas) y un botón para exportar el texto a Discord o a un archivo. Sale de
-- datos que GuildUnion ya tiene (la lista de la hermandad y el registro de altas/bajas). Y el informe de la unión: los
-- números de cada hermandad, que da uno de sus oficiales a otro oficial (SQ y SR, como /gu carga), sumados, con
-- clases, razas y profesiones por su clave del juego (no por el nombre, que depende del idioma de cada uno).
local _, HU = ...
local L = HU.L
local DJ = HU.DJ

local MAX_LEVEL = 60       -- (Forever es contenido vanilla: el tope es 60)
local ACTIVE_DAYS = 30     -- (activo = conectado ahora o visto en los últimos tantos días)
local DAY = 86400

-- ¿Puede ver las estadísticas? Los oficiales (ven la nota de oficial) y el maestro
function HU:CanSeeStats()
    return (self:CanOfficer() or (IsGuildLeader and IsGuildLeader())) and true or false
end

-- (¿es un alt? Por el rango o la nota pública: muchas hermandades marcan los alts con un rango «Alt» o lo ponen en la
-- nota. No se puede saber de verdad qué personajes son del mismo jugador, así que es lo que diga la hermandad)
local ALT_WORDS = { "alt", "mula", "twink", "secundari", "doble" }
local function IsAlt(e)
    local s = ((e.rank or "") .. " " .. (e.note or "")):lower()
    for _, w in ipairs(ALT_WORDS) do if s:find(w, 1, true) then return true end end
    return false
end

-- (activo: conectado ahora, o desconectado hace menos de ACTIVE_DAYS días; offSecs son los segundos sin conectarse)
local function IsActive(e)
    if e.online then return true end
    return type(e.offSecs) == "number" and e.offSecs < ACTIVE_DAYS * DAY
end

local function Text(x) if type(x) == "string" and x ~= "" and not HU.Secret(x) then return x end end
-- (la raza, por el GUID: el nombre que da el juego y su clave fija, «NightElf»…; nil si no se puede saber)
local function RaceOf(guid)
    if not (guid and GetPlayerInfoByGUID) then return nil end
    local ok, _, _, race, raceFile = pcall(GetPlayerInfoByGUID, guid)
    if not ok then return nil end
    return Text(race), Text(raceFile)
end

-- (el nombre de la clase, en el idioma del juego; si no se reconoce, tal cual)
local function ClassLabel(name)
    local t = _G.LOCALIZED_CLASS_NAMES_MALE
    return (type(t) == "table" and t[name]) or name
end

local function CountRecent(log, days)
    local n, since = 0, time() - days * DAY
    for _, e in ipairs(log or {}) do if type(e.t) == "number" and e.t >= since then n = n + 1 end end
    return n
end

-- (una lista { clave -> n } a { { name, n }, de más a menos })
local function Sorted(byName)
    local out = {}
    for name, n in pairs(byName) do out[#out + 1] = { name = name, n = n } end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    return out
end

local function Pct(part, total) return total > 0 and (100 * part / total) or 0 end

-- Las estadísticas, en una tabla (la usan la ventana, el informe de la unión y las pruebas). nil si no estoy en una
-- hermandad. Clases, razas y profesiones, también por su clave fija (byClassKey, byRaceKey, byProfID): no dependen del
-- idioma, y así se suman las de toda la unión
function HU:GuildStats()
    local guild = IsInGuild() and GetGuildInfo and GetGuildInfo("player")
    if not guild then return nil end
    local roster = self.rosterList or {}
    local s = {
        guild = guild, total = #roster, online = 0, mobile = 0,
        active = 0, alts = 0, activeNoAlt = 0, totalNoAlt = 0,
        byRank = {}, byClass = {}, byRace = {},
        professions = self:GuildProfessionCounts(),
        maxLevel = 0, avgLevel = 0, levelSum = 0, levelN = 0,
        levelBuckets = { { "1-19", 0 }, { "20-39", 0 }, { "40-59", 0 }, { tostring(MAX_LEVEL), 0 } },
        inactive7 = 0, inactive30 = 0,
    }
    local rankTotals, rankOnline, rankLabel, classN, raceN, raceKey = {}, {}, {}, {}, {}, {}
    local sumLevel, levelN = 0, 0
    for _, e in ipairs(roster) do
        local alt, active = IsAlt(e), IsActive(e)
        if e.online then s.online = s.online + 1 end
        if e.mobile then s.mobile = s.mobile + 1 end
        if active then s.active = s.active + 1 end
        if alt then s.alts = s.alts + 1 else
            s.totalNoAlt = s.totalNoAlt + 1
            if active then s.activeNoAlt = s.activeNoAlt + 1 end
        end
        local ri = e.rankIndex or 99
        rankTotals[ri] = (rankTotals[ri] or 0) + 1
        if e.online then rankOnline[ri] = (rankOnline[ri] or 0) + 1 end
        rankLabel[ri] = rankLabel[ri] or e.rank or self:RankName(self.myTag, ri)
        if type(e.class) == "string" and e.class ~= "" then classN[e.class] = (classN[e.class] or 0) + 1 end
        local race, rkey = RaceOf(e.guid)
        if race then raceN[race] = (raceN[race] or 0) + 1 end
        if rkey then raceKey[rkey] = (raceKey[rkey] or 0) + 1 end
        local lv = tonumber(e.level)
        if lv and lv > 0 then
            sumLevel, levelN = sumLevel + lv, levelN + 1
            if lv > s.maxLevel then s.maxLevel = lv end
            local b = (lv >= MAX_LEVEL and 4) or (lv >= 40 and 3) or (lv >= 20 and 2) or 1
            s.levelBuckets[b][2] = s.levelBuckets[b][2] + 1
        end
        local off = e.offSecs
        if type(off) == "number" then
            if off >= 30 * DAY then s.inactive30 = s.inactive30 + 1 end
            if off >= 7 * DAY then s.inactive7 = s.inactive7 + 1 end
        end
    end
    s.levelSum, s.levelN = sumLevel, levelN
    s.avgLevel = levelN > 0 and (sumLevel / levelN) or 0
    s.activePct, s.altsPct = Pct(s.active, s.total), Pct(s.alts, s.total)
    s.activeNoAltPct = Pct(s.activeNoAlt, s.totalNoAlt)
    local ris = {}
    for ri in pairs(rankTotals) do ris[#ris + 1] = ri end
    table.sort(ris)
    for _, ri in ipairs(ris) do
        s.byRank[#s.byRank + 1] = { name = rankLabel[ri] or (L("Rango ") .. ri), total = rankTotals[ri], online = rankOnline[ri] or 0 }
    end
    for _, c in ipairs(Sorted(classN)) do s.byClass[#s.byClass + 1] = { name = ClassLabel(c.name), n = c.n } end
    s.byRace = Sorted(raceN)
    -- (por clave fija: la clase de la lista ya es la del juego en inglés, «MAGE»; la profesión, por su número)
    s.byClassKey, s.byRaceKey, s.byProfID = classN, raceKey, {}
    for _, p in ipairs(s.professions) do if p.id then s.byProfID[p.id] = (s.byProfID[p.id] or 0) + p.n end end
    local db = self.db or {}
    local inv = (db.inviteLog and db.inviteLog[guild]) or {}
    local lea = (db.leaveLog and db.leaveLog[guild]) or {}
    s.joined7, s.joined30 = CountRecent(inv, 7), CountRecent(inv, 30)
    s.left7, s.left30 = CountRecent(lea, 7), CountRecent(lea, 30)
    return s
end

-- Las estadísticas en texto llano (sin colores: para pegar en Discord o en un archivo)
function HU:GuildStatsText()
    local s = self:GuildStats()
    if not s then return L("No estás en una hermandad.") end
    local lines = {}
    local function add(x) lines[#lines + 1] = x end
    local function section(title, rows)
        add(""); add(title)
        for _, r in ipairs(rows) do add(string.format("  %-18s %3d", r.name, r.n)) end
        if #rows == 0 then add("  -") end
    end
    add(HU.ADDON_TITLE .. " - " .. string.format(L("Estadísticas de %s"), s.guild) .. " - " .. date("%d/%m/%Y %H:%M"))
    add("")
    add(string.format(L("Miembros: %d  ·  conectados: %d"), s.total, s.online)
        .. (s.mobile > 0 and string.format(L("  ·  con el móvil: %d"), s.mobile) or ""))
    add(string.format(L("Activos (vistos en %d días): %d (%.0f%%)  ·  sin contar alts: %.0f%%"), ACTIVE_DAYS, s.active, s.activePct, s.activeNoAltPct))
    add(string.format(L("Alts: %d (%.0f%%)"), s.alts, s.altsPct))
    add("")
    add(L("Por rango:"))
    for _, r in ipairs(s.byRank) do add(string.format("  %-22s %3d  (%d %s)", r.name, r.total, r.online, L("conectados"))) end
    add("")
    add(string.format(L("Niveles: máximo %d  ·  media %.1f  ·  al %d: %d"), s.maxLevel, s.avgLevel, MAX_LEVEL, s.levelBuckets[4][2]))
    for _, b in ipairs(s.levelBuckets) do add(string.format("  %-7s %3d", b[1], b[2])) end
    section(L("Clases:"), s.byClass)
    section(L("Razas:"), s.byRace)
    section(L("Profesiones:"), s.professions)
    add("")
    add(L("Actividad:"))
    add(string.format(L("  Altas: %d (7 días)  ·  %d (30 días)"), s.joined7, s.joined30))
    add(string.format(L("  Bajas: %d (7 días)  ·  %d (30 días)"), s.left7, s.left30))
    add(string.format(L("  Sin conectarse: %d (más de 7 días)  ·  %d (más de 30 días)"), s.inactive7, s.inactive30))
    return table.concat(lines, "\n")
end

-- La ventana de texto, para copiar (Ctrl+A, Ctrl+C) y pegar en Discord o en un archivo
function HU:ExportGuildStats()
    if self.UI and self.UI.ShowCopy then
        self.UI:ShowCopy(L("Estadísticas de la hermandad"), self:GuildStatsText(),
            { hint = L("Ctrl+A selecciona todo · Ctrl+C copia · pégalo en Discord o en un archivo de texto") })
    else
        for l in self:GuildStatsText():gmatch("[^\n]+") do self:Print(l) end
    end
end

---------------------------------------------------------------------------
-- La ventana con gráficos de barras (como los addons de estadísticas) [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local win
local ROW_H, BAR_W, LABEL_W = 16, 150, 110
local GOLD = { 0.90, 0.74, 0.28 }
local TEAL = { 0.20, 0.90, 0.55 }

-- (una fila de barra: la etiqueta, la barra (ancha según n/max) y el número; se reutilizan)
local function BarRow(parent, i)
    local r = parent.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, parent)
    r:SetSize(parent:GetWidth(), ROW_H)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetPoint("LEFT", 2, 0); r.label:SetWidth(LABEL_W); r.label:SetJustifyH("LEFT"); r.label:SetWordWrap(false)
    r.bg = r:CreateTexture(nil, "ARTWORK")
    r.bg:SetPoint("LEFT", LABEL_W + 6, 0); r.bg:SetSize(BAR_W, 10)
    r.bg:SetColorTexture(1, 1, 1, 0.06)
    r.bar = r:CreateTexture(nil, "OVERLAY")
    r.bar:SetPoint("LEFT", r.bg, "LEFT", 0, 0); r.bar:SetHeight(10)
    r.num = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.num:SetPoint("LEFT", r.bg, "RIGHT", 6, 0); DJ.C(r.num, { 0.92, 0.92, 0.95 })
    parent.rows[i] = r
    return r
end
-- (un título de sección)
local function Head(parent, i)
    local h = parent.heads[i]
    if h then return h end
    h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    DJ.C(h, GOLD); parent.heads[i] = h
    return h
end

local function Render(self)
    local s = self:GuildStats()
    local body = win.body
    for _, r in ipairs(body.rows) do r:Hide() end
    for _, h in ipairs(body.heads) do h:Hide() end
    local y, ri, hi = 0, 0, 0
    local function addHead(text)
        hi = hi + 1; local h = Head(body, hi)
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", 4, -y); h:SetText(text); h:Show()
        y = y + 20
    end
    local function addBars(rows, valueOf, color)
        local max = 1
        for _, r in ipairs(rows) do max = math.max(max, valueOf(r)) end
        for _, r in ipairs(rows) do
            ri = ri + 1; local row = BarRow(body, ri)
            local v = valueOf(r)
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y)
            row.label:SetText(r.name)
            row.bar:SetColorTexture(color[1], color[2], color[3], 0.9)
            row.bar:SetWidth(math.max(1, BAR_W * v / max))
            row.num:SetText(tostring(v)); row:Show()
            y = y + ROW_H
        end
        if #rows == 0 then addHead("  -") end
    end
    -- resumen arriba
    win.summary:SetText(string.format(L("Miembros: %d  ·  conectados: %d"), s.total, s.online)
        .. "\n" .. string.format(L("Activos (vistos en %d días): %d (%.0f%%)  ·  sin contar alts: %.0f%%"), ACTIVE_DAYS, s.active, s.activePct, s.activeNoAltPct)
        .. "\n" .. string.format(L("Alts: %d (%.0f%%)"), s.alts, s.altsPct))
    addHead(L("Por rango:"))
    addBars(s.byRank, function(r) return r.total end, GOLD)
    addHead(L("Niveles:"))
    addBars(s.levelBuckets, function(r) return r[2] end, TEAL)
    -- (los tramos de nivel llevan su etiqueta en r[1], no r.name)
    for i = ri - #s.levelBuckets + 1, ri do if body.rows[i] then body.rows[i].label:SetText(s.levelBuckets[i - (ri - #s.levelBuckets)][1]) end end
    addHead(L("Clases:"))
    addBars(s.byClass, function(r) return r.n end, GOLD)
    addHead(L("Razas:"))
    addBars(s.byRace, function(r) return r.n end, TEAL)
    addHead(L("Profesiones:"))
    addBars(s.professions, function(r) return r.n end, GOLD)
    body:SetHeight(y + 10)
end

local function Build(self)
    win = DJ.Window("GuildUnionStats", UIParent, 420, 480)
    win.titleText:SetText(L("Estadísticas de la hermandad"))
    local cf = win.content
    win.summary = cf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.summary:SetPoint("TOPLEFT", 10, -8); win.summary:SetJustifyH("LEFT"); win.summary:SetSpacing(2)
    local scroll = CreateFrame("ScrollFrame", "GuildUnionStatsScroll", cf, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -62); scroll:SetPoint("BOTTOMRIGHT", -28, 42)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(360, 10); body.rows, body.heads = {}, {}
    scroll:SetScrollChild(body)
    win.body = body
    local exp = DJ.Button(cf, L("Exportar"), 120, 22)
    exp:SetPoint("BOTTOMRIGHT", -8, 10)
    exp:SetScript("OnClick", function() HU:ExportGuildStats() end)
    win.export = exp
    -- (el informe de la unión: los números de cada hermandad, que da uno de sus oficiales)
    local uni = DJ.Button(cf, L("Pedir a la unión"), 140, 22)
    uni:SetPoint("RIGHT", exp, "LEFT", -6, 0)
    uni:SetScript("OnClick", function() HU:AskUnionStats() end)
    win.union = uni
    tinsert(UISpecialFrames, "GuildUnionStats")
    return win
end

-- «Oficiales» > «Estadísticas» (o /gu stats): la ventana con los gráficos
function HU:ShowGuildStats()
    if not self:CanSeeStats() then return self:Print(L("Las estadísticas son solo para oficiales.")) end
    if not IsInGuild() then return self:Print(L("No estás en una hermandad.")) end
    if not win then Build(self) end
    Render(self)
    win:Show()
end

---------------------------------------------------------------------------
-- El informe de la unión: los números de cada hermandad, sumados, como /gu carga (Report.lua) [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local UNION_WAIT = 10     -- lo que se espera a las respuestas
local UNION_GAP = 30      -- entre dos preguntas mías; y quien contesta, al mismo, como mucho una vez en este tiempo
local UNION_MAX = 20      -- respuestas como mucho en UNION_GAP s, a todos juntos
-- (los números que van en SR, en este orden: solo números, sin nombres)
local UNION_FIELDS = { "total", "online", "mobile", "active", "alts", "activeNoAlt", "totalNoAlt", "maxLevel",
    "levelSum", "levelN", "b1", "b2", "b3", "b4", "joined7", "joined30", "left7", "left30", "inactive7", "inactive30" }
-- (y detrás, tres listas de cuántos hay de cada clase, raza y profesión principal, en este orden fijo y por su clave
-- del juego, no por el nombre, que depende del idioma de cada uno; las razas, HU.RACE_ORDER de Social.lua)
local UNION_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local UNION_PROFS = { 171, 164, 333, 202, 182, 165, 186, 393, 197 }
local LISTS = #UNION_FIELDS + 4   -- (en SR, dónde empiezan las listas)
local UNION_CACHE = 10    -- lo que valen mis números para contestar: si me preguntan varios a la vez, se cuentan una vez
local unionRun            -- mi pregunta en marcha: { id, rows = { { tag, name, officer, mine, data, bad } }, byKey }
local unionAskT = -999
local cache               -- { t, list }: mis números de la última vez

-- (el tope de cada número: lo que acepta quien lo recibe)
local function Cap(k) return (k == "levelSum" and 999999) or (k == "maxLevel" and 100) or 9999 end

-- (cuántos hay de cada clave, en ese orden: «3.0.2…»)
local function CountList(by, keys)
    local out = {}
    for i, k in ipairs(keys) do out[i] = tostring(math.min(9999, by[k] or 0)) end
    return table.concat(out, ".")
end

-- Mis números como van en SR, sin la orden: etiqueta, id, versión, los de UNION_FIELDS y las tres listas. nil fuera de
-- una hermandad. Con hasta 1.000 miembros caben de sobra en un mensaje (como mucho ~242 de 255 letras)
local function UnionFields(self, id)
    if not (cache and GetTime() - cache.t < UNION_CACHE) then
        local s = self:GuildStats()
        if not s then return nil end
        local b = s.levelBuckets
        local v = { total = s.total, online = s.online, mobile = s.mobile, active = s.active, alts = s.alts,
            activeNoAlt = s.activeNoAlt, totalNoAlt = s.totalNoAlt, maxLevel = s.maxLevel, levelSum = s.levelSum,
            levelN = s.levelN, b1 = b[1][2], b2 = b[2][2], b3 = b[3][2], b4 = b[4][2], joined7 = s.joined7,
            joined30 = s.joined30, left7 = s.left7, left30 = s.left30, inactive7 = s.inactive7, inactive30 = s.inactive30 }
        local list = {}
        for _, k in ipairs(UNION_FIELDS) do list[#list + 1] = tostring(math.min(Cap(k), math.max(0, math.floor(v[k])))) end
        list[#list + 1] = CountList(s.byClassKey, UNION_CLASSES)
        list[#list + 1] = CountList(s.byRaceKey, HU.RACE_ORDER)
        list[#list + 1] = CountList(s.byProfID, UNION_PROFS)
        cache = { t = GetTime(), list = list }
    end
    local out = { self.myTag, id, tostring(HU.version) }
    for _, x in ipairs(cache.list) do out[#out + 1] = x end
    return out
end

-- (un número que llega: entero de 0 al tope; cualquier otra cosa no vale)
local function UnionInt(s, max)
    if type(s) ~= "string" or #s > 6 or not s:match("^%d+$") then return nil end
    local n = tonumber(s)
    return (n and n <= max) and n or nil
end
-- (una lista de SR: tantos números como claves, que no sumen más de max; nil si no vale)
local function ParseCounts(s, n, max)
    if type(s) ~= "string" or #s > n * 5 then return nil end
    local out, sum = {}, 0
    for x in (s .. "."):gmatch("([^.]*)%.") do
        local v = UnionInt(x, 9999)
        if not v then return nil end
        out[#out + 1], sum = v, sum + v
    end
    return (#out == n and sum <= max) and out or nil
end
-- Los datos de un SR (f[1] etiqueta, f[2] id, f[3] versión, los números y las tres listas), o nil si algo no vale o no
-- cuadra entre sí
local function ParseUnion(f)
    local ver = f[3]
    if type(ver) ~= "string" or #ver > 16 or not ver:match("^[%w%.%-]+$") then return nil end
    if f[LISTS + 3] ~= nil then return nil end
    local d = { ver = ver }
    for i, k in ipairs(UNION_FIELDS) do
        d[k] = UnionInt(f[3 + i], Cap(k))
        if not d[k] then return nil end
    end
    -- (lo que sale de una misma lista cuadra: nadie cuenta dos veces y los tramos de nivel suman los que lo tienen)
    for _, k in ipairs({ "online", "mobile", "active", "levelN", "inactive7" }) do
        if d[k] > d.total then return nil end
    end
    if d.alts + d.totalNoAlt ~= d.total or d.activeNoAlt > math.min(d.active, d.totalNoAlt)
        or d.b1 + d.b2 + d.b3 + d.b4 ~= d.levelN or d.levelSum > d.levelN * d.maxLevel
        or d.inactive30 > d.inactive7 or d.joined7 > d.joined30 or d.left7 > d.left30 then
        return nil
    end
    -- (clases y razas, una por miembro como mucho; profesiones principales, dos)
    d.classes = ParseCounts(f[LISTS], #UNION_CLASSES, d.total)
    d.races = ParseCounts(f[LISTS + 1], #HU.RACE_ORDER, d.total)
    d.profs = ParseCounts(f[LISTS + 2], #UNION_PROFS, 2 * d.total)
    if not (d.classes and d.races and d.profs) then return nil end
    return d
end

-- (a quién de esa hermandad le pregunto: a un oficial suyo con el addon y conectado (su addon me ha hablado en los
-- últimos 15 min), el enlace primero si lo es; si no conozco a ninguno, a su enlace o a mi mejor contacto, que solo
-- contestará si es oficial. Devuelve su ficha y si sé que es oficial)
local function UnionTarget(self, tag)
    local now, best, bestScore = GetTime(), nil, nil
    for _, key in ipairs(self:RemoteKeys(tag)) do
        local p = self.remote[key]
        local age = p and now - (p.last or 0)
        local ok = p and p.tag == tag and p.name and age < 900 and self:IsOfficerName(p.name)
        local score = ok and ((p.relay and 1000 or 0) - age / 10)
        if score and (not bestScore or score > bestScore) then best, bestScore = p, score end
    end
    if best then return best, true end
    return self:KnownRelay(tag) or self:BestPeer(tag), false
end

-- Contestar: solo un oficial (o el maestro), a otro oficial de la unión, por susurro, con topes y con mi lista cargada
local answered, answeredN, winT, winN = {}, 0, -999, 0
-- (abierta: lo que vale lo mira el manejador, como UQ. Oficial a oficial: quien pregunta, según lo que sé de su
-- hermandad (su rango en su lista y sus rangos de oficial, RN); si no lo sé, no contesto)
HU:RegisterMessage("SQ", { open = true, ttl = 15, combat = "req" })
HU.comm.SQ = function(self, sender, f, dist)
    local tag, id = f[1], f[2]
    if dist ~= "WHISPER" or not (self.cfg and self.myTag and tag and self.cfg.byTag[tag]) then return end
    if type(id) ~= "string" or #id > 8 or not id:match("^%w+$") then return end
    if not (self:MemberOf(sender, tag) or (tag ~= self.myTag and self:Vouched(sender, tag))) then return end
    if not (self:CanSeeStats() and self:IsOfficerName(sender)) then return end
    -- (recién entrado, sin mi lista todavía, diría que somos 0)
    if #(self.rosterList or {}) == 0 then return end
    local k, now = sender:lower(), GetTime()
    if answered[k] and now - answered[k] < UNION_GAP then return end
    if now - winT >= UNION_GAP then winT, winN = now, 0 end
    if winN >= UNION_MAX then return end
    local fields = UnionFields(self, id)
    if not fields then return end
    if not answered[k] then answeredN = answeredN + 1 end
    answered[k], winN = now, winN + 1
    if answeredN > 200 then
        for key, t in pairs(answered) do if now - t >= UNION_GAP then answered[key] = nil; answeredN = answeredN - 1 end end
    end
    self:Whisper(sender, "SR~" .. table.concat(fields, "~"), true)
end

-- (solo de a quien se lo he preguntado, con la etiqueta de su hermandad y en esta pregunta; cada número se mira)
HU:RegisterMessage("SR", { open = true, ttl = 15 })
HU.comm.SR = function(self, sender, f, dist)
    local run = unionRun
    if dist ~= "WHISPER" or not run or f[2] ~= run.id then return end
    local row = run.byKey[sender:lower()]
    if not row or row.tag ~= f[1] or row.data then return end
    local d = ParseUnion(f)
    if not d then
        row.bad = true
        return self:Debug("Estadísticas de la unión: números que no valen de", sender)
    end
    row.data = d
end

local function UnionLine(d)
    return string.format(L("%d miembros · conectados %d · activos %d (%.0f%%) · alts %d (%.0f%%) · nivel medio %.1f (máx. %d)"),
        d.total, d.online, d.active, Pct(d.active, d.total), d.alts, Pct(d.alts, d.total),
        d.levelN > 0 and d.levelSum / d.levelN or 0, d.maxLevel)
end

local function UnionRow(self, row)
    local head = "<" .. tostring(row.tag) .. ">  "
    if row.mine then
        return head .. L("(la mía)") .. "  " .. (row.data and UnionLine(row.data) or L("aún no tengo la lista de mi hermandad"))
    end
    if not row.name then return head .. L("no conozco a nadie suyo conectado con el addon") end
    local who = self:Nice(row.name)
    if row.data then return head .. who .. "  " .. UnionLine(row.data) end
    return head .. who .. (row.officer and "" or L(" (no sé si es oficial)")) .. "  "
        .. (row.bad and L("ha contestado con números que no valen") or L("NO HA CONTESTADO"))
end

-- (la suma de las que han contestado, la mía incluida; el nivel más alto, el mayor de todos. La que no ha contestado
-- suma ZERO)
local ZERO = {}
for _, k in ipairs(UNION_FIELDS) do ZERO[k] = 0 end
-- (suma una lista de cuántos a otra; la que no ha llegado no suma)
local function AddList(into, list)
    for i, v in ipairs(list or {}) do into[i] = (into[i] or 0) + v end
end
local function AddUp(rows)
    local t = { classes = {}, races = {}, profs = {} }
    for _, k in ipairs(UNION_FIELDS) do t[k] = 0 end
    for _, row in ipairs(rows) do
        local d = row.data or ZERO
        for _, k in ipairs(UNION_FIELDS) do t[k] = (k == "maxLevel") and math.max(t[k], d[k]) or (t[k] + d[k]) end
        AddList(t.classes, d.classes)
        AddList(t.races, d.races)
        AddList(t.profs, d.profs)
    end
    return t
end

-- (el nombre de una raza por su clave, en el idioma del addon: HU.RACE_NAMES de Social.lua; de una profesión, el del
-- juego o el nuestro, Packs/Professions.lua; de una clase, ClassLabel)
local function RaceLabel(k)
    local n = HU.RACE_NAMES[k]
    return n and ((HU.lang == "en" and n.en) or n.es) or k
end
local function ProfLabel(id) return HU:ProfessionName(id) end
-- (una sección: cuántos hay de cada uno, de más a menos y con su nombre; los que no hay, fuera)
local function CountLines(out, title, counts, keys, label)
    out[#out + 1] = title
    local byName = {}
    for i, k in ipairs(keys) do
        local n, name = counts[i] or 0, label(k)
        if n > 0 then byName[name] = (byName[name] or 0) + n end
    end
    local rows = Sorted(byName)
    for _, r in ipairs(rows) do out[#out + 1] = string.format("  %-18s %3d", r.name, r.n) end
    if #rows == 0 then out[#out + 1] = "  -" end
end

local function TotalLines(t)
    local out = {
        string.format(L("Miembros: %d  ·  conectados: %d"), t.total, t.online)
            .. (t.mobile > 0 and string.format(L("  ·  con el móvil: %d"), t.mobile) or ""),
        string.format(L("Activos (vistos en %d días): %d (%.0f%%)  ·  sin contar alts: %.0f%%"), ACTIVE_DAYS, t.active,
            Pct(t.active, t.total), Pct(t.activeNoAlt, t.totalNoAlt)),
        string.format(L("Alts: %d (%.0f%%)"), t.alts, Pct(t.alts, t.total)),
        string.format(L("Niveles: máximo %d  ·  media %.1f  ·  al %d: %d"), t.maxLevel,
            t.levelN > 0 and t.levelSum / t.levelN or 0, MAX_LEVEL, t.b4),
    }
    for i, label in ipairs({ "1-19", "20-39", "40-59", tostring(MAX_LEVEL) }) do
        out[#out + 1] = string.format("  %-7s %3d", label, t["b" .. i])
    end
    out[#out + 1] = L("Actividad:")
    out[#out + 1] = string.format(L("  Altas: %d (7 días)  ·  %d (30 días)"), t.joined7, t.joined30)
    out[#out + 1] = string.format(L("  Bajas: %d (7 días)  ·  %d (30 días)"), t.left7, t.left30)
    out[#out + 1] = string.format(L("  Sin conectarse: %d (más de 7 días)  ·  %d (más de 30 días)"), t.inactive7, t.inactive30)
    CountLines(out, L("Clases:"), t.classes, UNION_CLASSES, ClassLabel)
    CountLines(out, L("Razas:"), t.races, HU.RACE_ORDER, RaceLabel)
    CountLines(out, L("Profesiones:"), t.profs, UNION_PROFS, ProfLabel)
    return out
end

local function ShowUnion(self, run)
    if unionRun ~= run then return end
    unionRun = nil
    local lines = { HU.ADDON_TITLE .. " " .. tostring(HU.version) .. " - " .. L("estadísticas de la unión") .. " - "
        .. date("%d/%m/%Y %H:%M"),
        L("Cada hermandad da solo números, sin nombres: los cuenta uno de sus oficiales con la lista de su hermandad."), "" }
    local known, got = 0, 0
    for _, row in ipairs(run.rows) do
        lines[#lines + 1] = UnionRow(self, row)
        if row.mine or row.name then known = known + 1 end
        if row.data then got = got + 1 end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = L("Toda la unión, sumando las que han contestado:")
    for _, l in ipairs(TotalLines(AddUp(run.rows))) do lines[#lines + 1] = "  " .. l end
    local summary = string.format(L("Estadísticas de la unión: han contestado %d de %d."), got, known)
    lines[#lines + 1] = ""
    lines[#lines + 1] = summary
    self:Print(summary)
    if self.UI and self.UI.ShowCopy then
        self.UI:ShowCopy(L("Estadísticas de la unión"), table.concat(lines, "\n"),
            { hint = L("Ctrl+A selecciona todo · Ctrl+C copia · pégalo en Discord o en un archivo de texto") })
    else
        for _, l in ipairs(lines) do self:Print(l) end
    end
end

-- «Pedir a la unión» (ventana de /gu stats; oficiales y el maestro): pregunta a un oficial de cada hermandad y a los
-- UNION_WAIT s enseña lo que ha llegado, con lo de la mía y la suma
function HU:AskUnionStats()
    if not self:CanSeeStats() then return self:Print(L("Las estadísticas son solo para oficiales.")) end
    if not (self.cfg and self.myTag) then return self:Print(L("Aún no hay comunidad: no sé qué hermandades mirar.")) end
    if unionRun then return self:Print(L("Ya estás pidiendo las estadísticas de la unión: el resultado sale en unos segundos.")) end
    local wait = math.ceil(UNION_GAP - (GetTime() - unionAskT))
    if wait > 0 then
        return self:Print(string.format(L("Espera %d s para volver a pedirlas: cada hermandad contesta como mucho una vez cada %d s."), wait, UNION_GAP))
    end
    if HU.paused or self:IsChatLockedDown() then
        return self:Print(L("Ahora no se pueden mandar mensajes del addon (el juego bloquea el chat): prueba en un rato."))
    end
    unionAskT = GetTime()
    local run = { id = HU.B36(time()), rows = {}, byKey = {} }
    unionRun = run
    HU.After(UNION_WAIT, function() ShowUnion(HU, run) end)
    -- (la mía, con mis números: sin mensajes)
    run.rows[1] = { tag = self.myTag, mine = true, data = ParseUnion(UnionFields(self, run.id) or {}) }
    local asked = 0
    for _, tag in ipairs(self:OtherTags()) do
        local p, officer = UnionTarget(self, tag)
        local row = { tag = tag, name = p and p.name, officer = officer }
        local k = row.name and self:Key(row.name)
        if k and k ~= self:MeKey() then
            run.byKey[k] = row
            asked = asked + 1
            self:Whisper(row.name, "SQ~" .. self.myTag .. "~" .. run.id, true)
        end
        run.rows[#run.rows + 1] = row
    end
    self:Print(string.format(L("Pidiendo las estadísticas a la unión: preguntado a %d. El resultado, en %d s."), asked, UNION_WAIT))
end

HU:RegisterSlash("stats", { aliases = { "estadisticas" }, fn = function() HU:ShowGuildStats() end })

HU:Module("GuildStats", { "Comm", "Config", "Core", "Domain/Trust", "Guard", "Lists", "Net/Relay", "Net/RosterSync", "Net/Security", "Net/Transport", "Packs/Professions", "Protocol", "Ranks", "Roster", "TradeCraft" })
