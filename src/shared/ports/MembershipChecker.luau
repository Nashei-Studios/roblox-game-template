--!strict
--[[
    Port: is this user a member of this Roblox community? Server side only; the client never
    says "I joined" (issue #36). The shipped adapter wraps Player:IsInGroupAsync; a second adapter
    (Open Cloud ListGroupMemberships) can plug in behind the same port and be chained after it with
    features/community-reward/FallbackMembership, without changing any caller (ADR 0022).
]]

export type CheckError = { kind: "check_failed", message: string }

export type CheckResult = { ok: true, value: boolean } | { ok: false, error: CheckError }

export type MembershipChecker = {
    -- A `false` can be stale (IsInGroupAsync caches per peer): treat it as "not yet", never as proof.
    isMember: (self: MembershipChecker, userId: number, communityId: number) -> CheckResult,
}

return {}
