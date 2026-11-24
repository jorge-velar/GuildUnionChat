-- La tabla del protocolo (docs/protocolo.md), sacada del registro de órdenes (HU.msgs, Protocol.lua).
-- Lo que no está en el registro es la descripción: va aquí, una por orden, y protocolo_spec exige que
-- no falte ninguna. Se rehace con:  lua tests/run.lua Protocolo --actualizar
local M = {}

-- Qué es cada orden: el formato (campos separados por ~) y para qué sirve
M.DESC = {
    AU = "`AU~id~hora~etiq~autor~texto`: una entrada del registro compartido",
    BN = "`BN~nombre~1|0~autor~etiq~t`: veto (1) o readmisión (0)",
    CF = "`CF~canal~[ETIQ] mensaje`: chat de un compañero cuyo texto no sale por el canal (por GUILD)",
    CG = "`CG~canal~autor~[ETIQ] mensaje`: chat que un compañero recibió por susurro y reparte por GUILD",
    CK = "el canal pasado a mano (`/gu pasarcanal`): solo vale de provisional",
    CP = "`CP~canal~clave~t~autor~etiq`: el canal de la comunidad, repartido por un oficial (gana el más nuevo)",
    CQ = "al entrar, pide el canal (contesta el primero que lo tenga)",
    CW = "`CW~canal~autor~[ETIQ] mensaje`: chat por susurro, del autor o de un compañero suyo que lo reparte",
    CX = "`CX~nombre~clave~borrado~autor~etiq~t`: crear o quitar un canal extra",
    EM = "`EM~código~ruta~autor~etiqAutor~t`: emoticono propio (ruta vacía = borrado)",
    EQ = "`EQ~id~quién~firma`: pide los errores guardados",
    ER = "`ER~id~remitente~versión~dónde~error`: un error guardado",
    GA = "`GA~id~1|0~nombre o motivo`: respuesta a una invitación a la comunidad",
    GC = "`GC~ETIQ~rrggbb~autor~etiqAutor~t`: color de una hermandad (vacío = el de siempre)",
    GD = "`GD~id`: petición de echar ya atendida",
    GK = "`GK~id~tag~objetivo~solicitante~etiqSol`: pide echar a alguien de otra hermandad",
    GL = "`GL~id~parte~partes~datos`: la configuración de la comunidad, tras aceptar la invitación",
    GP = "`GP~id~tag~objetivo~rango~solicitante~etiqSol`: pide cambiar el rango a alguien de otra hermandad",
    GR = "`GR~id~ok|no~quién~objetivo~motivo`: respuesta a quien pidió echar",
    GV = "`GV~id~ETIQ~título~hermandad`: invitación a la comunidad (al contacto de la hermandad nueva)",
    HI = "`HI~ver~etiq~mod~enlace…`: saludo (por GUILD a la hermandad, o por susurro a otra)",
    HL = "`HL~t~tipo~etiq~autor~mensaje`: una línea del historial",
    HQ = "`HQ~desde~oficial`: al entrar, pide lo escrito mientras no estabas",
    HR = "respuesta a un saludo, con los mismos campos (no provoca más saludos)",
    HY = "el enlace nuevo pide a su hermandad que salude (cada uno contesta con `HR`)",
    KS = "`KS~nombre~rango de antes~quién~t`: castigo repartido a los oficiales de mi hermandad",
    LN = "`LN~carril~generación~hora`: el carril del canal de la comunidad",
    LO = "`LO~up|reset`: un oficial de mi hermandad propone cambiar de carril a toda la comunidad",
    LP = "la sonda del carril, por el canal oculto",
    LQ = "«¿en qué carril estás?», de otra hermandad (se contesta con `LN`)",
    LV = "`LV~carril`: el enlace de otra hermandad dice que ese carril no le trae texto",
    LX = "`LX~carril~gen~hora~ETIQ~contacto`: un compañero me pasa el aviso de carril de otra hermandad",
    MA = "`MA~id~nombre,nombre`: respuesta de la guardia, los que sí son de mi hermandad",
    MG = "`MG~t~autor~etiqAutor~nombres`: lista de gestores (la firma el maestro de la principal)",
    ML = "`ML~etiq~id~parte~partes~datos`: un trozo de la lista de todos los conectados de una hermandad, solo para verla (Miembros de la unión)",
    MO = "`MO~etiq~id~parte~partes~datos`: un trozo de los desconectados de esa hermandad («nombre,clase,nivel,rango,horas»), solo por susurro a quien los pidió con `MP~…~o`",
    MP = "`MP~miEtiq~suEtiq[~o]`: pide esa lista (por GUILD, a quien se encarga de esa hermandad; por susurro, a alguien de ella; se contesta con `ML`, y con `o` también con `MO`)",
    MQ = "`MQ~id~nombre,nombre`: la guardia pregunta a una hermandad si son suyos",
    MU = "`MU~nombre~segundos~autor~etiq~t`: silenciar (0 = para siempre, -1 = quitar el silencio)",
    MZ = "varios silencios juntos (las entradas de `MU`, separadas por `;`)",
    NF = "`NF~t~quién~parte~partes~líneas`: la configuración de la nota de oficial",
    NG = "`NG~ETIQ~nombre~1|0~autor~etiq~t`: hermandad añadida o quitada (gana el más nuevo)",
    NK = "pide la configuración a la hermandad (contesta un oficial con `NF`)",
    NQ = "`NQ~R:ETIQ,…~W:ETIQ,…`: qué listas faltan (R = conectados, W = miembros)",
    OD = "`OD~etiq~Nombre,clase,nivel,horas;…`: desconectados de una hermandad",
    OE = "lo mismo que `OD`, por la cola media: los que alguien está mirando ahora",
    OQ = "`OQ~miEtiq~suEtiq`: pide los desconectados (se contesta con `OD`)",
    PA = "respuesta a `PG`",
    PB = "`PB~etiq~Nombre:raza:rol:spec:profs;…`: fichas de una hermandad",
    PF = "`PF~raza~rol~spec~profs`: mi ficha (por GUILD)",
    PG = "`PG~nombre`: «¿eres de la hermandad?» (por GUILD)",
    PH = "`PH~ETIQ~enlace~ayudante,…`: el enlace y los ayudantes de otra hermandad, contados por un compañero",
    PL = "`PL~ETIQ:Nombre,…`: el enlace comparte los contactos que conoce",
    PN = "`PN~hora~autor~etiq~texto`: mensaje fijado (texto vacío = quitarlo)",
    PQ = "al entrar, pide el mensaje fijado",
    PR = "`PR~ETIQ,ETIQ`: el enlace pregunta a su hermandad por un contacto en esas hermandades",
    PV = "salgo del juego (`/camp`, `/logout`, `/quit`), por GUILD",
    PW = "al final no he salido",
    PX = "`PX~ETIQ~nombre`: el juego dice que ese de otra hermandad no está conectado",
    RA = "la presentación del enlace (por el canal oculto o por susurro)",
    RB = "`RB~etiq~seq~total~conectados~parte~partes~datos`: la lista de conectados entera, en trozos",
    RC = "`RC~ETIQ~seqBase~seqNueva~total~conectados~parte~partes~cambios`: cambios de la lista de conectados",
    RD = "`RD~id`: petición de rango ya atendida",
    RF = "`RF~ETIQ[~2]`: pide la lista de conectados entera (2 = segunda opinión)",
    RN = "`RN~ETIQ~nombres~rangos de oficial`: los nombres de los rangos de una hermandad",
    RQ = "el primero de su hermandad en entrar pregunta si hay alguien más (para ser enlace sin esperar)",
    RR = "`RR~id~ok|no~quién~objetivo`: respuesta a una petición de rango",
}

local COMBAT = { list = "lista", req = "petición", data = "datos", last = "la última" }

local function Marks(s)
    local m = {}
    if s.tagField then m[#m + 1] = "etiq. " .. s.tagField end
    if s.bootstrap then m[#m + 1] = "arranque" end
    if s.open then m[#m + 1] = "abierta" end
    if s.channel then m[#m + 1] = "canal" end
    if s.remoteData then m[#m + 1] = "datos remotos" end
    return table.concat(m, ", ")
end

local function Queue(s)
    local q = s.queue or "normal"
    local extra = {}
    if s.latestWins then extra[#extra + 1] = "la última" end
    if s.skipLocked then extra[#extra + 1] = "se tira con el chat bloqueado" end
    return q .. (#extra > 0 and (" (" .. table.concat(extra, ", ") .. ")") or "")
end

local function Ttl(s)
    if s.ttl == false then return "nunca" end
    if s.ttl then return s.ttl .. " s" end
    return ""
end

-- files: { "Core.lua", ... } y read(f) -> texto. Devuelve [orden] = archivo donde se registra
function M.Sources(files, read)
    local at = {}
    for _, f in ipairs(files) do
        for cmd in read(f):gmatch('HU:RegisterMessage%("(%u+)"') do at[cmd] = f end
    end
    return at
end

function M.Render(msgs, at)
    local cmds = {}
    for cmd in pairs(msgs) do cmds[#cmds + 1] = cmd end
    table.sort(cmds)
    local out = {
        "# Protocolo de red",
        "",
        "> Generado de `HU.msgs` (`HU:RegisterMessage`, Protocol.lua) por `tests/lib/protocolo.lua`. No se",
        "> edita a mano: `lua tests/run.lua Protocolo --actualizar`. Cómo funciona todo esto: ARCHITECTURE.md,",
        "> «Cómo funciona».",
        "",
        "Cada orden es un mensaje de addon: la orden, y los campos separados por `~`. Sale por `HU20`, salvo las",
        "colas `b…` (datos grandes), que salen por `HU20B`.",
        "",
        "- **Cola** (Net/Transport.lua): `chat` > `normal` > `mid` > `low` por `HU20`, y `bfast` > `bulk` >",
        "  `bmid` > `blow` por `HU20B`. «La última»: una nueva con la misma vía y destino sustituye a la que",
        "  esperaba. «Se tira con el chat bloqueado»: si el juego bloquea el chat (campos de batalla, jefes),",
        "  no se guarda en la cola.",
        "- **Caduca**: lo que espera más que eso en la cola se tira.",
        "- **Seguridad** (Net/Security.lua, `AllowAddonMessage`; «etiq. N»: el campo N es la etiqueta de la",
        "  hermandad de la que habla). Por GUILD vale todo (el juego garantiza que es de mi hermandad), salvo",
        "  los «datos remotos» de otra hermandad: solo del enlace, sus ayudantes o un oficial. Por el canal",
        "  oculto, solo lo marcado «canal». Por susurro: «abierta», de cualquiera (la comprueba su manejador);",
        "  con la etiqueta de mi hermandad, nunca; con la de otra, solo «arranque» y de quien es de la",
        "  comunidad (si aún no lo sé, se retiene 3 min); sin etiqueta, de quien sale en alguna lista.",
        "- **En combate** (Combat.lua; en banda, mazmorra, campo de batalla o arena) se guarda para después:",
        "  «lista», las dos últimas listas enteras de cada hermandad y sus últimos cambios; «petición» y «la",
        "  última», la última de cada uno (las peticiones de más de 15 s se tiran); «datos», hasta un tope por",
        "  orden. Sin nada, se atiende al momento.",
        "",
        "| Orden | Qué es | Archivo | Cola | Caduca | Seguridad | En combate |",
        "|---|---|---|---|---|---|---|",
    }
    for _, cmd in ipairs(cmds) do
        local s = msgs[cmd]
        out[#out + 1] = string.format("| `%s` | %s | %s | %s | %s | %s | %s |", cmd,
            (M.DESC[cmd] or "?"):gsub("|", "\\|"), at[cmd] or "?", Queue(s), Ttl(s), Marks(s), COMBAT[s.combat] or "")
    end
    out[#out + 1] = ""
    return table.concat(out, "\n")
end

return M
