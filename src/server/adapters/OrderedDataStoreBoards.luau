--!strict
--[[
    Adapter: OrderedBoardStore over OrderedDataStore. The engine object is injected (ADR 0009):
    `openStore(name)` returns two thin functions, so this file loads under Lune and is tested with
    fakes. Every call runs under pcall and a failure comes back as a typed error with its message;
    nothing is swallowed. Store names are "Board_<boardKey>" and entry keys are the user id.
]]

-- Structurally identical to ports/OrderedBoardStore.luau (kept local so this file loads under Lune).
type Entry = { userId: number, value: number }
type StoreError = { kind: "store_failed", message: string }
type SetResult = { ok: true, value: nil } | { ok: false, error: StoreError }
type TopResult = { ok: true, value: { Entry } } | { ok: false, error: StoreError }
type OrderedBoardStore = {
    setScore: (
        self: OrderedBoardStore,
        boardKey: string,
        userId: number,
        value: number
    ) -> SetResult,
    top: (self: OrderedBoardStore, boardKey: string, size: number) -> TopResult,
}

-- One OrderedDataStore, reduced to what the adapter needs. `read` returns the best `size` rows.
export type StoreHandle = {
    write: (key: string, value: number) -> (),
    read: (size: number) -> { { key: string, value: number } },
}

export type Deps = {
    -- DataStoreService:GetOrderedDataStore(name) wrapped as a StoreHandle.
    openStore: (name: string) -> StoreHandle,
}

local STORE_PREFIX = "Board_"

local OrderedDataStoreBoards = {}

function OrderedDataStoreBoards.new(deps: Deps): OrderedBoardStore
    local handles: { [string]: StoreHandle } = {}

    local function handleFor(boardKey: string): StoreHandle
        local existing = handles[boardKey]
        if existing ~= nil then
            return existing
        end
        local opened = deps.openStore(STORE_PREFIX .. boardKey)
        handles[boardKey] = opened
        return opened
    end

    local store: OrderedBoardStore = {
        setScore = function(
            _self: OrderedBoardStore,
            boardKey: string,
            userId: number,
            value: number
        ): SetResult
            local called, failure = pcall(function()
                handleFor(boardKey).write(tostring(userId), math.max(0, math.floor(value)))
            end)
            if not called then
                return { ok = false, error = { kind = "store_failed", message = tostring(failure) } }
            end
            return { ok = true, value = nil }
        end,
        top = function(_self: OrderedBoardStore, boardKey: string, size: number): TopResult
            local called, rows = pcall(function()
                return handleFor(boardKey).read(size)
            end)
            if not called then
                return { ok = false, error = { kind = "store_failed", message = tostring(rows) } }
            end
            local entries: { Entry } = {}
            for _, row in rows :: { { key: string, value: number } } do
                local userId = tonumber(row.key)
                if userId ~= nil then
                    table.insert(entries, { userId = userId, value = row.value })
                end
            end
            return { ok = true, value = entries }
        end,
    }
    return store
end

return OrderedDataStoreBoards
