--!strict
--[[
    The timed invite boost (x`multiplier` on the perk for `rewardSeconds`). Session memory only: it is
    not saved, so no schema change. Granting again refreshes to one full window, never beyond it.
    Pure: loads under Lune.
]]

local SocialConfig = require("./SocialConfig")

export type InviteBoost = {
    -- Starts (or refreshes to a full window) the boost.
    grant: (self: InviteBoost, userId: number, now: number) -> (),
    multiplier: (self: InviteBoost, userId: number, now: number) -> number,
    remainingSeconds: (self: InviteBoost, userId: number, now: number) -> number,
    forget: (self: InviteBoost, userId: number) -> (),
}

local InviteBoostModule = {}

function InviteBoostModule.new(config: SocialConfig.SocialConfig?): InviteBoost
    local rules = (config or SocialConfig.default).invite
    local untilTime: { [number]: number } = {}
    local service: InviteBoost
    service = {
        grant = function(_self: InviteBoost, userId: number, now: number)
            untilTime[userId] = math.max(untilTime[userId] or 0, now + rules.rewardSeconds)
        end,
        multiplier = function(self: InviteBoost, userId: number, now: number): number
            return if self:remainingSeconds(userId, now) > 0 then rules.multiplier else 1
        end,
        remainingSeconds = function(_self: InviteBoost, userId: number, now: number): number
            return math.max(0, (untilTime[userId] or 0) - now)
        end,
        forget = function(_self: InviteBoost, userId: number)
            untilTime[userId] = nil
        end,
    }
    return service
end

return InviteBoostModule
