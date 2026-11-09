--!strict
local CommunityPerk = require("../../../src/shared/features/community-reward/CommunityPerk")
local MembershipChecker = require("../../../src/shared/ports/MembershipChecker")
local harness = require("../../harness")

type Rig = {
    perk: CommunityPerk.CommunityPerk,
    clock: { now: number },
    answer: { value: MembershipChecker.CheckResult },
    calls: { number },
}

local function config(): CommunityPerk.CommunityPerkConfig
    return {
        enabled = true,
        communityId = 77,
        perkPct = 10,
        maxPerkPct = 50,
        membershipTtlSeconds = 600,
        recheckCooldownSeconds = 30,
    }
end

local function rig(cfg: CommunityPerk.CommunityPerkConfig?): Rig
    local clock = { now = 100 }
    local answer = { value = { ok = true, value = true } :: MembershipChecker.CheckResult }
    local calls: { number } = {}
    local checker: MembershipChecker.MembershipChecker = {
        isMember = function(
            _self: MembershipChecker.MembershipChecker,
            userId: number,
            _communityId: number
        ): MembershipChecker.CheckResult
            table.insert(calls, userId)
            return answer.value
        end,
    }
    local perk = CommunityPerk.new({
        config = cfg or config(),
        checker = checker,
        now = function()
            return clock.now
        end,
    })
    return { perk = perk, clock = clock, answer = answer, calls = calls }
end

local function outcomeOf(result: CommunityPerk.RefreshResult): string
    if result.ok then
        return result.outcome
    end
    return result.error
end

return function(suite: harness.Harness)
    suite:test("validate accepts a sane config and flags a perk above the ceiling", function()
        harness.equal(#CommunityPerk.validate(config()), 0)
        local bad = config()
        bad.perkPct = 500
        harness.equal(#CommunityPerk.validate(bad), 1)
        bad.communityId = nil
        harness.equal(#CommunityPerk.validate(bad), 2)
    end)

    suite:test("a disabled config validates without a community and gives no perk", function()
        local off = config()
        off.enabled = false
        off.communityId = nil
        harness.equal(#CommunityPerk.validate(off), 0)
        local r = rig(off)
        harness.equal(outcomeOf(r.perk:refresh(1)), "disabled")
        harness.equal(r.perk:pctFor(1), 0)
    end)

    suite:test("nobody has a perk before a check", function()
        harness.equal(rig().perk:pctFor(1), 0)
    end)

    suite:test("a confirmed member gets the perk until the TTL runs out", function()
        local r = rig()
        harness.equal(outcomeOf(r.perk:refresh(1)), "member")
        harness.equal(r.perk:pctFor(1), 10)
        r.clock.now = 100 + 600
        harness.equal(r.perk:pctFor(1), 10)
        r.clock.now = 100 + 601
        harness.equal(r.perk:pctFor(1), 0)
    end)

    suite:test("a non member gets nothing", function()
        local r = rig()
        r.answer.value = { ok = true, value = false }
        harness.equal(outcomeOf(r.perk:refresh(1)), "not_member")
        harness.equal(r.perk:pctFor(1), 0)
    end)

    suite:test("a single false does not take the perk from a known member", function()
        local r = rig()
        r.perk:refresh(1)
        r.clock.now = 200
        r.answer.value = { ok = true, value = false }
        harness.equal(outcomeOf(r.perk:refresh(1)), "kept")
        harness.equal(r.perk:pctFor(1), 10)
    end)

    suite:test("a failed check reports the error and keeps the previous answer", function()
        local r = rig()
        r.perk:refresh(1)
        r.clock.now = 200
        r.answer.value = { ok = false, error = { kind = "check_failed", message = "down" } }
        harness.equal(outcomeOf(r.perk:refresh(1)), "check_failed")
        harness.equal(r.perk:pctFor(1), 10)
    end)

    suite:test("refreshes are rate limited per player and reach the port once", function()
        local r = rig()
        r.perk:refresh(1)
        harness.equal(outcomeOf(r.perk:refresh(1)), "cooldown")
        harness.equal(#r.calls, 1)
        harness.equal(outcomeOf(r.perk:refresh(2)), "member")
        r.clock.now = 131
        harness.equal(outcomeOf(r.perk:refresh(1)), "member")
        harness.equal(#r.calls, 3)
    end)

    suite:test("forget drops the cache so the perk is gone and a check is allowed again", function()
        local r = rig()
        r.perk:refresh(1)
        r.perk:forget(1)
        harness.equal(r.perk:pctFor(1), 0)
        harness.equal(outcomeOf(r.perk:refresh(1)), "member")
    end)
end
