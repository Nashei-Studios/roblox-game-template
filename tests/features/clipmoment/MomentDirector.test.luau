--!strict
local MomentDirector = require("../../../src/shared/features/clipmoment/MomentDirector")
local harness = require("../../harness")

local function beat(): MomentDirector.Beat
    return {
        sting = "hit",
        stingLeadSeconds = 0.5,
        cameraKick = 0.6,
        slowMoScale = 0.3,
        slowMoSeconds = 1,
        captureAfterSeconds = 0.4,
        promptAfterCaptureSeconds = 1.2,
    }
end

local function config(): MomentDirector.MomentConfig
    return MomentDirector.defaults({
        { id = "big_break", kind = "big_break", beat = beat() },
        { id = "rare_drop", kind = "rare_drop", beat = beat() },
    })
end

local function has(problems: { string }, needle: string): boolean
    return string.find(table.concat(problems, "|"), needle, 1, true) ~= nil
end

local function rig(settings: MomentDirector.Settings?, cfg: MomentDirector.MomentConfig?)
    local clock = { now = 0 }
    local current: MomentDirector.Settings = settings or { effects = true, sharePrompt = true }
    local director = MomentDirector.new({
        config = cfg or config(),
        now = function()
            return clock.now
        end,
        settings = function()
            return current
        end,
    })
    return { director = director, clock = clock, settings = current }
end

local function actions(plan: MomentDirector.Plan): string
    local names: { string } = {}
    for _, step in plan.steps do
        table.insert(names, step.action)
    end
    return table.concat(names, ",")
end

return function(suite: harness.Harness)
    suite:test(
        "a valid config has no problems; advise flags a missing sting and no moments",
        function()
            harness.equal(#MomentDirector.validate(config()), 0)
            harness.equal(#MomentDirector.advise(config()), 0)
            local mute = config()
            mute.moments[1].beat.sting = nil
            harness.equal(#MomentDirector.advise(mute), 1)
            harness.equal(#MomentDirector.advise(MomentDirector.defaults({})), 1)
        end
    )

    suite:test("validate reports ids, kick, slow motion, delays and limits", function()
        local bad = config()
        bad.promptsPerSession = -1
        bad.minSecondsBetweenPrompts = -1
        bad.effectCooldownSeconds = -1
        bad.moments[1].id = ""
        bad.moments[1].kind = ""
        bad.moments[1].beat.cameraKick = 2
        bad.moments[1].beat.slowMoScale = 1.5
        bad.moments[1].beat.captureAfterSeconds = 99
        bad.moments[1].beat.sting = ""
        bad.moments[2].id = "rare_drop"
        bad.moments[2].beat.slowMoSeconds = nil
        local problems = MomentDirector.validate(bad)
        for _, needle in
            {
                "promptsPerSession",
                "minSecondsBetweenPrompts",
                "effectCooldown",
                "1 to 32",
                "needs a kind",
                "cameraKick",
                "slowMoScale",
                "captureAfterSeconds",
                "sting must",
                "together",
            }
        do
            harness.isTrue(has(problems, needle), needle)
        end
        local twice = config()
        twice.moments[2].id = "big_break"
        harness.isTrue(has(MomentDirector.validate(twice), "declared twice"))
        local long = config()
        long.moments[1].beat.slowMoSeconds = 9
        harness.isTrue(has(MomentDirector.validate(long), "slowMoSeconds"))
    end)

    suite:test(
        "a trigger times the hype: sting first, peak after the lead, capture, then prompt",
        function()
            local r = rig()
            local plan = r.director:trigger("big_break")
            harness.isTrue(plan ~= nil)
            if plan ~= nil then
                harness.equal(
                    actions(plan),
                    "sting,camera_kick,slow_mo_start,capture,slow_mo_end,share_prompt"
                )
                harness.equal(plan.steps[1].at, 0)
                harness.equal(plan.steps[2].at, 0.5, "camera at the peak, after the sting lead")
                harness.equal(plan.steps[4].at, 0.9)
                harness.equal(plan.steps[5].at, 1.5)
                harness.equal(plan.steps[6].at, 2.1)
                harness.equal(#plan.dropped, 0)
            end
        end
    )

    suite:test("an unknown moment gives no plan", function()
        harness.equal(rig().director:trigger("nope"), nil)
    end)

    suite:test("the prompt shows once per session; the sting and effects still play", function()
        local r = rig()
        harness.isTrue(r.director:trigger("big_break") ~= nil)
        r.clock.now = 100
        local second = r.director:trigger("rare_drop")
        harness.isTrue(second ~= nil)
        if second ~= nil then
            harness.equal(actions(second), "sting,camera_kick,slow_mo_start,slow_mo_end")
            harness.equal(second.dropped[1], "prompt_session_limit")
        end
        harness.equal(r.director:promptsShown(), 1)
    end)

    suite:test("with more prompts allowed, they keep a minimum gap", function()
        local cfg = config()
        cfg.promptsPerSession = 3
        local r = rig(nil, cfg)
        harness.isTrue(r.director:trigger("big_break") ~= nil)
        r.clock.now = 10
        local soon = r.director:trigger("big_break")
        harness.equal(soon ~= nil and soon.dropped[1] or "", "prompt_too_soon")
        r.clock.now = 70
        local later = r.director:trigger("big_break")
        harness.isTrue(later ~= nil and string.find(actions(later), "share_prompt", 1, true) ~= nil)
        harness.equal(r.director:promptsShown(), 2)
    end)

    suite:test("effects cool down so a chain of moments does not shake every second", function()
        local cfg = config()
        cfg.promptsPerSession = 9
        cfg.minSecondsBetweenPrompts = 0
        local r = rig(nil, cfg)
        harness.isTrue(r.director:trigger("big_break") ~= nil)
        r.clock.now = 2
        local chained = r.director:trigger("rare_drop")
        harness.equal(chained ~= nil and chained.dropped[1] or "", "effect_cooldown")
        harness.isTrue(
            chained ~= nil and string.find(actions(chained), "camera_kick", 1, true) == nil
        )
    end)

    suite:test("opt-out settings drop effects or the prompt but keep the sting", function()
        local quiet = rig({ effects = false, sharePrompt = false })
        local plan = quiet.director:trigger("big_break")
        harness.isTrue(plan ~= nil)
        if plan ~= nil then
            harness.equal(actions(plan), "sting")
            harness.equal(table.concat(plan.dropped, ","), "effects_off,prompt_opted_out")
        end
        harness.equal(quiet.director:promptsShown(), 0)
        local promptOnly = rig({ effects = false, sharePrompt = true })
        local second = promptOnly.director:trigger("big_break")
        harness.isTrue(second ~= nil and actions(second) == "sting,capture,share_prompt")
        harness.equal(second ~= nil and second.steps[2].at or -1, 0.9)
    end)

    suite:test("a moment with no sting and no effects only captures at the peak", function()
        local cfg = config()
        cfg.moments[1].beat = {
            sting = nil,
            stingLeadSeconds = 0,
            cameraKick = nil,
            slowMoScale = nil,
            slowMoSeconds = nil,
            captureAfterSeconds = 0,
            promptAfterCaptureSeconds = 0.5,
        }
        local plan = rig(nil, cfg).director:trigger("big_break")
        harness.isTrue(plan ~= nil and actions(plan) == "capture,share_prompt")
    end)
end
