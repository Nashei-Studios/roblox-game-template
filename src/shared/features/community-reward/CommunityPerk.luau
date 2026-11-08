--!strict
--[[
    Community perk: a lasting percentage perk for members of the game's Roblox community, as
    seen in the referents ("Like and join the group for +1 Digging Luck"). Pure: loads under Lune;
    the membership checker and the clock are injected.

    It is a PERCENTAGE, never a currency and never Robux: the game multiplies it into the stat it
    owns (luck, income...). Feed `pctFor` to `SocialWiring.start({ communityPerkPct = ... })`.

    Rules:
    - Membership is decided on the server only (MembershipChecker port); the client never says
      "I joined".
    - `pctFor` is synchronous and never yields: it reads a cache. Only `refresh` calls the port,
      which may yield, so call it from join handling and from a "check again" request.
    - A cached "member" answer is valid for `membershipTtlSeconds`; after that the perk lapses
      until a refresh confirms membership again, so leaving the community ends the perk.
    - A failed check keeps the previous answer until it expires (the port may be down).
    - Refreshes are rate-limited per player by `recheckCooldownSeconds`; one runs at a time.
]]

local MembershipChecker = require("../../ports/MembershipChecker")
local RewardConfig = require("../rewards/RewardConfig")

export type CommunityPerkConfig = {
    enabled: boolean,
    -- The Roblox community (group) id. nil until the game sets it.
    communityId: number?,
    -- Percentage a member gets (10 means +10 percent).
    perkPct: number,
    -- Hard ceiling of `perkPct` accepted by validation, so a typo cannot become a x100 perk.
    maxPerkPct: number,
    -- How long a "member" answer counts without a new check.
    membershipTtlSeconds: number,
    -- Minimum seconds between two checks for the same player.
    recheckCooldownSeconds: number,
}

export type RefreshOutcome = "member" | "not_member" | "kept"

export type RefreshError = "disabled" | "cooldown" | "busy" | "check_failed"

export type RefreshResult =
    { ok: true, outcome: RefreshOutcome, pct: number }
    | { ok: false, error: RefreshError }

export type CommunityPerk = {
    pctFor: (self: CommunityPerk, userId: number) -> number,
    refresh: (self: CommunityPerk, userId: number) -> RefreshResult,
    forget: (self: CommunityPerk, userId: number) -> (),
}

export type Deps = {
    config: CommunityPerkConfig,
    checker: MembershipChecker.MembershipChecker,
    -- Server clock in seconds (os.clock is enough: only differences are used).
    now: () -> number,
}

type Entry = { member: boolean, checkedAt: number }

local CommunityPerkModule = {}

--- One human-readable problem per invalid value (empty when valid).
function CommunityPerkModule.validate(config: CommunityPerkConfig): { string }
    local problems: { string } = {}
    if
        not RewardConfig.isFinite(config.membershipTtlSeconds)
        or config.membershipTtlSeconds <= 0
    then
        table.insert(problems, "communityPerk.membershipTtlSeconds must be positive")
    end
    if
        not RewardConfig.isFinite(config.recheckCooldownSeconds)
        or config.recheckCooldownSeconds <= 0
    then
        table.insert(problems, "communityPerk.recheckCooldownSeconds must be positive")
    end
    if not config.enabled then
        return problems
    end
    local communityId = config.communityId
    if communityId == nil then
        table.insert(problems, "communityPerk is enabled but has no communityId")
    elseif not RewardConfig.isPositiveInteger(communityId) then
        table.insert(problems, "communityPerk.communityId must be a positive integer")
    end
    if not RewardConfig.isFinite(config.maxPerkPct) or config.maxPerkPct <= 0 then
        table.insert(problems, "communityPerk.maxPerkPct must be positive")
    elseif not RewardConfig.isFinite(config.perkPct) or config.perkPct <= 0 then
        table.insert(problems, "communityPerk.perkPct must be positive")
    elseif config.perkPct > config.maxPerkPct then
        table.insert(problems, "communityPerk.perkPct is above maxPerkPct")
    end
    return problems
end

function CommunityPerkModule.new(deps: Deps): CommunityPerk
    local entries: { [number]: Entry } = {}
    local lastCheck: { [number]: number } = {}
    local running: { [number]: boolean } = {}

    local function pctNow(userId: number): number
        local entry = entries[userId]
        if entry == nil or not entry.member or not deps.config.enabled then
            return 0
        end
        if deps.now() - entry.checkedAt > deps.config.membershipTtlSeconds then
            return 0
        end
        return deps.config.perkPct
    end

    local service: CommunityPerk = {
        pctFor = function(_self: CommunityPerk, userId: number): number
            return pctNow(userId)
        end,
        refresh = function(_self: CommunityPerk, userId: number): RefreshResult
            local communityId = deps.config.communityId
            if not deps.config.enabled or communityId == nil then
                return { ok = false, error = "disabled" }
            end
            if running[userId] then
                return { ok = false, error = "busy" }
            end
            local now = deps.now()
            local previous = lastCheck[userId]
            if previous ~= nil and now - previous < deps.config.recheckCooldownSeconds then
                return { ok = false, error = "cooldown" }
            end
            lastCheck[userId] = now
            running[userId] = true
            local membership = deps.checker:isMember(userId, communityId)
            running[userId] = nil
            if not membership.ok then
                return { ok = false, error = "check_failed" }
            end
            local checkedAt = deps.now()
            if membership.value then
                entries[userId] = { member = true, checkedAt = checkedAt }
                return { ok = true, outcome = "member", pct = deps.config.perkPct }
            end
            -- A `false` can be stale (IsInGroupAsync caches per peer): a member we already know
            -- keeps the perk until the TTL runs out instead of losing it on one `false`.
            local known = entries[userId]
            if known ~= nil and known.member then
                return { ok = true, outcome = "kept", pct = pctNow(userId) }
            end
            entries[userId] = { member = false, checkedAt = checkedAt }
            return { ok = true, outcome = "not_member", pct = 0 }
        end,
        forget = function(_self: CommunityPerk, userId: number)
            entries[userId] = nil
            lastCheck[userId] = nil
            running[userId] = nil
        end,
    }
    return service
end

return CommunityPerkModule
