-- Guild Union - con Prat: las líneas salen con el formato que el jugador tiene puesto en Prat
-- (copia 121, de prueba). [+ARCHITECTURE.md]
local _, HU = ...

local EVENT = { main = "CHAT_MSG_GUILD", off = "CHAT_MSG_OFFICER" }
local ctx          -- la línea de otra hermandad que se le está pidiendo a Prat: { tag, author, mark }
local registered = false
HU.pratStats = { ok = 0, fallback = 0, err = 0, own = 0 }

-- ¿Está Prat, con lo que hace falta? (Prat.Format es lo que Prat ofrece a otros addons para pedirle
-- una línea ya montada; lo usa WIM)
function HU.UsingPrat()
    local P = _G.Prat
    return type(P) == "table" and type(P.Format) == "function" and type(P.RegisterChatEvent) == "function"
end
function HU.PratActive()
    return registered and HU.db ~= nil and not HU.db.pratOff and HU.UsingPrat()
end

-- Justo antes de que Prat junte las partes de una línea de hermandad u oficiales: se le pone delante
-- del nombre lo mismo que sin Prat (punto o etiqueta, icono de rango) y se pintan emoticonos y menciones.
-- m es la línea por partes: pP es lo que va justo antes del nombre, MESSAGE el texto.
-- (copia 146) Prat parte el nombre por el guion, como «Nombre-Reino», y lo que queda detrás lo trata
-- de reino: lo acorta a tres letras y le da otro color («Little-Wil» en vez de «Little Wilix»). En
-- Forever no hay reinos: esa segunda parte es el apellido. Aquí se le devuelve el nombre entero a la
-- parte del nombre (que ya viene con su color) y se vacía la del reino.
local function WholeName(m, nice)
    local player, server = m.PLAYER, m.SERVER
    if type(nice) ~= "string" or type(player) ~= "string" or type(server) ~= "string" or server == "" then return end
    if HU.Secret(player) or HU.Secret(server) then return end
    local first, last = nice:match("^(%S+) (.+)$")
    if not first then return end
    local _, b = player:find(first, 1, true)
    if not b then return end
    if not player:find(nice, 1, true) then
        m.PLAYER = player:sub(1, b) .. " " .. last .. player:sub(b + 1)
    end
    m.SERVER, m.sS, m.Ss = "", "", ""
    HU.pratStats.whole = (HU.pratStats.whole or 0) + 1
end

-- (copia 161) Prat pinta el nombre con el color de la clase solo si la sabe él (su lista de la
-- hermandad o el identificador del jugador); si no, lo deja en su color común, gris, y así salían
-- todos. GuildUnion sabe más (listas de las hermandades y lo que recuerda): se le pone ese color,
-- solo si el jugador tiene Prat en «color por clase».
local function ClassName(m, author, guid)
    local P = _G.Prat
    local pn = type(P.GetModule) == "function" and P:GetModule("PlayerNames", true)
    local prof = type(pn) == "table" and type(pn.db) == "table" and pn.db.profile
    if type(prof) ~= "table" or prof.colormode ~= "CLASS" then return end
    local player = m.PLAYER
    if type(player) ~= "string" or player == "" or HU.Secret(player) then return end
    if HU.Secret(guid) then guid = nil end
    local class = HU:ClassFor(author, guid)
    if type(class) ~= "string" or HU.Secret(class) then return end
    local plain = (player:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    -- (el mismo color que sin Prat)
    local r, g, b = HU.ClassRGB(class)
    if not r then return end
    m.PLAYER = string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)) .. plain .. "|r"
    HU.pratStats.class = (HU.pratStats.class or 0) + 1
end

local function Pre(m, event)
    if type(m) ~= "table" or (event ~= "CHAT_MSG_GUILD" and event ~= "CHAT_MSG_OFFICER") then return end
    if not HU.PratActive() or not HU.myTag then return end
    local text = m.MESSAGE
    if type(text) ~= "string" or HU.Secret(text) then return end
    if ctx then
        -- (una línea de otra hermandad que he pedido yo: HU:PratLine)
        WholeName(m, HU:Nice(ctx.author))
        ClassName(m, ctx.author, ctx.guid)
        m.pP = HU:NamePrefix(ctx.tag, ctx.author, ctx.mark) .. (m.pP or "")
        m.MESSAGE = HU:Emotes(text)
        return
    end
    -- (una línea de MI hermandad, que ha entrado por el juego)
    local args = m.ARGS
    local raw, author = type(args) == "table" and args[1], type(args) == "table" and args[2]
    if type(raw) ~= "string" or type(author) ~= "string" or HU.Secret(raw) or HU.Secret(author) then return end
    WholeName(m, HU:Nice(HU:FullName(author) or author))
    ClassName(m, HU:FullName(author) or author, args[12])
    if not HU.db.ownPaint then return end
    if event == "CHAT_MSG_GUILD" and HU:GuildLineHidden(raw, author) then
        m.DONOTPROCESS = true -- (silenciados y eco de versiones viejas: Prat no la escribe)
        return
    end
    local full = HU:FullName(author) or author
    local mentioned = full:lower() ~= (HU:MeKey() or "") and HU:MentionsMe(raw, full, HU.myTag)
    m.pP = HU:NamePrefix(HU.myTag, full, HU.MENTION_MARK[mentioned], HU:MateHasAddon(full)) .. (m.pP or "")
    m.MESSAGE = HU:Emotes(HU:HighlightMentions(text, full, HU.myTag))
    HU.pratStats.own = HU.pratStats.own + 1
end
local function OnPre(_, m, _, event)
    -- (un fallo aquí no puede dejar a Prat sin escribir la línea)
    local ok, err = pcall(Pre, m, event)
    if not ok then
        HU.pratStats.err = HU.pratStats.err + 1
        HU.pratStats.last = tostring(err)
    end
end

-- (copia 122) Prat saca el nivel y la clase de la lista de MI hermandad; de los de otra no sabe nada
-- y la línea salía sin nivel. Si yo lo sé (solo de los que vienen en la lista corta de su hermandad:
-- oficiales, enlace y ayudantes), se lo digo a su módulo de nombres antes de pedirle la línea.
-- «GUILDUNION» como origen: Prat no lo guarda entre sesiones.
local function TellPrat(tag, author, shown)
    local R = HU.remoteRoster and HU.remoteRoster[tag]
    local e = R and R.byKey and R.byKey[HU:Key(author) or ""]
    local lvl, class = e and tonumber(e.level), e and e.class
    if not ((lvl and lvl > 0) or class) then return end
    local P = _G.Prat
    local pn = type(P.GetModule) == "function" and P:GetModule("PlayerNames")
    if pn and type(pn.addName) == "function" then
        pn:addName(shown, nil, type(class) == "string" and class or nil, (lvl and lvl > 0) and lvl or nil, nil, "GUILDUNION")
        HU.pratStats.level = (HU.pratStats.level or 0) + 1
    end
end

-- La línea de otra hermandad tal como la escribiría Prat en la ventana f, o nil para escribirla como
-- siempre (sin Prat, apagado con /gu prat off, canales extra, o si Prat falla o no devuelve nada).
function HU:PratLine(f, kind, tag, author, msg, guid, mark)
    local ev = EVENT[kind]
    if not ev or not HU.PratActive() then return nil end
    ctx = { tag = tag, author = author, mark = mark, guid = guid }
    -- (copia 122: el nombre como lo da el juego en una línea de hermandad, «Nombre Apellido» con
    -- espacio. Con «Nombre-Apellido» Prat tomaba el apellido por un reino y lo pintaba aparte)
    local shown = self:Nice(author)
    pcall(TellPrat, tag, author, shown)
    -- (los argumentos de un CHAT_MSG_GUILD de verdad: texto, autor, idioma, canal, autor, marcas, zona,
    -- número de canal, nombre de canal, idioma, línea, guid...)
    local ok, text = pcall(_G.Prat.Format, f, ev, nil, msg, shown, "", "", shown, "", 0, 0, "", 0, 0, guid, 0, false, false, false, false)
    ctx = nil
    if ok and type(text) == "string" and text ~= "" and not HU.Secret(text) then
        HU.pratStats.ok = HU.pratStats.ok + 1
        return text
    end
    HU.pratStats.fallback = HU.pratStats.fallback + 1
    if not ok then
        HU.pratStats.err = HU.pratStats.err + 1
        HU.pratStats.last = tostring(text)
    end
    return nil
end

HU:On("PLAYER_LOGIN", function()
    if registered or not HU.UsingPrat() then return end
    local ok = pcall(_G.Prat.RegisterChatEvent, HU, "Prat_PreAddMessage", OnPre)
    registered = ok and true or false
end)
