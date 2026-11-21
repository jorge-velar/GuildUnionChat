# Guild Union: instrucciones para Claude

Addon de WoW (destino principal WoW Forever, Lua 5.1). Código, comentarios y textos en español; los
textos que ve el jugador van con `L()` y su inglés en LocaleEN.lua. Los comentarios largos van a
ARCHITECTURE.md (en el código queda la primera línea con `[+ARCHITECTURE.md]`).

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
