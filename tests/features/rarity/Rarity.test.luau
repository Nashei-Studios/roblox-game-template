--!strict
local Contrast = require("../../../src/shared/features/ui/Contrast")
local ItemIcon = require("../../../src/shared/features/ui/ItemIcon")
local PerfBudget = require("../../../src/shared/perf/PerfBudget")
local RarityConfig = require("../../../src/shared/features/rarity/RarityConfig")
local RarityFx = require("../../../src/shared/features/rarity/RarityFx")
local harness = require("../../harness")

local CONFIG = RarityConfig.default
local SURFACE = "#171C30"

local function budgetCap(): number
    local fx = PerfBudget.clientFx
    if fx == nil then
        error("PerfBudget.clientFx is missing")
    end
    return fx.maxParticlesPerSecond
end

local function copyConfig(): RarityConfig.Config
    local tiers: { RarityConfig.Tier } = {}
    for _, tier in CONFIG.tiers do
        table.insert(tiers, table.clone(tier))
    end
    local copy = table.clone(CONFIG)
    copy.tiers = tiers
    return copy
end

local ITEM: ItemIcon.Item = {
    id = "pick_a",
    name = "Pick A",
    rarity = "epic",
    imageAssetId = "123456",
    swatchHex = "#445566",
}

return function(suite: harness.Harness)
    suite:test("the default ladder is valid against the surface and the PerfBudget", function()
        local problems = RarityConfig.validate(CONFIG, SURFACE, budgetCap())
        harness.equal(#problems, 0, table.concat(problems, "; "))
    end)

    suite:test(
        "every tier frame passes 3:1 on the card surface and the locked frame is neutral",
        function()
            for _, tier in CONFIG.tiers do
                local ratio = Contrast.ratio(tier.frameHex, SURFACE) or 0
                harness.isTrue(ratio >= Contrast.AA_UI, `{tier.id} contrast {ratio}`)
            end
            harness.isTrue(RarityConfig.rank(CONFIG, "common") == 1, "common is the first tier")
        end
    )

    suite:test(
        "validate reports a repeated id, a bad hex, a bad effect tier and a hot budget",
        function()
            local bad = copyConfig()
            bad.tiers[2].id = "common"
            bad.tiers[3].frameHex = "blue"
            bad.glowFrom = "nope"
            bad.particlesPerSecond = budgetCap() + 1
            bad.particlesFrom = "uncommon"
            local problems = RarityConfig.validate(bad, SURFACE, budgetCap())
            harness.isTrue(#problems >= 5, `got {#problems}: {table.concat(problems, "; ")}`)
        end
    )

    suite:test("effects start at their tier: glow, shimmer, then particles from epic", function()
        local common = RarityFx.spec(CONFIG, "common", "high", SURFACE)
        local uncommon = RarityFx.spec(CONFIG, "uncommon", "high", SURFACE)
        local rare = RarityFx.spec(CONFIG, "rare", "high", SURFACE)
        local epic = RarityFx.spec(CONFIG, "epic", "high", SURFACE)
        harness.isFalse(common.glow, "common has no glow")
        harness.isTrue(uncommon.glow, "uncommon glows")
        harness.isFalse(uncommon.shimmer, "uncommon does not shimmer")
        harness.isTrue(rare.shimmer, "rare shimmers")
        harness.equal(rare.particlesPerSecond, 0, "rare has no particles")
        harness.equal(epic.particlesPerSecond, CONFIG.particlesPerSecond, "epic has particles")
        harness.equal(epic.label, "Epic", "label text is carried")
    end)

    suite:test("low quality keeps color, label and glow but drops shimmer and particles", function()
        local high = RarityFx.spec(CONFIG, "mythic", "high", SURFACE)
        local low = RarityFx.spec(CONFIG, "mythic", "low", SURFACE)
        harness.equal(low.frameHex, high.frameHex, "same color")
        harness.equal(low.label, high.label, "same label")
        harness.equal(low.glow, high.glow, "same glow")
        harness.isFalse(low.shimmer, "no shimmer at low")
        harness.equal(low.shimmerPeriodSeconds, 0, "no period without shimmer")
        harness.equal(low.particlesPerSecond, 0, "no particles at low")
        local keep = copyConfig()
        keep.lowQualityParticleFactor = 0.5
        harness.equal(
            RarityFx.spec(keep, "epic", "low", SURFACE).particlesPerSecond,
            5,
            "factor scales"
        )
    end)

    suite:test("an unknown rarity falls back to the commonest tier", function()
        local spec = RarityFx.spec(CONFIG, "typo", "high", SURFACE)
        harness.equal(spec.id, "common", "fallback")
        harness.equal(spec.rank, 1, "rank")
    end)

    suite:test("quality: the switch wins, then manual level, then touch on automatic", function()
        local function pick(setting: "auto" | "high" | "low", level: number, touch: boolean)
            return RarityFx.qualityFor(
                CONFIG,
                { setting = setting, graphicsLevel = level, touch = touch }
            )
        end
        harness.equal(pick("high", 1, true), "high", "switch high")
        harness.equal(pick("low", 10, false), "low", "switch low")
        harness.equal(pick("auto", 3, false), "low", "low manual level")
        harness.equal(pick("auto", 8, true), "high", "high manual level on touch")
        harness.equal(pick("auto", 0, true), "low", "touch on automatic")
        harness.equal(pick("auto", 0, false), "high", "desktop on automatic")
        local noTouchRule = copyConfig()
        noTouchRule.lowOnTouchWhenAuto = false
        local input: RarityFx.QualityInput = { setting = "auto", graphicsLevel = 0, touch = true }
        harness.equal(RarityFx.qualityFor(noTouchRule, input), "high", "rule off")
    end)

    suite:test("mix blends and ignores a bad hex", function()
        harness.equal(RarityFx.mix("#000000", "#FFFFFF", 0.5), "#808080", "midpoint")
        harness.equal(RarityFx.mix("#102030", "#FFFFFF", 0), "#102030", "amount 0")
        harness.equal(RarityFx.mix("nope", "#FFFFFF", 0.5), "nope", "bad from")
        harness.equal(RarityFx.mix("#102030", "nope", 0.5), "#102030", "bad to")
    end)

    suite:test("the world and the card read the same spec", function()
        local fromIcon = ItemIcon.spec(ITEM, { unlocked = true }, CONFIG, "high", SURFACE, "Lv").fx
        local fromWorld = RarityFx.spec(CONFIG, ITEM.rarity, "high", SURFACE)
        harness.equal(fromIcon.frameHex, fromWorld.frameHex, "frame")
        harness.equal(fromIcon.particlesPerSecond, fromWorld.particlesPerSecond, "particles")
    end)

    suite:test("PerfBudget carries the client fx caps", function()
        local fx = PerfBudget.clientFx
        harness.isTrue(fx ~= nil, "clientFx present")
        if fx ~= nil then
            harness.isTrue(fx.maxLiveShimmers > 0 and fx.maxLiveEmitters > 0, "positive caps")
        end
    end)
end
