--!strict
--[[
    The "Friend +N %" HUD segment (ADR 0030/0031), pure so it is testable without a screen.
    `nil` means "nothing to show": the HUD omits the segment when the server reports no boost.
]]

local SocialConfig = require("./SocialConfig")

local FriendBoostLabel = {}

-- `pct` is `friendBoostPct` of the last state snapshot the server sent.
function FriendBoostLabel.text(pct: number): string?
    local rounded = math.floor(pct + 0.5)
    if rounded <= 0 then
        return nil
    end
    return `Friend +{rounded}%`
end

--- The reason to bring friends, shown while no friend boost is active (ADR 0052). Display
--- only: the boost itself is granted by the server, never by this text. The numbers come from
--- the social config, so the hint cannot drift from the rule.
function FriendBoostLabel.hint(pct: number, perFriendPct: number, capPct: number): string?
    if math.floor(pct + 0.5) > 0 or perFriendPct <= 0 then
        return nil
    end
    return `Friends +{math.floor(perFriendPct)}% each (max {math.floor(capPct)}%)`
end

--- "3 players" for the tag of a shared objective: its target grows with the players present.
--- `noun` is the plural the game uses ("players" by default).
function FriendBoostLabel.roster(playersPresent: number, noun: string?): string?
    if playersPresent < 2 then
        return nil
    end
    return `{math.floor(playersPresent)} {noun or "players"}`
end

--- What the HUD pill shows: the active boost, else the hint once the tutorial is over, else
--- nothing. A lone player in the tutorial sees no social nudge.
function FriendBoostLabel.pill(
    pct: number,
    config: SocialConfig.SocialConfig,
    tutorialDone: boolean
): string?
    local active = FriendBoostLabel.text(pct)
    if active ~= nil then
        return active
    end
    if not tutorialDone then
        return nil
    end
    return FriendBoostLabel.hint(pct, config.friendBoost.perFriendPct, config.friendBoost.capPct)
end

return FriendBoostLabel
