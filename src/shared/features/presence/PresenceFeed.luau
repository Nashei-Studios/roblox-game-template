--!strict
--[[
    The presence feed (ADR 0053): what players did in the last hours in ANY server of the game,
    so a one-player server still shows a living world. Pure: loads under Lune; the shared store,
    the Roblox text filter and the clock are injected.

    - `record` writes one entry of a declared kind. A name is stored only after the text filter
      accepted it; if the filter fails the entry is dropped (nothing unfiltered leaves the server).
    - Per player and kind a minimum gap applies, so one player cannot fill the feed.
    - The feed is capped: after a write the oldest entries past `maxEntries` are removed.
    - `read` is cached for `readCacheSeconds`. A failed read keeps the old cache and waits a full
      interval (no hammering a failing store). Expired, malformed and undeclared items are never
      returned.
    Failures go through `onError` with context; nothing throws and nothing is swallowed.
]]

local FeedStore = require("../../ports/FeedStore")
local PresenceConfig = require("./PresenceConfig")
local PresenceEntry = require("./PresenceEntry")

export type Entry = PresenceEntry.Entry

export type NameResult = { ok: true, value: string } | { ok: false, error: string }

export type Deps = {
    config: PresenceConfig.PresenceConfig,
    store: FeedStore.FeedStore,
    -- TextService:FilterStringAsync wrapped; may yield.
    filterName: (userId: number, name: string) -> NameResult,
    -- Server clock, Unix seconds (os.time in production).
    now: () -> number,
    onError: (message: string) -> (),
}

export type Outcome = "recorded" | "skipped_gap" | "unknown_kind" | "filter_failed" | "store_failed"

export type Feed = {
    record: (self: Feed, kind: string, userId: number, name: string, value: number) -> Outcome,
    -- The live entries of the last `ttlSeconds`, newest first (cached).
    read: (self: Feed) -> { Entry },
}

local PresenceFeed = {}

function PresenceFeed.new(deps: Deps): Feed
    local config = deps.config
    local declared: { [string]: boolean } = {}
    for _, kind in config.kinds do
        declared[kind.id] = true
    end
    local lastRecorded: { [string]: number } = {}
    local cache: { Entry } = {}
    local lastRead: number? = nil

    local function trim()
        local listed = deps.store:recent(config.maxEntries + 5)
        if not listed.ok then
            deps.onError(`presence trim read failed: {listed.error.message}`)
            return
        end
        local items = listed.value
        for index = config.maxEntries + 1, #items do
            local removed = deps.store:remove(items[index].key)
            if not removed.ok then
                deps.onError(`presence trim remove failed: {removed.error.message}`)
            end
        end
    end

    local feed: Feed = {
        record = function(
            _self: Feed,
            kind: string,
            userId: number,
            name: string,
            value: number
        ): Outcome
            if not declared[kind] then
                return "unknown_kind"
            end
            local now = deps.now()
            local gapKey = `{userId}:{kind}`
            local previous = lastRecorded[gapKey]
            if previous ~= nil and now - previous < config.minGapSeconds then
                return "skipped_gap"
            end
            local filtered = deps.filterName(userId, name)
            if not filtered.ok then
                deps.onError(`presence name filter failed: {filtered.error}`)
                return "filter_failed"
            end
            local entry: Entry = {
                kind = kind,
                userId = userId,
                value = math.max(0, math.floor(value)),
                at = now,
                name = PresenceEntry.cleanName(filtered.value, config.maxNameLength),
            }
            if entry.name == "" then
                return "filter_failed"
            end
            local written = deps.store:add({
                key = `{now}-{userId}-{kind}`,
                value = PresenceEntry.encode(entry),
                at = now,
            }, config.ttlSeconds)
            if not written.ok then
                deps.onError(`presence write failed: {written.error.message}`)
                return "store_failed"
            end
            lastRecorded[gapKey] = now
            lastRead = nil
            trim()
            return "recorded"
        end,
        read = function(_self: Feed): { Entry }
            local now = deps.now()
            local last = lastRead
            if last ~= nil and now - last < config.readCacheSeconds then
                return cache
            end
            lastRead = now
            local result = deps.store:recent(config.maxEntries)
            if not result.ok then
                deps.onError(`presence read failed: {result.error.message}`)
                return cache
            end
            local live: { Entry } = {}
            for _, item in result.value do
                local entry = PresenceEntry.decode(item.value)
                if entry ~= nil and declared[entry.kind] and now - entry.at < config.ttlSeconds then
                    table.insert(live, entry)
                end
            end
            table.sort(live, function(a: Entry, b: Entry): boolean
                return a.at > b.at
            end)
            cache = live
            return cache
        end,
    }
    return feed
end

return PresenceFeed
