-- La tabla del protocolo (docs/protocolo.md) está al día con el registro de órdenes (HU.msgs) y cada
-- orden tiene su descripción en tests/lib/protocolo.lua. Si cambia a propósito, se rehace con
--   lua tests/run.lua Protocolo --actualizar
local runner = require("lib.runner")
local F = require("lib.fixtures")
local modulos = require("lib.modulos")
local protocolo = require("lib.protocolo")
local A = assert_

local ROOT = runner.here .. "/.."
local DOC = ROOT .. "/docs/protocolo.md"

local function Read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return (s:gsub("\r\n", "\n"))
end

describe("Protocolo: la tabla de docs/protocolo.md", function()
    local HU, files, src
    before_each(function()
        HU = F.Community().HU
        local list, _, texts = modulos.Compute(ROOT)
        files, src = list, texts
    end)

    it("cada orden registrada tiene descripción, y no sobra ninguna", function()
        local missing, extra = {}, {}
        for cmd in pairs(HU.msgs) do if not protocolo.DESC[cmd] then missing[#missing + 1] = cmd end end
        for cmd in pairs(protocolo.DESC) do if not HU.msgs[cmd] then extra[#extra + 1] = cmd end end
        table.sort(missing); table.sort(extra)
        A.same({}, missing, "órdenes sin descripción en tests/lib/protocolo.lua")
        A.same({}, extra, "descripciones de órdenes que ya no están registradas")
    end)

    it("se sabe en qué archivo se registra cada orden", function()
        local at = protocolo.Sources(files, function(f) return src[f] end)
        for cmd in pairs(HU.msgs) do A.truthy(at[cmd], cmd .. " sin archivo") end
    end)

    it("docs/protocolo.md es lo que sale del registro", function()
        local at = protocolo.Sources(files, function(f) return src[f] end)
        local now = protocolo.Render(HU.msgs, at)
        if runner.update then
            local f = assert(io.open(DOC, "wb"))
            f:write(now); f:close()
            return
        end
        A.equal(now, Read(DOC), "docs/protocolo.md no está al día: lua tests/run.lua Protocolo --actualizar")
    end)
end)
