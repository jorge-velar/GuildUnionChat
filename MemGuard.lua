-- Guild Union - tope de memoria: si el addon pasa de LIMIT_MB, se borra lo más viejo (primero lo que
-- se puede volver a calcular, luego los días más viejos del historial de oficiales y por último el chat)
local ADDON_NAME, HU = ...
local L = HU.L

HU.MEM_LIMIT_MB = 20
-- (cada 15 min, fuera de combate y con el panel cerrado: medir la memoria de los addons le cuesta al
-- juego ~50 ms con muchos addons, y con el panel abierto cuenta la basura que aún no se ha limpiado)
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
    if self.HistDropCaches then self:HistDropCaches() end
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
    if not warned and self.CanPin and self:CanPin() then
        warned = true
        self:Print(string.format(L("Memoria del addon por encima de %d MB (%.1f MB): se ha borrado lo más viejo; ahora %.1f MB."), HU.MEM_LIMIT_MB, before, mb))
    end
    if self.TestLogAdd then self.TestLogAdd("memoria", string.format("%.1f MB -> %.1f MB", before, mb)) end
    return mb
end

HU:OnStart(function()
    HU.NewTicker(CHECK, function()
        if InCombatLockdown and InCombatLockdown() then return end
        if HU.UI and HU.UI.frame and HU.UI.frame:IsShown() then return end
        HU:MemTrim()
    end)
end)
