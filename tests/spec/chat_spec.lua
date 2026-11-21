-- El chat entre hermandades por dentro (Channel.lua, History.lua): emoticonos, qué líneas se enseñan
-- y el historial que se rellena con lo que traen otros. Pruebas de caracterización: fijan lo de hoy.
local F = require("lib.fixtures")
local A = assert_

local a, HU
local function Fresh()
    a = F.Community()
    HU = a.HU
end

-- Las líneas del historial de un autor: { "texto", ... }
local function HistoryOf(author)
    local out = {}
    for _, e in ipairs(HU.db.history or {}) do
        if e.a and e.a:lower() == author:lower() then out[#out + 1] = e.m end
    end
    return out
end

describe("Chat: emoticonos", function()
    before_each(Fresh)

    it("«:-)» al principio o tras un espacio pasa a su icono", function()
        local out = HU:Emotes(":-) hola")
        A.truthy(out:find("|T", 1, true), "sin icono: " .. out)
        A.truthy(out:find("hola", 1, true), "se pierde el texto: " .. out)
    end)

    it("pegado a una palabra no es un emoticono", function()
        A.equal("hola:-)x", HU:Emotes("hola:-)x"))
    end)

    it("sin emoticonos, el texto sale igual", function()
        A.equal("hola, ¿qué tal?", HU:Emotes("hola, ¿qué tal?"))
    end)
end)

describe("Chat: qué líneas de otras hermandades se enseñan", function()
    before_each(Fresh)

    it("una línea normal de DOS se enseña y se guarda", function()
        A.truthy(HU:OnUnionChat("main", "[DOS] hola", "Bea-Reino"))
        A.same({ "hola" }, HistoryOf("Bea-Reino"))
    end)

    it("«[ETIQ:B]» (Buscar grupo de una versión vieja) no se enseña", function()
        A.falsy(HU:OnUnionChat("main", "[DOS:B] busco grupo", "Bea-Reino"))
        A.same({}, HistoryOf("Bea-Reino"))
    end)

    it("«[ETIQ:O]» (oficiales por el canal principal) solo vale en el modo prueba, que ya no existe", function()
        A.falsy(HU:OnUnionChat("main", "[DOS:O] solo oficiales", "Bea-Reino"))
        A.same({}, HistoryOf("Bea-Reino"))
    end)

    it("una línea de mi propia hermandad no se repite (ya está en /g)", function()
        A.falsy(HU:OnUnionChat("main", "[UNO] hola", "Compi-Reino"))
        A.same({}, HistoryOf("Compi-Reino"))
    end)

    it("en un canal extra se enseña también lo de mi hermandad", function()
        A.truthy(HU:OnUnionChat("x:Raid", "[UNO] hola", "Compi-Reino"))
        A.same({ "hola" }, HistoryOf("Compi-Reino"))
    end)
end)

describe("Chat: historial rellenado por otros (HistInsert)", function()
    before_each(Fresh)

    it("mete la línea una vez y no la repite", function()
        local e = { a = "Bea-Reino", m = "hola desde DOS", t = HU.StampNow() - 60, k = "main", g = "DOS" }
        A.truthy(HU:HistInsert(e), "la primera vez entra")
        A.falsy(HU:HistInsert(e), "la segunda, no")
    end)

    it("dos autores el mismo día tienen cada uno su línea", function()
        local t = HU.StampNow() - 120
        A.truthy(HU:HistInsert({ a = "Bea-Reino", m = "uno", t = t, k = "main", g = "DOS" }))
        A.truthy(HU:HistInsert({ a = "Blas-Reino", m = "dos", t = t + 1, k = "main", g = "DOS" }))
    end)

    it("no mete lo de oficiales ni lo de fuera de plazo", function()
        A.falsy(HU:HistInsert({ a = "Bea-Reino", m = "x", t = HU.StampNow() - 60, k = "off", g = "DOS" }), "oficiales")
        A.falsy(HU:HistInsert({ a = "Bea-Reino", m = "x", t = HU.StampNow() + 3600, k = "main", g = "DOS" }), "del futuro")
        A.falsy(HU:HistInsert({ a = "Bea-Reino", m = "x", t = HU.StampNow() - 400 * 86400, k = "main", g = "DOS" }), "muy viejo")
    end)
end)

describe("Chat: lo que un compañero no puede mandar por el canal (CF)", function()
    before_each(function()
        Fresh()
        F.Stub(HU, "HandlesTag", true)
        F.Stub(HU, "BestPeers", { { name = "Bea-Reino" } })
        a.w:TakeSent()
    end)
    local function ToBea()
        local out = {}
        for _, s in ipairs(a.w:TakeSent()) do if s.target == "Bea-Reino" then out[#out + 1] = s.text end end
        return out
    end

    it("lo reparto a la otra hermandad por susurro, con el compañero de autor", function()
        a.w:Receive("HU20", "CF~m~[UNO] hola~que tal", "GUILD", "Compi-Reino")
        A.same({ "CW~m~Compi-Reino~[UNO] hola~que tal" }, ToBea())
    end)

    it("no reparto lo de oficiales, lo de otra hermandad ni lo de quien no es de la mía", function()
        a.w:Receive("HU20", "CF~o~[UNO] secreto", "GUILD", "Compi-Reino")
        a.w:Receive("HU20", "CF~m~[DOS] hola", "GUILD", "Compi-Reino")
        a.w:Receive("HU20", "CF~m~[UNO] hola", "GUILD", "Extraño-Reino")
        a.w:Receive("HU20", "CF~m~[UNO] hola", "WHISPER", "Compi-Reino")
        A.same({}, ToBea())
    end)
end)
