-- Guild Union - Comercio (la sección Trade de la lista de miembros) [+ARCHITECTURE.md]
-- Los anuncios (pedir o vender) viajan a toda la unión con el conjunto TR (Packs/Trade.lua) y el chat de cada encargo, por
-- susurro (TC). HU:TradeTest (solo por código: las pruebas) la rellena de solicitudes y chats de mentira, que no viajan.
-- Diseño: Obsidian/Addons/GuildUnion - Comercio (diseño).md
local _, HU = ...
local L = HU.L

-- (las recetas de cada profesión, leídas al abrir su ventana, y la casilla «Solo lo que puedo hacer»; los chats con cada
-- persona y lo sin leer, para que /reload no los borre: ver Tidy; las que quité de mi lista, las privadas para mí ya
-- avisadas y las líneas que esperan a que la otra persona se conecte. tradeReqs: las solicitudes de la copia 324, que se
-- proponen una vez, ver Migrate)
HU:Saved({ char = { "tradeRecipes", "tradeOnlyCraft", tradeReqs = {}, tradeChats = {}, tradeUnread = {},
    tradeClosed = {}, tradeSeen = {}, tradePending = {} } })

-- (filas y títulos de 24, con 4 de margen a cada lado del texto: Jorge, 24/11, «muy apelotonado». Caben en la sección
-- con la ventana del juego a su alto de siempre: comercio_spec)
local ROW_H, ROWS = 24, 9
local HDR_H, CELL_PAD = 24, 4
-- (arriba, dos filas: los botones Tablón · Mis encargos · Buscar (DJ.Switch) y, en ROW2_Y, el buscador y la casilla (en
-- Buscar, los filtros); las listas van de BODY_Y a BOTTOM_H por encima del borde de abajo, donde va «+ Nuevo anuncio» (24
-- de alto, a 8 del borde), para que no tape nada) [+ARCHITECTURE.md]
local ROW2_Y, ROW2_H = -36, 28   -- (más pegada a los botones: Jorge, 24/11, «sube un poco más»)
local BODY_Y, BOTTOM_H = -74, 36   -- (la lista, 6 por debajo del buscador: Jorge, 24/11, «un poco menos» de gris)
local SEARCH_W = 200
local SEARCH_ROWS = 3       -- al buscar: filas de cada mitad (publicadas arriba, quién lo hace abajo)
-- (la barra de bajar va a la derecha de su lista, por fuera; cada lista le deja su sitio (scroll) y el borde del panel
-- (edge), para que no se salga: listR en total. Jorge, 25/11: «cuidado con las barras de bajar que se salen un poco». Y la
-- ventana de quién lo hace un objeto de Buscar (who*) y su botón «Ver todos» (allW). En una tabla: el archivo ya tiene
-- casi 200 variables, lo más que deja Lua 5.1) [+ARCHITECTURE.md]
local SIZES = { edge = 10, scroll = 24, listR = 34, whoW = 460, whoH = 402, whoRows = 10, allW = 64 }
local MAX_OPEN = 5          -- anuncios abiertos por persona
local MINE, OTHERS = "|cff4da6ff", "|cffffd100"
local GREY = "|cff9a8f78"
-- (las ventas, de otro color: su texto y un fondo suave en la fila)
local SALE, SALE_RGB = "|cff3fd0c0", { 0.25, 0.82, 0.75 }
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local CHAT_W = 200
local DOT_ON = "|TInterface\\FriendsFrame\\StatusIcon-Online:10:10|t"
local DOT_OFF = "|TInterface\\FriendsFrame\\StatusIcon-Offline:10:10|t"
local testOnline = { ["Pepe-Prueba"] = true, ["Bea-Prueba"] = true, ["Lyra-Prueba"] = false, ["Jandra-Prueba"] = false }
local ACT_W = 84            -- la última columna: el botón (Aceptar / Me interesa / Cancelar) o quién la aceptó
local COIN_ICON = { "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon" }
local GOLD = { 1, 0.82, 0.2 }
-- (lo que dura un anuncio del tablón, a elegir al ponerlo: Jorge, 25/11, «desde 5h-12h-24-48h»)
local EXPIRY_HOURS, EXPIRY_DEFAULT = { 5, 12, 24, 48 }, 24
local ITEM_WAIT = 5         -- lo que se espera a que el juego conozca un objeto para decidir si es BOE
local BIND_EQUIP = (Enum and Enum.ItemBind and Enum.ItemBind.OnEquip) or 2
-- (los filtros de Buscar: la rareza (la calidad del juego, con los nombres de Blizzard; sin legendario, que no se
-- fabrica: Jorge, 25/11, «quita el orange») y tipos (las clases del juego, Enum.ItemClass); varios a la vez)
local QUALITIES = { { 1, "Común", "ffffff" }, { 2, "Poco común", "1eff00" }, { 3, "Raro", "0070dd" }, { 4, "Épico", "a335ee" } }
local TYPES = { { "cons", "Consumible", { 0 } }, { "trade", "Mercancías", { 7 } }, { "cont", "Contenedores", { 1, 11 } },
    { "armor", "Armadura", { 4 } }, { "weapon", "Armas", { 2 } }, { "ammo", "Munición", { 6 } },
    { "misc", "Misceláneo", { 15 } } }

-- Botones con el estilo del Dungeon Journal (DJStyle.lua): rojos, y negros los elegidos
local DJ = HU.DJ
local function Flat(parent, text, w, h) return DJ.Button(parent, text, w, h) end

-- Columnas: en el Tablón, con materiales; en Mis encargos (más estrecha, con el chat al lado), sin ellos; en Buscar, los
-- objetos que encajan con quién lo hace
local COLS = {
    pub = { { "who", "Quién", 100 }, { "item", "Receta / objeto", 170 }, { "qty", "Cant.", 40 }, { "mats", "Mats", 44 }, { "tip", "Propina", 66 }, { "state", "Estado", 0 },
        { "act", "Acción", ACT_W + 6 } },
    priv = { { "who", "Con quién", 86 }, { "item", "Receta / objeto", 120 }, { "qty", "Cant.", 36 }, { "tip", "Propina", 56 }, { "state", "Estado", 0 } },
    search = { { "who", "Quién", 110 }, { "guild", "Hermandad", 80 }, { "prof", "Profesión", 130 }, { "lvl", "Nivel", 0 } },
    find = { { "item", "Objeto", 0 }, { "lvl", "Nivel", 44 }, { "prof", "Profesión", 120 }, { "who", "Quién lo hace", 230 } },
}

-- (lo que se ve: las de prueba y las de la red, juntas; se rehace con Merge)
local reqs = {}             -- { id, who, item, sale, mats, tip, state = "open"|"taken"|"done"|"sold"|"gone", taker, buyers, pub, to, exp, t, test }
local testReqs = {}         -- las de prueba (HU:TradeTest): solo en este PC
local netReqs = {}          -- las de la red (HU:TradeRequests, Packs/Trade.lua): se rehacen con Rebuild
local netDirty = true       -- han cambiado (aviso «trade») o se abre la sección: se rehacen antes de usarlas
local chats = {}            -- [persona] = { líneas }: uno por persona
local unread = {}           -- [persona] = sus líneas sin leer (llegadas con su chat fuera de la pantalla)
local chatKey
local view = "pub"          -- "pub": el Tablón; "priv": Mis encargos; "find": Buscar
local sortKey, sortDesc     -- nil: lo más nuevo arriba; si no, por esa columna (clic en su título), si la vista la tiene
local PUB_KEEP = 600        -- una aceptada (o vendida) sigue 10 min en el Tablón
local selected              -- la fila elegida (EntryKey)
local picks = {}            -- Mis encargos: las elegidas con Ctrl / Mayús (para eliminar varias)
local lastPick              -- la última elegida (para Mayús)
local ui
local Paint

local function Me() return HU:Me() or "?" end
-- (los nombres de la red se comparan sin mayúsculas: el «para quién» es lo que escribió quien pide)
local function IsMe(name) return type(name) == "string" and name:lower() == Me():lower() end
local function SameName(a, b) return type(a) == "string" and type(b) == "string" and a:lower() == b:lower() end
local function IsMine(r) return IsMe(r.who) end
-- (id: huella del nombre de quien la pide, la hora, un contador de la sesión y algo de azar, en 16 cifras: con la red,
-- distinto en toda la unión aunque dos pidan en el mismo segundo o el azar se repita)
local idSeq = 0
local function NewId()
    idSeq = (idSeq + 1) % 256
    return string.format("%s%06x%02x%04x", HU.Hash(Me()):sub(1, 4), time() % 0x1000000, idSeq, math.random(0, 0xffff))
end
-- (¿me interesa esta venta? lo dije con mi «t»)
local function Interested(r)
    for _, n in ipairs(r.buyers or {}) do if IsMe(n) then return true end end
    return false
end
-- (en una privada, la otra persona: a quién se la pido o quién la hace, o quién me la pide. En una venta mía, cada
-- interesado tiene su fila en Mis encargos: `buyer`)
local function Other(r)
    if r.buyer then return r.buyer end
    if IsMine(r) then return r.taker or r.to end
    return r.who
end
-- (cada fila: su número o, en una venta mía, el número y el interesado)
local function EntryKey(e) return e.buyer and (e.id .. "|" .. e.buyer:lower()) or e.id end
local function IdOf(key) return type(key) == "string" and key:match("^[^|]+") or nil end
local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")) end
-- (cobre -> «2 [oro] 50 [plata]», con los iconos)
local function Coins(c)
    local g, sv, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local out = {}
    for i, v in ipairs({ g, sv, cu }) do
        if v > 0 then out[#out + 1] = v .. "|T" .. COIN_ICON[i] .. ":12:12|t" end
    end
    return #out > 0 and table.concat(out, " ") or ("0|T" .. COIN_ICON[3] .. ":12:12|t")
end
-- (quién está conectado: mi hermandad, las listas de las otras, los que tienen GuildUnion y quien me acaba de escribir por
-- el chat de un encargo; se rehace en cada repintado) [+ARCHITECTURE.md]
local onlineMap = {}
local wroteT = {}           -- [nombre en minúsculas] = cuándo me escribió por el chat de un encargo (estaba conectado)
local function BuildOnline()
    onlineMap = {}
    for k, v in pairs(testOnline) do onlineMap[k:lower()] = v end
    for _, e in ipairs(HU.rosterList or {}) do
        if type(e.name) == "string" then onlineMap[e.name:lower()] = e.online and true or false end
    end
    for _, rr in pairs(HU.remoteRoster or {}) do
        for _, m in ipairs(rr.members or {}) do
            if type(m.name) == "string" and onlineMap[m.name:lower()] == nil then onlineMap[m.name:lower()] = m.online ~= false end
        end
    end
    local now = GetTime()
    for _, pr in pairs(HU.remote or {}) do
        if type(pr.name) == "string" and type(pr.last) == "number" and now - pr.last < 300 then onlineMap[pr.name:lower()] = true end
    end
    for k, t in pairs(wroteT) do if now - t < 300 then onlineMap[k] = true end end
end
-- (true conectado, false desconectado, nil no se sabe: de otra hermandad solo se sabe de unos pocos)
local function Status(name)
    if IsMe(name) then return true end
    local full = type(name) == "string" and (HU:FullName(name) or name) or ""
    return onlineMap[full:lower()]
end
local function Dot(name) return Status(name) and DOT_ON or DOT_OFF end
local function Searching() return ui and HU.Trim(ui.search:GetText() or "") ~= "" end
local function Query()
    local t = Plain(HU.Trim(ui.search:GetText() or ""))
    return (t:gsub("^%[", ""):gsub("%]$", "")):lower()
end
-- (¿me toca a mí? la pedí yo, me la piden a mí, la hago yo o me interesa la venta)
local function Involved(r) return IsMine(r) or IsMe(r.to) or IsMe(r.taker) or (r.sale == true and Interested(r)) end
-- (caducado: un anuncio del tablón pasada su hora; ya no se ve en ninguna parte. Packs/Trade.lua tampoco lo publica)
local function Expired(r, now) return r.exp ~= nil and (now or HU.StampNow()) >= r.exp end

---------------------------------------------------------------------------
-- Sin leer: las líneas de otro que llegan con su chat fuera de la pantalla [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- (¿se ve ahora el chat con esa persona? la sección a la vista, en Mis encargos sin buscar y con su chat puesto)
local function ChatOnScreen(key)
    return ui ~= nil and key ~= nil and key == chatKey and view == "priv" and ui:IsVisible() and not Searching()
        and not HU:UnionCfg().tradeOff
end
-- Cuántas líneas hay sin leer, entre todos los chats (UnionRoster.lua hace brillar la pestaña de Comercio)
function HU:TradeUnread()
    local n = 0
    for _, c in pairs(unread) do n = n + c end
    return n
end
-- (la pestaña Mis encargos, con el número: «Mis encargos (2)»)
local function PaintUnread()
    local b = ui and ui.viewBtns and ui.viewBtns.priv
    if not b then return end
    local n = HU:TradeUnread()
    b:Label(n > 0 and string.format(L("Mis encargos (%d)"), n) or L("Mis encargos"))
end
local function MarkRead(key)
    if not (key and unread[key]) then return end
    unread[key] = nil
    PaintUnread()
    HU:Changed("tradeUnread")
end
-- (detrás del nombre en Mis encargos: cuántas suyas hay sin leer)
local function UnreadMark(key)
    local n = key and unread[key]
    return n and (" |cff40ff40(" .. n .. ")|r") or ""
end

---------------------------------------------------------------------------
-- Chat (derecha, solo en Mis encargos): el de la persona del comercio que eliges. Solo se ve aquí
---------------------------------------------------------------------------
-- (sys: un aviso del addon en su chat, tal cual y sin nombre delante, como el de una privada nueva para mí)
local function ChatLine(key, who, text, sys)
    chats[key] = chats[key] or {}
    local line = sys and text or ((IsMe(who) and MINE or OTHERS) .. HU:Short(who) .. "|r: " .. text)
    local l = chats[key]
    l[#l + 1] = line
    if #l > 200 then table.remove(l, 1) end
    if key == chatKey and ui then ui.msgs:AddMessage(line) end
    -- (de otro y con su chat fuera de la pantalla: sin leer; nunca más de las que guarda el chat)
    if not IsMe(who) and not ChatOnScreen(key) then
        unread[key] = math.min(#l, (unread[key] or 0) + 1)
        PaintUnread()
        HU:Changed("tradeUnread")
    end
end
-- Una línea en el chat con `key` desde fuera (las pruebas); las que llegan por la red entran por la orden TC, abajo
function HU:TradeChatLine(key, who, text) ChatLine(key, who, text) end

local function OpenChat(key)
    chatKey = key
    if not ui then return end
    ui.msgs:Clear()
    if ui.chatInput then
        if key then ui.chatInput:Enable() else ui.chatInput:SetText(""); ui.chatInput:ClearFocus(); ui.chatInput:Disable() end
        ui.chatHint:SetShown(not key)
    end
    ui.chatTitle:SetText(key and (OTHERS .. HU:Short(key) .. "|r " .. Dot(key)) or ("|cff808080" .. L("Elige un comercio para hablar") .. "|r"))
    for _, line in ipairs(key and chats[key] or {}) do ui.msgs:AddMessage(line) end
    if ChatOnScreen(key) then MarkRead(key) end
end

---------------------------------------------------------------------------
-- La red: los anuncios de toda la unión (conjunto TR, Packs/Trade.lua) y el chat de cada encargo (TC) [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local CHAT_MAX = 200                -- letras de una línea del chat que viaja
local HOLD_FOR, HOLD_MAX = 600, 30  -- lo que llega sin una solicitud entre los dos espera esto (aún no la tengo), tantas como mucho
local PENDING_MAX = 50              -- líneas que esperan a que la otra persona se conecte, por persona
local IN_FLIGHT = 30                -- lo mandado hace menos de esto vuelve a esperar si el juego dice que no estaba
local RETRY_UNKNOWN = 300           -- a quien no se sabe si está y no estaba, se le vuelve a probar cada tanto
local held = {}                     -- { from, m, t }: lo que ha llegado sin una solicitud entre los dos (todavía)
local inflight = {}                 -- [nombre en minúsculas] = { name, lines, t }: lo mandado hace poco
local bounced = {}                  -- [nombre en minúsculas] = cuándo dijo el juego que no estaba
local builtTag                      -- mi hermandad cuando se rehicieron (si cambia, se rehacen)

local function Merge()
    reqs = {}
    for _, r in ipairs(testReqs) do reqs[#reqs + 1] = r end
    for _, r in ipairs(netReqs) do reqs[#reqs + 1] = r end
end

-- (el anuncio entre los dos que se ve en Mis encargos, ni cancelado ni quitado de mi lista, y el nombre de su chat: en
-- una venta mía, el interesado que es)
local function Between(name)
    for i = #reqs, 1, -1 do
        local r = reqs[i]
        if not r.test and r.state ~= "gone" and not r.closed and Involved(r) then
            if r.sale and IsMine(r) then
                for _, b in ipairs(r.buyers or {}) do if SameName(b, name) then return r, b end end
            elseif SameName(Other(r), name) then
                return r, Other(r)
            end
        end
    end
end
-- (una línea de otro, al chat del anuncio entre los dos; sin él, false)
local function TakeLine(from, text)
    local r, key = Between(from)
    if not r then return false end
    ChatLine(key, key, text)
    return true
end
local function RecheckHeld()
    local keep, now = {}, GetTime()
    for _, h in ipairs(held) do
        if now - h.t <= HOLD_FOR and not TakeLine(h.from, h.m) then keep[#keep + 1] = h end
    end
    held = keep
end

-- (una privada nueva para mí o alguien a quien le interesa una venta mía: un aviso en el chat con esa persona, que cuenta
-- como sin leer; una vez por solicitud y por interesado)
local function NotifyNew()
    local seen = HU.db.tradeSeen
    for _, r in ipairs(netReqs) do
        if not seen[r.id] and not r.pub and r.state == "open" and IsMe(r.to) and not IsMine(r) then
            seen[r.id] = time()
            ChatLine(r.who, r.who, GREY .. L("Nueva solicitud") .. ":|r " .. r.item .. ((r.qty or 1) > 1 and (" x" .. r.qty) or ""), true)
        end
        if r.sale and r.state == "open" and IsMine(r) then
            for _, b in ipairs(r.buyers or {}) do
                local k = r.id .. ":" .. b:lower()
                if not seen[k] then
                    seen[k] = time()
                    ChatLine(b, b, GREY .. L("Le interesa") .. ":|r " .. r.item, true)
                end
            end
        end
    end
end

-- Las de la red, otra vez (al abrir la sección, con el aviso «trade» y si cambia mi hermandad), con lo quitado de mi lista.
-- Una mía del tablón ya aceptada se vuelve a mandar sin caducidad, para que no se borre a medias [+ARCHITECTURE.md]
local function Rebuild()
    netDirty, builtTag = false, HU.myTag
    netReqs = HU:TradeRequests()
    local closed = HU.db.tradeClosed
    for _, r in ipairs(netReqs) do
        r.closed = closed[r.id] ~= nil or nil
        if r.exp and not r.sale and IsMine(r) and (r.state == "taken" or r.state == "done") then HU:TradeKeep(r) end
    end
    Merge()
    NotifyNew()
    if held[1] then RecheckHeld() end
end
local function Fresh() if netDirty or builtTag ~= HU.myTag then Rebuild() end end
-- (con el aviso «trade»: se juntan los de un momento —un paquete llega en varios trozos— y se pinta si se ve)
local rebuildQueued
local function MarkDirty()
    netDirty = true
    if rebuildQueued then return end
    rebuildQueued = true
    HU.After(1, function()
        rebuildQueued = nil
        if not netDirty then return end
        Rebuild()
        Paint()
    end)
end
-- (lo que falte de la mía —lo que me perdí estando fuera— y de las otras: al abrir, cada 60 s mientras se ve y cuando llega
-- una línea sin su solicitud)
local function NeedAll()
    if not HU.myTag then return end
    HU:PackNeed(HU.myTag, "TR")
    for _, tag in ipairs(HU:OtherTags()) do HU:PackNeed(tag, "TR") end
    -- (y, un momento después, para que salga antes lo de Comercio, las profesiones y recetas de toda la unión, para
    -- «Quién lo hace»)
    HU.After(5, function() HU:NeedUnionProfessions() end)
end

-- Mandar: por susurro, a la otra persona. Si no está conectada, la línea espera (guardada por personaje) y sale cuando se
-- la ve; si no se sabe (de otra hermandad, casi siempre), se prueba, y si el juego dice que no estaba, vuelve a esperar
local function Deliver(key, text)
    HU:MarkPinged(key)
    HU:Send("TC~" .. text, "WHISPER", key)
    local k, now = key:lower(), GetTime()
    local f = inflight[k]
    if not f or now - f.t > IN_FLIGHT then f = { name = key, lines = {} }; inflight[k] = f end
    f.t = now
    f.lines[#f.lines + 1] = text
end
local function Queue(key, text, at)
    local pend = HU.db.tradePending
    local l = pend[key] or {}
    pend[key] = l
    table.insert(l, at or #l + 1, { m = text, t = time() })
    while #l > PENDING_MAX do table.remove(l, 1) end
end
local function TryFlush(key, now)
    local pend = HU.db.tradePending
    local l, st, b = pend[key], Status(key), bounced[key:lower()]
    if not (st == true or (st == nil and (not b or now - b >= RETRY_UNKNOWN))) then return end
    pend[key] = nil
    for _, e in ipairs(l or {}) do Deliver(key, e.m) end
end
local function SendChat(key, text)
    Queue(key, HU.Utf8Cut((text:gsub("%c", " ")), CHAT_MAX))
    BuildOnline()
    TryFlush(key, GetTime())
end
-- (el juego dice que no está: el susurro no salió o «no hay ningún jugador llamado…». Lo que le acabo de mandar vuelve a
-- esperar, delante de lo que ya esperaba)
local forget = HU.ForgetOffline
function HU:ForgetOffline(who)
    forget(self, who)
    local k = self:Short(who):lower()
    local f = inflight[k]
    if not (f and GetTime() - f.t <= IN_FLIGHT) then return end
    inflight[k], bounced[k] = nil, GetTime()
    for i, m in ipairs(f.lines) do Queue(f.name, m, i) end
end

-- TC~texto: una línea del chat de un encargo, de la otra persona. Solo por susurro y si hay una solicitud entre los dos; si
-- aún no la tengo (llega antes que su paquete), espera un rato y se pide lo que falte
HU:RegisterMessage("TC", { fields = { "text*" }, open = true, queue = "chat", ttl = 60,
    handler = function(self, sender, f, dist)
        local from = dist == "WHISPER" and self:FullName(sender)
        local text = HU.SafeText(HU.Utf8Cut((tostring(f.text or ""):gsub("|+", "|")), CHAT_MAX), true)
        if not from or HU.Trim(text) == "" then return end
        wroteT[from:lower()] = GetTime()
        Fresh()
        if not TakeLine(from, text) then
            if #held >= HOLD_MAX then table.remove(held, 1) end
            held[#held + 1] = { from = from, m = text, t = GetTime() }
            NeedAll()
        end
        -- (está conectado: lo que le esperaba sale ya)
        local now = GetTime()
        for key in pairs(HU.db.tradePending) do
            if SameName(key, from) then BuildOnline(); TryFlush(key, now) end
        end
    end })

-- (cada 30 s: lo que espera sale si la otra persona está; lo que llegó sin su solicitud, se vuelve a mirar)
local function Repaso()
    local now = GetTime()
    for k, f in pairs(inflight) do if now - f.t > IN_FLIGHT then inflight[k] = nil end end
    if held[1] then
        Fresh()
        RecheckHeld()
        if held[1] then NeedAll() end
    end
    local pend = HU.db.tradePending
    if not next(pend) then return end
    BuildOnline()
    for key in pairs(pend) do TryFlush(key, now) end
end

---------------------------------------------------------------------------
-- Objetos: lo que el juego sabe de ellos (C_Item; en Forever no hay GetItemInfo suelto) y si son BOE [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local function Pack(...) return { n = select("#", ...), ... } end
local function Num(v) return (type(v) == "number" and not HU.Secret(v)) and v or nil end
-- (de un objeto (número, nombre o enlace): { name, link, q (calidad), il (nivel de objeto), rl (nivel requerido: el que
-- pide para usarlo; 0, ninguno), cls (clase), bind (ligado) }; nil si el juego aún no lo tiene)
local function ItemInfo(item)
    local get = C_Item and C_Item.GetItemInfo
    if type(get) ~= "function" then return nil end
    local res = Pack(pcall(get, item))
    local name, link = res[2], res[3]
    if not (res[1] and type(name) == "string" and type(link) == "string") or HU.Secret(name) or HU.Secret(link) then return nil end
    return { name = name, link = link, q = Num(res[4]), il = Num(res[5]), rl = Num(res[6]), cls = Num(res[13]),
        bind = Num(res[15]) }
end

-- Fabricables (CraftItems.lua): el juego da su nombre y enlace en tu idioma; se piden poco a poco (30 cada
-- medio segundo) desde que se monta la sección (al cargar la ventana de hermandad del juego), y los que tarda se
-- reintentan dos vueltas más. De paso se guardan su calidad, sus niveles y su clase, para Buscar [+ARCHITECTURE.md]
local craft = {}            -- [objeto] (o ["s" .. hechizo]) = { key = nombre en minúsculas, link, skill, lv, q, il, rl, cls, bind }
local craftLoader
local findDirty = true      -- Buscar: la lista de objetos que encajan, por rehacer (cambia un filtro o llegan objetos)
-- (los encantamientos son hechizos, no objetos: el juego da su nombre y su enlace al momento, sin pedirlos)
local function LoadCraftSpells()
    local S = C_Spell
    if type(HU.CRAFT_SPELLS) ~= "table" or not (S and S.GetSpellName and S.GetSpellLink) then return end
    for skill, list in pairs(HU.CRAFT_SPELLS) do
        for i = 1, #list - 1, 2 do
            local id = list[i]
            local okN, name = pcall(S.GetSpellName, id)
            local okL, link = pcall(S.GetSpellLink, id)
            if okN and okL and type(name) == "string" and type(link) == "string" and not HU.Secret(name)
                and not HU.Secret(link) then
                craft["s" .. id] = { key = HU.Fold(name), link = link, skill = skill, lv = list[i + 1] }
                findDirty = true
            end
        end
    end
end
local function LoadCraftNames()
    if craftLoader or type(HU.CRAFT_ITEMS) ~= "table" then return end
    LoadCraftSpells()
    local queue, info = {}, {}
    for skill, list in pairs(HU.CRAFT_ITEMS) do
        for i = 1, #list - 1, 2 do
            if not info[list[i]] then queue[#queue + 1] = list[i] end
            info[list[i]] = { skill = skill, lv = list[i + 1] }
        end
    end
    local pos, pass, missing = 1, 1, {}
    craftLoader = HU:Every(0.5, "Comercio: nombres", function()
        for _ = 1, 30 do
            local id = queue[pos]
            if not id then
                -- (una vuelta entera: con Buscar a la vista, se pinta lo que ha llegado)
                if ui and view == "find" and ui:IsVisible() then Paint() end
                if pass >= 3 or #missing == 0 then craftLoader:Cancel(); return end
                queue, missing, pos, pass = missing, {}, 1, pass + 1
                return
            end
            pos = pos + 1
            local it = ItemInfo(id)
            if it then
                craft[id] = { key = HU.Fold(it.name), link = it.link, skill = info[id].skill, lv = info[id].lv, q = it.q,
                    il = it.il, rl = it.rl, cls = it.cls, bind = it.bind }
                findDirty = true
            else
                missing[#missing + 1] = id
            end
        end
    end, { pauseInCombat = true })
end

-- (el número del objeto que pide un anuncio: su enlace o, lo escrito a mano, el nombre exacto de un fabricable; un
-- hechizo o un encantamiento no es un objeto)
local function ItemIdOf(item)
    if type(item) ~= "string" or HU.Secret(item) then return nil end
    local id = item:match("|Hitem:(%d+)")
    if id then return tonumber(id) end
    if item:find("|H", 1, true) then return nil end
    local name = HU.Fold(Plain(item)):gsub("^%s*%[", ""):gsub("%]%s*$", "")
    for k, c in pairs(craft) do if type(k) == "number" and c.key == name then return k end end
    return nil
end
-- ¿Es BOE (se liga al equipar, de verde a legendario)? true o false, y el número del objeto. nil si el juego aún no lo
-- conoce: se le pide y avisa al llegar (ITEM_DATA_LOAD_RESULT). Lo que no es un objeto, no [+ARCHITECTURE.md]
local function BoeOf(item)
    local id = ItemIdOf(item)
    if not id then return false end
    local it = ItemInfo(id)
    if not it then
        local ask = C_Item and C_Item.RequestLoadItemDataByID
        if type(ask) == "function" then pcall(ask, id) end
        return nil, id
    end
    local q = it.q or 0
    return it.bind == BIND_EQUIP and q >= 2 and q <= 5, id
end

-- (las profesiones y el nivel que hacen falta para algo que encaje con q, por su nombre, y lo que encaja ([clave] = true).
-- Solo cuenta lo que mejor encaja: con «bolsa», lo que lleva esa palabra entera y no «Bolsas» ni «Embolsar», si lo hay.
-- Jorge, 24/11: «más al grano»)
local function CraftNeeds(q)
    local needs, keys, best = {}, {}, nil
    for k, c in pairs(craft) do
        local r = HU.TextRank(c.key, q)
        if r then
            local tier = (r <= 2 and 1) or (r <= 4 and 2) or 3
            if not best or tier < best then best, needs, keys = tier, {}, {} end
            if tier == best then
                keys[k] = true
                if needs[c.skill] == nil or c.lv < needs[c.skill] then needs[c.skill] = c.lv end
            end
        end
    end
    if not best then return nil, nil end
    return needs, keys
end

-- (los de mi hermandad con sus profesiones de la comunidad, { name, tag, prof, icon, id, online, rank } por profesión; se
-- leen una vez por repintado)
local clubRows
local function ClubRows()
    if clubRows then return clubRows end
    clubRows = {}
    local cid = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local ok, ids = false, nil
    if cid and not HU.Secret(cid) then ok, ids = pcall(C_Club.GetClubMembers, cid) end
    for _, id in ipairs((ok and type(ids) == "table") and ids or {}) do
        local ok2, info = pcall(C_Club.GetMemberInfo, cid, id)
        local n = ok2 and info and info.name
        if type(n) == "string" and not HU.Secret(n) then
            local off = Enum and Enum.ClubMemberPresence and info.presence == Enum.ClubMemberPresence.Offline
            local full = HU:FullName(n) or n
            for _, p in ipairs(HU:ClubProfessions(info)) do
                clubRows[#clubRows + 1] = { name = full, tag = HU.myTag, prof = p.name, icon = p.icon, id = p.id,
                    online = not off, rank = p.rank }
            end
        end
    end
    return clubRows
end
local function ClubRow(m) return { name = m.name, tag = m.tag, prof = m.prof, icon = m.icon, online = m.online, rank = m.rank } end
-- (¿tiene ya línea de oficios de esa profesión? Entonces vale lo que dice su línea, también si seguro que no sabe la
-- receta: no sale otra vez con lo que da el juego)
local function HasLine(name, skill)
    for _, p in ipairs(HU:UnionProfessionsOf(name) or {}) do if p.id == skill then return true end end
    return false
end

-- «Quién lo hace»: los de toda la unión con su línea de oficios (Packs/Professions.lua: nivel de verdad y si saben la
-- receta, también desconectados) y los de mi hermandad que no la tienen, con lo que da el juego [+ARCHITECTURE.md]
local function SearchMembers(q)
    q = q:lower()
    local out, have = {}, {}
    local needs, keys = CraftNeeds(q)
    for _, r in ipairs(HU:UnionCrafters(q, keys, needs)) do
        r.online = Status(r.name)
        out[#out + 1] = r
        have[(HU:Key(r.name) or r.name) .. "|" .. r.skill] = true
    end
    for _, m in ipairs(ClubRows()) do
        local need = needs and type(m.id) == "number" and needs[m.id]
        -- (sin nivel —el de los demás, que la comunidad no da—: sale si tiene la profesión)
        if not have[m.name:lower() .. "|" .. tostring(m.id)] and not HasLine(m.name, m.id)
            and (HU.TextRank(m.prof, q) or (need and (m.rank == nil or m.rank >= need))) then
            out[#out + 1] = ClubRow(m)
        end
    end
    -- (primero quien sabe la receta; luego los de nivel sabido, de más a menos; los demás, detrás)
    table.sort(out, function(a, b)
        if (a.knows == true) ~= (b.knows == true) then return a.knows == true end
        local ra, rb = a.rank or -1, b.rank or -1
        if ra ~= rb then return ra > rb end
        return a.name < b.name
    end)
    return out
end

---------------------------------------------------------------------------
-- Buscar (la pestaña): los fabricables que encajan con los filtros (profesión, nivel requerido, rareza y tipo; de
-- varios, cualquiera) y con su buscador (nombre o enlace) y, de cada uno, quién de la unión lo hace, conectados primero.
-- La lista, solo al cambiar un filtro o al llegar objetos; quién lo hace, solo de las filas que se ven y de la ventana
-- de «Ver todos» [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local findProf, findQual, findType = {}, {}, {}   -- [profesión] / [calidad] / [tipo] = true
local findMin, findMax                             -- nivel requerido (el que pide el objeto para usarlo), de… a…
local findList                                     -- lo que encaja: { key, item, rl, il, skill, lv, name }
local findSel                                      -- el elegido (su clave)
local crafters = {}                                -- [clave] = quién lo hace (se vacía en cada repintado)
local function FindItems(idx)
    if findList and not findDirty then return findList end
    findDirty = false
    local classes = {}
    for _, t in ipairs(TYPES) do if findType[t[1]] then for _, c in ipairs(t[3]) do classes[c] = true end end end
    local anyP, anyQ, anyT = next(findProf) ~= nil, next(findQual) ~= nil, next(findType) ~= nil
    -- (un encantamiento no es un objeto: no tiene rareza, tipo ni nivel; con uno de esos filtros, fuera)
    local itemOnly = anyQ or anyT or findMin ~= nil or findMax ~= nil
    -- (su buscador: un enlace (Mayús+clic) es ese fabricable y nada más (`only`, su clave); un texto, los que lo llevan
    -- en el nombre (`q`), como el buscador del Tablón (HU.TextRank))
    local box = ui.filters.search
    local text = box.link or box:GetText() or ""
    local q, only = nil, tonumber(text:match("|Hitem:(%d+)") or "")
    local sp = text:match("|Hspell:(%d+)") or text:match("|Henchant:(%d+)")
    if sp then only = "s" .. sp end
    if not only then
        q = HU.Trim((Plain(text):gsub("^%s*%[", ""):gsub("%]%s*$", "")))
        if q == "" then q = nil end
    end
    local out = {}
    for k, c in pairs(craft) do
        local spell = type(k) ~= "number"
        local skill, lv
        for _, t in ipairs(idx[k] or {}) do
            if (not anyP or findProf[t.skill]) and (lv == nil or t.lv < lv) then skill, lv = t.skill, t.lv end
        end
        local ok = skill ~= nil and not (spell and itemOnly) and (only == nil or k == only)
            and (q == nil or HU.TextRank(c.key, q) ~= nil)
        -- (sin nivel requerido, 0: vale con cualquier «hasta»)
        if ok and not spell then
            ok = (not anyQ or findQual[c.q] == true) and (not anyT or classes[c.cls] == true)
                and (not findMin or (c.rl or -1) >= findMin) and (not findMax or (c.rl or math.huge) <= findMax)
        end
        if ok then
            out[#out + 1] = { key = k, item = c.link, rl = (not spell) and c.rl or nil, il = (not spell) and c.il or nil,
                skill = skill, lv = lv, name = c.key }
        end
    end
    -- (de más nivel requerido a menos; sin él, detrás; luego por nivel de objeto, por el que pide la profesión y por
    -- nombre)
    table.sort(out, function(a, b)
        local ra, rb = a.rl or -1, b.rl or -1
        if ra ~= rb then return ra > rb end
        local ia, ib = a.il or -1, b.il or -1
        if ia ~= ib then return ia > ib end
        if a.lv ~= b.lv then return a.lv > b.lv end
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.key) < tostring(b.key)
    end)
    findList = out
    return out
end

---------------------------------------------------------------------------
-- ¿Puedo hacerlo? Mis profesiones (el juego las da siempre) y mis recetas (solo con la ventana de la profesión abierta:
-- se guardan al abrirla) [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- (el nombre de cada profesión de CraftItems.lua, para decir cuál te falta)
local PROF_NAMES = { [129] = "Primeros auxilios", [164] = "Herrería", [165] = "Peletería", [171] = "Alquimia",
    [185] = "Cocina", [186] = "Minería", [197] = "Sastrería", [202] = "Ingeniería", [333] = "Encantamiento" }

-- (los fabricables por su número: [objeto] o ["s" .. hechizo] = { { id, spell, skill, lv }, ... }, uno por profesión
-- que lo hace y en orden de profesión; se monta la primera vez que hace falta)
local craftIndex
local function CraftIndex()
    if craftIndex then return craftIndex end
    craftIndex = {}
    for _, src in ipairs({ { HU.CRAFT_ITEMS, false }, { HU.CRAFT_SPELLS, true } }) do
        for skill, list in pairs(type(src[1]) == "table" and src[1] or {}) do
            for i = 1, #list - 1, 2 do
                local k = src[2] and ("s" .. list[i]) or list[i]
                craftIndex[k] = craftIndex[k] or {}
                table.insert(craftIndex[k], { id = list[i], spell = src[2], skill = skill, lv = list[i + 1] })
            end
        end
    end
    for _, e in pairs(craftIndex) do table.sort(e, function(a, b) return a.skill < b.skill end) end
    return craftIndex
end

-- Quién lo hace un fabricable (su clave): los de la unión con su línea de oficios que lo saben o tienen el nivel, y los de
-- mi hermandad sin línea que tienen la profesión; conectados primero, luego quien sabe la receta y por nivel
local function CraftersOf(key)
    if crafters[key] then return crafters[key] end
    local needs = {}
    for _, t in ipairs(CraftIndex()[key] or {}) do
        if needs[t.skill] == nil or t.lv < needs[t.skill] then needs[t.skill] = t.lv end
    end
    local out = {}
    for _, r in ipairs(HU:UnionCrafters(nil, { [key] = true }, needs)) do
        r.online = Status(r.name)
        out[#out + 1] = r
    end
    for _, m in ipairs(ClubRows()) do
        local need = type(m.id) == "number" and needs[m.id]
        if need and (m.rank == nil or m.rank >= need) and not HasLine(m.name, m.id) then out[#out + 1] = ClubRow(m) end
    end
    table.sort(out, function(a, b)
        if (a.online == true) ~= (b.online == true) then return a.online == true end
        if (a.knows == true) ~= (b.knows == true) then return a.knows == true end
        local ra, rb = a.rank or -1, b.rank or -1
        if ra ~= rb then return ra > rb end
        return a.name < b.name
    end)
    crafters[key] = out
    return out
end
-- (en la fila de un objeto: el primero que lo hace, con su circulito, su nivel y el tic, y cuántos más)
local function WhoSummary(list)
    local c = list[1]
    if not c then return "|cff808080" .. L("Nadie") .. "|r" end
    local s = (IsMe(c.name) and MINE or OTHERS) .. HU:Short(c.name) .. "|r " .. (c.online and DOT_ON or DOT_OFF) .. " "
        .. (c.rank and tostring(c.rank) or "—") .. (c.knows and (" |T" .. TICK .. ":12:12|t") or "")
    if #list > 1 then s = s .. " " .. GREY .. "+" .. (#list - 1) .. "|r" end
    return s
end
-- (el icono de una profesión, el del juego, si lo da: se recuerda)
local profIcons = {}
local function ProfLabel(skill)
    if profIcons[skill] == nil then
        local f = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture
        local ok, tex = false, nil
        if type(f) == "function" then ok, tex = pcall(f, skill) end
        profIcons[skill] = (ok and tex and not HU.Secret(tex)) and tex or false
    end
    local icon = profIcons[skill]
    return (icon and ("|T" .. icon .. ":14:14|t ") or "") .. L(PROF_NAMES[skill] or "?")
end
-- (el enlace del objeto elegido en Buscar, para pedirlo)
local function FindLink() return findSel and craft[findSel] and craft[findSel].link or nil end

-- (lo que pide una solicitud, entre los fabricables: su lista de CraftIndex, o nil si no se reconoce. Un enlace de
-- objeto o de encantamiento, por su número; lo escrito a mano, por el nombre exacto que da el juego)
local function CraftTargets(item)
    if type(item) ~= "string" or HU.Secret(item) then return nil end
    local idx = CraftIndex()
    local id = item:match("|Hitem:(%d+)")
    if id then return idx[tonumber(id)] end
    id = item:match("|Hspell:(%d+)") or item:match("|Henchant:(%d+)")
    if id then return idx["s" .. id] end
    local name = HU.Fold(Plain(item)):gsub("^%s*%[", ""):gsub("%]%s*$", "")
    for k, c in pairs(craft) do if c.key == name then return idx[k] end end
    return nil
end

-- (mis profesiones: [número] = nivel; false si el juego no las da: entonces no se puede comprobar)
local function MyProfessions()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return false end
    local res = Pack(pcall(GetProfessions))
    if not res[1] then return false end
    local out, byName = {}, {}
    for i = 2, res.n do
        if type(res[i]) == "number" then
            -- (nombre, icono, nivel, máximo, hechizos, desplazamiento, número de profesión…)
            local ok, name, _, rank, _, _, _, skill = pcall(GetProfessionInfo, res[i])
            if ok and type(skill) == "number" and not HU.Secret(skill) then
                out[skill] = (type(rank) == "number" and not HU.Secret(rank)) and rank or 0
                if type(name) == "string" and not HU.Secret(name) then byName[name:lower()] = out[skill] end
            end
        end
    end
    return out, byName
end

-- Las profesiones de alguien de mi hermandad, de su ficha en la comunidad (C_Club.GetMemberInfo): { id, name, icon,
-- guid, rank }. En Forever la comunidad da siempre nivel 1 (Jorge, 24/11: su Herboristería 195 y su Minería 111 salían a
-- 1): el mío sale de mi personaje, como en Comercio; el de los demás no se sabe y queda sin nivel (nil). Lo usan la
-- columna de profesiones y la ficha (UnionRoster.lua) y «Quién lo hace» [+ARCHITECTURE.md]
function HU:ClubProfessions(info)
    local out = {}
    if type(info) ~= "table" then return out end
    local mine, mineByName
    if info.isSelf == true then mine, mineByName = MyProfessions() end
    for _, k in ipairs({ "1", "2" }) do
        local pid, pn, pr = info["profession" .. k .. "ID"], info["profession" .. k .. "Name"], info["profession" .. k .. "Rank"]
        if type(pn) == "string" and pn ~= "" and not HU.Secret(pn) then
            local icon
            if type(pid) == "number" and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture then
                local okI, tex = pcall(C_TradeSkillUI.GetTradeSkillTexture, pid)
                if okI and tex and not HU.Secret(tex) then icon = tex end
            end
            local rank = (type(pr) == "number" and not HU.Secret(pr) and pr > 1) and pr or nil
            if mine then rank = (type(pid) == "number" and mine[pid]) or mineByName[pn:lower()] or rank end
            out[#out + 1] = { id = pid, name = pn, icon = icon, guid = info.guid, rank = rank }
        end
    end
    return out
end

-- Si puedo hacer lo que pide `item` (un enlace o lo escrito): ok y, si no, el porqué. Lo que no se reconoce, o sin poder
-- leer mis profesiones, sí: no se puede comprobar. `profs`: las de MyProfessions [+ARCHITECTURE.md]
local function CraftCheck(item, profs)
    local targets = CraftTargets(item)
    if not (targets and profs) then return true end
    local saved = (HU.db and HU.db.tradeRecipes) or {}
    local why
    for _, t in ipairs(targets) do
        local rank = profs[t.skill]
        if rank then
            local rec = saved[t.skill]
            local known = type(rec) == "table" and rec[t.spell and "spells" or "items"]
            if type(known) == "table" and known[t.id] then return true end
            if rank < t.lv then why = why or string.format(L("Te falta nivel (%d)"), t.lv)
            elseif type(rec) == "table" and rec.full then why = why or L("No tienes la receta")
            else return true end
        end
    end
    return false, why or string.format(L("Te falta %s"), L(PROF_NAMES[targets[1].skill] or "?"))
end
function HU:CanCraft(item) return CraftCheck(item, MyProfessions()) end

-- Recetas: al abrir la ventana de una profesión mía, las aprendidas (su número, que es el del hechizo, y el objeto que
-- crean) se guardan por personaje en `tradeRecipes[profesión]`. Con un filtro puesto en esa ventana la lista no viene
-- entera: se suman a las de antes y no cuenta como leída entera (`full`) [+ARCHITECTURE.md]
local RECIPE_FILTERS = { "GetOnlyShowMakeableRecipes", "GetOnlyShowSkillUpRecipes", "GetOnlyShowFirstCraftRecipes",
    "AreAnyInventorySlotsFiltered", "AnyRecipeCategoriesFiltered" }
-- (una función de C_TradeSkillUI, si el juego la tiene; nil si no o si falla)
local function TS(fn, ...)
    local f = C_TradeSkillUI and C_TradeSkillUI[fn]
    if type(f) ~= "function" then return nil end
    local ok, v = pcall(f, ...)
    if ok and not HU.Secret(v) then return v end
    return nil
end
local function Unfiltered()
    for _, fn in ipairs(RECIPE_FILTERS) do if TS(fn) then return false end end
    local text = TS("GetRecipeItemNameFilter")
    return TS("GetShowLearned") ~= false and not (type(text) == "string" and text ~= "")
end
local readQueued
local function ReadRecipes()
    readQueued = nil
    local db = HU.db
    if not db or TS("IsTradeSkillReady") == false or TS("IsDataSourceChanging") then return end
    -- (la de otro (enlazada o de la hermandad) o la de un PNJ no es la mía)
    if TS("IsTradeSkillLinked") or TS("IsTradeSkillGuild") or TS("IsTradeSkillGuildMember") or TS("IsNPCCrafting") then return end
    local info = TS("GetChildProfessionInfo")
    if type(info) ~= "table" or not info.professionID or info.professionID == 0 then info = TS("GetBaseProfessionInfo") end
    local skill = type(info) == "table" and (info.parentProfessionID or info.professionID)
    if type(skill) ~= "number" or skill == 0 then return end
    local ids, full = TS("GetAllRecipeIDs"), true
    if type(ids) ~= "table" then ids, full = TS("GetFilteredRecipeIDs"), Unfiltered() end
    if type(ids) ~= "table" then return end
    local items, spells = {}, {}
    for _, id in ipairs(ids) do
        local r = TS("GetRecipeInfo", id)
        if type(r) == "table" and r.learned == true then
            spells[id] = true
            local s = TS("GetRecipeSchematic", id, false)
            if type(s) == "table" and type(s.outputItemID) == "number" then items[s.outputItemID] = true end
        end
    end
    -- (ninguna aprendida: la ventana aún no las ha dado; no se pisa lo guardado)
    if next(spells) == nil then return end
    db.tradeRecipes = db.tradeRecipes or {}
    local old = db.tradeRecipes[skill]
    if not full and type(old) == "table" then
        for k in pairs(old.items or {}) do items[k] = true end
        for k in pairs(old.spells or {}) do spells[k] = true end
        full = old.full
    end
    db.tradeRecipes[skill] = { t = time(), full = full or nil, items = items, spells = spells }
    if ui and ui:IsShown() then Paint() end
end
-- (la ventana avisa varias veces seguidas al abrirse y con cada cambio: se lee una vez, un momento después)
local function QueueRead()
    if readQueued then return end
    readQueued = true
    HU.After(0.3, ReadRecipes)
end
HU:On("TRADE_SKILL_SHOW", QueueRead)
HU:On("TRADE_SKILL_LIST_UPDATE", QueueRead)

---------------------------------------------------------------------------
-- Solicitudes
---------------------------------------------------------------------------
local function StateText(r)
    if r.sale then
        if r.state == "sold" then return GREY .. L("Vendida") .. "|r" end
        return SALE .. L("Venta") .. "|r"
    end
    if r.state == "done" then return GREY .. L("Hecha") .. "|r" end
    if r.state == "taken" then return "|cff40ff40" .. L("Aceptada") .. "|r" end
    return L("Abierta")
end
-- (en el Tablón, cuánto le queda a uno abierto: «5h» o, la última hora, «<1h»; en minutos no cabía sin apretar)
local function TimeLeft(r, now)
    if not r.exp or r.state ~= "open" then return "" end
    local s = r.exp - now
    return " " .. GREY .. (s >= 3600 and (math.floor(s / 3600 + 0.5) .. "h") or "<1h") .. "|r"
end

local function Matches(r, q)
    for _, v in ipairs({ HU:Short(r.who or ""), Plain(r.item), r.taker and HU:Short(r.taker) or "" }) do
        if HU.TextRank(v, q) then return true end
    end
    return false
end

-- (¿está puesta «Solo lo que puedo hacer»? vale en las dos vistas y al buscar)
local function OnlyCraft() return HU.db ~= nil and HU.db.tradeOnlyCraft == true end

-- (¿sale en el Tablón? los abiertos y, 10 min más, los aceptados, con quién lo aceptó, y los vendidos; con la hora del
-- servidor, la de la red)
local function OnBoard(r, now)
    if r.pub ~= true then return false end
    if r.state == "open" then return true end
    if r.state == "taken" then return now - (r.takenAt or 0) < PUB_KEEP end
    return r.state == "sold" and now - (r.soldAt or 0) < PUB_KEEP
end

-- (profs: las de MyProfessions, si ya están leídas)
local function Visible(profs)
    local out = {}
    local q = Searching() and Query()
    local priv = view == "priv" and not q
    local only = OnlyCraft()
    local now = HU.StampNow()
    if only and profs == nil then profs = MyProfessions() end
    for i = #reqs, 1, -1 do
        local r = reqs[i]
        local ok
        if r.state == "gone" or Expired(r, now) then
            ok = false
        elseif not priv then
            -- (Tablón y, al buscar, lo publicado que encaja)
            ok = OnBoard(r, now) and (not q or Matches(r, q))
        else
            -- (Mis encargos: las que me tocan: las mías, las que me piden a mí, las que hago yo y las ventas que me
            -- interesan. Una pública sin aceptar no tiene a nadie al otro lado: solo sale en el Tablón; una venta mía,
            -- una fila con cada interesado)
            ok = Involved(r) and not r.closed
            if ok and r.sale and IsMine(r) then
                for _, b in ipairs(r.buyers or {}) do out[#out + 1] = setmetatable({ buyer = b }, { __index = r }) end
                ok = false
            elseif ok and not r.sale then
                ok = not (r.pub and r.state == "open")
            end
        end
        -- (con la casilla: en el Tablón y al buscar, solo lo que se reconoce y puedo hacer (una venta no se hace); en Mis
        -- encargos, fuera lo que haría yo y no puedo hacer, y lo que pedí yo o quiero comprar, siempre: Jorge, 24/11)
        if ok and only then
            if priv then ok = IsMine(r) or r.sale or (CraftCheck(r.item, profs))
            else ok = not r.sale and CraftTargets(r.item) ~= nil and (CraftCheck(r.item, profs)) end
        end
        if ok then out[#out + 1] = r end
    end
    if sortKey then
        local STATE = { open = 1, taken = 2, done = 3, sold = 4 }
        local function V(r)
            -- (Quién: lo que enseña la columna; en Mis encargos, la otra persona)
            if sortKey == "who" then return (priv and Other(r) or r.who or ""):lower() end
            if sortKey == "item" then return Plain(r.item):lower() end
            if sortKey == "mats" then return r.mats and 1 or 0 end
            if sortKey == "qty" then return r.qty or 1 end
            if sortKey == "tip" then return r.tip or -1 end
            if sortKey == "state" then return STATE[r.state] or 9 end
            if sortKey == "act" then return (r.taker or ""):lower() end
            return r.t or 0
        end
        table.sort(out, function(a, b)
            local va, vb = V(a), V(b)
            if va == vb then return (a.t or 0) > (b.t or 0) end
            if sortDesc then return va > vb end
            return va < vb
        end)
    end
    return out
end

-- (los míos sin terminar, para el tope: abiertos o aceptados; los quitados de mi lista y los caducados ya no cuentan)
local function OpenCount()
    local n, now = 0, HU.StampNow()
    for _, r in ipairs(reqs) do
        if IsMine(r) and not r.closed and (r.state == "open" or r.state == "taken") and not Expired(r, now) then n = n + 1 end
    end
    return n
end

-- (una solicitud por su id; Live: la de ahora, por si la fila se pintó antes de que llegara un cambio)
local function FindReq(id) for _, r in ipairs(reqs) do if r.id == id then return r end end end
local function Live(r) Fresh(); return FindReq(r.id) or r end

-- Las acciones de las de la red pasan por HU:Propose (Packs/Trade.lua) y se ven al repintar; las de prueba cambian aquí
-- Aceptar una de otro: la haces tú (sigue en el Tablón con tu nombre, y aparece en tus encargos con su chat). Solo si
-- puedes hacerla (HU:CanCraft): el botón ya sale apagado. Una venta: «Me interesa», la pueden querer varios
local function Accept(r)
    r = Live(r)
    if IsMine(r) or r.state ~= "open" then return end
    if r.sale then
        if Interested(r) then return end
        if r.test then r.buyers = r.buyers or {}; table.insert(r.buyers, Me())
        elseif not HU:TradeAnswer(r.id, "t") then return end
    else
        if not HU:CanCraft(r.item) then return end
        if r.test then r.state, r.taker, r.takenAt = "taken", Me(), HU.StampNow()
        elseif not HU:TradeAnswer(r.id, "t") then return end
    end
    OpenChat(r.who)
    Paint()
end
-- La X: mía, cancelarla (una venta, eliminarla); de otro (privada, me la piden a mí), rechazarla
local function Cancel(r)
    r = Live(r)
    if r.state == "done" or r.state == "sold" or not (IsMine(r) or IsMe(r.to)) then return end
    if r.test then r.state = "gone"
    elseif IsMine(r) then HU:TradeCancel(r)
    else HU:TradeAnswer(r.id, "r") end
    selected = nil
    Paint()
end

-- (eliminar de Mis encargos: el mío sin aceptar (o la venta mía, sin vender) se cancela; los demás solo se quitan de mi
-- lista, y la que hago yo y no está hecha, además, se suelta: vuelve a estar abierta para quien la pidió. Una venta que
-- me interesaba: ya no)
local function RemoveReq(r)
    r = Live(r)
    if IsMine(r) and r.state == "open" then
        if r.test then r.state = "gone" else HU:TradeCancel(r) end
        return
    end
    r.closed = true
    if r.test then return end
    HU.db.tradeClosed[r.id] = time()
    if (r.state == "taken" and IsMe(r.taker)) or (r.sale and r.state == "open" and Interested(r)) then HU:TradeAnswer(r.id, "") end
end
-- (eliminar las marcadas, una vez cada una: en una venta mía, varias filas son la misma)
local function RemovePicked()
    local done = {}
    for key in pairs(picks) do
        local id = IdOf(key)
        local x = not done[id] and FindReq(id)
        if x then done[id] = true; RemoveReq(x) end
    end
    picks, selected = {}, nil
    Paint()
end
-- «Hecha»: solo quien la hace (quien la aceptó) y mientras está aceptada
local function CanMarkDone(r) return r ~= nil and r.state == "taken" and IsMe(r.taker) end
local function MarkDone(r)
    r = r and Live(r)
    if not CanMarkDone(r) then return end
    if r.test then r.state = "done" else HU:TradeAnswer(r.id, "d") end
    Paint()
end
-- «Vendida»: solo quien vende y mientras sigue a la venta; deja de estar abierta para todos
local function CanMarkSold(r) return r ~= nil and r.sale == true and r.state == "open" and IsMine(r) end
local function MarkSold(r)
    r = r and Live(r)
    if not CanMarkSold(r) then return end
    if r.test then r.state, r.soldAt = "sold", HU.StampNow() else HU:TradeSold(r) end
    Paint()
end

-- Clic derecho en una fila: la otra persona (susurrar, invitar al grupo); en Mis encargos, marcarla como hecha (si la
-- hago yo y está aceptada) y eliminarla; una venta mía, marcarla vendida; en la búsqueda, pedirle una receta (en Buscar,
-- el objeto elegido); y Cancelar (cierra el menú)
local function RowMenu(owner, r)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local person
    if not r.id then person = r.name
    elseif view == "priv" and not Searching() then person = Other(r)
    elseif IsMine(r) then person = r.taker
    else person = r.who end
    local priv = r.id and view == "priv" and not Searching()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        if person then
            root:CreateTitle(HU:Short(person))
            root:CreateButton(L("Susurrar"), function() HU.WhisperTo(person) end)
            root:CreateButton(L("Invitar al grupo"), function()
                local fn = C_PartyInfo and C_PartyInfo.InviteUnit
                if fn then pcall(fn, HU:FullName(person) or person) end
            end)
            if not r.id then root:CreateButton(L("Pedir una receta"), function() ui.OpenNew(person, view == "find" and FindLink() or nil) end) end
        end
        if priv and CanMarkDone(r) then
            root:CreateButton(L("Marcar como hecha"), function() MarkDone(r) end)
        end
        if r.id and CanMarkSold(r) then
            root:CreateButton(L("Marcar como vendida"), function() MarkSold(r) end)
        end
        if priv then
            local n = 0
            for _ in pairs(picks) do n = n + 1 end
            if n > 0 then
                root:CreateButton(string.format(L("Eliminar (%d)"), n), RemovePicked)
            else
                root:CreateButton(L("Eliminar"), function() RemoveReq(r); selected = nil; Paint() end)
            end
        end
        root:CreateButton(L("Cancelar"), function() end)
    end)
end

-- Coloca columnas, títulos y filas según lo que toca (la flecha de orden, solo en las listas que se ordenan)
local function Columns(lst, cols, width)
    local total = lst.list:GetWidth()
    if type(total) ~= "number" or total <= 0 then total = 560 end
    local used = 0
    for _, col in ipairs(cols) do used = used + col[3] end
    local x = 2
    for i, h in ipairs(lst.hdrCells) do
        local col = cols[i]
        h:SetShown(col ~= nil)
        if col then
            local w = col[3] > 0 and col[3] or math.max(50, total - used - (width or 4) - 4)
            h:ClearAllPoints(); h:SetPoint("BOTTOMLEFT", lst.hdr, "BOTTOMLEFT", x, 0); h:SetWidth(w + 2)
            h.key = col[1]
            -- (la columna por la que se ordena, con una flecha)
            local arrow = (lst.sortable and sortKey == col[1]) and (sortDesc and " v" or " ^") or ""
            h:SetText(col[2] ~= "" and (L(col[2]) .. arrow) or "")
            for _, row in ipairs(lst.rows) do
                local c = row.cells[i]
                c:Show(); c:ClearAllPoints(); c:SetPoint("LEFT", row, "LEFT", x + CELL_PAD, 0); c:SetWidth(w - 2 * CELL_PAD)
            end
            x = x + w
        else
            for _, row in ipairs(lst.rows) do row.cells[i]:Hide() end
        end
    end
end

-- (una lista con o sin su título encima; da lo que mide de alto)
local function Titled(lst, text)
    lst.title:SetText(text or ""); lst.title:SetShown(text ~= nil)
    lst.hdr:ClearAllPoints()
    lst.hdr:SetPoint("TOPLEFT", lst.list, "TOPLEFT", 0, text and -14 or 0); lst.hdr:SetPoint("RIGHT", lst.list, "RIGHT", 0, 0)
    lst.scroll:SetHeight(lst.n * ROW_H)
    lst.list:SetHeight((text and 14 or 0) + HDR_H + 2 + lst.n * ROW_H)
end

-- (las columnas de la lista de solicitudes: las de Mis encargos o, en el Tablón y al buscar, las del Tablón; sin
-- propinas, sin la suya)
local function ReqCols()
    local cols = (view == "priv" and not Searching()) and COLS.priv or COLS.pub
    if not HU:UnionCfg().tipsOff then return cols end
    local out = {}
    for _, col in ipairs(cols) do if col[1] ~= "tip" then out[#out + 1] = col end end
    return out
end

-- (Buscar: los objetos que encajan, en toda la altura; quién lo hace cada uno, en su columna y, con «Ver todos», en su
-- ventana. Hasta el 25/11 iba debajo una lista de quién lo hace el elegido: Jorge, «la quitas»)
local function LayoutFind()
    local items = ui.items
    ui.chat:Hide(); ui.req.list:Hide(); ui.found.list:Hide()
    items.list:ClearAllPoints()
    items.list:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 6, 0); items.list:SetPoint("RIGHT", ui.body, "RIGHT", -SIZES.listR, 0)
    items.n = ROWS
    Titled(items, nil)
    items.list:Show()
    Columns(items, COLS.find, 4)
    -- (el texto de quién lo hace, a la izquierda de «Ver todos», que va al final de su columna)
    local w = COLS.find[#COLS.find][3] - 2 * CELL_PAD - SIZES.allW - 4
    for _, row in ipairs(items.rows) do row.cells[4]:SetWidth(w) end
    ui.new:ClearAllPoints()
    ui.new:SetPoint("BOTTOM", ui, "BOTTOM", 0, 8)
    ui.new:Show()
end

-- En Mis encargos, con el chat a la derecha; en el Tablón, a todo lo ancho. Al buscar: arriba las publicadas que
-- encajan y abajo quién lo hace [+ARCHITECTURE.md]. `list`: las solicitudes que se ven (Visible)
local function Layout(cols, list)
    local searching = Searching()
    local priv = view == "priv" and not searching
    local req, found = ui.req, ui.found
    ui.items.list:Hide()
    -- (en Mis encargos, el chat siempre a la derecha)
    local withChat = priv
    ui.chat:SetShown(withChat)
    req.list:ClearAllPoints()
    req.list:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 6, 0)
    -- (con el chat, su barra de bajar va entre la lista y el chat, sin pisarlo)
    if withChat then req.list:SetPoint("RIGHT", ui.chat, "LEFT", -(6 + SIZES.scroll), 0)
    else req.list:SetPoint("RIGHT", ui.body, "RIGHT", -SIZES.listR, 0) end
    local noPub = searching and #list == 0
    req.list:SetShown(not noPub)
    req.n = searching and SEARCH_ROWS or ROWS
    Titled(req, searching and L("Publicadas") or nil)
    -- (quién lo hace, sola: con su título, cabe una fila menos)
    found.n = noPub and ROWS - 1 or SEARCH_ROWS
    found.list:ClearAllPoints()
    if noPub then found.list:SetPoint("TOPLEFT", ui.body, "TOPLEFT", 6, 0)
    else found.list:SetPoint("TOPLEFT", req.list, "BOTTOMLEFT", 0, -6) end
    found.list:SetPoint("RIGHT", ui.body, "RIGHT", -SIZES.listR, 0)
    Titled(found, L("Quién lo hace"))
    found.list:SetShown(searching)
    Columns(req, cols, priv and 44 or 4)
    if searching then Columns(found, COLS.search, 4) end
    -- («+ Nuevo anuncio», en el centro de la sección; en Mis encargos, en el de la lista, que deja la derecha al chat:
    -- así no choca con él. Jorge, 24/11)
    ui.new:ClearAllPoints()
    ui.new:SetPoint("BOTTOM", ui, "BOTTOM", withChat and -(SIZES.edge + CHAT_W + SIZES.scroll) / 2 or 0, 8)
    ui.new:SetShown(not searching)
end

local function PaintRows(lst, list, fill)
    FauxScrollFrame_Update(lst.scroll, #list, lst.n, ROW_H)
    local off = FauxScrollFrame_GetOffset(lst.scroll)
    for i, row in ipairs(lst.rows) do
        local e = i <= lst.n and list[off + i] or nil
        row.entry = e
        row.accept:Hide(); row.cancel:Hide(); row.actText:Hide()
        row.itemBtn:SetShown(e ~= nil and e.item ~= nil); row.yes:Hide(); row.no:Hide(); row.pickTex:Hide(); row.saleTex:Hide()
        if e then fill(row, e); row:Show() else row:Hide() end
        -- (el clic del enlace, solo encima del texto del enlace, no en toda la casilla)
        if row.itemBtn:IsShown() then
            local fs = row.cells[lst.itemCol or 2]
            local w = fs:GetStringWidth() or 0
            local cw = fs:GetWidth() or w
            row.itemBtn:SetWidth(math.max(8, math.min(w, cw > 0 and cw or w) + 2))
        end
    end
    lst.empty:SetShown(#list == 0)
end

-- (una fila de «Quién lo hace»: con su color de siempre y el circulito; clic derecho: pedir una receta. El tic: sabe la
-- receta)
local function FillWho(row, e)
    local c = row.cells
    c[1]:SetText((e.name == Me() and MINE or OTHERS) .. HU:Short(e.name) .. "|r " .. (e.online and DOT_ON or DOT_OFF))
    c[2]:SetText("|cff" .. HU:GuildColorHex(e.tag) .. tostring(e.tag or "") .. "|r")
    c[3]:SetText((e.icon and ("|T" .. e.icon .. ":14:14|t ") or "") .. e.prof)
    c[4]:SetText((e.rank and tostring(e.rank) or "—") .. (e.knows and (" |T" .. TICK .. ":12:12|t") or ""))
end

-- Buscar: los objetos que encajan (quién lo hace, solo de los que se ven; con alguien, «Ver todos»)
local function PaintFind()
    local items = FindItems(CraftIndex())
    local still = false
    for _, e in ipairs(items) do if e.key == findSel then still = true; break end end
    if not still then findSel = nil end
    LayoutFind()
    ui.items.empty:SetText(next(craft) and L("Ningún objeto fabricable encaja con los filtros.") or L("Cargando los objetos del juego…"))
    PaintRows(ui.items, items, function(row, e)
        local c = row.cells
        local who = CraftersOf(e.key)
        row.pickTex:SetShown(e.key == findSel)
        c[1]:SetText(e.item)
        c[2]:SetText((e.rl and e.rl > 0) and tostring(e.rl) or "—")
        c[3]:SetText(ProfLabel(e.skill))
        c[4]:SetText(WhoSummary(who))
        row.allBtn:SetShown(#who > 0)
    end)
end

function Paint()
    if not (ui and ui:IsShown()) then return end
    -- (comercio apagado por el maestro: solo el panel con el aviso; ni interruptor, ni buscador, ni casilla, ni pedir)
    local off = HU:UnionCfg().tradeOff and true or false
    local find = view == "find"
    ui.offMsg:SetShown(off)
    for _, w in ipairs(ui.onlyOn) do w:SetShown(not off) end
    -- (la fila 2: el buscador y la casilla; en Buscar, los filtros)
    for _, w in ipairs(ui.row2) do w:SetShown(not off and not find) end
    ui.filters:SetShown(not off and find)
    if off then ui.newDlg:Hide(); ui.who:Hide(); return end
    Fresh()
    BuildOnline()
    clubRows, crafters = nil, {}
    ui.who.Paint()
    local searching = Searching()
    -- (el chat que queda en pantalla, leído; antes de pintar las filas, que llevan lo de cada uno)
    if ChatOnScreen(chatKey) then MarkRead(chatKey) end
    PaintUnread()
    for k, b in pairs(ui.viewBtns) do b:SetSelected(k == view and not searching) end
    if find then
        ui.delBtn:Hide(); ui.doneBtn:Hide()
        return PaintFind()
    end
    -- (se ordena por una columna de la vista: si esta no la tiene (Mats y Acción solo están en el Tablón; sin propinas,
    -- tampoco la suya), vuelve a lo más nuevo arriba)
    local cols = ReqCols()
    local sorted = false
    for _, col in ipairs(cols) do if col[1] == sortKey then sorted = true end end
    if not sorted then sortKey, sortDesc = nil, nil end
    local profs = MyProfessions()
    ui.lastList = Visible(profs)
    Layout(cols, ui.lastList)
    -- («Solo lo que puedo hacer»: vale y se ve en las dos vistas y al buscar)
    local only = OnlyCraft()
    ui.onlyCraft:SetChecked(only)
    if searching then
        ui.found.empty:SetText(L("Nadie de la unión lo hace (profesión u objeto fabricable)."))
        PaintRows(ui.found, SearchMembers(Query()), FillWho)
    end
    ui.req.empty:SetText(searching and L("Ninguna solicitud publicada encaja.")
        or (view == "pub" and only and L("En el tablón no hay nada que puedas hacer.")) or L("No hay solicitudes."))
    local nPicks = 0
    for _ in pairs(picks) do nPicks = nPicks + 1 end
    ui.delBtn:SetShown(view == "priv" and not searching and nPicks > 0)
    ui.delBtn:SetText(string.format(L("Eliminar (%d)"), nPicks))
    local cur = selected and FindReq(IdOf(selected))
    -- («Hecha», en las que hago yo; ya hecha, apagado. En una venta mía, «Vendida»)
    local sale = cur ~= nil and cur.sale == true and IsMine(cur)
    ui.doneBtn:SetText(sale and L("Vendida") or L("Hecha"))
    ui.doneBtn:SetShown(view == "priv" and not searching and cur ~= nil and (sale or IsMe(cur.taker)))
    ui.doneBtn:SetEnabled(sale and CanMarkSold(cur) or CanMarkDone(cur))
    local now = HU.StampNow()
    PaintRows(ui.req, ui.lastList, function(row, r)
        local mine = IsMine(r)
        local test = r.test and (" |cff808080(" .. L("prueba") .. ")|r") or ""
        local key = EntryKey(r)
        row.pickTex:SetShown(key == selected or picks[key] == true)
        row.saleTex:SetShown(r.sale == true)
        -- (lo de cada columna, por su clave: sin propinas, la suya no está)
        local v = { item = r.item or "?", qty = tostring(r.qty or 1), state = StateText(r) .. test,
            tip = r.tip and Coins(r.tip) or (GREY .. L("A negociar") .. "|r") }
        if view == "pub" or searching then
            v.state = v.state .. TimeLeft(r, now)
            v.who = mine and (MINE .. L("Yo") .. "|r " .. DOT_ON) or (OTHERS .. HU:Short(r.who) .. "|r " .. Dot(r.who))
            v.mats = (r.mats == nil or r.sale) and "—" or (r.mats and L("Sí") or L("No"))
            -- (la última columna: Aceptar (o Me interesa, en una venta) si es de otro y está abierta; Cancelar si es mía;
            -- si ya la aceptó alguien, su nombre; vendida, «Vendida»; una venta que ya me interesa, «Te interesa»)
            if r.taker then
                row.actText:SetText(IsMe(r.taker) and (MINE .. L("Yo") .. "|r") or (OTHERS .. HU:Short(r.taker) .. "|r " .. Dot(r.taker))); row.actText:Show()
            elseif r.state == "sold" then
                row.actText:SetText(GREY .. L("Vendida") .. "|r"); row.actText:Show()
            elseif mine then
                row.cancel:Show()
            elseif r.sale and Interested(r) then
                row.actText:SetText("|cff40ff40" .. L("Te interesa") .. "|r"); row.actText:Show()
            elseif r.state == "open" then
                -- (apagado si no puedo hacerla: el porqué, al pasar el ratón. Una venta no se hace: siempre encendido)
                local can, why = true, nil
                if not r.sale then can, why = CraftCheck(r.item, profs) end
                row.accept:SetText(r.sale and L("Me interesa") or L("Aceptar"))
                row.accept:SetEnabled(can); row.accept.why = why
                row.accept:Show()
            end
        else
            -- (la otra persona, con cuántas suyas hay sin leer)
            local other = Other(r)
            v.who = (mine and MINE or OTHERS) .. HU:Short(other) .. "|r " .. Dot(other) .. UnreadMark(other)
            -- (solo en las abiertas: el tic para aceptarla —si me la piden a mí y puedo hacerla— y la X para
            -- cancelarla —mía, también una venta— o rechazarla; las aceptadas y las ventas de otros, sin nada)
            local ask = r.state == "open" and not mine and not r.sale
            row.yes:SetShown(ask)
            if ask then
                local can, why = CraftCheck(r.item, profs)
                row.yes:SetEnabled(can); row.yes.why = why
            end
            row.no:SetShown(r.state == "open" and (mine or not r.sale))
        end
        for i, col in ipairs(cols) do row.cells[i]:SetText(v[col[1]] or "") end
    end)
end

---------------------------------------------------------------------------
-- Nuevo anuncio: pedir o vender (un BOE solo se vende, y solo se venden BOE), el objeto (con autorrelleno), quién pone
-- los materiales, propina o precio en oro · plata · cobre, si va al tablón (con cuánto dura) o para alguien (con
-- autorrelleno del nombre) [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local SUGGEST_N = 6

-- (lo que encaja con lo escrito, de mejor a peor (HU.TextRank: lo exacto y las palabras enteras primero); en cada grupo,
-- el nombre más corto, que es el que más se parece a lo escrito, y luego por nombre)
local function Better(x, y)
    if x.rank ~= y.rank then return x.rank < y.rank end
    if #x.key ~= #y.key then return #x.key < #y.key end
    return x.key < y.key
end

-- Lista de sugerencias bajo una caja: source(q) da { { text, value, key, rank } }; clic o Intro (la primera) la elige
-- (la ficha del juego de lo que lleva `text`, si es un enlace, a la derecha de `owner`, sin taparlo: Jorge, 24/11, «que
-- aparezca al pasar el ratón lo que es, pero que no moleste»)
local function HyperTip(owner, text)
    local link = type(text) == "string" and not HU.Secret(text) and text:match("|H(.-)|h")
    if not link then return end
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() else GameTooltip:Hide() end
end

local function Suggest(box, source)
    local list = CreateFrame("Frame", nil, box, "BackdropTemplate")
    list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -1)
    list:SetWidth(math.max(box:GetWidth() + 8, 260))
    DJ.Panel(list, DJ.T.frame, DJ.T.border, 10, 2)
    list:SetFrameLevel(box:GetFrameLevel() + 30)
    list:Hide()
    local btns, found = {}, {}
    local function Pick(v) box:SetText(v); box:SetCursorPosition(#v); list:Hide() end
    for i = 1, SUGGEST_N do
        local b = CreateFrame("Button", nil, list)
        b:SetHeight(16)
        b:SetPoint("TOPLEFT", 4, -2 - (i - 1) * 16); b:SetPoint("RIGHT", list, "RIGHT", -4, 0)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 2, 0); b.text:SetPoint("RIGHT", -2, 0); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.15)
        b:SetScript("OnClick", function(s) if s.value then Pick(s.value) end end)
        -- (un objeto: al pasar el ratón, su ficha, al lado de la lista)
        b:SetScript("OnEnter", function(s) HyperTip(list, s.value) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btns[i] = b
    end
    box:HookScript("OnTextChanged", function(s, user)
        if not user then list:Hide(); return end
        local q = HU.Trim(s:GetText() or "")
        found = #q >= 2 and source(q) or {}
        table.sort(found, Better)
        for i, b in ipairs(btns) do
            local f = found[i]
            b.value = f and f.value
            b.text:SetText(f and f.text or ""); b:SetShown(f ~= nil)
        end
        list:SetHeight(4 + math.min(#found, SUGGEST_N) * 16)
        list:SetShown(#found > 0)
    end)
    box:HookScript("OnEnterPressed", function() if list:IsShown() and found[1] then Pick(found[1].value) end end)
    box:HookScript("OnEscapePressed", function() list:Hide() end)
    box:HookScript("OnHide", function() list:Hide() end)
end

-- Objetos que el juego ya conoce: el de ese nombre exacto, los de mis bolsas, los de las solicitudes y los
-- fabricables. Todos los que encajan, de mejor a peor, y luego los primeros (antes se cortaba a 60 en el orden de
-- la tabla y los mejores se podían quedar fuera)
local function ItemMatches(text)
    local out, seen = {}, {}
    local function push(link, k)
        if seen[k] then return end
        local rank = HU.TextRank(k, text)
        if not rank then return end
        seen[k] = true
        out[#out + 1] = { text = link, value = link, key = k, rank = rank }
    end
    local function add(link)
        if type(link) ~= "string" or HU.Secret(link) or not link:find("|H", 1, true) then return end
        push(link, (HU.Fold(Plain(link)):gsub("^%[", ""):gsub("%]$", "")))
    end
    local exact = ItemInfo(text)
    if exact then add(exact.link) end
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local slotLink = C_Container and C_Container.GetContainerItemLink
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local okN, n = pcall(numSlots, bag)
        for slot = 1, (okN and type(n) == "number") and n or 0 do
            local okL, l = pcall(slotLink, bag, slot)
            if okL then add(l) end
        end
    end
    for _, r in ipairs(reqs) do add(r.item) end
    for _, c in pairs(craft) do push(c.link, c.key) end
    table.sort(out, Better)
    for i = #out, SUGGEST_N + 1, -1 do out[i] = nil end
    return out
end

-- Personajes que conozco: mi hermandad, las listas de las otras y los que tienen GuildUnion
local function NameMatches(text)
    local out, seen = {}, { [Me():lower()] = true }
    local function add(full, tag)
        if type(full) ~= "string" or HU.Secret(full) then return end
        local k = full:lower()
        local short = HU:Short(full)
        local rank = not seen[k] and HU.TextRank(short, text)
        if not rank then return end
        seen[k] = true
        local t = tag and (" |cff" .. HU:GuildColorHex(tag) .. "<" .. tag .. ">|r") or ""
        out[#out + 1] = { text = short .. t, value = full, key = HU.Fold(short), rank = rank }
    end
    for _, e in ipairs(HU.rosterList or {}) do add(e.name, HU.myTag) end
    for tag, rr in pairs(HU.remoteRoster or {}) do for _, m in ipairs(rr.members or {}) do add(m.name, tag) end end
    for _, pr in pairs(HU.remote or {}) do add(pr.name, pr.tag) end
    return out
end

-- (lo que espera a que el juego conozca el objeto para decidir si es BOE: { id }; se publica al llegar)
local pendingSubmit

local function BuildNewDialog(host)
    local d = CreateFrame("Frame", "GuildUnionTradeNew", host, "BackdropTemplate")
    d:SetSize(310, 290)
    d:SetPoint("CENTER", host, "CENTER", 0, 0)
    d:SetFrameStrata("DIALOG")
    DJ.Panel(d, DJ.T.content, DJ.T.border, 14, 4)
    DJ.Parchment(d, 0.18)
    d:EnableMouse(true)
    -- (se mueve arrastrándola, sin salirse de la pantalla: Jorge, 25/11, «la ventana del request order debe ser movible»)
    d:SetMovable(true); d:SetClampedToScreen(true); d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:Hide()
    d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.title:SetPoint("TOPLEFT", 12, -10)
    local function Label(text, font)
        local l = d:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
        l:SetText(text)
        return l
    end
    local function Check(text)
        local c = CreateFrame("CheckButton", nil, d, "UICheckButtonTemplate")
        c:SetSize(20, 20)
        if c.Text then c.Text:SetFontObject("GameFontHighlightSmall"); c.Text:SetText(text) end
        return c
    end
    -- (casillas que se excluyen: marcar una desmarca las demás)
    local function Group(list, onChange)
        for _, c in ipairs(list) do
            c:SetScript("OnClick", function()
                for _, o in ipairs(list) do o:SetChecked(o == c) end
                if onChange then onChange() end
            end)
        end
    end

    d.kindLabel = Label(L("Anuncio:"))
    d.kindAsk, d.kindSell = Check(L("Pedir")), Check(L("Vender"))
    d.itemLabel = Label(L("Objeto o encantamiento (o Mayús+clic):"))
    d.item = HU.NewEditBox(d, 222)
    d.qtyLabel = Label(L("Cantidad:"))
    d.qty = HU.NewEditBox(d, 42); d.qty:SetNumeric(true); d.qty:SetMaxLetters(3)
    d.qty:SetJustifyH("CENTER")
    Suggest(d.item, ItemMatches)

    d.matsLabel = Label(L("Materiales:"))
    d.matsMe, d.matsSeller = Check(L("Yo")), Check(L("Vendedor"))
    Group({ d.matsMe, d.matsSeller })

    -- (la propina (o el precio, al vender): se esconde si el maestro no permite propinas, UnionConfig.lua)
    d.tipLabel = Label(L("Propina:"))
    d.tipParts = { d.tipLabel, Label(L("(en blanco: a negociar)"), "GameFontDisableSmall") }
    d.coins = {}
    for i, icon in ipairs(COIN_ICON) do
        local box = HU.NewEditBox(d, 56); box:SetNumeric(true)
        box:SetMaxLetters(i == 1 and 6 or 2); box:SetJustifyH("CENTER")
        local tex = d:CreateTexture(nil, "ARTWORK")
        tex:SetSize(14, 14); tex:SetTexture(icon); tex:SetPoint("BOTTOM", box, "TOP", -3, 2)
        d.coins[i] = box
        d.tipParts[#d.tipParts + 1] = box; d.tipParts[#d.tipParts + 1] = tex
    end

    d.pubLabel = Label(L("En el tablón:"))
    d.pubYes, d.pubNo = Check(L("Sí")), Check(L("No"))
    d.toLabel = Label(L("Personaje:"))
    d.to = HU.NewEditBox(d, 196)
    Suggest(d.to, NameMatches)
    -- (cuánto dura en el tablón: 5, 12, 24 (de entrada) o 48 h; las privadas no caducan, como hasta ahora)
    d.expLabel = Label(L("Dura:"))
    d.expChecks = {}
    for i, h in ipairs(EXPIRY_HOURS) do
        local c = Check(h .. " h")
        c.hours = h
        d.expChecks[i] = c
    end
    Group(d.expChecks)

    -- Coloca las filas que tocan, de arriba abajo: al vender no hay materiales ni «En el tablón» (una venta va siempre
    -- al tablón) y la propina es el precio; en el tablón, cuánto dura; si no, a quién
    function d.Relayout()
        local sale = d.kindSell:GetChecked() and true or false
        local pub = sale or (d.pubYes:GetChecked() and true or false)
        local tips = not HU:UnionCfg().tipsOff
        local y = -34
        local function At(w, x, dy)
            w:ClearAllPoints(); w:SetPoint("TOPLEFT", x, y + (dy or 0)); w:Show()
        end
        At(d.kindLabel, 12); At(d.kindAsk, 96, 5); At(d.kindSell, 170, 5)
        y = y - 26
        At(d.itemLabel, 12); At(d.qtyLabel, 248); At(d.item, 18, -14); At(d.qty, 254, -14)
        y = y - 46
        for _, w in ipairs({ d.matsLabel, d.matsMe, d.matsSeller, d.pubLabel, d.pubYes, d.pubNo }) do w:SetShown(not sale) end
        if not sale then
            At(d.matsLabel, 12); At(d.matsMe, 96, 5); At(d.matsSeller, 170, 5)
            y = y - 26
        end
        d.tipLabel:SetText(sale and L("Precio:") or L("Propina:"))
        for _, w in ipairs(d.tipParts) do w:SetShown(tips) end
        if tips then
            At(d.tipParts[1], 12); At(d.tipParts[2], 64)
            for i, box in ipairs(d.coins) do At(box, 18 + (i - 1) * 74, -32) end
            y = y - 64
        end
        if not sale then
            At(d.pubLabel, 12); At(d.pubYes, 96, 5); At(d.pubNo, 170, 5)
            y = y - 28
        end
        d.toLabel:SetShown(not pub); d.to:SetShown(not pub); d.expLabel:SetShown(pub)
        for _, c in ipairs(d.expChecks) do c:SetShown(pub) end
        if pub then
            At(d.expLabel, 12)
            for i, c in ipairs(d.expChecks) do At(c, 64 + (i - 1) * 58, 5) end
        else
            At(d.toLabel, 12); At(d.to, 102, 4)
        end
        y = y - 28
        d:SetHeight(-y + 38)
    end
    function d.SetPub(pub)
        d.pubYes:SetChecked(pub); d.pubNo:SetChecked(not pub)
        d.Relayout()
    end
    function d.SetExpiry(hours)
        for _, c in ipairs(d.expChecks) do c:SetChecked(c.hours == hours) end
    end
    local function Hours()
        for _, c in ipairs(d.expChecks) do if c:GetChecked() then return c.hours end end
        return EXPIRY_DEFAULT
    end
    Group({ d.kindAsk, d.kindSell }, d.Relayout)
    Group({ d.pubYes, d.pubNo }, function()
        d.Relayout()
        if d.to:IsShown() then d.to:SetFocus() end
    end)

    -- Publicar. Un BOE solo se vende y solo se venden BOE: si el juego aún no conoce el objeto, se le pide y se decide al
    -- llegar (final: ya no se espera más; lo que sigue sin saberse, al pedir vale y al vender no) [+ARCHITECTURE.md]
    function d.Submit(final)
        -- (con el comercio apagado no se pide nada, aunque la ventana se hubiera quedado abierta de antes)
        if HU:UnionCfg().tradeOff then
            d:Hide()
            return HU:Print(L("El maestro de la hermandad ha desactivado el comercio (pestaña GuildUnion, Configuración → Comercio)."))
        end
        local item = HU.Trim(d.item:GetText() or "")
        if item == "" then return HU:Print(L("Pon el objeto que pides (Mayús+clic en él).")) end
        Fresh()
        if OpenCount() >= MAX_OPEN then return HU:Print(string.format(L("Ya tienes %d solicitudes abiertas: cierra alguna antes."), MAX_OPEN)) end
        local sale = d.kindSell:GetChecked() and true or false
        local pub = sale or (d.pubYes:GetChecked() and true or false)
        local to = HU.Trim(d.to:GetText() or "")
        if not pub and to == "" then return HU:Print(L("Si no va al tablón, pon a quién se la pides.")) end
        local boe, id = BoeOf(item)
        if boe == nil and not final then
            local p = { id = id }
            pendingSubmit = p
            HU.After(ITEM_WAIT, function()
                if pendingSubmit ~= p then return end
                pendingSubmit = nil
                if d:IsShown() then d.Submit(true) end
            end)
            return HU:Print(L("Comprobando el objeto con el juego…"))
        end
        -- (un BOE que se fabrica sí se pide: es encargarlo a quien sabe hacerlo, no comprarlo. Casi todo el equipo fabricado
        -- de Forever es BOE verde o mejor. Uno de botín, solo se vende. Jorge, 25/11: «los BOES solo se podrán vender, nunca
        -- poner para comprar»)
        if boe and not sale and not CraftTargets(item) then
            return HU:Print(L("Es BOE de botín (se liga al equipar y no se fabrica): solo se puede vender, no pedir."))
        end
        if sale and boe == nil then return HU:Print(L("No se ha podido comprobar el objeto: prueba otra vez.")) end
        if sale and not boe then return HU:Print(L("Solo se venden objetos BOE: los que se ligan al equipar, de verde a legendario.")) end
        -- (la propina o el precio, en cobre; las tres cajas vacías: a negociar)
        local tip, any = 0, false
        for i, box in ipairs(d.coins) do
            local v = tonumber(box:GetText() or "")
            if v then any = true; tip = tip + v * (i == 1 and 10000 or i == 2 and 100 or 1) end
        end
        local mats
        if d.matsMe:GetChecked() then mats = true elseif d.matsSeller:GetChecked() then mats = false end
        -- (a toda la unión, con el conjunto TR: queda ya en lo mío y sale por mi hermandad; sin la unión, no se puede)
        local r = { id = NewId(), who = Me(), item = item, sale = sale or nil, mats = (not sale) and mats or nil,
            tip = (any and not (HU:UnionCfg().tipsOff)) and tip or nil, qty = math.max(1, tonumber(d.qty:GetText() or "") or 1),
            state = "open", pub = pub, to = (not pub) and (HU:FullName(to) or to) or nil,
            exp = pub and (HU.StampNow() + Hours() * 3600) or nil }
        if not HU:TradeOrder(r) then return HU:Print(L("No se ha podido pedir: tu hermandad todavía no está en la unión.")) end
        d:Hide()
        view = pub and "pub" or "priv"
        ui.search:SetText("")
        Paint()
    end
    local ok = Flat(d, L("Publicar"), 110, 22); ok:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 12)
    local no = Flat(d, L("Cancelar"), 110, 22); no:SetPoint("BOTTOMLEFT", d, "BOTTOM", 6, 12)
    no:SetScript("OnClick", function() d:Hide() end)
    ok:SetScript("OnClick", function() pendingSubmit = nil; d.Submit(false) end)
    -- (Mayús+clic en un objeto con esta caja escribiendo: entra su enlace)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", function(text)
            if d:IsShown() and d.item:HasFocus() and type(text) == "string" then d.item:SetText(text) end
        end)
    end
    return d
end
-- (el juego ya conoce el objeto que esperaba un anuncio: se decide ahora)
local function ItemArrived(itemID)
    local p = pendingSubmit
    if not (p and itemID == p.id) then return end
    pendingSubmit = nil
    if ui and ui.newDlg:IsShown() then ui.newDlg.Submit(true) end
end
HU:On("ITEM_DATA_LOAD_RESULT", ItemArrived)
HU:On("GET_ITEM_INFO_RECEIVED", ItemArrived)

---------------------------------------------------------------------------
-- Modo prueba: solicitudes y chats de mentira; no se manda nada. Sin botón ni comando (Jorge, 24/11: «quitando el
-- test mode»): solo por código, con HU:TradeTest; lo usan las pruebas
---------------------------------------------------------------------------
-- (quitar lo de prueba: sus solicitudes y los chats con los de prueba)
local function ClearTest()
    testReqs = {}
    Merge()
    for key in pairs(chats) do if key:find("%-Prueba$") then chats[key] = nil end end
    -- (y sus líneas sin leer)
    local had = false
    for key in pairs(unread) do if key:find("%-Prueba$") then unread[key] = nil; had = true end end
    if chatKey and chatKey:find("%-Prueba$") then OpenChat(nil) end
    selected, picks = nil, {}
    if had then PaintUnread(); HU:Changed("tradeUnread") end
end

local function AddTest()
    ClearTest()
    local now = HU.StampNow()
    local function R(who, item, mats, tip, state, pub, to, taker, qty)
        testReqs[#testReqs + 1] = { id = NewId(), who = who, item = item, mats = mats, tip = tip and tip * 10000, qty = qty, state = state, pub = pub,
            to = to, taker = taker, takenAt = taker and now or nil, t = now, test = true }
    end
    local function Link(id, name, color)
        local it = ItemInfo(id)
        if it then return it.link end
        return "|cff" .. color .. "|Hitem:" .. id .. "::::::::60:::::::|h[" .. name .. "]|h|r"
    end
    R("Jandra-Prueba", Link(3928, "Poción de curación superior", "ffffff"), false, 2.5, "open", true, nil, nil, 5)
    R("Pepe-Prueba", Link(7378, "Bolsa de tejido de lana", "1eff00"), true, nil, "open", true)
    R("Lyra-Prueba", Link(7931, "Cofia de mitril", "1eff00"), true, 3, "taken", true, nil, "Bea-Prueba")
    R(Me(), Link(7056, "Capa de seda carmesí", "1eff00"), true, 5, "open", true)
    R("Bea-Prueba", Link(8949, "Elixir de agilidad", "ffffff"), false, 1, "open", false, Me())
    R(Me(), Link(7954, "Gran espada de mitril", "0070dd"), true, nil, "taken", false, "Pepe-Prueba", "Pepe-Prueba")
    R("Lyra-Prueba", Link(7931, "Cofia de mitril", "1eff00"), true, 2, "open", false, Me())
    R(Me(), Link(3928, "Poción de curación superior", "ffffff"), false, 0.5, "open", false, "Jandra-Prueba")
    Merge()
    ChatLine("Lyra-Prueba", "Lyra-Prueba", L("Te dejo el encargo; mañana me conecto."))
    ChatLine("Pepe-Prueba", "Pepe-Prueba", L("Te hago la espada esta noche."))
    ChatLine("Bea-Prueba", "Bea-Prueba", L("¿Me haces el elixir? Pago bien."))
    Paint()
end

-- Poner (on) o quitar lo de prueba
function HU:TradeTest(on)
    if on then AddTest() else ClearTest(); Paint() end
end

---------------------------------------------------------------------------
-- Lo guardado, por personaje: los chats con cada persona, lo sin leer, lo quitado de mi lista, las privadas ya avisadas y
-- lo que espera a que la otra persona se conecte (Jorge, 24/11: «al hacer /reload se borra todo»). Las solicitudes, en
-- las propuestas (Net/Packs.lua). Lo de prueba no se guarda, y lo de hace más de KEEP_DAYS se quita [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local KEEP_DAYS = 30
local function Tidy()
    local old, db = time() - KEEP_DAYS * 86400, HU.db
    for key in pairs(chats) do if key:find("%-Prueba$") then chats[key] = nil end end
    for key in pairs(unread) do if key:find("%-Prueba$") or not chats[key] then unread[key] = nil end end
    for _, set in ipairs({ db.tradeClosed, db.tradeSeen }) do
        for id, t in pairs(set) do if type(t) ~= "number" or t < old then set[id] = nil end end
    end
    for key, l in pairs(db.tradePending) do
        if type(l) == "table" then
            for i = #l, 1, -1 do if type(l[i]) ~= "table" or type(l[i].m) ~= "string" or (tonumber(l[i].t) or 0) < old then table.remove(l, i) end end
        end
        if type(l) ~= "table" or key:find("%-Prueba$") or not l[1] then db.tradePending[key] = nil end
    end
end
-- La copia 324 guardaba mis solicitudes en el personaje (tradeReqs): las abiertas se proponen una vez, en cuanto se sabe mi
-- hermandad, y la lista se vacía. Entonces nada viajaba: nadie pudo aceptarlas, y las canceladas ya no se ven
local function Migrate()
    local old = HU.db and HU.db.tradeReqs
    if not (old and old[1] and HU.myTag) then return end
    for _, r in ipairs(old) do
        if type(r) == "table" and not r.test and IsMe(r.who) and r.state == "open" and type(r.id) == "string"
            and r.id:match("^%w+$") and #r.id <= 20 then
            HU:TradeOrder(r)
        end
    end
    for i = #old, 1, -1 do old[i] = nil end
end
-- (con el aviso «trade» se rehacen las de la red; si cambia mi hermandad, también, y se mira lo de la copia 324. Con
-- «professions», lo de oficios que llega mientras se busca (o con Buscar a la vista): se repinta un momento después, una
-- vez)
local foundQueued
HU:Listen("CHANGED", function(what)
    if what == "trade" then MarkDirty()
    elseif what == "config" then
        Migrate()
        if builtTag ~= HU.myTag then MarkDirty() end
    elseif what == "professions" and not foundQueued and ui and ui:IsVisible()
        and (Searching() or view == "find" or ui.who:IsShown()) then
        foundQueued = true
        HU.After(2, function()
            foundQueued = nil
            if ui:IsVisible() then Paint() end
        end)
    end
end)
HU:OnStart(function()
    chats, unread = HU.db.tradeChats, HU.db.tradeUnread
    Tidy()
    Migrate()
    netDirty = true
    HU:Changed("tradeUnread")
    HU:Every(30, "Comercio: chat pendiente", Repaso)
    -- (con la sección a la vista, cada minuto: lo que falte de las solicitudes, y se repinta (lo que le queda a cada
    -- anuncio; lo caducado se va))
    HU:Every(60, "Comercio: al día", function()
        if ui and ui:IsVisible() then NeedAll(); Paint() end
    end)
end)
HU:On("PLAYER_LOGOUT", Tidy)

---------------------------------------------------------------------------
-- Montar la sección (UnionRoster.lua la pone en la pestaña Trade)
---------------------------------------------------------------------------
-- (Aceptar o el tic, apagados: por qué no puedo hacerla, en rojo; Paint deja el porqué en `why`)
local function WhyTip(s)
    if not s.why then return end
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:SetText(s.why, 1, 0.35, 0.35)
    GameTooltip:Show()
end

-- (un filtro de Buscar cambia: la lista se rehace y se vuelve arriba)
local function FilterChanged()
    findDirty = true
    FauxScrollFrame_SetOffset(ui.items.scroll, 0)
    Paint()
end
-- (el texto del botón de un filtro: su nombre sin nada elegido; lo elegido, si es uno; si no, cuántos)
local function FilterLabel(base, set, opts)
    local n, one = 0, nil
    for _, o in ipairs(opts) do if set[o[1]] then n, one = n + 1, o end end
    if n == 0 then return L(base) end
    if n == 1 then return L(one[2]) end
    return string.format("%s (%d)", L(base), n)
end
-- (el menú de un filtro: casillas, varias a la vez; con su color o, las profesiones, con su icono detrás de la casilla.
-- Sale siempre debajo de su botón, como los desplegables del juego: con el de clic derecho salía donde estaba el ratón.
-- Jorge, 25/11: «cada vez que salga este desplegable, debe salir siempre en el mismo sitio». Sin el sistema de menús
-- del juego, el de clic derecho) [+ARCHITECTURE.md]
local function FilterMenu(owner, base, set, opts)
    local M, V, U = Menu, MenuVariants, MenuUtil
    local function Open(gen)
        if M and M.GetManager and M.PopulateDescription and V and V.GetDefaultContextMenuMixin and CreateAnchor
            and U and U.CreateRootMenuDescription then
            local desc = U.CreateRootMenuDescription(V.GetDefaultContextMenuMixin())
            M.PopulateDescription(gen, owner, desc)
            return M.GetManager():OpenMenu(owner, desc, CreateAnchor("TOPLEFT", owner, "BOTTOMLEFT", 0, -2))
        end
        if U and U.CreateContextMenu then return U.CreateContextMenu(owner, gen) end
    end
    Open(function(_, root)
        root:CreateTitle(L(base))
        for _, o in ipairs(opts) do
            local text = (o.skill and ProfLabel(o.skill)) or (o.color and ("|cff" .. o.color .. L(o[2]) .. "|r")) or L(o[2])
            root:CreateCheckbox(text, function() return set[o[1]] == true end, function()
                set[o[1]] = (not set[o[1]]) or nil
                owner:SetText(FilterLabel(base, set, opts))
                FilterChanged()
            end)
        end
    end)
end

-- La fila 2 de Buscar: profesión · nivel (el requerido) de… a… · rareza · tipo · buscador, en vez del buscador y la
-- casilla. Los menús, con casillas, salen debajo de su botón (FilterMenu) [+ARCHITECTURE.md]
local function BuildFilters(host)
    local f = CreateFrame("Frame", nil, host)
    f:SetAllPoints(host)
    local y = ROW2_Y - ROW2_H / 2
    local profs = {}
    for skill, name in pairs(PROF_NAMES) do profs[#profs + 1] = { skill, name, skill = skill } end
    table.sort(profs, function(a, b) return L(a[2]) < L(b[2]) end)
    local quals, types = {}, {}
    for i, q in ipairs(QUALITIES) do quals[i] = { q[1], q[2], color = q[3] } end
    for i, t in ipairs(TYPES) do types[i] = { t[1], t[2] } end
    local function FilterBtn(base, set, opts, x, w)
        local b = Flat(f, L(base), w, 22)
        b:SetPoint("LEFT", host, "TOPLEFT", x, y)
        b:SetScript("OnClick", function(s) FilterMenu(s, base, set, opts) end)
        return b
    end
    f.prof = FilterBtn("Profesión", findProf, profs, 23, 118)
    -- («Nivel:», el que pide el objeto para usarlo, con las dos cajas pegadas. Jorge, 25/11: «item lvl no, debe ser Level
    -- nada más (nivel requerido), los 2 campos más pegados a donde pone level»)
    f.lvlLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.lvlLabel:SetPoint("LEFT", host, "TOPLEFT", 149, y); f.lvlLabel:SetWidth(32); f.lvlLabel:SetJustifyH("LEFT")
    f.lvlLabel:SetText(L("Nivel:"))
    local function Level(x, set)
        local box = HU.NewEditBox(f, 30)
        box:SetPoint("LEFT", host, "TOPLEFT", x, y); box:SetNumeric(true); box:SetMaxLetters(3); box:SetJustifyH("CENTER")
        box:HookScript("OnTextChanged", function(s)
            set(tonumber(s:GetText() or ""))
            FilterChanged()
        end)
        return box
    end
    f.lvlMin = Level(187, function(v) findMin = v end)
    f.lvlTo = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.lvlTo:SetPoint("LEFT", host, "TOPLEFT", 221, y); f.lvlTo:SetWidth(14); f.lvlTo:SetJustifyH("CENTER")
    f.lvlTo:SetText(L("a"))
    f.lvlMax = Level(241, function(v) findMax = v end)
    f.qual = FilterBtn("Rareza", findQual, quals, 281, 92)
    f.type = FilterBtn("Tipo", findType, types, 381, 104)
    -- Un enlace en un buscador (Mayús+clic o una sugerencia): se ve su nombre entre corchetes, del color de su calidad, y
    -- el enlace queda aparte (`box.link`). Con los códigos del enlace dentro, en una caja estrecha el juego no lo pintaba
    -- (Jorge, 25/11: «cuando linkeo no se ve, pero está»). Con un enlace puesto, borrar (o escribir) lo quita entero, de
    -- una vez («si le doy al botón de borrar… debería borrarse, entero de una si es linkeado») [+ARCHITECTURE.md]
    function f.SetLink(box, link)
        box.link, box.linkText = link, "[" .. (link:match("|h%[(.-)%]|h") or Plain(link)) .. "]"
        local hex = link:match("^|c%x%x(%x%x%x%x%x%x)")
        if hex then
            box:SetTextColor(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255)
        end
        box:SetText(box.linkText)
    end
    function f.WatchLink(box)
        box:HookScript("OnTextChanged", function(s, user)
            local text = s:GetText() or ""
            if s.link and text == s.linkText then return end
            if s.link then
                s.link, s.linkText = nil, nil
                s:SetTextColor(1, 1, 1)
                if user then s:SetText(""); return end
            end
            -- (otro enlace encima del que había, o uno nuevo: se ve por su nombre)
            if text:find("|H", 1, true) then f.SetLink(s, text) end
        end)
    end
    -- (al final, su buscador, como el del Tablón: un nombre, o el enlace de un objeto con Mayús+clic (BuildTrade), que
    -- deja solo ese objeto; con un enlace, al pasar el ratón, su ficha. Jorge, 25/11: «añade buscador para el item también,
    -- que se pueda linkear ahí con el shift+click»)
    local search = CreateFrame("EditBox", "GuildUnionTradeFindSearch", f, "SearchBoxTemplate")
    search:SetSize(108, 22)
    search:SetPoint("RIGHT", host, "TOPRIGHT", -14, y)
    if search.Instructions then
        search.Instructions:SetText(L("Buscar objeto")); DJ.C(search.Instructions, DJ.T.muted)
    end
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", search, "TOPLEFT", -9, 3); box:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", 3, -3)
    DJ.Panel(box, DJ.T.row, { DJ.T.line[1], DJ.T.line[2], DJ.T.line[3], 0.55 }, 10, 2)
    box:SetFrameLevel(search:GetFrameLevel())
    search:SetFrameLevel(box:GetFrameLevel() + 2)
    f.WatchLink(search)
    search:HookScript("OnTextChanged", FilterChanged)
    search:HookScript("OnEnter", function(s) HyperTip(s, s.link or s:GetText()) end)
    search:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.search = search
    return f
end

-- «Quién lo hace» un objeto de Buscar (`who.key`), en su ventana, que se mueve: todos los que pueden, como en la columna;
-- clic derecho en alguien, susurrarle o solicitar pedido (un anuncio privado para esa persona con el objeto ya puesto; a
-- mí, nada). Se abre con «Ver todos», al final de quién lo hace en cada fila de Buscar. Jorge, 25/11: «un botón para sacar
-- una pestaña (movible) con todos los que pueden, con botón derecho susurrar o solicitar pedido». Va aparte de
-- BuildTrade, que ya usa casi todo lo que deja Lua 5.1 (60 variables de fuera) [+ARCHITECTURE.md]
local function BuildWho(host, MakeList)
    local S = SIZES
    -- (las filas de objetos de Buscar: clic, se elige (lo que pide «+ Nuevo anuncio»); clic derecho, publicarlo en el
    -- tablón o ver quién lo hace (Jorge, 25/11: «que pueda hacer botón derecho "publicar en tablón"… y hacerlo público»);
    -- al final de quién lo hace, «Ver todos»)
    for _, row in ipairs(ui.items.rows) do
        row:SetScript("OnClick", function(s, button)
            local e = s.entry
            if not e then return end
            findSel = e.key
            Paint()
            if button ~= "RightButton" or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(s, function(_, root)
                root:CreateTitle(e.item)
                root:CreateButton(L("Publicar en el tablón"), function() ui.OpenNew(nil, e.item) end)
                if row.allBtn:IsShown() then root:CreateButton(L("Ver quién lo hace"), function() ui.OpenWho(e.key) end) end
                root:CreateButton(L("Cancelar"), function() end)
            end)
        end)
        local all = Flat(row, L("Ver todos"), S.allW, 18)
        all:SetNormalFontObject("GameFontNormalSmall"); all:SetHighlightFontObject("GameFontHighlightSmall")
        all:SetPoint("RIGHT", row, "RIGHT", -(6 + CELL_PAD), 0)
        all:SetScript("OnClick", function() if row.entry then ui.OpenWho(row.entry.key) end end)
        all:Hide()
        row.allBtn = all
    end
    local who = DJ.Window("GuildUnionTradeWho", host, S.whoW, S.whoH)
    tinsert(UISpecialFrames, "GuildUnionTradeWho")
    who.titleText:SetWidth(S.whoW - 70); who.titleText:SetWordWrap(false)
    -- (arriba, un buscador por nombre, solo entre los de la ventana: Jorge, 25/11)
    local find = CreateFrame("EditBox", "GuildUnionTradeWhoSearch", who.content, "SearchBoxTemplate")
    find:SetSize(170, 20)
    find:SetPoint("TOPLEFT", who.content, "TOPLEFT", 14, -7)
    if find.Instructions then find.Instructions:SetText(L("Buscar nombre")); DJ.C(find.Instructions, DJ.T.muted) end
    who.find = find
    local wl = MakeList(S.whoRows, false, "GuildUnionTradeWhoScroll", who.content)
    wl.list:SetPoint("TOPLEFT", who.content, "TOPLEFT", 6, -32)
    wl.list:SetWidth(S.whoW - 36 - 12 - S.scroll)
    Titled(wl, nil)
    wl.empty:SetText(L("Nadie de la unión lo hace."))
    find:HookScript("OnTextChanged", function()
        FauxScrollFrame_SetOffset(wl.scroll, 0)
        who.Paint()
    end)
    local function WhoMenu(owner, r)
        local c = who.key and craft[who.key]
        if not (c and MenuUtil and MenuUtil.CreateContextMenu) or IsMe(r.name) then return end
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateTitle(HU:Short(r.name))
            root:CreateButton(L("Susurrar"), function() HU.WhisperTo(r.name) end)
            root:CreateButton(L("Solicitar pedido"), function() ui.OpenNew(r.name, c.link) end)
            root:CreateButton(L("Cancelar"), function() end)
        end)
    end
    for _, row in ipairs(wl.rows) do
        row:SetScript("OnClick", function(s, button)
            if button == "RightButton" and s.entry then WhoMenu(s, s.entry) end
        end)
    end
    who.lst = wl
    who.hint = DJ.C(who:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), DJ.T.muted)
    who.hint:SetPoint("BOTTOM", who, "BOTTOM", 0, 20)
    ui.who = who
    -- (lo pinta Paint, si está abierta: con lo de ahora, como la columna; con el buscador, solo los nombres que encajan)
    function who.Paint()
        if not who:IsShown() then return end
        local c = who.key and craft[who.key]
        if not c then who:Hide(); return end
        local list = CraftersOf(who.key)
        who.titleText:SetText(L("Quién lo hace") .. ": " .. c.link)
        who.hint:SetText(string.format(L("Pueden hacerlo: %d · clic derecho: susurrar o solicitar pedido"), #list))
        local q = HU.Trim(find:GetText() or "")
        if q ~= "" then
            local out = {}
            for _, r in ipairs(list) do if HU.TextRank(r.name, q) then out[#out + 1] = r end end
            list = out
        end
        Columns(wl, COLS.search, 4)
        PaintRows(wl, list, FillWho)
    end
    function ui.OpenWho(key)
        if key ~= who.key then
            FauxScrollFrame_SetOffset(wl.scroll, 0)
            find:SetText("")
        end
        who.key, findSel = key, key
        -- (la primera vez, a la derecha de la ventana de hermandad; luego, donde la deje el jugador)
        if not who.placed then
            who.placed = true
            who:ClearAllPoints()
            who:SetPoint("TOPLEFT", CommunitiesFrame or host, "TOPRIGHT", 4, 0)
        end
        who:Show(); who:Raise()
        Paint()
    end
    -- (es de la sección: se cierra con ella)
    host:HookScript("OnHide", function() who:Hide() end)
end

function HU:BuildTrade(host)
    ui = host
    -- Arriba, los botones rojos Tablón · Mis encargos · Buscar, juntos en el centro; debajo, el buscador a la izquierda y
    -- «Solo lo que puedo hacer» a la derecha (en Buscar, los filtros); abajo, «+ Nuevo anuncio» (Jorge, 24/11: el sitio
    -- de la «opción 3», con los botones y el buscador y la casilla de antes) [+ARCHITECTURE.md]
    local sw = DJ.Switch(host, { { "pub", L("Tablón") }, { "priv", L("Mis encargos") }, { "find", L("Buscar") } })
    sw:SetPoint("TOP", host, "TOP", 0, -4)
    ui.switch = sw
    ui.viewBtns = sw.btns
    for k, b in pairs(sw.btns) do
        b:SetScript("OnClick", function()
            view, selected, picks = k, nil, {}
            ui.search:SetText("")
            FauxScrollFrame_SetOffset(ui.scroll, 0)
            Paint()
        end)
    end
    -- (el buscador, como antes: el del juego, con su ayuda en gris claro y un marco oscuro de borde dorado detrás; centrado
    -- en la fila)
    local search = CreateFrame("EditBox", "GuildUnionTradeSearch", host, "SearchBoxTemplate")
    search:SetSize(SEARCH_W, 22)
    search:SetPoint("TOPLEFT", host, "TOPLEFT", 23, ROW2_Y - (ROW2_H - 22) / 2)
    if search.Instructions then
        search.Instructions:SetText(L("Buscar receta")); DJ.C(search.Instructions, DJ.T.muted)
    end
    local sbox = CreateFrame("Frame", nil, host, "BackdropTemplate")
    sbox:SetPoint("TOPLEFT", search, "TOPLEFT", -9, 3); sbox:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", 3, -3)
    DJ.Panel(sbox, DJ.T.row, { DJ.T.line[1], DJ.T.line[2], DJ.T.line[3], 0.55 }, 10, 2)
    sbox:SetFrameLevel(search:GetFrameLevel())
    search:SetFrameLevel(sbox:GetFrameLevel() + 2)
    ui.searchBox = sbox
    -- (con un objeto escrito, al pasar el ratón, su ficha, a la derecha del buscador)
    search:HookScript("OnEnter", function(s) HyperTip(s, s.link or s:GetText()) end)
    search:HookScript("OnLeave", function() GameTooltip:Hide() end)
    search:HookScript("OnTextChanged", function()
        if not ui.found then return end
        FauxScrollFrame_SetOffset(ui.req.scroll, 0); FauxScrollFrame_SetOffset(ui.found.scroll, 0)
        Paint()
    end)
    ui.search = search
    -- «Solo lo que puedo hacer», a la derecha de la misma fila: la casilla del juego, como antes, con su texto detrás, que
    -- acaba en el borde. En el Tablón (y al buscar), solo lo que HU:CanCraft deja; en Mis encargos, fuera lo que haría yo
    -- y no puedo hacer. Se recuerda por personaje
    local only = CreateFrame("CheckButton", nil, host, "UICheckButtonTemplate")
    only:SetSize(22, 22)
    if only.Text then only.Text:SetFontObject("GameFontHighlightSmall"); only.Text:SetText(L("Solo lo que puedo hacer")) end
    local tw = only.Text and only.Text:GetStringWidth()
    tw = (type(tw) == "number" and tw > 0 and not HU.Secret(tw)) and tw or 130
    only:SetPoint("LEFT", host, "TOPRIGHT", -(14 + 22 + 2 + tw), ROW2_Y - ROW2_H / 2)
    only:SetScript("OnClick", function(s)
        HU.db.tradeOnlyCraft = (not OnlyCraft()) or nil
        s:SetChecked(OnlyCraft())
        FauxScrollFrame_SetOffset(ui.req.scroll, 0)
        Paint()
    end)
    only:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(L("Solo lo que puedo hacer"))
        GameTooltip:AddLine(L("En el tablón, solo lo que puedes hacer con tus profesiones y tus recetas (lo que no se sabe qué es, tampoco). En Mis encargos, esconde los que harías tú y no puedes hacer; los que pides tú se ven siempre."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    only:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.onlyCraft = only
    -- (en Buscar, en la misma fila, los filtros)
    ui.filters = BuildFilters(host)
    ui.filters.WatchLink(search)
    -- (Mayús+clic en un objeto con uno de los dos buscadores escribiendo: entra su enlace, que se ve por su nombre)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", function(text)
            if type(text) ~= "string" then return end
            for _, box in ipairs({ search, ui.filters.search }) do
                if box:HasFocus() then box:SetText(text) end
            end
        end)
    end

    -- (detrás de todo, el panel de la sección, justo debajo de las dos filas: color «content» y borde, como el calendario)
    local bg = CreateFrame("Frame", nil, host, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", host, "TOPLEFT", 2, BODY_Y + 4); bg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)
    bg:SetFrameLevel(host:GetFrameLevel() + 1)
    DJ.Panel(bg, DJ.T.content, DJ.T.border, 14, 4)
    DJ.Parchment(bg, 0.18)
    local body = CreateFrame("Frame", nil, host)
    body:SetPoint("TOPLEFT", host, "TOPLEFT", 0, BODY_Y); body:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, BOTTOM_H)
    body:SetFrameLevel(bg:GetFrameLevel() + 2)
    ui.body = body
    -- (el aviso de apagado, en el panel: en host quedaba por debajo de él y no se veía)
    ui.offMsg = DJ.C(bg:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"), DJ.T.muted)
    ui.offMsg:SetPoint("CENTER"); ui.offMsg:SetWidth(420)
    ui.offMsg:SetText(L("El maestro de la hermandad ha desactivado el comercio (pestaña GuildUnion, Configuración → Comercio)."))
    HU:Listen("CHANGED", function(what) if what == "unionCfg" and ui:IsShown() then Paint() end end)

    -- Derecha (solo en Mis encargos): el chat de la persona del comercio que eliges, de arriba abajo: desde debajo del
    -- buscador hasta el borde de abajo de la sección (Jorge, 24/11)
    local chat = CreateFrame("Frame", nil, body, "BackdropTemplate")
    chat:SetPoint("TOPRIGHT", body, "TOPRIGHT", -SIZES.edge, 0); chat:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -SIZES.edge, 8)
    chat:SetWidth(CHAT_W)
    DJ.Panel(chat, DJ.T.panel, DJ.T.border, 12, 3)
    DJ.Parchment(chat, 0.13)
    ui.chat = chat
    ui.chatTitle = chat:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.chatTitle:SetPoint("TOPLEFT", 8, -7); ui.chatTitle:SetPoint("RIGHT", chat, "RIGHT", -8, 0)
    ui.chatTitle:SetJustifyH("LEFT"); ui.chatTitle:SetWordWrap(false)
    -- («Hecha» en lo que hago yo; «Vendida» en una venta mía)
    local done = Flat(chat, L("Hecha"), 64, 18)
    done:SetPoint("TOPRIGHT", -5, -4)
    done:SetScript("OnClick", function()
        local r = selected and FindReq(IdOf(selected))
        if r and r.sale then MarkSold(r) else MarkDone(r) end
    end)
    ui.doneBtn = done
    ui.chatTitle:SetPoint("RIGHT", done, "LEFT", -6, 0)
    local msgs = CreateFrame("ScrollingMessageFrame", nil, chat)
    msgs:SetPoint("TOPLEFT", 6, -24); msgs:SetPoint("BOTTOMRIGHT", -6, 28)
    -- (la letra pequeña de siempre con 3 de aire entre líneas: el marco de mensajes la reparte a cada línea)
    local font = CreateFont("GuildUnionTradeChatFont")
    font:CopyFontObject(GameFontHighlightSmall); font:SetSpacing(3)
    msgs:SetFontObject(font); msgs:SetJustifyH("LEFT")
    msgs:SetFading(false); msgs:SetMaxLines(200)
    msgs:EnableMouseWheel(true)
    msgs:SetScript("OnMouseWheel", function(s, d) if d > 0 then s:ScrollUp() else s:ScrollDown() end end)
    ui.msgs = msgs
    local input = HU.NewEditBox(chat, CHAT_W - 14)
    input:SetPoint("BOTTOMLEFT", 10, 6)
    input:SetScript("OnEnterPressed", function(s)
        local text = HU.Trim(s:GetText() or "")
        -- (a la otra persona por susurro; a un desconectado, cuando se conecte. A las de prueba, no)
        if text ~= "" and chatKey then
            ChatLine(chatKey, Me(), text)
            if not chatKey:find("%-Prueba$") then SendChat(chatKey, text) end
        end
        s:SetText(""); s:ClearFocus()
    end)
    ui.chatInput = input
    ui.chatHint = chat:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.chatHint:SetPoint("LEFT", input, "LEFT", 2, 0); ui.chatHint:SetText(L("Elige un comercio con alguien para escribir"))

    -- Las listas: las solicitudes y, al buscar, debajo, quién lo hace; en Buscar, los objetos (y quién lo hace uno, en su
    -- ventana: `parent`)
    local function MakeList(n, sortable, sfName, parent)
        local lst = { n = n, rows = {}, hdrCells = {}, sortable = sortable }
        local list = CreateFrame("Frame", nil, parent or body)
        lst.list = list
        lst.title = list:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lst.title:SetPoint("TOPLEFT", list, "TOPLEFT", 4, 0); lst.title:Hide()
        local hdr = CreateFrame("Frame", nil, list)
        hdr:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0); hdr:SetPoint("RIGHT", list, "RIGHT", 0, 0); hdr:SetHeight(HDR_H)
        local hline = hdr:CreateTexture(nil, "ARTWORK")
        hline:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35); hline:SetHeight(1)
        hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT")
        lst.hdr = hdr
        for i = 1, 7 do
            local b = CreateFrame("Button", nil, hdr)
            b:SetHeight(HDR_H)
            b:SetNormalFontObject("GameFontNormalSmall")
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06)
            b:SetScript("OnClick", function(s)
                local key = s.key
                -- (solo se ven los títulos de la vista, y Paint quita el orden de una columna que ya no está)
                if not sortable or not key then return end
                if sortKey == key then
                    if sortDesc then sortKey, sortDesc = nil, nil else sortDesc = true end
                else
                    sortKey, sortDesc = key, false
                end
                Paint()
            end)
            lst.hdrCells[i] = b
        end
        local sf = CreateFrame("ScrollFrame", sfName, list, "FauxScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -2); sf:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
        sf:SetHeight(n * ROW_H)
        sf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, Paint) end)
        lst.scroll = sf
        for i = 1, n do
            local row = CreateFrame("Button", nil, list)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * ROW_H); row:SetPoint("RIGHT", sf, "RIGHT", 0, 0)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.pickTex = row:CreateTexture(nil, "BORDER")
            row.pickTex:SetAllPoints(); row.pickTex:SetColorTexture(0.25, 0.55, 1, 0.28); row.pickTex:Hide()
            -- (una venta: un fondo suave de su color)
            row.saleTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
            row.saleTex:SetAllPoints(); row.saleTex:SetColorTexture(SALE_RGB[1], SALE_RGB[2], SALE_RGB[3], 0.10); row.saleTex:Hide()
            if i % 2 == 0 then
                local stripe = row:CreateTexture(nil, "BACKGROUND")
                stripe:SetAllPoints(); stripe:SetColorTexture(1, 1, 1, 0.05)
            end
            row.cells = {}
            for c = 1, 7 do
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetJustifyH("CENTER"); fs:SetWordWrap(false)
                row.cells[c] = fs
            end
            local itemBtn = CreateFrame("Button", nil, row)
            itemBtn:SetPoint("CENTER", row.cells[2], "CENTER"); itemBtn:SetHeight(ROW_H)
            itemBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            itemBtn:SetScript("OnClick", function(_, button)
                local link = row.entry and row.entry.item
                local h = link and link:match("|H(.-)|h")
                if h then SetItemRef(h, link, button) end
            end)
            itemBtn:SetScript("OnEnter", function(s)
                if view == "priv" and not Searching() then return end
                local link = row.entry and row.entry.item
                local h = link and link:match("|H(.-)|h")
                if h then GameTooltip:SetOwner(s, "ANCHOR_RIGHT"); pcall(GameTooltip.SetHyperlink, GameTooltip, h); GameTooltip:Show() end
            end)
            itemBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.itemBtn = itemBtn
            -- (Tablón, última columna: Aceptar / Me interesa / Cancelar, o el nombre de quien la aceptó. Aceptar, apagado si
            -- no puedo hacerla, con el porqué al pasar el ratón)
            local accept = Flat(row, L("Aceptar"), ACT_W, 20)
            accept:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            accept:SetScript("OnClick", function() if row.entry then Accept(row.entry) end end)
            accept:SetMotionScriptsWhileDisabled(true)
            accept:SetScript("OnEnter", WhyTip); accept:SetScript("OnLeave", function() GameTooltip:Hide() end)
            local actText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            actText:SetPoint("RIGHT", row, "RIGHT", -2, 0); actText:SetWidth(ACT_W); actText:SetJustifyH("CENTER")
            local cancel = Flat(row, L("Cancelar"), ACT_W, 20)
            cancel:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            cancel:SetScript("OnClick", function() if row.entry then Cancel(row.entry) end end)
            row.accept, row.cancel, row.actText = accept, cancel, actText
            -- (Mis encargos, en las abiertas: el tic acepta la que me piden a mí —apagado y gris si no puedo hacerla, con
            -- el porqué—; la X cancela la mía o rechaza la que me piden)
            local no = CreateFrame("Button", nil, row)
            no:SetSize(18, 18); no:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            no:SetNormalTexture(CROSS); no:SetHighlightTexture(CROSS, "ADD")
            no:SetScript("OnClick", function() if row.entry then Cancel(row.entry) end end)
            local yes = CreateFrame("Button", nil, row)
            yes:SetSize(18, 18); yes:SetPoint("RIGHT", no, "LEFT", -4, 0)
            yes:SetNormalTexture(TICK); yes:SetHighlightTexture(TICK, "ADD"); yes:SetDisabledTexture(TICK)
            local grey = yes:GetDisabledTexture()
            if grey then grey:SetDesaturated(true); grey:SetAlpha(0.35) end
            yes:SetScript("OnClick", function() if row.entry then Accept(row.entry) end end)
            yes:SetMotionScriptsWhileDisabled(true)
            yes:SetScript("OnEnter", WhyTip); yes:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.yes, row.no = yes, no
            -- (clic: elegirla; en Mis encargos, además, el chat pasa a ser el de esa persona. En la búsqueda, clic
            -- derecho: pedirle una receta)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(s, button)
                local r = s.entry
                if r and button == "RightButton" then return RowMenu(s, r) end
                if not (r and r.id) then return end
                local key = EntryKey(r)
                -- (en Mis encargos: Ctrl suma o quita; Mayús elige desde la última hasta esta; clic solo, solo esa)
                if view == "priv" and not Searching() then
                    if IsControlKeyDown() then
                        -- (la elegida con un clic solo también cuenta: si no, quedaba fuera de las marcadas)
                        if selected and selected ~= key and next(picks) == nil then
                            for _, x in ipairs(ui.lastList or {}) do if EntryKey(x) == selected then picks[selected] = true end end
                        end
                        picks[key] = (not picks[key]) or nil
                    elseif IsShiftKeyDown() and lastPick then
                        local a, b
                        for k, x in ipairs(ui.lastList or {}) do
                            if EntryKey(x) == lastPick then a = k end
                            if EntryKey(x) == key then b = k end
                        end
                        if a and b then
                            if a > b then a, b = b, a end
                            for k = a, b do picks[EntryKey(ui.lastList[k])] = true end
                        end
                    else
                        picks = {}
                    end
                    lastPick = key
                end
                selected = key
                if view == "priv" and not Searching() then
                    OpenChat(Other(r))
                end
                Paint()
            end)
            lst.rows[i] = row
        end
        lst.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        lst.empty:SetPoint("TOP", sf, "TOP", 0, -24); lst.empty:SetWidth(380)
        return lst
    end
    ui.req = MakeList(ROWS, true, "GuildUnionTradeScroll")
    ui.found = MakeList(ROWS, false, "GuildUnionTradeScroll2")
    ui.list, ui.scroll = ui.req.list, ui.req.scroll
    -- (Buscar: los objetos, con su enlace en la primera columna; sus clics y «Ver todos», en BuildWho)
    ui.items = MakeList(ROWS, false, "GuildUnionTradeScroll3")
    ui.items.itemCol = 1
    for _, row in ipairs(ui.items.rows) do
        row.itemBtn:ClearAllPoints(); row.itemBtn:SetPoint("CENTER", row.cells[1], "CENTER")
    end
    ui.items.list:Hide()
    BuildWho(host, MakeList)

    -- Abajo: «+ Nuevo anuncio», como hasta la copia 304 (teñido de verde, letra blanca), centrado debajo de la lista
    -- (Layout); va en el panel, para quedar encima de él [+ARCHITECTURE.md]
    local newDlg = BuildNewDialog(host)
    local new = Flat(bg, "+ " .. L("Nuevo anuncio"), 200, 24)
    new:SetPoint("BOTTOM", host, "BOTTOM", 0, 8)
    for _, k in ipairs({ "Left", "Middle", "Right" }) do if new[k] then new[k]:SetVertexColor(0.45, 1, 0.45) end end
    new:SetNormalFontObject("GameFontHighlight")
    -- (to: pedírsela a alguien en concreto, privada: «Pedir una receta» desde la búsqueda; item: lo que se pide (en
    -- Buscar, el objeto elegido). Con el comercio apagado no se abre)
    function ui.OpenNew(to, item)
        if HU:UnionCfg().tradeOff then return end
        pendingSubmit = nil
        newDlg.title:SetText(to and (L("Pedir una receta a ") .. HU:Short(to)) or L("Nuevo anuncio"))
        newDlg.item:SetText(item or ""); newDlg.to:SetText(to or ""); newDlg.qty:SetText("1")
        for _, box in ipairs(newDlg.coins) do box:SetText("") end
        newDlg.matsMe:SetChecked(true); newDlg.matsSeller:SetChecked(false)
        newDlg.kindAsk:SetChecked(true); newDlg.kindSell:SetChecked(false)
        newDlg.SetExpiry(EXPIRY_DEFAULT)
        newDlg.SetPub(not to and view ~= "priv")
        newDlg:Show(); newDlg.item:SetFocus()
    end
    new:SetScript("OnClick", function() ui.OpenNew(nil, view == "find" and FindLink() or nil) end)
    ui.new, ui.newDlg = new, newDlg
    -- (a su derecha, «Eliminar (N)», con algo marcado en Mis encargos: cabe antes del chat)
    local del = Flat(body, "", 80, 22)
    del:SetPoint("LEFT", new, "RIGHT", 6, 0)
    del:SetScript("OnClick", RemovePicked)
    del:Hide()
    ui.delBtn = del
    -- (lo que solo se ve con el comercio encendido: apagado, queda el panel con el aviso. La fila 2 va aparte: en Buscar
    -- lleva los filtros)
    ui.onlyOn = { body, sw, new }
    ui.row2 = { search, sbox, only }

    Suggest(ui.search, ItemMatches)
    -- (al abrirla: las solicitudes otra vez y lo que falte de toda la unión)
    host:HookScript("OnShow", function() LoadCraftNames(); netDirty = true; NeedAll(); Paint() end)
    LoadCraftNames()
    OpenChat(nil)
    Paint()
end

HU:Module("Trade", { "BlizzTab", "Config", "Core", "ListWindow", "Lists", "Net/Packs", "Net/Transport", "Packs/Professions", "Packs/Trade", "Protocol", "UnionConfig" })
