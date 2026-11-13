---
doc: community
stage: 2
revisit: 11
owner: el grupo decide; el agente redacta
status: draft
as_of:
sections: Respuestas, Recompensa por unirse, Criterio de listo, Evidencia
---
# Recompensa de comunidad

El estudio usa un solo grupo de Roblox para todos sus juegos: [Nashei Studios, id 405835365](https://www.roblox.com/communities/405835365). Unirse al grupo es un canal prestado de crecimiento (ver `docs/win-condition-checklist.md`) y tiene una recompensa en el juego. Este documento declara cuál es y cómo se muestra. La mecánica ya existe en el template: la recompensa única de unirse (ADR 0026, `community-reward`) y el beneficio duradero de miembro (ADR 0037, `CommunityPerk`, detrás del puerto `MembershipChecker`).

## Preguntas que debe responder

1. ¿Qué recibe quien se une: monedas una vez (ADR 0026), un porcentaje duradero (ADR 0037) o ambas? ¿Cuánto, con qué números de `economy.md`?
2. ¿Dónde se anuncia (HUD, tienda, pantalla de carga) y en qué minuto de la sesión? ¿Se puede ignorar sin castigo?
3. ¿Cómo se verifica la membresía (`Player:IsInGroupAsync` detrás del puerto) y qué hace el juego si la consulta falla?
4. ¿El grupo es el mismo para todos los juegos? Sí: id 405835365. Si este juego usa otro, ¿por qué? (Es una excepción y lleva ADR.)
5. ¿Qué publica el estudio en el grupo (updates, códigos, eventos) y quién lo hace?
6. ¿Cómo se mide el efecto (miembros nuevos por día, conversión de la oferta)?

## Respuestas

1. TBD
2. TBD
3. TBD
4. TBD
5. TBD
6. TBD

## Recompensa por unirse

| Recompensa | Tipo | Valor | Dónde se muestra |
|---|---|---|---|
| TBD | TBD | TBD | TBD |

## Criterio de listo

- [ ] Recompensa nombrada con su número y su fuente en `economy.md`.
- [ ] El id del grupo es 405835365 o la excepción tiene ADR.
- [ ] Enlaza los ADR 0026 y 0037 del template.
- [ ] La oferta es opcional y no bloquea el juego.
- [ ] Hay un evento de analítica para ver cuántos se unen.

## Evidencia

Enlaces: [ADR 0026](../adr/0026-ui-kit-leaderboards-community-reward.md), [ADR 0037](../adr/0037-community-perk.md), [el grupo](https://www.roblox.com/communities/405835365).

- TBD
