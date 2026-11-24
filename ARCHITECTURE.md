# Guild Union · cómo funciona y notas del código

> [!note] Qué hay aquí
> - **Cómo funciona**: las piezas grandes, por conceptos: los archivos, el protocolo, los prefijos, la
>   confianza y el enlace.
> - **Los registros**: cómo se declara cada cosa nueva (órdenes, módulos, avisos, lo guardado, lo que se
>   repite, migraciones, comandos).
> - **Notas por archivo**: los comentarios largos que estaban en el código. En el código queda la
>   primera línea con la marca `[+ARCHITECTURE.md]`; aquí está el texto entero, en el apartado de su
>   archivo y en el orden del código. Cada nota lleva el nombre de la función, o la primera línea de
>   código que sigue a la marca: para ir de una a otra se busca ese nombre o el principio del
>   comentario (nunca un número de línea, que cambia con cada edición).
> - Al final, apartados por tema y el historial de las copias de prueba.
>
> La tabla de las órdenes de red está aparte, generada del código: [docs/protocolo.md](docs/protocolo.md).

## Pruebas: la regla

Todo cambio de código llega con sus pruebas en `tests/spec/`, y el CI lo comprueba
(`tests/cobertura.lua`):

- **Lo nuevo o cambiado** en una PR tiene que estar probado al **70 %** como mínimo. Si no, el CI
  dice qué líneas faltan. Solo quedan fuera los archivos de pura interfaz (BlizzTab, WMPanel,
  ListWindow, UIWindows, Wizard).
- **Ningún archivo baja** de su cobertura mínima (`tests/cobertura-minima.txt`). Cuando un archivo
  sube, se rehacen los mínimos para que no vuelva a bajar: se copia el artefacto `cobertura-minima`
  del CI (son de Lua 5.1; con la 5.4 de un equipo salen otros valores).
- **Cada fallo visto en el juego** se arregla escribiendo primero la prueba que lo reproduce.
- Lo que hace falta de varios jugadores (chat entre hermandades, listas, enlaces) se prueba con la
  red de `tests/lib/red.lua`, no a mano.

Cómo se escriben y se pasan las pruebas: [docs/propuesta-arquitectura.md](docs/propuesta-arquitectura.md#paso-1-en-detalle).

## Cómo funciona

### Las piezas

Los archivos se cargan en el orden del `.toc`. Cada uno acaba con `HU:Module(nombre, { necesita })`
(ver «Los registros»).

| Capa | Archivos | Qué hacen |
|---|---|---|
| Núcleo | `Core.lua`, `Protocol.lua` | `HU`, eventos, registros (comandos, migraciones, tareas, módulos, avisos, lo guardado) y el de órdenes de red |
| Configuración | `Config.lua`, `NoteConfig.lua`, `Orders.lua`, `Popup.lua` | lo que dice la Información de hermandad (`GU:…`), quién es oficial, avisos de versión |
| Red | `Comm.lua`, `Net/Transport.lua`, `Net/Relay.lua`, `Net/RosterSync.lua`, `Net/Security.lua` | contactos, cola de envío, el enlace, las listas de conectados y la entrada de mensajes |
| Confianza | `Domain/Trust.lua`, `Lists.lua`, `Guard.lua`, `GuardKeeper.lua` | de quién me fío, en qué estado está la lista de cada hermandad, la guardia del canal |
| Chat | `Channel.lua`, `ChatPaint.lua`, `ChatTabs.lua`, `Channels.lua`, `Mention.lua`, `History.lua` | el canal de la comunidad, el respaldo por susurro, pintar las líneas, historial |
| Resto | `Presence.lua`, `Ranks.lua`, `Social.lua`, `Community.lua`, `Combat.lua`, `Pinned.lua`, … | conectados, rangos, silencios y vetos, unirse a la comunidad, modo combate, fijado |
| Ventanas | `UI.lua`, `UIWindows.lua`, `BlizzTab.lua`, `WMPanel.lua`, `ListWindow.lua`, `Wizard.lua`, … | lo que se ve (sin pruebas de cobertura obligatorias) |

**Comm.lua partido** (paso 3 de docs/propuesta-arquitectura.md), sin cambiar nada del código y en este
orden de carga:

| Archivo | Qué hay |
|---|---|
| `Comm.lua` | contactos (`guildPeers`, `remote`, el índice por etiqueta) y las listas guardadas al salir |
| `Net/Transport.lua` | la cola de envío, `HU:Send`, los prefijos y los susurros a desconectados |
| `Domain/Trust.lua` | estados de las listas (`b`/`m`/`p`/`c`), anclas, contactos comprobados, `SenderKind`, `BestPeers` |
| `Net/Relay.lua` | el enlace y sus ayudantes, saludos (`HI`/`HR`/`HY`/`RA`), presentaciones, carriles (`LN`…) y los ciclos |
| `Net/RosterSync.lua` | listas de conectados: enteras (`RB`), cambios (`RC`), peticiones (`RF`, `NQ`), huellas |
| `Net/Security.lua` | `AllowAddonMessage`, `Vouched`, `Hold`/`ReplayHeld`, `Admit`, `PartialAdmit` y la entrada (`HU.OnAddonMessage`) |

Lo que comparten se pasa por `HU`: `HU.netPerf` (las medidas de este ordenador), `HU.VOUCH_TTL`,
`HU.ReshareRoster`, `HU:BulkQueueSize()` y `HU.QueueTick` (el cupo de la cola, que cada segundo llama
la tarea `cola-cupo`).

### El protocolo

Cada orden de red se declara una vez, con `HU:RegisterMessage`, junto a su manejador: su cola, cuánto
tarda en caducar, sus marcas de seguridad y qué se hace con ella en combate. La tabla de todas, con su
formato y lo que declaran, se genera de ese registro: [docs/protocolo.md](docs/protocolo.md)
(`lua tests/run.lua Protocolo --actualizar`; la prueba falla si no está al día o si una orden no
tiene descripción en `tests/lib/protocolo.lua`).

El formato de cada mensaje está fijado por `tests/spec/formato_spec.lua` (`tests/golden/formato.txt`)
y se prueba contra la última versión publicada: un cambio de formato tiene que seguir entendiéndose
con las versiones que ya están en el juego.

### Los cinco prefijos y quién comprueba cada uno

| Prefijo | Para qué | Por dónde llega | Quién lo comprueba |
|---|---|---|---|
| `HU20` | las órdenes del registro (saludos, listas, silencios, chat por susurro…) | GUILD, susurro, el canal oculto | `HU.OnAddonMessage` (Net/Security.lua): `Admit` (tope por remitente) y `AllowAddonMessage` (las marcas de cada orden) |
| `HU20B` | las mismas órdenes, las de datos grandes (colas `b…`: `RB`, `RC`, `PB`, `OD`, `HL`) | igual | igual que `HU20`; solo cambia la cola, que tiene su propio cupo para no frenar el chat |
| `HU20C` | el chat como mensaje oculto por el canal (`CM~canal~[ETIQ] mensaje`), la sonda (`SD`) y `/gu prueba` (`TQ`/`TR`) | solo el canal | `OnHiddenChat` (Channel.lua): solo por CHANNEL, solo de un canal en el que estoy y que llegue de verdad de ese canal (`OurChannelKind`). Entrar al canal pide la contraseña: quien habla ahí queda «visto en el canal» (`MarkChannelSeen`) |
| `HU20H` | el historial entre oficiales (búsquedas, contexto, sincronización) | susurro | History.lua: solo con el historial encendido; las peticiones y la sincronización, solo de un oficial de confianza (`TrustedOfficer`) y con tope por minuto; las respuestas, solo a una búsqueda pendiente y de un oficial o de quien se preguntó |
| `HU20T` | el registro de pruebas (`/gu registro`) | susurro | TestLog.lua: solo si el registro está encendido (apagado por defecto). No mira quién lo manda |

`HU20C`, `HU20H` y `HU20T` no pasan por la seguridad central (diagnóstico #12 de la propuesta): cada
uno hace sus comprobaciones, las de la tabla.

### La confianza: de quién se acepta qué

La regla de fondo: **los datos de una hermandad solo valen si vienen de alguien de esa hermandad**, y
nadie de fuera puede mandar datos de la mía.

- **Mi hermandad.** Lo que llega por GUILD es de un compañero: lo garantiza el juego. Quién es oficial
  se sabe por los permisos del rango (`HU:RankRole`, Config.lua), no por su nombre.
- **Las otras hermandades.** De cada una se tiene su lista de conectados (`HU.remoteRoster`), en uno de
  cuatro estados (Domain/Trust.lua): `b` arranque (se ve, pero nadie cuenta como miembro), `m`
  miembros, `p` rangos provisionales y `c` confirmada (la ha mandado o confirmado un contacto
  comprobado). El **ancla** de cada hermandad (el maestro u oficial que aceptó la invitación, o quien
  invitó a la mía) confirma su lista al momento mientras siga siendo maestro u oficial en ella.
- **Quién puede mandarme la lista de otra hermandad** (`HU:SenderKind`): alguien a quien nombró su
  enlace comprobado, un contacto comprobado, alguien de mi copia de su lista, un contacto de antes o
  quien salió en una presentación por el canal. Ya no vale haber escrito en el chat con su etiqueta.
- **Un desconocido que dice ser de la comunidad** (`HU:Vouched`) vale si ha hablado por el canal oculto
  (2 h), sale en la lista del canal, es un contacto conocido de esa hermandad o un ayudante que anunció
  su enlace. Si aún no lo sé, lo que manda para arrancar (saludos, listas) se retiene hasta 3 min
  (`Hold`, como mucho 100) y se aplica en cuanto se le reconoce (`ReplayHeld`).
- **Datos de otra hermandad que llegan por la mía** (`remoteData`): solo los reparten el enlace, sus
  ayudantes o un oficial (`HU:IsGuildForwarder`). La lista de conectados de un compañero cualquiera
  vale, pero como débil.
- **Topes**, para que nadie pueda inundar: cada remitente de fuera, 60 mensajes de golpe y 2 por segundo
  (un contacto comprobado, 200 y 10); trozos a medio recibir, 4 por remitente y 400 en total.

Las reglas exactas de cada orden: las marcas de [docs/protocolo.md](docs/protocolo.md). Los detalles y
el porqué de cada uno, en las notas de Domain/Trust.lua, Net/Security.lua y Lists.lua.

### El enlace y sus ayudantes

Los addons no pueden escribir en un canal personalizado, así que entre hermandades se habla por
susurro. En cada hermandad, **el enlace** es quien habla con las otras: les manda la lista de
conectados de la suya y reparte lo que recibe. Los **ayudantes** se reparten ese trabajo con él.

- **Quién es** (Net/Relay.lua, `HU:RelayScore`): cada uno dice su puntuación en el saludo (`HI`) y es
  enlace el que más tiene; con la misma, el primero por nombre. Los oficiales y el maestro van
  primero (+100, si su conexión va bien); entre iguales, cuentan el ping, que no dé saltos, el tiempo conectado (un `/reload`
  no lo pone a cero) y que no se haya caído en la última hora. Restan estar ocupado (banda, campo de
  batalla o arena: 150), ausente (40) o en zona de descanso, donde se sale del juego al momento (20).
  El enlace actual tiene 15 de ventaja, para que no cambie por un poco de ping: cada cambio es una
  lista nueva para todas las hermandades. La puntuación que dice otro se recorta (`HU:SaneScore`).
- **Al entrar** no se es enlace durante 30 s (si no, cada uno se creía el enlace y pisaba la lista
  buena), salvo el primero de su hermandad en entrar, que pregunta (`RQ`) y no espera.
- **Los ayudantes** son los siguientes mejores, con ventaja los que ya lo son, y no cambian más de una
  vez cada 2 minutos. Un enlace nuevo se queda con los del anterior (`HU:InheritHelpers`).
- **Las otras hermandades** saben quién es por su presentación (`RA`) y por lo que cuentan sus
  compañeros (`PL`, `PH`). Quien se presenta sin estar comprobado es enlace provisional, con reglas
  contra quien se presenta demasiado a menudo.
- **Al salir del juego** (`/camp`, `/logout`), el enlace o un ayudante lo dice (`PV`) y avisa él mismo a
  las otras hermandades, para no esperar a que otro herede el puesto.

El canal de la comunidad tiene además **carriles** (salas numeradas, `LN`, `LO`, `LV`, `LX`): si el canal
deja de llevar texto, la comunidad se puede mudar a otro. Sus reglas están en las notas de
Net/Relay.lua y en los apartados de las copias 117 a 120, al final.

### Las dos listas de las otras hermandades

- **La pequeña** (`RB`/`RC`, siempre): su maestro, sus oficiales, su enlace y sus ayudantes conectados.
  Es la que usa la confianza (de quién se aceptan sus datos) y la guardia.
- **La de todos los conectados** («Miembros» en la pestaña, UnionMembers.lua: `MP`/`ML`): solo para
  verla, **no cuenta para nada de la confianza**. No se manda sola; se pide al mirarla, porque son
  decenas de mensajes por hermandad y el juego deja uno por segundo. En cada hermandad la pide una
  sola persona (quien se encarga de esa hermandad, `HU:ResponsibleFor`) y la reparte por GUILD.
  Contesta alguien de la otra hermandad, solo a quien es de la comunidad (lleva la zona de cada uno).

## Los registros

Cómo se declara cada cosa nueva (la lista corta está en CLAUDE.md).

### Registro de órdenes: `HU:RegisterMessage`

Cada orden de red (prefijos HU20 y HU20B) se declara una vez, junto a su manejador, con todo lo
suyo; lo leen la seguridad (`AllowAddonMessage`), la cola (`HU:Send`), el combate
(`HU.CombatDispatch`) y `/gu diag`. Antes cada cosa estaba en su tabla (hasta 6 por orden, en
Comm.lua y Combat.lua) y, si faltaba una, no había error: el mensaje iba a la cola por defecto, se
rechazaba o en combate se trataba distinto, sin avisar.

```lua
HU:RegisterMessage("CW", { fields = { "chan", "author", "line*" }, queue = "chat", ttl = 60,
    handler = function(self, sender, f, dist) --[[ f.chan, f.author, f.line ]] end })
```

| Clave | Qué es | Sin declarar |
|---|---|---|
| `tagField` | campo con la etiqueta de la hermandad de la que habla el mensaje | sin etiqueta |
| `bootstrap` | con la etiqueta de otra hermandad, vale de quien es de la comunidad; sin avalar, se retiene | no |
| `open` | invitaciones de hermandades nuevas: vale de cualquiera por susurro (el manejador comprueba) | no |
| `channel` | puede llegar por el canal oculto | no |
| `remoteData` | datos de otra hermandad por GUILD: solo del enlace, sus ayudantes o un oficial | no |
| `queue` | `chat`, `normal`, `mid`, `low` (HU20) o `bfast`, `bulk`, `bmid`, `blow` (HU20B) | `normal` |
| `ttl` | segundos que puede esperar en la cola; `false` = no caduca (silencios y vetos) | 300 |
| `latestWins` | uno nuevo con la misma orden, vía y destino sustituye al que espera | no |
| `skipLocked` | con el chat bloqueado por el juego no se guarda (saludos y presentaciones) | no |
| `combat` | en combate dentro de una instancia: `list`, `req`, `data` o `last` | se trata ya |
| `fields` | nombres de los campos; `f.nombre` es `f[i]`, y el último con `*` es el resto con sus `~` | solo `f[i]` |
| `handler` | el manejador (si no, el de `HU.comm[orden]` de siempre) | |

- El nombre son 1 o 2 mayúsculas; una clave mal escrita, un valor del tipo que no es, una cola o un
  tipo de combate desconocidos, `bootstrap`/`remoteData` sin `tagField`, un `*` que no es el último
  o una orden registrada dos veces dan error al cargar (y las pruebas lo ven).
- Los campos con nombre no crean otra tabla: la entrada pone una metatabla compartida en la de
  `HU.Split`. Siguen valiendo `f[i]` y `table.concat(f, "~", i)`.
- Los manejadores siguen en `HU.comm[orden]`: varios archivos envuelven el de otro (`PQ`, `CP`,
  `RC`, `HI`...). Por eso el registro no exige `handler`.
- `tests/spec/registro_spec.lua` fija que lo declarado da exactamente las tablas de la 5.4.41 y que
  toda orden con manejador está registrada (y al revés).

### Módulos: `HU:Module` al final de cada archivo

Cada archivo del .toc acaba con `HU:Module("Net/Relay", { "Channel", "Comm", … })`: su nombre (la
ruta sin `.lua`) y los archivos que definen las funciones de `HU` que llama.

- Va **al final** porque así solo consta si el archivo ha cargado entero.
- Al entrar (`PLAYER_LOGIN`, antes de los `OnStart`), `HU:CheckModules()` mira que esté todo lo
  necesitado. Lo que falte sale en `/gu errores`, con quién lo necesita.
- La lista no se escribe a mano: `tests/lib/modulos.lua` la calcula y `modulos_spec` exige que lo
  declarado sea exactamente eso. Una dependencia nueva hay que declararla, y así se ve en la PR.

Por eso sobran las comprobaciones `HU.X and HU:X()` / `if HU.X then HU:X() end`:

- todos los archivos se cargan siempre, en orden, y lo comprueba `CheckModules`;
- esconden los nombres mal escritos (la llamada no se hace nunca, sin avisar).

Se han quitado 185. `guardas_spec` no deja que vuelvan sobre una función que siempre existe, salvo
las de su lista `JUSTIFIED`, con su motivo. Hoy solo hay una: `SyncCharSearch`, que no existe hasta
que el juego carga su ventana de hermandad. Las de funciones del juego o de sus marcos (`IsShown`,
`GetAtlasInfo`…) siguen: el juego puede no tenerlas.

### Avisos entre módulos: `HU:Listen` / `HU:Fire`

`HU:Fire("CHANGED", "members")` llama a todo lo que ha hecho `HU:Listen("CHANGED", fn)`, en orden.
Cada uno va por `SafeCall`, como los eventos del juego: si uno falla, los demás siguen.

Hoy lo usa `HU:Changed`, que antes llamaba a `HU.UI:MarkDirty` directamente y ahora avisa con
`CHANGED`; lo escucha UI.lua. Los siguientes candidatos son los avisos que hoy son llamadas
directas entre módulos (`RefreshConfig`, `RetryDeferred`…).

### Lo guardado: `HU:Saved`

Cada módulo declara sus claves al principio de su archivo:

```lua
HU:Saved({ account = { bans = {}, loginHistory = false }, char = { history = {}, "offlineT" } })
```

- `account` es para toda la cuenta y `char`, para cada personaje.
- `clave = valor` le da un valor por defecto; la clave sola, sin valor.
- Core.lua junta las declaraciones en `HU.PER_CHAR` y en sus valores por defecto. Antes eran dos
  listas a mano en Core.lua: `DEFAULTS` y `PER_CHAR`.
- Una clave declarada dos veces es un error.
- `datos_spec` fija que lo declarado da exactamente lo de la 5.4.41.

### Planificador: `HU:Every`

```lua
HU:Every(15, "listas-ciclo", function() HU:RosterCycle() end, { pauseInCombat = false, maxFailures = nil, times = nil })
```

Todo lo que se repite pasa por aquí: ya no hay `HU.NewTicker`. Cada tarea lleva un nombre, que sale
en `/gu errores` si falla y en `/gu perf` con sus veces y su tiempo (`HU:TaskLines()`).

- **Cada tarea sigue teniendo su propio temporizador del juego**, como antes. Uno solo para todas
  cambiaría en qué momento corre cada una, y eso ya sería un cambio de comportamiento.
- Un fallo no la para (`SafeCall`), salvo con `maxFailures`. `pauseInCombat` no la hace mientras
  `HU:CombatHold()`, la regla de combate de siempre.
- Las 40 que había llevan las dos opciones apagadas, porque hacían lo mismo sin ellas. Las que ya
  miraban el combate lo siguen haciendo dentro.
- `HU.After` se queda como está: no se repite y se usa mucho con 0 s para repartir trabajo entre
  fotogramas.

### Migraciones: `HU:RegisterMigration` y `HU:RunMigrations`

Lo guardado tiene dos ámbitos con su número de esquema: la cuenta (`adb.schema`, que también es
`db.schema`) y cada personaje (`cdb.schema`, dentro de `adb.chars`). Cada migración es un paso de
un número al siguiente:

```lua
HU:RegisterMigration("char", 1, "de la cuenta al personaje", function(adb, cdb, info)
    if not info then return false end -- (necesita la Información: se vuelve a probar)
    …
    return true
end)
```

- Se ejecutan al cargar el addon (`ADDON_LOADED`, con `info = nil`) y cada vez que se lee la
  Información de la hermandad (`RefreshConfig`, con `info = { guild, text }`). Una que devuelve
  `false` se queda para la siguiente, y las de detrás esperan.
- Ejecutar una dos veces no estropea nada.
- **Lo guardado por una versión más nueva** (un esquema mayor que el número de migraciones que
  conoce esta) no se toca: se avisa en `/gu errores` y no se migra nada de ese ámbito.
- La 1 del personaje es la que antes hacía `RefreshConfig` con la marca suelta `cdb.migrated`:
  copia al personaje lo que versiones viejas guardaban para la cuenta (canal, fijado, notas…), solo
  si era de su hermandad. Sigue poniendo `cdb.migrated`, que miran las versiones de antes.
- `tests/spec/datos_spec.lua`: cada caso de la migración 1, la versión más nueva, y lo que guarda
  la última versión publicada en un rato de juego (`tests/lib/escenario.lua`), que al actualizar no
  pierde ninguna clave y con lo que se puede volver a la versión de antes.

### Registro de los comandos /gu: `HU:RegisterSlash`

```lua
HU:RegisterSlash("cola", { aliases = { "queue" }, help = "|cffffd100/gu cola|r  …",
    available = nil, fn = function(arg, rawArg, cmd) … end })
```

- `fn` recibe el argumento en minúsculas, tal cual y el nombre del comando (no el alias:
  `/gu search` llega como `buscar`).
- `available`: el comando depende de algo que puede no estar cargado (`OpenWizard`,
  `ShowGuildsWindow`…); si devuelve falso, sale la ayuda, como un comando que no existe.
- La ayuda son las líneas `help` de todos, **en el orden en que se registran**. Una entrada sin `fn`
  solo pone su línea en la ayuda (`/hg`, que es otro comando, y la segunda línea de `/gu carril`).
- Un nombre o alias repetido, una clave que no existe o en mayúsculas dan error al cargar.
- `tests/spec/slash_spec.lua` ejecuta todos los comandos y alias y compara con
  `tests/golden/comandos.txt` (a qué funciones de `HU` llama cada uno y qué escribe). Un comando
  nuevo hay que añadirlo a su lista `INPUTS` (una prueba lo exige) y rehacer la referencia.

## Notas por archivo

Los comentarios largos del código, por archivo (en el orden del .toc) y en el orden del código.
Cada título es la función donde está la marca, o la primera línea de código que la sigue.

## Core.lua

### `_G.GuildUnionInternal = HU`

### `for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do`

Forever usa el cliente moderno: si el juego bloquea que el addon escriba solo en el canal (como
en Retail), a partir de ahí la presentación va como mensaje oculto, y se manda ya otra vez
(según el caso, el juego lo da como "bloqueado" o como "prohibido": se escuchan los dos)

### `HU.Secret`

Solo WoW Forever: los personajes tienen nombre y apellido, y el apellido va donde en los demás
juegos va el reino ("Nombre-Apellido"); no hay reinos. Echar, ascender, degradar e invitar a la
hermandad solo los deja hacer el juego desde un botón suyo: se hace con /gremove, etc.

### `local NAME_MAP_EVERY, NAME_MISS_FOR, NAME_MISS_MAX, NAME_MAP_MS = 30, 30, 500, 1`

Forever: "Pepe" -> "Pepe-Garcia" si solo hay un Pepe entre los que conocemos
El mapa de nombres (miles) costaba 5-12 ms rehacerlo, y se rehacía con cualquier nombre que no estuviera:
un intruso, un aviso del juego, o mensajes con nombres inventados a propósito daban un tirón. Ahora:
  * los que no se encontraron se recuerdan NAME_MISS_FOR s (como mucho NAME_MISS_MAX): no lo rehacen;
  * se rehace como mucho cada NAME_MAP_EVERY s, o antes si cambian los nombres de mi hermandad, y por
    trozos de NAME_MAP_MS por fotograma; mientras, contesta el mapa anterior.

### `HU.SafeBool`

Midnight: el juego no deja mandar mensajes de chat ni de addon en algunas mazmorras y
encuentros. Lo pendiente se queda en cola hasta que se pueda.
(sin modo sencillo en ReduceClean: siempre apagado; aquí y no en UIStubs, que depende de UI.lua)

### `HU.NetT`

Momento de una acción que llega por la red, para «gana la más nueva»: como mucho dentro de 5
minutos. Antes valía cualquier número: con t=1e300 (o 2^53) la acción falsa ya no la podía
cambiar nadie, porque t+1 da lo mismo. Se recorta en vez de rechazar, por los relojes mal puestos.

### `local LINK_OK = { item = true, spell = true, quest = true, achievement = true…`

Texto que llega de otro addon (chat oculto, fijado, notas, historial...): sin saltos de línea ni
caracteres de control, y sin códigos de formato (|T textura, |H enlace, |c color, |K...), que se
pintaban tal cual: se podía imitar una línea del maestro, tapar la pantalla con una textura
gigante o colar un enlace que enseña una dirección y copia otra. Con links = true se respetan los
enlaces de juego bien formados (objeto, hechizo, misión, logro...), que el chat normal también deja.

### en `evento ADDON_LOADED`: `local adb = GuildUnionDB`

Lo de cada personaje va aparte (si no, un personaje de otra hermandad, o al que han echado,
vería el chat, el fijado y el canal de la comunidad de otro personaje de la misma cuenta)
(dentro de lo de la cuenta, un apartado por personaje: así funciona aunque el juego no se
haya reiniciado tras actualizar, que es cuando lee los archivos guardados nuevos)

## Protocol.lua

### Qué hay en el archivo

Guild Union Reduce - sin modo prueba (/gu prueba): servía para probar el addon sin hermandad, con
miembros inventados en el panel viejo. En ReduceClean se quita; estas funciones quedan para quien
todavía las llama.

## Perf.lua

### Qué hay en el archivo

Guild Union - medidor de tirones dentro del juego (/gu perf)
Apagado no cuesta nada: no envuelve nada ni tiene OnUpdate. Encendido (/gu perf on) mide cada
llamada de HU:SafeCall (eventos, temporizadores, inicio) y cada fotograma.

## Popup.lua

### `HU.Dialogs = {}`

Antes usábamos las ventanas del juego (StaticPopup). Tocar esas ventanas desde un addon
"contamina" las del propio juego, y al darle a "Salir del juego" o "Desconectar" el juego
bloqueaba la acción y pedía desactivar el addon. Ahora usamos ventanas nuestras con
las mismas opciones (text, button1, button2, hasEditBox, OnAccept, OnCancel, timeout...).

### Actualización IMPORTANTE (HU.mustUpdate, lo pone OnHello solo si a…

Actualización IMPORTANTE (HU.mustUpdate, lo pone OnHello solo si alguien de confianza trae una
HU.MIN_VERSION más nueva que mi versión): franja roja fija encima del panel, sin botón para cerrarla,
y línea roja en el chat al saberlo y cada 30 min (nunca en combate ni dentro de mazmorra o banda).
Sin ventana (Jorge, 07/11).
Del mensaje solo se usan los números de la versión.

### `HU:SetGuildMin`

La versión mínima de la Información de MI hermandad (Config.lua). Con mi versión por debajo, el addon
no manda nada (ni mensajes del addon, ni reenvío al canal, ni respaldo); el /g normal del juego sigue.
Se quita sola al actualizar o si el maestro baja o borra la línea.

### `local MUST_TTL = 7 * 86400`

(lo guardado: sigue mientras mi versión sea más vieja que esa; al actualizar, se borra solo)
(la franja del panel es fija hasta actualizar; lo que se repite cada 30 min es la línea del chat)
(db.mustUpdate = { v = versión, t = cuándo lo dijo un oficial por última vez }: caduca a los 7 días)

## Orders.lua

### Qué hay en el archivo

Guild Union - órdenes de hermandad (/ginvite, /gpromote, /gdemote, /gremove), por dos caminos.
Quien las pide: `HU:RunOrders(job)` (el menú de rango y «Echar» de la lista, vía `HU:TypeLines`, y
«Aceptar» de «Peticiones de oficiales»); `job = { title, text, lines, onDone(hechas), onLine(línea) }`.
Si hay otra lista a medias, la nueva espera su turno.

**Con el botón: echar, subir y bajar de rango.** En Forever /gremove, /gpromote y /gdemote son
órdenes seguras: el juego las registra en `SecureCmdList` (`CheckAddSecureSlashCommand` en
Blizzard_ChatFrameBase/Shared/SlashCommands.lua, como /cast o /target). Un botón seguro
(`SecureActionButtonTemplate`, type `macro`, macrotext con las órdenes) las lanza con tu clic, igual que
una macro tuya: es lo que hacen los addons de gestión de hermandad (Guild Roster Manager, con su
macro). Probado en Forever el 23/11: echa. Una ventanita pregunta como las del juego, sin enseñar las
órdenes: «¿Seguro que quieres echar a Ana de la hermandad?», «… subir a Ana 2 rangos?», con varias
personas los nombres debajo; quien pide las órdenes puede traer su pregunta (`job.ask`, `job.list`:
el cambio de rango dice el rango nuevo). «Sí» es el botón seguro y lanza todas de un clic; «No» no
lanza nada. No se puede quitar la ventanita: el juego solo deja lanzarlas desde un botón seguro
pulsado por ti, y el clic derecho o la ficha no pueden serlo (con la ficha se podría, pero echaría
sin preguntar).
- El botón lanza al soltar (atributo `useOnKeyDown = false`, que `SecureActionButton_OnClick` mira antes
  que la opción ActionButtonUseKeyDown) y se registra al pulsar y al soltar (`AnyDown`, `AnyUp`): si el
  juego usara la opción, lanzaría igual una sola vez. Con solo `AnyUp` y la opción puesta, no haría nada.
- Tras el clic se esperan 1,5 s: si el juego avisa de un bloqueo (MACRO_ACTION_BLOCKED/FORBIDDEN, o
  ADDON_ACTION_BLOCKED/FORBIDDEN con nuestro nombre), se pasa a copiar y pegar con las mismas órdenes
  y el botón no se vuelve a usar hasta /reload. Si no avisa, se dan por hechas.
- Combate: el botón no se puede preparar, ni la ventanita mover o cerrar. Se esconde en
  PLAYER_REGEN_DISABLED (lo último que se puede hacer antes) y vuelve en PLAYER_REGEN_ENABLED; lo
  pedido en combate se pregunta al salir.

**Copiar y pegar: /ginvite y lo demás.** /ginvite no es segura (`CheckAddSlashCommand`): con una
macro, el juego la bloquea («solo la interfaz de Blizzard», probado en Forever el 5/11). Ni un addon
ni una macro pueden invitar; tú sí, escribiéndolo. Y si el addon escribe en la caja del chat, el juego
bloquea esas órdenes hasta /reload. La ventana te deja cada orden seleccionada para copiarla:
  Ctrl+C → Intro (abre el chat) → Ctrl+V → Intro
Al enviarla (tu segundo Intro) pasa sola a la siguiente; si el juego contesta en el chat
(«Has invitado a…», «no se encuentra…»), también. Si no, botón «Siguiente». Esto solo vale con la
ventana abierta: con el botón, las respuestas del chat no mueven nada.
El addon solo MIRA la caja del chat: nunca escribe en ella.

### `Norm`

Tu segundo Intro (el que envía la orden en el chat): si lo enviado es la orden de la ventana,
se pasa a la siguiente. El addon solo MIRA la caja del chat (lee el texto y se entera del
Intro, después de que Blizzard haya hecho lo suyo); nunca escribe en ella.

## Config.lua

### `HU.ADDON_TITLE = "Guild Union"`

Formato (una directiva por línea, en la Información de hermandad de CADA hermandad):

GU:c:NombreCanal:contraseña        canal común (la contraseña es opcional)
GU:g:Nombre Hermandad:ETIQ         una línea por hermandad, incluida la propia

Chat de oficiales (en la nota de oficial de cualquier miembro, normalmente el maestro):

GU:o:CanalOficiales:contraseña

### `HU.ParseChannelNote`

GU:c:Canal:clave en una nota de oficial (así la contraseña no la ve cualquiera)
(canal y clave solo letras y números. Si detrás viene algo pegado que no es un espacio, por
ejemplo «GU:c:Canal:clave,120» porque EPGP escribió al lado, la línea no vale: devuelve
nil, nil, true para que no se reparta una clave equivocada)

### `Doubt`

Un oficial de WLP vio en rojo «Falta al menos una línea GU:g» y «Tu hermandad no aparece» justo tras
cambiar de zona, con la Información de hermandad bien escrita (11/11). El juego puede dar la Información
vacía o a medias un momento; fuera de los primeros 45 s tras entrar eso se tomaba por bueno, y si quedaba
alguna línea suelta de la comunidad (la del título, de las notas repartidas) salía el error.
Ahora, si ya había una configuración buena y la lectura nueva la deja sin hermandades o sin la mía, no se
aplica: se pide la lista de hermandad al servidor (`RequestRoster`) y se vuelve a mirar. Solo se cree si
han pasado `DOUBT_MIN` s **y** el servidor ha entregado la lista otra vez (`rosterVersion` ha subido) y la
lectura sigue igual; o a los `DOUBT_MAX` s, por si el servidor no contesta. Mientras, sigue valiendo la
configuración anterior. Si el maestro quita de verdad la hermandad de la comunidad, se nota unos 25 s
más tarde que antes.

### `HU:QuickConfig`

Arranque rápido: al entrar, el juego tarda unos segundos en dar la Información de hermandad y la
lista. Con la última configuración buena de este personaje (de su misma hermandad) se entra al
canal al momento; cuando llega la de verdad, RefreshConfig la sustituye.

### en `HU:QuickConfig`: `local gname = GetGuildInfo("player")`

(si el juego ya dice la hermandad y no es la de entonces, no vale. Si es la misma, vale
aunque sea vieja: EPGP y parecidos pueden haber borrado la línea GU:c de la nota de oficial
y entonces es lo único que queda; si aún no lo dice, solo la de menos de 7 días)

### Quién es oficial: por permisos (ReduceClean-40)

`HU:RankRole(tag, rango)`: el rango 0 es el maestro. Para los demás, en este orden:
1. Línea `GU:r:ETIQ:N` en la Información (a mano): oficiales del 1 al N. Si está, manda.
2. Rangos con permiso de oficial (`HU:OfficerRanksOf`):
   * **mi hermandad:** los rangos con la casilla «Oficial» marcada en Control de hermandad
     (`C_GuildInfo.GuildControlGetRankFlags(rango + 1)[22]`; el 22 es la casilla `OfficerCheckbox`
     de `Blizzard_GuildControlUI`). Se lee como mucho cada 30 s y al llegar `GUILD_RANKS_UPDATE`;
     se guarda (`db.myOfficerRanks`) por si un día no se puede leer.
   * **otras hermandades:** no se pueden ver sus permisos. Su enlace los manda detrás de los
     nombres de los rangos: `RN~ETIQ~nombres~1,2` («0» = solo el maestro; vacío = no se saben). Valen
     lo mismo que los rangos de su lista, que trae el mismo enlace (mismas reglas: `REMOTE_DATA`,
     `TAG_FIELD`). Se guardan (`db.officerRanks`). Llegan con la lista entera: si una hermandad
     cambia los permisos, las demás lo ven en la siguiente lista entera.
3. Sin saberlo (versión vieja que no los manda, o permisos sin leer): como antes, solo el rango 1.
Un rango sin la casilla Oficial (p. ej. «Castigado») nunca cuenta, esté donde esté.
`HU:OfficerRanksNote()`: la línea del asistente (paso 8) con los rangos que cuentan.
Pendiente de ver en el juego: si un raso puede leer `GuildControlGetRankFlags` (si no, usa lo
guardado o el rango 1).

maestro: corona; admin: dos espadas cruzadas en rojo; oficial: las espadas normales. Admin es el
rango de oficial más alto bajo el maestro, y solo cuando la hermandad tiene más de un rango de
oficial (`HU:IsAdminRank`; con `GU:r:ETIQ:N`, el rango 1 si N ≥ 2). Es solo para pintar
(`HU:RoleOf` devuelve "admin"): los permisos siguen saliendo de `HU:RankRole`, que no los distingue.
Hasta la copia 75 el rojo marcaba a los moderadores del canal; se quitó (Jorge, 12/11). Se pinta en
dos sitios: la línea del chat (`FormatLineParts`) y la lista de oficiales conectados (BlizzTab.lua)
(un poco más grandes y bajadas 1 px, para que queden centradas con el texto; las espadas se
recortan un poco para que no se vea el borde de la imagen)

### `local rankMemo, rankMemoN, RANK_MEMO_SECS = {}, 0, 5`

Pone la corona o las espadas en una textura (las filas de la lista)
Rango de alguien a partir de las listas que tenemos
(cada línea del chat lo pide para el icono, y con una lista de otra hermandad sin índice se
recorrían sus 1.000 miembros uno a uno: una sola línea llegaba a 3 ms. Se recuerda 5 s)

## Channel.lua

### Orden de los canales: `HU:FixChannelOrder` (ReduceClean-36)

Si el nuestro está delante de un canal del juego (General, Comercio…), se cambia de sitio con el
primero de ellos que va detrás (`C_ChatInfo.SwapChatChannelsByChannelIndex`). Un cambio cada vez
y como mucho uno cada 0,5 s; en el caso normal (nuestro /1, General /2) basta uno.
- **Solo funciona desde algo que hace el jugador.** Comprobado por Jorge el 10/11: desde un
  temporizador no hace nada (ni da error); con `/run` directo sí. Por eso se llama desde
  `GLOBAL_MOUSE_DOWN` (cualquier clic) y al abrir el chat con Intro (`ChatTabs.lua`, gancho a
  `ChatFrameUtil.OpenChat`).
- Los clics **solo se escuchan mientras el orden está mal** (`HU:WatchChannelOrder`, marco
  propio `orderFrame`): se mira cuando el juego avisa de cambios en los canales
  (`CHANNEL_UI_UPDATE`, `CHAT_MSG_CHANNEL_NOTICE`) y medio segundo después de cada cambio de
  sitio; con el orden bien, se deja de escuchar `GLOBAL_MOUSE_DOWN`.
- Hasta la 35, `MoveChannelHigh` lo intentaba 1 s después de entrar o de unirse al canal: en el
  juego no hacía nada, y el nuestro se quedaba con el /1 si entraba cuando no estaba el General
  (mazmorra, cambio de carril…). El juego recuerda ese orden al volver a entrar.

### en `HU:ApplyChannels`: `local settled = (self.cfg ~= nil and not self.cfg.quick) or (GetTime() - (HU.…`

(al entrar al juego, la hermandad tarda en cargar: no se sale de nada los primeros 30 s
si aún no hay configuración)
(con la configuración guardada del arranque rápido tampoco: aún no se sabe si sigues siendo
oficial, y se saldría del canal de oficiales para volver a entrar al poco)

### `local rosterSel, rosterDirty = {}, {}`

La lista de miembros de un canal se le pide al juego con la POSICIÓN del canal en la ventana
Social > Chat (la de GetChannelDisplayInfo), no con su número del chat (/6). En Classic solían
coincidir; en el cliente moderno (Forever, Retail) no, y se leía otro canal: el Comercio, con
1.100 personas y sin dueño, que es lo que salía en «En el canal» y en la guardia.
Devuelve: posición para GetChannelRosterInfo, cuántos hay, la función de lectura y el número del chat.
El juego solo carga la lista del canal seleccionado en esa ventana: se selecciona (sin abrirla),
como mucho cada 30 s; si aún no está cargada, la lectura sale vacía y se repite en la vuelta siguiente.

### `HU:NeedsChannelList`

¿Necesito leer la lista entera del canal por mi cuenta? Solo el enlace (busca moderadores a los
que saludar) y quien es o puede ser moderador: los maestros y oficiales, a los que el propietario
hace moderadores, y quien ya sabe que lo es (la guardia). Con miles en el canal, que la leyeran
todos cada 2 minutos era el mayor gasto del servidor (auditoría de 5.000, E2).

### en `HU:ChannelRoster`: `local cf = ChannelFrame`

(con la ventana de canales de Blizzard abierta no se le cambia el canal que mira: si mira
el nuestro se lee tal cual; si mira otro, esta vez no se lee. Cerrada, al abrirla vuelve
ella sola al que tenía)

### `HU:OurChannelKind`

¿De qué canal mío viene un mensaje de addon? (localID y channelName son los argumentos 7 y 8 de
CHAT_MSG_ADDON). Devuelve el tipo (main, off, x:Nombre), true si el cliente no dice de qué canal
es (no se puede comprobar), o nil si es de un canal que no es nuestro (el de otro addon, el
comercio...).

### `local needsT, needsV = -999, false`

entradas y salidas del canal: solo las usa quien lee la lista del canal (enlace, oficiales,
moderadores: la guardia). Los demás no hacen nada con ellas (escala2); las listas no dependen de esto.
(con miles entrando a la vez, la respuesta se guarda 1 s: IsRelay recorre la hermandad)

### en `HU:Forward`: `local quick = self.cfg and self.cfg.quick`

(recién entrado con la configuración guardada, el juego aún puede no dar la hermandad ni la
lista: vale la hermandad guardada, y la lista se mira en cuanto llega)
(sin la lista aún, también vale si el propio juego ya dice mi hermandad: al entrar la
lista tarda, y mientras tanto el /g no salía)

### Si el texto no sale por el canal. En Forever, lo oculto del addon p…

Si el texto no sale por el canal. En Forever, lo oculto del addon por un canal el juego lo acepta
pero no se lo entrega a nadie (Olympus midió 0 de 123): el respaldo ya no va por el canal sino
por susurro a un contacto de cada otra hermandad (CW), que lo reparte a la suya por GUILD (CG).
El chat de oficiales va por susurro directo a los oficiales conectados de las otras.
Si el juego bloquea escribir en el canal, o mi propia línea no vuelve (el eco, como Olympus), se
usa el respaldo para esa línea y para las de los 5 minutos siguientes; luego se vuelve a probar
el canal. Nunca se guarda para siempre (antes, un solo bloqueo lo dejaba así en toda la cuenta).

### `local CarriedByOther -- (copia 150: se define junto a Duplicate, más abajo)`

Formatos:  CW~canal~autor~[ETIQ] msg  (susurro a un contacto de otra hermandad)
           CF~canal~[ETIQ] msg        (a mi hermandad: «repartidlo»; cada ayudante del enlace
                                       susurra a las hermandades que le tocan, como con las listas)
Una línea son tantos susurros como otras hermandades, y el juego deja ~10 de golpe y luego 1 por
segundo: con pocas hermandades los manda el autor; con más, se reparten entre el equipo del enlace.

### en `orden CW`: `if not self:MemberOf(sender, tag) then`

(quien lo trae tiene que ser de esa hermandad, si ya tengo su lista; el autor lo mira
OnUnionChat)
(como en OnUnionChat: solo la lista COMPLETA reciente basta para rechazar; la de conectados
llega a trozos y en un relevo se queda a medias, y se tiraba el respaldo de su enlace de
verdad; banco eco-2, s 815. Con ella sola, solo se rechaza a quien la guardia ya pilló)

### en `orden CW`: `local inner = line:match("^%[%w+:E%] ([^:]+): ")`

(el tope es por quien lo trae y autor: un compañero que reparte lo de toda su hermandad
no se queda frenado por lo que escriben los demás)
(en una línea de eco [ETIQ:E] Autor: el autor de verdad va dentro: el tope es por él)

### `HU:RegisterMessage("CG", { fields = { "chan", "author", "line*" }, queue = "c…`

CG~canal~autor~[ETIQ] mensaje : por GUILD, de un compañero que lo recibió por susurro
(vale de cualquier compañero que esté en la lista de mi hermandad, no solo del enlace: el
respaldo tiene que ir aunque el contacto elegido no sea el enlace. A cambio, tope por
remitente, y cada línea mostrada queda en el registro con quién la reenvió)

### Carriles del canal (lo que le pasó a Olympus la noche del lanzamie…

Carriles del canal (lo que le pasó a Olympus la noche del lanzamiento de Forever): el juego puede
empezar a rechazar todo lo que va a un canal («canal no válido») aunque sigas dentro, y aceptar
cualquier otro. Tras LANE_AFTER rechazos seguidos, el addon se pasa solo al canal siguiente
(Nombre1, Nombre2… hasta LANE_MAX) con la misma contraseña; como les pasa a todos, se vuelven a
encontrar allí sin que nadie escriba nada. Se recuerda para el próximo /reload, y el enlace lo
dice en su saludo para que su hermandad le siga.

### `HU:LaneLock`

Estado del carril de la comunidad: { lane, gen, t }. Se guarda en la cuenta, por canal de la
comunidad (lo comparten los alts de esa comunidad, no los de otra). db.chanLane, por personaje,
queda como copia para la 5.4.7 y como punto de partida al migrar.

### Otro dice en qué carril está la comunidad: se sigue el más alto,…

Otro dice en qué carril está la comunidad: se sigue el más alto, pero solo si lo dice alguien
«fuerte» (el enlace de mi hermandad, el enlace conocido de otra, o un oficial). Lo que diga
cualquier otro solo hace sondear mi canal: me muevo si a mí también me rechazan, como con LN~n
(si no, cualquiera con la contraseña mandaba a toda la comunidad al carril 9 con un susurro).

### en `HU:OfferLane`: `if strong == "contact" then`

(el contacto de otra hermandad, sin comprobar: solo el enlace de mi hermandad le hace caso, y solo
para subir UN carril con la misma generación, como mucho cada LANE_CONTACT_GAP. Un intruso con la
contraseña, como mucho, sube un carril cada 10 min, y a las 6 h todos vuelven al principal)

### `HU:ProbeLane`

Sondeo: un mensaje pequeño al canal (n, si se pide más); si el juego lo rechaza, ChannelSendResult
manda los que faltan para los 3 rechazos y cambia de carril. Es lo único oculto que va por el canal:
en Forever no le llega a nadie, pero no hace falta, solo se mira lo que contesta el juego (el error 7)

### en `tarea carril-sondeo`: `if HU.wasRelay and GetTime() - lastChannelSend > LANE_PROBE_EVERY - 0.5 and H…`

(con wasRelay, lo que salió en mi último saludo, y no IsRelay: este repasa a todos los
compañeros, ~1,8 ms con 500. Un sondeo de más de un enlace antiguo no hace daño. El sondeo,
en la imagen siguiente)

### `if C_Club and C_Club.SendMessage and C_Club.GetGuildClubId then`

Retail: lo que se escribe en el chat de la ventana de la hermandad del juego (Comunidades) no
pasa por SendChatMessage. Se trata igual que el /g: pasa a las demás hermandades y, si estás
silenciado o vetado, no le llega a nadie con el addon (en el chat normal).

### `local KIND_SHORT = { main = "H", off = "O" }`

Igual, pero por separado: la cabecera (canal, hermandad, nombre) y el mensaje
compact (chat del panel): sin el reino, y el canal en corto ([H], [O]) o sin él
(showKind = false en las pestañas de un solo chat, donde ya se sabe cuál es)

### `local customByCode, customMaxLen, customFirstPat`

Enlaces web (https://..., www....): se vuelven clicables en el panel del addon.
El juego no puede abrir el navegador, así que al hacer clic sale una ventana para copiarlo.
Solo se cambian si van sueltos (al principio o tras un espacio, y seguidos de espacio o fin),
para no tocar horas como 10:30 ni enlaces.
emoticonos de la comunidad: código -> ruta (caché; se rehace cuando cambian)

### en `HU:Emotes`: `if not msg:find("|", 1, true) then`

(atajo: casi ningún mensaje lleva emoticonos. Sin códigos «|», sin ninguno de los emoticonos
del addon escrito tal cual y sin ninguna letra con la que empiece uno de la comunidad, sale
tal cual. Antes bastaba una «x» o una «B» en el mensaje, que casi siempre hay, para recorrerlo
letra a letra)

### `local ENTRY_IDX = { t = 1, k = 2, tag = 3, a = 4, m = 5, g = 6, hl = 7, late …`

Entradas del chat guardado en formato compacto: lista por posiciones en vez de campos con
nombre (ocupa la mitad). La metatabla deja leer y escribir e.t, e.a... igual que antes, y las
entradas viejas (con nombres) siguen valiendo tal cual.

### `local held = {}`

Todo lo que ha escrito un personaje (busca por nombre, con o sin reino)
Quién ha escrito más (para elegir de una lista)
Un mensaje del chat unido, llegue por el canal (CHAT_MSG_CHANNEL) o como mensaje oculto del addon
(cuando el juego no deja al que escribe mandarlo al canal: ver Forward)
Mensajes retenidos de quien escribe con mi etiqueta sin estar comprobado (10 por persona, 90 s)

### en `HU:OnUnionChat`: `if tag == HU.myTag and not HU:MemberOf(author, tag) and not (HU:GuildVerified…`

seguridad: quien escribe tiene que estar de verdad en la hermandad de la etiqueta
(si aún no sé nada de esa hermandad, acabo de entrar: se acepta mientras llegan sus listas;
el canal tiene contraseña y la guardia echa a los intrusos)
Con la lista COMPLETA de esa hermandad (también desconectados), no estar en ella basta para
rechazar. Con solo la de conectados (comunidad grande: no se reparten listas completas) no:
esa lista llega a trozos y le faltan los recién conectados, y se perdían mensajes de miembros
de verdad (banco 18:22: 173 de 791). Ahí solo se rechaza a quien la guardia ya confirmó como
intruso, o a quien su hermandad reclamó como suyo con otra etiqueta.
con MI etiqueta y no es de mi hermandad: se hace pasar por nosotros

### `local chanQ, chanHead, chanTail, chanBusy = {}, 1, 0, false`

Fluidez (meta: ningún fotograma de más de 1,85 ms): las líneas del canal van a una cola que se
procesa con un tope de tiempo por fotograma. La primera sale al momento; si llegan varias en el
mismo fotograma, las demás salen en los siguientes, en orden. Y guardarlas en el historial (lo que
no se ve) va detrás, en otro paso. Nada se pierde ni se repite: solo se reparte.

### `local CHAN_FRAME_MS = 0.8`

(el tope es por FOTOGRAMA, no por llamada: las líneas suelen llegar de una en una, cada una con
la cola vacía, y cada llamada empezaba de cero; varias en el mismo fotograma pasaban de 1,85 ms.
Banco, 3×1000 de la 1145: 32 fotogramas así. Ahora se suma lo gastado en el fotograma y, al
llegar al tope, lo que queda espera al siguiente)

### `local moved = {}`

El juego da a cada canal el primer número libre (/4, /5...). Para no quitarle el sitio
a un canal del juego, se intenta mover el nuestro al número libre más alto.
(como mucho dos veces por canal y sesión, y con un minuto entre una y otra: si otro addon
que ordena canales lo vuelve a mover, no nos lo quitamos el uno al otro sin parar)

### `HU.After(0.3, function()`

(hasta la 35; sustituido por `HU:FixChannelOrder`, ver más abajo)

## ChatPaint.lua

### Qué hay en el archivo

Guild Union - panel: base (temas, piezas comunes, menús, fichas) y ventana principal
El resto del panel está en: UIMembers (Miembros), UIChat (chats), UIOfficers (Oficiales),
UIInfo (información, silenciar, recetas) y UIWindows (configuración y ventanas sueltas).

## PratBridge.lua

### Qué hay en el archivo

Guild Union Reduce - sin el panel grande: quitados UIMembers, UIChat, UIOfficers y UIInfo.
El resto del addon todavía llama a algunas de sus funciones (repintar el chat del panel, la lista,
el mensaje fijado...). Aquí quedan como «no hacer nada», para que no den error. Todo lo que se ve
está ahora en la ventana de hermandad de Blizzard (BlizzTab.lua) y en el chat normal del juego.

## WMPanel.lua

### Qué hay en el archivo

Rellenar el nombre de una mención con Tab. Pieza suelta: si falla o se quita del `.toc`, lo demás sigue igual.
  * Solo mira la caja de escribir del juego cuando se habla por hermandad u oficiales y el texto no
    empieza por «/» (el juego revisa los textos con «/» cada vez que cambian; ahí no se escribe nada).
  * Al cambiar el texto busca el último «@» antes del cursor y lo que va detrás (2 letras o más, como
    mucho un espacio). Con eso arma la lista: mi hermandad (`HU.roster`), lo que se sabe de las otras
    (`HU.remoteRoster`) y quien ha hablado en la última hora (`HU.EachRecentSpeaker`, Channel.lua).
    Sin mayúsculas ni acentos; primero los conectados.
  * Encima de la caja sale una franja con los tres primeros. No es una lista que se pulse: solo avisa.
  * Tab pone el nombre completo («@Nombre Apellido »). Otro Tab sin tocar nada cambia al siguiente.
  * El Tab entra por `ChatEdit_CustomTabPressed`, el enganche que deja el juego para los addons (lo
    llama con securecall). Si otro addon lo tenía puesto, se le llama cuando aquí no hay nada que rellenar.

## Comm.lua

### `HU.guildPeers = {}     -- [clave] = { name, last, mod, ver }  usuarios del ad…`

Mensajes de addon (prefijo HUNI, campos separados por "~"):

HI~ver~tag~mod~relay        saludo (por GUILD a la hermandad o por WHISPER a otra hermandad)
HR~ver~tag~mod~relay        respuesta a un saludo por susurro
PL~TAG:Nombre,TAG:Nombre    el enlace de la hermandad comparte los contactos que conoce
RB~tag~seq~total~online~parte~partes~datos     lista de miembros conectados (troceada)
Q~nombre,nombre             la guardia pregunta a un moderador si esos jugadores son de su hermandad
A~nombre,nombre             respuesta: los que sí son de su hermandad

En Classic los addons no pueden enviar mensajes a canales personalizados,
así que entre hermandades se usan susurros entre un "enlace" de cada una.

### `local NO_KEYS = {}`

Índice por etiqueta: con miles de contactos, cada BestPeer/KnownRelay/MarkRelay los recorría todos
(auditoría de 5.000, E6). Quien lo usa comprueba que la clave sigue y que es de esa etiqueta, así que
quitar a alguien no lo deja mal.
  * el que entra nuevo se añade a su lista en el momento; si entra sin etiqueta, se apunta y se añade en
    cuanto se le pone (antes se esperaba a rehacer el índice: con 30 s, las listas completas tardaban
    170 s en vez de 75);
  * cada RK.EVERY s se rehace entero (por quien cambia de etiqueta o se sustituye por otra ficha), pero
    POR TROZOS de RK.MS por fotograma, recorriendo la lista de claves en el orden en que entraron; mientras,
    contesta el índice de antes. Antes se rehacía de golpe, recorriendo a todos, en la llamada de quien lo
    pedía primero (RC, el envío a cada hermandad): hasta 4 ms.
(todo en una tabla: la parte principal del archivo no puede pasar de 200 variables locales)

### `HU.ghostRoster = {}    -- [tag] = { members = {...}, t, v }`

Listas «de la última vez»: SOLO para enseñarlas en el panel, en gris, mientras llegan las de verdad.
No están en remoteRoster ni en nada que mire la confianza (MemberOf, CheckedOf, SenderKind, KnownSet,
la guardia, el relevo, PL/PH...): solo las lee UIMembers. Se quita la de cada hermandad en cuanto
llega su lista (HU.comm.RB) o a los GHOST_TTL s.

## Net/Transport.lua

### `local qChat, queue, mid, low = {}, {}, {}, {}`

cuatro colas, por orden de importancia (sale siempre lo de la primera que
tenga algo):
  1. el chat: silencios, vetos, chat lento, canales, mensaje fijado, emoticonos...
  2. lo normal: saludos, contactos y las listas de CONECTADOS de las otras hermandades
  3. las fichas (profesiones, rol...) y los inactivos que alguien está mirando ahora
  4. lo que no corre prisa: listas completas de miembros e inactivos en segundo plano

### `HU:Send`

urgent = true pone el mensaje delante de su cola. Devuelve false si no ha entrado en la cola.
slow = true: a la cola de poca prisa aunque la orden sea de las del chat (repasos periódicos)
fast = true: por la cola del chat, delante (conectado/desconectado de oficiales: Presence.lua)

### `HU:DropQueued`

Lo nuevo ocupa el sitio de lo viejo (idea de Olympus): una lista entera nueva para una hermandad
deja sin sentido los trozos que aún esperan de la anterior y de sus cambios, mandados al mismo
contacto de esa hermandad (aunque los trozos se repartan entre sus ayudantes; con fast, en qChat)

### en `HU:DropQueued`: `if m.gtag == tag and m.gdest == dest and m.cmd == "RB" then table.remove(q, i…`

(solo los trozos de listas enteras: los cambios (RC) se quedan. Son pequeños, aplicarlos dos veces
no hace daño y salen en orden. Si se tiraban, el cambio llegaba con la lista entera, 1-2 s tarde y
a la hermandad entera; y la segunda copia de cada cambio, la del contacto, casi nunca salía)

### en `HU.QueueTick`: `if #qChat > 0 or (#queue > 0 and #bfast == 0) then`

(si el juego cuenta los dos prefijos juntos, lo que sale primero se lleva el sitio: antes
salían siempre los datos grandes, y unos inactivos largos retrasaban 15 s un silencio.
Ahora: chat y silencios, luego los cambios de las listas, luego lo normal, y lo grande al final)

## Domain/Trust.lua

### `local VOUCH_TTL = 900       -- lo que dura el aviso de un enlace comprobado (…`

Quién puede mandarme la lista de conectados de otra hermandad, y cuánto me fío de ella.
Estado de la lista de cada hermandad (r.state):
  "b" arranque: se ve, pero nadie cuenta como miembro (weak) ni da rango
  "m" miembros: cuentan como miembros; el rango se guarda aparte (rankHidden) y no se usa
  "p" rangos provisionales (r.pBy = "old": dos cuentas, una conocida; "time": solo por tiempo)
  "c" confirmada: la ha mandado o confirmado un contacto comprobado

### `local OLD_FROM_TIME = false`

(las dos cuentas que respaldaron una lista que llegó a rangos solo por tiempo se guardan como antiguas.
Apagado: con dos cuentas y 30 min, un intruso se confirmaba él solo. En una comunidad nueva, el ancla
es «/gu confirmar ETIQ» de un oficial)

### `HU:AnchorValid`

Ancla de confianza de cada hermandad: el maestro (u oficial) que aceptó la invitación a la comunidad
(el remitente lo pone el juego), o quien invitó a la mía. Su lista vale como confirmada al momento.
Vale mientras no tenga la lista de esa hermandad confirmada o, si la tengo, mientras salga en ella de
maestro u oficial; si sale con otro rango (lo han cambiado o echado), deja de valer para siempre.
Lo guarda Community.lua en db.anchors[etiq] = { name, dead }.

### `HU:SenderKind`

Con qué me fío de quien me susurra una lista de esa hermandad: "vouched" (lo nombró su enlace
comprobado), "peer" (contacto comprobado), "member" (sale en mi lista actual), "old" (contacto de
antes, sin comprobar), "boot" (salió en una presentación del canal) o nil. Ya no vale haber escrito
en el chat con su etiqueta ni un saludo HI.

### en `HU:DecideRoster`: `if conflict and not self:AnchorValid(tag, k) then`

(un contacto comprobado que contradice la que tengo sin confirmar: disputa; si la tengo
confirmada de otro, también: que lo vean los oficiales. El ancla de esa hermandad no: la
suya manda)

### en `HU:AfterRosterDecided`: `if HU.MarkRelay and k then`

(enlace PROVISIONAL: lo que va para esa hermandad se le manda a quien me mandó la lista, pero sin
«dicho por él», así que no se cuenta a otros con PL/PH ni nombra ayudantes)
(pero no si su enlace se ha presentado él mismo hace poco y es otro: la segunda opinión le quitaba
la marca, mi enlace dejaba de contarlo a mi hermandad (PL), nadie se fiaba de él y la lista no se
confirmaba nunca; clave-reloj, G03)

### en `HU:ConfirmRoster`: `r.updated = GetTime()`

(a toda mi hermandad, la confirme quien la confirme: SetRosterState solo la reparte si soy el
enlace o llevo esa hermandad. Un oficial cuenta como forwarder, así que la toman con su estado
"c". Como recién hecha (edad 0), para que nadie la descarte por tener una copia más nueva)

### `HU:OnStart(function()`

Al entrar: se espera a que el juego meta sus canales (como mucho 15 s) y se entra al nuestro (con
la configuración guardada si la de la hermandad aún no ha llegado).

### `HU:SafePeer`

El mejor contacto, solo si me fío de él: para lo que lleva contraseñas (canal y canales extra). Antes
iba al mejor contacto, que el primer día podía ser un intruso que se decía enlace (90-125 s en el
banco): se llevaba la contraseña nueva aunque la acabaran de cambiar para echarle

### en `HU:BestPeer`: `if m and m.t == now and m.p and self.remote[m.p.name:lower()] == m.p then ret…`

(si se ha quitado al elegido en este mismo fotograma, p. ej. «no está conectado», se busca otro)
(solo dentro del mismo fotograma: el mejor contacto depende de a quién se oyó por última vez, y al
llegar un aviso de carril su remitente pasa a ser el mejor. Con 1 s se devolvía el de antes,
HU.LaneContact no daba por bueno el aviso y la otra hermandad no seguía el carril hasta el saludo
siguiente: 7b semilla 3, chat > 1 s 51 %, carril nuevo a los 628 s)

### en `HU:BestPeerCalc`: `local rr = self.remoteRoster[tag]`

(con lista buena de esa hermandad, quien no sale en ella va detrás de todos los que sí. El
«soy moderador» del saludo ya no cuenta: lo decía cualquiera del canal (nadie lo comprueba) y
se quedaba con lo que iba para esa hermandad y con las preguntas de la guardia)

## Net/Relay.lua

### `SamplePerf`

Quién es el enlace: primero los oficiales y el maestro (si su conexión va bien), y entre
iguales el de mejor ping y más fotogramas por segundo (menos cargado el ordenador). Cada
uno dice su puntuación en el saludo; con la misma puntuación, el primero por nombre.

Puntos (Clean-19): ping sin escalones (30 − ping/5, mínimo 0); estabilidad: saltos del ping
(media de cuánto cambia entre medidas de 30 s: < 5 ms +6, < 15 +4, < 40 +2), tiempo conectado
desde la entrada real al juego (`cdb.sessionStart`, un /reload no lo pone a cero: > 10 min +2,
> 30 +4, > 1 h +6) y −10 por cada otra entrada al juego en la última hora, como mucho −30
(`cdb.logins`, solo con `isInitialLogin` de PLAYER_ENTERING_WORLD). Salir y entrar a propósito
también cuenta. Máximo sin oficial: 30 + 6 + 3 + 6 + 6 + 6 = 57.

### `local AFK_AFTER, AFK_PENALTY, BUSY_PENALTY = 180, 40, 150`

Ocupado: en una banda, un campo de batalla o una arena (resta 150), o ausente (AFK) desde hace
un rato (resta 40). Devuelve si lo está y cuánto resta.
(el AFK automático del juego salta a los 5 min sin moverse: con 150 el enlace cambiaba cada vez
que un oficial se quedaba quieto y volvía al moverse, y cada cambio era una lista nueva para las
otras hermandades. Con 40, otro oficial le releva; un raso no)
(desde la 39, `UnitIsAFK` e `IsResting` pasan por `HU.SafeBool`: en combate o mazmorra el juego
puede darlos como valor secreto y usarlos directamente daba error cada 15 s; secreto = «no»)

### en `HU:RelayScore`: `if IsResting and HU.SafeBool(IsResting(), false) then`

en zona de descanso (ciudad, posada) se sale del juego al momento y no da tiempo a pasar el puesto:
mejor que sea enlace otro. Solo tras 60 s seguidos (entrar y salir de una ciudad no cambia el enlace);
resta 20, más que la ventaja de 15 del enlace actual. Es resta y no suma: la puntuación tiene tope
(SaneScore, 199) y una suma se perdía en los mejores

### `HU:SaneScore`

La puntuación que dice un compañero, dentro de lo posible: como mucho 199, y más de 99 solo si
es oficial de verdad en la lista del juego (Clean-19: antes 149 y 49; sin oficial ya se llega a 57). Antes valía cualquier número (1e309 da infinito)
y quien quisiera se quedaba con el enlace y con lo que llega de las otras hermandades.

### en `HU:MyHelpersCalc`: `local current = {}`

(los ayudantes, en el mismo orden que el enlace: los mejores primero; se buscan los mejores
sin ordenar a los cientos de compañeros)
(los que ya son ayudantes tienen ventaja, como el enlace: si no, se turnaban por un poco de ping
o de fotogramas, y cada cambio era una lista nueva para todas las hermandades)
(por clave completa: antes se acortaba el nombre de cada uno de los cientos de compañeros)

### `HU:InheritHelpers`

Acabo de pasar a ser el enlace: me quedo con los ayudantes del anterior, y con él si sigue
conectado. Así, los 2 min que ya los mantiene HelloText (helpersChangedT) no cambian. Antes
empezaba con los míos, la lista que va a las otras hermandades los quitaba y a los pocos segundos
los volvía a meter, y la otra hermandad dejaba de verlos ese rato.

### en `HU:HelloText`: `local cur = self.advertisedHelpers`

(los ayudantes no se cambian más de una vez cada 2 minutos mientras los de ahora sigan
conectados: en la entrada masiva cambiaban hasta 10 veces y cada cambio era una lista
nueva para las otras hermandades, que no se daban por completas hasta el último)

### en `HU:HelloText`: `if changed and cmd ~= "HR" then self:HelpersChangedHello() end`

(y a mi hermandad enseguida, no en el saludo de dentro de 2-5 minutos: los ayudantes van en
la lista que mandan a otras hermandades, y uno que no sabía quién había entrado mandaba una
lista entera sin él que pisaba la buena)

### `HU.LaneContact`

Contacto de otra hermandad que dice ser su enlace, sin estar comprobado: el que me toca para esa
hermandad (BestPeer) y que sale en su lista (no basta con decir que es el enlace: eso se lo pone
cada uno en su saludo; condición de Seguridad, 07/11). En Forever casi nunca se
llega a «comprobado» y, sin esto, si a una hermandad se le rompe el canal, la otra no la seguía
(ver OfferLane: con esto solo se sube un carril, y como mucho cada 10 minutos)

### `local guildHeardT -- última vez que oí un mensaje del addon de otro de mi h…`

El primero de su hermandad en entrar no espera los 30 s de prudencia para ser enlace: pregunta
«¿hay enlace?» (RQ, por GUILD) y, si al entrar en el canal no ha oído NADA de su hermandad, se hace
enlace y se presenta ya; así le llegan las listas de las otras hermandades en unos 15-20 s.
Solo contesta el enlace (no todos, como con HY). En una entrada masiva todos se oyen entre ellos
y siguen los 30 s y la elección por puntuación de siempre.

### en `HU:AloneCheck`: `for _, d in ipairs({ 12, 25 }) do HU.After(d, function() HU:AloneAskRosters()…`

(a los 12 y 25 s pido la lista a quien conozco de cada hermandad que me falte: la que me mandan
al verme llega a veces antes de que yo los haya visto en el canal, no se acepta, y su enlace no
la repetía hasta pasados 30 s. «~1» = confírmamela: vale a los 5 s)

### en `HU:BulkWhisper`: `if fast then`

(cambio pequeño: a dos de esa hermandad, por las dos vías, que tienen cupo aparte (1 mensaje por
segundo cada una). Primero a un oficial suyo con el addon: su hermandad siempre acepta lo que él
reenvía. Luego a su contacto. Con 5 copias por hermandad, un cambio eran 15-45 mensajes y a las
últimas hermandades les llegaba a los 10-40 s)
(en modo sencillo, como antes: una sola copia por la cola normal)

### en `HU:BulkWhisper`: `local g = HU.sendGroup`

(todos los trozos de un mismo envío, al mismo: si cada trozo iba a un ayudante distinto, cada uno
reenviaba a su hermandad medio envío, y como los trozos se juntan por quien los reenvía, la lista no se
completaba nunca; clave-reloj, G03)

### `HU.PEER_TTL = 700`

Soy el "enlace" de mi hermandad si mi nombre es el primero (alfabéticamente)
entre los usuarios del addon conectados de mi hermandad.
Cuánto vale un saludo de un compañero (se saluda cada 2-5 min, según lo grande que sea la hermandad)

### en `HU:IsRelay`: `if self.loginT and GetTime() - self.loginT < 30 and not self.aloneRelay then …`

(recién entrado no se es enlace: aún no se ha oído a nadie y cada uno se creía el enlace
durante unos minutos, mandaba su lista a las otras hermandades y pisaba la buena)
(salvo el primero de su hermandad en entrar: AloneCheck)

### en `HU:SeenPeer`: `if (not p.remT or GetTime() - p.remT > 60) and self:CheckedOf(name, tag) then`

(guardarlo entre sesiones: como mucho una vez por minuto por persona; antes, con cada
mensaje de chat que escribía)
(solo quien está de verdad en la lista de esa hermandad: antes bastaba con mandar una lista o
hablar con su etiqueta, y quedaba guardado como contacto de ella para siempre)

### `local sharedRelayOf, plRelayOf = {}, {}`

(de qué enlace se contó lo último: si cambia, se cuenta ya, sin esperar los 300/600 s. Si no, tras un
relevo mi hermandad no conocía al enlace nuevo de la otra hasta 5 min después; en Forever la
presentación del canal, que antes les llegaba a todos a la vez, no llega)

### `HU:KnownRelay`

El enlace de esa hermandad, solo si lo dijo él mismo hace poco. Es lo único que se cuenta a
otros: si se pasaba el "mejor contacto", alguien que solo había hablado en el canal acababa
marcado como enlace en toda la hermandad, y no contesta a las peticiones de listas.

### en `OnHello`: `local minv = f[10]`

actualización IMPORTANTE: su versión mínima es más nueva que la mía. Solo de un oficial o GM: de
mi hermandad (por su rango en mi lista) o de otra con su lista confirmada («c»). Un raso podía
mandar 99.9 y dejar a toda la comunidad con la franja para siempre (Seguridad, 07/11). Y quien la
dice tiene que tener él mismo una versión de al menos esa (si no, es un número inventado)

### en `OnHello`: `if f[7] and HU.OfferLane and ((f[8] and f[8] ~= "") or isRelay) then`

(carril de la comunidad: del enlace o de un oficial, se sigue; de cualquier otro compañero
con generación, solo hace sondear (OfferLane); sin generación (versiones anteriores),
solo cuenta el enlace, como antes)

### en `OnHello`: `if relay and not (HU:CheckedOf(sender, tag) or HU:FullPeer(sender, tag) or (H…`

(por susurro, «soy el enlace de X» solo vale de alguien de la lista de X, o avalado por X:
si no, un intruso con solo la contraseña del canal se quedaba de enlace de X, recibía lo
que iba para X y lo presentaba a mi hermandad con PL/PH. Si no cuadra, contacto normal)
(de su lista CONFIRMADA, o contacto comprobado: con una sin confirmar, el que la mandó se daría
por enlace él solo y mi hermandad lo presentaría con PL/PH como si estuviera comprobado)

### en `OnHello`: `if not (HU:RosterTrusted(tag)) and HU.BootPresented then HU.BootPresented(tag…`

(pero sin datos buenos de X vale como una presentación del canal (raSeen): solo sirve para
arrancar, con la lista como «arranque». El saludo es tan fácil de fingir como el RA, y sin
esto el enlace no aceptaba la lista de X hasta oír su RA, que puede tardar minutos)

### en `OnHello`: `if HU:CheckedOf(sender, tag) then HU:RememberPeer(sender, tag) end`

(contacto guardado = comprobado: solo si sale en la lista confirmada de su hermandad. Antes se
guardaba a cualquiera que saludara, y en su segundo saludo ya contaba como comprobado: su
«soy el enlace» se aceptaba y el PH de mi forwarder lo daba por enlace en toda mi hermandad)

### Cada enlace se presenta en el canal oculto (lo ven todos los del ad…

cada enlace se presenta en el canal oculto (lo ven todos los del addon de
todas las hermandades a la vez). Así nadie tiene que ir buscando contactos hermandad por
hermandad, que con 20 hermandades tardaba muchísimo.   "[ETIQ:R] ayudante,ayudante"

### `HU:AnnounceByWhisper`

La presentación por susurro: al enlace (o mejor contacto) de cada hermandad y a sus ayudantes,
que son quienes la usan (huella de la lista, ayudantes, arranque). Sin contacto en una hermandad,
la encuentra el saludo de RelayHelloRest. target: solo a él (contestar a otra presentación).

### `local PROV_SPAM, PROV_HOLD = 25, 75`

Enlace provisional de X (quien se presenta sin estar comprobado, cuando X no tiene enlace «dicho por
él»). Regla (decisión de ADMIN):
  1) gana el último que se presenta (en una entrada masiva el enlace cambia en segundos);
  2) salvo quien se presenta demasiado a menudo: un addon de verdad no manda RA más de una vez cada
     31 s (AnnounceRelay), así que quien manda dos con menos de PROV_SPAM s entre uno y otro no puede
     quedarse el sitio ni seguir en él durante PROV_HOLD s desde el último demasiado seguido;
  3) si tengo lista de X (aunque sea de arranque), quien sale en ella gana a quien no sale, aunque se
     haya presentado antes: un intruso no se turna con el de verdad (lo que va para X, chat incluido,
     pasa por el provisional). Sin lista de X, solo 1) y 2).
Además lo pierde quien lo tenga si me llega por susurro una lista de X de otro remitente comprobado
(miembro, contacto o avalado): ver HU.ClearProvRelay en HU.comm.RB.

### Si ya tengo la lista de esa hermandad, el que se presenta como su e…

(si ya tengo la lista de esa hermandad, el que se presenta como su enlace tiene que estar en
ella: antes cualquiera del canal se hacía pasar por el enlace de otra hermandad y recibía
lo que iba para ella)

### en `HU:OnRelayAnnounce`: `do`

(salir en una presentación del canal se apunta siempre: solo vale para arrancar, y una lista
confirmada y al día no la cambia nadie así. Si no, el enlace nuevo de una hermandad cuyo enlace se
cayó sin avisar no podía mandar su lista hasta que la mía caducara, unos 40 min)

### en `HU:OnRelayAnnounce`: `if byWhisper or self:KnownRelay(tag) then return end`

No sale en mi lista de X. Si X no tiene enlace «dicho por él» desde hace más de 900 s (el
primero de su hermandad en entrar es un raso), queda de enlace PROVISIONAL: le mando lo que va
para X, pero sin «dicho por él», sin ayudantes ni PL/PH, y sin tocar el estado de mi lista.
El primero guarda el sitio mientras siga presentándose (PROV_HOLD); otro solo se lo quita si
es un contacto guardado. Si no, un intruso con la contraseña se quedaba lo de X hablando el último.
(por susurro, nunca: sin pasar por el canal no se sabe ni si tiene la contraseña)

### en `HU:OnRelayAnnounce`: `if self:IsRelay() and (not answeredRA[pk] or GetTime() - answeredRA[pk] > 600…`

(y se le contesta como a cualquier enlace nuevo: si no, no me oía hasta mi siguiente
presentación (minutos) y no aceptaba la lista que le mando. El saludo directo llega enseguida;
la presentación del canal espera a los 30 s de prudencia)

### en `HU:OnRelayAnnounce`: `local names, hash = (msg or ""):match("^(.-)%s*#(%x+)%s*$")`

Sin datos buenos de esa hermandad, quien se presenta no es aún su enlace «dicho por él» ni nombra
ayudantes: antes, cualquiera del canal se quedaba de enlace de una hermandad sin lista. Solo
queda apuntado para arrancar (raSeen, abajo). El enlace provisional es quien me mandó la lista
de arranque (HU.comm.RB); si es él, sigue siéndolo.

### en `HU:OnRelayAnnounce`: `MarkRelay(tag, author)`

(sin enlace «dicho por él» de X: el que se presenta queda de enlace provisional con la misma
regla que arriba. Antes solo el que me había mandado la lista sin confirmar; en una entrada
masiva era el primero en presentarse, que ya no era enlace, y lo de X le seguía llegando)

### en `HU:OnRelayAnnounce`: `if hash and tag ~= self.myTag then`

huecos: si mi lista de conectados de esa hermandad no coincide con la suya dos avisos
seguidos (unos 10 minutos), me he perdido algún cambio: la pido a mi hermandad, y si
sigue igual, quien se encarga de esa hermandad la pide entera a su enlace

### en `HU:OnRelayAnnounce`: `if r.annMiss >= 2 and self:ResponsibleFor(tag)`

(fase de lanzamiento: la lista son unos nombres; si no cuadra dos veces, se le pide
entera a su enlace directamente, en vez de solo a mi hermandad, que puede tener la misma
copia incompleta. Quien se encarga de esa hermandad, para no pedirla todos)

### en `HU.comm.PH`: `local strict = not self:IsGuildForwarder(sender)`

Seguridad: de mi enlace, sus ayudantes o un oficial, como antes. De otro compañero, solo si el
enlace que nombra está en la lista de X, y de sus ayudantes solo los que también lo estén
(antes cualquier compañero nombraba enlace de X a quien quisiera, y toda la hermandad le
mandaba lo de X y le preguntaba la guardia)

### en `HU.comm.PH`: `local firm = self:CheckedOf(relay, tag) or self:FullPeer(relay, tag) or self:…`

(PH lo manda quien acaba de recibir el saludo del propio enlace: vale como dicho por él, pero
solo si yo también lo tengo por comprobado; si no, enlace sin «dicho por él», que no se cuenta
a otros ni da confianza)

### `local laneProbeT = -999`

Un compañero se ha pasado a otro carril del canal (LN~n): el enlace lo comprueba sondeando el
suyo; si también le rechazan, se mueve y lo dice en su saludo (así la hermandad no sigue a
cualquiera, solo al enlace). LP (sondeo) no hace nada al recibirse.

### en `HU.comm.LN`: `if strong == "contact" and not self:IsRelay() and self.myTag and IsInGuild()`

(el aviso de otra hermandad me llega a mí porque soy su contacto, pero solo mi enlace puede
mudar a mi hermandad: se lo paso por GUILD. Si no, no se enteraba hasta el siguiente saludo
de su enlace, a los 1-10 min, y mientras el chat entre las dos iba por el respaldo)

### `local laneAnswerT, laneAnswered, laneAnswerN = -999, {}, 0`

LQ: «¿en qué carril estás?» de otra hermandad. Contesto con mi LN por susurro (a cada uno como
mucho cada 10 s, y a todos 1 por segundo). También a quien no me ha saludado: con hermandades
grandes casi nunca me llega el saludo de quien pregunta, y entonces no contestaba

### `HU:RegisterMessage("LX")`

LX~carril~gen~hora~ETIQ~contacto: un compañero me pasa el aviso de carril del contacto de otra
hermandad. Solo el enlace le hace caso, y solo si ese contacto sale en la lista de su hermandad;
luego vale como «contacto» en OfferLane (un carril, misma generación, cada 10 min como mucho)

### en `HU.comm.PL`: `local strict = false`

Seguridad: por susurro solo lo presenta el enlace (o un ayudante u oficial) comprobado de otra
hermandad; antes valía de cualquiera que hubiera hablado en el canal, que se nombraba enlace
de X y además se lo contábamos a toda la hermandad. Por la hermandad, de mi enlace, sus
ayudantes o un oficial vale como antes; de otro compañero, solo nombres que estén en la lista
de esa hermandad (sin datos de ella, no se le hace caso).

### en `HU:HelloCycleRest`: `local modList = members and self.chanModList or {}`

los moderadores se saludan entre ellos (los necesita la guardia)
(con 20 hermandades hay muchos moderadores: a cada uno, como mucho cada 15 minutos)
(solo se recorren los moderadores, no las miles de personas del canal)

### en `HU:OnStart`: `local TAKEOVER_GAP = 45`

(acabo de pasar a ser el enlace: saludo y presentación en el canal ya, sin esperar al saludo
siguiente, que tardaba 2-5 min; mientras, la otra hermandad seguía hablando con el enlace viejo.
Como mucho uno cada TAKEOVER_GAP s, por si dos con puntuación parecida se van turnando)

### en `HU:OnStart`: `HU.After(2, function()`

primero a mi hermandad (al momento) y, si sigue faltando algo, a las otras hermandades
(a los 3 s, no a los 15: las listas tienen que estar en ≤30 s. Para que una entrada masiva no
mande cientos de NQ a la vez, cada uno espera un poco al azar, más cuanta más gente conectada:
el primero que pregunta marca la petición para todos (nqSeen) y la respuesta va por GUILD y les
sirve a todos, así que el resto ya no pregunta. Con 1.000 conectados salen unos 15 NQ)
(la gente conectada se mira a los 2 s, cuando el juego ya suele tener la lista; si aún no la
tiene, se supone que son muchos)

### en `HU:OnStart`: `for _, d in ipairs({ 2, 6 }) do HU.After(d + math.random() * 1.5, function() …`

y a los contactos guardados de cada otra hermandad, sin esperar a ser enlace (oficiales, quien está
solo, o cualquiera a sus contactos comprobados: ver AskSavedContacts). A los 2, 6 y 12 s: la lista
de la hermandad llega a los 1-3 s y, si llega sin confirmar, se confirma con el contacto

### en `HU:OnStart`: `HU.After(2, function()`

(los rasos, solo si siguen sin confirmar, con una espera al azar que crece con los conectados,
como el NQ: en una entrada masiva no salen todos a la vez y casi todos la reciben antes por GUILD)
(día a día: a los ~2-4 s y otra vez a los ~7-9 s)

## Net/RosterSync.lua

### Zonas: `HU.ZoneOut` y `HU.ZoneIn`

El nombre de la zona que da el juego (`GetGuildRosterInfo`) está en el idioma de quien lo lee: en una lista
de la unión salían unas zonas en español y otras en inglés (23/11). En las listas (RB, RC, ML) la zona viaja
como el número de su mapa, «@1429»: `ZoneOut` lo busca en el mapa del juego (`C_Map.GetMapChildrenInfo` del
mundo, todos los descendientes; el índice nombre → número se hace una vez, en cuanto el juego da los mapas) y
`ZoneIn`, en `ParseRosterEntry`, pone el nombre de ese mapa en el idioma de quien la recibe
(`C_Map.GetMapInfo`). La zona que no está en el mapa va con su nombre, como antes; un número que no conozco,
sin zona. Va dentro del código corto de cada lista («#1=@1429»). Una versión de antes enseña «@1429» tal cual.

### `NextSeq`

Número de envío siguiente: la HORA DEL SERVIDOR (igual para todos) por 10, más un contador para que dos
envíos del mismo segundo no tengan el mismo. Así dos listas o cambios de una hermandad se pueden comparar
SIEMPRE, los haya hecho quien los haya hecho. Antes cada origen numeraba por su cuenta y solo se
comparaban los del mismo: una lista vieja reenviada sin origen pisaba a la buena y quitaba a quien
acababa de volver (banco, chivato de listas: 6 de 6 casos, oficiales y GM que volvían hacía 2-8 s)

### `HU:SendRosterDelta`

Solo los cambios desde lo último que se mandó:  RC~ETIQ~seqBase~seqNueva~total~conectados~parte~partes~cambios
  cambios: +nombre,clase,nivel,rango,zona[,a]  (entra o cambia)   -nombre  (se va)
Devuelve false si son tantos que es mejor mandar la lista entera

### `local pushed = {}`

Fase de lanzamiento: alguien de la lista de otra hermandad (oficial, enlace o ayudante) acaba de
entrar en el canal, así que viene de conectarse o de /reload y ha perdido las listas. Quien se
encarga de su hermandad le manda la mía sin esperar a que la pida (la petición podía no llegar
nunca a quien la contesta). Son unos pocos nombres.

### en `HU:AskMissingRosterTag`: `if p and not p.relay then`

(quien vuelve de una desconexión ha perdido los contactos y el "mejor" puede ser cualquiera
que haya hablado en el canal, que no contesta a RF: primero se pregunta a mi hermandad quién
es su enlace y se vuelve a intentar enseguida)

### `local savedAsked = {}`

Recién entrado: a los contactos guardados de cada hermandad de la que no tengo lista confirmada les
pido la lista directamente (RF~miEtiq~2), sin esperar a ser enlace ni a que conteste mi hermandad.
Solo oficiales y quien está solo en su hermandad: con 2.000 entrando a la vez serían miles de
susurros, y a los demás se la pasa su hermandad (NQ). Como mucho 2 contactos por hermandad y 2
vueltas. La respuesta pasa por HU:SenderKind / HU:DecideRoster como cualquier lista.

### en `HU:AskSavedContacts`: `local full = {}`

Contactos comprobados (no antiguos) de esa hermandad: con ellos cualquiera, también un raso,
confirma enseguida la lista que le ha pasado su hermandad (que, si la hermandad aún se asienta,
llega «sin confirmar» y así se quedaba minutos). A ellos se les pide aunque la lista acabe de
pasar por GUILD: lo que falta no es la lista sino un contacto comprobado que la confirme. El
otro lado contesta como mucho SECOND_MAX veces cada SECOND_WIN s, así que no se multiplica

### Quien acaba de entrar pide primero a SU hermandad lo que le falta

quien acaba de entrar pide primero a SU hermandad lo que le falta
(sus compañeros ya tienen las listas de las otras hermandades). Contestan el enlace y sus
ayudantes, repartiéndose las hermandades, y lo mandan por GUILD (así les sirve a todos
los que acaban de entrar). Solo si nadie lo tiene, se pide a la otra hermandad (RF/WQ).
  NQ~R:ETIQ,ETIQ~W:ETIQ,ETIQ    (R = lista de conectados, W = lista de miembros)

### `local listSeen = { sig = {}, force = {}, GAP = 10 }`

(en una sola tabla: la parte principal del archivo no puede pasar de 200 variables locales)
sig[tag] = { sig, t }: la última lista de esa hermandad que pasó por GUILD (o que mandé yo); force[tag] =
cuándo la mandé yo con prisa; GAP: en ese tiempo no sale otra igual ni otra con prisa

### `local lastNQ, nqTry = -999, 0`

Id de un trozo de la lista de una hermandad: trozo · número de envío de quien la hizo · huella. Hoy hay
un solo trozo (1, la lista entera); con las listas completas por trozos, cada trozo llevará el suyo.
Sale de lo que ya lleva la RB: no cambia el mensaje y las versiones viejas lo siguen entendiendo.

### en `HU:SendStoredRoster`: `local now, mySig = GetTime(), listSeen.Sig(r)`

(la misma lista que acaba de pasar por GUILD no se vuelve a mandar, y con prisa como mucho una vez
por hermandad cada 10 s: por GUILD les llega a todos los que acaban de entrar. Antes, con cada
compañero que entraba, salía otra igual: 600-880 en 30 min y la cola del enlace no se vaciaba)
(solo si pasó después del último que entró o la pidió (listSeen.need): si no, ese no la tiene)

### en `HU:SendStoredRoster`: `local gap = 10`

(la misma lista entera, como mucho cada 10 minutos: los cambios ya llegan al momento.
En la fase de lanzamiento la lista son unos pocos nombres: cada 10 s, para que a quien
entra o vuelve tras una desconexión se la mande alguien de su hermandad enseguida; con muchos
entrando a la vez, una sola vez cada 10 s les sirve a todos)

### en `HU:SendStoredRoster`: `local age = math.max(0, math.floor(GetTime() - (r.updated or GetTime())))`

(al final, cuántos segundos tiene mi copia: quien tenga una más nueva no deja que esta la pise;
quién la hizo: el número de envío solo se puede comparar entre listas del mismo origen; y su
estado (b/m/p/c): mi hermandad la toma igual que yo, sin darla por buena si no lo es)

### `local WELCOME_DELAY, WELCOME_GAP = 1, 10`

Quien entra suelto tiene que tener las listas de todas las hermandades en 5-10 s. En cuanto el juego
avisa de que un compañero se ha conectado, quien se encarga de cada hermandad (el enlace o el ayudante
que la lleva) reparte por GUILD la lista que tiene, con su estado, a los WELCOME_DELAY s: lo que tarda
su addon en estar listo. En fase de lanzamiento cada lista es un solo mensaje. Con muchos entrando a
la vez sale como mucho una por hermandad cada WELCOME_GAP s, y les sirve a todos. (No va por susurro:
una lista de otra hermandad que susurra un compañero no se acepta, y así no depende de que pregunte)
(1 s: lo que llegue antes de que el addon del que entra esté listo, él lo guarda y lo aplica en cuanto
lo está; ver earlyRB en HU.comm.RB)

### `quiet`

(día a día: quien contesta lleva más de 5 min conectado y tiene la copia confirmada. Entonces
contesta UNO, el mismo para todos, al momento; a los 0,6 s el enlace y a los 2 s el siguiente
del reparto, si aún no ha pasado por GUILD, aunque esté dentro del freno de SendStoredRoster.
Si no, como antes: mientras la hermandad se asienta, repartir al momento copias recién hechas
tapaba las confirmadas que llegaban después)

### `PromoteSameOrigin`

Lista que alguien de confianza de mi hermandad reparte como confirmada («c»: un oficial con /gu
confirmar, o el enlace), pero mi copia es más nueva o algo distinta: no se pisa, solo se le sube el
estado si es del mismo origen. Antes se descartaba y la mitad de la hermandad seguía sin confirmar.

### `local memberAsked = {}`

Lista confirmada que ya no cuadra con la que llega (ha cambiado quien la lleva: el enlace nuevo no
salía en ella, y la suya se descartaba para siempre, así que nunca quedaba comprobado). Se pide la
lista a alguien conectado de la que tengo, mejor un oficial: si la manda él, cuenta como «de la
lista» y la nueva queda confirmada, con el enlace nuevo dentro.

### `HU.partialRoster = {}`

Lo que ya ha llegado de una lista entera que viene en varios trozos: solo para el panel, que va
enseñando los nombres según llegan (y no quita a nadie hasta tenerla entera). El resto del addon
sigue con la lista anterior hasta que llegan todos los trozos.

### `HU.ApplyRosterDelta`

st: la hora del servidor del cambio (su número de envío). Cada miembro guarda la de su último cambio
(m.st; los de una lista entera, la de la lista): un cambio más viejo que lo que ya sé de ese nombre no
lo toca. Así un «sale» que llega tarde no quita a quien ya ha vuelto, ni un «entra» viejo pisa uno nuevo

### en `HU.comm.RB`: `if dist == "GUILD" and (f[9] == nil or f[9] == "") and (f[10] == nil or f[10]…`

(por GUILD, una lista sin quién la hizo NI estado no se acepta: todos los addons la reenvían con los
dos. Así un reenvío tardío, o alguien con el addon tocado, no puede borrar a nadie; banco, chivato de
listas: 6 de 6 desaparecidos eran esto)

### en `HU.comm.RB`: `local kind = (self.acceptKind[tag] or {})[self:Key(sender) or ""]`

(con su antigüedad, 0, quién la hizo, para que mis compañeros puedan comparar números de envío,
y el estado con que la tomo: mis compañeros la toman igual. Si no cabe, sin quién la hizo; si
tampoco, solo va tal cual si es confirmada: si no, la tomarían por buena)

### en `HU.comm.RB`: `local pkey = tag .. ":" .. seq .. ":" .. sender:lower()`

(puede haber dos listas llegando a la vez: cada una se junta por separado)
(y también por quien la manda: dos compañeros que reparten la misma lista la trocean cada uno a su
manera, y juntar el trozo 1 de uno con el 2 de otro dejaba media lista; banco, chivato: G02 de 19
a 6, el GM y el enlace incluidos)

### en `HU.comm.RB`: `local quietMax = 15`

(si a los 40 s sigue a medias, se ha perdido algún trozo: se pide a
mi hermandad en vez de esperar a la siguiente lista entera, que tarda 30 minutos)
(solo si no llega ningún trozo más en 40 s: si van llegando, es que va despacio)
(fase de lanzamiento: la lista son 1-2 trozos; si a los 15 s sin trozos nuevos sigue a medias,
se pide ya, también a quien me la susurró (RF~etiq~1). Antes se esperaban 2 minutos)

### en `HU.comm.RB`: `local age = (dist == "GUILD") and tonumber(f[8]) or nil`

Una lista repartida dentro de mi hermandad dice cuántos segundos tiene. Si la mía es más nueva
(me han llegado cambios después), no se pisa: antes, una copia vieja borraba a quien acababa de
entrar en la lista, y no volvía hasta la comprobación de cada 10 minutos. Y se reparte la mía,
para corregir a los demás (si nadie lo ha hecho ya).

### en `HU.comm.RB`: `local theirSig = (dist == "GUILD") and f[11] or nil`

Del mismo origen y con un número de envío más bajo que la mía: es más vieja (cada origen numera
hacia arriba). Antes, una copia vieja que un compañero tenía guardada pisaba la buena aunque su
antigüedad pareciera nueva (los cambios sueltos la marcan como recién actualizada), y quien
acababa de entrar desaparecía hasta la siguiente lista entera (minutos).
(el número da la vuelta al llegar a 99.999: solo cuenta como más viejo si la diferencia es pequeña)
Mismo origen y mismo número de envío que la mía, pero otra huella: una de las dos se quedó a
medias (visto en el banco: el maestro de una hermandad desaparecía al pisarse la buena con otra
copia del mismo envío). No se pisa ninguna; quien se encarga de esa hermandad pide la entera a
su enlace, como mucho una vez por hermandad cada 60 s, y la nueva llega a todos por GUILD.

### en `HU.comm.RB`: `local older = mine and not mine.weak and mine.seq and seq < mine.seq`

(más vieja que la mía, venga de quien venga: el número es la hora del servidor de cuando se hizo,
y la mía lleva la del último cambio que le he aplicado)
(ya no se tira: se junta con la mía nombre a nombre más abajo, y lo más nuevo de cada uno gana. Si se
tiraba, las listas de otros compañeros tampoco contaban para confirmarla: en clave-reloj, la de G03 no
se confirmaba nunca. Por GUILD, además, se reparte la mía para corregir a los demás)

### en `HU.comm.RB`: `local cs = mine and not mine.weak and HU.RosterStateOf(mine)`

(un reenvío tal cual lleva el estado con que lo tomó quien lo reenvía, que puede saber menos que
yo: si la lista es exactamente la mía, no me baja el estado. Antes, cada reenvío de un ayudante
devolvía G03 a «arranque» a toda la hermandad, nadie contaba como miembro y no se confirmaba
nunca; clave-reloj. Una lista distinta sí la baja, como siempre: así se ven las disputas)

### en `HU.comm.RB`: `local ok = self:Key(origin)`

(yo llevo el reloj de esa hermandad y esta lista es un reenvío tal cual de un compañero de
confianza (edad 0, sin huella: no es una copia guardada) de la que le susurró quien la hizo:
cuenta como si me la hubiera mandado a mí. Si no, cuando la otra hermandad repartía sus
listas entre mis ayudantes, las dos cuentas nunca me coincidían y la lista no se confirmaba:
clave-reloj, G03 sin rangos en toda la prueba)

### en `HU.comm.RB`: `if mine and mine.members and mine ~= nr then`

Junta con la mía, nombre a nombre (lo pidió Jorge: que no desaparezca nadie). Cada uno lleva la hora
de su último cambio (st):
  · está en las dos: gana la que sepa algo más nuevo de él;
  · solo en la mía y con un cambio posterior a esta lista: se queda (entró o cambió después);
  · solo en la mía y sin nada posterior: solo se quita si la lista es FIABLE: confirmada («c») y hecha
    por alguien que llevaba ≥5 min conectado (su lista del juego ya bien cargada). Una que no lo sea
    solo añade: quien acaba de entrar o recargar no puede vaciar una hermandad (banco, semilla 2:
    G03 casi entera fuera 2-7 s)

### en `HU.comm.RB`: `local reliable = false`

(fiable: confirmada, y quien la hizo sale en MI copia de su hermandad conectado desde hace ≥5 min,
según la hora de su último cambio. Lo que dice él de sí mismo (seq.up) solo sirve para descartar:
un addon tocado podría decir siempre 5 min)

### en `HU.comm.RB`: `local kept = false`

(lo que se queda solo porque la lista no es fiable, se queda KEEP_FOR s como mucho: si no, la copia
guardaba para siempre a quien ya se fue, su huella nunca cuadraba con la de los demás y la lista no
se confirmaba nunca, y sin confirmar tampoco podía quitarlo. En clave-reloj, G03 sin rangos)

### en `HU.comm.RB`: `local before, late = nil, false`

(los cambios que llegaron mientras llegaba esta lista son más nuevos que ella: se vuelven a aplicar.
Y por GUILD, también los que llegaron después de la última actualización de la copia del que la
reparte (ahora - su edad): esa copia no los tenía. Con solo el margen de 5 s de arriba, un compañero
al que le faltaba el cambio lo quitaba a toda la hermandad al repartir su lista (bienvenida, NQ), y
volvía con la siguiente lista entera: 20-60 s)
(solo los de los últimos 30 s: el pisado pasa a los pocos segundos del cambio, y con cambios más
viejos dos copias podían no ponerse nunca de acuerdo)
(con la hora del servidor de cada lista y de cada cambio: se vuelven a aplicar TODOS los cambios
guardados hechos después de esta lista, vengan de quien vengan. Antes solo los de los últimos 30 s
por la hora de llegada, y quien acababa de volver se perdía si la lista era de antes)

### en `HU.comm.RB`: `if late and before and MembersSigHash(nr.members) ~= before then`

(y si de verdad le faltaban, la corregida vale como recién hecha y se reparte, para que la arregle
también quien la tenía vieja. Solo quien lleva esa hermandad en la mía, con el freno normal de 10 s y
como mucho cada 30 s: antes la repartía con prisa cualquiera que la corrigiera, y en una conversación
continua con 4 hermandades cada reparto provocaba otros (615 listas en la cola del enlace))

### en `HU.comm.RB`: `if dist == "WHISPER" then`

Segunda opinión: si pisa la que mandó su enlace hace poco una lista de otro de esa hermandad
(alguien que se creyó enlace un momento, con una copia vieja), se le pide la entera al enlace.
Solo quien la recibe por susurro, para no pedirla todos.

### en `HU.comm.RB`: `if pt.fwdFlag ~= state and (self:IsRelay() or self:HandlesTag(tag) or (state …`

(los trozos se repartieron con otro estado del que ha quedado: se reparte otra vez)
(también un oficial o ayudante que acaba de confirmarla con su contacto: así le llega «c» a toda
mi hermandad y los rasos no tienen que pedirla cada uno)

### en `HU.comm.RF`: `if f[2] == "2" then`

(RF~etiq~2: segunda opinión, o alguien de otra hermandad que acaba de entrar y me tiene como
contacto guardado. Contesta cualquiera del grupo del enlace o un oficial, aunque no le toque esa
hermandad, solo con la lista: sin tocar lo enviado ni mandar rangos o fichas aparte. Como mucho
una vez cada 30 s a cada uno y SECOND_MAX en total cada SECOND_WIN s: con una entrada masiva, el
resto la recibe de su propia hermandad)

### en `HU.comm.RF`: `if st and GetTime() - st.fullT < gap then`

(dentro del freno no se descarta: se manda cuando acabe, UNA sola vez por hermandad, al último que
la pidió: la lista se reparte en su hermandad y les sirve a todos. Antes se perdía y quien no la
tenía entera esperaba a su siguiente petición, ~3 minutos. Una por persona atascaba la cola en
una entrada masiva: 50 listas enteras de golpe)

### en `HU.comm.RC`: `local rd = recentDeltas[tag] or {}`

los cambios ("entra" / "sale") se aplican aunque mi copia no sea justo la que esperaban: aplicarlos
dos veces no hace daño. Antes se pedía la lista entera, y con mucha gente entrando y saliendo eso
atascaba las colas y retrasaba los cambios siguientes, que tampoco encajaban.
(se guardan un rato: si mientras tanto se está recibiendo una lista entera hecha antes, al
terminar de llegar se vuelven a aplicar, porque la entera los pisaría)

### en `HU.comm.RC`: `if h ~= want and dist == "WHISPER" and (not fullAsked[tag] or GetTime() - ful…`

(no cuadra: mi copia vino de otro, por ejemplo de quien fue enlace un momento. Se pide la
entera ya a quien manda los cambios, en vez de esperar dos presentaciones (~10 min). Solo
quien recibió el susurro, para no pedirla todos a la vez)

## Net/Security.lua

### `channel = true` · lo que puede llegar por el canal oculto (RA y LP)

Por el canal oculto solo van la presentación del enlace y la sonda del carril (el chat va con su
propio prefijo, en Channel.lua). Nada del addon va por grupo, banda o campo de batalla: antes se
aceptaba todo lo que no fuera susurro, y cualquiera de tu grupo podía mandar listas falsas.

### `HU:AllowAddonMessage` · las marcas de seguridad

Las marcas (`tagField`, `bootstrap`, `open`, `channel`, `remoteData`) las declara cada orden en su
`HU:RegisterMessage` (ver Protocol.lua); antes eran las tablas `TAG_FIELD`, `BOOTSTRAP`, `OPEN`,
`CHANNEL_OK` y `REMOTE_DATA` de Comm.lua.

Seguridad de los mensajes del addon
  * Por GUILD solo llegan mensajes de compañeros de hermandad (lo garantiza el juego).
  * Por susurro, solo se acepta a quien está en la lista de alguna de las hermandades.
    Excepción para arrancar: saludos y listas de miembros de una hermandad cuya lista
    todavía no tenemos (si no, nunca se podría conseguir la primera).
  * Los datos de una hermandad (listas, rangos, fichas, desconectados) solo se aceptan
    de alguien que está en la lista de ESA hermandad.

### `local CHECK_GAP, checkAt = 15, -999`

Lectura de la lista del canal a petición (cuando llega un saludo o una lista de alguien sin avalar):
solo quien ya la lee (el enlace, oficiales, maestro, moderadores), como mucho cada CHECK_GAP s. Los
rasos no la leen. Quien entra al canal (aviso de entrada) también cuenta como visto.

### `HU:Vouched`

¿Puedo fiarme de que un desconocido es de la comunidad, aunque aún no tenga su lista?
Ha hablado por el canal oculto, o es un contacto conocido de esa hermandad (de otras sesiones,
o me lo ha presentado mi hermandad). Antes, para arrancar valía un susurro de cualquiera.

### Lista de conectados de otra hermandad sin su lista completa (fase d…

Lista de conectados de otra hermandad sin su lista completa (fase de lanzamiento): antes
valía de cualquiera que hubiera hablado en el canal, que así se colaba de oficial de esa
hermandad y dejaba fuera a su enlace de verdad. Ahora se mira con qué se fía uno de quien la
manda (HU:SenderKind) y la lista se guarda con un estado (HU:DecideRoster, en HU.comm.RB).
Los comprobados, los de la lista y los antiguos se miran ANTES de la puerta cerrada: así nadie
deja fuera al de verdad. Con la lista confirmada y al día, los demás ya no entran.

### en `Hold`: `local key = sender:lower() .. cmd`

(una lista de varios trozos se guarda entera: antes la clave era remitente + orden y cada trozo
pisaba al anterior, así que al avalar al remitente solo se aplicaba el último y la lista se
quedaba a medias hasta pedirla otra vez, unos 3 minutos. Para lo demás, el último basta)

### `local ADMIT_BURST, ADMIT_RATE, ADMIT_MAX = 60, 2, 3000`

Seguridad (idea n.º 8 de Olympus): admisión con tope por remitente. De cada uno de fuera de mi
hermandad, 60 mensajes de golpe y luego 2 por segundo; lo demás se tira antes de leerlo. Así nadie con
la contraseña puede ahogar a un enlace a base de mensajes. Se recuerda a 3.000 remitentes como mucho.
El enlace o contacto COMPROBADO de otra hermandad (contacto guardado, de su lista confirmada o su
enlace «dicho por él») tiene un cupo mayor: le pasa el chat de respaldo de toda su hermandad, el
relleno del historial y las listas de una entrada masiva, y no se le puede tirar nada.

### `local PART_PER_SENDER, PART_TOTAL = 4, 400`

(idea n.º 8, segunda parte) trozos a medio recibir con tope: 4 por remitente de fuera y 400 en total.
Si se llena, se tira lo del desconocido que más acapara, nunca lo de mi hermandad. Cada entrada
lleva by (remitente) y g (llegó por mi hermandad).

## Lists.lua

### en `HU:MemberOf`: `local members = r.members or {}`

(sin índice: se hace uno aparte la primera vez y se rehace si la lista cambia. Antes se
recorrían sus 1.000 miembros en cada línea del chat)
(el índice guarda la POSICIÓN y se comprueba al mirar: si la lista es otra, ha cambiado de
tamaño o en ese sitio ya no está ese nombre (RB, RC, correcciones, bajas), se rehace. Así un
expulsado deja de contar al momento, como antes. Y «weak» se mira en el miembro de ahora)

### `HU:TrustedOfficer`

Seguridad: quien firma una acción de oficial (fijar, silenciar, notas públicas, canales...)
tiene que estar en una de las hermandades y ser maestro u oficial conocido.
Devuelve true, o false y "unknown" si es de las hermandades pero aún no sabemos su rango.

### `local deferred, deferT = {}, nil`

Acciones de oficial que esperan a conocer el rango de quien las firma
(se reintentan al llegar la lista de conectados de su hermandad; caducan a los 15 min
desde que llegaron: al volver a dejarlas en espera se conserva la hora de llegada)

### `HU:IsGuildForwarder`

Seguridad: QUIÉN TRAE una acción de oficial (no solo quién dice firmarla).
Antes solo se miraba el nombre escrito dentro del mensaje, y cualquier miembro con el addon
podía firmar como un oficial. Ahora, si quien la manda no es el propio firmante:
  * por hermandad (GUILD): tiene que ser un oficial de verdad (rango de la lista del juego), el
    enlace (el que calcula cada uno, no el que dice serlo) o uno de sus ayudantes: son los que
    reparten en la hermandad lo que llega de las otras;
  * por susurro: el enlace, un ayudante o un oficial de la hermandad del firmante.

### `FirmRank`

Seguridad: acciones que cambian la comunidad y se quedan (canal y contraseña, canales extra,
hermandades, colores, emoticonos, Buscar grupo). Con una lista de otra hermandad aún sin
confirmar (rangos provisionales), un intruso podía hacerlas en los minutos en que tenía rango y no
se deshacían al bajarle la lista. Ahora el firmante tiene que ser de mi hermandad o de una lista
confirmada; si no, la acción espera (Defer) por si se confirma.

### `HU:BigCommunity`

en comunidades grandes (más de 6 hermandades) las listas completas ya no se
reparten solas: los nombres de los inactivos llegan con sus datos (a petición y en segundo
plano) y la guardia pregunta a cada hermandad. Así se ahorra lo que más tráfico movía.
(desde la 5.3.0, siempre: lo que hacía falta para 20 hermandades también aligera las pequeñas.
Las listas completas no se reparten, la guardia se conforma con las de conectados y los
desconectados de otras hermandades llegan a petición)

### `HU.whitelist = {}          -- [tag] = { list = {nombres}, set = {[clave]=true…`

Cada hermandad comparte la lista de TODOS sus miembros (también desconectados).
La guardia solo echa a quien no está en ninguna de estas listas.

WH~tag~huella~cantidad          "mi lista tiene esta huella"  (cada 3 min)
WQ~tag                          "mándame la lista completa de tag"
WL~tag~huella~parte~partes~a,b,c    trozo de la lista

La huella cambia en cuanto alguien entra o sale de la hermandad, así que las
demás piden la lista nueva enseguida. Las listas se guardan entre sesiones.

### `HU.PHASE = "launch"`

Fase de lanzamiento: a las otras hermandades solo van el maestro, los oficiales, el enlace y sus
ayudantes; la guardia completa está apagada y cada hermandad vigila a quien escribe con su
etiqueta. "full" vuelve a repartir a todos los conectados (se puede probar con /gu fase).

### `HU.CHAT_ONLY = true`

Versión «solo chat» (5.4.11): siempre fase de lanzamiento. Por dentro solo viaja la lista pequeña
(maestro, oficiales, enlace y ayudantes), que usan la guardia y la confianza en el enlace; no se
puede pasar a la completa (ni con /gu fase ni con un db.phase guardado de antes)

## Presence.lua

### `SendRecent`

Solo «ha entrado X» / «se ha ido X», enseguida y sin saber qué copia tiene esa hermandad (los cambios
valen sobre cualquier copia). Para quien acaba de heredar una hermandad (la lista entera va detrás) y
para el suplente de quien la lleva (BacksTag).

### `BacksTag`

¿Soy el suplente de quien lleva esta hermandad? (el del puesto anterior al mío; el primer ayudante lo es
del enlace). Si quien la lleva se ha caído sin avisar, el juego no lo dice hasta pasados unos 20 s y
mientras tanto nadie mandaba sus cambios. El suplente manda también los cambios pequeños, ya.

### en `HU:PresenceFlushTag`: `fullSent[tag] = GetTime()`

(me acaba de tocar esta hermandad, porque se ha ido quien la llevaba: no sé qué lista tienen.
La lista entera, sin colarse, y «se ha ido X» por delante: después, para que la lista entera no
lo quite de la cola, HU:DropQueued)

### Red de seguridad: susurro a alguien de otra hermandad que sale cone…

Red de seguridad: susurro a alguien de otra hermandad que sale conectado y el juego dice «no hay
nadie con ese nombre» -> fuera de conectados en mi copia ya, y se dice a mi hermandad (PX). Vuelve a
salir con el siguiente cambio que diga que está (o con la lista entera de su hermandad).
  PX~ETIQ~nombre

### Salir del juego de forma normal (/camp, /logout, /quit): quien se c…

Salir del juego de forma normal (/camp, /logout, /quit): quien se comparte lo dice a su hermandad
(PV, por GUILD) y deja de contar ya; si es el enlace o un ayudante, manda él mismo «-yo» a TODAS las
otras hermandades (2 copias cada una: con 4 hermandades, 6 mensajes, dentro del cupo seguido). Antes
se esperaba al aviso del juego y a que otro heredara: con el enlace fallaba siempre (5-7 s).
Si se cancela (PW), vuelve a salir conectado. No con PLAYER_LOGOUT: también salta con /reload.

### `HU:AfterRosterScan`

y cada vez que el juego refresca la lista de la hermandad (por si alguien no sale en los avisos)
(la lista se lee por trozos: esto va al terminar de leerla)
(quien ha dicho «me voy» sigue saliendo conectado en la lista del juego hasta que se va: no cuenta)

## ChanPresence.lua

### Qué hay en el archivo

Guild Union - presencia por el canal (idea de GreenWall Revived): si alguien de OTRA hermandad que está
en su grupo compartido (maestro, oficial, enlace o ayudante) sale del canal de la comunidad y en 10 s no
vuelve ni da señales, cuenta como un «se ha desconectado» con la hora de la salida

## Ranks.lua

### `HU.remoteRanks = {}   -- [tag] = { "Maestro", "Oficial", ... }  (posición 1 …`

En tu hermandad: si tienes permiso de ascender/degradar, el cambio se hace al momento.

En otra hermandad no se puede cambiar un rango directamente (el juego no lo permite),
así que se envía una petición:

RN~tag~rango0,rango1,...                       nombres de rangos de una hermandad
RK~id~tag~objetivo~rango~solicitante~etiqSol   petición de cambio de rango
RD~id                                          petición ya atendida (cierra la ventana a los demás)
RR~id~ok|no~quien~objetivo                     respuesta al solicitante

A los oficiales de la otra hermandad que tengan el addon y permiso les sale una
ventana: "Ana <ALF> pide poner a Bruno como Veterano. Aceptar / Rechazar".
El primero que acepta lo aplica.

### Rango "Castigado": al silenciar o vetar a alguien de tu hermandad, …

Rango "Castigado": al silenciar o vetar a alguien de tu hermandad, se le puede bajar a ese
rango (que no tiene permiso para hablar en el chat de hermandad: así el juego tampoco le
deja escribir). Al acabar, se le devuelve su rango. Cada cambio es un clic en un botón del
juego (/gdemote, /gpromote): un addon no puede cambiar rangos por su cuenta.
- Bajar: ventana `GU_PUNISH` justo después de silenciar (solo a quien silencia, si puede degradar y
  el silenciado es de su hermandad). Devolver: ventana `GU_UNPUNISH` cuando acaba el tiempo (si sigue
  conectado), al quitar el silencio, o 20 s después de entrar si acabó estando fuera.
- Castigo repartido (ReduceClean-38): al pulsar Bajar, quien castiga manda `KS~nombre~rango de
  antes~quién~t` por el canal oculto de su hermandad (solo GUILD; lo acepta quien ve que lo manda un
  oficial). Al pulsar Devolver se manda con rango -1: los demás lo borran y se les cierra la ventana.
  Cada 30 s (y 20 s después de entrar) cada oficial mira los castigos con el silencio ya acabado
  (los silencios llegan a todos, MU): «¿Devolverle su rango?» le sale a quien castigó; si ese no
  está conectado, a cualquier oficial que pueda ascender. Si se pulsa «Ahora no», vuelve a salir a
  los 10 min. Al quitar el silencio o al acabarse estando conectado, a quien castigó le sale ya.
- Sin rango de castigo (ReduceClean-37): ventana `GU_NOPUNISH` («crea un rango Castigado sin
  permiso para hablar»), con las mismas condiciones que `GU_PUNISH`. Nombres que valen:
  castigado, castigada, castigados, punished. El addon no puede comprobar los permisos del rango
  (`GuildControlGetRankFlags` no existe en Forever).

## Audit.lua

### `local seen = {}`

Fuentes del registro:
- Mensajes del sistema de tu hermandad: ascensos, degradaciones, expulsiones,
entradas, salidas y cambio de maestro (los ve todo el mundo de la hermandad;
el enlace los reenvía a las demás hermandades).
- Avisos del canal: quién echa, veta o nombra moderador a quién.
- Acciones del addon: peticiones de rango enviadas y rechazadas.

AU~id~hora~etiqueta~autor~texto     entrada de registro compartida

### Rachas (solo en el registro de oficiales): cuando un oficial echa o…

Rachas (solo en el registro de oficiales): cuando un oficial echa o veta del chat
  FIRST BLOOD   el primero del día en toda la comunidad
  DOUBLE / TRIPLE / QUADRA / PENTA KILL   varios seguidos (menos de 30 s entre uno y otro)
  LEGENDARY / GODLIKE / UNSTOPPABLE / BEYOND GODLIKE   10, 25, 50 y 100 vetos en total
Van en el registro como una entrada que empieza por "!!" y se pinta en rojo.

## Pinned.lua

### `Clean`

PN~hora~autor~etiq~texto     mensaje fijado (texto vacío = quitarlo)
PQ                           alguien que acaba de entrar pide el mensaje fijado

## ChatTabs.lua

### Cada pestaña escribe en lo suyo (ReduceClean-35)

- Se aplica al abrir el chat (gancho a `ChatFrameUtil.OpenChat`, solo sin texto) y al hacer clic
  izquierdo en la pestaña (gancho a `FCF_Tab_OnClick`). Cambia el tipo y el «pegajoso» del cuadro de
  esa ventana: Hermandad → GUILD, Oficiales → OFFICER. No toca nada si el tipo actual no es el
  pegajoso (contestando un susurro, etc.).

### `local TABS = HU.LT({`

Crea en el chat del juego las pestañas:
"Hermandad"     chat de hermandad + lo que llega de las otras hermandades
"Oficiales"     chat de oficiales unido (solo si puedes verlo)
Se crean una vez; si las cierras, se pueden volver a crear desde el panel o con /gu pestañas.

**ReduceClean-88 (13/11): versión para salir, hecha desde la prueba 2.** Tres cosas:
- Dentro de un campo de batalla o una arena, los filtros de `CHAT_MSG_GUILD` y `CHAT_MSG_OFFICER` se
  dan de baja (`HU:SyncPvpFilters`, Core.lua; la llama `SyncSelfPaint` de Channel.lua en
  `UPDATE_BATTLEFIELD_STATUS`, `PLAYER_ENTERING_WORLD` y `ZONE_CHANGED_NEW_AREA`). Ahí las líneas de
  mi hermandad las pinta el juego, sin etiqueta. Al salir se vuelven a poner y, como `HU.selfPaint`
  ya está encendido, las pinta el addon. Motivo: con los filtros puestos dentro de la partida la
  5.4.31 (copia 85) daba 16× «string conversion on a secret string value (tainted by GuildUnion)» y
  el chat no se veía. Era el «modo 3» de la prueba (copia 86); el rastro y los modos `/gu bg` se
  han quitado. Sin confirmación escrita de Jorge de que el modo 3 se viera bien en la partida.
- Enlaces de profesión (`|Htrade:`) que no se abren al pulsarlos: NO es por cómo pinta el addon. La
  copia 88 dejaba esas líneas sin tocar (las pintaba el juego, sin etiqueta) y tampoco se abrían; a
  quien pone el enlace sí se le abre el suyo. Lo que encaja es que Forever no deja abrir la profesión
  de otro jugador desde el chat. La 89 quita aquel cambio: esas líneas vuelven a llevar etiqueta.
  Falta, para cerrarlo del todo, la prueba con Guild Union desactivado.
- Lo de la 87, que sigue igual:

**ReduceClean-87 (prueba 2 de campos de batalla, 13/11): el addon ya no crea pestañas ni toca la caja
de escribir.** Fuera `HU:CreateChatTabs` (con `FCF_OpenNewWindow` y el vaciado de grupos), la creación
sola al configurarse, `/gu pestañas`, el botón «Pestaña del chat GuildUnion» de Oficiales y el cambio
de tipo de chat al pulsar una pestaña o abrir el chat (`ApplyTab`: `SetChatType`, `SetStickyType`,
`UpdateHeader`). Motivo: Olympus avisa de que crear o configurar ventanas de chat desde un addon deja
marcados sus datos, y dentro de una partida la 5.4.31 daba «string conversion on a secret string value
(tainted by GuildUnion)». Sin confirmar que fuera la causa. Queda: reconocer por su nombre las pestañas
«Hermandad» y «Oficiales» que el jugador tenga (las recupera el juego al entrar) para pintar ahí lo de
las otras hermandades, el menú «Guild Union» del clic derecho en una pestaña, y el orden de canales
al abrir el chat. Lo de abajo sobre crear pestañas y «cada pestaña escribe en lo suyo» ya no vale.

«Buscar grupo» se quitó entero en la ReduceClean-85 (Jorge, 13/11: no se usaba): fuera la pestaña,
`/glf` y `/buscargrupo`, `HU:SendLFG`, el modo de la caja de escribir (`eb.guLFG`) y el interruptor de
oficiales (`LG`, `db.lfgState`). Lo que mande una versión vieja con la marca `[ETIQ:B]` se descarta
en `HU:OnUnionChat`, y un `LG` que llegue no tiene quien lo atienda (Comm lo ignora). El addon no
cierra la pestaña «Buscar grupo» que ya tenga alguien creada: la cierra él a mano. El historial
guardado conserva sus líneas viejas de ese tipo (`lfg` en History.lua y Social.lua).

## Guard.lua

### `HU.pendingSince = {} -- [clave] = desde cuándo está en el canal sin aparece…`

Regla: quien esté en cualquiera de las hermandades unidas NUNCA se echa.

- Cada moderador (o el propietario) del canal con el addon vigila por su cuenta.
- Un jugador es intruso solo si no aparece en la lista de su hermandad
ni en las listas completas de las demás hermandades.
- Si falta la lista actualizada de alguna hermandad, no se echa a nadie:
sin esa lista no se puede saber si es uno de los suyos.
- Además se espera un margen (por defecto 2 min) para dar tiempo a que
llegue la lista nueva cuando alguien acaba de entrar en una hermandad.

### en `HU:StoreChannelMembers`: `if kind == "main" and self.chanSeen and not sliced then`

(«visto en el canal» = quien está ahora en él: hace falta la contraseña para entrar. En Forever no
llega nada oculto del addon por el canal, así que esto es lo único que avala a quien entra por
primera vez. Da lo mismo que el chanSeen de siempre y nada más: ni enlace «dicho por él», ni
rangos, ni confirmar listas. Lo retenido de alguien que ya está en él se vuelve a mirar)

### `local ASYNC_SLICE, ASYNC_STEP, ASYNC_BUDGET = 150, 0.02, 1.5`

La misma lista, leída por trozos: para lo que no tiene prisa, como el saludo (con miles en el canal,
leerla de golpe daba un tirón de ~20 ms). fn(lista o nil)
(trozos de 150 y como mucho ~1,5 ms por fotograma; el «visto en el canal» y la búsqueda de mi línea
van dentro de cada trozo, y los avisos al acabar, en el fotograma siguiente: antes el último trozo
lo hacía todo junto y pasaba de 4 ms)

### La guardia pregunta. Si falta la lista completa de alguna hermandad…

la guardia pregunta. Si falta la lista completa de alguna hermandad, en
vez de esperar a que llegue, pregunta a su contacto "¿son de los tuyos?" (él tiene la lista
entera de su hermandad, también los desconectados). Solo se echa a alguien cuando TODAS
esas hermandades han contestado que no es suyo.
  MQ~id~nombre,nombre      pregunta (a una hermandad)
  MA~id~nombre,nombre      respuesta: los que sí son de mi hermandad (puede ir vacía)

### en `HU:GuardAsk`: `local MAX_BODY = 200`

solo van en la pregunta (y solo cuentan como preguntados) los nombres enteros que caben en
el mensaje; los demás, en la siguiente. Si no, a los que no cabían nadie los reclamaba y se
daban por intrusos aunque fueran de las hermandades.

### `local WIT_WAIT = 20`

Seguridad (idea n.º 10 de Olympus): un TESTIGO. A cada hermandad se le pregunta a su mejor contacto
y, si hay otro contacto de su lista buena, también a él. «Es mío» solo vale si lo dicen los dos;
«no es mío» de los dos = intruso; si no coinciden, no se decide nada (ni se protege ni se acusa).
Si el testigo no contesta en WIT_WAIT s, vale lo del primero, como antes.

### en `HU.comm.MA`: `if not self:MemberOf(sender, tag) then`

(contesta por X solo quien está en la lista buena de X: antes valía el «mejor contacto», que
podía ser un intruso, y su «todos son míos» dejaba ciega a la guardia. Si no, como si no
contestara: la pregunta caduca y no se marca a nadie)

### `HU:GuildVerified`

Guardia por hermandad: alguien escribe en el canal con la etiqueta de MI hermandad y no está en
ella. Mi lista la da el juego entera (también desconectados), así que no hace falta preguntar a
nadie. Lo hace un oficial: lo silencia una hora para todas las hermandades y, si es moderador,
lo echa del canal.
¿Es de mi hermandad, según el JUEGO? Quien ha mandado algo por la vía GUILD (saludos, o la
respuesta PA de abajo) es miembro seguro: por esa vía solo pueden mandar los miembros y el
remitente lo pone el juego, no se puede falsificar ni depende de cómo se escriban los nombres

### `local CHANNEL_HAS_STALE = 60`

¿Sigue en el canal? (nil si no se puede saber)
(por el índice de nombres de la última lectura: antes recorría la lista entera en cada consulta, y la
llaman SenderKind, Vouched y las anclas con cada lista que llega. Si la lectura tiene más de 10 s y
menos de 60, vale mientras se relee por trozos, sin tirón)

### `local impAsk = {}`

Alguien escribe con MI etiqueta y no está en mi lista ni ha hablado por la hermandad: un oficial le
pregunta por la vía GUILD («PG~nombre»); su addon, si es de los nuestros, contesta «PA» por la
misma vía (solo vale si el juego dice que lo manda él). Sin respuesta en 20 s se repite; sin
respuesta a los 40 s está conectado con el addon y no es de la hermandad: silencio de 1 h para
todas las hermandades y, si soy moderador, fuera del canal. Mientras se comprueba, sus mensajes
quedan retenidos (Channel.lua): si resulta ser de los nuestros se enseñan; si no, se tiran.
Límites: una pregunta por nombre cada 5 min y 5 por minuto en total.

### Propietario del canal: siempre un maestro u oficial

Propietario del canal: siempre un maestro u oficial
  * Si soy el propietario y no soy maestro ni oficial (el juego me lo ha pasado al irse el
    anterior), se lo paso al mejor que haya en el canal: maestro, oficial que ya es moderador,
    oficial.
  * Si soy el propietario y soy maestro u oficial, hago moderadores a los maestros y oficiales
    del canal que aún no lo son (así pueden echar a un impostor, y cuando me vaya el juego tiene
    a quién pasárselo), y quito la moderación a quien la tenga sin ser maestro ni oficial.

### en `HU:StatusLines`: `local r = self.remoteRoster[tag]`

(la lista que de verdad se reparte: los conectados de esa hermandad; en la fase de
lanzamiento son su maestro y sus oficiales. Antes se miraba la lista completa de miembros,
que ya no viaja, y salía siempre «sin lista»)

### `LightMembers`

Revisión ligera: solo los que acaban de entrar y los sospechosos que siguen pendientes.
Sin recorrer el canal entero ni montar la tabla de conocidos (con miles en el canal, la
completa cada 15 s gastaba segundos de procesador y mucha basura).

### `local full = true`

¿tengo la lista COMPLETA (también desconectados) de todas las demás? Si no, no basta con no
aparecer en las listas de conectados (a quien acaba de entrar le faltan unos segundos): se
pregunta a todas y solo es intruso quien ninguna reclama. Así nunca se echa a alguien de las
hermandades porque su lista de conectados aún no estaba al día.

## GuardKeeper.lua

### Qué hay en el archivo

Guild Union - guardia por encargo (decisión de Jorge, 07/11)
  * Canal principal: nadie busca intrusos solo. Un maestro u oficial lo pide con
    /gu guardia revisar y decide él a quién echar.
  * Vetados del canal principal: los echa UN encargado (el propietario del canal o, si no tiene
    el addon, el moderador con el addon de HU.Hash más bajo), no todos los moderadores.
  * Chat de oficiales: guardia automática del encargado de ese canal (intrusos y vetados).

### `local SCAN_SLICE = 200`

Una pasada por la lista del juego: propietario, moderadores y vetados presentes (y, en el chat de
oficiales, todos: es pequeño). El principal se lee por trozos de SCAN_SLICE por fotograma, como la
guardia de antes: con miles de personas, de golpe daba un tirón. done(Ld o nil) al terminar.

## Social.lua

### `Clean`

PF~raza~rol~spec~profs                    mi ficha (por GUILD). profs = "ALC300.HERB275"
PB~tag~Nombre:raza:rol:spec:profs;...     fichas de una hermandad (el enlace las pasa a las demás)
OD~tag~Nombre,clase,nivel,horas;...       desconectados de una hermandad
MU~nombre~segundos~autor~etiq~t           silenciar (0 = para siempre, -1 = quitar el silencio)
GK~id~tag~objetivo~solicitante~etiqSol    petición de echar a alguien de otra hermandad
GD~id                                     petición ya atendida
GR~id~ok|no~quien~objetivo~motivo         respuesta al solicitante
HQ~desde~oficial                          al entrar: pide lo escrito mientras no estabas
HL~t~tipo~tag~autor~mensaje               una línea de ese historial
RP~prof                                   pedir la lista de recetas de una profesión
RS~prof~parte~partes~ids                  lista de recetas (ids de objeto, "e123" = encantamiento)

### en `HU:SendRosterTo`: `local ps = profilesSent[p.tag]`

(desde el último envío a esa hermandad, no desde el último completo: antes cada lista volvía a
llevar todas las fichas cambiadas en la última hora, y con muchas listas el enlace acumulaba
100 fichas en la cola; banco, continua-4)

### Lo de los desconectados y las fichas, a petición

lo de los desconectados y las fichas, a petición
  OQ~miEtiq~suEtiq   pídeme nivel/clase/tiempo de tus desconectados (contesta con OD)
  FQ~suEtiq~nombre   pídeme la ficha de ese jugador (contesta con PB)

### `HU:OnStart(function()`

(hasta la 5.4.8 se guardaba como contacto a cualquiera que mandara una lista: lo guardado puede
llevar intrusos. No se borra: se marca como antiguo, que solo vale para arrancar y para coincidir
con otra cuenta, hasta que se compruebe otra vez)

### `HU:OnStart(function()`

¿Faltan aún los inactivos de alguna hermandad? (para el aviso "cargando" de la lista)
En segundo plano y sin avisar: cada poco, el que se encarga en mi hermandad pide los
inactivos de una hermandad que falte (le llegan a toda mi hermandad y se guardan).
Así, cuando alguien elige Inactivos, casi siempre ya están.

### en `HU:OnStart`: `HU.After(math.random() * 120, function() HU:Every(120, "desconectados-reparti…`

(solo el enlace, una hermandad cada 2 minutos y solo si no tiene nada urgente que mandar)
(empieza con un retraso al azar: si no, cada 2 min coincidía en el mismo fotograma con los
demás relojes de 10, 15 y 60 s, que arrancan todos a la vez, y juntos pasaban de 8 ms)

### `local FUTURE_MAX = HU.STAMP_FUTURE`

Hora de los silencios y vetos (decide cuál es el más nuevo): la del servidor, igual para todos.
Antes era la del PC de quien los ponía, y con un reloj desajustado un «quitar» viejo ganaba a uno
nuevo. Lo que llegue más de 5 min por delante de la hora del servidor se descarta.

### `local pendingMutes, muteFlushPlanned = {}, false`

Varios silencios seguidos van juntos en un solo mensaje por destino (MZ): con uno por silencio
y destino, el quinto tardaba ~8 s en salir y mientras tanto se seguía viendo al silenciado.
  MZ~nombre,segs,autor,etiq,t,motivo;nombre,...

### en `HU.comm.MZ`: `HU.comm.MU(self, sender, { p[1], p[2], p[3], p[4], p[5], p[6] }, dist, false)`

(cada uno como un MU; el reenvío a mi hermandad va una vez, abajo)
(con la vía real por la que llegó el paquete: la comprobación de quién lo trae la necesita;
con "BATCH" se rechazaban todos los silencios repartidos por el enlace. raw = false: el
reenvío a mi hermandad va una vez, abajo)

### `HU:IsBanned`

Vetar del chat: no puede volver a entrar aunque esté en la hermandad o tenga la contraseña
  BN~nombre~1|0~autor~etiq~t      1 = vetado, 0 = readmitido
Lo aplica en el canal cualquier moderador o propietario con el addon, y además nadie
muestra lo que escriba un vetado.

### `HU.GuildCmd`

Echar de la hermandad es una acción "protegida": un addon no puede hacerlo por su cuenta
(el juego lo bloquea y dice que el addon "se ha bloqueado"). Se hace con /gremove desde un
botón del juego: el addon solo prepara el comando y tú pulsas el botón.

### `local HQ_WAIT = 8      -- segundos que se esperan peticiones antes de mandar`

Si entran cientos a la vez (reinicio del servidor), contestar a cada uno por separado atascaba
la cola del que contestaba. Ahora se juntan las peticiones y se manda una sola vez a toda la
hermandad (quien ya lo tenía lo descarta), como mucho cada 2 minutos y en la cola lenta.

### `ResponderBusy`

Contesta uno solo para toda la hermandad (el mismo para todos los que preguntan). Nunca el
enlace ni sus ayudantes, que ya van cargados con las listas, salvo que no haya nadie más.
Orden de quién contesta (lo usan IsResponder y HLRankOK: tiene que ser el mismo en los dos).
Primero los que no son enlace ni ayudantes; entre iguales, el hash más bajo del nombre.

### `local RESP_EVERY = 2`

Los dos mejores (si pregunta el primero, contesta el segundo). Con cientos de compañeros
recorrerlos todos en cada HQ daba fotogramas de hasta 4 ms (banco, continua-4: 106 de más de
1,85 ms en el enlace). Ahora se recorren por trozos en fotogramas seguidos, cada
RESP_EVERY s, y el HQ solo mira el último resultado. Solo la primera vez (aún sin resultado) se
calculan de una vez.

### `local hqSeenT = -999`

Seguridad: ¿puede este compañero mandarme por la hermandad lo de «mientras no estabas»?
Antes valía cualquiera y podía inventarse líneas de otros. Ahora solo si alguien lo ha pedido
hace poco (HQ) y quien lo manda es de los que contestan: enlace, ayudante u oficial, o uno de
los primeros por nombre (el que contesta es el primero; se dejan 3 de margen porque cada uno
conoce a compañeros algo distintos).

### `HasEntry`

(antes solo se miraban las 400 últimas: con mucho chat, una línea de hace 10-20 min ya estaba más
atrás y el relleno de quien vuelve la metía otra vez. Ahora se mira hacia atrás todo lo que sea
de esos 3 minutos alrededor; el historial va ordenado por hora: se busca por mitades dónde
empiezan y se para al pasarlos)

### en `HU:OnStart`: `local sNow = StampNow()`

limpiar vetos levantados hace más de 30 días (antes se guardaban y se reenviaban para siempre)
(y los guardados con una hora del futuro, de un PC adelantado, se dejan en la de ahora: si no,
ganarían a cualquier cambio nuevo)

### en `HU:OnStart`: `local resync = {} -- [etiqueta] = { sig, peer, t }`

el enlace repasa con las otras hermandades los silencios y vetos de la suya cada 5 min. Con
muchas hermandades era un susurro por silencio y por hermandad (30 × 9 = 270 cada 5 min, casi
todo su cupo, y en la cola del chat): ahora todos los silencios en MZ agrupados, por la cola
de poca prisa, y a cada hermandad solo si algo ha cambiado, si su contacto es otro o cada 30 min

### `HU:TypeLines`

Comandos (de una o varias líneas: echar, ascender, degradar) que tienes que escribir tú en el
chat: van a la ventana de órdenes (Orders.lua). Antes el addon los escribía en la caja del chat
al abrirla tú, y eso en Forever contamina esos comandos y el juego los bloquea hasta /reload.

## UnionMembers.lua

### Qué hay en el archivo

Miembros de la unión: todos los conectados de otra hermandad, solo para verlos en la pestaña
(«Miembros», BlizzTab.lua). Desde la 5.4.11 a las otras hermandades solo va la lista pequeña; esta
es aparte, no toca `RB`/`RC` ni la confianza, y las versiones de antes no la conocen (no contestan).

- **Pedirla** (`HU:WantUnionMembers`, que la pestaña llama cada 2 s mientras se ve): con una copia
  de menos de 1 min, nada. Si me toca a mí (`HU:ResponsibleFor`) o mi hermandad no tiene enlace, la
  pido yo por susurro (`MP`); si no, la pido a mi hermandad por GUILD y la pide quien se encarga. Si
  a los 40 s no ha llegado (quizá nuestro enlace tiene una versión de antes), la pido yo.
- **A quién**: a alguien de esa hermandad: su enlace, sus ayudantes, sus mejores contactos y los de
  la lista pequeña que tengo. Primero quien ya me ha contestado alguna vez (`HU.unionAnswered`), luego
  aquellos de los que no sé la versión y al final los contactos con la versión sabida: el número de
  versión no dice si alguien tiene Miembros (una copia de prueba puede llevar el mismo que la
  publicada). Si no empieza a contestar en 10 s, a otro; tras 8, «no contesta». (Visto el 22/11: con
  la versión ordenando y solo 3 intentos, el maestro de WLP3, el único con Miembros, nunca se
  preguntaba.)
- **Contestar** (`HU.comm.MP`): solo por mi propia hermandad y a quien es de la comunidad (está en
  alguna lista o avalado); a cada uno una lista por minuto y como mucho 3 por minuto en total, y nada
  con la cola llena. La lista son todos mis conectados (`HU:OnlineEntries`, sin el filtro de la fase
  de lanzamiento), en trozos que se entienden solos (`HU.PackMembers`: los códigos de zona van en el
  mismo trozo).
- **Recibir** (`HU.comm.ML`): por susurro, solo de a quien se la pedí; quien la pide la pasa a su
  hermandad por GUILD, donde vale solo de quien reparte por ella (`remoteData`). Mientras llega se
  enseña lo que hay; la anterior se sigue enseñando hasta que la nueva está entera; a los 10 min
  deja de enseñarse.
- **Todas las hermandades** a la vez (`HU:WantUnionMembers(nil)`): de una en una, y cada una como
  mucho cada 5 min, para no pedir las 19 a la vez.

### Con /who

Para una hermandad en la que nadie tiene Miembros (o nadie conectado). El juego solo deja hacer /who
desde un clic (probado en Forever el 23/11: desde un temporizador no hace nada), así que se
aprovechan los de la pestaña: abrirla, «Miembros», elegir hermandad, mover la lista o hacer clic en
ella llaman a `HU:UnionWhoTick`, que busca una hermandad sin lista (ni de Miembros ni un /who de menos
de 1 min), como mucho un /who cada 5 s. Mientras se espera la respuesta, las ventanas del juego que
escuchan `WHO_LIST_UPDATE` (`GetFramesRegisteredForEvent`, salvo `HU.eventFrame`) dejan de
escucharlo: así la de búsqueda no se abre. Vuelven a escuchar en el fotograma siguiente a la
respuesta, o a los 15 s si no llega; un /who escrito a mano las abre como siempre. El botón «Buscar
con /who» fuerza una búsqueda.

`/who g-"Nombre de la hermandad"` (`HU:WhoUnionMembers`) y, cuando el juego avisa
(`WHO_LIST_UPDATE`), se guardan los de esa hermandad (el nombre tiene que coincidir entero: el /who
también trae nombres parecidos). Solo desde un clic: el juego no deja a un addon hacer /who por su
cuenta. Solo se toma la respuesta al /who que he pedido, si llega en 15 s. No trae rangos; si llega la
lista de Miembros, se enseña esa. Si el juego no los da todos, el estado dice «N de M».

## History.lua

### Lo buscado, marcado como texto seleccionado (ReduceClean-46/47)

`HU.QuerySpans(mensaje, búsqueda)` da los trozos (bytes) donde está lo buscado, sin mirar mayúsculas
ni acentos (`HU.Fold` letra a letra) y saltando los códigos del juego del mensaje (`|c`, `|cn…:`,
`|H…|h`, `|T…|t`, `|A…|a`). `Line` devuelve `{ texto, bytes antes del mensaje, mensaje }` y `Show`
pone detrás de cada trozo un fondo azul de «texto seleccionado» (`MarkRow`, con
`CalculateScreenAreaFromCharacterSpan`, lo mismo que usa el chat de Blizzard al seleccionar con el
ratón; índices en bytes del texto entero, el final sin incluir). Todo con `pcall`: si fallase, la
línea sale sin marcar. (La 46 lo pintaba de naranja; Jorge lo quería como seleccionado.)
Al llegar más resultados de la misma búsqueda la lista ya no vuelve arriba (`W.keepScroll`); sí con
una búsqueda nueva.
**48:** viendo el contexto («[ver]»), lo que sigue llegando se guarda pero no se pinta (`W.inContext`):
antes te devolvía a la lista. Al volver, la lista queda donde la dejaste (`W.listScroll`).
El historial guarda y compara con la hora del servidor (`HU.StampNow`), no con la del PC de cada
oficial: con relojes distintos, los mensajes de varios oficiales salían desordenados. Lo guardado
antes sigue con la hora del PC de quien lo guardó.

### `local MAX_BYTES = 8 * 1024 * 1024`

tope de lo guardado de mi comunidad si soy oficial (se borran los días más viejos y, si hoy solo
ya no cabe, lo más viejo de hoy). Con 5.000 jugadores el canal da 3-10 MB al día: no caben 30
días en ningún tope que quepa en MemGuard; se guardan los más recientes que quepan.

### `SafeRemote`

Texto de otro, listo para guardar o enseñar. SafeText dobla cada | suelta; aplicado otra vez a un
texto ya limpio las volvía a doblar, y en cada salto la línea cambiaba. Aquí se juntan primero las
| seguidas: el resultado es el mismo aunque el texto llegue ya limpio.

### Huellas del relleno de huecos (ver «Rellenar huecos solos», más …

Huellas del relleno de huecos (ver «Rellenar huecos solos», más abajo). Se leen las líneas
guardadas byte a byte, sin crear textos ni tablas por línea (antes cada vuelta dejaba unos 15 MB
de basura). Da lo mismo que antes: suma de «autor en minúsculas \1 MatchText(texto)».
Cada día guarda su suma por tramos de 10 minutos (sirve para huellas de día, hora y 10 min) y se
pone al día con cada línea nueva: un día solo se vuelve a recorrer si cambia de otra forma.

### en `HU:HistInsert`: `local lines = day.lines`

Las líneas van ordenadas por segundo: el sitio se busca por bisección y los repetidos se miran
solo en ±120 s alrededor. Antes se recorría el día de atrás adelante: una línea de hace horas
(el rellenado del historial las trae) recorría cien mil líneas y daba tirones de 140 ms.

### `NameMatcher`

Buscar en mi PC (por trozos, para no dar tirones con 30 días)
  opts: { name = "Nombre", text = "texto", since = momento, kinds = {main=true...} }
  done(resultados): newest first; cada uno lleva day y i para ver el contexto

### Rellenar huecos solos (idea de GuildManagement, probada en Forever)…

Rellenar huecos solos (idea de GuildManagement, probada en Forever). Cada 5 minutos, un oficial
compara con otro (o con un compañero con el addon, que guarda 2 días) unas «huellas» del chat
(cuántos mensajes y una suma de sus textos) por día; donde no coinciden, por hora, y luego por
10 minutos; y pide solo ese trozo. Así quien entra recupera lo de mientras no estaba sin buscar.
Solo se tira: cada uno pide lo que le falta. El chat de oficiales nunca viaja.
  V~id~tam~desde~hasta       pide huellas (tam = segundos por trozo: 86400, 3600 o 600)
  v~id~tam~k:n:h,k:n:h…      huellas (k = trozo = inicio/tam); varios mensajes, y w~id al final
  S~id~k~tam                 pide las líneas de ese trozo
  D~id~t~k~tag~autor~msg     una línea; F~id~n al final

### `DayScanner`

Recorre las líneas de un día sin crear textos: fn(s, p, e) con la línea de s entre p y e (sin e).
Devuelve una función paso(presupuesto) → acabado, presupuesto que sobra. Del día abierto mira solo
las líneas que había al empezar (las nuevas se suman solas, en DigestOnAdd)

### `DigestsAsync`

Huellas de [a, b): [k] = { n, h } (solo trozos con algo; sin el chat de oficiales).
Por trozos de DIGEST_SLICE líneas cada 30 ms (con 20.000 líneas en un día, de golpe eran 130 ms).
Cada día suma por tramos de 10 min una sola vez (digestCache); los tramos que quedan a medias de
[a, b) se miran línea a línea. Los trozos que comparten dos días se suman (antes el segundo día
pisaba al primero y la huella de un día solo contaba una hora). done(huellas)

### en `SyncNext`: `local wantLines = #s.queue > 0 and s.lines > 0`

(se acabaron los pasos con cosas en la cola: un hueco grande. Se sigue con el mismo
compañero en 30 s, en vez de esperar 5 min. Solo si hay líneas por traer: si lo que queda
son trozos ya traídos cuya huella no cuadra, no se insiste)

## Channels.lua

### `local MAX_EXTRA = 3`

CX~nombre~clave~borrado(0/1)~autor~etiq~t     crear o quitar un canal extra
Los canales extra son canales ocultos, igual que el de hermandad: todos los que tienen el addon
en cualquiera de las hermandades entran solos. Se escriben desde su pestaña en Chat.
Crear o quitar uno queda en el registro de oficiales.

### `HU:MaySendSecrets`

quien entra recibe la lista de canales (el enlace la manda junto al mensaje fijado)
¿Le puedo mandar contraseñas a quien las pide al entrar (PQ)? De mi hermandad, o un contacto de fiar
de la suya (HU:PeerVerified): antes, cualquiera con la contraseña del canal que pedía el fijado se
llevaba también las de los canales extra y la nueva del canal

### `CPMsg`

Canal y contraseña desde la nota de oficial
  CP~canal~clave~t~autor~etiq     lo reparte un oficial (el más nuevo manda)
  CQ                              alguien que no lo tiene lo pide al entrar
Un oficial que lee "GU:c:Canal:clave" en una nota de oficial lo pasa a su hermandad
(un solo aviso) y a las demás hermandades; cada addon lo guarda para la próxima vez.
Si el propietario del canal está conectado, cambia él solo la contraseña del canal.

### `local noteMissT, noteMissWarned`

Ningún oficial tiene ya la línea GU:c en su nota (EPGP, CEPGP, DKP o Guild Roster Manager
escriben en todas las notas de oficial). Se sigue con el canal guardado (db.netChan, que no se
borra por esto) y se avisa una vez por sesión, cuando falta en dos lecturas de la lista
separadas al menos un minuto. La nota no se escribe sola: pisaríamos la de ese addon.

### `local cqVotes = {} -- [canal~clave~t] = { [compañero] = true }`

Respuestas a mi CQ de compañeros que no son oficial, enlace ni ayudante: cualquiera podía mandarme
un canal falso firmado por un oficial. Ahora hacen falta dos iguales de compañeros distintos; si
en 20 s solo ha contestado uno (y nadie lo contradice), se usa como provisional: cualquier canal
que llegue de un oficial, el enlace o un ayudante lo pisa aunque sea más viejo.

### `local pendingCP, pendingN = {}, 0`

Canal de otra hermandad cuya lista aún no está confirmada: antes esperaba 15 min y se perdía (la
clave nueva no salía de su hermandad y la comunidad se partía). Ahora se guarda el más nuevo de cada
firmante (de esa hermandad, traído por quien puede traerlo) y se aplica al confirmarse su lista;
y se pide la lista a otro contacto para que se confirme antes.

### en `CPCore`: `local carrier = sender`

(de un compañero de mi hermandad por susurro: es la respuesta a mi CQ al entrar. Solo vale
si lo he pedido hace poco o si quien contesta es oficial, enlace o ayudante: si no, cualquier
compañero podía mandarme por susurro un canal falso firmado por un oficial)

## Community.lua

### `local pending = {}   -- invitaciones que he mandado: [id] = { contact, tag, t }`

Cómo entra una hermandad nueva:
1. Un maestro u oficial de la comunidad pone el nombre de un maestro (o alguien que pueda
editar la Información de hermandad) de la hermandad nueva y una etiqueta.
2. A esa persona le sale un aviso. Si acepta, el addon escribe las líneas GU: en la
Información de su hermandad y le pasa el canal y la contraseña.
3. Las demás hermandades la añaden solas a su lista (no hace falta tocar su Información).

Mensajes (prefijo HUNI):
GV~id~ETIQ~título~hermandad          invitación (al contacto de la hermandad nueva)
GA~id~1|0~nombre o motivo             respuesta
GL~id~parte~partes~datos              la configuración, por partes (g=Nombre:ETIQ;t=Título;c=Canal:clave)
NG~ETIQ~nombre~1|0~autor~etiq~t       hermandad añadida (1) o quitada (0); el más nuevo manda

### en `HU:ApplyJoin`: `local lines = {}`

(con muchas hermandades no caben todas en la Información (máx. 500 letras):
se escribe la propia y las que quepan; las demás se guardan como añadidas desde el panel,
que el addon reparte solo)

### en `HU:ApplyJoin`: `local others, byLine = {}, {}`

el título y mi hermandad van siempre en la Información (así el addon funciona aunque no
haya ningún oficial conectado); las demás hermandades, en las notas de oficial de los
oficiales (solo las ven ellos) y, si no hay notas libres, en la Información

### `local emPending, emBy = {}, nil`

Lista (ordenada) de los emoticonos activos: { {code=, path=}, ... }
Texto con una línea por emoticono:  codigo=Interface\Icons\Nombre
Sustituye la lista entera (lo que no esté, se borra). Devuelve ok, nº, errores
El pack de Twitch que viene dentro del addon (EmotePack.lua): se añade a los que ya hay
(los del pack ganan si se repite un código). Devuelve ok, nº, errores
¿Están ya puestos todos los del pack?
Aviso en el chat cuando el maestro añade emoticonos (se juntan los que llegan seguidos)

## NoteConfig.lua

### `NoteLine`

Las líneas de la comunidad (GU:t:Título, GU:g:Hermandad:ETIQ, GU:r:ETIQ:N) se pueden poner en
las NOTAS DE OFICIAL de los oficiales (una por nota, máx. 31 letras), en vez de en la
Información de hermandad, que la ve cualquiera. Lo que no quepa va a la Información.

- Los oficiales (que ven las notas de oficial) las leen y las reparten a su hermandad.
- Los demás las reciben del addon y las guardan para la próxima vez.

NF~t~quien~parte~partes~líneas      configuración de las notas (líneas separadas por ";")
NK                                  pídeme la configuración (al entrar, si no la tengo)

### `InfoHasCommunity`

La llama la lista de la hermandad (solo los oficiales ven las notas)
¿Ha quedado escrita la Información de hermandad? (en Retail el juego puede no dejar al addon:
entonces la unión solo duraría hasta el /reload). Si no, se guarda una copia que el addon
reparte a la hermandad, y al maestro se le enseñan las líneas para pegarlas él.
(devuelve nil si ahora no se puede leer, por una restricción del juego: entonces no se toca la copia)

## ErrorShare.lua

### `local ASK_WINDOW = 600   -- durante 10 min se aceptan respuestas a mi petición`

Cada addon guarda sus errores (los 10 últimos, también entre sesiones) y no los manda a nadie.
Quien sepa la contraseña del chat unido (la de GU:c:Canal:clave) puede pedírselos a todos:

/gu errores pedir <contraseña>

La petición va por el chat de hermandad del addon y los enlaces la pasan a las demás
hermandades. Cada addon comprueba la contraseña y, si tiene errores guardados, se los
susurra (oculto) a quien los ha pedido. Le llegan a /gu errores y se quedan guardados.
La contraseña no viaja: va una firma hecha con ella, con el nombre de quien pide y la petición.

EQ~id~quien~firma                    (petición)
ER~id~remitente~versión~dónde~error  (un error, máx. 250 letras)

## MassLogin.lua

### Qué hay en el archivo

Guild Union - entradas masivas (tras un reinicio del servidor): la bienvenida a los que entran
(silencios, vetos, mensaje fijado, canales, colores, emoticonos...) la manda el enlace una sola vez
a toda la hermandad, en vez de a cada uno por susurro. Antes, con cientos entrando a la vez, eran
miles de susurros y cada uno que los recibía los volvía a repartir a toda su hermandad.

## Combat.lua

### Qué hay en el archivo

Guild Union - modo combate: en combate dentro de una banda o mazmorra el addon solo muestra y manda
el chat. Lo que no corre prisa (listas, historial, fichas, presencia en bloque, barridos de contactos)
se deja para después; lo que llega se guarda (como mucho la última lista por hermandad) y se procesa
al salir, por la entrada normal (con todas sus comprobaciones) y en trozos de ≤1 ms por fotograma.
Además, el enlace o un ayudante que entra en una instancia cede el papel hasta salir de ella.

### `combat = ...` · lo que llega y se aplaza (antes `DEFER_IN`)

lo que llega y se aplaza: "list" = listas de conectados, "data" = datos, "req" = peticiones,
"last" = de cada uno, la última. Lo declara cada orden en su `HU:RegisterMessage`; la entrada
(`HU.OnAddonMessage`) llama a `HU.CombatDispatch` con esas órdenes. Antes, Combat.lua envolvía al
cargarse los manejadores de `HU.comm` de las órdenes de `DEFER_IN`.
(los cambios pequeños de las listas, RC, NO se aplazan: con ellos llega al momento quién de los que se
comparten, GM, oficiales, enlace y ayudantes, entra o sale; tiene que verse en <1 s, como el chat)

### en `CatchUp`: `local long = diag.holdT and diag.releaseT and diag.releaseT - diag.holdT > 60`

(tras un combate largo o si se tiró algo: se piden a mi hermandad todas las listas de una vez;
contesta quien se encarga de cada hermandad, por GUILD, y les sirve a todos los que salen. Tras un
pull corto no hace falta: lo guardado basta)

### `local TRICKLE_AGE, TRICKLE_EVERY, TRICKLE_MS = 60, 0.1, 1.0`

En combate largo: las listas enteras (RB) que llevan más de TRICKLE_AGE s guardadas se procesan igual,
una cada TRICKLE_EVERY s como mucho y solo si lo que cuestan (lo medido) cabe en TRICKLE_MS. Así ninguna
lista se queda vieja toda la mazmorra. Lo demás (PL, PH, historial, fichas) espera a salir: algunos
cuestan más de 2 ms cada uno y no se pueden partir

## UI.lua

### `BINDING_HEADER_GUILDUNION = "GuildUnion"`

Atajo de teclado (Bindings.xml, Menú > Atajos de teclado > GuildUnion > «Abrir GuildUnion»).
La J abre GuildUnion (Jorge, 08/11): se pone como atajo temporal de la sesión (SetOverrideBinding), así
no se toca lo guardado del jugador y, sin el addon, la J vuelve a ser la de siempre. /gu tecla off la
quita; la ventana de hermandad del juego, con /gu hermandad

## UIWindows.lua

### Qué hay en el archivo

Guild Union Reduce - ventanas sueltas que siguen haciendo falta: copiar texto, novedades, crear
comunidad y enlaces web. (Las del panel viejo —hermandades, mapa, chat, emoticonos, información,
intrusos, invitaciones masivas, color, informar fallo— se quitaron en ReduceClean)

## BlizzTab.lua

### El buscador no mueve la lista de Blizzard (ReduceClean-39)

Hasta la 38 el buscador desplazaba la lista de miembros de Blizzard hasta la persona
(`ScrollToElementDataByPredicate`). Al desplazarla, Blizzard prepara las filas nuevas dentro de esa
llamada; si la llamada viene del addon, esas filas (y el `memberInfo` de cada una) quedan
contaminadas, y lo que el jugador haga luego con ese miembro en su ventana lo bloquea el juego:
cambiar el rango (`SetGuildRankOrder`), guardar la nota (`SetNote`), «Copiar nombre»
(`CopyToClipboard`). Informes de Jorge del 10/11 con la 37.
Ahora `ScrollTo` solo **mira**: busca la fila entre las que se ven (`FindFrameByPredicate`) y le pone
encima un resaltado nuestro (pegado a la fila, no dentro de ella). Durante 20 s lo vuelve a buscar
cada 0,25 s, así que si bajas con la rueda la marca te sigue. Si está en la lista pero no se ve,
lo dice una vez en el chat.
**49:** en la lista estrecha de la vista del chat el aviso es solo la flecha; en la ancha de Miembros,
flecha y texto, y mientras dura la marca cada fila que se ve lleva su **número de posición** a la
derecha (Blizzard no los pone y el «183 de 690» no servía de nada). Se leen las filas
(`GetFrames`, `FindFrameElementDataIndex`) y los números son nuestros, pegados a cada fila.
**43:** el aviso ya no parpadea: recuadro fijo con el borde de las fichas del juego, flecha dorada y
el nombre en dorado. Al borrar lo escrito en el buscador (X, Escape o borrar) se quitan el aviso y
la marca (`ClearMark`).
**45:** elegir a alguien de otra hermandad (Intro o clic) ya no abre un susurro: se dice de qué
hermandad es (`Pick`). Susurrar sigue en el clic derecho. La marca y el aviso ya no duran 20 s:
siguen mientras no cambies lo escrito en el buscador (se miran cada 0,25 s, solo con la ventana
abierta); al escribir otra cosa, borrarlo o esconderse el buscador, `ClearMark`.
**44:** el buscador sale en la vista de miembros y en la del chat; no en Información ni con nuestra
pestaña abierta (se miraba `IsShown` de la casilla, que sigue «puesta» aunque su lista esté
escondida; ahora `IsVisible`, y se recoloca al cambiar de vista y al abrir o cerrar nuestra pestaña,
`HU.SyncCharSearch`).
**42:** si está en la lista pero no se ve, una flecha parpadeando en el borde de la lista (abajo o
arriba, hacia donde está) con «Nombre: más abajo · 37 de 120». Solo lecturas de la lista
(`FindElementDataIndexByPredicate`, `GetDataIndexBegin/End`, `GetDataProviderSize`). Al aparecer
su fila, la flecha se quita y la fila se resalta. Probado con la 41 (10/11): mover la lista desde el
addon bloquea rango y «Copiar nombre» aunque luego la muevas tú; por eso no se mueve nunca.

### Clic derecho en la lista de Blizzard (ReduceClean-39)

`Menu.ModifyMenu("MENU_UNIT_COMMUNITIES_GUILD_MEMBER", …)`: la vía de Blizzard para que los addons
añadan opciones a sus menús. Blizzard llama a lo nuestro aparte (`securecallfunction`), después de
montar lo suyo, así que sus opciones no se contaminan. Solo para oficiales (`HU:CanPin`) y no sobre
uno mismo: «Silenciar 10 min», «Quitar silencio», «Buscar lo que ha dicho» (lo mismo que el menú
de nuestra lista, `PlayerMenu`).

### Qué hay en el archivo

Guild Union Reduce - todo dentro de la ventana de hermandad de Blizzard:
  * una pestaña más en su lateral («GuildUnion»), hecha con piezas de Blizzard
  * el chat de las otras hermandades, también en el chat de esa ventana
No se toca nada de lo suyo (ni sus listas ni sus botones): solo se pone encima. Tocar lo suyo es lo
que hace que Forever bloquee acciones de esa ventana (pasó con /ginvite).

### `local rebuild   -- { epochs = {...}, k = 0, ptr = 1 } mientras Blizzard repinta`

Cuando Blizzard rehace su chat (al abrir la ventana o cambiar de canal), borra lo nuestro. Para
que vuelva intercalado por hora: al empezar (su Clear) se mira la lista de mensajes que va a
pintar, y cada vez que pinta uno (su AddMessage) se meten detrás los nuestros que van antes del
siguiente suyo. Al acabar (DisplayChat), los que queden. No se rehace nada suyo: solo se añade.

### Buscador de personajes en la pestaña de miembros de Blizzard, junt…

Buscador de personajes en la pestaña de miembros de Blizzard, junto a su filtro (como el de
GuildManagement): busca en mi hermandad y en los oficiales conectados de las otras. La lista de
Blizzard no se filtra (tocar sus datos bloquea sus botones).

### en `ScrollTo`: `local found = box.FindElementDataByPredicate and select(2, pcall(box.FindElem…`

(desconectado y la lista no enseña desconectados: no se marca la casilla desde el addon —eso
contaminaría la lista y bloquearía sus botones—; se hace brillar para que la marques tú, y
al marcarla se marca a la persona)

## UnionRoster.lua

### Qué hay en el archivo

Una fila de botones rojos del juego sobre la ventana de hermandad (`CommunitiesFrame`; se monta al cargar
`Blizzard_Communities`): **Chat · Miembros · Comercio · Calendario**, con imagen en vez de texto (24/11, Jorge: el
nombre sale al pasar el ratón; `Iconize`): Chat y Miembros, las de los iconos del juego a la derecha de la ventana
(`UI_Chat`, `achievement_guildperk_everybodysfriend`); Comercio, el martillo de herrería; Calendario, el calendario del
minimapa de Forever (atlas `ui-hud-minimap-calendar-button`). Miembros es la lista de toda la unión; Comercio y
Calendario son marcos hijos de `cover` que llenan `HU:BuildTrade` y `HU:BuildCalendar`. El botón elegido va negro (`HU.DJ.PickRed`); el
buscador de personajes solo sale en Chat y Miembros (`HU.charSearchOff`). Estado: `tab` (0 = Chat, 1 = Miembros, 2-3
= las otras) y `mode` («roster», «chat» o nil). El Banco (UnionBank.lua) se quitó el 24/11: sin la parte de red no
enseñaba los bancos de las otras hermandades y las peticiones no le llegaban a nadie; está en el historial de Git.

**La lista del juego no se toca.** Lo nuestro (`cover`) es hijo de la ventana, no de su lista, y va encima: 26 px
más arriba (tapa sus títulos, no la casilla «Mostrar desconectados» ni el buscador) y 22 px más a la derecha
(tapa su barra). La casilla solo se lee (`GetChecked`). Si el addon metiera filas en la lista del juego o abriera
su ficha, la ventana quedaría «contaminada» y el juego bloquearía lo que solo hace su interfaz: ascender, degradar,
expulsar y guardar notas. Nivel 300 como mínimo y capa `HIGH`: el borde de su lista (`InsetFrame`, nivel 100)
tapaba el primer título, y la barra del chat del juego, en otra capa, asomaba encima de los botones.

### Miembros: la lista de la unión

`Entries()` junta a los conectados de la unión (`HU:UnionRosterEntries`: los míos de la lista del juego, los de
las otras de Miembros o del /who) y, con «Mostrar desconectados», mis desconectados (de las otras no se sabe).
Las listas RB que las otras mandan solas (`HU.remoteRoster[tag].members`) ponen el rango a quien llegó sin él y
añaden a quien falte; quien sigue sin rango (del /who) va con el rango más bajo de mi hermandad (`noRank`): así se
mezcla por nivel y no se queda al final. Columnas como las del juego más Hermandad; tras el nombre, corona
(maestro) o espadas (oficial; rojas, admin: `HU:RoleOf`); desconectado, en Zona cuánto lleva (`Ago`). Nota: solo
la pública de mi hermandad (las otras no llegan), que `ReadNotes` lee tras cada `GUILD_ROSTER_UPDATE`.
Orden (`Less`): rango (0 = maestro, en todas), nivel de mayor a menor y nombre, todas mezcladas; un clic en un
título ordena por esa columna, otro al revés y el tercero vuelve al de siempre (`sortKey`, `sortDesc`). `Paint` pinta
las filas que caben, pide las listas que falten (`HU:WantUnionMembers(nil)`) y dice abajo cómo va cada una
(`HU:UnionMembersStatus`); se repinta con `GUILD_ROSTER_UPDATE`, `CHANGED` «unionMembers» y cada 2 s.

**«Solo mi hermandad» = la lista del juego** (`mine`, solo en Miembros; se recuerda en `HU.db.unionRosterMine`;
`RealList()`). Lo nuestro (`cover`) se esconde entero y queda la ventana del juego tal cual: sus títulos para
ordenar, su casilla de desconectados y, al pinchar, **su ficha, la única que guarda notas**. En Forever ningún
addon puede guardarlas (`C_GuildInfo.SetNote` restringida; Ultimate Guild Roster lo dice igual; GuildNoteUpdater
dejó de funcionar en 12.0) y si el addon abre esa ficha, mueve esa lista o abre su diálogo, el juego lo bloquea.
Para encontrar a alguien en ella, el buscador de personajes (BlizzTab.lua, `ScrollTo`): flecha con su posición y
resaltado, solo leyendo la lista. La casilla sigue a la vista para volver; las otras secciones, quitándola.

### La ficha de un miembro

Clic izquierdo: nuestra ficha (`GuildUnionMemberCard`, a la derecha de los iconos de la ventana; otro clic en la
misma persona la cierra), para todas las hermandades. La del juego no se abre desde aquí: abierta por un addon, el
juego bloquearía sus botones (expulsar, rango, notas). Con su aspecto y sus textos: hermandad, zona, rango, última
conexión, profesiones (solo de mi hermandad, `C_Club.GetMemberInfo`, y «Ver recetas»: `QueryGuildMemberRecipes`),
nota y nota de oficial (si puedo verla; con «GU:», «(configuración de GuildUnion)»); abajo, Echar (como el clic
derecho: activo con los de mi hermandad que mi rango puede echar, `HU:CanKickMember`, y con los de otra si soy
oficial) e Invitar al grupo. Las notas de los de mi hermandad se pueden pinchar (`EditNotesInGame`): ponen «Solo
mi hermandad» (la lista del juego) y marcan a esa persona con el buscador (`HU.MarkInGameList`, BlizzTab.lua),
porque solo la ficha del juego las guarda. En la vista de chat, un clic en la lista de la derecha del juego abre
la ficha del juego, sin tocarla (hasta el 23/11 se cerraba y salía la nuestra: así no se podían guardar notas).

### Varios a la vez y clic derecho

Ctrl suma o quita uno, Mayús elige del último al de ahora (en el orden de la lista) y un clic solo elige uno y abre
su ficha, como el buscador de personajes (`HU.UnionRosterPick`). Clic derecho: sobre uno de varios elegidos, menú
«N elegidos»; si no, el de GuildUnion (`HU.PlayerMenu`). Los dos acaban con `AddGuildActions`:
- De mi hermandad: «Cambiar rango» (con permiso; `HU:RankMacro` da un /gpromote o /gdemote por rango, o por qué
  no) y «Echar de la hermandad», que sale con los que mi rango puede echar y solo a ellos (`HU:CanKickMember`:
  permiso y rango por debajo del mío; `HU.GuildCmd("gremove")`; `RemoveFromGuild` lo vuelve a mirar y, si no, dice
  por qué), por la ventana de órdenes (`HU:TypeLines`, Orders.lua): en Forever un addon no puede hacerlo; cada orden
  la mandas tú.
- De otra, si soy oficial (`HU:CanOfficer`): «Pedir a su hermandad que lo eche» (`HU:AskGuildKick`, GK) y, si son
  todos de la misma y se saben sus rangos, «Pedir a su hermandad cambio de rango» (`HU:AskGuildRank`, GP). Va por
  susurro a alguien suyo con el addon, que lo reparte; a sus oficiales les sale en «Peticiones de oficiales».

### La fila en las dos vistas: `Sync` y `Layout`

`Sync` mira la vista con `IsVisible` (el `IsShown` de la casilla sigue verdadero con su lista escondida): «roster»
si se ve la casilla de desconectados; «chat» si se ven el chat y su lista (la ventana pequeña, sin lista, no
cuenta). Al entrar en la de chat se empieza en Chat; en la de miembros, en Miembros o en la sección pulsada desde
el chat (`wantTab`). Corre con `OnShow`/`OnHide` de la casilla, la lista y el chat, al abrir la ventana y, en el
acto, tras `SetDisplayMode` (si no, se ven un instante los botones en el sitio de la vista anterior).
`Layout`: los cinco botones caben siempre (se estrechan) y la fila va en el mismo sitio en las dos vistas
(23 y -34 de `CommunitiesList`). En la de miembros, `cover` tapa la lista; en la de chat es solo la fila (los clics
pasan al chat) y el chat y su lista se atan debajo (`ChatAnchors`); el juego recoloca esa lista al actualizarla y
un `hooksecurefunc` sobre su `SetPoint` la vuelve a poner en el acto (`placing`). Al volver a la de miembros, lista
y chat vuelven a sus sitios del juego antes de poner la fila encima (si no, lista y fila quedarían atadas la una a
la otra); el chat, a mano: el juego solo lo coloca al maximizar. En combate ni la lista ni el chat se mueven: llevan
colgados nuestros botones seguros y el juego lo bloquea (`ADDON_ACTION_BLOCKED`); `GameLocked` lo apunta
(`secureLater`) y se colocan al salir del combate (`PLAYER_REGEN_ENABLED` → `Sync`). `cover` sale siempre en las dos
vistas (`HU.db.unionRosterOff` no se usa: `Sync` lo borra).

### Botones seguros

Cambiar de vista desde el addon dejaría la ventana «tocada» y el juego bloquearía rangos y notas: los botones que
cambian de vista son seguros (`SecureActionButtonTemplate`, `type=click`) y los pulsa el juego.
- «Chat» en la vista de miembros (`GuildUnionRosterChatSecure`) pulsa `ChatTab`; Miembros, Comercio y Calendario en
  la de chat (`GuildUnionChatSection1`…`3`) pulsan `RosterTab`; su `PreClick` apunta la sección (`wantTab`).
- Cuatro sitios: el 0 es «Chat» (en la vista de miembros, el seguro; en la de chat, el nuestro, elegido) y del 1 al 3
  las secciones (en la vista de chat, los seguros). Un día fueron un solo botón que cambiaba entre Chat y Miembros;
  Jorge prefirió uno para cada uno (24/11).
- **Arriba lo nuestro, debajo lo del juego** (Jorge, 24/11): la fila sube `ROW_UP` (31) al sitio del desplegable
  «Guild» (vista de chat) o de la casilla «Mostrar desconectados» (vista de miembros), y esos bajan `DROP` (34) a donde
  estaba la fila (`TopRow`): el desplegable (`StreamDropdown`, con nuestro buscador, que va atado a él), los cascos del
  chat de voz (`VoiceChatHeadset`) y la casilla (que sube a la capa `HIGH` para verse encima de lo nuestro, igual que el
  buscador). «Solo mi hermandad» baja con ellos. Lo de debajo no se mueve: los títulos, Comercio y Calendario van
  `ROW_UP` más abajo de la fila, y en la vista de chat el chat y su lista también (`ChatAnchors`). El juego recoloca el
  desplegable y los cascos al agrandar la ventana: un enganche a su `SetPoint` los vuelve a bajar. Solo fuera de
  combate: la casilla lleva colgados nuestros botones seguros.
- Centrados (24/11): `Layout` calcula el ancho de lo nuestro en esa vista (en la de miembros, el de la lista del juego
  y 25 más; en la de chat, de la columna de comunidades al borde de la ventana) y de ahí `x0`, el principio de la
  fila. Con esa misma cuenta van los nuestros (atados a la fila) y los seguros (atados a la lista del juego o a la
  columna, fuera de combate).
- Los botones de arriba no piden /who (24/11: al volver de Comercio a Miembros, el juego lo bloqueó dentro de ese
  clic); lo piden los títulos, las filas, la rueda y la barra (`WhoTick`).
- En combate no se puede enseñar, esconder ni mover un botón seguro: cuelgan de algo que solo se ve en su vista
  (la casilla de desconectados; los de sección, el chat) y se colocan fuera de combate (`secureLater`). Tampoco se
  pueden crear: si `Blizzard_Communities` se carga en combate, la fila se monta al salir de él (`Setup`, `setupLater`).
- `Unpress`: la vista cambia antes de soltar el ratón y se quedaban «pulsados»; al volver a verse se sueltan.

### Botones de abajo: Peticiones de oficiales · Ver registro · Invitar miembro

En la vista de miembros, a la izquierda de «Ajustes de hermandad» del juego y colgados de la casilla de
desconectados; en la de chat, los dos primeros los pone BlizzTab.lua, colgados del «Invitar miembro» del juego.
- «Invitar miembro»: botón seguro que pulsa el del juego (`f.InviteButton`, que solo sale en la vista de chat);
  si lo pulsara el addon, el juego bloquearía la invitación.
- «Ver registro» (`HU:ShowInviteLog`, InviteLog.lua): Invitaciones y Salidas; el juego solo guarda las últimas
  entradas y aquí se van guardando (`HU.db.inviteLog`, `HU.db.leaveLog`, por hermandad, hasta 2.000).
- «Peticiones de oficiales» (`HU:ShowRequests`): otra hermandad pide echar (GK) o cambiar el rango (GP) a alguien
  de la mía; sin ventana emergente, se guarda (`HU.db.kickRequests`, 24 h) y el botón lleva el número
  (`HU:KickRequestCount`: las que puedo hacer). Aceptar abre las órdenes y, al mandarlas, contesta (`AnswerKick`,
  `AnswerRank`) y apunta la salida (`HU:LogRequestedKick`).

### Contador de conectados de la unión

`GuildUnionUnionCounts`, en la barra del título, a la izquierda de minimizar y cerrar: es lo único que no se
mueve (los cascos del juego cambian de sitio) y el contador del juego queda tapado por la fila. Sale solo en la
vista de chat y en la de miembros (nuestras pestañas): lo decide `Sync`. «N/M conectados» de toda la unión: la mía
de `GetNumGuildMembers`, las otras de su lista RB (`HU.remoteRoster[tag].online`, `.total`), «+» si falta alguna; al
pasar el ratón, cada hermandad. El texto lo pone `UpdateCounts` (solo si se ve), en `Sync` y cada 3 s.

### /who: `WhoTick`

El juego solo deja hacer /who desde un clic del jugador (UnionMembers.lua): en Miembros, los botones, los títulos,
las filas, cualquier clic en `cover` y lo que mueve el jugador en la lista (la rueda, pulsar o arrastrar la barra y
sus flechas) llaman a `WhoTick` → `HU:UnionWhoTick(nil)`, que busca con /who una hermandad sin lista. No va en
`OnVerticalScroll`: salta también cuando la lista se recoloca sola (al pintarla o cambiar de tamaño), sin clic.
Nunca dentro de `Sync` (`inSync`; `Sync` va con `pcall` para no dejarlo puesto): `Sync` corre tras `SetDisplayMode`
y, si el cambio de vista viene de un botón seguro, dentro de su clic, y el juego bloquea ese /who
(`ADDON_ACTION_BLOCKED`). Tampoco en combate (`InCombatLockdown`): puede esperar (el código no da otro motivo).

### BlizzTab.lua: la mitad derecha es «Configuración»

En el panel de GuildUnion (pestaña GuildUnion o ventana propia), la mitad derecha la monta UnionConfig.lua:
`panel.config = HU:BuildUnionConfig(panel)`. Lo de antes («Oficiales conectados» / «Miembros», elegir hermandad,
«Buscar con /who», la lista) pasa a un marco escondido (`stash`): su código sigue (`RefreshOfficers`), pero no se
ve; sin «Miembros» que pulsar, el panel ya no lanza /who. A la izquierda ya no está el botón «Lista negra»: va en
Configuración > Lista negra; su ventana (`HU:ShowBlacklist`, Blacklist.lua) solo se abre con `/gu listanegra`.

## ChatTabs.lua · Chattynator

Chattynator (addon de chat de otro autor, con versión para Forever) esconde las ventanas y pestañas de
chat del juego y pone las suyas. Leído en su versión 234:
  * Los mensajes normales los pinta copiando el mecanismo del juego: pasa los filtros y usa
    `CHAT_FLAG_<marca>`, así que la etiqueta propia, las marcas de mención y los emoticonos funcionan.
  * De lo que escriben los addons solo recoge `DEFAULT_CHAT_FRAME:AddMessage`. Lo escrito en otra
    ventana del juego (la pestaña «Buscar grupo») no se ve.
  * Usa la caja de escribir del juego (`ChatFrame1EditBox`): el Tab de menciones y `/glf` funcionan.
Por eso, con Chattynator cargado (`HU.UsingChattynator`), `HU:FramesFor` devuelve solo la ventana
principal para todos los tipos, y no se crean las pestañas propias. No se usa su
`AddMessageToWindowAndTab`: marca el mensaje para una sola pestaña y, si el jugador no tiene activados
ahí los mensajes de addon, no lo vería en ningún sitio.

## Channel.lua · la etiqueta como enlace

`HU:TagText(tag, hex, addon)` pinta `<ETIQ>` como enlace de addon (`|Haddon:GuildUnion:tag:ETIQ:x|h`).
El juego avisa de cualquier enlace del chat con `ChatFrame.OnHyperlinkEnter` y `OnHyperlinkLeave`
(EventRegistry); ahí se enseña un recuadro con el nombre de la hermandad, miembros y conectados
(de `HU.rosterTotal/rosterOnline` en la mía; de `remoteRoster[tag].total/.online/.updated` en las
otras, con «hace X min») y, en las líneas propias, si el autor tiene el addon. El clic no hace nada.
## Channel.lua · no entrar al canal donde el juego lo bloquea

En un campo de batalla o una arena el juego bloquea `JoinTemporaryChannel` (ADDON_ACTION_BLOCKED), y
al entrar al juego `EnsureJoined` lo intentaba una vez por segundo durante 20 s: tantos bloqueos
seguidos sacan el aviso del juego «tus addons están dando muchos problemas» (visto el 12/11).

- `HU:CanJoinNow()` dice si se puede intentar: no con el chat bloqueado (`IsChatLockedDown`), no en
  zona `pvp`/`arena` (`IsInInstance`) y no con una partida en estado `active` (`GetBattlefieldStatus`:
  desde que se acepta, antes de la pantalla de carga). `EnsureJoined` no intenta nada mientras tanto.
- Las mazmorras y bandas no se cortan por zona: ahí solo manda `IsChatLockedDown`, para no dejar sin
  chat a quien entra al juego dentro de una.
- Red de seguridad: el intento se marca con `HU.expectBlock = "join"`; si aun así sale bloqueado,
  ese canal espera 60 s (`c.blockedT`) en vez de reintentar cada segundo.
- Al cambiar de zona (`PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`) se vuelve a mirar a los 2 s,
  para entrar al canal nada más salir de la partida.

## Channel.lua · memoria de clases

El color del nombre en el chat unido sale de la clase, y la clase se buscaba en cada mensaje: por el
identificador del mensaje (`GetPlayerInfoByGUID`), en la lista de mi hermandad o en la lista corta de
las otras (`HU:ClassOfName`). Si ninguna la daba, naranja; el mismo jugador cambiaba de color según
por dónde llegara su mensaje.

- `RememberClass` / `RecallClass` (locales, junto a `ClassColored`): cuando se sabe la clase se apunta
  en `db.classMemo` (`[nombre en minúsculas] = número de clase`, de la cuenta) y, cuando no se sabe, se
  usa la apuntada. Lo que llega con identificador manda y corrige lo apuntado.
- Tope: dos tandas de `MEMO_GEN` nombres (`classMemo` y `classMemoOld`). Al llenarse la actual pasa a
  vieja y se tira la vieja anterior; lo que se vuelve a usar de la vieja se rescata a la actual.
- Los repasos del historial no traen identificador: usan la memoria, nunca la escriben mal.
- Fallo arreglado de paso: en el eco (`[ETIQ:E]`, lo de alguien sin addon que reenvía su enlace)
  `OnUnionChat` cambiaba el autor pero dejaba el identificador de quien reenvía, y el nombre salía con
  la clase del que reenviaba. Ahora el eco va sin identificador.
- Límite: de quien nunca se ha sabido la clase (miembro sin addon de otra hermandad que no está en la
  lista corta) sigue saliendo naranja. Arreglarlo es mandar la clase dentro del eco: comunicación.

## Core.lua · filtros del chat y valores secretos (campos de batalla)

Error visto el 12/11 (BugSack, con rastro): `attempt to perform string conversion on a secret string
value (execution tainted by 'GuildUnion')` en `ChatHistory_GetToken`, llamado desde
`MessageEventHandler` (ChatFrameOverrides.lua:683) con `chatType="GUILD"` y `chanSender=<secret>`.

Qué pasa: el juego solo llama a los filtros de addons si el **texto** se puede leer
(`canaccessvalue(...)` mira el primer dato). Hay momentos en que el texto de `/g` se lee pero el
identificador de quien escribe (`arg12`) es secreto. `MentionFilter` devolvía todos los datos del
mensaje, también ese; al volver de un addon quedan manchados y el juego falla al usarlos
(`strlower` de un secreto) y la línea no se pinta. El rastro del 12/11 fue **en una mazmorra**
(Jorge); no se sabe cuándo exactamente sella el juego el identificador (¿en combate?): a Jorge en
mazmorra no le salió y a otro sí.

Dos defensas (la segunda, cambiada en la copia 84):
- **Copia 114 (15/11): el respaldo deja de depender de un solo contacto. Versión 5.4.34.** Visto en
  el juego: a un mismo autor lo leía una hermandad y otra no, porque el chat del respaldo (CW) iba a
  UN contacto por hermandad y, si ese tenía una versión vieja que lo tiraba, su hermandad entera lo
  perdía. Ideas tomadas del estudio de Olympus (sin copiar código): varios caminos y contar una vez.
  (1) `HU:BestPeers(tag, 2)`: el CW va a dos contactos, primero los que tienen 5.4.33 o posterior
  (`p.ver`, del saludo). (2) `Duplicate` recuerda quién trajo la línea: la misma por el respaldo
  desde OTRO compañero en 15 s es la misma; quien ya la tiene no la reparte otra vez (CG).
  (3) Eco: un solo eco tarde ya no da el canal por roto 5 min; hacen falta dos seguidos (`echoMiss`).
  (4) `/gu visto Nombre`: líneas de ese autor entregadas por el canal antes de cualquier filtro
  (`HU.chanRaw`) y enseñadas (`HU.chanShown`). (5) `/gu version Nombre`. (6) Aviso en el chat, cada
  10 min, cuando no estoy en el canal, con el motivo. (7) Nombre del canal tapado en los avisos de
  depuración y en `/gu estado`. (8) `Defer` guarda la orden: el aviso de un reintento la dice bien.
- **Copia 115 (15/11): `/gu sonda N`, solo para medir.** En los diagnósticos del juego llegan cientos
  de sondas `LP`, que son mensajes ocultos por el canal: en Forever hoy sí se entregan (el 04/11
  Olympus midió 0 de 123). Antes de usarlos como camino de emergencia del chat, sin intermediarios,
  se mide: N mensajes numerados de 90 letras por `HU20C` (`SD~tanda~i~n~ETIQ~relleno`), uno cada
  1,2 s; cada receptor dice «te han llegado X de N» y qué números faltan (también en `/gu diag`).
  Solo oficiales; de cada remitente, una sonda por minuto. No cambia cómo viaja el chat.
- **Copia 113 (15/11): el nombre del canal, tapado en los avisos de depuración.** Con `/gu debug`,
  «Arranque rápido…» y «Config OK» escribían el nombre del canal entero y salía en las capturas.
  Ahora `HU.MaskChannel` (Core.lua): dos letras y puntos, como `/gu diag`.
- **Copia 112 (15/11): que quitar el eco no esconda ni haga pasar por perdido nada.** `IsEchoLine`
  más estricta: solo líneas de un compañero que TIENE el addon (`guildPeers`), nunca las mías ni las
  de quien no lo tiene; el aviso de eco, solo la frase exacta. Cada línea escondida se cuenta
  (`ChatDrop`). Y el eco de versiones viejas que llega por el respaldo (`CW` con `[ETIQ:E]`) se
  cuenta aparte, «eco de una versión vieja (no es un mensaje perdido)», sin retenerlo ni comprobarlo:
  el aviso «Mensaje rechazado (seguridad): CW» dice ahora si era eco o chat de verdad.
- **Copia 111 (15/11): el eco, fuera del todo otra vez.** Jorge: «el eco NUNCA lo quiero activado,
  porque rompe el formato». Fuera `Echo.lua`, sus enganches, `/gu eco` y el botón del maestro (lo que
  volvió en la 107 por un diagnóstico mío equivocado). `[ETIQ:E]` se descarta. Lo nuevo: `HU:IsEchoLine`
  (Channel.lua) reconoce por su forma las líneas de eco que un enlace con una versión hasta la 5.4.31
  sigue escribiendo en /g («[ETIQ] Nombre: texto» con la etiqueta de otra hermandad, y el aviso de
  eco activado) y `GuildLineHidden` las esconde al escribir la línea (ChatPaint.lua), sin filtro. Con
  el chat bloqueado o `/gu pintar off` se ven. Consecuencia sabida y aceptada: quien no tiene el addon
  no lee a las otras hermandades ni ellas a él.
- **Copias 109 y 110 (15/11): mensajes de chat que se perdían entre gente con addon. Versión 5.4.33.**
  Dos causas vistas en el juego con `/gu debug` y `/gu carril`:
  1. **Carriles partidos.** `OfferLane` rechazaba una generación más de 1 por encima de la propia.
     Quien se quedaba dos atrás (o instalaba de cero) no podía seguir a la comunidad cuando esta subía
     de carril: canal distinto, y no se leían (carril 0 gen 2 frente a carril 1 gen 8). Ahora lo que
     dice el enlace o un oficial (`LaneStrong`) se sigue sin tope; fuera `LANE_GEN_STEP`.
  2. **Chat del respaldo tirado.** Quien no puede escribir por el canal manda su chat por susurro
     (CW) a un contacto de cada otra hermandad, que lo reparte (CG). `AllowAddonMessage` tiraba el CW
     si el remitente no estaba en una lista ni «visto en el canal»; con la lista corta de ahora, casi
     nadie de fuera lo está. Y como el contacto lo tiraba, su hermandad entera lo perdía. Ahora se
     retiene (`Hold`, 180 s) y `HU:VerifyChatSender` lo comprueba por dos vías: lectura del canal (solo
     entra quien tiene la contraseña; como mucho cada 20 s) y pregunta a su hermandad (guardia, MQ/MA;
     `FinishTag` llama a `ReplayHeld`). `ReplayHeld` acepta `Vouched` o, para el chat, `InAnyGuild`.
  Además: `HU.diagChat` (contadores en `/gu diag`: enviado por canal/respaldo, recibido por cada vía,
  retenidos y confirmados, carril) y, en la 110, `HU.ChatDrop(motivo, quién)`: cada sitio donde un
  mensaje de chat se descartaba en silencio lo apunta con su motivo. El aviso «Acción de oficial
  rechazada» dice la orden (`HU.curCmd`). Corregido el separador de las líneas de eco agrupadas, que
  en las copias 107 y 108 quedó como carácter 24 en vez de `` (error al escribir el parche).
- **Copia 108 (15/11): historial de oficiales con marca de addon y filtro por hermandad.** Solo
  ventana (`History.lua`). Cada línea lleva, tras la etiqueta, el punto de la hermandad en color si
  el autor tiene el addon, en gris si no, o «?» si no se sabe (`HU:AuthorHasAddon`: lo que se sabe
  AHORA, no cuando escribió; el historial no lo guarda). Botón «Hermandad: Todas / <ETIQ>» arriba a
  la derecha: cada clic pasa a la siguiente y repite la búsqueda; lo de mi PC se filtra al buscar
  (`opts.tag`), lo que llega de otros oficiales al pintar (`W.tagFilter`). «Ajustes» ya sale
  traducido en inglés.
- **Copia 107 (14/11): el eco vuelve, sin filtros de chat.** Al quitar `Echo.lua` (copia 98) se fue
  también lo que el enlace hacía por los compañeros SIN addon: pasar su /g a las otras hermandades
  (`EchoOutgoing`, líneas `[ETIQ:E] Autor: texto` por el respaldo CW/CG) y aceptarlas al recibir
  (`EchoUnwrap`). Resultado en el juego: quien no tenía el addon dejó de oírse fuera de su hermandad.
  Vuelve `Echo.lua` tal cual estaba en la 5.4.31 (copia 89/90) y sus enganches en `Channel.lua`
  (`OnUnionChat`, `EchoIncoming`, `EchoSeen`, `EchoOutgoing`, `EchoStarName`), `/gu eco` y el botón del
  maestro (ahora en la fila de «Ajustes»). Lo que cambia respecto a la 5.4.31: las líneas de eco que
  el enlace escribe en /g ya no las esconde un filtro de chat (era lo que rompía el chat bloqueado):
  las esconde `ChatPaint.lua` al escribir la línea, porque `HU:GuildLineHidden` vuelve a mirar
  `IsEchoLine`. Con el texto secreto (chat bloqueado) o con `/gu pintar off` no se esconden: quien
  tiene el addon las ve repetidas en /g, pero no se pierde nada.
- **Copia 106 (14/11): botón «Registro de invitaciones» en la ventana de hermandad del juego.** Lo
  crea `Setup` (BlizzTab.lua) como hijo de `CommunitiesFrame.InviteButton` («Invitar miembro»),
  pegado a su izquierda: se ve y se esconde con él, y `SyncTab` lo esconde si la comunidad elegida
  no es la hermandad. Abre `HU:ShowInviteLog`. Sustituye al botón «Invitaciones» que la copia 103
  puso dentro de la ventana de la lista negra; `/gu invitaciones` sigue.
- **Copia 105 (14/11):** «Oficiales conectados» ordenada por papel (maestro, administrador, oficial)
  y nombre (`OfficerEntries`, BlizzTab.lua).
- **Copia 104 (14/11): aviso al invitar a alguien de la lista negra.** Blacklist.lua engancha con
  `hooksecurefunc` `C_GuildInfo.Invite` (lo que usan `/ginvite`, el menú de clic derecho y el
  cuadro de invitar del juego) y `GuildInvite` si existe. Va después de la función del juego, así
  que no la toca ni puede parar la invitación: si el nombre está en `db.bans`, a quien invita le
  sale un texto rojo en el centro de la pantalla (`UIErrorsFrame`), un sonido y una línea en su
  chat con quién lo vetó y el motivo. Vale para cualquiera con el addon, no solo oficiales.
- **Copia 103 (14/11): registro de invitaciones (InviteLog.lua) y armazón común de ventanas de lista
  (ListWindow.lua).** El juego apunta en su registro de hermandad quién invitó a quién
  (`GetNumGuildEvents` / `GetGuildEventInfo`, tipo `"invite"`), pero solo conserva las últimas
  entradas. InviteLog.lua se lo pide (`QueryGuildEventLog`, al entrar, cada 10 min y al abrir la
  ventana), y al llegar `GUILD_EVENT_LOG_UPDATE` guarda las invitaciones nuevas en
  `db.inviteLog[nombre de hermandad]` = `{ t, by, who }` (tope 2.000). El juego no da fecha sino
  «hace cuánto» (años, meses, días, horas): se pasa a hora aproximada y una entrada ya guardada se
  reconoce por mismo invitador + mismo invitado + hora parecida (margen de 2 h o el 10 % de la
  antigüedad). No se reparte entre jugadores: cada uno guarda lo que ve su addon. `HU:InvitedBy(nombre)`
  lo usa el aviso de la lista negra («Lo invitó X»). Ventana `HU:ShowInviteLog` (`/gu invitaciones`
  y botón «Invitaciones» en la ventana de la lista negra): fecha, quién invitó, a quién (blanco
  sigue en la hermandad, gris ya no está, rojo en la lista negra) y buscador.
  ListWindow.lua: `HU.NewListWindow` (ventana movible con título, texto, cabecera de columnas, lista
  con barra y `win:Fill`), `HU.NewEditBox`, `HU.NewButton`; la usan las dos ventanas, para no repetir.
- **Copia 102 (14/11): el aviso de la lista negra va al chat de oficiales (/o).** `BlacklistCheck`
  escribe con `HU.RawSend(…, "OFFICER")` una línea que empieza por `[Guild Union] ` (texto llano, la
  ven también los oficiales sin addon; no cruza a otras hermandades porque el puente solo reenvía lo
  que el jugador teclea). Para que no la repitan todos los oficiales con addon: cada uno espera
  2–12 s al azar y, si mientras ve en /o una línea con esa marca y el nombre, lo da por dicho
  (`db.blackSaid[k]` = hora); de cada persona se dice como mucho una vez cada 24 h. Si ya se dijo
  hoy o no se puede escribir en /o (sin permiso, chat bloqueado), se le dice solo a él con
  `HU:Print`. El botón «Comprobar ahora» nunca escribe en /o. Quitar a alguien de la lista borra su
  marca de «dicho».
- **Copia 101 (14/11): cada hermandad coteja solo a sus miembros** (decisión de Jorge; la copia 100
  miraba también las otras y se deshizo). La lista es común; `HU:BlacklistCheck` cruza `db.bans` solo
  con `HU.roster`. Botón «Comprobar ahora»: `HU:BlacklistCheck(true)` repasa también a los ya
  avisados y contesta aunque no haya nadie.
- **Copia 99 (14/11): lista negra de la comunidad (Blacklist.lua).** No añade datos ni mensajes
  nuevos: es la lista de vetados que ya existía (`db.bans`, `HU:SetBan`, mensaje `BN`, Social.lua),
  que se reparte entre hermandades, se entrega a quien entra y se repasa cada 5 min, pero que no
  tenía ningún botón desde la limpieza. Blacklist.lua pone: (1) la ventana `HU:ShowBlacklist`
  (botón «Lista negra» en la zona de oficiales de la pestaña, y `/gu listanegra`): lista de vetados
  con quién lo vetó y el motivo, en rojo el que está ahora en mi hermandad; añadir (con motivo) y
  quitar, para quien cumple `HU:CanPin` (maestro, administradores y oficiales); (2) el cotejo
  `HU:BlacklistCheck`: cada 60 s cruza `db.bans` con `HU.roster` (mi hermandad) y avisa una vez por
  persona y sesión a quien puede actuar. Vetar sigue haciendo lo de siempre: fuera del canal de la
  comunidad y sus líneas ocultas. Va por nombre de personaje: un personaje secundario no se detecta.
- **Copia 98 (14/11) = 5.4.32, limpieza antes de subir.** Lo que dicen las notas de más abajo sobre
  `selfPaint`, `SyncPvpFilters`, `MentionFilter`, `PaintOwnLine`, `OwnTagFlag`, `HideFilter` y el eco
  es historia: ese código ya no existe. Quitado de Channel.lua (de 1.924 a ~1.720 líneas) y Core.lua;
  `Echo.lua` fuera del paquete y todas sus llamadas quitadas (una línea `[ETIQ:E]` de una versión
  vieja se descarta en `OnUnionChat`; `GU:e:` de la Información se sigue leyendo en Config.lua para
  no tomarlo por una línea desconocida, pero nadie lo usa). Queda un solo filtro de chat, el de
  `CHAT_MSG_SYSTEM` (Comm.lua, vía `HU.AddChatFilter`).
  Archivo nuevo **ChatPaint.lua**: el adorno de las líneas de mi hermandad (`DecorateOwnLine` y la
  sustitución de `AddMessage`), separado de Channel.lua. Lo que estaba repetido entre las líneas de
  las otras hermandades y las de la mía va ahora en dos funciones de Channel.lua que usan los dos
  caminos: `HU:NamePrefix` (marca de mención + punto o etiqueta + icono de rango; con `has == false`
  sale en gris, compañero sin addon) y `HU:GuildColored` (el `[Hermandad]` en color). El manejador
  de `CHAT_MSG_GUILD` que guarda el historial usa `HU:GuildLineHidden` en vez de repetir sus
  condiciones. Pendiente para la división grande: Comm.lua (3.876 líneas), Channel.lua, History.lua.
- **Copias 96–97 (14/11): Ajustes con casillas.** Tres filas bajo «Ajustes» (BlizzTab.lua): Marca
  (dos redondeles, etiqueta o punto), Hermandad (casilla «En color») y Emoticonos (casilla
  «Mostrar»), con una raya de división encima.
- **Copia 95 (14/11): «Formato de texto» en Ajustes.** Dos ajustes por jugador, con un botón cada
  uno bajo «Ajustes» en la pestaña del addon (BlizzTab.lua): `db.chatMark` (`"dot"` de serie, o
  `"tag"`) decide si delante del nombre va el punto del color de la hermandad o la etiqueta
  `<ETIQ>`; `db.chatGuildColor` (apagado de serie) pinta el `[Hermandad]` en el color de la
  hermandad que habla. Valen igual para las líneas de las otras hermandades (`FormatLineParts`) y
  para las de la mía (`DecorateOwnLine`, que envuelve en color el enlace `|Hchannel:` que pone el
  juego). Sustituyen a `chatStyle` y `chatTag` de las copias 92–93; `/gu estilo` desaparece y
  `/gu etiqueta on/off` cambia `chatMark`.
- **Copia 94 (14/11, prueba): las líneas de mi hermandad se adornan «en el paso 3».** El fallo del
  bloqueo del chat venía de intervenir en los filtros (antes de que el juego monte la línea). Ahora
  el juego recibe, filtra y monta la línea de /g y /o sin nada nuestro por medio, y solo al final,
  cuando llama a `AddMessage` de la ventana, entra el addon: `WrapFrame` (Channel.lua) sustituye
  `ChatFrameN.AddMessage` por una función que, si el evento es `CHAT_MSG_GUILD` u `OFFICER`, pasa el
  texto por `DecorateOwnLine` (dentro de `pcall`) y luego llama a la original. El juego le pasa a
  `AddMessage` el evento y sus argumentos (`eventArgs`), así que autor y mensaje salen de ahí, sin
  filtro ni escucha aparte. `DecorateOwnLine` mete delante del primer `|Hplayer:` la marca de
  mención, el punto (`chatStyle`) o la etiqueta (`chatTag`) y el icono de rango, y pasa el cuerpo
  por menciones y emoticonos; devuelve `false` para no escribir la línea (`GuildLineHidden`:
  silenciados y líneas propias ocultas). Con texto, mensaje o autor secretos no toca nada: la línea
  sale en el formato del juego. Las líneas que pinta el addon (otras hermandades, avisos) no llevan
  evento y pasan sin tocar. Interruptor: `db.ownPaint` (`/gu pintar on/off`). Riesgo a probar en
  mazmorra: al sustituir `AddMessage`, lo que el juego ejecuta después en ese mismo manejador
  (`SetLastTellTarget` en susurros, `FlashTabIfNotShown`) corre marcado por el addon.
- **Copia 93 (14/11, prueba): punto de color.** `db.chatStyle` elige cómo se distingue la hermandad
  en las líneas de las otras: `"dot"` (de serie) pone delante del nombre un punto teñido con el color
  de la hermandad (`HU:DotText`, `Media\dot.tga`, dentro del enlace de la etiqueta para que salga su
  recuadro al pasar el ratón); `"color"` es lo de la copia 92. `/gu estilo` cambia de uno a otro.
- **Copia 92 (14/11): color por hermandad en vez de etiqueta.** En `HU:FormatLineParts` (línea del
  chat del juego, no la compacta de la ventana del addon) el trozo de `CHAT_GUILD_GET` /
  `CHAT_OFFICER_GET` que va antes del nombre (`[Hermandad]`) se envuelve en el color de la hermandad
  (`GuildColorHex`) cuando la línea es de otra hermandad. La etiqueta `<ETIQ>` en el chat pasa a
  depender de `db.chatTag` (apagada de serie; `/gu etiqueta on`); `db.showTag` queda para la ventana
  del addon. Las líneas de mi hermandad las pinta el juego y no se tocan.
- **Copia 91 (prueba para verla en el juego, 14/11): sin filtros en los chats de jugadores y sin eco.**
  Idea tomada de cómo trabaja Olympus (solo filtra mensajes del sistema). `HU.CHAT_FILTERS = false`
  en Channel.lua hace que `AddFilter` no registre nada: fuera `MentionFilter` (/g y /o: etiqueta,
  icono de rango, menciones resaltadas, emoticonos, `selfPaint`), el de `GuildLineHidden`
  (silenciados, líneas propias ocultas, eco) y `HideFilter` (canal de la unión, que ya se quita de
  las ventanas con `HU:HideChannel`). Queda solo el de `CHAT_MSG_SYSTEM` (Comm.lua). El juego pinta
  las líneas de mi hermandad tal cual; las de las otras las sigue pintando el addon. `Echo.lua` no
  se carga (quitado del .toc, guardado en `_quitados/`): todo el que lo llama comprueba antes que
  exista (`if HU.EchoIncoming then …`), así que el eco queda apagado en las dos direcciones y lo
  que llegue como `[ETIQ:E]` de versiones anteriores se descarta. El código que queda sin uso
  (`MentionFilter`, `PaintOwnLine`, `OwnTagFlag`, `selfPaint`, `SyncPvpFilters`, `cfg.echo`,
  `GU:e:1`) NO se ha borrado todavía: se limpia cuando Jorge dé el visto bueno al aspecto.
- **Copia 90 (hipótesis, sin probar en el juego):** ante un dato secreto el filtro ya no devuelve
  nada, ni siquiera `false`. Rastro del 13/11 23:24 en mazmorra con la 5.4.31: `/g` con el
  identificador secreto y el texto legible → `ChatFrameFilters.lua` sí llama al filtro
  (`canaccessvalue(...)` deja pasar), nuestro `false` llega manchado a `results[1]`, el juego lo lee
  y queda «tainted by GuildUnion»; al pintar falla en `HistoryKeeper.lua:35` (`strlower` de un
  secreto) y la línea no sale. Sin valores devueltos no hay nada manchado que leer.
- `HU.AddChatFilter`: si **cualquier** dato del mensaje es secreto (`AnySecret`), el filtro contesta
  solo `false` y no devuelve datos (hasta la copia 89; ver la línea de arriba). Antes miraba solo texto y nombre. Es la defensa principal: va
  mensaje a mensaje y vale en cualquier sitio, mazmorras incluidas. Indicio de que basta: el filtro
  de silenciados de `/g` lleva semanas contestando solo `true`/`false` sin que saliera este error.
- `HU.selfPaint` (copia 84, 5.4.31; sustituye al quitar y poner filtros de la 5.4.30, que no
  arreglaba nada). Rastro del 13/11 con la 5.4.30: `HistoryKeeper.lua:9: attempted to index a table
  that cannot be accessed while tainted (execution tainted by 'GuildUnion')`, desde
  `MessageEventHandler:682`, `chatType="GUILD"`, `accessIDs=<forbidden table>`.
  - Por qué: la tabla `accessIDs` del juego usa como clave un texto con el identificador de quien
    escribe. En cuanto el juego guarda una clave secreta (cualquier línea de jugador en una partida),
    la tabla queda prohibida para ejecución manchada **hasta el `/reload`**. `MentionFilter` devuelve
    la línea cambiada (texto, marca con etiqueta e icono): eso mancha la ejecución de esa línea, el
    juego falla al consultar la tabla y **no la pinta**. Un filtro que solo contesta `true`/`false`
    no mancha (visto con la copia 82).
  - Síntoma: tras una partida no se ven las líneas de `/g` y `/o` de la propia hermandad; sí `/s`,
    `/group` y las de las otras hermandades (esas las pinta el addon con `AddMessage`).
  - Arreglo: `HU.selfPaint` se enciende al entrar a una partida (`HU:InPvpNow`) o al ver cualquier
    dato secreto en una línea de chat (un marco aparte en Channel.lua mira todos los datos de los
    chats de jugadores; `AnySecret` en los filtros también lo enciende) y no se apaga hasta el
    `/reload`. Con él encendido `MentionFilter` contesta `true` (descartar) y pinta la línea él mismo
    en esa ventana (`PaintOwnLine`, con `FormatLineParts` como las de las otras hermandades). Antes
    de pintar pregunta a `HU:GuildLineHidden` (eco, silenciados, líneas propias ocultas), porque al
    descartar ya no se llama al filtro siguiente.
  - Diferencias de la línea pintada por el addon frente a la del juego: el enlace del nombre no
    lleva el número de línea (no sirve para denunciar esa línea desde el menú), no sale la marca
    `<AFK>`/`<DND>`, y otros addons que filtren `/g` después de nosotros no la ven. La hora sí se pone
    si el jugador la tiene activada.
  - Sin configurar (`HU.myTag` vacío) no se pinta nada propio: contesta `false` y la pinta el juego.
  - Sin probar en el juego.

Otro aviso parecido visto la misma noche, `tainted by 'TradeSkillMaster'` al escribir, no es
nuestro (ese addon sustituye `HandleModifiedItemClick` y `ChatEdit_InsertLink`).

## Copia 117 (15/11): mudanza de carril hiperestricta

**Qué se vio en el juego.** Recién entrado, el juego rechaza los mensajes ocultos al canal durante el primer minuto (`/gu sonda 30`: aceptó 0 de 30 al entrar y 30 de 30 un minuto después, mismo personaje), aunque el texto normal sí sale. El enlace sondeaba cada 10 s y se mudaba con 6 rechazos en unos 20 s: cada enlace que entraba subía de carril a toda la comunidad. Quien no recibía el aviso se quedaba en otro canal viendo volver sus propias líneas, sin usar el respaldo y sin nada apuntado. En el registro de Jorge: 14 cambios en 5 días; el 15/11, de carril 2 a 4 tras dos entradas del enlace.

**Mudanza automática (`ChannelSendResult`, `TryMoveLane`).** Solo el enlace, y solo con todo esto a la vez:
1. `LANE_SETTLE` = 600 s desde la última pantalla de carga (`PLAYER_ENTERING_WORLD`, `LOADING_SCREEN_DISABLED`). Antes de eso los rechazos se cuentan aparte (`HU.laneStats.ignored`) y no suman.
2. `LANE_REFUSE_SECS` = 300 s de rechazos seguidos (resultado 7), con al menos `LANE_REFUSE_MIN` = 20, sin un solo envío aceptado en medio.
3. En ese rato no ha llegado nada por el canal, ni texto ni oculto ni el eco propio (`HU.chanInT`, que pone `MarkChannelSeen`).
4. El enlace de otra hermandad lo confirma por susurro (`LV~carril`, vale `LANE_VOTE_TTL` = 120 s). El `LV` nunca mueve por sí solo: solo cuenta si a mí me pasa lo mismo.

Los que no son el enlace ya no hacen nada con sus rechazos. Seguir al enlace o a un oficial (`OfferLane`) no cambia, para no separarse de quien lleve la 5.4.33.

**A mano:** `/gu carril subir` (oficiales) sube un carril a todos; `/gu carril reiniciar` sigue devolviendo al principal.

**Consecuencia:** con un solo enlace conectado en la comunidad no hay mudanza automática (falta la regla 4). Mientras, el texto sin eco va por el respaldo.

**Mientras haya versiones anteriores activas**, sus enlaces siguen subiendo el carril al entrar y esta versión los sigue. Se acaba cuando `GU:v` las pause.

**También en esta copia** (lo mismo que la 116, que quitaba los carriles y no se usa): espera del eco por envío y no por texto; descartes que eran mudos contados en `/gu diag` (etiqueta que no está en mi `GU:g`, autor silenciado, «al enviar: no sales en una hermandad unida», tope del reparto CF, tope de 100 retenidos); repetidos por dos caminos aparte; línea con lo caducado en la cola y lo rechazado por admisión; aviso «no estás en el canal» solo tras unos 3 min seguidos fuera.

**Pendiente:** identificador único por mensaje y confirmación de entrega.

## Copia 118 (15/11): carriles con doble confirmación

Sobre la 117. Todo decidido por Jorge el 15/11.

- **Subida automática:** además de las reglas de la 117, la tienen que confirmar **dos hermandades distintas** (`LANE_VOTES_NEEDED`; todas las otras si hay menos de dos) y no hay ninguna si ya ha habido una subida, de quien sea, en las últimas 24 h (`db.laneRaisedT`, `LANE_AUTO_GAP`).
- **A mano, cosa de dos** (`HU:ProposeLane`, `OnLaneProposal`, `ConfirmLane`): `/gu carril subir` o `/gu carril reiniciar` de un oficial manda `LO~up|reset` por GUILD; lo ven los oficiales de su hermandad y se hace solo si otro escribe `/gu carril confirmar` en 2 min (lo ejecuta el que confirma). El maestro puede solo, escribiéndolo dos veces en 30 s.
- **A quién se sigue** (`LaneStrong`, Comm.lua): cada uno solo a los de su hermandad (su enlace o un oficial suyo, por GUILD). A los de otra hermandad, por susurro, solo les hace caso el enlace, que luego lo dice a los suyos. Antes cualquier oficial de la comunidad movía a cualquiera.
- **Gente en otra sala** (`NoteLane` en `OfferLane`, `HU:LaneStrays`): se apunta la sala que dice cada uno en su saludo o `LN`. Si durante 2 min hay alguien en otra, aviso a los oficiales, una línea cada 30 min como mucho. Solo avisa. `/gu carril` lo enseña siempre, junto con cómo va la regla automática (`HU:LaneStatusText`).
- **Cada cambio de sala** se imprime a los oficiales con quién y por qué (`SetLaneState`).
- **Caducidad:** se mira cada 5 s y no cada 60. Se quitará en la versión que numere los mensajes (acordado: sin falsas alarmas ya no tiene razón de ser).
- **Fuera del chat** el aviso «La lista de X está en disputa» (se queda en `/gu debug`).
- **Sin revisión automática** (Jorge, 15/11: «no movemos gente»): nadie cambia de sala solo por ver a otros en otra. En su lugar, **`/gu carril juntar`** (`HU:GatherLane`): un oficial trae a toda la comunidad a SU sala, la que sea, con una generación por encima de la más alta que ha oído. Lo puede hacer solo, escribiéndolo dos veces en 30 s (no crea una sala nueva). El aviso de «gente en otra sala» lo recomienda.

## Copia 119 = 5.4.35 (15/11): que las versiones viejas no puedan subir de carril

Jorge, 15/11: «pon que pueda moverme a la 0 y los muevo a la 0 y hacemos que el resto de addons no puedan subir de canal». Visto ese día: de la sala 2 a la 9 en tres horas, un escalón por cada enlace con versión vieja que entraba.

- **El oficial actualizado se queda el puesto de enlace** (`RelayScore`): dice entre 173 y 199 puntos, por encima de lo máximo de un oficial con versión vieja (157 + 15 de ventaja del enlace = 172) y dentro del tope que todos aceptan de un oficial (`SaneScore`, 199). En las versiones viejas solo el enlace sondea y sube de carril, así que con un oficial actualizado conectado nadie de su hermandad lo sube. Ocupado no puntúa así. Es de transición: quitarlo cuando todos estén actualizados.
- **Solo se obedece a esta versión o posterior** (`HU:LaneTrusted`, `LANE_TRUST_VERSION`, en `OfferLane`): lo que diga sobre la sala una versión anterior se apunta para el aviso de «gente en otra sala» y se cuenta (`laneStats.oldIgnored`), pero no mueve a nadie. La versión se saca del saludo (`guildPeers`, `remote`); del primer saludo de alguien de otra hermandad aún no se sabe y se ignora hasta el siguiente.
- **`/gu carril reiniciar` lo puede un oficial solo**, escribiéndolo dos veces, igual que `juntar`. Subir sigue siendo cosa de dos (o el maestro). El reinicio va con una generación por encima de la más alta oída.
- **Número 5.4.35** y no 5.4.34: el zip de prueba de la copia 115 llevaba 5.4.34 y tiene el fallo de los carriles.
- **Límites:** sin un oficial actualizado conectado en una hermandad, su enlace viejo sigue subiendo a los suyos (a los actualizados ya no los arrastra). Las versiones anteriores a la 5.4.33 no pueden seguir un reinicio si van más de una generación por detrás.

## Copia 120 = 5.4.36 (15/11)

- **De una versión vieja sí se obedece «a la sala principal»** (`OfferLane`): solo se ignoran sus órdenes hacia otra sala (las falsas alarmas son siempre subidas). Con la 119 (5.4.35), quien actualizaba en una hermandad donde nadie más lo había hecho no hacía caso a su enlace y se quedaba en la sala guardada hasta que le caducara. El contador `laneStats.oldIgnored` ya solo suma lo que habría cambiado de sala.
- **Cualquiera con la versión nueva puntúa alto para ser el enlace** (`RelayScore`; Jorge, 15/11): el oficial, 173–199; quien no lo es, 80–99 (lo máximo que las versiones viejas le aceptan a un no oficial es 99; un no oficial viejo llega a 72). A un oficial con versión vieja (100 o más) un no oficial no le gana.
- **El enlace que no es oficial solo guarda el puesto**: ni inicia la subida automática (`TryMoveLane`) ni vale su confirmación (`LV`).
- **5.4.36 y no 5.4.35:** la 5.4.35 ya estaba en GitHub con su etiqueta.

## Copia 121 (15/11, de prueba): formato de Prat

`PratBridge.lua`. Petición de usuarios: que las líneas de otras hermandades tengan el formato que cada uno lleva en su addon de chat, sin tener que elegirlo.

- **Líneas de otras hermandades** (`HU:PratLine`, llamado desde `HU:Display`): se le pide la línea a Prat con `Prat.Format(ventana, "CHAT_MSG_GUILD", nil, <argumentos de un mensaje de hermandad>)`, que es lo que Prat ofrece a otros addons (lo usa WIM). Devuelve el texto con el formato del jugador; se escribe con `AddMessage` como siempre. Si Prat no está, está apagado (`/gu prat off`), falla o no devuelve nada, se escribe la línea de siempre: nunca se pierde una línea por esto. Todo va dentro de `pcall`.
- **El punto o la etiqueta** (`Pre`, aviso `Prat_PreAddMessage`): Prat avisa antes de juntar las partes de cada línea; ahí se pone lo nuestro en `m.pP` (lo que va justo antes del nombre) y los emoticonos y menciones en `m.MESSAGE`. Vale para las líneas de otras hermandades y para las de la mía, que con Prat se quedaban sin punto porque Prat pone los corchetes fuera del enlace del nombre. Los silenciados se cortan con `m.DONOTPROCESS`.
- **`ChatPaint.lua`** no toca nada con Prat enganchado.
- **`/gu prat`** enseña cómo va (cuántas líneas con formato de Prat, cuántas con el de siempre, fallos y el último error); `/gu prat off|on` lo apaga o enciende.
- **Sin probar en el juego.** Riesgos apuntados: `Prat.Format` llama por dentro a `ChatHistory_GetAccessID` del juego, que tras un campo de batalla da error a los addons (el mismo del chat que no se pintaba); aquí lo recoge el `pcall` y sale la línea de siempre. Los filtros de chat de otros addons para la hermandad se aplican también a estas líneas. La ventana de hermandad del juego (BlizzTab) sigue con el formato propio.
- **Copia 122:** a Prat se le pasa el nombre con espacio («Nombre Apellido», como en las líneas de la propia hermandad; con guion tomaba el apellido por un reino). Y antes de pedirle la línea se le dice el nivel y la clase del autor si se saben (`TellPrat` → `PlayerNames:addName`): solo los de la lista corta de su hermandad. Para el nivel de todos haría falta que viajara con cada mensaje: va con el cambio de formato de la fase 1.
- **Copia 161 (16/11): nombres grises con Prat.** Prat pinta el nombre con el color de clase solo si la sabe él (su lista de la hermandad o `GetPlayerInfoByGUID`); si no, usa su «color común», gris (0,65) por defecto, y así salían todos («nunca se ha pintado bien en el Prat», Jorge). Su módulo de nombres colorea en `Prat_FrameMessage`, antes de `Prat_PreAddMessage`, así que en `Pre` (`ClassName`) se vuelve a pintar `m.PLAYER` con la clase que sabe GuildUnion (`HU:ClassFor`: identificador, listas de las hermandades y lo recordado; el mismo color que sin Prat). Solo si el jugador tiene Prat en «color por clase» (`PlayerNames.db.profile.colormode == "CLASS"`); si ha elegido otro modo, no se toca. `/gu prat` cuenta cuántas (`pratStats.class`).
- **Copia 123:** el recuadro de la etiqueta o el punto de una hermandad enseña además la suma de miembros de toda la comunidad (`OnTagEnter`, Channel.lua). La propia es `rosterTotal`; las otras, `remoteRoster[tag].total`; si falta alguna, «al menos N».

## Copia 125 (16/11, de prueba): pestaña dentro de Whisper Messenger

`WMPanel.lua`. Petición de Jorge: que el chat de las otras hermandades salga dentro de la ventana de Whisper Messenger.

- **Lo que no se puede:** añadir líneas a su conversación «Guild» ni filas a su lista. Esa conversación la llena él con los eventos del juego y no ofrece ninguna función para añadir mensajes.
- **Lo que sí ofrece:** `WhisperMessengerAPI.Connect("GuildUnion")` devuelve las funciones para otros addons; `RegisterPanel(id, { title, onShow, onHide, onSplit, badge, onMarkAllRead })` pone una pestaña junto a «Whispers» y «Groups» y, al pulsarla, llama a `onShow(marco)` con el hueco vacío. `onSplit(marco, ancho)` dice el ancho de su lista. `badge()` devuelve los no leídos; `RefreshPanelBadge(id)` lo repinta. `GetLook()` da sus colores.
- **Lo que dibuja el addon** en ese hueco: a la izquierda, «Todas las hermandades» y una fila por hermandad (filtro); a la derecha, las últimas líneas del historial (`db.history`, tipo `main`) y las nuevas en directo; abajo, una caja que escribe en el chat de la propia hermandad (el addon lo lleva a las otras como siempre).
- **En directo:** `HU.AddHistory` se envuelve una vez en `PLAYER_LOGIN`; cada entrada nueva se escribe si el panel está a la vista y, si no y es de otra hermandad, suma un no leído.
- **`/gu wm`** enseña si Whisper Messenger está, si la pestaña se registró y el último fallo al dibujar.
- **Sin probar en el juego.** Sin Whisper Messenger no hace nada. El usuario tiene que tener permitidas las integraciones (vienen permitidas).
- **Copias 126 y 127:** dentro de la pestaña, el chat va en burbujas imitando las de Whisper Messenger (sus piezas son privadas y no usa ninguna librería de interfaz: todo es código suyo). Icono de clase del juego (`Interface\\ICONS\\ClassIcon_<clase>`) recortado en redondo con la máscara de retratos; cabecera con punto o etiqueta, nombre y hora; burbuja con borde del color del fondo aclarado; sus medidas (icono 24–26, márgenes 12 y 8, 75 % del ancho). Las letras son las suyas si están (`WM_ChatNormal`, `WM_HighlightSmall`, `WM_Normal`: las crea con nombre y siguen los ajustes del jugador); si no, las del juego.
- **Copias 128 y 129:** panel rehecho contra capturas de Jorge, pieza a pieza. Fondo liso casi negro en todo el hueco (sin pintarlo se veía la textura de la ventana); cabecera con icono enmarcado, título y marca pequeña gris; sobre la burbuja solo nombre con color de clase y hora como la suya; burbuja azul muy oscuro con borde claro, letra 2 puntos mayor y más margen; lista con icono enmarcado, último mensaje y hora; caja de escribir negra con borde dorado y flecha de enviar. El marco dorado y la flecha son imágenes de Whisper Messenger cargadas de su carpeta (`Interface\\AddOns\\WhisperMessenger\\Media`), no copiadas.
- **Copias 130 y 131:** el panel lee el aspecto de Whisper Messenger (`Skin()`: `WhisperMessengerDB.settings.hudStyle`, `themePreset`, `bubbleColorPreset`, y `GetLook()`) y usa sus mismos valores (licencia MIT). Burbujas: con estilo classic o retail, el marco de los recuadros de ayuda del juego (`TooltipBackdropTemplate`) teñido, con el borde aclarado un 35 %; con off, fondo liso. Fondos: con retail, las texturas del juego `auctionhouse-background-index` (mensajes) y `Professions-background-summarylist` (lista); con classic, transparentes; con off, colores. Fila elegida: `UI-QuestLogTitleHighlight` sumada y teñida con el color de acento del tema; al pasar el ratón, `UI-QuestTitleHighlight`. Cabecera y franja de escribir: color de cromo del tema. Caja de escribir: `Common-Input-Border` en tres trozos. Las letras se ponen con `SetFontObject`.
- **Copia 132:** sombra de 10 px arriba y abajo de los mensajes (negro al 35 %, en degradado, solo si hay mensajes por ese lado) y bocadillos que se desvanecen en los últimos 24 px del borde, como en Whisper Messenger (`UpdateEdges`).
- **Copia 133:** zona de escribir como la suya con estilo nativo: sin franja detrás (transparente), caja con el borde de las cajas de búsqueda del juego (`common-search-border-*`) y sin relleno, y tres botones de 26 (respuestas rápidas, emojis, enviar). El de emojis abre los emoticonos de Guild Union (los suyos son reacciones que solo ve quien tiene Whisper Messenger) y mete el código en la caja; el de respuestas rápidas lee `WhisperMessengerDB.settings.quickReplies` (o sus cuatro por defecto) y mete el texto en la caja sin enviarlo.
- **Copias 134 y 135:** la caja de escribir vuelve al borde de las cajas de texto (`Common-Input-Border`) teñido de dorado: el de las cajas de búsqueda (`common-search-border-*`), que es el que usa él con retail, salía roto en Forever. Desplegables con el recuadro del juego sin teñir (negro, borde dorado). El selector de emojis enseña sus 18 (hoja `reactions.png`, 9 por fila) y escribe «:nombre:» en la caja, igual que el suyo; las burbujas del panel pintan «:nombre:» como dibujo. Respuestas rápidas con fila de 23, ancho fijo y resalte dorado.
- **Copias 136 a 138:** caja de escribir con borde fino redondeado (`UI-Tooltip-Border`, 10) dorado e interior oscuro; desplegables en la capa `FULLSCREEN_DIALOG`, nivel 200, con el recuadro del juego sin teñir (azul muy oscuro, borde claro: así son los suyos); `HU:ClassFor` da la clase por las mismas vías que el chat y, sin clase, el nombre va en naranja; los mensajes propios van a la derecha, con la hora y «Tú» encima y el avatar al otro lado.
- **Copia 139:** con el estilo nativo, el margen del bocadillo lleva además el grosor del borde del recuadro (4 por lado), como hace él: bocadillo de una línea ~33 px de alto (antes ~25) y 8 px más de ancho; 6 px entre el nombre y el bocadillo.
- **Copia 140:** brillo de la cabecera como el suyo: capa blanca al 5 % en degradado vertical (transparente abajo, entera arriba) sobre el color de la cabecera.
- **Copias 141 y 142:** el borde de la caja de escribir depende del estilo (dorado con retail, gris plateado con classic). Con «off»: bocadillos y caja con fondo liso y esquinas redondeadas (el borde de los recuadros pintado del color del fondo); la caja ya no se baja de nivel, porque quedaba al de la franja de fondo, que con «off» sí se pinta y la tapaba; el texto de ayuda cuelga de la caja de texto.
- **Copia 143:** con «off», los fondos de los bocadillos y de la caja de escribir se montan como los suyos: cinco rectángulos y cuatro esquinas (cuartos de `TempPortraitAlphaMaskSmall`), todo del mismo color, radio 8, sin borde. Y el brillo blanco al 5 % también sobre la franja de escribir.
- **Copia 144:** la zona de escribir rehecha pieza por pieza según `Composer.lua`, `ComposerSurface.lua` y `ComposerLayout.lua` de Whisper Messenger: panel de 44; caja de texto a 8 y 8, de 28 de alto; texto con márgenes 8, 8, 4, 4; ayuda a 8; botones de 26 con 4 de hueco y 8 de margen. Los adornos van en la propia caja de texto (antes iban en un marco aparte): con «off», `Rounded` (radio 8) con el color de la caja, fondo de cromo, raya arriba y brillo; con «classic» y «retail», `NativeBorder` (tres trozos, laterales de 8 a toda la altura: `common-search-border-*` con «retail» si el juego los tiene, si no `Common-Input-Border`), sin fondo ni raya, texto blanco y ayuda gris 0,5. `/gu wm` dice qué borde ha usado.
- **Copia 146:** (1) botón de copiar en cada bocadillo de la pestaña de Whisper Messenger, como su `HoverCopy.lua`: icono de 14 al 45 % que sale en la esquina al pasar el ratón; abre `UI:ShowCopy` con el texto sin colores ni enlaces. (2) Con Prat, `WholeName` en `PratBridge.lua`: Prat parte el nombre por el guion y trata el apellido como reino (lo acorta y lo pinta aparte); antes de que escriba la línea se devuelve el nombre entero a `m.PLAYER` y se vacía `m.SERVER`, tanto en las líneas de otra hermandad como en las de la mía. `HU.pratStats.whole` cuenta las veces.
- **Copia 147 (de prueba):** `HU:FixChannelOrder` apagado (`SWAP_CHANNELS = false` en `Channel.lua`). El chat se envía al canal por número; se sospecha, sin confirmar, que el intercambio descuadra ese número entre el juego y el servidor. Consecuencia conocida: el canal de la comunidad puede quedarse con el /1 o el /2 si entra antes que los del juego.
- **Copia 147, `Report.lua` (nuevo):** `/gu ids` enseña los números de canal de este jugador (nombres tapados) y le pregunta al servidor quién hay en el número de la comunidad (`ListChannelByName`, lo mismo que `/chatlist N`; respuesta por `CHAT_MSG_CHANNEL_LIST`, 3 s): compara número, nombre y cuánta de esa gente conoce el addon, y dice si cuadra. `/gu todo` (o `informe`) junta en la ventana de copiar: el diagnóstico (`HU:DiagLines`, antes dentro de la orden `diag` en `Core.lua`), los números de canal, la sala y quién está en otra con su versión, las versiones de quien ha saludado y los enlaces, y por autor cuántas líneas han llegado por el canal y cuántas se han enseñado (marca a quien solo llega por el respaldo), Prat, Whisper Messenger y la cola.
- **Copia 148 (5.4.39):** más medidas en `/gu todo`, todas de solo apuntar: `HU.chatLog` (últimos 60 mensajes de otras hermandades: hora, autor, vía, pintado / repetido / descartado y por qué; lo rellenan `OnUnionChat` y `HU.ChatDrop`), `HU.sendLog` (mis últimos 15 envíos, con lo que tardó el eco; `WatchEcho`, `GotEcho`, `ChatFallback`) y `HU.echoStats`, `db.laneLog` (30 cambios de sala o generación con motivo, guardado entre sesiones; `SetLaneState`), quién falta en el canal (saludados hace poco que el servidor no nombra), por hermandad (conectados, dentro del canal, contactos del respaldo y su versión), huellas de la configuración (16 bits la lista de hermandades, 12 bits canal+contraseña: para comparar sin enseñar), sesión (tiempos, entradas y salidas mías del canal cada 5 s, memoria, últimos errores). **`/gu prueba Nombre Apellido`**: 5 líneas de texto `#GUT tanda n destinatario` por el canal (no casan con el formato del chat: nadie las ve y las versiones anteriores las ignoran; se interceptan en `CHAT_MSG_CHANNEL` antes de la cola) más un aviso oculto `TQ~` por el canal con el prefijo `HU20C`; el addon del destinatario cuenta 7 s y contesta `TR~` en oculto por el canal. Una prueba por remitente cada 20 s. Las 5 líneas salen en el mismo instante de la orden, que es cuando el juego deja mandar texto a un canal.
- **Copia 149:** en `/gu todo`, «quién falta en el canal» y el recuento de mi hermandad solo cuentan a los conectados (`roster[k].online`); de las otras hermandades, a quien ha saludado en los últimos 5 min. En la 148 salían como «fuera del canal» los que se habían desconectado hacía poco.
- **Copia 150 (5.4.40) — chat por los dos caminos y salas.** Tras la revisión completa del 16/11. **Chat:** (1) `HU:Forward` manda cada línea por el canal Y por el respaldo (`ChatFallback`), siempre; el eco propio solo queda para estadística (lo de oficiales sigue igual). (2) `HU.comm.CW`: enseñar y repartir se deciden por separado (`HU.lastVerdict`): el contacto reparte por `CG` aunque ya tuviera la línea por el canal, salvo que otro compañero ya la haya repartido (`CarriedByOther`). (3) `Duplicate` cuenta, por autor y texto, las enseñadas y las llegadas por cada sitio (`c`, `w:portador`): es repetida si por ese sitio no han llegado más de las enseñadas; ventana de 120 s. (4) `SendCW`: sin contacto reciente tira de dos conectados de `remoteRoster`; si tampoco, avisa al jugador cuando esa línea no tenía otro camino. (5) `HU.comm.CG` ya no exige que quien reparte salga en mi lista. (6) `pcall` a `HU:Display` y «pintado» se apunta después. (7) `HU.OnChannelText`: lo que llega antes de `HU.ready` se guarda (60) y se repone en `Start`. (8) `Comm.lua`, cola: el chat urgente va detrás del último chat urgente (marca `chatU`), en orden, y delante del resto. **Canal:** `RejoinSoon` reinicia `backoff`, que además tiene tope de 60 s. **Salas:** `LaneBetter` a igual generación prefiere la sala más baja; `MoveLane` y `RaiseLane` suben la generación; `LaneState` olvida una vez la sala guardada (`db.laneMig = 150`); la vía «contacto» de `OfferLane` ya no sube de sala y solo deja pasar un reinicio (sala 0 con generación mayor), que además se le pasa al enlace por `LX`; `LANE_TRUST_VERSION = 5.4.40`. **Candado:** línea `GU:l:N` en la Información de mi hermandad (`HU.ParseLaneLock`, `HU:SetLaneLock`, `db.laneLock`): `LaneState` devuelve siempre esa sala y `SetLaneState` rechaza cualquier otra. **Sin hacer:** la retención de remitentes aún no reconocidos (caduca sin contarse y se repone desordenada) y contar como descarte los eventos con valor secreto.
- **Copia 151 (5.4.40), tras la revisión independiente de la 150.** Corregido: (1) `Resend` no le manda a un contacto lo que ya recibió de mí (pintaba y repartía dos veces a toda su hermandad cuando el otro contacto se desconectaba). (2) Solo el chat principal (`token == "m"`) va siempre por los dos caminos; los canales extra, como antes, y `HU.comm.CW` no enseña lo de un canal extra en el que no estoy. (3) `OnChatLost` no avisa si la línea también salió por el canal (`HU.alsoChan`). (4) El aviso de «sin contacto» va como parámetro `solo` de `SendCW`, no como variable suelta. (5) `laneLock` y `laneMig` son por personaje (`HU.PER_CHAR`); la sala de la cuenta se olvida una vez con `laneMigA`, cuando ya se sabe el canal. (6) Una línea repetida solo se reparte si antes se pintó de verdad (`seen.ok`). (7) El contacto con más de 60 mensajes en cola no reparte (se cuenta); `CG` caduca a los 20 s. (8) El orden nuevo de la cola, solo para `CW`/`CG`/`CF`. (9) `BestPeers` prefiere contactos con 5.4.40. (11) `oldIgnored` vuelve a contar. (12) Un contacto sin comprobar no puede subir la generación más de 5. (13) Con la sala fijada no se piden confirmaciones de subida. Además: `/gu prueba` manda 3 líneas, y el informe enseña la «copia del mundo» (número del canal de Comercio).
- **Copia 154 (5.4.40): sale de la 151, sin `/gu recuento`.** Todo lo de medir pasa a un addon aparte, **Guild Union Measure** (`addons\GuildUnionMeasure`, solo para gente de confianza), que escucha los mismos eventos del juego y apunta en su propio archivo. Lo único que se añade aquí es la puerta: `_G.GuildUnionInternal = HU` (`Core.lua`). Measure la usa para leer la sala (`HU:LaneState`) y para apuntar lo que decide `HU.LogChat` con cada línea (pintada, repetida, descartada). Las copias 152 y 153 (recuento dentro del addon) quedan sin publicar.
- **Copia 155 (5.4.40): la pestaña «Guild Union» de Whisper Messenger solo cuenta como pendiente lo que me nombra.** `OnEntry` (`WMPanel.lua`) sumaba a `unread` cada línea de otra hermandad con el panel cerrado, y Whisper Messenger enseñaba «900 mensajes pendientes». Ahora solo suma si `HU:MentionsMe` (con `@Nombre Apellido` o `@everyone`, de cualquier hermandad y no mía). El resto se ve al abrir la pestaña. Solo ventana: sin banco.
- **Copia 156 (5.4.40): clic derecho en las filas de la pestaña de Whisper Messenger, como el suyo.** Jorge, con captura del menú de Whisper Messenger: «añade un botón derecho mute como aquí, mismas opciones». Su API de pestañas no deja tocar su lista, así que el menú va en nuestras filas («Todas las hermandades» y cada hermandad), con sus textos y su orden: *Marcar los últimos mensajes como no leídos* (las líneas de esa fila desde la última mía; apagado si no hay), *Exportar conversación* (ventana de copiar con las últimas 500), *Silenciar / Quitar silencio* (no suben pendientes ni con mención; «todas» silencia todo), *Anclar arriba / Desanclar* (ancladas arriba en el orden en que se anclaron), *Eliminar* (la fila se esconde hasta que llega algo suyo; la última no se puede). Los pendientes van ahora por fila (`unreadBy`) y la pestaña suma todos; al ver una fila se dan por leídas las suyas. Marcas como las suyas: campana tachada (`muted.png`), chincheta (`pinned.png`) y número. Se guarda por personaje en `db.wmRows`. Solo ventana: sin banco.
- **Copia 157 (5.4.40): el clic derecho de las filas de Whisper Messenger no se abre con la interfaz de mando.** `MenuUtil.CreateContextMenu` desde un addon contamina el foco del mando de Blizzard (ForeverPlusPlus; ChillZone apaga lo suyo con mando). Se mira con `C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad` y, si es así, se avisa en el chat en vez de abrir el menú. Solo ventana: sin banco.
- **Copia 158 (5.4.41): ninguna función de canal con el chat bloqueado.** God Platinum (16/11, 5.4.40, al entrar en un campo de batalla) vio la ventana del juego «GuildUnion … desactivar o ignorar», sin poder pulsar nada. En Forever (como en Midnight 12.0.5) las funciones de canales están prohibidas mientras dura el bloqueo del chat, y la 5.4.40 llamaba a varias sin mirarlo: leer la lista del canal (`SetSelectedDisplayChannel` en `HU:ChannelRoster`, que se dispara al llegar respaldo de alguien sin reconocer, y la 5.4.40 manda respaldo siempre), ocultar el canal de la ventana (`HU:HideChannel` al cambiar de número), salir de canales (`HU:ApplyChannels`), contraseña, echar, vetar y moderadores, y `ListChannelByName` en `/gu todo`. Ahora todas pasan por `HU:ChannelApiBlocked()` (= `IsChatLockedDown()` o dentro de una partida JcJ); ocultar el canal y aplicar canales se aplazan y el ciclo de 10 s los hace al salir. Entrar al canal ya lo miraba (`CanJoinNow`, copia 73). Incluye la 157 (menú de Whisper Messenger apagado con mando).
- **Copia 159 (5.4.41): también silenciar en el canal.** El banco nuevo con campo de batalla (`--campo-batalla`, ADMIN 16/11) encontró en la 5.4.40 9 llamadas prohibidas con el chat bloqueado (`SetSelectedDisplayChannel` ×8, `ChannelMute` ×1) y en la 158 todavía 1 (`ChannelMute`, de `ChannelMuteCall` en `Social.lua`, cuando al enlace le llega un silencio). Ahora también pasa por `HU:ChannelApiBlocked()`.
- **Copia 160 (5.4.41): las líneas de mi hermandad las pinta el addon, sin meterse en la función de escribir del juego.** Desde la copia 94, `ChatPaint.lua` sustituía el `AddMessage` de cada ventana para adornar `/g` y `/o`. Eso manchaba todas las líneas: tras cualquier bloqueo del chat (campo de batalla, jefe, o la prueba con `addonChatRestrictionsForced`), cada línea daba «attempted to iterate a table that cannot be accessed while tainted (GuildUnion)» hasta el `/reload` (Jorge, 16/11, 202 errores). Ahora es un filtro (`ChatFrameUtil.AddMessageEventFilter`) que solo contesta verdadero o falso: el juego lo llama con `securecallfunction`, aislado. Si hay que adornar, oculta la línea y el addon la escribe en esa ventana con `FormatLineParts` (punto o etiqueta, gris si no tiene el addon, icono de rango, color de clase, menciones, emoticonos, hora si la tiene puesta). Con datos secretos, chat bloqueado, Prat, Chattynator o `ownPaint` apagado, la pinta el juego tal cual. Si falla al pintarla, no se oculta. Se pierde «Denunciar» en esas líneas. `FormatLineParts` acepta `has` (si el autor tiene el addon).
- **Copia 162 (17/11): canal fantasma, chat perdido durante un jefe y `/gu ids` sin repetidos.** Sale de la 161. Medido con Guild Union Measure (5 archivos, 16-17/11).
  - **Canal fantasma (`Channel.lua`).** Tras entrar al mundo, un `/reload` o entrar en una mazmorra, a veces el juego del jugador tiene el canal de la comunidad en su número (`GetChannelName` da id) pero el servidor no le manda nada: llega el aviso `NOT_ALLOWED_IN_CHANNEL` y el canal no sale en la lista de canales del servidor (`GetChannelDisplayInfo`). `EnsureJoined` lo daba por bueno y no volvía a entrar; se curaba solo en 2-30 min, o nunca (Ariatt, Aeslith: toda la sesión). Mientras dura, el chat solo llega por el respaldo y se pierde lo que va solo por el canal. Ahora `HU:CheckGhostChannels` (en el ciclo de 10 s) mira cada canal nuestro: si tiene número y no sale en esa lista en 3 comprobaciones seguidas, `HU:RejoinChannel` sale (`LeaveChannelByName`) y a los 2 s vuelve a entrar con la contraseña. Como mucho uno por minuto; tras 5 seguidos sin arreglarlo, avisa una vez en el chat. Con un grupo plegado en la ventana de canales la lista no enseña sus canales: entonces no se sabe y no se hace nada. El aviso `NOT_ALLOWED_IN_CHANNEL` solo se apunta (`c.notAllowed`, `/gu debug`): también llega con el canal bien, justo después de reentrar. `/gu ids` enseña «en la lista de canales: SÍ / NO (canal fantasma)» y las reentradas.
  - **Chat perdido durante un jefe (`Combat.lua`, `Social.lua`).** Con el chat bloqueado (`C_ChatInfo.InChatMessagingLockdown`) el texto del canal llega secreto y no se puede leer ni pintar. Al salir de un campo de batalla ya se pedía a la hermandad lo escrito (`AskMissedChat`, `HQ`/`HL`); fuera de JcJ (jefes de mazmorra y banda) no. Ahora un reloj de 2 s (`CheckChatLock`) apunta cuándo empieza el bloqueo y, al acabar, pide lo de ese rato (repite una vez a los 150 s si nadie contesta). Lo que llega se escribe en el chat aunque `loginHistory` esté apagado, durante 60 s (`HU.showLateUntil`), con la cabecera «Mientras el chat estaba bloqueado (n)», y sin las líneas de mi hermandad (esas las pintó el juego en `/g`).
  - **`/gu ids` (`Report.lua`).** Los nombres de la respuesta del servidor se cuentan sin repetidos: la respuesta tardía a una pregunta anterior se sumaba («nombra a 320 personas» con 160 dentro).
- **Copia 163 (17/11): en banda, tope de líneas en el chat tras un jefe.** Sale de la 162. Jorge: campo de batalla solo en el panel (como ya era); mazmorra en el chat; banda «habrá que pensar» → tope. `CheckChatLock` (`Combat.lua`) pone `HU.showLateLeft = 10` si el bloqueo acabó dentro de una banda; `HU:ShowLate` escribe en el chat solo las últimas que quepan (lo que queda se descuenta entre tandas de la misma petición) y una línea «(+N más en el panel de …)»; si no cabe ninguna, solo ese aviso en la ventana principal. En el panel va todo siempre. Solo cambia lo que se escribe en el chat: sin banco, lo prueba Jorge.
- **Copia 164 = 5.4.42 (17/11):** la 163 con el número 5.4.42 para subir a CurseForge. Trae la 161 (Prat con color de clase), la 162 (canal fantasma, chat tras un jefe, `/gu ids` sin repetidos) y la 163 (tope en banda).
- **Copia 165 (17/11): sin el tirón de cada 15 minutos.** Sale de la 164 (sigue con el número 5.4.42). Medido con Guild Union Measure: el contador de fotogramas de más de 50 ms de GuildUnion subía cada 15 min exactos (El Maracas, con muchos addons, picos de 128-167 ms; Janeth 53-75 ms). Era `MemGuard.lua`: `UpdateAddOnMemoryUsage` recorre todos los addons del jugador y el juego se lo apunta al que lo llama. Ahora `Check` mide como mucho cada 15 min y solo cuando no se nota: en `PLAYER_ENTERING_WORLD` (pantalla de carga: entrar, `/reload`, mazmorra, campo de batalla) o con el jugador ausente (`UnitIsAFK`, mirado cada minuto); si en 2 h no ha habido ninguna de las dos, una vez fuera de combate. El resto de `MemTrim` no cambia. El minuto de Janeth al 10,8 % (17/11 03:29, tras un combate en mazmorra) no fue un tirón: es el reparto de lo aplazado en combate (`Drain`, 0,8 ms por fotograma), que va por diseño.
- **Copia 166 (17/11): la misma línea ya no sale dos veces si lleva un enlace de misión.** Sale de la 165. Captura de Jorge: una línea de Balas Caoticas (WLP) con tres enlaces salió dos veces seguidas en [Guild], una con los enlaces en verde y otra en rojo. El color de un enlace de misión no viaja igual por el canal que por el respaldo, y `Duplicate` comparaba el texto exacto: dos «textos» distintos, dos líneas pintadas. Medido antes con Measure: misma línea, mismo largo, huella distinta según el camino. Ahora `LineKey` (`Channel.lua`) quita los códigos de color (`|cXXXXXXXX`, `|r`) para la clave de `Duplicate`, `CarriedByOther` y la marca de pintada. Lo que se pinta no cambia.
- **Copia 167 (17/11): caída del servidor de chat del juego.** Sale de la 166. Jorge (captura): «You have been disconnected from the Chat Server…» y luego «reconnected» dos veces; lo escribe el juego desde `CHAT_SERVER_DISCONNECTED` / `CHAT_SERVER_RECONNECTED` (`ChatFrameOverrides.lua`), no GuildUnion. Al volver, los canales propios pueden quedar como canal fantasma. Ahora `Channel.lua` apunta las dos horas (`HU.chatServerDownT`, `HU.chatServerUpT`) y al volver comprueba los canales a los 5, 15 y 30 s; durante el minuto siguiente basta con 2 comprobaciones seguidas sin el canal en la lista (en vez de 3) para salir y volver a entrar. `/gu ids` dice hace cuánto se cayó y volvió. En los 5 archivos de Measure del 16-17/11 no hubo ninguna caída (Measure ya lo apunta desde antes como «servidor de chat DESCONECTADO / reconectado»): los canales fantasma de esos días no vinieron de aquí.
- **Copia 168 (17/11): la reentrada del canal fantasma entra de verdad.** Sale de la 167. Jorge (5.4.42 de la copia 166, captura de `/gu ids`): «canal de la comunidad: /6», ningún /6 en la lista de números, «en la lista de canales: NO (canal fantasma) · reentradas: 5», el servidor sin contestar y el aviso de rendirse. En el canal fantasma `GetChannelName(nombre)` sigue dando el número aunque `GetChannelName(6)` no dé nada; `RejoinChannel` salía y a los 2 s llamaba a `EnsureJoined`, que veía `ChannelId` y se creía dentro: nunca volvía a entrar. Ahora a los 2 s llama a `JoinTemporaryChannel` directamente (con la misma guarda de bloqueo que `EnsureJoined`). Sin banco: el banco no tiene canal fantasma.

- **Copia 174 = 5.4.43 (19/11): solo quita los avisos que asustan.** Sale de la **168** (la 5.4.42 que tiene la gente), no de la 173: lleva solo el cambio de avisos de la 172/173 y deja fuera lo de las copias 169-171 (aviso de comunidad, reentrar si tu línea no vuelve, ajustes de reentradas), que nadie ha probado en el juego. Decisión de Jorge.
  - **`RejoinChannel`**: al agotar las reentradas ya no imprime «El servidor no te deja estar en el canal…» (solo `Debug`).
  - **Aviso de fuera del canal** (ticker de 60 s, `Channel.lua`): solo tres casos exactos que puede arreglar un oficial: sin configuración (faltan las GU:g), sin `myTag` (la hermandad no sale en las GU:g), o sin nombre de canal (falta la GU:c o no hay compañero que la tenga). Con el canal conocido y fuera (otro reino interno, canal fantasma, canal lleno) solo `Debug`. Ya no mira `cfg.missingChannel`, que se queda puesto aunque el canal llegue por la nota de oficial y hacía decir «nadie te ha pasado el canal» a quien sí lo tenía. Como mucho cada 30 min (antes 10).
  - `LocaleEN.lua`: los tres textos nuevos. `GuildUnion.toc`: 5.4.43.
- **Copia 175 = 5.4.43 definitiva (19/11): sin avisos de fallos en el chat.** Sale de la 174 (sigue con el número 5.4.43; la 174 no se llegó a subir). Jorge: «quítalos todos, que se tengan que preguntar cuando a alguien le falle». Elegido: los de fallos; se quedan los de moderación (te han silenciado o vetado, estás silenciado), versiones, lista negra y los de oficiales.
  - **`HU:Notice(texto)`** (`Core.lua`): guarda los 30 últimos avisos de la sesión con su hora y los escribe en la depuración. **`/gu informe`** tiene una sección nueva, «AVISOS DE ESTA SESIÓN (no se enseñan en el chat)» (`Report.lua`, `NoticeLines`).
  - Pasan de `Print` a `Notice`: los tres de configuración del aviso de fuera del canal (`Channel.lua`), contraseña incorrecta y vetado del canal (`CHAT_MSG_CHANNEL_NOTICE`; ya sin el nombre del canal, que salía en capturas, y con «GU:c» en vez del viejo «HU:»), «tu mensaje puede no haber llegado a <X>» (`SendCW`), «tu mensaje no ha llegado» (`OnChatLost`) y el del campo de batalla (`Combat.lua`).

## Trade.lua

La sección Comercio de la lista de miembros (UnionRoster.lua crea `cover.trade` y llama a `HU:BuildTrade(host)`):
pedir objetos fabricados a la unión, en un tablón (Público) o a alguien concreto (Privado), y hablar con cada persona.
**Fase 1: solo la ventana, sin red.** Nada viaja: las solicitudes (`reqs`) y los chats (`chats`) son tablas del
archivo, solo de esta sesión (se pierden con /reload), y nadie más las ve; el «Modo prueba» la llena de datos. La red
está prevista con los paquetes con huella: el conjunto `TR` (`Net/Packs.lua`, aún sin escribir).
Arriba, el buscador (150 de ancho: más ancho chocaba con «Público»), Público · Privado (cambiar borra búsqueda,
elegida y marcadas) y «Modo prueba»; debajo, «+ Nueva solicitud» (`ui.new`), teñido de verde como «+ Nuevo evento»,
que no sale mientras se busca. El «Buscar personaje» de la ventana lo esconde `ShowTab` (UnionRoster.lua,
`HU.charSearchOff`) y no Trade.lua, porque el `Sync` de BlizzTab.lua lo volvería a sacar.

### Una solicitud

`{ id, who, item, qty, mats, tip, pub, to, state, taker, takenAt, t, closed, test }`
- `id` (`NewId`), 16 cifras: huella del nombre de quien la pide (`HU.Hash`, 4), la hora (6), un contador de la sesión
  (2) y azar (4); con la red, distinto en toda la unión aunque dos pidan en el mismo segundo.
- `item`, el enlace (o lo escrito); `qty`, 1 o más; `tip`, la propina en cobre (nil: «A negociar»); `mats`, true si
  los materiales los pone quien pide («Yo», de entrada), false si quien la hace («Vendedor»).
- `pub`: pública, o privada para `to`. `state`: `open` (Abierta), `taken` (Aceptada por `taker` a la hora `takenAt`),
  `done` (Hecha) o `gone` (cancelada o rechazada: ya no sale). `closed`: quitada de mi Privado (solo de mi lista).
- `test`: del modo prueba. Tope: 5 sin terminar por persona (`MAX_OPEN`, `OpenCount`: abiertas y aceptadas; las
  quitadas de mi lista no cuentan), pensado para la red.
- Lo mío va en azul (`MINE`; en Público, «Yo») y lo de otros en amarillo (`OTHERS`).

### Público y Privado (`Visible`, `Layout`)

- **Público**, a todo lo ancho: las públicas abiertas y, 10 min más (`PUB_KEEP`), las aceptadas con quien la aceptó,
  para que se vea que ya está cogida; luego solo en Privado. Quién · Receta / objeto · Cant. · Mats (Sí / No) ·
  Propina · Estado · Acción: «Aceptar» (de otro y abierta), «Cancelar» (mía sin aceptar) o quién la aceptó. `Accept`
  la pasa a `taken` conmigo como `taker` y deja puesto el chat con quien la pidió.
- **Privado**: las que me tocan (`Involved`: mías, las que me piden y las que hago yo), menos las quitadas y las
  públicas sin aceptar, que no tienen a nadie al otro lado. Comparte el ancho con el chat y va sin Mats para que quepa:
  Con quién (`Other`) · Receta / objeto · Cant. · Propina · Estado; en las abiertas, un tic (aceptar la que me piden)
  y una X (`Cancel`: cancelar la mía o rechazar la que me piden).
- Con `tipsOff`, ninguna de las dos lleva Propina (`ReqCols`).
- Sin filtros: clic en un título ordena (otro, al revés; el tercero, lo más nuevo arriba). El orden se quita solo si la
  vista nueva no tiene esa columna (Mats y Acción solo están en Público; sin propinas, no hay Propina).
  Sobre el objeto, un botón (`itemBtn`) del ancho del enlace: clic, su ficha (`SetItemRef`, como en el chat); ratón
  encima, la flotante (en Privado no). El resto de la casilla elige la fila.

### Nueva solicitud (`BuildNewDialog`, `ui.OpenNew`)

Objeto (autorrelleno o Mayús+clic: enganche a `ChatFrameUtil.InsertLink` mientras la caja tiene el foco), Cantidad
(1 de entrada, hasta 3 cifras), Materiales Yo · Vendedor (se excluyen), Propina en oro · plata · cobre (vacías: a
negociar) y Pública Sí · No (de entrada, según la pestaña; con No, «Personaje»). «Pedir» exige el objeto, que no pase
del tope y que una privada tenga a quién, y salta a Público o Privado. `ui.OpenNew(nombre)` la abre privada para esa
persona («Pedir una receta a …»). Con el comercio apagado (`tradeOff`) no se pide: `ui.OpenNew` no la abre y «Pedir»
la cierra y lo dice. Autorrelleno (`Suggest`): desde 2 letras, todo lo que encaja de mejor a peor (`Rank`, `Better`:
el nombre exacto, los que empiezan por lo escrito y los que lo llevan dentro; en cada grupo, por nombre), y se ven los
6 primeros (`SUGGEST_N`); clic o Intro (la primera) elige. Objetos (`ItemMatches`): el de ese nombre exacto si el
juego lo conoce, los de mis bolsas, los de las solicitudes y los fabricables (CraftItems.lua). Nombres
(`NameMatches`): mi hermandad, las listas de las otras y los que tienen GuildUnion, con su etiqueta y sin mí.

### Buscar

Sugiere objetos como al pedir; compara en texto llano (`Query`: de un enlace, su nombre). Mientras se busca no hay
pestaña elegida, ni chat, ni «+ Nueva solicitud», y la vista se parte en dos de 4 filas:
- **Publicadas**: las del tablón que encajan por quién la pide, el objeto o quién la aceptó (`Matches`); si no hay
  ninguna, se esconde y «Quién lo hace» ocupa todo (10 filas).
- **Quién lo hace** (`SearchMembers`): los de mi hermandad con una profesión cuyo nombre encaja, o con la profesión y
  el nivel de un fabricable que encaja (`CraftNeeds`), de más nivel a menos. Es aproximado: el juego da sus dos
  profesiones y su nivel (`C_Club.GetMemberInfo`), no sus recetas. Las otras hermandades, con la red.

### Chat con cada persona y circulitos

Solo en Privado, a la derecha (`ui.chat`), y solo aquí: no sale en el chat normal. Uno por persona (`chats[nombre]`,
hasta 200 líneas); elegir una solicitud lo cambia al de la otra persona (`OpenChat(Other(r))`); sin nadie, la caja
está apagada. A un desconectado se le escribe igual (con la red, lo leería al entrar); hoy solo se añade aquí.
Detrás de cada nombre, un circulito verde o gris (desconectado o no se sabe): `BuildOnline` rehace `onlineMap` en cada
repintado con mi hermandad (`HU.rosterList`), las listas de las otras (`HU.remoteRoster`), los que tienen GuildUnion
vistos hace menos de 5 min (`HU.remote`) y los de prueba. Yo, siempre verde; en «Quién lo hace», la presencia del club.

### Clic derecho, varias a la vez y «Hecha»

- `RowMenu`: la otra persona, con Susurrar e Invitar al grupo; en «Quién lo hace», «Pedir una receta»; en Privado,
  «Marcar como hecha» (si se puede: ver abajo) y «Eliminar» («Eliminar (N)» con varias marcadas); y «Cancelar», que
  cierra el menú.
- En Privado, Ctrl+clic suma o quita una fila (la elegida con un clic solo entra también) y Mayús+clic, el tramo desde
  la última (`picks`); con algo marcado sale «Eliminar (N)» junto a «+ Nueva solicitud». `RemoveReq`: la mía sin
  aceptar se cancela; las demás salen de mi lista.
- «Hecha» (arriba a la derecha del chat, para la elegida, si la hago yo) y «Marcar como hecha» la pasan a `done`
  (`MarkDone`): solo quien la hace y mientras está aceptada (`CanMarkDone`); ya hecha, «Hecha» queda apagado.

### Modo prueba y configuración

«Modo prueba» se enciende y se apaga (encendido, oscuro; `ui.testOn`). `AddTest` quita lo de prueba que hubiera y pone
8 solicitudes (4 públicas, 4 privadas: me piden, pido, aceptadas) y tres líneas de chat, con personas «-Prueba» (Pepe
y Bea conectados, Lyra y Jandra no) y el enlace de verdad si el juego conoce el objeto; `ClearTest` lo quita todo.
`tradeOff` y `tipsOff`, en la configuración de la hermandad (`HU:UnionCfg()`, Configuración → Comercio,
UnionConfig.lua), los cambia el maestro y de momento solo valen en su personaje; sin poner, todo activo. `tradeOff`
deja solo el panel con el aviso (`ui.offMsg`): esconde lo demás (`ui.onlyOn`: cuerpo, buscador, Público · Privado,
«Modo prueba» y «+ Nueva solicitud»), cierra la ventana de pedir y no deja pedir. `tipsOff` quita la columna Propina
y la propina al pedir, y no la guarda. Con `HU:Changed("unionCfg")` se repinta.

## CraftItems.lua

`HU.CRAFT_ITEMS[profesión] = { objeto, nivel, objeto, nivel, ... }`: lo que se fabrica en Forever y el nivel para
aprender la receta. La clave es el número de profesión del juego, el de `C_Club.GetMemberInfo` (`profession1ID`,
`profession2ID`): 129 Primeros auxilios, 164 Herrería, 165 Peletería, 171 Alquimia, 185 Cocina, 186 Minería (fundir),
197 Sastrería, 202 Ingeniería y 333 Encantamiento. Solo números: el nombre y el enlace los da el juego, en el idioma de
cada uno.

`HU.CRAFT_SPELLS[333]`: los **encantamientos**, hechizos que se lanzan sobre el objeto de otro y no crean objeto (los
que sí, como varas, varitas y aceites, están en `CRAFT_ITEMS`).

**De dónde salen (24/11):** de wow.gg (`/professions/forever/<profesión>`), que publica las recetas de Forever sacadas
de los datos del juego: 2.004 objetos (892 nuevos de Forever, como el «Arcane Salvager» o las pociones de curación,
que en Forever son de Primeros auxilios) y 165 encantamientos (33 nuevos). wow.gg da los encantamientos sin su número
de hechizo: se cruzaron por nombre con los de vanilla de Wowhead Classic (119) y el resto se buscó en Wowhead
(`/forever/search/suggestions-template`, hechizo con el nombre exacto: los 46 salieron sin dudas). Antes la lista era
de Wowhead Classic y traía objetos de Season of Discovery que Forever no tiene: ya no.

### Los nombres: `LoadCraftNames` (en Trade.lua)

- Pide cada objeto al juego (`C_Item.GetItemInfo`) y guarda lo que llega en `craft[id] = { key, link, skill, lv }`
  (`key`, el nombre en minúsculas), solo para la sesión. Lo usan `ItemMatches` y `CraftNeeds(q)`: por profesión, el
  nivel más bajo entre los fabricables cuyo nombre contiene lo buscado.
- Poco a poco, para no pedir 1.373 de golpe: 30 cada medio segundo con `HU:Every` («Comercio: nombres», en
  `/gu perf`), en pausa durante el modo combate (`pauseInCombat`).
- Si el juego no tiene el objeto a mano, devuelve nil y lo pide al servidor; sin esperar su aviso, los que faltan se
  vuelven a pedir en dos vueltas más. Luego el temporizador se para y no se repite en la sesión.
- Se llama al final de `HU:BuildTrade` (al cargar la ventana de hermandad del juego) y en cada `OnShow` de Comercio;
  `craftLoader` impide que arranque dos veces.
- Los encantamientos (`LoadCraftSpells`), de una vez y antes que los objetos: `C_Spell.GetSpellName` y
  `C_Spell.GetSpellLink` los dan al momento. Van en `craft["s" .. hechizo]` con su profesión y nivel, así que salen
  en las sugerencias, en «Quién lo hace» (`CraftNeeds`) y en las solicitudes como un enlace más (su ficha al pasar
  el ratón y al pinchar, como la de un objeto).

## DJStyle.lua

`HU.DJ`, el estilo compartido de Comercio, Calendario y Configuración. Sale del addon Dungeon Journal de
Forever, con los fondos de WhisperMessenger; de los dos se estudió el código, sin copiar su arte. Va en el .toc antes
de Trade, UnionCalendar y UnionConfig, que leen `HU.DJ` al cargarse. Colores (`DJ.T`): fondos lisos casi
negros y grises muy oscuros (`frame`, `content`, `panel`, `header`, `row`), borde gris piedra (`border`), lo elegido
en azul pizarra (`rowSel`), la letra (`text`) y la apagada (`muted`), y el dorado del juego para títulos, rayas y lo
que se señala (`title`, `line`, `hover`). Además, las texturas `DJ.WHITE`, `DJ.TIP_BORDER` y `DJ.ROW_HL`.

### Ayudantes

- `DJ.Panel(f, bg, border, edge, inset)`: fondo liso (`WHITE8X8`) y borde de tooltip con colores de `T`; `f` ha de ser
  `BackdropTemplate`. `DJ.Line(f, alpha)`: raya dorada de 1 px (alfa 0,55 si no se dice) que coloca quien la pide.
- `DJ.Parchment(f, alpha)`: la textura de pergamino (`QuestBG`) detrás, hoy a alfa 0 porque los fondos son lisos; se
  queda para no tocar a quien la llama. `DJ.Big(fs, size)`: tamaño de letra. `DJ.C(fs, c)`: color de `T` (da `fs`).
- `DJ.RoundIcon(parent, size)`: icono redondo (máscara de retrato) con el aro del minimapa; devuelve solo el icono.
- `DJ.Window(name, parent, w, h, onClose)`: ventana DIALOG que nace escondida y se arrastra: fondo liso casi negro
  (`T.frame`) con marco de diálogo, franja de título con rayas doradas (`d.titleText`), X (`onClose` o esconderla) y
  `d.content` (panel `content`), con 44 px libres abajo para botones.

### Botones: `DJ.Button` y `DJ.PickRed`

- `DJ.Button(parent, text, w, h)`: el botón rojo del juego (`UIPanelButtonTemplate`, 22 de alto si no se dice);
  `:Pick(on)` lo deja elegido (`b.picked` lo dice) y `:Label(t)` es `SetText`.
- `DJ.PickRed(b, on)` vale para cualquier botón rojo: también los de arriba de la lista de miembros (`ShowTab`,
  UnionRoster.lua), las pestañas de las ventanas «Registro» (Invitaciones · Salidas) y «Peticiones de oficiales»
  (Todas · Echar · Rango) de InviteLog.lua y Miembros · Oficiales (BlizzTab.lua). Elegido, sus tres piezas (`Left`,
  `Middle`, `Right`) se desaturan y oscurecen hasta el negro y la letra pasa a blanca; sin elegir, rojo con letra
  dorada. Si ya está así no hace nada (`djPicked`): se llama en cada repintado.
- Por qué el elegido mantiene la forma: no se esconde ni se añade nada, solo se tiñen las piezas que ya tiene. Sigue
  siendo el mismo botón que sus vecinos (contorno y tamaño), solo que oscuro, y vale para botones de otros archivos.

## UnionCalendar.lua

### Qué hay en el archivo

La sección Calendario de la lista de miembros (UnionRoster.lua la monta en `cover.calendar` con `HU:BuildCalendar`).
Arriba, Eventos · Calendario en el centro, «+ Nuevo evento» debajo (verde y centrado: abajo pisaba las tarjetas) y
«Modo prueba» a la derecha. Piezas de DJStyle.lua (`HU.DJ`). Solo eventos de la unión: el calendario del juego no se toca.
- **Eventos** (`PaintCards`): los próximos (desde hace 3 h, `Upcoming`), por fecha, en tarjetas de 2 en 2 (dos filas a
  la vista): tinte del tipo, imagen, título, tipo · hora · «Nv. N+», día grande con día de la semana y mes, «por» quién
  (yo en azul, los demás en amarillo, con su hermandad a color), «N van» (tic si voy), roles, y «Apuntarme» / «Más
  información» (o clic en la tarjeta). Van en un panel centrado (`ui.list`) cuya zona de tarjetas (`ui.cardArea`) solo
  deja el hueco de la barra con más de dos filas, para no descentrarse; la rueda baja de fila en fila.
- **Calendario** (`PaintMonth`): el mes en casillas, lunes primero, flechas del libro de hechizos; solo las semanas que
  tiene (casillas más altas). Cada día: número, «+N evento(s)» y un cuadradito del color del primero; hoy con borde
  dorado, el elegido en azul. Clic en un día: el panel de la derecha (`PaintDay`) enseña sus eventos (clic: la ficha;
  se ven 5, `DAY_N`, y con más sale la barra y las filas se estrechan; al cambiar de día vuelve arriba) y «+ Nuevo
  evento» para ese día (el de arriba también lo usa).

### Fase 1: solo la ventana, sin red

Los eventos viven en una tabla local de la sesión (`events`): no salen de este PC y se pierden con /reload. La red irá
con los paquetes con huella (Net/Packs.lua, aún sin escribir; diseño en Obsidian, «GuildUnion - specs paquetes con
huella»), conjunto `EV`. Evento: `{ id, title, kind, t, who, tag, desc, minLevel, icon, signups = { [nombre] = "yes" },
roles = { [nombre] = rol }, raids, test }`. Tipos (`KINDS`, con color e icono): Banda, Mazmorra, JcJ, Social y Otro; al
crear se ofrecen Banda, JcJ y Social (Mazmorra solo sale en el modo prueba; Otro es el de reserva).

### Nuevo evento (`BuildNewDialog`)

Ventana movible: título (40 letras), tipo, imagen, día, hora, nivel mínimo y descripción (varias líneas, 240 → `desc`).
- Imagen: vista previa + «Elegir imagen», que abre una rejilla de 64 iconos de vanilla (`EVENT_ICONS`, 8 x 4 y barra).
  Siempre hay una: la del tipo, que sigue al tipo hasta que se elige otra (`iconCustom`).
- Día y hora se eligen, no se escriben (sin errores de formato): «Día», un calendario pequeño (hoy en dorado, el
  elegido oscuro); «Hora» (20:00 al abrir), una lista de 00:00 a 23:45 de 15 en 15, con barra, abierta por la elegida.
- Las tres ventanitas se excluyen (`d.ClosePopups(keep)`) y pinchar fuera las cierra: una capa invisible de toda la
  pantalla, por debajo de ellas, que se enseña mientras alguna está abierta (`d.WatchPopup`).
- Nivel mínimo (2 cifras; vacío o 1, ninguno) → `minLevel`: «Nv. N+» en tarjeta y ficha; no deja apuntarse con menos.
- «Crear» pide título y un día y una hora que no hayan pasado; el evento lleva la hermandad de quien lo crea (`tag`)
  y este queda apuntado con su rol (`MyRole`: el último con el que se apuntó o, si no, el primero que hace su clase).

### La ficha del evento (`BuildDetail`, `PaintDetail`)

Ventana movible (740 x 480, `DETAIL_H`) que es solo las raids: arriba icono, título, tipo · día y hora · por · cuántos
van · nivel y los roles; debajo, la descripción (hasta 4 líneas, `DESC_LINES`), que baja la raya y todo lo demás y hace
crecer la ventana lo que ocupa (`descH`); abajo a la derecha, «Apuntarme» / «Apuntado» (verde, con tic).
- Apuntarse (`SignUp`): mira el nivel y pide el rol con un menú que solo trae los de la clase (`CAN_ROLE`, vanilla:
  tanque guerrero, druida o paladín; sanador sacerdote, druida, paladín o chamán; daño, todas). Ya apuntado, pregunta
  «¿Seguro que quieres salir del evento?» (`ui.confirm`); salir te quita también de la raid.
- Raids: `{ name, leader, groups = { {nombres} x 8 } }`, 8 grupos de 5, hasta 20 (`MAX_RAIDS`). Pestañas «Raid N
  (cuántos)» en filas de 10 (65 de ancho, letra pequeña en todos sus estados: no cambia de tamaño al pasar el ratón) y,
  para quien organiza, «+ Añadir» en el hueco siguiente; con segunda fila, la ventana crece 26 más (sumados a los de la
  descripción) y lo de debajo baja otro tanto, para que nada se salga ni se monte. «+ Añadir» pregunta quién la lleva
  en una ventanita con buscador y barra (`d.picker`; un menú no cabía con mucha gente), primero los apuntados sin raid.
  La nueva se llama «Raid N» con el número siguiente al más alto (`NewRaid`: al quitar una del medio no se repite).
- Barra «Líder de la raid» (corona, roles de la raid) sobre los grupos. `SetLeader`: el líder va el primero del grupo
  1 (si está lleno, el último baja a otro grupo) y nadie más puede ocupar ese hueco. El líder no se mueve
  (`LeadsAny`): no se arrastra (lo avisa) y su menú no trae «Mover a» ni «Sacar de la raid»; solo cambia con «Hacer
  líder de la raid» o soltando a otro en la barra del líder, y el anterior pasa al hueco 2 (si sale del evento, la
  raid se queda sin líder).
- Banquillo «Sin raid (N)» a la izquierda (`Unassigned`), con nivel (`LevelMap`) y color de clase (`ClassMap`: mi
  hermandad, las listas de las otras y el modo prueba); se ven 12 (`BENCH_N`) y, con más, la barra (las filas pasan de
  142 a 122 de ancho); al abrir otro evento vuelve arriba. Cada persona, en una sola raid del evento.
  Al apuntarse se entra solo en una raid con sitio (`AutoPlace` → `BestRaid`: la que menos tiene de su rol y luego la
  más vacía) o al banquillo; «Colocar en raids (N)» (`PlaceBench`) lo reparte igual: tanques, sanadores, daño.
- Arrastrar (botón izquierdo, quien organiza; al líder, no): el nombre se va de su hueco y un rótulo sigue al ratón.
  Se suelta en un hueco (si hay otro, se cambian; si viene del banquillo, solo ese otro sale al banquillo; en el del
  líder, va a su lado, al hueco 2), un grupo (si cabe), la pestaña de otra raid, la barra del líder (lo hace líder) o
  el banquillo (sale de la raid); fuera de todo, vuelve.
- Clic derecho (`NameMenu`): quien organiza, «Hacer líder de la raid», «Mover a >» y «Sacar de la raid» (al líder,
  ninguno); todos, «Susurrar» e «Invitar al grupo» (uno a uno, desde el clic del menú, que el juego lo deja).
- Bajo los grupos: «Invitar a todos (N)», «Quitar raid» (sin preguntar; su gente vuelve al banquillo) y «Convertir en
  banda» (`C_PartyInfo.ConvertToRaid`; activo si estoy en grupo, no en banda, y lo llevo yo). Al líder sin banda, un
  aviso en rojo en vez de la ayuda de arrastrar. Se repinta con `GROUP_ROSTER_UPDATE`.
- `InviteRaid` invita (`C_PartyInfo.InviteUnit`) a los de la raid que no están en mi grupo (en grupo sin banda, antes
  intenta convertirlo); sin banda, como mucho 4 (un grupo es de 5), y avisa de que otro clic invita al resto. Marca
  junto al nombre (`invites`): reloj (invitado), tic (dentro) o X (rechaza, ya tiene grupo, no se le encuentra u
  ocupado, o no entra en 90 s). Los rechazos se leen de `CHAT_MSG_SYSTEM` con los textos del propio juego
  (`ERR_DECLINE_GROUP_S` y compañía, pasados a patrón con `Pattern`): sirve en cualquier idioma.

### Permisos

«+ Nuevo evento» (los dos): `HU:CanMakeEvents()` (UnionConfig.lua) o el modo prueba; se pone al día con `CHANGED`
«unionCfg». Apagado, al pasar el ratón dice quién crea eventos según `calMake` (`NoMakeTip`): «Solo el maestro crea
eventos.» o «Solo los oficiales crean eventos.». Organizar (`CanManage`: añadir raid, mover, colocar, hacer líder):
quien creó el evento o el líder de alguna de sus raids. «Invitar a todos» y «Convertir en banda»: el líder de esa
raid. «Quitar raid»: quien creó el evento o ese líder. Apuntarse, ver la ficha, susurrar e invitar al grupo: cualquiera.

### Modo prueba

Se enciende y se apaga (encendido, el botón oscuro). `AddTest` pone cinco eventos de mi hermandad y de otra
(`HU:OtherTags()`, o «OTRA»): hoy a las 21:00, una banda (nivel 55) de otra persona con 23 apuntados de mentira
(`-Prueba`, clase y nivel en `testClass` / `testLevel`) y una raid que llevo yo (así se puede organizar) con 12
colocados, el resto en el banquillo y las tres marcas de invitación; además, una mazmorra, un JcJ, un social mío y otra
banda (nivel 60). `ClearTest` quita sus eventos, marcas, clases y niveles, y cierra la ficha solo si era de un
evento de prueba.

## UnionConfig.lua

### Qué hay en el archivo

La configuración de la hermandad, en la mitad derecha de la pestaña GuildUnion (BlizzTab.lua llama a
`HU:BuildUnionConfig`; Oficiales y Miembros siguen allí, escondidos en `stash`). Título «Configuración» con «Puedes
cambiarla» o «Solo el maestro la cambia» al lado. Cuatro pestañas en dos filas (3 + 1, de 84, con la letra normal del
botón: la pequeña cambiaba de tamaño al pasar el ratón): Comercio, Lista negra, Calendario y Hermandad; se abre en
Comercio. La cambia el maestro (`HU:IsUnionGM()`: `HU:IsMaster()`, el maestro de la hermandad o quien tiene el
rango 0, o la casilla «Probar como maestro (solo en este PC)», `testGM`, para probar la ventana); los controles del
maestro (`controls`) se apagan para los demás, que la ven igual.

### Fase 1: solo en este PC

Se guarda en `HU.db.unionCfg`, de cada personaje (`HU:Saved` char: cada hermandad tiene la suya), y no viaja: lo que
cambia el maestro solo vale en su personaje (un permiso que da no le llega a nadie). Todos la leen con
`HU:UnionCfg()`, que la crea vacía si falta. Cada cambio avisa con `HU:Changed("unionCfg")` y Calendario y Comercio
se repintan. La red irá con los paquetes con huella (Net/Packs.lua, aún sin escribir), conjunto `CO`, que
solo publicará el maestro.

### Las pestañas

- **Comercio** (lo lee Trade.lua): «Comercio activo en la hermandad» (`tradeOff`; apagado, Comercio solo enseña un
  aviso y no deja pedir) y «Permitir propinas» (`tipsOff`; sin propinas, no hay columna Propina y la ventana de pedir
  esconde la propina y no la guarda).
- **Lista negra**: la de la comunidad, aquí dentro (la misma que `/gu listanegra`, Blacklist.lua). No es de fase 1: es
  `db.bans` (Social.lua), que ya viaja entre hermandades. Lista con barra (`HU:BlacklistEntries`; en rojo, los que
  están ahora en mi hermandad; al pasar el ratón, quién lo vetó y el motivo; clic: el nombre a la caja de abajo).
  Nombre + «Quitar» (`HU:Unban`), motivo + «Añadir» (`HU:SetBan`, que pide motivo) y «Comprobar ahora»
  (`HU:BlacklistCheck(true)`) solo los ven los oficiales (`HU:CanPin`), no solo el maestro; en la ventana de
  `/gu listanegra`, igual.
- **Calendario**: quién crea eventos (`calMake`: «gm», «officers» por defecto o «all») y «Permiso por un tiempo»:
  nombre (con sugerencias, `HU:NameSuggest`), horas (24 por defecto, de 1 a 999) y «Dar» → `calAllow[clave] = { name,
  untilT, by }`. Debajo, quién lo tiene y hasta cuándo, el que caduca primero arriba (lista con barra: las filas
  que quepan, hasta 5); la X para quitarlo, solo el maestro. Los caducados se borran al repintar. `HU:CanMakeEvents()`
  dice sí con «all», al maestro, a un oficial con «officers» o a quien tenga un permiso sin caducar.
- **Hermandad**: el color (muestra + «Elegir color» con el selector del juego: se ve en vivo y Cancelar lo deja como
  estaba). No va en `unionCfg`: va en `HU.db.guildColors[miEtiqueta] = { hex, by, byTag, t }`, la forma del mensaje
  `GC` (Community.lua), y avisa también con `HU:Changed("config")`.
