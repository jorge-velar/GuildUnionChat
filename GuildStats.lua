-- Guild Union - estadísticas de la hermandad, para oficiales y el maestro (Jorge, 26/11) [+ARCHITECTURE.md]
-- Miembros, rangos, niveles, clases, razas, profesiones y actividad (activos, alts, inactivos), con gráficos de barras
-- en el juego (como los addons de estadísticas) y un botón para exportar el texto a Discord o a un archivo. Todo sale de
-- datos que GuildUnion ya tiene (la lista de la hermandad y el registro de altas/bajas): sin red nueva.
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

-- (la raza, por el GUID; nil si no se puede saber)
local function RaceOf(guid)
    if not (guid and GetPlayerInfoByGUID) then return nil end
    local ok, _, _, race = pcall(GetPlayerInfoByGUID, guid)
    if ok and type(race) == "string" and race ~= "" and not HU.Secret(race) then return race end
    return nil
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

-- Las estadísticas, en una tabla (la usan la ventana y las pruebas). nil si no estoy en una hermandad
function HU:GuildStats()
    local guild = IsInGuild() and GetGuildInfo and GetGuildInfo("player")
    if not guild then return nil end
    local roster = self.rosterList or {}
    local s = {
        guild = guild, total = #roster, online = 0, mobile = 0,
        active = 0, alts = 0, activeNoAlt = 0, totalNoAlt = 0,
        byRank = {}, byClass = {}, byRace = {},
        professions = self:GuildProfessionCounts(),
        maxLevel = 0, avgLevel = 0,
        levelBuckets = { { "1-19", 0 }, { "20-39", 0 }, { "40-59", 0 }, { tostring(MAX_LEVEL), 0 } },
        inactive7 = 0, inactive30 = 0,
    }
    local rankTotals, rankOnline, rankLabel, classN, raceN = {}, {}, {}, {}, {}
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
        local race = RaceOf(e.guid)
        if race then raceN[race] = (raceN[race] or 0) + 1 end
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

HU:RegisterSlash("stats", { aliases = { "estadisticas" }, fn = function() HU:ShowGuildStats() end })

HU:Module("GuildStats", { "Core", "Ranks", "Roster", "TradeCraft" })
