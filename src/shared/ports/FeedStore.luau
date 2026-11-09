--!strict
--[[
    Port: a capped, time-ordered feed shared by every server of the game (ADR 0053). The adapter
    src/server/adapters/MemoryStoreFeed implements it over a MemoryStoreSortedMap. Server side
    only: no client path can write or read it. Calls yield in production.
]]

-- `value` is opaque text (features/presence/PresenceEntry encodes it); `at` is Unix seconds and
-- is the sort key, so `recent` returns the newest first.
export type Item = { key: string, value: string, at: number }

export type StoreError = { kind: "store_failed", message: string }

export type WriteResult = { ok: true, value: nil } | { ok: false, error: StoreError }

export type ReadResult = { ok: true, value: { Item } } | { ok: false, error: StoreError }

export type FeedStore = {
    -- Adds one item that the store forgets by itself after `ttlSeconds`.
    add: (self: FeedStore, item: Item, ttlSeconds: number) -> WriteResult,
    -- The `limit` newest items, newest first.
    recent: (self: FeedStore, limit: number) -> ReadResult,
    -- Drops one item (used to keep the feed at its cap).
    remove: (self: FeedStore, key: string) -> WriteResult,
}

return {}
