---
doc: economy
stage: 2
owner: el agente; Victor valida
status: draft
as_of:
sections: Respuestas, Monedas, Fuentes y sumideros, Premios aleatorios, Criterio de listo, Evidencia
---
# Economía

Fuentes, sumideros y valor esperado. Los números salen de la hoja (`balance/*.csv`), no de la prosa. Molde adaptado de `economy-model` de Claude Code Game Studios (MIT, ver `THIRD-PARTY.md`) y de la guía de economías virtuales de Roblox.

## Preguntas que debe responder

1. ¿Qué monedas existen y para qué sirve cada una? Idealmente una blanda y, si hace falta, una premium.
2. ¿Cuál es la fuente (cómo entra) y el sumidero (cómo sale) de cada moneda? Una moneda sin sumidero se infla.
3. ¿Cuánto tarda un jugador en ganar su primera mejora, la décima y la última? (Metas en minutos.)
4. ¿Hay algún premio aleatorio? Entonces: probabilidades, valor esperado (EV) y, si hay "piedad" (pity), su tope.
5. ¿Qué pasa con un jugador que no paga? ¿Qué compra el que paga y rompe algo para el otro?
6. ¿Qué bandas se fijan con una prueba (por ejemplo `scripts/pacing`) para que un cambio de números no rompa el ritmo?
7. ¿Cuáles son los límites éticos? (Sin presión de tiempo falsa, sin azar pagado oculto: ver `roblox-monetization` y la política de elementos aleatorios pagados.)

## Respuestas

1. TBD
2. TBD
3. TBD
4. TBD
5. TBD
6. TBD
7. TBD

## Monedas

| Moneda | Tipo | Para qué sirve | Tope |
|---|---|---|---|
| TBD | TBD | TBD | TBD |

## Fuentes y sumideros

| Moneda | Fuente | Tasa | Sumidero | Tasa |
|---|---|---|---|---|
| TBD | TBD | TBD | TBD | TBD |

## Premios aleatorios

| Tabla | Premio | Probabilidad | EV | Piedad |
|---|---|---|---|---|
| TBD | TBD | TBD | TBD | TBD |

## Criterio de listo

- [ ] Cada moneda tiene su fuente y su sumidero.
- [ ] Todo premio aleatorio tiene su fila de EV.
- [ ] La hoja `balance/*.csv` existe, está normalizada y acotada.
- [ ] Las bandas viven en una prueba del repo.
- [ ] Victor validó los números.

## Evidencia

Ruta de la hoja, de la prueba de ritmo y de la medición de referentes (nota del vault) que justifica los órdenes de magnitud.

- TBD
