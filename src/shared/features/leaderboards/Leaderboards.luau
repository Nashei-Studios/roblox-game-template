--!strict
--[[
    Leaderstats and global ordered boards (issue #25). Implements ports/Leaderboards. Pure: loads
    under Lune; the store, the views, the clock and the profiles are injected.

    Schedule (all numbers from Config, tested with a fake clock and a fake store):
    - Joining reads NOTHING from the store: `track` only fills leaderstats from the profile.
    - Writes: once per `writeSeconds` per tracked player and board, and only when the value
      changed since the last successful write of that store key; once more on `forget`.
    - Reads: one `top` per board every `refreshSeconds`; the result is cached and published.
      A failed read keeps the old cache and waits a full interval (no hammering a failing store).
    - A reset cycle changes the store key per UTC period, so the new list starts empty by itself.
    Failures are reported through `onError` with context; they never throw and never block.
]]

local BoardKey = require("./BoardKey")
local LeaderboardsConfig = require("./LeaderboardsConfig")
local OrderedBoardStore = require("../../ports/OrderedBoardStore")
local PlayerStats = require("./PlayerStats")
local Ports = require("../../ports/Leaderboards")

export type Entry = Ports.Entry

export type Deps = {
    config: LeaderboardsConfig.LeaderboardsConfig,
    store: OrderedBoardStore.OrderedBoardStore,
    view: Ports.StatView,
    publisher: Ports.BoardPublisher,
    -- Server clock, Unix seconds (os.time in production).
    now: () -> number,
    profileFor: (userId: number) -> PlayerStats.StatProfile?,
    onError: (message: string) -> (),
}

type Tracked = {
    -- Last value written per store key, so an unchanged score is not written again.
    written: { [string]: number },
    -- Last value pushed to the view per stat.
    shown: { [string]: number },
}

local LeaderboardsModule = {}

function LeaderboardsModule.new(deps: Deps): Ports.Leaderboards
    local tracked: { [number]: Tracked } = {}
    local cache: { [string]: { Entry } } = {}
    local lastRefresh: { [string]: number } = {}
    local lastWrite: number? = nil
    local ids = LeaderboardsConfig.sortedIds(deps.config)

    local function refreshView(userId: number, state: Tracked)
        local profile = deps.profileFor(userId)
        if profile == nil then
            return
        end
        for _, stat in deps.config.leaderstats do
            local value = PlayerStats.read(profile, stat)
            if value ~= nil and state.shown[stat] ~= value then
                state.shown[stat] = value
                deps.view:set(userId, stat, value)
            end
        end
    end

    local function writeScores(userId: number, state: Tracked, now: number)
        local profile = deps.profileFor(userId)
        if profile == nil then
            return
        end
        for _, id in ids do
            local board = deps.config.boards[id]
            local value = PlayerStats.read(profile, board.stat)
            local key = BoardKey.storeKey(id, board.resetCycle, now)
            if value ~= nil and state.written[key] ~= value then
                local stored = deps.store:setScore(key, userId, value)
                if stored.ok then
                    state.written[key] = value
                else
                    deps.onError(
                        `leaderboard "{id}" write for {userId} failed: {stored.error.message}`
                    )
                end
            end
        end
    end

    local function refreshBoards(now: number)
        for _, id in ids do
            local board = deps.config.boards[id]
            local previous = lastRefresh[id]
            if previous == nil or now - previous >= board.refreshSeconds then
                lastRefresh[id] = now
                local key = BoardKey.storeKey(id, board.resetCycle, now)
                local read = deps.store:top(key, board.size)
                if read.ok then
                    cache[id] = read.value
                    deps.publisher:publish(id, read.value, now)
                else
                    deps.onError(`leaderboard "{id}" read failed: {read.error.message}`)
                end
            end
        end
    end

    local service: Ports.Leaderboards = {
        track = function(_self: Ports.Leaderboards, userId: number)
            local state: Tracked = { written = {}, shown = {} }
            tracked[userId] = state
            refreshView(userId, state)
        end,
        forget = function(_self: Ports.Leaderboards, userId: number)
            local state = tracked[userId]
            if state == nil then
                return
            end
            writeScores(userId, state, deps.now())
            tracked[userId] = nil
            deps.view:remove(userId)
        end,
        tick = function(_self: Ports.Leaderboards)
            local now = deps.now()
            for userId, state in tracked do
                refreshView(userId, state)
            end
            if lastWrite == nil or now - lastWrite >= deps.config.writeSeconds then
                lastWrite = now
                for userId, state in tracked do
                    writeScores(userId, state, now)
                end
            end
            refreshBoards(now)
        end,
        top = function(_self: Ports.Leaderboards, boardId: string): { Entry }?
            return cache[boardId]
        end,
    }
    return service
end

return LeaderboardsModule
