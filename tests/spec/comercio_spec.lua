-- Comercio (Trade.lua): las líneas sin leer, «¿puedo hacerlo?» (HU:CanCraft, con las recetas que se leen al abrir la
-- ventana de una profesión), «Solo lo que puedo hacer», el «+» de pedir y el aspecto. Lo de antes de Comercio sigue en
-- miembros_spec.
local F = require("lib.fixtures")
local A = assert_

---------------------------------------------------------------------------
-- El WoW de mentira, con lo que aquí hace falta mirar
---------------------------------------------------------------------------
-- (lo que no guarda: activado, marcado, tamaño, alto, puntos y colores de fondo y borde)
local function Observe(a)
    local meta = a.w.frameMeta
    local base = meta.__index
    local extra = {
        SetEnabled = function(self, v) rawset(self, "_off", not v) end,
        IsEnabled = function(self) return not rawget(self, "_off") end,
        SetChecked = function(self, v) rawset(self, "_checked", v and true or false) end,
        GetChecked = function(self) return rawget(self, "_checked") == true end,
        SetSize = function(self, w, h) rawset(self, "_w", w); rawset(self, "_h", h) end,
        SetHeight = function(self, h) rawset(self, "_h", h) end,
        ClearAllPoints = function(self) rawset(self, "_pts", {}) end,
        SetPoint = function(self, p, ...)
            local pts = rawget(self, "_pts") or {}
            rawset(self, "_pts", pts)
            pts[p] = { ... }
        end,
        SetBackdropColor = function(self, ...) rawset(self, "_bg", { ... }) end,
        SetBackdropBorderColor = function(self, ...) rawset(self, "_edge", { ... }) end,
    }
    meta.__index = function(f, k) return extra[k] or base(f, k) end
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
        Click(tr.testBtn)
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
        Click(Row(tr, "Cofia"), "LeftButton")
        A.equal(2, HU:TradeUnread())
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
        Click(tr.testBtn)
        A.equal(0, HU:TradeUnread())
        A.equal("Mis encargos", tr.viewBtns.priv:GetText())
        A.same({ 1, 2, 3, 2, 3, 2, 3, 2, 3, 2, 0 }, seen, "un aviso «tradeUnread» con cada cambio")
        A.same({}, a:Errors())
    end)

    it("aceptar en el Tablón pone su chat sin verse: sigue sin leer hasta ir a Mis encargos", function()
        local a = F.Community()
        local HU = a.HU
        local tr = OpenTrade(a)
        Click(tr.testBtn)
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
        Click(tr.testBtn)
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
        a.env.GetItemInfo = function(id)
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
        Click(tr.testBtn)
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
        Click(tr.testBtn)
        A.same({ "Capa de seda carmesí", "Cofia de mitril", "Bolsa de tejido de lana", "Poción de curación superior" }, Items(tr))
        A.truthy(tr.onlyCraft:IsShown())
        A.falsy(tr.onlyCraft:GetChecked())
        A.same({ "Solo lo que puedo hacer", "En el tablón, solo lo que puedes hacer con tus profesiones y tus recetas (lo que no se sabe qué es, tampoco)." },
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
        Click(Btn(a, d, "Pedir"))
        A.same({ "Cofia de mitril", "Bolsa de tejido de lana" }, Items(tr))
        -- (al buscar, también en lo publicado)
        Search(tr, "o")
        A.truthy(tr.onlyCraft:IsShown())
        A.same({ "Cofia de mitril", "Bolsa de tejido de lana" }, Items(tr))
        Search(tr, "")
        -- (en Mis encargos no vale ni se ve)
        Click(tr.viewBtns.priv)
        A.falsy(tr.onlyCraft:IsShown())
        A.equal(4, #Rows(tr))
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
        Click(tr.testBtn)
        A.truthy(tr.onlyCraft:GetChecked())
        A.same({ "Cofia de mitril" }, Items(tr))
        A.same({}, a:Errors())
    end)
end)

---------------------------------------------------------------------------
-- Aspecto
---------------------------------------------------------------------------
describe("Comercio (Trade.lua): aspecto", function()
    it("el «+» de Comercio y el de Calendario: verde claro con borde claro y más grande; apagado, gris", function()
        local a = F.Community()
        Observe(a)
        local tr = OpenTrade(a)
        local P = a.HU.DJ.PLUS
        for i, b in ipairs({ tr.new, a.env.GuildUnionUnionRoster.calendar.new }) do
            A.equal("+", b:GetText(), "sigue siendo un «+», " .. i)
            A.same({ 26, 26 }, { b._w, b._h }, "más grande, " .. i)
            A.same(P.bg, b._bg, "verde, " .. i)
            A.truthy(math.max(P.bg[1], P.bg[2], P.bg[3]) >= 0.5, "claro")
            A.truthy(math.min(P.edge[1], P.edge[2], P.edge[3]) >= 0.6, "con el borde claro")
            A.same(P.edge, b._edge)
            b:GetScript("OnDisable")(b)
            A.same({ P.offBg, P.offEdge }, { b._bg, b._edge }, "apagado, gris, " .. i)
            b:GetScript("OnEnable")(b)
            A.same(P.bg, b._bg)
        end
        -- (en su fila, sin pisar el panel de la sección, que empieza 4 por encima del cuerpo)
        A.same({ tr, "TOPLEFT", 14, -30 }, tr.new._pts.TOPLEFT)
        A.truthy(-30 - tr.new._h >= tr.body._pts.TOPLEFT[4] + 4, "el «+» no pisa el panel")
        A.same({}, a:Errors())
    end)

    it("nombres: Tablón · Mis encargos y «Buscar receta», también en inglés (Board · My Orders, Search recipe)", function()
        local a = F.Community()
        Observe(a)
        local tr = OpenTrade(a)
        A.same({ "Tablón", "Mis encargos" }, { tr.viewBtns.pub:GetText(), tr.viewBtns.priv:GetText() })
        A.equal("Buscar receta", tr.search.Instructions:GetText())
        A.equal(200, tr.search._w, "más ancho")
        A.equal("Solo lo que puedo hacer", tr.onlyCraft.Text:GetText())
        -- (al pedir: «En el tablón: Sí / No»; con No, a quién)
        tr.OpenNew(nil)
        local d = a.env.GuildUnionTradeNew
        local label
        for _, fr in ipairs(a.w.frames) do if fr._parent == d and fr:GetText() == "En el tablón:" then label = fr end end
        A.truthy(label, "«En el tablón:»")
        Click(d.pubNo)
        d.item:SetText("Algo")
        local n0 = #a.w.chat
        Click(Btn(a, d, "Pedir"))
        A.matches("Si no va al tablón, pon a quién se la pides.", tostring(a.w.chat[n0 + 1] and a.w.chat[n0 + 1].msg))
        local en = F.Community({ locale = "enUS" })
        local tr2 = OpenTrade(en)
        A.same({ "Board", "My Orders" }, { tr2.viewBtns.pub:GetText(), tr2.viewBtns.priv:GetText() })
        A.equal("Search recipe", tr2.search.Instructions:GetText())
        A.equal("Only what I can craft", tr2.onlyCraft.Text:GetText())
        A.same({}, a:Errors())
        A.same({}, en:Errors())
    end)

    it("filas y títulos con aire, y caben en la sección con la ventana del juego a su alto de siempre", function()
        local a = F.Community()
        Observe(a)
        local tr = OpenTrade(a)
        -- (la ventana del juego mide 426 de alto: su lista de miembros, 426 - 63 - 28; la sección sube 26 por encima
        -- y deja 2 arriba y 4 abajo; el cuerpo de las listas empieza 62 más abajo)
        local BODY = (426 - 63 - 28) + 26 - 2 - 4 - 62
        A.truthy(tr.req.rows[1]._h >= 22, "filas más altas que las de 18: " .. tostring(tr.req.rows[1]._h))
        A.truthy(tr.req.hdr._h >= 24, "títulos")
        A.truthy(tr.req.list._h <= BODY, "el Tablón cabe: " .. tostring(tr.req.list._h) .. " de " .. BODY)
        -- (al buscar: lo publicado encima, quién lo hace debajo, con 6 entre medias)
        Click(tr.testBtn)
        Search(tr, "Poción")
        A.equal(1, #Rows(tr))
        local both = tr.req.list._h + 6 + tr.found.list._h
        A.truthy(both <= BODY, "las dos caben: " .. both .. " de " .. BODY)
        -- (sin nada publicado que encaje, quién lo hace ocupa todo)
        Search(tr, "nada de nada")
        A.truthy(tr.found.list._h <= BODY, "quién lo hace, sola: " .. tostring(tr.found.list._h))
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
