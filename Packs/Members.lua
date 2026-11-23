-- Guild Union - Paquete MB: la lista completa de miembros de cada hermandad (también los desconectados) [+ARCHITECTURE.md]
-- Una línea por miembro: «Nombre-Reino,clase,nivel,rango» (clase en número, HU.CLASS_INDEX). Estar
-- conectado y la zona no van aquí: cambian cada minuto y llegan con RB/RC y Miembros (UnionMembers.lua)
local _, HU = ...

HU:RegisterPackSet("MB", {
    chunks = 16,
    key = function(e) return e.name end,
    encode = function(e)
        if not (e.name and HU.SafeName(e.name)) then return nil end
        return string.format("%s,%d,%d,%d", e.name, HU.CLASS_INDEX[e.class] or 0, tonumber(e.level) or 0, tonumber(e.rankIndex) or 99)
    end,
    -- (lo que tengo yo: la lista de mi hermandad del juego, en cuanto se ha leído)
    source = function()
        local list = HU.rosterList
        if not list or #list == 0 then return nil end
        return list
    end,
    onChange = function() HU:Changed("unionMembers") end,
})

-- Los miembros de una hermandad según su paquete (solo los trozos ya comprobados)
function HU:PackedMembers(tag)
    local out = {}
    for _, l in ipairs((self:PackLines(tag, "MB"))) do
        local name, cls, lvl, rank = l:match("^([^,]+),(%d+),(%d+),(%d+)$")
        if name and HU.SafeName(name) then
            out[#out + 1] = { name = name, tag = tag, class = HU.CLASSES[tonumber(cls)], level = tonumber(lvl) or 0,
                rankIndex = tonumber(rank) }
        end
    end
    return out
end

HU:Module("Packs/Members", { "Core", "Net/Packs" })
