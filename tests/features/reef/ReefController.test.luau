--!strict
local ReefConfig = require("../../../src/shared/features/reef/ReefConfig")
local ReefController = require("../../../src/shared/features/reef/ReefController")
local ReefRules = require("../../../src/shared/features/reef/ReefRules")
local harness = require("../../harness")

type Fixture = {
    controller: ReefController.ReefController,
    data: ReefController.ReefData,
    advance: (seconds: number) -> (),
    passes: { [string]: boolean },
    near: { value: boolean },
    rolls: { number },
}

local function newFixture(): Fixture
    local now = 100
    local passes: { [string]: boolean } = {}
    local near = { value = true }
    -- rolls are consumed in order; an empty queue yields 0 (the first, most common outcome)
    local rolls: { number } = {}
    local controller = ReefController.new({
        table = ReefConfig.default,
        clock = function(): number
            return now
        end,
        rng = function(): number
            if #rolls == 0 then
                return 0
            end
            return table.remove(rolls, 1) :: number
        end,
        ownsPass = function(_userId: number, passName: string): boolean
            return passes[passName] == true
        end,
        isNearStand = function(_userId: number): boolean
            return near.value
        end,
    })
    local data: ReefController.ReefData = {
        coins = 0,
        rodLevel = 1,
        bait = 0,
        totalCatches = 0,
        fishStock = {},
    }
    return {
        controller = controller,
        data = data,
        advance = function(seconds: number)
            now += seconds
        end,
        passes = passes,
        near = near,
        rolls = rolls,
    }
end

local function castKind(result: ReefController.CastResult): string
    if result.ok then
        return "ok"
    end
    return result.error.kind
end

local function sellKind(result: ReefController.SellResult): string
    if result.ok then
        return "ok"
    end
    return result.error.kind
end

-- Casts and reels at the bite time; the data then holds one fish.
local function catchOne(fixture: Fixture)
    local cast = fixture.controller:cast(1, fixture.data, 1)
    assert(cast.ok, "cast should be accepted")
    fixture.advance(cast.value.biteDelaySeconds)
    local reel = fixture.controller:reel(1, fixture.data)
    assert(reel.ok and reel.value.caught, "reel should land the fish")
end

return function(suite: harness.Harness)
    suite:test("the first cast of a new player bites within the tutorial delay", function()
        local fixture = newFixture()
        local cast = fixture.controller:cast(1, fixture.data, 1)
        harness.isTrue(cast.ok, "accepted")
        if cast.ok then
            harness.equal(cast.value.biteDelaySeconds, ReefRules.TUTORIAL_BITE_SECONDS, "delay")
            harness.isTrue(cast.value.biteDelaySeconds <= 5, "within 5 seconds")
        end
    end)

    suite:test("reeling inside the window lands the rolled fish", function()
        local fixture = newFixture()
        local cast = fixture.controller:cast(1, fixture.data, 1)
        harness.isTrue(cast.ok, "cast")
        fixture.advance(ReefRules.TUTORIAL_BITE_SECONDS + 0.5)
        local reel = fixture.controller:reel(1, fixture.data)
        harness.isTrue(reel.ok and reel.value.caught, "caught")
        if reel.ok and reel.value.caught then
            harness.equal(reel.value.fishId, "minnow", "first fish with a zero roll")
        end
        harness.equal(fixture.data.fishStock.minnow, 1, "stock")
        harness.equal(fixture.data.totalCatches, 1, "total")
    end)

    suite:test("reeling before the bite misses and ends the cast", function()
        local fixture = newFixture()
        fixture.controller:cast(1, fixture.data, 1)
        fixture.advance(1)
        local reel = fixture.controller:reel(1, fixture.data)
        harness.isTrue(reel.ok and not reel.value.caught, "missed")
        if reel.ok and not reel.value.caught then
            harness.equal(reel.value.reason, "too_early", "reason")
        end
        harness.equal(fixture.data.totalCatches, 0, "nothing caught")
        harness.equal(fixture.controller:reel(1, fixture.data).ok, false, "cast is gone")
    end)

    suite:test("reeling after the window misses", function()
        local fixture = newFixture()
        fixture.controller:cast(1, fixture.data, 1)
        fixture.advance(ReefRules.TUTORIAL_BITE_SECONDS + ReefRules.REEL_WINDOW_SECONDS + 0.1)
        local reel = fixture.controller:reel(1, fixture.data)
        harness.isTrue(reel.ok and not reel.value.caught, "missed")
        if reel.ok and not reel.value.caught then
            harness.equal(reel.value.reason, "too_late", "reason")
        end
    end)

    suite:test("reel without a cast is a typed error", function()
        local fixture = newFixture()
        local reel = fixture.controller:reel(1, fixture.data)
        harness.isFalse(reel.ok, "rejected")
        if not reel.ok then
            harness.equal(reel.error.kind, "no_cast", "kind")
        end
    end)

    suite:test("a second cast while one is live is refused, an expired one is replaced", function()
        local fixture = newFixture()
        fixture.controller:cast(1, fixture.data, 1)
        harness.equal(castKind(fixture.controller:cast(1, fixture.data, 1)), "cast_pending")
        fixture.advance(60)
        harness.equal(castKind(fixture.controller:cast(1, fixture.data, 1)), "ok", "expired")
    end)

    suite:test("zone input is validated and locked by the rod", function()
        local fixture = newFixture()
        harness.equal(castKind(fixture.controller:cast(1, fixture.data, "1")), "invalid_zone")
        harness.equal(castKind(fixture.controller:cast(1, fixture.data, 0)), "invalid_zone")
        harness.equal(castKind(fixture.controller:cast(1, fixture.data, 1.5)), "invalid_zone")
        harness.equal(castKind(fixture.controller:cast(1, fixture.data, 99)), "invalid_zone")
        local locked = fixture.controller:cast(1, fixture.data, 2)
        harness.equal(castKind(locked), "zone_locked", "rod 1 does not reach zone 2")
        if not locked.ok and locked.error.kind == "zone_locked" then
            harness.equal(locked.error.maxZone, 1, "maxZone")
        end
        fixture.data.rodLevel = 2
        harness.equal(castKind(fixture.controller:cast(1, fixture.data, 2)), "ok", "rod 2")
    end)

    suite:test("a rod level outside the table falls back to zone 1", function()
        local fixture = newFixture()
        fixture.data.rodLevel = 99
        harness.equal(castKind(fixture.controller:cast(1, fixture.data, 2)), "zone_locked")
    end)

    suite:test("the rolled fish follows the weights", function()
        local fresh = newFixture()
        fresh.data.totalCatches = 1
        table.insert(fresh.rolls, 0) -- bite delay
        table.insert(fresh.rolls, 0.99) -- fish: the rarest of zone 1
        local cast = fresh.controller:cast(1, fresh.data, 1)
        harness.isTrue(cast.ok, "cast")
        if cast.ok then
            fresh.advance(cast.value.biteDelaySeconds)
        end
        local reel = fresh.controller:reel(1, fresh.data)
        harness.isTrue(reel.ok and reel.value.caught, "caught")
        if reel.ok and reel.value.caught then
            harness.equal(reel.value.fishId, "perch", "rare fish")
        end
    end)

    suite:test("bait halves the delay, is spent once, and never changes the fish", function()
        local plain = newFixture()
        plain.data.totalCatches = 1
        local plainCast = plain.controller:cast(1, plain.data, 1)
        local baited = newFixture()
        baited.data.totalCatches = 1
        baited.data.bait = 2
        local baitedCast = baited.controller:cast(1, baited.data, 1)
        harness.isTrue(plainCast.ok and baitedCast.ok, "both cast")
        if plainCast.ok and baitedCast.ok then
            harness.equal(
                baitedCast.value.biteDelaySeconds,
                plainCast.value.biteDelaySeconds * ReefRules.BAIT_BITE_FACTOR,
                "delay"
            )
            harness.isTrue(baitedCast.value.usedBait, "usedBait")
            harness.isFalse(plainCast.value.usedBait, "no bait, none used")
        end
        harness.equal(baited.data.bait, 1, "one spent")
    end)

    suite:test("the tutorial cast does not spend bait", function()
        local fixture = newFixture()
        fixture.data.bait = 3
        fixture.controller:cast(1, fixture.data, 1)
        harness.equal(fixture.data.bait, 3, "bait")
    end)

    suite:test("a refused cast does not spend bait", function()
        local fixture = newFixture()
        fixture.data.totalCatches = 1
        fixture.data.bait = 1
        fixture.controller:cast(1, fixture.data, 1)
        harness.equal(fixture.data.bait, 0, "spent once")
        fixture.data.bait = 1
        harness.equal(castKind(fixture.controller:cast(1, fixture.data, 1)), "cast_pending")
        harness.equal(fixture.data.bait, 1, "not spent by the refused cast")
    end)

    suite:test("the bucket fills up and the BiggerBucket pass raises its size", function()
        local fixture = newFixture()
        fixture.data.fishStock = { minnow = ReefRules.BASE_BUCKET }
        local full = fixture.controller:cast(1, fixture.data, 1)
        harness.equal(castKind(full), "bucket_full")
        if not full.ok and full.error.kind == "bucket_full" then
            harness.equal(full.error.capacity, ReefRules.BASE_BUCKET, "capacity")
        end
        fixture.passes[ReefRules.BIGGER_BUCKET_PASS] = true
        harness.equal(
            fixture.controller:bucketCapacity(1),
            ReefRules.BASE_BUCKET + ReefRules.BUCKET_PASS_EXTRA,
            "capacity with pass"
        )
        harness.equal(castKind(fixture.controller:cast(1, fixture.data, 1)), "ok", "room again")
    end)

    suite:test("selling pays the table value, empties the bucket, and needs the stand", function()
        local fixture = newFixture()
        fixture.data.fishStock = { minnow = 2, snapper = 1 }
        fixture.near.value = false
        harness.equal(sellKind(fixture.controller:sell(1, fixture.data)), "not_near_stand")
        harness.equal(fixture.data.coins, 0, "nothing paid away from the stand")
        fixture.near.value = true
        local sold = fixture.controller:sell(1, fixture.data)
        harness.isTrue(sold.ok, "sold")
        if sold.ok then
            harness.equal(sold.value.coinsEarned, 2 * 6 + 30, "earned")
            harness.equal(sold.value.fishSold, 3, "count")
        end
        harness.equal(fixture.data.coins, 42, "coins")
        harness.equal(fixture.controller:stockCount(fixture.data), 0, "empty")
        harness.equal(sellKind(fixture.controller:sell(1, fixture.data)), "empty_bucket")
    end)

    suite:test("the SellAnywhere pass skips the stand check", function()
        local fixture = newFixture()
        fixture.data.fishStock = { minnow = 1 }
        fixture.near.value = false
        fixture.passes[ReefRules.SELL_ANYWHERE_PASS] = true
        harness.equal(sellKind(fixture.controller:sell(1, fixture.data)), "ok")
    end)

    suite:test(
        "an unknown fish id in the stock is sold for nothing, not for a client number",
        function()
            local fixture = newFixture()
            fixture.data.fishStock = { ghost = 4, minnow = 1 }
            local sold = fixture.controller:sell(1, fixture.data)
            harness.isTrue(sold.ok, "sold")
            if sold.ok then
                harness.equal(sold.value.coinsEarned, 6, "only the known fish pays")
            end
        end
    )

    suite:test("a sale that would overflow coins is refused and keeps the fish", function()
        local fixture = newFixture()
        fixture.data.coins = 2 ^ 53
        fixture.data.fishStock = { minnow = 1 }
        harness.equal(sellKind(fixture.controller:sell(1, fixture.data)), "overflow")
        harness.equal(fixture.data.fishStock.minnow, 1, "fish kept")
    end)

    suite:test("buying a rod derives the price from the saved level", function()
        local fixture = newFixture()
        fixture.data.coins = 11
        local short = fixture.controller:buyRod(1, fixture.data)
        harness.isFalse(short.ok, "too poor")
        if not short.ok and short.error.kind == "not_enough_coins" then
            harness.equal(short.error.price, 12, "price")
            harness.equal(short.error.coins, 11, "coins")
        end
        harness.equal(fixture.data.rodLevel, 1, "unchanged")
        fixture.data.coins = 20
        local bought = fixture.controller:buyRod(1, fixture.data)
        harness.isTrue(bought.ok, "bought")
        harness.equal(fixture.data.rodLevel, 2, "level")
        harness.equal(fixture.data.coins, 8, "coins")
    end)

    suite:test("the last rod cannot be bought twice", function()
        local fixture = newFixture()
        fixture.data.rodLevel = #ReefConfig.default.rods
        fixture.data.coins = 1e6
        local result = fixture.controller:buyRod(1, fixture.data)
        harness.isFalse(result.ok, "refused")
        if not result.ok then
            harness.equal(result.error.kind, "max_rod", "kind")
        end
        harness.equal(fixture.data.coins, 1e6, "coins")
    end)

    suite:test("a fresh player can afford the second rod after about two catches", function()
        local fixture = newFixture()
        for _ = 1, 2 do
            catchOne(fixture)
            fixture.advance(60)
        end
        harness.equal(fixture.controller:stockCount(fixture.data), 2, "two fish")
        local sold = fixture.controller:sell(1, fixture.data)
        harness.isTrue(sold.ok, "sold")
        harness.isTrue(fixture.controller:buyRod(1, fixture.data).ok, "second rod bought")
    end)

    suite:test("isPending recognises only the live cast and forget clears it", function()
        local fixture = newFixture()
        local cast = fixture.controller:cast(1, fixture.data, 1)
        harness.isTrue(cast.ok, "cast")
        if cast.ok then
            harness.isTrue(fixture.controller:isPending(1, cast.value.castId), "live")
            harness.isFalse(fixture.controller:isPending(1, cast.value.castId + 1), "other id")
            harness.isFalse(fixture.controller:isPending(2, cast.value.castId), "other player")
            fixture.controller:forget(1)
            harness.isFalse(fixture.controller:isPending(1, cast.value.castId), "forgotten")
            local again = fixture.controller:cast(1, fixture.data, 1)
            harness.isTrue(again.ok and again.value.castId ~= cast.value.castId, "new id")
        end
    end)
end
