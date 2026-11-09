--!strict
local TierModelConfig = require("../../../src/shared/features/tiermodels/TierModelConfig")
local TierSurface = require("../../../src/shared/features/tiermodels/TierSurface")
local harness = require("../../harness")

local part = TierModelConfig.part

local function near(actual: number?, expected: number, tolerance: number, label: string)
    assert(actual ~= nil, `{label} is nil`)
    harness.isTrue(math.abs(actual - expected) <= tolerance, `{label}: {actual} vs {expected}`)
end

return function(suite: harness.Harness)
    suite:test("contains: a block holds its inside and not its outside", function()
        local block = part("block", { 4, 6, 2 }, { 1, 3, 0 }, "primary")
        harness.isTrue(TierSurface.contains(block, 1, 3, 0))
        harness.isTrue(TierSurface.contains(block, 2.9, 5.9, 0.9))
        harness.isFalse(TierSurface.contains(block, 3.2, 3, 0))
        harness.isFalse(TierSurface.contains(block, 1, 6.2, 0))
    end)

    suite:test("contains: a ball is an ellipsoid, not its box", function()
        local ball = part("ball", { 4, 4, 4 }, { 0, 2, 0 }, "primary")
        harness.isTrue(TierSurface.contains(ball, 0, 2, 0))
        harness.isTrue(TierSurface.contains(ball, 1.9, 2, 0))
        harness.isFalse(TierSurface.contains(ball, 1.9, 3.9, 1.9))
    end)

    suite:test("contains: yaw, pitch and roll turn the part", function()
        local plank = part("block", { 8, 1, 1 }, { 0, 0, 0 }, "primary", { 90, 0, 0 })
        harness.isTrue(TierSurface.contains(plank, 0, 0, 3.5), "yawed 90 degrees it lies along z")
        harness.isFalse(TierSurface.contains(plank, 3.5, 0, 0))
        local rolled = part("block", { 8, 1, 1 }, { 0, 0, 0 }, "primary", { 0, 0, 90 })
        harness.isTrue(TierSurface.contains(rolled, 0, 3.5, 0), "rolled 90 degrees it stands up")
        local pitched = part("block", { 1, 1, 8 }, { 0, 0, 0 }, "primary", { 0, 90, 0 })
        harness.isTrue(TierSurface.contains(pitched, 0, 3.5, 0), "pitched 90 degrees it stands up")
    end)

    suite:test("contains: a wedge rises toward +z and a cylinder is round across x", function()
        local wedge = part("wedge", { 4, 4, 4 }, { 0, 2, 0 }, "primary")
        harness.isTrue(TierSurface.contains(wedge, 0, 3.5, 1.9), "tall end")
        harness.isFalse(TierSurface.contains(wedge, 0, 3.5, -1.9), "low end is empty up high")
        harness.isTrue(TierSurface.contains(wedge, 0, 0.5, -0.5), "low end is solid near the base")
        local cylinder = part("cylinder", { 6, 4, 4 }, { 0, 2, 0 }, "primary")
        harness.isTrue(TierSurface.contains(cylinder, 2.9, 2, 0))
        harness.isFalse(TierSurface.contains(cylinder, 0, 3.9, 1.9), "corner of the square section")
    end)

    suite:test("radiusAt finds the outer surface along a direction", function()
        local block = { part("block", { 6, 6, 6 }, { 0, 3, 0 }, "primary") }
        near(TierSurface.radiusAt(block, 0, 3, 14), 3, 0.3, "+x face")
        near(TierSurface.radiusAt(block, math.pi / 2, 3, 14), 3, 0.3, "+z face")
        harness.equal(TierSurface.radiusAt(block, 0, 7, 14), nil)
    end)

    suite:test("radiusAt passes through the gap of an arch and reports nil", function()
        local arch = {
            part("block", { 3, 9, 3 }, { -6, 4.5, 0 }, "primary"),
            part("block", { 3, 9, 3 }, { 6, 4.5, 0 }, "primary"),
        }
        near(TierSurface.radiusAt(arch, 0, 4, 14), 7.5, 0.3, "pillar")
        harness.equal(TierSurface.radiusAt(arch, math.pi / 2, 4, 14), nil)
    end)

    suite:test("shell walks down to the first height with a surface", function()
        local mound = { part("block", { 8, 4, 8 }, { 0, 2, 0 }, "primary") }
        local spot = TierSurface.shell(mound, 0, 9, 14)
        assert(spot ~= nil, "mound has a shell")
        harness.isTrue(spot.y <= 4, "lowered under the top")
        near(spot.radius, 4, 0.3, "radius")
        harness.equal(TierSurface.shell({}, 0, 5, 14), nil)
    end)

    suite:test("height is the highest reach of any part", function()
        harness.equal(TierSurface.height({}), 0)
        harness.isTrue(
            TierSurface.height({ part("block", { 2, 12, 2 }, { 0, 6, 0 }, "glow") }) >= 12
        )
    end)
end
