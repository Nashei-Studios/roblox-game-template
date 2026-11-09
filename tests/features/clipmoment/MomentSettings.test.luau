--!strict
local MomentDirector = require("../../../src/shared/features/clipmoment/MomentDirector")
local MomentSettings = require("../../../src/shared/features/clipmoment/MomentSettings")
local harness = require("../../harness")

local function director(
    store: MomentSettings.Store,
    clock: { now: number }
): MomentDirector.Director
    return MomentDirector.new({
        config = MomentDirector.defaults({
            {
                id = "big",
                kind = "big_moment",
                beat = {
                    sting = "hit",
                    stingLeadSeconds = 0.3,
                    cameraKick = 1,
                    slowMoScale = nil,
                    slowMoSeconds = nil,
                    captureAfterSeconds = 0.5,
                    promptAfterCaptureSeconds = 1.5,
                },
            },
        }),
        now = function()
            return clock.now
        end,
        settings = function()
            return store:director()
        end,
    })
end

local function actions(plan: MomentDirector.Plan?): string
    local names: { string } = {}
    if plan ~= nil then
        for _, step in plan.steps do
            table.insert(names, step.action)
        end
    end
    return table.concat(names, ",")
end

return function(suite: harness.Harness)
    suite:test("everything is on by default and the rows list the three toggles", function()
        local toggles = MomentSettings.defaults()
        harness.isTrue(toggles.effects and toggles.sharePrompt and toggles.autoCapture, "all on")
        local rows = MomentSettings.rows()
        harness.equal(#rows, 3)
        local keys: { string } = {}
        for _, row in rows do
            table.insert(keys, row.key)
            harness.isTrue(row.default, "default on")
            harness.isTrue(row.label ~= "" and row.description ~= "", "has text")
        end
        harness.equal(table.concat(keys, ","), "effects,autoCapture,sharePrompt")
    end)

    suite:test("a prompt needs a capture: either toggle off removes it", function()
        local on =
            MomentSettings.resolve({ effects = true, sharePrompt = true, autoCapture = true })
        harness.isTrue(on.effects and on.sharePrompt, "prompt on")
        local noCapture =
            MomentSettings.resolve({ effects = true, sharePrompt = true, autoCapture = false })
        harness.isFalse(noCapture.sharePrompt, "no capture, no prompt")
        local noPrompt =
            MomentSettings.resolve({ effects = false, sharePrompt = false, autoCapture = true })
        harness.isFalse(noPrompt.sharePrompt, "opted out")
        harness.isFalse(noPrompt.effects, "effects off")
    end)

    suite:test("the director follows the toggles live and the sting always stays", function()
        local store = MomentSettings.new({ onError = function(_message) end })
        local clock = { now = 0 }
        local moment = director(store, clock)
        harness.equal(actions(moment:trigger("big")), "sting,camera_kick,capture,share_prompt")
        clock.now = 100
        store:set("sharePrompt", false)
        harness.equal(actions(moment:trigger("big")), "sting,camera_kick")
        clock.now = 200
        store:set("sharePrompt", true)
        store:set("autoCapture", false)
        store:set("effects", false)
        harness.equal(actions(moment:trigger("big")), "sting")
    end)

    suite:test(
        "a plan is routed: beats stay in the game, capture steps go to the presenter",
        function()
            local store = MomentSettings.new({ onError = function(_message) end })
            local plan = director(store, { now = 0 }):trigger("big")
            harness.isTrue(plan ~= nil, "plan")
            if plan ~= nil then
                local routed = MomentSettings.route(plan)
                harness.equal(#routed.local_, 2)
                harness.equal(#routed.capture, 2)
                harness.equal(routed.capture[1].action, "capture")
                harness.equal(routed.capture[2].action, "share_prompt")
                harness.equal(routed.local_[1].action, "sting")
            end
        end
    )

    suite:test("saved toggles load, foreign values are ignored and set saves", function()
        local saved: { MomentSettings.Toggles } = {}
        local store = MomentSettings.new({
            load = function(): { [string]: unknown }?
                local foreign: { [string]: unknown } =
                    { effects = false, sharePrompt = "yes", extra = true }
                return foreign
            end,
            save = function(toggles: MomentSettings.Toggles): boolean
                table.insert(saved, table.clone(toggles))
                return true
            end,
            onError = function(_message) end,
        })
        local toggles = store:get()
        harness.isFalse(toggles.effects, "loaded false")
        harness.isTrue(toggles.sharePrompt, "a non-boolean keeps the default")
        harness.isTrue(store:set("autoCapture", false), "set ok")
        harness.equal(#saved, 1)
        harness.isFalse(saved[1].autoCapture, "saved value")
        harness.isFalse(store:get().autoCapture, "get returns a copy of the state")
        local copy = store:get()
        copy.effects = true
        harness.isFalse(store:get().effects, "mutating the copy changes nothing")
    end)

    suite:test("a missing save, a failed save and an unknown key are reported", function()
        local errors: { string } = {}
        local failing = MomentSettings.new({
            load = function(): { [string]: unknown }?
                return nil
            end,
            save = function(_toggles): boolean
                return false
            end,
            onError = function(message: string)
                table.insert(errors, message)
            end,
        })
        harness.isFalse(failing:set("effects", false), "save failed")
        harness.isFalse(failing:set("bogus", true), "unknown key")
        harness.equal(#errors, 2)
        harness.isTrue(string.find(errors[1], "effects", 1, true) ~= nil, "names the key")
        local memory = MomentSettings.new({ onError = function(_message) end })
        harness.isTrue(memory:set("effects", false), "session-only store works")
    end)
end
