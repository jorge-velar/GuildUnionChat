-- Guild Union - órdenes de hermandad (/ginvite, /gpromote, /gdemote, /gremove): con un botón seguro y tu clic; si el
-- juego no lo deja, la ventana para copiarlas y pegarlas en el chat [+ARCHITECTURE.md]
local ADDON, HU = ...
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
    -- (solo con la ventana de copiar y pegar: con el botón, las respuestas no mandan)
    if not (job and dialog and dialog:IsShown()) or #job.lines == 0 or type(text) ~= "string" or HU.Secret(text) then return end
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
        if job and dialog and dialog:IsShown() and #job.lines > 0 and sent and GetTime() - at < 120
            and Norm(sent) == Norm(job.lines[1]) then
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
    -- (escondida antes de poner su OnHide: si no, al esconderla cerraría la lista que acaba de llegar)
    f:Hide()
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
    return f
end

---------------------------------------------------------------------------
-- Con un botón seguro: en Forever /gremove, /gpromote y /gdemote son órdenes seguras (como /cast) y un botón [+ARCHITECTURE.md]
-- seguro las lanza con tu clic, tras confirmar; /ginvite no (copiar y pegar). Si el juego lo bloquea, copiar y pegar
---------------------------------------------------------------------------
local SECURE = { ["/gremove"] = true, ["/gpromote"] = true, ["/gdemote"] = true }
local BLOCK_WAIT = 1.5      -- tras el clic, cuánto se espera a ver si el juego lo ha bloqueado
local secureOff = false     -- el juego lo ha bloqueado en esta sesión: copiar y pegar hasta /reload
local confirm, waiting      -- la ventanita de confirmar; waiting = { blocked } entre el clic y la comprobación
local Present

local function AllSecure(lines)
    for _, line in ipairs(lines) do
        local cmd = line:match("^(/%S+)")
        if not (cmd and SECURE[cmd:lower()]) then return false end
    end
    return true
end

-- (el juego avisa así cuando no deja hacer algo: a una macro, o a un addon por su nombre)
for _, ev in ipairs({ "MACRO_ACTION_BLOCKED", "MACRO_ACTION_FORBIDDEN" }) do
    HU:On(ev, function() if waiting then waiting.blocked = true end end)
end
for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    HU:On(ev, function(addon) if waiting and addon == ADDON then waiting.blocked = true end end)
end

-- (combate: la ventanita, con su botón seguro, no se puede mover ni cerrar; se esconde justo antes y vuelve al
-- salir, con las mismas órdenes)
HU:On("PLAYER_REGEN_DISABLED", function()
    if confirm and confirm:IsShown() and job and not waiting then
        job.afterCombat = true
        confirm.acting = true
        confirm:Hide()
        confirm.acting = nil
    end
end)
HU:On("PLAYER_REGEN_ENABLED", function()
    if job and job.afterCombat and not waiting then
        job.afterCombat = nil
        Present()
    end
end)

local function ShowCopyPaste()
    dialog = dialog or Build()
    dialog:Show()
    dialog:Raise()
    Refresh()
end

-- (tras el clic: si el juego no ha dicho nada, hechas todas; si lo ha bloqueado, a copiar y pegar)
local function AfterClick()
    local w = waiting
    waiting = nil
    if not (w and job) then return end
    if w.blocked then
        secureOff = true
        HU:Print(L("El juego no ha dejado hacerlo con el botón: cópialas y pégalas en el chat."))
        ShowCopyPaste()
        return
    end
    Consume(#job.lines)
    Finish()
end

local function BuildConfirm()
    local f = CreateFrame("Frame", "GuildUnionOrdersConfirm", UIParent, "BackdropTemplate")
    -- (escondida antes de poner su OnHide: si no, al esconderla cancelaría la orden que acaba de llegar)
    f:Hide()
    f:SetSize(380, 200)
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
    -- (como las preguntas del juego: la pregunta arriba, debajo los nombres si son varios, y Sí / No)
    f.body = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT", 24, -24)
    f.body:SetPoint("TOPRIGHT", -24, -24)
    f.body:SetJustifyH("CENTER")
    f.cmds = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.cmds:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -10)
    f.cmds:SetPoint("RIGHT", -24, 0)
    f.cmds:SetJustifyH("CENTER")
    f.cmds:SetMaxLines(8)
    -- «Sí»: el botón seguro, que lanza al soltar (useOnKeyDown); también al pulsar, por si el juego usa el otro
    local yes = CreateFrame("Button", "GuildUnionOrdersYes", f, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    yes:SetSize(110, 24)
    yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 18)
    yes:SetText(L("Sí"))
    yes:RegisterForClicks("AnyUp", "AnyDown")
    yes:SetAttribute("type", "macro")
    yes:SetAttribute("useOnKeyDown", false)
    -- (al soltar, cuando el juego ya la ha lanzado: se cierra y se mira si la ha bloqueado)
    yes:HookScript("PostClick", function(_, _, down)
        if down or waiting or not job then return end
        waiting = {}
        f.acting = true
        f:Hide()
        f.acting = nil
        HU.After(BLOCK_WAIT, AfterClick)
    end)
    f.yes = yes
    local no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    no:SetSize(110, 24)
    no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 18)
    no:SetText(L("No"))
    local function Cancel()
        if waiting then return end
        local done = job
        job = nil
        f:Hide()
        if done and done.onDone then done.onDone(0) end
        StartQueued()
    end
    no:SetScript("OnClick", Cancel)
    -- (Escape o cerrar: igual que Cancelar, salvo al cerrarse tras el clic)
    f:SetScript("OnHide", function() if job and not f.acting and not waiting then Cancel() end end)
    tinsert(UISpecialFrames, "GuildUnionOrdersConfirm")
    return f
end

-- (lo que se va a hacer, en palabras y por persona: «echar a Ana de la hermandad», «subir a Ana 2 rangos»)
local function Phrases(lines)
    local order, count = {}, {}
    for _, line in ipairs(lines) do
        local cmd, who = line:match("^(/%S+)%s+(.+)$")
        cmd = cmd and cmd:lower()
        if cmd and SECURE[cmd] then
            local k = cmd .. " " .. who
            if not count[k] then order[#order + 1] = { cmd = cmd, who = who, k = k }; count[k] = 0 end
            count[k] = count[k] + 1
        end
    end
    local out = {}
    for _, o in ipairs(order) do
        local n = count[o.k]
        if o.cmd == "/gremove" then out[#out + 1] = string.format(L("echar a %s de la hermandad"), o.who)
        elseif o.cmd == "/gpromote" then
            out[#out + 1] = n > 1 and string.format(L("subir a %s %d rangos"), o.who, n) or string.format(L("subir a %s un rango"), o.who)
        else
            out[#out + 1] = n > 1 and string.format(L("bajar a %s %d rangos"), o.who, n) or string.format(L("bajar a %s un rango"), o.who)
        end
    end
    return out, order
end

-- (la pregunta, como las del juego, sin enseñar las órdenes; con varias personas, la lista debajo. Quien pide
-- las órdenes puede traer la suya: job.ask y job.list)
local function Question(j)
    if j.ask then return j.ask, j.list or "" end
    local phrases, order = Phrases(j.lines)
    if #phrases == 1 then return string.format(L("¿Seguro que quieres %s?"), phrases[1]), "" end
    local names, allRemove = {}, true
    for _, o in ipairs(order) do
        names[#names + 1] = o.who
        if o.cmd ~= "/gremove" then allRemove = false end
    end
    if allRemove then
        return string.format(L("¿Seguro que quieres echar de la hermandad a estas %d personas?"), #names), table.concat(names, "\n")
    end
    for i, p in ipairs(phrases) do phrases[i] = (p:gsub("^%l", string.upper)) end
    return L("¿Seguro que quieres hacer esto?"), table.concat(phrases, "\n")
end

local function ShowConfirm()
    confirm = confirm or BuildConfirm()
    local ask, list = Question(job)
    confirm.body:SetText(ask)
    confirm.cmds:SetText(list)
    confirm:SetHeight(76 + confirm.body:GetStringHeight() + (list ~= "" and confirm.cmds:GetStringHeight() + 10 or 0))
    confirm.yes:SetAttribute("macrotext", table.concat(job.lines, "\n"))
    confirm:Show()
    confirm:Raise()
end

-- (órdenes de hermandad: con el botón, salvo que el juego ya lo bloqueara; en combate, al salir. Lo demás, a
-- copiar y pegar)
Present = function()
    if secureOff or not AllSecure(job.lines) then return ShowCopyPaste() end
    if InCombatLockdown() then
        job.afterCombat = true
        HU:Print(L("En combate no se puede: te lo pregunto al salir."))
        return
    end
    ShowConfirm()
end

-- job = { title, text, lines = {...}, onDone(sent), onLine(line), ask, list, quiet }
function HU:RunOrders(newJob)
    if not newJob or not newJob.lines or #newJob.lines == 0 then return false end
    newJob.sent = 0
    if job and #job.lines > 0 then
        queue[#queue + 1] = newJob
        -- (quiet: quien la pide ya ha avisado, como las tandas de /gu sinaddon, Report.lua)
        if not newJob.quiet then self:Print(L("Hay otra lista de órdenes a medias: esta va después (") .. #queue .. L(" en espera).")) end
        return true
    end
    job = newJob
    Present()
    return true
end

HU:Module("Orders", { "Core", "Roster" })
