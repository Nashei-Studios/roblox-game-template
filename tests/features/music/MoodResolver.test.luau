--!strict
local MoodResolver = require("../../../src/shared/features/music/MoodResolver")
local harness = require("../../harness")

local function rules(): MoodResolver.MoodRules
    return {
        rules = {
            MoodResolver.holdAfter("drop", "objective_won", 20, false),
            MoodResolver.holdAfter("outro", "objective_open", 5, true),
            MoodResolver.whileOn("buildup", "objective_open"),
            MoodResolver.sustained("run", "moving", 1, 3),
        },
        fallback = "hub",
    }
end

local KNOWN = { drop = true, outro = true, buildup = true, run = true, hub = true }

local function signals(state: { [string]: boolean })
    return {
        isOn = function(_self, name: string): boolean
            return state[name] == true
        end,
    }
end

return function(suite: harness.Harness)
    suite:test("a valid rule set has no problems and each mistake is named", function()
        harness.equal(#MoodResolver.validate(rules(), KNOWN), 0)
        local broken: MoodResolver.MoodRules = {
            rules = {
                MoodResolver.whileOn("nowhere", ""),
                {
                    mood = "hub",
                    signal = "x",
                    kind = "wobble",
                    holdSeconds = -1,
                    enterSeconds = -1,
                    onFall = false,
                },
                MoodResolver.holdAfter("hub", "x", 0, false),
            },
            fallback = "missing",
        }
        local problems = MoodResolver.validate(broken, KNOWN)
        harness.isTrue(#problems >= 7, `expected at least 7 problems, got {#problems}`)
    end)

    suite:test("the fallback plays when nothing is active", function()
        local resolver = MoodResolver.new({ rules = rules(), signals = signals({}) })
        harness.equal(resolver:mood(0), "hub")
    end)

    suite:test("a while rule follows its signal", function()
        local state: { [string]: boolean } = {}
        local resolver = MoodResolver.new({ rules = rules(), signals = signals(state) })
        state.objective_open = true
        harness.equal(resolver:mood(1), "buildup")
        state.objective_open = false
        -- Closing the open signal starts the outro hold (falling edge).
        harness.equal(resolver:mood(2), "outro")
        harness.equal(resolver:mood(7), "hub")
    end)

    suite:test("a hold on the rising edge lasts its seconds and outranks lower rules", function()
        local state: { [string]: boolean } = { objective_open = true }
        local resolver = MoodResolver.new({ rules = rules(), signals = signals(state) })
        harness.equal(resolver:mood(0), "buildup")
        state.objective_won = true
        harness.equal(resolver:mood(1), "drop")
        harness.equal(resolver:mood(20.9), "drop")
        harness.equal(resolver:mood(21), "buildup", "the hold ended, the open objective shows")
        state.objective_won = false
        state.objective_open = false
        harness.equal(resolver:mood(22), "outro")
    end)

    suite:test("a hold sees its edge even while a higher rule is active", function()
        local state: { [string]: boolean } = {}
        local both: MoodResolver.MoodRules = {
            rules = {
                MoodResolver.whileOn("drop", "force"),
                MoodResolver.holdAfter("outro", "blip", 10, false),
            },
            fallback = "hub",
        }
        local resolver = MoodResolver.new({ rules = both, signals = signals(state) })
        state.force = true
        harness.equal(resolver:mood(0), "drop")
        state.blip = true
        harness.equal(resolver:mood(1), "drop")
        state.force = false
        harness.equal(resolver:mood(2), "outro", "the blip was seen at t=1 and holds until 11")
        harness.equal(resolver:mood(11), "hub")
    end)

    suite:test("a sustained rule needs time to enter and lingers after it stops", function()
        local state: { [string]: boolean } = {}
        local resolver = MoodResolver.new({ rules = rules(), signals = signals(state) })
        state.moving = true
        harness.equal(resolver:mood(10), "hub", "just started")
        harness.equal(resolver:mood(10.5), "hub")
        harness.equal(resolver:mood(11), "run")
        state.moving = false
        harness.equal(resolver:mood(13.9), "run", "lingers")
        harness.equal(resolver:mood(14), "hub")
        state.moving = true
        harness.equal(resolver:mood(20), "hub", "a new start must be sustained again")
        state.moving = false
        harness.equal(resolver:mood(20.5), "hub", "a stutter never reached the entry time")
    end)
end
