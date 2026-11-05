--!strict
--[[
    Port: leaderstats and global boards. In-house implementation: features/leaderboards/Leaderboards.
    Callers (Main.server) depend on this type only, so a pack adapter can plug in later (ADR 0022).
    Server to client only: values reach players through replicated instances written by the
    StatView and BoardPublisher ports; there is no remote and no client write path.
]]

export type Entry = { userId: number, value: number }

-- The player's scores shown next to the name (Roblox "leaderstats"). A view of PlayerData.
export type StatView = {
    set: (self: StatView, userId: number, stat: string, value: number) -> (),
    -- Drops the player's view (call when the player leaves).
    remove: (self: StatView, userId: number) -> (),
}

-- Where the cached top of a board is shown to everyone (a replicated value the client reads).
export type BoardPublisher = {
    publish: (self: BoardPublisher, boardId: string, entries: { Entry }, updatedAt: number) -> (),
}

export type Leaderboards = {
    -- A player joined and their data is loaded: starts their leaderstats. No store read.
    track: (self: Leaderboards, userId: number) -> (),
    -- A player is leaving: writes their changed scores once and forgets them.
    forget: (self: Leaderboards, userId: number) -> (),
    -- Call about once per second: refreshes leaderstats, runs due writes and due board reads.
    tick: (self: Leaderboards) -> (),
    -- The cached top of a board (nil before the first refresh or for an unknown board).
    top: (self: Leaderboards, boardId: string) -> { Entry }?,
}

return {}
