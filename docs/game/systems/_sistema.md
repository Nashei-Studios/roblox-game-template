---
doc: sistema-molde
stage: 2
owner: el agente redacta; el dueño del frente aprueba
status: draft
as_of:
sections: Resumen, Reglas, Estados, Interacciones, Fórmulas, Casos borde, Perillas de ajuste, Dependencias, Criterio de listo, Evidencia
---
# Sistema: TBD

Copia este archivo a `systems/<nombre>.md`, cambia `doc: sistema-molde` por `doc: <nombre>` y llénalo. Los archivos que empiezan con `_` no los valida `docs-check`; los copiados sí. Solo los sistemas con fórmulas llevan archivo.

## Resumen
Qué hace el sistema en dos frases y qué parte del loop sirve.

## Reglas
Lista numerada de reglas verificables.

## Estados
Los estados del sistema y las transiciones (diagrama Mermaid `stateDiagram-v2` si hay más de tres).

## Interacciones
Con qué otros sistemas habla y qué contrato (remote, evento, módulo).

## Fórmulas
Cada fórmula con sus variables, unidades y los valores iniciales. Los valores viven en una hoja (`balance/*.csv`) o en `Config`, no solo en prosa.

## Casos borde
Qué pasa en el límite: cero, máximo, desconexión, dos jugadores a la vez, reintento de compra.

## Perillas de ajuste
Qué números se tocan para balancear y su rango seguro.

## Dependencias
Qué necesita este sistema y qué lo necesita a él.

## Criterio de listo

- [ ] Las ocho secciones tienen contenido.
- [ ] Las fórmulas tienen sus números y una prueba en el repo que fija las bandas.
- [ ] Sin dependencias circulares con otros sistemas.

## Evidencia

Enlace a la prueba (`tests/...`), a la hoja o al dato medido.

- TBD
