--!strict
--[[
    Adapter: MembershipChecker over Player:IsInGroupAsync. The engine call is injected (ADR 0009)
    so this file loads under Lune and is tested with fakes. The call yields and can fail, so it
    runs under pcall and a failure comes back as a typed error with its message; it is never
    swallowed. IsInGroupAsync caches per peer: a `false` may be stale, so callers treat it as
    "not yet" (features/community-reward/CommunityReward grants only on `true`).
]]

-- Structurally identical to ports/MembershipChecker.luau (kept local so this file loads under Lune).
type CheckError = { kind: "check_failed", message: string }
type CheckResult = { ok: true, value: boolean } | { ok: false, error: CheckError }
type MembershipChecker = {
    isMember: (self: MembershipChecker, userId: number, communityId: number) -> CheckResult,
}

export type PlayersLike<P> = {
    GetPlayerByUserId: (self: unknown, userId: number) -> P?,
}

export type Deps<P> = {
    players: PlayersLike<P>,
    -- Player:IsInGroupAsync(communityId); may yield or throw.
    isInGroup: (player: P, communityId: number) -> boolean,
}

local RobloxGroupMembership = {}

function RobloxGroupMembership.new<P>(deps: Deps<P>): MembershipChecker
    local checker: MembershipChecker = {
        isMember = function(
            _self: MembershipChecker,
            userId: number,
            communityId: number
        ): CheckResult
            local player = deps.players:GetPlayerByUserId(userId)
            if player == nil then
                return { ok = false, error = { kind = "check_failed", message = "player_gone" } }
            end
            local called, answer = pcall(deps.isInGroup, player, communityId)
            if not called then
                return {
                    ok = false,
                    error = { kind = "check_failed", message = tostring(answer) },
                }
            end
            return { ok = true, value = answer == true }
        end,
    }
    return checker
end

return RobloxGroupMembership
