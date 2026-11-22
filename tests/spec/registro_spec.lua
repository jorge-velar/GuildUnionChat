-- Registro de órdenes (Protocol.lua, HU:RegisterMessage): lo declarado da EXACTAMENTE las tablas que
-- había antes en Comm.lua y Combat.lua (copiadas aquí de la 5.4.41), y el registro rechaza errores.
local F = require("lib.fixtures")
local addon = require("lib.addon")
local A = assert_

-- Las tablas de la 5.4.41 (paso 1), tal cual
local OLD = {
    tagField = { HI = 2, HR = 2, RB = 1, RC = 1, RN = 1, PB = 1, OD = 1, OE = 1, RF = 1, RA = 1 },
    bootstrap = { HI = true, HR = true, RB = true, RC = true, RN = true, RF = true, RA = true },
    open = { GV = true, GA = true, GL = true, CK = true },
    channel = { RA = true, LP = true },
    remoteData = { RB = true, RC = true, RN = true, PB = true, OD = true, OE = true },
    queue = { RC = "bfast", RB = "bulk", PB = "bmid", OD = "blow", HL = "blow",
        MU = "chat", MZ = "chat", BN = "chat", CX = "chat", CP = "chat", CQ = "chat", PN = "chat", GK = "chat",
        CW = "chat", CG = "chat", CF = "chat", OE = "mid", MQ = "mid", EM = "mid" },
    ttl = { HI = 60, HR = 60, HY = 60, RA = 60, LP = 60, PL = 60, PH = 60, LN = 60, LV = 60, LO = 60,
        RC = 300, RB = 600, PB = 900, OD = 900, HL = 900,
        CX = 600, CP = 600, CQ = 600, PN = 600, GK = 600, CW = 60, CG = 20, CF = 60,
        MU = false, MZ = false, BN = false },
    latestWins = { HI = true, HR = true, HY = true, RA = true, LN = true },
    skipLocked = { HI = true, HR = true, HY = true, RA = true, LP = true, PL = true, PH = true, LN = true },
    combat = { RB = "list", RF = "req", NQ = "req", HQ = "req", OQ = "req",
        HL = "data", PB = "data", OD = "data", OE = "data", PH = "last", PL = "last" },
}
local BULK_PREFIX = { RB = true, RC = true, PB = true, OD = true, HL = true }
local OLD_COUNT = 63

-- Órdenes nuevas desde la 5.4.41, con sus marcas (las de antes no cambian: la tabla OLD sigue igual)
local NEW = {
    -- (Miembros de la unión, UnionMembers.lua)
    MP = { open = true, combat = "req" },
    ML = { tagField = 1, remoteData = true, open = true, queue = "bmid", ttl = 120, combat = "data" },
}
for cmd, marks in pairs(NEW) do
    for key, v in pairs(marks) do
        OLD[key] = OLD[key] or {}
        OLD[key][cmd] = v
    end
    if marks.queue and marks.queue:sub(1, 1) == "b" then BULK_PREFIX[cmd] = true end
end
local COUNT = OLD_COUNT
for _ in pairs(NEW) do COUNT = COUNT + 1 end

local function Sorted(t) local l = {} for k in pairs(t) do l[#l + 1] = k end table.sort(l) return l end

describe("Registro de órdenes", function()
    local a, HU
    before_each(function()
        a = F.Community()
        HU = a.HU
    end)

    it("cada marca declarada coincide con la tabla de antes", function()
        for key, old in pairs(OLD) do
            local got = {}
            for cmd, spec in pairs(HU.msgs) do
                if spec[key] ~= nil then got[cmd] = spec[key] end
            end
            A.same(old, got, key)
        end
    end)

    it("el prefijo de cada orden es el de antes (HU20B para los datos grandes)", function()
        for cmd in pairs(HU.msgs) do
            A.equal(BULK_PREFIX[cmd] and "HU20B" or "HU20", HU:MessagePrefix(cmd), cmd)
        end
        A.equal("HU20", HU:MessagePrefix("QZ")) -- (sin registrar)
    end)

    it("toda orden con manejador está registrada, y al revés", function()
        A.same(Sorted(HU.comm), Sorted(HU.msgs))
        A.equal(COUNT, #Sorted(HU.msgs))
    end)

    it("rechaza nombres, claves y valores que no valen", function()
        local function Fails(cmd, spec, what)
            local ok, err = pcall(HU.RegisterMessage, HU, cmd, spec)
            A.falsy(ok, "debía fallar: " .. what)
            A.truthy(tostring(err):find(what, 1, true), "error: " .. tostring(err))
        end
        Fails("Q9", nil, "orden no válida")
        Fails("abc", nil, "orden no válida")
        Fails("CW", nil, "ya registrada")
        Fails("QA", { tagfield = 1 }, "clave desconocida")
        Fails("QB", { ttl = "60" }, "ttl tiene que ser number")
        Fails("QC", { queue = "rapida" }, "cola desconocida")
        Fails("QD", { combat = "luego" }, "combate desconocido")
        Fails("QE", { bootstrap = true }, "necesitan tagField")
        Fails("QF", { fields = { "a*", "b" } }, "tiene que ser el último")
        Fails("QG", { fields = { "a", "a" } }, "campo repetido")
        Fails("QH", { fields = { "1a" } }, "nombre de campo no válido")
        A.falsy(HU.msgs.QA)
    end)

    it("los campos con nombre leen la posición; el de * es el resto, con sus ~", function()
        local seen
        HU:RegisterMessage("QZ", { fields = { "chan", "author", "line*" }, handler = function(_, _, f) seen = f end })
        a.w:Receive("HU20", "QZ~m~Ana-Reino~[DOS] hola~que tal", "GUILD", "Compi-Reino")
        A.equal("m", seen.chan)
        A.equal("Ana-Reino", seen.author)
        A.equal("[DOS] hola~que tal", seen.line)
        A.equal("m", seen[1]) -- (por posición, como siempre)
        A.equal(nil, seen.otro)
    end)

    it("/gu diag lista las órdenes desde el registro (y marca con ? las desconocidas)", function()
        a.w:Receive("HU20", "PR~x", "GUILD", "Compi-Reino")
        a.w:Receive("HU20", "QZ~x", "GUILD", "Compi-Reino")
        local rec, none
        for _, l in ipairs(HU:DiagLines()) do
            rec = rec or l:match("^recibido: (.*)$")
            none = none or l:match("^sin recibir %(de " .. COUNT .. " órdenes%): (.*)$")
        end
        A.truthy(rec and rec:find("PR=1", 1, true) and rec:find("QZ?=1", 1, true), "recibido: " .. tostring(rec))
        A.truthy(none and none:find("CW", 1, true) and not none:find("PR", 1, true), "sin recibir: " .. tostring(none))
    end)

    it("Protocol.lua va justo detrás de Core.lua en el .toc (los demás registran al cargarse)", function()
        local files = addon.LuaFiles()
        local core
        for i, fn in ipairs(files) do if fn == "Core.lua" then core = i end end
        A.equal("Protocol.lua", files[core + 1])
    end)
end)
