--!strict
local HitFx = require("../../../src/shared/features/hitfx/HitFx")
local harness = require("../../harness")

local KINDS: { [string]: HitFx.HitSpec } = {
    dust = { count = 6, speedMin = 3, speedMax = 7, size = 0.35, lifetime = 0.4, glow = 0 },
    sparks = { count = 10, speedMin = 10, speedMax = 18, size = 0.2, lifetime = 0.3, glow = 0.6 },
}

return function(suite: harness.Harness)
    suite:test("valid kinds produce no problems", function()
        harness.equal(#HitFx.validate(KINDS), 0, table.concat(HitFx.validate(KINDS), "; "))
    end)

    suite:test("invalid kinds are reported one problem each", function()
        local bad: { [string]: HitFx.HitSpec } = {
            heavy = { count = 99, speedMin = 3, speedMax = 7, size = 1, lifetime = 1, glow = 0 },
            flat = { count = 5, speedMin = 9, speedMax = 2, size = 1, lifetime = 1, glow = 0 },
            glowy = { count = 5, speedMin = 1, speedMax = 2, size = 1, lifetime = 1, glow = 2 },
            zero = { count = 0, speedMin = 1, speedMax = 2, size = 1, lifetime = 1, glow = 0 },
            nan = { count = 0 / 0, speedMin = 1, speedMax = 2, size = 1, lifetime = 1, glow = 0 },
        }
        harness.equal(#HitFx.validate(bad), 5, table.concat(HitFx.validate(bad), "; "))
    end)

    suite:test("settings turn a spec into emitter numbers and unknown kinds into nil", function()
        local settings = HitFx.settings(KINDS, "sparks")
        harness.isTrue(settings ~= nil, "known kind")
        if settings ~= nil then
            harness.equal(settings.count, 10, "count")
            harness.equal(settings.lifetimeMax, 0.3, "longest")
            harness.isTrue(settings.lifetimeMin < settings.lifetimeMax, "shortest is shorter")
            harness.equal(settings.glow, 0.6, "glow")
        end
        harness.isTrue(HitFx.settings(KINDS, "missing") == nil, "unknown kind")
    end)
end
