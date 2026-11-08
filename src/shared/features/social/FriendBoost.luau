--!strict
--[[
    Friend Boost (ADR 0030, 0031): +perFriendPct % of the game's perk per friend in the same server,
    capped. A perk multiplier only, never a currency grant. Pure: loads under Lune; `isFriendsWith` and `spawn` are injected.

    Rules:
    - The friendship of a pair is asked once and kept; answers die with either player's leave.
    - Questions run in parallel, at most `maxConcurrentChecks` at a time, each in its own thread
      (`spawn`), so a slow call never delays another player's join.
    - Players are walked through array copies: a call that yields while another player joins can
      never see a table change under a `for ... in`.
    - An answer is stored only if both players are still here and the question was not cancelled by
      a leave; a player who leaves and comes back is asked again.
    - A failed call, or one that answers something other than a boolean, counts 0 %, is not
      stored and never raises. `refreshUnanswered` asks again for exactly those pairs.
    - `boostPct` is O(1): the count of friends only changes when an answer arrives or a player
      leaves, and it is kept, not recomputed.
]]

local SocialConfig = require("./SocialConfig")

export type Deps = {
    -- Player:IsFriendsWith adapter. May yield or throw.
    isFriendsWith: (userId: number, otherUserId: number) -> boolean,
    -- Runs a function in its own thread (task.spawn in the game).
    spawn: (run: () -> ()) -> (),
    config: SocialConfig.SocialConfig?,
    -- Called for a player right BEFORE their friend count changes, so the caller can settle
    -- anything paid at the old rate. Errors are swallowed.
    beforeChange: ((userId: number) -> ())?,
    -- Called after a pair got an answer. Errors are swallowed.
    onResolved: ((userId: number, otherUserId: number) -> ())?,
}

export type FriendBoost = {
    -- A player joined. Asks about every pair with the players already present.
    onJoin: (self: FriendBoost, userId: number) -> (),
    onLeave: (self: FriendBoost, userId: number) -> (),
    -- Asks again for every present pair with no answer and no question in flight. Returns how
    -- many questions were queued.
    refreshUnanswered: (self: FriendBoost) -> number,
    -- Whole percent, 0 to capPct.
    boostPct: (self: FriendBoost, userId: number) -> number,
}

type Job = { first: number, second: number }

local FriendBoostModule = {}

--- The boost for a friend count, in whole percent.
function FriendBoostModule.pctFor(config: SocialConfig.SocialConfig, friends: number): number
    local raw = math.max(0, friends) * config.friendBoost.perFriendPct
    return math.floor(math.min(raw, config.friendBoost.capPct) + 0.5)
end

local function keysOf(set: { [number]: unknown }): { number }
    local keys: { number } = {}
    for key in set do
        table.insert(keys, key)
    end
    return keys
end

function FriendBoostModule.new(deps: Deps): FriendBoost
    local config = deps.config or SocialConfig.default
    local maxInFlight = config.friendBoost.maxConcurrentChecks
    local present: { [number]: boolean } = {}
    -- answers[a][b] = are they friends; the same fact is stored under both players.
    local answers: { [number]: { [number]: boolean } } = {}
    -- Friends present, kept in step with `answers`.
    local counts: { [number]: number } = {}
    -- pending[a][b] = the job asking about this pair; a job whose entry changed was cancelled.
    local pending: { [number]: { [number]: Job } } = {}
    local queue: { Job } = {}
    local inFlight = 0

    local function guarded(callback: () -> ())
        pcall(callback)
    end

    local function changing(userId: number)
        local before = deps.beforeChange
        if before ~= nil then
            guarded(function()
                before(userId)
            end)
        end
    end

    local pump: () -> ()

    local function record(job: Job, friends: boolean)
        answers[job.first][job.second] = friends
        answers[job.second][job.first] = friends
        if friends then
            counts[job.first] += 1
            counts[job.second] += 1
        end
    end

    local function run(job: Job)
        local called, answer = pcall(deps.isFriendsWith, job.first, job.second)
        inFlight -= 1
        local own = pending[job.first]
        if own ~= nil and own[job.second] == job then
            own[job.second] = nil
            local other = pending[job.second]
            if other ~= nil then
                other[job.first] = nil
            end
            if
                called
                and type(answer) == "boolean"
                and present[job.first]
                and present[job.second]
            then
                if answer then
                    changing(job.first)
                    changing(job.second)
                end
                record(job, answer)
                local resolved = deps.onResolved
                if resolved ~= nil then
                    guarded(function()
                        resolved(job.first, job.second)
                    end)
                end
            end
        end
        pump()
    end

    pump = function()
        while inFlight < maxInFlight and #queue > 0 do
            local job = table.remove(queue, 1) :: Job
            local own = pending[job.first]
            if own ~= nil and own[job.second] == job then
                inFlight += 1
                deps.spawn(function()
                    run(job)
                end)
            end
        end
    end

    local function enqueue(first: number, second: number): boolean
        if first == second or not present[first] or not present[second] then
            return false
        end
        if answers[first][second] ~= nil or pending[first][second] ~= nil then
            return false
        end
        local job: Job = { first = first, second = second }
        pending[first][second] = job
        pending[second][first] = job
        table.insert(queue, job)
        return true
    end

    local service: FriendBoost = {
        onJoin = function(_self: FriendBoost, userId: number)
            if present[userId] then
                return
            end
            local others = keysOf(present)
            present[userId] = true
            answers[userId] = {}
            pending[userId] = {}
            counts[userId] = 0
            for _, otherId in others do
                enqueue(userId, otherId)
            end
            pump()
        end,
        onLeave = function(_self: FriendBoost, userId: number)
            if not present[userId] then
                return
            end
            present[userId] = nil
            local mine = answers[userId]
            for _, otherId in keysOf(mine) do
                if mine[otherId] then
                    changing(otherId)
                    counts[otherId] -= 1
                end
                answers[otherId][userId] = nil
            end
            for _, otherId in keysOf(pending[userId]) do
                pending[otherId][userId] = nil
            end
            answers[userId] = nil
            pending[userId] = nil
            counts[userId] = nil
        end,
        refreshUnanswered = function(_self: FriendBoost): number
            local ids = keysOf(present)
            local queued = 0
            for index = 1, #ids do
                for next = index + 1, #ids do
                    if enqueue(ids[index], ids[next]) then
                        queued += 1
                    end
                end
            end
            pump()
            return queued
        end,
        boostPct = function(_self: FriendBoost, userId: number): number
            return FriendBoostModule.pctFor(config, counts[userId] or 0)
        end,
    }
    return service
end

return FriendBoostModule
