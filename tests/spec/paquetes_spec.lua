-- Paquetes con huella (Net/Packs.lua) y la lista completa de miembros (Packs/Members.lua): se anuncian
-- solos, los trozos se piden al mirarlos, los trae un porteador por hermandad y los cambios pequeños viajan
-- como diferencias. La huella es la versión: sin números que inflar
local red = require("lib.red")
local F = require("lib.fixtures")
local A = assert_

local function Names(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = (e.name:match("^([^-]+)")) end
    table.sort(out)
    return out
end

-- Avanza de 5 en 5 s hasta que se cumpla; devuelve los segundos o nil
local function Until(net, cond, max)
    local t = 0
    while t < max do
        if cond() then return t end
        net:Advance(5)
        t = t + 5
    end
    return cond() and t or nil
end

-- Los mensajes que empiezan por `cmd` desde el índice i0 del registro de la red (y que cumplen `ok`)
local function Sent(net, cmd, i0, ok)
    local out = {}
    for i = (i0 or 0) + 1, #net.log do
        local m = net.log[i]
        if m.text:sub(1, #cmd + 1) == cmd .. "~" and (not ok or ok(m)) then out[#out + 1] = m end
    end
    return out
end

-- UNO: Ana (oficial) y Alba; DOS: Bea (oficial), Blas y Bruno conectados, Beto y Berta no.
-- Con `tres`, también TRES: Tere (oficial) y Toni conectados, Tito no
local function Union(tres, step)
    local opts = { step = step or 0.5 }
    if tres then
        opts.info = table.concat({ F.INFO, "GU:g:Hermandad Tres:TRES" }, "\n")
        opts.guilds = { UNO = "Hermandad Uno", DOS = "Hermandad Dos", TRES = "Hermandad Tres" }
    end
    local net = red.New(opts)
    local p = {
        ana = net:Player("Ana", "UNO", { rankIndex = 1 }),
        alba = net:Player("Alba", "UNO"),
        bea = net:Player("Bea", "DOS", { rankIndex = 1 }),
        blas = net:Player("Blas", "DOS"),
        bruno = net:Player("Bruno", "DOS"),
        beto = net:Player("Beto", "DOS"),
        berta = net:Player("Berta", "DOS"),
    }
    local on = { "ana", "alba", "bea", "blas", "bruno" }
    if tres then
        p.tere = net:Player("Tere", "TRES", { rankIndex = 1 })
        p.toni = net:Player("Toni", "TRES")
        p.tito = net:Player("Tito", "TRES")
        on[#on + 1], on[#on + 2] = "tere", "toni"
    end
    for _, n in ipairs(on) do net:Login(p[n]) end
    net:Advance(150)
    return net, p
end

-- Un paquete MB ya comprobado (para las pruebas sin red): las líneas, en sus trozos
local function Pack(HU, lines)
    local t, h, ok = {}, {}, {}
    for i = 1, 16 do t[i] = {} end
    for _, l in ipairs(lines) do
        local c = t[HU.PackChunkOf(l:match("^([^,]+)"), 16)]
        c[#c + 1] = l
    end
    for i = 1, 16 do table.sort(t[i]); h[i] = HU.PackHash(t[i]); ok[i] = h[i] end
    return { h = h, t = t, ok = ok }
end

describe("Paquetes: la huella", function()
    it("el orden de las líneas no cuenta y una letra cambiada sí", function()
        local a = F.Community()
        local HU = a.HU
        local h1 = HU.PackHash({ "Ana-R,1,10,2", "Blas-R,3,20,4" })
        A.equal(h1, HU.PackHash({ "Blas-R,3,20,4", "Ana-R,1,10,2" }))
        A.truthy(h1 ~= HU.PackHash({ "Ana-R,1,10,2", "Blas-R,3,21,4" }), "nivel cambiado, otra huella")
        A.equal(12, #h1, "12 letras")
        A.falsy(h1:find("[^0-9a-z]"), "solo cifras y letras")
    end)

    it("cada nombre cae siempre en el mismo trozo, sin importar mayúsculas, y llenan todos", function()
        local a = F.Community()
        local HU = a.HU
        local c = HU.PackChunkOf("Ana-Reino", 16)
        A.truthy(c >= 1 and c <= 16)
        A.equal(c, HU.PackChunkOf("ana-reino", 16))
        local used, n = {}, 0
        for i = 1, 400 do used[HU.PackChunkOf("Jugador" .. i .. "-Reino", 16)] = true end
        for _ in pairs(used) do n = n + 1 end
        A.equal(16, n)
    end)
end)

describe("Paquetes: la lista completa de miembros (MB)", function()
    it("el enlace de DOS anuncia su lista solo y nadie trae trozos hasta que alguien mira", function()
        local net, p = Union()
        local mb = p.alba.HU:PackGet("DOS", "MB")
        A.truthy(mb and #mb.h == 16, "el anuncio de DOS ha llegado a UNO")
        -- (los trozos vacíos ya valen con la huella: los que tienen a alguien, todavía no)
        local got, total = p.alba.HU:PackProgress("DOS", "MB")
        A.truthy(got < total, "faltan los trozos con gente")
        A.equal(0, #p.alba.HU:PackedMembers("DOS"), "nadie todavía")
        A.equal(0, #Sent(net, "WT"), "ningún trozo sin que nadie mire")
        A.same({}, net:Errors())
    end)

    it("al mirarla llega completa, con los desconectados, una sola copia por trozo y para toda UNO", function()
        local net, p = Union()
        local i0 = #net.log
        p.alba.HU:PackNeed("DOS", "MB")
        A.truthy(Until(net, function() return #p.alba.HU:PackedMembers("DOS") == 5 end, 120), "no ha llegado la lista")
        A.same({ "Bea", "Berta", "Beto", "Blas", "Bruno" }, Names(p.alba.HU:PackedMembers("DOS")))
        -- (Ana no ha pedido nada: le ha llegado por GUILD lo que trajo el porteador)
        A.equal(5, #p.ana.HU:PackedMembers("DOS"), "y a Ana, sin pedirla")
        A.equal(0, #Sent(net, "WP", i0, function(m) return m.from.name:match("^Ana") and m.dist == "GUILD" end), "Ana no ha pedido")
        -- (a DOS se le pide una sola vez, por susurro, quien hace de porteador)
        A.equal(1, #Sent(net, "WP", i0, function(m) return m.dist == "WHISPER" end), "un solo porteador")
        -- (cada parte de cada trozo, una sola vez por GUILD dentro de UNO)
        local seen = {}
        for _, m in ipairs(Sent(net, "WT", i0, function(m) return m.dist == "GUILD" and m.from.tag == "UNO" end)) do
            local k = m.text:match("^WT~DOS~MB~(%d+~%d+)")
            A.falsy(seen[k], "parte repetida " .. tostring(k))
            seen[k] = true
        end
        A.same({}, net:Errors())
    end)

    it("un alta en DOS llega como diferencia: sin trozos enteros", function()
        local net, p = Union()
        p.alba.HU:PackNeed("DOS", "MB")
        A.truthy(Until(net, function() return #p.alba.HU:PackedMembers("DOS") == 5 end, 120))
        local i0 = #net.log
        net:Login(net:Player("Bego", "DOS"))
        A.truthy(Until(net, function() return #p.alba.HU:PackedMembers("DOS") == 6 end, 240), "no llega el alta")
        A.equal(0, #Sent(net, "WT", i0, function(m) return m.text:match("^WT~DOS~") end), "sin trozos enteros")
        A.truthy(#Sent(net, "WD", i0) > 0, "por diferencia")
        A.equal(6, #p.ana.HU:PackedMembers("DOS"), "también a Ana")
        A.same({}, net:Errors())
    end)

    it("un anuncio de alguien de fuera no cuenta", function()
        local net, p = Union()
        local real = table.concat(p.alba.HU:PackGet("DOS", "MB").h, ",")
        local fake = {}
        for i = 1, 16 do fake[i] = "000000000000" end
        p.alba.w:Receive("HU20B", "WM~DOS~MB~16~" .. table.concat(fake, ","), "WHISPER", "Extra-Reino")
        A.equal(real, table.concat(p.alba.HU:PackGet("DOS", "MB").h, ","))
        A.same({}, net:Errors())
    end)

    it("un anuncio falso de dentro solo dura hasta el siguiente repaso del enlace de DOS", function()
        local net, p = Union(false, 1)
        local real = table.concat(p.alba.HU:PackGet("DOS", "MB").h, ",")
        local fake = {}
        for i = 1, 16 do fake[i] = "000000000000" end
        -- (Ana es oficial de UNO: lo que reparte por GUILD se acepta)
        p.ana.HU:Send("WM~DOS~MB~16~" .. table.concat(fake, ","), "GUILD")
        net:Advance(2)
        A.equal(table.concat(fake, ","), table.concat(p.alba.HU:PackGet("DOS", "MB").h, ","), "entra")
        A.truthy(Until(net, function() return table.concat(p.alba.HU:PackGet("DOS", "MB").h, ",") == real end, 700),
            "el repaso del enlace de DOS lo arregla")
        A.same({}, net:Errors())
    end)

    it("un trozo que no cuadra con su huella se tira", function()
        local net, p = Union()
        local HU = p.alba.HU
        local bad0 = HU.PackBadCount()
        -- (un trozo con gente: el vacío ya vale con su huella)
        local mb, i = HU:PackGet("DOS", "MB"), nil
        for k = 1, 16 do if mb.h[k] ~= HU.PackHash({}) then i = k break end end
        p.alba.w:Receive("HU20B", "WT~DOS~MB~" .. i .. "~1~1~Intruso-Reino,1,60,0", "GUILD", "Ana-Reino")
        A.equal(0, #HU:PackedMembers("DOS"), "no entra")
        A.equal(bad0 + 1, HU.PackBadCount())
        A.same({}, net:Errors())
    end)

    it("en una entrada masiva no se pide nada hasta que se calma", function()
        local net, p = Union()
        local HU = p.alba.HU
        local quiet = false
        F.Stub(HU, "QuietLogins", function() return quiet end)
        local i0 = #net.log
        HU:PackNeed("DOS", "MB")
        net:Advance(40)
        A.equal(0, #Sent(net, "WP", i0), "nada mientras entra tanta gente")
        quiet = true
        A.truthy(Until(net, function() return #HU:PackedMembers("DOS") == 5 end, 120), "y luego llega")
        A.same({}, net:Errors())
    end)

    it("con tres hermandades, UNO ve completas a DOS y a TRES", function()
        local net, p = Union(true)
        p.alba.HU:PackNeed("DOS", "MB")
        p.alba.HU:PackNeed("TRES", "MB")
        A.truthy(Until(net, function()
            return #p.alba.HU:PackedMembers("DOS") == 5 and #p.alba.HU:PackedMembers("TRES") == 3
        end, 180), "no llegan las dos")
        A.same({ "Tere", "Tito", "Toni" }, Names(p.ana.HU:PackedMembers("TRES")))
        A.same({}, net:Errors())
    end)
end)

describe("Paquetes: Members con desconectados de otras hermandades", function()
    -- (la ventana de hermandad del juego, lo justo, con «Mostrar desconectados» marcada)
    local function GuildWindow(a)
        local f = a.env.CreateFrame("Frame", "CommunitiesFrame")
        f.GuildInfoTab, f.CommunitiesControlFrame, f.Chat = false, false, false
        f.CommunitiesList = a.env.CreateFrame("Frame", nil, f)
        f.MemberList = a.env.CreateFrame("Frame", nil, f)
        f.MemberList.IsVisible = function() return true end
        local chk = a.env.CreateFrame("CheckButton", nil, f.MemberList)
        f.MemberList.ShowOfflineButton = chk
        chk.IsVisible = function() return true end
        chk.GetChecked = function() return true end
        a.w:Fire("ADDON_LOADED", "Blizzard_Communities")
        return f
    end

    it("salen con «?» si no se sabe si están conectados; con la lista de conectados al día, desconectados", function()
        local a = F.Community()
        local HU = a.HU
        HU.db.packs = { DOS = { MB = Pack(HU, { "Bea-Reino,8,60,1", "Beto-Reino,1,40,4" }) } }
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        local function Row(name)
            for _, r in ipairs(cover.rows) do
                if r:IsShown() and (r.cells.name:GetText() or ""):find(name, 1, true) then return r end
            end
        end
        local beto = Row("Beto")
        A.truthy(beto, "Beto, de DOS, sale")
        A.matches("%?", beto.cells.zone:GetText(), "no se sabe si está")
        A.matches("DOS", beto.cells.guild:GetText())
        -- (llega la lista de conectados de DOS: Bea está; Beto no, así que está desconectado)
        HU.unionMembers.DOS = { members = { { name = "Bea-Reino", tag = "DOS", online = true, level = 60, ri = 1 } }, t = a.env.GetTime() }
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        A.falsy(Row("Beto").cells.zone:GetText():find("?", 1, true), "desconectado")
        A.same({}, a:Errors())
    end)

    it("mientras llega, abajo dice cuánto falta de la lista completa", function()
        local a = F.Community()
        local HU = a.HU
        local pk = Pack(HU, { "Bea-Reino,8,60,1" })
        pk.t, pk.ok = {}, {}
        HU.db.packs = { DOS = { MB = pk } }
        GuildWindow(a)
        local cover = a.env.GuildUnionUnionRoster
        cover:GetScript("OnEvent")(cover, "GUILD_ROSTER_UPDATE")
        A.matches("0/16", cover.status:GetText())
        A.same({}, a:Errors())
    end)
end)
