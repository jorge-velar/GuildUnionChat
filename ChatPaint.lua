-- Guild Union - cómo se ven en el chat del juego las líneas de /g y /o de mi hermandad
-- (copia 160) Un filtro de chat que solo contesta «ocultar» o «no»: el juego lo llama aislado
-- (securecallfunction), así que no mancha nada. Si hay que adornar la línea, la oculta y la escribe el
-- addon en esa misma ventana, como ya hace con las de las otras hermandades. Antes (copias 94 a 159) el
-- addon se metía en la función de escribir de cada ventana, y eso manchaba todas las líneas: tras un
-- campo de batalla, cada línea daba «attempted to iterate a table that cannot be accessed while
-- tainted» hasta el /reload (visto por Jorge el 16/11). [+ARCHITECTURE.md]
local _, HU = ...

-- La línea de mi hermandad, adornada, en esa ventana
local function PaintOwn(frame, event, msg, author, guid)
    local kind = (event == "CHAT_MSG_OFFICER") and "off" or "main"
    local full = HU:FullName(author) or author
    local mentioned = full:lower() ~= (HU:MeKey() or "") and HU:MentionsMe(msg, full, HU.myTag)
    local hmsg = HU:HighlightMentions(msg, full, HU.myTag)
    local head, body = HU:FormatLineParts(kind, HU.myTag, full, hmsg, guid, nil, nil,
        HU.MENTION_MARK[mentioned], HU:MateHasAddon(full))
    local line = head .. body
    -- (la hora delante, si el jugador la tiene puesta en el chat del juego)
    local fmt = ChatFrameUtil and ChatFrameUtil.GetTimestampFormat and ChatFrameUtil.GetTimestampFormat()
    if type(fmt) == "string" and fmt ~= "" then
        local stamp = (TimeUtil and TimeUtil.BetterDate) or date
        local ok, s = pcall(stamp, fmt, time())
        if ok and type(s) == "string" then line = s .. line end
    end
    local r, g, b = HU:KindColor(kind)
    frame:AddMessage(line, r, g, b)
end

local function OwnFilter(frame, event, msg, author, ...)
    -- (con datos secretos o el chat bloqueado: la pinta el juego tal cual, sin adorno)
    if HU.Secret(msg) or HU.Secret(author) or type(msg) ~= "string" or type(author) ~= "string" then return false end
    if HU:IsChatLockedDown() then return false end
    -- (silenciados y líneas de eco de versiones viejas: no se enseñan)
    if event == "CHAT_MSG_GUILD" and HU:GuildLineHidden(msg, author) then return true end
    if not (HU.db and HU.db.ownPaint and HU.myTag) then return false end
    -- (con Prat o Chattynator la línea la monta ese addon: PratBridge.lua pone el adorno con Prat)
    if HU.PratActive() then return false end
    if HU.UsingChattynator() then return false end
    if not (frame and type(frame.AddMessage) == "function") then return false end
    local guid = select(10, ...)
    if HU.Secret(guid) then guid = nil end
    -- (si algo falla al escribirla, no se oculta: la pinta el juego y no se pierde)
    local ok, err = pcall(PaintOwn, frame, event, msg, author, guid)
    if not ok then
        HU:RecordError(err, "pintar línea propia")
        return false
    end
    return true
end

local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if add then
    add("CHAT_MSG_GUILD", OwnFilter)
    add("CHAT_MSG_OFFICER", OwnFilter)
end

HU:Module("ChatPaint", { "Channel", "ChatTabs", "Core", "PratBridge" })
