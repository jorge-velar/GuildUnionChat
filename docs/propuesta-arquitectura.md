# Propuesta: arquitectura para seguir añadiendo funciones

> Estado: **propuesta para discutir**. No cambia código. Basada en la versión 5.4.12 (commit c61142e).

## Resumen

El addon funciona y tiene piezas muy buenas, pero **añadir una función nueva obliga a tocar muchos
sitios que no se avisan entre sí** (Core, Comm y el módulo de la función). Proponemos unos
registros centrales (mensajes de red, comandos, datos guardados, temporizadores), partir Comm.lua y
una red de pruebas, en pasos pequeños y sin reescribir el addon de golpe.

## Lo que ya está bien (y hay que conservar)

- `HU:SafeCall`, `HU.After` y `HU.NewTicker`: un error en un evento o un temporizador no rompe el addon.
- Cola de envío con prioridades, caducidad (`QUEUE_TTL`), «gana el último» (`LATEST_WINS`) y un
  prefijo aparte para los datos grandes (`HU20B`).
- Admisión con tope por remitente (`Admit`, `PartialAdmit`) y saneado de lo que llega (`SafeText`, `SafeName`).
- Datos por personaje y por cuenta separados con una metatabla (`HU.db`).

## Diagnóstico

Cifras aproximadas, sacadas con grep sobre el código de la 5.4.12.

| # | Problema | Dónde | Por qué frena |
|---|---|---|---|
| 1 | Cada mensaje de red se define en 3 o 4 sitios | Función en cualquier archivo. Seguridad: `TAG_FIELD`, `BOOTSTRAP`, `OPEN`, `REMOTE_DATA` y `CHANNEL_OK`, en Comm.lua. Cola: `CHAT_CMDS`, `MID_CMDS`, `BULK_CMDS`… Caducidad: `QUEUE_TTL`, `NEVER_EXPIRE`, `LATEST_WINS` | Si falta una tabla no hay error: el mensaje va a la cola por defecto o se rechaza sin avisar |
| 2 | Comm.lua es demasiado grande: 3.873 líneas y 200 KB | Comm.lua | Tiene 11 bloques `do … end` solo para no pasar de 200 variables locales; dentro hay 5 o 6 módulos |
| 3 | No hay dependencias declaradas entre módulos | `HU`: unas 408 funciones públicas y 78 campos | Unas 185 líneas con `if HU.X then`, que esconden nombres mal escritos |
| 4 | El orden de carga se resuelve con parches | `HU.comm` se crea en Comm.lua, que se carga después de Channel.lua: Channel.lua registra sus funciones dentro de `OnStart` | Hay que saber en qué orden van los archivos del .toc |
| 5 | Formato de mensajes por posición y sin escapar | `HU.Split(text, "~")`. `CW` junta lo que sobra con `table.concat(f, "~", 3)` | Añadir un campo obliga a contar posiciones en todos los sitios que lo leen |
| 6 | 29 temporizadores independientes | 4 de ellos van a 1 s o menos (Channel, Comm, Echo, History). History usa `C_Timer` directamente en 4 sitios | Cada uno con su regla de combate; algunos se saltan `SafeCall` |
| 7 | Base de datos guardada sin versión | `DEFAULTS` y `PER_CHAR` en Core; la única migración es una marca suelta (`cdb.migrated`) | Cambiar la forma de un dato guardado es arriesgado |
| 8 | `/gu` es un único `if/elseif` de 230 líneas | Core.lua. Alias y ayuda (`HELP`) por separado | Es fácil que la ayuda y los comandos reales dejen de coincidir |
| 9 | Restos de las versiones Reduce y «solo chat» | `IsTest()` y `SimpleMode()` devuelven `false`, `AnnounceList()` está vacía, todo UIStubs.lua; unas 89 líneas preguntan por `CHAT_ONLY`, `IsTest`, `LaunchPhase` o `SimpleMode` | Ramas que ya no se ejecutan pero hay que leer y mantener |
| 10 | No hay pruebas | El CI solo pasa luacheck, y sus avisos no paran la integración | La lógica de seguridad y los lectores de configuración cambian sin red |
| 11 | La documentación apunta a números de línea | ARCHITECTURE.md (117 KB), con líneas de la ReduceClean-7 | Se queda desfasada con cada cambio; falta una tabla del protocolo |

## Propuestas

### A. Registro único de mensajes de red

`HU.comm` y el registro se crean en Core.lua; así se acaba el problema del orden de carga. Cada
módulo declara todo lo de su mensaje en un solo sitio:

```lua
HU:RegisterMessage("CW", {
    via      = { WHISPER = true },             -- sustituye CHANNEL_OK / OPEN / dist ~= ...
    queue    = "chat", ttl = 60,                -- sustituye CHAT_CMDS / QUEUE_TTL
    fields   = { "token", "author", "line*" },  -- "*" = el resto, con los ~ incluidos
    trust    = "community",                     -- open | community | member(tag) | forwarder
    tagField = nil,
    handler  = function(self, sender, m, dist) --[[ m.author, m.line ]] end,
})
```

- `Send` y `AllowAddonMessage` leen el registro en vez de sus tablas.
- La ayuda, `/gu diag` y la tabla del protocolo de la documentación se pueden generar a partir de él.
- **Se migra mensaje a mensaje**: las tablas actuales siguen funcionando para los que aún no estén
  registrados. Los campos por nombre se leen sobre el mismo formato con `~`, así que todo sigue
  siendo compatible con las versiones que ya tienen los jugadores.

### B. Partir Comm.lua

Por sus costuras naturales, sin cambiar cómo se comporta:

| Archivo nuevo | Contenido actual |
|---|---|
| `Net/Transport.lua` | Cola, `Send`, `Flush`, `BulkWhisper` |
| `Net/Security.lua` | `Admit`, `PartialAdmit`, `Hold`/`ReplayHeld`, `AllowAddonMessage` |
| `Net/Relay.lua` | `RelayScore`, ayudantes, saludo (`HI`/`HR`/`HY`/`RA`), ciclos |
| `Net/RosterSync.lua` | `RB`, `RC`, `RF`, `NQ`, cambios de lista, huellas |
| `Domain/Trust.lua` | Estados de lista (`b`/`m`/`p`/`c`), anclas, `Vouched`, `FullPeer`, `SenderKind` |

El objetivo es que la confianza se pregunte en un solo sitio, `Trust:Level(sender, tag)`, en vez
de las preguntas de ahora repartidas entre Comm, Lists y Guard.

### C. Módulos con dependencias y avisos internos

```lua
local M = HU:NewModule("Guard", { "Roster", "Trust" })
function M:OnInit() end    -- al cargar (ADDON_LOADED)
function M:OnLogin() end   -- al entrar al juego (PLAYER_LOGIN)
```

- El núcleo comprueba que las dependencias existen al arrancar; la mayoría de los `if HU.X then` sobran.
- Un bus interno de avisos (`HU:Fire("ROSTER_CHANGED", tag)` / `HU:Listen(...)`) sustituye las
  llamadas directas entre módulos (`Changed`, `RefreshConfig`, `RetryDeferred`…). Una función
  nueva se engancha a lo que ya existe sin tocar los otros módulos.

### D. Un único planificador

`HU:Every(15, "rosterCycle", fn, { pauseInCombat = true, budgetMs = 1 })` en lugar de los 29
temporizadores:

- una sola regla para el combate y las restricciones;
- tiempos medidos por tarea, para `/gu perf`;
- nada se salta `SafeCall`.

### E. Base de datos con versión

- `db.schema = N` y una lista ordenada de migraciones.
- Cada módulo declara sus valores por defecto y si son de la cuenta o del personaje
  (`HU:Defaults("Pinned", "char", { pinned = {} })`). Desaparece la lista global `PER_CHAR`.

### F. Registro de comandos `/gu`

`HU:RegisterSlash("guardia", { aliases = { "guard" }, officer = true, help = "...", fn = ... })`.
La ayuda sale sola y cada módulo trae sus propios comandos.

### G. Limpiar los restos de Reduce

O se borran las ramas muertas, o se dejan detrás de una tabla `HU.features` explícita si se
piensan recuperar. Lo que no conviene es tener funciones vacías que parecen funcionar.

### H. Red de seguridad

- Pruebas con `busted` y una capa mínima que imite la API de WoW, en el CI. Prioridades:
  `ParseConfigText`/`ParseChannelNote`, `SafeText`/`SafeName`, `AllowAddonMessage`, la cola de
  envío y `ApplyRosterDelta`.
- Que los avisos de luacheck paren la integración.
- Un script que extraiga todos los `L("…")` y avise de los que no tienen traducción en
  LocaleEN.lua. Hoy eso solo se ve dentro del juego, con `/gu idioma`.

### I. Documentación por conceptos

Una tabla del protocolo (generada con A), un apartado sobre el modelo de confianza y otro sobre la
elección del enlace. En el código, las referencias van por nombre de función, no por número de línea.

## Orden propuesto

El addon ya tiene jugadores, así que se va por pasos y no se reescribe de golpe:

1. **H**: pruebas y luacheck estricto. Es poco trabajo y protege todo lo que venga después.
2. **A + F + E**: los registros. Son cambios mecánicos, se migran poco a poco y son los que más
   ayudan a añadir funciones. Primera prueba: `CW`, `CG` y `CF`.
3. **B**: partir Comm.lua, apoyado en las pruebas del paso 1.
4. **C + D**: módulos, bus interno y planificador.
5. **G + I**: limpieza y documentación.

## Cómo quedaría una función nueva

Un archivo que declara sus mensajes (`RegisterMessage`), sus comandos (`RegisterSlash`), sus datos
guardados (`Defaults`) y sus temporizadores (`Every`), y escucha los avisos que necesita
(`Listen`). Sin tocar Core ni Comm.
