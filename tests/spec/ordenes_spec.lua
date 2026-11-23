-- Órdenes de hermandad (Orders.lua): /gremove, /gpromote, /gdemote y /ginvite con un botón seguro y tu clic, tras
-- confirmarlas; si el juego lo bloquea, la ventana de copiar y pegar de siempre, con las mismas órdenes
local F = require("lib.fixtures")
local A = assert_

-- (los botones seguros del WoW de mentira, con sus atributos)
local function Attrs(a)
    local create = a.env.CreateFrame
    a.env.CreateFrame = function(...)
        local f = create(...)
        local attr = {}
        f.SetAttribute = function(_, k, v) attr[k] = v end
        f.GetAttribute = function(_, k) return attr[k] end
        return f
    end
end
-- (el clic en el botón seguro: lo que el addon engancha, PostClick, al pulsar y al soltar)
local function Press(b) b:GetScript("PostClick")(b, "LeftButton", true); b:GetScript("PostClick")(b, "LeftButton", false) end
local function Shown(a, name) local f = rawget(a.env, name); return f ~= nil and f:IsShown() end

describe("Órdenes de hermandad: con el botón seguro", function()
    it("echar: pregunta como el juego («¿Seguro que…?», Sí / No), sin enseñar la orden, y la lanza el botón seguro", function()
        local a = F.Community()
        Attrs(a)
        local done
        a.HU:RunOrders({ title = "Echar de la hermandad", text = "Compi", lines = { "/gremove Compi" }, onDone = function(n) done = n end })
        local c, yes = a.env.GuildUnionOrdersConfirm, a.env.GuildUnionOrdersYes
        A.truthy(Shown(a, "GuildUnionOrdersConfirm"), "la ventanita de confirmar")
        A.falsy(Shown(a, "GuildUnionOrders"), "sin la de copiar y pegar")
        A.equal("¿Seguro que quieres echar a Compi de la hermandad?", c.body:GetText())
        A.equal("", c.cmds:GetText())
        A.equal("Sí", yes:GetText())
        A.is_nil((c.body:GetText() .. c.cmds:GetText()):find("/g", 1, true), "sin enseñar la orden")
        A.equal("macro", yes:GetAttribute("type"))
        A.equal(false, yes:GetAttribute("useOnKeyDown"), "se lanza al soltar")
        A.equal("/gremove Compi", yes:GetAttribute("macrotext"))
        -- (al pulsar, todavía nada; al soltar, ya lanzada por el juego: se cierra)
        yes:GetScript("PostClick")(yes, "LeftButton", true)
        A.truthy(c:IsShown(), "al pulsar sigue abierta")
        yes:GetScript("PostClick")(yes, "LeftButton", false)
        A.falsy(c:IsShown())
        A.is_nil(done, "se espera un momento por si el juego lo bloquea")
        a.w:Advance(2)
        A.equal(1, done, "hecha")
        A.same({}, a:Errors())
    end)

    it("varias (subir dos rangos): un clic las lanza todas, y cada una cuenta", function()
        local a = F.Community()
        Attrs(a)
        local done, each = nil, {}
        a.HU:RunOrders({ title = "Cambiar rango", text = "Compi", lines = { "/gpromote Compi", "/gpromote Compi" },
            onDone = function(n) done = n end, onLine = function(l) each[#each + 1] = l end })
        local yes = a.env.GuildUnionOrdersYes
        A.equal("/gpromote Compi\n/gpromote Compi", yes:GetAttribute("macrotext"))
        A.equal("¿Seguro que quieres subir a Compi 2 rangos?", a.env.GuildUnionOrdersConfirm.body:GetText())
        Press(yes)
        a.w:Advance(2)
        A.equal(2, done)
        A.same({ "/gpromote Compi", "/gpromote Compi" }, each)
        A.same({}, a:Errors())
    end)

    it("con varias personas, los nombres debajo; con su propia pregunta (el rango nuevo), esa", function()
        local function Ask(job)
            local a = F.Community()
            Attrs(a)
            a.HU:RunOrders(job)
            local c = a.env.GuildUnionOrdersConfirm
            A.same({}, a:Errors())
            return c.body:GetText(), c.cmds:GetText()
        end
        local q, list = Ask({ lines = { "/gremove Ana Sol", "/gremove Bea" } })
        A.equal("¿Seguro que quieres echar de la hermandad a estas 2 personas?", q)
        A.equal("Ana Sol\nBea", list)
        q, list = Ask({ lines = { "/gremove Ana", "/gdemote Bea", "/gdemote Bea" } })
        A.equal("¿Seguro que quieres hacer esto?", q)
        A.equal("Echar a Ana de la hermandad\nBajar a Bea 2 rangos", list)
        A.equal("¿Seguro que quieres subir a Ana un rango?", (Ask({ lines = { "/gpromote Ana" } })))
        A.equal("¿Seguro que quieres bajar a Ana un rango?", (Ask({ lines = { "/gdemote Ana" } })))
        q, list = Ask({ lines = { "/gpromote Ana" }, ask = "¿Seguro que quieres pasar a Ana a «Oficial»?" })
        A.equal("¿Seguro que quieres pasar a Ana a «Oficial»?", q)
        A.equal("", list)
    end)

    it("si el juego lo bloquea, pasa a copiar y pegar con las mismas órdenes, y ya no lo intenta hasta /reload", function()
        local a = F.Community()
        Attrs(a)
        local done
        a.HU:RunOrders({ title = "Echar de la hermandad", lines = { "/gremove Compi" }, onDone = function(n) done = n end })
        Press(a.env.GuildUnionOrdersYes)
        a.w:Fire("ADDON_ACTION_BLOCKED", "GuildUnion", "C_GuildInfo.Uninvite()")
        a.w:Advance(2)
        A.is_nil(done, "no se da por hecha")
        A.truthy(Shown(a, "GuildUnionOrders"), "la ventana de copiar y pegar")
        A.equal("/gremove Compi", a.env.GuildUnionOrders.cmd:GetText())
        -- (la siguiente, directamente a copiar y pegar)
        a.env.GuildUnionOrders:Hide()
        a.env.GuildUnionOrders:GetScript("OnHide")(a.env.GuildUnionOrders)
        a.HU:RunOrders({ title = "Echar de la hermandad", lines = { "/gremove Jefa" } })
        A.falsy(Shown(a, "GuildUnionOrdersConfirm"))
        A.truthy(Shown(a, "GuildUnionOrders"))
        A.equal("/gremove Jefa", a.env.GuildUnionOrders.cmd:GetText())
    end)

    it("también si lo bloquea como macro («solo la interfaz de Blizzard»)", function()
        local a = F.Community()
        Attrs(a)
        local done
        a.HU:RunOrders({ lines = { "/gdemote Compi" }, onDone = function(n) done = n end })
        Press(a.env.GuildUnionOrdersYes)
        a.w:Fire("MACRO_ACTION_FORBIDDEN", "C_GuildInfo.Demote()")
        a.w:Advance(2)
        A.is_nil(done)
        A.truthy(Shown(a, "GuildUnionOrders"))
        A.equal("/gdemote Compi", a.env.GuildUnionOrders.cmd:GetText())
    end)

    it("con el botón, las respuestas del juego en el chat no pasan órdenes (eso es de copiar y pegar)", function()
        local a = F.Community()
        Attrs(a)
        a.env.ERR_GUILD_REMOVE_SS = "%s ha sido expulsado de la hermandad por %s."
        -- (la ventana de copiar y pegar ya usada antes, y cerrada)
        a.HU:RunOrders({ lines = { "/ginvite Nuevo" } })
        local paste = a.env.GuildUnionOrders
        paste:Hide()
        paste:GetScript("OnHide")(paste)
        local done, each = nil, {}
        a.HU:RunOrders({ lines = { "/gremove Compi", "/gremove Jefa" }, onDone = function(n) done = n end,
            onLine = function(l) each[#each + 1] = l end })
        Press(a.env.GuildUnionOrdersYes)
        a.w:Fire("CHAT_MSG_SYSTEM", "Compi ha sido expulsado de la hermandad por Yo.")
        a.w:Advance(2)
        A.equal("/ginvite Nuevo", paste.cmd:GetText(), "la ventana escondida no se toca (ni coge el teclado)")
        A.falsy(paste:IsShown())
        A.equal(2, done)
        A.same({ "/gremove Compi", "/gremove Jefa" }, each)
        A.same({}, a:Errors())
    end)

    it("lo que bloquea el juego a otro addon no cuenta", function()
        local a = F.Community()
        Attrs(a)
        local done
        a.HU:RunOrders({ lines = { "/gremove Compi" }, onDone = function(n) done = n end })
        Press(a.env.GuildUnionOrdersYes)
        a.w:Fire("ADDON_ACTION_BLOCKED", "OtroAddon", "CastSpellByName()")
        a.w:Advance(2)
        A.equal(1, done)
        A.same({}, a:Errors())
    end)

    it("/ginvite (el juego no la deja en una macro) y lo que no es de hermandad, a copiar y pegar", function()
        for _, line in ipairs({ "/ginvite Nuevo", "/reload" }) do
            local a = F.Community()
            Attrs(a)
            a.HU:RunOrders({ lines = { line } })
            A.falsy(Shown(a, "GuildUnionOrdersConfirm"), line)
            A.truthy(Shown(a, "GuildUnionOrders"), line)
            A.equal(line, a.env.GuildUnionOrders.cmd:GetText())
            A.same({}, a:Errors())
        end
    end)

    it("en combate no se enseña (el botón no se puede preparar): al salir, sí", function()
        local a = F.Community()
        Attrs(a)
        a.w.inCombat = true
        a.HU:RunOrders({ lines = { "/gremove Compi" } })
        A.falsy(Shown(a, "GuildUnionOrdersConfirm"))
        A.falsy(Shown(a, "GuildUnionOrders"))
        a.w.inCombat = false
        a.w:Fire("PLAYER_REGEN_ENABLED")
        A.truthy(Shown(a, "GuildUnionOrdersConfirm"))
        A.equal("/gremove Compi", a.env.GuildUnionOrdersYes:GetAttribute("macrotext"))
        A.same({}, a:Errors())
    end)

    it("si empieza un combate con la ventanita abierta, se esconde sin cancelar y vuelve al salir", function()
        local a = F.Community()
        Attrs(a)
        local done
        a.HU:RunOrders({ lines = { "/gremove Compi" }, onDone = function(n) done = n end })
        local c = a.env.GuildUnionOrdersConfirm
        a.w:Fire("PLAYER_REGEN_DISABLED")
        a.w.inCombat = true
        A.falsy(c:IsShown())
        A.is_nil(done, "no se cancela")
        a.w.inCombat = false
        a.w:Fire("PLAYER_REGEN_ENABLED")
        A.truthy(c:IsShown())
        Press(a.env.GuildUnionOrdersYes)
        a.w:Advance(2)
        A.equal(1, done)
        A.same({}, a:Errors())
    end)

    it("«No» no lanza nada, la da por no hecha y sigue con la que esperaba", function()
        local a = F.Community()
        Attrs(a)
        local first, second
        a.HU:RunOrders({ lines = { "/gremove Compi" }, onDone = function(n) first = n end })
        a.HU:RunOrders({ lines = { "/gdemote Jefa" }, onDone = function(n) second = n end })
        local c = a.env.GuildUnionOrdersConfirm
        local no
        for _, fr in ipairs(a.w.frames) do if fr._parent == c and fr:GetText() == "No" then no = fr end end
        no:GetScript("OnClick")(no)
        A.equal(0, first)
        a.w:Advance(1)
        A.truthy(c:IsShown(), "la siguiente")
        A.equal("/gdemote Jefa", a.env.GuildUnionOrdersYes:GetAttribute("macrotext"))
        Press(a.env.GuildUnionOrdersYes)
        a.w:Advance(2)
        A.equal(1, second)
        A.same({}, a:Errors())
    end)
end)
