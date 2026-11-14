-- Guild Union - cómo se ven en el chat del juego las líneas de /g y /o de mi hermandad
-- El juego las recibe y las monta él solo; el addon las adorna al final, cuando el juego llama al
-- AddMessage de la ventana para escribirlas. Sin filtros de chat. [+ARCHITECTURE.md]
local _, HU = ...

-- Devuelve la línea adornada, nil para dejarla como está o false para no escribirla (silenciados)
local function DecorateOwnLine(text, event, args)
    if HU.Secret(text) or type(text) ~= "string" or type(args) ~= "table" then return nil end
    if not (HU.db and HU.db.ownPaint and HU.myTag) then return nil end
    local msg, author = args[1], args[2]
    if HU.Secret(msg) or HU.Secret(author) or type(msg) ~= "string" or type(author) ~= "string" then return nil end
    local full = HU:FullName(author) or author
    if event == "CHAT_MSG_GUILD" and HU:GuildLineHidden(msg, author) then return false end
    -- (el nombre es el primer enlace de jugador de la línea; el mensaje va tras «]|h … : »)
    local p = text:find("|Hplayer:", 1, true)
    if not p then return nil end
    local _, linkEnd = text:find("]|h", p, true)
    local _, headEnd = text:find(": ", linkEnd or p, true)
    if not (linkEnd and headEnd) then return nil end
    local mentioned = full:lower() ~= (HU:MeKey() or "") and HU:MentionsMe(msg, full, HU.myTag)
    local prefix = HU:NamePrefix(HU.myTag, full, HU.MENTION_MARK[mentioned], HU:MateHasAddon(full))
    local body = HU:Emotes(HU:HighlightMentions(text:sub(headEnd + 1), full, HU.myTag))
    -- ([Hermandad] es el enlace de canal que el juego pone delante del nombre)
    local before = text:sub(1, p - 1)
    local c = before:find("|Hchannel:", 1, true)
    local _, ce = before:find("|h.-|h", c or 1)
    if c and ce then
        before = before:sub(1, c - 1) .. HU:GuildColored(before:sub(c, ce), HU.myTag) .. before:sub(ce + 1)
    end
    return before .. prefix .. text:sub(p, headEnd) .. body
end

local wrapped = {}
local function WrapFrame(frame)
    if not frame or wrapped[frame] or type(frame.AddMessage) ~= "function" then return end
    wrapped[frame] = true
    local orig = frame.AddMessage
    frame.AddMessage = function(self, text, r, g, b, id, accessID, typeID, event, eventArgs, ...)
        if event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
            local ok, res = pcall(DecorateOwnLine, text, event, eventArgs)
            if ok then
                if res == false then return end
                if res then text = res end
            end
        end
        return orig(self, text, r, g, b, id, accessID, typeID, event, eventArgs, ...)
    end
end

HU:On("PLAYER_LOGIN", function()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do WrapFrame(_G["ChatFrame" .. i]) end
end)
