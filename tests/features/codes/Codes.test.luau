--!strict
local Codes = require("../../../src/shared/features/codes/Codes")
local CodesConfig = require("../../../src/shared/features/codes/CodesConfig")
local ProductGrants = require("../../../src/shared/features/monetization/ProductGrants")
local harness = require("../../harness")

local config: CodesConfig.CodesConfig = {
    maxCodeLength = 16,
    attemptCooldownSeconds = 1,
    failureThreshold = 3,
    entries = {
        { code = "Welcome", reward = { kind = "coins", amount = 100 } },
        { code = "SPRING", reward = { kind = "coins", amount = 50 }, expiresAt = 1000 },
        { code = "TWICE", reward = { kind = "coins", amount = 10 }, maxRedemptions = 2 },
    },
}

type Fixture = {
    codes: Codes.Codes,
    profile: Codes.CodesProfile,
    advance: (seconds: number) -> (),
    online: (value: boolean) -> (),
}

local function newFixture(): Fixture
    local now = 100
    local present = true
    local profile: Codes.CodesProfile = { coins = 0, redeemedCodes = {} }
    local codes = Codes.new({
        config = config,
        now = function(): number
            return now
        end,
        profileFor = function(_userId: number): Codes.CodesProfile?
            if present then
                return profile
            end
            return nil
        end,
        grants = ProductGrants.new(Codes.grantTable(config)),
    })
    return {
        codes = codes,
        profile = profile,
        advance = function(seconds: number)
            now += seconds
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
    suite:test("redeems case-insensitively and trims the text", function()
        local fixture = newFixture()
        local result = fixture.codes:redeem(1, "  wElCoMe ")
        harness.isTrue(result.ok, "redeemed")
        harness.equal(fixture.profile.coins, 100, "coins granted")
        harness.equal(fixture.profile.redeemedCodes.WELCOME, 1, "use recorded")
    end)

    suite:test("an unknown code is invalid and grants nothing", function()
        local fixture = newFixture()
        local result = fixture.codes:redeem(1, "nope")
        harness.equal(errorOf(result), "invalid_code")
        harness.equal(fixture.profile.coins, 0, "no coins")
    end)

    suite:test("a code can be used once by default", function()
        local fixture = newFixture()
        fixture.codes:redeem(1, "WELCOME")
        fixture.advance(5)
        local again = fixture.codes:redeem(1, "welcome")
        harness.equal(errorOf(again), "already_redeemed")
        harness.equal(fixture.profile.coins, 100, "not granted twice")
    end)

    suite:test("maxRedemptions allows that many uses per player", function()
        local fixture = newFixture()
        harness.isTrue(fixture.codes:redeem(1, "TWICE").ok, "first")
        fixture.advance(5)
        harness.isTrue(fixture.codes:redeem(1, "TWICE").ok, "second")
        fixture.advance(5)
        harness.equal(errorOf(fixture.codes:redeem(1, "TWICE")), "already_redeemed")
        harness.equal(fixture.profile.coins, 20, "two grants")
    end)

    suite:test("an expired code is refused at its expiry instant", function()
        local fixture = newFixture()
        fixture.advance(900) -- now = 1000 = expiresAt
        harness.equal(errorOf(fixture.codes:redeem(1, "SPRING")), "expired")
        harness.equal(fixture.profile.coins, 0, "no coins")
    end)

    suite:test("a code is valid just before its expiry", function()
        local fixture = newFixture()
        fixture.advance(899)
        harness.isTrue(fixture.codes:redeem(1, "SPRING").ok, "still valid")
    end)

    suite:test("attempts inside the cooldown are refused", function()
        local fixture = newFixture()
        fixture.codes:redeem(1, "bad")
        harness.equal(errorOf(fixture.codes:redeem(1, "WELCOME")), "cooldown")
        fixture.advance(1)
        harness.isTrue(fixture.codes:redeem(1, "WELCOME").ok, "allowed after the cooldown")
    end)

    suite:test("the cooldown doubles after the failure threshold", function()
        local fixture = newFixture()
        for _ = 1, 3 do
            fixture.codes:redeem(1, "bad")
            fixture.advance(1)
        end
        -- Three failures: the last set a 2 s cooldown and only 1 s has passed.
        harness.equal(errorOf(fixture.codes:redeem(1, "WELCOME")), "cooldown")
        fixture.advance(1)
        harness.isTrue(fixture.codes:redeem(1, "WELCOME").ok, "allowed after 2 s")
    end)

    suite:test("a success resets the failure count", function()
        local fixture = newFixture()
        for _ = 1, 2 do
            fixture.codes:redeem(1, "bad")
            fixture.advance(1)
        end
        harness.isTrue(fixture.codes:redeem(1, "WELCOME").ok, "success")
        fixture.advance(1)
        fixture.codes:redeem(1, "bad")
        fixture.advance(1)
        harness.isTrue(fixture.codes:redeem(1, "SPRING").ok, "cooldown is back to 1 s")
    end)

    suite:test("no loaded data is reported", function()
        local fixture = newFixture()
        fixture.online(false)
        harness.equal(errorOf(fixture.codes:redeem(1, "WELCOME")), "no_data")
    end)

    suite:test("forget clears the attempt state", function()
        local fixture = newFixture()
        fixture.codes:redeem(1, "bad")
        fixture.codes:forget(1)
        harness.isTrue(fixture.codes:redeem(1, "WELCOME").ok, "fresh state")
    end)

    suite:test("a grant that fails records nothing", function()
        local fixture = newFixture()
        fixture.profile.coins = ProductGrants.MAX_COINS
        harness.equal(errorOf(fixture.codes:redeem(1, "WELCOME")), "grant_failed")
        harness.isTrue(fixture.profile.redeemedCodes.WELCOME == nil, "use not recorded")
    end)
end
