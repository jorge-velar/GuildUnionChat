-- Comercio (Trade.lua): las líneas sin leer, «¿puedo hacerlo?» (HU:CanCraft, con las recetas que se leen al abrir la
-- ventana de una profesión), «Solo lo que puedo hacer», «+ Nueva solicitud» y el aspecto (qué va dónde y que quepa).
-- Lo de antes de Comercio sigue en miembros_spec.
local F = require("lib.fixtures")
local A = assert_

---------------------------------------------------------------------------
-- El WoW de mentira, con lo que aquí hace falta mirar
---------------------------------------------------------------------------
-- (lo que no guarda: activado, marcado, tamaño, alto, puntos, colores (tinte, relleno, letra, fondo y borde), letras,
-- transparencia, y las texturas de casilla (una de mentira por marco))
local function Observe(a)
    local meta = a.w.frameMeta
    local base = meta.__index
    local function Tex(self, key)
        local t = rawget(self, key)
        if not t then t = self:CreateTexture(); rawset(self, key, t) end
        return t
    end
    local extra = {
        SetEnabled = function(self, v) rawset(self, "_off", not v) end,
        IsEnabled = function(self) return not rawget(self, "_off") end,
        SetChecked = function(self, v) rawset(self, "_checked", v and true or false) end,
        GetChecked = function(self) return rawget(self, "_checked") == true end,
        SetSize = function(self, w, h) rawset(self, "_w", w); rawset(self, "_h", h) end,
        SetWidth = function(self, w) rawset(self, "_w", w) end,
        SetHeight = function(self, h) rawset(self, "_h", h) end,
        ClearAllPoints = function(self) rawset(self, "_pts", {}) end,
        SetPoint = function(self, p, ...)
            local pts = rawget(self, "_pts") or {}
            rawset(self, "_pts", pts)
            pts[p] = { ... }
        end,
        SetVertexColor = function(self, ...) rawset(self, "_color", { ... }) end,
        SetTexture = function(self, t) rawset(self, "_tex", t) end,
        SetColorTexture = function(self, ...) rawset(self, "_fill", { ... }) end,
        SetTextColor = function(self, ...) rawset(self, "_textColor", { ... }) end,
        SetBackdropColor = function(self, ...) rawset(self, "_bg", { ... }) end,
        SetBackdropBorderColor = function(self, ...) rawset(self, "_edge", { ... }) end,
        SetBackdrop = function(self, b) rawset(self, "_backdrop", b) end,
        SetNormalFontObject = function(self, font) rawset(self, "_font", font) end,
        SetFontObject = function(self, font) rawset(self, "_fontObj", font) end,
        SetFont = function(self, _, size) rawset(self, "_fontSize", size) end,
        SetAlpha = function(self, v) rawset(self, "_alpha", v) end,
        GetNormalTexture = function(self) return Tex(self, "_normalTex") end,
        GetPushedTexture = function(self) return Tex(self, "_pushedTex") end,
    }
    meta.__index = function(f, k) return extra[k] or base(f, k) end
end

-- La sección con la ventana del juego a su tamaño de siempre (814 x 426). La lista de miembros del juego, en su vista
-- (Blizzard_Communities: CommunitiesFrame.xml y CommunitiesMemberList.lua), va de 26 a la derecha de la columna de
-- comunidades (que acaba en 170) a 26 del borde derecho, y de 60 por debajo de esa columna (que empieza 23 por debajo
-- del borde de arriba) a 28 del de abajo. Lo nuestro (UnionRoster.lua) empieza 3 a su izquierda, acaba 22 a su derecha y
-- sube 57 (TOP 26 y ROW_UP 31); la sección deja 2 arriba y 4 abajo
local SECTION_W = (814 - 26 + 22) - (170 + 26 - 3)        -- 617
local SECTION_H = (426 - 28 - 4) - ((23 + 60 - 57) + 2)   -- 366

-- Lo que mide un texto en la letra del juego (Friz Quadrata, FRIZQT__.TTF; el WoW de mentira mide 0): el avance de cada
-- letra en milésimas de su tamaño, leído del archivo de la letra (sin kerning), y un 5 % más por lo que redondea el juego
local FRIZ = { [" "] = 261, ["("] = 322, [")"] = 325, ["+"] = 640, ["."] = 257, [":"] = 257, ["<"] = 640,
    A = 767, B = 633, C = 670, D = 743, E = 550, F = 469, G = 793, H = 791, I = 304, J = 290, K = 657, L = 552, M = 1003,
    N = 788, O = 856, P = 577, Q = 855, R = 633, S = 580, T = 538, U = 752, V = 655, W = 1002, X = 722, Y = 638, Z = 654,
    a = 545, b = 588, c = 521, d = 624, e = 582, f = 333, g = 619, h = 589, i = 256, j = 254, k = 528, l = 252, m = 926,
    n = 593, o = 631, p = 627, q = 625, r = 349, s = 467, t = 347, u = 589, v = 568, w = 833, x = 552, y = 561, z = 517,
    ["á"] = 545, ["é"] = 582, ["í"] = 256, ["ó"] = 631, ["ú"] = 589, ["ñ"] = 593, ["ü"] = 589,
    ["Á"] = 767, ["É"] = 550, ["Í"] = 304, ["Ó"] = 856, ["Ú"] = 752, ["Ñ"] = 788 }
for d = 0, 9 do FRIZ[tostring(d)] = 640 end
local function TextWidth(text, size)
    local w = 0
    for ch in text:gmatch("[\1-\127\194-\244][\128-\191]*") do w = w + assert(FRIZ[ch], "sin el ancho de «" .. ch .. "»") end
    return w * size / 1000 * 1.05
end

-- (de izquierda a derecha, dónde queda un marco de la sección (de 0 a SECTION_W): por su punto y su ancho, siguiendo a
-- los marcos a los que se ata)
local function Span(tr, f)
    if f == tr then return 0, SECTION_W end
    local n, p, pt = 0, nil, nil
    for k, v in pairs(f._pts or {}) do n, p, pt = n + 1, k, v end
    assert(n == 1, "se esperaba un solo punto")
    local rl, rr = Span(tr, pt[1])
    local x = (pt[2]:find("LEFT") and rl) or (pt[2]:find("RIGHT") and rr) or (rl + rr) / 2
    x = x + (pt[3] or 0)
    if p:find("LEFT") then return x, x + f._w end
    if p:find("RIGHT") then return x - f._w, x end
    return x - f._w / 2, x + f._w / 2
end

-- (¿se ve? él y todos los de encima, como IsVisible en el juego)
local function Visible(f)
    while f do
        if f._shown == false then return false end
        f = f._parent
    end
    return true
end

-- (la ventana de hermandad del juego, lo justo para que salga la nuestra: como en miembros_spec)
local function GuildWindow(a)
    local f = a.env.CreateFrame("Frame", "CommunitiesFrame")
    f.Chat, f.GuildInfoTab, f.CommunitiesControlFrame = false, false, false
    f.ChatTab = a.env.CreateFrame("CheckButton", nil, f)
    f.RosterTab = a.env.CreateFrame("CheckButton", nil, f)
    f.CommunitiesList = a.env.CreateFrame("Frame", nil, f)
    f.MemberList = a.env.CreateFrame("Frame", nil, f)
    f.MemberList.IsVisible = function() return true end
    local chk = a.env.CreateFrame("CheckButton", nil, f.MemberList)
    f.MemberList.ShowOfflineButton = chk
    chk.IsVisible = function() return true end
    a.w:Fire("ADDON_LOADED", "Blizzard_Communities")
    return f
end

-- La sección Comercio a la vista: se enseña ella (sin las pestañas de UnionRoster.lua) y sabe si se ve
local function OpenTrade(a)
    GuildWindow(a)
    local tr = a.env.GuildUnionUnionRoster.trade
    tr.IsVisible = function(self) return Visible(self) end
    tr:Show()
    return tr
end

local function Click(b, ...) return b:GetScript("OnClick")(b, ...) end
-- (una casilla del juego se marca o desmarca sola al pulsarla, antes de su OnClick; en el WoW de mentira, no: se hace aquí)
local function Toggle(c, ...)
    c:SetChecked(not c:GetChecked())
    return Click(c, ...)
end
-- (las filas de la lista de solicitudes que se ven, en orden; la de un objeto)
local function Rows(tr)
    local out = {}
    for _, r in ipairs(tr.req.rows) do if r:IsShown() and r.entry then out[#out + 1] = r end end
    return out
end
local function Row(tr, text)
    for _, r in ipairs(Rows(tr)) do if r.entry.item:find(text, 1, true) then return r end end
end
-- (los objetos de las filas que se ven, por su nombre)
local function Items(tr)
    local out = {}
    for i, r in ipairs(Rows(tr)) do out[i] = r.entry.item:match("%[(.-)%]") or r.entry.item end
    return out
end
-- (el botón de `parent` con ese texto)
local function Btn(a, parent, text)
    for _, fr in ipairs(a.w.frames) do if fr._parent == parent and fr:GetText() == text then return fr end end
end
-- (lo que sale al pasar el ratón: el título y las líneas de debajo; nil si no sale nada)
local function Hover(a, b)
    local tip = a.env.GameTooltip
    local lines = {}
    tip:Hide(); tip:SetText("")
    tip.AddLine = function(_, text) lines[#lines + 1] = text end
    b:GetScript("OnEnter")(b)
    if not tip:IsShown() then return nil end
    table.insert(lines, 1, tip:GetText())
    return lines
end
local function Search(tr, text)
    tr.search:SetText(text)
    tr.search:GetScript("OnTextChanged")(tr.search)
end

-- Mis profesiones en el juego, { [número] = nivel }: como en Forever, GetProfessions da sus índices (con huecos) y
-- GetProfessionInfo, de cada uno, nombre, icono, nivel, máximo, hechizos, desplazamiento y número de profesión
local function Professions(a, list)
    local idx = {}
    for skill, rank in pairs(list) do idx[#idx + 1] = { skill = skill, rank = rank } end
    table.sort(idx, function(x, y) return x.skill < y.skill end)
    a.env.GetProfessions = function()
        return idx[1] and 1 or nil, idx[2] and 2 or nil, idx[3] and 3 or nil, nil, idx[4] and 4 or nil
    end
    a.env.GetProfessionInfo = function(i)
        local p = idx[i]
        if p then return "Profesión " .. p.skill, "icono", p.rank, 300, 2, 0, p.skill, 0, 0, 0, "Profesión" end
    end
end
local function ItemLink(id, name)
    return "|cff1eff00|Hitem:" .. id .. "::::::::60:::::::|h[" .. (name or ("Objeto " .. id)) .. "]|h|r"
end
local function SpellLink(id, kind) return "|cff71d5ff|H" .. (kind or "spell") .. ":" .. id .. "|h[Encantar " .. id .. "]|h|r" end

---------------------------------------------------------------------------
-- Sin leer
---------------------------------------------------------------------------
describe("Comercio (Trade.lua): líneas sin leer", function()
    it("las de otro con su chat fuera de la pantalla cuentan; se leen al ponerse en pantalla (Mis encargos, sin buscar, a la vista)", function()
        local a = F.Community()
        local HU = a.HU
        local seen = {}
        HU:Listen("CHANGED", function(what) if what == "tradeUnread" then seen[#seen + 1] = HU:TradeUnread() end end)
        local tr = OpenTrade(a)
        A.equal(0, HU:TradeUnread())
        A.equal("Mis encargos", tr.viewBtns.priv:GetText())
        -- (el modo prueba trae una línea de Lyra, una de Pepe y una de Bea; en el Tablón no se ve ningún chat)
        HU:TradeTest(true)
        A.equal(3, HU:TradeUnread())
        A.same({ 1, 2, 3 }, seen)
        A.equal("Mis encargos (3)", tr.viewBtns.priv:GetText())
        A.equal("Tablón", tr.viewBtns.pub:GetText())
        -- (en Mis encargos, sin chat elegido: siguen sin leer, y cada uno lo lleva detrás del nombre)
        Click(tr.viewBtns.priv)
        A.equal(3, HU:TradeUnread())
        A.matches("Lyra.*%(1%)", Row(tr, "Cofia").cells[1]:GetText())
        A.matches("Pepe.*%(1%)", Row(tr, "espada").cells[1]:GetText())
        A.falsy(Row(tr, "Poción").cells[1]:GetText():find("(", 1, true), "Jandra no ha escrito")
        -- (abrir el chat de Lyra lo deja leído)
        A.equal(3, HU:TradeUnreadChats(), "tres chats con algo sin leer")
        Click(Row(tr, "Cofia"), "LeftButton")
        A.equal(2, HU:TradeUnread())
        A.equal(2, HU:TradeUnreadChats())
        A.equal("Mis encargos (2)", tr.viewBtns.priv:GetText())
        A.falsy(Row(tr, "Cofia").cells[1]:GetText():find("(", 1, true))
        -- (con su chat en pantalla, lo que escribe ya está leído; lo mío nunca cuenta, ni escrito en su caja)
        HU:TradeChatLine("Lyra-Prueba", "Lyra-Prueba", "¿Lo tienes?")
        HU:TradeChatLine("Bea-Prueba", HU:Me(), "Ya voy")
        tr.chatInput:SetText("Mañana te la doy")
        tr.chatInput:GetScript("OnEnterPressed")(tr.chatInput)
        A.equal(2, HU:TradeUnread())
        -- (la sección escondida: cuenta; al volver a enseñarse con su chat puesto, leído)
        tr:Hide()
        HU:TradeChatLine("Lyra-Prueba", "Lyra-Prueba", "¿Sigues?")
        A.equal(3, HU:TradeUnread())
        tr:Show()
        A.equal(2, HU:TradeUnread())
        -- (buscando no hay chat: cuenta; al dejar de buscar, leído)
        Search(tr, "mitril")
        HU:TradeChatLine("Lyra-Prueba", "Lyra-Prueba", "¿Hola?")
        A.equal(3, HU:TradeUnread())
        Search(tr, "")
        A.equal(2, HU:TradeUnread())
        -- (con el comercio apagado por el maestro tampoco se ve)
        HU:UnionCfg().tradeOff = true
        HU:Changed("unionCfg")
        HU:TradeChatLine("Lyra-Prueba", "Lyra-Prueba", "¿?")
        A.equal(3, HU:TradeUnread())
        HU:UnionCfg().tradeOff = nil
        HU:Changed("unionCfg")
        A.equal(2, HU:TradeUnread())
        -- (fuera el modo prueba: fuera sus líneas sin leer)
        HU:TradeTest(false)
        A.equal(0, HU:TradeUnread())
        A.equal("Mis encargos", tr.viewBtns.priv:GetText())
        A.same({ 1, 2, 3, 2, 3, 2, 3, 2, 3, 2, 0 }, seen, "un aviso «tradeUnread» con cada cambio")
        A.same({}, a:Errors())
    end)

    it("aceptar en el Tablón pone su chat sin verse: sigue sin leer hasta ir a Mis encargos", function()
        local a = F.Community()
        local HU = a.HU
        local tr = OpenTrade(a)
        HU:TradeTest(true)
        Click(Row(tr, "Bolsa").accept)
        A.equal("taken", Row(tr, "Bolsa").entry.state)
        A.equal(3, HU:TradeUnread(), "la de Pepe, sin leer")
        Click(tr.viewBtns.priv)
        A.equal(2, HU:TradeUnread(), "en Mis encargos, con su chat: leída")
        A.falsy(Row(tr, "Bolsa").cells[1]:GetText():find("(", 1, true), "y su fila ya no lo lleva")
        A.matches("Bea.*%(1%)", Row(tr, "Elixir").cells[1]:GetText())
        A.same({}, a:Errors())
    end)

    it("en inglés, la pestaña con el número: «My Orders (3)»", function()
        local a = F.Community({ locale = "enUS" })
        local tr = OpenTrade(a)
        a.HU:TradeTest(true)
        A.same({ "Board", "My Orders (3)" }, { tr.viewBtns.pub:GetText(), tr.viewBtns.priv:GetText() })
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
-- ¿Puedo hacerlo?
---------------------------------------------------------------------------
describe("Comercio (Trade.lua): ¿puedo hacerlo? (HU:CanCraft)", function()
    it("por profesión y nivel; lo que no se reconoce o sin poder leer mis profesiones, sí", function()
        local a = F.Community()
        local HU = a.HU
        -- (sin la función del juego no se puede comprobar: todo sí)
        A.same({ true }, { HU:CanCraft(ItemLink(7956)) })
        -- (Herrería a 230 y Cocina a 50)
        Professions(a, { [164] = 230, [185] = 50 })
        A.same({ true }, { HU:CanCraft(ItemLink(7936)) }, "Herrería 225")
        A.same({ false, "Te falta nivel (235)" }, { HU:CanCraft(ItemLink(7960)) })
        A.same({ false, "Te falta Sastrería" }, { HU:CanCraft(ItemLink(7056)) })
        -- (un encantamiento es un hechizo: su enlace de hechizo o el de la ventana de la profesión)
        A.same({ false, "Te falta Encantamiento" }, { HU:CanCraft(SpellLink(7418)) })
        A.same({ false, "Te falta Encantamiento" }, { HU:CanCraft(SpellLink(7418, "enchant")) })
        -- (lo que no está entre los fabricables, no se puede comprobar)
        A.same({ true }, { HU:CanCraft("Algo que no existe") })
        A.same({ true }, { HU:CanCraft(ItemLink(6948, "Piedra de hogar")) })
        A.same({ true }, { HU:CanCraft(nil) })
        -- (la barra de oro, de Alquimia y de Minería: vale cualquiera; sin ninguna, la primera)
        A.same({ false, "Te falta Alquimia" }, { HU:CanCraft(ItemLink(3577)) })
        Professions(a, { [186] = 160 })
        A.same({ true }, { HU:CanCraft(ItemLink(3577)) }, "Minería 155")
        -- (sin profesiones)
        Professions(a, {})
        A.same({ false, "Te falta Herrería" }, { HU:CanCraft(ItemLink(7936)) })
        -- (si el juego falla al darlas, no se puede comprobar)
        a.env.GetProfessions = function() error("fallo") end
        A.same({ true }, { HU:CanCraft(ItemLink(7936)) })
        A.same({}, a:Errors())
    end)

    it("lo escrito a mano se reconoce por el nombre exacto que da el juego (con o sin corchetes)", function()
        local a = F.Community()
        local HU = a.HU
        local names = { [7960] = "Espada de prueba", [7936] = "Botas de prueba" }
        a.env.C_Item.GetItemInfo = function(id)
            if type(id) ~= "number" then return nil end
            local name = names[id] or ("Objeto " .. id)
            return name, ItemLink(id, name)
        end
        Professions(a, { [164] = 230 })
        OpenTrade(a)
        a.w:Advance(40) -- (los nombres se piden poco a poco: 30 cada medio segundo)
        A.same({ true }, { HU:CanCraft("botas de prueba") })
        A.same({ false, "Te falta nivel (235)" }, { HU:CanCraft("[Espada de prueba]") })
        A.same({ true }, { HU:CanCraft("Espada de otra prueba") }, "otro nombre: no se reconoce")
        A.same({}, a:Errors())
    end)

    it("las recetas, al abrir la ventana de la profesión: por personaje; sin la suya, «No tienes la receta»", function()
        local a = F.Community()
        local HU = a.HU
        Professions(a, { [164] = 230 })
        -- (la ventana de Herrería: cuatro recetas, una sin aprender, y una que el juego no da (falla); la receta crea el
        -- objeto de `out`)
        local list = { 9001, 9002, 9003, 9005, 9999 }
        local out = { [9001] = 7936, [9002] = 7954, [9003] = 7959, [9005] = 12416 }
        local learned = { [9001] = true, [9002] = true, [9005] = true }
        local prof = { professionID = 2437, parentProfessionID = 164 }
        local st, reads = { ready = true }, 0
        local T = {
            IsTradeSkillReady = function() return st.ready end,
            IsTradeSkillLinked = function() return st.linked == true end,
            GetChildProfessionInfo = function() return prof end,
            GetFilteredRecipeIDs = function() reads = reads + 1; return list end,
            GetRecipeInfo = function(id)
                if id == 9999 then error("receta que no hay") end
                return { recipeID = id, learned = learned[id] == true }
            end,
            GetRecipeSchematic = function(id) return { recipeID = id, outputItemID = out[id] } end,
            GetOnlyShowMakeableRecipes = function() return st.makeable == true end,
        }
        a.env.C_TradeSkillUI = T
        local function Open(ev)
            a.w:Fire(ev or "TRADE_SKILL_SHOW")
            a.w:Advance(1)
        end
        -- (sin abrirla nunca: basta el nivel)
        A.same({ true }, { HU:CanCraft(ItemLink(7959)) })
        -- (el juego avisa varias veces seguidas: se lee una)
        a.w:Fire("TRADE_SKILL_SHOW"); a.w:Fire("TRADE_SKILL_LIST_UPDATE")
        Open("TRADE_SKILL_LIST_UPDATE")
        A.equal(1, reads)
        local saved = HU.cdb.tradeRecipes[164]
        A.truthy(saved and saved.full, "leída entera")
        A.same({ [7936] = true, [7954] = true, [12416] = true }, saved.items)
        A.same({ [9001] = true, [9002] = true, [9005] = true }, saved.spells)
        A.is_nil(HU.adb.tradeRecipes, "de cada personaje, no de la cuenta")
        A.same({ false, "No tienes la receta" }, { HU:CanCraft(ItemLink(7959)) })
        A.same({ true }, { HU:CanCraft(ItemLink(7936)) })
        A.same({ true }, { HU:CanCraft(ItemLink(12416)) }, "con la receta aprendida, aunque pida 235")
        A.same({ false, "Te falta nivel (235)" }, { HU:CanCraft(ItemLink(7960)) }, "sin nivel, eso primero")
        -- (la de otro (enlazada), sin estar lista o aún sin recetas: no se lee ni se pisa lo guardado)
        learned[9003] = true
        st.linked = true; Open()
        st.linked, st.ready = nil, false; Open()
        st.ready = true
        local before = list
        list = {}; Open()
        list = before
        A.same({ false, "No tienes la receta" }, { HU:CanCraft(ItemLink(7959)) })
        A.same({ true }, { HU:CanCraft(ItemLink(7936)) })
        -- (con un filtro de la ventana viene una parte: se suma a lo de antes)
        st.makeable, list = true, { 9003 }
        Open()
        A.same({ true }, { HU:CanCraft(ItemLink(7959)) })
        A.same({ true }, { HU:CanCraft(ItemLink(7936)) }, "lo de antes sigue")
        -- (una profesión nueva, la primera vez con filtro: no cuenta como leída, basta el nivel)
        Professions(a, { [164] = 230, [197] = 150 })
        local other
        local tail = HU.CRAFT_ITEMS[197]
        for i = 1, #tail - 1, 2 do if not other and tail[i] ~= 7056 and tail[i + 1] <= 150 then other = tail[i] end end
        prof, list, out[9101], learned[9101] = { professionID = 197 }, { 9101 }, 7056, true
        Open()
        A.falsy(HU.cdb.tradeRecipes[197].full)
        A.same({ true }, { HU:CanCraft(ItemLink(7056)) })
        A.same({ true }, { HU:CanCraft(ItemLink(other)) }, "sin leerla entera, basta el nivel")
        st.makeable = nil
        Open()
        A.same({ false, "No tienes la receta" }, { HU:CanCraft(ItemLink(other)) }, "ya entera")
        -- (si el juego da todas las recetas, valen aunque haya un filtro)
        st.makeable, out[9102], learned[9102] = true, other, true
        T.GetAllRecipeIDs = function() return { 9101, 9102 } end
        Open()
        A.truthy(HU.cdb.tradeRecipes[197].full)
        A.same({ true }, { HU:CanCraft(ItemLink(other)) })
        T.GetAllRecipeIDs, st.makeable = nil, nil
        -- (Encantamiento: recetas sin objeto, por su hechizo)
        Professions(a, { [164] = 230, [333] = 100 })
        prof, list, learned[7418] = { professionID = 333 }, { 7418, 7420 }, true
        Open()
        A.same({ true }, { HU:CanCraft(SpellLink(7418)) })
        A.same({ false, "No tienes la receta" }, { HU:CanCraft(SpellLink(7420, "enchant")) })
        -- (sin profesión hija, la de base)
        Professions(a, { [186] = 160 })
        prof, list, out[9201], learned[9201] = { professionID = 0 }, { 9201 }, 3577, true
        T.GetBaseProfessionInfo = function() return { professionID = 186 } end
        Open()
        A.truthy(HU.cdb.tradeRecipes[186].items[3577])
        A.same({}, a:Errors())
    end)

    it("en el Tablón, «Aceptar» apagado si no puedo hacerla, con el porqué al pasar el ratón; en Mis encargos, el tic igual", function()
        local a = F.Community()
        Observe(a)
        Professions(a, { [129] = 200, [164] = 230 })
        local tr = OpenTrade(a)
        a.HU:TradeTest(true)
        local pocion, bolsa = Row(tr, "Poción"), Row(tr, "Bolsa")
        A.falsy(pocion.accept:IsEnabled())
        A.same({ "Te falta nivel (215)" }, Hover(a, pocion.accept))
        A.same({ "Te falta Peletería" }, Hover(a, bolsa.accept))
        Click(pocion.accept)
        A.equal("open", pocion.entry.state, "apagado no acepta")
        -- (con nivel: encendido, sin nada al pasar el ratón, y se acepta)
        Professions(a, { [129] = 220, [164] = 230 })
        Click(tr.viewBtns.pub)
        pocion = Row(tr, "Poción")
        A.truthy(pocion.accept:IsEnabled())
        A.is_nil(Hover(a, pocion.accept))
        Click(pocion.accept)
        A.equal("taken", Row(tr, "Poción").entry.state)
        -- (Mis encargos: la cofia de Lyra sí; el elixir de Bea, de Alquimia, no)
        Click(tr.viewBtns.priv)
        local cofia, elixir = Row(tr, "Cofia"), Row(tr, "Elixir")
        A.truthy(cofia.yes:IsEnabled())
        A.falsy(elixir.yes:IsEnabled())
        A.same({ "Te falta Alquimia" }, Hover(a, elixir.yes))
        Click(elixir.yes)
        A.equal("open", Row(tr, "Elixir").entry.state)
        Click(cofia.yes)
        A.equal("taken", Row(tr, "Cofia").entry.state)
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
-- «Solo lo que puedo hacer»
---------------------------------------------------------------------------
describe("Comercio (Trade.lua): «Solo lo que puedo hacer»", function()
    it("el Tablón (y lo publicado al buscar) solo enseña lo que se reconoce y puedo hacer; se guarda en el personaje", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        Professions(a, { [164] = 230, [165] = 160 })
        local tr = OpenTrade(a)
        HU:TradeTest(true)
        A.same({ "Capa de seda carmesí", "Cofia de mitril", "Bolsa de tejido de lana", "Poción de curación superior" }, Items(tr))
        A.truthy(tr.onlyCraft:IsShown())
        A.falsy(tr.onlyCraft:GetChecked())
        A.same({ "Solo lo que puedo hacer", "En el tablón, solo lo que puedes hacer con tus profesiones y tus recetas (lo que no se "
            .. "sabe qué es, tampoco). En Mis encargos, esconde los que harías tú y no puedes hacer; los que pides tú se ven siempre." },
            Hover(a, tr.onlyCraft))
        tr.onlyCraft:GetScript("OnLeave")(tr.onlyCraft)
        Click(tr.onlyCraft)
        A.equal(true, HU.cdb.tradeOnlyCraft, "en el personaje")
        A.is_nil(HU.adb.tradeOnlyCraft)
        A.truthy(tr.onlyCraft:GetChecked())
        A.same({ "Cofia de mitril", "Bolsa de tejido de lana" }, Items(tr))
        -- (una pedida a mano, que no se sabe qué es: fuera)
        tr.OpenNew(nil)
        local d = a.env.GuildUnionTradeNew
        d.item:SetText("Cosa rara")
        Click(Btn(a, d, "Publicar"))
        A.same({ "Cofia de mitril", "Bolsa de tejido de lana" }, Items(tr))
        -- (al buscar, también en lo publicado)
        Search(tr, "o")
        A.truthy(tr.onlyCraft:IsShown())
        A.same({ "Cofia de mitril", "Bolsa de tejido de lana" }, Items(tr))
        Search(tr, "")
        -- (en Mis encargos también se ve y vale: fuera el elixir que me pide Bea, de Alquimia; lo mío, siempre. Primero, los
        -- de chats con algo sin leer: Lyra y Pepe)
        Click(tr.viewBtns.priv)
        A.truthy(tr.onlyCraft:IsShown())
        A.same({ "Cofia de mitril", "Gran espada de mitril", "Poción de curación superior" }, Items(tr))
        -- (sin nada que pueda hacer, lo dice)
        Professions(a, {})
        Click(tr.viewBtns.pub)
        A.equal(0, #Rows(tr))
        A.equal("En el tablón no hay nada que puedas hacer.", tr.req.empty:GetText())
        -- (quitada: todo otra vez)
        Click(tr.onlyCraft)
        A.is_nil(HU.cdb.tradeOnlyCraft)
        A.equal(5, #Rows(tr))
        A.equal("No hay solicitudes.", tr.req.empty:GetText())
        A.same({}, a:Errors())
    end)

    it("se recuerda: el personaje que la dejó puesta la encuentra puesta", function()
        local key
        for k in pairs(F.Community().HU.adb.chars) do key = k end
        local a = F.Community({ db = { chars = { [key] = { tradeOnlyCraft = true } } } })
        Observe(a)
        Professions(a, { [164] = 230 })
        local tr = OpenTrade(a)
        a.HU:TradeTest(true)
        A.truthy(tr.onlyCraft:GetChecked())
        A.same({ "Cofia de mitril" }, Items(tr))
        A.same({}, a:Errors())
    end)

    it("en Mis encargos esconde los que haría yo y no puedo hacer (HU:CanCraft); los que pedí yo se ven siempre", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        -- (Herrería: la cofia que me pide Lyra, sí; el elixir que me pide Bea, de Alquimia, no)
        Professions(a, { [164] = 230 })
        local tr = OpenTrade(a)
        HU:TradeTest(true)
        Click(tr.viewBtns.priv)
        -- (primero los de chats con algo sin leer: Lyra, Pepe y Bea; luego la poción para Jandra)
        A.same({ "Cofia de mitril", "Gran espada de mitril", "Elixir de agilidad", "Poción de curación superior" }, Items(tr))
        Click(tr.onlyCraft)
        A.same({ "Cofia de mitril", "Gran espada de mitril", "Poción de curación superior" }, Items(tr),
            "fuera el elixir; la poción y la espada son mías")
        -- (sin profesiones, solo lo mío, aunque yo no sepa hacerlo: la espada la hace Pepe)
        Professions(a, {})
        Click(tr.viewBtns.priv)
        A.same({ "Gran espada de mitril", "Poción de curación superior" }, Items(tr))
        A.equal("No hay solicitudes.", tr.req.empty:GetText())
        -- (quitada, todo otra vez)
        Click(tr.onlyCraft)
        A.equal(4, #Rows(tr))
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
-- Aspecto
---------------------------------------------------------------------------
describe("Comercio (Trade.lua): aspecto", function()
    it("las pestañas de arriba (DJ.Switch, DJStyle.lua): dos botones rojos del juego, juntos; el elegido, gris", function()
        local a = F.Community()
        Observe(a)
        local DJ = a.HU.DJ
        local sw = DJ.Switch(a.env.UIParent, { { "a", "Uno" }, { "b", "Dos" } })
        A.same({ 306, 28 }, { sw._w, sw._h }, "dos botones de 150 x 28, con 6 entre ellos")
        local x, y = sw.btns.a, sw.btns.b
        A.same({ sw, "TOPLEFT", 0, 0 }, x._pts.TOPLEFT)
        A.same({ sw, "TOPLEFT", 156, 0 }, y._pts.TOPLEFT)
        A.same({ 150, 28 }, { x._w, x._h })
        A.truthy(x.Left and x.Middle and x.Right, "el botón rojo del juego (UIPanelButtonTemplate)")
        A.same({ "Uno", "Dos" }, { x:GetText(), y:GetText() })
        A.falsy(x.picked or y.picked)
        x:Pick(true); y:SetSelected(false)
        A.truthy(x.picked, "el elegido, gris (DJ.PickRed)")
        A.falsy(y.picked)
        y:Label("Otra")
        A.equal("Otra", y:GetText())
        A.same({}, a:Errors())
    end)

    it("lo elegido, gris como la pestaña elegida del Dungeon Journal (antes, negro): el juego le pone el rojo al pulsar, soltar, enseñarse o encenderse y vuelve el gris; sin elegir, rojo; la letra, la de siempre", function()
        local a = F.Community()
        Observe(a)
        local DJ = a.HU.DJ
        local GREY, DOWN, RED = "Interface\\Buttons\\UI-Panel-Button-Disabled", "Interface\\Buttons\\UI-Panel-Button-Disabled-Down",
            "Interface\\Buttons\\UI-Panel-Button-Up"
        local b = DJ.Button(a.env.UIParent, "Uno", 100)
        local function Skin() return { b.Left._tex, b.Middle._tex, b.Right._tex } end
        local function Game(file) for _, k in ipairs({ "Left", "Middle", "Right" }) do b[k]:SetTexture(file) end end
        b:Pick(true)
        A.same({ GREY, GREY, GREY }, Skin(), "elegido: las tres piezas, grises")
        A.is_nil(b._font, "la letra no cambia: dorada, como en el Dungeon Journal")
        -- (lo que hace el juego al pulsarlo (UIPanelButton_OnMouseDown / OnMouseUp, SecureUIPanelTemplates.lua), y detrás lo nuestro)
        Game("Interface\\Buttons\\UI-Panel-Button-Down"); b:GetScript("OnMouseDown")(b)
        A.same({ DOWN, DOWN, DOWN }, Skin(), "pulsándolo, gris hundido")
        Game(RED); b:GetScript("OnMouseUp")(b)
        A.same({ GREY, GREY, GREY }, Skin(), "al soltarlo, gris otra vez")
        for _, what in ipairs({ "OnShow", "OnEnable" }) do
            Game(RED); b:GetScript(what)(b)
            A.same({ GREY, GREY, GREY }, Skin(), what)
        end
        b:Pick(false)
        A.same({ RED, RED, RED }, Skin(), "sin elegir, rojo")
        Game("Interface\\Buttons\\UI-Panel-Button-Down"); b:GetScript("OnMouseUp")(b)
        A.same({ "Interface\\Buttons\\UI-Panel-Button-Down", "Interface\\Buttons\\UI-Panel-Button-Down",
            "Interface\\Buttons\\UI-Panel-Button-Down" }, Skin(), "sin elegir, lo del juego no se toca")
        -- (apagado, el juego pone su gris de apagado: elegirlo no lo toca; al encenderse, el gris de elegido)
        b:SetEnabled(false); Game(GREY)
        b:Pick(true)
        A.same({ GREY, GREY, GREY }, Skin())
        b:SetEnabled(true); Game(RED); b:GetScript("OnEnable")(b)
        A.same({ GREY, GREY, GREY }, Skin())
        A.same({}, a:Errors())
    end)

    it("arriba, los botones Tablón · Mis encargos · Buscar en el centro, igual que los de Eventos; debajo, el buscador a la izquierda y «Solo lo que puedo hacer» a la derecha, sin pisarse (también en inglés)", function()
        for _, locale in ipairs({ "esES", "enUS" }) do
            local a = F.Community({ locale = locale })
            Observe(a)
            local L = a.HU.L
            local tr = OpenTrade(a)
            local cal = a.env.GuildUnionUnionRoster.calendar
            local sw, search, only = tr.switch, tr.search, tr.onlyCraft
            -- (fila 1: los botones, en el centro y enteros dentro de la sección; son las vistas de siempre, y Buscar al lado
            -- de Mis encargos)
            A.same({ tr, "TOP", 0, -4 }, sw._pts.TOP)
            A.equal(sw.btns.pub, tr.viewBtns.pub)
            A.equal(sw.btns.priv, tr.viewBtns.priv)
            A.equal(sw.btns.find, tr.viewBtns.find)
            A.same({ sw, "TOPLEFT", 2 * (150 + 6), 0 }, tr.viewBtns.find._pts.TOPLEFT, "Buscar, a la derecha de Mis encargos")
            local l, r = Span(tr, sw)
            A.truthy(l >= 2 and r <= SECTION_W - 2, locale .. ": los botones caben: de " .. l .. " a " .. r)
            A.same({ cal, "TOP", 0, -4 }, cal.switch._pts.TOP, "los de Eventos, en el mismo sitio")
            for _, b in pairs(sw.btns) do
                A.same({ b._w, b._h }, { cal.switch.btns.list._w, cal.switch.btns.list._h }, "y del mismo tamaño y estilo")
                A.truthy(b.Left and b.Pick, "el botón rojo del juego (DJ.Button)")
            end
            -- (los textos caben, también con dos cifras de sin leer)
            for _, t in ipairs({ { tr.viewBtns.pub, L("Tablón") }, { tr.viewBtns.priv, string.format(L("Mis encargos (%d)"), 99) },
                { tr.viewBtns.find, L("Buscar") } }) do
                A.truthy(TextWidth(t[2], 12) + 16 <= t[1]._w, locale .. ": «" .. t[2] .. "» cabe en su botón")
            end
            -- (fila 2, debajo: el buscador del juego, como antes, 200 x 22, centrado en la fila, con su marco de borde dorado)
            A.same({ tr, "TOPLEFT", 23, -39 }, search._pts.TOPLEFT)
            A.same({ 200, 22 }, { search._w, search._h })
            A.truthy(-4 - sw._h > -39 + 3, "debajo de los botones, sin pisarlos")
            A.same({ 1, 0.82, 0, 0.55 }, tr.searchBox._edge, "el marco, con borde dorado")
            -- (y la casilla del juego a la derecha, centrada en la fila, con su texto detrás que acaba en el borde: el WoW de
            -- mentira no mide textos y se usa el ancho de reserva, 130)
            A.same({ tr, "TOPRIGHT", -(14 + 22 + 2 + 130), -36 - 28 / 2 }, only._pts.LEFT)
            A.equal("GameFontHighlightSmall", only.Text._fontObj)
            local cl = Span(tr, only)
            local _, sr = Span(tr, search)
            A.truthy(cl >= sr + 3 + 8, locale .. ": la casilla no pisa el buscador: empieza en " .. cl)
            A.truthy(cl + 22 + 2 + TextWidth(only.Text:GetText(), 10) <= SECTION_W, locale .. ": su texto cabe")
            -- (las dos filas, encima del panel de la sección, donde empiezan las listas)
            A.truthy(-39 - search._h - 3 > tr.new:GetParent()._pts.TOPLEFT[4], "las filas no pisan el panel")
            A.same({}, a:Errors())
        end
    end)

    it("«+ Nuevo anuncio» (antes «+ Nueva solicitud»), como hasta la copia 304, abajo: en el Tablón, en el centro; en Mis encargos, centrado debajo de la lista, y el chat de arriba abajo a la derecha, sin chocar", function()
        local a = F.Community()
        Observe(a)
        local L = a.HU.L
        local tr = OpenTrade(a)
        local new, del, chat = tr.new, tr.delBtn, tr.chat
        A.equal("+ Nuevo encargo", new:GetText(), "Jorge, 25/11: «new order»")
        A.same({ 200, 24 }, { new._w, new._h })
        for _, k in ipairs({ "Left", "Middle", "Right" }) do A.same({ 0.45, 1, 0.45 }, new[k]._color, "teñido de verde: " .. k) end
        A.equal("GameFontHighlight", new._font, "letra blanca")
        A.is_nil(new:GetScript("OnEnter"), "al pasar el ratón, nada: ya se lee")
        A.same({ tr, "BOTTOM", 0, 8 }, new._pts.BOTTOM, "Tablón: abajo, en el centro de la sección")
        -- (va en el panel de la sección, que llega hasta abajo, para quedar encima de él; el cuerpo de las listas acaba 4
        -- por encima)
        A.same({ tr, "BOTTOMRIGHT", -2, 2 }, new:GetParent()._pts.BOTTOMRIGHT)
        A.same({ tr, "BOTTOMRIGHT", 0, 8 + new._h + 4 }, tr.body._pts.BOTTOMRIGHT)
        -- (Mis encargos: el chat, a la derecha, desde arriba del cuerpo (debajo del buscador) hasta abajo de la sección, a
        -- 10 del borde; la lista, a su izquierda, con el sitio de su barra de bajar entre los dos (6 + 24), y el botón,
        -- centrado debajo de ella)
        Click(tr.viewBtns.priv)
        A.same({ tr.body, "TOPRIGHT", -10, 0 }, chat._pts.TOPRIGHT)
        A.same({ tr, "BOTTOMRIGHT", -10, 8 }, chat._pts.BOTTOMRIGHT)
        A.same({ chat, "LEFT", -(6 + 24), 0 }, tr.req.list._pts.RIGHT)
        local chatL = SECTION_W - 10 - chat._w
        local listMid = (6 + chatL - 6 - 24) / 2
        A.same({ tr, "BOTTOM", listMid - SECTION_W / 2, 8 }, new._pts.BOTTOM, "centrado debajo de la lista")
        -- («Eliminar (N)», a su derecha, cabe antes del chat, también en inglés)
        A.same({ new, "RIGHT", 6, 0 }, del._pts.LEFT)
        local _, delR = Span(tr, del)
        A.truthy(delR + 4 <= chatL, "«Eliminar (N)» no choca con el chat: acaba en " .. delR .. "; el chat empieza en " .. chatL)
        for _, text in ipairs({ string.format(L("Eliminar (%d)"), 9), "Delete (9)" }) do
            A.truthy(TextWidth(text, 12) + 6 <= del._w, "«" .. text .. "» cabe en su botón")
        end
        -- (de vuelta al Tablón, en el centro otra vez; buscando no sale, como antes; clic: la ventana de pedir)
        Click(tr.viewBtns.pub)
        A.same({ tr, "BOTTOM", 0, 8 }, new._pts.BOTTOM)
        Search(tr, "mitril")
        A.falsy(new:IsShown())
        Search(tr, "")
        A.truthy(new:IsShown())
        Click(new)
        A.truthy(a.env.GuildUnionTradeNew:IsShown())
        A.equal("Nuevo encargo", a.env.GuildUnionTradeNew.title:GetText(), "y su ventana, con el mismo nombre")
        A.truthy(Btn(a, a.env.GuildUnionTradeNew, "Publicar"), "que se publica con «Publicar»")
        local en = F.Community({ locale = "enUS" })
        local tr2 = OpenTrade(en)
        A.equal("+ New order", tr2.new:GetText())
        Click(tr2.new)
        A.equal("New order", en.env.GuildUnionTradeNew.title:GetText())
        A.truthy(Btn(en, en.env.GuildUnionTradeNew, "Post"))
        A.same({}, a:Errors())
        A.same({}, en:Errors())
    end)

    it("sin botón de modo prueba (Jorge, 24/11): lo de prueba se pone y se quita solo por código, con HU:TradeTest", function()
        local a = F.Community()
        local tr = OpenTrade(a)
        A.is_nil(tr.testBtn)
        -- (ningún botón de la sección dice «Modo prueba»)
        local function Inside(f)
            while f do if f == tr then return true end f = f._parent end
            return false
        end
        for _, fr in ipairs(a.w.frames) do
            A.falsy(Inside(fr) and fr:GetText() == "Modo prueba", "un botón «Modo prueba» en Comercio")
        end
        a.HU:TradeTest(true)
        A.equal(4, #Rows(tr), "el Tablón de prueba")
        a.HU:TradeTest(false)
        A.equal(0, #Rows(tr))
        A.same({}, a:Errors())
    end)

    it("nombres: Tablón · Mis encargos y «Buscar receta», también en inglés (Board · My Orders, Search recipe)", function()
        local a = F.Community()
        Observe(a)
        local tr = OpenTrade(a)
        A.same({ "Tablón", "Mis encargos" }, { tr.viewBtns.pub:GetText(), tr.viewBtns.priv:GetText() })
        -- (la ayuda del buscador, según la vista: Jorge, 25/11, «search on board» y «search order»)
        A.equal("Buscar en el tablón", tr.search.Instructions:GetText())
        Click(tr.viewBtns.priv)
        A.equal("Buscar encargo", tr.search.Instructions:GetText())
        Click(tr.viewBtns.pub)
        A.same({ 200, 22 }, { tr.search._w, tr.search._h }, "el del juego, como antes")
        A.equal("Solo lo que puedo hacer", tr.onlyCraft.Text:GetText())
        -- (al pedir: la casilla «Encargo personal»; con ella, a quién, con autorrelleno; sin nadie, no se puede)
        tr.OpenNew(nil)
        local d = a.env.GuildUnionTradeNew
        A.same({ "Encargo personal", false, false }, { d.personal.Text:GetText(), d.personal:GetChecked(), d.to:IsShown() })
        Toggle(d.personal)
        A.truthy(d.to:IsShown())
        d.item:SetText("Algo")
        local n0 = #a.w.chat
        Click(Btn(a, d, "Publicar"))
        A.matches("Para un encargo personal, pon para quién es.", tostring(a.w.chat[n0 + 1] and a.w.chat[n0 + 1].msg))
        local en = F.Community({ locale = "enUS" })
        local tr2 = OpenTrade(en)
        A.same({ "Board", "My Orders" }, { tr2.viewBtns.pub:GetText(), tr2.viewBtns.priv:GetText() })
        A.equal("Search on board", tr2.search.Instructions:GetText())
        Click(tr2.viewBtns.priv)
        A.equal("Search order", tr2.search.Instructions:GetText())
        A.equal("Only what I can craft", tr2.onlyCraft.Text:GetText())
        A.same({}, a:Errors())
        A.same({}, en:Errors())
    end)

    it("filas y títulos con aire, y caben en la sección con la ventana del juego a su alto de siempre", function()
        local a = F.Community()
        Observe(a)
        local tr = OpenTrade(a)
        -- (el cuerpo de las listas: de debajo de las dos filas de arriba a encima de «+ Nueva solicitud»)
        local BODY = SECTION_H + tr.body._pts.TOPLEFT[4] - tr.body._pts.BOTTOMRIGHT[4]
        A.truthy(tr.req.rows[1]._h >= 22, "filas más altas que las de 18: " .. tostring(tr.req.rows[1]._h))
        A.truthy(tr.req.hdr._h >= 24, "títulos")
        A.truthy(tr.req.list._h <= BODY, "el Tablón cabe: " .. tostring(tr.req.list._h) .. " de " .. BODY)
        A.equal(9, tr.req.n, "9 filas")
        -- (al buscar: lo publicado encima, quién lo hace debajo, con 6 entre medias)
        a.HU:TradeTest(true)
        Search(tr, "Poción")
        A.equal(1, #Rows(tr))
        local both = tr.req.list._h + 6 + tr.found.list._h
        A.truthy(both <= BODY, "las dos caben: " .. both .. " de " .. BODY)
        -- (sin nada publicado que encaje, quién lo hace ocupa todo)
        Search(tr, "nada de nada")
        A.truthy(tr.found.list._h <= BODY, "quién lo hace, sola: " .. tostring(tr.found.list._h))
        -- (en Buscar, los objetos solos, sin título: 9 filas, como el Tablón)
        Search(tr, "")
        Click(tr.viewBtns.find)
        A.equal(9, tr.items.n)
        A.truthy(tr.items.list._h <= BODY, "los objetos caben: " .. tostring(tr.items.list._h))
        A.same({}, a:Errors())
    end)

    it("las barras de bajar no se salen (Jorge, 25/11): cada lista les deja su sitio a su derecha, dentro del panel; con el chat, entre la lista y el chat; también en la ventana de quién lo hace", function()
        local a = F.Community()
        Observe(a)
        local tr = OpenTrade(a)
        -- (la barra del juego (FauxScrollFrameTemplate) va por fuera de su lista: de 5 a 23 a su derecha (6 de hueco, 16
        -- de barra y las flechas, de 18). El panel acaba a 2 del borde y su marco ocupa 4 más)
        local BAR = 23
        local function BarRight(lst)
            local p = lst.list._pts.RIGHT
            if p[1] == tr.body then return SECTION_W + p[3] + BAR end
            A.equal(tr.chat, p[1], "o el cuerpo o el chat")
            return (SECTION_W - 10 - tr.chat._w) + p[3] + BAR
        end
        a.HU:TradeTest(true)
        A.truthy(BarRight(tr.req) <= SECTION_W - 2 - 4 - 4, "Tablón: acaba en " .. BarRight(tr.req))
        Search(tr, "Poción")
        A.truthy(BarRight(tr.found) <= SECTION_W - 2 - 4 - 4, "quién lo hace: acaba en " .. BarRight(tr.found))
        Search(tr, "")
        Click(tr.viewBtns.priv)
        local chatL = SECTION_W - 10 - tr.chat._w
        A.truthy(BarRight(tr.req) <= chatL - 4, "Mis encargos: acaba en " .. BarRight(tr.req) .. "; el chat empieza en " .. chatL)
        Click(tr.viewBtns.find)
        A.truthy(BarRight(tr.items) <= SECTION_W - 2 - 4 - 4, "Buscar: acaba en " .. BarRight(tr.items))
        -- (en la ventana: su lista, a 6 del borde de su panel (ancho de la ventana menos 2 × 18), y su barra dentro)
        local who = a.env.GuildUnionTradeWho
        local inner = 460 - 2 * 18 - 4
        A.truthy(6 + who.lst.list._w + BAR <= inner - 2, "la ventana: acaba en " .. (6 + who.lst.list._w + BAR) .. " de " .. inner)
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
-- Quién lo hace, con la comunidad de Forever
---------------------------------------------------------------------------
describe("Comercio (Trade.lua): quién lo hace, con la comunidad de Forever", function()
    it("la comunidad da nivel 1: el mío sale de mi personaje; el de los demás no se sabe («—», detrás)", function()
        local a = F.Community()
        a.env.C_Club = {
            GetGuildClubId = function() return 9 end,
            GetClubMembers = function() return { 1, 2, 3 } end,
            GetMemberInfo = function(_, id)
                if id == 1 then return { name = "Tester", isSelf = true, profession1ID = 186, profession1Name = "Mining", profession1Rank = 1 } end
                if id == 2 then return { name = "Compi", profession1ID = 186, profession1Name = "Mining", profession1Rank = 1 } end
                return { name = "Bea", profession1ID = 186, profession1Name = "Mining", profession1Rank = 250 }
            end,
        }
        Professions(a, { [186] = 111 })
        local tr = OpenTrade(a)
        Search(tr, "mining")
        local got = {}
        for _, r in ipairs(tr.found.rows) do
            if r:IsShown() and r.entry then got[#got + 1] = r.entry.name:match("^([^-]+)") .. " " .. r.cells[4]:GetText() end
        end
        A.same({ "Bea 250", "Tester 111", "Compi —" }, got)
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
-- La ficha al pasar el ratón
---------------------------------------------------------------------------
describe("Comercio (Trade.lua): qué es un objeto, al pasar el ratón", function()
    it("en el buscador y en sus sugerencias, la ficha del juego del enlace, al lado sin taparlo; sin enlace, nada", function()
        local a = F.Community()
        Observe(a)
        local tr = OpenTrade(a)
        local tip = a.env.GameTooltip
        local shown
        tip.SetHyperlink = function(_, link) shown = link end
        local link = ItemLink(2589, "Paño de lino")
        tr.search:SetText(link)
        tr.search:GetScript("OnEnter")(tr.search)
        A.equal("item:2589::::::::60:::::::", shown, "la ficha del objeto escrito")
        local pt = tip._pts.TOPLEFT
        A.truthy(pt[1] == tr.search and pt[2] == "TOPRIGHT" and pt[3] == 4, "a la derecha del buscador")
        shown = nil
        tr.search:SetText("lino")
        tr.search:GetScript("OnEnter")(tr.search)
        A.is_nil(shown, "sin enlace, nada")
        A.same({}, a:Errors())
    end)

    it("al buscar, lo exacto primero: «bolsa» saca antes «Bolsa de…» (la más corta primero) que «Gran bolsa», «Bolsas» o «Embolsar»; sin acentos (Jorge, 24/11)", function()
        local a = F.Community()
        local HU = a.HU
        local R = HU.TextRank
        -- (cómo encaja, de mejor a peor: el nombre entero, empieza con la palabra entera, la lleva entera, empieza a
        -- medias, una palabra empieza así, dentro de una palabra, y varias palabras sueltas)
        A.same({ 0, 1, 2, 3, 4, 5, 6 }, {
            R("Poción de maná", "pocion de MANA"), R("Bolsa de lino", "bolsa"), R("Gran bolsa de cuero", "Bolsa"),
            R("Bolsas de pólvora", "bolsa"), R("Gran bolsaza", "bolsa"), R("Embolsar", "bolsa"),
            R("Bolsa de seda verde", "seda  bolsa") })
        A.is_nil(R("Bolsa de seda verde", "seda roja"))
        A.is_nil(R("Bolsa", "  "))
        -- (en las sugerencias del buscador, en ese orden; con la palabra entera, la más corta primero)
        local list = HU.CRAFT_ITEMS[197]
        local names = { [list[1]] = "Embolsar", [list[3]] = "Bolsas de pólvora", [list[5]] = "Gran bolsa de cuero",
            [list[7]] = "Bolsa de bombas de cobre", [list[9]] = "Bolsa de lino" }
        a.env.C_Item.GetItemInfo = function(id)
            if type(id) ~= "number" then return nil end
            local name = names[id] or ("Objeto " .. id)
            return name, ItemLink(id, name)
        end
        local tr = OpenTrade(a)
        a.w:Advance(40) -- (los nombres se piden poco a poco: 30 cada medio segundo)
        tr.search:SetText("bolsa")
        tr.search:GetScript("OnTextChanged")(tr.search, true)
        local shown = {}
        for _, fr in ipairs(a.w.frames) do
            local box = fr._parent and fr._parent._parent
            if box == tr.search and fr.text and fr.value and fr:IsShown() then shown[#shown + 1] = fr.text:GetText():match("%[(.-)%]") end
        end
        A.same({ "Bolsa de lino", "Bolsa de bombas de cobre", "Gran bolsa de cuero", "Bolsas de pólvora", "Embolsar" }, shown)
        -- (lo escrito a mano se reconoce también sin acentos ni mayúsculas)
        Professions(a, {})
        A.falsy((HU:CanCraft("bolsa DE lino")), "reconocida: me falta la profesión")
        A.truthy((HU:CanCraft("Bolsa de linos")), "otro nombre: no se reconoce")
        A.same({}, a:Errors())
    end)

    it("se guarda en el personaje: tras /reload siguen mis solicitudes, los chats y lo sin leer; lo de prueba no; al mes, se quita (Jorge, 24/11)", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        local tr = OpenTrade(a)
        HU:TradeTest(true)
        tr.OpenNew(nil)
        local d = a.env.GuildUnionTradeNew
        d.item:SetText("Cosa rara")
        Click(Btn(a, d, "Publicar"))
        HU:TradeChatLine("Ana-Reino", "Ana-Reino", "hola")
        A.truthy(HU.cdb.tradeReqs and HU.cdb.tradeChats["Ana-Reino"], "en el personaje")
        a.w:Fire("PLAYER_LOGOUT")
        local b = F.Community({ db = a.env.GuildUnionDB, charDb = a.env.GuildUnionCharDB })
        Observe(b)
        local tr2 = OpenTrade(b)
        A.same({ "Cosa rara" }, Items(tr2), "la mía sigue; las de prueba, no")
        A.equal(1, #b.HU.db.tradeChats["Ana-Reino"], "su chat")
        A.equal(1, b.HU:TradeUnread(), "y su línea, sin leer")
        A.is_nil(b.HU.db.tradeChats["Lyra-Prueba"])
        -- (a los 30 días de pedirla, se quita: la propuesta caduca y al volver a abrir ya no está. tradeReqs ya no se usa)
        b.w.epoch = b.w.epoch + 31 * 86400
        tr2:Hide(); tr2:Show()
        A.same({}, Items(tr2))
        b.w:Fire("PLAYER_LOGOUT")
        A.equal(0, #b.HU.db.tradeReqs)
        A.same({}, a:Errors())
        A.same({}, b:Errors())
    end)
end)

---------------------------------------------------------------------------
-- Anuncios (25/11): cuánto duran en el tablón, vender BOE y la pestaña Buscar
---------------------------------------------------------------------------
-- (los objetos que conoce el juego: [número] = { nombre, calidad, nivel, clase, ligado, nivel requerido (si no, 1) },
-- como los da C_Item.GetItemInfo: nombre, enlace, calidad, nivel, nivel mínimo, tipo, subtipo, pila, hueco, icono,
-- precio, clase, subclase y ligado (2: al equipar). En Forever no hay GetItemInfo suelto)
local QCOLOR = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }
local function Known(a, items)
    a.env.C_Item.GetItemInfo = function(id)
        local it = items[id]
        if not it then return nil end
        local link = "|cff" .. QCOLOR[it[2]] .. "|Hitem:" .. id .. "::::::::60:::::::|h[" .. it[1] .. "]|h|r"
        return it[1], link, it[2], it[3], it[6] or 1, "", "", 1, "", 0, 0, it[4], 0, it[5]
    end
end
-- (una línea de TR u OF de alguien de mi hermandad, como llega por GUILD)
local function WU(a, from, set, key, data, t)
    a.w:Receive("HU20B", "WU~UNO~" .. set .. "~" .. key .. "~" .. (t or a.HU.StampNow()) .. "~" .. data, "GUILD", from)
end
local function Id(HU, who, n) return HU.Hash(who):sub(1, 4) .. string.format("%012d", n) end
-- (¿lo último que ha dicho el addon en el chat lleva ese texto?)
local function Said(a, text)
    local m = a.w.chat[#a.w.chat]
    return m ~= nil and tostring(m.msg):find(text, 1, true) ~= nil
end
-- (mi línea de TR en el almacén que lleva ese texto, y su número)
local function Mine(HU, text)
    local st = HU.db.wuStore.UNO and HU.db.wuStore.UNO.TR or {}
    for k, e in pairs(st) do
        if k:find("^tester%-reino,o") and e.d:find(text, 1, true) then return e, k:match(",o(%w+)$") end
    end
end
-- (la caducidad de unos datos de TR)
local function Expiry(d) return d:match("^[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,([^,]*),") end
-- (un menú de mentira, el de clic derecho o el de un filtro: título, botones y casillas)
local function FakeMenu(a)
    local m = { buttons = {}, checks = {} }
    local root = {
        CreateTitle = function(_, t) m.title = t end,
        CreateButton = function(_, t, fn) m.buttons[t] = fn end,
        CreateCheckbox = function(_, t, is, set) m.checks[#m.checks + 1] = { text = t, is = is, set = set } end,
    }
    a.env.MenuUtil = { CreateContextMenu = function(owner, gen) m.atCursor = owner; gen(owner, root) end }
    m.root = root
    return m
end
-- (y el sistema de menús entero, como en Forever (Blizzard_Menu): un menú que se abre atado a un punto (CreateAnchor y
-- OpenMenu, como los desplegables del juego) apunta dónde, en `anchor`, y con qué estilo)
local function FakeDrop(a)
    local m = FakeMenu(a)
    a.env.MenuVariants = { GetDefaultContextMenuMixin = function() return "contexto" end }
    a.env.MenuUtil.CreateRootMenuDescription = function(mixin) m.mixin = mixin; return m.root end
    a.env.CreateAnchor = function(...) return { ... } end
    a.env.Menu = {
        PopulateDescription = function(gen, owner, desc) gen(owner, desc) end,
        GetManager = function() return { OpenMenu = function(_, owner, _, anchor) m.owner, m.anchor = owner, anchor end } end,
    }
    return m
end
-- (poner un anuncio con su ventana: opts = { item, sell, to, hours, gold })
local function Post(a, tr, opts)
    tr.OpenNew(opts.to)
    local d = a.env.GuildUnionTradeNew
    if opts.sell then Click(d.kindSell) end
    d.item:SetText(opts.item)
    for _, c in ipairs(d.expChecks) do if c.hours == opts.hours then Click(c) end end
    if opts.gold then d.coins[1]:SetText(tostring(opts.gold)) end
    Click(Btn(a, d, a.HU.L("Publicar")))
    return d
end
local function Req(HU, text)
    for _, r in ipairs(HU:TradeRequests()) do if r.item:find(text, 1, true) then return r end end
end
local ACT_W = 84 -- (la última columna del Tablón, Trade.lua)

describe("Comercio (Trade.lua): anuncios que caducan", function()
    it("en el tablón se elige cuánto dura (5, 12, 24 de entrada o 48 h): viaja su hora, se ve lo que le queda y, al caducar, no se ve en ninguna parte ni se publica; las privadas no caducan", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        local tr = OpenTrade(a)
        tr.OpenNew(nil)
        local d = a.env.GuildUnionTradeNew
        local hours = {}
        for _, c in ipairs(d.expChecks) do hours[#hours + 1] = c.Text:GetText() .. (c:GetChecked() and " *" or "") end
        A.same({ "5 h", "12 h", "24 h *", "48 h" }, hours, "24 h de entrada")
        A.equal("Duración:", d.expLabel:GetText())
        A.same({ true, true, false }, { d.expLabel:IsShown(), d.expChecks[1]:IsShown(), d.to:IsShown() }, "en el tablón: cuánto dura")
        Toggle(d.personal)
        A.same({ false, false, true }, { d.expLabel:IsShown(), d.expChecks[1]:IsShown(), d.to:IsShown() }, "personal: a quién")
        Click(d.expChecks[4])
        A.same({ false, false, false, true }, { d.expChecks[1]:GetChecked(), d.expChecks[2]:GetChecked(),
            d.expChecks[3]:GetChecked(), d.expChecks[4]:GetChecked() }, "se elige una")
        d:Hide()
        -- (5 h: la hora en que caduca, en base 36, en sus datos; en el tablón, lo que le queda)
        local t0 = HU.StampNow()
        Post(a, tr, { item = "Cosa rara", hours = 5 })
        A.equal("o,p,1,1,-,1,-," .. HU.B36(t0 + 5 * 3600) .. ",t:Cosa rara", Mine(HU, "Cosa rara").d)
        A.same({ "Cosa rara" }, Items(tr))
        A.matches("Abierta.*5h", Row(tr, "Cosa rara").cells[6]:GetText())
        -- (otra de 48 h, y una privada, que no caduca)
        Post(a, tr, { item = "Otra cosa", hours = 48 })
        A.equal(HU.B36(t0 + 48 * 3600), Expiry(Mine(HU, "Otra cosa").d))
        Post(a, tr, { item = "Para Compi", to = "Compi-Reino" })
        A.equal("o,p,1,1,-,0,Compi-Reino,-,t:Para Compi", Mine(HU, "Para Compi").d)
        -- (la última hora, «<1h»; cada minuto se repinta solo. Lo más largo cabe en su casilla del Estado, sin apretar:
        -- la lista mide lo que la sección menos 6 y 24, y el Estado es lo que dejan las otras columnas, menos sus márgenes)
        Click(tr.viewBtns.pub)
        a.w.epoch = a.w.epoch + 5 * 3600 - 40 * 60
        a.w:Advance(60)
        A.truthy(Row(tr, "Cosa rara").cells[6]:GetText():find("Abierta |cff9a8f78<1h|r", 1, true))
        local cell = (SECTION_W - 6 - 24) - (100 + 170 + 40 + 44 + 66 + ACT_W + 6) - 8 - 2 * 4
        for _, t in ipairs({ "Abierta 48h", "Abierta <1h", "Venta 48h", "Open 48h", "Sale <1h" }) do
            A.truthy(TextWidth(t, 10) <= cell, "«" .. t .. "» cabe en " .. cell)
        end
        -- (caducada: fuera del tablón sin tocar nada, de lo que publica mi hermandad y, al limpiar, del almacén; ya no cuenta
        -- para el tope)
        a.w.epoch = a.w.epoch + 40 * 60
        a.w:Advance(60)
        A.same({ "Otra cosa" }, Items(tr))
        A.is_nil(Req(HU, "Cosa rara"))
        for _, l in ipairs((HU:PackLines("UNO", "TR"))) do A.falsy(l:find("Cosa rara", 1, true), l) end
        for _, l in pairs(HU.PackRefresh("TR").lineOf) do A.falsy(l:find("Cosa rara", 1, true), l) end
        HU.PackCleanStores()
        A.is_nil(Mine(HU, "Cosa rara"), "fuera del almacén")
        for i = 1, 3 do Post(a, tr, { item = "Más " .. i }) end
        A.truthy(Mine(HU, "Más 3"), "caben otras 3 (con la de 48 h y la privada, 5)")
        -- (a los 3 días: la de 48 h, fuera; la privada sigue)
        a.w.epoch = a.w.epoch + 3 * 86400
        a.w:Advance(60)
        Click(tr.viewBtns.pub)
        A.same({}, Items(tr))
        Click(tr.viewBtns.priv)
        A.same({ "Para Compi" }, Items(tr))
        A.same({}, a:Errors())
    end)

    it("una mía del tablón que alguien acepta deja de caducar (se vuelve a mandar sin la hora): el encargo no se borra a medias", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        local tr = OpenTrade(a)
        Post(a, tr, { item = "Yelmo", hours = 5 })
        local e, id = Mine(HU, "Yelmo")
        A.truthy(Expiry(e.d) ~= "-")
        WU(a, "Compi-Reino", "TR", "a" .. id, "t")
        a.w:Advance(2)
        A.equal("o,p,1,1,-,1,-,-,t:Yelmo", Mine(HU, "Yelmo").d, "sin caducidad")
        a.w.epoch = a.w.epoch + 6 * 3600
        a.w:Advance(60)
        Click(tr.viewBtns.priv)
        A.same({ "Yelmo" }, Items(tr))
        A.same({ "taken", "Compi-Reino" }, { Row(tr, "Yelmo").entry.state, Row(tr, "Yelmo").entry.taker })
        A.same({}, a:Errors())
    end)
end)

describe("Comercio (Trade.lua): vender BOE", function()
    -- (verde y se liga al equipar: BOE; blanco y sin ligar; azul que se liga al recogerlo; gris al equipar; legendaria)
    local GOODS = {
        [7931] = { "Cofia de mitril", 2, 40, 4, 2 }, [2589] = { "Paño de lino", 1, 5, 7, 0 },
        [7954] = { "Gran espada de mitril", 3, 47, 2, 1 }, [6948] = { "Gris al equipar", 0, 10, 4, 2 },
        [12345] = { "Legendaria", 5, 70, 2, 2 },
    }

    it("un BOE que se fabrica sí se pide: es encargarlo a quien sabe hacerlo, no comprarlo (Jorge, 25/11)", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        Known(a, GOODS)
        local tr = OpenTrade(a)
        Post(a, tr, { item = ItemLink(7931, "Cofia de mitril") })
        local e = Mine(HU, "Cofia de mitril")
        A.truthy(e, "propuesta")
        A.truthy(e.d:match("^o,p,"), "un encargo (pedir), no una venta: " .. tostring(e and e.d))
        A.same({}, a:Errors())
    end)

    it("un BOE de botín no se puede pedir y lo que no es BOE no se vende (se dice por qué); la venta va al tablón, sin materiales, con precio y de otro color, con «Venta»", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        Known(a, GOODS)
        local tr = OpenTrade(a)
        local d = a.env.GuildUnionTradeNew
        -- (vender lo que no es BOE: blanco, que se liga al recogerlo, gris, escrito a mano o un encantamiento)
        for _, item in ipairs({ ItemLink(2589, "Paño de lino"), ItemLink(7954, "Gran espada de mitril"), ItemLink(6948, "Gris"),
            "Cosa rara", SpellLink(7418) }) do
            Post(a, tr, { item = item, sell = true })
            A.truthy(Said(a, "Solo se venden objetos BOE: los que se ligan al equipar, de verde a legendario."), item)
        end
        A.is_nil(Mine(HU, ""), "nada propuesto")
        A.same({}, Items(tr))
        -- (al vender, ni materiales ni «En el tablón» (va siempre) y la propina es el precio; cuánto dura, sí)
        tr.OpenNew(nil)
        Click(d.kindSell)
        A.same({ false, false, true, true }, { d.matsLabel:IsShown(), d.personal:IsShown(), d.expLabel:IsShown(), d.tipLabel:IsShown() })
        A.equal("Precio:", d.tipLabel:GetText())
        Click(d.kindAsk)
        A.same({ true, true, "Propina:" }, { d.matsLabel:IsShown(), d.personal:IsShown(), d.tipLabel:GetText() })
        -- (sin propinas, tampoco precio)
        HU:UnionCfg().tipsOff = true
        Click(d.kindSell)
        A.falsy(d.coins[1]:IsShown())
        HU:UnionCfg().tipsOff = nil
        d:Hide()
        -- (el BOE, a la venta: al tablón, de otro color, con «Venta», su precio y sin materiales; la mía, con Cancelar)
        Post(a, tr, { item = ItemLink(7931, "Cofia de mitril"), sell = true, gold = 3 })
        A.falsy(d:IsShown())
        A.matches("^o,v,1,0,30000,1,%-,%w+,i7931:Cofia de mitril$", Mine(HU, "Cofia").d)
        local row = Row(tr, "Cofia")
        A.truthy(row.saleTex:IsShown(), "de otro color")
        A.same({ 0.25, 0.82, 0.75, 0.10 }, row.saleTex._fill)
        A.matches("3fd0c0Venta|r.*24h", row.cells[6]:GetText())
        A.same({ "—", true }, { row.cells[4]:GetText(), row.cells[5]:GetText():find("^3|T") ~= nil })
        A.truthy(row.cancel:IsShown())
        -- (una legendaria también se vende; una solicitud no lleva el color de las ventas)
        Post(a, tr, { item = ItemLink(12345, "Legendaria"), sell = true })
        Post(a, tr, { item = "Encargo normal" })
        A.truthy(Row(tr, "Legendaria").saleTex:IsShown())
        A.falsy(Row(tr, "Encargo normal").saleTex:IsShown())
        A.equal("Abierta |cff9a8f7824h|r", Row(tr, "Encargo normal").cells[6]:GetText())
        -- (eliminar la legendaria con Cancelar: «g», fuera para todos)
        Click(Row(tr, "Legendaria").cancel)
        A.matches("^g,v,", Mine(HU, "Legendaria").d)
        A.is_nil(Row(tr, "Legendaria"))
        -- (un BOE de botín, que no se fabrica, también se puede encargar: Jorge, 25/11, «que los BOE también sea posible
        -- crear un order»)
        Post(a, tr, { item = ItemLink(12345, "Legendaria") })
        A.falsy(d:IsShown())
        local ordered
        for k, e in pairs(HU.db.wuStore.UNO.TR) do
            if k:find("^tester%-reino,o") and e.d:match("^o,p,.*Legendaria") then ordered = true end
        end
        A.truthy(ordered, "encargada")
        -- (en inglés: «Sale»)
        local en = F.Community({ locale = "enUS" })
        Observe(en)
        Known(en, GOODS)
        local tr2 = OpenTrade(en)
        Post(en, tr2, { item = ItemLink(7931, "Cofia de mitril"), sell = true })
        A.falsy(en.env.GuildUnionTradeNew:IsShown())
        A.matches("Sale", Row(tr2, "Cofia").cells[6]:GetText())
        A.same({}, a:Errors())
        A.same({}, en:Errors())
    end)

    it("la quieren varios: quien vende ve una fila con cada uno (con su aviso), habla con cada uno y la marca «Vendida» (o desde el clic derecho); vendida, deja de estar abierta", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        Known(a, GOODS)
        local tr = OpenTrade(a)
        Post(a, tr, { item = ItemLink(7931, "Cofia de mitril"), sell = true })
        local _, id = Mine(HU, "Cofia")
        local now = HU.StampNow()
        WU(a, "Compi-Reino", "TR", "a" .. id, "t", now - 2)
        WU(a, "Jefa-Reino", "TR", "a" .. id, "t", now - 1)
        WU(a, "Tester-Reino", "TR", "a" .. id, "t", now - 1)
        a.w:Advance(2)
        A.equal(2, HU:TradeUnread(), "un aviso de cada uno")
        A.matches("Le interesa.*Cofia", HU.db.tradeChats["Compi-Reino"][1])
        A.equal("open", Row(tr, "Cofia").entry.state, "sigue a la venta")
        Click(tr.viewBtns.priv)
        local who = {}
        for _, r in ipairs(Rows(tr)) do who[#who + 1] = r.entry.buyer end
        A.same({ "Compi-Reino", "Jefa-Reino" }, who)
        local jefa = Rows(tr)[2]
        A.matches("Jefa", jefa.cells[1]:GetText())
        A.matches("Venta", jefa.cells[5]:GetText())
        A.same({ false, true }, { jefa.yes:IsShown(), jefa.no:IsShown() }, "sin tic; la X la elimina")
        -- (elijo a Jefa: su chat, leído, y «Vendida» en vez de «Hecha»; solo su fila elegida)
        Click(jefa, "LeftButton")
        A.matches("Jefa", tr.chatTitle:GetText())
        A.equal(1, HU:TradeUnread())
        A.same({ "Vendida", true, true }, { tr.doneBtn:GetText(), tr.doneBtn:IsShown(), tr.doneBtn:IsEnabled() })
        for _, t in ipairs({ "Vendida", "Sold" }) do A.truthy(TextWidth(t, 12) + 8 <= tr.doneBtn._w, t .. " cabe en su botón") end
        A.same({ false, true }, { Rows(tr)[1].pickTex:IsShown(), Rows(tr)[2].pickTex:IsShown() })
        tr.chatInput:SetText("Te la guardo")
        tr.chatInput:GetScript("OnEnterPressed")(tr.chatInput)
        local sent = a.w.sent[#a.w.sent]
        A.same({ "TC~Te la guardo", "WHISPER", "Jefa-Reino" }, { sent.text, sent.dist, sent.target })
        -- (lo que escribe Compi entra en su fila)
        a.w:Receive("HU20", "TC~¿Sigue?", "WHISPER", "Compi-Reino")
        A.matches("¿Sigue%?", HU.db.tradeChats["Compi-Reino"][2])
        -- (Ctrl+clic en las dos: «Eliminar (2)»)
        a.env.IsControlKeyDown = function() return true end
        Click(Rows(tr)[1], "LeftButton")
        a.env.IsControlKeyDown = function() return false end
        A.equal("Eliminar (2)", tr.delBtn:GetText())
        Click(Rows(tr)[1], "LeftButton")
        -- (el clic derecho también la marca vendida)
        local m = FakeMenu(a)
        Click(Rows(tr)[1], "RightButton")
        A.truthy(m.buttons["Marcar como vendida"])
        A.is_nil(m.buttons["Marcar como hecha"])
        m.buttons["Marcar como vendida"]()
        A.matches("^s,v,", Mine(HU, "Cofia").d)
        for _, r in ipairs(Rows(tr)) do A.matches("Vendida", r.cells[5]:GetText()) end
        A.same({ false, false }, { Rows(tr)[1].no:IsShown(), tr.doneBtn:IsEnabled() }, "ya no se marca otra vez")
        -- (en el tablón, 10 min con «Vendida»; luego, solo en Mis encargos)
        Click(tr.viewBtns.pub)
        A.matches("Vendida", Row(tr, "Cofia").actText:GetText())
        A.falsy(Row(tr, "Cofia").cancel:IsShown())
        a.w.epoch = a.w.epoch + 601
        a.w:Advance(60)
        A.is_nil(Row(tr, "Cofia"))
        Click(tr.viewBtns.priv)
        A.equal(2, #Rows(tr))
        -- (otra, eliminada desde Mis encargos con «Eliminar (N)»: una vez aunque tenga dos filas)
        Post(a, tr, { item = ItemLink(12345, "Legendaria"), sell = true })
        local _, id2 = Mine(HU, "Legendaria")
        WU(a, "Compi-Reino", "TR", "a" .. id2, "t")
        WU(a, "Jefa-Reino", "TR", "a" .. id2, "t")
        a.w:Advance(2)
        Click(tr.viewBtns.priv)
        local rows = {}
        for _, r in ipairs(Rows(tr)) do if r.entry.item:find("Legendaria", 1, true) then rows[#rows + 1] = r end end
        A.equal(2, #rows)
        Click(rows[1], "LeftButton")
        a.env.IsShiftKeyDown = function() return true end
        Click(rows[2], "LeftButton")
        a.env.IsShiftKeyDown = function() return false end
        local n0 = #a.w.sent
        Click(tr.delBtn)
        A.matches("^g,v,", Mine(HU, "Legendaria").d)
        local n = 0
        for i = n0 + 1, #a.w.sent do if a.w.sent[i].text:find("~TR~o" .. id2 .. "~", 1, true) then n = n + 1 end end
        A.equal(1, n, "una sola vez")
        A.same({}, a:Errors())
    end)

    it("una venta de otro: «Me interesa» (aunque no tenga la profesión), la pueden querer varios; en Mis encargos, con quien vende; vendida, «Vendida»; quitarla de mi lista es ya no quererla", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        Professions(a, {})
        local tr = OpenTrade(a)
        local id, id2 = Id(HU, "Compi-Reino", 1), Id(HU, "Compi-Reino", 2)
        local exp = HU.B36(HU.StampNow() + 12 * 3600)
        WU(a, "Compi-Reino", "TR", "o" .. id, "o,v,1,0,50000,1,-," .. exp .. ",i7931:Cofia de mitril")
        WU(a, "Compi-Reino", "TR", "o" .. id2, "o,v,1,0,-,1,-," .. exp .. ",i7954:Gran espada")
        a.w:Advance(2)
        local row = Row(tr, "Cofia")
        A.truthy(row.saleTex:IsShown())
        A.same({ true, true, "Me interesa" }, { row.accept:IsShown(), row.accept:IsEnabled(), row.accept:GetText() })
        A.matches("12h", row.cells[6]:GetText())
        -- (los textos caben, también en inglés: el botón, con su letra; «Te interesa», en la casilla de la acción)
        for _, t in ipairs({ "Me interesa", "I want it" }) do A.truthy(TextWidth(t, 12) + 8 <= row.accept._w, t) end
        for _, t in ipairs({ "Te interesa", "You want it", "Vendida", "Sold" }) do A.truthy(TextWidth(t, 10) + 8 <= row.actText._w, t) end
        A.is_nil(Hover(a, row.accept), "sin porqué: no se hace")
        -- (con «Solo lo que puedo hacer», las ventas no salen en el tablón: no se hacen)
        Click(tr.onlyCraft)
        A.is_nil(Row(tr, "Cofia"))
        Click(tr.onlyCraft)
        Click(Row(tr, "Cofia").accept)
        A.equal("t", HU.db.wuStore.UNO.TR["tester-reino,a" .. id].d)
        row = Row(tr, "Cofia")
        A.falsy(row.accept:IsShown())
        A.matches("Te interesa", row.actText:GetText())
        -- (Jefa también, después: sigue a la venta, con los dos, por orden)
        WU(a, "Jefa-Reino", "TR", "a" .. id, "t", HU.StampNow() + 1)
        a.w:Advance(2)
        A.equal("open", Row(tr, "Cofia").entry.state)
        A.same({ "Tester-Reino", "Jefa-Reino" }, Row(tr, "Cofia").entry.buyers)
        -- (en Mis encargos, con Compi: sin tic ni X ni «Vendida»; con «Solo lo que puedo hacer», también)
        Click(tr.viewBtns.priv)
        A.same({ "Cofia de mitril" }, Items(tr))
        local mine = Row(tr, "Cofia")
        A.matches("Compi", mine.cells[1]:GetText())
        A.same({ false, false }, { mine.yes:IsShown(), mine.no:IsShown() })
        Click(mine, "LeftButton")
        A.matches("Compi", tr.chatTitle:GetText())
        A.falsy(tr.doneBtn:IsShown(), "no la vendo yo")
        Click(tr.onlyCraft)
        A.same({ "Cofia de mitril" }, Items(tr))
        Click(tr.onlyCraft)
        -- (Compi la vende: «Vendida»; y lo que me escribe, a su chat)
        WU(a, "Compi-Reino", "TR", "o" .. id, "s,v,1,0,50000,1,-," .. exp .. ",i7931:Cofia de mitril")
        a.w:Advance(2)
        A.matches("Vendida", Row(tr, "Cofia").cells[5]:GetText())
        a.w:Receive("HU20", "TC~Vendida, lo siento", "WHISPER", "Compi-Reino")
        A.matches("lo siento", HU.db.tradeChats["Compi-Reino"][#HU.db.tradeChats["Compi-Reino"]])
        -- (la espada: me interesa y luego la quito de mi lista: ya no la quiero)
        Click(tr.viewBtns.pub)
        Click(Row(tr, "Gran espada").accept)
        Click(tr.viewBtns.priv)
        local m = FakeMenu(a)
        Click(Row(tr, "Gran espada"), "RightButton")
        A.is_nil(m.buttons["Marcar como vendida"], "no es mía")
        m.buttons["Eliminar"]()
        A.equal("", HU.db.wuStore.UNO.TR["tester-reino,a" .. id2].d)
        A.is_nil(Row(tr, "Gran espada"))
        Click(tr.viewBtns.pub)
        A.equal("Me interesa", Row(tr, "Gran espada").accept:GetText())
        A.same({}, a:Errors())
    end)

    it("si el juego aún no conoce el objeto, venderlo se decide al llegar (BOE: al tablón; si no llega, no); encargarlo, al momento", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        local items, asked = {}, {}
        Known(a, items)
        a.env.C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
        local tr = OpenTrade(a)
        local d = Post(a, tr, { item = ItemLink(7931, "Cofia de mitril"), sell = true })
        A.same({ 7931 }, asked, "se le pide")
        A.truthy(Said(a, "Comprobando el objeto con el juego…"))
        A.truthy(d:IsShown())
        A.same({}, Items(tr))
        -- (llega: es BOE; se publica)
        items[7931] = { "Cofia de mitril", 2, 40, 4, 2 }
        a.w:Fire("ITEM_DATA_LOAD_RESULT", 7931, true)
        A.falsy(d:IsShown())
        A.same({ "Cofia de mitril" }, Items(tr))
        A.matches("^o,v,", Mine(HU, "Cofia").d)
        -- (encargar uno que no conoce, aunque sea un BOE de botín: sale al momento, sin preguntar al juego. Jorge, 25/11:
        -- «que los BOE también sea posible crear un order»)
        Post(a, tr, { item = ItemLink(12346, "Otra cofia") })
        A.falsy(d:IsShown())
        A.truthy(Mine(HU, "Otra cofia"))
        A.same({ 7931 }, asked, "sin pedírselo al juego")
        Post(a, tr, { item = ItemLink(7933, "Misterio") })
        A.falsy(d:IsShown())
        A.truthy(Mine(HU, "Misterio"))
        -- (venderlo, si no llega, no)
        Post(a, tr, { item = ItemLink(7934, "Enigma"), sell = true })
        a.w:Advance(5)
        A.truthy(Said(a, "No se ha podido comprobar el objeto: prueba otra vez."))
        A.truthy(d:IsShown())
        -- (cerrada antes de que llegue: no se publica)
        Post(a, tr, { item = ItemLink(7935, "Cerrada"), sell = true })
        d:Hide()
        items[7935] = { "Cerrada", 2, 10, 4, 2 }
        a.w:Fire("ITEM_DATA_LOAD_RESULT", 7935, true)
        a.w:Advance(5)
        A.is_nil(Mine(HU, "Cerrada"))
        A.same({}, a:Errors())
    end)
end)

describe("Comercio (Trade.lua): la pestaña Buscar", function()
    -- (la comunidad de mi hermandad: yo, Compi (Herrería) y Jefa (Sastrería); el juego, los nombres de profesión e iconos)
    local function Club(a)
        a.env.C_Club = {
            GetGuildClubId = function() return 9 end,
            GetClubMembers = function() return { 1, 2, 3 } end,
            GetMemberInfo = function(_, id)
                if id == 1 then return { name = "Tester", isSelf = true } end
                if id == 2 then return { name = "Compi", profession1ID = 164, profession1Name = "Herrería", profession1Rank = 1 } end
                return { name = "Jefa", profession1ID = 197, profession1Name = "Sastrería", profession1Rank = 1 }
            end,
        }
        a.env.C_TradeSkillUI = { GetTradeSkillTexture = function(id) return "icono" .. id end }
    end
    -- (lo de OF de otra hermandad, ya llegado: «Nombre-Reino,profesión,datos»)
    local function PackOf(HU, tag, list)
        local lines, t = {}, HU.B36(HU.StampNow())
        for _, x in ipairs(list) do
            local n, k, d = x:match("^([^,]+),([^,]+),(.*)$")
            lines[#lines + 1] = n .. "," .. k .. "," .. t .. "," .. d
        end
        HU.db.packs = HU.db.packs or {}
        HU.db.packs[tag] = { OF = { h = { "h1" }, ok = { "h1" }, t = { lines } } }
        HU.packSets.OF.onChange(tag)
    end
    -- (lo que se ve: los objetos y, de quién lo hace, «Nombre ETIQ nivel ✓»)
    local function Found(tr, lst)
        local out = {}
        for _, r in ipairs((lst or tr.items).rows) do
            if r:IsShown() and r.entry then
                if r.entry.key then out[#out + 1] = r.cells[1]:GetText():match("%[(.-)%]")
                else out[#out + 1] = r.entry.name:match("^([^-]+)") .. " " .. r.entry.tag .. " " .. (r.cells[4]:GetText():gsub(" |T.-|t", " ✓")) end
            end
        end
        return out
    end
    local function Check(a, menu, text)
        for _, c in ipairs(menu.checks) do if c.text:find(text, 1, true) then return c.set() end end
        error("no hay casilla " .. text)
    end

    it("al lado de Mis encargos: filtros de profesión, nivel (el requerido), rareza y tipo (varios a la vez) y un buscador entre los fabricables; de cada uno, quién de la unión lo hace, conectados primero; «Ver todos», su ventana", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        Club(a)
        -- (tres de Herrería, en el orden de su lista de oficios, una de Sastrería, una de Alquimia y seis clavos de
        -- Herrería sin nivel requerido, para que haya más de las 9 filas que se ven)
        local l = HU.ProfessionsForTests.list(164)
        local hoja, botas, espada = l[1].id, l[2].id, l[3].id
        local bolsa, pocion = HU.CRAFT_ITEMS[197][1], HU.CRAFT_ITEMS[171][1]
        -- (nombre, calidad, nivel de objeto, clase, ligado y nivel requerido)
        local known = { [hoja] = { "Hoja tosca", 1, 6, 2, 0, 1 }, [botas] = { "Botas verdes", 2, 15, 4, 2, 10 },
            [espada] = { "Espada azul", 3, 30, 2, 2, 25 }, [bolsa] = { "Bolsa de lino", 1, 10, 1, 0, 0 },
            [pocion] = { "Poción menor", 1, 5, 0, 0, 1 } }
        for i = 4, 9 do known[l[i].id] = { "Clavo " .. i, 1, 1, 7, 0, 0 } end
        Known(a, known)
        -- (Compi (UNO) sabe la espada; Bea (DOS, desconectada) también, con más nivel; Blas (DOS), solo la hoja)
        WU(a, "Compi-Reino", "OF", "164", "250," .. l.hash .. ",E")
        PackOf(HU, "DOS", { "Bea-Reino,164,275," .. l.hash .. ",E", "Blas-Reino,164,290," .. l.hash .. ",B" })
        HU.remoteRoster.DOS = { updated = a.env.GetTime(), members = { { name = "Bea-Reino", online = false }, { name = "Blas-Reino", online = true } } }
        local asked = {}
        local crafters = HU.UnionCrafters
        F.Stub(HU, "UnionCrafters", function(self, q, items, needs)
            if items and not q then asked[#asked + 1] = next(items) end
            return crafters(self, q, items, needs)
        end)
        a.env.ChatFrameUtil = { InsertLink = function() return false end }
        local tr = OpenTrade(a)
        a.w:Advance(40) -- (los nombres, poco a poco: 30 cada medio segundo)
        A.falsy(tr.filters:IsShown(), "los filtros, solo en Buscar")
        Click(tr.viewBtns.find)
        A.truthy(tr.viewBtns.find.picked, "elegido, gris")
        A.same({ true, false, false, false }, { tr.filters:IsShown(), tr.search:IsShown(), tr.searchBox:IsShown(), tr.onlyCraft:IsShown() })
        -- (sin la lista de quién lo hace de debajo: Jorge, 25/11, «la quitas»; los objetos, en las 9 filas)
        A.same({ true, false, false, false }, { tr.items.list:IsShown(), tr.req.list:IsShown(), tr.chat:IsShown(), tr.found.list:IsShown() })
        A.equal(9, tr.items.n)
        A.same({ "Nivel:", "Rareza", "Tipo", "Buscar objeto" }, { tr.filters.lvlLabel:GetText(), tr.filters.qual:GetText(),
            tr.filters.type:GetText(), tr.filters.search.Instructions:GetText() })
        -- (sin filtros, todos los que el juego conoce, de más nivel requerido a menos (sin él, detrás). Quién lo hace no se
        -- mira al pintar la lista, que así se trababa al bajar (Jorge, 25/11): en sus dos últimas columnas, «Ver todos» y
        -- «Publicarlo» (Jorge: «all [see all]… otra columna de board… [post it]»))
        local shown = Found(tr)
        A.equal(9, #shown)
        A.same({ "Espada azul", "Botas verdes", "Hoja tosca", "Poción menor", "Bolsa de lino" }, { unpack(shown, 1, 5) })
        A.equal(0, #asked, "nadie calcula quién lo hace al pintar la lista")
        local rows = tr.items.rows
        A.same({ "25", "Herrería", true }, { rows[1].cells[2]:GetText(), rows[1].cells[3]:GetText():match("Herrería"),
            rows[1].cells[3]:GetText():find("icono164", 1, true) ~= nil })
        A.same({ "10", "1", "—" }, { rows[2].cells[2]:GetText(), rows[3].cells[2]:GetText(), rows[5].cells[2]:GetText() },
            "el nivel requerido; sin él, «—»")
        A.same({ "Quién lo hace", "Tablón" }, { tr.items.hdrCells[4]:GetText(), tr.items.hdrCells[5]:GetText() })
        for i = 1, 3 do
            A.same({ true, true, "", "" }, { rows[i].allBtn:IsShown(), rows[i].postBtn:IsShown(), rows[i].cells[4]:GetText(),
                rows[i].cells[5]:GetText() }, "fila " .. i)
        end
        A.same({ "Ver todos", "Publicarlo" }, { rows[1].allBtn:GetText(), rows[1].postBtn:GetText() })
        A.same({ rows[1].cells[4], rows[1].cells[5] }, { rows[1].allBtn._pts.CENTER[1], rows[1].postBtn._pts.CENTER[1] },
            "en el centro de sus columnas")
        -- («Publicarlo»: el encargo del tablón con ese objeto, y queda elegido)
        Click(rows[2].postBtn)
        local pd = a.env.GuildUnionTradeNew
        A.same({ true, "Nuevo encargo", true }, { pd:IsShown(), pd.title:GetText(), pd.expLabel:IsShown() })
        A.matches("Botas verdes", pd.item:GetText())
        pd:Hide()
        -- (bajando: lo último)
        a.env.FauxScrollFrame_SetOffset(tr.items.scroll, 2)
        tr.items.scroll:GetScript("OnVerticalScroll")(tr.items.scroll, 48)
        A.equal("Hoja tosca", Found(tr)[1])
        -- (su buscador: por el nombre, sin acentos ni mayúsculas, y se vuelve arriba)
        local s = tr.filters.search
        s:SetText("POCION"); s:GetScript("OnTextChanged")(s, true)
        A.same({ "Poción menor" }, Found(tr))
        A.equal(0, a.env.FauxScrollFrame_GetOffset(tr.items.scroll))
        -- (Mayús+clic en un objeto con el buscador escribiendo: entra su enlace y sale solo ese objeto; sin escribir en él, nada)
        -- (en el juego, SetText avisa con OnTextChanged; el WoW de mentira, no: se avisa a mano)
        local function Insert(box, lk) a.env.ChatFrameUtil.InsertLink(lk); box:GetScript("OnTextChanged")(box, false) end
        local link = select(2, a.env.C_Item.GetItemInfo(espada))
        s.HasFocus = function() return true end
        Insert(s, link)
        -- (se ve su nombre, del color de su calidad, sin los códigos del enlace, que queda aparte: Jorge, 25/11, «cuando
        -- linkeo no se ve, pero está»)
        A.same({ "[Espada azul]", link }, { s:GetText(), s.link })
        A.same({ 0, 0x70 / 255, 0xdd / 255 }, s._textColor)
        A.same({ "Espada azul" }, Found(tr))
        s.HasFocus = function() return false end
        Insert(s, select(2, a.env.C_Item.GetItemInfo(botas)))
        A.same({ "Espada azul" }, Found(tr))
        -- (borrar con un enlace puesto lo quita entero, de una vez: «debería borrarse, entero de una si es linkeado»)
        s:SetText("[Espada azul"); s:GetScript("OnTextChanged")(s, true)
        A.same({ "", true, { 1, 1, 1 } }, { s:GetText(), s.link == nil, s._textColor })
        A.equal(9, #Found(tr), "todos otra vez")
        -- (otro enlace encima del que había: el nuevo, por su nombre; lo que no se fabrica, nada)
        s.HasFocus = function() return true end
        Insert(s, link)
        s:SetText("|cffffffff|Hitem:999999::::::::60:::::::|h[Piedra]|h|r"); s:GetScript("OnTextChanged")(s, false)
        A.same({ "[Piedra]", "|cffffffff|Hitem:999999::::::::60:::::::|h[Piedra]|h|r" }, { s:GetText(), s.link })
        A.same({}, Found(tr))
        s.HasFocus = function() return false end
        s:SetText(""); s:GetScript("OnTextChanged")(s, true)
        -- (los desplegables salen siempre debajo de su botón, como los del juego, y no donde está el ratón (Jorge, 25/11);
        -- el de profesión, con su icono detrás de la casilla)
        local m = FakeDrop(a)
        Click(tr.filters.prof)
        A.same({ "TOPLEFT", tr.filters.prof, "BOTTOMLEFT", 0, -2 }, m.anchor)
        A.same({ tr.filters.prof, "contexto" }, { m.owner, m.mixin })
        A.is_nil(m.atCursor, "no en el ratón")
        A.equal("Profesión", m.title)
        A.equal("|Ticono171:14:14|t Alquimia", m.checks[1].text)
        Check(a, m, "Herrería")
        A.equal("Herrería", tr.filters.prof:GetText())
        A.same({ "Espada azul", "Botas verdes", "Hoja tosca" }, { unpack(Found(tr), 1, 3) })
        -- (rareza, con los nombres de Blizzard y sin el naranja, que no se fabrica (Jorge, 25/11): poco común y raro)
        m.checks = {}
        Click(tr.filters.qual)
        A.same({ "TOPLEFT", tr.filters.qual, "BOTTOMLEFT", 0, -2 }, m.anchor)
        A.equal("Rareza", m.title)
        local qs = {}
        for i, c in ipairs(m.checks) do qs[i] = c.text end
        A.same({ "|cffffffffComún|r", "|cff1eff00Poco común|r", "|cff0070ddRaro|r", "|cffa335eeÉpico|r" }, qs)
        m.checks = {}
        Click(tr.filters.qual)
        Check(a, m, "Poco común")
        Check(a, m, "Raro")
        A.equal("Rareza (2)", tr.filters.qual:GetText())
        A.truthy(m.checks[2].is(), "marcada")
        A.same({ "Espada azul", "Botas verdes" }, Found(tr))
        -- (nivel requerido, de 20 a…; no el de objeto)
        tr.filters.lvlMin:SetText("20")
        tr.filters.lvlMin:GetScript("OnTextChanged")(tr.filters.lvlMin)
        A.same({ "Espada azul" }, Found(tr))
        tr.filters.lvlMax:SetText("25")
        tr.filters.lvlMax:GetScript("OnTextChanged")(tr.filters.lvlMax)
        A.same({ "Espada azul" }, Found(tr), "pide 25 (su nivel de objeto es 30)")
        tr.filters.lvlMax:SetText("24")
        tr.filters.lvlMax:GetScript("OnTextChanged")(tr.filters.lvlMax)
        A.same({}, Found(tr))
        A.equal("Ningún objeto fabricable encaja con los filtros.", tr.items.empty:GetText())
        for _, box in ipairs({ tr.filters.lvlMin, tr.filters.lvlMax }) do box:SetText(""); box:GetScript("OnTextChanged")(box) end
        -- (tipo: armadura; y armas)
        m.checks = {}
        Click(tr.filters.type)
        A.same({ "TOPLEFT", tr.filters.type, "BOTTOMLEFT", 0, -2 }, m.anchor)
        Check(a, m, "Armadura")
        A.same({ "Botas verdes" }, Found(tr))
        m.checks = {}
        Click(tr.filters.type)
        Check(a, m, "Armas")
        A.equal("Tipo (2)", tr.filters.type:GetText())
        A.same({ "Espada azul", "Botas verdes" }, Found(tr))
        -- (clic derecho en un objeto: se elige y sale «Publicar en el tablón» (Jorge, 25/11), que abre el anuncio del
        -- tablón con él; y «Ver quién lo hace» si alguien lo hace)
        m = FakeMenu(a)
        Click(tr.items.rows[2], "RightButton")
        A.truthy(tr.items.rows[2].pickTex:IsShown(), "elegido")
        A.matches("Botas verdes", m.title)
        A.truthy(m.buttons["Publicar en el tablón"] and m.buttons["Ver quién lo hace"] and m.buttons["Cancelar"])
        m.buttons["Publicar en el tablón"]()
        local nd = a.env.GuildUnionTradeNew
        A.same({ true, "Nuevo encargo", true }, { nd:IsShown(), nd.title:GetText(), nd.expLabel:IsShown() })
        A.matches("Botas verdes", nd.item:GetText())
        -- (la ventana del anuncio se mueve, sin salirse de la pantalla: Jorge, 25/11)
        A.truthy(nd._scripts.OnDragStart and nd._scripts.OnDragStop, "se arrastra")
        nd:Hide()
        m = FakeMenu(a)
        Click(tr.items.rows[1], "RightButton")
        A.truthy(m.buttons["Ver quién lo hace"])
        -- («Ver todos» en la espada: su ventana, a la derecha de la de hermandad, con todos, conectados primero; la
        -- espada, elegida)
        local who = a.env.GuildUnionTradeWho
        A.falsy(who:IsShown())
        Click(tr.items.rows[1].allBtn)
        A.truthy(who:IsShown())
        A.equal(a.env.CommunitiesFrame, who._pts.TOPLEFT[1])
        A.same({ "TOPRIGHT", 4, 0 }, { who._pts.TOPLEFT[2], who._pts.TOPLEFT[3], who._pts.TOPLEFT[4] })
        A.truthy(tr.items.rows[1].pickTex:IsShown())
        A.matches("Quién lo hace: .*Espada azul", who.titleText:GetText())
        A.same({ "Compi UNO 250 ✓", "Bea DOS 275 ✓" }, Found(tr, who.lst))
        A.matches("Pueden hacerlo: 2", who.hint:GetText())
        -- (su buscador por nombre, solo entre los de la ventana: Jorge, 25/11)
        A.equal("Buscar nombre", who.find.Instructions:GetText())
        who.find:SetText("bea"); who.find:GetScript("OnTextChanged")(who.find, true)
        A.same({ "Bea DOS 275 ✓" }, Found(tr, who.lst))
        A.matches("Pueden hacerlo: 2", who.hint:GetText(), "cuántos pueden, todos")
        who.find:SetText("blas"); who.find:GetScript("OnTextChanged")(who.find, true)
        A.same({}, Found(tr, who.lst), "Blas no sabe hacer la espada")
        who.find:SetText(""); who.find:GetScript("OnTextChanged")(who.find, true)
        A.same({ "Compi UNO 250 ✓", "Bea DOS 275 ✓" }, Found(tr, who.lst))
        A.truthy(a.env.UISpecialFrames[#a.env.UISpecialFrames] == "GuildUnionTradeWho", "se cierra con Esc")
        -- (se mueve)
        A.truthy(who._scripts.OnDragStart and who._scripts.OnDragStop, "se arrastra")
        -- (clic derecho en Compi: susurrar o hacerle un encargo, con la espada ya puesta: Jorge, 25/11, «whisp y make an
        -- order»)
        m = FakeMenu(a)
        Click(who.lst.rows[1], "RightButton")
        A.equal("Compi-Reino", m.title)
        A.truthy(m.buttons["Susurrar"] and m.buttons["Hacer un encargo"] and m.buttons["Cancelar"])
        A.is_nil(m.buttons["Invitar al grupo"])
        local whispered
        F.Stub(HU, "WhisperTo", function(name) whispered = name end)
        m.buttons["Susurrar"]()
        A.equal("Compi-Reino", whispered)
        m.buttons["Hacer un encargo"]()
        local d = a.env.GuildUnionTradeNew
        A.same({ true, "Encargo para Compi-Reino", "Compi-Reino", true }, { d:IsShown(), d.title:GetText(), d.to:GetText(),
            d.personal:GetChecked() })
        A.matches("Espada azul", d.item:GetText())
        d:Hide()
        -- (en mí: solo mi nombre, sin susurrar ni encargar)
        m = FakeMenu(a)
        local first = who.lst.rows[1]
        local saved = first.entry
        first.entry = { name = HU:Me() }
        Click(first, "RightButton")
        A.truthy(m.title and m.buttons["Cancelar"])
        A.is_nil(m.buttons["Susurrar"]); A.is_nil(m.buttons["Hacer un encargo"])
        first.entry = saved
        -- (las filas de la ventana, por encima de su barra: les llegan los clics)
        A.truthy(who.lst.rows[1]:GetFrameLevel() > who.lst.scroll:GetFrameLevel())
        -- («+ Nuevo encargo», con lo elegido, al tablón)
        A.truthy(tr.new:IsShown())
        Click(tr.new)
        A.same({ "Nuevo encargo", true }, { d.title:GetText(), d.expLabel:IsShown() })
        A.matches("Espada azul", d.item:GetText())
        d:Hide()
        -- (fuera los filtros de rareza y tipo, solo Sastrería: la bolsa; la ventana sigue con la espada hasta que se pide
        -- otra. De la bolsa, Jefa solo tiene la profesión (sin línea de oficios), así que ya no sale: solo quien sabe la
        -- receta. Jorge, 25/11)
        for _, b in ipairs({ tr.filters.qual, tr.filters.type, tr.filters.prof }) do
            m.checks = {}
            Click(b)
            for _, c in ipairs(m.checks) do if c.is() then c.set() end end
        end
        A.same({ "Profesión", "Rareza", "Tipo" }, { tr.filters.prof:GetText(), tr.filters.qual:GetText(), tr.filters.type:GetText() })
        m.checks = {}
        Click(tr.filters.prof)
        Check(a, m, "Sastrería")
        A.same({ "Bolsa de lino" }, Found(tr))
        A.matches("Espada azul", who.titleText:GetText())
        who.find:SetText("jefa")
        Click(tr.items.rows[1].allBtn)
        A.matches("Bolsa de lino", who.titleText:GetText())
        A.equal("", who.find:GetText(), "con otro objeto, el buscador vacío")
        A.same({}, Found(tr, who.lst), "Jefa solo tiene la profesión, no se sabe que sepa la receta: no sale")
        -- (sin repintar por fotograma)
        local function Inside(f)
            while f do if f == tr then return true end f = f._parent end
            return false
        end
        for _, fr in ipairs(a.w.frames) do A.falsy(Inside(fr) and fr._scripts.OnUpdate, "un OnUpdate en Comercio") end
        -- (de vuelta al Tablón: el buscador y la casilla, sin filtros; Mayús+clic también entra en su buscador. La ventana,
        -- abierta hasta que se cierra la sección)
        Click(tr.viewBtns.pub)
        A.same({ false, true, true, false }, { tr.filters:IsShown(), tr.search:IsShown(), tr.onlyCraft:IsShown(), tr.items.list:IsShown() })
        tr.search.HasFocus = function() return true end
        a.env.ChatFrameUtil.InsertLink(link)
        A.equal(link, tr.search:GetText())
        A.truthy(who:IsShown())
        tr:Hide()
        A.falsy(who:IsShown())
        tr:Show()
        A.falsy(who:IsShown(), "no vuelve sola")
        A.same({}, a:Errors())
    end)

    it("los encantamientos (no son objetos) solo salen sin filtros de color, tipo o nivel; mientras cargan los nombres, lo dice; con OF nuevo se repinta; caben, también en inglés", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        local first = HU.CRAFT_SPELLS[333][1]
        a.env.C_Spell = {
            GetSpellName = function(id) if id == first then return "Encantar brazales" end end,
            GetSpellLink = function(id) if id == first then return "|cff71d5ff|Hspell:" .. id .. "|h[Encantar brazales]|h|r" end end,
        }
        local tr = OpenTrade(a)
        Click(tr.viewBtns.find)
        A.same({ "Encantar brazales" }, Found(tr))
        A.equal("—", tr.items.rows[1].cells[2]:GetText(), "sin nivel")
        local m = FakeMenu(a)
        Click(tr.filters.qual)
        Check(a, m, "Poco común")
        A.same({}, Found(tr))
        m.checks[2].set()
        A.same({ "Encantar brazales" }, Found(tr))
        -- (lo que llega de oficios con Buscar a la vista se pinta 2 s después; solo sale quien sabe la receta, así que
        -- Compi llega con su línea marcando ese encantamiento. Jorge, 25/11)
        local el = HU.ProfessionsForTests.list(333)
        local pos
        for i = 1, el.n do if el[i].id == first and el[i].spell then pos = i; break end end
        A.truthy(pos, "el encantamiento está en la lista de oficios")
        local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local v = 2 ^ ((pos - 1) % 6)
        local bits = string.rep("A", math.floor((pos - 1) / 6)) .. B64:sub(v + 1, v + 1)
        WU(a, "Compi-Reino", "OF", "333", "300," .. el.hash .. "," .. bits)
        a.w:Advance(3)
        Click(tr.items.rows[1].allBtn)
        A.same({ "Compi UNO 300 ✓" }, Found(tr, a.env.GuildUnionTradeWho.lst))
        -- (sin nada del juego todavía)
        local b = F.Community()
        Observe(b)
        b.env.C_Spell = nil
        local tr2 = OpenTrade(b)
        Click(tr2.viewBtns.find)
        A.equal("Cargando los objetos del juego…", tr2.items.empty:GetText())
        -- (la fila de filtros cabe y no se pisa, en los dos idiomas)
        for _, x in ipairs({ { b, tr2 }, { F.Community({ locale = "enUS" }) } }) do
            local c, t = x[1], x[2]
            if not t then Observe(c); t = OpenTrade(c) end
            local L, f = c.HU.L, t.filters
            local right, typeR = 0, nil
            for _, w in ipairs({ f.prof, f.lvlLabel, f.lvlMin, f.lvlTo, f.lvlMax, f.qual, f.type, f.search }) do
                local l, r = Span(t, w)
                A.truthy(l >= right, "se pisan: " .. l .. " < " .. right)
                if w == f.search then A.truthy(l - 9 >= typeR, "el marco del buscador no pisa «Tipo»") end
                right = r
                if w == f.type then typeR = r end
            end
            A.truthy(right <= SECTION_W - 14, "cabe: acaba en " .. right)
            -- («Nivel:», con las cajas pegadas: Jorge, 25/11)
            A.truthy(TextWidth(L("Nivel:"), 10) <= f.lvlLabel._w, L("Nivel:"))
            local _, labelR = Span(t, f.lvlLabel)
            local minL = Span(t, f.lvlMin)
            A.truthy(minL - labelR <= 6, "la caja, pegada a «" .. L("Nivel:") .. "»: " .. (minL - labelR))
            A.truthy(TextWidth(L("a"), 10) <= f.lvlTo._w, L("a"))
            -- (lo más largo que puede decir cada botón)
            for _, y in ipairs({ { f.prof, { L("Primeros auxilios"), L("Encantamiento"), L("Peletería"), L("Profesión") .. " (9)" } },
                { f.qual, { L("Poco común"), L("Común"), L("Raro"), L("Épico"), L("Rareza") .. " (4)" } },
                { f.type, { L("Contenedores"), L("Misceláneo"), L("Mercancías"), L("Consumible"), L("Tipo") .. " (7)" } } }) do
                for _, text in ipairs(y[2]) do A.truthy(TextWidth(text, 12) + 16 <= y[1]._w, "«" .. text .. "» cabe en su botón") end
            end
            -- (la ayuda del buscador, entre su lupa y su X; «Ver todos», en letra pequeña, en su botón)
            A.truthy(TextWidth(L("Buscar objeto"), 10) + 20 + 14 <= f.search._w, L("Buscar objeto"))
            local all, post = t.items.rows[1].allBtn, t.items.rows[1].postBtn
            A.truthy(TextWidth(L("Ver todos"), 10) + 12 <= all._w, L("Ver todos"))
            A.truthy(TextWidth(L("Publicarlo"), 10) + 12 <= post._w, L("Publicarlo"))
            A.same({ "GameFontNormalSmall", "GameFontNormalSmall" }, { all._font, post._font })
            -- (los títulos de esas dos columnas caben en ellas: 92 y 84, menos 4 a cada lado)
            A.truthy(TextWidth(L("Quién lo hace"), 10) <= 92 - 8, L("Quién lo hace"))
            A.truthy(TextWidth(L("Tablón"), 10) <= 84 - 8, L("Tablón"))
            A.same({}, c:Errors())
        end
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
-- Lo que pidió Jorge al ver la 331 (25/11): desplegables que se cierran con otro clic, la propina, Mis encargos con lo
-- sin leer primero y las flechas de «cargando» de Buscar
---------------------------------------------------------------------------
describe("Comercio (Trade.lua): lo del 25/11 por la tarde", function()
    it("los desplegables de Buscar: otro clic en su botón con el menú abierto lo cierra, también si el juego lo acaba de cerrar por ese mismo clic", function()
        local a = F.Community()
        Observe(a)
        local tr = OpenTrade(a)
        Click(tr.viewBtns.find)
        local m = FakeDrop(a)
        m.opens = 0
        a.env.Menu.GetManager = function()
            return { OpenMenu = function()
                m.opens = m.opens + 1
                m.menu = { Close = function(self) self.closed = true; if self.cb then self.cb() end end,
                    SetClosedCallback = function(self, cb) self.cb = cb end }
                return m.menu
            end }
        end
        local b = tr.filters.prof
        local function Press() b:GetScript("OnMouseDown")(b); Click(b) end
        Press()
        A.same({ 1, nil }, { m.opens, m.menu.closed })
        a.w:Advance(1)
        Press()
        A.same({ 1, true }, { m.opens, m.menu.closed }, "otro clic: se cierra y no se vuelve a abrir")
        a.w:Advance(1)
        Press()
        A.equal(2, m.opens, "el siguiente, se abre")
        -- (el juego lo cierra al pulsar fuera de él, antes del clic: si es en el botón, en ese mismo instante, no se reabre)
        a.w:Advance(1)
        m.menu:Close()
        Press()
        A.equal(2, m.opens)
        a.w:Advance(1)
        Press()
        A.equal(3, m.opens, "cerrado hace un momento, se abre")
        A.same({}, a:Errors())
    end)

    it("la propina: «Sin propina» y «A negociar» se excluyen y esconden las monedas; al vender, solo «A negociar»; en el tablón se lee", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        local tr = OpenTrade(a)
        tr.OpenNew(nil)
        local d = a.env.GuildUnionTradeNew
        A.same({ "Sin propina", "A negociar" }, { d.noTip.Text:GetText(), d.nego.Text:GetText() })
        A.same({ true, true, true }, { d.noTip:IsShown(), d.nego:IsShown(), d.coins[1]:IsShown() })
        Toggle(d.noTip)
        A.same({ true, false, false }, { d.noTip:GetChecked(), d.nego:GetChecked(), d.coins[1]:IsShown() })
        Toggle(d.nego)
        A.same({ false, true, false }, { d.noTip:GetChecked(), d.nego:GetChecked(), d.coins[1]:IsShown() }, "se excluyen")
        Toggle(d.nego)
        A.truthy(d.coins[1]:IsShown(), "sin ninguna, las monedas")
        -- (al vender, el precio: solo «A negociar»)
        Click(d.kindSell)
        A.same({ "Precio:", false, true }, { d.tipLabel:GetText(), d.noTip:IsShown(), d.nego:IsShown() })
        Click(d.kindAsk)
        -- (sin propina: «0» en sus datos y «Sin propina» en el tablón; a negociar, «-» y «A negociar»)
        d.item:SetText("Encargo sin propina")
        Toggle(d.noTip)
        Click(Btn(a, d, "Publicar"))
        A.matches("^o,p,1,1,0,1,%-,", Mine(HU, "Encargo sin propina").d)
        A.matches("Sin propina", Row(tr, "Encargo sin propina").cells[5]:GetText())
        tr.OpenNew(nil)
        A.same({ false, false }, { d.noTip:GetChecked(), d.nego:GetChecked() }, "cada vez, sin marcar")
        d.item:SetText("Encargo a negociar")
        d.coins[1]:SetText("5")
        Toggle(d.nego)
        Click(Btn(a, d, "Publicar"))
        A.matches("^o,p,1,1,%-,1,%-,", Mine(HU, "Encargo a negociar").d, "con «A negociar», las monedas no cuentan")
        A.matches("A negociar", Row(tr, "Encargo a negociar").cells[5]:GetText())
        A.same({}, a:Errors())
    end)

    it("Mis encargos: los de chats con algo sin leer, primero y con brillo; leer no los mueve; lo que llega, sí; el número es de chats", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        local tr = OpenTrade(a)
        HU:TradeTest(true)
        Click(tr.viewBtns.priv)
        A.same({ "Cofia de mitril", "Gran espada de mitril", "Elixir de agilidad", "Poción de curación superior" }, Items(tr))
        local rows = Rows(tr)
        A.same({ true, true, true, false }, { rows[1].glow:IsShown(), rows[2].glow:IsShown(), rows[3].glow:IsShown(),
            rows[4].glow:IsShown() }, "con brillo, los de sin leer")
        -- (leer la de Lyra: deja de brillar, pero no se mueve)
        Click(rows[1], "LeftButton")
        A.same({ "Cofia de mitril", "Gran espada de mitril", "Elixir de agilidad", "Poción de curación superior" }, Items(tr))
        A.falsy(Rows(tr)[1].glow:IsShown())
        A.equal("Mis encargos (2)", tr.viewBtns.priv:GetText())
        -- (Bea escribe dos veces más: cuatro líneas sin leer, pero dos chats)
        HU:TradeChatLine("Bea-Prueba", "Bea-Prueba", "¿Hay novedades?")
        HU:TradeChatLine("Bea-Prueba", "Bea-Prueba", "¿Hola?")
        A.same({ 4, 2 }, { HU:TradeUnread(), HU:TradeUnreadChats() })
        A.equal("Mis encargos (2)", tr.viewBtns.priv:GetText(), "el número, de chats")
        -- (escribe Jandra, la de la poción: al repintar, sube con las de sin leer)
        HU:TradeChatLine("Jandra-Prueba", "Jandra-Prueba", "¿Y la poción?")
        HU:Changed("unionCfg")
        A.same({ "Poción de curación superior", "Gran espada de mitril", "Elixir de agilidad", "Cofia de mitril" }, Items(tr))
        A.same({}, a:Errors())
    end)

    it("encargo personal: el nombre se autorrellena también con las listas completas de las otras hermandades, desconectados incluidos", function()
        local a = F.Community()
        Observe(a)
        local HU = a.HU
        -- (la lista completa de DOS, ya llegada: «Nombre-Reino,clase,nivel,rango»)
        HU.db.packs = HU.db.packs or {}
        HU.db.packs.DOS = { MB = { h = { "h1" }, ok = { "h1" }, t = { { "Zacarías-Reino,1,60,1" } } } }
        local tr = OpenTrade(a)
        tr.OpenNew(nil)
        local d = a.env.GuildUnionTradeNew
        Toggle(d.personal)
        d.to:SetText("zaca"); d.to:GetScript("OnTextChanged")(d.to, true)
        local hit
        for _, f in ipairs(a.w.frames) do if f.value == "Zacarías-Reino" then hit = f end end
        A.truthy(hit and hit:IsShown(), "Zacarías, de DOS")
        A.matches("<DOS>", hit.text:GetText())
        A.same({}, a:Errors())
    end)

    it("Buscar: mientras el juego da los nombres de los objetos, el círculo de carga del juego, pequeño, abajo a la derecha de la sección; al acabar, fuera; fuera de Buscar no se ve", function()
        local a = F.Community()
        Observe(a)
        Known(a, {})
        local tr = OpenTrade(a)
        Click(tr.viewBtns.find)
        local spin = tr.items.spin
        A.truthy(spin:IsShown())
        A.same({ "LoadingSpinnerTemplate", 24, 24 }, { spin._template, spin._w, spin._h }, "el del buscador de grupos")
        A.same({ tr, "BOTTOMRIGHT", -12, 8 }, spin._pts.BOTTOMRIGHT)
        A.equal(tr.items.list, spin:GetParent(), "de la lista de Buscar: se esconde con ella")
        a.w:Advance(400)
        A.falsy(spin:IsShown(), "al acabar, fuera")
        A.same({}, a:Errors())
    end)

    it("nuevo encargo: atada por arriba (con «Sin propina» encoge sin bajar y se quita en el mismo sitio); arrastrada, sigue atada por arriba; la X la cierra; «Encargo personal», más abajo y con una raya encima", function()
        local a = F.Community()
        Observe(a)
        local tr = OpenTrade(a)
        tr.OpenNew(nil)
        local d = a.env.GuildUnionTradeNew
        A.same({ tr, "CENTER", 0, 160 }, d._pts.TOP, "atada por arriba")
        A.is_nil(d._pts.CENTER, "no por el centro: al encoger bajaba y el clic caía en «Yo» de Materiales")
        local h0, y0 = d._h, d.noTip._pts.TOPLEFT[2]
        Toggle(d.noTip)
        A.same({ true, false }, { d._h < h0, d.coins[1]:IsShown() }, "sin monedas, encoge")
        A.same({ tr, "CENTER", 0, 160 }, d._pts.TOP, "sin moverse")
        A.equal(y0, d.noTip._pts.TOPLEFT[2], "la casilla, donde estaba")
        Toggle(d.noTip)
        A.same({ false, true, h0 }, { d.noTip:GetChecked(), d.coins[1]:IsShown(), d._h }, "otra vez con propina")
        -- («Encargo personal»: 12 más abajo que antes, con la raya en medio)
        local tipY = d.tipLabel._pts.TOPLEFT[2]
        A.same({ true, tipY - 22 - 44 - 12 + 5 }, { d.sep:IsShown(), d.personal._pts.TOPLEFT[2] })
        A.same({ 12, tipY - 22 - 44 - 6 + 2 }, { d.sep._pts.TOPLEFT[1], d.sep._pts.TOPLEFT[2] })
        Click(d.kindSell)
        A.same({ false, false }, { d.sep:IsShown(), d.personal:IsShown() }, "al vender, ni casilla ni raya")
        Click(d.kindAsk)
        -- (arrastrada: al soltarla, atada por arriba donde quedó, para que tampoco baje)
        d:GetScript("OnDragStop")(d)
        A.same({ a.env.UIParent, "BOTTOMLEFT", 0, 0 }, d._pts.TOPLEFT)
        A.is_nil(d._pts.TOP)
        -- (la X)
        A.same({ "UIPanelCloseButton", "TOPRIGHT", -2, -2 }, { d.close._template, "TOPRIGHT", d.close._pts.TOPRIGHT[1], d.close._pts.TOPRIGHT[2] })
        Click(d.close)
        A.falsy(d:IsShown(), "la X la cierra")
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
-- Lo que comparten los archivos de Comercio (HU.TradeInternal, Trade.lua): luacheck no ve sus campos
---------------------------------------------------------------------------
describe("Comercio: lo que comparten sus archivos (HU.TradeInternal)", function()
    it("todo lo que leen de la tabla existe con la sección montada (salvo el estado que empieza vacío)", function()
        local runner = require("lib.runner")
        local addon = require("lib.addon")
        local a = F.Community()
        OpenTrade(a)
        local T = a.HU.TradeInternal
        -- (vacíos hasta que se elige algo: el chat puesto y la fila elegida)
        local MAYBE_NIL = { chatKey = true, selected = true }
        local missing, n = {}, 0
        for _, f in ipairs(addon.LuaFiles()) do
            if f:match("^Trade%w*%.lua$") then
                local src = assert(addon.ReadFile(runner.here .. "/../" .. f))
                for name in src:gsub("%-%-[^\n]*", ""):gmatch("%f[%w_.]T%.([%a_][%w_]*)") do
                    n = n + 1
                    if T[name] == nil and not MAYBE_NIL[name] then missing[#missing + 1] = f .. ": T." .. name end
                end
            end
        end
        A.same({}, missing)
        A.truthy(n > 100, "no se han leído los archivos de Comercio")
        A.same({}, a:Errors())
    end)
end)
