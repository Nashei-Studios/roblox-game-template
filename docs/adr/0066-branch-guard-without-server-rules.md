# 0066 — Guard for main and develop when the server cannot enforce rules

- **Estado:** aceptado
- **Fecha:** 2026-11-11

## Contexto

Victor pide que `main` y `develop` estén protegidas en todo repo: un comando destructivo no puede borrar ni reescribir una rama permanente. GitHub solo hace cumplir rulesets y branch protection en repos públicos o en planes pagados. Probado el 2026-11-11 en `Nashei-Studios`: la API responde 403 en un repo privado y la interfaz avisa que la regla no se aplica. Los juegos son privados y no se paga ningún plan.

## Opciones consideradas

1. **Hacer públicos todos los repos** — reglas reales del servidor · expone el código de cada juego, que se puede copiar.
2. **Solo convención** (rama por defecto, PR, CI) — cero costo · no detiene un `push --force` ni un borrado; depende de que nadie se equivoque.
3. **Defensa en capas sin servidor** — hook `pre-push` versionado (previene), workflow `audit-push` (detecta y guarda la punta anterior), rulesets donde el repo es público · no es un bloqueo real: el hook se puede saltar y solo existe en máquinas que corrieron el bootstrap.

## Decisión

**Opción 3**, y rulesets reales en los repos públicos (plantilla, `studio`, `.github`).

- `.githooks/pre-push`, activado por `scripts/bootstrap.ps1` con `core.hooksPath`: rechaza push directo a `main`, borrado de `main` o `develop`, y reescritura de historia en ambas.
- `.github/workflows/audit-push.yml`: en cada push a `main` o `develop` guarda la punta anterior en `refs/backup/<rama>/<fecha>` y abre un issue si el push fue forzado o no vino de una PR.
- Cada juego hereda las dos piezas al estamparse.

## Consecuencias

- Positivas: un error local se detiene antes de salir; uno que pase queda registrado y con la punta anterior recuperable; no cuesta plan ni expone el código.
- Negativas: no es garantía. Quien no corrió el bootstrap no tiene el hook; `ALLOW_PROTECTED_PUSH=1` o `--no-verify` lo saltan; los pushes hechos con `GITHUB_TOKEN` no disparan `audit-push`; borrar una rama no dispara un push de rama, así que el borrado solo lo frena el hook. `refs/backup/` crece y hay que podarlo.
- Qué haría revisar esta decisión: que GitHub habilite rulesets en privados del plan gratis, que un juego pase a público, o un incidente que el hook no detuvo.
