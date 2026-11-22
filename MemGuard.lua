-- Guild Union - tope de memoria: si el addon pasa de LIMIT_MB, se borra lo más viejo (primero lo que
-- se puede volver a calcular, luego los días más viejos del historial de oficiales y por último el chat)
local ADDON_NAME, HU = ...
local L = HU.L

HU.MEM_LIMIT_MB = 20
-- (como mucho cada 15 min, fuera de combate y con el panel cerrado: con el panel abierto cuenta la
-- basura que aún no se ha limpiado. Cuándo se mide: abajo, copia 165)
local CHECK = 900
local CHAT_MIN = 1500   -- el chat del panel no baja de aquí
local warned = false

local function AddonMB()
    local upd = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
    local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
    if not upd or not get then return nil end
    pcall(upd)
    local ok, kb = pcall(get, ADDON_NAME)
    return ok and tonumber(kb) and kb / 1024 or nil
end

function HU:MemTrim()
    local mb = AddonMB()
    if not mb or mb <= HU.MEM_LIMIT_MB then self.memRounds, self.memOver = nil, nil; return mb end
    -- (solo si se pasa dos veces seguidas: una sola puede ser basura que el juego aún no ha limpiado)
    if not self.memOver then self.memOver = true; return mb end
    local before = mb
    -- 1) lo que se puede volver a calcular
    self:HistDropCaches()
    collectgarbage("collect")
    mb = AddonMB() or mb
    -- 2) los días más viejos del historial de oficiales: 3 por vuelta, una vuelta por segundo
    if mb > HU.MEM_LIMIT_MB and self.HistDropOldestDay and (self.memRounds or 0) < 10 then
        local dropped = 0
        while dropped < 3 and self:HistDropOldestDay() do dropped = dropped + 1 end
        if dropped > 0 then
            self.memRounds = (self.memRounds or 0) + 1
            collectgarbage("collect")
            HU.After(1, function() HU:MemTrim() end)
            return AddonMB() or mb
        end
    end
    self.memRounds = nil
    -- 3) el chat del panel, lo más viejo
    local h = self.db and self.db.history
    if mb > HU.MEM_LIMIT_MB and h and #h > CHAT_MIN then
        local keep = {}
        for i = #h - CHAT_MIN + 1, #h do keep[#keep + 1] = h[i] end
        for i = #h, 1, -1 do h[i] = nil end
        for i, e in ipairs(keep) do h[i] = e end
        if self.UI and self.UI.FillChat then self.UI:FillChat() end
        collectgarbage("collect")
        mb = AddonMB() or mb
    end
    if not warned and self:CanPin() then
        warned = true
        self:Print(string.format(L("Memoria del addon por encima de %d MB (%.1f MB): se ha borrado lo más viejo; ahora %.1f MB."), HU.MEM_LIMIT_MB, before, mb))
    end
    self.TestLogAdd("memoria", string.format("%.1f MB -> %.1f MB", before, mb))
    return mb
end

-- (copia 165) Medir la memoria de los addons recorre TODOS los addons del jugador: con muchos, 70-170 ms [+ARCHITECTURE.md]
local FALLBACK = 7200   -- si en 2 h no hay pantalla de carga ni ausente, se mide igual una vez
local lastCheck = -1e9
local function Check()
    if GetTime() - lastCheck < CHECK then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if HU.UI and HU.UI.frame and HU.UI.frame:IsShown() then return end
    lastCheck = GetTime()
    HU:MemTrim()
end
-- (durante la pantalla de carga: el juego ya está parado y no se nota)
HU:On("PLAYER_ENTERING_WORLD", function() HU:SafeCall("memoria", Check) end)
HU:OnStart(function()
    -- (cada minuto se mira si toca: solo ausente, o si en FALLBACK no ha habido pantalla de carga)
    HU:Every(60, "memoria", function()
        local ok, afk = pcall(UnitIsAFK, "player")
        afk = ok and HU.SafeBool(afk, false)
        if afk or GetTime() - lastCheck >= FALLBACK then Check() end
    end)
end)

HU:Module("MemGuard", { "Core", "History", "Pinned" })
