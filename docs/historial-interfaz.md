# Historial de la interfaz (diario de copias)

> Lo que se apuntaba en ARCHITECTURE.md copia a copia mientras se hacía la interfaz (Miembros, Comercio,
> Calendario, Banco y Configuración). ARCHITECTURE.md describe ahora cómo funciona; esto queda para saber
> por qué se llegó ahí. No se pone al día.

## UnionRoster.lua

### Qué hay en el archivo

Las secciones de la lista de miembros de la ventana de hermandad del juego, con botones rojos del
juego arriba (copia 178 con pestañas; copia 180, botones; Jorge 23/11):
**Miembros** (la principal: al abrir la ventana se empieza siempre en ella), **Comercio**,
**Calendario** y **Banco** (estas tres, de momento, solo dicen «próximamente»).

En Miembros, una lista nuestra con todos los de la unión: los conectados de mi hermandad (de la
lista del juego) y los de las otras (de Miembros o del /who: `HU:UnionRosterEntries`) y, si la
casilla «Mostrar desconectados» del juego está marcada, también los desconectados de mi hermandad
(de las otras no se sabe). Columnas como las del juego más «Hermandad»: nivel, clase (icono), nombre,
zona, rango, hermandad (su etiqueta, p. ej. WLP: copia 184) y nota. La nota solo es la pública de mi hermandad (las de las otras no
llegan); se lee del juego con cada `GUILD_ROSTER_UPDATE`. Orden: rango de hermandad (0 = maestro, en todas) y
nivel de mayor a menor, todas las hermandades mezcladas (copia 179); los que llegan sin rango (del /who)
cuentan como el rango más bajo de mi hermandad. Un clic en un título ordena por esa
columna, otro al revés y el tercero vuelve al orden de siempre.

**La lista del juego no se toca.** La nuestra es hija de la ventana (no de su lista) y va encima,
tapando también sus títulos; la casilla de desconectados y el buscador quedan a la vista. La casilla
solo se lee (`GetChecked`), nunca se marca desde el addon. Si se metieran filas en la lista del
juego, su ventana quedaría «contaminada» y el juego bloquearía lo que solo puede hacer su interfaz:
ascender, degradar, expulsar o guardar notas (lo mismo que se vio con la ventana entera:
BlizzTab.lua). Para eso está la casilla **«GuildUnion»**, a la derecha del buscador (copia 179):
puesta (por defecto), nuestras pestañas; quitada, la lista del juego tal cual. Se recuerda
(`db.unionRosterOff`). Clic: su ficha (copia 190), una ventana nuestra con el aspecto de la del
juego (nombre, nivel y clase, hermandad, zona, rango, última conexión, profesiones y nota; botones
Susurrar e Invitar al grupo). No se abre la del juego: abierta por un addon, el juego bloquearía sus
botones (expulsar, rango, notas). Profesiones solo de mi hermandad (`C_Club.GetMemberInfo`); de las
otras, «—» hasta Comercio. Clic derecho: el menú de GuildUnion (`HU.PlayerMenu`).

Varios a la vez (copia 191): Ctrl suma o quita uno, Mayús elige del último al de ahora (en el orden
que se ve). Clic derecho: «Cambiar rango» (todos los rangos de mi hermandad) y «Echar de la
hermandad», solo para los de mi hermandad y si tengo permiso. El juego no deja que un addon lo haga
solo: se monta con `HU:RankMacro` / `HU.GuildCmd("gremove")` y va a la ventana de órdenes
(`HU:TypeLines`, Orders.lua), donde tú mandas cada /gpromote, /gdemote o /gremove. La lista tapa
también la barra de la lista del juego (22 px a la derecha). El buscador de personajes busca en
todas las hermandades y, con esta lista a la vista, lleva a la persona (`HU.UnionRosterPick`).

Copia 192: la ficha va a la derecha de los iconos de la ventana; profesiones con su icono
(`C_TradeSkillUI.GetTradeSkillTexture`) y nivel, y un botón «Ver recetas» por profesión
(`C_GuildInfo.QueryGuildMemberRecipes`, como el juego); nota de oficial (si puedes verla; las líneas
con «GU:» no se enseñan). En la vista de chat sale también la fila de botones, con «Chat» delante: con
el icono del chat se empieza en Chat (solo la fila, el chat del juego debajo); con el de miembros, en
Miembros (`Layout`).

Copia 193: «Chat» también en la vista de miembros. Es un botón seguro (`SecureActionButtonTemplate`,
`type=click` sobre `CommunitiesFrame.ChatTab`): lo pulsa el juego, no el addon, y la ventana no queda
«tocada». Es hijo de la casilla de desconectados (solo se ve en esa vista) para no tener que enseñarlo
ni esconderlo en combate; con la casilla «GuildUnion» quitada se esconde fuera de combate. Los botones
se estrechan si no caben, y en la vista de chat la fila sube 6 px para tapar el borde del chat.

Copia 194: en la vista de chat, Members…Bank son botones seguros (hijos de `CommunitiesFrame.Chat`) que
pulsan el icono de miembros del juego (`RosterTab`); su PreClick apunta la sección (`wantTab`) y, al
llegar a la vista de miembros, se abre esa. Así la barra del chat no queda por encima de nuestra lista.
Lo nuestro va a nivel 300 como mínimo, por encima de esa barra.

Copia 195: además, capa «HIGH» (la barra del chat está en otra capa y asomaba igual): la lista, la
casilla, la ficha y los botones seguros. Y el chat de la ventana de hermandad pinta a las otras
hermandades con punto o etiqueta según Ajustes (`db.chatMark`): `FormatLineParts(..., "blizz")`.

Copia 196: en la vista de chat, la lista de miembros de la derecha baja 14 px (`CHAT_SHIFT`) para quedar
debajo de los botones (solo su TOPLEFT; el juego la vuelve a colocar al cambiar de vista; no es un
marco protegido). La fila de botones se ata a la ventana, no a esa lista. La ventana pequeña (chat sin
lista) no cuenta como vista de chat.

Copia 197: el chat también baja 8 px (`CHAT_TEXT_SHIFT`; su borde y la flecha de su barra asomaban
entre los botones). El juego solo lo coloca al maximizar la ventana, así que Sync lo pone siempre en la
vista de chat (y lo devuelve a -44 con la casilla «GuildUnion» quitada). La fila se ata a la columna de
comunidades y a la ventana.

Copia 198 (arregla la 197, que subió la fila encima del desplegable): la fila va 59 bajo el borde de la
ventana; en la vista de chat, el chat y su lista de la derecha se atan a la parte de abajo de la fila
(sin cálculos). Al volver a la vista de miembros, antes de colocar la fila encima de la lista, la lista y
el chat vuelven a los sitios que les da el juego (si no, quedarían atados el uno al otro). Los botones
seguros Members…Bank van con la fila (atados a la columna de comunidades), no con el chat.

Copia 199: el juego vuelve a colocar la lista de la derecha cuando la actualiza; un `hooksecurefunc` sobre
su `SetPoint` la vuelve a poner debajo de la fila (con `placing` para no repetirse). En la vista de chat,
el contador del juego («68/786 Online», `MemberList.MemberCount`) se vuelve transparente y en su sitio
sale el de cada hermandad: la mía de `GetNumGuildMembers`, las otras de su lista RB (`remoteRoster[tag]`
.online/.total). El buscador de personajes va en el mismo sitio en las dos vistas: a la derecha del
desplegable «Guild» (en la vista de miembros está escondido pero sigue en su sitio).

Copia 200: la ficha copia el aspecto de la del juego (`CommunitiesGuildMemberDetailFrameTemplate`):
borde `DialogBorderDarkTemplate`, nombre dorado, «Etiqueta: valor» en una línea con los textos del
juego (ZONE_COLON…), notas en recuadros `TooltipBackdropTemplate`, botones abajo. En la vista de chat, un
clic en la lista de la derecha del juego abre la nuestra: `hooksecurefunc(f, "OpenGuildMemberDetailFrame")`
cierra la del juego y abre la nuestra (`EntryByName`). Al cambiar de vista, Sync va en el acto (antes
se veían un instante los botones en el sitio de la vista anterior).

Copia 201: la lista de la derecha se vuelve a poner en el acto cuando el juego la mueve (al conectarse
alguien se veía un instante en su sitio). En la ficha, una línea por profesión: icono con el nivel en
la esquina y «Ver recetas»; abajo, Echar (`REMOVE`, por la ventana de órdenes, solo mi hermandad y con
permiso) e Invitar al grupo, como el juego.

Copia 202: la fila de botones va exactamente en el mismo sitio en las dos vistas: en la de chat se ata
a la columna de comunidades en el punto donde cae en la de miembros (23, -34), con los dos bordes de
arriba atados a la columna (antes el derecho iba a la ventana y la fila bajaba 13 px). En la ficha, el
nivel de cada profesión va a la derecha de su icono (hasta 3 cifras; copia 203) y luego «Ver recetas».

Copia 204: el botón «Registro de invitaciones» pasa a «Registro» (InviteLog.lua), con dos pestañas:
Invitaciones (db.inviteLog) y Salidas (db.leaveLog: «quit» = se fue, «remove» = lo echó alguien),
ambas con columna de hermandad (la etiqueta, por el nombre en la configuración) y juntando lo guardado
de todas mis hermandades. La leyenda tiene ancho fijo y cabe dentro.

Copia 205: «Registro» más pequeño y, a su lado, «Solicitudes» (encendido con el número si hay alguna).
Un oficial pulsa Remove (ficha o clic derecho) sobre alguien de OTRA hermandad: `HU:AskGuildKick` manda
GK por susurro a quien tenga el addon en esa hermandad (BestPeer), que lo reparte por su hermandad
(como siempre). A sus oficiales, en vez de la ventana emergente de antes, se les guarda en
«Solicitudes» (db.kickRequests, 24 h). Aceptar: ventana de órdenes con el /gremove y, cuando se manda,
`AnswerKick` contesta (GD a su hermandad, GR a quien lo pidió). Rechazar: `AnswerKick(false)`. El
formato de GK no cambia; antes no había quién lo mandara.

Copia 206: cada solicitud lleva al final un tic (aceptar) y una X (rechazar); con Mayús o Ctrl se eligen
varias y los botones de abajo valen para todas (aceptar varias = una orden /gremove por persona; se
contesta a cada una según las vas mandando). «Modo prueba» añade tres de mentira (`test = true`) que
solo se quitan: no abren órdenes ni contestan a nadie.

Copia 207: Solicitudes con dos pestañas, Echar y Rango. Rango es una orden nueva, GP (Ranks.lua):
`HU:AskGuildRank` (clic derecho sobre alguien de otra hermandad, «Pedir a su hermandad cambio de
rango», con los rangos de esa hermandad) la manda como GK; a sus oficiales (con permiso de ascender o
degradar) se les guarda en la pestaña Rango; aceptar = órdenes /gpromote o /gdemote (`HU:RankMacro`) y
`AnswerRank` (RD/RR de siempre). En la vista de chat, en vez del contador del juego (tapado por la
fila), junto a los cascos: conectados/miembros de toda la unión; al pasar el ratón, los de cada hermandad.

Copia 208: Solicitudes en una sola lista; la columna Petición dice «Echar» en rojo o «Rango: X» en
amarillo; arriba, un filtro Todas / Echar / Rango.

Copia 209: solo se enseñan (y cuentan en el botón) las solicitudes que yo puedo hacer: un cambio de
rango, si `HU:RankMacro` lo deja (permiso, y ese rango por debajo del mío: subir a oficial o admin, solo
a quien puede darlo); echar, si `HU:CanKickMember`. Se guardan igual: si cambia mi rango, aparecen.

Copia 210: al echar a alguien por una solicitud, se apunta ya en Registro → Salidas (`HU:LogRequestedKick`)
con «pedido por X <ETIQ>»; cuando llega la misma del registro del juego, se reconoce como la misma. Los clics valen para el /who
(`HU:UnionWhoTick`). Solo sale en la vista de miembros (`IsVisible` de la casilla, como el buscador).

## Trade.lua

### Qué hay en el archivo

La sección Comercio (botón Trade de la lista de miembros, UnionRoster.lua la pone en `cover.trade`).
Diseño completo: Obsidian/Addons/GuildUnion - Comercio (diseño).md. Arriba, Solicitudes y Buscar (este,
de momento «próximamente») y el modo prueba. En Solicitudes: a la izquierda, el chat de comercio
(General y una pestaña por persona, hasta 4; solo se ve aquí); a la derecha, las solicitudes con
pestañas Público/Privado, filtro Todas/Mías/De otros, mías en azul y de otros en amarillo, columnas
quién · pide (el enlace del objeto, Mayús+clic al pedir) · materiales · propina (en blanco: a negociar)
· estado. Nueva / Lo hago / Hecha / Cancelar / Hablar (abre su chat privado). Tope: 5 abiertas.

**Fase 1 (copia 211): sin red.** Todo se queda en la sesión de cada uno; el modo prueba rellena
solicitudes y chats de mentira. Las fases 2-4 (red: solicitudes públicas, privadas, chat) van aparte
 y con banco.

Copia 212 (lo que pidió Jorge): Solicitudes y Buscar en el centro; el chat a la derecha; sin botones abajo:
a la derecha de Estado, un tic (de otro y abierta: «lo hago», y pasa a Privado entre los dos; mía y
hecha por alguien: «hecha») y una X (mía sin terminar: cancelarla). Arriba Público · Privado y «Nueva»;
debajo, Todas · Mías · De otros. Clic en una privada: abre el chat con la otra persona.

Copia 213: sin botones Solicitudes/Buscar: arriba Público · Privado, un buscador, Nueva y el modo prueba.
En Público, la lista a todo lo ancho, sin chat ni filtro; en Privado, filtro Todas/Mías/De otros y el
chat (uno por persona, sin General) a la derecha. Al escribir en el buscador, la lista pasa a ser la de
quién tiene esa profesión y a qué nivel (por ahora, mi hermandad, de `C_Club.GetMemberInfo`).

Copia 214: en Público, la última columna es un botón «Aceptar» (de otro y abierta), «Cancelar» (mía), o
el nombre de quien la aceptó; aceptada, sigue en Público con estado «Aceptada» y sale en el Privado de los
dos. En Privado: el chat es el de la persona del comercio que eliges (sin botones de pestaña: arriba, su
nombre), columnas más estrechas (sin materiales) para que la propina no pise el estado, tic/X en las
mías; el filtro Todas · Mías · De otros es texto (el elegido, dorado y subrayado). «Nueva solicitud»
abajo. El buscador pone «Buscar» y busca por nombre o profesión (recetas y objetos, con la red).

Copia 215: en Público solo «Aceptar» (las mías se cancelan desde Privado); una aceptada sigue 10 min en el
tablón (`PUB_KEEP`) y luego solo en Privado; filtro Todas · Sin aceptar. En Privado, «Aceptada» en verde y
sin tic/X; en las abiertas, tic (aceptar, si me la piden a mí) y X (cancelar la mía o rechazar). En la
búsqueda, la profesión con su icono, los desconectados en gris y, con clic derecho, «Pedir una receta»
(abre una solicitud privada para esa persona).

Copia 216: en Público vuelve «Cancelar» en las mías. Títulos con el aspecto de los del juego
(ColumnDisplayButton) y todo centrado; filas con rayas; la última columna ocupa lo que quede. En Privado,
una mía del tablón sin aceptar dice «Tablón» en vez de «?».

Copia 217 (arregla la 216): títulos de 24 de alto (los del juego miden eso; a 20 se salían por arriba y
pisaban el filtro), una 6.ª columna sin título en Público para el botón, así la fila de títulos llega al
final; «Nueva solicitud» y el chat 10 px más arriba (abajo los tapaba el borde de la ventana).

Copia 218: sin barras de filtro: un clic en un título ordena por esa columna (otro, al revés; el tercero,
lo más nuevo arriba), con una flecha en el título. «Receta / objeto»: el enlace con el color de su
calidad; un botón encima de la celda abre su ficha (`SetItemRef`, como en el chat) y al pasar el ratón
sale la ficha. En las mías, «Yo» en vez de mi nombre. El modo prueba usa enlaces de verdad.

Copia 219: aspecto plano, menos «clásico». Público · Privado son pestañas (texto; la elegida en dorado
con una raya debajo, sobre una raya fina de lado a lado). Botones planos (`Flat`: fondo oscuro, borde
fino del color del acento, brillo al pasar): Aceptar y «+ Nueva solicitud» en verde, Cancelar en rojo,
Modo prueba en dorado. Títulos de columna: texto dorado con una raya fina debajo (siguen ordenando).
El chat y la ventana de pedir, con borde de 1 px.

Copia 220: la ventana de pedir, nueva. Objeto con autorrelleno (`Suggest` + `ItemMatches`: el objeto de ese
nombre exacto si el juego lo conoce, los de mis bolsas y los de las solicitudes; Intro o clic elige; Mayús+clic
sigue valiendo). Materiales: Yo · Vendedor (se excluyen; `mats` true/false, nil = «—»). Propina en tres cajas
oro · plata · cobre con su icono encima; se guarda en cobre (`tip`) y se pinta con `Coins`. Pública: Sí · No;
con No sale «Personaje» con autorrelleno (`NameMatches`: mi hermandad, las listas de las otras y los que
tienen GuildUnion). Al pedir, la lista salta a Público o Privado según lo elegido. Cancelar en gris y los dos
botones centrados. Recetas que no tengo ni he visto no salen hasta la fase de red.

Copia 221: arriba, el modo prueba a la izquierda, Público · Privado en el centro (pestañas de 100 de ancho,
letra 14) y el buscador a la derecha. Las listas salen de `MakeList` (cada una con su título, cabecera,
scroll y filas): `ui.req` (solicitudes) y `ui.found` (quién lo hace). Al buscar, `Layout` parte la vista en
dos de 4 filas: arriba «Publicadas» (las públicas que encajan por quién la pide, objeto o quién la aceptó;
`Matches`) y abajo «Quién lo hace» (por profesión, ya no por nombre; recetas, objetos y otras hermandades
llegarán con la red). Sin buscar, todo como antes.

Copia 222: el buscador a la izquierda y el modo prueba a la derecha (las pestañas siguen en el centro).

Copia 223: delante de cada nombre, un circulito verde (conectado) o gris (desconectado o no se sabe);
`BuildOnline` lo saca en cada repintado de mi hermandad (`rosterList`), las listas de las otras (`remoteRoster`)
y los que tienen GuildUnion vistos hace menos de 5 min (`HU.remote`). Clic derecho en una fila (`RowMenu`):
Susurrar, Invitar al grupo, en la búsqueda «Pedir una receta», en Privado «Cerrar con esta persona»
(`CloseWith`: sus comercios salen de la lista, `r.closed`, y se cierra su chat) y Cancelar (cierra el menú).
En Privado la ficha del objeto ya no sale al pasar el ratón: solo al pinchar el enlace.

Copia 224: el circulito, a la derecha del nombre. Buscador de 150 (a 200 chocaba con «Público»). La última
columna de Público se titula «Acción». En Privado el chat solo sale al elegir un comercio aceptado (o hecho);
al elegir uno abierto, o sin ninguno, se esconde y la lista ocupa todo el ancho.

Copia 225 (deshace lo del chat de la 224): en Privado el chat se ve siempre, y al elegir cualquier comercio
(aceptado o no) pasa a ser el de esa persona; «Tablón» (sin nadie aún) lo deja en «Elige un comercio».

Copia 226: el botón del enlace (`itemBtn`) mide lo que el texto del enlace, centrado en su casilla; el resto de
la casilla es de la fila (clic: elegirla).

Copia 227: en la búsqueda los desconectados ya no van en gris: su color normal y el circulito gris. El título
del chat de Privado lleva también el circulito.

Copia 228: la caja del chat solo se puede usar con alguien elegido (si no, apagada con «Elige un comercio con
alguien para escribir»). A un desconectado se escribe igual y la línea lleva «(pendiente: lo leerá al entrar)»;
sin red de momento no se manda (fase 4: buzón). En la búsqueda los nombres van en amarillo (mío, azul). El modo
prueba añade dos privadas con desconectados (Lyra me pide; yo le pido a Janeth).

Copia 229: sin la marca «(pendiente…)» en las líneas a un desconectado (se escribe igual que a uno conectado).

Copia 230: en Privado ya no salen las públicas sin aceptar («Tablón»): solo en Público; al aceptarla alguien,
pasa a Privado con su nombre y su chat.

## CraftItems.lua

Los objetos que se fabrican en Forever (vanilla): `HU.CRAFT_ITEMS[profesión] = { objeto, nivel, ... }`, con el
número de profesión del juego (171 Alquimia, 164 Herrería, 185 Cocina, 333 Encantamiento, 202 Ingeniería, 129
Primeros auxilios, 165 Peletería, 186 Minería —fundir—, 197 Sastrería) y el nivel para aprender la receta.
Sacado una vez de Wowhead Classic (listas de hechizos por profesión, campo «creates»), 23/11: 1.373 objetos.
Solo números: el nombre y el enlace los da el juego en el idioma de cada uno.

Copia 231 (Trade.lua): al abrir Comercio por primera vez, `LoadCraftNames` pide al juego los nombres poco a poco
(30 cada medio segundo, en pausa en combate; los que tardan se reintentan dos vueltas más) y los guarda en
`craft`. Salen en las sugerencias de «Nueva solicitud» (hasta 60) y en «Quién lo hace»: si lo buscado encaja con
un fabricable, salen los de mi hermandad con esa profesión y nivel suficiente (`CraftNeeds`, comparando
`professionNID` con el número de profesión).

Copia 232: «Cantidad» al lado del objeto (`qty`, 1 por defecto; en la lista «5 x [objeto]»). El buscador de Comercio
tiene las mismas sugerencias que «Nueva solicitud» (`Suggest` + `ItemMatches`); lo buscado se compara en texto llano
(`Query`: si es un enlace, su nombre). Si no hay publicadas que encajen, «Publicadas» se esconde y «Quién lo hace»
ocupa todo (10 filas). Mientras se ve Comercio se esconde el «Buscar personaje» de arriba (BlizzTab.lua).

Copia 233: la cantidad en su columna «Cant.» (Público y Privado, ordenable), en vez de «5 x» delante del objeto;
las filas y la cabecera pasan a 7 casillas.

Copia 234: el «Buscar personaje» (BlizzTab.lua) no sale en Comercio, Calendario ni Banco: `ShowTab` (UnionRoster.lua)
pone `HU.charSearchOff` y llama a `HU.SyncCharSearch`; al esconderse la tapa vuelve. (En la 232 lo escondía Trade.lua
al abrirse, pero `Sync` lo volvía a enseñar.)

Copia 235 (UnionRoster.lua): en la vista de miembros, abajo a la izquierda de «Ajustes de hermandad», Solicitudes ·
Registro · Invitar miembro, como en la del chat. El «Invitar miembro» del juego solo sale en la vista del chat
(`COMMUNITIES_FRAME_DISPLAY_MODES.CHAT`); el nuestro es un botón seguro `type=click` que lo pulsa. Cuelgan de la
casilla de desconectados (solo visible en la vista de miembros), así no hay que enseñarlos ni esconderlos en combate.

## UnionCalendar.lua

La sección Calendar de la lista de miembros (UnionRoster.lua la pone en `cover.calendar`). Copia 236, fase 1: solo
la ventana, sin red; lo creado se queda en la sesión y el «Modo prueba» pone cinco eventos. Arriba, pestañas
Eventos · Calendario (las planas de Trade.lua: `HU.FlatButton`, `HU.FlatTab`). A la derecha, siempre, el panel
del evento elegido: título, tipo, día y hora, quién lo organiza (con su hermandad), descripción, quién va / quizá /
no, y los botones Voy · Quizá · No (otro clic en el mismo, se borra). En Calendario, sin evento elegido, el panel
enseña los eventos del día elegido (clic: ese evento; «< Día» vuelve).
- **Eventos**: los próximos (desde hace 3 h) por fecha: día, evento, tipo (con color), organiza, cuántos van; a la
  izquierda el tic si voy.
- **Calendario**: el mes en cuadrícula, lunes primero, flechas < > para cambiar de mes; en cada día hasta dos
  eventos (con el color del tipo) y «+N»; hoy con borde dorado, el día elegido en azul; doble clic, nuevo evento.
- **Nuevo evento** (abajo): solo oficiales (`HU:CanPin`), o con el modo prueba puesto. Título, tipo (Banda,
  Mazmorra, JcJ, Social, Otro), día dd/mm (si ya pasó, el año que viene), hora hh:mm y descripción. Quien lo crea
  queda apuntado como «Voy».
Decisiones de Jorge (23/11): crean los oficiales; solo eventos de la unión (no los del calendario del juego).

Copia 237: Eventos sin tabla: una tira grande por evento (`PaintCards`, 4 a la vista): raya del color del tipo,
fecha (día de la semana, número grande, mes), título grande, tipo · hora · «por» quién lo pone (con su hermandad),
cuántos van, y botones «Apuntarme» (Apuntado / Quizá si ya lo estás; otro clic, te quita) y «Más información».
La ficha del evento ya no está a la derecha: es una ventana encima (`PaintDetail`) con la información, quién va y
Voy · Quizá · No, y X para cerrar. En Calendario, a la derecha, los eventos del día como tiras pequeñas (clic: la
ficha).

Copia 238: la ficha (`BuildDetail`, 560x372) se mueve arrastrándola; arriba una banda con el color del tipo que se
apaga hacia la derecha, título grande y «tipo · día, hora · por quién». Dos pestañas:
- **Resumen**: descripción y «Apuntados» en tres columnas (Voy · Quizá · No, nombres con el color de su clase si se
  sabe: `ClassMap` mira mi hermandad, las listas de las otras y el modo prueba), y Voy · Quizá · No grandes abajo.
- **Raids** (`e.raids = { { name, leader, members = { [nombre] = true } } }`): a la izquierda «Sin raid» (los que
  van y no están en ninguna) y las raids (hasta 5) con su líder; «+ Añadir raid». A la derecha la elegida: líder
  (corona), «Invitar a todos (N)» y «Quitar raid», y sus miembros en 4 columnas x 10 (una raid de 40). Clic en un
  nombre: hacer líder, pasar a otra raid, sacar de la raid, susurrar. Organizan (añadir, mover, líder, quitar) quien
  puso el evento, los oficiales o el modo prueba (`CanManage`); «Invitar a todos» lo ve el líder de esa raid y quien
  organiza.
- `InviteRaid`: si estoy en grupo y no en raid, la convierte en raid (`C_PartyInfo.ConvertToRaid`); invita con
  `C_PartyInfo.InviteUnit` a los que no están ya. Sin grupo solo caben 4: se invita a 4 y se avisa de que, al
  aceptar, otro clic invita al resto.

Copia 239: Raids con el formato de banda del juego. Cada raid es `{ name, leader, groups = { {nombres} x8 } }`
(8 grupos de 5). Arriba una pestaña por raid (nombre, cuántos y su líder con corona) y «+ Añadir raid» (hasta 5);
debajo «Líder de la raid» bien a la vista, «Invitar a todos (N)» y «Quitar raid». Izquierda: el banquillo («Sin
raid», los que van y no están en ninguna). Derecha: los 8 grupos (4 x 2), nombres con el color de su clase y la
corona del líder. Quien organiza arrastra un nombre (un rótulo sigue al ratón) a un hueco (si está ocupado, se
cambian), a un grupo (si cabe) o al banquillo (sale de la raid): `Place`, `TakeOut`, `AddToRaid`. Una persona
solo está en una raid del evento. Clic derecho en un nombre: hacer líder, pasar a otra raid, sacar, susurrar.
La ficha mide 724x440 y se mueve. Nombres en letra normal (no pequeña) en Resumen y Raids.

Copia 240 (UnionCalendar.lua reescrito): con el aspecto de las ventanas del juego (Forever). Botones rojos
(`UIPanelButtonTemplate`; el elegido, encendido con `LockHighlight`) para Eventos · Calendario, modo prueba,
nuevo evento, Apuntarme / Más información, Voy · Quizá · No, raids, Invitar a todos. Tiras de Eventos con fondo de
piedra (`UI-Background-Rock`) y borde dorado, icono del tipo con marco, número del día grande y dorado. Calendario
con las casillas del calendario del juego (`Interface\Calendar\CalendarBackground`, `Highlights`, `CurrentDay`) y
las flechas del libro de hechizos; el panel del día es un `InsetFrameTemplate`. La ficha del evento y «Nuevo
evento» son ventanas del juego (`ButtonFrameTemplate`: título, X, icono del tipo como retrato) que se mueven; la
ficha lleva las pestañas abajo (`PanelTabButtonTemplate`: Resumen · Raids) y los botones en su barra de abajo.
- Raids con los grupos de banda del juego (`UI-RaidFrame-GroupOutline`, huecos `UI-RaidFrame-GroupButton`, «Vacío»).
- «+ Añadir raid» pregunta primero quién la lleva (menú con los que van; los que ya están en otra raid, al final y
  con su raid). `SetLeader`: el líder va siempre el primero del grupo 1 (si está lleno, el último baja a otro
  grupo); el hueco 1 del grupo 1 no se puede quitar al líder. Barra «Líder de la raid» encima de los grupos (se
  puede soltar un nombre en ella para hacerlo líder).
- Invitar a todos invita a todos los de esa raid y apunta cada uno en `invites`: reloj (invitado), tic (ya está en
  el grupo: `GROUP_ROSTER_UPDATE`), X (rechaza, ya tiene grupo, no se le encuentra u ocupado: los textos del juego
  `ERR_DECLINE_GROUP_S` y compañía en `CHAT_MSG_SYSTEM`; o no entra en 90 s). La marca sale a la derecha del nombre.

Copia 241: sin Resumen (Jorge): la ficha del evento es solo las raids, sin pestañas; Voy · Quizá · No abajo a la
derecha, en la barra de botones (Invitar a todos y Quitar raid, a la izquierda).

Copia 242: estilo de la Guía de mazmorras: la página de la Guía (`UI-EJ-JournalBG`) de fondo en Eventos, Calendario
y la ficha; las tiras de Eventos son la placa de los jefes (`UI-EncounterJournalTextures`, normal/pulsada/brillo) con
el título en el color de los jefes; la cabecera de página detrás del mes y de «Líder de la raid». Solo se acepta
(Jorge): sin Quizá ni No; «Apuntarme» / «Apuntado» en la tira y en la ficha.

Copia 243: sin la página de la Guía de fondo (no le gusta a Jorge); se quedan las placas de jefe y las cabeceras.

Copia 244: el icono del tipo, en el hueco del retrato de la placa (capa OVERLAY: en ARTWORK lo tapaba la placa y el
hueco salía negro); sin el marco de acción extra.

Copia 245 (UnionCalendar.lua rehecho con el estilo del addon Dungeon Journal de Forever; estudiado en su código, sin
copiar su arte): colores de su tema «Hall of Thanes» (tabla `T`: frame, content, border, header, panel, row, rowSel,
title, text, muted…). Ayudantes: `Panel` (fondo liso WHITE8X8 + borde de tooltip, colores de `T`), `Parchment`
(`QuestBG` encima al 13-18 %), `Line` (raya dorada de 1 px), `DJButton` (botón oscuro con texto dorado, `:Pick(on)`
lo deja elegido, `:Label`), `RoundIcon` (icono con máscara redonda y aro del minimapa) y `DJWindow` (ventana: piedra
con marco de diálogo, franja de título con rayas doradas, X, panel de dentro «content» con pergamino; se mueve).
- La sección es un panel «content» con pergamino; arriba Eventos · Calendario y Modo prueba con `DJButton`.
- Eventos: tarjetas de 2 en 2 (112 de alto), como las de mazmorras: piedra cálida, tinte del color del tipo, sombra
  arriba y raya de brillo; icono redondo, título dorado con sombra, tipo · hora, «N van» arriba a la derecha, día
  grande + día de la semana y mes, «por» quién, y Apuntarme / Más información. Borde dorado al pasar el ratón.
- Calendario: casillas de panel (fila; el día elegido en «rowSel», hoy con borde dorado), cabecera del mes en panel,
  flechas del libro; a la derecha panel lateral con los eventos del día.
- Ficha del evento (`DJWindow` 740x480): icono redondo y título arriba, línea de tipo · día · por · cuántos van;
  raids con `DJButton`, barra del líder en panel de cabecera, banquillo en panel lateral, 8 grupos en paneles de
  fila; abajo Invitar a todos · Quitar raid y, a la derecha, Apuntarme.

## DJStyle.lua

Copia 246: el estilo del Dungeon Journal, compartido por Calendario y Comercio (`HU.DJ`): colores `T`, `Panel`,
`Parchment`, `Line`, `RoundIcon`, `Window` y `Button`. Los botones son los rojos del juego (`UIPanelButtonTemplate`)
y, elegidos (`:Pick(true)`: pestañas, el día, «Apuntado», la raid que se ve), se quedan negros con borde dorado (se
esconden sus tres piezas rojas y se pone un fondo de panel). Comercio usa estos botones para todo (Público · Privado,
Aceptar, Cancelar, Modo prueba, Nueva solicitud), el panel «content» con pergamino detrás de la sección, el chat en
panel lateral y la ventana de pedir en panel.

Copia 246, Calendario:
- Roles (tanque, sanador, daño; icono redondo del buscador de grupo, `UI-LFG-ICON-PORTRAITROLES`). «Apuntarme»
  pregunta el rol (`e.roles[nombre]`); ya apuntado, otro clic te quita (y sales de la raid). El icono del rol va
  delante de cada nombre; cuántos de cada rol en la tarjeta, en la ficha y en la barra del líder de cada raid.
- Al apuntarse se entra solo en una raid con sitio (`AutoPlace` → `BestRaid`: la que menos tiene de su rol y luego
  la más vacía); si no hay ninguna, al banquillo «Sin raid». En el banquillo, «Colocar en raids (N)» (`PlaceBench`)
  los reparte igual, primero tanques, luego sanadores y luego daño.
- Soltar un nombre sobre la pestaña de otra raid lo pasa a esa raid.

Copia 247: fuera el marrón (a Jorge no le gusta). `DJ.T` pasa a pizarra fría: fondos casi negros con un punto azul
(como el fondo de los bocadillos del juego), bordes gris piedra (como la ventana de hermandad), elegido en azul
pizarra, y el dorado del juego (1, 0.82, 0) para títulos, rayas y borde de lo elegido. El pergamino queda solo como
textura, desaturado, frío y al 35 % de lo que era. Textos crema → gris claro.

Copia 248: estilo de WhisperMessenger (estudiado en su código; sin copiar su arte). `DJStyle.lua` rehecho con la
misma API: superficies de su tema oscuro (casi negro, gris muy oscuro), borde de 1 px blanco al 10 %, un solo acento
rojo (0.85, 0.20, 0.20) para lo elegido (hoy, borde al pasar, botón elegido), textos blanco / gris claro.
`Panel`: fondo liso + borde de 1 px. `Parchment` ya no es pergamino: brillo leve arriba (degradado blanco 0→4 %).
`Button`: rojo plano (0.45, 0.12, 0.12), más claro al pasar; elegido, negro con borde rojo; desactivado, gris.
`Window`: fondo casi negro, borde 1 px, sombra de tres bandas, barra de título de 30 con brillo, «x» que se pone roja
al pasar, panel «content». `RoundIcon`: solo la máscara redonda. Tarjetas de Eventos: planas, con tinte y barra de
2 px del color del tipo a la izquierda.

Copia 249: se queda el fondo de WhisperMessenger, pero los botones vuelven a ser los rojos del juego
(`UIPanelButtonTemplate`). `DJ.PickRed(botón, on)`: elegido, se esconden sus piezas rojas y queda negro con borde
dorado de 1 px y letra blanca. También lo usan los botones de arriba de la lista de miembros (Chat, Miembros,
Comercio, Calendario, Banco) en `ShowTab` (UnionRoster.lua), en vez de `LockHighlight`.

Copia 250 (Jorge: «solo mantén el fondo, el resto lo de antes»): vuelve todo lo de la 247 (paneles con borde de
tooltip gris, ventana con marco de diálogo y franja de título con rayas doradas, tarjetas con sombra arriba y raya
dorada, iconos redondos con aro, títulos y rayas doradas, elegido azul pizarra) y los botones rojos con
`DJ.PickRed` de la 249; solo cambian los fondos, que son los de WhisperMessenger (casi negro y grises muy oscuros,
lisos: sin pergamino ni piedra).

Copia 251:
- `DJ.PickRed`: el elegido mantiene la forma del botón rojo; sus tres piezas se desaturan y oscurecen (negro) y la
  letra pasa a blanca.
- Raids: al arrastrar un nombre desaparece de su hueco (si se suelta fuera, vuelve); el banquillo enseña el nivel
  (`LevelMap`: mi hermandad, listas de las otras, modo prueba); «Invitar a todos» y «Quitar raid» debajo de los
  grupos; el clic derecho tiene «Mover a >» con las raids donde no está.
- Nuevo evento: «+ Nuevo evento» arriba a la izquierda (abajo pisaba las tarjetas); solo Banda, JcJ y Social;
  «Nivel mínimo» (`e.minLevel`: sale en la tarjeta y en la ficha como «Nv. N+», y no deja apuntarse con menos);
  descripción en una caja de varias líneas.
- Comercio, Privado: Ctrl suma/quita filas y Mayús elige un tramo (`picks`); «Eliminar (N)» al lado de «Nueva
  solicitud» y en el clic derecho (`RemoveReq`: la mía sin aceptar se cancela; las demás solo salen de mi lista).
  «Hecha» arriba a la derecha del chat y «Marcar como hecha» en el clic derecho (`MarkDone`).

Copia 252: «+ Añadir raid» abre una ventanita (`d.picker`) con buscador y lista con barra en vez del menú (con mucha
gente no cabía): se filtra por nombre. Al apuntarse solo salen los roles que puede hacer la clase (`CAN_ROLE`, de
vanilla: tanque guerrero, druida, paladín; sanador sacerdote, druida, paladín, chamán; daño, todas). En el mes, cada
día enseña un puntito del color de cada evento (hasta 4) y «+N evento(s)».

Copia 253: fuera «Cerrar con esta persona» del clic derecho de Privado (y su función `CloseWith`); para quitar
comercios de la lista está «Eliminar».

Copia 254, permisos en la ficha del evento: organiza (`CanManage`: añadir raid, mover gente, colocar en raids,
hacer líder) quien creó el evento o el líder de alguna de sus raids (ya no los oficiales ni el modo prueba).
«Invitar a todos», solo el líder de esa raid. «Quitar raid», quien creó el evento o el líder de esa raid.

Copia 255: apuntado, el botón dice «Apuntado» en verde con el tic; al pulsarlo otra vez, `ui.confirm` pregunta
«¿Seguro que quieres salir del evento?» (Sí / No).

Copia 256: el mes solo dibuja las semanas que tiene (casillas más altas); «+N evento(s)» en una línea debajo
del número (antes no cabía y salían puntos suspensivos) y un cuadradito del color del primer evento arriba a la derecha.

Copia 257: los botones elegidos de Registro / Solicitudes (InviteLog.lua) y de Miembros / Oficiales (BlizzTab.lua)
también con `DJ.PickRed` (oscuros), como el resto. Calendario: fuera el doble clic en un día y su aviso; en el panel
del día elegido, abajo, «+ Nuevo evento» para ese día.

Copia 258: en las tarjetas, el tic de «N van» solo si yo voy. En la ficha, «Convertir en banda» (solo el líder de
esa raid; activo si está en grupo, no en banda, y lo lleva él: `C_PartyInfo.ConvertToRaid`) junto a Invitar a todos /
Quitar raid; y, al líder sin banda, un aviso en rojo abajo en vez de la ayuda de arrastrar. Se repinta con
`GROUP_ROSTER_UPDATE`.

Copia 259: «Imagen» al crear un evento: 16 iconos de vanilla (`EVENT_ICONS`) para elegir (`e.icon`; sin elegir, la
del tipo: `EventIcon`), en la tarjeta, la ficha y el panel del día. «+ Nuevo evento» debajo de Eventos · Calendario,
centrado y destacado (botón rojo teñido de verde, letra blanca); el panel de la sección baja 28 y las tarjetas miden
100.

Copia 260: la imagen del evento, una vista previa grande + «Elegir imagen», que abre la rejilla de 16 (4 x 4); siempre
hay una: por defecto la del tipo (cambia con el tipo mientras no se elija otra). Tarjetas centradas: el mismo margen a
los dos lados (con barra para bajar, 28 a cada lado; sin ella, 12). El modo prueba ya no duplica sus eventos.

Copia 261: 32 imágenes (rejilla 8 x 4). El día y la hora ya no se escriben: «Día» abre un calendario pequeño (< mes >,
días; hoy en dorado, el elegido oscuro) y «Hora» una rejilla de horas 00-23 y minutos 00/15/30/45 (la hora deja la
ventanita abierta, el minuto la cierra). Sin avisos de formato.

Copia 262: la hora, dos desplegables del juego (hora 00-23 · minutos de 5 en 5, con barra; `MenuUtil` + `CreateRadio`),
en vez de la rejilla. Las ventanitas (imagen, día) no se abren a la vez (`d.ClosePopups`). Tarjetas: la barra para
bajar no se ve (descentraba): margen 12 a cada lado, rueda del ratón de fila en fila y abajo «N eventos más abajo».

Copia 263: vuelve la barra: tarjetas y barra juntas en un panel centrado (`ui.list`, margen 12 a cada lado); dentro,
la zona de las tarjetas (`ui.cardArea`) deja a la derecha el hueco de la barra solo cuando hace falta (más de dos filas).
La hora: un botón «20:00» que abre una lista de horas de 15 en 15 con barra (`tp`), la elegida marcada y a la vista.

Copia 264: 64 imágenes; la rejilla enseña 8 x 4 y tiene barra para el resto. Pinchar fuera de una ventanita (imagen,
día, hora) la cierra: una capa invisible del tamaño de la pantalla, por debajo de las ventanitas, que se enseña
mientras alguna está abierta (`d.WatchPopup`).

Copia 265 (UnionRoster.lua): los botones seguros «Chat» (vista de miembros) y Miembros…Banco (vista de chat) se
esconden al cambiar de vista antes de soltar el ratón y se quedaban «pulsados» (letra movida, sin centrar). Al
volver a verse (`OnShow`, fuera de combate) se dejan sueltos: `SetButtonState("NORMAL")` y su `OnMouseUp`.

## UnionBank.lua

La sección Bank de la lista de miembros (UnionRoster.lua la pone en `cover.bank`). Copia 266, fase 1: solo la
ventana, sin red; el «Modo prueba» rellena tres bancos y dos solicitudes. Lo ven los oficiales; todos, si el maestro lo
abre (`HU.db.unionCfg.bankView = "all"`). Pestañas: **Bancos de hermandad** (rejilla de huecos como un banco, con barra;
buscador por nombre de objeto; filtro por hermandad; la etiqueta de la hermandad en cada hueco si se ven todas; clic:
pedirlo, si `bankRequest` lo deja), **Banco propio** (mis bolsas, y el banco si está abierto, de `C_Container`) y
**Solicitudes** (objeto, quién pide, de qué banco, estado; un oficial de esa hermandad aprueba —y lo envía por
correo— o rechaza). La ventana de pedir: cantidad (hasta lo que hay) y nota.

## UnionConfig.lua

Copia 266: la mitad derecha de la pestaña GuildUnion ya no es Oficiales / Miembros (sus marcos siguen, escondidos en
`stash`, BlizzTab.lua) sino la configuración de la hermandad, en `HU.db.unionCfg` (fase 1: solo en este PC; avisa con
`HU:Changed("unionCfg")`). La cambia el maestro (`IsGuildLeader`; o «Probar como maestro», `testGM`); los demás la ven.
Pestañas: **Hermandad** (color: muestra, «Elegir color» con el selector del juego y la paleta rápida; se guarda en
`HU.db.guildColors[miEtiqueta]`, como el mensaje GC), **Banco** (quién lo ve: oficiales / todos; quién puede pedir:
todos / oficiales / nadie), **Comercio** (activo; propinas: si no, la ventana de pedir esconde la propina y no la
guarda; apagado, la sección Comercio solo enseña un aviso) y **Lista negra** (abre su ventana; oficiales).

Copia 267: la configuración cabe en su mitad: título «Configuración» con quién la cambia debajo (se pisaban), pestañas
de 64 (se salían) y, en Hermandad, el color en una línea (muestra + «Elegir color»), sin paleta ni explicación.

Copia 268: pestañas de la configuración en este orden: Comercio, Lista negra, Banco, Hermandad (se abre en Comercio).
«Modo prueba» de Comercio, Calendario y Banco se enciende y se apaga (encendido, el botón oscuro): al apagarlo,
`ClearTest` quita lo de prueba. Las pestañas del Banco, centradas.

Copia 269 (UnionBank.lua reescrito):
- Banco propio, en dos: **Bolsas** (bolsas 0..NUM_BAG_SLOTS) y **Banco** (el del personaje: -1 y sus bolsas; el juego
  solo lo deja leer con el banco abierto, así que se guarda lo último visto en `HU.db.myBankSnap` y se dice cuándo).
- Cada objeto de un banco de hermandad lleva su pestaña (`{ id, count, tab }`): en la ficha, al pedir y en Solicitudes,
  «WLP3 · pestaña 2».
- Solicitudes es un registro: objeto, quién pide, banco y pestaña, estado (Pendiente / Sacado por X / Rechazada);
  al pasar el ratón, el registro completo (pedido por, sacado por, rechazada por, con fecha, y la nota). Rechazar,
  solo el maestro de la hermandad del banco (`IsGuildLeader` o «Probar como maestro»). Ya no hay «Aprobar».
- Se saca en el banco de hermandad del juego: con `GUILDBANKFRAME_OPENED` sale, al lado de su ventana, «Lo pedido a
  tu hermandad» con cada solicitud pendiente y «Sacar» (marca sacado por mí, con la hora; de momento no mueve el
  objeto: se saca a mano y se envía por correo). En el modo prueba, «Probar: abrir el banco de hermandad» la abre.

Copia 270: Banco con cuarta pestaña, **Registro** (una línea por cosa que pasa —pide, saca, rechaza— con fecha; `log`,
la más nueva abajo; los enlaces se pueden pinchar). El filtro de hermandad deja de ser un desplegable: «Todas» y un
botón por hermandad con su color (el elegido, oscuro). El modo prueba baja a la segunda fila, a la derecha. Comercio:
«+ Nueva solicitud» como «+ Nuevo evento»: centrado bajo Público · Privado, verde; la sección baja 28.

Copia 271: el filtro de hermandad del Banco, un solo botón («Todas las hermandades», las elegidas o «N hermandades»);
al pulsarlo, una casilla por hermandad para elegir una o varias (`filterTags`), y «Todas» para quitar el filtro.

Copia 272: la lista negra ya no tiene botón a la izquierda: está dentro de Configuración > Lista negra (lista con
scroll, en rojo los que están en tu hermandad; nombre/motivo con Añadir y Quitar para `HU:CanPin()`; `HU:Unban`).
Banco: tres pestañas; el registro está dentro de Solicitudes, con el botón verde «Ver registro» / «Volver a
solicitudes» abajo a la izquierda (`reqLog`). `BankIDs` usa `Enum.BagIndex` si existe (bolsa de componentes).

Copia 275: en Miembros, los desconectados llevan en la columna Zona cuánto llevan desconectados (`Ago`); ordenar
por esa columna los pone al final, de menos a más. Banco propio: un botón «Todo» con casillas Banco y Bolsas
(`ownSet`; vacío = todo, primero el banco). El menú de hermandades, solo con las etiquetas. Registro por días
(«Hoy», «Ayer», fecha) con la hora en cada línea, y los nombres a color (`Who`: clase si se sabe; si no, uno fijo).

Copia 276: en Miembros, a la izquierda de la casilla «GuildUnion», la casilla «Solo mi hermandad»
(`HU.db.unionRosterMine`): la lista solo con los de mi hermandad. Se ve con «GuildUnion» marcada.

Copia 277: fuera la casilla «GuildUnion» (siempre puesta: `Sync` borra `unionRosterOff`); «Solo mi hermandad» ocupa su sitio.

Copia 278: Configuración con pestaña Calendario (cinco pestañas, letra pequeña): quién crea eventos (`calMake`:
Maestro / Oficiales / Todos) y permisos por un tiempo (`calAllow[clave] = { name, untilT, by }`, en horas; caducan
solos). `HU:CanMakeEvents()` decide si se puede usar «+ Nuevo evento». Fase 1: se guarda en este PC, todavía no viaja.
En la vista del chat, los botones de abajo, como en Miembros: «Ver registro» y «Peticiones de oficiales».

Copia 279: pestañas de la configuración en dos filas (3 + 2, de 84, letra normal: sin el salto de tamaño al
pasar el ratón); «Puedes cambiarla» va al lado del título. Los permisos del calendario, las filas que quepan.

Copia 280: «Solo mi hermandad», solo en la pestaña Miembros. El contador de conectados de la unión cuelga de la
ventana (antes del chat): en la vista de chat junto a los cascos y en las pestañas, arriba a la derecha.
El /who de la barra de Miembros (`WhoTick`) no se lanza mientras `Sync` coloca la ventana (`inSync`) ni en combate:
al cambiar de vista con el botón seguro, el scroll lo disparaba dentro del clic seguro y el juego lo bloqueaba.

Copia 286: hasta 20 raids por evento (`MAX_RAIDS`). Se ven 5 pestañas (`RAID_TABS`, desde `raidFirst`); con más,
flechas < > que pasan a la raid anterior o siguiente, y la elegida siempre queda a la vista. Cada pestaña
lleva su raid en `idx` (también para soltar a alguien encima al arrastrar).
Copia 287: sin flechas: las 20 pestañas en dos filas de 10 (65 de ancho, letra pequeña), «+ Añadir» en el hueco
siguiente. Con la segunda fila, la ventana crece 26 (`DETAIL_H`) y líder, banquillo y grupos bajan 26.
