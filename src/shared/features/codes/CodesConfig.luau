--!strict
--[[
    Typed config of the promo-code system and its validation. Pure: loads under Lune.
    Codes never live in a script: every code, reward, expiry and limit is declared in
    Config.default.codes and `validate` reports each problem.
]]

local RewardConfig = require("../rewards/RewardConfig")

export type CodeEntry = {
    -- Stored as written; matched case-insensitively (see CodesConfig.normalize).
    code: string,
    reward: RewardConfig.Reward,
    -- Unix seconds (UTC) from which the code stops working. nil = never expires.
    expiresAt: number?,
    -- How many times ONE player may redeem it. nil = once.
    maxRedemptions: number?,
}

export type CodesConfig = {
    -- Longest text the server accepts (also the cap of the RedeemCode remote string).
    maxCodeLength: number,
    -- Minimum seconds between two attempts of one player.
    attemptCooldownSeconds: number,
    -- Consecutive failures after which the cooldown doubles.
    failureThreshold: number,
    entries: { CodeEntry },
}

local CodesConfigModule = {}

--- The text a player types, reduced to its comparable form: trimmed and upper-case.
function CodesConfigModule.normalize(text: string): string
    return string.upper((string.gsub(text, "^%s*(.-)%s*$", "%1")))
end

--- One human-readable problem per invalid value (empty when valid).
function CodesConfigModule.validate(config: CodesConfig): { string }
    local problems: { string } = {}
    if not RewardConfig.isPositiveInteger(config.maxCodeLength) then
        table.insert(problems, "codes.maxCodeLength must be a positive integer")
    end
    if
        config.attemptCooldownSeconds ~= config.attemptCooldownSeconds
        or config.attemptCooldownSeconds <= 0
    then
        table.insert(problems, "codes.attemptCooldownSeconds must be positive")
    end
    if not RewardConfig.isPositiveInteger(config.failureThreshold) then
        table.insert(problems, "codes.failureThreshold must be a positive integer")
    end
    local seen: { [string]: boolean } = {}
    for _, entry in config.entries do
        local key = CodesConfigModule.normalize(entry.code)
        if key == "" or string.find(key, "^[%w_%-]+$") == nil then
            table.insert(
                problems,
                `code "{entry.code}" must be non-empty letters, digits, "_" or "-"`
            )
        elseif #key > config.maxCodeLength then
            table.insert(problems, `code "{entry.code}" is longer than maxCodeLength`)
        end
        if seen[key] then
            table.insert(problems, `code "{entry.code}" is declared twice (case-insensitive)`)
        end
        seen[key] = true
        for _, problem in RewardConfig.problems(entry.reward, `code "{entry.code}"`) do
            table.insert(problems, problem)
        end
        local expiresAt = entry.expiresAt
        if expiresAt ~= nil and (not RewardConfig.isFinite(expiresAt) or expiresAt <= 0) then
            table.insert(problems, `code "{entry.code}" has an invalid expiresAt`)
        end
        local maxRedemptions = entry.maxRedemptions
        if maxRedemptions ~= nil and not RewardConfig.isPositiveInteger(maxRedemptions) then
            table.insert(problems, `code "{entry.code}" has an invalid maxRedemptions`)
        end
    end
    return problems
end

return CodesConfigModule
