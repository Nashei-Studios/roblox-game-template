---
doc: load-budget
stage: 3
revisit: 10
owner: el agente redacta; Victor valida los topes con la primera medición
status: draft
as_of:
sections: Respuestas, Presupuesto, Límites de DataStore, Cohorte de 0 a 250 jugadores simultáneos, Criterio de listo, Evidencia
---
# Presupuesto de carga y tiempo de entrada

Los números contra los que se mide un juego antes y después de publicarlo en privado: tiempo de entrada, FPS en teléfono, memoria, latido del servidor, red y DataStore. Qué es: la tabla de topes con su origen y la forma de medir cada uno. Qué no es: una medición. Ninguna cifra de esta página se midió en un juego; la columna "Medido" queda en `TBD` hasta correr la prueba de [`prueba-de-carga-privada.md`](prueba-de-carga-privada.md) (#203).

Cada número lleva una etiqueta:

| Etiqueta | Significa |
|---|---|
| `sourced` | Sale de la documentación oficial de Roblox, con la URL en la tabla de evidencia |
| `chosen` | Tope elegido por el estudio porque la documentación no publica cifra. Se ajusta con la primera medición; no se lee como un límite de Roblox |
| `GAP` | No hay número y no se inventa. Va con quién lo cierra |

Los topes que el CI ya vigila viven en `src/shared/perf/PerfBudget.luau` (`lune run scripts/perf-budget`, ADR 0019); esta página los repite para que quien planifica la prueba los tenga en un solo lugar. Si difieren, manda el código.

## Preguntas que debe responder

1. ¿Cuánto puede tardar la entrada y cuándo se considera un fallo?
2. ¿Qué FPS y qué memoria se exigen en un teléfono de gama baja?
3. ¿Qué latido, memoria y red se exigen al servidor con el servidor lleno?
4. ¿Cuántas solicitudes de DataStore puede costar una entrada y cuál es el límite de Roblox?
5. ¿Qué número de la tabla queda sin medir y qué lo produce?

## Respuestas

1. La entrada llega a "jugable" (personaje en escena y HUD visible tras pulsar Jugar) con p50 de 8 s como máximo, p90 de 15 s y fallo duro sobre 20 s. Todos `chosen`. Medido: TBD (#203).
2. FPS p10 de 30 como mínimo y 45 como objetivo en gama baja; la memoria del cliente no crece en 10 minutos de sesión. Medido: TBD (#203).
3. Latido medio bajo 16 ms, memoria bajo la mitad del total, red por jugador según `PerfBudget.runtime`. Medido: TBD (#203).
4. Hasta 3 solicitudes por entrada y ninguna dentro de un bucle de espera (`chosen`); el límite de Roblox es `60 + jugadores x 40` por minuto y por servidor (`sourced`).
5. La columna "Medido" completa y la memoria del cliente por dispositivo (`GAP`). Los produce la prueba de #203.

## Presupuesto

| Presupuesto | Tope | Etiqueta | Origen | Cómo se mide | Medido |
|---|---|---|---|---|---|
| Entrada a "jugable" (clic en Jugar hasta poder moverse con personaje y HUD) | p50 hasta 8 s, p90 hasta 15 s, fallo duro sobre 20 s | `chosen` | La página de tiempos de carga no da objetivo | Sonda de entrada (ADR 0032) en Roblox Player, 5 entradas | TBD (#203) |
| Servidor: de `PlayerAdded` a personaje cargado, sin conflicto de sesión | hasta 4 s | `chosen` | Sin cifra publicada | Sonda de entrada del servidor | TBD (#203) |
| Espera por candado de sesión | hasta 90 s | `chosen` | `PerfBudget.load.session.maxWaitSeconds`; la política de ADR 0032 | `lune run scripts/perf-budget` (simulado) y reentrada en menos de 3 minutos (#203) | TBD (#203) |
| FPS del cliente en teléfono de gama baja | p10 desde 30, objetivo 45 | `chosen` | La documentación solo dice que 60 FPS exige CPU bajo 16 ms | Teléfono real, MicroProfiler y Developer Console | TBD (#203) |
| CPU por frame del cliente | bajo 16 ms en PC; bajo 33 ms en teléfono de gama baja | 16 ms `sourced`, 33 ms `chosen` | Página de rendimiento de analytics | MicroProfiler del cliente | TBD (#203) |
| Memoria del cliente | sin cifra publicada; no crece en 10 minutos de sesión | `GAP` | La documentación no da número. El tope por dispositivo se lee del gráfico de memoria de Creator Hub, que exige 100 usuarios diarios | Developer Console, pestaña Memory, cada minuto | TBD (#203) |
| Memoria del servidor | bajo el 50 % del total, que es 6,25 GiB + 100 MiB por jugador conectado | `sourced` | Página de identificar rendimiento; ADR 0019 | Developer Console del servidor, pestaña Memory | TBD (#203) |
| Latido del servidor | media bajo 16 ms; investigar sobre 33 ms | 16 ms `sourced`, 33 ms `chosen` | Páginas de rendimiento | Developer Console, Server Jobs | TBD (#203) |
| Red por jugador | `PerfBudget.runtime`: `sendKbpsPerPlayer` 4 y `receiveKbpsPerPlayer` 2, en Kbps | `chosen` | La documentación no da cifra por jugador | `Stats.DataSendKbps` y `DataReceiveKbps` en el servidor; Ctrl Alt F7 en el cliente | TBD (#203) |
| RemoteEvent de cliente a servidor | menos de 500 solicitudes por segundo por cliente, compartidas entre todos los RemoteEvent | `sourced` | Referencia de `RemoteEvent` | Presupuesto de remotes del CI | cubierto por `perf-budget` |
| Instancias de Workspace | hasta 5.000 instancias y 4.000 partes | `chosen` | `PerfBudget.load.services`; con streaming la meta es el área de entrada, no el total | Exportación del lugar y `lune run scripts/perf-budget` | TBD (#203) |
| Instancias de StarterGui al entrar | hasta 600 | `chosen` | `PerfBudget.load.services` | Igual que la fila anterior | TBD (#203) |
| Solicitudes de DataStore por entrada | hasta 3, ninguna en un bucle de espera | `chosen` | `PerfBudget.load.dataStore.maxRequestsPerJoin` | `lune run scripts/perf-budget` y el registro de la sonda | TBD (#203) |

Un número `chosen` se cambia en `PerfBudget.luau` en una PR que explique la medición que lo justifica. Nunca se sube un tope para que el CI pase.

## Límites de DataStore

Fórmulas de Roblox por servidor y por minuto (`sourced`, página de códigos de error y límites):

| Tipo | Solicitudes por minuto |
|---|---|
| Lectura estándar (`GetAsync`, `UpdateAsync` y otras) | `60 + jugadores x 40` |
| Escritura estándar (`SetAsync`, `UpdateAsync` y otras) | `60 + jugadores x 40` |

`UpdateAsync` consume una lectura y una escritura. Aritmética propia sobre esas fórmulas: con 6 jugadores por servidor el límite es 300 por minuto. El límite a nivel de experiencia entera queda como `GAP`: la nota de investigación lo calcula con una base distinta de la fórmula oficial de arriba, y hasta verificarlo en la página no se publica un número. Dueño: quien cierre #203.

## Cohorte de 0 a 250 jugadores simultáneos

Con la comunidad en cero, el CCU de la prueba privada es el número de administradores presentes, así que hay dos pruebas distintas y ninguna es una prueba de carga masiva:

| Prueba | Qué cubre | Dónde se corre |
|---|---|---|
| Sintética | Topes de instancias, espera de sesión y solicitudes de DataStore por entrada | CI, `lune run scripts/perf-budget` |
| Humana | Tiempo de entrada, teléfono, servidor lleno | Servidor privado, [`prueba-de-carga-privada.md`](prueba-de-carga-privada.md) |

Con N jugadores por servidor, 250 jugadores simultáneos son `ceil(250 / N)` servidores a la vez; con N = 6 son 42. Cada servidor hace su propia entrada, así que el tiempo de entrada y la sesión de DataStore pesan más que el ancho de banda. Un servidor lleno se prueba con N clientes, nunca con 250. No hay forma oficial verificada de generar cientos de clientes: queda descartado hasta que la haya.

## Criterio de listo

- [ ] Cada fila de "Presupuesto" tiene tope, etiqueta y origen.
- [ ] La columna "Medido" tiene un valor con fecha, o `TBD (#203)`.
- [ ] Los topes de la tabla coinciden con `PerfBudget.luau`.
- [ ] Cada `GAP` tiene dueño.
- [ ] Está enlazada desde `qa-plan.md` y `metrics.md`.

## Evidencia

- [Cómo se mide cada número, paso a paso](prueba-de-carga-privada.md)
- [ADR 0019: presupuesto de rendimiento](../adr/0019-performance-budget.md)
- [ADR 0032: la entrada y la sonda](../adr/0032-join-architecture-data-as-background-state.md)
- [Procedimiento manual de rendimiento](../performance.md)
- [Tiempos de carga (Roblox)](https://create.roblox.com/docs/projects/performance-optimization/load-times)
- [Rendimiento en analytics (Roblox)](https://create.roblox.com/docs/production/analytics/performance)
- [Identificar rendimiento (Roblox)](https://create.roblox.com/docs/performance-optimization/identify)
- [Límites de DataStore (Roblox)](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits)
- [RemoteEvent (Roblox)](https://create.roblox.com/docs/reference/engine/classes/RemoteEvent)
- [GAP] El tope de memoria del cliente por dispositivo y el límite de DataStore a nivel de experiencia no tienen cifra verificada. Dueño: quien ejecute #203.
