--!strict
--[[
    Port: persistent ordered scores, one board key per list (ADR 0022). The adapter
    src/server/adapters/OrderedDataStoreBoards implements it over OrderedDataStore. Server side
    only: no client path can write or read it. Calls yield in production.
]]

export type Entry = { userId: number, value: number }

export type StoreError = { kind: "store_failed", message: string }

export type SetResult = { ok: true, value: nil } | { ok: false, error: StoreError }

export type TopResult = { ok: true, value: { Entry } } | { ok: false, error: StoreError }

export type OrderedBoardStore = {
    -- Stores the player's score on the board (a non-negative integer).
    setScore: (
        self: OrderedBoardStore,
        boardKey: string,
        userId: number,
        value: number
    ) -> SetResult,
    -- The `size` highest scores, best first.
    top: (self: OrderedBoardStore, boardKey: string, size: number) -> TopResult,
}

return {}
