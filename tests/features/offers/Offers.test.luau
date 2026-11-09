--!strict
local OfferRail = require("../../../src/shared/features/offers/OfferRail")
local PassLadder = require("../../../src/shared/features/offers/PassLadder")
local harness = require("../../harness")

local function ladder(): PassLadder.PassLadderConfig
    return {
        id = "income",
        stacking = "highest",
        maxMultiplier = 64,
        tiers = {
            { passName = "x2", multiplier = 2 },
            { passName = "x4", multiplier = 4 },
            { passName = "x8", multiplier = 8 },
        },
    }
end

local KNOWN = { x2 = true, x4 = true, x8 = true }

local function ownsOnly(names: { string }): (passName: string) -> boolean
    return function(passName: string): boolean
        return table.find(names, passName) ~= nil
    end
end

local function offer(id: string, rotating: boolean, startsAfter: number, maxAge: number?)
    return {
        id = id,
        kind = "product" :: OfferRail.ItemKind,
        itemName = "item_" .. id,
        rotating = rotating,
        startsAfterSessionSeconds = startsAfter,
        maxAccountAgeDays = maxAge,
        hideWhenOwned = false,
    }
end

type Overrides = { sessionSeconds: number?, age: number?, rotation: number? }

local function context(overrides: Overrides?): OfferRail.Context
    local o: Overrides = overrides or {}
    return {
        sessionSeconds = o.sessionSeconds or 1000,
        accountAgeDays = o.age or 0,
        owns = function(_kind: OfferRail.ItemKind, _name: string): boolean
            return false
        end,
        dismissed = {} :: { [string]: boolean },
        rotationIndex = o.rotation or 0,
    }
end

local function ids(offers: { OfferRail.Offer }): string
    local out: { string } = {}
    for _, o in offers do
        table.insert(out, o.id)
    end
    return table.concat(out, ",")
end

return function(suite: harness.Harness)
    suite:test("a valid ladder has no problems", function()
        harness.equal(#PassLadder.validate(ladder(), KNOWN), 0)
    end)

    suite:test("validate catches descending tiers, unknown passes and duplicates", function()
        local config = ladder()
        config.tiers[2].multiplier = 2
        config.tiers[3].passName = "x4"
        config.tiers[1].passName = "ghost"
        harness.equal(#PassLadder.validate(config, KNOWN), 3)
    end)

    suite:test("highest stacking takes the best owned tier only", function()
        harness.equal(PassLadder.multiplier(ladder(), ownsOnly({})), 1)
        harness.equal(PassLadder.multiplier(ladder(), ownsOnly({ "x2", "x8" })), 8)
    end)

    suite:test("product stacking multiplies and clips to the ceiling", function()
        local config = ladder()
        config.stacking = "product"
        config.maxMultiplier = 50
        harness.equal(PassLadder.multiplier(config, ownsOnly({ "x2", "x4" })), 8)
        harness.equal(PassLadder.multiplier(config, ownsOnly({ "x2", "x4", "x8" })), 50)
    end)

    suite:test("nextTier is the upsell and nil at the top", function()
        local first = PassLadder.nextTier(ladder(), ownsOnly({}))
        harness.equal(if first then first.passName else "none", "x2")
        local second = PassLadder.nextTier(ladder(), ownsOnly({ "x2" }))
        harness.equal(if second then second.passName else "none", "x4")
        harness.isTrue(PassLadder.nextTier(ladder(), ownsOnly({ "x8" })) == nil, "top")
    end)

    suite:test("priceOrderProblems flags a tier that costs no more than the one below", function()
        local prices: { [string]: number? } = { x2 = 49, x4 = 99, x8 = 99 }
        local problems = PassLadder.priceOrderProblems(ladder(), function(name: string)
            return prices[name]
        end)
        harness.equal(#problems, 1)
        prices.x8 = 249
        harness.equal(#PassLadder.priceOrderProblems(ladder(), function(name: string)
            return prices[name]
        end), 0)
        prices.x4 = nil
        harness.equal(#PassLadder.priceOrderProblems(ladder(), function(name: string)
            return prices[name]
        end), 1)
    end)

    suite:test("the rail shows permanent offers first, then the rotating window", function()
        local config: OfferRail.OfferRailConfig = {
            maxVisible = 4,
            rotatingSlots = 2,
            offers = {
                offer("p1", false, 0),
                offer("r1", true, 0),
                offer("r2", true, 0),
                offer("r3", true, 0),
            },
        }
        harness.equal(ids(OfferRail.visible(config, context({ rotation = 0 }))), "p1,r1,r2")
        harness.equal(ids(OfferRail.visible(config, context({ rotation = 2 }))), "p1,r3,r1")
        harness.equal(ids(OfferRail.visible(config, context({ rotation = 3 }))), "p1,r1,r2")
    end)

    suite:test("starter timing holds an offer back and closes it for veterans", function()
        local config: OfferRail.OfferRailConfig = {
            maxVisible = 3,
            rotatingSlots = 0,
            offers = { offer("starter", false, 300, 7) },
        }
        harness.equal(ids(OfferRail.visible(config, context({ sessionSeconds = 100 }))), "")
        harness.equal(ids(OfferRail.visible(config, context({ sessionSeconds = 300 }))), "starter")
        harness.equal(
            ids(OfferRail.visible(config, context({ sessionSeconds = 300, age = 8 }))),
            ""
        )
    end)

    suite:test("owned and dismissed offers are hidden", function()
        local pass = offer("vip", false, 0)
        pass.hideWhenOwned = true
        local config: OfferRail.OfferRailConfig =
            { maxVisible = 3, rotatingSlots = 0, offers = { pass, offer("pack", false, 0) } }
        local ctx = context()
        ctx.owns = function(_kind: OfferRail.ItemKind, name: string): boolean
            return name == "item_vip"
        end
        ctx.dismissed["pack"] = true
        harness.equal(ids(OfferRail.visible(config, ctx)), "")
    end)

    suite:test("maxVisible caps the rail and canPrompt only accepts shown offers", function()
        local config: OfferRail.OfferRailConfig = {
            maxVisible = 1,
            rotatingSlots = 1,
            offers = { offer("a", false, 0), offer("b", false, 0), offer("r", true, 0) },
        }
        local ctx = context()
        harness.equal(ids(OfferRail.visible(config, ctx)), "a")
        harness.isTrue(OfferRail.canPrompt(config, ctx, "a") ~= nil, "shown")
        harness.isTrue(OfferRail.canPrompt(config, ctx, "b") == nil, "hidden by the cap")
        harness.isTrue(OfferRail.canPrompt(config, ctx, "zzz") == nil, "unknown")
    end)

    suite:test("validate catches unknown items and bad numbers", function()
        local config: OfferRail.OfferRailConfig = {
            maxVisible = 0,
            rotatingSlots = -1,
            offers = { offer("a", false, -5), offer("a", false, 0) },
        }
        harness.isTrue(#OfferRail.validate(config, {}, {}) >= 5, "many problems")
        local good: OfferRail.OfferRailConfig =
            { maxVisible = 2, rotatingSlots = 1, offers = { offer("a", false, 0) } }
        harness.equal(#OfferRail.validate(good, {}, { item_a = true }), 0)
    end)
end
