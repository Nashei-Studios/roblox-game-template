# 0070 — No direct push to develop

- **Estado:** aceptado
- **Fecha:** 2026-11-13
- **Supersede:** la parte de [0066](0066-branch-guard-without-server-rules.md) que dejaba pasar un push directo a `develop`.

## Contexto

ADR 0066 dejó el hook `pre-push` frenando el push directo a `main`, el borrado de `main` y `develop` y la reescritura de ambas. Un push directo (fast-forward) a `develop` seguía permitido, aunque el flujo del estudio es ramas cortas, PR chicas con squash y automerge al verde. Un push directo salta el CI y el squash, y `audit-push` solo lo detecta después.

## Opciones consideradas

1. **Dejarlo como está** — sin fricción · `develop` puede recibir código sin CI.
2. **Rechazar todo push a `develop` en el hook** — mismo mensaje guía que `main`, misma salida de emergencia · el hook sigue siendo local y se puede saltar.
3. **Cambiar a repos públicos para tener rulesets** — ya descartado en 0066.

## Decisión

**Opción 2.** `.githooks/pre-push` rechaza cualquier push a `refs/heads/develop` (alta, avance, reescritura) con el mensaje "Push a short branch and open a PR". El borrado de `main` y `develop` y el push a `main` siguen igual. `ALLOW_PROTECTED_PUSH=1` sigue siendo la salida de emergencia. El hook solo actúa sobre `refs/heads/main` y `refs/heads/develop`: `chore/template-sync`, `release` y cualquier otra rama no se tocan, y los merges de PR ocurren en el servidor, sin pasar por el hook.

## Consecuencias

- Positivas: todo el código entra a `develop` por PR con CI; el mensaje guía dice qué hacer.
- Negativas: sigue sin ser garantía del servidor (`--no-verify`, máquinas sin bootstrap). Un arreglo urgente exige abrir una PR o usar la salida de emergencia avisando al equipo.
- Qué haría revisar esta decisión: rulesets disponibles en repos privados del plan gratis.
