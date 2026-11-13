--!strict
--[[
    Tests of the pure UI motion table (docs/adr/0063): the presets of the game 2 spec, the
    duration limits, the no-ease-In rule, reduced motion and the counter.
]]

local harness = require("../../harness")
local UiMotion = require("../../../src/shared/features/ui/UiMotion")

return function(suite: harness.Harness)
    suite:test("the preset table validates", function()
        harness.equal(#UiMotion.validate(UiMotion.PRESETS), 0)
    end)

    suite:test("durations match the spec table", function()
        harness.equal(UiMotion.preset("modalOpen").seconds, 0.2)
        harness.equal(UiMotion.preset("modalClose").seconds, 0.14)
        harness.equal(UiMotion.preset("pressDown").seconds, 0.09)
        harness.equal(UiMotion.preset("pressUp").seconds, 0.14)
        harness.equal(UiMotion.preset("hoverIn").seconds, 0.12)
        harness.equal(UiMotion.preset("notificationPop").seconds, 0.16)
        harness.equal(UiMotion.preset("counter").seconds, 0.25)
    end)

    suite:test("an unknown preset errors", function()
        harness.isFalse((pcall(UiMotion.preset, "nope")))
    end)

    suite:test("validate rejects a slow, ease-In or unpaired preset", function()
        local bad: { [string]: UiMotion.Preset } = {
            slow = { seconds = 0.5, style = "Quad", direction = "Out" },
            easeIn = { seconds = 0.1, style = "Quad", direction = "In" },
            half = { seconds = 0.1, style = "Quad", direction = "Out", scaleFrom = 1 },
        }
        harness.equal(#UiMotion.validate(bad), 3)
    end)

    suite:test("reveal may take 320 ms, others may not", function()
        local reveal: { [string]: UiMotion.Preset } =
            { resultReveal = { seconds = 0.32, style = "Back", direction = "Out" } }
        local other: { [string]: UiMotion.Preset } =
            { modalOpen = { seconds = 0.32, style = "Back", direction = "Out" } }
        harness.equal(#UiMotion.validate(reveal), 0)
        harness.equal(#UiMotion.validate(other), 1)
    end)

    suite:test("normal motion returns the preset unchanged", function()
        local resolved = UiMotion.resolve("modalOpen", false)
        harness.isTrue(resolved ~= nil and resolved.scaleTo == 1)
    end)

    suite:test("reduced motion keeps a fade of the same duration and drops the scale", function()
        local resolved = UiMotion.resolve("modalOpen", true)
        harness.isTrue(resolved ~= nil)
        if resolved ~= nil then
            harness.equal(resolved.seconds, 0.2)
            harness.equal(resolved.scaleTo, nil)
            harness.equal(resolved.fadeTo, 0)
        end
    end)

    suite:test("reduced motion plays nothing for scale-only motion", function()
        harness.equal(UiMotion.resolve("pressDown", true), nil)
        harness.equal(UiMotion.resolve("hoverIn", true), nil)
        harness.equal(UiMotion.resolve("counter", true), nil)
    end)

    suite:test("counter eases to the target and lands exactly", function()
        harness.equal(UiMotion.countValue(0, 100, 0, 0.25, false), 0)
        harness.equal(UiMotion.countValue(0, 100, 0.125, 0.25, false), 75)
        harness.equal(UiMotion.countValue(0, 100, 0.25, 0.25, false), 100)
        harness.equal(UiMotion.countValue(0, 100, 9, 0.25, false), 100)
    end)

    suite:test("counter jumps at once under reduced motion or zero duration", function()
        harness.equal(UiMotion.countValue(0, 100, 0, 0.25, true), 100)
        harness.equal(UiMotion.countValue(5, 9, 0, 0, false), 9)
    end)

    suite:test("counts down too and clamps the ease", function()
        harness.equal(UiMotion.countValue(100, 0, 0.125, 0.25, false), 25)
        harness.equal(UiMotion.easeQuadOut(-1), 0)
        harness.equal(UiMotion.easeQuadOut(2), 1)
    end)
end
