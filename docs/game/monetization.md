---
doc: monetization
stage: 2
revisit: 11
owner: el agente redacta; Victor aprueba los precios
status: draft
as_of:
sections: Respuestas, Pases y productos, Creado antes de publicar, Política, Criterio de listo, Evidencia
---
# Monetización

Pases y productos, cuándo aparecen y en cuál de los cinco contextos de compra (decisión 0024 del vault). Los ids de pases y productos quedan en `nil` hasta que existan de verdad (regla del template); nunca se inventan. Los precios finales se fijan en la release. Palancas, porcentajes y fuentes: nota del vault `research/2026-11-12-monetizacion-y-proceso-de-grill`.

## Preguntas que debe responder

1. ¿Qué se vende? Una tabla: durable o consumible, mejora o expresión.
2. ¿En cuál de los cinco contextos de compra (en juego, antes de jugar, lobby, complementaria, UI) aparece cada oferta, y en qué minuto de la sesión?
3. ¿Qué precio inicial y por qué (rango de los pases de los referentes en `competition.md`, medido con fecha)?
4. ¿Cuál es la escalera de pases (entrada de 49 a 99 Robux, conveniencia, suerte y poder, identidad) y cuántos escalones tiene el primer lanzamiento?
5. ¿Hay starter pack? ¿En qué minuto aparece (nunca en la primera carga) y qué incluye?
6. ¿Hay un x2 (dinero, suerte, velocidad) y un pase de automatización? ¿Cuáles se complementan entre sí para no repetir avisos?
7. ¿El equipo por mundo o zona se vende con pase? ¿Cuántos por mundo?
8. ¿Hay algo aleatorio de pago? Entonces va su fila de valor esperado en `economy.md` y se resuelve la política de abajo.
9. ¿Qué queda gratis para quien no paga y por qué el juego no se rompe sin pagar?
10. ¿Qué pasa si una compra falla o se reintenta (recibo idempotente, ADR 0016)?
11. ¿Cuáles de las demás palancas se activan: suscripción, servidores privados, video con recompensa, anuncios inmersivos, Roblox Plus (ADR 0024)? Para cada una que no: la razón.
12. ¿Qué ofrece la comunidad (`community.md`) y qué no se vende?
13. ¿Qué números se miden desde el primer día (conversión a pagador, ARPDAU, ingreso por visita) y dónde quedan (`metrics.md`)?

## Respuestas

1. TBD
2. TBD
3. TBD
4. TBD
5. TBD
6. TBD
7. TBD
8. TBD
9. TBD
10. TBD
11. TBD
12. TBD
13. TBD

## Pases y productos

| Oferta | Tipo | Durable o consumible | Mejora o expresión | Contexto de compra | Precio |
|---|---|---|---|---|---|
| TBD | TBD | TBD | TBD | TBD | TBD |

## Creado antes de publicar

Marca cada casilla cuando el objeto existe en la plataforma y su id está en la configuración del juego. Sin eso, la oferta no se muestra.

- [ ] Experiencia publicada en el grupo del estudio (los pases y los productos no se crean sin juego publicado).
- [ ] Cada pase con nombre, descripción, categoría e ícono de hasta 512x512.
- [ ] Cada producto de desarrollador con precio y precios regionales activados (en productos no vienen activos).
- [ ] Manejador de recibos probado con una compra repetida y una caída de servidor.
- [ ] Ningún precio escrito en el código ni en la UI: se leen en ejecución.
- [ ] Suscripción, si se usa: nombre corto confirmado (es permanente) y precio de al menos 49 Robux.
- [ ] Servidores privados, si se usan: activados y con precio decidido (cambiarlo cancela las suscripciones activas).
- [ ] Producto de la recompensa de video, si se usa: creado en el universo del juego.
- [ ] Fila de valor esperado y pantalla de probabilidades para todo azar de pago.
- [ ] Cuestionario de contenido respondido.
- [ ] Victor aprobó los precios finales.

## Política

- Todo ítem aleatorio de pago muestra todos los resultados y sus probabilidades numéricas antes de gastar la moneda que se compra con Robux (llaves, tickets). Los potenciadores de suerte y las garantías se explican antes.
- Para un jugador con `ArePaidRandomItemsRestricted` verdadero (se lee con `PolicyService`), el generador no se ofrece: ruta ganable gratis, orden fijo conocido, compra directa del resultado o se quita.
- La recompensa de video no puede ser Robux ni azar, y se entrega al terminar el anuncio.
- Un incentivo por unirse al grupo es el único atado a una acción social; likes y favoritos no se premian hasta leer la política vigente (hay un `[GAP]` en la nota del vault).
- Sin urgencia falsa, sin temporizadores que se reinician, sin culpa al salir (barra E10 del vault).

## Criterio de listo

- [ ] Tabla durable/consumible y mejora/expresión.
- [ ] Escalera de pases y momento del starter pack escritos.
- [ ] Fila de EV para todo azar y la rama para el jugador restringido.
- [ ] Lista "Creado antes de publicar" revisada.
- [ ] Nada que rompa el juego para quien no paga.
- [ ] Cumple la barra de economía y monetización del vault (`docs/bars/economy-monetization`).
- [ ] Victor aprobó los precios.

## Evidencia

Rango de pases de los referentes (nota del vault, medido con fecha), la nota `research/2026-11-12-monetizacion-y-proceso-de-grill` y la skill `roblox-monetization` aplicada.

- TBD
