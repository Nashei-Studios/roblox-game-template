---
doc: ui-flows
stage: 2
revisit: 5
owner: el agente redacta; Nande y Leon aprueban
status: draft
as_of:
sections: Respuestas, Flujo de pantallas, Botones del HUD, Criterio de listo, Evidencia
---
# Flujos de interfaz

Pantallas, botones del HUD y a dónde lleva cada uno. La interfaz se construye con el sistema de UI del template (`docs/ui-system.md`, ADR 0035), nunca con `Instance.new` suelto.

## Preguntas que debe responder

1. ¿Qué pantallas existen y cómo se llega a cada una? (Diagrama Mermaid.)
2. ¿Qué botones tiene el HUD? Máximo 6 con teclado y 4 en móvil táctil (ADR 0065); cada uno con su destino.
3. ¿De qué kit sale el aspecto (`docs/ui-kit-intake.md`)?
4. ¿Cómo se ve cada pantalla en móvil vertical, móvil horizontal y escritorio?
5. ¿Qué pasa con el gamepad y con el teclado (foco y atajos)?
6. ¿Qué texto y qué iconos requiere, y en qué idioma?

## Respuestas

1. TBD
2. TBD
3. TBD
4. TBD
5. TBD
6. TBD

## Flujo de pantallas

```mermaid
flowchart TD
  HUD --> Tienda
  HUD --> Mejoras
```

## Botones del HUD

| Botón | Teclado | Móvil | Destino |
|---|---|---|---|
| TBD | TBD | TBD | TBD |

## Criterio de listo

- [ ] Diagrama Mermaid del flujo entre pantallas.
- [ ] Cada botón del HUD con su destino y dentro del límite (6 y 4).
- [ ] Kit de origen anotado.
- [ ] Vista móvil vertical y horizontal descrita.
- [ ] `lune run scripts/ui-audit` pasa para las piezas ya comprometidas.

## Evidencia

Enlace a las capturas del simulador de dispositivos o a la auditoría de UI (`docs/ui-audit.md`).

- TBD
