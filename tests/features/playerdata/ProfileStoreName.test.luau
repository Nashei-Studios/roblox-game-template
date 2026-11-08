--!strict
local Config = require("../src/shared/Config")
local ProfileStoreName = require("../src/shared/ProfileStoreName")
local harness = require("./harness")

return function(suite: harness.Harness)
    suite:test("live servers use the live store, Studio its own", function()
        local data = { profileStore = "Live", studioProfileStore = "Dev" }
        harness.equal(ProfileStoreName.pick(false, data), "Live", "live")
        harness.equal(ProfileStoreName.pick(true, data), "Dev", "studio")
    end)

    suite:test("the shipped config keeps the live name and separates Studio", function()
        harness.equal(ProfileStoreName.pick(false, Config.data), "PlayerData", "live unchanged")
        harness.isTrue(
            ProfileStoreName.pick(true, Config.data) ~= ProfileStoreName.pick(false, Config.data),
            "studio differs"
        )
    end)
end
