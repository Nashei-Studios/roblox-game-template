--!strict
--[[
    A FeedStore kept in a table (ADR 0053), for tests and for a one-client Studio playtest:
    seed it with `PresenceFixture`-style entries so the wall is not empty. It honours the port
    contract: newest first, `remove`, and a TTL checked against an injected clock. Never the
    production store; the production adapter is server/adapters/MemoryStoreFeed.
]]

local FeedStore = require("../../ports/FeedStore")

export type Options = {
    -- Clock for the TTL, Unix seconds.
    now: () -> number,
    -- Make the next calls fail, to test the error paths.
    failWrites: boolean,
    failReads: boolean,
}

export type Store = {
    options: Options,
    add: (self: Store, item: FeedStore.Item, ttlSeconds: number) -> FeedStore.WriteResult,
    recent: (self: Store, limit: number) -> FeedStore.ReadResult,
    remove: (self: Store, key: string) -> FeedStore.WriteResult,
    size: (self: Store) -> number,
}

type Stored = { item: FeedStore.Item, expiresAt: number }

local InMemoryFeedStore = {}

function InMemoryFeedStore.new(now: () -> number): Store
    local stored: { Stored } = {}
    local options: Options = { now = now, failWrites = false, failReads = false }

    local function live(): { Stored }
        local current = options.now()
        local kept: { Stored } = {}
        for _, row in stored do
            if row.expiresAt > current then
                table.insert(kept, row)
            end
        end
        stored = kept
        table.sort(stored, function(a: Stored, b: Stored): boolean
            return a.item.at > b.item.at
        end)
        return stored
    end

    local store: Store
    store = {
        options = options,
        add = function(
            _self: Store,
            item: FeedStore.Item,
            ttlSeconds: number
        ): FeedStore.WriteResult
            if options.failWrites then
                return { ok = false, error = { kind = "store_failed", message = "write down" } }
            end
            for index, row in stored do
                if row.item.key == item.key then
                    table.remove(stored, index)
                    break
                end
            end
            table.insert(stored, { item = item, expiresAt = options.now() + ttlSeconds })
            return { ok = true, value = nil }
        end,
        recent = function(_self: Store, limit: number): FeedStore.ReadResult
            if options.failReads then
                return { ok = false, error = { kind = "store_failed", message = "read down" } }
            end
            local items: { FeedStore.Item } = {}
            for _, row in live() do
                if #items < limit then
                    table.insert(items, row.item)
                end
            end
            return { ok = true, value = items }
        end,
        remove = function(_self: Store, key: string): FeedStore.WriteResult
            if options.failWrites then
                return { ok = false, error = { kind = "store_failed", message = "write down" } }
            end
            for index, row in stored do
                if row.item.key == key then
                    table.remove(stored, index)
                    break
                end
            end
            return { ok = true, value = nil }
        end,
        size = function(_self: Store): number
            return #live()
        end,
    }
    return store
end

return InMemoryFeedStore
