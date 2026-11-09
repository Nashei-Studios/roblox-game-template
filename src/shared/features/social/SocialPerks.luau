--!strict
--[[
    The social perk multiplier of a player: friend boost, community perk and invite boost,
    multiplied together and clipped to `maxPerkMultiplier` (ADR 0031). A perk multiplier only, never a currency grant.
    Pure: loads under Lune.
]]

local SocialConfig = require("./SocialConfig")

export type SocialPerks = {
    friendBoostPct: number,
    -- What the game's configurable perk (income rate, luck, damage...) is multiplied by.
    perkMultiplier: number,
}

local SocialPerksModule = {}

--- The combined multiplier, never above the configured ceiling.
function SocialPerksModule.multiplier(
    config: SocialConfig.SocialConfig,
    friendPct: number,
    communityPct: number,
    inviteMultiplier: number
): number
    local product = (1 + friendPct / 100) * (1 + communityPct / 100) * inviteMultiplier
    return math.min(product, config.maxPerkMultiplier)
end

--- No social bonus at all.
function SocialPerksModule.none(): SocialPerks
    return { friendBoostPct = 0, perkMultiplier = 1 }
end

return SocialPerksModule
