-- Guild Union - Comercio (la sección Trade de la lista de miembros): el estado, sin leer, el chat de cada encargo, la red,
-- las acciones de las solicitudes, el modo prueba y lo guardado; y todas las funciones de HU de Comercio [+ARCHITECTURE.md]
-- Los anuncios (pedir o vender) viajan a toda la unión con el conjunto TR (Packs/Trade.lua) y el chat de cada encargo, por
-- susurro (TC). HU:TradeTest (solo por código: las pruebas) la rellena de solicitudes y chats de mentira, que no viajan.
-- Lo demás, en TradeCraft.lua (objetos, fabricables, ¿puedo hacerlo?), TradeOrder.lua (la ventana de nuevo encargo),
-- TradeView.lua (lo que se ve, Paint y el montaje) y TradeFind.lua (la pestaña Buscar), con HU.TradeInternal (abajo).
-- Diseño: Obsidian/Addons/GuildUnion - Comercio (diseño).md
local _, HU = ...
local L = HU.L

-- (los chats con cada persona y lo sin leer, para que /reload no los borre: ver Tidy; las que quité de mi lista, las
-- privadas para mí ya avisadas y las líneas que esperan a que la otra persona se conecte. tradeReqs: las solicitudes de la
-- copia 324, que se proponen una vez, ver Migrate)
HU:Saved({ char = { tradeReqs = {}, tradeChats = {}, tradeUnread = {}, tradeClosed = {}, tradeSeen = {}, tradePending = {} } })

---------------------------------------------------------------------------
-- Lo que comparten los archivos de Comercio: una tabla privada del addon que crea este, el primero que carga. El estado
-- que cambia va en sus campos; las funciones que usan varios, también: cada archivo se copia al cargar las de los que van
-- antes, y las de los que van después (como T.Paint) las llama por la tabla [+ARCHITECTURE.md]
---------------------------------------------------------------------------
local T = {}
HU.TradeInternal = T
-- (lo que se ve: las de prueba y las de la red, juntas; se rehace con Merge)
T.reqs = {}             -- { id, who, item, sale, mats, tip, state = "open"|"taken"|"done"|"sold"|"gone", taker, buyers, pub, to, exp, t, test }
T.unread = {}           -- [persona] = sus líneas sin leer (llegadas con su chat fuera de la pantalla)
T.view = "pub"          -- "pub": el Tablón; "priv": Mis encargos; "find": Buscar
T.picks = {}            -- Mis encargos: las elegidas con Ctrl / Mayús (para eliminar varias)
T.netDirty = true       -- las de la red han cambiado (aviso «trade») o se abre la sección: se rehacen antes de usarlas
-- (y, vacíos al empezar: T.ui, la sección (HU:BuildTrade); T.chatKey, el chat que está puesto; T.selected, la fila
-- elegida (EntryKey); T.craftLoader, el que pide al juego los nombres de los fabricables (TradeCraft.lua))

-- (los colores y los iconos de todo Comercio: lo mío en azul, lo de otros en amarillo)
local MINE, OTHERS = "|cff4da6ff", "|cffffd100"
local GREY = "|cff9a8f78"
local DOT_ON = "|TInterface\\FriendsFrame\\StatusIcon-Online:10:10|t"
local DOT_OFF = "|TInterface\\FriendsFrame\\StatusIcon-Offline:10:10|t"
local COIN_ICON = { "Interface\\MoneyFrame\\UI-GoldIcon", "Interface\\MoneyFrame\\UI-SilverIcon", "Interface\\MoneyFrame\\UI-CopperIcon" }
T.MINE, T.OTHERS, T.GREY, T.DOT_ON, T.DOT_OFF, T.COIN_ICON = MINE, OTHERS, GREY, DOT_ON, DOT_OFF, COIN_ICON
T.GOLD = { 1, 0.82, 0.2 }
local testOnline = { ["Pepe-Prueba"] = true, ["Bea-Prueba"] = true, ["Lyra-Prueba"] = false, ["Jandra-Prueba"] = false }

local testReqs = {}         -- las de prueba (HU:TradeTest): solo en este PC
local netReqs = {}          -- las de la red (HU:TradeRequests, Packs/Trade.lua): se rehacen con Rebuild
local chats = {}            -- [persona] = { líneas }: uno por persona

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
local function Searching() return T.ui and HU.Trim(T.ui.search:GetText() or "") ~= "" end
-- (¿me toca a mí? la pedí yo, me la piden a mí, la hago yo o me interesa la venta)
local function Involved(r) return IsMine(r) or IsMe(r.to) or IsMe(r.taker) or (r.sale == true and Interested(r)) end
-- (caducado: un anuncio del tablón pasada su hora; ya no se ve en ninguna parte. Packs/Trade.lua tampoco lo publica)
local function Expired(r, now) return r.exp ~= nil and (now or HU.StampNow()) >= r.exp end
T.Me, T.IsMe, T.IsMine, T.NewId, T.Interested, T.Other, T.EntryKey, T.IdOf = Me, IsMe, IsMine, NewId, Interested, Other, EntryKey, IdOf
T.Plain, T.Coins, T.BuildOnline, T.Status, T.Dot, T.Searching, T.Involved, T.Expired = Plain, Coins, BuildOnline, Status, Dot, Searching, Involved, Expired

---------------------------------------------------------------------------
-- Sin leer: las líneas de otro que llegan con su chat fuera de la pantalla [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- (¿se ve ahora el chat con esa persona? la sección a la vista, en Mis encargos sin buscar y con su chat puesto)
local function ChatOnScreen(key)
    local ui = T.ui
    return ui ~= nil and key ~= nil and key == T.chatKey and T.view == "priv" and ui:IsVisible() and not Searching()
        and not HU:UnionCfg().tradeOff
end
-- Cuántas líneas hay sin leer, entre todos los chats (UnionRoster.lua hace brillar la pestaña de Comercio)
function HU:TradeUnread()
    local n = 0
    for _, c in pairs(T.unread) do n = n + c end
    return n
end
-- Cuántos chats (personas) tienen algo sin leer: el número de la pestaña de Comercio, del botón de hermandad del juego
-- y de «Mis encargos» (Jorge, 25/11: «con el número de chats sin leer»). Avisa con HU:Changed("tradeUnread")
function HU:TradeUnreadChats()
    local n = 0
    for _, c in pairs(T.unread) do if c > 0 then n = n + 1 end end
    return n
end
-- (la pestaña Mis encargos, con el número: «Mis encargos (2)»)
local function PaintUnread()
    local b = T.ui and T.ui.viewBtns and T.ui.viewBtns.priv
    if not b then return end
    local n = HU:TradeUnreadChats()
    b:Label(n > 0 and string.format(L("Mis encargos (%d)"), n) or L("Mis encargos"))
end
local function MarkRead(key)
    if not (key and T.unread[key]) then return end
    T.unread[key] = nil
    PaintUnread()
    HU:Changed("tradeUnread")
end
-- (detrás del nombre en Mis encargos: cuántas suyas hay sin leer)
local function UnreadMark(key)
    local n = key and T.unread[key]
    return n and (" |cff40ff40(" .. n .. ")|r") or ""
end
T.ChatOnScreen, T.PaintUnread, T.MarkRead, T.UnreadMark = ChatOnScreen, PaintUnread, MarkRead, UnreadMark

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
    local ui = T.ui
    if key == T.chatKey and ui then ui.msgs:AddMessage(line) end
    -- (de otro y con su chat fuera de la pantalla: sin leer; nunca más de las que guarda el chat)
    if not IsMe(who) and not ChatOnScreen(key) then
        T.unread[key] = math.min(#l, (T.unread[key] or 0) + 1)
        if ui then ui.rerank = true end
        PaintUnread()
        HU:Changed("tradeUnread")
    end
end
-- Una línea en el chat con `key` desde fuera (las pruebas); las que llegan por la red entran por la orden TC, abajo
function HU:TradeChatLine(key, who, text) ChatLine(key, who, text) end

local function OpenChat(key)
    T.chatKey = key
    local ui = T.ui
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
T.ChatLine, T.OpenChat = ChatLine, OpenChat

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
    local all = {}
    for _, r in ipairs(testReqs) do all[#all + 1] = r end
    for _, r in ipairs(netReqs) do all[#all + 1] = r end
    T.reqs = all
end

-- (el anuncio entre los dos que se ve en Mis encargos, ni cancelado ni quitado de mi lista, y el nombre de su chat: en
-- una venta mía, el interesado que es)
local function Between(name)
    local reqs = T.reqs
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
    T.netDirty, builtTag = false, HU.myTag
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
local function Fresh() if T.netDirty or builtTag ~= HU.myTag then Rebuild() end end
-- (con el aviso «trade»: se juntan los de un momento —un paquete llega en varios trozos— y se pinta si se ve)
local rebuildQueued
local function MarkDirty()
    T.netDirty = true
    if T.ui then T.ui.rerank = true end
    if rebuildQueued then return end
    rebuildQueued = true
    HU.After(1, function()
        rebuildQueued = nil
        if not T.netDirty then return end
        Rebuild()
        T.Paint()
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
T.Fresh, T.NeedAll, T.SendChat = Fresh, NeedAll, SendChat
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
-- Solicitudes: sus acciones (los botones de cada fila, «Hecha» y el clic derecho: TradeView.lua)
---------------------------------------------------------------------------
-- (una solicitud por su id; Live: la de ahora, por si la fila se pintó antes de que llegara un cambio)
local function FindReq(id) for _, r in ipairs(T.reqs) do if r.id == id then return r end end end
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
    T.Paint()
end
-- La X: mía, cancelarla (una venta, eliminarla); de otro (privada, me la piden a mí), rechazarla
local function Cancel(r)
    r = Live(r)
    if r.state == "done" or r.state == "sold" or not (IsMine(r) or IsMe(r.to)) then return end
    if r.test then r.state = "gone"
    elseif IsMine(r) then HU:TradeCancel(r)
    else HU:TradeAnswer(r.id, "r") end
    T.selected = nil
    T.Paint()
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
    for key in pairs(T.picks) do
        local id = IdOf(key)
        local x = not done[id] and FindReq(id)
        if x then done[id] = true; RemoveReq(x) end
    end
    T.picks, T.selected = {}, nil
    T.Paint()
end
-- «Hecha»: solo quien la hace (quien la aceptó) y mientras está aceptada
local function CanMarkDone(r) return r ~= nil and r.state == "taken" and IsMe(r.taker) end
local function MarkDone(r)
    r = r and Live(r)
    if not CanMarkDone(r) then return end
    if r.test then r.state = "done" else HU:TradeAnswer(r.id, "d") end
    T.Paint()
end
-- «Vendida»: solo quien vende y mientras sigue a la venta; deja de estar abierta para todos
local function CanMarkSold(r) return r ~= nil and r.sale == true and r.state == "open" and IsMine(r) end
local function MarkSold(r)
    r = r and Live(r)
    if not CanMarkSold(r) then return end
    if r.test then r.state, r.soldAt = "sold", HU.StampNow() else HU:TradeSold(r) end
    T.Paint()
end
T.FindReq, T.Accept, T.Cancel, T.RemoveReq, T.RemovePicked = FindReq, Accept, Cancel, RemoveReq, RemovePicked
T.CanMarkDone, T.MarkDone, T.CanMarkSold, T.MarkSold = CanMarkDone, MarkDone, CanMarkSold, MarkSold

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
    for key in pairs(T.unread) do if key:find("%-Prueba$") then T.unread[key] = nil; had = true end end
    if T.chatKey and T.chatKey:find("%-Prueba$") then OpenChat(nil) end
    T.selected, T.picks = nil, {}
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
        local it = T.ItemInfo(id)
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
    T.Paint()
end

-- Poner (on) o quitar lo de prueba
function HU:TradeTest(on)
    if on then AddTest() else ClearTest(); T.Paint() end
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
    for key in pairs(T.unread) do if key:find("%-Prueba$") or not chats[key] then T.unread[key] = nil end end
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
    elseif what == "professions" and not foundQueued and T.ui and T.ui:IsVisible()
        and (Searching() or T.view == "find" or T.ui.who:IsShown()) then
        foundQueued = true
        HU.After(2, function()
            foundQueued = nil
            if T.ui:IsVisible() then T.Paint() end
        end)
    end
end)
HU:OnStart(function()
    chats, T.unread = HU.db.tradeChats, HU.db.tradeUnread
    Tidy()
    Migrate()
    T.netDirty = true
    HU:Changed("tradeUnread")
    HU:Every(30, "Comercio: chat pendiente", Repaso)
    -- (con la sección a la vista, cada minuto: lo que falte de las solicitudes, y se repinta (lo que le queda a cada
    -- anuncio; lo caducado se va))
    HU:Every(60, "Comercio: al día", function()
        if T.ui and T.ui:IsVisible() then NeedAll(); T.Paint() end
    end)
end)
HU:On("PLAYER_LOGOUT", Tidy)

---------------------------------------------------------------------------
-- Las funciones de HU de lo que va en los otros archivos de Comercio: todas están aquí, para que lo de fuera (UnionRoster.lua)
-- solo necesite este archivo y un cambio por dentro no cambie su HU:Module [+ARCHITECTURE.md]
---------------------------------------------------------------------------
-- Las profesiones de alguien de mi hermandad, de su ficha en la comunidad (TradeCraft.lua)
function HU:ClubProfessions(info) return T.ClubProfessions(info) end
-- Si puedo hacer lo que pide `item` (un enlace o lo escrito): ok y, si no, el porqué (TradeCraft.lua)
function HU:CanCraft(item) return T.CraftCheck(item, T.MyProfessions()) end
-- Montar la sección (UnionRoster.lua la pone en la pestaña Trade): TradeView.lua
function HU:BuildTrade(host) T.Build(host) end

HU:Module("Trade", { "Config", "Core", "Lists", "Net/Packs", "Net/Transport", "Packs/Professions", "Packs/Trade", "Protocol", "UnionConfig" })
