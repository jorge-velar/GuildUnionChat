-- Propuestas (WU, Net/Packs.lua): lo de cada uno en los conjuntos que no salen del juego (eventos, comercio, oficios).
-- Cada uno manda lo suyo por GUILD y todos los de su hermandad lo guardan; el enlace lo publica como cualquier paquete
-- y quien se lo perdió estando fuera lo pide al mirar. Aquí, con un conjunto de prueba (ZZ)
local red = require("lib.red")
local F = require("lib.fixtures")
local A = assert_

-- (el conjunto de prueba: datos de letras, cifras y espacios; caduca a los 600 s)
local function Set(p)
    p.HU:RegisterPackSet("ZZ", { chunks = 4, proposals = true, keep = 600,
        validate = function(_, _, d) return d:match("^[%w ]+$") ~= nil end })
    return p
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

-- Lo que ve un jugador del conjunto ZZ: «Nombre:clave:datos <ETIQ>», ordenado
local function Lines(p)
    local out = {}
    for _, e in ipairs(p.HU:Proposals("ZZ")) do out[#out + 1] = e.n:match("^([^-]+)") .. ":" .. e.k .. ":" .. e.d .. " <" .. e.tag .. ">" end
    table.sort(out)
    return out
end

-- UNO: Ana (oficial) y Alba; DOS: Bea (oficial), Blas y Bruno. Todos con el conjunto ZZ
local function Union()
    local net = red.New({ step = 0.5 })
    local p = {
        ana = net:Player("Ana", "UNO", { rankIndex = 1 }),
        alba = net:Player("Alba", "UNO"),
        bea = net:Player("Bea", "DOS", { rankIndex = 1 }),
        blas = net:Player("Blas", "DOS"),
        bruno = net:Player("Bruno", "DOS"),
    }
    for _, n in ipairs({ "ana", "alba", "bea", "blas", "bruno" }) do Set(net:Login(p[n])) end
    net:Advance(150)
    return net, p
end

describe("Propuestas (WU): mi hermandad", function()
    it("lo que propongo queda ya en mi almacén y le llega a mi hermandad por GUILD, con mi nombre", function()
        local net, p = Union()
        A.truthy(p.ana.HU:Propose("ZZ", "uno", "hola desde Ana"))
        A.same({ "Ana:uno:hola desde Ana <UNO>" }, Lines(p.ana), "en mi almacén, sin esperar")
        net:Advance(2)
        A.same({ "Ana:uno:hola desde Ana <UNO>" }, Lines(p.alba))
        A.same({}, Lines(p.bea), "a DOS no le llega por GUILD")
        -- (gana la más nueva y borrar también viaja)
        p.ana.HU:Propose("ZZ", "uno", "cambiado")
        net:Advance(2)
        A.same({ "Ana:uno:cambiado <UNO>" }, Lines(p.alba))
        p.ana.HU:Propose("ZZ", "uno", nil)
        net:Advance(2)
        A.same({}, Lines(p.alba), "borrada")
        A.same({}, net:Errors())
    end)

    it("no se acepta lo que no cuadra: otro conjunto, otra hermandad, por susurro, datos raros o demasiadas seguidas", function()
        local _, p = Union()
        local w, now = p.alba.w, p.alba.HU.StampNow()
        A.falsy(p.ana.HU:Propose("ZZ", "uno", "con|barra"), "datos que no valen: ni se mandan")
        A.falsy(p.ana.HU:Propose("ZZ", "clave con espacios", "x"))
        A.falsy(p.ana.HU:Propose("XX", "uno", "x"), "un conjunto que no existe")
        w:Receive("HU20B", "WU~DOS~ZZ~uno~" .. now .. "~de otra", "GUILD", "Blas-Reino")
        w:Receive("HU20B", "WU~UNO~ZZ~uno~" .. now .. "~por susurro", "WHISPER", "Ana-Reino")
        w:Receive("HU20B", "WU~UNO~ZZ~uno~" .. now .. "~no vale!", "GUILD", "Ana-Reino")
        w:Receive("HU20B", "WU~UNO~ZZ~uno~" .. (now + 3600) .. "~del futuro", "GUILD", "Ana-Reino")
        A.same({}, Lines(p.alba))
        -- (como mucho 5 seguidas de cada uno en cada conjunto, contando las que no valían; luego, 10 por minuto)
        for i = 1, 8 do w:Receive("HU20B", "WU~UNO~ZZ~k" .. i .. "~" .. now .. "~dato " .. i, "GUILD", "Ana-Reino") end
        A.equal(4, #Lines(p.alba), "la de datos raros ya gastó una")
        A.same({}, p.alba.a:Errors())
    end)

    it("se guarda: tras /reload sigue; y lo que caduca se quita", function()
        local net, p = Union()
        p.ana.HU:Propose("ZZ", "uno", "para guardar")
        net:Advance(2)
        net:Logout(p.alba)
        Set(net:Login(p.alba))
        net:Advance(30)
        A.same({ "Ana:uno:para guardar <UNO>" }, Lines(p.alba), "sigue tras /reload")
        net:Advance(620)
        A.same({}, Lines(p.alba), "a los 600 s, caducada")
        A.same({}, net:Errors())
    end)

    it("quien estaba fuera, al mirar, lo pide al equipo del enlace y le llega; lo suyo que el equipo no tenía, lo vuelve a mandar", function()
        local net, p = Union()
        net:Logout(p.alba)
        p.ana.HU:Propose("ZZ", "uno", "mientras no estabas")
        net:Advance(5)
        Set(net:Login(p.alba))
        net:Advance(30)
        A.same({}, Lines(p.alba), "no lo oyó")
        -- (como la ventana: lo pide cada vez que se pinta)
        A.truthy(Until(net, function() p.alba.HU:PackNeed("UNO", "ZZ"); return #Lines(p.alba) == 1 end, 240), "no le llega")
        A.same({ "Ana:uno:mientras no estabas <UNO>" }, Lines(p.alba))
        A.same({}, net:Errors())
    end)

    it("un trozo de mi hermandad solo vale del equipo del enlace: nadie mete líneas de otro", function()
        local net, p = Union()
        p.alba.HU:PackNeed("UNO", "ZZ")
        net:Advance(20)
        -- (Blas no es de UNO; Alba tampoco es del equipo: lo que mandan por GUILD como trozo no entra)
        local line = "Ana-Reino,uno," .. p.alba.HU.B36(p.alba.HU.StampNow()) .. ",falsa"
        p.alba.w:Receive("HU20B", "WT~UNO~ZZ~1~1~1~" .. line, "GUILD", "Blas-Reino")
        A.same({}, Lines(p.alba))
        A.same({}, net:Errors())
    end)
end)

describe("Propuestas (WU): que no se pierda nada", function()
    -- (los WU que ha mandado alguien desde i0)
    local function WUs(net, who, i0)
        local n = 0
        for i = (i0 or 0) + 1, #net.log do
            local m = net.log[i]
            if m.text:match("^WU~") and m.from.name == who then n = n + 1 end
        end
        return n
    end

    it("lo de mi hermandad, también con HU:PackLines (del almacén, sin lo borrado)", function()
        local net, p = Union()
        p.ana.HU:Propose("ZZ", "uno", "hola")
        p.ana.HU:Propose("ZZ", "dos", "adios")
        p.ana.HU:Propose("ZZ", "dos", "")
        net:Advance(2)
        local lines, complete = p.alba.HU:PackLines("UNO", "ZZ")
        A.equal(1, #lines)
        A.truthy(lines[1]:match("^Ana%-Reino,uno,%w+,hola$"), lines[1])
        A.truthy(complete)
        A.same({}, net:Errors())
    end)

    it("cuando cambia el enlace, cada uno vuelve a mandar lo suyo (una vez), por si el nuevo no lo tenía", function()
        local net, p = Union()
        p.ana.HU:Propose("ZZ", "uno", "lo mio")
        net:Advance(2)
        local i0 = #net.log
        F.Stub(p.ana.HU, "RelayName", "Alba-Reino")
        net:Advance(80)
        A.equal(1, WUs(net, "Ana", i0), "otra vez, una sola")
        A.same({}, net:Errors())
    end)

    it("si el equipo no tiene lo mío (su trozo vacío), lo vuelvo a mandar", function()
        local net, p = Union()
        p.alba.HU:Propose("ZZ", "dos", "de Alba")
        net:Advance(2)
        p.alba.HU:PackNeed("UNO", "ZZ")
        net:Advance(10)
        local i0 = #net.log
        local empty = p.alba.HU.PackHash({})
        p.alba.w:Receive("HU20B", "WM~UNO~ZZ~4~" .. table.concat({ empty, empty, empty, empty }, ","), "GUILD", "Ana-Reino")
        net:Advance(2)
        A.equal(1, WUs(net, "Alba", i0), "lo suyo, otra vez")
        A.same({}, net:Errors())
    end)

    it("lo caducado sale del almacén (al entrar y cada hora)", function()
        local net, p = Union()
        p.ana.HU:Propose("ZZ", "uno", "pronto viejo")
        net:Advance(2)
        A.truthy(next(p.alba.HU.db.wuStore.UNO.ZZ))
        net:Advance(620)
        -- (en el addon los conjuntos se declaran al cargar; aquí, después de entrar: la limpieza, a mano)
        p.alba.HU.PackCleanStores()
        A.falsy(next(p.alba.HU.db.wuStore.UNO.ZZ), "fuera")
        A.same({}, net:Errors())
    end)
end)

describe("Propuestas (WU): las otras hermandades", function()
    it("el enlace lo publica con el paquete: DOS lo ve al mirarlo, y también cuando se borra", function()
        local net, p = Union()
        p.ana.HU:Propose("ZZ", "uno", "para la union")
        p.alba.HU:Propose("ZZ", "dos", "de Alba")
        net:Advance(2)
        p.bea.HU:PackNeed("UNO", "ZZ")
        A.truthy(Until(net, function() return #Lines(p.bea) == 2 end, 300), "no llega a DOS")
        A.same({ "Alba:dos:de Alba <UNO>", "Ana:uno:para la union <UNO>" }, Lines(p.bea))
        -- (Blas, de DOS, lo tiene sin pedirlo: el porteador lo reparte por GUILD)
        A.equal(2, #Lines(p.blas))
        -- (Ana lo borra: tras el siguiente anuncio, en DOS ya no está)
        p.ana.HU:Propose("ZZ", "uno", "")
        A.truthy(Until(net, function() p.bea.HU:PackNeed("UNO", "ZZ"); return #Lines(p.bea) == 1 end, 400), "no se borra en DOS")
        A.same({ "Alba:dos:de Alba <UNO>" }, Lines(p.bea))
        A.same({}, net:Errors())
    end)
end)

describe("Propuestas (WU): sin red", function()
    it("un conjunto de propuestas necesita validate", function()
        local HU = F.Community().HU
        A.falsy(pcall(HU.RegisterPackSet, HU, "YY", { chunks = 4, proposals = true }))
        A.truthy(pcall(HU.RegisterPackSet, HU, "YY", { chunks = 4, proposals = true, validate = function() return true end }))
    end)
end)
