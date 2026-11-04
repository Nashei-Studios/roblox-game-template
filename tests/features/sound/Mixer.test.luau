--!strict
local Mixer = require("../../../src/shared/features/sound/Mixer")
local harness = require("../../harness")

local function near(actual: number, expected: number, label: string)
    harness.isTrue(math.abs(actual - expected) < 1e-9, `{label}: expected {expected}, got {actual}`)
end

return function(suite: harness.Harness)
    suite:test("gain maps percent to 0..1 and clamps", function()
        near(Mixer.gain(50), 0.5, "half")
        near(Mixer.gain(-10), 0, "below")
        near(Mixer.gain(250), 1, "above")
        near(Mixer.gain(0 / 0), 0, "NaN")
    end)

    suite:test("mix multiplies the base volume by the group volume", function()
        near(Mixer.mix(0.5, 50), 0.25, "quarter")
        near(Mixer.mix(2, 100), 1, "base is clamped")
    end)

    suite:test("fade interpolates linearly and clamps the progress", function()
        near(Mixer.fade(0, 1, 0, 2), 0, "start")
        near(Mixer.fade(0, 1, 1, 2), 0.5, "middle")
        near(Mixer.fade(0, 1, 5, 2), 1, "past the end")
        near(Mixer.fade(1, 0, 0.5, 2), 0.75, "downwards")
        near(Mixer.fade(0, 1, -1, 2), 0, "before the start")
    end)

    suite:test("a zero duration jumps to the target", function()
        near(Mixer.fade(0, 1, 0, 0), 1, "instant")
    end)
end
