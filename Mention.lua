-- Guild Union - rellenar el nombre de una mención (@) con Tab [+ARCHITECTURE.md]
local _, HU = ...

local MIN_CHARS = 2
local SHOWN = 3
local CHAT_TYPES = { GUILD = true, OFFICER = true }

local hint          -- franja encima de la caja de escribir
local last          -- última mención rellenada: { box, text, head, rest, list, idx }

-- Lo que hay entre el último @ y el cursor, si es el comienzo de una mención
local function Fragment(box)
    local text = box:GetText()
    -- (si empieza por «/» no se toca: el juego revisa esos textos al cambiarlos)
    if type(text) ~= "string" or HU.Secret(text) or text == "" or text:sub(1, 1) == "/" then return end
    if not CHAT_TYPES[box:GetAttribute("chatType") or ""] then return end
    local cur = box:GetCursorPosition()
    local left = text:sub(1, cur)
    local at, frag = left:match("^.*()@([^@]*)$")
    if not at then return end
    if at > 1 and not left:sub(at - 1, at - 1):match("%s") then return end
    if #frag < MIN_CHARS or frag:find("^%s") or frag:find("%s.*%s") or frag:find("|", 1, true) then return end
    return at, frag, text, cur
end

-- Quién empieza así: mi hermandad, lo que se sabe de las otras y quien ha hablado hace poco.
-- Primero los conectados
local function Candidates(frag)
    local want = (HU.Fold(frag):gsub("%-", " "))
    local out, done = {}, {}
    local meKey = HU:MeKey()
    local function try(full, online)
        if type(full) ~= "string" then return end
        local k = full:lower()
        if done[k] or k == meKey then return end
        local nice = HU:Nice(full)
        local folded = HU.Fold(nice)
        if folded ~= want and folded:sub(1, #want) == want then
            done[k] = true
            out[#out + 1] = { nice = nice, online = online and 1 or 0 }
        end
    end
    for _, e in pairs(HU.roster or {}) do try(e.name, e.online) end
    for _, r in pairs(HU.remoteRoster or {}) do
        for _, m in ipairs(r.members or {}) do try(m.name, true) end
    end
    HU.EachRecentSpeaker(function(name) try(name, true) end)
    -- (@everyone, solo para quien puede usarlo; sale el primero)
    if HU.CanPin and HU:CanPin() and want ~= "everyone" and ("everyone"):sub(1, #want) == want then
        out[#out + 1] = { nice = "everyone", online = 2 }
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online > b.online end
        return a.nice < b.nice
    end)
    return out
end

local function HideHint()
    if hint then hint:Hide() end
end

local function ShowHint(box, list, idx)
    if not hint then
        hint = CreateFrame("Frame", nil, UIParent)
        hint:SetFrameStrata("DIALOG")
        hint.bg = hint:CreateTexture(nil, "BACKGROUND")
        hint.bg:SetAllPoints()
        hint.bg:SetColorTexture(0, 0, 0, 0.8)
        hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint.text:SetPoint("LEFT", 6, 0)
    end
    local parts = {}
    for i = 0, math.min(SHOWN, #list) - 1 do
        local c = list[(idx - 1 + i) % #list + 1]
        parts[#parts + 1] = (i == 0) and ("|cff7fd4ff" .. c.nice .. "|r") or ("|cffaaaaaa" .. c.nice .. "|r")
    end
    local more = #list > SHOWN and ("  |cff888888+" .. (#list - SHOWN) .. "|r") or ""
    hint.text:SetText("|cffffd100Tab|r  " .. table.concat(parts, "   ") .. more)
    hint:SetSize(hint.text:GetStringWidth() + 12, 18)
    hint:ClearAllPoints()
    hint:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 8, 0)
    hint:Show()
end

local function OnTextChanged(box)
    if last and (last.box ~= box or last.text ~= box:GetText()) then last = nil end
    local _, frag = Fragment(box)
    if not frag then return HideHint() end
    local list = Candidates(frag)
    if #list == 0 then return HideHint() end
    ShowHint(box, list, 1)
end

local function Fill(box, head, rest, list, idx)
    local nice = list[idx].nice
    local sep = (rest:sub(1, 1) == " ") and "" or " "
    local text = head .. nice .. sep .. rest
    box:SetText(text)
    box:SetCursorPosition(#head + #nice + 1)
    last = { box = box, text = text, head = head, rest = rest, list = list, idx = idx }
    -- (con varios: el siguiente Tab cambia al siguiente nombre)
    if #list > 1 then ShowHint(box, list, idx % #list + 1) else HideHint() end
end

-- Tab: rellena el nombre; otro Tab sin haber tocado nada pasa al siguiente
local function OnTab(box)
    if last and last.box == box and last.text == box:GetText() and #last.list > 1 then
        Fill(box, last.head, last.rest, last.list, last.idx % #last.list + 1)
        return true
    end
    local at, frag, text, cur = Fragment(box)
    if not at then return false end
    local list = Candidates(frag)
    if #list == 0 then return false end
    Fill(box, text:sub(1, at), text:sub(cur + 1), list, 1)
    return true
end

-- (ChatEdit_CustomTabPressed es el enganche que deja el juego para esto; se respeta el de otro addon)
local prevTab = _G.ChatEdit_CustomTabPressed
_G.ChatEdit_CustomTabPressed = function(box, ...)
    local ok, used = pcall(OnTab, box)
    if ok and used then return true end
    if prevTab then return prevTab(box, ...) end
end

HU:OnStart(function()
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local box = _G["ChatFrame" .. i .. "EditBox"]
        if box and box.HookScript then
            box:HookScript("OnTextChanged", function(b) HU:SafeCall("mencion", OnTextChanged, b) end)
            box:HookScript("OnEditFocusLost", HideHint)
            box:HookScript("OnHide", HideHint)
        end
    end
end)
