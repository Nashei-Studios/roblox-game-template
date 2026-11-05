--!strict
--[[
    Chains two MembershipChecker adapters. IsInGroupAsync can answer a stale `false` for a player
    who joined after the server first asked; the optional second checker (Open Cloud membership
    lookup) is consulted whenever the first one says "no" or fails. A stale answer therefore only
    delays the grant: this module can turn a `false` into `true` only when the second source says
    so, and never grants anything by itself. Pure: loads under Lune.
]]

local MembershipChecker = require("../../ports/MembershipChecker")

local FallbackMembership = {}

--- `secondary` may be nil (then `primary` is returned unchanged).
function FallbackMembership.new(
    primary: MembershipChecker.MembershipChecker,
    secondary: MembershipChecker.MembershipChecker?
): MembershipChecker.MembershipChecker
    if secondary == nil then
        return primary
    end
    local chained: MembershipChecker.MembershipChecker = {
        isMember = function(
            _self: MembershipChecker.MembershipChecker,
            userId: number,
            communityId: number
        ): MembershipChecker.CheckResult
            local first = primary:isMember(userId, communityId)
            if first.ok and first.value then
                return first
            end
            local second = secondary:isMember(userId, communityId)
            if second.ok then
                return second
            end
            -- The second source failed too: keep the first answer (a plain "no" or its error).
            return first
        end,
    }
    return chained
end

return FallbackMembership
