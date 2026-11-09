--!strict
--[[
    Implementations of the PodiumSource port (ADR 0055), all pure so they load under Lune:
    - fromStore: a real read through the OrderedBoardStore port (its OrderedDataStore adapter is
      server/adapters/OrderedDataStoreBoards). Costs one GetSortedAsync per refresh.
    - fromCache: reads a top that is already cached (for example Leaderboards:top), so the podium
      adds no store read at all. This is what a game with a running Leaderboards should use.
    - inMemory: a table with a failure switch, for tests and a one-client Studio seed.
]]

local OrderedBoardStore = require("../../ports/OrderedBoardStore")
local PodiumSource = require("../../ports/PodiumSource")

export type Entry = PodiumSource.Entry

export type InMemory = PodiumSource.PodiumSource & {
    -- Replaces the entries the source answers with (best first).
    set: (self: InMemory, entries: { Entry }) -> (),
    -- While true every read fails, to test the empty-pedestal fallback.
    setFailing: (self: InMemory, failing: boolean) -> (),
    -- Number of reads so far.
    reads: (self: InMemory) -> number,
}

local PodiumSources = {}

local function sliced(entries: { Entry }, size: number): { Entry }
    local copy: { Entry } = {}
    for index = 1, math.min(size, #entries) do
        table.insert(copy, entries[index])
    end
    return copy
end

--- `keyFor` returns the store key to read now (BoardKey.storeKey(id, cycle, os.time())), so a
--- daily or weekly board follows its reset period.
function PodiumSources.fromStore(
    store: OrderedBoardStore.OrderedBoardStore,
    keyFor: () -> string
): PodiumSource.PodiumSource
    local source: PodiumSource.PodiumSource = {
        top = function(_self: PodiumSource.PodiumSource, size: number): PodiumSource.TopResult
            local read = store:top(keyFor(), size)
            if read.ok then
                return { ok = true, value = sliced(read.value, size) }
            end
            return {
                ok = false,
                error = { kind = "source_failed", message = read.error.message },
            }
        end,
    }
    return source
end

--- `readCached` returns the cached top, or nil before the first refresh (read as nobody yet).
function PodiumSources.fromCache(readCached: () -> { Entry }?): PodiumSource.PodiumSource
    local source: PodiumSource.PodiumSource = {
        top = function(_self: PodiumSource.PodiumSource, size: number): PodiumSource.TopResult
            local cached = readCached()
            if cached == nil then
                return { ok = true, value = {} }
            end
            return { ok = true, value = sliced(cached, size) }
        end,
    }
    return source
end

function PodiumSources.inMemory(initial: { Entry }): InMemory
    local entries = initial
    local failing = false
    local count = 0
    local source: InMemory
    source = {
        top = function(_self: PodiumSource.PodiumSource, size: number): PodiumSource.TopResult
            count += 1
            if failing then
                return { ok = false, error = { kind = "source_failed", message = "forced failure" } }
            end
            return { ok = true, value = sliced(entries, size) }
        end,
        set = function(_self: InMemory, next: { Entry })
            entries = next
        end,
        setFailing = function(_self: InMemory, value: boolean)
            failing = value
        end,
        reads = function(_self: InMemory): number
            return count
        end,
    }
    return source
end

return PodiumSources
