# 0072 — No commit on develop or main, and board text fenced as data

- **Estado:** aceptado
- **Fecha:** 2026-11-14
- **Amplía:** [0066](0066-branch-guard-without-server-rules.md) y [0070](0070-no-direct-push-to-develop.md)
- **Refs:** #265, Nashei-Studios/studio#108 y su ADR 0006

## Contexto

El ADR 0070 dejó al `pre-push` rechazando todo push a `develop` y `main`. Un commit en esas ramas todavía se podía hacer en local: quedaba listo para un push que el hook frena, o para un `--no-verify`. En studio, la guardia de rama del agente intentó leer cada `git commit` y `git push` de la shell, y siete rondas de revisión de seguridad automática encontraron siempre otra forma de escribirlos. Git, en cambio, conoce la rama real. Por otro lado, los hooks del propio juego (`tools/board-hooks`) metían en el contexto del agente los posts del Agent Board y los títulos de los issues sin largo máximo y sin delimitarlos como dato. Dentro de un clon de juego son esos hooks los que hablan.

## Opciones consideradas

1. **Dejarlo como está** — sin cambios · un commit en `develop` no se frena hasta el push, y un post largo o con instrucciones entra entero al contexto.
2. **`pre-commit` en `.githooks`, y el texto del tablero con tope y delimitado** — git aplica la regla al crear el commit; el agente recibe los posts como dato, con un límite · el hook se puede saltar igual que el `pre-push` (`--no-verify`, `ALLOW_PROTECTED_COMMIT=1`), y un post largo llega cortado.

## Decisión

**Opción 2.**

- `.githooks/pre-commit` rechaza un commit con `HEAD` en `develop` o `main`. Un `HEAD` sin rama pasa. Salida de emergencia, dicha antes al equipo: `ALLOW_PROTECTED_COMMIT=1`.
- `tools/board-hooks/board-text.ps1` (`Format-BoardData`, la misma de studio):
  - Deja los últimos 8 posts, de 1200 caracteres cada uno y 8000 en total.
  - Los pone entre `<board-data-XXXXXXXX>` con un sufijo aleatorio por llamada, y la cola de trabajo entre `<work-queue-XXXXXXXX>`.
  - Neutraliza las marcas escritas dentro de un post.
- `tools/board` indenta las líneas del cuerpo que empiezan como el encabezado de un post (`--- @`).
- Las variantes `board-session-start.sh` y `board-prompt.sh` le pasan el trabajo a `board-hook.ps1` cuando hay `pwsh`. Sin `pwsh`, igual cortan a 8000 caracteres, cambian `<` y `>` por corchetes y delimitan con un sufijo aleatorio.

## Consecuencias

- Positivas: la regla de ramas se cumple al crear el commit, se haya escrito el comando como se haya escrito. El texto del tablero entra acotado y marcado como dato.
- Negativas: el hook depende de `core.hooksPath`, igual que el `pre-push`. Un post de más de 1200 caracteres llega cortado, con el comando para leerlo entero.
- Qué haría revisar esta decisión: reglas de rama del servidor en privados del plan gratis.
