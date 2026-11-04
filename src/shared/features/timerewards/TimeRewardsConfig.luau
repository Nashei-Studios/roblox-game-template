--!strict
--[[
    Typed config of the time rewards (daily streak and session gifts) and its validation.
    Pure: loads under Lune. The whole schedule lives in Config.default.timeRewards.
]]

local RewardConfig = require("../rewards/RewardConfig")

export type DailyEntry = {
    -- 1-based position in the streak cycle; the days must be 1..N with no gap.
    day: number,
    reward: RewardConfig.Reward,
}

export type SessionGift = {
    -- Stable id the client sends as intent (never an index).
    id: string,
    -- Minutes of the current session after which the gift can be claimed.
    afterMinutes: number,
    reward: RewardConfig.Reward,
}

export type TimeRewardsConfig = {
    -- Extra hours after the end of the day that follows a claim in which the streak still lives.
    graceHours: number,
    daily: { DailyEntry },
    sessionGifts: { SessionGift },
}

local TimeRewardsConfigModule = {}

--- One human-readable problem per invalid value (empty when valid).
function TimeRewardsConfigModule.validate(config: TimeRewardsConfig): { string }
    local problems: { string } = {}
    if not RewardConfig.isFinite(config.graceHours) or config.graceHours < 0 then
        table.insert(problems, "timeRewards.graceHours must be zero or positive")
    end
    if #config.daily == 0 then
        table.insert(problems, "timeRewards.daily must declare at least one day")
    end
    for index, entry in config.daily do
        if entry.day ~= index then
            table.insert(
                problems,
                `timeRewards.daily entry {index} has day {entry.day} (days must be 1..N in order)`
            )
        end
        for _, problem in RewardConfig.problems(entry.reward, `daily day {entry.day}`) do
            table.insert(problems, problem)
        end
    end
    local seen: { [string]: boolean } = {}
    for _, gift in config.sessionGifts do
        if gift.id == "" or #gift.id > 24 then
            table.insert(problems, "a session gift id must be 1 to 24 characters")
        end
        if seen[gift.id] then
            table.insert(problems, `session gift "{gift.id}" is declared twice`)
        end
        seen[gift.id] = true
        if not RewardConfig.isFinite(gift.afterMinutes) or gift.afterMinutes <= 0 then
            table.insert(problems, `session gift "{gift.id}" needs a positive afterMinutes`)
        end
        for _, problem in RewardConfig.problems(gift.reward, `session gift "{gift.id}"`) do
            table.insert(problems, problem)
        end
    end
    return problems
end

return TimeRewardsConfigModule
