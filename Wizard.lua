-- Guild Union - asistente «Crear comunidad» (Jorge, 10/11): una sola ventana de principio a fin
--   1 nombre y etiqueta · 2 líneas de la Información · 2.1 canal libre · 3 aviso → contraseña
--   4 comprobar · 4.1 solo yo en el canal · 5 invitar · 6 esperando · 7 Información actualizada · 8 listo
-- Modo prueba (/gu asistente prueba): no entra en canales ni invita; simula que la otra acepta.
local _, HU = ...
local L = HU.L

local w
local LETTERS = "abcdefghijkmnpqrstuvwxyz" -- (sin l ni o: no se confunden con 1 y 0)
local function RandomWord(n)
    local t = {}
    for i = 1, n do
        local k = math.random(1, #LETTERS)
        t[i] = LETTERS:sub(k, k)
    end
    return table.concat(t)
end

local function MyGuild() return (GetGuildInfo and GetGuildInfo("player")) or "?" end

local function InfoLines(extraGuilds)
    local lines = { "GU:t:" .. w.title, "GU:p:" .. w.tag, "GU:g:" .. MyGuild() .. ":" .. w.tag }
    for _, g in ipairs(extraGuilds or {}) do lines[#lines + 1] = "GU:g:" .. g.name .. ":" .. g.tag end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Canal libre: entro de prueba y cuento. Solo yo (o ninguno aún) = libre
---------------------------------------------------------------------------
local function ChannelCount(name)
    local id = GetChannelName and GetChannelName(name)
    if not id or id == 0 then return nil end
    return (GetNumChannelMembers and GetNumChannelMembers(id)) or 0
end
local function CheckAlone(name, pass, done)
    if w.test then return HU.After(1, function() done(true) end) end
    if JoinTemporaryChannel then pcall(JoinTemporaryChannel, name, pass) end
    HU.After(2.5, function()
        if HU.HideChannel then HU:HideChannel(name) end
        local n = ChannelCount(name)
        done(n ~= nil and n <= 1)
    end)
end
local function LeaveTest(name)
    if w and not w.test and name and LeaveChannelByName and (GetChannelName(name) or 0) > 0 then pcall(LeaveChannelByName, name) end
end

---------------------------------------------------------------------------
-- La ventana
---------------------------------------------------------------------------
local function Build()
    w = CreateFrame("Frame", "GuildUnionWizard", UIParent, "BackdropTemplate")
    w:SetSize(520, 400)
    w:SetPoint("CENTER")
    w:SetFrameStrata("FULLSCREEN_DIALOG") -- (por encima de la ventana de GuildUnion)
    w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    w:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
    tinsert(UISpecialFrames, "GuildUnionWizard")
    local close = HU.CloseButton(w)
    close:SetPoint("TOPRIGHT", -2, -2)

    w.head = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    w.head:SetPoint("TOPLEFT", 16, -14)
    w.stepText = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    w.stepText:SetPoint("TOPRIGHT", -36, -18)
    w.text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.text:SetPoint("TOPLEFT", w.head, "BOTTOMLEFT", 0, -12)
    w.text:SetWidth(488); w.text:SetJustifyH("LEFT"); w.text:SetSpacing(2)

    local function Input(label, width, maxLetters)
        local fs = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetText(label)
        local e = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
        e:SetSize(width, 20); e:SetAutoFocus(false)
        if maxLetters then e:SetMaxLetters(maxLetters) end
        e:SetScript("OnEscapePressed", e.ClearFocus)
        e:SetScript("OnEnterPressed", function() if w.next:IsShown() and w.next:IsEnabled() then w.next:Click() end end)
        e.label = fs
        return e
    end
    w.in1 = Input("", 260, 40)
    w.in2 = Input("", 70, 6)
    w.in1.label:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -14)
    w.in1:SetPoint("TOPLEFT", w.in1.label, "BOTTOMLEFT", 6, -4)
    w.in2.label:SetPoint("LEFT", w.in1.label, "LEFT", 290, 0)
    w.in2:SetPoint("TOPLEFT", w.in2.label, "BOTTOMLEFT", 6, -4)

    -- cuadro para copiar (Ctrl+A, Ctrl+C); no se puede editar
    local bg = CreateFrame("Frame", nil, w, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", w.text, "BOTTOMLEFT", 0, -12)
    bg:SetSize(488, 120)
    bg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    bg:SetBackdropColor(0, 0, 0, 0.6)
    local sf = CreateFrame("ScrollFrame", "GuildUnionWizardScroll", bg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -28, 8)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject(ChatFontNormal); eb:SetWidth(440)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnTextChanged", function(s, user) if user then s:SetText(w.copyText or ""); s:HighlightText() end end)
    eb:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)
    sf:SetScrollChild(eb)
    w.copyBg, w.copy = bg, eb
    w.copyHint = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    w.copyHint:SetPoint("TOPLEFT", bg, "BOTTOMLEFT", 2, -4)
    w.copyHint:SetText(L("Pulsa en el cuadro, Ctrl+A y Ctrl+C para copiar"))

    w.status = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.status:SetPoint("BOTTOMLEFT", 18, 48)
    w.status:SetWidth(484); w.status:SetJustifyH("LEFT")

    local function Btn(text, width)
        local b = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        b:SetSize(width, 24); b:SetText(text)
        return b
    end
    w.next = Btn(L("Siguiente"), 150)
    w.next:SetPoint("BOTTOMRIGHT", -16, 14)
    w.back = Btn(L("Atrás"), 90)
    w.back:SetPoint("RIGHT", w.next, "LEFT", -8, 0)
    w.extra = Btn("", 170)
    w.extra:SetPoint("BOTTOMLEFT", 16, 14)
    w:SetScript("OnHide", function()
        w.copyText = nil; w.copy:SetText("")                 -- (la contraseña no se queda a la vista)
        HU.onGuildJoined, HU.onGuildRefused = nil, nil
        -- (si se cierra antes de terminar, se sale del canal de prueba)
        if not w.created then LeaveTest(w.chan) end
    end)
    w:Hide()
end

local function ShowCopy(text)
    w.copyText = text
    w.copy:SetText(text)
    w.copyBg:Show(); w.copyHint:Show()
end

local Show -- (cada paso llama al siguiente)
local function Reset(step, total)
    w.step = step
    w.head:SetText(w.test and (L("Crear comunidad") .. "  |cffff9933" .. L("(PRUEBA)") .. "|r") or L("Crear comunidad"))
    w.stepText:SetText(string.format(L("Paso %s de 8"), total or step))
    w.text:SetText("")
    w.status:SetText("")
    for _, e in ipairs({ w.in1, w.in2 }) do e:Hide(); e.label:Hide() end
    w.copyText = nil; w.copy:SetText(""); w.copyBg:Hide(); w.copyHint:Hide()
    w.next:Show(); w.next:Enable(); w.next:SetText(L("Siguiente")); w.next:SetScript("OnClick", nil)
    w.back:Hide(); w.back:SetScript("OnClick", nil)
    w.extra:Hide(); w.extra:SetScript("OnClick", nil)
end
local function Ask(e, label, value)
    e.label:SetText(label); e.label:Show()
    e:SetText(value or ""); e:Show()
end
local function Err(msg) w.status:SetText("|cffff6060" .. msg .. "|r") end

local STEPS = {}

-- 1. Nombre de la comunidad y etiqueta de tu hermandad
STEPS[1] = function()
    Reset(1)
    w.text:SetText(L("Vas a crear una comunidad nueva con tu hermandad como |cffffd100principal|r: su maestro (tú) y los gestores que nombres son los que invitan a las demás.\n\nEscribe el nombre de la comunidad y una etiqueta corta para tu hermandad."))
    Ask(w.in1, L("Nombre de la comunidad"), w.title)
    Ask(w.in2, L("Etiqueta (máx. 6)"), w.tag)
    w.next:SetScript("OnClick", function()
        local title = HU.CleanTitle(w.in1:GetText())
        local tag = HU.Trim(w.in2:GetText()):upper()
        if title == "" then return Err(L("Escribe el nombre de la comunidad.")) end
        if not tag:match("^%w+$") or #tag > 6 then return Err(L("La etiqueta tiene que ser de 1 a 6 letras o números.")) end
        w.title, w.tag = title, tag
        Show(2)
    end)
end

-- 2. Líneas para la Información de hermandad
STEPS[2] = function()
    Reset(2)
    w.text:SetText(L("Copia estas líneas y pégalas en la |cffffd100Información de hermandad|r (J → Información → editar). Puedes dejar lo que ya tengas escrito."))
    ShowCopy(InfoLines())
    w.back:Show(); w.back:SetScript("OnClick", function() Show(1) end)
    w.next:SetScript("OnClick", function() Show(2.1) end)
end

-- 2.1 Buscar un canal libre (solo yo dentro): si no, otro nombre
STEPS[2.1] = function()
    Reset(2.1, 2)
    w.text:SetText(L("Buscando un canal libre para la comunidad (que no haya nadie más dentro)..."))
    w.next:Disable()
    local tries = 0
    local function Try()
        tries = tries + 1
        if w.chan then LeaveTest(w.chan) end
        w.chan, w.pass = RandomWord(8), RandomWord(8)
        CheckAlone(w.chan, w.pass, function(alone)
            if not w:IsShown() or w.step ~= 2.1 then return end
            if alone then return Show(3) end
            if tries < 5 then return Try() end
            Err(L("No encuentro un canal libre. Vuelve a intentarlo en un momento."))
            w.next:Enable(); w.next:SetText(L("Reintentar"))
            w.next:SetScript("OnClick", function() Show(2.1) end)
        end)
    end
    Try()
end

-- 3. Aviso; la contraseña solo aparece al pulsar «Aceptar»
STEPS[3] = function()
    Reset(3)
    w.text:SetText(L("|cffff9933Atención:|r lo siguiente es el |cffffd100canal y su contraseña|r. No lo enseñes en directo, en capturas ni en Discord.\n\nPulsa «Aceptar» cuando nadie esté mirando tu pantalla."))
    w.next:SetText(L("Aceptar"))
    w.back:Show(); w.back:SetScript("OnClick", function() Show(2) end)
    w.next:SetScript("OnClick", function()
        w.text:SetText(L("Pega esta línea en tu |cffffd100nota de oficial|r (J → Miembros → tú → nota de oficial). Solo la ven quienes pueden ver notas de oficial."))
        ShowCopy("GU:c:" .. w.chan .. ":" .. w.pass)
        w.next:SetText(L("Siguiente"))
        w.next:SetScript("OnClick", function() Show(4) end)
    end)
end

-- 4. Comprobar que está todo puesto (y 4.1: solo yo en el canal)
STEPS[4] = function()
    Reset(4)
    w.text:SetText(L("Cuando hayas pegado las dos cosas, pulsa «Comprobar»: el addon lee la Información y tu nota."))
    w.next:SetText(L("Comprobar"))
    w.back:Show(); w.back:SetScript("OnClick", function() Show(3) end)
    w.next:SetScript("OnClick", function()
        w.next:Disable()
        w.status:SetText(L("Comprobando..."))
        if not w.test and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        HU.After(w.test and 1 or 3, function()
            if not w:IsShown() or w.step ~= 4 then return end
            w.next:Enable()
            if not w.test then
                HU:RefreshConfig(true)
                local cfg, n = HU.cfg, HU.db.netChan
                if not (cfg and HU.myTag == w.tag) then return Err(L("No veo las líneas en la Información de hermandad. Revisa que estén bien pegadas, cada una en su línea.")) end
                if cfg.principal ~= w.tag then return Err(L("Falta la línea GU:p en la Información.")) end
                local chanOk = (n and n.channel == w.chan and (n.pass or "") == w.pass) or (cfg.channel == w.chan)
                if not chanOk then return Err(L("No veo la línea del canal en tu nota de oficial. Revisa que esté sola en la nota.")) end
            end
            Show(4.1)
        end)
    end)
end

STEPS[4.1] = function()
    Reset(4.1, 4)
    w.text:SetText(L("Todo puesto. Comprobando que en el canal solo estás tú..."))
    w.next:Disable()
    HU.After(w.test and 1 or 3, function()
        if not w:IsShown() or w.step ~= 4.1 then return end
        local n = w.test and 1 or ChannelCount(w.chan)
        if n and n <= 1 then
            w.created = true
            if HU.AddAudit and not w.test then HU:AddAudit({ tag = HU.myTag, actor = HU:Me(), text = L("creó la comunidad ") .. w.title }, "all") end
            return Show(5)
        end
        Err(string.format(L("En el canal hay %s personas: alguien más lo usa. Cambia de canal para que nadie de fuera lea vuestro chat."), tostring(n or "?")))
        w.next:Enable(); w.next:SetText(L("Cambiar de canal"))
        w.next:SetScript("OnClick", function() Show(2.1) end)
    end)
end

-- 5. Invitar a la otra hermandad (sin cerrar la ventana)
STEPS[5] = function()
    Reset(5)
    w.head:SetText(w.test and (L("Invitar a la comunidad") .. "  |cffff9933" .. L("(PRUEBA)") .. "|r") or L("Invitar a la comunidad"))
    w.text:SetText(L("Invita a la otra hermandad: escribe el nombre de su |cffffd100maestro|r (o de un oficial que pueda editar su Información) y la etiqueta que tendrá. Tiene que estar conectado y con el addon."))
    Ask(w.in1, L("Maestro (u oficial) de la otra hermandad"), w.other)
    Ask(w.in2, L("Su etiqueta"), w.otherTag)
    w.next:SetText(L("Invitar"))
    w.next:SetScript("OnClick", function()
        local who, tag = HU.Trim(w.in1:GetText()), HU.Trim(w.in2:GetText()):upper()
        if who == "" then return Err(L("Escribe el nombre de su maestro (u oficial).")) end
        if not tag:match("^%w+$") or #tag > 6 then return Err(L("La etiqueta tiene que ser de 1 a 6 letras o números.")) end
        if tag == (w.tag or HU.myTag) then return Err(L("Esa etiqueta ya es la de tu hermandad.")) end
        w.other, w.otherTag = who, tag
        if not w.test then
            local ok, why = HU:InviteGuild(who, tag)
            if not ok then return Err(why or "?") end
        end
        Show(6)
    end)
end

-- 6. Esperando a que acepte
STEPS[6] = function()
    Reset(6)
    w.text:SetText(string.format(L("Invitación enviada a |cffffd100%s|r. Esperando a que acepte...\n\nA su maestro le sale un aviso; si acepta, recibe sus líneas para la Información y el canal le llega solo, sin verlo."), w.other))
    w.next:Disable()
    w.back:Show(); w.back:SetText(L("Atrás")); w.back:SetScript("OnClick", function() Show(5) end)
    HU.onGuildJoined = function(name, tag)
        HU.onGuildJoined, HU.onGuildRefused = nil, nil
        w.joinedName, w.joinedTag = name, tag
        if w:IsShown() then Show(7) end
    end
    HU.onGuildRefused = function(who, why)
        HU.onGuildJoined, HU.onGuildRefused = nil, nil
        if w:IsShown() and w.step == 6 then Err(string.format(L("%s no se ha unido: %s"), who or "?", why or "?")) end
    end
    if w.test then HU.After(3, function() if HU.onGuildJoined then HU.onGuildJoined(L("Hermandad de prueba"), w.otherTag) end end) end
end

-- 7. Tu Información actualizada (con la hermandad nueva)
STEPS[7] = function()
    Reset(7)
    w.text:SetText(string.format(L("|cff44ff44¡Listo! %s <%s> se ha unido.|r\n\nTexto actualizado para tu Información de hermandad: sustituye las líneas GU: que tenías por estas."), w.joinedName or "?", w.joinedTag or "?"))
    local extra = {}
    if w.test then
        extra[1] = { name = w.joinedName, tag = w.joinedTag }
        ShowCopy(InfoLines(extra))
    else
        local lines = { "GU:t:" .. HU:Title(), "GU:p:" .. (HU:PrincipalTag() or w.tag or "") }
        for _, g in ipairs((HU.cfg and HU.cfg.guilds) or {}) do lines[#lines + 1] = "GU:g:" .. g.name .. ":" .. g.tag end
        ShowCopy(table.concat(lines, "\n"))
    end
    w.next:SetScript("OnClick", function() Show(8) end)
end

-- 8. Aviso final
STEPS[8] = function()
    Reset(8)
    w.text:SetText(L("|cff44ff44¡Comunidad lista!|r\n\nEl resto de la hermandad no tiene que configurar nada: |cffffd100con instalar el addon ya estarán conectados|r. El canal les llega solo de un compañero que ya lo tenga.")
        .. "\n\n" .. HU:OfficerRanksNote())
    w.next:SetText(L("Cerrar"))
    w.next:SetScript("OnClick", function() w:Hide() end)
    w.extra:Show(); w.extra:SetText(L("Invitar a otra hermandad"))
    w.extra:SetScript("OnClick", function() w.other, w.otherTag = nil, nil; Show(5) end)
end

Show = function(step)
    local fn = STEPS[step]
    if fn then HU:SafeCall("asistente", fn) end
end

-- Abre el asistente: sin comunidad, desde el principio; con comunidad, en «Invitar». test = modo prueba
function HU:OpenWizard(test)
    if not test then
        if not IsInGuild() then return self:Print(L("Tienes que estar en una hermandad.")) end
        if self.myTag then
            if not self:CanInvite() then return self:Print(L("Solo el maestro de la hermandad principal y sus gestores pueden invitar hermandades.")) end
        elseif not self:IsMaster() then
            return self:Print(L("Solo el maestro de la hermandad puede crear una comunidad."))
        end
    end
    if not w then Build() end
    w.test, w.created = test and true or false, false
    w.title, w.tag, w.chan, w.pass, w.other, w.otherTag = nil, nil, nil, nil, nil, nil
    if test then w.title, w.tag = L("Comunidad de prueba"), "PRB1" end
    w:Show()
    if self.myTag and not test then w.tag, w.title, w.created = self.myTag, self:Title(), true; Show(5) else Show(1) end
end
