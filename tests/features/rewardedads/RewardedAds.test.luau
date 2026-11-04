--!strict
local AdGateway = require("../../../src/shared/ports/AdGateway")
local Config = require("../../../src/shared/Config")
local RewardedAds = require("../../../src/shared/features/rewardedads/RewardedAds")
local harness = require("../../harness")

type Fixture = {
    ads: RewardedAds.RewardedAds,
    shown: { AdGateway.ShowRequest },
    setOutcome: (outcome: AdGateway.ShowOutcome) -> (),
    setAllowed: (allowed: boolean) -> (),
    nextDay: () -> (),
    breakGateway: () -> (),
}

local PLACEMENT: Config.RewardedAdPlacementConfig = {
    name = "Lobby",
    placementId = 99,
    rewardProduct = "Coins100",
    label = "Watch an ad for coins",
}

local function newFixture(enabled: boolean, productId: number?): Fixture
    local shown: { AdGateway.ShowRequest } = {}
    local state = {
        outcome = "completed" :: AdGateway.ShowOutcome,
        allowed = true,
        day = 1,
        broken = false,
    }
    local gateway: AdGateway.AdGateway = {
        show = function(_self, _userId: number, request: AdGateway.ShowRequest)
            table.insert(shown, request)
            if state.broken then
                return { ok = false, error = { kind = "show_failed", message = "engine down" } }
            end
            return { ok = true, value = state.outcome }
        end,
    }
    local ads = RewardedAds.new({
        config = {
            enabled = enabled,
            disclosureLabel = "This is an ad",
            dailyCap = 2,
            placements = { PLACEMENT },
        },
        productIdOf = function(_name: string): number?
            return productId
        end,
        gateway = gateway,
        allow = function(_userId: number): boolean
            return state.allowed
        end,
        dayKey = function(): number
            return state.day
        end,
    })
    return {
        ads = ads,
        shown = shown,
        setOutcome = function(outcome: AdGateway.ShowOutcome)
            state.outcome = outcome
        end,
        setAllowed = function(allowed: boolean)
            state.allowed = allowed
        end,
        nextDay = function()
            state.day += 1
        end,
        breakGateway = function()
            state.broken = true
        end,
    }
end

local function reasonOf(result: RewardedAds.HandleResult): string
    if result.ok then
        return result.outcome
    end
    return result.reason
end

return function(suite: harness.Harness)
    suite:test("disabled by config: nothing is shown", function()
        local fixture = newFixture(false, 5)
        harness.equal(reasonOf(fixture.ads:handle(1, "Lobby")), "disabled", "reason")
        harness.equal(#fixture.shown, 0, "no ad")
        harness.equal(fixture.ads:remainingToday(1), 0, "button hidden")
    end)

    suite:test("a valid request shows the ad with the Config ids", function()
        local fixture = newFixture(true, 5)
        harness.equal(reasonOf(fixture.ads:handle(1, "Lobby")), "completed", "outcome")
        harness.equal(fixture.shown[1].rewardProductId, 5, "reward product id")
        harness.equal(fixture.shown[1].placementId, 99, "placement id")
    end)

    suite:test("rate limited and unknown placements never reach the gateway", function()
        local fixture = newFixture(true, 5)
        fixture.setAllowed(false)
        harness.equal(reasonOf(fixture.ads:handle(1, "Lobby")), "rate_limited", "limited")
        fixture.setAllowed(true)
        harness.equal(reasonOf(fixture.ads:handle(1, "Hack")), "not_allowed", "unknown")
        harness.equal(reasonOf(fixture.ads:handle(1, 12)), "not_a_string", "wrong type")
        harness.equal(#fixture.shown, 0, "no ad")
    end)

    suite:test("a product without an id is not shown", function()
        local fixture = newFixture(true, nil)
        harness.equal(reasonOf(fixture.ads:handle(1, "Lobby")), "reward_not_configured", "reason")
        harness.equal(#fixture.shown, 0, "no ad")
    end)

    suite:test("the daily cap counts completed ads and resets the next day", function()
        local fixture = newFixture(true, 5)
        fixture.ads:handle(1, "Lobby")
        fixture.ads:handle(1, "Lobby")
        harness.equal(fixture.ads:remainingToday(1), 0, "cap used")
        harness.equal(reasonOf(fixture.ads:handle(1, "Lobby")), "daily_cap_reached", "capped")
        fixture.nextDay()
        harness.equal(fixture.ads:remainingToday(1), 2, "new day")
        harness.equal(reasonOf(fixture.ads:handle(1, "Lobby")), "completed", "works again")
    end)

    suite:test("unavailable and interrupted ads are normal outcomes and are not counted", function()
        local fixture = newFixture(true, 5)
        fixture.setOutcome("notReady")
        harness.equal(reasonOf(fixture.ads:handle(1, "Lobby")), "notReady", "not ready")
        fixture.setOutcome("interrupted")
        harness.equal(reasonOf(fixture.ads:handle(1, "Lobby")), "interrupted", "interrupted")
        harness.equal(fixture.ads:remainingToday(1), 2, "cap untouched")
    end)

    suite:test("a gateway failure is a typed rejection with its detail", function()
        local fixture = newFixture(true, 5)
        fixture.breakGateway()
        local result = fixture.ads:handle(1, "Lobby")
        harness.equal(reasonOf(result), "show_failed", "reason")
        if not result.ok then
            harness.equal(result.detail, "engine down", "detail")
        end
    end)

    suite:test("disclosure and labels come from Config", function()
        local fixture = newFixture(true, 5)
        harness.equal(fixture.ads:disclosure(), "This is an ad", "disclosure")
        harness.equal(fixture.ads:labelOf("Lobby"), "Watch an ad for coins", "label")
        harness.isTrue(fixture.ads:labelOf("Nope") == nil, "unknown label")
    end)

    suite:test("forget clears the daily count", function()
        local fixture = newFixture(true, 5)
        fixture.ads:handle(1, "Lobby")
        fixture.ads:forget(1)
        harness.equal(fixture.ads:remainingToday(1), 2, "reset")
    end)
end
