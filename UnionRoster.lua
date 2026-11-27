-- Guild Union - secciones de la lista de miembros del juego: Miembros (todos los de la unión), Comercio y Eventos (pestañas de la derecha) [+ARCHITECTURE.md]
local ADDON_NAME, HU = ...
local L = HU.L
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
-- (unionRosterOff: la casilla «GuildUnion» de antes, que ya no está: se borra; unionRosterMine: «Solo mi hermandad»)
HU:Saved({ account = { "unionRosterOff", "unionRosterMine" } })

local ROW_H, ROWS = 18, 40
local TAB_H, HDR_H = 34, 24
local TRADE_ROCK = 72   -- (lo gris de arriba, en Comercio: hasta su panel; ver Layout)
local TOP = 26   -- cuánto sube por encima de la lista del juego: tapa sus títulos, no la casilla ni el buscador
-- (la franja de arriba, TAB_H, va justo debajo de la barra del título: lo nuestro sube ROW_UP más, y ahí queda lo del
-- juego en su sitio (buscador, casillas, cascos, «en línea»): DROP = 0. Antes había ahí una fila de botones redondos, que
-- se quitó al llevar Comercio y Calendario a otro sitio: hoy, pestañas de la derecha. Jorge, 24/11) [+ARCHITECTURE.md]
local ROW_UP, DROP = 31, 0
-- (vista de chat: la piedra de la franja baja INSET_EDGE más y tapa el borde de arriba del fondo del juego; el chat y su
-- lista empiezan justo debajo, y sus bordes empiezan 7 y 3 por encima de ellos) [+ARCHITECTURE.md]
local INSET_EDGE = 3
local CHAT_EDGE, LIST_EDGE = 7, 3
-- (Comercio y Eventos, pestañas de la derecha como las del juego (RightSideTabTemplate): de su tamaño y a su distancia)
local SIDE_TAB, SIDE_TAB_GAP = 32, 20
-- (la barra de la columna de comunidades: el juego la pone 45 por debajo de la columna; con lo nuestro, arriba del todo)
local LIST_BAR_Y, LIST_BAR_Y_GAME = -3, -45
-- (la franja de esa barra, entre la columna y lo nuestro: toda oscura, de arriba abajo, con la barra por encima; mide
-- STRIP_W, y en los 4 que quedan hasta lo nuestro empieza el borde del chat, que no se tapa) [+ARCHITECTURE.md]
local STRIP, STRIP_W = 23, 19
local ONLINE_FRESH = 120 -- la lista de conectados de otra hermandad (Miembros) vale para saber quién no está
-- (columnas como las del juego, más «Hermandad»; ancho 0 = hasta el borde)
local COLS = {
    -- (game: el título del propio juego, en su idioma y corto, como en su lista; si no está, el nuestro)
    { key = "level", title = "Nivel", game = "COMMUNITIES_ROSTER_COLUMN_TITLE_LEVEL", w = 34 },
    { key = "class", title = "Clase", game = "COMMUNITIES_ROSTER_COLUMN_TITLE_CLASS", w = 45 },
    { key = "name", title = "Nombre", game = "COMMUNITIES_ROSTER_COLUMN_TITLE_NAME", w = 105 },
    { key = "zone", title = "Zona", game = "COMMUNITIES_ROSTER_COLUMN_TITLE_ZONE", w = 92 },
    { key = "rank", title = "Rango", game = "COMMUNITIES_ROSTER_COLUMN_TITLE_RANK", w = 76 },
    { key = "guild", title = "Hermandad", game = "GUILD", w = 58 },
    -- (las dos profesiones, solo su icono, juntos (Jorge, 24/11: «júntalos y haz esa pestaña más pequeña»): título corto,
    -- que «Profesiones» no cabe; sin punto (Jorge, 25/11). Solo las de mi hermandad, que son las que da el juego)
    { key = "prof", title = "Prof", w = 40 },
    { key = "note", title = "Nota", game = "COMMUNITIES_ROSTER_COLUMN_TITLE_NOTE", w = 0 },
}
-- (cada sección con su imagen: Miembros, la del icono de miembros del juego; Comercio, el martillo de herrería;
-- Eventos, la nuestra del calendario (Media))
local TABS = {
    { title = "Miembros", icon = "Interface/Icons/achievement_guildperk_everybodysfriend" },
    -- (side: su nombre en la pestaña de la derecha, si no es el mismo. Jorge, 24/11: «se llama professions & trade»)
    { title = "Comercio", side = "Profesiones y comercio", trade = true, icon = "Interface/Icons/Trade_BlackSmithing" },
    -- (Jorge, 25/11: «cambiar el nombre de calendario a eventos»; dentro siguen las vistas Eventos y Calendario)
    { title = "Eventos", calendar = true, icon = MEDIA .. "boton-calendario" },
}
local tab = 1          -- 0 = Chat (solo en la vista de chat); 1 = Miembros; 2-4 = Comercio, Eventos y Banco
local mode             -- "roster" (vista de miembros del juego) o "chat" (vista de chat); nil = otra
local wantTab          -- la sección pulsada desde la vista de chat: se abre al llegar a la de miembros
local sortKey, sortDesc   -- nil: rango y luego nivel
local cover, mine
local SyncNow          -- (la de Build: vuelve a mirar la vista y coloca lo nuestro)
-- «Solo mi hermandad» en Miembros: lo nuestro se quita y queda la lista del juego, tal cual. Al pinchar en alguien sale
-- su ficha, la única con la que el juego deja guardar notas (a un addon, nunca) [+ARCHITECTURE.md]
local function RealList() return mode == "roster" and tab == 1 and HU.db.unionRosterMine == true end
-- (los elegidos con clic, Mayús y Ctrl, por nombre en minúsculas; shown: la lista entera, en su orden)
local sel, anchorKey, shown = {}, nil, {}
local notes, notesDirty = {}, true
-- (la lista entera se rehace solo si cambia algo de lo que la forma: ver Paint. listDirty, por un aviso de que ha cambiado)
local listDirty, lastSig = true, nil
local LIST_EVERY = 30   -- (y como mucho cada tantos segundos, por lo que caduca con el tiempo: quién sigue conectado)

local function Win() return _G.CommunitiesFrame end

local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "ffffff"
end

-- (cuánto lleva desconectado: «hace 3 d»)
local function Ago(secs)
    if not secs then return "—" end
    local d, h = math.floor(secs / 86400), math.floor((secs % 86400) / 3600)
    if d > 0 then return string.format(L("hace %d d"), d) end
    if h > 0 then return string.format(L("hace %d h"), h) end
    return L("hace menos de 1 h")
end

-- Notas públicas de mi hermandad (las de las otras no llegan): se leen al cambiar la lista del juego
local offNotes = {}
local function ReadNotes()
    notesDirty = false
    notes, offNotes = {}, {}
    local n = GetNumGuildMembers and GetNumGuildMembers() or 0
    if type(n) ~= "number" or HU.Secret(n) then return end
    for i = 1, n do
        local name, _, _, _, _, _, note, offNote = GetGuildRosterInfo(i)
        local full = type(name) == "string" and not HU.Secret(name) and HU:FullName(name)
        if full then
            if type(note) == "string" and note ~= "" and not HU.Secret(note) then notes[full:lower()] = note end
            -- (la de oficial solo llega si puedes verla; las líneas de configuración del addon no se enseñan)
            if type(offNote) == "string" and offNote ~= "" and not HU.Secret(offNote) then
                offNotes[full:lower()] = offNote:find("GU:", 1, true) and L("(configuración de GuildUnion)") or offNote
            end
        end
    end
end

-- Profesiones de mi hermandad (las da el juego por su comunidad: de las otras no llegan), para la columna: se leen al
-- cambiar la lista del juego, como mucho cada PROF_EVERY segundos (son cientos de miembros) [+ARCHITECTURE.md]
local PROF_EVERY = 30
local profCache, profsDirty, profsAt = {}, true, nil
local function ReadProfs()
    local now = GetTime()
    if profsAt and now - profsAt < PROF_EVERY then return end
    profsDirty, profsAt = false, now
    local cid = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not cid or HU.Secret(cid) then return end
    local ok, ids = pcall(C_Club.GetClubMembers, cid)
    if not ok or type(ids) ~= "table" then return end
    local out = {}
    for _, id in ipairs(ids) do
        local ok2, info = pcall(C_Club.GetMemberInfo, cid, id)
        local n = ok2 and type(info) == "table" and info.name
        if type(n) == "string" and not HU.Secret(n) then
            -- (el nivel: el mío, de mi personaje; el de los demás, la comunidad de Forever no lo da: Trade.lua)
            local list = HU:ClubProfessions(info)
            if #list > 0 then out[(HU:FullName(n) or n):lower()] = list end
        end
    end
    profCache = out
end

local function ShowOffline()
    local f = Win()
    local b = f and f.MemberList and f.MemberList.ShowOfflineButton
    return b and b:GetChecked() and true or false
end

local SORT = {
    level = function(e) return e.level or 0 end,
    class = function(e) return e.class or "" end,
    name = function(e) return e.k end,
    zone = function(e) return e.online == false and string.format("~%012d", e.offSecs or 0) or (e.zone or ""):lower() end,
    rank = function(e) return e.ri or 99 end,
    guild = function(e) return tostring(e.tag or "") end,
    prof = function(e) return (e.prof and e.prof[1] and e.prof[1].name or "~"):lower() end,
    note = function(e) return (e.note or ""):lower() end,
}
-- Por defecto: rango de hermandad, nivel (de mayor a menor) y nombre, todas las hermandades mezcladas. (k: el nombre en
-- minúsculas, una vez por fila: pasarlo a minúsculas en cada comparación era lo que más tardaba al ordenar miles)
local function Less(a, b)
    if sortKey then
        local va, vb = SORT[sortKey](a), SORT[sortKey](b)
        if va ~= vb then if sortDesc then return va > vb end return va < vb end
    end
    if a.ri ~= b.ri then return a.ri < b.ri end
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    return a.k < b.k
end

-- Todos: los conectados de la unión y, con la casilla del juego marcada, los desconectados de mi hermandad
local function Entries()
    if notesDirty then ReadNotes() end
    if profsDirty then ReadProfs() end
    local list = HU:UnionRosterEntries()
    if ShowOffline() then
        for _, e in ipairs(HU.rosterList) do
            if not e.online and e.name then
                list[#list + 1] = { name = e.name, k = e.name:lower(), tag = HU.myTag, class = e.class, level = e.level, zone = e.zone,
                    ri = e.rankIndex or 99, rank = e.rank or "", online = false, own = true, offSecs = e.offSecs }
            end
        end
    end
    -- Las listas que las otras hermandades mandan solas (RB: maestro, oficiales, enlace y ayudantes, con su
    -- rango): son las de «Oficiales conectados» y siempre están al día. Ponen el rango a quien llegó sin
    -- él (del /who) y añaden a quien falte (Jorge, 23/11)
    local byKey = {}
    for _, e in ipairs(list) do byKey[e.k] = e end
    for _, tag in ipairs(HU:OtherTags()) do
        local r = HU.remoteRoster and HU.remoteRoster[tag]
        for _, m in ipairs(r and r.members or {}) do
            if m.online and m.name and m.rankIndex then
                local rank = (m.rank and m.rank ~= "") and m.rank or HU:RankName(tag, m.rankIndex) or ""
                local k = m.name:lower()
                local have = byKey[k]
                if have then
                    if (have.ri or 99) >= 99 then have.ri, have.rank = m.rankIndex, rank end
                else
                    local e = { name = m.name, k = k, tag = tag, class = m.class, level = m.level, zone = m.zone, afk = m.afk,
                        ri = m.rankIndex, rank = rank, online = true }
                    list[#list + 1] = e
                    byKey[k] = e
                end
            end
        end
    end
    -- Con la casilla de desconectados: la lista completa de las otras hermandades, de su paquete MB [+ARCHITECTURE.md]
    -- (Packs/Members.lua), que se pide al mirarla. Si la lista de conectados de esa hermandad está al día,
    -- quien no sale en ella está desconectado; si no, no se sabe y sale «?»
    if ShowOffline() then
        for _, tag in ipairs(HU:OtherTags()) do
            HU:PackNeed(tag, "MB")
            local st = HU.unionMembers[tag]
            local known = st and st.members and st.t and GetTime() - st.t < ONLINE_FRESH
            for _, m in ipairs(HU:PackedMembers(tag)) do
                local k = m.name:lower()
                if not byKey[k] then
                    local e = { name = m.name, k = k, tag = tag, class = m.class, level = m.level, ri = m.rankIndex,
                        rank = (m.rankIndex and HU:RankName(tag, m.rankIndex)) or "", online = false, unknown = not known }
                    list[#list + 1] = e
                    byKey[k] = e
                end
            end
        end
    end
    -- (los que llegan sin rango, del /who, van con el rango más bajo de mi hermandad: así se mezclan
    -- por nivel con los demás en vez de quedarse todos juntos al final)
    local low = 0
    for _, e in ipairs(list) do
        if e.own and (e.ri or 99) < 99 and e.ri > low then low = e.ri end
    end
    for _, e in ipairs(list) do
        if (e.ri or 99) >= 99 then e.ri, e.noRank = low, true end
        if e.own then e.note, e.offNote, e.prof = notes[e.k], offNotes[e.k], profCache[e.k] end
    end
    table.sort(list, Less)
    return list
end

-- (lo que forma la lista: si no ha cambiado nada, no se rehace. Rehacerla cada 2 s con 4 hermandades de 600 y los
-- desconectados eran 16 ms y 2,4 MB de basura cada vez; Jorge, 24/11: «hasta un 5 % de procesador») [+ARCHITECTURE.md]
local function ListSig()
    local parts = { tostring(HU.rosterVersion), ShowOffline() and "o" or "-", tostring(sortKey), sortDesc and "d" or "a",
        math.floor(GetTime() / LIST_EVERY) }
    for _, t in ipairs(HU:OtherTags()) do
        local st, rr = HU.unionMembers[t], HU.remoteRoster and HU.remoteRoster[t]
        -- (y lo que va llegando de su lista completa, el paquete MB)
        local got, total = HU:PackProgress(t, "MB")
        parts[#parts + 1] = table.concat({ t, tostring(st and st.t), tostring(st and st.cur and st.cur.got),
            tostring(st and st.who and st.who.t), tostring(rr), tostring(got), tostring(total) }, ":")
    end
    return table.concat(parts, "|")
end

-- Las filas que caben: las demás, con la barra
local function Paint()
    if not (cover and cover:IsShown() and tab == 1) then return end
    HU:WantUnionMembers(nil)
    -- (la huella, después de rehacerla: Entries también quita lo que ha caducado)
    if listDirty or ListSig() ~= lastSig then
        shown = Entries()
        listDirty, lastSig = false, ListSig()
    end
    local list = shown
    local sf = cover.scroll
    local visible = ROWS
    local h = sf:GetHeight()
    if type(h) == "number" and h > 0 then visible = math.max(1, math.min(ROWS, math.floor(h / ROW_H))) end
    FauxScrollFrame_Update(sf, #list, visible, ROW_H)
    local off = FauxScrollFrame_GetOffset(sf)
    local online = 0
    for _, e in ipairs(list) do if e.online then online = online + 1 end end
    for i = 1, ROWS do
        local row, e = cover.rows[i], i <= visible and list[off + i] or nil
        row.entry = e
        if e then
            local c = row.cells
            local dim = not e.online
            row.selTex:SetShown(sel[e.name:lower()] == true)
            c.level:SetText((e.level and e.level > 0) and tostring(e.level) or "")
            local tc = e.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[e.class]
            if tc then c.class:SetTexCoord(unpack(tc)); c.class:Show() else c.class:Hide() end
            c.class:SetDesaturated(dim)
            c.name:SetText(dim and ("|cff808080" .. HU:Nice(e.name) .. "|r") or ("|cff" .. ClassHex(e.class) .. HU:Nice(e.name) .. "|r"))
            -- (detrás del nombre, corona para el maestro y espadas para el admin (rojas) y el oficial, como en
            -- la pestaña; sin rango sabido, nada. Es una imagen aparte, pegada al final del nombre: con el
            -- nombre recortado sigue viéndose)
            local role = not e.noRank and HU:RoleOf(e.name, e.tag, e.ri) or nil
            local ri = c.rankIcon
            if role then
                if role == "gm" then
                    ri:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon"); ri:SetTexCoord(0, 1, 0, 1); ri:SetVertexColor(1, 1, 1)
                else
                    ri:SetTexture("Interface\\CharacterFrame\\UI-StateIcon"); ri:SetTexCoord(34 / 64, 62 / 64, 2 / 64, 30 / 64)
                    if role == "admin" then ri:SetVertexColor(unpack(HU.ADMIN_COLOR)) else ri:SetVertexColor(1, 1, 1) end
                end
                local w = c.name:GetStringWidth()
                w = (type(w) == "number" and w > 0) and math.min(w, c.nameMax) or 0
                ri:ClearAllPoints(); ri:SetPoint("LEFT", c.name, "LEFT", w + 2, 0)
                ri:SetDesaturated(dim)
                ri:Show()
            else
                ri:Hide()
            end
            -- (desconectado: en vez de la zona, cuánto lleva desconectado)
            if e.online == false then c.zone:SetText(e.unknown and "|cffb0b0b0?|r" or ("|cff9d9d9d" .. Ago(e.offSecs) .. "|r"))
            else c.zone:SetText((e.zone or "") .. (e.afk and (" |cff808080(" .. L("Ausente") .. ")|r") or "")) end
            c.rank:SetText(e.rank or "")
            -- (la etiqueta de la hermandad, corta; el nombre entero, en la barra de abajo y en el menú)
            c.guild:SetText("|cff" .. HU:GuildColorHex(e.tag) .. tostring(HU:TagLabel(e.tag) or "") .. "|r")
            c.note:SetText(e.note or "")
            -- (profesiones: solo el icono (Jorge, 24/11: «esta pestaña sin niveles»: de los demás, Forever no los da); los
            -- nombres y el nivel, en la ficha)
            for j = 1, 2 do
                local icon, p = c.prof[j], e.prof and e.prof[j]
                if p then
                    icon:SetTexture(p.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    icon:SetDesaturated(dim)
                    icon:Show()
                else
                    icon:Hide()
                end
            end
            for _, k in ipairs({ "level", "zone", "rank", "note" }) do c[k]:SetAlpha(dim and 0.5 or 1) end
            row:Show()
        else
            row:Hide()
        end
    end
    -- (abajo: cuántos y cómo va la lista de cada hermandad)
    local parts = { string.format(L("%d conectados"), online) }
    for _, t in ipairs(HU:OtherTags()) do
        local s = HU:UnionMembersStatus(t)
        -- (con desconectados: cuánto ha llegado de su lista completa, mientras llega)
        local got, total = HU:PackProgress(t, "MB")
        if ShowOffline() and got and got < total then
            s = (s ~= "" and (s .. ", ") or "") .. string.format(L("lista completa %d/%d"), got, total)
        end
        if s ~= "" then parts[#parts + 1] = "|cff" .. HU:GuildColorHex(t) .. t .. "|r " .. s end
    end
    cover.status:SetText(table.concat(parts, "  ·  "))
end

-- Un clic del jugador aquí (títulos, filas, la rueda, la barra de la lista y sus flechas): el único momento en que
-- el juego deja hacer /who (UnionMembers.lua). No con OnVerticalScroll: salta también cuando la lista se recoloca
-- sola (al pintarla o cambiar de tamaño), sin clic
-- (nunca mientras colocamos la ventana: si el cambio de vista viene de un botón seguro del juego, el /who
-- queda dentro de su clic y el juego lo bloquea: ADDON_ACTION_BLOCKED, visto el 23/11)
-- (tampoco con los botones de arriba: «Miembros» lo pedía al volver de Comercio y el juego lo bloqueó, 24/11)
local inSync = false
local function WhoTick()
    if inSync or InCombatLockdown() then return end
    if cover and cover:IsShown() and tab == 1 and HU:UnionWhoTick(nil) then Paint() end
end

-- (en la vista de chat, sin la raya de arriba del chat ni de su lista (Jorge, 24/11): la piedra llega hasta ellos, como
-- en Miembros. Solo transparente: el borde es del juego) [+ARCHITECTURE.md]
local boxTopsShown = true
local function BoxTops(f, show)
    if show == boxTopsShown or not f then return end
    boxTopsShown = show
    for _, box in ipairs({ f.Chat, f.MemberList }) do
        local inset = type(box) == "table" and type(box.InsetFrame) == "table" and box.InsetFrame or nil
        local ns = inset and type(inset.NineSlice) == "table" and inset.NineSlice or nil
        if ns then
            for _, k in ipairs({ "TopEdge", "TopLeftCorner", "TopRightCorner" }) do
                if type(ns[k]) == "table" then ns[k]:SetAlpha(show and 1 or 0) end
            end
        end
    end
end

-- Dónde va lo nuestro: en la vista de miembros, encima de su lista; en la de chat, solo la franja de arriba (el chat del
-- juego se ve debajo)
local function Layout()
    local f = Win()
    local ml = f and f.MemberList
    if not (cover and ml) then return end
    local chatMode = mode == "chat" and f.Chat ~= nil
    cover:ClearAllPoints()
    if chatMode then
        -- (justo debajo de la barra del título, de la columna de comunidades (+23) al borde de la ventana (-4); atado a la
        -- columna y no al chat, que va debajo de la franja: ver Sync)
        cover:SetPoint("TOPLEFT", f.CommunitiesList, "TOPRIGHT", 23, -34 + ROW_UP)
        local clRight, fRight = f.CommunitiesList:GetRight(), f:GetRight()
        local dx = (type(clRight) == "number" and type(fRight) == "number") and (fRight - clRight - 4) or 640
        cover:SetPoint("TOPRIGHT", f.CommunitiesList, "TOPRIGHT", dx, -34 + ROW_UP)
        cover:SetHeight(TAB_H)
    else
        cover:SetPoint("TOPLEFT", ml, "TOPLEFT", -3, TOP + ROW_UP)
        -- (hasta 22 más a la derecha: tapa también la barra de la lista del juego, que se veía al lado de la nuestra)
        cover:SetPoint("BOTTOMRIGHT", ml, "BOTTOMRIGHT", 22, 0)
    end
    -- (en la vista de chat los clics pasan al chat del juego; la piedra de la franja es la de abajo, cover.band, que va
    -- debajo de lo del juego (cascos, «en línea»): la de lo nuestro, en la capa HIGH, lo taparía)
    cover:EnableMouse(tab ~= 0)
    cover.rock:SetShown(not chatMode)
    -- (en Comercio, hasta su panel: sus dos filas de arriba, botones y buscador, quedan enteras sobre lo gris (Jorge,
    -- 24/11: «más grande lo gris claro de arriba»). Su panel empieza 72 por debajo de lo nuestro: 2 de la sección y 70
    -- de su BODY_Y + 4, Trade.lua)
    local rockH = (tab == 2) and TRADE_ROCK or (TAB_H + HDR_H)
    cover.rock:SetHeight(rockH)
    -- (el fondo oscuro, desde donde acaba lo gris: van en la misma capa y el oscuro, creado después, lo tapaba; en la 318
    -- Comercio seguía con la franja oscura encima de su panel. Jorge, 24/11: «esto sigue por debajo, revísalo bien»)
    cover.dark:ClearAllPoints()
    cover.dark:SetPoint("TOPLEFT", cover, "TOPLEFT", 0, -rockH)
    cover.dark:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", 0, 0)
    cover.dark:SetShown(tab ~= 0)
    if cover.band then cover.band:SetShown(chatMode) end
    BoxTops(f, not chatMode)
end

-- (la casilla «Mostrar desconectados» del juego solo pinta algo en Miembros: en Comercio y Calendario, ni se ve ni se
-- pulsa (Jorge, 24/11). Solo sus dibujos y su texto: de ella cuelgan nuestros botones seguros y los de abajo, que siguen)
-- [+ARCHITECTURE.md]
local offlineShown, offlineMouse = true, true
local function OfflineBox(show)
    local f = Win()
    local b = f and f.MemberList and f.MemberList.ShowOfflineButton
    if type(b) ~= "table" then return end
    if show ~= offlineShown then
        offlineShown = show
        for _, r in ipairs({ b:GetRegions() }) do r:SetAlpha(show and 1 or 0) end
    end
    -- (que se pulse o no, solo fuera de combate: como de ella cuelgan botones seguros, en combate el juego no deja
    -- tocarla (ADDON_ACTION_BLOCKED con CheckButton:EnableMouse, Jorge, 25/11). Al salir, otra vez)
    if show ~= offlineMouse and not InCombatLockdown() then
        offlineMouse = show
        b:EnableMouse(show)
    end
end
HU:On("PLAYER_REGEN_ENABLED", function() OfflineBox(offlineShown) end)

-- (marcada, la pestaña de la derecha de la sección abierta. En Comercio y Calendario, la de miembros del juego no: el
-- juego la vuelve a marcar cada vez que pone al día sus pestañas, y se le quita otra vez (Build). Marcar no es mover ni
-- esconder: vale también en combate) [+ARCHITECTURE.md]
local function CheckTabs()
    local f = Win()
    for _, b in ipairs(cover and cover.side and cover.side.tabs or {}) do b:SetChecked(mode == "roster" and b.tab == tab) end
    if mode == "roster" and f and type(f.RosterTab) == "table" then f.RosterTab:SetChecked(tab <= 1) end
    -- (y la de chat del juego, marcada solo en la vista de chat: Jorge, 24/11, al pasar de Chat a Miembros se le quedaba
    -- marcada. El juego la desmarca al poner al día sus pestañas; esto lo asegura)
    if mode and f and type(f.ChatTab) == "table" then f.ChatTab:SetChecked(mode == "chat") end
end

local function ShowTab(i)
    tab = i
    CheckTabs()
    if RealList() then
        -- (Miembros con «Solo mi hermandad»: la lista del juego; lo nuestro, fuera. La casilla sigue, para volver)
        cover:Hide()
        if mine then mine:Show() end
        return
    end
    cover.tabs.selectedTab = i
    local members = i == 1
    cover.hdr:SetShown(members); cover.scroll:SetShown(members); cover.status:SetShown(members)
    for _, row in ipairs(cover.rows) do if not members then row:Hide() end end
    -- (Comercio: su sección, Trade.lua)
    cover.trade:SetShown(i > 0 and TABS[i].trade == true)
    cover.calendar:SetShown(i > 0 and TABS[i].calendar == true)
    -- (el «Buscar personaje» de arriba, solo en Chat y Miembros)
    HU.charSearchOff = i >= 2
    HU.SyncCharSearch()
    if mine then mine:SetShown(i == 1) end
    OfflineBox(i <= 1)
    Layout()
    Paint()
end

-- La ficha de un miembro (clic izquierdo en Miembros): como la del juego, pero nuestra, para todas las
-- hermandades. La del juego no se abre desde aquí: abierta por un addon, el juego bloquearía sus botones
-- (expulsar, rango, notas) [+ARCHITECTURE.md]
local card
local RemoveFromGuild   -- (más abajo, con el clic derecho; lo usa también el botón de la ficha)

-- (el GUID de alguien de mi hermandad en la lista del juego: el 17.º dato de GetGuildRosterInfo)
local function RosterGuid(name)
    local want = (HU:FullName(name) or name):lower()
    local n = GetNumGuildMembers and GetNumGuildMembers() or 0
    if type(n) ~= "number" or HU.Secret(n) then return nil end
    for i = 1, n do
        local r = { GetGuildRosterInfo(i) }
        local full = type(r[1]) == "string" and not HU.Secret(r[1]) and HU:FullName(r[1])
        if full and full:lower() == want then
            return (type(r[17]) == "string" and not HU.Secret(r[17])) and r[17] or nil
        end
    end
    return nil
end

-- «Ver recetas»: las mías, abriendo la ventana de esa profesión (C_TradeSkillUI.OpenTradeSkill, como hace el juego); las de
-- otro, pidiéndoselas al juego por su GUID (C_GuildInfo.QueryGuildMemberRecipes), que abre su ventana con ellas si el
-- servidor las da. Jorge, 24/11: «no funciona»: sin el GUID de la comunidad no se pedía nada, ni siquiera las mías
-- [+ARCHITECTURE.md]
local function OpenRecipes(p)
    if type(p) ~= "table" or type(p.id) ~= "number" then return end
    if p.mine and C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
        local ok, opened = pcall(C_TradeSkillUI.OpenTradeSkill, p.id)
        if ok and opened then return end
    end
    local q = C_GuildInfo and C_GuildInfo.QueryGuildMemberRecipes
    if q and p.guid then pcall(q, p.guid, p.id) end
end
-- (¿tiene recetas esa profesión? Las de recoger —Herboristería, Desuello— no: sin «Ver recetas». Las que fabrican, las de
-- CraftItems.lua)
local function HasRecipes(id)
    return type(id) == "number" and ((HU.CRAFT_ITEMS and HU.CRAFT_ITEMS[id] ~= nil) or (HU.CRAFT_SPELLS and HU.CRAFT_SPELLS[id] ~= nil))
end

-- Profesiones de alguien de mi hermandad (las da el juego por su comunidad de hermandad; las de las otras
-- hermandades, con su nivel, llegan con OF: CardProfessions)
local function OwnProfessions(name)
    local cid = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not cid or HU.Secret(cid) then return nil end
    local ok, ids = pcall(C_Club.GetClubMembers, cid)
    if not ok or type(ids) ~= "table" then return nil end
    local want = (HU:FullName(name) or name):lower()
    for _, id in ipairs(ids) do
        local ok2, info = pcall(C_Club.GetMemberInfo, cid, id)
        local n = ok2 and info and info.name
        if type(n) == "string" and not HU.Secret(n) and (HU:FullName(n) or n):lower() == want then
            local out = HU:ClubProfessions(info)
            -- (para «Ver recetas»: si son mías, y su GUID; si la comunidad no lo da, el de la lista del juego)
            local guid = (type(info.guid) == "string" and not HU.Secret(info.guid)) and info.guid or RosterGuid(n)
            for _, p in ipairs(out) do p.mine, p.guid = info.isSelf == true, guid end
            return #out > 0 and out or nil
        end
    end
    return nil
end

-- (textos del juego, en su idioma, como en su ficha; si no están, los nuestros)
local function GT(global, ours) local v = _G[global]; return (type(v) == "string" and v ~= "") and v or L(ours) end

-- La ficha, con el aspecto de la del juego (CommunitiesGuildMemberDetailFrameTemplate): nombre dorado,
-- nivel y clase, «Etiqueta: valor» en la misma línea, las notas en su recuadro y los botones abajo
local function BuildCard(f)
    card = CreateFrame("Frame", "GuildUnionMemberCard", f)
    card:SetSize(212, 330)
    -- (a la derecha de los iconos de la ventana: chat, miembros…)
    card:SetPoint("TOPLEFT", f, "TOPRIGHT", 40, -28)
    card:SetFrameStrata("HIGH")
    card:SetFrameLevel(cover:GetFrameLevel() + 30)
    card:EnableMouse(true)
    card:Hide()
    local border = CreateFrame("Frame", nil, card, "DialogBorderDarkTemplate")
    border:SetPoint("TOPLEFT", 4, 0); border:SetPoint("BOTTOMRIGHT", 6, 1)
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 10, -6); bg:SetPoint("BOTTOMRIGHT", 0, 7)
    bg:SetColorTexture(0.03, 0.03, 0.03, 0.92)
    local close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 3, -4)
    close:SetScript("OnClick", function() card:Hide() end)

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", 17, -18); card.title:SetWidth(165)
    card.title:SetJustifyH("LEFT"); card.title:SetWordWrap(false)
    card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.sub:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -2)

    -- (etiqueta y valor en la misma línea, como en la del juego)
    card.lines = {}
    local prev
    local LABELS = {
        { "GUILD", "Hermandad" }, { "ZONE_COLON", "Zona" }, { "RANK_COLON", "Rango" },
        { "LAST_ONLINE_COLON", "Última conexión" }, { nil, "Profesiones" },
    }
    for i, lb in ipairs(LABELS) do
        local lab = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if i == 1 then lab:SetPoint("TOPLEFT", card.sub, "BOTTOMLEFT", 0, -11)
        else lab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -8) end
        local text = lb[1] and GT(lb[1], lb[2]) or L(lb[2])
        if not text:find(":%s*$") then text = text .. ":" end
        lab:SetText(text)
        local val = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("LEFT", lab, "RIGHT", 2, 0)
        val:SetPoint("RIGHT", card, "RIGHT", -14, 0)
        val:SetJustifyH("LEFT"); val:SetWordWrap(false)
        card.lines[i] = val
        prev = lab
    end
    -- (debajo de «Profesiones:», una línea por profesión: su icono, con el nivel en la esquina, y el botón
    -- «Ver recetas», como el juego)
    local rows = CreateFrame("Frame", nil, card)
    rows:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 4, -4); rows:SetSize(184, 44)
    rows.btns, rows.icons, rows.levels = {}, {}, {}
    for k = 1, 2 do
        local icon = rows:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        -- (primero el icono y, a su derecha, el nivel: hasta 3 cifras)
        icon:SetPoint("TOPLEFT", 0, -(k - 1) * 22)
        local lvl = rows:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lvl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        lvl:SetWidth(24); lvl:SetJustifyH("LEFT")
        -- («Ver recetas»: el botón rojo del juego, con letra pequeña. Jorge, 25/11: «pasarlo a rojo de nuevo»; del 24/11
        -- al 25/11 fue oscuro, como los paneles de Comercio y Calendario) [+ARCHITECTURE.md]
        local b = CreateFrame("Button", "GuildUnionMemberCardRecipes" .. k, rows, "UIPanelButtonTemplate")
        b:SetSize(92, 20)
        b:SetPoint("LEFT", lvl, "RIGHT", 2, 0)
        b:SetNormalFontObject("GameFontNormalSmall")
        b:SetHighlightFontObject("GameFontHighlightSmall")
        b:SetDisabledFontObject("GameFontDisableSmall")
        b:SetText(L("Ver recetas"))
        b:SetScript("OnClick", function(s) OpenRecipes(s.prof) end)
        -- (apagado, al pasar el ratón dice por qué: RecipesWhy. El juego no lanza OnEnter en un botón apagado sin esto)
        b:SetMotionScriptsWhileDisabled(true)
        b:SetScript("OnEnter", function(s)
            if not s.why then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(s.why, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        icon:Hide(); lvl:Hide(); b:Hide()
        rows.btns[k], rows.icons[k], rows.levels[k] = b, icon, lvl
    end
    card.recipes = rows
    -- (las notas, cada una en su recuadro)
    local function NoteBox(labelText, anchor, dy)
        local lab = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lab:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, dy)
        lab:SetText(labelText)
        local box = CreateFrame("Frame", nil, card, "TooltipBackdropTemplate")
        box:SetSize(181, 40)
        box:SetPoint("TOPLEFT", lab, "BOTTOMLEFT", -2, 0)
        local t = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        t:SetSize(165, 32); t:SetPoint("TOP", 1, -6)
        t:SetJustifyH("LEFT"); t:SetJustifyV("TOP")
        return box, t
    end
    -- (solo se leen: un clic en ellas ya no lleva a la ficha del juego para cambiarlas. Jorge, 24/11)
    local noteBox
    noteBox, card.lines[6] = NoteBox(GT("NOTE_COLON", "Nota"), rows, -4)
    local _, offText = NoteBox(GT("OFFICER_NOTE_COLON", "Nota de oficial"), noteBox, -4)
    card.lines[7] = offText

    -- (abajo, como el juego: Echar e Invitar al grupo. Echar va por la ventana de órdenes, como el clic
    -- derecho: solo para los de mi hermandad y si tengo permiso)
    local bRemove = CreateFrame("Button", "GuildUnionMemberCardRemove", card, "UIPanelButtonTemplate")
    bRemove:SetSize(96, 22); bRemove:SetPoint("BOTTOMLEFT", 16, 12); bRemove:SetText(GT("REMOVE", "Echar"))
    bRemove:SetScript("OnClick", function() if card.entry then RemoveFromGuild({ card.entry }) end end)
    card.remove = bRemove
    local bInvite = CreateFrame("Button", "GuildUnionMemberCardInvite", card, "UIPanelButtonTemplate")
    bInvite:SetSize(96, 22); bInvite:SetPoint("LEFT", bRemove, "RIGHT", 1, 0); bInvite:SetText(GT("GROUP_INVITE", "Invitar al grupo"))
    bInvite:SetScript("OnClick", function()
        local fn = C_PartyInfo and C_PartyInfo.InviteUnit
        if fn and card.entry then pcall(fn, HU:FullName(card.entry.name) or card.entry.name) end
    end)
end

-- (las de la ficha: de mi hermandad, las del juego, con el nivel de su línea de oficios (Packs/Professions.lua) si el
-- juego no lo da y si esa línea está y trae recetas (para «Ver recetas»); de otra, las de sus líneas de oficios. Las
-- líneas se piden a su hermandad al abrirla (de la mía, lo que me perdí estando fuera). Cocina y Primeros auxilios no:
-- las tiene cualquiera; sus líneas solo sirven para «Quién lo hace» (Jorge, 25/11))
local function CardProfessions(e)
    local union, main = HU:UnionProfessionsOf(e.name) or {}, {}
    for _, p in ipairs(union) do if not p.secondary then main[#main + 1] = p end end
    if e.tag then HU:NeedUnionProfessions(e.tag) end
    if not e.own then return main end
    local own = OwnProfessions(e.name)
    if not own then return main end
    for _, p in ipairs(own) do
        for _, u in ipairs(union) do
            if u.id == p.id then p.rank, p.line, p.recipes = p.rank or u.rank, true, u.recipes end
        end
    end
    return own
end
-- (por qué no se pueden ver las recetas de otro: sin su línea de oficios de esa profesión, no tiene el addon o aún no ha
-- llegado; con ella pero sin recetas, no ha abierto esa ventana con el addon. Las mías, siempre. Jorge, 25/11)
-- [+ARCHITECTURE.md]
local function RecipesWhy(p)
    if p.mine then return nil end
    if not p.line then return L("No tiene GuildUnion (o aún no ha llegado lo suyo)") end
    if not p.recipes then return string.format(L("Aún no ha abierto su ventana de %s"), tostring(p.name)) end
    return nil
end

-- force: siempre abrirla (desde la lista del juego); sin él, otro clic en la misma persona la cierra
local function ShowCard(e, force)
    local f = Win()
    if not (f and cover) then return end
    if not card then BuildCard(f) end
    if not force and card:IsShown() and card.entry and card.entry.name == e.name then return card:Hide() end
    card.entry = e
    card.title:SetText(HU:Nice(e.name))
    local cls = e.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[e.class] or e.class or ""
    card.sub:SetText(((e.level and e.level > 0) and (L("Nivel") .. " " .. e.level .. " ") or "") .. cls)
    local v = card.lines
    v[1]:SetText("|cff" .. HU:GuildColorHex(e.tag) .. "<" .. tostring(HU:TagLabel(e.tag) or "") .. ">  " .. HU:GuildName(e.tag) .. "|r")
    v[2]:SetText((e.zone and e.zone ~= "") and e.zone or "—")
    v[3]:SetText((not e.noRank and e.rank ~= "" and e.rank) or "—")
    v[4]:SetText(e.online and ("|cff40ff40" .. L("Conectado") .. "|r") or Ago(e.offSecs))
    -- (profesiones: una línea cada una, su icono con el nivel y «Ver recetas»)
    local profs = CardProfessions(e)
    local rows = card.recipes
    for k = 1, 2 do
        local p = profs[k]
        rows.btns[k].prof = p
        rows.icons[k]:SetShown(p ~= nil); rows.levels[k]:SetShown(p ~= nil)
        -- («Ver recetas», solo en las que fabrican y de mi hermandad (el juego no da las de otra); apagado si no se puede
        -- pedir (ni mía ni con GUID) o si aún no las tiene (RecipesWhy, que sale al pasar el ratón))
        rows.btns[k]:SetShown(p ~= nil and e.own == true and HasRecipes(p.id))
        rows.btns[k].why = p and RecipesWhy(p)
        if p then
            rows.icons[k]:SetTexture(p.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            rows.levels[k]:SetText(p.rank and tostring(p.rank) or "")
            rows.btns[k]:SetText(p.icon and L("Ver recetas") or (p.name .. ": " .. L("Ver recetas")))
            rows.btns[k]:SetEnabled(p.mine == true or (p.guid ~= nil and rows.btns[k].why == nil))
        end
    end
    v[5]:SetText(#profs == 0 and "—" or "")
    -- (de mi hermandad, si mi rango me deja echarlo; de otra, si soy oficial: se le pide a su hermandad)
    card.remove:SetEnabled((e.own == true and HU:CanKickMember(e.name)) or (not e.own and e.tag ~= nil and HU:CanOfficer()))
    v[6]:SetText((e.note and e.note ~= "") and e.note or "")
    v[7]:SetText((e.offNote and e.offNote ~= "") and e.offNote or "")
    card:Show()
end
-- (lo de oficios que llega con la ficha abierta: se repinta un momento después, una vez)
local cardQueued
HU:Listen("CHANGED", function(what)
    if what ~= "professions" or cardQueued or not (card and card:IsShown()) then return end
    cardQueued = true
    HU.After(2, function()
        cardQueued = nil
        if card:IsShown() and card.entry then ShowCard(card.entry, true) end
    end)
end)

-- Varios a la vez: Ctrl suma o quita uno, Mayús elige del último al de ahora; un clic solo, uno y su
-- ficha. Clic derecho: cambiar rango o echar a los de mi hermandad, por la ventana de órdenes (el juego
-- no deja que un addon lo haga solo: tú mandas cada /gpromote, /gdemote o /gremove) [+ARCHITECTURE.md]
local function Selected()
    local out = {}
    for _, e in ipairs(shown) do if sel[e.name:lower()] then out[#out + 1] = e end end
    return out
end

local function ChangeRank(targets, idx, rankName)
    local lines, names = {}, {}
    for _, e in ipairs(targets) do
        local macro, why = HU:RankMacro(e.name, idx)
        if macro then lines[#lines + 1] = macro; names[#names + 1] = HU:Nice(e.name)
        else HU:Print(HU:Nice(e.name) .. ": " .. tostring(why)) end
    end
    if #lines == 0 then return end
    -- (la pregunta con el rango nuevo: «¿Seguro que quieres pasar a Ana a «Oficial»?»)
    local rank = tostring(rankName)
    local ask = #names == 1 and string.format(L("¿Seguro que quieres pasar a %s a «%s»?"), names[1], rank)
        or string.format(L("¿Seguro que quieres pasar a estas %d personas a «%s»?"), #names, rank)
    HU:TypeLines(table.concat(lines, "\n"), L("Cambiar rango") .. ": " .. rank, ask, #names > 1 and table.concat(names, "\n") or nil)
end

-- (los de mi hermandad, por la ventana de órdenes, si mi rango me deja: si no, la orden fallaría y se dice por
-- qué; los de otra, se le pide a su hermandad: les sale en «Peticiones de oficiales», InviteLog.lua)
RemoveFromGuild = function(targets)
    local lines = {}
    for _, e in ipairs(targets) do
        if e.own then
            local can, why = HU:CanKickMember(e.name)
            if can then lines[#lines + 1] = HU.GuildCmd("gremove", e.name)
            else HU:Print(HU:Nice(e.name) .. ": " .. tostring(why)) end
        elseif e.tag then HU:AskGuildKick(e.name, e.tag) end
    end
    if #lines > 0 then HU:TypeLines(table.concat(lines, "\n"), L("Echar de la hermandad")) end
end

-- Las opciones de hermandad (solo los de la mía; los de las otras no se pueden tocar desde aquí)
local function AddGuildActions(root, targets)
    local own, others = {}, {}
    for _, e in ipairs(targets) do
        if e.own then own[#own + 1] = e elseif e.tag then others[#others + 1] = e end
    end
    -- (los de otras hermandades: pedir a su hermandad que los eche)
    if #others > 0 and HU:CanOfficer() then
        -- (cambiar rango: los rangos de esa hermandad; solo si todos los elegidos son de la misma)
        local tag, same = others[1].tag, true
        for _, e in ipairs(others) do if e.tag ~= tag then same = false end end
        local ranks = same and HU:RankNames(tag) or {}
        if #ranks > 0 then
            local sub = root:CreateButton(L("Pedir a su hermandad cambio de rango"))
            for i, name in ipairs(ranks) do
                sub:CreateButton(name, function() for _, e in ipairs(others) do HU:AskGuildRank(e.name, e.tag, i - 1) end end)
            end
        end
        root:CreateButton("|cffff4040" .. L("Pedir a su hermandad que lo eche") .. "|r", function() RemoveFromGuild(others) end)
    end
    if #own == 0 then return end
    local canRank = HU:CanPromote() or HU:CanDemote()
    if canRank then
        local sub = root:CreateButton(L("Cambiar rango"))
        for i, name in ipairs(HU:RankNames(HU.myTag)) do
            sub:CreateButton(name, function() ChangeRank(own, i - 1, name) end)
        end
    end
    -- (echar, solo a los que mi rango deja: a uno de rango igual o más alto, la orden fallaría)
    local kick = {}
    for _, e in ipairs(own) do if HU:CanKickMember(e.name) then kick[#kick + 1] = e end end
    if #kick > 0 then
        root:CreateButton("|cffff4040" .. L("Echar de la hermandad") .. "|r", function() RemoveFromGuild(kick) end)
    end
end

local function RowClick(row, button)
    local e = row.entry
    local key = e.name:lower()
    if button == "RightButton" then
        -- (con varios elegidos y el clic sobre uno de ellos: el menú de todos; si no, el de esa persona)
        local list = sel[key] and Selected() or {}
        if #list > 1 and MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(row, function(_, root)
                root:CreateTitle(string.format(L("%d elegidos"), #list))
                AddGuildActions(root, list)
            end)
        else
            sel, anchorKey = { [key] = true }, key
            Paint()
            HU.PlayerMenu(row, e, function(root) AddGuildActions(root, { e }) end)
        end
        return
    end
    if IsControlKeyDown() then
        sel[key] = (not sel[key]) or nil
        anchorKey = key
    elseif IsShiftKeyDown() and anchorKey then
        local a, b
        for i, x in ipairs(shown) do
            local k = x.name:lower()
            if k == anchorKey then a = i end
            if k == key then b = i end
        end
        if a and b then
            if a > b then a, b = b, a end
            sel = {}
            for i = a, b do sel[shown[i].name:lower()] = true end
        end
    else
        sel, anchorKey = { [key] = true }, key
        ShowCard(e)
    end
    Paint()
end

-- El buscador de personajes (BlizzTab.lua), con nuestra lista a la vista: lleva a esa persona, la deja
-- elegida y abre su ficha. Devuelve true si lo ha hecho
function HU.UnionRosterPick(e)
    if not (cover and cover:IsShown() and tab == 1 and e and e.name) then return false end
    local key = (HU:FullName(e.name) or e.name):lower()
    Paint()
    for i, x in ipairs(shown) do
        if x.name:lower() == key then
            sel, anchorKey = { [key] = true }, key
            local sf = cover.scroll
            local h = sf:GetHeight()
            local visible = (type(h) == "number" and h > 0) and math.max(1, math.floor(h / ROW_H)) or ROWS
            local off = math.max(0, math.min(i - 1, #shown - visible))
            local bar = sf:GetName() and _G[sf:GetName() .. "ScrollBar"]
            if bar then bar:SetValue(off * ROW_H) end
            FauxScrollFrame_SetOffset(sf, off)
            Paint()
            if not (card and card:IsShown() and card.entry and card.entry.name:lower() == key) then ShowCard(x) end
            return true
        end
    end
    HU:Print(string.format(L("%s no está conectado ahora mismo (de las otras hermandades solo salen los conectados)."), HU:Nice(e.name)))
    return true
end

-- Sin leer en Comercio: el puntito de aviso del juego con el número de chats que tienen algo sin leer encima, en la
-- pestaña de Comercio y en el botón de hermandad del menú del juego (Jorge, 25/11) [+ARCHITECTURE.md]
local function UnreadBadge(owner, size, atlas)
    local dot = owner:CreateTexture(nil, "OVERLAY", nil, 2)
    dot:SetAtlas(atlas); dot:SetSize(size, size)
    local num = owner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    num:SetDrawLayer("OVERLAY", 7)
    num:SetPoint("CENTER", dot, "CENTER", 0, 0)
    local badge = { dot = dot, num = num }
    function badge.Sync()
        local n = HU:TradeUnreadChats()
        num:SetText(n > 99 and "99+" or tostring(n))
        dot:SetShown(n > 0); num:SetShown(n > 0)
    end
    badge.Sync()
    return badge
end
-- (en el botón «Hermandad y comunidades» del menú del juego, GuildMicroButton: en un marco nuestro colgado de él, encima
-- de su aviso y donde lo pone el juego. De lo suyo no se toca nada. Se monta la primera vez que hace falta)
local microBadge
local function MicroBadge()
    if not microBadge then
        local mb = _G.GuildMicroButton
        if type(mb) ~= "table" then return end
        local holder = CreateFrame("Frame", "GuildUnionMicroUnread", mb)
        holder:SetAllPoints(mb)
        holder:SetFrameLevel(math.max(mb:GetFrameLevel() + 10, 110))
        microBadge = UnreadBadge(holder, 21, "UI-HUD-MicroMenu-Communities-Icon-Notification")
        microBadge.dot:SetPoint("TOP", holder, "TOP", 0, 6)
    end
    microBadge.Sync()
end
HU:Listen("CHANGED", function(what) if what == "tradeUnread" then MicroBadge() end end)
HU:OnStart(MicroBadge)

local function Build(f)
    local ml = f and f.MemberList
    local anchor = ml and ml.ShowOfflineButton
    if cover or not anchor then return end

    -- Encima de la lista del juego y de sus títulos (sin tocarla: hija de la ventana, no de su lista).
    -- La casilla de desconectados y el buscador quedan a la vista, encima
    cover = CreateFrame("Frame", "GuildUnionUnionRoster", f, "BackdropTemplate")
    cover:HookScript("OnHide", function()
        HU.charSearchOff = false; HU.SyncCharSearch()
        if cover.band then cover.band:Hide() end
        BoxTops(f, true)
        OfflineBox(true)
    end)
    cover:SetPoint("TOPLEFT", ml, "TOPLEFT", -3, TOP)
    -- (hasta 22 más a la derecha: tapa también la barra de la lista del juego, que se veía al lado de la nuestra)
    cover:SetPoint("BOTTOMRIGHT", ml, "BOTTOMRIGHT", 22, 0)
    -- (el marco del borde de la lista del juego, InsetFrame, se pone a nivel 100: por encima, o su
    -- borde se ve por delante de lo nuestro y tapa el primer título)
    -- (y por encima de la barra del chat del juego, que asomaba por encima de los botones)
    cover:SetFrameLevel(math.max(ml:GetFrameLevel() + 20, 300))
    -- (y en una capa más alta: la barra del chat del juego está en otra capa y asomaba igual)
    cover:SetFrameStrata("HIGH")
    cover:EnableMouse(true)
    cover:Hide()

    -- Arriba, la franja (TAB_H) donde queda lo del juego: el buscador, las casillas, los cascos y el «en línea»
    local tabs = CreateFrame("Frame", nil, cover)
    tabs:SetPoint("TOPLEFT", 0, 0); tabs:SetPoint("TOPRIGHT", 0, 0); tabs:SetHeight(TAB_H)
    tabs.selectedTab = 1
    -- (detrás de la franja y de los títulos, la misma piedra que el juego pone encima, como en su lista: así no se ven
    -- rayas; el fondo oscuro empieza en la primera fila. En el marco de abajo del todo: si no, tapa los títulos)
    local rock = cover:CreateTexture(nil, "BACKGROUND")
    rock:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    rock:SetHorizTile(true); rock:SetVertTile(true)
    rock:SetPoint("TOPLEFT", cover, "TOPLEFT", STRIP_W - STRIP, 0); rock:SetPoint("TOPRIGHT", cover, "TOPRIGHT")
    rock:SetHeight(TAB_H + HDR_H)
    cover.rock = rock
    -- (la franja de la barra de la columna de comunidades: el mismo mármol oscuro del fondo del juego, de arriba abajo
    -- (Jorge, 24/11: «un solo formato para todas las páginas»); la barra va encima, en la capa HIGH: ListBar)
    local strip = cover:CreateTexture(nil, "BACKGROUND")
    strip:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
    strip:SetHorizTile(true); strip:SetVertTile(true)
    strip:SetPoint("TOPLEFT", cover, "TOPLEFT", -STRIP, 0)
    if type(f.CommunitiesList) == "table" then
        strip:SetPoint("BOTTOMRIGHT", f.CommunitiesList, "BOTTOMRIGHT", STRIP_W, 0)
    end
    cover.strip = strip
    -- (en la vista de chat, la misma piedra hasta el chat y su lista (Jorge, 24/11): en el fondo del juego, encima de su
    -- borde y debajo de lo suyo, y desde la misma esquina que la de la franja, para que casen sin costura) [+ARCHITECTURE.md]
    local inset = type(f.Inset) == "table" and f.Inset or nil
    local edge = inset and type(inset.NineSlice) == "table" and inset.NineSlice or nil
    if inset then
        local band = edge and edge:CreateTexture(nil, "OVERLAY") or inset:CreateTexture(nil, "BACKGROUND", nil, 1)
        band:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
        band:SetHorizTile(true); band:SetVertTile(true)
        band:SetPoint("TOPLEFT", cover, "TOPLEFT", STRIP_W - STRIP, 0); band:SetPoint("TOPRIGHT", cover, "TOPRIGHT")
        band:SetHeight(TAB_H + INSET_EDGE)
        band:Hide()
        cover.band = band
    end
    -- Abajo, como en la vista del chat: Oficiales (Peticiones de oficiales y Ver registro, en su desplegable) · Invitar
    -- miembro, a la izquierda de «Ajustes de hermandad» (Jorge, 23/11 y 25/11). El juego solo enseña su «Invitar miembro»
    -- en la vista del chat: aquí lo pulsa un botón seguro (si lo pulsara el addon, el juego bloquearía la invitación).
    -- Cuelgan de la casilla de desconectados, como el «Chat» seguro: solo se ven en la vista de miembros [+ARCHITECTURE.md]
    local gcb = f.CommunitiesControlFrame and f.CommunitiesControlFrame.GuildControlButton
    if f.InviteButton and gcb then
        local inv = CreateFrame("Button", "GuildUnionRosterInvite", anchor, "SecureActionButtonTemplate,UIPanelButtonTemplate")
        inv:SetSize(130, 20)
        inv:SetText(L("Invitar miembro"))
        inv:SetPoint("RIGHT", gcb, "LEFT", -4, 0)
        inv:SetFrameStrata("HIGH")
        inv:RegisterForClicks("AnyUp", "AnyDown")
        inv:SetAttribute("type", "click")
        inv:SetAttribute("clickbutton", f.InviteButton)
        local off = HU:OfficersButton(anchor, "GuildUnionRosterOfficers")
        off:SetPoint("RIGHT", inv, "LEFT", -4, 0)
        off:SetFrameStrata("HIGH")
    end
    cover.tabs = tabs
    tabs:SetFrameLevel(cover:GetFrameLevel() + 6)

    -- Comercio y Eventos, pestañas de la derecha como las del juego (Jorge, 24/11: «intentamos con botones
    -- laterales»; antes fueron una fila de botones redondos arriba y luego entradas de la columna de comunidades): justo
    -- debajo de la de miembros del juego («justo después de raid») y las demás del juego, debajo; luego irán Wanted y LFG.
    -- Botones seguros que pulsan la pestaña de miembros del juego (PreClick apunta la sección; si ya se ve esa vista,
    -- PostClick la abre), con el dibujo de las del juego (RightSideTabTemplate: el marco del libro de hechizos, el icono y
    -- sus dos brillos) [+ARCHITECTURE.md]
    local side = { tabs = {}, fromSide = false }
    for i, t in ipairs(TABS) do
        if t.trade or t.calendar then
            local b = CreateFrame("CheckButton", t.trade and "GuildUnionTradeTab" or "GuildUnionCalendarTab", f, "SecureActionButtonTemplate")
            b:SetSize(SIDE_TAB, SIDE_TAB)
            b:SetFrameLevel(510)
            local rim = b:CreateTexture(nil, "BORDER")
            rim:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
            rim:SetSize(SIDE_TAB * 2, SIDE_TAB * 2); rim:SetPoint("TOPLEFT", -3, 11)
            local ic = b:CreateTexture(nil, "ARTWORK")
            ic:SetTexture(t.icon)
            ic:SetSize(SIDE_TAB - 2, SIDE_TAB - 2); ic:SetPoint("CENTER")
            ic:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
            b.icon = ic
            local glow = b:CreateTexture(nil, "HIGHLIGHT")
            glow:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); glow:SetBlendMode("ADD"); glow:SetAllPoints()
            local picked = b:CreateTexture(nil, "OVERLAY")
            picked:SetTexture("Interface\\Buttons\\CheckButtonHilight"); picked:SetBlendMode("ADD"); picked:SetAllPoints()
            b:SetCheckedTexture(picked)
            b.tooltip = L(t.side or t.title)
            b:SetScript("OnEnter", function(s)
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                GameTooltip:SetText(s.tooltip)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:SetAttribute("type", "click")
            b:SetAttribute("clickbutton", f.RosterTab)
            b.tab = i
            b:SetScript("PreClick", function() wantTab, side.fromSide = i, true end)
            -- (ya en la vista de miembros, la pestaña del juego no cambia nada: la sección se abre aquí. Si no se llegó a
            -- esa vista (se soltó fuera), nada queda apuntado y las marcas vuelven a ser las de antes)
            b:SetScript("PostClick", function()
                side.fromSide = false
                if mode ~= "roster" then wantTab = nil; CheckTabs(); return end
                wantTab, tab = nil, i
                if SyncNow then SyncNow() end
            end)
            if t.trade then
                -- (con mensajes sin leer en Comercio, la pestaña lleva el puntito de aviso de las comunidades del juego con
                -- el número de chats que los tienen; al leerlos se va: HU:TradeUnreadChats, Trade.lua. Jorge, 24/11: el
                -- puntito, sin brillo; 25/11: «con el número de chats sin leer») [+ARCHITECTURE.md]
                b.badge = UnreadBadge(b, 16, "communities-icon-notification")
                b.badge.dot:SetPoint("TOPRIGHT", b, "TOPRIGHT", 3, 3)
                side.trade = b
            end
            b:Hide()
            side.tabs[#side.tabs + 1] = b
            -- (con el panel de GuildUnion abierto, sin su marca: BlizzTab.lua)
            HU.sideTabs[#HU.sideTabs + 1] = b
        end
    end
    -- (en Comercio y Calendario, un clic en la entrada de la hermandad de la columna de comunidades vuelve al chat (Jorge,
    -- 24/11): un botón seguro invisible encima de ella que pulsa la pestaña de chat del juego, con su brillo al pasar el
    -- ratón; en las demás vistas no está y el clic es de la entrada. El botón derecho pasa a ella: su menú sigue. La lista
    -- del juego no se toca: si el addon la tocara, su ficha bloquearía notas y rangos) [+ARCHITECTURE.md]
    local cl = f.CommunitiesList
    local home = CreateFrame("Button", nil, cl, "SecureActionButtonTemplate")
    home:SetFrameLevel((type(cl.ScrollBox) == "table" and cl.ScrollBox or cl):GetFrameLevel() + 10)
    home:RegisterForClicks("AnyUp", "AnyDown")
    home:SetAttribute("type", "click")
    home:SetAttribute("clickbutton", f.ChatTab)
    home:EnableMouse(true)
    if home.SetPassThroughButtons then home:SetPassThroughButtons("RightButton") end
    local hhl = home:CreateTexture(nil, "HIGHLIGHT")
    hhl:SetTexture("Interface\\Common\\bluemenu-main")
    hhl:SetTexCoord(0.00390625, 0.87890625, 0.75195313, 0.83007813)
    hhl:SetHeight(80); hhl:SetPoint("LEFT"); hhl:SetPoint("RIGHT")
    hhl:SetBlendMode("ADD"); hhl:SetAlpha(0.8)
    home:Hide()
    side.home = home
    cover.side = side

    -- Los títulos de las columnas, como los del juego; un clic ordena por esa columna
    local hdr = CreateFrame("Frame", nil, cover)
    -- (justo debajo de la franja, donde están la casilla de desconectados, «Solo mi hermandad» y el buscador)
    hdr:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, 0)
    hdr:SetPoint("RIGHT", cover, "RIGHT", 0, 0)
    hdr:SetHeight(HDR_H)
    hdr:SetFrameLevel(cover:GetFrameLevel() + 6)
    local starts, prev = {}, nil
    for i, col in ipairs(COLS) do
        local b = CreateFrame("Button", nil, hdr, "ColumnDisplayButtonNoScriptsTemplate")
        local gt = col.game and _G[col.game]
        b:SetText(type(gt) == "string" and gt ~= "" and gt or L(col.title))
        if i == 1 then b:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 2, 0)
        else b:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", -2, 0) end
        if col.w > 0 then b:SetWidth(col.w) else b:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", -24, 0) end
        b:SetScript("OnClick", function()
            if sortKey == col.key then
                if sortDesc then sortKey, sortDesc = nil, nil else sortDesc = true end
            else
                sortKey, sortDesc = col.key, false
            end
            Paint(); WhoTick()
        end)
        starts[i] = (i == 1) and 2 or (starts[i - 1] + COLS[i - 1].w - 2)
        prev = b
    end
    cover.hdr = hdr
    local dark = cover:CreateTexture(nil, "BACKGROUND")
    dark:SetColorTexture(0.04, 0.04, 0.05, 1)
    dark:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, 0)
    dark:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", 0, 0)
    cover.dark = dark
    -- (la sección Comercio, Trade.lua: debajo de los botones, hasta abajo)
    cover.trade = CreateFrame("Frame", nil, cover)
    -- (desde arriba del todo: en Comercio y Calendario la franja no lleva nada del juego, y sus botones van ahí)
    cover.trade:SetPoint("TOPLEFT", cover, "TOPLEFT", 0, -2)
    cover.trade:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", 0, 4)
    cover.trade:SetFrameLevel(cover:GetFrameLevel() + 5)
    cover.trade:Hide()
    HU:BuildTrade(cover.trade)
    -- (la sección Eventos, UnionCalendar.lua: igual)
    cover.calendar = CreateFrame("Frame", nil, cover)
    cover.calendar:SetPoint("TOPLEFT", cover, "TOPLEFT", 0, -2)
    cover.calendar:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", 0, 4)
    cover.calendar:SetFrameLevel(cover:GetFrameLevel() + 5)
    cover.calendar:Hide()
    HU:BuildCalendar(cover.calendar)

    cover.status = cover:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cover.status:SetPoint("BOTTOMLEFT", 8, 6)
    cover.status:SetPoint("RIGHT", cover, "RIGHT", -8, 0)
    cover.status:SetJustifyH("LEFT"); cover.status:SetWordWrap(false)

    local sf = CreateFrame("ScrollFrame", "GuildUnionUnionRosterScroll", cover, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -2)
    sf:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", -26, 22)
    sf:SetScript("OnVerticalScroll", function(s, offset) FauxScrollFrame_OnVerticalScroll(s, offset, ROW_H, Paint) end)
    -- (el /who, con lo que mueve el jugador: la rueda, la barra y sus flechas; ver WhoTick)
    sf:HookScript("OnMouseWheel", function() WhoTick() end)
    local bar = _G[sf:GetName() .. "ScrollBar"]
    if bar then
        bar:HookScript("OnMouseDown", function() WhoTick() end)
        for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
            local arrow = _G[bar:GetName() .. k]
            if arrow then arrow:HookScript("OnClick", function() WhoTick() end) end
        end
    end
    sf:SetScript("OnSizeChanged", function() Paint() end)
    cover.scroll = sf
    cover.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, cover)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", sf, "RIGHT", 0, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        if i % 2 == 0 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints(); stripe:SetColorTexture(1, 1, 1, 0.03)
        end
        row.selTex = row:CreateTexture(nil, "BORDER")
        row.selTex:SetAllPoints(); row.selTex:SetColorTexture(0.25, 0.55, 1, 0.28)
        row.selTex:Hide()
        local c = {}
        for k, col in ipairs(COLS) do
            local x = starts[k] + 6
            if col.key == "class" then
                local tex = row:CreateTexture(nil, "ARTWORK")
                tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
                tex:SetSize(16, 16)
                tex:SetPoint("LEFT", starts[k] + (col.w - 16) / 2, 0)
                c.class = tex
            elseif col.key == "prof" then
                -- (dos huecos, el icono de cada profesión, juntos y centrados en la columna)
                c.prof = {}
                for j = 1, 2 do
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(14, 14)
                    icon:SetPoint("LEFT", starts[k] + (col.w - 30) / 2 + (j - 1) * 16, 0)
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    c.prof[j] = icon
                end
            else
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("LEFT", x, 0)
                -- (el nombre deja sitio a su derecha para el icono de rango)
                local iw = col.key == "name" and 16 or 0
                if col.w > 0 then fs:SetWidth(col.w - 10 - iw) else fs:SetPoint("RIGHT", row, "RIGHT", -4, 0) end
                fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
                c[col.key] = fs
                if iw > 0 then
                    c.nameMax = col.w - 10 - iw
                    c.rankIcon = row:CreateTexture(nil, "ARTWORK")
                    c.rankIcon:SetSize(14, 14)
                    c.rankIcon:Hide()
                end
            end
        end
        row.cells = c
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(s, button)
            WhoTick()
            if s.entry then RowClick(s, button) end
        end)
        cover.rows[i] = row
    end
    cover:SetScript("OnMouseDown", function() WhoTick() end)
    cover:SetScript("OnShow", function()
        -- (se pide la lista de la hermandad al juego, por si estaba vieja)
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        ShowTab(tab)
    end)
    cover:RegisterEvent("GUILD_ROSTER_UPDATE")
    cover:SetScript("OnEvent", function() notesDirty, profsDirty, listDirty = true, true, true; Paint() end)
    HU:Listen("CHANGED", function(what) if what == "unionMembers" then listDirty = true; Paint() end end)
    -- (la casilla del juego: al marcarla o quitarla, la nuestra se repinta; solo se lee, no se toca)
    anchor:HookScript("OnClick", function() HU.After(0, Paint) end)
    local acc = 0
    cover:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc > 2 then acc = 0; Paint() end
    end)

    -- («Solo mi hermandad», encima de la lista a la derecha: solo con los de mi hermandad)
    mine = CreateFrame("CheckButton", "GuildUnionRosterMine", f, "UICheckButtonTemplate")
    mine:SetSize(24, 24)
    mine:SetPoint("BOTTOMLEFT", ml, "TOPRIGHT", -120, TOP + 2 - DROP)
    mine:SetFrameStrata("HIGH")
    mine:SetFrameLevel(cover:GetFrameLevel() + 2)
    if mine.Text then mine.Text:SetText(L("Solo mi hermandad")) end
    -- (la vista de miembros se reconoce por la casilla de desconectados; la de chat, por el chat. IsVisible
    -- y no IsShown, como el buscador. Al cambiar de vista: con el icono del chat se empieza en Chat; con el
    -- de miembros, en Miembros)
    local lastMode, secureLater, UpdateCounts
    -- (la lista y el chat del juego llevan colgados nuestros botones seguros: en combate el juego no deja moverlos
    -- (ADDON_ACTION_BLOCKED en SetPoint, visto el 23/11, copia 287). Se apunta y se colocan al salir del combate)
    local function GameLocked()
        if InCombatLockdown() then secureLater = true; return true end
        return false
    end
    -- (en la vista de chat, el chat y su lista de la derecha empiezan debajo de la fila de botones y del desplegable
    -- «Guild», que va debajo de ella: atados a la fila. De vuelta en la de miembros, Sync los devuelve a su sitio)
    local placing = false
    local function ChatAnchors()
        if GameLocked() then return end
        placing = true
        ml:SetPoint("TOPLEFT", cover, "BOTTOMRIGHT", -161, -INSET_EDGE - LIST_EDGE)
        f.Chat:SetPoint("TOPLEFT", cover, "BOTTOMLEFT", 6, -INSET_EDGE - CHAT_EDGE)
        -- (la barra del chat, arriba del todo como la de su lista (Jorge, 24/11): la franja del mensaje fijado,
        -- BlizzTab.lua, baja los mensajes y la barra iba con ellos. Los mismos 15 y 1 que le da el juego)
        local chatBar = type(f.Chat.ScrollBar) == "table" and f.Chat.ScrollBar or nil
        if chatBar then chatBar:SetPoint("TOPLEFT", f.Chat, "TOPRIGHT", 15, 1) end
        placing = false
    end
    -- Arriba lo nuestro, debajo lo del juego (Jorge, 24/11): el desplegable «Guild» (con nuestro buscador, atado a él)
    -- y los cascos del chat de voz bajan DROP; en la vista de miembros, también la casilla de desconectados, que sube
    -- de capa para verse encima de lo nuestro. Fuera de combate: la casilla lleva colgados nuestros botones seguros.
    -- El juego los recoloca al agrandar la ventana: se vuelven a poner [+ARCHITECTURE.md]
    local dd = type(f.StreamDropdown) == "table" and f.StreamDropdown or nil
    local headset = type(f.VoiceChatHeadset) == "table" and f.VoiceChatHeadset or nil
    local placingTop = false
    -- (el sitio del desplegable «Guild» de siempre: ahí va nuestro buscador, en las dos vistas, BlizzTab.lua)
    local spot = CreateFrame("Frame", nil, f)
    spot:SetPoint("TOPLEFT", f, "TOPLEFT", 195, -31 - DROP)
    spot:SetSize(dd and dd:GetWidth() or 150, dd and dd:GetHeight() or 26)
    HU.chatSearchSpot = spot
    local function TopRow()
        if not mode or GameLocked() then return end
        placingTop = true
        -- (el desplegable «Guild»: en la vista de chat, a la derecha, donde los cascos y el «N/M en línea» de mi hermandad,
        -- que se quitan (ChatTop). Jorge, 24/11: «pon lo de cambiar de chat al de oficial o el chat normal»)
        -- [+ARCHITECTURE.md]
        if dd then
            dd:ClearAllPoints()
            if mode == "chat" then dd:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -31 - DROP)
            else dd:SetPoint("TOPLEFT", f, "TOPLEFT", 195, -31 - DROP) end
        end
        if headset then headset:ClearAllPoints(); headset:SetPoint("TOPRIGHT", f, "TOPRIGHT", -180, -26 - DROP) end
        -- (a la derecha, delante de «Solo mi hermandad»: a la izquierda va el buscador, en el mismo sitio que en la vista de
        -- chat. Jorge, 24/11) [+ARCHITECTURE.md]
        local label = type(anchor.Text) == "table" and anchor.Text or nil
        local lw = label and label:GetStringWidth()
        lw = (type(lw) == "number" and lw > 0 and not HU.Secret(lw)) and lw or 110
        anchor:ClearAllPoints()
        anchor:SetPoint("BOTTOMLEFT", ml, "TOPRIGHT", -120 - 14 - lw - 26, TOP - DROP)
        anchor:SetFrameStrata("HIGH")
        anchor:SetFrameLevel(cover:GetFrameLevel() + 12)
        local search = _G.GuildUnionReduceSearch
        if search then search:SetFrameStrata("HIGH"); search:SetFrameLevel(cover:GetFrameLevel() + 12) end
        placingTop = false
    end
    for _, w in ipairs({ dd, headset }) do
        if w then hooksecurefunc(w, "SetPoint", function() if not placingTop and mode then TopRow() end end) end
    end
    -- (en la vista de chat, fuera los cascos del chat de voz y el «N/M en línea» de mi hermandad (el de toda la unión va en
    -- la barra del título): transparentes y sin clics, que esconderlos es cosa del juego. El desplegable «Guild», a la
    -- vista y con clics, en su sitio de la derecha (TopRow). Jorge, 24/11) [+ARCHITECTURE.md]
    local count = type(ml.MemberCount) == "table" and ml.MemberCount or nil
    local chatTop
    local function ChatTop()
        local on = mode == "chat"
        if on == chatTop then return end
        chatTop = on
        if headset then headset:SetAlpha(on and 0 or 1); headset:EnableMouse(not on) end
        if count then count:SetAlpha(on and 0 or 1) end
        if dd then dd:SetAlpha(1); dd:EnableMouse(true) end
    end
    -- (la barra de la columna de comunidades, arriba del todo y por encima de la piedra en nuestras vistas (Jorge, 24/11);
    -- en las demás, donde y como la pone el juego. Solo se cambia su esquina de arriba: la de abajo sigue la suya)
    -- [+ARCHITECTURE.md]
    local clBar = type(cl.ScrollBar) == "table" and cl.ScrollBar or nil
    local clBarStrata, clBarLevel = clBar and clBar:GetFrameStrata(), clBar and clBar:GetFrameLevel()
    -- (el botón de vuelta al chat, encima de la entrada de la hermandad: la lista recicla sus marcos y los recoloca al
    -- moverla. Fuera de combate: es un botón seguro)
    local function PlaceHome()
        if GameLocked() then return end
        local sb = type(cl.ScrollBox) == "table" and cl.ScrollBox or nil
        local guildFrame
        if sb and sb.ForEachFrame then
            sb:ForEachFrame(function(fr, data)
                local ci = type(data) == "table" and data.clubInfo
                if type(ci) == "table" and ci.clubType == Enum.ClubType.Guild then guildFrame = fr end
            end)
        end
        side.home:ClearAllPoints()
        if guildFrame then side.home:SetAllPoints(guildFrame) end
        side.guildFrame = guildFrame
    end
    -- (al cambiar la lista del juego, y al enseñarse la columna, otra vez en su sitio)
    if cl.Update then hooksecurefunc(cl, "Update", function() HU.After(0, PlaceHome) end) end
    cl:HookScript("OnShow", function() HU.After(0, PlaceHome) end)
    -- (las pestañas, justo debajo de la de miembros del juego, que el juego nunca mueve, y solo con la hermandad elegida,
    -- como su pestaña de Información. Fuera de combate: son botones seguros) [+ARCHITECTURE.md]
    local function PlaceTabs()
        if GameLocked() then return end
        local info = f.GuildInfoTab
        local show = type(info) == "table" and info:IsShown() and true or false
        local above = f.RosterTab
        for _, b in ipairs(side.tabs) do
            if show and b.above ~= above then
                b.above = above
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SIDE_TAB_GAP)
            end
            b:SetShown(show)
            above = b
        end
    end
    -- (las del juego que iban debajo de la de miembros —Beneficios, si está; si no, Información; las demás van atadas a
    -- ella—, debajo de las nuestras. El juego vuelve a atar Información a Miembros cada vez que pone al día sus pestañas:
    -- se vuelve a bajar. No son botones seguros ni llevan nada seguro atado: también en combate) [+ARCHITECTURE.md]
    local function MoveGameTabs()
        local last = side.tabs[#side.tabs]
        if not (last and last:IsShown()) then return end
        local benefits = f.GuildBenefitsTab
        local first = (type(benefits) == "table" and benefits:IsShown()) and benefits or f.GuildInfoTab
        if type(first) ~= "table" then return end
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -SIDE_TAB_GAP)
    end
    -- (el juego pone al día sus pestañas al cambiar de vista o de comunidad: las nuestras, detrás)
    if f.UpdateCommunitiesTabs then
        hooksecurefunc(f, "UpdateCommunitiesTabs", function() PlaceTabs(); MoveGameTabs(); CheckTabs() end)
    end
    -- (el puntito de Comercio, con mensajes sin leer, y cuántos chats los tienen)
    local function TradeBadge()
        if side.trade then side.trade.badge.Sync() end
    end
    HU:Listen("CHANGED", function(what) if what == "tradeUnread" then TradeBadge() end end)
    TradeBadge()
    -- (la pestaña de miembros del juego, pulsada en la vista de miembros —no desde nuestras pestañas—: a Miembros)
    if type(f.RosterTab) == "table" then
        f.RosterTab:HookScript("OnClick", function()
            if cover.side.fromSide or mode ~= "roster" or tab == 1 then return end
            tab = 1
            if SyncNow then SyncNow() end
        end)
    end
    local clBarUp = false
    local function ListBar(up)
        if not clBar or up == clBarUp then return end
        clBarUp = up
        clBar:SetPoint("TOPLEFT", cl, "TOPRIGHT", 6, up and LIST_BAR_Y or LIST_BAR_Y_GAME)
        clBar:SetFrameStrata(up and "HIGH" or clBarStrata)
        clBar:SetFrameLevel(up and cover:GetFrameLevel() + 12 or clBarLevel)
    end
    -- (el juego vuelve a colocar la lista de la derecha a su aire —al actualizarla—: si está en la vista de
    -- chat con nuestra fila, se vuelve a poner debajo de la fila un instante después)
    hooksecurefunc(ml, "SetPoint", function()
        if placing or mode ~= "chat" then return end
        -- (en el acto: si se espera al siguiente fotograma, la lista se ve un instante en el sitio del juego)
        ChatAnchors()
    end)

    -- Conectados y miembros de toda la unión, en la barra del título (el contador del juego queda tapado por la
    -- fila de botones): en la vista de chat y en nuestras pestañas. Al pasar el ratón, los de cada hermandad
    -- [+ARCHITECTURE.md]
    local counts
    local perGuild = {}
    if f.Chat then
        counts = CreateFrame("Frame", "GuildUnionUnionCounts", f)
        counts:SetSize(200, 18)
        counts:SetFrameStrata("HIGH")
        counts.text = counts:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        counts.text:SetAllPoints(); counts.text:SetJustifyH("LEFT")
        counts:EnableMouse(true)
        counts:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(L("Conectados / miembros"))
            for _, line in ipairs(perGuild) do GameTooltip:AddLine(line, 1, 1, 1) end
            GameTooltip:Show()
        end)
        counts:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    UpdateCounts = function()
        -- (si se ve, lo decide Sync: aquí solo el texto)
        if not (counts and counts:IsShown()) then return end
        perGuild = {}
        local sumOn, sumTot, unknown = 0, 0, false
        local total, online = 0, 0
        if GetNumGuildMembers then
            local t, o = GetNumGuildMembers()
            if type(t) == "number" and not HU.Secret(t) then total = t end
            if type(o) == "number" and not HU.Secret(o) then online = o end
        end
        if HU.myTag then
            sumOn, sumTot = online, total
            perGuild[#perGuild + 1] = "|cff" .. HU:GuildColorHex(HU.myTag) .. HU:TagLabel(HU.myTag) .. "|r  " .. online .. " / " .. total
        end
        for _, t in ipairs(HU:OtherTags()) do
            local r = HU.remoteRoster and HU.remoteRoster[t]
            local on2, tot2 = r and tonumber(r.online), r and tonumber(r.total)
            if on2 then sumOn = sumOn + on2 else unknown = true end
            if tot2 then sumTot = sumTot + tot2 else unknown = true end
            perGuild[#perGuild + 1] = "|cff" .. HU:GuildColorHex(t) .. t .. "|r  " .. (on2 or "?") .. " / " .. (tot2 or "?")
        end
        -- (con alguna hermandad sin datos todavía, «+» detrás: hay más)
        counts.text:SetText(string.format(L("%d/%d conectados"), sumOn, sumTot) .. (unknown and "+" or ""))
    end
    -- (y se va poniendo al día: la lista del juego y las de las otras hermandades cambian solas)
    local accCounts = 0
    cover:HookScript("OnUpdate", function(_, dt)
        accCounts = accCounts + dt
        if accCounts > 3 then accCounts = 0; UpdateCounts() end
    end)
    local function SyncBody()
        -- (la de chat, con su lista de la derecha: la ventana pequeña también enseña el chat, pero sin lista)
        local m = (anchor:IsVisible() and "roster") or (f.Chat and f.Chat:IsVisible() and ml:IsVisible() and "chat") or nil
        if m ~= lastMode then
            lastMode, mode = m, m
            if m == "chat" then tab = 0 elseif m == "roster" then tab = wantTab or 1 end
            wantTab = nil
        end
        -- (sin casilla «GuildUnion» (Jorge, 23/11): lo nuestro siempre puesto, también para quien la tenía quitada)
        HU.db.unionRosterOff = nil
        mine:SetShown(m == "roster")
        mine:SetChecked(HU.db.unionRosterMine == true)
        -- (conectados: en la vista de chat y en todas las pestañas, el mismo sitio; en las demás vistas, no)
        if counts then
            counts:ClearAllPoints()
            -- (siempre en la barra del título, a la izquierda de minimizar y cerrar: es lo único que no se
            -- mueve. Los cascos del juego cambian de sitio, -180 o -10, y el texto se salía de la ventana)
            counts:SetPoint("RIGHT", f, "TOPRIGHT", -64, -11); counts.text:SetJustifyH("RIGHT")
            counts:SetFrameStrata("HIGH")
            counts:SetShown(m ~= nil)
        end
        -- (de vuelta en la vista de miembros, la lista y el chat dejan de estar atados a nuestra fila ANTES de
        -- colocarla encima de la lista: si no, se atarían el uno al otro. Son los sitios que les da el juego. En
        -- combate, al salir: la lista ya la deja el juego en su sitio al enseñarla o cambiar de vista, y el enganche
        -- de arriba no la mueve, así que no quedan atadas la una a la otra)
        if m == "roster" and f.CommunitiesList and not GameLocked() then
            ml:SetPoint("TOPLEFT", f.CommunitiesList, "TOPRIGHT", 26, -60)
            if f.Chat then f.Chat:SetPoint("TOPLEFT", f.CommunitiesList, "TOPRIGHT", 31, -44) end
        end
        cover:SetShown(m ~= nil and not RealList())
        if cover:IsShown() then ShowTab(tab) end
        if m == "chat" then ChatAnchors() end
        TopRow()
        ChatTop()
        ListBar(m ~= nil)
        PlaceHome()
        PlaceTabs()
        MoveGameTabs()
        if not GameLocked() then side.home:SetShown(m == "roster" and tab >= 2 and side.guildFrame ~= nil) end
        CheckTabs()
        UpdateCounts()
        -- (los botones seguros tampoco se colocan en combate (Layout): al salir, otra vez)
        if InCombatLockdown() then secureLater = true end
    end
    local function Sync()
        inSync = true
        local ok, err = pcall(SyncBody)
        inSync = false
        if not ok then error(err, 0) end
    end
    local function SyncSoon() HU.After(0, Sync) end
    SyncNow = Sync
    HU:On("PLAYER_REGEN_ENABLED", function() if secureLater then secureLater = false; SyncSoon() end end)
    -- (marcada: la lista del juego; quitada: vuelve lo nuestro, con toda la unión)
    mine:SetScript("OnClick", function(s)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        HU.db.unionRosterMine = s:GetChecked() and true or nil
        FauxScrollFrame_SetOffset(cover.scroll, 0)
        if card then card:Hide() end
        Sync()
    end)
    for _, w in ipairs({ anchor, ml, f.Chat or nil }) do w:HookScript("OnShow", SyncSoon); w:HookScript("OnHide", SyncSoon) end
    -- (al cambiar de vista, en el acto: si se espera al siguiente fotograma, durante un instante se ven los
    -- botones en el sitio de la vista anterior)
    if f.SetDisplayMode then hooksecurefunc(f, "SetDisplayMode", function() Sync(); SyncSoon() end) end
    -- (un clic en la lista del juego —la de la derecha en la vista de chat, o la de «Solo mi hermandad»— abre su
    -- ficha, la del juego, sin tocarla: con ella se guardan las notas. Si el addon la cerrara o abriera, el juego
    -- bloquearía guardarlas)
    -- (al abrir la ventana se vuelve a mirar la vista: Chat o Miembros, según cuál abra el juego)
    f:HookScript("OnShow", function() lastMode = nil; SyncSoon() end)
    ShowTab(tab)
    Sync()
end

-- (los botones seguros no se pueden crear en combate: si la ventana del juego se carga en pleno combate, se
-- monta al salir de él)
local setupLater = false
local function Setup()
    if InCombatLockdown() then setupLater = true; return end
    HU:SafeCall("unión en la lista", Build, Win())
end
HU:On("ADDON_LOADED", function(name) if name == "Blizzard_Communities" then Setup() end end)
HU:On("PLAYER_REGEN_ENABLED", function() if setupLater then setupLater = false; Setup() end end)
HU:OnStart(function()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities") then Setup() end
end)

HU:Module("UnionRoster", { "BlizzTab", "Config", "Core", "InviteLog", "Net/Packs", "Packs/Members", "Packs/Professions", "Ranks", "Roster", "Social", "Trade", "UnionCalendar", "UnionMembers" })
