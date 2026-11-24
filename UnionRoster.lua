-- Guild Union - secciones de la lista de miembros del juego (botones rojos): Miembros (todos los de la unión), Comercio, Calendario y Banco [+ARCHITECTURE.md]
local _, HU = ...
local L = HU.L
-- (unionRosterOff: la casilla «GuildUnion» de antes, que ya no está: se borra; unionRosterMine: «Solo mi hermandad»)
HU:Saved({ account = { "unionRosterOff", "unionRosterMine" } })

local ROW_H, ROWS = 18, 40
local TAB_H, HDR_H = 34, 24
local BTN_W, BTN_H = 118, 24
local TOP = 26   -- cuánto sube por encima de la lista del juego: tapa sus títulos, no la casilla ni el buscador
-- (columnas como las del juego, más «Hermandad»; ancho 0 = hasta el borde)
local COLS = {
    -- (game: el título del propio juego, en su idioma y corto, como en su lista; si no está, el nuestro)
    { key = "level", title = "Nivel", game = "COMMUNITIES_ROSTER_COLUMN_TITLE_LEVEL", w = 34 },
    { key = "class", title = "Clase", game = "COMMUNITIES_ROSTER_COLUMN_TITLE_CLASS", w = 45 },
    { key = "name", title = "Nombre", game = "COMMUNITIES_ROSTER_COLUMN_TITLE_NAME", w = 105 },
    { key = "zone", title = "Zona", game = "COMMUNITIES_ROSTER_COLUMN_TITLE_ZONE", w = 100 },
    { key = "rank", title = "Rango", game = "COMMUNITIES_ROSTER_COLUMN_TITLE_RANK", w = 85 },
    { key = "guild", title = "Hermandad", game = "GUILD", w = 58 },
    { key = "note", title = "Nota", game = "COMMUNITIES_ROSTER_COLUMN_TITLE_NOTE", w = 0 },
}
local TABS = {
    { title = "Miembros" },
    { title = "Comercio", trade = true },
    { title = "Calendario", calendar = true },
}
local tab = 1          -- 0 = Chat (solo en la vista de chat); 1 = Miembros; 2-4 = Comercio, Calendario y Banco
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

local function ShowOffline()
    local f = Win()
    local b = f and f.MemberList and f.MemberList.ShowOfflineButton
    return b and b:GetChecked() and true or false
end

local SORT = {
    level = function(e) return e.level or 0 end,
    class = function(e) return e.class or "" end,
    name = function(e) return e.name:lower() end,
    zone = function(e) return e.online == false and string.format("~%012d", e.offSecs or 0) or (e.zone or ""):lower() end,
    rank = function(e) return e.ri or 99 end,
    guild = function(e) return tostring(e.tag or "") end,
    note = function(e) return (e.note or ""):lower() end,
}
-- Por defecto: rango de hermandad, nivel (de mayor a menor) y nombre, todas las hermandades mezcladas
local function Less(a, b)
    if sortKey then
        local va, vb = SORT[sortKey](a), SORT[sortKey](b)
        if va ~= vb then if sortDesc then return va > vb end return va < vb end
    end
    if a.ri ~= b.ri then return a.ri < b.ri end
    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
    return a.name:lower() < b.name:lower()
end

-- Todos: los conectados de la unión y, con la casilla del juego marcada, los desconectados de mi hermandad
local function Entries()
    if notesDirty then ReadNotes() end
    local list = HU:UnionRosterEntries()
    if ShowOffline() then
        for _, e in ipairs(HU.rosterList) do
            if not e.online and e.name then
                list[#list + 1] = { name = e.name, tag = HU.myTag, class = e.class, level = e.level, zone = e.zone,
                    ri = e.rankIndex or 99, rank = e.rank or "", online = false, own = true, offSecs = e.offSecs }
            end
        end
    end
    -- Las listas que las otras hermandades mandan solas (RB: maestro, oficiales, enlace y ayudantes, con su
    -- rango): son las de «Oficiales conectados» y siempre están al día. Ponen el rango a quien llegó sin
    -- él (del /who) y añaden a quien falte (Jorge, 23/11)
    local byKey = {}
    for _, e in ipairs(list) do byKey[e.name:lower()] = e end
    for _, tag in ipairs(HU:OtherTags()) do
        local r = HU.remoteRoster and HU.remoteRoster[tag]
        for _, m in ipairs(r and r.members or {}) do
            if m.online and m.name and m.rankIndex then
                local rank = (m.rank and m.rank ~= "") and m.rank or HU:RankName(tag, m.rankIndex) or ""
                local have = byKey[m.name:lower()]
                if have then
                    if (have.ri or 99) >= 99 then have.ri, have.rank = m.rankIndex, rank end
                else
                    local e = { name = m.name, tag = tag, class = m.class, level = m.level, zone = m.zone, afk = m.afk,
                        ri = m.rankIndex, rank = rank, online = true }
                    list[#list + 1] = e
                    byKey[m.name:lower()] = e
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
        if e.own then e.note, e.offNote = notes[e.name:lower()], offNotes[e.name:lower()] end
    end
    table.sort(list, Less)
    return list
end

-- Las filas que caben: las demás, con la barra
local function Paint()
    if not (cover and cover:IsShown() and tab == 1) then return end
    HU:WantUnionMembers(nil)
    local list = Entries()
    shown = list
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
            if e.online == false then c.zone:SetText("|cff9d9d9d" .. Ago(e.offSecs) .. "|r")
            else c.zone:SetText((e.zone or "") .. (e.afk and (" |cff808080(" .. L("Ausente") .. ")|r") or "")) end
            c.rank:SetText(e.rank or "")
            -- (la etiqueta de la hermandad, corta; el nombre entero, en la barra de abajo y en el menú)
            c.guild:SetText("|cff" .. HU:GuildColorHex(e.tag) .. tostring(e.tag or "") .. "|r")
            c.note:SetText(e.note or "")
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
        if s ~= "" then parts[#parts + 1] = "|cff" .. HU:GuildColorHex(t) .. t .. "|r " .. s end
    end
    cover.status:SetText(table.concat(parts, "  ·  "))
end

-- Un clic del jugador aquí (botones, títulos, filas, la rueda, la barra de la lista y sus flechas): el único
-- momento en que el juego deja hacer /who (UnionMembers.lua). No con OnVerticalScroll: salta también cuando la
-- lista se recoloca sola (al pintarla o cambiar de tamaño), sin clic
-- (nunca mientras colocamos la ventana: si el cambio de vista viene de un botón seguro del juego, el /who
-- queda dentro de su clic y el juego lo bloquea: ADDON_ACTION_BLOCKED, visto el 23/11)
local inSync = false
local function WhoTick()
    if inSync or InCombatLockdown() then return end
    if cover and cover:IsShown() and tab == 1 and HU:UnionWhoTick(nil) then Paint() end
end

-- Dónde va lo nuestro: en la vista de miembros, encima de su lista; en la de chat, encima del chat y de
-- su lista de la derecha. Con «Chat» elegido, solo la fila de botones: el chat del juego se ve debajo
local function Layout()
    local f = Win()
    local ml = f and f.MemberList
    if not (cover and ml) then return end
    local tb = cover.tabs
    local chatMode = mode == "chat" and f.Chat ~= nil
    -- (los botones caben siempre: más estrechos si no hay sitio)
    local w = cover:GetWidth()
    local bw = BTN_W
    if type(w) == "number" and w > 0 then bw = math.min(BTN_W, math.floor((w - 16 - 6 * (#TABS - 1)) / #TABS)) end
    for _, b in ipairs(tb.Tabs) do b:SetWidth(bw) end
    if tb.chatSecure and not InCombatLockdown() then tb.chatSecure:SetWidth(bw) end
    -- El primer sitio cambia: en Miembros, «Chat» (el botón seguro, debajo); en Comercio y Calendario, «Miembros»
    -- (el nuestro, encima de él); en la vista de chat, «Miembros» (el seguro). Así sobra un botón [+ARCHITECTURE.md]
    for i, b in ipairs(tb.Tabs) do
        b:SetShown(not chatMode and (i > 1 or tab ~= 1))
        b:ClearAllPoints()
        b:SetPoint("LEFT", tb, "LEFT", 8 + (i - 1) * (bw + 6), 0)
    end
    -- (en la vista de chat, los botones seguros que pasan a la vista de miembros con esa sección. Se colocan fuera
    -- de combate, que es cuando el juego deja mover un botón seguro)
    if chatMode and tb.chatModeBtns and not InCombatLockdown() then
        for i, b in ipairs(tb.chatModeBtns) do
            b:SetWidth(bw)
            b:ClearAllPoints()
            -- (con la fila, no con el chat, que baja)
            b:SetPoint("LEFT", f.CommunitiesList, "TOPRIGHT", 23 + 8 + (i - 1) * (bw + 6), -34 - TAB_H / 2)
        end
    end
    cover:ClearAllPoints()
    if chatMode then
        -- (el chat empieza 17 más arriba que su lista de la derecha; y 6 más arriba aún, para tapar el
        -- borde de arriba del chat, que se veía como una raya encima de los botones)
        -- (atado a la ventana y a la columna de comunidades, no al chat, que baja: ver Sync)
        -- (justo debajo del desplegable «Guild» y del buscador: 59 bajo el borde de la ventana)
        -- (exactamente donde va en la vista de miembros: allí es la lista del juego, -3 y +26, y esa lista va
        -- a 26 y -60 de la columna de comunidades. Todo atado a la columna: la misma fila en las dos vistas)
        cover:SetPoint("TOPLEFT", f.CommunitiesList, "TOPRIGHT", 23, -34)
        -- (en la vista de chat siempre está «Chat» elegido: solo la fila. A la derecha, hasta el borde de la
        -- ventana: atado a la ventana y no a la lista de la derecha, que baja; ver Sync)
        -- (el borde derecho, a 4 del de la ventana, pero a la misma altura: atado también a la columna)
        local clRight, fRight = f.CommunitiesList:GetRight(), f:GetRight()
        local dx = (type(clRight) == "number" and type(fRight) == "number") and (fRight - clRight - 4) or 640
        cover:SetPoint("TOPRIGHT", f.CommunitiesList, "TOPRIGHT", dx, -34)
        cover:SetHeight(TAB_H)
    else
        cover:SetPoint("TOPLEFT", ml, "TOPLEFT", -3, TOP)
        -- (hasta 22 más a la derecha: tapa también la barra de la lista del juego, que se veía al lado de la nuestra)
        cover:SetPoint("BOTTOMRIGHT", ml, "BOTTOMRIGHT", 22, 0)
    end
    -- (con «Chat», los clics pasan al chat del juego salvo en los botones)
    cover:EnableMouse(tab ~= 0)
    cover.rock:SetHeight(tab == 0 and TAB_H or TAB_H + HDR_H + 2)
    cover.dark:SetShown(tab ~= 0)
end

local function ShowTab(i)
    tab = i
    if RealList() then
        -- (Miembros con «Solo mi hermandad»: la lista del juego; lo nuestro, fuera. La casilla sigue, para volver)
        cover:Hide()
        if mine then mine:Show() end
        return
    end
    -- (el botón elegido, negro con borde dorado y letra blanca; los demás, rojos: DJStyle.lua)
    cover.tabs.selectedTab = i
    for k, b in ipairs(cover.tabs.Tabs) do HU.DJ.PickRed(b, k == i) end
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
    Layout()
    Paint()
end

-- La ficha de un miembro (clic izquierdo en Miembros): como la del juego, pero nuestra, para todas las
-- hermandades. La del juego no se abre desde aquí: abierta por un addon, el juego bloquearía sus botones
-- (expulsar, rango, notas) [+ARCHITECTURE.md]
local card
local RemoveFromGuild   -- (más abajo, con el clic derecho; lo usa también el botón de la ficha)

-- (las notas solo se guardan con la ficha del juego: un clic en las nuestras lleva a la lista del juego, «Solo mi
-- hermandad», con esa persona marcada por el buscador —flecha y resaltado, sin tocar la lista: BlizzTab.lua—)
local function EditNotesInGame(e)
    HU.db.unionRosterMine = true
    if mine then mine:SetChecked(true) end
    if card then card:Hide() end
    if SyncNow then SyncNow() end
    HU:Print(string.format(L("Las notas se cambian en la ficha del juego: pincha en %s en esta lista."), HU:Nice(e.name)))
    HU.After(0.1, function() HU.MarkInGameList(e.name) end)
end

-- Profesiones de alguien de mi hermandad (las da el juego por su comunidad de hermandad; de las otras
-- hermandades no llegan todavía)
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
            local out = {}
            for _, k in ipairs({ "1", "2" }) do
                local pid, pn, pr = info["profession" .. k .. "ID"], info["profession" .. k .. "Name"], info["profession" .. k .. "Rank"]
                if type(pn) == "string" and pn ~= "" and not HU.Secret(pn) then
                    local icon
                    if type(pid) == "number" and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture then
                        local okI, tex = pcall(C_TradeSkillUI.GetTradeSkillTexture, pid)
                        if okI and tex and not HU.Secret(tex) then icon = tex end
                    end
                    out[#out + 1] = { id = pid, name = pn, icon = icon, guid = info.guid,
                        rank = (type(pr) == "number" and not HU.Secret(pr)) and pr or nil }
                end
            end
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
        local b = CreateFrame("Button", "GuildUnionMemberCardRecipes" .. k, rows, "UIPanelButtonTemplate")
        b:SetSize(110, 20)
        b:SetPoint("LEFT", lvl, "RIGHT", 2, 0)
        b:SetText(L("Ver recetas"))
        b:SetScript("OnClick", function(s)
            local q = C_GuildInfo and C_GuildInfo.QueryGuildMemberRecipes
            if q and s.prof and s.prof.guid and s.prof.id then pcall(q, s.prof.guid, s.prof.id) end
        end)
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
    local noteBox
    noteBox, card.lines[6] = NoteBox(GT("NOTE_COLON", "Nota"), rows, -4)
    local offBox, offText = NoteBox(GT("OFFICER_NOTE_COLON", "Nota de oficial"), noteBox, -4)
    card.lines[7] = offText
    -- (de mi hermandad: un clic en una nota lleva a la ficha del juego, la única que las guarda)
    for _, box in ipairs({ noteBox, offBox }) do
        box:EnableMouse(true)
        box:SetScript("OnMouseUp", function() if card.entry and card.entry.own then EditNotesInGame(card.entry) end end)
        box:SetScript("OnEnter", function(s)
            if not (card.entry and card.entry.own) then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(L("Editar las notas"))
            GameTooltip:AddLine(L("El juego solo deja cambiarlas en su ficha: te llevo a su lista con esta persona marcada."), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

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
    v[1]:SetText("|cff" .. HU:GuildColorHex(e.tag) .. "<" .. tostring(e.tag or "") .. ">  " .. HU:GuildName(e.tag) .. "|r")
    v[2]:SetText((e.zone and e.zone ~= "") and e.zone or "—")
    v[3]:SetText((not e.noRank and e.rank ~= "" and e.rank) or "—")
    v[4]:SetText(e.online and ("|cff40ff40" .. L("Conectado") .. "|r") or Ago(e.offSecs))
    -- (profesiones: una línea cada una, su icono con el nivel y «Ver recetas»)
    local profs = e.own and OwnProfessions(e.name) or {}
    local rows = card.recipes
    for k = 1, 2 do
        local p = profs[k]
        rows.btns[k].prof = p
        rows.icons[k]:SetShown(p ~= nil); rows.levels[k]:SetShown(p ~= nil); rows.btns[k]:SetShown(p ~= nil)
        if p then
            rows.icons[k]:SetTexture(p.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            rows.levels[k]:SetText(p.rank and tostring(p.rank) or "")
            rows.btns[k]:SetText(p.icon and L("Ver recetas") or (p.name .. ": " .. L("Ver recetas")))
        end
    end
    v[5]:SetText(#profs == 0 and "—" or "")
    -- (de mi hermandad, si mi rango me deja echarlo; de otra, si soy oficial: se le pide a su hermandad)
    card.remove:SetEnabled((e.own == true and HU:CanKickMember(e.name)) or (not e.own and e.tag ~= nil and HU:CanOfficer()))
    v[6]:SetText((e.note and e.note ~= "") and e.note or "")
    v[7]:SetText((e.offNote and e.offNote ~= "") and e.offNote or "")
    card:Show()
end

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

local function Build(f)
    local ml = f and f.MemberList
    local anchor = ml and ml.ShowOfflineButton
    if cover or not anchor then return end

    -- Encima de la lista del juego y de sus títulos (sin tocarla: hija de la ventana, no de su lista).
    -- La casilla de desconectados y el buscador quedan a la vista, encima
    cover = CreateFrame("Frame", "GuildUnionUnionRoster", f, "BackdropTemplate")
    cover:HookScript("OnHide", function() HU.charSearchOff = false; HU.SyncCharSearch() end)
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

    -- Arriba, los botones rojos del juego (como «Guild Settings»), uno por sección
    local tabs = CreateFrame("Frame", nil, cover)
    tabs:SetPoint("TOPLEFT", 0, 0); tabs:SetPoint("TOPRIGHT", 0, 0); tabs:SetHeight(TAB_H)
    -- (detrás de los botones y de los títulos, la misma piedra que el juego pone encima, como en su
    -- lista: así no se ven rayas; el fondo oscuro empieza en la primera fila)
    -- (en el marco de abajo del todo, no en el de los botones: si no, tapa los títulos)
    local rock = cover:CreateTexture(nil, "BACKGROUND")
    rock:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    rock:SetHorizTile(true); rock:SetVertTile(true)
    rock:SetPoint("TOPLEFT", cover, "TOPLEFT"); rock:SetPoint("TOPRIGHT", cover, "TOPRIGHT")
    rock:SetHeight(TAB_H + HDR_H + 2)
    cover.rock = rock
    tabs.Tabs = {}
    -- Abajo, como en la vista del chat: Peticiones de oficiales · Registro · Invitar miembro, a la izquierda de
    -- «Ajustes de hermandad» (Jorge, 23/11). El juego solo enseña su «Invitar miembro» en la vista del chat: aquí lo
    -- pulsa un botón seguro (si lo pulsara el addon, el juego bloquearía la invitación). Cuelgan de la casilla de
    -- desconectados, como el «Chat» seguro: solo se ven en la vista de miembros [+ARCHITECTURE.md]
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
        local log = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
        log:SetSize(120, 20)
        log:SetText(L("Ver registro"))
        log:SetPoint("RIGHT", inv, "LEFT", -4, 0)
        log:SetFrameStrata("HIGH")
        log:SetScript("OnClick", function() HU:ShowInviteLog() end)
        local rq = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
        rq:SetSize(140, 20)
        rq:SetPoint("RIGHT", log, "LEFT", -4, 0)
        rq:SetFrameStrata("HIGH")
        rq:SetScript("OnClick", function() HU:ShowRequests() end)
        local function SyncRequests()
            local n = HU:KickRequestCount()
            rq:SetText(n > 0 and (L("Peticiones de oficiales") .. " (" .. n .. ")") or L("Peticiones de oficiales"))
            if n > 0 then rq:LockHighlight() else rq:UnlockHighlight() end
        end
        HU:Listen("CHANGED", function(what) if what == "requests" then SyncRequests() end end)
        rq:HookScript("OnShow", SyncRequests)
        SyncRequests()
    end
    -- («Chat» en la vista de miembros: un botón seguro que pulsa el icono del chat del juego. Si lo pulsara
    -- el addon, la ventana quedaría «tocada» y el juego bloquearía rangos y notas. Es hijo de la casilla
    -- de desconectados, que solo se ve en la vista de miembros: así no hay que enseñarlo ni esconderlo en
    -- combate, que el juego no deja hacer con un botón seguro)
    local chatSecure = CreateFrame("Button", "GuildUnionRosterChatSecure", anchor, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    chatSecure:SetSize(BTN_W, BTN_H)
    chatSecure:SetText(L("Chat"))
    chatSecure:SetPoint("LEFT", ml, "TOPLEFT", 5, TOP - TAB_H / 2)
    chatSecure:SetFrameStrata("HIGH")
    chatSecure:SetFrameLevel(cover:GetFrameLevel() + 8)
    chatSecure:RegisterForClicks("AnyUp", "AnyDown")
    chatSecure:SetAttribute("type", "click")
    chatSecure:SetAttribute("clickbutton", f.ChatTab)
    tabs.chatSecure = chatSecure
    -- (al pulsarlo, la vista cambia y el botón se esconde antes de soltar el ratón: se quedaba «pulsado», con la
    -- letra movida hacia abajo. Al volver a verse, se deja suelto) [+ARCHITECTURE.md]
    local function Unpress(b)
        b:HookScript("OnShow", function(s2)
            if InCombatLockdown() then return end
            pcall(s2.SetButtonState, s2, "NORMAL")
            local up = s2:GetScript("OnMouseUp")
            if up then pcall(up, s2, "LeftButton") end
        end)
    end
    Unpress(chatSecure)
    -- (Miembros, Comercio y Calendario en la vista de chat: botones seguros que pulsan el icono de miembros del juego; antes,
    -- PreClick apunta qué sección abrir al llegar. Hijos del chat del juego: solo se ven en esa vista)
    if f.Chat then
        tabs.chatModeBtns = {}
        for i, t in ipairs(TABS) do
            local b = CreateFrame("Button", "GuildUnionChatSection" .. i, f.Chat, "SecureActionButtonTemplate,UIPanelButtonTemplate")
            b:SetSize(BTN_W, BTN_H)
            b:SetText(L(t.title))
            b:SetFrameStrata("HIGH")
            b:SetFrameLevel(cover:GetFrameLevel() + 8)
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:SetAttribute("type", "click")
            b:SetAttribute("clickbutton", f.RosterTab)
            b:SetScript("PreClick", function() wantTab = i end)
            Unpress(b)
            tabs.chatModeBtns[i] = b
        end
    end
    for i, t in ipairs(TABS) do
        local b = CreateFrame("Button", "GuildUnionRosterSection" .. i, tabs, "UIPanelButtonTemplate")
        b:SetSize(BTN_W, BTN_H)
        b:SetText(L(t.title))
        if i == 1 then b:SetPoint("LEFT", tabs, "LEFT", 8, 0)
        else b:SetPoint("LEFT", tabs.Tabs[i - 1], "RIGHT", 6, 0) end
        b:SetScript("OnClick", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB); ShowTab(i); WhoTick() end)
        tabs.Tabs[i] = b
    end
    -- («Miembros» va en el sitio del «Chat» seguro y, cuando se ve, encima de él: Layout)
    tabs.Tabs[1]:SetFrameLevel(cover:GetFrameLevel() + 10)
    tabs.numTabs = #TABS
    cover.tabs = tabs
    -- (los botones, por encima de todo lo nuestro: que nada los tape)
    tabs:SetFrameLevel(cover:GetFrameLevel() + 6)

    -- Los títulos de las columnas, como los del juego; un clic ordena por esa columna
    local hdr = CreateFrame("Frame", nil, cover)
    hdr:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -2)
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
    cover.trade:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -2)
    cover.trade:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", 0, 4)
    cover.trade:SetFrameLevel(cover:GetFrameLevel() + 5)
    cover.trade:Hide()
    HU:BuildTrade(cover.trade)
    -- (la sección Calendario, UnionCalendar.lua: igual)
    cover.calendar = CreateFrame("Frame", nil, cover)
    cover.calendar:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -2)
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
    cover:SetScript("OnEvent", function() notesDirty = true; Paint() end)
    HU:Listen("CHANGED", function(what) if what == "unionMembers" then Paint() end end)
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
    mine:SetPoint("BOTTOMLEFT", ml, "TOPRIGHT", -120, TOP + 2)
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
    -- (en la vista de chat, el chat y su lista de la derecha empiezan justo debajo de la fila de botones:
    -- atados a ella, así no hay que calcular nada. De vuelta en la de miembros, Sync los devuelve a su sitio)
    local placing = false
    local function ChatAnchors()
        if GameLocked() then return end
        placing = true
        ml:SetPoint("TOPLEFT", cover, "BOTTOMRIGHT", -161, -2)
        f.Chat:SetPoint("TOPLEFT", cover, "BOTTOMLEFT", 6, -2)
        placing = false
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
            perGuild[#perGuild + 1] = "|cff" .. HU:GuildColorHex(HU.myTag) .. HU.myTag .. "|r  " .. online .. " / " .. total
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

HU:Module("UnionRoster", { "BlizzTab", "Config", "Core", "InviteLog", "Ranks", "Roster", "Social", "Trade", "UnionCalendar", "UnionMembers" })
