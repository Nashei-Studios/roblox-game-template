--!strict
--[[
    The social layer without the engine (ADR 0030, 0031): friend boost, invite reward, the
    combined multiplier and the retry loop, with every effect injected. Pure: loads under Lune.
    server/adapters/SocialWiring only adapts Players, HttpService, MemoryStore and task.

    - `perksFor` runs on every hot-path call (a swing, a tick): it reads three small numbers and returns the SAME table
      until one of them changes, so it allocates nothing in the steady state.
    - The invite boost is session memory; the once-per-pair-per-day ledger is shared across
      servers (a Ledger port, MemoryStore in the wiring).
    - Nothing here may throw into the join path: every outward call is guarded.
]]

local FriendBoost = require("./FriendBoost")
local InviteBoost = require("./InviteBoost")
local InviteReward = require("./InviteReward")
local SocialConfig = require("./SocialConfig")
local SocialPerks = require("./SocialPerks")

export type Deps = {
    config: SocialConfig.SocialConfig?,
    -- Live-ops flag `inviteReward`.
    inviteRewardEnabled: () -> boolean,
    -- Unix seconds.
    now: () -> number,
    isFriendsWith: (userId: number, otherUserId: number) -> boolean,
    isPresent: (userId: number) -> boolean,
    ledger: InviteReward.Ledger,
    decode: (text: string) -> unknown,
    spawn: (run: () -> ()) -> (),
    -- Runs `run` once after `seconds`.
    delay: (seconds: number, run: () -> ()) -> (),
    -- Called for a player right BEFORE their social multiplier changes (settle anything paid at the old rate).
    beforeChange: (userId: number) -> (),
    -- Called after it changed (re-read the rate, push the snapshot).
    onChanged: (userId: number) -> (),
    -- Whole percent of the community perk; 0 while it is off or the player is not a member.
    communityPerkPct: (userId: number) -> number,
    warn: (message: string) -> (),
}

export type SocialRuntime = {
    perksFor: (self: SocialRuntime, userId: number) -> SocialPerks.SocialPerks,
    -- Yields nothing: the friend questions run in their own threads.
    onJoin: (self: SocialRuntime, userId: number, joinData: unknown) -> (),
    onLeave: (self: SocialRuntime, userId: number) -> (),
    -- Starts the retry loop for pairs whose friendship could not be read.
    start: (self: SocialRuntime) -> (),
}

type Cached = {
    friendPct: number,
    communityPct: number,
    invite: number,
    perks: SocialPerks.SocialPerks,
}

local SocialRuntimeModule = {}

function SocialRuntimeModule.new(deps: Deps): SocialRuntime
    local config = deps.config or SocialConfig.default
    local invites = InviteBoost.new(config)
    -- Players whose last published Friend Boost is known, to tell who actually changed.
    local lastPct: { [number]: number } = {}
    local cache: { [number]: Cached } = {}
    local present: { [number]: boolean } = {}

    local function guarded(label: string, run: () -> ())
        local ok = xpcall(run, function(failure: unknown): ()
            deps.warn(`Social {label} failed: {tostring(failure)}`)
        end)
        return ok
    end

    local friends: FriendBoost.FriendBoost

    -- A copy: publishing calls out, and a callout may let another player join or leave.
    local function presentIds(): { number }
        local ids: { number } = {}
        for userId in present do
            table.insert(ids, userId)
        end
        return ids
    end

    local function publish(userId: number)
        if not present[userId] then
            return
        end
        local pct = friends:boostPct(userId)
        if lastPct[userId] ~= pct then
            lastPct[userId] = pct
            deps.onChanged(userId)
        end
    end

    friends = FriendBoost.new({
        config = config,
        isFriendsWith = deps.isFriendsWith,
        spawn = deps.spawn,
        beforeChange = deps.beforeChange,
        onResolved = function(first: number, second: number)
            guarded("publish", function()
                publish(first)
                publish(second)
            end)
        end,
    })

    local reward = InviteReward.new({
        enabled = deps.inviteRewardEnabled,
        now = deps.now,
        isPresent = deps.isPresent,
        ledger = deps.ledger,
        decode = deps.decode,
        grant = function(userId: number)
            guarded("invite grant", function()
                deps.beforeChange(userId)
                invites:grant(userId, deps.now())
                deps.onChanged(userId)
                -- The boost ends by the clock; tell the caller so the rate is re-read then.
                deps.delay(config.invite.rewardSeconds + 1, function()
                    guarded("invite expiry", function()
                        if present[userId] then
                            deps.beforeChange(userId)
                            deps.onChanged(userId)
                        end
                    end)
                end)
            end)
        end,
    })

    local service: SocialRuntime = {
        perksFor = function(_self: SocialRuntime, userId: number): SocialPerks.SocialPerks
            local friendPct = friends:boostPct(userId)
            local communityPct = deps.communityPerkPct(userId)
            local invite = invites:multiplier(userId, deps.now())
            local hit = cache[userId]
            if
                hit ~= nil
                and hit.friendPct == friendPct
                and hit.communityPct == communityPct
                and hit.invite == invite
            then
                return hit.perks
            end
            local perks: SocialPerks.SocialPerks = {
                friendBoostPct = friendPct,
                perkMultiplier = SocialPerks.multiplier(config, friendPct, communityPct, invite),
            }
            cache[userId] = {
                friendPct = friendPct,
                communityPct = communityPct,
                invite = invite,
                perks = perks,
            }
            return perks
        end,
        onJoin = function(_self: SocialRuntime, userId: number, joinData: unknown)
            present[userId] = true
            lastPct[userId] = 0
            guarded("friend check", function()
                friends:onJoin(userId)
            end)
            guarded("invite reward", function()
                reward:onJoin(userId, joinData)
            end)
        end,
        onLeave = function(_self: SocialRuntime, userId: number)
            guarded("leave", function()
                friends:onLeave(userId)
            end)
            present[userId] = nil
            lastPct[userId] = nil
            cache[userId] = nil
            invites:forget(userId)
            -- Friends of the one who left lost a percentage; tell them.
            for _, otherId in presentIds() do
                publish(otherId)
            end
        end,
        start = function(_self: SocialRuntime)
            local wait = config.friendBoost.retrySeconds
            local function tick()
                guarded("retry", function()
                    local queued = friends:refreshUnanswered()
                    -- Keep waiting longer while the pairs keep failing; start over when idle.
                    wait = if queued > 0
                        then math.min(wait * 2, config.friendBoost.retryMaxSeconds)
                        else config.friendBoost.retrySeconds
                    for _, otherId in presentIds() do
                        publish(otherId)
                    end
                end)
                deps.delay(wait, tick)
            end
            deps.delay(wait, tick)
        end,
    }
    return service
end

return SocialRuntimeModule
