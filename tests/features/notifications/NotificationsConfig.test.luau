--!strict
local NotificationsConfig =
    require("../../../src/shared/features/notifications/NotificationsConfig")
local harness = require("../../harness")

local function base(): NotificationsConfig.NotificationsConfig
    local kinds: { [string]: NotificationsConfig.KindConfig } = {}
    for _, name in NotificationsConfig.REQUIRED_KINDS do
        kinds[name] = { text = "x", style = "info", durationSeconds = 2 }
    end
    return { maxQueue = 4, maxVisible = 2, dedupeSeconds = 1, maxWaitSeconds = 10, kinds = kinds }
end

return function(suite: harness.Harness)
    suite:test("a complete config has no problems", function()
        harness.equal(#NotificationsConfig.validate(base(), {}), 0)
    end)

    suite:test("each missing required kind is reported", function()
        local config = base()
        config.kinds["code_invalid"] = nil
        config.kinds["daily_claimed"] = nil
        harness.equal(#NotificationsConfig.validate(config, {}), 2)
    end)

    suite:test("bad limits are each reported", function()
        local config = base()
        config.maxQueue = 0
        config.maxVisible = 1.5
        config.dedupeSeconds = -1
        config.maxWaitSeconds = 0
        harness.equal(#NotificationsConfig.validate(config, {}), 4)
    end)

    suite:test("bad text, style, duration and sound are reported", function()
        local config = base()
        config.kinds["code_invalid"] = {
            text = "",
            style = ("loud" :: unknown) :: NotificationsConfig.ToastStyle,
            durationSeconds = 0,
            sound = "ghost",
        }
        harness.equal(#NotificationsConfig.validate(config, {}), 4)
    end)

    suite:test("a declared sound is accepted", function()
        local config = base()
        config.kinds["code_invalid"].sound = "ding"
        harness.equal(#NotificationsConfig.validate(config, { ding = true }), 0)
    end)
end
