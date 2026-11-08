# 0038. LiveOps-lite: server-authoritative timed rotation

- Status: accepted
- Date: 2026-11-08
- Deciders: Victor Ruiz
- Refs: #86, #55, referent-features-matrix F31, S08

## Context

Mine a Mountain advertises "a new mountain every hour", Crypto Empire restocks its shop on a visible timer, and the seasonal updates of Tower Defense Simulator and Venom Evolution revolve around dated events. These give players a reason to come back on a clock. Issue #55 asks for a full event calendar, server events and global events over MessagingService; that is a larger design.

## Options

| Option | Notes |
|---|---|
| A. Full LiveOps now (calendar editor, MessagingService fan-out, ConfigService) | Needs live testing in Studio and a cross-server design; blocks the simple case |
| B. A pure scheduler where state is a function of `now` | Chosen as the first slice: no store, no message, same answer on every server |
| C. Persist the current rotation in a MemoryStore | Adds a failure mode and a write path for something computable |

No open-source piece applies; the platform pieces (MessagingService, ConfigService) are listed in the ecosystem map for the later slice.

## Decision

Option B. `LiveOps` holds rotation slots (period, anchor, cycled entries) and event windows (start, duration, optional repetition). All answers derive from the injected server clock. `poll` returns the changes since the previous poll with a baseline on the first call, so announcements never fire at server start.

## Consequences

- Positive: deterministic and testable under Lune; servers agree without coordination; the client cannot influence what is active; `periodIndex` can drive `OfferRail`.
- Negative: events are decided at config time, so an ad hoc live event needs the later ConfigService or MessagingService slice; clock skew between servers is bounded by the platform clock, not corrected here; the module does not persist which announcements were shown.
- Lost: no calendar UI; #55 stays open for global events.

## What would change this

A need for events created without a deploy (then Experience Config feeds the same `events` shape), or per-player rotations (then the slot gets a player-seeded entry list).
