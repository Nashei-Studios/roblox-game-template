# features/presence

What other players did in the last hours, in any server, for a wall or a panel, so a one-player server still shows a living world. Decision: [ADR 0053](../../../../docs/adr/0053-presence-board-over-a-feed-store.md). Source: game 1 ghost presence board, with its kinds and words moved to config.

## What it is / is not

- Is: pure Luau that loads under Lune. A capped feed over a `FeedStore` port, a codec for entries that trusts nothing, and a board that picks and words rows from templates the game declares.
- Is not: the store (that is `server/adapters/MemoryStoreFeed`), the name filter (`server/adapters/TextServiceNameFilter`), the wall or panel (a presenter of the game UI), or a remote. It has no remote.

## Tree

```
presence/
  PresenceConfig.luau   kinds (id, pick, rows, templates), caps, empty state; problems()
  PresenceEntry.luau    entry type, encode / decode, cleanName
  PresenceFeed.luau     record (kind, gap, filter, write, trim) and cached read
  PresenceBoard.luau    build, ago, encode / decode, rows
  InMemoryFeedStore.luau  the port in a table, for tests and a one-client Studio seed
ports/FeedStore.luau
server/adapters/MemoryStoreFeed.luau        MemoryStoreSortedMap over the port
server/adapters/TextServiceNameFilter.luau  FilterStringAsync over a typed result
```

Why split: the rules (cap, TTL, gap, picking) change with design; the store and the filter change with the engine; the wall changes with art.

## Adopt in a game

1. Declare the kinds, for example `{ id = "record", pick = "max", rows = 1, headline = "{name}  {value} pts", detail = "Best score  {ago}" }`, and call `PresenceConfig.problems` at bootstrap.
2. On the server build `MemoryStoreFeed.new({ handle })` over `MemoryStoreService:GetSortedMap(...)`, wrap the filter with `TextServiceNameFilter.new`, and create `PresenceFeed.new({ config, store, filterName, now = os.time, onError })`.
3. Call `feed:record(kind, userId, name, value)` from the server feature that knows the thing happened (not from a client).
4. Publish `PresenceBoard.encode(PresenceBoard.build(feed:read(), os.time(), config))` into one replicated value (a `StringValue`) on a timer slightly longer than `readCacheSeconds`.
5. On the client `PresenceBoard.rows(PresenceBoard.decode(text), os.time(), config)` and draw the rows with the game UI. Studio only: seed an `InMemoryFeedStore` with entries of other players.

## Add a new kind

Add a `KindDef` to the config (id, `max` or `newest`, rows, two templates) and a `record` call; add a case to the test of your game config. No code in this folder changes.

## Forbidden here

A remote that lets a client write or read the feed, a name stored without passing the filter, engine calls (`game:`, `Instance.new`) in this folder, game words in ids or templates of the mold, trusting a stored row without `decode`.

## Tests

`tests/features/presence/Presence.test.luau` (config, codec, feed, cap, cache, foreign items, board, wire, the in-memory store and both adapters), registered in `scripts/suites.luau`.
