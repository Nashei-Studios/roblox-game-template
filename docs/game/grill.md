---
doc: grill
stage: 1
owner: el grupo decide; el agente conduce y redacta
status: draft
as_of:
sections: Reglas de la sesión, Agenda, Rendimiento y carga, Respuestas, Criterio de listo, Evidencia
---
# Grill de juego

La primera sesión donde el grupo cuestiona el concepto antes de construir. Dura entre 60 y 90 minutos; las preguntas son cerradas (sí o no, una opción de una lista, un número) y cada una trae su evidencia. Lo que sale de aquí llena los demás documentos de `docs/game/`. Método y fuentes: nota del vault `research/2026-11-12-monetizacion-y-proceso-de-grill` (apuesta de tiempo y corte automático de Shape Up, pre-mortem de Klein, prototipo de un día de Roblox).

## Preguntas que debe responder

1. ¿Se recorrieron todos los bloques de la agenda, o los que faltan tienen dueño y fecha en un issue `acuerdo`?
2. ¿Cada respuesta cerrada quedó copiada en el documento de la última columna?
3. ¿Quedó escrito el criterio de abandono por número y la fecha del corte automático?
4. ¿Cada riesgo del pre-mortem tiene dueño y una mitigación, o está aceptado por escrito?
5. ¿Alguna respuesta se apoya en una cifra sin medir? Entonces va como `[GAP]`, no como número.

## Reglas de la sesión

- Quien conduce no es quien defiende la idea.
- Una decisión sin evidencia se escribe con dueño y fecha en un issue `acuerdo`; no se resuelve a mano alzada.
- Los gameplays de los referentes se ven en YouTube; no se juegan por el escritorio.
- Primera reunión: bloques 0 a 8, 13 y 14. Los bloques 9 a 12 pueden pasar a una segunda de 30 minutos. Es una propuesta a calibrar con el primer juego que la use.

## Agenda

| Bloque | Min | Preguntas cerradas | Evidencia que debe traer | Documento que llena |
|---|---|---|---|---|
| 0. Punto de partida | 5 | Horas por semana de cada persona (número); fecha jugable y fecha de veredicto; número que dice que valió la pena | Calendario; decisión 0032 del vault | `content-roadmap.md`, `metrics.md` |
| 1. Concepto y fantasía | 10 | ¿La frase "Es un [género] donde [acción] en [ambiente] para [meta]" se entiende en 10 s con un desconocido (sí o no)? ¿Gancho en menos de 9 palabras? ¿Qué momento filmaría un desconocido? | Frase escrita y la prueba con un desconocido | `concept.md` |
| 2. Pilares | 5 | Entre 3 y 5 pilares, cada uno falsable y con su "esto nos obliga a decir que no a" | Lista | `concept.md` |
| 3. Público y plataforma | 5 | Rango de edad; plataforma primaria (móvil, PC o consola); jugadores máximos por servidor | Datos del género en la foto de mercado del vault | `concept.md`, `ui-flows.md` |
| 4. Loops | 10 | Loop de 30 s (cinco verbos y segundos por vuelta); de 5 min (qué compra el jugador); de sesión (cuándo termina); de semana (qué lo trae de vuelta) | Gameplays de los referentes | `core-loop.md`, `progression.md` |
| 5. Win condition de 0 a 250 | 5 | ¿Hay un clip que se comparte (sí o no)? ¿Qué lo muestra en los primeros 10 s? | `docs/win-condition-checklist.md` (ADR 0044) | `concept.md` |
| 6. Cohorte | 10 | Tres referentes del mismo contexto (juegos de 0 a 250 jugadores que retienen) con jugadores, visitas, votos, edad, último update, pases y rango, con fecha; la UNA diferencia | Nota de competencia del vault | `competition.md` |
| 7. Monetización desde el día 1 | 10 | Lista de pases y productos; precio inicial dentro del rango de la cohorte; starter pack y minuto en que aparece; ¿hay azar de pago (sí o no)?; qué queda gratis | `monetization.md` y su lista "Creado antes de publicar"; barra E1 a E10 | `monetization.md`, `economy.md` |
| 8. Alcance y corte | 10 | ¿Cabe en 7 a 10 días (sí o no)? Lista cerrada de lo que entra y lo que no; entre 6 y 9 épicas y entre 30 y 60 historias; fecha del corte automático | Estimación por épica | `content-roadmap.md` |
| 9. Riesgos técnicos y spikes | 5 | Los tres mayores riesgos técnicos; un spike de tope un día por cada uno; ¿hay algo sin kit (sí o no)? | Auditoría de kits del vault; ADR de la plantilla | `systems-index.md`, `prototype-report.md` |
| 10. Rendimiento y carga | 5 | Ver la sección siguiente | ADR 0019 y la nota de rendimiento del vault | `qa-plan.md`, `metrics.md` |
| 11. Arte y contenido | 5 | Origen de cada modelo y zona (kit, propio, comprado); contadores de contenido (mundos, equipos, criaturas) si el diferenciador es "el más completo" | Kits y licencias del vault | `world-and-narrative.md`, `audio.md` |
| 12. Comunidad y live ops | 5 | Qué recibe quien se une al grupo 405835365 y cómo se muestra en el primer minuto; cadencia de updates que se puede sostener (número por semana); un evento de ejemplo con fecha | ADR 0026 y 0037; nota de competencia | `community.md`, `liveops.md` |
| 13. Pre-mortem | 10 | Cada persona escribe en silencio 3 razones por las que el juego fracasó a las 72 horas; se agrupan; cada grupo recibe dueño y mitigación o se acepta por escrito | Notas del grupo | `prototype-report.md`, issue `acuerdo` por riesgo aceptado |
| 14. Matar o seguir | 5 | Criterio de abandono por número escrito antes de jugar el prototipo; persona que decide; día del corte | Decisión 0032 del vault | `prototype-report.md`, `metrics.md` |

## Rendimiento y carga

Puerta del grill: ningún concepto pasa a construcción sin un presupuesto por cada línea, o un `[GAP]` con dueño y fecha. Esta sección fija qué se pregunta; la investigación detallada de cifras llega en otra nota del vault y se enlaza aquí cuando exista. No se inventa ningún número.

| Línea | Pregunta cerrada | Presupuesto (número, o `[GAP]`) | Cómo se comprueba | Documento |
|---|---|---|---|---|
| Tiempo de entrada | ¿Cuántos segundos pasan desde que se pulsa jugar hasta la primera acción del loop en un teléfono de gama baja? ¿Qué se carga después de la primera acción y no antes? | TBD | Medición en un dispositivo real; embudo de `ftue.md` | `ftue.md`, `qa-plan.md` |
| Memoria | ¿Cuántos MB de cliente en móvil de gama baja y en PC? ¿Qué zonas o modelos se cargan y descargan por streaming? | TBD | Medidor de Studio en el dispositivo; lista de modelos más pesados | `qa-plan.md` |
| Red | ¿Qué ancho de banda por jugador en el peor caso? ¿Cada remote nuevo tiene su entrada en el presupuesto? | TBD | `lune run scripts/perf-budget` (ADR 0019) | `systems-index.md`, `qa-plan.md` |
| Servidores | ¿Jugadores máximos por servidor (número)? ¿Qué pasa con el servidor a medio llenar y con el lleno? ¿Cuántas instancias y scripts activos en el caso lleno? | TBD | Prueba con el servidor lleno en playtest | `qa-plan.md`, `metrics.md` |

Cada fila con `[GAP]` va a un issue `acuerdo` con dueño y fecha antes del prototipo.

## Respuestas

1. TBD
2. TBD
3. TBD
4. TBD
5. TBD

## Criterio de listo

- [ ] Todos los bloques recorridos o con issue `acuerdo`.
- [ ] Criterio de abandono por número y fecha del corte escritos.
- [ ] Cada riesgo del pre-mortem con dueño o aceptado por escrito.
- [ ] Las cuatro líneas de rendimiento y carga con presupuesto o `[GAP]` con dueño.
- [ ] Cada respuesta copiada a su documento.

## Evidencia

Nota del vault `research/2026-11-12-monetizacion-y-proceso-de-grill` y la plantilla `grill-de-juego.md` del repositorio del estudio; el acta de la sesión enlazada aquí.

- TBD
