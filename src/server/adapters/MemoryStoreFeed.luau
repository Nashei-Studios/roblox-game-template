--!strict
--[[
    Adapter: FeedStore over a MemoryStoreSortedMap (ADR 0053). The engine object is injected
    (ADR 0009): `handle` is three thin functions, so this file loads under Lune and is tested
    with fakes. Every call runs under pcall and a failure comes back as a typed error with its
    message; nothing is swallowed. The sort key is the entry time, so the newest come first.
]]

-- Structurally identical to ports/FeedStore.luau (kept local so this file loads under Lune).
type Item = { key: string, value: string, at: number }
type StoreError = { kind: "store_failed", message: string }
type WriteResult = { ok: true, value: nil } | { ok: false, error: StoreError }
type ReadResult = { ok: true, value: { Item } } | { ok: false, error: StoreError }
type FeedStore = {
    add: (self: FeedStore, item: Item, ttlSeconds: number) -> WriteResult,
    recent: (self: FeedStore, limit: number) -> ReadResult,
    remove: (self: FeedStore, key: string) -> WriteResult,
}

-- One MemoryStoreSortedMap, reduced to what the adapter needs.
export type Row = { key: string, value: unknown, sortKey: unknown }
export type MapHandle = {
    -- SetAsync(key, value, expiration, sortKey)
    set: (key: string, value: string, ttlSeconds: number, sortKey: number) -> (),
    -- GetRangeAsync(Descending, limit): rows newest first.
    range: (limit: number) -> { Row },
    -- RemoveAsync(key)
    remove: (key: string) -> (),
}

export type Deps = {
    handle: MapHandle,
}

local MemoryStoreFeed = {}

local function failed(message: unknown): { ok: false, error: StoreError }
    return { ok = false, error = { kind = "store_failed", message = tostring(message) } }
end

function MemoryStoreFeed.new(deps: Deps): FeedStore
    local handle = deps.handle
    local store: FeedStore = {
        add = function(_self: FeedStore, item: Item, ttlSeconds: number): WriteResult
            local called, failure = pcall(function()
                handle.set(item.key, item.value, ttlSeconds, item.at)
            end)
            if not called then
                return failed(failure)
            end
            return { ok = true, value = nil }
        end,
        recent = function(_self: FeedStore, limit: number): ReadResult
            local called, rows = pcall(function(): { Row }
                return handle.range(limit)
            end)
            if not called then
                return failed(rows)
            end
            local items: { Item } = {}
            for _, row in rows :: { Row } do
                -- Foreign data: only a text value and a numeric sort key are accepted.
                if type(row.value) == "string" and type(row.sortKey) == "number" then
                    table.insert(items, { key = row.key, value = row.value, at = row.sortKey })
                end
            end
            return { ok = true, value = items }
        end,
        remove = function(_self: FeedStore, key: string): WriteResult
            local called, failure = pcall(function()
                handle.remove(key)
            end)
            if not called then
                return failed(failure)
            end
            return { ok = true, value = nil }
        end,
    }
    return store
end

return MemoryStoreFeed
