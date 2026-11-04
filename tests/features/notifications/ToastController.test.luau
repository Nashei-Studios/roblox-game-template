--!strict
local NotificationsConfig =
    require("../../../src/shared/features/notifications/NotificationsConfig")
local ToastController = require("../../../src/shared/features/notifications/ToastController")
local ToastRenderer = require("../../../src/shared/ports/ToastRenderer")
local harness = require("../../harness")

local config: NotificationsConfig.NotificationsConfig = {
    maxQueue = 4,
    maxVisible = 1,
    dedupeSeconds = 1,
    maxWaitSeconds = 30,
    kinds = {
        win = { text = "You got {amount}", style = "success", durationSeconds = 3, sound = "ding" },
        note = { text = "Hello", style = "info", durationSeconds = 2 },
    },
}

type Fixture = {
    controller: ToastController.ToastController,
    shown: { ToastRenderer.Toast },
    hidden: { number },
    played: { string },
}

local function newFixture(): Fixture
    local shown: { ToastRenderer.Toast } = {}
    local hidden: { number } = {}
    local played: { string } = {}
    local renderer: ToastRenderer.ToastRenderer = {
        show = function(_self: ToastRenderer.ToastRenderer, toast: ToastRenderer.Toast)
            table.insert(shown, toast)
        end,
        hide = function(_self: ToastRenderer.ToastRenderer, toastId: number)
            table.insert(hidden, toastId)
        end,
    }
    local controller = ToastController.new({
        config = config,
        renderer = renderer,
        playSound = function(name: string)
            table.insert(played, name)
        end,
    })
    return { controller = controller, shown = shown, hidden = hidden, played = played }
end

return function(suite: harness.Harness)
    suite:test("a known kind is shown with its amount and plays its sound", function()
        local fixture = newFixture()
        harness.isTrue(fixture.controller:receive("win", 25, 0), "accepted")
        harness.equal(fixture.shown[1].text, "You got 25")
        harness.equal(fixture.shown[1].style, "success")
        harness.equal(fixture.played[1], "ding")
    end)

    suite:test("an unknown kind shows nothing", function()
        local fixture = newFixture()
        harness.isFalse(fixture.controller:receive("hack", 1, 0), "refused")
        harness.equal(#fixture.shown, 0)
    end)

    suite:test("a toast waits for a free slot and replaces the expired one", function()
        local fixture = newFixture()
        fixture.controller:receive("win", 1, 0)
        fixture.controller:receive("note", 0, 0)
        harness.equal(#fixture.shown, 1, "one slot")
        fixture.controller:tick(2)
        harness.equal(#fixture.shown, 1, "first still visible at 2 s")
        fixture.controller:tick(3)
        harness.equal(#fixture.hidden, 1, "first hidden at its duration")
        harness.equal(#fixture.shown, 2, "second shown")
        harness.equal(fixture.shown[2].text, "Hello")
    end)

    suite:test("a toast without a sound plays none", function()
        local fixture = newFixture()
        fixture.controller:receive("note", 0, 0)
        harness.equal(#fixture.played, 0)
    end)

    suite:test("works without a sound callback", function()
        local renderer: ToastRenderer.ToastRenderer = {
            show = function(_self: ToastRenderer.ToastRenderer, _toast: ToastRenderer.Toast) end,
            hide = function(_self: ToastRenderer.ToastRenderer, _toastId: number) end,
        }
        local controller = ToastController.new({ config = config, renderer = renderer })
        harness.isTrue(controller:receive("win", 1, 0), "no crash")
    end)
end
