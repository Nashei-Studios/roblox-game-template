--!strict
--[[
    Pure session-gift rules (issue #27): a gift is ready once `afterMinutes` of the current
    session have passed on the server clock, and can be claimed once per session. A clock that
    went backwards (now before the join time) makes nothing ready.
]]

local TimeRewardsConfig = require("./TimeRewardsConfig")

export type Check =
    { ok: true, gift: TimeRewardsConfig.SessionGift }
    | { ok: false, reason: "unknown_gift" | "not_ready" | "already_claimed" }

local SessionGifts = {}

function SessionGifts.check(
    gifts: { TimeRewardsConfig.SessionGift },
    giftId: string,
    joinedAt: number,
    now: number,
    claimed: { [string]: boolean }
): Check
    for _, gift in gifts do
        if gift.id == giftId then
            if claimed[giftId] then
                return { ok = false, reason = "already_claimed" }
            end
            if now - joinedAt < gift.afterMinutes * 60 then
                return { ok = false, reason = "not_ready" }
            end
            return { ok = true, gift = gift }
        end
    end
    return { ok = false, reason = "unknown_gift" }
end

return SessionGifts
