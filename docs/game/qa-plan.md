---
doc: qa-plan
stage: 3
revisit: 9
owner: el agente redacta; lo revisa otra sesión que no escribió el código
status: draft
as_of:
sections: Respuestas, Matriz de pruebas, Criterio de listo, Evidencia
---
# Plan de QA

Qué se prueba y cómo, antes de publicar. Molde adaptado de `test-plan` de Claude Code Game Studios (MIT, ver `THIRD-PARTY.md`).

## Preguntas que debe responder

1. ¿Qué prueba automática cubre cada sistema de `systems-index.md` (Lune, propiedades y fuzz del ADR 0062)?
2. ¿Qué se verifica a mano y con qué evidencia (captura, video, partida de dos clientes)?
3. ¿Cuáles son los casos borde sacados de `systems/` y de `economy.md` (cero, tope, reintento de compra, desconexión)?
4. ¿Qué dispositivos del simulador se prueban (teléfono vertical, tableta, escritorio) y cuál es la lista?
5. ¿Qué cubre la prueba de humo antes de cada publicación?
6. ¿Quién firma y en qué orden? Quien prueba no es quien escribió el código.
7. ¿Qué dice la puerta local del template (`stylua`, `selene`, analyze, tests, cobertura, perf-budget, build)?

## Respuestas

1. TBD
2. TBD
3. TBD
4. TBD
5. TBD
6. TBD
7. TBD

## Matriz de pruebas

| Sistema | Prueba automática | Prueba manual | Casos borde | Estado |
|---|---|---|---|---|
| TBD | TBD | TBD | TBD | TBD |

## Criterio de listo

- [ ] Matriz sistema a prueba (Lune, Studio por MCP, manual).
- [ ] Casos borde sacados de `systems/`.
- [ ] Lista de dispositivos del simulador.
- [ ] La puerta local del template está en verde.
- [ ] Lo firma una sesión o persona que no escribió el código.

## Evidencia

Salida de la puerta local (comando y código de salida) y capturas o notas de la prueba manual.

- TBD
