-- Guild Union - estadísticas de la hermandad, para oficiales y el maestro (Jorge, 26/11) [+ARCHITECTURE.md]
-- Miembros, rangos, niveles, clases y actividad (altas, bajas e inactivos), de la lista de la hermandad
-- (Roster.lua) y del registro de altas y bajas (InviteLog.lua). Se enseñan en una ventana para copiar (Ctrl+C) y
-- pegar en Discord o en un archivo de texto: un addon no puede escribir archivos, así que «exportar» es copiar.
local _, HU = ...
local L = HU.L

local MAX_LEVEL = 60   -- (Forever es contenido vanilla: el tope es 60)
local DAY = 86400

-- ¿Puede ver las estadísticas? Los oficiales (ven la nota de oficial) y el maestro
function HU:CanSeeStats()
    return (self:CanOfficer() or (IsGuildLeader and IsGuildLeader())) and true or false
end

-- (cuántas entradas de un registro (altas o bajas) caen en los últimos `days` días)
local function CountRecent(log, days)
    local n, since = 0, time() - days * DAY
    for _, e in ipairs(log or {}) do if type(e.t) == "number" and e.t >= since then n = n + 1 end end
    return n
end

-- Las estadísticas, en una tabla (la usan la ventana y las pruebas). nil si no estoy en una hermandad
function HU:GuildStats()
    local guild = IsInGuild() and GetGuildInfo and GetGuildInfo("player")
    if not guild then return nil end
    local roster = self.rosterList or {}
    local s = {
        guild = guild, total = #roster, online = 0, mobile = 0,
        byRank = {}, byClass = {},
        maxLevel = 0, avgLevel = 0,
        levelBuckets = { { "1-19", 0 }, { "20-39", 0 }, { "40-59", 0 }, { tostring(MAX_LEVEL), 0 } },
        inactive7 = 0, inactive30 = 0,
    }
    local rankTotals, rankOnline, rankLabel, classN = {}, {}, {}, {}
    local sumLevel, levelN = 0, 0
    for _, e in ipairs(roster) do
        if e.online then s.online = s.online + 1 end
        if e.mobile then s.mobile = s.mobile + 1 end
        local ri = e.rankIndex or 99
        rankTotals[ri] = (rankTotals[ri] or 0) + 1
        if e.online then rankOnline[ri] = (rankOnline[ri] or 0) + 1 end
        rankLabel[ri] = rankLabel[ri] or e.rank or self:RankName(self.myTag, ri)
        if type(e.class) == "string" and e.class ~= "" then classN[e.class] = (classN[e.class] or 0) + 1 end
        local lv = tonumber(e.level)
        if lv and lv > 0 then
            sumLevel, levelN = sumLevel + lv, levelN + 1
            if lv > s.maxLevel then s.maxLevel = lv end
            local b = (lv >= MAX_LEVEL and 4) or (lv >= 40 and 3) or (lv >= 20 and 2) or 1
            s.levelBuckets[b][2] = s.levelBuckets[b][2] + 1
        end
        -- (inactivos: solo desconectados; offSecs son los segundos que lleva sin conectarse, Roster.lua)
        local off = e.offSecs
        if type(off) == "number" then
            if off >= 30 * DAY then s.inactive30 = s.inactive30 + 1 end
            if off >= 7 * DAY then s.inactive7 = s.inactive7 + 1 end
        end
    end
    s.avgLevel = levelN > 0 and (sumLevel / levelN) or 0
    -- (rangos por índice: el 0 es el maestro, así que de más alto a más bajo)
    local ris = {}
    for ri in pairs(rankTotals) do ris[#ris + 1] = ri end
    table.sort(ris)
    for _, ri in ipairs(ris) do
        s.byRank[#s.byRank + 1] = { name = rankLabel[ri] or (L("Rango ") .. ri), total = rankTotals[ri], online = rankOnline[ri] or 0 }
    end
    -- (clases de más a menos)
    for c, n in pairs(classN) do s.byClass[#s.byClass + 1] = { name = c, n = n } end
    table.sort(s.byClass, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    -- (altas y bajas, del registro propio, por hermandad; InviteLog.lua)
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
    add(HU.ADDON_TITLE .. " - " .. string.format(L("Estadísticas de %s"), s.guild) .. " - " .. date("%d/%m/%Y %H:%M"))
    add("")
    add(string.format(L("Miembros: %d  ·  conectados: %d"), s.total, s.online)
        .. (s.mobile > 0 and string.format(L("  ·  con el móvil: %d"), s.mobile) or ""))
    add("")
    add(L("Por rango:"))
    for _, r in ipairs(s.byRank) do
        add(string.format("  %-22s %3d  (%d %s)", r.name, r.total, r.online, L("conectados")))
    end
    add("")
    add(string.format(L("Niveles: máximo %d  ·  media %.1f  ·  al %d: %d"), s.maxLevel, s.avgLevel, MAX_LEVEL, s.levelBuckets[4][2]))
    for _, b in ipairs(s.levelBuckets) do add(string.format("  %-7s %3d", b[1], b[2])) end
    add("")
    add(L("Clases:"))
    for _, c in ipairs(s.byClass) do add(string.format("  %-18s %3d", c.name, c.n)) end
    add("")
    add(L("Actividad:"))
    add(string.format(L("  Altas: %d (7 días)  ·  %d (30 días)"), s.joined7, s.joined30))
    add(string.format(L("  Bajas: %d (7 días)  ·  %d (30 días)"), s.left7, s.left30))
    add(string.format(L("  Sin conectarse: %d (más de 7 días)  ·  %d (más de 30 días)"), s.inactive7, s.inactive30))
    return table.concat(lines, "\n")
end

-- La ventana: el texto para copiar (Ctrl+A, Ctrl+C) y pegar en Discord o en un archivo
function HU:ShowGuildStats()
    if not self:CanSeeStats() then return self:Print(L("Las estadísticas son solo para oficiales.")) end
    local text = self:GuildStatsText()
    if self.UI and self.UI.ShowCopy then
        self.UI:ShowCopy(L("Estadísticas de la hermandad"), text,
            { hint = L("Ctrl+A selecciona todo · Ctrl+C copia · pégalo en Discord o en un archivo de texto") })
    else
        for l in text:gmatch("[^\n]+") do self:Print(l) end
    end
end

HU:RegisterSlash("stats", { aliases = { "estadisticas" }, fn = function() HU:ShowGuildStats() end })

HU:Module("GuildStats", { "Core", "Ranks", "Roster" })
