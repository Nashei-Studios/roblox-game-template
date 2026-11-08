--!strict
--[[
    Numbers of the social layer (ADR 0030). Pure: loads under Lune. Kept out of Config so the
    module stays testable alone; `SocialConfig.problems` is checked by the social tests.
]]

export type SocialConfig = {
    friendBoost: {
        -- Percent of the game perk per friend in the same server.
        perFriendPct: number,
        -- The most the boost can reach, in percent.
        capPct: number,
        -- IsFriendsWith calls in flight at once.
        maxConcurrentChecks: number,
        -- Seconds between two retries of the pairs that got no answer; doubles while they keep
        -- failing, up to retryMaxSeconds.
        retrySeconds: number,
        retryMaxSeconds: number,
    },
    invite: {
        -- Seconds of the invite boost both players get.
        rewardSeconds: number,
        -- Perk multiplier while the invite boost lasts.
        multiplier: number,
        -- Paid invites per inviter per UTC day.
        dailyPaidPerInviter: number,
    },
    -- Ceiling of friend x community x invite, so the sum of rewards never outruns the gates.
    maxPerkMultiplier: number,
}

local SocialConfigModule = {}

SocialConfigModule.default = {
    friendBoost = {
        perFriendPct = 10,
        capPct = 50,
        maxConcurrentChecks = 4,
        retrySeconds = 60,
        retryMaxSeconds = 600,
    },
    invite = { rewardSeconds = 15 * 60, multiplier = 3, dailyPaidPerInviter = 5 },
    maxPerkMultiplier = 3,
} :: SocialConfig

--- One human-readable problem per invalid value (empty when valid).
function SocialConfigModule.problems(config: SocialConfig): { string }
    local problems: { string } = {}
    local friend = config.friendBoost
    if not (friend.perFriendPct >= 0 and friend.perFriendPct < math.huge) then
        table.insert(problems, "social.friendBoost.perFriendPct must be finite and not negative")
    end
    if not (friend.capPct >= 0 and friend.capPct <= 255) then
        table.insert(problems, "social.friendBoost.capPct must be between 0 and 255")
    end
    local invite = config.invite
    if not (invite.rewardSeconds > 0 and invite.rewardSeconds < math.huge) then
        table.insert(problems, "social.invite.rewardSeconds must be positive")
    end
    if not (invite.multiplier >= 1 and invite.multiplier < math.huge) then
        table.insert(problems, "social.invite.multiplier must be at least 1")
    end
    if friend.maxConcurrentChecks < 1 or friend.maxConcurrentChecks % 1 ~= 0 then
        table.insert(problems, "social.friendBoost.maxConcurrentChecks must be a positive integer")
    end
    if not (friend.retrySeconds > 0 and friend.retryMaxSeconds >= friend.retrySeconds) then
        table.insert(problems, "social.friendBoost retry seconds must be positive and ordered")
    end
    if invite.dailyPaidPerInviter < 1 or invite.dailyPaidPerInviter % 1 ~= 0 then
        table.insert(problems, "social.invite.dailyPaidPerInviter must be a positive integer")
    end
    if not (config.maxPerkMultiplier >= 1 and config.maxPerkMultiplier < math.huge) then
        table.insert(problems, "social.maxPerkMultiplier must be at least 1")
    end
    return problems
end

return SocialConfigModule
