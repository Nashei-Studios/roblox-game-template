--!strict
local ProductGrants = require("../../../src/shared/features/monetization/ProductGrants")
local TimeRewards = require("../../../src/shared/features/timerewards/TimeRewards")
local TimeRewardsConfig = require("../../../src/shared/features/timerewards/TimeRewardsConfig")
local harness = require("../../harness")

local DAY = 86400

local config: TimeRewardsConfig.TimeRewardsConfig = {
    graceHours = 0,
    daily = {
        { day = 1, reward = { kind = "coins", amount = 10 } },
        { day = 2, reward = { kind = "coins", amount = 20 } },
    },
    sessionGifts = {
        { id = "five", afterMinutes = 5, reward = { kind = "coins", amount = 7 } },
    },
}

type Fixture = {
    service: TimeRewards.TimeRewards,
    profile: TimeRewards.TimeProfile,
    setNow: (value: number) -> (),
    online: (value: boolean) -> (),
}

local function newFixture(): Fixture
    local now = 10 * DAY
    local present = true
    local profile: TimeRewards.TimeProfile = {
        coins = 0,
        timeRewards = { lastDay = 0, streak = 0 },
    }
    local service = TimeRewards.new({
        config = config,
        now = function(): number
            return now
        end,
        profileFor = function(_userId: number): TimeRewards.TimeProfile?
            if present then
                return profile
            end
            return nil
        end,
        grants = ProductGrants.new(TimeRewards.grantTable(config)),
    })
    return {
        service = service,
        profile = profile,
        setNow = function(value: number)
            now = value
        end,
        online = function(value: boolean)
            present = value
        end,
    }
end

-- The error of a failed result, or "ok" for a success.
local function errorOf(result: unknown): string
    local record = result :: { [string]: unknown }
    return tostring(record.error or "ok")
end

return function(suite: harness.Harness)
    suite:test("the first daily claim grants day 1 and starts the streak", function()
        local fixture = newFixture()
        local result = fixture.service:claimDaily(1)
        harness.isTrue(result.ok and result.value.amount == 10, "day 1 reward")
        harness.equal(fixture.profile.coins, 10)
        harness.equal(fixture.profile.timeRewards.streak, 1)
    end)

    suite:test("claiming twice in the same day is idempotent", function()
        local fixture = newFixture()
        fixture.service:claimDaily(1)
        fixture.setNow(10 * DAY + 3600)
        harness.equal(errorOf(fixture.service:claimDaily(1)), "already_claimed")
        harness.equal(fixture.profile.coins, 10, "granted once")
    end)

    suite:test("consecutive days advance the schedule and then cycle", function()
        local fixture = newFixture()
        fixture.service:claimDaily(1)
        fixture.setNow(11 * DAY)
        fixture.service:claimDaily(1)
        fixture.setNow(12 * DAY)
        local third = fixture.service:claimDaily(1)
        harness.isTrue(third.ok and third.value.amount == 10 and third.value.streak == 3, "cycles")
        harness.equal(fixture.profile.coins, 40)
    end)

    suite:test("a skipped day resets the streak to day 1", function()
        local fixture = newFixture()
        fixture.service:claimDaily(1)
        fixture.setNow(13 * DAY)
        local result = fixture.service:claimDaily(1)
        harness.isTrue(result.ok and result.value.streak == 1, "reset")
    end)

    suite:test("a clock that went backwards grants nothing", function()
        local fixture = newFixture()
        fixture.service:claimDaily(1)
        fixture.setNow(8 * DAY)
        harness.equal(errorOf(fixture.service:claimDaily(1)), "clock_regressed")
        harness.equal(fixture.profile.coins, 10)
    end)

    suite:test("a failed grant does not advance the streak", function()
        local fixture = newFixture()
        fixture.profile.coins = ProductGrants.MAX_COINS
        harness.equal(errorOf(fixture.service:claimDaily(1)), "grant_failed")
        harness.equal(fixture.profile.timeRewards.lastDay, 0)
    end)

    suite:test("no loaded data is reported for both claims", function()
        local fixture = newFixture()
        fixture.online(false)
        harness.equal(errorOf(fixture.service:claimDaily(1)), "no_data")
        harness.equal(errorOf(fixture.service:claimSession(1, "five")), "no_data")
    end)

    suite:test("a session gift needs a started session", function()
        local fixture = newFixture()
        harness.equal(errorOf(fixture.service:claimSession(1, "five")), "no_session")
    end)

    suite:test("a session gift is granted once, after its time", function()
        local fixture = newFixture()
        fixture.service:startSession(1)
        harness.equal(errorOf(fixture.service:claimSession(1, "five")), "not_ready")
        fixture.setNow(10 * DAY + 300)
        harness.isTrue(fixture.service:claimSession(1, "five").ok, "claimed")
        harness.equal(errorOf(fixture.service:claimSession(1, "five")), "already_claimed")
        harness.equal(errorOf(fixture.service:claimSession(1, "nope")), "unknown_gift")
        harness.equal(fixture.profile.coins, 7)
    end)

    suite:test("a failed session grant stays claimable", function()
        local fixture = newFixture()
        fixture.service:startSession(1)
        fixture.setNow(10 * DAY + 300)
        fixture.profile.coins = ProductGrants.MAX_COINS
        harness.equal(errorOf(fixture.service:claimSession(1, "five")), "grant_failed")
        fixture.profile.coins = 0
        harness.isTrue(fixture.service:claimSession(1, "five").ok, "retry works")
    end)

    suite:test("forget drops the session", function()
        local fixture = newFixture()
        fixture.service:startSession(1)
        fixture.service:forget(1)
        harness.equal(errorOf(fixture.service:claimSession(1, "five")), "no_session")
    end)
end
