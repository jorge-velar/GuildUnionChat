# Guild Union — versión 5.4.7

Une el chat de hermandad de varias hermandades: lo que se escribe en **/g** lo ven **todas** las hermandades de la comunidad. Con panel de miembros de todas, chat de oficiales, canal protegido, guardia contra intrusos, chat lento, mensaje fijado, emoticonos y más. Está hecho para comunidades grandes: **hasta 20 hermandades y unas 20.000 personas**.

La 5.0 es la antigua "Guild Union 20" convertida en la versión principal (se llama otra vez **GuildUnion**).

## Novedades 5.4.7

- **`HL` (lo escrito mientras no estabas) ya no se acepta de cualquiera.** Por la hermandad solo vale si alguien ha pedido el historial (`HQ`) en los últimos 5 minutos y quien lo manda es el enlace, un ayudante, un oficial o uno de los 3 primeros por nombre (`HU.Hash`) entre los compañeros conectados con el addon, que es donde está el que contesta (`HLSourceOK`, Social.lua). Antes cualquier compañero podía inventar líneas a nombre de otro.
- **`PG` falso.** Cuando un oficial ve el `PG~nombre` de otro, no pregunta él (para no repetir). Ahora solo se hace caso si el `PG` viene de un oficial de verdad (rango del juego); antes un miembro podía mandarlo y ningún oficial comprobaba al impostor (Comm.lua, `comm.PG`).

## Novedades 5.4.6

- **Una copia vieja ya no pisa la buena.** Visto en el banco con 2.036 addons de verdad: el enlace de G02 manda su lista a los 115 s (sin Pabaae, que entra a los 120); G01 recibe una más nueva a los 136 s. A los 194 s un compañero de G01 reparte en su hermandad la copia vieja que tenía guardada y los demás la aceptan: Pabaae desaparece hasta la siguiente lista entera (359 s). El addon solo comparaba la antigüedad de las copias, y los cambios sueltos («entra X») marcan una copia como recién actualizada aunque le falte alguien. Ahora cada copia recuerda **quién la hizo** (`origin`: quien la susurra, o el campo 9 del `RB` repartido en la hermandad; los cambios `RC` lo actualizan) y una copia **del mismo origen con un número de envío (`seq`) más bajo** no pisa la propia; además se reparte la propia para corregir a los demás. El número de envío ya no empieza al azar tras un `/reload`: se guarda (`seqCounter` en `GuildUnionDB`) y sigue, para que las listas nuevas no parezcan viejas. El `RB` que llega por susurro se reenvía a la hermandad con su antigüedad (0) y su origen (si cabe en 250 letras). Las versiones anteriores ignoran el campo nuevo.

## Novedades 5.4.5

- **Restricciones del juego (Forever).** En combate, jefes, mítica+, partidas PvP y algunos mapas, el juego bloquea funciones marcadas como restringidas; una es leer la Información de hermandad. El addon la leía tras cada repaso de la lista y el juego contestaba con un `ADDON_ACTION_BLOCKED` (salía «[bloqueado] … UNKNOWN()» en `/gu errores`); con la lectura vacía podía dar la comunidad por perdida y salirse del canal hasta la siguiente lectura. Ahora `HU:GuildInfoText()` pregunta antes a `C_RestrictedActions.IsAddOnRestrictionActive`: si hay restricción no lee, se queda con lo que tenía y vuelve a leer al acabar (`ADDON_RESTRICTION_STATE_CHANGED` / fin de combate). Crear o unirse a una comunidad en ese momento espera también, para no borrar lo que tenga escrito la Información.

- **Las listas aparecen trozo a trozo.** Una lista entera de otra hermandad llega en varios trozos y antes no se usaba nada hasta tenerlos todos, así que en el panel salían todos de golpe. Ahora el panel enseña ya los nombres de los trozos que han llegado (`HU.partialRoster`); el resto del addon (guardia, peticiones de listas) sigue con la lista anterior hasta tenerla entera, así que no cambia la seguridad ni hay saltos.

- **Ayudantes completos enseguida al cambiar de enlace.** Un enlace nuevo solo conocía a quien había saludado desde que entró; el resto no volvía a saludar hasta 2–5 min después, y hasta entonces faltaba algún ayudante (y su nombre en las listas de las otras hermandades). Ahora el enlace nuevo pide un saludo (`HY`) y cada compañero contesta una vez (`HR`, repartidos en 12 s). Además, la regla de «no cambiar ayudantes más de una vez cada 2 min» ya no impide **añadir** uno a un hueco libre.

- **Maestros y oficiales, moderadores del canal** (decisión de Jorge, 06/11). Hasta la 5.4.4 el propietario le quitaba la moderación a todos («nadie más que el propietario manda»), aunque el comentario de `Guard.lua` decía lo contrario; así, a un impostor solo lo echaba del canal el propietario y los demás oficiales solo lo silenciaban. Ahora `CheckChannelOwner` (cada 60 s, solo en el propietario si es maestro u oficial) da moderador con `ChannelModerator` a los maestros y oficiales del canal (hasta 5 por vuelta, una vez cada 10 min por nombre) y se lo quita a quien lo tenga sin serlo. Cada hermandad decide sus oficiales con sus rangos (`GU:r:ETIQ:N`), así que **un oficial de cualquier hermandad puede echar a cualquiera del canal**: es el precio de que todos puedan echar impostores.

- **El chat del panel baja solo.** Al llegar un mensaje el contenido crece y el juego avisa de un movimiento del scroll antes de que el addon baje; el addon lo tomaba como «el jugador ha subido» y dejaba de seguir el chat. Ahora, si estaba abajo y solo ha crecido el contenido, sigue abajo (`lastRange` en `UIChat.lua`). Además, una caja de mensaje activa sin texto elegido (tras arrastrar un poco el ratón) ya no congela el chat.

- **Ver recetas en Forever.** Forever usa la ventana de profesiones moderna: el enlace de la lista de recetas (`C_TradeSkillUI.GetTradeSkillListLink`) solo existe cuando la ventana ha cargado sus datos (`TRADE_SKILL_LIST_UPDATE`), y el addon lo buscaba antes (`TRADE_SKILL_SHOW`) y con un evento que ahí no existe (`TRADE_SKILL_UPDATE`), así que no llegaba a guardarlo y nadie podía ver tus recetas. Ahora, además de escuchar esos eventos, guarda al entrar (y con `SKILL_LINES_CHANGED`) el enlace de cada profesión desde el libro de profesiones (`C_SpellBook.GetSpellBookItemTradeSkillLink`, lo mismo que Mayús+clic en el libro), sin abrir nada. Y al ver las recetas de otro (`IsTradeSkillLinked`, de hermandad…) ya no se guarda su enlace como si fuera el tuyo.

## Novedades 5.4.4

- **La lista del canal era la de otro canal (Forever y Retail).** El juego numera los canales de dos formas: el número del chat (`/6`) y la posición en la ventana Social > Chat. La lista de miembros se pide con la posición, y el addon le pasaba el número: en el cliente moderno no coinciden y salía otro canal (el Comercio: «En el canal: 1.177. Propietario: ninguno» en un canal recién creado por ti). Afectaba a `/gu estado`, `/gu canal`, al reparto de la propiedad a oficiales y a la guardia («la lista del canal no está disponible»). Casi seguro que el «`GUWLP56` con 1.542 personas y nombres rusos» del 05/11 era esto. Ahora `HU:ChannelRoster` busca la posición por el nombre (`GetChannelDisplayInfo`), selecciona ese canal en la ventana (`SetSelectedDisplayChannel`, sin abrirla, como mucho cada 30 s) para que el juego cargue su lista, y si aún no está cargada lo reintenta en la vuelta siguiente. Como volver a seleccionar el mismo canal no hace que el juego pida la lista otra vez, al refrescar (cada 30 s, o cuando alguien entra o sale del canal) pasa un momento por otro canal y vuelve. El banco no lo detectaba porque el simulador numera igual las dos cosas.

- **`/gu estado` ya no dice «sin lista» por sistema.** Esa línea miraba la lista completa de miembros, que desde la 5.3.0 no se reparte. Ahora dice lo que de verdad llega de cada hermandad: en la fase de lanzamiento, «maestro N y oficiales N conectados (hace X)»; en la completa, cuántos conectados hay en total.

- **Recargar con un clic (Forever).** Los avisos de «¿recargar la interfaz?» (cambiar apariencia o idioma, `/reload` en el chat del panel) vuelven a usar la ventana de aviso del propio juego, cuyo botón sí puede recargar; la versión de las 00:28 la había quitado y te hacía copiar y pegar `/reload`. La ventana de órdenes queda solo de respaldo si el juego lo bloqueara también.

- **Rangos de las otras hermandades tras un `/reload`.** Sus nombres («Maestro», «Oficial»…) solo llegan con la lista entera, cada 30 min; al recargar se perdían y el panel enseñaba «Rango 0», «Rango 1». Ahora se guardan por personaje y se recuperan al entrar.

- **Panel:** en Retail y Forever el chat va corrido como el del juego (las líneas que siguen empiezan en el margen, no debajo del mensaje); la lista de miembros de General tiene ancho fijo (solo se pliega y despliega); y en la lista estrecha la corona y las espadas van en un sitio fijo, a la izquierda del punto de conectado, en vez de pegadas a un nombre que podía taparlas.

- **Chat lento más claro:** el aviso al que escribe antes de tiempo es corto («Chat lento: espera 12 s.»), y mientras está puesto, cada caja del chat del panel enseña a la derecha «Lento: cada 30 s» de forma fija.

- **Seguridad, repaso de la revisión del 05/11:** (1) los silencios que el enlace reparte en paquete (`MZ`) se rechazaban todos por la comprobación nueva de «quién lo trae» (llegaban con una vía inventada, «BATCH»): ahora pasan con la vía real, así que los silencios vuelven a llegar a todas las hermandades; (2) el canal y la contraseña que llegan por **susurro de un compañero** solo se aceptan si los acabas de pedir al entrar (`CQ`, 60 s) o si quien contesta es oficial, enlace o ayudante: antes cualquier compañero podía mandarte un canal falso firmado por un oficial; (3) vuelve el segundo saludo a los 36 s de entrar, para que el enlace se presente en el canal enseguida y no a los 2–5 min.

- **Historial de oficiales sin tirones (vuelve de la 5.4.3):** el rellenado cada 5 min calculaba las huellas de 30 días de golpe (63–305 ms de tirón en el enlace con 3.000 personas; más con historiales de 13 MB). Vuelve a ir por trozos y fotogramas, con las huellas de los días cerrados guardadas, y las líneas de un trozo se filtran primero por segundo.

- **Impostores comprobados por el juego.** Quien escribe con tu etiqueta y no está en tu lista ni ha hablado por la hermandad recibe una pregunta por la **vía de hermandad del juego** (`PG`), que solo pueden usar los miembros y cuyo remitente no se puede falsificar; su addon contesta `PA` por la misma vía. Sin respuesta a los 20 s se repite; sin respuesta a los 40 s (está conectado con el addon y no es de la hermandad): silencio de 1 h para todas y, si eres moderador, fuera del canal, **automático**. Mientras se comprueba, sus mensajes quedan retenidos: si es de los nuestros se enseñan después; si no, nadie los ve. Ya no depende de cómo escriba los nombres Forever. Límites: una pregunta por nombre cada 5 min y 5 por minuto. (El modo «aviso» provisional de esta noche se ha quitado.)

- **Historial: insertar una línea vieja ya no da tirones.** Al rellenar huecos de hace horas, cada línea recorría el día entero (cien mil líneas tras 4 h de charla: 35–140 ms). Ahora busca su sitio por bisección y mira repetidos solo en ±2 min. Visto en una simulación de 10 h.

## Novedades 5.4.3

- **Menos tirones en hermandades grandes:** la lista de tu hermandad se lee por trozos (200 miembros cada vez) y como mucho cada 30 segundos, en vez de entera con cada aviso del juego. Si algo la pide con prisa (la guardia, un cambio de rango, alguien que entra o sale de la hermandad), a los pocos segundos.
- Las notas de oficial solo se vuelven a mirar si han cambiado, y la «última conexión» de cada desconectado, como mucho cada 15 minutos.
- Quién se conecta o se desconecta sigue viéndose al momento (por el aviso del juego).
- **Saludo sin tirones:** el saludo (y cada respuesta a un saludo) preguntaba «¿soy moderador?» montando la lista entera de la gente del canal; ahora usa la comprobación rápida, y la lista del canal que necesita el saludo se lee por trozos (500 cada vez). Lo mismo al pintar tus espadas rojas.
- La huella de los nombres de tu hermandad solo se rehace si alguien entra o sale (antes, con cada lectura de la lista).
- **Listas de las otras hermandades que se quedaban incompletas** (a veces durante 10 minutos o más). Había cuatro formas de perder a alguien:
  1. Un compañero repartía en tu hermandad una copia vieja y pisaba la buena. Ahora cada copia dice cuántos segundos tiene y la más nueva no se pisa (y quien la tiene la vuelve a repartir).
  2. Al cambiar los ayudantes de una hermandad, los demás no se enteraban hasta el saludo siguiente (2–5 min). Ahora el enlace lo dice a los pocos segundos.
  3. Si el papel de enlace pasaba un momento a otro, el enlace de verdad creía que las otras hermandades seguían con su lista. Ahora, al volver a ser enlace, manda la lista entera; y quien recibe un cambio que no cuadra pide la lista entera enseguida.
  4. Un cambio que llegaba mientras se recibía una lista entera hecha antes quedaba pisado por ella. Ahora se vuelve a aplicar.
  5. Si una lista que no viene del enlace de esa hermandad pisa la que el enlace mandó hace poco, se le pide la entera al enlace para confirmarla (segunda opinión).
- **Lo importante sale antes:** cada segundo salen primero el chat y los silencios, luego los cambios de las listas y lo normal, y al final lo grande (listas enteras, inactivos). Antes salían primero los datos grandes, y unos inactivos largos podían retrasar 15 s un silencio. Además, un silencio sale aunque el addon haya gastado su cupo del segundo (el juego deja margen).
- **El enlace ya no baila al entrar todos:** recién entrado nadie se cree enlace durante 30 s (antes cada uno lo era hasta oír a los demás, mandaba su lista a las otras hermandades y pisaba la buena). El enlace vuelve a saludar en cuanto oye a un compañero nuevo, y quien entra sin conocer aún a su enlace saluda cada 45 s hasta oírlo. Los ayudantes solo cambian ante alguien claramente mejor.
- **Inactivos solo de oficiales:** de las otras hermandades solo se mandan maestro y oficiales inactivos (en el panel ya solo se ven ellos). Antes iban cientos de nombres en decenas de mensajes.
- **Chat oculto con reintentos:** si el juego contesta «ahora no» (cupo, canal saturado, chat cerrado en banda o mazmorra), el mensaje se guarda y se reintenta cada segundo hasta 30 s; antes se perdía. Va por la vía «registrada» del juego (`SendAddonMessageLogged`), la pensada para texto de personas; se sigue aceptando la de versiones anteriores.
- **Carriles del canal (lo que le pasó a Olympus la noche del lanzamiento de Forever):** si el juego rechaza 3 envíos seguidos al canal con «canal no válido» aunque sigas dentro, el addon se pasa solo al canal siguiente (`Nombre1`, `Nombre2`… hasta 9) con la misma contraseña, lo recuerda para el próximo `/reload` y avisa a su hermandad (que solo sigue al enlace) y a los enlaces de las otras hermandades (que lo comprueban por su cuenta). El enlace sondea el canal cada minuto si no ha mandado nada. En el banco, los 16 addons se reencontraron en el carril nuevo en menos de 2 minutos.
- **Invitar, echar y cambiar rangos como en GuildManagement (probado en Forever):** esas órdenes son «solo para la interfaz de Blizzard»: ni el addon, ni una macro, ni un botón seguro pueden hacerlas, y si el addon escribe en la caja del chat, el juego las bloquea hasta `/reload` (eso hacía la 5.4.1). Ahora sale una **ventana de órdenes** con cada `/ginvite`, `/gremove`, `/gpromote` o `/gdemote` ya seleccionado: **Ctrl+C → Intro → Ctrl+V → Intro**. Al enviarla pasa sola a la siguiente (y también si el juego contesta en el chat); si no, botón **Siguiente**. En la invitación masiva se salta a quien ya esté en la hermandad. `/gu diag` dice si el juego tiene esos comandos bloqueados y qué addon los tocó.
- **El historial se rellena solo (idea de GuildManagement):** cada 5 minutos, y al entrar, un oficial compara con otro oficial conectado unas «huellas» de lo guardado (cuántos mensajes y una suma de sus textos) por día; donde no coinciden, por hora, y luego por 10 minutos; y pide solo ese trozo. Quien vuelve tras unas horas recupera lo que se dijo sin buscar nada. Solo se pide, nunca se empuja; el chat de oficiales nunca viaja. `/gu historial rellenar` lo fuerza.
- **Si no hay oficiales conectados:** los miembros con el addon guardan **2 días** del chat de hermandad y buscar grupo (nunca el de oficiales, tope 1 MB) y contestan **solo a oficiales**: al relleno de huecos y a `/gu buscar` cuando hay menos de dos oficiales conectados.
- **Chat más barato:** un mensaje sin emoticonos ya no se recorre letra a letra (era lo que más basura de memoria generaba), y quien escribe se guarda en disco como mucho una vez por minuto, no con cada mensaje.

## Novedades 5.4.2

- **Panel de miembros:** de las otras hermandades salen solo el **maestro y los oficiales**. El enlace y sus ayudantes siguen viajando en la lista (el addon los necesita para aceptar sus mensajes), pero ya no aparecen en el panel.

## Novedades 5.3.0

- **Historial de oficiales (30 días):** los maestros y oficiales guardan el chat de la comunidad de los últimos 30 días (hasta unos 3 MB; si se pasa, se borran los días más viejos). Con **/gu buscar Nombre** (o **/gu historial**) se ve todo lo que ha dicho alguien, los más nuevos primero, y con **[ver]**, lo que se dijo antes y después. Se puede buscar también por texto.
- **Lo que pasó mientras no estabas:** la búsqueda pregunta además a los oficiales conectados (de todas las hermandades). Cada uno busca en lo suyo y contesta solo con lo que encuentra (como mucho 40 mensajes); los repetidos se juntan. Solo contestan a quien es oficial **ahora**, y el chat de oficiales nunca se pasa.
- **Aparte del resto:** el historial va por su propio canal de mensajes ocultos y su propia cola, así que nunca frena las listas ni el chat. Si diera errores, se apaga solo; **/gu historial off** lo apaga a mano.
- **Entradas masivas:** el chat de mientras no estabas lo manda una sola persona, una vez, a toda la hermandad (antes, el primero por orden alfabético se lo mandaba a cada uno y atascaba las listas de miembros). Lo de oficiales sigue yendo solo a los oficiales.
- **Guardia más ligera:** con miles de personas en el canal revisa por partes, quien no es moderador casi no gasta nada, y con más de 6 hermandades le basta con las listas de conectados.
- **Guardia más segura:** al preguntar a las otras hermandades por muchos sospechosos a la vez, los que no cabían en el mensaje se daban por intrusos aunque fueran de las hermandades. Ahora cada pregunta lleva solo los que caben y el resto va en la siguiente; y quien acaba de entrar (sin su lista cargada) no contesta.
- **Conectados al momento:** quien entra o sale del juego aparece así en las listas de las otras hermandades en unos segundos (antes, hasta 2 minutos). En una entrada o salida masiva se juntan los cambios y tarda algo más.
- **Ver recetas** abre directamente la ventana de profesiones del juego (Retail y Forever).
- **Lo de las comunidades grandes, para todas:** también con 2 a 6 hermandades, las listas completas de miembros ya no se reparten (eran la mayor parte del tráfico), la guardia se conforma con las listas de conectados y los desconectados de las otras hermandades salen al elegir **Inactivos** (la primera vez tardan unos segundos).
- **Forever, nombre y apellido:** echar, ascender, degradar e invitar usan «Nombre Apellido»; las invitaciones lo reintentan como «Nombre-Apellido» si el juego no lo encuentra.
- **Menos tirones:** las listas que llegan, la de tu hermandad, el saludo del enlace y la guardia se reparten entre varios fotogramas; y el chat del panel no gasta nada mientras está cerrado (se rellena al abrirlo).
- **Ventana «Guild & Communities» (Forever y Retail):** enseña solo el chat de tu hermandad; lo de las otras sale en las pestañas del chat y en el panel. Escribir desde esa ventana sí llega a las demás.

## Novedades 5.2.1

- **El chat del panel se borraba al salir:** en la 5.2.0 lo de cada personaje iba a un archivo de guardado nuevo, y el juego solo lee los archivos nuevos de un addon **después de cerrarlo y abrirlo** (con /reload no basta). Si solo se recargaba, no se guardaba nada. Ahora va dentro del archivo de siempre, en un apartado por personaje, y funciona aunque no se reinicie.
- Lo que escribieron mientras no estabas te lo pasa un compañero de tu hermandad con el addon al entrar; como el historial empezó de cero con la 5.2.0, se irá llenando a partir de ahora.

## Novedades 5.2.0

- **Si te echan de la hermandad, se acabó el chat:** el juego te deja dentro del canal oculto aunque recargues o te echen, y por eso se seguía leyendo lo nuevo. Ahora el addon recuerda en qué canales ha entrado y, si ya no te tocan (te han echado, tu hermandad ya no está en la comunidad...), sale de ellos. Si alguien con el addon cambiado se queda, la **guardia** lo echa (hace falta un moderador conectado); y si sospecháis, cambiad la contraseña.
- **Cada personaje lo suyo:** el chat, el mensaje fijado, el canal y la contraseña se guardan ahora **por personaje**, no para toda la cuenta. Antes, un personaje de otra hermandad de la misma cuenta veía el chat de la comunidad de tu otro personaje (eso es lo que pasaba con la segunda hermandad "sin configurar"). Al actualizar, el historial del chat empieza de cero; la unión se mantiene.
- **Rango de castigo:** crea en tu hermandad un rango llamado **Castigado** (el último, sin el permiso "Hablar en el chat de hermandad"). Al silenciar o vetar a alguien de tu hermandad, el addon te ofrece bajarle a ese rango con un clic; al acabar el silencio o quitarle el veto, te ofrece devolverle su rango. Así el juego tampoco le deja escribir, ni en el /g ni en la ventana de la hermandad.
- **Recetas en Retail:** al abrir tu profesión, el addon guarda el enlace de la profesión. Los demás, al pedir tus recetas, reciben el enlace: al pulsarlo, el juego enseña todas tus recetas.
- **Profesiones en Retail:** se leen con las funciones de Retail, también las de los de otras hermandades.
- **"Mensajes" de un jugador:** solo para maestros y oficiales (los miembros ya no lo ven en la ficha ni en el clic derecho).
- **Entrar al juego más rápido:** lo guardado se limpia solo: fichas y recetas de más de 30 días, rangos de más de 14 y listas de inactivos de más de 2. Cargar el addon y entrar cuesta unos milisegundos.

## Novedades 5.1.9

- **Retail, chat de la ventana de la hermandad (Comunidades):** lo que se escribía ahí no pasaba por el addon. Ahora sí: llega a las demás hermandades, y si quien escribe está silenciado, vetado o con el chat lento, a los que tienen el addon no les sale en el chat normal y a él le sale el aviso.
- Lo que el addon no puede hacer es borrar mensajes de la propia ventana de Comunidades del juego (es de Blizzard). Para que un vetado no pueda escribir de ninguna forma en la hermandad, pásalo a un rango sin el permiso **"Hablar en el chat de hermandad"** (Hermandad > Ajustes > Rangos).

## Novedades 5.1.8

- **Retail, chat de oficiales sin texto (otra vez):** en Retail los mensajes del chat del panel se dibujan ahora con texto normal, no con la caja de texto del juego (que en el chat de oficiales no los enseñaba). La caja sigue debajo, transparente, para poder seleccionar y copiar.
- **Mensaje fijado para los que entran:** se lo pasaba solo el enlace de su hermandad, y si el enlace era alguien que acababa de entrar y aún no lo tenía, no le llegaba a nadie. Ahora también se lo pasa un oficial que lo tenga.
- **Al escribir, el chat vuelve abajo:** si estabas leyendo mensajes de antes (o habías saltado a uno), al mandar un mensaje el chat vuelve al final, en directo.

## Novedades 5.1.7

- **Retail, chat de oficiales sin texto:** el mensaje llegaba bien (se veía en `/gu diag`) pero no se dibujaba: la caja del mensaje se creaba antes de que la letra del chat estuviera lista y en Retail se quedaba así. Ahora la letra está puesta desde el principio y se vuelve a poner en cada mensaje.

## Novedades 5.1.6

- **Silenciados, vetados y chat lento:** quien escribía en /g veía su propio mensaje y creía que había llegado, aunque a los demás con el addon no les salía. Ahora tampoco le sale a él (ni en el chat del juego ni en el panel) y le sale el aviso de por qué. Ojo: el /g es del juego, así que los de su hermandad **sin** el addon sí lo ven.
- **Invitaciones masivas en Retail:** el botón ya no lleva el nombre (se salía del botón): dice **Invitar siguiente (3/40)**. Cada nombre invitado se borra de la lista, así se ve lo que falta. En Retail tiene que ser un clic por invitación: es una norma del juego (un addon no puede invitar solo).

## Novedades 5.1.5

- **Chat del panel que no se descoloca:** con nombres largos (los de otro reino en Retail, la corona, la etiqueta...) al mensaje le quedaba tan poco sitio que salía una letra por línea, o no se veía (por eso el chat de oficiales parecía vacío). Ahora:
  - el nombre sale sin el reino (el reino se ve en la lista y al pasar el ratón);
  - el canal va en corto, [H] Hermandad, [O] Oficiales, [BG] Buscar Grupo, y solo en la pestaña **Todo** (en las demás ya se sabe cuál es);
  - si aun así el nombre ocupa mucho, el mensaje baja a la línea de abajo y usa todo el ancho.
- Arreglado un fallo de la 5.1.4: el archivo de novedades y el del inglés no cargaban (por unas comillas).
- **Retail:** los separadores "·" salían como cuadros porque la letra del juego no tiene ese signo. Ahora es un guion.
- **Nuevo: `/gu diag`.** Abre una ventana para copiar con lo que llega del juego al chat (hermandad, oficiales, canal, addon), cuántos mensajes ha guardado el addon y si el juego los oculta. Sirve para encontrar por qué un chat sale vacío.

## Novedades 5.1.4

- **Retail:** el enlace de cada hermandad se presentaba escribiendo un texto en el canal oculto, y en Retail el juego no deja a un addon escribir en un canal sin que pulses una tecla (salía `ADDON_ACTION_BLOCKED` en `/gu errores`). Ahora se presenta con un mensaje oculto del addon por el mismo canal. En Classic sigue igual.

## Novedades 5.1.3 — Retail (Midnight)

Una sola carpeta para **Classic Era, Retail (Midnight) y WoW Forever** (el .toc lleva 11509, 120105 y 16001).

- **Acciones protegidas:** en Retail (y Forever) el juego no deja a un addon echar, ascender, degradar ni invitar a la hermandad por su cuenta (salía "GuildUnion se ha bloqueado..."). Ahora el botón de aceptar de esos avisos es **un botón del juego** que hace `/gremove`, `/gpromote`, `/gdemote` o `/ginvite`. Se ve igual; solo hay que pulsarlo. En combate se espera a salir.
- **Invitaciones masivas en Retail:** el botón grande pasa a ser **"Invitar a Nombre (3/40)"**: cada clic manda una invitación y prepara la siguiente (el juego no deja mandarlas solas). La barra de progreso sigue igual. Los de otro reino, con su reino: `Nombre-Reino`.
- **Reinos conectados:** los nombres viajan siempre con su reino ("Pepe-Sanguino"). Antes, en Retail, un "Pepe" de otro reino se confundía con otro, y por eso fallaban los silencios en su propia hermandad, el chat lento, los desconectados de las listas, la clase de los inactivos, las fichas y los roles. En pantalla, los de tu reino salen sin el reino.
- **La unión ya no se borra con /reload:** si el juego no deja al addon escribir en la Información de hermandad, el addon guarda una copia, se la pasa a los de tu hermandad (por el canal oculto, solo desde oficiales) y al maestro le enseña las líneas para pegarlas en la Información (Hermandad > Información). Cuando estén pegadas, la copia se borra sola.
- **Rangos:** se pueden borrar desde Oficiales > Rangos (el juego pide el número del rango). Si el rango tiene gente, avisa; si el juego no deja, dice que se borre en la ventana de la hermandad del juego.
- **Diagnóstico:** lo que el juego bloquee al addon queda en `/gu errores` con el nombre de la función. `/gu memoria` dice cuánta memoria usa el addon y cuántos mensajes hay en cola.
- **Mensajes del addon:** si el juego dice que va saturado, el mensaje vuelve a la cola y se reintenta (hasta 5 veces), sin perder la prioridad (primero el chat, luego conectados, fichas y por último desconectados).
- **Emoticonos de Twitch sin instalar nada:** con el juego cerrado, doble clic en `Tools\Emoticonos de Twitch.bat`, escribe el canal y listo (usa PowerShell, que ya trae Windows). Baja los emoticonos, crea el pack y deja en el Escritorio **"GuildUnion con emotes.zip"** para pasárselo a los demás. En el juego, el maestro va a Configuración > Chat > Importar y pulsa el botón del pack.

## Novedades 5.0.3

- **Cabecera de la lista (pestaña Miembros):** cada columna (Nombre, Lugar, Hermandad, Rango, Estado) es ahora un recuadro entero, de raya a raya: se ilumina al pasar el ratón y se puede pulsar en cualquier sitio. La columna por la que se ordena queda resaltada con fondo dorado, una raya abajo y la flecha. "Nombre" va alineado a la izquierda.
- **Espadas rojas para los moderadores:** quien es moderador del canal del chat unido sale con las dos espadas en **rojo** (en la lista, en el chat, en las fichas y en las menciones). Los oficiales que no son moderadores siguen con las espadas normales y los maestros con la corona. La corona y las espadas son ahora un poco más grandes y van centradas con el texto, recortadas para que no se vea el borde de la imagen.
- **Invitaciones masivas con barra de progreso:** mientras invita, debajo de la lista sale una barra que se va llenando, con "12 / 40" en el centro y lo que falta a la derecha ("faltan 28 (0:28)"). Al terminar se pone verde ("Hecho: 40 invitaciones enviadas."); si la paras, roja, con las que quedaron sin invitar.
- **Filtros puestos:** cada filtro es una cápsula con borde redondeado, con su icono (clase, profesión o rol) y su color (clase o hermandad): "Clase  Guerrero", "Raza  Orco"... A la derecha, una **X blanca en un círculo rojo**. Al pasar el ratón se ilumina y, al pulsar, se quita solo ese filtro. **Quitar todos** sale aparte, como un enlace en rojo.

## Novedades 5.0.2 — WoW Forever

- **Carga en Classic Era y en WoW Forever** (el .toc lleva las dos interfaces, 11509 y 16001, la de la beta de Forever). Si en el lanzamiento Blizzard cambia el número, el juego lo marcará como "desactualizado": basta con marcar **Cargar addons desactualizados** hasta la siguiente versión.
- **Nombre y apellido:** en Forever el apellido va donde en los demás juegos va el reino ("Pepe-Garcia"). El addon lo trata como parte del nombre:
  - en la lista, en las fichas y en el chat sale **"Pepe Garcia"**;
  - se puede escribir con espacio o con guion (`Pepe Garcia` o `Pepe-Garcia`), y si solo pones el nombre ("Pepe") y solo hay un Pepe conocido, es él;
  - las menciones valen con `@Pepe` o con el nombre completo;
  - las invitaciones masivas mandan "Nombre-Apellido" y, si el juego dice que no existe, lo vuelven a probar como "Nombre Apellido".
- **Datos ocultos:** en Forever (como en Midnight) el juego a veces esconde a los addons el texto o el nombre de un mensaje (por ejemplo, en mazmorras). El addon ya no los toca.
- **Funciones nuevas:** profesiones, especialización (rol), nombres de objetos y hechizos, ascender/degradar y filtros del chat usan las funciones del juego moderno cuando no están las de Classic.
- **Sin errores a la vista:** los temporizadores y los filtros del chat del addon ya no pueden sacar ventanas de error; si algo falla, se guarda para los oficiales (`/gu errores`).
- **Más seguro:** el historial del chat que te pasan al entrar solo se acepta de alguien de tu hermandad y con fechas válidas (antes se podía colar texto con un susurro oculto).

> Ojo: Forever sale el 4 de noviembre y todo lo de arriba se ha hecho con lo que se sabe de la beta. Si algo cambia el día del lanzamiento, `/gu errores` (oficiales) dirá qué falla.

## Novedades 5.0.1

- **Filtro por raza:** en **Filtros** hay ahora **Raza** (se pueden marcar varias). La raza sale también en la ficha pequeña al pasar el ratón por un miembro y en su ficha de información, siempre en el idioma del addon (aunque el otro juegue en inglés). Solo se sabe la raza de quien tiene el addon (va en su ficha).
- **Invitaciones masivas:** un personaje por línea (nombre y apellido juntos en la misma línea, como en Forever) y una invitación cada segundo.
- **Filtros a la vista:** los filtros puestos salen debajo del botón **Filtros** como etiquetas ("Clase: Guerrero", "Raza: Orco"...), cada una con una **X en un círculo rojo** para quitar solo ese filtro. Con dos o más sale también **Quitar todos**. Si no caben, sale "+N" con los que faltan. La lista baja un poco para dejarles sitio.

## Novedades 5.0.0

- **Bienvenida:** la primera vez sale un mensaje de bienvenida (en lugar del de novedades) que explica que lo que escribas en /g lo ven todas las hermandades, que en **Configuración** puedes cambiar el aspecto, la letra y más, y que con **clic derecho** en un miembro ves su ficha de información.
- **Registro de oficiales con estilo:** la primera vez que alguien echa o veta en el día sale **FIIIRRRSSTTT BLOOOOOOOD** en rojo; si echa a varios seguidos (en 30 s), **DOOOUUUBLEEEE KILL**, **TRIIIPLEEEE**, **QUAAADRAAA** y **PEEENTAAA KILL**. Y al llegar a 10, 25, 50 y 100 vetos, un mensaje especial (**LEEEGEEENDAAARY**, **GOOODLIIIKE**...). Solo lo ven maestros y oficiales. Lo que echa la guardia sola no cuenta.
- **Destacar mensajes (oficiales):** el botón **!** junto al de los emoticonos hace que tu próximo mensaje salga destacado para todos, con un fondo azul como cuando seleccionas texto (el mensaje se sigue leyendo). En el chat del juego sale con **»** delante. Si alguien que no es oficial pone » no se destaca.
- **Invitaciones masivas (oficiales):** Oficiales > Opciones > **Invitaciones**. Pega hasta 100 nombres, **uno debajo de otro** (un personaje por línea, con nombre y apellido en la misma línea); se invita a uno **cada segundo**, saltando repetidos y a quien ya está en la hermandad. Se puede parar. Queda en el registro.
- **Configuración más privada:** al unir una hermandad, las líneas `GU:g:` de las **otras** hermandades se escriben en las **notas de oficial** de los oficiales (una por nota, si cabe en 31 letras). Lo que no cabe va a la Información de hermandad. El título y la línea de tu propia hermandad siguen en la Información, para que el addon funcione aunque no haya ningún oficial conectado. Los oficiales leen las notas y el addon se las pasa a los demás miembros (que las guardan para la próxima vez). El maestro, además, quita a los rangos de miembro el permiso **"Ver notas de oficial"**, para que solo los oficiales las vean. En la Información queda una línea `GU:n:N` que dice cuántas hay en notas (así solo las piden los que no las tienen).
- **Errores del addon solo para oficiales:** el aviso de error, `/gu errores` y "Copiar errores" solo los ven maestros y oficiales.
- **Emoticonos de Twitch:** el programa `Tools\emoticonos_twitch.py` baja los emoticonos de un canal de Twitch (BTTV, FFZ, 7TV), los convierte al formato del juego y te da las líneas para pegar en Importar emoticonos. Ver más abajo.
- **Panel General:** se quita la cabecera de columnas de la lista de miembros (solo queda en la pestaña Miembros).
- Varios maestros: el maestro de cada hermandad tiene los mismos permisos de maestro en la comunidad. Los rangos de cada hermandad se copian solos.

## Emoticonos de Twitch

El juego no puede conectarse a internet, así que los emoticonos tienen que ir **dentro de la carpeta del addon** de todos los jugadores:

1. Instala Python 3 y la librería Pillow (`pip install pillow`).
2. Ejecuta `python Tools\emoticonos_twitch.py nombredelcanal`. Guarda las imágenes en `Media\Twitch` y crea `emoticonos_nombredelcanal.txt`.
3. El maestro pega las líneas del .txt en **Configuración > Chat > Importar emoticonos**.
4. Reparte la carpeta `Media\Twitch` con el addon (por ejemplo, en el mismo .zip) y **cierra y vuelve a abrir el juego** (con /reload no carga imágenes nuevas). A quien no tenga las imágenes le saldrá un cuadro en su lugar.

## Instalación

1. Copia la carpeta `GuildUnion` en `World of Warcraft\_classic_era_\Interface\AddOns\` (Classic Era) o en `World of Warcraft\_retail_\Interface\AddOns\` (Retail).
2. Si tenías **Guild Union 20** o **We Love PvP**, desactívalos (si están activos a la vez, Guild Union no arranca y te avisa).
3. Abre el panel con `/gu` (o `/guildunion`) o con el botón del minimapa.

## Preparado para comunidades grandes

- **Miembros de las otras hermandades:** se ven siempre **los conectados**. Los **desconectados** de otra hermandad salen al elegirla en el filtro **Hermandad** con **Inactivos** marcado, o al **buscar un nombre** (3 letras o más). La primera vez tardan unos segundos (nivel, clase y desde cuándo se piden a esa hermandad) y luego se quedan guardados. *En comunidades pequeñas (hasta unas 3.000 personas en las otras hermandades) se ven todos, como en la versión normal.*
- **Fichas** (profesiones, rol, raza): llegan solas las de los conectados; la de un desconectado se pide al abrir su tarjeta.
- **Al entrar**, lo que te falta (listas de las otras hermandades) te lo pasan **tus propios compañeros** en unos segundos, en vez de pedírselo cada uno a las 19 hermandades.
- **El chat** funciona desde el primer momento: mientras llegan las listas de una hermandad, sus mensajes se aceptan igual (el canal tiene contraseña y la guardia sigue echando a los intrusos).
- **Contactos al instante:** el enlace de cada hermandad se presenta en el canal oculto (lo ven todos los del addon a la vez), así que todas las hermandades se encuentran en segundos en vez de ir buscándose una a una.
- **Lo urgente primero:** las listas de miembros, fichas y desconectados van en una cola aparte, detrás de las listas de conectados y los avisos.
- **Hermandades que se unen:** la Información de hermandad solo admite 500 letras; si no caben las 20 líneas `GU:g:`, se escribe la propia y las que quepan, y el resto se guarda como "añadida desde el panel" (el addon las reparte solo).
- Por dentro: más ayudantes del enlace (hasta 10), menos saludos repetidos, los cambios de la lista de conectados valen aunque los mande otro compañero, y el panel y el chat no recorren miles de nombres en cada mensaje.

## Nombre de la comunidad

El título del panel, del chat y de los avisos es el de la **hermandad principal** (la primera línea `GU:g:` de la Información de hermandad). Para poner otro nombre, añade una línea `GU:t:Nombre de la comunidad`.

## Añadir hermandades desde el panel (nuevo en 4.0)

**Oficiales > Opciones > Hermandades** muestra las hermandades de la comunidad. Cualquier maestro u oficial puede:

- **Invitar a una hermandad:** escribe el nombre de su maestro (o de quien pueda editar su Información de hermandad), que tiene que estar conectado y con el addon, y una etiqueta (hasta 6 letras). Le sale un aviso; si acepta:
  - el addon escribe las líneas `GU:` en la Información de su hermandad (respetando el texto que ya tuviera) y le pasa el canal y la contraseña;
  - las demás hermandades la añaden solas a su lista: **no hace falta tocar su Información de hermandad**.
- **Quitar** una hermandad que se añadió desde el panel. Las que están en la Información de hermandad se quitan borrando su línea de ahí.

Todo queda en el registro de oficiales. Solo se aceptan cambios de maestros y oficiales de la comunidad.

## Miembros y oficiales

Es el mismo addon para todos; se adapta solo al rango de cada uno.
- **Miembros:** ven General, Miembros y Chat; escriben en Hermandad y Buscar Grupo; notas privadas, Información, recetas, susurrar, invitar al grupo, desacoplar, apariencia y letra.
- **Solo oficiales y maestro:** pestaña Oficiales, chat de Oficiales, editar el mensaje fijado, notas públicas, silenciar, vetar, echar, cambiar rangos y canales.
- **Invitar a la hermandad** sale a quien tenga ese permiso en su rango del juego.
- Aunque alguien modificara su addon, los demás rechazan cualquier acción de oficial que no venga de un oficial conocido.
- En modo prueba: `/gu prueba miembro` para ver el addon como un miembro y `/gu prueba oficial` para volver.

## Configuración (la hacen los maestros una sola vez)

1. **Información de hermandad** de CADA hermandad (la lee cualquiera; aquí ya no va la contraseña):
```
GU:g:Nombre Exacto Hermandad Uno:WLP1
GU:g:Nombre Exacto Hermandad Dos:WLP2
```
2. **Nota de oficial** del maestro de UNA sola hermandad (la principal). Solo la ven quienes pueden leer notas de oficial. Máximo 31 letras:
```
GU:c:Canal:clave
```
   El addon de los oficiales la lee y se la pasa a todos los miembros de todas las hermandades sin que la vean. Cada uno la guarda para la próxima vez.
3. (Opcional) Chat de oficiales: en la nota de oficial de **otro** miembro de cada hermandad (no cabe en la misma nota): `GU:o:CanalOfi:clave2`

**Cambiar la contraseña o el nombre del canal:** edita la nota de oficial del paso 2 y pulsa Oficiales > Estado > Contraseñas. En segundos llega a todos. Si cambias solo la contraseña, el propietario del canal (si está conectado) la cambia en el canal él solo; si sospecháis una filtración, cambia también el nombre.

Si una hermandad todavía tiene `GU:c` en la Información de hermandad, sigue funcionando, pero Estado avisa para que la quitéis de ahí.

### Qué hermandades están permitidas y cómo añadir más

- Las permitidas son las que tienen una línea `GU:g:` en la Información de hermandad. Las ves en **Oficiales > Estado** ("Hermandades permitidas") o con `/gu estado`.
- Para añadir una hermandad nueva, lo más fácil es **Oficiales > Opciones > Hermandades > Invitar** (ver arriba). También se puede a mano: su línea `GU:g:Nombre Exacto:ETIQ` en la Información de hermandad de todas las hermandades.
- Quien esté en cualquiera de ellas nunca es expulsado del canal por la guardia.

### Moderadores (necesarios para la guardia)

- El primer jugador que entra en el canal se convierte en su propietario. Conviene que el maestro entre primero, o que se le pase la propiedad con `/owner NombreCanal Jugador`.
- El propietario nombra moderador al menos a un oficial de cada hermandad con `/moderator NombreCanal Jugador`.

## Probarlo sin hermandad

1. Escribe `/gu prueba`. Te unes a un canal de prueba oculto (HUPrueba, clave "prueba"). Para usar otro canal y otra clave: `/gu prueba MiCanal miclave`.
2. Abre el panel (`/gu` o el botón del minimapa):
   - En **Miembros** sales tú (hermandad "WeLovePVP") y una hermandad de ejemplo, "WeLovePvp" `<DEMO>`, con miembros inventados (algunos ausentes, desconectados desde hace horas o días, con profesiones y rol). Puedes probar los botones de rango con ellos: como no hay nadie real de `<DEMO>`, la petición te dirá que no hay nadie conectado.
   - En **Chat** puedes escribir (o con `/hg mensaje` desde el chat normal; en modo prueba no existe /g). Lo que escribes sale también en tu chat del juego. Si un amigo con el addon escribe `/gu prueba` con el mismo canal y clave, os veis los mensajes.
   - En **Oficiales**, si eres el propietario del canal (el primero que entra), tu amigo aparece como intruso pasados 2 minutos. Con `/gu permitir NombreAmigo` deja de serlo.
   - En el **mapa del mundo** ves a los de `<DEMO>` paseando a tu alrededor, y a tu amigo si está en el mismo canal de prueba. A ti mismo no te pinta: ya estás con la flecha del juego.
3. `/gu prueba off` sale del modo prueba.

## Historial de Guild Union 20

### Novedades 20.0.6

- **La guardia pregunta:** si falta la lista completa de alguna hermandad, en vez de quedarse en espera pregunta a su contacto (enlace o ayudante) "¿son de los tuyos?". Él tiene la lista entera de su hermandad, también los desconectados. Solo se echa a alguien cuando **todas** esas hermandades contestan que no es suyo; si alguna no contesta o no hay a quién preguntar, no se echa a nadie. La respuesta vale 5 minutos y los confirmados como miembros, 1 hora. Así la guardia protege desde el primer minuto.
- **Sin listas completas en comunidades grandes:** con más de 6 hermandades, las listas de 1.000 nombres de cada una ya no se reparten (eran la mayor parte del tráfico). Los nombres de los inactivos llegan con su nivel, clase y desde cuándo (a petición y en segundo plano, ahora una hermandad cada 2 minutos) y la guardia pregunta. En la prueba de 20 hermandades el tráfico total del addon bajó de unos 4.000 a unos 1.000 mensajes por minuto entre todos, y la cola más larga, de unos 2.000 a unos 300. Con 6 hermandades o menos, todo sigue como antes.
- **Huecos que se cierran solos:** cada enlace anuncia en el canal, junto a sus ayudantes, la huella de su lista de conectados. Si la copia que tienes no coincide dos avisos seguidos (unos 10 minutos), se pide a tu hermandad; si sigue sin coincidir, quien se encarga de esa hermandad la pide entera a su enlace. Además, si al que le tocaba mandarla también le falta, la manda el enlace. En la prueba: 100 % de las listas de conectados a los 5 minutos de terminar de entrar todos.
- Los inactivos de una hermandad los manda cualquiera de sus ayudantes, no solo su enlace.

### Novedades 20.0.5

- **Ver miles de inactivos sin tirones:** con **Inactivos**, la lista ya no se rehace cada vez que alguien se conecta o cambia de zona (solo cuando cambian los inactivos). Con **Todos**, los desconectados se ordenan una vez y se guardan; cada vez solo se vuelven a ordenar los conectados. En la prueba con 20.000 personas: de 300 ms a menos de 40 ms por actualización.
- **Menos peticiones de listas completas:** las vuelve a pedir solo quien se encarga de esa hermandad (antes, cada compañero que no la tenía).

### Novedades 20.0.4

- **Prioridades al mandar:** los mensajes ocultos del addon salen en cuatro colas, siempre por este orden:
  1. **el chat**: silencios, vetos, chat lento, canales, mensaje fijado, emoticonos (el chat en sí va por el canal y nunca espera);
  2. **los conectados**: saludos, contactos y listas de conectados de las otras hermandades;
  3. **las fichas** (profesiones, rol...) y los inactivos que alguien está mirando en ese momento;
  4. **lo de segundo plano**: inactivos que trae el enlace sin que nadie los pida y listas completas de miembros.

### Novedades 20.0.3

- **Inactivos a petición:** la lista empieza siempre en **Activos** y entonces no se gasta nada en los desconectados de las otras hermandades. Al elegir **Inactivos** o **Todos** se cargan los de **todas** las hermandades; lo que aún falte se pide en ese momento (abajo pone "cargando inactivos..." mientras llega). La lista se refresca con calma (cada 8 s) cuando son miles.
- **En segundo plano, sin que nadie lo note:** el enlace de cada hermandad va trayendo los inactivos de las otras, uno cada 5 minutos y solo si no tiene nada urgente que mandar. Le llegan a toda su hermandad y se guardan 12 horas, así que cuando alguien elige Inactivos casi siempre ya están.
- Los inactivos salen aunque la lista completa de miembros de esa hermandad aún no haya llegado.
- **Mejor elección del enlace:** además de ser maestro u oficial, el ping y los fotogramas, el addon mide ahora:
  - una **prueba de velocidad** del ordenador (cuánto tarda en hacer un trabajo como el del addon; se repite cada 10 minutos);
  - **lo que tardan en volver tus propios mensajes** por la hermandad (la conexión real con el servidor);
  - si **lleva un rato conectado** (más de 10 minutos);
  - si está **en una banda, un campo de batalla o una arena, o ausente**: entonces deja de ser buen enlace y lo hace otro al momento (al salir vuelve a contar).
  Cada uno solo comparte su nota, nada de su ordenador. **El que ya es enlace tiene un pequeño margen**: solo se cambia si hay alguien claramente mejor (así no se cambia cada poco).

### Novedades 20.0.2

- **Activos / Inactivos / Todos:** la casilla **Inactivos** de Miembros (y de la lista aparte) es ahora un desplegable: **Activos** (solo conectados, lo normal), **Inactivos** (solo desconectados) o **Todos**.
- **Quién hace de enlace:** antes era el primero por orden alfabético. Ahora va primero **el maestro y los oficiales**, siempre que su conexión vaya bien (ping por debajo de 500 ms y el juego sin ir a tirones); entre iguales, el de **mejor ping** y **más fotogramas por segundo** (el ordenador menos cargado). Se mide con una media, así que un tirón de lag no cambia el enlace. **Conviene que todos actualicen a la vez**: con versiones mezcladas, cada una podría elegir un enlace distinto (funciona, pero con más mensajes).
- Con 20 hermandades, **Inactivos** muestra los desconectados de tu hermandad y de las que elijas en el filtro **Hermandad** (o al buscar un nombre).

### Novedades 20.0.1

- **Listas de conectados más pequeñas:** la zona de cada jugador va como un código corto ("#1") que se explica una sola vez por lista. Ocupan bastante menos y se llenan antes.
- **Altas y bajas al momento:** cuando el juego avisa en el chat de que alguien **se une, se va o es expulsado** de la hermandad (o al ver el cambio en la lista de la hermandad), el enlace manda solo ese cambio a las demás hermandades (`+nombre` / `-nombre`), en vez de la lista entera de 1.000 nombres. Si son muchos cambios a la vez, se avisa y se pide la lista entera como antes.
- **Listas a medias:** si una lista de conectados o de miembros llega incompleta (se perdió algún trozo), se pide enseguida a los compañeros de tu hermandad en vez de esperar a la siguiente lista entera (hasta 30 minutos).
- **Guardia:** cuenta como miembros a los conectados de las otras hermandades aunque su lista completa aún no haya llegado o no tenga todavía a alguien que acaba de entrar. Y, como siempre, **no echa a nadie mientras falte la lista de alguna hermandad**.
- **Oficiales:** con más de 6 hermandades, el recuadro **Estado** muestra un resumen (cuántas tienen contacto, lista de conectados y lista completa, y cuáles faltan); el detalle de cada una sale con `/gu estado`. La ventana **Hermandades** enseña 8 y el resto con la rueda del ratón.
- Menos saludos repetidos entre addons.

## Novedades 4.11.21

- **Chat lento también en tu hermandad:** si alguien escribe con `/g` antes de tiempo, el juego manda el mensaje igualmente (un addon no lo puede parar), pero ahora **los de su hermandad que tienen el addon no lo ven**, ni en el panel ni en su chat del juego. Solo lo verían quienes no tienen el addon. A las otras hermandades nunca llega. Los maestros y oficiales siguen sin límite.

## Novedades 4.11.20

- **Errores guardados y con contraseña:** se quita el botón **Informar fallo**. Cada addon guarda sus errores (los 10 últimos, también al cerrar el juego) y **no los manda a nadie**. Quien sepa la **contraseña del chat unido** (la de `GU:c:Canal:clave`) puede pedírselos a todos con `/gu errores pedir contraseña`: cada addon que tenga errores se los susurra (oculto) en el siguiente medio minuto, también de las otras hermandades. Llegan a `/gu errores`, se quedan guardados (hasta 200) y se borran con `/gu errores borrar`. La contraseña no viaja por el chat: va una firma hecha con ella.

## Novedades 4.11.18

- **Cabecera de Miembros:** al pasar el ratón por una columna se ilumina de arriba abajo del recuadro, con un degradado dorado suave que se apaga hacia abajo y una raya dorada fina en la base, solo del ancho del texto.

## Novedades 4.11.17

- **Cabecera de Miembros:** ya no sale la ventana de ayuda al pasar el ratón. Tiene separadores finos entre columnas, un brillo suave arriba y la columna se ilumina al pasar el ratón.

## Novedades 4.11.16

- **Cabecera de Miembros más cuidada:** va dentro de un recuadro como las tarjetas, con **Nombre, Lugar, Hermandad, Rango y Estado** (se quita Nivel). La columna por la que se ordena sale en amarillo con una flechita pequeña (abajo: normal; arriba: al revés) y una raya fina debajo.

## Novedades 4.11.15

- **Cabecera de columnas en Miembros:** encima de la lista salen **Nombre, Nivel, Lugar, Hermandad, Rango y Estado**. Pulsa una para ordenar por ella (sale en amarillo con una flecha); otra vez, al revés. El botón Ordenar sigue funcionando igual.
- **Nombre de hermandad igual para todos:** antes los conectados podían salir con la etiqueta (DEMO) y los desconectados con el nombre (Hermandad Demo). Ahora la lista se rehace al cambiar la configuración.

## Novedades 4.11.14

- **Registro y chat sin huecos:** las líneas se miden dentro de la propia ventana (contando su escala y su letra), así que con la letra pequeña ya no queda espacio de más entre registros o mensajes.
- **Letra por ventana:** el clic derecho en una pestaña (Tamaño de letra / Tipo de letra) cambia solo esa ventana. En el panel cambia el chat y el registro del panel; en el chat aparte, solo el chat aparte. Si el chat aparte nunca se ha cambiado, usa la misma letra que el panel.

## Novedades 4.11.13

- **Chat y registro:** al bajar el tamaño de la letra ya no quedan huecos entre mensajes (se seguía midiendo con el tamaño de antes).

## Novedades 4.11.12

- **Chat lento:** si están elegidos todos los canales (aunque sea uno a uno en el desplegable), el aviso y la línea de estado dicen "todos los canales" en vez de nombrarlos uno por uno.
- **Chat del panel:** los mensajes largos (como el aviso del chat lento) ya no se montan encima del mensaje de debajo.

## Novedades 4.11.11

- **Enter según dónde hayas pinchado:** si lo último que has pulsado es el addon (el panel, el chat flotante o sus menús), Enter abre la caja de escribir del addon. Si has pinchado fuera (el mundo, el chat del juego, otra ventana), Enter abre el chat normal del juego. Al abrir el panel, el addon cuenta como pulsado.

## Novedades 4.11.10

- **Chat lento:** el desplegable para elegir chats se llama **Canales** y se cierra al volver a pulsarlo. Debajo se ve lo que hay puesto: "Activo: cada 10 segundos · Canales: todos" (o los chats elegidos), o "Ahora: desactivado". Recuadro un poco más alto para que nada se salga ni se monte.

## Novedades 4.11.9

- El **Chat lento** está en la propia pestaña **Oficiales**, en un recuadro **encima de Intrusos** (sin abrir ninguna ventana): **Activado** y cada cuánto; **Todos los canales** y, al quitarlo, el desplegable para elegir los chats; y **Aplicar**. En Opciones quedan los botones **Canales**, **Rangos** y **Hermandades**.

## Novedades 4.11.8

- **Oficiales > Opciones** tiene cuatro botones: **Canales**, **Chat lento**, **Rangos** y **Hermandades**.
  - **Canales** abre una ventana solo con Buscar Grupo y los canales extra (añadir o quitar).
  - **Chat lento** abre su propia ventana: **Activado** y cada cuánto (**cada 5 segundos** ... **cada 1 minuto**, **cada 2 minutos**, **cada 5 minutos**); la casilla **Todos los canales** (marcada, vale para todos, también los que se creen después); si la quitas, se desbloquea un desplegable para elegir los chats (Hermandad, Buscar Grupo y cada canal extra); y **Aplicar**.
- **Clic derecho en una pestaña del chat** (maestros y oficiales): **Chat lento** para ese chat (en **Todo**, para todos los canales), o **Sin chat lento**. El tiempo es el mismo para todos los chats que lo tengan.
- **Avisos en el chat de la hermandad** (en el chat del juego y en el del panel, para todas las hermandades): cuando se pone o se quita el chat lento, cuando se silencia a alguien (y durante cuánto, con el motivo) y cuando se veta a alguien del chat.

## Novedades 4.11.7

- En **Oficiales > Opciones** hay tres botones: **Chat**, **Rangos** y **Hermandades**. **Chat** abre una ventana aparte con el **Chat lento** y los **Canales** (Buscar Grupo y canales extra). Así el recuadro de **Intrusos** vuelve a tener sitio.
- **Chat lento por canal:** en esa ventana, cada canal extra que añadáis sale con su propia casilla, para ponerle modo lento o no (además de Hermandad y Buscar Grupo).

## Novedades 4.11.6

- **Chat lento** tiene su propio recuadro en Oficiales (debajo de Opciones): **Activado** y cada cuánto en la primera línea, los chats en la segunda y **Aplicar** abajo. Después de aplicar, el botón queda en gris y pone **Aplicado** hasta que cambies algo; al lado se ve lo que hay puesto ahora.

## Novedades 4.11.5

- **Chat lento** en Oficiales > Opciones, más claro: casilla **Chat lento**, debajo cada cuánto (**cada 5 segundos**, **cada 10 segundos**... **cada 5 minutos**), los chats a los que afecta (**Hermandad**, **Buscar Grupo**, **Canales**) y el botón **Aplicar**. Hasta pulsar Aplicar no cambia nada para nadie.

## Novedades 4.11.4

- **Cola de envío:** en **Oficiales > Estado** se ve cuántos mensajes del addon tienes pendientes de enviar (listas, no el chat) y cuánto tardarán. Botón **Vaciar cola** y comandos `/gu cola` y `/gu cola vaciar`. Lo que estaba pendiente se vuelve a pedir y a mandar solo.
- **Modo lento** (en **Oficiales > Opciones**, o `/gu lento 30` y `/gu lento off`): cada jugador solo puede escribir **un mensaje cada X tiempo** (5 s, 10 s, 15 s, 30 s, 1 min, 2 min o 5 min) en los chats unidos.
  - En **Chats** se elige a cuáles afecta: Hermandad (la de todas), Buscar Grupo y canales extra.
  - Los **maestros y oficiales no tienen límite**, y el chat de oficiales nunca tiene modo lento.
  - Si escribes desde el panel antes de tiempo, te avisa de cuánto falta y lo escrito se queda en la caja.
  - Si escribes en el /g del juego, tu hermandad lo ve (eso no lo puede impedir un addon), pero no pasa a las demás hermandades.
  - Lo que llega demasiado seguido de alguien (por ejemplo, de alguien sin el addon) tampoco se muestra.
  - Lo ven todas las hermandades, sale un aviso en el chat y queda en el registro.
- **Arreglos para miembros nuevos** (salían en las pruebas de comunidades grandes):
  - quien entra en una hermandad ya no espera a la siguiente lista completa para ver a los conectados de las otras: la pide él;
  - los avisos de los oficiales le llegan aunque aún no tenga las listas;
  - si el enlace de una hermandad es alguien recién llegado, las listas se siguen actualizando bien.

## Novedades 4.11.3

- **Probado en simulación con 4 hermandades de 1.000 miembros** (1.600 conectados) **y 2.000 personas con el addon**: todas las hermandades se encuentran entre sí, todos reciben las listas y el chat, y nadie pasa del límite de mensajes del juego.
- **Varios reparten el trabajo:** cada hermandad tiene un enlace y de 4 a 8 ayudantes. Lo que llega de otras hermandades se reparte entre ellos, y el envío de la lista de conectados a las demás hermandades también.
- **La lista de conectados** de otras hermandades llega entera cada 30 minutos y, entre medias, solo los cambios (quién entra, sale o cambia de nivel, rango o estado). Si a alguien no le cuadra, pide la lista entera.
- **Saludos:** en hermandades con cientos de usuarios del addon, solo los primeros (posibles enlaces y ayudantes) saludan a menudo; el resto, cada 15 minutos.
- **Arreglos que solo salían con muchas hermandades o mucha gente:**
  - hermandades que no llegaban a conocerse entre sí;
  - listas que no se completaban si llegaban dos a la vez;
  - listas de miembros que se mandaban de más.
- **Panel:** la lista de todos se guarda por partes y solo se reordena cuando cambia; con 4.000 miembros repintar cuesta pocos milisegundos.

## Novedades 4.11.2

- **Preparado para comunidades grandes** (probado en simulación con 3 hermandades de 430 miembros, unas 1.300 personas):
  - Los saludos entre los que tienen el addon se espacian solos según el tamaño de la hermandad (de cada 2 minutos a cada 5).
  - La lista de conectados que se manda a las otras hermandades solo se manda si ha cambiado, y más despacio cuanto más larga es.
  - Preguntas a toda la hermandad (contactos, canal): en hermandades grandes contestan solo unos pocos, no todos.
  - El panel solo vuelve a ordenar la lista cuando cambia de verdad, y ordenar es más rápido.

## Novedades 4.11.1

- **El mapa se ha quitado de momento** para que el addon sea más ligero: ya no se mandan posiciones ni se pintan puntos en el mapa del mundo ni en el minimapa. Desaparecen Configuración > Mapa, el modo ahorro de FPS (era para el mapa) y la casilla de los oficiales "Mapa de otras hermandades". `/gu mapa` avisa de que está desactivado.
- El mapa **está guardado** (con sus librerías) para volver a ponerlo más adelante sin tener que rehacerlo.

## Novedades 4.11

- **Código ordenado por dentro** (no cambia nada de lo que se ve): el panel, que estaba en un solo archivo de más de 5.000 líneas, ahora está repartido por partes. También se ha quitado código que ya no se usaba.

### Cómo está organizado el addon

| Archivo | Qué hace |
|---|---|
| Core.lua | Arranque, ajustes guardados, idioma, comandos /gu y registro de errores |
| Comm.lua, Lists.lua | Mensajes entre jugadores y listas de miembros de cada hermandad |
| Channel.lua, Channels.lua | Canal oculto, mensajes, emoticonos y menciones |
| Community.lua, Config.lua, Ranks.lua | Comunidad, hermandades, colores, emoticonos de la comunidad y rangos |
| Guard.lua | Guardia contra intrusos |
| Social.lua, Notes.lua, Pinned.lua, Audit.lua | Perfiles, profesiones, recetas, notas, mensaje fijado y registro |
| (Map.lua) | Mapa del mundo y minimapa: guardado aparte de momento (ver Novedades 4.11.1) |
| UI.lua | Base del panel: temas, botones, menús, fichas y ventana principal |
| UIMembers.lua | Pestaña Miembros: lista, filtros, favoritos y lista aparte |
| UIChat.lua | Chats, mensaje fijado y ventana de chat aparte |
| UIOfficers.lua | Pestaña Oficiales: chat, registro, opciones, notas y rangos |
| UIInfo.lua | Información de un jugador, silenciar y recetas |
| UIWindows.lua | Configuración, novedades, hermandades, informar fallo y otras ventanas |
| Popup.lua, Minimap.lua, ChatTabs.lua, Test.lua | Ventanas de confirmación, botón del minimapa, pestañas del chat del juego y modo prueba |

## Novedades 4.10.12

- Cuando el maestro **añade emoticonos**, a todos les sale un aviso en el chat: "Nombre ha añadido los emoticonos: [icono] :codigo: ...". Si llegan varios seguidos, salen en un solo mensaje. Al entrar al juego no se avisa de los que ya existían.

## Novedades 4.10.11

- Clic derecho en las pestañas: **Tamaño de letra** ya no lleva el número (se ve marcado al abrir el desplegable). La opción de Todo se llama **Chats que se muestran** y cabe en una línea.

## Novedades 4.10.10

- **Filtros:** en **Hermandad**, **Clase**, **Rol** y **Profesión** (igual que en Rango) se pueden marcar varias opciones a la vez; "Todas"/"Todos" quita la selección. Salen los que cumplan cualquiera de las marcadas en cada filtro (p. ej. Guerrero o Paladín) y todos los filtros a la vez.

## Novedades 4.10.9

- Al pulsar **Copiar** ya no sale el aviso "Pulsa Ctrl+C para copiar" (lo seleccionado queda marcado; se copia con Ctrl+C).

## Novedades 4.10.8

- Al entrar ya **no se abre la ventana de novedades**: solo sale una línea en el chat. Se pueden ver en Configuración > Novedades.
- **Clic derecho > Copiar** ya no abre otra ventana ni quita lo seleccionado: lo deja marcado y aparece "Pulsa Ctrl+C para copiar". Si no habías elegido nada, elige todos los mensajes del chat. (El juego no deja a los addons copiar directamente al portapapeles: el Ctrl+C lo tiene que pulsar el jugador.)

## Novedades 4.10.7

- **Importar emoticonos** es solo para el **maestro** de la hermandad (los demás ya no ven el botón, y lo que mande alguien que no sea maestro no se acepta). La ventana sale por delante de Configuración > Chat.
- Clic derecho en la pestaña **Todo**: **Chats que se ven en "Todo"** abre un desplegable con una casilla por chat (Hermandad, Buscar Grupo, canales extra) para dejarlos o quitarlos.

## Novedades 4.10.6

- **Chat:** arreglada la franja gris que salía a la izquierda del chat.
- Al elegir varios mensajes arrastrando, se marcan **solo las letras** (como una selección normal), no los huecos en blanco.
- **Clic derecho > Copiar** (una sola opción): copia lo que tengas seleccionado (o todo el chat si no hay nada) y lo seleccionado **sigue marcado**, para que veas qué has copiado. Se quita al volver a hacer clic en el chat o al cambiar de pestaña.

## Novedades 4.10.5

- **Chat:** si arrastras desde un mensaje hacia arriba o hacia abajo, se eligen los mensajes enteros por los que pasas (si sales del chat, se desplaza solo). Se marcan en azul y se copian con **Ctrl+C** (solo el texto, sin nombres). Dentro de un mismo mensaje se puede elegir un trozo, como antes.
- **Clic derecho** ya no quita lo seleccionado: el menú tiene **Copiar selección** y **Copiar todo**.

## Novedades 4.10.4

- Botón **Informar fallo** arriba a la derecha, junto a la versión: escribes qué ha pasado y el addon prepara un informe (versión, personaje, hermandad, modo, FPS y errores guardados) para copiarlo con Ctrl+C y mandárselo a Sadance.

## Novedades 4.10.3

- Los menús de **Ordenar** y **Filtros** miden exactamente lo mismo que su botón (teniendo en cuenta la escala del panel).
- El botón "Pestañas en el juego" ahora se llama **Copiar pestañas en el chat** y es oscuro.

## Novedades 4.10.2

- **Chat rehecho:** cada mensaje va en su propia fila. A la izquierda la hora, el canal, la hermandad y el nombre (no se pueden seleccionar; doble clic en el nombre susurra, clic derecho abre su menú) y a la derecha el mensaje, que es lo único que se puede seleccionar y copiar. Si un mensaje ocupa varias líneas, siguen alineadas con el mensaje. Además solo se dibujan los mensajes que se ven, así que pesa menos.
- **Configuración > Chat:** el tamaño de letra es una barra (como en el mapa) y "Fuente:" va fuera del botón. Para maestros y oficiales pone "Importar emoticonos" junto al botón Importar.
- **Ordenar y Filtros:** los menús miden lo mismo que su botón.
- **Lista estrecha:** la hermandad vuelve a ser un punto de color (con el rango al lado) y salen las profesiones.
- **Pestaña Miembros:** la hermandad más a la izquierda y el rango a su derecha, en la misma línea.
- Mapa > Configuración: la casilla del borde ya no se sale del recuadro.

## Novedades 4.10.1

- **Chat:** al arrastrar para copiar solo se selecciona el **mensaje**; la hora, la hermandad y el nombre no (el nombre se sigue pudiendo pulsar: doble clic susurra, clic derecho abre su menú). Al cambiar de pestaña se quita lo seleccionado.
- **Filtros > Rango:** ya no está "Oficiales"; se pueden marcar **varios rangos** a la vez (por ejemplo Maestro y Oficial).
- **Ya no hay botón Mapa** arriba: todo está en **Configuración > Mapa** (Mostrar, Puntos e Información). "Forma:" va fuera del botón, **Tamaño** y **Brillo** son barras con el valor en el título y las puntas encima. Apagar a los que llevan rato sin noticias ya no es una opción: se hace siempre.
- Menús de **Ordenar** y **Filtros** más pequeños. Botón de minimizar la lista cuadrado; con la lista minimizada, arriba hay un botón para volver a abrirla.
- Punto de la hermandad más pequeño en la lista; en la lista estrecha sale la hermandad y luego el rango; la zona va más cerca del nombre.
- Colores de hermandad: sin "El de siempre". Importar emoticonos trae una línea de ejemplo. Icono de emoticonos centrado. Información: sin correo de momento.

## Novedades 4.10

- **Configuración** (arriba a la izquierda, donde estaba Apariencia): **Mapa**, **Chat**, **Apariencia** (temas y **Tamaño de avisos**), **Idioma**, **Ahorro automático si bajan los FPS**, **Novedades** e **Información** (versión y autor).
- **Configuración > Chat:** tamaño y tipo de letra (para todos los chats del addon), **Ver emoticonos** y **Ver los emoticonos de la comunidad**. Un maestro u oficial puede **Importar** emoticonos propios (una línea por emoticono: `codigo=Interface\Icons\Nombre`) y llegan a todas las hermandades.
- **Clic derecho en una pestaña del chat:** Desacoplar (sale solo esa pestaña), tamaño y tipo de letra. En la ventana desacoplada: Eliminar ventana. El **registro de oficiales** también se puede desacoplar y cambiar de letra; los títulos de cada día van centrados.
- **Intro** con el panel abierto en General: escribe directamente en el chat del addon.
- Colores de hermandad: opción **Personalizado...** con la rueda de colores del juego. En la lista, un punto de color; el icono de oficial son dos espadas cruzadas (también en el chat).
- Los menús Ordenar y Filtros tienen el ancho del botón. La columna de hermandad ya no pisa las profesiones.
- **Recetas:** si cierras la ventana ya no vuelve a abrirse sola, y el aviso sale dentro de la ventana una sola vez.
- **Intrusos:** Echar / Vetar primero recarga las listas y vuelve a comprobar (no se echa a quien acaba de entrar en una hermandad).
- **Rendimiento:** la lista de miembros se calcula una vez y se reutiliza, se repinta como mucho una vez por segundo, y el mapa no repinta los puntos con el mapa cerrado. Si los FPS bajan mucho un rato, el **modo ahorro** deja de pintar a las otras hermandades y actualiza menos (vuelve solo).
- Tamaño **Muy pequeño** para los puntos del mapa. Icono del addon en la lista de addons.

## Novedades 4.9.2

- Pulsar **Intro** en el chat sin haber escrito nada deja de escribir (el teclado vuelve al juego).
- La **lista desacoplada** tiene **Ordenar**, **Filtros** e **Inactivos**, compartidos con la lista del panel (lo que cambies en una vale para las dos).
- Oficiales: en lugar de la casilla, un botón oscuro **Añadir al General** / **Quitar del General** para la pestaña del chat de oficiales en General.
- Los botones de letra (aA) y de emoticonos tienen el dibujo centrado; el botón de minimizar la lista es más ancho.

## Novedades 4.9.1

- Lista de miembros: los títulos van centrados entre dos rayas: "---- Favoritos ----" y "---- Miembros ----".
- La pestaña Oficiales se abre siempre en el **chat de oficiales**; para ver el registro hay que pinchar en él.
- Clic derecho en la pestaña **Todo**: ahora es un menú pequeño con casillas (Hermandad, Buscar Grupo, canales extra).
- **Mensajes de un jugador:** el botón se llama **Recientes** y enseña lo que has buscado en esta sesión (se borra al recargar o salir). El buscador tiene la X roja.

## Novedades 4.9

- **Mapa del mundo:** botón redondo arriba a la derecha para ocultar o enseñar a los compañeros (es lo mismo que "Usar el mapa").
- **Puntos del mapa:** por defecto son **pequeños** y **sin borde** de color de hermandad. Si se elige el borde, ahora es de 1 píxel.
- **Mapa > Configuración:** "Transparencia" ahora es una barra de **Brillo** (a la derecha, más brillo). "Apagar a los que llevan rato sin noticias" es una casilla (Sí / No).
- **Colores de las hermandades:** en Oficiales > Opciones > **Hermandades**, cada hermandad tiene un cuadradito de color; al pulsarlo se elige otro color (o "El de siempre"). Lo cambia un maestro u oficial y lo ven todos (chat, lista y mapa). Queda en el registro.

## Novedades 4.8

- **Clic derecho en las pestañas del chat de General:** en **Oficiales**, "Quitar de General"; en **Todo**, una ventanita para elegir qué chats salen en "Todo" (Hermandad, Buscar Grupo y los canales extra; el de oficiales nunca).
- **Copiar:** clic derecho en cualquier chat (o en el registro de oficiales) > Copiar. También se puede seleccionar con el ratón y Ctrl+C.
- **Oficiales:** primero la pestaña **Chat de oficiales** y luego **Registro de oficiales**. Ya no hay botón Copiar.
- **Mapa:** el botón **Configuración** está arriba a la derecha de su menú.
- **Lista de miembros:** los favoritos van **separados** del resto (con su título); la casilla "Desconectados" se llama **Inactivos**; el botón de minimizar es más grande y está más arriba.

## Novedades 4.7

- **Mapa:** los puntos y los bordes usan colores más vivos (antes salían oscuros), y por defecto se apagan menos cuando alguien lleva rato sin dar señales.
- **Mapa:** si marcas "No compartir mi posición", tampoco ves a los demás.
- **Favoritos** (personales): estrella arriba a la derecha de cada tarjeta, o clic derecho > Añadir a favoritos. Los favoritos salen los primeros de la lista, y en Filtros está **Solo favoritos**. Solo los ves tú.
- **Información** del jugador: debajo del rol sale la **segunda especialización**. Se envía junto a la primera ("Sombra/Sagrado"); con versiones viejas del addon se verá así, tal cual.

## Novedades 4.6

- **Pestañas: General, Miembros y Oficiales.** La pestaña Chat ya no está: el chat vive en General. Para buscar en él, la **lupa** de abajo (sale un buscador arriba a la derecha del chat).
- **Oficiales:** el registro y el **chat de oficiales** comparten sitio; se cambia con las dos pestañas de arriba ("Registro de oficiales" / "Chat de oficiales"). La casilla **También en General** quita o pone la pestaña Oficiales en el chat de General.
- El chat de oficiales **nunca sale en "Todo"**. Cuando llega un mensaje nuevo y no lo estás viendo, sus pestañas llevan un **puntito amarillo**.
- **Minimizar la lista** de General: botón arriba a la derecha de la lista. Se vuelve a abrir con la pestaña « de la derecha.
- Los **buscadores** tienen una **X roja**: borra lo escrito y deja de escribir.
- En la lista estrecha, después del nivel sale **dónde está** (aunque se corte). El botón de orden se llama **Ordenar** (en el menú, la opción elegida lleva ">").

## Novedades 4.5

- **Añadir hermandades con aprobación:** cuando un maestro u oficial invita a una hermandad, queda como propuesta hasta que la apruebe un maestro u oficial de **otra** hermandad (Oficiales > Opciones > Hermandades > Pendientes de aprobar). El que aprueba envía la invitación. Si la comunidad tiene una sola hermandad, se invita directamente.
- **Crear comunidad:** si tu hermandad no está en ninguna, el panel lo dice y el maestro tiene el botón **Crear comunidad**: nombre, etiqueta, canal y contraseña (ya vienen rellenos). El addon escribe la Información de hermandad y guarda el canal en la nota de oficial del maestro.
- **Mapa con menos tráfico:** cada uno manda su posición cada 4 s con poca gente y hasta cada 20 s con 300 o más conectados en la hermandad. Opción **Usar el mapa** para apagarlo del todo (no se pinta nada).
- **Contactos más rápidos:** si el enlace de una hermandad no tiene contacto en otra, pregunta a los suyos y contesta quien conozca a alguien.
- **Errores:** si algo falla, sale un aviso y `/gu errores` (o Apariencia > Copiar errores) abre el texto para copiarlo y mandarlo.
- **Novedades:** al actualizar sale una ventana con lo nuevo (también con `/gu novedades` o Apariencia > Novedades).
- **Versiones viejas:** Oficiales > Estado dice quién de tu hermandad tiene una versión vieja, y a los oficiales se les avisa al entrar.
- `/gu idioma` muestra los textos que se han visto sin traducir al inglés (para corregirlos).
- Arreglados: la ventana de copiar texto se creaba de nuevo cada vez; unas notas mal guardadas podían dar error al cargar.

## Prueba beta (antes de repartirlo a toda la comunidad)

1. Dos hermandades y unas 20–30 personas, durante una semana.
2. Dos oficiales con `/gu debug on`.
3. Cada día, comprobar: el chat llega a las dos hermandades; la lista de miembros está completa; `/gu estado` dice "Canal: conectado"; el mapa enseña a los de la otra hermandad; Oficiales > Estado no tiene avisos raros.
4. Probar a propósito: cambiar la contraseña (nota de oficial del maestro), vetar y readmitir a alguien, invitar una tercera hermandad (con aprobación), quitarla.
5. Con mucha gente conectada, mirar los FPS con el mapa activado y con "Usar el mapa" apagado.
6. Quien vea un error: `/gu errores`, copiar y mandarlo.

## Novedades 4.4

- Lista de miembros: abajo, **Desacoplar** a la izquierda e **Invitar** (más grande) a la derecha. **Seleccionar todos** solo aparece cuando hay 2 o más seleccionados.
- Oficiales: **Estado** solo ocupa lo que necesita su texto y el **registro de oficiales** es más grande, separado por días (Hoy, Ayer, Lunes 2 de noviembre...).
- **Intrusos** (antes "Guardia: intrusos") ocupa más sitio; si hay más de los que caben, el botón **Ver lista** abre una ventana con todos, con Echar y Vetar. "Mensajes de un jugador" es más pequeño.

## Novedades 4.3

- La lista de miembros llega hasta abajo. Se puede estrechar más: muy estrecha, la hermandad pasa a ser un cuadradito de su color, se ve el nivel ("Nv 60") y los desconectados pone "Desc.".
- Fondo de detrás del panel (el que comparten el chat y la lista) más oscuro.
- Pestañas del chat de General: si no caben, primero se esconde "Pestañas chat" y luego se usan nombres cortos (Todo, Herm., Grupo, Ofic.).
- Mapa > Configuración: "Forma" (icono de clase, icono de spec o punto con color de clase), "Información" (lo que sale al pasar el ratón) y una barra para elegir cuánto se apagan los que llevan rato sin noticias.
- Hermandades > Invitar: explicación de la etiqueta.

## Novedades 4.2

- **Idioma:** botón arriba a la derecha (English / Español). Por defecto, **inglés**; quien venía de We Love PvP sigue en español. Al cambiarlo pide recargar la interfaz.
- Los comandos también valen en inglés: `/gu status`, `/gu test`, `/gu tabs`, `/gu map`, `/gu list`... (los de español siguen funcionando).
- Lo que escribe cada uno (motivos, registro, mensaje fijado) se ve en el idioma en que se escribió.

## Novedades 4.1

- **Mapa > Configuración...**: icono de la clase, de la rama de talentos o un círculo del color de clase; tamaño; transparencia; borde del color de la hermandad; más apagados los que llevan rato sin noticias; y qué sale al pasar el ratón (hermandad, nivel, clase, rama, vida, rango, zona).
- Botones de arriba en oscuro; banda oscura detrás de las pestañas grandes.
- "Invitar" está abajo a la derecha de la lista de miembros.
- La lista de miembros usa todo el alto (más tarjetas) y no se puede estrechar tanto como para cortar el texto.
- Arreglados textos montados: el nombre y la hermandad de arriba con el título, las opciones de Oficiales con sus botones, y las pestañas del chat de General con "Pestañas chat" (si no caben, ese botón se esconde; sigue en `/gu pestañas`).

## Novedades 4.0

- El addon se llama **Guild Union** (antes We Love PvP), para que lo pueda usar cualquier comunidad de hermandades. Pasa tus ajustes solo (ver Instalación).
- El título sale del nombre de la hermandad principal (o de la línea `GU:t:`).
- **Hermandades** en Oficiales > Opciones: invitar hermandades nuevas (entran solas) y quitarlas.
- La ventana de un enlace web sale donde haces clic y se cierra al pulsar fuera o cualquier tecla.

## Novedades 3.6.4

- Lista de miembros: casilla **Desconectados** en lugar del desplegable "Todos" (sin marcar, solo conectados). **Desacoplar** ahora está abajo, en el centro. El orden "Más tiempo fuera" se llama **Inactividad** y es la última opción. Con la lista muy estrecha se quitan los iconos de profesiones.

## Novedades 3.6

- **Arreglado el aviso al salir del juego** ("el addon ha intentado una acción bloqueada" / pedía desactivarlo). Las ventanas de confirmación del addon (rangos, echar, vetar, invitar, mensaje fijado, canales, apariencia) son ahora propias y ya no tocan las del juego.
- Nuevas pestañas del chat (Todo, Hermandad, Buscar Grupo, Oficiales y canales extra), al estilo de las de la ventana de macros: con el mismo marco marrón que el cuadro del chat; la elegida se une al cuadro y las demás quedan detrás, con letra dorada.
- **Enlaces web clicables** en el chat y en el mensaje fijado (https://... o www...). Al hacer clic sale una ventana con el enlace ya seleccionado: Ctrl+C y lo pegas en el navegador (el juego no puede abrir el navegador por sí mismo).
- Menú del Mapa con casillas de verdad (se pueden marcar varias sin que se cierre).
- La explicación del botón Mapa sale a su derecha y ya no lo tapa.

## Mapa (nuevo en 3.5)

En el **mapa del mundo** (y en el minimapa) salen los conectados de **todas las hermandades unidas**, no solo de la tuya. Cada punto es el icono de su clase con un borde del color de su hermandad; al pasar el ratón ves nombre, hermandad, nivel y vida.

- **Tu hermandad** se mueve casi al momento: cada uno manda su posición cada pocos segundos mientras se mueve.
- **Las otras hermandades** se actualizan cada 15 segundos: el enlace de cada hermandad junta las posiciones de los suyos y las manda en un paquete al contacto de las demás, que las pasa a su hermandad. Con muchísimos conectados el paquete es más grande y va algo más despacio (el juego deja mandar más o menos un mensaje por segundo).
- Solo se aceptan paquetes de alguien que está en la lista de esa hermandad.
- Si en tu hermandad hay gente con el addon **GuildMap**, también salen en el mapa.
- No salen los de tu grupo (el juego ya los pinta) ni nadie dentro de mazmorras.
- Botón **Mapa** (arriba, junto a Apariencia), con casillas: ver a mi hermandad, ver a las otras hermandades, mostrar también en el minimapa y **no compartir mi posición**.
- **Oficiales > Opciones > "Mapa: ver a las otras hermandades (todos)"**: si hay lag, cualquier maestro u oficial lo desactiva y nadie de ninguna hermandad ve a los de las otras (cada uno sigue viendo a la suya). Queda en el registro.

El mapa usa la librería HereBeDragons, que va **dentro del addon** (carpeta `Libs`, licencia BSD, ver `Libs/LICENCIAS.txt`): no hay que instalar nada aparte. Con `/gu mapa` compruebas que está cargada, tu posición y cuántos se ven.

## Novedades 2.9.5

- El chat desacoplado tiene botón de letra (tamaño y tipo).
- "+ Añadir a la hermandad" va centrado debajo de la lista; "Seleccionar" a la izquierda.
- Los canales extra salen también como pestaña en el chat de General.
- En el clic derecho, "Información" es la última opción antes de las de oficial.

## Novedades 2.9.4

- (Las pestañas del chat del panel vuelven a ser botones rojos desde la 2.9.8.)
- En la ficha al pasar el ratón, las profesiones van una debajo de otra con su nivel al lado.
- La ventana de Información muestra también las notas (pública y privada).
- **Seleccionar varios:** Ctrl+clic añade o quita, Mayús+clic coge un tramo, y el botón **Seleccionar todos** (debajo de la lista) los marca a todos. Con varios marcados, clic derecho para las acciones.
- **Invitar** a la hermandad: botón arriba (junto a la versión). Debajo de la lista está **Desacoplar** (la lista en una ventana aparte).

## Novedades 2.9.3

- Arriba, en vez del recuadro grande, una sola línea: "2 Hermandades | 21 Miembros | 9 Conectados" (pasa el ratón para ver cada hermandad).
- Los menús del clic derecho se cierran al hacer clic en cualquier otro sitio.
- **Emoticonos con caras**: escribe `:)` `:D` `xD` `;)` `:P` `:(` `:'(` `:O` `:@` `B)` `<3` o elígelos con el botón de la carita. Los ve quien tiene el addon; el resto ve el texto.
- Filtro por **rol** (tanque, sanador, DPS) en Filtros.
- "Lista aparte" ahora se llama **Desacoplar** (arriba de la lista). **+ Invitar a la hermandad** está debajo de la lista. Para marcar a varios, botón **Seleccionar** debajo de la lista.
- **Desacoplar** el chat también desde General. El chat desacoplado tiene pestañas como las del chat del juego, encima de la ventana: arrastrándolas se mueve. Ya no se descoloca el texto al cambiarle el tamaño.
- "Buscar Grupo (LFG)" ahora es **Buscar Grupo**, y aparece en Oficiales > Canales para quitarlo o volver a ponerlo (queda en el registro).
- Los botones de Oficiales > Estado explican lo que hacen al pasar el ratón.

## Novedades 2.9

- **Chat aparte** (botón en Chat o `/gu chat`): ventana pequeña con Hermandad, Buscar Grupo (LFG) y Oficiales, que se mueve y se agranda. Se queda abierta entre sesiones.
- En el chat: pestañas debajo del mensaje fijado, **buscar en el chat**, botón de **letra** (icono "Aa": tamaño y tipo de letra) y **emoticonos** ({estrella}, {calavera}...).
- **Mensajes de un jugador > [ir al chat]**: abre el chat en ese mensaje para ver la conversación ("Volver al final" para regresar).
- Lista sin la barra de botones de abajo: buscador, **Lista aparte** e **+ Invitar** (a la hermandad) en la propia lista; Estado, Orden y **Filtros** (hermandad, rango, clase y **profesión**).
- **Selección múltiple**: Ctrl+clic añade o quita, Mayús+clic coge un tramo, "Todos". Clic derecho sobre los seleccionados: invitar al grupo a todos (pasa a banda si hacen falta más de 5), cambiar el rango a todos, silenciar o desilenciar a todos.
- Menú del clic derecho con la sección **Opciones de oficial** separada.
- Ficha al pasar el ratón más clara: nombre y estado; hermandad, rango y profesiones; nivel y clase; zona; y las notas en recuadros.
- **Oficiales**: botones "?" con la explicación de cada apartado y tarjeta **Canales** para crear o quitar canales extra (quedan en el registro). En Estado sale el número de cada canal.
- Apariencias: Por defecto, **Smooth** y Moderna.
- La lista aparte ya no se abre sola al entrar.

## Uso

- Escribe en `/g` como siempre: lo ven todas las hermandades.
- `/gu` o el botón del minimapa abre el panel, que tiene cuatro pestañas: General (lista y chat), Miembros (solo la lista, a todo el ancho), Chat y Oficiales. Con clic derecho en el botón se abre directamente Oficiales. El botón se mueve arrastrándolo y se oculta con `/gu minimapa off`.
- **General:** a la izquierda un chat pequeño (con las mismas pestañas que la pestaña Chat) y a la derecha la lista. **Miembros:** solo la lista, a todo el ancho, con una columna de zona (o cuánto tiempo lleva desconectado).
- **La lista** va en tarjetas con nombre (color de su clase), icono de clase, nivel, zona, hermandad, rango, iconos de sus profesiones principales y estado: punto verde conectado, **amarillo ausente** (AFK) y gris desconectado. Primero salen los conectados, luego los ausentes y al final los desconectados. De los desconectados se ve el nivel, la clase y "Desconectado hace 3 días". Por defecto solo salen los conectados; marca la casilla **Desconectados** (arriba a la derecha) para ver también a los desconectados. Filtros por hermandad, rango, clase, rol y profesión, y orden (la última opción, **"Inactividad"**, pone primero a los que llevan más tiempo sin entrar). Si haces la lista muy estrecha, se quitan los iconos de profesiones para que no se monte el texto. Abajo, la barra de acciones del seleccionado: Susurrar, Invitar, Info, Mensajes, Nota, Ascender, Degradar y Rango.
- **Información** (clic derecho > Información o botón "Info"): ventana pequeña con raza y clase, nivel, dónde está, su **rol** (tanque, sanador o DPS, según sus talentos) y sus **profesiones** con icono y nivel. En las profesiones con recetas hay un botón **"Ver recetas"** que pide la lista al jugador (tiene que estar conectado con el addon y haber abierto alguna vez su ventana de esa profesión; la lista se guarda para verla luego). Puedes cambiar tu rol con `/gu rol tanque|sanador|dps|auto`.
- **Silenciar** (maestro y oficiales): clic derecho > "Silenciar en el chat..." y eliges 2 minutos, 10 minutos, 1 hora, para siempre u otro tiempo escribiendo el número. El silenciado no puede escribir en el chat de la comunidad y, para quien tiene el addon, tampoco se le ve en el /g. Si ya está silenciado, en el menú sale "Desilenciar". Queda en el registro de oficiales.
- **Echar de la hermandad** (quien tenga permiso de expulsar): clic derecho > "Echar de la hermandad". Pide confirmación (Sí / No) y también lo saca del chat de la comunidad. Si es de otra hermandad, se envía la petición a sus oficiales, como con los rangos.
- **Menciones:** escribe `@Nombre` para hablarle a alguien. Al escribir `@` y las primeras letras sale una lista para elegir (Tab completa con el primero). Si te mencionan a ti, el mensaje sale marcado y resaltado en naranja, con un sonido, tanto en el panel como en el chat del juego.
- **Chat del panel:** selecciona cualquier trozo de texto arrastrando con el ratón y cópialo con Ctrl+C (cualquier otra tecla devuelve el teclado al juego). Los enlaces de objetos muestran su ficha al pasar el ratón. **Doble clic en un nombre** abre el susurro en el chat del juego; **clic derecho en un nombre**, el mismo menú que en la lista. El chat empieza desde abajo y, al enviar, la caja deja de escribir.
- **El chat se guarda:** al entrar, el addon pide a un compañero conectado lo que se escribió **mientras no estabas** y lo guarda en el chat del panel. Por defecto no se escribe en el chat del juego; si lo quieres ahí, activa Oficiales > Opciones > "Historial en el chat al entrar".
- **Apariencia:** botón arriba a la izquierda: Por defecto (madera y oro), Smooth (ventanas de Blizzard) y Moderna (plana y oscura). Se aplica al recargar la interfaz.
- **Mensaje fijado con enlaces:** al editarlo, Mayús+clic en un objeto lo enlaza; en el recuadro se puede pasar el ratón y hacer clic sobre él.
- **Chat:** pestañas Todo, Hermandad, Buscar grupo y Oficiales (esta última solo para quien puede ver el chat de oficiales). Se escribe en la pestaña elegida. "Buscar grupo" lo ven todas las hermandades y también se puede usar con `/buscargrupo mensaje`. En la caja de escribir se pega con Ctrl+V y se enlazan objetos con Mayús+clic.
- **Pestañas en el chat del juego:** la primera vez se crean solas las pestañas "Hermandad" (tu hermandad y las demás), "Buscar grupo" y, si eres oficial, "Oficiales". Si las cierras, vuelve a crearlas con `/gu pestañas` o el botón "Pestañas chat" de la pestaña Oficiales.
- **Maestro y oficiales:** el maestro lleva una corona y los oficiales una estrella amarilla, en la lista y en el chat. Por defecto es oficial el rango 1 (el siguiente al maestro). Si una hermandad tiene más rangos de oficial, añade en la Información de hermandad una línea como `GU:r:HU1:2` (rangos 1 y 2 de la hermandad HU1).
- **Clic derecho** en un miembro (en la lista o en el chat): Información, Susurrar, Invitar, Nota, Ver mensajes, Ascender, Degradar, **Cambiar rango ▸** (al pasar el ratón por la flecha salen los rangos), Silenciar/Desilenciar y Echar de la hermandad.
- **Tamaño de letra del chat:** desplegable con los píxeles junto a la caja de escribir (o `/gu letra 14`).
- **Mensaje fijado:** encima del chat del panel hay un recuadro con un mensaje fijado que ven todas las hermandades. Solo el maestro y los oficiales pueden cambiarlo (botón Editar). Queda apuntado en el registro de oficiales.
- **Lista aparte:** botón "Lista aparte" arriba del panel, Mayús+clic en el botón del minimapa o `/gu lista`. Es una ventana pequeña solo con los miembros (conectados o todos, por hermandad, con buscador) que puedes dejar abierta mientras juegas; se mueve, se agranda desde su esquina y recuerda si estaba abierta. Clic derecho en un nombre para el menú.
- **Ancho de la lista y del chat:** arrastra la línea dorada que los separa.
- **Tamaño:** arrastra la esquina inferior derecha del panel para agrandarlo o achicarlo (o `/gu escala 0.8`).
- **Notas:** clic derecho > Añadir nota (o botón "Nota"). Cada personaje tiene una **nota pública**, que ven todos los que tienen el addon en todas las hermandades y que solo pueden escribir el maestro y los oficiales, y una **nota privada**, que solo ve quien la escribe. Al pasar el ratón por un miembro se ven las dos, separadas.
- **Rangos y permisos:** pestaña Oficiales > botón "Rangos". Muestra los rangos de tu hermandad y los permisos de cada uno. El maestro puede cambiar nombres y permisos, añadir rangos y borrar el último.
- **Oficiales > Registro de oficiales:** quién ha hecho qué, con fecha: ascensos y degradaciones, expulsiones de la hermandad, entradas y salidas, cambio de maestro, quién echa o veta del canal, y las peticiones de rango enviadas o rechazadas. Se ven también las de las demás hermandades y se puede filtrar por oficial y copiar.
- **Oficiales > Mensajes de un jugador:** todo lo que ha escrito un personaje en el chat de la comunidad (también desde el botón "Mensajes" de la pestaña Miembros).
- Los comandos son `/gu` (o `/guildunion`; `/wlp` sigue valiendo). `/gu chat` abre el chat aparte. Las líneas de configuración antiguas `HU:...` y `WLP:...` siguen valiendo, pero ahora se escriben `GU:...`.
- `/gu canal` (o el botón "Ver quién está en el canal") lista quién está en el canal y quién es propietario o moderador.
- `/gu estado` muestra el estado. `/gu config` muestra la ayuda de configuración. Con `/gu` y cualquier otra palabra se listan todos los comandos.

## Cambiar rangos

En la lista haz clic en alguien para seleccionarlo. Abajo tienes los botones Ascender, Degradar y Rango, y con clic derecho "Cambiar rango ▸".

- **En tu hermandad:** si tienes permiso para ascender o degradar, el cambio se hace al momento. El juego no deja dar un rango igual o superior al tuyo.
- **En otra hermandad:** el juego no permite cambiar rangos de otra hermandad, así que el addon envía una petición. A los oficiales de esa hermandad que tengan el addon y permiso les sale una ventana: "Ana <HU1> pide cambiar el rango de Bruno: Miembro -> Veterano. Aceptar / Rechazar". El primero que acepta lo aplica, y a ti te llega la respuesta.
- Solo pueden pedir cambios los oficiales con permiso para cambiar rangos en su propia hermandad.
- De los desconectados de otras hermandades no se conoce el rango actual. Con ellos solo funciona "Cambiar rango".

## Botones de Oficiales > Estado (bajo "Comprobaciones")

- **Contraseñas:** vuelve a leer las contraseñas y la configuración (líneas GU:). Úsalo después de cambiarlas.
- **Miembros:** revisa al momento las listas de miembros, los contactos de las otras hermandades y el canal, sin esperar a los 2 minutos.
- **Chats oficiales:** echa del canal de oficiales a quien esté dentro sin ser maestro u oficial (hay que ser propietario o moderador de ese canal).
- **Rangos** (rangos y permisos de tu hermandad) está ahora en Oficiales > Opciones, como última opción.
- "Pestañas chat" está ahora en General, arriba a la derecha del chat.

## Vetar del chat

- Clic derecho en un jugador > **Vetar del chat...** (maestro y oficiales). Sale un aviso: no podrá volver a entrar en el chat de la comunidad, aunque esté dentro de la hermandad y aunque tenga las contraseñas.
- Se veta en el canal del juego (lo aplica cualquier moderador o propietario del canal con el addon) y, además, nadie con el addon ve lo que escriba.
- Al vetar o silenciar hay que escribir el **motivo** (sin motivo no se aplica). Llega a todas las hermandades, se le dice al afectado, se ve en su ficha y queda en el registro de oficiales.
- Para quitarlo: clic derecho > **Readmitir en el chat**. Las dos cosas quedan en el registro de oficiales.

## Seguridad

- **Antes de enviar:** el addon solo manda tus mensajes al chat unido si de verdad estás en tu hermandad y es una de las permitidas.
- **Al recibir:** un mensaje del chat solo se muestra si quien lo escribe está en la lista de la hermandad de su etiqueta. Alguien de fuera con la contraseña, o alguien que se haga pasar por otra hermandad, no sale.
- **Acciones de oficial** (mensaje fijado, silenciar, notas públicas, crear o quitar canales, Buscar Grupo): solo se aceptan si quien las firma es maestro u oficial conocido de una de las hermandades. Si su rango aún no se conoce (acaba de entrar), la acción espera hasta que llegue, en vez de perderse.
- **Listas de miembros:** solo se aceptan de alguien que está en la lista de esa misma hermandad, así nadie puede colarse en una lista.
- Lo que no se puede evitar: alguien con la contraseña puede leer el canal mientras está dentro (la guardia lo echa), y un miembro de las hermandades que modifique su addon podría falsear avisos dentro de las hermandades.

## Cómo funciona la guardia

- **Regla:** quien esté en cualquiera de las hermandades unidas nunca se echa, ni siquiera con el botón.
- Cada hermandad comparte con las demás la lista completa de sus miembros, también los desconectados. Si alguien entra o sale de una hermandad, las demás reciben la lista nueva en pocos minutos. Las listas se guardan entre sesiones.
- Solo se echa a quien no aparece en ninguna lista. Si falta la lista actualizada de alguna hermandad, no se echa a nadie.
- Antes de echar a alguien se espera un margen (2 minutos por defecto), por si acaba de entrar en una hermandad.
- Vigila cualquier moderador o el propietario del canal que tenga el addon.
- Por defecto la guardia solo avisa: los intrusos aparecen en la pestaña Oficiales con los botones Echar y Vetar. La expulsión automática se activa con la casilla del panel o con `/gu guardia on`.

## Limitaciones de esta versión

- Quien no tiene el addon no ve el chat de las otras hermandades.
- Los conectados de otras hermandades se actualizan cada 3 minutos; los desconectados (nivel, clase, tiempo fuera), cada 30 minutos.
- Profesiones, raza y rol solo se conocen de quien tiene el addon. En Classic Era el juego no tiene enlaces de profesión, por eso las recetas se piden con "Ver recetas".
- Silenciar no impide escribir en el /g propio a quien no tiene el addon: sus compañeros sin addon lo seguirán viendo.
- La guardia no vigila el canal de oficiales.

## Qué comprobar en las pruebas

1. Que `/gu estado` diga "Canal: conectado" y que el canal no aparezca en el chat.
2. Que un mensaje en `/g` llegue a la otra hermandad con su etiqueta.
3. Que, a los 3-5 minutos, la pestaña Miembros muestre a los conectados de la otra hermandad.
4. Que la pestaña Oficiales no diga "La lista del canal no está disponible". Si lo dice, abre una vez Social > Chat y vuelve a mirar. Esto es lo más importante de confirmar, porque la guardia depende de ello.
5. Que un personaje sin hermandad que entre con la contraseña aparezca como intruso pasado el margen, y que nadie de las hermandades aparezca nunca.

Si algo falla, activa `/gu debug on` y copia los mensajes grises que salgan.

## Licencia

Copyright (c) 2026 Sadance. Licencia **MIT**: se puede usar, copiar, modificar y redistribuir libremente, manteniendo el aviso de copyright (ver `LICENSE.txt`). Las librerías de `Libs` conservan sus licencias.
