# Propuesta: arquitectura para seguir añadiendo funciones

> Estado: **revisada y lista para empezar el paso 1**. Escrita sobre la 5.4.12 y comprobada de nuevo
> sobre la **5.4.41** (las cifras del diagnóstico son de la 5.4.41 salvo donde se indica).
> La red de pruebas del paso 1 ya está montada (`tests/`, ver [Paso 1 en detalle](#paso-1-en-detalle)).

## Resumen

El addon funciona y tiene piezas muy buenas, pero **añadir una función nueva obliga a tocar muchos
sitios que no se avisan entre sí** (Core, Comm, Combat y el módulo de la función). Proponemos unos
registros centrales (mensajes de red, comandos, datos guardados, temporizadores), partir Comm.lua y
una red de pruebas, en pasos pequeños y sin reescribir el addon de golpe.

La primera versión de esta propuesta se ha revisado contra el código: había tablas y prefijos que
no contaba y un dato que no era exacto, y en dos sitios la solución podía provocar errores. Los
cambios están resumidos al final, en [Qué ha cambiado en la revisión](#qué-ha-cambiado-en-la-revisión).

## Lo que ya está bien (y hay que conservar)

- `HU:SafeCall`, `HU.After` y `HU.NewTicker`: un error en un evento o un temporizador no rompe el addon.
- El cortacircuitos del historial (`Guarded`, History.lua): tras 10 fallos se apaga solo.
- Cola de envío con prioridades, caducidad (`QUEUE_TTL`), «gana el último» (`LATEST_WINS`) y un
  prefijo aparte para los datos grandes (`HU20B`).
- Admisión con tope por remitente (`Admit`, `PartialAdmit`) y saneado de lo que llega (`SafeText`, `SafeName`).
- Una única regla de combate, `HU:CombatHold()` (Combat.lua), que ya usan otros módulos.
- Datos por personaje y por cuenta separados con una metatabla (`HU.db`).

## Diagnóstico

Cifras sacadas con grep y con el entorno de pruebas (`tests/`). Las de #3 y #6 son de la 5.4.12
y en la 5.4.41 han crecido: con un recuento parecido salen unas 490 funciones públicas en `HU` y
unos 40 `NewTicker`.

| # | Problema | Dónde | Por qué frena |
|---|---|---|---|
| 1 | Cada mensaje de red se define en hasta 6 sitios | Manejador en cualquier archivo. Seguridad: `TAG_FIELD`, `BOOTSTRAP`, `OPEN`, `REMOTE_DATA`, `CHANNEL_OK` (Comm.lua). Cola: `CHAT_CMDS`, `MID_CMDS`, `LOW_CMDS`, `BFAST_CMDS`, `BULK_CMDS`, `BMID_CMDS`, `BLOW_CMDS`. Caducidad: `QUEUE_TTL`, `NEVER_EXPIRE`, `LATEST_WINS`. Combate: `DEFER_IN` y `BULK_PREFIX` (Combat.lua) | Si falta una tabla no hay error: el mensaje va a la cola por defecto, se rechaza o en combate se trata distinto, sin avisar |
| 2 | Comm.lua es demasiado grande: 4.010 líneas y 208 KB | Comm.lua | Tiene unos 10 bloques `do … end` solo para no pasar de 200 variables locales; dentro hay 5 o 6 módulos |
| 3 | No hay dependencias declaradas entre módulos | `HU`: unas 408 funciones públicas y 78 campos | Unas 185 líneas con `if HU.X then`, que esconden nombres mal escritos |
| 4 | El orden de carga se resuelve con parches | `HU.comm` se crea en Comm.lua, que va después de Channel.lua: `CW`, `CG` y `CF` se registran dentro de `OnStart` | Hay que saber en qué orden van los archivos del .toc |
| 5 | Formato de mensajes por posición y sin escapar | `HU.Split(text, "~")`. `CW` junta lo que sobra con `table.concat(f, "~", 3)` | Añadir un campo obliga a contar posiciones en todos los sitios que lo leen |
| 6 | 29 temporizadores independientes | 4 de ellos van a 1 s o menos (Channel, Comm, Echo, History) | Cada uno con su regla de combate. (History usa `C_Timer` directamente, pero protegido con `Guarded`: no se salta la protección) |
| 7 | Base de datos guardada sin versión | `DEFAULTS` y `PER_CHAR` en Core; la única migración es una marca suelta (`cdb.migrated`) | Cambiar la forma de un dato guardado es arriesgado |
| 8 | `/gu` es un único `if/elseif` de 230 líneas | Core.lua. Alias y ayuda (`HELP`) por separado | Es fácil que la ayuda y los comandos reales dejen de coincidir |
| 9 | Restos de las versiones Reduce y «solo chat» | `IsTest()` y `SimpleMode()` devuelven `false`, `AnnounceList()` está vacía, todo UIStubs.lua; unas 89 líneas preguntan por `CHAT_ONLY`, `IsTest`, `LaunchPhase` o `SimpleMode`. **Y en el protocolo:** `WL`, `WH`, `WD`, `WQ`, `FQ` y `LG` están en 8 tablas de Comm y Combat, pero ya no se mandan ni tienen manejador (63 órdenes sí lo tienen); `HU.whitelist` no lo llena nadie, así que media `AllowAddonMessage` no se ejecuta nunca | Ramas que ya no se ejecutan pero hay que leer, mantener y migrar |
| 10 | No había pruebas | El CI solo pasaba luacheck, y sus avisos no paraban la integración | La lógica de seguridad y los lectores de configuración cambiaban sin red. **Resuelto en parte:** ver paso 1 |
| 11 | La documentación apunta a números de línea | ARCHITECTURE.md (2.589 líneas), con líneas de la ReduceClean-7 | Se queda desfasada con cada cambio; falta una tabla del protocolo |
| 12 | Hay cinco prefijos y no todos pasan por la seguridad central | `HU20` y `HU20B` pasan por `OnAddonMessage` (`Admit` + `AllowAddonMessage`). `HU20H` (History), `HU20C` (Channel, `OnHiddenChat`) y `HU20T` (TestLog) tienen su propio `CHAT_MSG_ADDON` con sus propias comprobaciones | Quien lee Comm.lua cree que ahí está toda la seguridad, y no es así |
| 13 | 54 textos sin traducción al inglés | `L("…")` sin entrada en LocaleEN.lua (619 textos distintos) | Hoy solo se ve dentro del juego, con `/gu idioma` |

## Propuestas

### A. Registro único de mensajes de red

`HU.comm` y el registro se crean en Core.lua; así se acaba el problema del orden de carga. Cada
módulo declara todo lo de su mensaje en un solo sitio:

```lua
HU:RegisterMessage("CW", {
    fields   = { "token", "author", "line*" },  -- "*" = el resto, con los ~ incluidos
    since    = "5.4.0",                          -- primera versión que lo entiende
    -- seguridad: las MISMAS marcas que hoy, no niveles nuevos (ver abajo)
    via      = { WHISPER = true, GUILD = true }, -- CHANNEL solo si hoy está en CHANNEL_OK
    tagField = nil, bootstrap = false, open = false, remoteData = false,
    -- cola y caducidad
    queue    = "chat", ttl = 60,                 -- o ttl = false (= NEVER_EXPIRE); latestWins = true
    -- combate (Combat.lua)
    combat   = nil,                              -- "list" | "req" | "data" | "last" (= DEFER_IN)
    handler  = function(self, sender, m, dist, raw) --[[ m.author, m.line ]] end,
})
```

Reglas:

- **La seguridad se declara con las marcas que ya existen** (`tagField`, `bootstrap`, `open`,
  `remoteData`, `via`). `AllowAddonMessage` sigue siendo el mismo algoritmo, pero lee las marcas
  del registro en vez de sus tablas. Un nivel de confianza resumido (`trust = "community"`, etc.) no
  recoge todos los casos que mira hoy: la vía de llegada, la fase de arranque con `Vouched`, la
  aceptación «débil» de `RB`, los casos especiales de `CW`, `WQ` y `PL`… Forzarlo podría abrir
  mensajes sin querer. Los niveles se estudian en B, ya con pruebas.
- **El manejador recibe el texto original (`raw`)**, como hoy: lo usan `Hold`/`ReplayHeld` y la
  deduplicación de Combat (`rawSeen`).
- **Los campos con nombre no crean una tabla por mensaje.** Los nombres se traducen a posiciones una
  sola vez, al registrar el mensaje (una metatabla compartida: `m.author` es `f[2]`). El chat es el
  camino por el que pasan más mensajes.
- **Formato:** solo puede haber un campo `*`, que tiene que ser el último, y `RegisterMessage` lo
  comprueba. En un mensaje con `*` no se pueden añadir más campos sin cambiar de orden. Los campos
  nuevos van al final y quien no los conoce los ignora.
- **El nombre de la orden son 1 o 2 MAYÚSCULAS** (patrón `^(%u%u?)~?`): `RegisterMessage` rechaza
  cualquier otro. Un nombre con cifras, como `Q9`, se leería como `Q`.
- `Send`, `AllowAddonMessage`, la cola y Combat leen el registro en vez de sus tablas.
- La ayuda, `/gu diag` y la tabla del protocolo de la documentación se generan a partir de él.
- **Se migra mensaje a mensaje**: las tablas actuales siguen funcionando para los que aún no estén
  registrados. Los campos con nombre se leen sobre el mismo formato con `~`, así que todo sigue
  siendo compatible con las versiones que ya tienen los jugadores.
- **Los prefijos** `HU20H`, `HU20C` y `HU20T` quedan fuera del registro en este paso. Se documenta
  qué comprueba cada uno (ver I).

### B. Partir Comm.lua

Por sus costuras naturales, sin cambiar cómo se comporta:

| Archivo nuevo | Contenido actual |
|---|---|
| `Net/Transport.lua` | Cola, `Send`, `Flush`, `BulkWhisper` |
| `Net/Security.lua` | `Admit`, `PartialAdmit`, `Hold`/`ReplayHeld`, `AllowAddonMessage` |
| `Net/Relay.lua` | `RelayScore`, ayudantes, saludo (`HI`/`HR`/`HY`/`RA`), ciclos |
| `Net/RosterSync.lua` | `RB`, `RC`, `RF`, `NQ`, cambios de lista, huellas |
| `Domain/Trust.lua` | Estados de lista (`b`/`m`/`p`/`c`), anclas, `Vouched`, `FullPeer`, `SenderKind` |

Aquí, con las pruebas de caracterización ya en verde, se estudia una sola pregunta de confianza,
`Trust:Level(sender, tag)`, en lugar de las preguntas repartidas hoy entre Comm, Lists y Guard.
Una condición: las pruebas de `tests/spec/seguridad_spec.lua` tienen que dar el mismo resultado
antes y después.

### C. Módulos con dependencias y avisos internos

```lua
local M = HU:NewModule("Guard", { "Roster", "Trust" })
function M:OnInit() end    -- al cargar (ADDON_LOADED)
function M:OnLogin() end   -- al entrar al juego (PLAYER_LOGIN; hoy HU:OnStart)
```

- El núcleo comprueba que las dependencias existen al arrancar; la mayoría de los `if HU.X then` sobran.
- Un bus interno de avisos (`HU:Fire("ROSTER_CHANGED", tag)` / `HU:Listen(...)`) sustituye las
  llamadas directas entre módulos (`Changed`, `RefreshConfig`, `RetryDeferred`…). Reutiliza el
  reparto de `HU:On`, con nombres que no son eventos del juego, para no tener dos sistemas.
- **Antes de C (paso 1)**, una metatabla estricta sobre `HU` en modo depuración, que avise al leer un
  campo que no existe. Encuentra los nombres mal escritos de los `if HU.X then` sin necesidad de
  un sistema de módulos, y abarata C o le quita urgencia.

### D. Un único planificador para lo que se repite

`HU:Every(15, "rosterCycle", fn, { pauseInCombat = true, budgetMs = 1, maxFailures = 10 })` en lugar
de los 29 temporizadores:

- la regla de combate es `HU:CombatHold()`, la que ya existe, y no una nueva;
- tiempos medidos por tarea, para `/gu perf`;
- nada se salta `SafeCall`, y `maxFailures` hace lo mismo que el cortacircuitos de History.

`HU.After` se queda como está: ya pasa por `SafeCall` y se usa mucho con 0 s para repartir trabajo
entre fotogramas (Social, History y la descarga de Combat con `DRAIN_MS`).

### E. Base de datos con versión

- `db.schema = N` y una lista ordenada de migraciones, que se ejecutan en `ADDON_LOADED` antes de
  que ningún módulo lea nada.
- Cada migración se puede ejecutar dos veces sin estropear nada.
- **Volver a una versión anterior:** si el addon encuentra un `schema` mayor que el suyo, no toca
  los datos y avisa con `/gu errores`.
- Cada módulo declara sus valores por defecto y si son de la cuenta o del personaje
  (`HU:Defaults("Pinned", "char", { pinned = {} })`). Desaparece la lista global `PER_CHAR`.

### F. Registro de comandos `/gu`

`HU:RegisterSlash("guardia", { aliases = { "guard" }, officer = true, help = "...", fn = ... })`.
La ayuda sale sola y cada módulo trae sus propios comandos.

### G. Limpiar los restos de Reduce

O se borran las ramas muertas, o se dejan detrás de una tabla `HU.features` explícita si se
piensan recuperar. Lo que no conviene es tener funciones vacías que parecen funcionar. Incluye
las órdenes `WL`/`WH`/`WD`/`WQ`/`FQ`/`LG` de todas las tablas y la rama de `AllowAddonMessage` que
mira `HU.whitelist`. Las pruebas de esa rama están marcadas como «rama muerta» y se borran con ella.

**Pasa al paso 1:** es poco trabajo y evita migrar código que no se ejecuta.

### H. Red de seguridad

- Pruebas con un ejecutor propio, sin dependencias (`tests/run.lua`). No se usa busted porque
  necesita compilar C con luarocks y en Windows no hay compilador. Funciona con Lua 5.1 (CI, el
  mismo Lua que WoW) y con 5.4 (en local).
- **Pruebas de caracterización** de punta a punta: fijan lo que hace hoy el addon para poder
  cambiar el código sin cambiar el comportamiento. `Admit`, `Hold` y `PartialAdmit` son `local`
  dentro de bloques `do` y no se pueden probar por separado, así que se prueban a través de
  `HU.OnAddonMessage`.
- **Pruebas de formato**: la forma de cada mensaje que se mandan las copias de la red queda fijada
  (`tests/golden/formato.txt`); todo lo que se manda lo acepta alguien; y la versión nueva se
  entiende con la última publicada en una red mezclada. Son la garantía de que los jugadores con
  versiones antiguas se siguen entendiendo con los nuevos. (Un «leer y volver a escribir» genérico no
  existe: cada mensaje se escribe a mano y se lee por posición.)
- **luacheck con lista de avisos conocidos**: el CI para solo con avisos *nuevos*. Los que ya había
  están en `tests/luacheck-conocidos.txt` y se van quitando.
- `tests/traducciones.lua` lista los `L("…")` sin traducción. Hoy solo informa; cuando estén todos,
  `--estricto` hará que pare el CI.

### I. Documentación por conceptos

Una tabla del protocolo (generada con A), un apartado sobre el modelo de confianza, otro sobre la
elección del enlace y otro sobre los cinco prefijos y quién comprueba cada uno. En el código, las
referencias van por nombre de función, no por número de línea.

## Orden propuesto

El addon ya tiene jugadores, así que se va por pasos y no se reescribe de golpe. Cada paso se
cierra cuando se cumple su «hecho cuando».

| Paso | Qué | Hecho cuando |
|---|---|---|
| 1 | **H + G + arreglos rápidos**: pruebas, luacheck con lista de conocidos, borrar restos de Reduce, `HU.comm` en Core, metatabla estricta | CI en verde con pruebas y luacheck que paran; ninguna orden sin manejador en las tablas; `CW`/`CG`/`CF` registrados al cargar |
| 2 | **A** (con las marcas de hoy), **F** y **E**. Primera prueba: `CW`, `CG` y `CF` | Ninguna tabla suelta de órdenes en Comm.lua ni en Combat.lua; `/gu diag` lista las órdenes desde el registro; la ayuda de `/gu` sale del registro; `db.schema` existe con su primera migración (`cdb.migrated`) |
| 3 | **B**, y se estudia `Trust:Level` | Comm.lua por debajo de 1.000 líneas y sin bloques `do` para las variables locales; las pruebas de seguridad dan lo mismo que antes |
| 4 | **C + D**: módulos, bus interno y planificador | Ningún `HU.NewTicker` fuera del planificador; los `if HU.X then` que quedan están justificados |
| 5 | **I** | ARCHITECTURE.md sin números de línea; tabla del protocolo generada |

## Paso 1 en detalle

### Ya está hecho

- `tests/lib/wow.lua`: un WoW de mentira con reloj, temporizadores (`Advance`), eventos (`Fire`),
  mensajes de addon que entran (`Receive`) y salen (`sent`), saturación (`failSend`), bloqueo del
  chat (`lockdown`), jugador «Tester-Reino» y su hermandad.
- `tests/lib/addon.lua`: carga **el addon entero** en el orden del .toc (incluidos los `<Script>`
  de los .xml, como el de LibDBIcon), lanza `ADDON_LOADED` y,
  con `:Login()`, `PLAYER_LOGIN`. Arranca y pasa un minuto sin errores guardados.
- `tests/lib/fixtures.lua`: una comunidad de dos hermandades (UNO y DOS) ya configurada.
- `tests/lib/red.lua`: **varios jugadores a la vez**, cada uno con su copia del addon, unidos por
  una red de mentira con reloj común. Reparte GUILD (a su hermandad), CHANNEL (a los del canal, con
  contraseña, dueño y lista de miembros) y WHISPER (el desconectado da `TargetOffline`), con el eco
  de lo propio como en el juego. Lleva la cuenta del tráfico de cada jugador por orden
  (`net:Traffic`). Es lo que hoy se prueba a mano con varias personas y `/gu registro`. Cada
  jugador puede llevar otra versión del addon (`ref = "v5.4.41"`), que se lee de git sin sacarla a
  ninguna carpeta, y lo guardado se conserva al salir y volver a entrar.
- `tests/lib/escenario.lua`: un rato de juego fijo con la red (chat de hermandad y de oficiales, un
  silencio, una búsqueda en el historial, alguien que sale y vuelve).
- Números al azar propios en el WoW de mentira (`wow.Seed`, Park-Miller), iguales con Lua 5.1 y 5.4:
  con el `math.random` de cada versión el escenario seguía otro camino en el CI que en local, y
  History.lua salía 10 puntos más bajo en local.
- 107 pruebas en `tests/spec/`:
  - `carga_spec`: carga, arranque y órdenes registradas (incluido el problema #4);
  - `utilidades_spec`: `Split`, `SafeText`, `SafeName`, `NetT`, `NetStamp`, `Utf8Cut`,
    `VersionGreater`, `ParseConfigText` y `ParseChannelNote`;
  - `seguridad_spec`: la tabla de decisiones de `AllowAddonMessage` por vía y caso, la recepción,
    `Hold`/`ReplayHeld` y la admisión con cupo;
  - `cola_spec`: prefijos, prioridades, saturación, bloqueo del chat, «gana el último», caducidad,
    silencios que no caducan y la pausa por versión mínima;
  - `red_spec`: dos hermandades con dos jugadores cada una. Arrancan sin errores y entran al canal;
    el chat de `/g` llega a la otra hermandad una sola vez, en los dos sentidos y en orden; no se
    repite en la propia; quien entra tarde también lo recibe; y cada uno tiene la lista de la otra
    hermandad antes de 90 s (hoy, 36 s);
  - `listas_spec`: de quién se sabe que es de una hermandad (`ListFresh`, `InAnyGuild`, `MemberOf`, `TrustedOfficer`/`TrustedMaster`) y la raza y profesiones de los demás (`PB`);
  - `comandos_spec`: `/gu fase` y `/gu confirmar`, las comprobaciones «firmes» de oficial y maestro, `MissingLists` y `PL` por susurro de alguien no comprobado;
  - `strict_spec` (la última): ninguna prueba ha leído un campo de `HU` que no existe (metatabla estricta);
  - `chat_spec`: emoticonos, qué líneas de otras hermandades se enseñan (`[ETIQ:B]`, `[ETIQ:O]`, las
    de mi hermandad, los canales extra) y el historial rellenado por otros (`HistInsert`);
  - `formato_spec`, con el escenario:
    - **ninguna forma de mensaje nueva** fuera de `tests/golden/formato.txt` (47 formas de 5
      prefijos). Se guardan los tipos de los campos (`<ver>`, `<n>`, `<nombre>`, `<etiq>`, `<x>`), no
      los valores, para que no dependa del orden de las tablas. Solo falla una forma nueva: con Lua
      5.1 y 5.4 los retrasos al azar dan otro recorrido y algún mensaje sale en una y no en la otra,
      así que `--actualizar` añade y no quita (lo viejo se borra a mano). Si el cambio es a
      propósito: `lua tests/run.lua Formato --actualizar`, y queda a la vista en el diff;
    - **ida y vuelta:** todo lo que se manda por `HU20`/`HU20B` lo acepta la seguridad de alguna otra
      copia. Las excepciones van en `NOBODY_ACCEPTS` con su motivo; hoy, solo `PB` (ver pendiente 10);
    - **versiones mezcladas:** Ana y Blas con la última versión publicada (la etiqueta `v*` más alta)
      y Alba y Bea con la de la carpeta. Sin errores, el chat en los dos sentidos, las listas, el
      silencio y la ida y vuelta.

    Comprobado a propósito: un campo nuevo en `MU` lo detecta la forma, e intercambiar el autor y el
    silenciado al escribir y al leer (la forma no cambia: los dos son nombres) lo detecta solo la red
    mezclada.
- CI (`.github/workflows/ci.yml`): pruebas con Lua 5.1, informe de traducciones y luacheck que
  para con cualquier aviso (`tests/luacheck-conocidos.txt` está vacía desde el paso 1). `tests/` queda fuera del zip del release y del paquete de CurseForge.
- Cobertura (`tests/cobertura.lua`, trabajo `cobertura` del CI): mide las líneas por las que pasa
  alguna prueba, **sin contar lo que se ejecuta solo al cargar el addon** (era casi la mitad de lo
  «cubierto»). Hoy, 33,7 % con Lua 5.1 (26,2 % antes de las pruebas de formato). Para el CI en dos
  casos:
  - un archivo baja de su mínimo (`tests/cobertura-minima.txt`, con 1 punto de margen) **y además**
    tiene más líneas sin probar que antes. Así, borrar código muerto que sí se probaba (el % baja sin
    que falte ninguna prueba) no para el CI; añadir código sin probar o quitar pruebas, sí. Los mínimos
    se miden con Lua 5.1: con la 5.4, luac reparte las instrucciones por líneas de otra forma y cada
    archivo sale hasta 1,2 puntos arriba o abajo, así que en local el margen es de 2 puntos y
    `--actualizar` solo guarda con 5.1. Los mínimos solo suben: cuando un archivo mejora, se copia el
    artefacto `cobertura-minima` del CI;
  - en una PR, las líneas nuevas o cambiadas están probadas a menos del 70 %. El informe dice cuáles
    faltan. Los archivos solo de interfaz (BlizzTab, WMPanel, ListWindow, UIWindows, Wizard) quedan
    fuera de esta regla.

  La tabla por archivo sale en el resumen de cada ejecución del CI.

### Pendiente

1. ~~Quitar los 18 avisos conocidos de luacheck~~ **Hecho** (rama `refactor/arquitectura`): nombres
   que tapaban a otros (`R` y `b` de fuera de Comm.lua renombrados a `SEND_RESULT` y `Bit`; los `L`
   y `c` de dentro, a `wl` y `col`), `if` vacíos reescritos con la condición al revés, una resta que
   no se usaba y dos `local` repetidos. La lista de conocidos está vacía: cualquier aviso para el CI.
   Las líneas tocadas que ninguna prueba ejecutaba tienen ahora `chat_spec`.
2. **Completar el formato con mensajes reales**: lo principal ya está (`formato_spec`). Falta añadir
   mensajes grabados en el juego con `/gu registro` (`tests/golden/entrada/`, cada uno con su efecto
   esperado) para las órdenes que el escenario no provoca y para versiones sin etiqueta en git
   (hay etiquetas de la 5.4.12 a la 5.4.41, con huecos: 5.4.13–5.4.28, 5.4.34, 5.4.38 y 5.4.39).
3. ~~**G**~~ **Hecho** (rama `refactor/arquitectura`), sin cambios de comportamiento:
   - fuera WL/WH/WD/WQ/FQ/LG de las tablas de Comm.lua y Combat.lua;
   - fuera `HU.whitelist` (siempre vacía) y todo lo que la leía en 9 archivos, con
     `AnyListMissing`, `AnnounceList`/`SendList` vacías y la línea «Lista completa» de `/gu estado`,
     que siempre decía que faltaban todas;
   - fuera `IsTest()` (siempre falso: 48 sitios, y Test.lua), `SimpleMode()` (siempre falso) y
     `CHAT_ONLY`/`HU.PHASE`/`LaunchPhase()` (siempre verdadero). `PresenceSchedule` ya solo tiene la
     vía rápida, y `/gu fase` solo dice que esta versión es solo de chat;
   - fuera UIStubs.lua: todos los que llaman a esos métodos del panel antiguo comprueban antes que
     existan.

   Las pruebas de la «rama muerta» se han quitado; las líneas tocadas que no ejecutaba ninguna
   prueba tienen ahora `listas_spec` y `comandos_spec`.
4. ~~`HU.comm = {}` en Core.lua~~ **Hecho**: Core.lua crea `HU.comm` y Channel.lua registra
   `CW`/`CG`/`CF` al cargarse (antes, en `OnStart`). La prueba de carga ahora exige que estén ya al
   cargar (diagnóstico #4 arreglado).
5. ~~Metatabla estricta~~ **Hecho**: `HU:StrictMode` (Core.lua), encendida con `/gu debug`. Leer
   un campo de `HU` que no existe y no está en `HU.MAYBE_NIL` (el estado que empieza vacío, 40
   campos) se apunta en `HU.strictMiss` con archivo y línea, y se avisa una vez. En las pruebas va
   siempre encendida y `strict_spec`, la última, falla con cualquier campo nuevo. Al activarla salieron
   dos restos más del eco quitado en la 5.4.32 (`HU.echoSending` y `HU:EchoStarName`, que nadie
   asignaba), ya borrados. Comprobado a propósito: `self.myTagg` en `HelloCycle` hace fallar la prueba
   con «myTagg (Comm.lua:3694)».
6. **A confirmar:** con `HU.paused` (versión mínima), lo que sale de la cola se pierde en vez de
   esperar (`SendOne` devuelve `false`). La prueba lo fija tal como está; si no es lo que se quiere,
   se cambia la prueba junto con el código.
7. Ir traduciendo los 54 textos que faltan y después pasar `tests/traducciones.lua --estricto`.
8. **Más escenarios de red** (`red_spec`): topes de tráfico por jugador y minuto con
   `net:Traffic`; una entrada masiva (150 jugadores en 60 s tras un reinicio) con tope de cola y
   sin nadie sin lista; conexiones y desconexiones vistas desde la otra hermandad; silencios
   repartidos; y el chat por el respaldo cuando el canal falla. Con lo que se mida en cada sesión
   real de `/gu registro` se ajustan los umbrales y las suposiciones de la red (p. ej. el límite de
   envío del servidor de Forever, que la red todavía no simula).
9. **Subir la cobertura donde más rinde:** History.lua (17 %, el historial compartido entre
   hermandades se puede probar con la red como el chat), Social.lua (17 %), Core.lua (15 %),
   Community.lua (4 %) y Orders.lua (1 %). De vez en cuando, una prueba de mutaciones sobre Comm.lua
   (cambiar a propósito `>` por `>=` o `true` por `false` y ver que alguna prueba falla) para saber
   si lo cubierto está probado de verdad.
10. **Hallazgo de la red: `PB` se pierde al principio.** La raza y las profesiones salen por
    susurro a la vez que la primera lista (a los ~36 s), cuando quien las recibe todavía no se fía del
    remitente. `RB` se retiene y se aplica después; `PB` no (no está en `BOOTSTRAP`), se rechaza y
    no se repite en al menos 6 minutos. Decidir si se retiene o se manda después de la lista; al
    arreglarlo, quitar `PB` de `NOBODY_ACCEPTS` en `formato_spec` (una prueba avisa).
11. **Hallazgo de G: `db.rankCache` se guarda pero no se usa.** Los rangos de las listas
    confirmadas se guardan «para comprobar a los oficiales aunque luego se desconecten», pero
    `RankInfoSlow` (Config.lua) solo los leía si la persona salía además en la lista completa de su
    hermandad, que ya no existe. Desde ReduceClean, un oficial de otra hermandad que se desconecta
    deja de poder comprobarse. Decidir: recuperarlo (leer `rankCache` sin esa condición; cambia la
    seguridad, con su prueba) o borrar también lo que lo escribe (Comm.lua y Social.lua).

### Cómo se prueba

```sh
lua tests/run.lua                 # todas las pruebas
lua tests/run.lua Seguridad       # solo las que llevan «Seguridad» en el nombre
lua tests/traducciones.lua        # textos sin traducción
lua tests/cobertura.lua --base origin/main   # cobertura, y lo nuevo desde main
```

Cuando una prueba falla por una función del juego que falta en el WoW de mentira, se añade a
`tests/lib/wow.lua` con el valor más neutro posible (lo que devolvería un cliente sin datos).

## Cómo quedaría una función nueva

Un archivo que declara sus mensajes (`RegisterMessage`), sus comandos (`RegisterSlash`), sus datos
guardados (`Defaults`) y sus temporizadores (`Every`), y escucha los avisos que necesita
(`Listen`). Sin tocar Core, Comm ni Combat. Y un archivo de pruebas en `tests/spec/` que, al menos,
mande sus mensajes con `w:Receive` y compruebe lo que sale en `w.sent`.

## Qué ha cambiado en la revisión

- Diagnóstico: #1 cuenta las tablas de Combat.lua (`DEFER_IN`, `BULK_PREFIX`) y todas las colas;
  #6 corregido (History no se salta la protección); #9 añade las órdenes muertas del protocolo y
  `HU.whitelist`; nuevos #12 (prefijos fuera de la seguridad central) y #13 (traducciones).
- A: seguridad con las marcas de hoy en lugar de niveles nuevos; `raw` en el manejador; campos con
  nombre sin crear tablas; reglas del campo `*`, del nombre de la orden y de `since`; campo `combat`.
- C: metatabla estricta antes que el sistema de módulos; el bus reutiliza `HU:On`.
- D: acotado a lo que se repite, con `CombatHold` y `maxFailures`; `HU.After` no cambia.
- E: migraciones que se pueden repetir y qué hacer al volver a una versión anterior.
- H: ejecutor propio en lugar de busted, caracterización de punta a punta, pruebas de formato y
  luacheck con lista de avisos conocidos.
- Orden: G pasa al paso 1, cada paso tiene su «hecho cuando», y hay un plan detallado del paso 1.
