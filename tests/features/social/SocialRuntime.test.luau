--!strict
local InviteReward = require("../../../src/shared/features/social/InviteReward")
local SocialRuntime = require("../../../src/shared/features/social/SocialRuntime")
local harness = require("../../harness")

type Scheduled = { at: number, run: () -> () }

type Harnessed = {
    runtime: SocialRuntime.SocialRuntime,
    clock: { now: number },
    flag: { on: boolean },
    friends: { [string]: boolean },
    failing: { value: boolean },
    community: { pct: number },
    changed: { number },
    before: { number },
    warnings: { string },
    scheduled: { Scheduled },
    present: { [number]: boolean },
    advance: (seconds: number) -> (),
    ledger: InviteReward.Ledger,
}

local function key(a: number, b: number): string
    return if a < b then `{a}:{b}` else `{b}:{a}`
end

local function build(ledger: InviteReward.Ledger?): Harnessed
    local clock = { now = 10 * 86400 }
    local flag = { on = true }
    local friends: { [string]: boolean } = {}
    local failing = { value = false }
    local community = { pct = 0 }
    local changed: { number } = {}
    local before: { number } = {}
    local warnings: { string } = {}
    local scheduled: { Scheduled } = {}
    local present: { [number]: boolean } = {}
    local usedLedger = ledger or InviteReward.memoryLedger(5)
    local runtime = SocialRuntime.new({
        inviteRewardEnabled = function(): boolean
            return flag.on
        end,
        now = function(): number
            return clock.now
        end,
        isFriendsWith = function(a: number, b: number): boolean
            if failing.value then
                error("IsFriendsWith failed")
            end
            return friends[key(a, b)] == true
        end,
        isPresent = function(userId: number): boolean
            return present[userId] == true
        end,
        ledger = usedLedger,
        decode = function(_text: string): unknown
            return {}
        end,
        spawn = function(run: () -> ())
            coroutine.wrap(run)()
        end,
        delay = function(seconds: number, run: () -> ())
            table.insert(scheduled, { at = clock.now + seconds, run = run })
        end,
        beforeChange = function(userId: number)
            table.insert(before, userId)
        end,
        onChanged = function(userId: number)
            table.insert(changed, userId)
        end,
        communityPerkPct = function(_userId: number): number
            return community.pct
        end,
        warn = function(message: string)
            table.insert(warnings, message)
        end,
    })
    local harnessed: Harnessed
    harnessed = {
        runtime = runtime,
        clock = clock,
        flag = flag,
        friends = friends,
        failing = failing,
        community = community,
        changed = changed,
        before = before,
        warnings = warnings,
        scheduled = scheduled,
        present = present,
        ledger = usedLedger,
        advance = function(seconds: number)
            clock.now += seconds
            local index = 1
            while index <= #scheduled do
                local item = scheduled[index]
                if item.at <= clock.now then
                    table.remove(scheduled, index)
                    item.run()
                else
                    index += 1
                end
            end
        end,
    }
    return harnessed
end

local function join(h: Harnessed, userId: number, inviter: number?)
    h.present[userId] = true
    h.runtime:onJoin(userId, { ReferredByPlayerId = inviter })
end

return function(suite: harness.Harness)
    suite:test(
        "runtime: a friend in the server publishes the percentage and the same perks object",
        function()
            local h = build()
            h.friends[key(1, 2)] = true
            join(h, 1, nil)
            join(h, 2, nil)
            local perks = h.runtime:perksFor(1)
            harness.equal(perks.friendBoostPct, 10, "pct")
            harness.isTrue(math.abs(perks.perkMultiplier - 1.1) < 1e-9, "multiplier")
            harness.isTrue(h.runtime:perksFor(1) == perks, "same object while nothing changes")
            harness.isTrue(
                table.find(h.changed, 1) ~= nil and table.find(h.changed, 2) ~= nil,
                "both told"
            )
            harness.isTrue(table.find(h.before, 1) ~= nil, "settled before the change")
            h.community.pct = 10
            local withCommunity = h.runtime:perksFor(1)
            harness.isTrue(withCommunity ~= perks, "a new object when an input changes")
            harness.isTrue(
                math.abs(withCommunity.perkMultiplier - 1.21) < 1e-9,
                "friend x community"
            )
            h.present[2] = nil
            h.runtime:onLeave(2)
            harness.equal(h.runtime:perksFor(1).friendBoostPct, 0, "friend left")
            harness.isTrue(h.changed[#h.changed] == 1, "the one left behind is told")
        end
    )

    suite:test("runtime: invite reward grants x3 to both, caps the product and expires", function()
        local h = build()
        join(h, 10, nil)
        join(h, 20, 10)
        harness.equal(h.runtime:perksFor(10).perkMultiplier, 3, "inviter x3")
        harness.equal(h.runtime:perksFor(20).perkMultiplier, 3, "invitee x3")
        h.community.pct = 10
        harness.equal(h.runtime:perksFor(20).perkMultiplier, 3, "still clipped at 3.0")
        h.community.pct = 0
        local told = #h.changed
        h.advance(901)
        harness.equal(h.runtime:perksFor(10).perkMultiplier, 1, "expired")
        harness.isTrue(#h.changed > told, "expiry is announced")
    end)

    suite:test("runtime: flag off grants nothing and a repeated join pays once", function()
        local h = build()
        h.flag.on = false
        join(h, 10, nil)
        join(h, 20, 10)
        harness.equal(h.runtime:perksFor(20).perkMultiplier, 1, "flag off")
        h.flag.on = true
        join(h, 30, 10)
        harness.equal(h.runtime:perksFor(30).perkMultiplier, 3, "flag on")
        h.runtime:onLeave(30)
        h.present[30] = nil
        join(h, 30, 10)
        harness.equal(h.runtime:perksFor(30).perkMultiplier, 1, "the same pair is not paid twice")
    end)

    suite:test("runtime: a ledger that throws is warned about and never breaks the join", function()
        local broken: InviteReward.Ledger = {
            claimPair = function(_self: InviteReward.Ledger, _pair): boolean
                error("ledger down")
            end,
            takeInviterSlot = function(
                _self: InviteReward.Ledger,
                _id: number,
                _day: number
            ): boolean
                return true
            end,
        }
        local h = build(broken)
        join(h, 10, nil)
        join(h, 20, 10)
        harness.equal(h.runtime:perksFor(20).perkMultiplier, 1, "no reward")
        harness.isTrue(#h.warnings >= 1, "the failure is reported")
    end)

    suite:test("runtime: failed friendship reads are retried with backoff", function()
        local h = build()
        h.friends[key(1, 2)] = true
        h.failing.value = true
        h.runtime:start()
        join(h, 1, nil)
        join(h, 2, nil)
        harness.equal(h.runtime:perksFor(1).friendBoostPct, 0, "failed is 0 %")
        h.advance(60)
        harness.equal(h.runtime:perksFor(1).friendBoostPct, 0, "still failing, backs off")
        h.failing.value = false
        h.advance(60)
        harness.equal(h.runtime:perksFor(1).friendBoostPct, 0, "next retry is 120 s away")
        h.advance(60)
        harness.equal(h.runtime:perksFor(1).friendBoostPct, 10, "recovered by the retry loop")
        harness.isTrue(h.changed[#h.changed] ~= nil, "published")
    end)
end
