# Fallos y mejoras conocidos

Cosas que funcionan peor de lo que podrían y que **se han dejado tal cual a propósito**: el refactor
de arquitectura no cambia el comportamiento del addon. Cada una dice dónde está, qué pasa en el
juego, qué prueba la fija hoy y cómo se arreglaría. Arreglar una es un cambio de comportamiento: va
en su propia PR, cambiando la prueba que la fija junto con el código.

## 1. `PB` (raza y profesiones) se pierde al principio

- **Dónde:** Comm.lua, `AllowAddonMessage` (`PB` no está en `BOOTSTRAP`) y quien lo envía con la
  primera lista.
- **Qué pasa:** al conectarse, la raza y las profesiones salen por susurro a la vez que la primera
  lista (a los ~36 s). Quien las recibe todavía no se fía del remitente, así que las rechaza; `RB`
  en el mismo caso se retiene y se aplica después, `PB` no. No se vuelven a mandar en al menos
  6 minutos: durante ese rato la ficha de los de la otra hermandad sale sin raza ni profesiones.
- **Qué lo fija:** `formato_spec`, `NOBODY_ACCEPTS = { PB = ... }`, y una prueba que avisa cuando
  la excepción deja de hacer falta.
- **Arreglo propuesto:** retener `PB` como `RB` hasta que el remitente sea de fiar, o mandarlo
  después de la lista. Al arreglarlo, quitar `PB` de `NOBODY_ACCEPTS`.

## 2. `db.rankCache` se guarda pero no se usa

- **Dónde:** se escribe en Comm.lua (al confirmar listas) y se limpia en Social.lua (más de 14
  días); `RankInfoSlow` (Config.lua) ya no lo lee.
- **Qué pasa:** la idea era poder comprobar a los oficiales de la otra hermandad aunque se
  desconecten. `RankInfoSlow` solo lo leía si además la persona salía en la lista completa de su
  hermandad, y esas listas se quitaron (ReduceClean). Desde entonces, un oficial de otra hermandad
  que se desconecta deja de poder comprobarse como oficial; mientras está conectado, sí.
- **Qué lo fija:** nada lo lee, así que ninguna prueba depende de él.
- **Arreglo propuesto:** una de dos, con su prueba en `listas_spec`:
  - recuperarlo: leer `rankCache` en `RankInfoSlow` sin esa condición. Cambia la seguridad (se
    fiaría de un rango visto hasta 14 días antes), así que conviene acortar esa edad;
  - o borrarlo del todo: lo que escribe en Comm.lua, la limpieza de Social.lua y su entrada en la
    base de datos (con la migración del paso E).

## 3. En pausa por versión mínima, la cola se vacía sin enviar

- **Dónde:** Comm.lua, `SendOne` (`if HU.paused then return false end`).
- **Qué pasa:** si la hermandad pone una versión mínima (`GU:v:` en su Información) y la mía es más
  antigua, el addon queda en pausa. Lo que ya estaba en la cola sale de ella y se descarta en vez de
  esperar. Como en pausa hay que actualizar igualmente, en el juego apenas se nota; si al quitar la
  pausa sin recargar (la hermandad baja la versión mínima) se esperaba que saliera lo pendiente, no
  sale.
- **Qué lo fija:** `cola_spec` («en pausa (versión mínima): lo que sale de la cola se pierde»).
- **Arreglo propuesto:** si se quiere conservar, devolver `true` en pausa (el mensaje vuelve
  delante de su cola, como cuando el juego va saturado) y poner un tope de tiempo para que no se
  acumule. Probablemente no merece la pena.

## 4. Claves guardadas que nadie usa

- **Dónde:** Core.lua, en su `HU:Saved` (antes, `DEFAULTS` y `PER_CHAR`).
- **Qué pasa:** `theme` (de la cuenta) se escribe con `"default"` en lo guardado cada vez que se
  carga el addon, y nada lo lee; `chatTab`, `chatTabsMade` y `proposals` (del personaje) están
  declaradas pero no las escribe ni las lee nadie. Son restos de versiones anteriores. No hacen
  daño, salvo unos bytes en lo guardado.
- **Qué lo fija:** `datos_spec` («da exactamente lo de antes»).
- **Arreglo propuesto:** quitarlas de `HU:Saved` y añadir una migración (`HU:RegisterMigration`)
  que borre `theme` de lo guardado; cambiar a la vez la lista de esa prueba.

## 5. Los desconectados de otra hermandad (`OD`, `OE`) no pasan por susurro

- **Dónde:** Net/Security.lua, `AllowAddonMessage`. Por susurro, una orden con la etiqueta de otra
  hermandad solo vale si es de arranque (`bootstrap`), y `OD` y `OE` no lo son; esa regla va antes
  que la de «quien sale en alguna lista», así que tampoco valen del enlace de esa hermandad.
- **Qué pasa:** el enlace pide los desconectados de cada hermandad (`OQ`) y su contacto los manda
  por susurro (`OD`, u `OE` si alguien los está mirando). Se rechazan siempre: los desconectados de
  las otras hermandades no llegan nunca. Lo mismo le pasa a `PB` por susurro en cualquier momento,
  no solo con la primera lista (ver 1). Hoy no se nota porque no hay ventana que los enseñe.
- **Qué lo fija:** `seguridad_spec` («lo que no es de arranque (PB, OD...) no vale»).
- **Arreglo propuesto:** por susurro, aceptar `OD`/`OE`/`PB` de quien reparte por esa hermandad
  (`HU:IsRemoteForwarder(remitente, etiqueta)`, que ya usa el manejador de `OD`), o quitar `OQ`,
  `OD` y `OE` si no se van a enseñar. Cambiar a la vez esa prueba.
