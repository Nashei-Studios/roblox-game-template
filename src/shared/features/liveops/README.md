# features/liveops

Timed rotations and recurring event windows on a server-authoritative clock. Decision: [ADR 0038](../../../../docs/adr/0038-liveops-lite-timed-rotation.md). Issue #86 (first slice of #55). Matrix rows F31, F32 (partly), S08 in [referent-features-matrix](../../../../docs/referent-features-matrix.md).

## What it is / is not

- Is: pure Luau that loads under Lune. Rotation slots ("a new zone every hour", "the shop restocks every 5 minutes") and event windows (one-off or recurring, for example a weekend) are functions of the server's `now`, so every server agrees with no store and no message. `poll` tells the game what changed since the last poll so it can announce it.
- Is not: cross-server or global events (MessagingService, still #55), a reward, a UI or a calendar editor. The client never decides what is active; it only displays the absolute times the server sends.

## Tree

```
liveops/
  LiveOps.luau   config types + validate, rotationAt, occurrenceAt, LiveOps.new (rotation, activeEvents, isActive, snapshot, poll)
```

One file on purpose: the pieces share the same types and are about 250 lines together. Split it when a second clock source (MessagingService) arrives.

## Use from a game

1. Declare slots (`id`, `periodSeconds`, `anchorSeconds`, `entries`) and events (`startsAt`, `durationSeconds`, optional `repeatEverySeconds`) in config; call `LiveOps.validate` in the bootstrap and refuse to start on problems.
2. Build `LiveOps.new({ config, now = os.time })` once on the server.
3. Gate server logic on `isActive(eventId)` and on `rotation(slotId).entry`; never on anything the client says.
4. Every few seconds call `poll()`; announce the changes (toast, chat) and refresh the clients with `snapshot()`.
5. Feed `rotation(slotId).periodIndex` to `OfferRail` as `rotationIndex` for rotating shop offers.

## Forbidden here

No client clock, no `os.time` call inside the module, no reward granting, no game vocabulary in ids.

## Tests

`tests/features/liveops/LiveOps.test.luau`, registered in `scripts/suites.luau`.
