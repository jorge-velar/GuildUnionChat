# GuildUnion ReduceClean · notas del código

> [!note] Qué es
> Los comentarios largos que estaban en el código (por qué se hace así, qué pasaba antes, qué midió el banco). En el código queda la primera línea con la marca `[+ARCHITECTURE.md]`; aquí está el texto entero, por archivo y número de línea (de la ReduceClean-7, antes de moverlos) y la primera línea de código que lo sigue.

## Core.lua

### línea 251 · `function HU.Secret(v)`

Solo WoW Forever: los personajes tienen nombre y apellido, y el apellido va donde en los demás
juegos va el reino ("Nombre-Apellido"); no hay reinos. Echar, ascender, degradar e invitar a la
hermandad solo los deja hacer el juego desde un botón suyo: se hace con /gremove, etc.

### línea 272 · `local NAME_MAP_EVERY, NAME_MISS_FOR, NAME_MISS_MAX, NAME_MAP_MS = 30, 30, 500, 1`

Forever: "Pepe" -> "Pepe-Garcia" si solo hay un Pepe entre los que conocemos
El mapa de nombres (miles) costaba 5-12 ms rehacerlo, y se rehacía con cualquier nombre que no estuviera:
un intruso, un aviso del juego, o mensajes con nombres inventados a propósito daban un tirón. Ahora:
  * los que no se encontraron se recuerdan NAME_MISS_FOR s (como mucho NAME_MISS_MAX): no lo rehacen;
  * se rehace como mucho cada NAME_MAP_EVERY s, o antes si cambian los nombres de mi hermandad, y por
    trozos de NAME_MAP_MS por fotograma; mientras, contesta el mapa anterior.

### línea 396 · `function HU:SimpleMode() return false end`

Midnight: el juego no deja mandar mensajes de chat ni de addon en algunas mazmorras y
encuentros. Lo pendiente se queda en cola hasta que se pueda.
(sin modo sencillo en ReduceClean: siempre apagado; aquí y no en UIStubs, que depende de UI.lua)

### línea 415 · `function HU.NetT(v)`

Momento de una acción que llega por la red, para «gana la más nueva»: como mucho dentro de 5
minutos. Antes valía cualquier número: con t=1e300 (o 2^53) la acción falsa ya no la podía
cambiar nadie, porque t+1 da lo mismo. Se recorta en vez de rechazar, por los relojes mal puestos.

### línea 438 · `local LINK_OK = { item = true, spell = true, quest = true, achievement = true, enchant = t`

Texto que llega de otro addon (chat oculto, fijado, notas, historial...): sin saltos de línea ni
caracteres de control, y sin códigos de formato (|T textura, |H enlace, |c color, |K...), que se
pintaban tal cual: se podía imitar una línea del maestro, tapar la pantalla con una textura
gigante o colar un enlace que enseña una dirección y copia otra. Con links = true se respetan los
enlaces de juego bien formados (objeto, hechizo, misión, logro...), que el chat normal también deja.

### línea 585 · `local adb = GuildUnionDB`

Lo de cada personaje va aparte (si no, un personaje de otra hermandad, o al que han echado,
vería el chat, el fijado y el canal de la comunidad de otro personaje de la misma cuenta)
(dentro de lo de la cuenta, un apartado por personaje: así funciona aunque el juego no se
haya reiniciado tras actualizar, que es cuando lee los archivos guardados nuevos)

## Perf.lua

### línea 1 · `local _, HU = ...`

Guild Union - medidor de tirones dentro del juego (/gu perf)
Apagado no cuesta nada: no envuelve nada ni tiene OnUpdate. Encendido (/gu perf on) mide cada
llamada de HU:SafeCall (eventos, temporizadores, inicio) y cada fotograma.

## Popup.lua

### línea 5 · `HU.Dialogs = {}`

Antes usábamos las ventanas del juego (StaticPopup). Tocar esas ventanas desde un addon
"contamina" las del propio juego, y al darle a "Salir del juego" o "Desconectar" el juego
bloqueaba la acción y pedía desactivar el addon. Ahora usamos ventanas nuestras con
las mismas opciones (text, button1, button2, hasEditBox, OnAccept, OnCancel, timeout...).

### línea 213 · `local MUST_TEXT = "Actualización IMPORTANTE de GuildUnion (%s). Tu versión (%s) puede deja`

Actualización IMPORTANTE (HU.mustUpdate, lo pone OnHello solo si alguien de confianza trae una
HU.MIN_VERSION más nueva que mi versión): franja roja fija encima del panel, sin botón para cerrarla,
y línea roja en el chat al saberlo y cada 30 min (nunca en combate ni dentro de mazmorra o banda).
Sin ventana (Jorge, 07/11).
Del mensaje solo se usan los números de la versión.

### línea 226 · `function HU:SetGuildMin(v, fromSaved)`

La versión mínima de la Información de MI hermandad (Config.lua). Con mi versión por debajo, el addon
no manda nada (ni mensajes del addon, ni reenvío al canal, ni respaldo); el /g normal del juego sigue.
Se quita sola al actualizar o si el maestro baja o borra la línea.

### línea 254 · `local MUST_TTL = 7 * 86400`

(lo guardado: sigue mientras mi versión sea más vieja que esa; al actualizar, se borra solo)
(la franja del panel es fija hasta actualizar; lo que se repite cada 30 min es la línea del chat)
(db.mustUpdate = { v = versión, t = cuándo lo dijo un oficial por última vez }: caduca a los 7 días)

## Orders.lua

### línea 1 · `local _, HU = ...`

Guild Union - ventana de órdenes (/ginvite, /gpromote, /gdemote, /gremove)
Copiado de GuildManagement (probado en Forever): en Forever esas acciones son «solo para la
interfaz de Blizzard»: ni un addon, ni una macro, ni un botón seguro pueden hacerlas, y si el
addon escribe en la caja del chat, el juego bloquea esas órdenes hasta /reload. Sí puedes
escribirlas tú. La ventana te deja cada orden seleccionada para copiarla:
  Ctrl+C → Intro (abre el chat) → Ctrl+V → Intro
Al enviarla (tu segundo Intro) pasa sola a la siguiente; si el juego contesta en el chat
(«Has invitado a…», «no se encuentra…»), también. Si no, botón «Siguiente».
El addon solo MIRA la caja del chat: nunca escribe en ella.

### línea 154 · `local function Norm(s)`

Tu segundo Intro (el que envía la orden en el chat): si lo enviado es la orden de la ventana,
se pasa a la siguiente. El addon solo MIRA la caja del chat (lee el texto y se entera del
Intro, después de que Blizzard haya hecho lo suyo); nunca escribe en ella.

## Config.lua

### línea 5 · `HU.ADDON_TITLE = "Guild Union"`

Formato (una directiva por línea, en la Información de hermandad de CADA hermandad):

GU:c:NombreCanal:contraseña        canal común (la contraseña es opcional)
GU:g:Nombre Hermandad:ETIQ         una línea por hermandad, incluida la propia

Chat de oficiales (en la nota de oficial de cualquier miembro, normalmente el maestro):

GU:o:CanalOficiales:contraseña

### línea 123 · `function HU.ParseChannelNote(note)`

GU:c:Canal:clave en una nota de oficial (así la contraseña no la ve cualquiera)
(canal y clave solo letras y números. Si detrás viene algo pegado que no es un espacio, por
ejemplo «GU:c:Canal:clave,120» porque EPGP escribió al lado, la línea no vale: devuelve
nil, nil, true para que no se reparta una clave equivocada)

### línea 167 · `function HU:QuickConfig()`

Arranque rápido: al entrar, el juego tarda unos segundos en dar la Información de hermandad y la
lista. Con la última configuración buena de este personaje (de su misma hermandad) se entra al
canal al momento; cuando llega la de verdad, RefreshConfig la sustituye.

### línea 174 · `local gname = GetGuildInfo("player")`

(si el juego ya dice la hermandad y no es la de entonces, no vale. Si es la misma, vale
aunque sea vieja: EPGP y parecidos pueden haber borrado la línea GU:c de la nota de oficial
y entonces es lo único que queda; si aún no lo dice, solo la de menos de 7 días)

### línea 359 · `HU.ICON_GM = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:15:15:0:-1|t"`

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

### línea 393 · `local rankMemo, rankMemoN, RANK_MEMO_SECS = {}, 0, 5`

Pone la corona o las espadas en una textura (las filas de la lista)
Rango de alguien a partir de las listas que tenemos
(cada línea del chat lo pide para el icono, y con una lista de otra hermandad sin índice se
recorrían sus 1.000 miembros uno a uno: una sola línea llegaba a 3 ms. Se recuerda 5 s)

### (57) `local function Doubt(self, sig)`

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

## Channel.lua

### línea 55 · `local settled = (self.cfg ~= nil and not self.cfg.quick) or (GetTime() - (HU.loginT or 0) `

(al entrar al juego, la hermandad tarda en cargar: no se sale de nada los primeros 30 s
si aún no hay configuración)
(con la configuración guardada del arranque rápido tampoco: aún no se sabe si sigues siendo
oficial, y se saldría del canal de oficiales para volver a entrar al poco)

### línea 107 · `local rosterSel, rosterDirty = {}, {}`

La lista de miembros de un canal se le pide al juego con la POSICIÓN del canal en la ventana
Social > Chat (la de GetChannelDisplayInfo), no con su número del chat (/6). En Classic solían
coincidir; en el cliente moderno (Forever, Retail) no, y se leía otro canal: el Comercio, con
1.100 personas y sin dueño, que es lo que salía en «En el canal» y en la guardia.
Devuelve: posición para GetChannelRosterInfo, cuántos hay, la función de lectura y el número del chat.
El juego solo carga la lista del canal seleccionado en esa ventana: se selecciona (sin abrirla),
como mucho cada 30 s; si aún no está cargada, la lectura sale vacía y se repite en la vuelta siguiente.

### línea 120 · `function HU:NeedsChannelList()`

¿Necesito leer la lista entera del canal por mi cuenta? Solo el enlace (busca moderadores a los
que saludar) y quien es o puede ser moderador: los maestros y oficiales, a los que el propietario
hace moderadores, y quien ya sabe que lo es (la guardia). Con miles en el canal, que la leyeran
todos cada 2 minutos era el mayor gasto del servidor (auditoría de 5.000, E2).

### línea 144 · `local cf = ChannelFrame`

(con la ventana de canales de Blizzard abierta no se le cambia el canal que mira: si mira
el nuestro se lee tal cual; si mira otro, esta vez no se lee. Cerrada, al abrirla vuelve
ella sola al que tenía)

### línea 169 · `function HU:OurChannelKind(localID, chanName)`

¿De qué canal mío viene un mensaje de addon? (localID y channelName son los argumentos 7 y 8 de
CHAT_MSG_ADDON). Devuelve el tipo (main, off, x:Nombre), true si el cliente no dice de qué canal
es (no se puede comprobar), o nil si es de un canal que no es nuestro (el de otro addon, el
comercio...).

### línea 227 · `local moved = {}`

El juego da a cada canal el primer número libre (/4, /5...). Para no quitarle el sitio
a un canal del juego, se intenta mover el nuestro al número libre más alto.
(como mucho dos veces por canal y sesión, y con un minuto entre una y otra: si otro addon
que ordena canales lo vuelve a mover, no nos lo quitamos el uno al otro sin parar)

### línea 245 · `HU.After(0.3, function()`

(hasta la 35; sustituido por `HU:FixChannelOrder`, ver más abajo)

### línea 283 · `HU:OnStart(function()`

Al entrar: se espera a que el juego meta sus canales (como mucho 15 s) y se entra al nuestro (con
la configuración guardada si la de la hermandad aún no ha llegado).

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

### línea 352 · `local needsT, needsV = -999, false`

entradas y salidas del canal: solo las usa quien lee la lista del canal (enlace, oficiales,
moderadores: la guardia). Los demás no hacen nada con ellas (escala2); las listas no dependen de esto.
(con miles entrando a la vez, la respuesta se guarda 1 s: IsRelay recorre la hermandad)

### línea 428 · `local quick = self.cfg and self.cfg.quick`

(recién entrado con la configuración guardada, el juego aún puede no dar la hermandad ni la
lista: vale la hermandad guardada, y la lista se mira en cuanto llega)
(sin la lista aún, también vale si el propio juego ya dice mi hermandad: al entrar la
lista tarda, y mientras tanto el /g no salía)

### línea 483 · `local ECHO_WAIT = 1`

Si el texto no sale por el canal. En Forever, lo oculto del addon por un canal el juego lo acepta
pero no se lo entrega a nadie (Olympus midió 0 de 123): el respaldo ya no va por el canal sino
por susurro a un contacto de cada otra hermandad (CW), que lo reparte a la suya por GUILD (CG).
El chat de oficiales va por susurro directo a los oficiales conectados de las otras.
Si el juego bloquea escribir en el canal, o mi propia línea no vuelve (el eco, como Olympus), se
usa el respaldo para esa línea y para las de los 5 minutos siguientes; luego se vuelve a probar
el canal. Nunca se guarda para siempre (antes, un solo bloqueo lo dejaba así en toda la cuenta).

### línea 520 · `local MAX_OFF_TARGETS = 15`

Formatos:  CW~canal~autor~[ETIQ] msg  (susurro a un contacto de otra hermandad)
           CF~canal~[ETIQ] msg        (a mi hermandad: «repartidlo»; cada ayudante del enlace
                                       susurra a las hermandades que le tocan, como con las listas)
Una línea son tantos susurros como otras hermandades, y el juego deja ~10 de golpe y luego 1 por
segundo: con pocas hermandades los manda el autor; con más, se reparten entre el equipo del enlace.

### línea 630 · `if not self:MemberOf(sender, tag) then`

(quien lo trae tiene que ser de esa hermandad, si ya tengo su lista; el autor lo mira
OnUnionChat)
(como en OnUnionChat: solo la lista COMPLETA reciente basta para rechazar; la de conectados
llega a trozos y en un relevo se queda a medias, y se tiraba el respaldo de su enlace de
verdad; banco eco-2, s 815. Con ella sola, solo se rechaza a quien la guardia ya pilló)

### línea 644 · `local inner = line:match("^%[%w+:E%] ([^:]+): ")`

(el tope es por quien lo trae y autor: un compañero que reparte lo de toda su hermandad
no se queda frenado por lo que escriben los demás)
(en una línea de eco [ETIQ:E] Autor: el autor de verdad va dentro: el tope es por él)

### línea 676 · `HU.comm.CG = function(self, sender, f, dist)`

CG~canal~autor~[ETIQ] mensaje : por GUILD, de un compañero que lo recibió por susurro
(vale de cualquier compañero que esté en la lista de mi hermandad, no solo del enlace: el
respaldo tiene que ir aunque el contacto elegido no sea el enlace. A cambio, tope por
remitente, y cada línea mostrada queda en el registro con quién la reenvió)

### línea 696 · `local LANE_AFTER, LANE_MAX = 3, 9`

Carriles del canal (lo que le pasó a Olympus la noche del lanzamiento de Forever): el juego puede
empezar a rechazar todo lo que va a un canal («canal no válido») aunque sigas dentro, y aceptar
cualquier otro. Tras LANE_AFTER rechazos seguidos, el addon se pasa solo al canal siguiente
(Nombre1, Nombre2… hasta LANE_MAX) con la misma contraseña; como les pasa a todos, se vuelven a
encontrar allí sin que nadie escriba nada. Se recuerda para el próximo /reload, y el enlace lo
dice en su saludo para que su hermandad le siga.

### línea 715 · `function HU:LaneState()`

Estado del carril de la comunidad: { lane, gen, t }. Se guarda en la cuenta, por canal de la
comunidad (lo comparten los alts de esa comunidad, no los de otra). db.chanLane, por personaje,
queda como copia para la 5.4.7 y como punto de partida al migrar.

### línea 784 · `local laneWeakProbeT, laneContactT = -999, -999`

Otro dice en qué carril está la comunidad: se sigue el más alto, pero solo si lo dice alguien
«fuerte» (el enlace de mi hermandad, el enlace conocido de otra, o un oficial). Lo que diga
cualquier otro solo hace sondear mi canal: me muevo si a mí también me rechazan, como con LN~n
(si no, cualquiera con la contraseña mandaba a toda la comunidad al carril 9 con un susurro).

### línea 796 · `if strong == "contact" then`

(el contacto de otra hermandad, sin comprobar: solo el enlace de mi hermandad le hace caso, y solo
para subir UN carril con la misma generación, como mucho cada LANE_CONTACT_GAP. Un intruso con la
contraseña, como mucho, sube un carril cada 10 min, y a las 6 h todos vuelven al principal)

### línea 856 · `function HU:ProbeLane(n)`

Sondeo: un mensaje pequeño al canal (n, si se pide más); si el juego lo rechaza, ChannelSendResult
manda los que faltan para los 3 rechazos y cambia de carril. Es lo único oculto que va por el canal:
en Forever no le llega a nadie, pero no hace falta, solo se mira lo que contesta el juego (el error 7)

### línea 868 · `if HU.wasRelay and GetTime() - lastChannelSend > LANE_PROBE_EVERY - 0.5 and HU:IsJoined("m`

(con wasRelay, lo que salió en mi último saludo, y no IsRelay: este repasa a todos los
compañeros, ~1,8 ms con 500. Un sondeo de más de un enlace antiguo no hace daño. El sondeo,
en la imagen siguiente)

### línea 975 · `if C_Club and C_Club.SendMessage and C_Club.GetGuildClubId then`

Retail: lo que se escribe en el chat de la ventana de la hermandad del juego (Comunidades) no
pasa por SendChatMessage. Se trata igual que el /g: pasa a las demás hermandades y, si estás
silenciado o vetado, no le llega a nadie con el addon (en el chat normal).

### línea 1056 · `local KIND_SHORT = { main = "H", off = "O", lfg = "BG" }`

Igual, pero por separado: la cabecera (canal, hermandad, nombre) y el mensaje
compact (chat del panel): sin el reino, y el canal en corto ([H], [O], [BG]) o sin él
(showKind = false en las pestañas de un solo chat, donde ya se sabe cuál es)

### línea 1122 · `local customByCode, customMaxLen, customFirstPat`

Enlaces web (https://..., www....): se vuelven clicables en el panel del addon.
El juego no puede abrir el navegador, así que al hacer clic sale una ventana para copiarlo.
Solo se cambian si van sueltos (al principio o tras un espacio, y seguidos de espacio o fin),
para no tocar horas como 10:30 ni enlaces.
emoticonos de la comunidad: código -> ruta (caché; se rehace cuando cambian)

### línea 1153 · `if not msg:find("|", 1, true) then`

(atajo: casi ningún mensaje lleva emoticonos. Sin códigos «|», sin ninguno de los emoticonos
del addon escrito tal cual y sin ninguna letra con la que empiece uno de la comunidad, sale
tal cual. Antes bastaba una «x» o una «B» en el mensaje, que casi siempre hay, para recorrerlo
letra a letra)

### línea 1304 · `local ENTRY_IDX = { t = 1, k = 2, tag = 3, a = 4, m = 5, g = 6, hl = 7, late = 8 }`

Entradas del chat guardado en formato compacto: lista por posiciones en vez de campos con
nombre (ocupa la mitad). La metatabla deja leer y escribir e.t, e.a... igual que antes, y las
entradas viejas (con nombres) siguen valiendo tal cual.

### línea 1342 · `local held = {}`

Todo lo que ha escrito un personaje (busca por nombre, con o sin reino)
Quién ha escrito más (para elegir de una lista)
Un mensaje del chat unido, llegue por el canal (CHAT_MSG_CHANNEL) o como mensaje oculto del addon
(cuando el juego no deja al que escribe mandarlo al canal: ver Forward)
Mensajes retenidos de quien escribe con mi etiqueta sin estar comprobado (10 por persona, 90 s)

### línea 1399 · `if tag == HU.myTag and not HU:IsTest() and not HU:MemberOf(author, tag) and not (HU.GuildV`

seguridad: quien escribe tiene que estar de verdad en la hermandad de la etiqueta
(si aún no sé nada de esa hermandad, acabo de entrar: se acepta mientras llegan sus listas;
el canal tiene contraseña y la guardia echa a los intrusos)
Con la lista COMPLETA de esa hermandad (también desconectados), no estar en ella basta para
rechazar. Con solo la de conectados (comunidad grande: no se reparten listas completas) no:
esa lista llega a trozos y le faltan los recién conectados, y se perdían mensajes de miembros
de verdad (banco 18:22: 173 de 791). Ahí solo se rechaza a quien la guardia ya confirmó como
intruso, o a quien su hermandad reclamó como suyo con otra etiqueta.
con MI etiqueta y no es de mi hermandad: se hace pasar por nosotros

### línea 1457 · `local chanQ, chanHead, chanTail, chanBusy = {}, 1, 0, false`

Fluidez (meta: ningún fotograma de más de 1,85 ms): las líneas del canal van a una cola que se
procesa con un tope de tiempo por fotograma. La primera sale al momento; si llegan varias en el
mismo fotograma, las demás salen en los siguientes, en orden. Y guardarlas en el historial (lo que
no se ve) va detrás, en otro paso. Nada se pierde ni se repite: solo se reparte.

### línea 1482 · `local CHAN_FRAME_MS = 0.8`

(el tope es por FOTOGRAMA, no por llamada: las líneas suelen llegar de una en una, cada una con
la cola vacía, y cada llamada empezaba de cero; varias en el mismo fotograma pasaban de 1,85 ms.
Banco, 3×1000 de la 1145: 32 fotogramas así. Ahora se suma lo gastado en el fotograma y, al
llegar al tope, lo que queda espera al siguiente)

## Comm.lua

### línea 5 · `HU.guildPeers = {}     -- [clave] = { name, last, mod, ver }  usuarios del addon en mi her`

Mensajes de addon (prefijo HUNI, campos separados por "~"):

HI~ver~tag~mod~relay        saludo (por GUILD a la hermandad o por WHISPER a otra hermandad)
HR~ver~tag~mod~relay        respuesta a un saludo por susurro
PL~TAG:Nombre,TAG:Nombre    el enlace de la hermandad comparte los contactos que conoce
RB~tag~seq~total~online~parte~partes~datos     lista de miembros conectados (troceada)
Q~nombre,nombre             la guardia pregunta a un moderador si esos jugadores son de su hermandad
A~nombre,nombre             respuesta: los que sí son de su hermandad

En Classic los addons no pueden enviar mensajes a canales personalizados,
así que entre hermandades se usan susurros entre un "enlace" de cada una.

### línea 21 · `local NO_KEYS = {}`

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

### línea 100 · `HU.ghostRoster = {}    -- [tag] = { members = {...}, t, v }`

Listas «de la última vez»: SOLO para enseñarlas en el panel, en gris, mientras llegan las de verdad.
No están en remoteRoster ni en nada que mire la confianza (MemberOf, CheckedOf, SenderKind, KnownSet,
la guardia, el relevo, PL/PH...): solo las lee UIMembers. Se quita la de cada hermandad en cuanto
llega su lista (HU.comm.RB) o a los GHOST_TTL s.

### línea 166 · `local qChat, queue, mid, low = {}, {}, {}, {}`

cuatro colas, por orden de importancia (sale siempre lo de la primera que
tenga algo):
  1. el chat: silencios, vetos, chat lento, canales, mensaje fijado, emoticonos...
  2. lo normal: saludos, contactos y las listas de CONECTADOS de las otras hermandades
  3. las fichas (profesiones, rol...) y los inactivos que alguien está mirando ahora
  4. lo que no corre prisa: listas completas de miembros e inactivos en segundo plano

### línea 330 · `function HU:Send(msg, dist, target, urgent, slow, fast)`

urgent = true pone el mensaje delante de su cola. Devuelve false si no ha entrado en la cola.
slow = true: a la cola de poca prisa aunque la orden sea de las del chat (repasos periódicos)
fast = true: por la cola del chat, delante (conectado/desconectado de oficiales: Presence.lua)

### línea 366 · `function HU:DropQueued(tag, dest)`

Lo nuevo ocupa el sitio de lo viejo (idea de Olympus): una lista entera nueva para una hermandad
deja sin sentido los trozos que aún esperan de la anterior y de sus cambios, mandados al mismo
contacto de esa hermandad (aunque los trozos se repartan entre sus ayudantes; con fast, en qChat)

### línea 374 · `if m.gtag == tag and m.gdest == dest and m.cmd == "RB" then table.remove(q, i); n = n + 1 `

(solo los trozos de listas enteras: los cambios (RC) se quedan. Son pequeños, aplicarlos dos veces
no hace daño y salen en orden. Si se tiraban, el cambio llegaba con la lista entera, 1-2 s tarde y
a la hermandad entera; y la segunda copia de cada cambio, la del contacto, casi nunca salía)

### línea 493 · `local function SamplePerf()`

Quién es el enlace: primero los oficiales y el maestro (si su conexión va bien), y entre
iguales el de mejor ping y más fotogramas por segundo (menos cargado el ordenador). Cada
uno dice su puntuación en el saludo; con la misma puntuación, el primero por nombre.

Puntos (Clean-19): ping sin escalones (30 − ping/5, mínimo 0); estabilidad: saltos del ping
(media de cuánto cambia entre medidas de 30 s: < 5 ms +6, < 15 +4, < 40 +2), tiempo conectado
desde la entrada real al juego (`cdb.sessionStart`, un /reload no lo pone a cero: > 10 min +2,
> 30 +4, > 1 h +6) y −10 por cada otra entrada al juego en la última hora, como mucho −30
(`cdb.logins`, solo con `isInitialLogin` de PLAYER_ENTERING_WORLD). Salir y entrar a propósito
también cuenta. Máximo sin oficial: 30 + 6 + 3 + 6 + 6 + 6 = 57.

### línea 524 · `local AFK_AFTER, AFK_PENALTY, BUSY_PENALTY = 180, 40, 150`

Ocupado: en una banda, un campo de batalla o una arena (resta 150), o ausente (AFK) desde hace
un rato (resta 40). Devuelve si lo está y cuánto resta.
(el AFK automático del juego salta a los 5 min sin moverse: con 150 el enlace cambiaba cada vez
que un oficial se quedaba quieto y volvía al moverse, y cada cambio era una lista nueva para las
otras hermandades. Con 40, otro oficial le releva; un raso no)
(desde la 39, `UnitIsAFK` e `IsResting` pasan por `HU.SafeBool`: en combate o mazmorra el juego
puede darlos como valor secreto y usarlos directamente daba error cada 15 s; secreto = «no»)

### línea 567 · `if IsResting and IsResting() then`

en zona de descanso (ciudad, posada) se sale del juego al momento y no da tiempo a pasar el puesto:
mejor que sea enlace otro. Solo tras 60 s seguidos (entrar y salir de una ciudad no cambia el enlace);
resta 20, más que la ventaja de 15 del enlace actual. Es resta y no suma: la puntuación tiene tope
(SaneScore, 199) y una suma se perdía en los mejores

### línea 580 · `function HU:SaneScore(name, s)`

La puntuación que dice un compañero, dentro de lo posible: como mucho 199, y más de 99 solo si
es oficial de verdad en la lista del juego (Clean-19: antes 149 y 49; sin oficial ya se llega a 57). Antes valía cualquier número (1e309 da infinito)
y quien quisiera se quedaba con el enlace y con lo que llega de las otras hermandades.

### línea 630 · `local current = {}`

(los ayudantes, en el mismo orden que el enlace: los mejores primero; se buscan los mejores
sin ordenar a los cientos de compañeros)
(los que ya son ayudantes tienen ventaja, como el enlace: si no, se turnaban por un poco de ping
o de fotogramas, y cada cambio era una lista nueva para todas las hermandades)
(por clave completa: antes se acortaba el nombre de cada uno de los cientos de compañeros)

### línea 657 · `function HU:InheritHelpers()`

Acabo de pasar a ser el enlace: me quedo con los ayudantes del anterior, y con él si sigue
conectado. Así, los 2 min que ya los mantiene HelloText (helpersChangedT) no cambian. Antes
empezaba con los míos, la lista que va a las otras hermandades los quitaba y a los pocos segundos
los volvía a meter, y la otra hermandad dejaba de verlos ese rato.

### línea 715 · `local cur = self.advertisedHelpers`

(los ayudantes no se cambian más de una vez cada 2 minutos mientras los de ahora sigan
conectados: en la entrada masiva cambiaban hasta 10 veces y cada cambio era una lista
nueva para las otras hermandades, que no se daban por completas hasta el último)

### línea 741 · `if changed and cmd ~= "HR" then self:HelpersChangedHello() end`

(y a mi hermandad enseguida, no en el saludo de dentro de 2-5 minutos: los ayudantes van en
la lista que mandan a otras hermandades, y uno que no sabía quién había entrado mandaba una
lista entera sin él que pisaba la buena)

### línea 766 · `HU.LaneContact = function(sender, tag)`

Contacto de otra hermandad que dice ser su enlace, sin estar comprobado: el que me toca para esa
hermandad (BestPeer) y que sale en su lista (no basta con decir que es el enlace: eso se lo pone
cada uno en su saludo; condición de Seguridad, 07/11). En Forever casi nunca se
llega a «comprobado» y, sin esto, si a una hermandad se le rompe el canal, la otra no la seguía
(ver OfferLane: con esto solo se sube un carril, y como mucho cada 10 minutos)

### línea 807 · `local guildHeardT -- última vez que oí un mensaje del addon de otro de mi hermandad (por G`

El primero de su hermandad en entrar no espera los 30 s de prudencia para ser enlace: pregunta
«¿hay enlace?» (RQ, por GUILD) y, si al entrar en el canal no ha oído NADA de su hermandad, se hace
enlace y se presenta ya; así le llegan las listas de las otras hermandades en unos 15-20 s.
Solo contesta el enlace (no todos, como con HY). En una entrada masiva todos se oyen entre ellos
y siguen los 30 s y la elección por puntuación de siempre.

### línea 855 · `for _, d in ipairs({ 12, 25 }) do HU.After(d, function() HU:AloneAskRosters() end) end`

(a los 12 y 25 s pido la lista a quien conozco de cada hermandad que me falte: la que me mandan
al verme llega a veces antes de que yo los haya visto en el canal, no se acepta, y su enlace no
la repetía hasta pasados 30 s. «~1» = confírmamela: vale a los 5 s)

### línea 885 · `if fast and self:SimpleMode() then fast = nil end`

(cambio pequeño: a dos de esa hermandad, por las dos vías, que tienen cupo aparte (1 mensaje por
segundo cada una). Primero a un oficial suyo con el addon: su hermandad siempre acepta lo que él
reenvía. Luego a su contacto. Con 5 copias por hermandad, un cambio eran 15-45 mensajes y a las
últimas hermandades les llegaba a los 10-40 s)
(en modo sencillo, como antes: una sola copia por la cola normal)

### línea 922 · `local g = HU.sendGroup`

(todos los trozos de un mismo envío, al mismo: si cada trozo iba a un ayudante distinto, cada uno
reenviaba a su hermandad medio envío, y como los trozos se juntan por quien los reenvía, la lista no se
completaba nunca; clave-reloj, G03)

### línea 933 · `HU.PEER_TTL = 700`

Soy el "enlace" de mi hermandad si mi nombre es el primero (alfabéticamente)
entre los usuarios del addon conectados de mi hermandad.
Cuánto vale un saludo de un compañero (se saluda cada 2-5 min, según lo grande que sea la hermandad)

### línea 964 · `if self.loginT and GetTime() - self.loginT < 30 and not self.aloneRelay then return false `

(recién entrado no se es enlace: aún no se ha oído a nadie y cada uno se creía el enlace
durante unos minutos, mandaba su lista a las otras hermandades y pisaba la buena)
(salvo el primero de su hermandad en entrar: AloneCheck)

### línea 1013 · `if (not p.remT or GetTime() - p.remT > 60) and self:CheckedOf(name, tag) then`

(guardarlo entre sesiones: como mucho una vez por minuto por persona; antes, con cada
mensaje de chat que escribía)
(solo quien está de verdad en la lista de esa hermandad: antes bastaba con mandar una lista o
hablar con su etiqueta, y quedaba guardado como contacto de ella para siempre)

### línea 1023 · `local VOUCH_TTL = 900       -- lo que dura el aviso de un enlace comprobado (o de mi herma`

Quién puede mandarme la lista de conectados de otra hermandad, y cuánto me fío de ella.
Estado de la lista de cada hermandad (r.state):
  "b" arranque: se ve, pero nadie cuenta como miembro (weak) ni da rango
  "m" miembros: cuentan como miembros; el rango se guarda aparte (rankHidden) y no se usa
  "p" rangos provisionales (r.pBy = "old": dos cuentas, una conocida; "time": solo por tiempo)
  "c" confirmada: la ha mandado o confirmado un contacto comprobado

### línea 1041 · `local OLD_FROM_TIME = false`

(las dos cuentas que respaldaron una lista que llegó a rangos solo por tiempo se guardan como antiguas.
Apagado: con dos cuentas y 30 min, un intruso se confirmaba él solo. En una comunidad nueva, el ancla
es «/gu confirmar ETIQ» de un oficial)

### línea 1091 · `function HU:AnchorValid(tag, k)`

Ancla de confianza de cada hermandad: el maestro (u oficial) que aceptó la invitación a la comunidad
(el remitente lo pone el juego), o quien invitó a la mía. Su lista vale como confirmada al momento.
Vale mientras no tenga la lista de esa hermandad confirmada o, si la tengo, mientras salga en ella de
maestro u oficial; si sale con otro rango (lo han cambiado o echado), deja de valer para siempre.
Lo guarda Community.lua en db.anchors[etiq] = { name, dead }.

### línea 1154 · `function HU:SenderKind(sender, tag)`

Con qué me fío de quien me susurra una lista de esa hermandad: "vouched" (lo nombró su enlace
comprobado), "peer" (contacto comprobado), "member" (sale en mi lista actual), "old" (contacto de
antes, sin comprobar), "boot" (salió en una presentación del canal) o nil. Ya no vale haber escrito
en el chat con su etiqueta ni un saludo HI.

### línea 1271 · `if conflict and not self:AnchorValid(tag, k) then`

(un contacto comprobado que contradice la que tengo sin confirmar: disputa; si la tengo
confirmada de otro, también: que lo vean los oficiales. El ancla de esa hermandad no: la
suya manda)

### línea 1328 · `if HU.MarkRelay and k then`

(enlace PROVISIONAL: lo que va para esa hermandad se le manda a quien me mandó la lista, pero sin
«dicho por él», así que no se cuenta a otros con PL/PH ni nombra ayudantes)
(pero no si su enlace se ha presentado él mismo hace poco y es otro: la segunda opinión le quitaba
la marca, mi enlace dejaba de contarlo a mi hermandad (PL), nadie se fiaba de él y la lista no se
confirmaba nunca; clave-reloj, G03)

### línea 1366 · `r.updated = GetTime()`

(a toda mi hermandad, la confirme quien la confirme: SetRosterState solo la reparte si soy el
enlace o llevo esa hermandad. Un oficial cuenta como forwarder, así que la toman con su estado
"c". Como recién hecha (edad 0), para que nadie la descarte por tener una copia más nueva)

### línea 1377 · `HU:OnStart(function()`

(hasta la 5.4.8 se guardaba como contacto a cualquiera que mandara una lista: lo guardado puede
llevar intrusos. No se borra: se marca como antiguo, que solo vale para arrancar y para coincidir
con otra cuenta, hasta que se compruebe otra vez)

### línea 1399 · `function HU:SafePeer(tag)`

El mejor contacto, solo si me fío de él: para lo que lleva contraseñas (canal y canales extra). Antes
iba al mejor contacto, que el primer día podía ser un intruso que se decía enlace (90-125 s en el
banco): se llevaba la contraseña nueva aunque la acabaran de cambiar para echarle

### línea 1414 · `if m and m.t == now and m.p and self.remote[m.p.name:lower()] == m.p then return m.p end`

(si se ha quitado al elegido en este mismo fotograma, p. ej. «no está conectado», se busca otro)
(solo dentro del mismo fotograma: el mejor contacto depende de a quién se oyó por última vez, y al
llegar un aviso de carril su remitente pasa a ser el mejor. Con 1 s se devolvía el de antes,
HU.LaneContact no daba por bueno el aviso y la otra hermandad no seguía el carril hasta el saludo
siguiente: 7b semilla 3, chat > 1 s 51 %, carril nuevo a los 628 s)

### línea 1426 · `local rr = self.remoteRoster[tag]`

(con lista buena de esa hermandad, quien no sale en ella va detrás de todos los que sí. El
«soy moderador» del saludo ya no cuenta: lo decía cualquiera del canal (nadie lo comprueba) y
se quedaba con lo que iba para esa hermandad y con las preguntas de la guardia)

### línea 1460 · `local sharedRelayOf, plRelayOf = {}, {}`

(de qué enlace se contó lo último: si cambia, se cuenta ya, sin esperar los 300/600 s. Si no, tras un
relevo mi hermandad no conocía al enlace nuevo de la otra hasta 5 min después; en Forever la
presentación del canal, que antes les llegaba a todos a la vez, no llega)

### línea 1482 · `function HU:KnownRelay(tag)`

El enlace de esa hermandad, solo si lo dijo él mismo hace poco. Es lo único que se cuenta a
otros: si se pasaba el "mejor contacto", alguien que solo había hablado en el canal acababa
marcado como enlace en toda la hermandad, y no contesta a las peticiones de listas.

### línea 1501 · `local minv = f[10]`

actualización IMPORTANTE: su versión mínima es más nueva que la mía. Solo de un oficial o GM: de
mi hermandad (por su rango en mi lista) o de otra con su lista confirmada («c»). Un raso podía
mandar 99.9 y dejar a toda la comunidad con la franja para siempre (Seguridad, 07/11). Y quien la
dice tiene que tener él mismo una versión de al menos esa (si no, es un número inventado)

### línea 1536 · `if f[7] and HU.OfferLane and ((f[8] and f[8] ~= "") or isRelay) then`

(carril de la comunidad: del enlace o de un oficial, se sigue; de cualquier otro compañero
con generación, solo hace sondear (OfferLane); sin generación (versiones anteriores),
solo cuenta el enlace, como antes)

### línea 1562 · `if relay and not (HU:CheckedOf(sender, tag) or HU:FullPeer(sender, tag) or (HU.VouchedOf a`

(por susurro, «soy el enlace de X» solo vale de alguien de la lista de X, o avalado por X:
si no, un intruso con solo la contraseña del canal se quedaba de enlace de X, recibía lo
que iba para X y lo presentaba a mi hermandad con PL/PH. Si no cuadra, contacto normal)
(de su lista CONFIRMADA, o contacto comprobado: con una sin confirmar, el que la mandó se daría
por enlace él solo y mi hermandad lo presentaría con PL/PH como si estuviera comprobado)

### línea 1570 · `if not (HU.RosterTrusted and HU:RosterTrusted(tag)) and HU.BootPresented then HU.BootPrese`

(pero sin datos buenos de X vale como una presentación del canal (raSeen): solo sirve para
arrancar, con la lista como «arranque». El saludo es tan fácil de fingir como el RA, y sin
esto el enlace no aceptaba la lista de X hasta oír su RA, que puede tardar minutos)

### línea 1614 · `if HU:CheckedOf(sender, tag) then HU:RememberPeer(sender, tag) end`

(contacto guardado = comprobado: solo si sale en la lista confirmada de su hermandad. Antes se
guardaba a cualquiera que saludara, y en su segundo saludo ya contaba como comprobado: su
«soy el enlace» se aceptaba y el PH de mi forwarder lo daba por enlace en toda mi hermandad)

### línea 1643 · `local lastAnnounce, lastAnnounceText = -999, nil`

cada enlace se presenta en el canal oculto (lo ven todos los del addon de
todas las hermandades a la vez). Así nadie tiene que ir buscando contactos hermandad por
hermandad, que con 20 hermandades tardaba muchísimo.   "[ETIQ:R] ayudante,ayudante"

### línea 1648 · `function HU:AnnounceByWhisper(text, target)`

La presentación por susurro: al enlace (o mejor contacto) de cada hermandad y a sus ayudantes,
que son quienes la usan (huella de la lista, ayudantes, arranque). Sin contacto en una hermandad,
la encuentra el saludo de RelayHelloRest. target: solo a él (contestar a otra presentación).

### línea 1702 · `for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do`

Forever usa el cliente moderno: si el juego bloquea que el addon escriba solo en el canal (como
en Retail), a partir de ahí la presentación va como mensaje oculto, y se manda ya otra vez
(según el caso, el juego lo da como "bloqueado" o como "prohibido": se escuchan los dos)

### línea 1735 · `local PROV_SPAM, PROV_HOLD = 25, 75`

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

### línea 1784 · `local L = self.whitelist[tag]`

(si ya tengo la lista de esa hermandad, el que se presenta como su enlace tiene que estar en
ella: antes cualquiera del canal se hacía pasar por el enlace de otra hermandad y recibía
lo que iba para ella)

### línea 1794 · `do`

(salir en una presentación del canal se apunta siempre: solo vale para arrancar, y una lista
confirmada y al día no la cambia nadie así. Si no, el enlace nuevo de una hermandad cuyo enlace se
cayó sin avisar no podía mandar su lista hasta que la mía caducara, unos 40 min)

### línea 1808 · `if byWhisper or self:KnownRelay(tag) then return end`

No sale en mi lista de X. Si X no tiene enlace «dicho por él» desde hace más de 900 s (el
primero de su hermandad en entrar es un raso), queda de enlace PROVISIONAL: le mando lo que va
para X, pero sin «dicho por él», sin ayudantes ni PL/PH, y sin tocar el estado de mi lista.
El primero guarda el sitio mientras siga presentándose (PROV_HOLD); otro solo se lo quita si
es un contacto guardado. Si no, un intruso con la contraseña se quedaba lo de X hablando el último.
(por susurro, nunca: sin pasar por el canal no se sabe ni si tiene la contraseña)

### línea 1821 · `if self:IsRelay() and (not answeredRA[pk] or GetTime() - answeredRA[pk] > 600) then`

(y se le contesta como a cualquier enlace nuevo: si no, no me oía hasta mi siguiente
presentación (minutos) y no aceptaba la lista que le mando. El saludo directo llega enseguida;
la presentación del canal espera a los 30 s de prudencia)

### línea 1850 · `local names, hash = (msg or ""):match("^(.-)%s*#(%x+)%s*$")`

Sin datos buenos de esa hermandad, quien se presenta no es aún su enlace «dicho por él» ni nombra
ayudantes: antes, cualquiera del canal se quedaba de enlace de una hermandad sin lista. Solo
queda apuntado para arrancar (raSeen, abajo). El enlace provisional es quien me mandó la lista
de arranque (HU.comm.RB); si es él, sigue siéndolo.

### línea 1868 · `MarkRelay(tag, author)`

(sin enlace «dicho por él» de X: el que se presenta queda de enlace provisional con la misma
regla que arriba. Antes solo el que me había mandado la lista sin confirmar; en una entrada
masiva era el primero en presentarse, que ya no era enlace, y lo de X le seguía llegando)

### línea 1916 · `if hash and tag ~= self.myTag then`

huecos: si mi lista de conectados de esa hermandad no coincide con la suya dos avisos
seguidos (unos 10 minutos), me he perdido algún cambio: la pido a mi hermandad, y si
sigue igual, quien se encarga de esa hermandad la pide entera a su enlace

### línea 1930 · `if r.annMiss >= 2 and self:LaunchPhase() and self.ResponsibleFor and self:ResponsibleFor(t`

(fase de lanzamiento: la lista son unos nombres; si no cuadra dos veces, se le pide
entera a su enlace directamente, en vez de solo a mi hermandad, que puede tener la misma
copia incompleta. Quien se encarga de esa hermandad, para no pedirla todos)

### línea 1952 · `local strict = not self:IsTest() and not self:IsGuildForwarder(sender)`

Seguridad: de mi enlace, sus ayudantes o un oficial, como antes. De otro compañero, solo si el
enlace que nombra está en la lista de X, y de sus ayudantes solo los que también lo estén
(antes cualquier compañero nombraba enlace de X a quien quisiera, y toda la hermandad le
mandaba lo de X y le preguntaba la guardia)

### línea 1978 · `local firm = self:IsTest() or self:CheckedOf(relay, tag) or self:FullPeer(relay, tag) or s`

(PH lo manda quien acaba de recibir el saludo del propio enlace: vale como dicho por él, pero
solo si yo también lo tengo por comprobado; si no, enlace sin «dicho por él», que no se cuenta
a otros ni da confianza)

### línea 1986 · `local laneProbeT = -999`

Un compañero se ha pasado a otro carril del canal (LN~n): el enlace lo comprueba sondeando el
suyo; si también le rechazan, se mueve y lo dice en su saludo (así la hermandad no sigue a
cualquiera, solo al enlace). LP (sondeo) no hace nada al recibirse.

### línea 1997 · `if strong == "contact" and not self:IsRelay() and self.myTag and IsInGuild()`

(el aviso de otra hermandad me llega a mí porque soy su contacto, pero solo mi enlace puede
mudar a mi hermandad: se lo paso por GUILD. Si no, no se enteraba hasta el siguiente saludo
de su enlace, a los 1-10 min, y mientras el chat entre las dos iba por el respaldo)

### línea 2032 · `do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locale`

LQ: «¿en qué carril estás?» de otra hermandad. Contesto con mi LN por susurro (a cada uno como
mucho cada 10 s, y a todos 1 por segundo). También a quien no me ha saludado: con hermandades
grandes casi nunca me llega el saludo de quien pregunta, y entonces no contestaba

### línea 2051 · `HU.comm.LX = function(self, sender, f, dist)`

LX~carril~gen~hora~ETIQ~contacto: un compañero me pasa el aviso de carril del contacto de otra
hermandad. Solo el enlace le hace caso, y solo si ese contacto sale en la lista de su hermandad;
luego vale como «contacto» en OfferLane (un carril, misma generación, cada 10 min como mucho)

### línea 2095 · `local strict = false`

Seguridad: por susurro solo lo presenta el enlace (o un ayudante u oficial) comprobado de otra
hermandad; antes valía de cualquiera que hubiera hablado en el canal, que se nombraba enlace
de X y además se lo contábamos a toda la hermandad. Por la hermandad, de mi enlace, sus
ayudantes o un oficial vale como antes; de otro compañero, solo nombres que estén en la lista
de esa hermandad (sin datos de ella, no se le hace caso).

### línea 2181 · `local function NextSeq()`

Número de envío siguiente: la HORA DEL SERVIDOR (igual para todos) por 10, más un contador para que dos
envíos del mismo segundo no tengan el mismo. Así dos listas o cambios de una hermandad se pueden comparar
SIEMPRE, los haya hecho quien los haya hecho. Antes cada origen numeraba por su cuenta y solo se
comparaban los del mismo: una lista vieja reenviada sin origen pisaba a la buena y quitaba a quien
acababa de volver (banco, chivato de listas: 6 de 6 casos, oficiales y GM que volvían hacía 2-8 s)

### línea 2415 · `function HU:SendRosterDelta(target, st, fast)`

Solo los cambios desde lo último que se mandó:  RC~ETIQ~seqBase~seqNueva~total~conectados~parte~partes~cambios
  cambios: +nombre,clase,nivel,rango,zona[,a]  (entra o cambia)   -nombre  (se va)
Devuelve false si son tantos que es mejor mandar la lista entera

### línea 2442 · `do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locale`

Fase de lanzamiento: alguien de la lista de otra hermandad (oficial, enlace o ayudante) acaba de
entrar en el canal, así que viene de conectarse o de /reload y ha perdido las listas. Quien se
encarga de su hermandad le manda la mía sin esperar a que la pida (la petición podía no llegar
nunca a quien la contesta). Son unos pocos nombres.

### línea 2504 · `if p and self:LaunchPhase() and not p.relay then`

(quien vuelve de una desconexión ha perdido los contactos y el "mejor" puede ser cualquiera
que haya hablado en el canal, que no contesta a RF: primero se pregunta a mi hermandad quién
es su enlace y se vuelve a intentar enseguida)

### línea 2524 · `local savedAsked = {}`

Recién entrado: a los contactos guardados de cada hermandad de la que no tengo lista confirmada les
pido la lista directamente (RF~miEtiq~2), sin esperar a ser enlace ni a que conteste mi hermandad.
Solo oficiales y quien está solo en su hermandad: con 2.000 entrando a la vez serían miles de
susurros, y a los demás se la pasa su hermandad (NQ). Como mucho 2 contactos por hermandad y 2
vueltas. La respuesta pasa por HU:SenderKind / HU:DecideRoster como cualquier lista.

### línea 2543 · `local full = {}`

Contactos comprobados (no antiguos) de esa hermandad: con ellos cualquiera, también un raso,
confirma enseguida la lista que le ha pasado su hermandad (que, si la hermandad aún se asienta,
llega «sin confirmar» y así se quedaba minutos). A ellos se les pide aunque la lista acabe de
pasar por GUILD: lo que falta no es la lista sino un contacto comprobado que la confirme. El
otro lado contesta como mucho SECOND_MAX veces cada SECOND_WIN s, así que no se multiplica

### línea 2579 · `local nqSeen = {}      -- [R/W..etiqueta] = cuándo las pidió otro de mi hermandad`

quien acaba de entrar pide primero a SU hermandad lo que le falta
(sus compañeros ya tienen las listas de las otras hermandades). Contestan el enlace y sus
ayudantes, repartiéndose las hermandades, y lo mandan por GUILD (así les sirve a todos
los que acaban de entrar). Solo si nadie lo tiene, se pide a la otra hermandad (RF/WQ).
  NQ~R:ETIQ,ETIQ~W:ETIQ,ETIQ    (R = lista de conectados, W = lista de miembros)

### línea 2587 · `local listSeen = { sig = {}, force = {}, GAP = 10 }`

(en una sola tabla: la parte principal del archivo no puede pasar de 200 variables locales)
sig[tag] = { sig, t }: la última lista de esa hermandad que pasó por GUILD (o que mandé yo); force[tag] =
cuándo la mandé yo con prisa; GAP: en ese tiempo no sale otra igual ni otra con prisa

### línea 2602 · `do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locale`

Id de un trozo de la lista de una hermandad: trozo · número de envío de quien la hizo · huella. Hoy hay
un solo trozo (1, la lista entera); con las listas completas por trozos, cada trozo llevará el suyo.
Sale de lo que ya lleva la RB: no cambia el mensaje y las versiones viejas lo siguen entendiendo.

### línea 2674 · `local now, mySig = GetTime(), listSeen.Sig(r)`

(la misma lista que acaba de pasar por GUILD no se vuelve a mandar, y con prisa como mucho una vez
por hermandad cada 10 s: por GUILD les llega a todos los que acaban de entrar. Antes, con cada
compañero que entraba, salía otra igual: 600-880 en 30 min y la cola del enlace no se vaciaba)
(solo si pasó después del último que entró o la pidió (listSeen.need): si no, ese no la tiene)

### línea 2682 · `local gap = self:LaunchPhase() and 10 or 600`

(la misma lista entera, como mucho cada 10 minutos: los cambios ya llegan al momento.
En la fase de lanzamiento la lista son unos pocos nombres: cada 10 s, para que a quien
entra o vuelve tras una desconexión se la mande alguien de su hermandad enseguida; con muchos
entrando a la vez, una sola vez cada 10 s les sirve a todos)

### línea 2706 · `local age = math.max(0, math.floor(GetTime() - (r.updated or GetTime())))`

(al final, cuántos segundos tiene mi copia: quien tenga una más nueva no deja que esta la pise;
quién la hizo: el número de envío solo se puede comparar entre listas del mismo origen; y su
estado (b/m/p/c): mi hermandad la toma igual que yo, sin darla por buena si no lo es)

### línea 2723 · `do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locale`

Quien entra suelto tiene que tener las listas de todas las hermandades en 5-10 s. En cuanto el juego
avisa de que un compañero se ha conectado, quien se encarga de cada hermandad (el enlace o el ayudante
que la lleva) reparte por GUILD la lista que tiene, con su estado, a los WELCOME_DELAY s: lo que tarda
su addon en estar listo. En fase de lanzamiento cada lista es un solo mensaje. Con muchos entrando a
la vez sale como mucho una por hermandad cada WELCOME_GAP s, y les sirve a todos. (No va por susurro:
una lista de otra hermandad que susurra un compañero no se acepta, y así no depende de que pregunte)
(1 s: lo que llegue antes de que el addon del que entra esté listo, él lo guarda y lo aplica en cuanto
lo está; ver earlyRB en HU.comm.RB)

### línea 2811 · `local function quiet(secs) return not (rbInGuild[tag] and GetTime() - rbInGuild[tag] < sec`

(día a día: quien contesta lleva más de 5 min conectado y tiene la copia confirmada. Entonces
contesta UNO, el mismo para todos, al momento; a los 0,6 s el enlace y a los 2 s el siguiente
del reparto, si aún no ha pasado por GUILD, aunque esté dentro del freno de SendStoredRoster.
Si no, como antes: mientras la hermandad se asienta, repartir al momento copias recién hechas
tapaba las confirmadas que llegaban después)

### línea 2838 · `local function PromoteSameOrigin(self, tag, mine, origin, pt, dist)`

Lista que alguien de confianza de mi hermandad reparte como confirmada («c»: un oficial con /gu
confirmar, o el enlace), pero mi copia es más nueva o algo distinta: no se pisa, solo se le sube el
estado si es del mismo origen. Antes se descartaba y la mitad de la hermandad seguía sin confirmar.

### línea 2847 · `local memberAsked = {}`

Lista confirmada que ya no cuadra con la que llega (ha cambiado quien la lleva: el enlace nuevo no
salía en ella, y la suya se descartaba para siempre, así que nunca quedaba comprobado). Se pide la
lista a alguien conectado de la que tengo, mejor un oficial: si la manda él, cuenta como «de la
lista» y la nueva queda confirmada, con el enlace nuevo dentro.

### línea 2916 · `HU.partialRoster = {}`

Lo que ya ha llegado de una lista entera que viene en varios trozos: solo para el panel, que va
enseñando los nombres según llegan (y no quita a nadie hasta tenerla entera). El resto del addon
sigue con la lista anterior hasta que llegan todos los trozos.

### línea 2982 · `function HU.ApplyRosterDelta(self, r, tag, parts, nparts, st)`

st: la hora del servidor del cambio (su número de envío). Cada miembro guarda la de su último cambio
(m.st; los de una lista entera, la de la lista): un cambio más viejo que lo que ya sé de ese nombre no
lo toca. Así un «sale» que llega tarde no quita a quien ya ha vuelto, ni un «entra» viejo pisa uno nuevo

### línea 3058 · `if dist == "GUILD" and (f[9] == nil or f[9] == "") and (f[10] == nil or f[10] == "") then `

(por GUILD, una lista sin quién la hizo NI estado no se acepta: todos los addons la reenvían con los
dos. Así un reenvío tardío, o alguien con el addon tocado, no puede borrar a nadie; banco, chivato de
listas: 6 de 6 desaparecidos eran esto)

### línea 3080 · `local kind = (self.acceptKind[tag] or {})[self:Key(sender) or ""]`

(con su antigüedad, 0, quién la hizo, para que mis compañeros puedan comparar números de envío,
y el estado con que la tomo: mis compañeros la toman igual. Si no cabe, sin quién la hizo; si
tampoco, solo va tal cual si es confirmada: si no, la tomarían por buena)

### línea 3096 · `local pkey = tag .. ":" .. seq .. ":" .. sender:lower()`

(puede haber dos listas llegando a la vez: cada una se junta por separado)
(y también por quien la manda: dos compañeros que reparten la misma lista la trocean cada uno a su
manera, y juntar el trozo 1 de uno con el 2 de otro dejaba media lista; banco, chivato: G02 de 19
a 6, el GM y el enlace incluidos)

### línea 3107 · `local quietMax = HU:LaunchPhase() and 15 or 120`

(si a los 40 s sigue a medias, se ha perdido algún trozo: se pide a
mi hermandad en vez de esperar a la siguiente lista entera, que tarda 30 minutos)
(solo si no llega ningún trozo más en 40 s: si van llegando, es que va despacio)
(fase de lanzamiento: la lista son 1-2 trozos; si a los 15 s sin trozos nuevos sigue a medias,
se pide ya, también a quien me la susurró (RF~etiq~1). Antes se esperaban 2 minutos)

### línea 3172 · `local age = (dist == "GUILD") and tonumber(f[8]) or nil`

Una lista repartida dentro de mi hermandad dice cuántos segundos tiene. Si la mía es más nueva
(me han llegado cambios después), no se pisa: antes, una copia vieja borraba a quien acababa de
entrar en la lista, y no volvía hasta la comprobación de cada 10 minutos. Y se reparte la mía,
para corregir a los demás (si nadie lo ha hecho ya).

### línea 3182 · `local theirSig = (dist == "GUILD") and f[11] or nil`

Del mismo origen y con un número de envío más bajo que la mía: es más vieja (cada origen numera
hacia arriba). Antes, una copia vieja que un compañero tenía guardada pisaba la buena aunque su
antigüedad pareciera nueva (los cambios sueltos la marcan como recién actualizada), y quien
acababa de entrar desaparecía hasta la siguiente lista entera (minutos).
(el número da la vuelta al llegar a 99.999: solo cuenta como más viejo si la diferencia es pequeña)
Mismo origen y mismo número de envío que la mía, pero otra huella: una de las dos se quedó a
medias (visto en el banco: el maestro de una hermandad desaparecía al pisarse la buena con otra
copia del mismo envío). No se pisa ninguna; quien se encarga de esa hermandad pide la entera a
su enlace, como mucho una vez por hermandad cada 60 s, y la nueva llega a todos por GUILD.

### línea 3205 · `local older = mine and not mine.weak and mine.seq and seq < mine.seq`

(más vieja que la mía, venga de quien venga: el número es la hora del servidor de cuando se hizo,
y la mía lleva la del último cambio que le he aplicado)
(ya no se tira: se junta con la mía nombre a nombre más abajo, y lo más nuevo de cada uno gana. Si se
tiraba, las listas de otros compañeros tampoco contaban para confirmarla: en clave-reloj, la de G03 no
se confirmaba nunca. Por GUILD, además, se reparte la mía para corregir a los demás)

### línea 3240 · `local cs = mine and not mine.weak and HU.RosterStateOf(mine)`

(un reenvío tal cual lleva el estado con que lo tomó quien lo reenvía, que puede saber menos que
yo: si la lista es exactamente la mía, no me baja el estado. Antes, cada reenvío de un ayudante
devolvía G03 a «arranque» a toda la hermandad, nadie contaba como miembro y no se confirmaba
nunca; clave-reloj. Una lista distinta sí la baja, como siempre: así se ven las disputas)

### línea 3256 · `local ok = self:Key(origin)`

(yo llevo el reloj de esa hermandad y esta lista es un reenvío tal cual de un compañero de
confianza (edad 0, sin huella: no es una copia guardada) de la que le susurró quien la hizo:
cuenta como si me la hubiera mandado a mí. Si no, cuando la otra hermandad repartía sus
listas entre mis ayudantes, las dos cuentas nunca me coincidían y la lista no se confirmaba:
clave-reloj, G03 sin rangos en toda la prueba)

### línea 3270 · `if mine and mine.members and mine ~= nr then`

Junta con la mía, nombre a nombre (lo pidió Jorge: que no desaparezca nadie). Cada uno lleva la hora
de su último cambio (st):
  · está en las dos: gana la que sepa algo más nuevo de él;
  · solo en la mía y con un cambio posterior a esta lista: se queda (entró o cambió después);
  · solo en la mía y sin nada posterior: solo se quita si la lista es FIABLE: confirmada («c») y hecha
    por alguien que llevaba ≥5 min conectado (su lista del juego ya bien cargada). Una que no lo sea
    solo añade: quien acaba de entrar o recargar no puede vaciar una hermandad (banco, semilla 2:
    G03 casi entera fuera 2-7 s)

### línea 3279 · `local reliable = false`

(fiable: confirmada, y quien la hizo sale en MI copia de su hermandad conectado desde hace ≥5 min,
según la hora de su último cambio. Lo que dice él de sí mismo (seq.up) solo sirve para descartar:
un addon tocado podría decir siempre 5 min)

### línea 3289 · `local kept = false`

(lo que se queda solo porque la lista no es fiable, se queda KEEP_FOR s como mucho: si no, la copia
guardaba para siempre a quien ya se fue, su huella nunca cuadraba con la de los demás y la lista no
se confirmaba nunca, y sin confirmar tampoco podía quitarlo. En clave-reloj, G03 sin rangos)

### línea 3314 · `local before, late = nil, false`

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

### línea 3335 · `if late and before and MembersSigHash(nr.members) ~= before then`

(y si de verdad le faltaban, la corregida vale como recién hecha y se reparte, para que la arregle
también quien la tenía vieja. Solo quien lleva esa hermandad en la mía, con el freno normal de 10 s y
como mucho cada 30 s: antes la repartía con prisa cualquiera que la corrigiera, y en una conversación
continua con 4 hermandades cada reparto provocaba otros (615 listas en la cola del enlace))

### línea 3352 · `if dist == "WHISPER" then`

Segunda opinión: si pisa la que mandó su enlace hace poco una lista de otro de esa hermandad
(alguien que se creyó enlace un momento, con una copia vieja), se le pide la entera al enlace.
Solo quien la recibe por susurro, para no pedirla todos.

### línea 3382 · `if pt.fwdFlag ~= state and (self:IsRelay() or self:HandlesTag(tag) or (state == "c" and (s`

(los trozos se repartieron con otro estado del que ha quedado: se reparte otra vez)
(también un oficial o ayudante que acaba de confirmarla con su contacto: así le llega «c» a toda
mi hermandad y los rasos no tienen que pedirla cada uno)

### línea 3429 · `if f[2] == "2" then`

(RF~etiq~2: segunda opinión, o alguien de otra hermandad que acaba de entrar y me tiene como
contacto guardado. Contesta cualquiera del grupo del enlace o un oficial, aunque no le toque esa
hermandad, solo con la lista: sin tocar lo enviado ni mandar rangos o fichas aparte. Como mucho
una vez cada 30 s a cada uno y SECOND_MAX en total cada SECOND_WIN s: con una entrada masiva, el
resto la recibe de su propia hermandad)

### línea 3450 · `if st and GetTime() - st.fullT < gap then`

(dentro del freno no se descarta: se manda cuando acabe, UNA sola vez por hermandad, al último que
la pidió: la lista se reparte en su hermandad y les sirve a todos. Antes se perdía y quien no la
tenía entera esperaba a su siguiente petición, ~3 minutos. Una por persona atascaba la cola en
una entrada masiva: 50 listas enteras de golpe)

### línea 3509 · `local rd = recentDeltas[tag] or {}`

los cambios ("entra" / "sale") se aplican aunque mi copia no sea justo la que esperaban: aplicarlos
dos veces no hace daño. Antes se pedía la lista entera, y con mucha gente entrando y saliendo eso
atascaba las colas y retrasaba los cambios siguientes, que tampoco encajaban.
(se guardan un rato: si mientras tanto se está recibiendo una lista entera hecha antes, al
terminar de llegar se vuelven a aplicar, porque la entera los pisaría)

### línea 3565 · `if h ~= want and dist == "WHISPER" and (not fullAsked[tag] or GetTime() - fullAsked[tag] >`

(no cuadra: mi copia vino de otro, por ejemplo de quien fue enlace un momento. Se pide la
entera ya a quien manda los cambios, en vez de esperar dos presentaciones (~10 min). Solo
quien recibió el susurro, para no pedirla todos a la vez)

### línea 3582 · `local TAG_FIELD = { HI = 2, HR = 2, WH = 1, WL = 1, WD = 1, RB = 1, RC = 1, RN = 1, PB = 1`

Seguridad de los mensajes del addon
  * Por GUILD solo llegan mensajes de compañeros de hermandad (lo garantiza el juego).
  * Por susurro, solo se acepta a quien está en la lista de alguna de las hermandades.
    Excepción para arrancar: saludos y listas de miembros de una hermandad cuya lista
    todavía no tenemos (si no, nunca se podría conseguir la primera).
  * Los datos de una hermandad (listas, rangos, fichas, desconectados) solo se aceptan
    de alguien que está en la lista de ESA hermandad.

### línea 3605 · `local CHANNEL_OK = { RA = true, LP = true }`

Por el canal oculto solo van la presentación del enlace y la sonda del carril (el chat va con su
propio prefijo, en Channel.lua). Nada del addon va por grupo, banda o campo de batalla: antes se
aceptaba todo lo que no fuera susurro, y cualquiera de tu grupo podía mandar listas falsas.

### línea 3616 · `local CHECK_GAP, checkAt = 15, -999`

Lectura de la lista del canal a petición (cuando llega un saludo o una lista de alguien sin avalar):
solo quien ya la lee (el enlace, oficiales, maestro, moderadores), como mucho cada CHECK_GAP s. Los
rasos no la leen. Quien entra al canal (aviso de entrada) también cuenta como visto.

### línea 3637 · `function HU:Vouched(sender, tag)`

¿Puedo fiarme de que un desconocido es de la comunidad, aunque aún no tenga su lista?
Ha hablado por el canal oculto, o es un contacto conocido de esa hermandad (de otras sesiones,
o me lo ha presentado mi hermandad). Antes, para arrancar valía un susurro de cualquiera.

### línea 3697 · `if (cmd == "RB" or cmd == "RC") and not (L and L.set and next(L.set)) then`

Lista de conectados de otra hermandad sin su lista completa (fase de lanzamiento): antes
valía de cualquiera que hubiera hablado en el canal, que así se colaba de oficial de esa
hermandad y dejaba fuera a su enlace de verdad. Ahora se mira con qué se fía uno de quien la
manda (HU:SenderKind) y la lista se guarda con un estado (HU:DecideRoster, en HU.comm.RB).
Los comprobados, los de la lista y los antiguos se miran ANTES de la puerta cerrada: así nadie
deja fuera al de verdad. Con la lista confirmada y al día, los demás ya no entran.

### línea 3714 · `if cmd == "WH" or cmd == "RF" then return self:MemberOf(sender, tag) or self:Vouched(sende`

el aviso de "mi lista ha cambiado" vale de cualquiera de esa hermandad (puede ser
nuevo y no estar aún en mi lista); la lista en sí solo se acepta de quien está
(lo mismo para pedir la lista de conectados: como mucho manda una cada 2 minutos)
(el nuevo tiene que haber pasado por el canal o ser un contacto conocido: antes
valía de cualquier jugador del mundo)

### línea 3752 · `local key = sender:lower() .. cmd`

(una lista de varios trozos se guarda entera: antes la clave era remitente + orden y cada trozo
pisaba al anterior, así que al avalar al remitente solo se aplicaba el último y la lista se
quedaba a medias hasta pedirla otra vez, unos 3 minutos. Para lo demás, el último basta)

### línea 3764 · `local ADMIT_BURST, ADMIT_RATE, ADMIT_MAX = 60, 2, 3000`

Seguridad (idea n.º 8 de Olympus): admisión con tope por remitente. De cada uno de fuera de mi
hermandad, 60 mensajes de golpe y luego 2 por segundo; lo demás se tira antes de leerlo. Así nadie con
la contraseña puede ahogar a un enlace a base de mensajes. Se recuerda a 3.000 remitentes como mucho.
El enlace o contacto COMPROBADO de otra hermandad (contacto guardado, de su lista confirmada o su
enlace «dicho por él») tiene un cupo mayor: le pasa el chat de respaldo de toda su hermandad, el
relleno del historial y las listas de una entrada masiva, y no se le puede tirar nada.

### línea 3815 · `do -- (en un bloque: la parte principal del archivo no puede pasar de 200 variables locale`

(idea n.º 8, segunda parte) trozos a medio recibir con tope: 4 por remitente de fuera y 400 en total.
Si se llena, se tira lo del desconocido que más acapara, nunca lo de mi hermandad. Cada entrada
lleva by (remitente) y g (llegó por mi hermandad).

### línea 3920 · `local modList = members and self.chanModList or {}`

los moderadores se saludan entre ellos (los necesita la guardia)
(con 20 hermandades hay muchos moderadores: a cada uno, como mucho cada 15 minutos)
(solo se recorren los moderadores, no las miles de personas del canal)

### línea 4100 · `local TAKEOVER_GAP = 45`

(acabo de pasar a ser el enlace: saludo y presentación en el canal ya, sin esperar al saludo
siguiente, que tardaba 2-5 min; mientras, la otra hermandad seguía hablando con el enlace viejo.
Como mucho uno cada TAKEOVER_GAP s, por si dos con puntuación parecida se van turnando)

### línea 4122 · `if #qChat > 0 or (#queue > 0 and #bfast == 0) then`

(si el juego cuenta los dos prefijos juntos, lo que sale primero se lleva el sitio: antes
salían siempre los datos grandes, y unos inactivos largos retrasaban 15 s un silencio.
Ahora: chat y silencios, luego los cambios de las listas, luego lo normal, y lo grande al final)

### línea 4146 · `HU.After(2, function()`

primero a mi hermandad (al momento) y, si sigue faltando algo, a las otras hermandades
(a los 3 s, no a los 15: las listas tienen que estar en ≤30 s. Para que una entrada masiva no
mande cientos de NQ a la vez, cada uno espera un poco al azar, más cuanta más gente conectada:
el primero que pregunta marca la petición para todos (nqSeen) y la respuesta va por GUILD y les
sirve a todos, así que el resto ya no pregunta. Con 1.000 conectados salen unos 15 NQ)
(la gente conectada se mira a los 2 s, cuando el juego ya suele tener la lista; si aún no la
tiene, se supone que son muchos)

### línea 4165 · `for _, d in ipairs({ 2, 6 }) do HU.After(d + math.random() * 1.5, function() HU:AskSavedCo`

y a los contactos guardados de cada otra hermandad, sin esperar a ser enlace (oficiales, quien está
solo, o cualquiera a sus contactos comprobados: ver AskSavedContacts). A los 2, 6 y 12 s: la lista
de la hermandad llega a los 1-3 s y, si llega sin confirmar, se confirma con el contacto

### línea 4169 · `HU.After(2, function()`

(los rasos, solo si siguen sin confirmar, con una espera al azar que crece con los conectados,
como el NQ: en una entrada masiva no salen todos a la vez y casi todos la reciben antes por GUILD)
(día a día: a los ~2-4 s y otra vez a los ~7-9 s)

## Lists.lua

### línea 4 · `HU.whitelist = {}          -- [tag] = { list = {nombres}, set = {[clave]=true}, hash, coun`

Cada hermandad comparte la lista de TODOS sus miembros (también desconectados).
La guardia solo echa a quien no está en ninguna de estas listas.

WH~tag~huella~cantidad          "mi lista tiene esta huella"  (cada 3 min)
WQ~tag                          "mándame la lista completa de tag"
WL~tag~huella~parte~partes~a,b,c    trozo de la lista

La huella cambia en cuanto alguien entra o sale de la hermandad, así que las
demás piden la lista nueva enseguida. Las listas se guardan entre sesiones.

### línea 87 · `local members = r.members or {}`

(sin índice: se hace uno aparte la primera vez y se rehace si la lista cambia. Antes se
recorrían sus 1.000 miembros en cada línea del chat)
(el índice guarda la POSICIÓN y se comprueba al mirar: si la lista es otra, ha cambiado de
tamaño o en ese sitio ya no está ese nombre (RB, RC, correcciones, bajas), se rehace. Así un
expulsado deja de contar al momento, como antes. Y «weak» se mira en el miembro de ahora)

### línea 121 · `function HU:TrustedOfficer(author, tag)`

Seguridad: quien firma una acción de oficial (fijar, silenciar, notas públicas, canales...)
tiene que estar en una de las hermandades y ser maestro u oficial conocido.
Devuelve true, o false y "unknown" si es de las hermandades pero aún no sabemos su rango.

### línea 160 · `local deferred, deferT = {}, nil`

Acciones de oficial que esperan a conocer el rango de quien las firma
(se reintentan al llegar la lista de conectados de su hermandad; caducan a los 15 min
desde que llegaron: al volver a dejarlas en espera se conserva la hora de llegada)

### línea 185 · `function HU:IsGuildForwarder(sender)`

Seguridad: QUIÉN TRAE una acción de oficial (no solo quién dice firmarla).
Antes solo se miraba el nombre escrito dentro del mensaje, y cualquier miembro con el addon
podía firmar como un oficial. Ahora, si quien la manda no es el propio firmante:
  * por hermandad (GUILD): tiene que ser un oficial de verdad (rango de la lista del juego), el
    enlace (el que calcula cada uno, no el que dice serlo) o uno de sus ayudantes: son los que
    reparten en la hermandad lo que llega de las otras;
  * por susurro: el enlace, un ayudante o un oficial de la hermandad del firmante.

### línea 275 · `local function FirmRank(self, author)`

Seguridad: acciones que cambian la comunidad y se quedan (canal y contraseña, canales extra,
hermandades, colores, emoticonos, Buscar grupo). Con una lista de otra hermandad aún sin
confirmar (rangos provisionales), un intruso podía hacerlas en los minutos en que tenía rango y no
se deshacían al bajarle la lista. Ahora el firmante tiene que ser de mi hermandad o de una lista
confirmada; si no, la acción espera (Defer) por si se confirma.

### línea 302 · `function HU:BigCommunity()`

en comunidades grandes (más de 6 hermandades) las listas completas ya no se
reparten solas: los nombres de los inactivos llegan con sus datos (a petición y en segundo
plano) y la guardia pregunta a cada hermandad. Así se ahorra lo que más tráfico movía.
(desde la 5.3.0, siempre: lo que hacía falta para 20 hermandades también aligera las pequeñas.
Las listas completas no se reparten, la guardia se conforma con las de conectados y los
desconectados de otras hermandades llegan a petición)

### línea 312 · `HU.PHASE = "launch"`

Fase de lanzamiento: a las otras hermandades solo van el maestro, los oficiales, el enlace y sus
ayudantes; la guardia completa está apagada y cada hermandad vigila a quien escribe con su
etiqueta. "full" vuelve a repartir a todos los conectados (se puede probar con /gu fase).

### línea 316 · `HU.CHAT_ONLY = true`

Versión «solo chat» (5.4.11): siempre fase de lanzamiento. Por dentro solo viaja la lista pequeña
(maestro, oficiales, enlace y ayudantes), que usan la guardia y la confianza en el enlace; no se
puede pasar a la completa (ni con /gu fase ni con un db.phase guardado de antes)

## Presence.lua

### línea 39 · `local function SendRecent(self, p, tag, fast)`

Solo «ha entrado X» / «se ha ido X», enseguida y sin saber qué copia tiene esa hermandad (los cambios
valen sobre cualquier copia). Para quien acaba de heredar una hermandad (la lista entera va detrás) y
para el suplente de quien la lleva (BacksTag).

### línea 58 · `local function BacksTag(self, tag)`

¿Soy el suplente de quien lleva esta hermandad? (el del puesto anterior al mío; el primer ayudante lo es
del enlace). Si quien la lleva se ha caído sin avisar, el juego no lo dice hasta pasados unos 20 s y
mientras tanto nadie mandaba sus cambios. El suplente manda también los cambios pequeños, ya.

### línea 109 · `fullSent[tag] = GetTime()`

(me acaba de tocar esta hermandad, porque se ha ido quien la llevaba: no sé qué lista tienen.
La lista entera, sin colarse, y «se ha ido X» por delante: después, para que la lista entera no
lo quite de la cola, HU:DropQueued)

### línea 220 · `local PX_OUT_MAX, PX_IN_MAX, PX_WIN = 6, 10, 60  -- avisos que mando / que acepto de cada `

Red de seguridad: susurro a alguien de otra hermandad que sale conectado y el juego dice «no hay
nadie con ese nombre» -> fuera de conectados en mi copia ya, y se dice a mi hermandad (PX). Vuelve a
salir con el siguiente cambio que diga que está (o con la lista entera de su hermandad).
  PX~ETIQ~nombre

### línea 276 · `local leavingPeers, LEAVING_FOR = {}, 60`

Salir del juego de forma normal (/camp, /logout, /quit): quien se comparte lo dice a su hermandad
(PV, por GUILD) y deja de contar ya; si es el enlace o un ayudante, manda él mismo «-yo» a TODAS las
otras hermandades (2 copias cada una: con 4 hermandades, 6 mensajes, dentro del cupo seguido). Antes
se esperaba al aviso del juego y a que otro heredara: con el enlace fallaba siempre (5-7 s).
Si se cancela (PW), vuelve a salir conectado. No con PLAYER_LOGOUT: también salta con /reload.

### línea 361 · `function HU:AfterRosterScan()`

y cada vez que el juego refresca la lista de la hermandad (por si alguien no sale en los avisos)
(la lista se lee por trozos: esto va al terminar de leerla)
(quien ha dicho «me voy» sigue saliendo conectado en la lista del juego hasta que se va: no cuenta)

## ChanPresence.lua

### línea 1 · `local _, HU = ...`

Guild Union - presencia por el canal (idea de GreenWall Revived): si alguien de OTRA hermandad que está
en su grupo compartido (maestro, oficial, enlace o ayudante) sale del canal de la comunidad y en 10 s no
vuelve ni da señales, cuenta como un «se ha desconectado» con la hora de la salida

## Ranks.lua

### línea 5 · `HU.remoteRanks = {}   -- [tag] = { "Maestro", "Oficial", ... }  (posición 1 = rango 0)`

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

### línea 192 · `local PUNISH_NAMES = { castigado = true, castigada = true, castigados = true, punished = t`

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

### línea 5 · `local seen = {}`

Fuentes del registro:
- Mensajes del sistema de tu hermandad: ascensos, degradaciones, expulsiones,
entradas, salidas y cambio de maestro (los ve todo el mundo de la hermandad;
el enlace los reenvía a las demás hermandades).
- Avisos del canal: quién echa, veta o nombra moderador a quién.
- Acciones del addon: peticiones de rango enviadas y rechazadas.

AU~id~hora~etiqueta~autor~texto     entrada de registro compartida

### línea 72 · `local MULTI = { [2] = "DOOOUUUBLEEEE KILL", [3] = "TRIIIPLEEEE KILL", [4] = "QUAAADRAAA KI`

Rachas (solo en el registro de oficiales): cuando un oficial echa o veta del chat
  FIRST BLOOD   el primero del día en toda la comunidad
  DOUBLE / TRIPLE / QUADRA / PENTA KILL   varios seguidos (menos de 30 s entre uno y otro)
  LEGENDARY / GODLIKE / UNSTOPPABLE / BEYOND GODLIKE   10, 25, 50 y 100 vetos en total
Van en el registro como una entrada que empieza por "!!" y se pinta en rojo.

## Notes.lua

### línea 4 · `local function Clean(s) return (tostring(s or ""):gsub("[~\r\n]", " ")) end`

Cada personaje puede tener:
- Nota pública: la ve todo el mundo con el addon (todas las hermandades).
Solo la pueden escribir el maestro y los oficiales.
- Nota privada: solo la ve quien la escribe (no sale nunca de su ordenador).

NT~nombre~hora~autor~etiq~texto     nota pública (texto vacío = borrarla)
NS~desde                            al entrar se piden las notas públicas que falten

## Pinned.lua

### línea 4 · `local function Clean(s) return (tostring(s or ""):gsub("[~\r\n]", " ")) end`

PN~hora~autor~etiq~texto     mensaje fijado (texto vacío = quitarlo)
PQ                           alguien que acaba de entrar pide el mensaje fijado

## ChatTabs.lua

### línea 5 · `local TABS = HU.LT({`

Crea en el chat del juego las pestañas:
"Hermandad"     chat de hermandad + lo que llega de las otras hermandades
"Buscar grupo"  los mensajes de Buscar grupo de todas las hermandades
"Oficiales"     chat de oficiales unido (solo si puedes verlo)
Se crean una vez; si las cierras, se pueden volver a crear desde el panel o con /gu pestañas.

### Cada pestaña escribe en lo suyo (ReduceClean-35)

- Se aplica al abrir el chat (gancho a `ChatFrameUtil.OpenChat`, solo sin texto) y al hacer clic
  izquierdo en la pestaña (gancho a `FCF_Tab_OnClick`). Cambia el tipo y el «pegajoso» del cuadro de
  esa ventana: Hermandad → GUILD, Oficiales → OFFICER. No toca nada si el tipo actual no es el
  pegajoso (contestando un susurro, etc.).
- Buscar grupo no es un tipo de chat del juego. El cuadro queda en SAY con la marca `eb.guLFG`, y un
  gancho a `UpdateHeader` pinta encima la cabecera «Buscar grupo:» (naranja, mismos márgenes que
  Blizzard). Al enviar, el evento `ChatFrame.OnEditBoxPreSendText` (Blizzard lo deja para que los
  addons toquen el texto; llega tras procesar los comandos /) **vacía primero el cuadro** y luego
  manda el texto con `HU:SendLFG`. Así, si algo falla, no sale nada por /decir. Se apunta en el
  historial de flechas como `/buscargrupo texto`.
- La marca se quita si el tipo deja de ser SAY o si el jugador escribe un comando de chat
  (`/g`, `/s`, `/w`, `/1`…; gancho a `HandleChatType`).
- Antes (hasta la 34) se escribía «/buscargrupo » en el cuadro y se veía «Say: /buscargrupo».

## Test.lua

### línea 1 · `local _, HU = ...`

Guild Union Reduce - sin modo prueba (/gu prueba): servía para probar el addon sin hermandad, con
miembros inventados en el panel viejo. En ReduceClean se quita; estas funciones quedan para quien
todavía las llama.

## Guard.lua

### línea 5 · `HU.pendingSince = {} -- [clave] = desde cuándo está en el canal sin aparecer en ninguna li`

Regla: quien esté en cualquiera de las hermandades unidas NUNCA se echa.

- Cada moderador (o el propietario) del canal con el addon vigila por su cuenta.
- Un jugador es intruso solo si no aparece en la lista de su hermandad
ni en las listas completas de las demás hermandades.
- Si falta la lista actualizada de alguna hermandad, no se echa a nadie:
sin esa lista no se puede saber si es uno de los suyos.
- Además se espera un margen (por defecto 2 min) para dar tiempo a que
llegue la lista nueva cuando alguien acaba de entrar en una hermandad.

### línea 79 · `if kind == "main" and self.chanSeen and not sliced then`

(«visto en el canal» = quien está ahora en él: hace falta la contraseña para entrar. En Forever no
llega nada oculto del addon por el canal, así que esto es lo único que avala a quien entra por
primera vez. Da lo mismo que el chanSeen de siempre y nada más: ni enlace «dicho por él», ni
rangos, ni confirmar listas. Lo retenido de alguien que ya está en él se vuelve a mirar)

### línea 100 · `local ASYNC_SLICE, ASYNC_STEP, ASYNC_BUDGET = 150, 0.02, 1.5`

La misma lista, leída por trozos: para lo que no tiene prisa, como el saludo (con miles en el canal,
leerla de golpe daba un tirón de ~20 ms). fn(lista o nil)
(trozos de 150 y como mucho ~1,5 ms por fotograma; el «visto en el canal» y la búsqueda de mi línea
van dentro de cada trozo, y los avisos al acabar, en el fotograma siguiente: antes el último trozo
lo hacía todo junto y pasaba de 4 ms)

### línea 303 · `HU.guardKnown = {}    -- [clave] = { tag, t }  confirmados como miembros por su hermandad`

la guardia pregunta. Si falta la lista completa de alguna hermandad, en
vez de esperar a que llegue, pregunta a su contacto "¿son de los tuyos?" (él tiene la lista
entera de su hermandad, también los desconectados). Solo se echa a alguien cuando TODAS
esas hermandades han contestado que no es suyo.
  MQ~id~nombre,nombre      pregunta (a una hermandad)
  MA~id~nombre,nombre      respuesta: los que sí son de mi hermandad (puede ir vacía)

### línea 325 · `local MAX_BODY = 200`

solo van en la pregunta (y solo cuentan como preguntados) los nombres enteros que caben en
el mensaje; los demás, en la siguiente. Si no, a los que no cabían nadie los reclamaba y se
daban por intrusos aunque fueran de las hermandades.

### línea 388 · `local WIT_WAIT = 20`

Seguridad (idea n.º 10 de Olympus): un TESTIGO. A cada hermandad se le pregunta a su mejor contacto
y, si hay otro contacto de su lista buena, también a él. «Es mío» solo vale si lo dicen los dos;
«no es mío» de los dos = intruso; si no coinciden, no se decide nada (ni se protege ni se acusa).
Si el testigo no contesta en WIT_WAIT s, vale lo del primero, como antes.

### línea 437 · `if not self:IsTest() and not self:MemberOf(sender, tag) then`

(contesta por X solo quien está en la lista buena de X: antes valía el «mejor contacto», que
podía ser un intruso, y su «todos son míos» dejaba ciega a la guardia. Si no, como si no
contestara: la pregunta caduca y no se marca a nadie)

### línea 510 · `local function LightMembers(self)`

Revisión ligera: solo los que acaban de entrar y los sospechosos que siguen pendientes.
Sin recorrer el canal entero ni montar la tabla de conocidos (con miles en el canal, la
completa cada 15 s gastaba segundos de procesador y mucha basura).

### línea 659 · `local full = true`

¿tengo la lista COMPLETA (también desconectados) de todas las demás? Si no, no basta con no
aparecer en las listas de conectados (a quien acaba de entrar le faltan unos segundos): se
pregunta a todas y solo es intruso quien ninguna reclama. Así nunca se echa a alguien de las
hermandades porque su lista de conectados aún no estaba al día.

### línea 711 · `function HU:GuildVerified(k)`

Guardia por hermandad: alguien escribe en el canal con la etiqueta de MI hermandad y no está en
ella. Mi lista la da el juego entera (también desconectados), así que no hace falta preguntar a
nadie. Lo hace un oficial: lo silencia una hora para todas las hermandades y, si es moderador,
lo echa del canal.
¿Es de mi hermandad, según el JUEGO? Quien ha mandado algo por la vía GUILD (saludos, o la
respuesta PA de abajo) es miembro seguro: por esa vía solo pueden mandar los miembros y el
remitente lo pone el juego, no se puede falsificar ni depende de cómo se escriban los nombres

### línea 723 · `local CHANNEL_HAS_STALE = 60`

¿Sigue en el canal? (nil si no se puede saber)
(por el índice de nombres de la última lectura: antes recorría la lista entera en cada consulta, y la
llaman SenderKind, Vouched y las anclas con cada lista que llega. Si la lectura tiene más de 10 s y
menos de 60, vale mientras se relee por trozos, sin tirón)

### línea 750 · `local impAsk = {}`

Alguien escribe con MI etiqueta y no está en mi lista ni ha hablado por la hermandad: un oficial le
pregunta por la vía GUILD («PG~nombre»); su addon, si es de los nuestros, contesta «PA» por la
misma vía (solo vale si el juego dice que lo manda él). Sin respuesta en 20 s se repite; sin
respuesta a los 40 s está conectado con el addon y no es de la hermandad: silencio de 1 h para
todas las hermandades y, si soy moderador, fuera del canal. Mientras se comprueba, sus mensajes
quedan retenidos (Channel.lua): si resulta ser de los nuestros se enseñan; si no, se tiran.
Límites: una pregunta por nombre cada 5 min y 5 por minuto en total.

### línea 795 · `local lastOwnerCheck = -999`

Propietario del canal: siempre un maestro u oficial
  * Si soy el propietario y no soy maestro ni oficial (el juego me lo ha pasado al irse el
    anterior), se lo paso al mejor que haya en el canal: maestro, oficial que ya es moderador,
    oficial.
  * Si soy el propietario y soy maestro u oficial, hago moderadores a los maestros y oficiales
    del canal que aún no lo son (así pueden echar a un impostor, y cuando me vaya el juego tiene
    a quién pasárselo), y quito la moderación a quien la tenga sin ser maestro ni oficial.

### línea 1024 · `local r = self.remoteRoster[tag]`

(la lista que de verdad se reparte: los conectados de esa hermandad; en la fase de
lanzamiento son su maestro y sus oficiales. Antes se miraba la lista completa de miembros,
que ya no viaja, y salía siempre «sin lista»)

## GuardKeeper.lua

### línea 1 · `local _, HU = ...`

Guild Union - guardia por encargo (decisión de Jorge, 07/11)
  * Canal principal: nadie busca intrusos solo. Un maestro u oficial lo pide con
    /gu guardia revisar y decide él a quién echar.
  * Vetados del canal principal: los echa UN encargado (el propietario del canal o, si no tiene
    el addon, el moderador con el addon de HU.Hash más bajo), no todos los moderadores.
  * Chat de oficiales: guardia automática del encargado de ese canal (intrusos y vetados).

### línea 31 · `local SCAN_SLICE = 200`

Una pasada por la lista del juego: propietario, moderadores y vetados presentes (y, en el chat de
oficiales, todos: es pequeño). El principal se lee por trozos de SCAN_SLICE por fotograma, como la
guardia de antes: con miles de personas, de golpe daba un tirón. done(Ld o nil) al terminar.

## Social.lua

### línea 6 · `local function Clean(s) return (tostring(s or ""):gsub("[~:;,%.|\r\n]", " ")) end`

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

### línea 284 · `local ps = profilesSent[p.tag]`

(desde el último envío a esa hermandad, no desde el último completo: antes cada lista volvía a
llevar todas las fichas cambiadas en la última hora, y con muchas listas el enlace acumulaba
100 fichas en la cola; banco, continua-4)

### línea 298 · `local oqAsked = {}`

lo de los desconectados y las fichas, a petición
  OQ~miEtiq~suEtiq   pídeme nivel/clase/tiempo de tus desconectados (contesta con OD)
  FQ~suEtiq~nombre   pídeme la ficha de ese jugador (contesta con PB)

### línea 320 · `HU:OnStart(function()`

¿Faltan aún los inactivos de alguna hermandad? (para el aviso "cargando" de la lista)
En segundo plano y sin avisar: cada poco, el que se encarga en mi hermandad pide los
inactivos de una hermandad que falte (le llegan a toda mi hermandad y se guardan).
Así, cuando alguien elige Inactivos, casi siempre ya están.

### línea 325 · `HU.After(math.random() * 120, function() HU.NewTicker(120, function()`

(solo el enlace, una hermandad cada 2 minutos y solo si no tiene nada urgente que mandar)
(empieza con un retraso al azar: si no, cada 2 min coincidía en el mismo fotograma con los
demás relojes de 10, 15 y 60 s, que arrancan todos a la vez, y juntos pasaban de 8 ms)

### línea 376 · `local FUTURE_MAX = HU.STAMP_FUTURE`

Hora de los silencios y vetos (decide cuál es el más nuevo): la del servidor, igual para todos.
Antes era la del PC de quien los ponía, y con un reloj desajustado un «quitar» viejo ganaba a uno
nuevo. Lo que llegue más de 5 min por delante de la hora del servidor se descarta.

### línea 397 · `local pendingMutes, muteFlushPlanned = {}, false`

Varios silencios seguidos van juntos en un solo mensaje por destino (MZ): con uno por silencio
y destino, el quinto tardaba ~8 s en salir y mientras tanto se seguía viendo al silenciado.
  MZ~nombre,segs,autor,etiq,t,motivo;nombre,...

### línea 453 · `HU.comm.MU(self, sender, { p[1], p[2], p[3], p[4], p[5], p[6] }, dist, false)`

(cada uno como un MU; el reenvío a mi hermandad va una vez, abajo)
(con la vía real por la que llegó el paquete: la comprobación de quién lo trae la necesita;
con "BATCH" se rechazaban todos los silencios repartidos por el enlace. raw = false: el
reenvío a mi hermandad va una vez, abajo)

### línea 569 · `function HU:IsBanned(name)`

Vetar del chat: no puede volver a entrar aunque esté en la hermandad o tenga la contraseña
  BN~nombre~1|0~autor~etiq~t      1 = vetado, 0 = readmitido
Lo aplica en el canal cualquier moderador o propietario con el addon, y además nadie
muestra lo que escriba un vetado.

### línea 703 · `function HU.GuildCmd(cmd, name)`

Echar de la hermandad es una acción "protegida": un addon no puede hacerlo por su cuenta
(el juego lo bloquea y dice que el addon "se ha bloqueado"). Se hace con /gremove desde un
botón del juego: el addon solo prepara el comando y tú pulsas el botón.

### línea 892 · `local HQ_WAIT = 8      -- segundos que se esperan peticiones antes de mandar`

Si entran cientos a la vez (reinicio del servidor), contestar a cada uno por separado atascaba
la cola del que contestaba. Ahora se juntan las peticiones y se manda una sola vez a toda la
hermandad (quien ya lo tenía lo descarta), como mucho cada 2 minutos y en la cola lenta.

### línea 902 · `local function ResponderBusy(self)`

Contesta uno solo para toda la hermandad (el mismo para todos los que preguntan). Nunca el
enlace ni sus ayudantes, que ya van cargados con las listas, salvo que no haya nadie más.
Orden de quién contesta (lo usan IsResponder y HLRankOK: tiene que ser el mismo en los dos).
Primero los que no son enlace ni ayudantes; entre iguales, el hash más bajo del nombre.

### línea 932 · `local RESP_EVERY = 2`

Los dos mejores (si pregunta el primero, contesta el segundo). Con cientos de compañeros
recorrerlos todos en cada HQ daba fotogramas de hasta 4 ms (banco, continua-4: 106 de más de
1,85 ms en el enlace). Ahora se recorren por trozos en fotogramas seguidos, cada
RESP_EVERY s, y el HQ solo mira el último resultado. Solo la primera vez (aún sin resultado) se
calculan de una vez.

### línea 1006 · `local hqSeenT = -999`

Seguridad: ¿puede este compañero mandarme por la hermandad lo de «mientras no estabas»?
Antes valía cualquiera y podía inventarse líneas de otros. Ahora solo si alguien lo ha pedido
hace poco (HQ) y quien lo manda es de los que contestan: enlace, ayudante u oficial, o uno de
los primeros por nombre (el que contesta es el primero; se dejan 3 de margen porque cada uno
conoce a compañeros algo distintos).

### línea 1117 · `local function HasEntry(h, t, a, m)`

(antes solo se miraban las 400 últimas: con mucho chat, una línea de hace 10-20 min ya estaba más
atrás y el relleno de quien vuelve la metía otra vez. Ahora se mira hacia atrás todo lo que sea
de esos 3 minutos alrededor; el historial va ordenado por hora: se busca por mitades dónde
empiezan y se para al pasarlos)

### línea 1333 · `local sNow = StampNow()`

limpiar vetos levantados hace más de 30 días (antes se guardaban y se reenviaban para siempre)
(y los guardados con una hora del futuro, de un PC adelantado, se dejan en la de ahora: si no,
ganarían a cualquier cambio nuevo)

### línea 1356 · `local resync = {} -- [etiqueta] = { sig, peer, t }`

el enlace repasa con las otras hermandades los silencios y vetos de la suya cada 5 min. Con
muchas hermandades era un susurro por silencio y por hermandad (30 × 9 = 270 cada 5 min, casi
todo su cupo, y en la cola del chat): ahora todos los silencios en MZ agrupados, por la cola
de poca prisa, y a cada hermandad solo si algo ha cambiado, si su contacto es otro o cada 30 min

### línea 1401 · `function HU:TypeLines(macro, title)`

Comandos (de una o varias líneas: echar, ascender, degradar) que tienes que escribir tú en el
chat: van a la ventana de órdenes (Orders.lua). Antes el addon los escribía en la caja del chat
al abrirla tú, y eso en Forever contamina esos comandos y el juego los bloquea hasta /reload.

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

### línea 6 · `local MAX_BYTES = 8 * 1024 * 1024`

tope de lo guardado de mi comunidad si soy oficial (se borran los días más viejos y, si hoy solo
ya no cabe, lo más viejo de hoy). Con 5.000 jugadores el canal da 3-10 MB al día: no caben 30
días en ningún tope que quepa en MemGuard; se guardan los más recientes que quepan.

### línea 125 · `local function SafeRemote(s)`

Texto de otro, listo para guardar o enseñar. SafeText dobla cada | suelta; aplicado otra vez a un
texto ya limpio las volvía a doblar, y en cada salto la línea cambiaba. Aquí se juntan primero las
| seguidas: el resultado es el mismo aunque el texto llegue ya limpio.

### línea 168 · `local HASH_MOD = 2147483647`

Huellas del relleno de huecos (ver «Rellenar huecos solos», más abajo). Se leen las líneas
guardadas byte a byte, sin crear textos ni tablas por línea (antes cada vuelta dejaba unos 15 MB
de basura). Da lo mismo que antes: suma de «autor en minúsculas \1 MatchText(texto)».
Cada día guarda su suma por tramos de 10 minutos (sirve para huellas de día, hora y 10 min) y se
pone al día con cada línea nueva: un día solo se vuelve a recorrer si cambia de otra forma.

### línea 422 · `local lines = day.lines`

Las líneas van ordenadas por segundo: el sitio se busca por bisección y los repetidos se miran
solo en ±120 s alrededor. Antes se recorría el día de atrás adelante: una línea de hace horas
(el rellenado del historial las trae) recorría cien mil líneas y daba tirones de 140 ms.

### línea 473 · `local function NameMatcher(name)`

Buscar en mi PC (por trozos, para no dar tirones con 30 días)
  opts: { name = "Nombre", text = "texto", since = momento, kinds = {main=true...} }
  done(resultados): newest first; cada uno lleva day y i para ver el contexto

### línea 883 · `local SYNC_EVERY = 300`

Rellenar huecos solos (idea de GuildManagement, probada en Forever). Cada 5 minutos, un oficial
compara con otro (o con un compañero con el addon, que guarda 2 días) unas «huellas» del chat
(cuántos mensajes y una suma de sus textos) por día; donde no coinciden, por hora, y luego por
10 minutos; y pide solo ese trozo. Así quien entra recupera lo de mientras no estaba sin buscar.
Solo se tira: cada uno pide lo que le falta. El chat de oficiales nunca viaja.
  V~id~tam~desde~hasta       pide huellas (tam = segundos por trozo: 86400, 3600 o 600)
  v~id~tam~k:n:h,k:n:h…      huellas (k = trozo = inicio/tam); varios mensajes, y w~id al final
  S~id~k~tam                 pide las líneas de ese trozo
  D~id~t~k~tag~autor~msg     una línea; F~id~n al final

### línea 905 · `local function DayScanner(day, fn)`

Recorre las líneas de un día sin crear textos: fn(s, p, e) con la línea de s entre p y e (sin e).
Devuelve una función paso(presupuesto) → acabado, presupuesto que sobra. Del día abierto mira solo
las líneas que había al empezar (las nuevas se suman solas, en DigestOnAdd)

### línea 935 · `local function DigestsAsync(a, b, size, done)`

Huellas de [a, b): [k] = { n, h } (solo trozos con algo; sin el chat de oficiales).
Por trozos de DIGEST_SLICE líneas cada 30 ms (con 20.000 líneas en un día, de golpe eran 130 ms).
Cada día suma por tramos de 10 min una sola vez (digestCache); los tramos que quedan a medias de
[a, b) se miran línea a línea. Los trozos que comparten dos días se suman (antes el segundo día
pisaba al primero y la huella de un día solo contaba una hora). done(huellas)

### línea 1095 · `local wantLines = #s.queue > 0 and s.lines > 0`

(se acabaron los pasos con cosas en la cola: un hueco grande. Se sigue con el mismo
compañero en 30 s, en vez de esperar 5 min. Solo si hay líneas por traer: si lo que queda
son trozos ya traídos cuya huella no cuadra, no se insiste)

## Channels.lua

### línea 5 · `local MAX_EXTRA = 3`

CX~nombre~clave~borrado(0/1)~autor~etiq~t     crear o quitar un canal extra
Los canales extra son canales ocultos, igual que el de hermandad: todos los que tienen el addon
en cualquiera de las hermandades entran solos. Se escriben desde su pestaña en Chat.
Crear o quitar uno queda en el registro de oficiales.

### línea 60 · `function HU:MaySendSecrets(who)`

quien entra recibe la lista de canales (el enlace la manda junto al mensaje fijado)
¿Le puedo mandar contraseñas a quien las pide al entrar (PQ)? De mi hermandad, o un contacto de fiar
de la suya (HU:PeerVerified): antes, cualquiera con la contraseña del canal que pedía el fijado se
llevaba también las de los canales extra y la nueva del canal

### línea 142 · `local function CPMsg(n) return table.concat({ "CP", n.channel, n.pass or "", n.t or 0, n.b`

Canal y contraseña desde la nota de oficial
  CP~canal~clave~t~autor~etiq     lo reparte un oficial (el más nuevo manda)
  CQ                              alguien que no lo tiene lo pide al entrar
Un oficial que lee "GU:c:Canal:clave" en una nota de oficial lo pasa a su hermandad
(un solo aviso) y a las demás hermandades; cada addon lo guarda para la próxima vez.
Si el propietario del canal está conectado, cambia él solo la contraseña del canal.

### línea 208 · `local noteMissT, noteMissWarned`

Ningún oficial tiene ya la línea GU:c en su nota (EPGP, CEPGP, DKP o Guild Roster Manager
escriben en todas las notas de oficial). Se sigue con el canal guardado (db.netChan, que no se
borra por esto) y se avisa una vez por sesión, cuando falta en dos lecturas de la lista
separadas al menos un minuto. La nota no se escribe sola: pisaríamos la de ese addon.

### línea 251 · `local cqVotes = {} -- [canal~clave~t] = { [compañero] = true }`

Respuestas a mi CQ de compañeros que no son oficial, enlace ni ayudante: cualquiera podía mandarme
un canal falso firmado por un oficial. Ahora hacen falta dos iguales de compañeros distintos; si
en 20 s solo ha contestado uno (y nadie lo contradice), se usa como provisional: cualquier canal
que llegue de un oficial, el enlace o un ayudante lo pisa aunque sea más viejo.

### línea 284 · `local pendingCP, pendingN = {}, 0`

Canal de otra hermandad cuya lista aún no está confirmada: antes esperaba 15 min y se perdía (la
clave nueva no salía de su hermandad y la comunidad se partía). Ahora se guarda el más nuevo de cada
firmante (de esa hermandad, traído por quien puede traerlo) y se aplica al confirmarse su lista;
y se pide la lista a otro contacto para que se confirme antes.

### línea 351 · `local carrier = sender`

(de un compañero de mi hermandad por susurro: es la respuesta a mi CQ al entrar. Solo vale
si lo he pedido hace poco o si quien contesta es oficial, enlace o ayudante: si no, cualquier
compañero podía mandarme por susurro un canal falso firmado por un oficial)

## Community.lua

### línea 5 · `local pending = {}   -- invitaciones que he mandado: [id] = { contact, tag, t }`

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

### línea 340 · `local lines = {}`

(con muchas hermandades no caben todas en la Información (máx. 500 letras):
se escribe la propia y las que quepan; las demás se guardan como añadidas desde el panel,
que el addon reparte solo)

### línea 352 · `local others, byLine = {}, {}`

el título y mi hermandad van siempre en la Información (así el addon funciona aunque no
haya ningún oficial conectado); las demás hermandades, en las notas de oficial de los
oficiales (solo las ven ellos) y, si no hay notas libres, en la Información

### línea 500 · `local emPending, emBy = {}, nil`

Lista (ordenada) de los emoticonos activos: { {code=, path=}, ... }
Texto con una línea por emoticono:  codigo=Interface\Icons\Nombre
Sustituye la lista entera (lo que no esté, se borra). Devuelve ok, nº, errores
El pack de Twitch que viene dentro del addon (EmotePack.lua): se añade a los que ya hay
(los del pack ganan si se repite un código). Devuelve ok, nº, errores
¿Están ya puestos todos los del pack?
Aviso en el chat cuando el maestro añade emoticonos (se juntan los que llegan seguidos)

## NoteConfig.lua

### línea 5 · `local function NoteLine(note)`

Las líneas de la comunidad (GU:t:Título, GU:g:Hermandad:ETIQ, GU:r:ETIQ:N) se pueden poner en
las NOTAS DE OFICIAL de los oficiales (una por nota, máx. 31 letras), en vez de en la
Información de hermandad, que la ve cualquiera. Lo que no quepa va a la Información.

- Los oficiales (que ven las notas de oficial) las leen y las reparten a su hermandad.
- Los demás las reciben del addon y las guardan para la próxima vez.

NF~t~quien~parte~partes~líneas      configuración de las notas (líneas separadas por ";")
NK                                  pídeme la configuración (al entrar, si no la tengo)

### línea 65 · `local function InfoHasCommunity()`

La llama la lista de la hermandad (solo los oficiales ven las notas)
¿Ha quedado escrita la Información de hermandad? (en Retail el juego puede no dejar al addon:
entonces la unión solo duraría hasta el /reload). Si no, se guarda una copia que el addon
reparte a la hermandad, y al maestro se le enseñan las líneas para pegarlas él.
(devuelve nil si ahora no se puede leer, por una restricción del juego: entonces no se toca la copia)

## Echo.lua

### línea 6 · `local ECHO_EVERY = 1 / 2.5`

Lo enciende el maestro de cada hermandad con la línea GU:e:1 en la Información de hermandad
(/gu eco on). Apagado si no está. Solo escribe el enlace; para dos o tres hermandades.

En mi /g (lo escribe el enlace):   [ETIQ] Autor-Reino: mensaje
A las otras hermandades:           [MIETIQ:E] Autor-Reino: mensaje   (por el respaldo, CW/CG)

Nunca va al eco: chat de oficiales, canales extra, Buscar grupo ni avisos del sistema. Quien tiene
el addon no ve las líneas de eco (ya lo ve por el panel y su chat).
Ideas tomadas de GreenWall Revived 1.15.3 (MIT, Mark Rogaski), de los fallos que tuvieron en el juego.

### línea 94 · `local lastRelayT = -999`

El enlace. El que entra NUNCA (IsRelay espera 30 s y luego lo dice en su saludo). En el relevo,
el enlace de antes sigue escribiendo hasta que el nuevo dice que ya es el enlace (como mucho 3
min), con 2 s más de espera: si el nuevo ya lo escribió, lo ve y no lo repite.
Devuelve: ¿escribo?, ¿estoy de traspaso?

### línea 108 · `local DOUBT_SECS = 15`

¿Hay duda de quién es el enlace en mi hermandad? Solo entonces se espera ECHO_WAIT antes de
escribir; si no, al momento. Duda = acabo de entrar, el enlace ha cambiado hace menos de 15 s,
estoy de traspaso o de suplente, u otro compañero dice que es el enlace.

### línea 159 · `local SLOW_EVERY = 1 / 1.5`

Freno solo: si el juego se traga una línea mía (no vuelve por mi /g en LOST_SECS) o avisa de que
voy demasiado rápido, el eco baja a SLOW_EVERY y vuelve poco a poco a ECHO_EVERY tras CALM_SECS sin
problemas. La línea perdida se repite una vez.

### línea 366 · `local OUT_LIMIT = 195          -- (255 menos lo que añaden CW / CG delante)`

(desde un evento no se puede escribir en el canal: va por el respaldo, CW / CG)
Los susurros salen a ~1 por segundo: en una hora punta (3 líneas por segundo) la cola crecía y
las líneas caducaban sin llegar (banco: 32 de 90). Ahora sale como mucho un susurro por segundo
y lleva juntas las líneas que se han ido acumulando:  [ETIQ:E] A: uno \30 B: dos \30 ...

### línea 411 · `function HU:EchoUnwrap(tag, carrier, msg)`

Una línea [ETIQ:E] Autor: msg que llega de otra hermandad. Solo vale si la trae su enlace (o un
oficial suyo): si no, cualquiera de esa hermandad podía escribir con el nombre de otro.
Devuelve el autor de verdad y el mensaje, o nil

### línea 428 · `local via`

(lo trae alguien de esa hermandad que no sé si es su enlace: no se tira, por si su enlace es un
raso, pero se dice quién lo trae, para que una suplantación se vea)
(y si ya lo vi en la lista hace menos de 15 min, también: mientras la lista no está confirmada
la gente entra y sale de ella a ratos, y se perdían sus líneas; banco eco-2, desde los 10 min)

### línea 541 · `if g and HU.cfg and not HU.cfg.quick and HU.db then`

(¿se acaba de encender de verdad? Se mira con la configuración de verdad, no la del arranque
rápido, y se compara con lo que vi la última vez en esta hermandad: así no se repite con
un /reload ni con un relevo; solo si yo lo vi apagado y ahora está encendido)

### línea 573 · `HU.NewTicker(5, function()`

quién es el enlace de cada otra hermandad, apuntado cada 5 s (para EchoUnwrap)
(aunque mi hermandad no tenga el eco: lo que hay que reconocer es el eco que traen las otras.
Antes solo se apuntaba con el eco encendido, y en las demás se rechazaba todo; banco eco-2)

### línea 588 · `local origRA = HU.OnRelayAnnounce`

(y quien se presenta como enlace en el canal ([ETIQ:R], hace falta la contraseña) y sale en mi
lista de esa hermandad: en la fase de lanzamiento KnownRelay suele estar vacío, porque solo lo
llena el saludo directo, que llega cada 10 min y quizá a otro de mi hermandad)

## ErrorShare.lua

### línea 5 · `local ASK_WINDOW = 600   -- durante 10 min se aceptan respuestas a mi petición`

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

### línea 1 · `local _, HU = ...`

Guild Union - entradas masivas (tras un reinicio del servidor): la bienvenida a los que entran
(silencios, vetos, mensaje fijado, canales, colores, emoticonos...) la manda el enlace una sola vez
a toda la hermandad, en vez de a cada uno por susurro. Antes, con cientos entrando a la vez, eran
miles de susurros y cada uno que los recibía los volvía a repartir a toda su hermandad.

## Combat.lua

### línea 1 · `local _, HU = ...`

Guild Union - modo combate: en combate dentro de una banda o mazmorra el addon solo muestra y manda
el chat. Lo que no corre prisa (listas, historial, fichas, presencia en bloque, barridos de contactos)
se deja para después; lo que llega se guarda (como mucho la última lista por hermandad) y se procesa
al salir, por la entrada normal (con todas sus comprobaciones) y en trozos de ≤1 ms por fotograma.
Además, el enlace o un ayudante que entra en una instancia cede el papel hasta salir de ella.

### línea 20 · `local DEFER_IN = {`

lo que llega y se aplaza: "list" = listas de conectados, "data" = datos, "req" = peticiones
(los cambios pequeños de las listas, RC, NO se aplazan: con ellos llega al momento quién de los que se
comparten, GM, oficiales, enlace y ayudantes, entra o sale; tiene que verse en <1 s, como el chat)

### línea 175 · `local long = diag.holdT and diag.releaseT and diag.releaseT - diag.holdT > 60`

(tras un combate largo o si se tiró algo: se piden a mi hermandad todas las listas de una vez;
contesta quien se encarga de cada hermandad, por GUILD, y les sirve a todos los que salen. Tras un
pull corto no hace falta: lo guardado basta)

### línea 228 · `local TRICKLE_AGE, TRICKLE_EVERY, TRICKLE_MS = 60, 0.1, 1.0`

En combate largo: las listas enteras (RB) que llevan más de TRICKLE_AGE s guardadas se procesan igual,
una cada TRICKLE_EVERY s como mucho y solo si lo que cuestan (lo medido) cabe en TRICKLE_MS. Así ninguna
lista se queda vieja toda la mazmorra. Lo demás (PL, PH, historial, fichas) espera a salir: algunos
cuestan más de 2 ms cada uno y no se pueden partir

## UI.lua

### línea 1 · `local _, HU = ...`

Guild Union - panel: base (temas, piezas comunes, menús, fichas) y ventana principal
El resto del panel está en: UIMembers (Miembros), UIChat (chats), UIOfficers (Oficiales),
UIInfo (información, silenciar, recetas) y UIWindows (configuración y ventanas sueltas).

### línea 737 · `BINDING_HEADER_GUILDUNION = "GuildUnion"`

Atajo de teclado (Bindings.xml, Menú > Atajos de teclado > GuildUnion > «Abrir GuildUnion»).
La J abre GuildUnion (Jorge, 08/11): se pone como atajo temporal de la sesión (SetOverrideBinding), así
no se toca lo guardado del jugador y, sin el addon, la J vuelve a ser la de siempre. /gu tecla off la
quita; la ventana de hermandad del juego, con /gu hermandad

## UIWindows.lua

### línea 1 · `local _, HU = ...`

Guild Union Reduce - ventanas sueltas que siguen haciendo falta: copiar texto, novedades, crear
comunidad y enlaces web. (Las del panel viejo —hermandades, mapa, chat, emoticonos, información,
intrusos, invitaciones masivas, color, informar fallo— se quitaron en ReduceClean)

## UIStubs.lua

### línea 1 · `local _, HU = ...`

Guild Union Reduce - sin el panel grande: quitados UIMembers, UIChat, UIOfficers y UIInfo.
El resto del addon todavía llama a algunas de sus funciones (repintar el chat del panel, la lista,
el mensaje fijado...). Aquí quedan como «no hacer nada», para que no den error. Todo lo que se ve
está ahora en la ventana de hermandad de Blizzard (BlizzTab.lua) y en el chat normal del juego.

## BlizzTab.lua

### línea 1 · `local _, HU = ...`

Guild Union Reduce - todo dentro de la ventana de hermandad de Blizzard:
  * una pestaña más en su lateral («GuildUnion»), hecha con piezas de Blizzard
  * el chat de las otras hermandades, también en el chat de esa ventana
No se toca nada de lo suyo (ni sus listas ni sus botones): solo se pone encima. Tocar lo suyo es lo
que hace que Forever bloquee acciones de esa ventana (pasó con /ginvite).

### línea 47 · `local rebuild   -- { epochs = {...}, k = 0, ptr = 1 } mientras Blizzard repinta`

Cuando Blizzard rehace su chat (al abrir la ventana o cambiar de canal), borra lo nuestro. Para
que vuelva intercalado por hora: al empezar (su Clear) se mira la lista de mensajes que va a
pintar, y cada vez que pinta uno (su AddMessage) se meten detrás los nuestros que van antes del
siguiente suyo. Al acabar (DisplayChat), los que queden. No se rehace nada suyo: solo se añade.

### línea 399 · `local ACCENTS = { ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] =`

Buscador de personajes en la pestaña de miembros de Blizzard, junto a su filtro (como el de
GuildManagement): busca en mi hermandad y en los oficiales conectados de las otras. La lista de
Blizzard no se filtra (tocar sus datos bloquea sus botones).

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

### línea 676 · `local found = box.FindElementDataByPredicate and select(2, pcall(box.FindElementDataByPred`

(desconectado y la lista no enseña desconectados: no se marca la casilla desde el addon —eso
contaminaría la lista y bloquearía sus botones—; se hace brillar para que la marques tú, y
al marcarla se marca a la persona)

### Clic derecho en la lista de Blizzard (ReduceClean-39)

`Menu.ModifyMenu("MENU_UNIT_COMMUNITIES_GUILD_MEMBER", …)`: la vía de Blizzard para que los addons
añadan opciones a sus menús. Blizzard llama a lo nuestro aparte (`securecallfunction`), después de
montar lo suyo, así que sus opciones no se contaminan. Solo para oficiales (`HU:CanPin`) y no sobre
uno mismo: «Silenciar 10 min», «Quitar silencio», «Buscar lo que ha dicho» (lo mismo que el menú
de nuestra lista, `PlayerMenu`).


## Mention.lua

### línea 1 · `local _, HU = ...`

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
