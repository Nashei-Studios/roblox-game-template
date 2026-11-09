--!strict
local ItemIcon = require("../../../src/shared/features/ui/ItemIcon")
local MomentDirector = require("../../../src/shared/features/clipmoment/MomentDirector")
local RarityConfig = require("../../../src/shared/features/rarity/RarityConfig")
local RevealMoment = require("../../../src/shared/features/reveal/RevealMoment")
local harness = require("../../harness")

local RARITY = RarityConfig.default
local CONFIG = RevealMoment.defaults()
local SURFACE = "#171C30"

local function item(rarity: string): ItemIcon.Item
    return {
        id = "pick_a",
        name = "Pick A",
        rarity = rarity,
        imageAssetId = "123456",
        swatchHex = "#445566",
    }
end

local function build(rarity: string, quality: "high" | "low", random: boolean, odds: number?)
    local result = RevealMoment.spec(
        CONFIG,
        RARITY,
        { item = item(rarity), random = random, oddsPercent = odds },
        quality,
        SURFACE
    )
    if not result.ok then
        error(result.error)
    end
    return result.value
end

return function(suite: harness.Harness)
    suite:test("the defaults are valid and last between 1.5 and 2.5 seconds", function()
        local problems = RevealMoment.validate(CONFIG, RARITY)
        harness.equal(#problems, 0, table.concat(problems, "; "))
    end)

    suite:test("validate reports a long reveal, a bad beam tier and too many beams", function()
        local bad = table.clone(CONFIG)
        bad.durationSeconds = 4
        bad.beamsFrom = "nope"
        bad.maxBeams = 99
        bad.tapGuardSeconds = 5
        harness.equal(#RevealMoment.validate(bad, RARITY), 4)
    end)

    suite:test("beams scale with the tier: none below Rare, more per tier, capped", function()
        harness.equal(build("common", "high", false, nil).beams.count, 0)
        harness.equal(build("uncommon", "high", false, nil).beams.count, 0)
        harness.equal(build("rare", "high", false, nil).beams.count, 4)
        harness.equal(build("epic", "high", false, nil).beams.count, 6)
        harness.equal(build("legendary", "high", false, nil).beams.count, 8)
        harness.equal(build("mythic", "high", false, nil).beams.count, 8)
    end)

    suite:test("the low quality switch halves the beams and drops the particles", function()
        local high = build("epic", "high", false, nil)
        local low = build("epic", "low", false, nil)
        harness.equal(low.beams.count, 3)
        harness.equal(#low.beams.anglesDegrees, 3)
        harness.isTrue(high.particlesPerSecond > 0, "high keeps particles")
        harness.equal(low.particlesPerSecond, 0)
        harness.equal(low.rarityHex, high.rarityHex, "color stays at low quality")
    end)

    suite:test("the spec carries the name, the rarity label, color and an even beam fan", function()
        local spec = build("legendary", "high", false, nil)
        harness.equal(spec.name, "Pick A")
        harness.equal(spec.rarityLabel, "Legendary")
        harness.equal(spec.rarityHex, "#FF8A3D")
        harness.equal(spec.icon.imageUrl, "rbxassetid://123456")
        harness.equal(spec.beams.anglesDegrees[1], 0)
        harness.equal(spec.beams.anglesDegrees[2], 45)
        harness.equal(spec.oddsText, nil)
    end)

    suite:test("a random source needs odds and shows them", function()
        local missing = RevealMoment.spec(
            CONFIG,
            RARITY,
            { item = item("rare"), random = true, oddsPercent = nil },
            "high",
            SURFACE
        )
        harness.isFalse(missing.ok, "no odds is refused")
        local zero = RevealMoment.problems({ item = item("rare"), random = true, oddsPercent = 0 })
        harness.equal(#zero, 1)
        harness.equal(build("rare", "high", true, 12.5).oddsText, "12.5%")
        harness.equal(build("rare", "high", true, 3).oddsText, "3%")
        harness.equal(RevealMoment.oddsText(0.05), "0.05%")
    end)

    suite:test("a session blocks input only while showing and ends by itself", function()
        local session = RevealMoment.session(build("epic", "high", false, nil))
        harness.isFalse(session:blocksInput(), "not before start")
        session:start(10)
        harness.isTrue(session:blocksInput(), "while showing")
        harness.equal(session:tick(11), "showing")
        harness.equal(session:progress(11), 0.5)
        harness.equal(session:tick(12), "done")
        harness.isFalse(session:blocksInput(), "released at the end")
        harness.equal(session:progress(99), 1)
    end)

    suite:test("one tap ends the reveal, but the guard ignores the tap that caused it", function()
        local session = RevealMoment.session(build("epic", "high", false, nil))
        harness.isFalse(session:dismiss(0), "pending ignores taps")
        session:start(10)
        harness.isFalse(session:dismiss(10.1), "inside the guard")
        harness.isTrue(session:dismiss(10.5), "after the guard")
        harness.equal(session:state(), "done")
        harness.isFalse(session:dismiss(10.6), "already done")
    end)

    suite:test("the reveal registers as a clip moment the director can time", function()
        local def = RevealMoment.momentDef("reveal_item", CONFIG)
        local config = MomentDirector.defaults({ def })
        harness.equal(
            #MomentDirector.validate(config),
            0,
            table.concat(MomentDirector.validate(config), "; ")
        )
        local director = MomentDirector.new({
            config = config,
            now = function()
                return 0
            end,
            settings = function()
                return { effects = true, sharePrompt = true }
            end,
        })
        local plan = director:trigger("reveal_item")
        harness.isTrue(plan ~= nil and #plan.steps >= 2, "capture and prompt are planned")
    end)
end
