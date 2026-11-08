--!strict
local FriendBoost = require("../../../src/shared/features/social/FriendBoost")
local SocialConfig = require("../../../src/shared/features/social/SocialConfig")
local harness = require("../../harness")

type Fake = {
    friends: { [string]: boolean },
    calls: number,
    failing: boolean,
    junk: boolean,
    -- When true, every question parks its thread until `release` resumes it.
    parking: boolean,
    parked: { thread },
    inFlight: number,
    peak: number,
}

local function key(a: number, b: number): string
    return if a < b then `{a}:{b}` else `{b}:{a}`
end

local function newFake(): Fake
    return {
        friends = {},
        calls = 0,
        failing = false,
        junk = false,
        parking = false,
        parked = {},
        inFlight = 0,
        peak = 0,
    }
end

local function spawnNow(run: () -> ())
    coroutine.wrap(run)()
end

local function release(fake: Fake)
    local waiting = fake.parked
    fake.parked = {}
    for _, thread in waiting do
        coroutine.resume(thread)
    end
end

local function newBoost(
    fake: Fake,
    hooks: {
        beforeChange: ((userId: number) -> ())?,
        onResolved: ((a: number, b: number) -> ())?,
    }?
): FriendBoost.FriendBoost
    return FriendBoost.new({
        spawn = spawnNow,
        beforeChange = if hooks ~= nil then hooks.beforeChange else nil,
        onResolved = if hooks ~= nil then hooks.onResolved else nil,
        isFriendsWith = function(a: number, b: number): boolean
            fake.calls += 1
            fake.inFlight += 1
            fake.peak = math.max(fake.peak, fake.inFlight)
            if fake.parking then
                table.insert(fake.parked, coroutine.running())
                coroutine.yield()
            end
            fake.inFlight -= 1
            if fake.failing then
                error("IsFriendsWith failed")
            end
            if fake.junk then
                local answer: unknown = "yes"
                return answer :: boolean
            end
            return fake.friends[key(a, b)] == true
        end,
    })
end

return function(suite: harness.Harness)
    suite:test("friend boost: 0, 1, 5 and 7 friends give 0, 10, 50 and the 50 cap", function()
        local cases: { { number } } = { { 0, 0 }, { 1, 10 }, { 5, 50 }, { 7, 50 } }
        for _, case in cases do
            local fake = newFake()
            local boost = newBoost(fake)
            for other = 2, 1 + case[1] do
                fake.friends[key(1, other)] = true
            end
            for other = 2, 8 do
                boost:onJoin(other)
            end
            boost:onJoin(1)
            harness.equal(boost:boostPct(1), case[2], `pct for {case[1]} friends`)
        end
    end)

    suite:test("friend boost: the same pair reversed is one pair", function()
        local fake = newFake()
        fake.friends[key(1, 2)] = true
        local boost = newBoost(fake)
        boost:onJoin(2)
        boost:onJoin(1)
        harness.equal(fake.calls, 1, "one question for the pair")
        harness.equal(boost:boostPct(1), 10, "seen from one side")
        harness.equal(boost:boostPct(2), 10, "and from the other")
    end)

    suite:test("friend boost: failures and non-boolean answers count 0 and are retried", function()
        local fake = newFake()
        fake.friends[key(1, 2)] = true
        local boost = newBoost(fake)
        fake.failing = true
        boost:onJoin(1)
        boost:onJoin(2)
        harness.equal(boost:boostPct(1), 0, "failed call is 0 %")
        fake.failing = false
        fake.junk = true
        harness.equal(boost:refreshUnanswered(), 1, "the failed pair is asked again")
        harness.equal(boost:boostPct(1), 0, "a non-boolean answer is 0 %")
        fake.junk = false
        harness.equal(boost:refreshUnanswered(), 1, "and again")
        harness.equal(boost:boostPct(1), 10, "recovered")
        harness.equal(boost:refreshUnanswered(), 0, "answered pairs are not asked again")
    end)

    suite:test("friend boost: answers are kept and dropped on leave", function()
        local fake = newFake()
        fake.friends[key(1, 2)] = true
        local boost = newBoost(fake)
        boost:onJoin(1)
        boost:onJoin(2)
        local after = fake.calls
        boost:refreshUnanswered()
        harness.equal(fake.calls, after, "no second call for an answered pair")
        boost:onLeave(2)
        harness.equal(boost:boostPct(1), 0, "friend left")
        boost:onJoin(2)
        harness.equal(fake.calls, after + 1, "a rejoin asks again")
        harness.equal(boost:boostPct(1), 10, "back")
        boost:onJoin(2)
        harness.equal(fake.calls, after + 1, "joining twice does nothing")
    end)

    suite:test("friend boost: a call that yields while another player joins is safe", function()
        local fake = newFake()
        fake.friends[key(1, 2)] = true
        fake.friends[key(1, 3)] = true
        fake.parking = true
        local boost = newBoost(fake)
        boost:onJoin(1)
        boost:onJoin(2)
        boost:onJoin(3)
        harness.equal(fake.calls, 3, "three pairs in parallel")
        fake.parking = false
        release(fake)
        harness.equal(boost:boostPct(1), 20, "both answers landed")
        harness.equal(boost:boostPct(2), 10, "player two has one friend")
        harness.equal(boost:boostPct(3), 10, "player three has one friend")
    end)

    suite:test(
        "friend boost: a player who leaves during the ask is asked again on return",
        function()
            local fake = newFake()
            fake.friends[key(1, 2)] = true
            fake.parking = true
            local boost = newBoost(fake)
            boost:onJoin(1)
            boost:onJoin(2)
            boost:onLeave(2)
            fake.parking = false
            release(fake)
            harness.equal(boost:boostPct(1), 0, "the answer of a player who left is dropped")
            local before = fake.calls
            boost:onJoin(2)
            harness.equal(fake.calls, before + 1, "asked again")
            harness.equal(boost:boostPct(1), 10, "and counted")
        end
    )

    suite:test("friend boost: at most maxConcurrentChecks questions run at once", function()
        local fake = newFake()
        fake.parking = true
        local boost = newBoost(fake)
        for userId = 1, 6 do
            boost:onJoin(userId)
        end
        harness.equal(fake.inFlight, 4, "four in flight, the rest queued")
        fake.parking = false
        for _ = 1, 10 do
            release(fake)
        end
        harness.equal(fake.peak, 4, "never above four")
        harness.equal(fake.calls, 15, "all 15 pairs were asked")
    end)

    suite:test(
        "friend boost: beforeChange runs before the count moves, onResolved after",
        function()
            local fake = newFake()
            fake.friends[key(1, 2)] = true
            local seen: { number } = {}
            local resolved = 0
            local holder: { boost: FriendBoost.FriendBoost? } = {}
            local boost = newBoost(fake, {
                beforeChange = function(userId: number)
                    local current = holder.boost
                    if current ~= nil and userId == 1 then
                        table.insert(seen, current:boostPct(1))
                    end
                end,
                onResolved = function(_a: number, _b: number)
                    resolved += 1
                    error("a failing hook must not break the boost")
                end,
            })
            holder.boost = boost
            boost:onJoin(1)
            boost:onJoin(2)
            harness.equal(seen[1], 0, "the old percentage was still in force")
            harness.equal(boost:boostPct(1), 10, "then it moved")
            harness.equal(resolved, 1, "resolved once")
            boost:onLeave(2)
            harness.equal(seen[2], 10, "leave also settles first")
        end
    )

    suite:test("social config is valid and rejects bad numbers", function()
        harness.equal(#SocialConfig.problems(SocialConfig.default), 0, "default valid")
        local bad: SocialConfig.SocialConfig = {
            friendBoost = {
                perFriendPct = -1,
                capPct = 300,
                maxConcurrentChecks = 0,
                retrySeconds = 0,
                retryMaxSeconds = 0,
            },
            invite = { rewardSeconds = 0, multiplier = 0.5, dailyPaidPerInviter = 0 },
            maxPerkMultiplier = 0,
        }
        harness.equal(#SocialConfig.problems(bad), 8, "eight problems")
        harness.equal(FriendBoost.pctFor(SocialConfig.default, -3), 0, "negative friends")
    end)
end
