-- Guild Union - ventana de órdenes (/ginvite, /gpromote, /gdemote, /gremove) [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L

local dialog, job
local queue = {}   -- listas que esperan a que acabe la que está en curso
local function StartQueued()
    if job or #queue == 0 then return end
    local nextJob = table.remove(queue, 1)
    HU.After(0.3, function() HU:RunOrders(nextJob) end)
end

---------------------------------------------------------------------------
-- ¿Está «contaminado» un comando del chat? (por cualquier addon; se arregla con /reload)
-- Devuelve: nil si Blizzard aún no lo ha cargado, true si está limpio, o false y quién lo contaminó
---------------------------------------------------------------------------
function HU:CommandTaint(cmd)
    local hash = rawget(_G, "hash_SlashCmdList")
    if type(hash) ~= "table" or rawget(hash, cmd) == nil or not issecurevariable then return nil end
    local secure, by = issecurevariable(hash, cmd)
    return secure and true or false, by
end

function HU:OrdersDiag()
    local any = false
    for _, c in ipairs({ "/GINVITE", "/GPROMOTE", "/GDEMOTE", "/GREMOVE" }) do
        local ok, by = self:CommandTaint(c)
        any = true
        if ok == nil then self:Print(c .. L(": el juego aún no lo ha cargado"))
        elseif ok then self:Print(c .. L(": |cff44ff44limpio|r"))
        else self:Print(c .. L(": |cffff4444bloqueado|r (lo tocó ") .. tostring(by) .. L("). Se arregla con /reload")) end
    end
    if not any then self:Print(L("Sin datos.")) end
end

local function Finish()
    local done = job
    job = nil
    if dialog then dialog:Hide() end
    if done and done.onDone then done.onDone(done.sent) end
    StartQueued()
end

local function Consume(n)
    for _ = 1, n do
        local line = table.remove(job.lines, 1)
        if line then
            job.sent = job.sent + 1
            if job.onLine then HU:SafeCall("orden", job.onLine, line) end
        end
    end
end

-- la orden actual, seleccionada y lista para Ctrl+C
local function Refresh()
    if not dialog or not job then return end
    -- invitaciones: si esa persona ya entró en la hermandad (aceptó mientras tanto), se salta
    while job.lines[1] do
        local who = job.lines[1]:match("^/ginvite%s+(.+)$")
        if not (who and HU:InMyGuild(who)) then break end
        table.remove(job.lines, 1)
        HU:Print(HU:Nice(who) .. L(" fuera de la lista de invitación: ya en la hermandad."))
    end
    if #job.lines == 0 then return Finish() end
    local line = job.lines[1]
    dialog.title:SetText(job.title or L("Órdenes"))
    dialog.body:SetText(job.text or "")
    dialog.progress:SetText(string.format(L("Hechas %d de %d"), job.sent, job.sent + #job.lines))
    dialog.cmd.value = line
    dialog.cmd:SetText(line)
    dialog.cmd:SetFocus()
    dialog.cmd:HighlightText()
end

local function Next()
    if not job or #job.lines == 0 then return end
    Consume(1)
    Refresh()
end

---------------------------------------------------------------------------
-- Respuestas del juego en el chat: si hablan de la persona de la orden actual, se pasa a la siguiente
---------------------------------------------------------------------------
local RESULT_STRINGS = {
    "ERR_GUILD_INVITE_S", "ERR_GUILD_PLAYER_NOT_FOUND_S", "ERR_ALREADY_IN_GUILD_S",
    "ERR_ALREADY_INVITED_TO_GUILD_S", "ERR_GUILD_PROMOTE_SSS", "ERR_GUILD_DEMOTE_SSS",
    "ERR_GUILD_REMOVE_SS", "ERR_GUILD_RANK_TOO_HIGH_S", "ERR_GUILD_RANK_TOO_LOW_S",
    "ERR_CHAT_PLAYER_NOT_FOUND_S", "ERR_GUILD_NOT_ALLIED", "ERR_GUILD_PERMISSIONS",
}
local patterns

-- "Has invitado a %s a tu hermandad." -> patrón que captura cada %s (también %1$s) y salta %d
local function ToPattern(fmt)
    local p = fmt:gsub("%%%d*%$?s", "\1"):gsub("%%%d*%$?d", "\2")
    p = p:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local hasName = p:find("\1", 1, true) ~= nil
    p = p:gsub("\1", "(.+)"):gsub("\2", "%%d+")
    return { pat = "^" .. p .. "$", hasName = hasName }
end

local function Patterns()
    if patterns then return patterns end
    patterns = {}
    for _, name in ipairs(RESULT_STRINGS) do
        local fmt = rawget(_G, name)
        if type(fmt) == "string" and fmt ~= "" then patterns[#patterns + 1] = ToPattern(fmt) end
    end
    return patterns
end

local function CleanName(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("[%[%]\"]", "")
    return s
end

-- ¿el mensaje del juego es la respuesta a la orden de esta persona?
local function AboutTarget(text, target)
    local want = HU:Key(target)
    if not want then return false end
    for _, p in ipairs(Patterns()) do
        local caps = { text:match(p.pat) }
        if #caps > 0 then
            -- (sin nombre, como «no tienes permiso»: también es la respuesta)
            if not p.hasName then return true end
            for _, c in ipairs(caps) do
                if HU:Key(CleanName(c)) == want then return true end
            end
        end
    end
    return false
end

local lastSentAt = -100   -- cuándo se pasó de orden por tu Intro en el chat

HU:On("CHAT_MSG_SYSTEM", function(text)
    if not job or #job.lines == 0 or type(text) ~= "string" or HU.Secret(text) then return end
    -- (si ya se pasó con tu Intro, esta es la respuesta a la orden anterior: no se pasa otra vez)
    if GetTime() - lastSentAt < 5 then return end
    local target = job.lines[1]:match("^/%S+%s+(.+)$")
    if target and AboutTarget(text, target) then
        HU.After(0.3, Next)
    end
end)

---------------------------------------------------------------------------
-- Tu segundo Intro (el que envía la orden en el chat): si lo enviado es la orden de la ventana, [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local function Norm(s)
    s = s:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return s
end

local function WatchChatBox(box)
    if not box or box.guWatched or not box.HookScript then return end
    box.guWatched = true
    box:HookScript("OnTextChanged", function(self)
        local t = self:GetText()
        if type(t) == "string" and t ~= "" and not HU.Secret(t) then
            self.guLast, self.guLastAt = t, GetTime()
        end
    end)
    box:HookScript("OnEscapePressed", function(self) self.guLast = nil end)
    box:HookScript("OnEnterPressed", function(self)
        local sent, at = self.guLast, self.guLastAt or 0
        self.guLast = nil
        if job and #job.lines > 0 and sent and GetTime() - at < 120 and Norm(sent) == Norm(job.lines[1]) then
            lastSentAt = GetTime()
            -- (un instante después, cuando el chat ya se ha cerrado)
            HU.After(0.1, Next)
        end
    end)
end

HU:OnStart(function()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do WatchChatBox(_G["ChatFrame" .. i .. "EditBox"]) end
end)

---------------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------------
local function Build()
    local f = CreateFrame("Frame", "GuildUnionOrders", UIParent, "BackdropTemplate")
    f:SetSize(400, 240)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -20)

    f.body = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT", 24, -46)
    f.body:SetPoint("TOPRIGHT", -24, -46)
    f.body:SetJustifyH("LEFT")
    f.body:SetMaxLines(3)

    f.progress = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    f.progress:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -8)

    -- la orden, seleccionada: Ctrl+C la copia y la caja suelta el teclado (así Intro abre el chat)
    local cmd = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    cmd:SetSize(340, 22)
    cmd:SetPoint("TOPLEFT", f.progress, "BOTTOMLEFT", 6, -10)
    cmd:SetAutoFocus(false)
    cmd:SetFontObject(ChatFontNormal)
    cmd:SetScript("OnTextChanged", function(self, userInput)
        -- (no se puede cambiar a mano: si se toca, vuelve la orden)
        if userInput and self.value and self:GetText() ~= self.value then
            self:SetText(self.value)
            self:HighlightText()
        end
    end)
    cmd:SetScript("OnKeyDown", function(self, key)
        if key == "C" and IsControlKeyDown() then
            HU.After(0, function() self:ClearFocus() end)
        end
    end)
    cmd:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    cmd:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    cmd:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    cmd:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    f.cmd = cmd

    f.hint = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    f.hint:SetPoint("TOPLEFT", cmd, "BOTTOMLEFT", -6, -10)
    f.hint:SetPoint("RIGHT", -24, 0)
    f.hint:SetJustifyH("LEFT")
    -- (la letra del juego no tiene la flecha: salia un cuadro)
    f.hint:SetText("|cffffd100Ctrl+C|r  >  |cffffd100Intro|r  >  |cffffd100Ctrl+V|r  >  |cffffd100Intro|r\n"
        .. "|cffaaaaaa" .. L("Al enviarla (el segundo Intro) pasa sola a la siguiente.") .. "|r")

    local copy = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    copy:SetSize(110, 24)
    copy:SetPoint("BOTTOMLEFT", 20, 18)
    copy:SetText(L("Seleccionar"))
    copy:SetScript("OnClick", function() cmd:SetFocus(); cmd:HighlightText() end)

    local nextBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextBtn:SetSize(100, 24)
    nextBtn:SetPoint("LEFT", copy, "RIGHT", 6, 0)
    nextBtn:SetText(L("Siguiente"))
    nextBtn:SetScript("OnClick", Next)
    nextBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:SetText(L("Dar esta por hecha y pasar a la siguiente"))
        GameTooltip:AddLine(L("Por si el juego no contesta nada en el chat."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    nextBtn:SetScript("OnLeave", GameTooltip_Hide)

    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(90, 24)
    cancel:SetPoint("BOTTOMRIGHT", -20, 18)
    cancel:SetText(L("Cerrar"))
    local function Close()
        local left = job and #job.lines or 0
        local done = job
        job = nil
        f:Hide()
        if left > 0 then HU:Print(L("Cerrado: ") .. left .. L(" órdenes sin hacer.")) end
        if done and done.onDone then done.onDone(done.sent) end
        StartQueued()
    end
    cancel:SetScript("OnClick", Close)
    -- (Escape: igual que Cerrar)
    f:SetScript("OnHide", function() if job then Close() end end)
    tinsert(UISpecialFrames, "GuildUnionOrders")
    f:Hide()
    return f
end

-- job = { title, text, lines = {...}, onDone(sent), onLine(line) }
function HU:RunOrders(newJob)
    if not newJob or not newJob.lines or #newJob.lines == 0 then return false end
    newJob.sent = 0
    if job and #job.lines > 0 then
        queue[#queue + 1] = newJob
        self:Print(L("Hay otra lista de órdenes a medias: esta va después (") .. #queue .. L(" en espera)."))
        return true
    end
    dialog = dialog or Build()
    job = newJob
    dialog:Show()
    dialog:Raise()
    Refresh()
    return true
end
