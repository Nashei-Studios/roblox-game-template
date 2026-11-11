# Espejo GitHub a Notion

Decisión y alternativas: [ADR 0065](adr/0065-group-workflow-github-source-notion-view.md). El espejo es de una sola vía: GitHub manda, Notion muestra. Lo que se edite en Notion se pisa en el siguiente evento.

## Qué es y qué no es

- Es el workflow `.github/workflows/notion-mirror.yml` más `scripts/notion-mirror.mjs`. Corre con cada evento de issue o PR y crea o actualiza una fila en una base de Notion.
- No es la integración oficial de Notion para GitHub, no sincroniza comentarios ni el Project, y no escribe nunca en GitHub.
- Está **inactivo** mientras falte el secreto `NOTION_TOKEN` o la variable `NOTION_DATABASE_ID`: imprime una línea y termina bien.

## Cómo activarlo (lo hace Victor, una vez)

1. En Notion crea una integración interna (notion.so/my-integrations) y copia su token.
2. Crea una base de datos con estas propiedades exactas: `Name` (título), `Ref` (texto), `Kind` (select), `State` (select), `Labels` (multi-select), `Assignees` (texto), `URL` (url), `Updated` (fecha).
3. En la base: menú ..., Connections, añade la integración.
4. En el repo: Settings, Secrets and variables, Actions. Secret `NOTION_TOKEN` con el token. Variable `NOTION_DATABASE_ID` con el id de la base (los 32 caracteres de su URL).
5. Abre o edita cualquier issue y revisa en la pestaña Actions que `notion-mirror` corrió y la fila apareció.

## Cómo se prueba

`node --test tests/tools/notion-mirror.test.mjs` (sin red: usa un Notion simulado). Cubre el mapeo, la creación y la actualización por `Ref`, la inactividad sin secreto y que un error no filtre el token.

## Límites conocidos

- Solo se espejan los eventos desde que se activa. Para traer el historial, edita o re-etiqueta cada issue, o ejecuta el script con un payload por issue.
- La API de Notion limita a unas 3 solicitudes por segundo por integración; el volumen de un equipo de tres no se acerca.
- Un issue borrado en GitHub no se borra en Notion.
- La versión de la API fijada es 2022-06-28 (consulta por `databases/{id}/query`). Si Notion la retira, hay que migrar a data sources.
