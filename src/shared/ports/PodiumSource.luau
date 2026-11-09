--!strict
--[[
    Port: where the podium reads the top of its board (ADR 0056). Implementations live in
    features/podium/PodiumSources: one over the OrderedBoardStore port (a real read), one over an
    already cached top (no extra store read), and an in-memory fake for tests and a one-client
    Studio seed. Server side only. Calls may yield in production.
]]

export type Entry = { userId: number, value: number }

export type SourceError = { kind: "source_failed", message: string }

export type TopResult = { ok: true, value: { Entry } } | { ok: false, error: SourceError }

export type PodiumSource = {
    -- The `size` highest entries, best first. An empty list is a valid answer (nobody yet).
    top: (self: PodiumSource, size: number) -> TopResult,
}

return {}
