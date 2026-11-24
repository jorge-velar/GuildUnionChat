# Protocolo de red

> Generado de `HU.msgs` (`HU:RegisterMessage`, Protocol.lua) por `tests/lib/protocolo.lua`. No se
> edita a mano: `lua tests/run.lua Protocolo --actualizar`. Cómo funciona todo esto: ARCHITECTURE.md,
> «Cómo funciona».

Cada orden es un mensaje de addon: la orden, y los campos separados por `~`. Sale por `HU20`, salvo las
colas `b…` (datos grandes), que salen por `HU20B`.

- **Cola** (Net/Transport.lua): `chat` > `normal` > `mid` > `low` por `HU20`, y `bfast` > `bulk` >
  `bmid` > `blow` por `HU20B`. «La última»: una nueva con la misma vía y destino sustituye a la que
  esperaba. «Se tira con el chat bloqueado»: si el juego bloquea el chat (campos de batalla, jefes),
  no se guarda en la cola.
- **Caduca**: lo que espera más que eso en la cola se tira.
- **Seguridad** (Net/Security.lua, `AllowAddonMessage`; «etiq. N»: el campo N es la etiqueta de la
  hermandad de la que habla). Por GUILD vale todo (el juego garantiza que es de mi hermandad), salvo
  los «datos remotos» de otra hermandad: solo del enlace, sus ayudantes o un oficial. Por el canal
  oculto, solo lo marcado «canal». Por susurro: «abierta», de cualquiera (la comprueba su manejador);
  con la etiqueta de mi hermandad, nunca; con la de otra, solo «arranque» y de quien es de la
  comunidad (si aún no lo sé, se retiene 3 min); sin etiqueta, de quien sale en alguna lista.
- **En combate** (Combat.lua; en banda, mazmorra, campo de batalla o arena) se guarda para después:
  «lista», las dos últimas listas enteras de cada hermandad y sus últimos cambios; «petición» y «la
  última», la última de cada uno (las peticiones de más de 15 s se tiran); «datos», hasta un tope por
  orden. Sin nada, se atiende al momento.

| Orden | Qué es | Archivo | Cola | Caduca | Seguridad | En combate |
|---|---|---|---|---|---|---|
| `AU` | `AU~id~hora~etiq~autor~texto`: una entrada del registro compartido | Audit.lua | normal |  |  |  |
| `BN` | `BN~nombre~1\|0~autor~etiq~t`: veto (1) o readmisión (0) | Social.lua | chat | nunca |  |  |
| `CF` | `CF~canal~[ETIQ] mensaje`: chat de un compañero cuyo texto no sale por el canal (por GUILD) | Channel.lua | chat | 60 s |  |  |
| `CG` | `CG~canal~autor~[ETIQ] mensaje`: chat que un compañero recibió por susurro y reparte por GUILD | Channel.lua | chat | 20 s |  |  |
| `CK` | el canal pasado a mano (`/gu pasarcanal`): solo vale de provisional | Channels.lua | normal |  | abierta |  |
| `CP` | `CP~canal~clave~t~autor~etiq`: el canal de la comunidad, repartido por un oficial (gana el más nuevo) | Channels.lua | chat | 600 s |  |  |
| `CQ` | al entrar, pide el canal (contesta el primero que lo tenga) | Channels.lua | chat | 600 s |  |  |
| `CW` | `CW~canal~autor~[ETIQ] mensaje`: chat por susurro, del autor o de un compañero suyo que lo reparte | Channel.lua | chat | 60 s |  |  |
| `CX` | `CX~nombre~clave~borrado~autor~etiq~t`: crear o quitar un canal extra | Channels.lua | chat | 600 s |  |  |
| `EM` | `EM~código~ruta~autor~etiqAutor~t`: emoticono propio (ruta vacía = borrado) | Community.lua | mid |  |  |  |
| `EQ` | `EQ~id~quién~firma`: pide los errores guardados | ErrorShare.lua | normal |  |  |  |
| `ER` | `ER~id~remitente~versión~dónde~error`: un error guardado | ErrorShare.lua | normal |  |  |  |
| `GA` | `GA~id~1\|0~nombre o motivo`: respuesta a una invitación a la comunidad | Community.lua | normal |  | abierta |  |
| `GC` | `GC~ETIQ~rrggbb~autor~etiqAutor~t`: color de una hermandad (vacío = el de siempre) | Community.lua | normal |  |  |  |
| `GD` | `GD~id`: petición de echar ya atendida | Social.lua | normal |  |  |  |
| `GK` | `GK~id~tag~objetivo~solicitante~etiqSol`: pide echar a alguien de otra hermandad | Social.lua | chat | 600 s |  |  |
| `GL` | `GL~id~parte~partes~datos`: la configuración de la comunidad, tras aceptar la invitación | Community.lua | normal |  | abierta |  |
| `GR` | `GR~id~ok\|no~quién~objetivo~motivo`: respuesta a quien pidió echar | Social.lua | normal |  |  |  |
| `GV` | `GV~id~ETIQ~título~hermandad`: invitación a la comunidad (al contacto de la hermandad nueva) | Community.lua | normal |  | abierta |  |
| `HI` | `HI~ver~etiq~mod~enlace…`: saludo (por GUILD a la hermandad, o por susurro a otra) | Net/Relay.lua | normal (la última, se tira con el chat bloqueado) | 60 s | etiq. 2, arranque |  |
| `HL` | `HL~t~tipo~etiq~autor~mensaje`: una línea del historial | Social.lua | blow | 900 s |  | datos |
| `HQ` | `HQ~desde~oficial`: al entrar, pide lo escrito mientras no estabas | Social.lua | normal |  |  | petición |
| `HR` | respuesta a un saludo, con los mismos campos (no provoca más saludos) | Net/Relay.lua | normal (la última, se tira con el chat bloqueado) | 60 s | etiq. 2, arranque |  |
| `HY` | el enlace nuevo pide a su hermandad que salude (cada uno contesta con `HR`) | Net/Relay.lua | normal (la última, se tira con el chat bloqueado) | 60 s |  |  |
| `KS` | `KS~nombre~rango de antes~quién~t`: castigo repartido a los oficiales de mi hermandad | Ranks.lua | normal |  |  |  |
| `LN` | `LN~carril~generación~hora`: el carril del canal de la comunidad | Net/Relay.lua | normal (la última, se tira con el chat bloqueado) | 60 s |  |  |
| `LO` | `LO~up\|reset`: un oficial de mi hermandad propone cambiar de carril a toda la comunidad | Net/Relay.lua | normal | 60 s |  |  |
| `LP` | la sonda del carril, por el canal oculto | Net/Relay.lua | normal (se tira con el chat bloqueado) | 60 s | canal |  |
| `LQ` | «¿en qué carril estás?», de otra hermandad (se contesta con `LN`) | Net/Relay.lua | normal |  |  |  |
| `LV` | `LV~carril`: el enlace de otra hermandad dice que ese carril no le trae texto | Net/Relay.lua | normal | 60 s |  |  |
| `LX` | `LX~carril~gen~hora~ETIQ~contacto`: un compañero me pasa el aviso de carril de otra hermandad | Net/Relay.lua | normal |  |  |  |
| `MA` | `MA~id~nombre,nombre`: respuesta de la guardia, los que sí son de mi hermandad | Guard.lua | normal |  |  |  |
| `MG` | `MG~t~autor~etiqAutor~nombres`: lista de gestores (la firma el maestro de la principal) | Community.lua | normal |  |  |  |
| `ML` | `ML~etiq~id~parte~partes~datos`: un trozo de la lista de todos los conectados de una hermandad, solo para verla (Miembros de la unión) | UnionMembers.lua | bmid | 120 s | etiq. 1, abierta, datos remotos | datos |
| `MP` | `MP~miEtiq~suEtiq`: pide esa lista (por GUILD, a quien se encarga de esa hermandad; por susurro, a alguien de ella; se contesta con `ML`) | UnionMembers.lua | normal |  | abierta | petición |
| `MQ` | `MQ~id~nombre,nombre`: la guardia pregunta a una hermandad si son suyos | Guard.lua | mid |  |  |  |
| `MU` | `MU~nombre~segundos~autor~etiq~t`: silenciar (0 = para siempre, -1 = quitar el silencio) | Social.lua | chat | nunca |  |  |
| `MZ` | varios silencios juntos (las entradas de `MU`, separadas por `;`) | Social.lua | chat | nunca |  |  |
| `NF` | `NF~t~quién~parte~partes~líneas`: la configuración de la nota de oficial | NoteConfig.lua | normal |  |  |  |
| `NG` | `NG~ETIQ~nombre~1\|0~autor~etiq~t`: hermandad añadida o quitada (gana el más nuevo) | Community.lua | normal |  |  |  |
| `NK` | pide la configuración a la hermandad (contesta un oficial con `NF`) | NoteConfig.lua | normal |  |  |  |
| `NQ` | `NQ~R:ETIQ,…~W:ETIQ,…`: qué listas faltan (R = conectados, W = miembros) | Net/RosterSync.lua | normal |  |  | petición |
| `OD` | `OD~etiq~Nombre,clase,nivel,horas;…`: desconectados de una hermandad | Social.lua | blow | 900 s | etiq. 1, datos remotos | datos |
| `OE` | lo mismo que `OD`, por la cola media: los que alguien está mirando ahora | Social.lua | mid |  | etiq. 1, datos remotos | datos |
| `OQ` | `OQ~miEtiq~suEtiq`: pide los desconectados (se contesta con `OD`) | Social.lua | normal |  |  | petición |
| `PA` | respuesta a `PG` | Net/Relay.lua | normal |  |  |  |
| `PB` | `PB~etiq~Nombre:raza:rol:spec:profs;…`: fichas de una hermandad | Social.lua | bmid | 900 s | etiq. 1, datos remotos | datos |
| `PF` | `PF~raza~rol~spec~profs`: mi ficha (por GUILD) | Social.lua | normal |  |  |  |
| `PG` | `PG~nombre`: «¿eres de la hermandad?» (por GUILD) | Net/Relay.lua | normal |  |  |  |
| `PH` | `PH~ETIQ~enlace~ayudante,…`: el enlace y los ayudantes de otra hermandad, contados por un compañero | Net/Relay.lua | normal (se tira con el chat bloqueado) | 60 s |  | la última |
| `PL` | `PL~ETIQ:Nombre,…`: el enlace comparte los contactos que conoce | Net/Relay.lua | normal (se tira con el chat bloqueado) | 60 s |  | la última |
| `PN` | `PN~hora~autor~etiq~texto`: mensaje fijado (texto vacío = quitarlo) | Pinned.lua | chat | 600 s |  |  |
| `PQ` | al entrar, pide el mensaje fijado | Pinned.lua | normal |  |  |  |
| `PR` | `PR~ETIQ,ETIQ`: el enlace pregunta a su hermandad por un contacto en esas hermandades | Net/Relay.lua | normal |  |  |  |
| `PV` | salgo del juego (`/camp`, `/logout`, `/quit`), por GUILD | Presence.lua | normal |  |  |  |
| `PW` | al final no he salido | Presence.lua | normal |  |  |  |
| `PX` | `PX~ETIQ~nombre`: el juego dice que ese de otra hermandad no está conectado | Presence.lua | normal |  |  |  |
| `RA` | la presentación del enlace (por el canal oculto o por susurro) | Net/Relay.lua | normal (la última, se tira con el chat bloqueado) | 60 s | etiq. 1, arranque, canal |  |
| `RB` | `RB~etiq~seq~total~conectados~parte~partes~datos`: la lista de conectados entera, en trozos | Net/RosterSync.lua | bulk | 600 s | etiq. 1, arranque, datos remotos | lista |
| `RC` | `RC~ETIQ~seqBase~seqNueva~total~conectados~parte~partes~cambios`: cambios de la lista de conectados | Net/RosterSync.lua | bfast | 300 s | etiq. 1, arranque, datos remotos |  |
| `RD` | `RD~id`: petición de rango ya atendida | Ranks.lua | normal |  |  |  |
| `RF` | `RF~ETIQ[~2]`: pide la lista de conectados entera (2 = segunda opinión) | Net/RosterSync.lua | normal |  | etiq. 1, arranque | petición |
| `RN` | `RN~ETIQ~nombres~rangos de oficial`: los nombres de los rangos de una hermandad | Ranks.lua | normal |  | etiq. 1, arranque, datos remotos |  |
| `RQ` | el primero de su hermandad en entrar pregunta si hay alguien más (para ser enlace sin esperar) | Net/Relay.lua | normal |  |  |  |
| `RR` | `RR~id~ok\|no~quién~objetivo`: respuesta a una petición de rango | Ranks.lua | normal |  |  |  |
