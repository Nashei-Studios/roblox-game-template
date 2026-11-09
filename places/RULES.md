# RULES: places

Owner: `owner:victor`.

## What it is
`dev.rbxl` is a local file built with `rojo build` for headless checks. It is not the live place and is never published (ADR 0045). The shared place lives in Team Create.

## Forbidden
- Publishing a file from here over the live place: it would erase the art.
- Merging place files. Each one has one owner.

## Handoff
Post a comment on the pinned **Agent Board** issue: what is done, what is left, the branch or PR, and an `@mention` of the next owner (`@vruizz22`, `@<nande-gh>`, `@<leon-gh>`, or the agent role). Add the `handoff` label to the issue you pass on. Do not message anyone elsewhere; the board is the record. Method and labels: `docs/team-workflow.md`.
