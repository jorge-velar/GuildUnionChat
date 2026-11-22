# Guild Union: instrucciones para Claude

Addon de WoW (destino principal WoW Forever, Lua 5.1). Código, comentarios y textos en español; los
textos que ve el jugador van con `L()` y su inglés en LocaleEN.lua. Los comentarios largos van a
ARCHITECTURE.md (en el código queda la primera línea con `[+ARCHITECTURE.md]`).

Durante el refactor de arquitectura (docs/propuesta-arquitectura.md) el addon funciona igual que
antes: un fallo o una mejora que aparezca se apunta en docs/fallos-conocidos.md y se arregla aparte.

## Código nuevo: los registros

- Una orden de red: `HU:RegisterMessage` junto a su manejador (Protocol.lua), su descripción en
  `tests/lib/protocolo.lua` y rehacer la tabla (`lua tests/run.lua Protocolo --actualizar`). Un comando `/gu`:
  `HU:RegisterSlash`, y añadirlo a `INPUTS` de `slash_spec` y rehacer la referencia. Algo que se
  repite: `HU:Every(segs, "nombre", fn)` (no hay `NewTicker`). Lo que se guarda: `HU:Saved` al
  principio del archivo; si cambia de forma, una migración (`HU:RegisterMigration`).
- Cada archivo acaba con `HU:Module(nombre, { necesita })`; si `modulos_spec` dice que no cuadra,
  se copia la línea que propone.
- Se llama directamente a las funciones de `HU` (nada de `if HU.X then HU:X() end`); `guardas_spec`
  lo vigila.

## Pruebas (obligatorio)

- Todo cambio de código del addon llega con pruebas en `tests/spec/`. Sin dependencias: el ejecutor
  es `tests/run.lua` y el WoW de mentira `tests/lib/wow.lua`.
- Lo que necesita varios jugadores (chat entre hermandades, listas, enlaces, silencios) se prueba con
  la red de `tests/lib/red.lua`.
- Un fallo visto en el juego: primero la prueba que lo reproduce, luego el arreglo.
- Antes de dar algo por hecho, pasar:
  - `lua tests/run.lua` (todas en verde);
  - `lua tests/cobertura.lua --base origin/main`: lo nuevo, probado al 70 % como mínimo, y ningún
    archivo por debajo de su mínimo. Aquí corre con Lua 5.4 (margen de 2 puntos); los mínimos son
    de Lua 5.1. Si un archivo sube, tras el CI se copia el artefacto `cobertura-minima` a
    `tests/cobertura-minima.txt` (no `--actualizar` con 5.4: daría otros valores).
- El formato de los mensajes de red está fijado (`tests/spec/formato_spec.lua`,
  `tests/golden/formato.txt`) y se prueba contra la última versión publicada. Si un cambio de formato
  es a propósito: `lua tests/run.lua Formato --actualizar`, mantener la compatibilidad con las
  versiones que ya están en el juego y decirlo en la PR.
- Si falta una función del juego en el WoW de mentira, se añade a `tests/lib/wow.lua` con el valor
  más neutro posible.
- luacheck solo corre en el CI (aquí no se puede instalar): no añadir avisos nuevos.
- Metatabla estricta: si `strict_spec` falla con un campo de `HU`, o es un nombre mal escrito (se
  arregla) o es estado que empieza vacío (se añade a `HU.MAYBE_NIL` en Core.lua). Nunca se añade un
  campo a esa lista sin comprobar que algo lo asigna.
