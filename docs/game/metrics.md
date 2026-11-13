---
doc: metrics
stage: 2
revisit: 12
owner: agente
status: draft
as_of:
sections: Respuestas, Eventos, Umbrales, Criterio de listo, Evidencia
---
# Métricas

Roblox nombra tres KPIs: participación, retención y monetización. Aquí se declara qué se mide y cuál es el número que decide si el juego sigue (decisión de la etapa 12).

## Preguntas que debe responder

1. ¿Qué eventos se emiten, cuándo se disparan y con qué propiedades? (Consume `src/shared/features/analytics`.)
2. ¿Cuál es el D1, el D7 y la duración de sesión de partida, y de dónde se leen (Creator Analytics, `scripts/own-analytics`)?
3. ¿Cuál es el umbral de abandono, por número y con fecha? (grill 12.1 y 12.2). Por ejemplo "si al día 7 hay menos de N jugadores concurrentes, se baja".
4. ¿Cuál es el embudo del primer minuto y qué evento lo cierra?
5. ¿Qué dato no es público y queda como `[GAP]` (retención ajena, origen del tráfico)?
6. ¿Cada cuánto se revisa y quién?

## Respuestas

1. TBD
2. TBD
3. TBD
4. TBD
5. TBD
6. TBD

## Eventos

| Evento | Cuándo se dispara | Propiedades |
|---|---|---|
| TBD | TBD | TBD |

## Umbrales

| Métrica | Valor mínimo | Fecha de lectura | as_of |
|---|---|---|---|
| TBD | TBD | TBD | TBD |

## Criterio de listo

- [ ] Lista de eventos con nombre, disparo y propiedades.
- [ ] D1, D7 y duración de sesión como mínimo.
- [ ] Umbral de abandono por número, con fecha.
- [ ] Cada número del vault lleva su fecha `as_of`.

## Evidencia

Enlace a `docs/win-condition-checklist.md` (medición de la etapa 12) y a la documentación de analítica de Roblox.

- TBD
