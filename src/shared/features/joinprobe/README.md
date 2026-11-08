# features/joinprobe

Measure a join before changing constants. [ADR 0032](../../../../docs/adr/0032-join-architecture-data-as-background-state.md). Origin: plus-one-mining PR #60. Refs #47.

## What it is / is not

- Is: `ServerJoinProbe` (elapsed seconds between named stages: join, entitlements, hello, post), `ClientJoinProbe` (marks since the client started, plus bounds validation of the report on the server), `ProbeLine` (deterministic `[JOINPROBE] {json}` line), `JoinProbeSink` (optional persistence to a DataStore, one key per player per UTC day, last 40 entries).
- Is not: a change to the join. It only records. Profile data never enters a line.

## Tree

```
joinprobe/
  ProbeLine.luau        sorted keys, ms precision, non-finite numbers dropped
  ServerJoinProbe.luau  stages, prior session holder metadata, provisional line
  ClientJoinProbe.luau  marks, waits (allow-listed names), validate(raw)
  JoinProbeSink.luau    UpdateAsync-like port, never throws, warns once
```

## Use from a game

Create one probe per side with an injected clock; `begin` at PlayerAdded, `mark` per stage, `finish` for the report. Send the client report once (`claimSend`), validate it with `ClientJoinProbe.validate` on the server (it is remote input, ADR 0012) and add its remote to the budget. Gate everything behind a `joinProbe` flag; wire the sink only when `JoinProbeSink.shouldWire(probeOn, sinkOn, isStudio)`.

## Forbidden here

No engine globals, no profile `Data` in a line, no unbounded client numbers.

## Tests

`tests/features/joinprobe/`.
