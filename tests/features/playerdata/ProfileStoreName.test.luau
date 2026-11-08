--!strict
local ProfileStoreName = require("../../../src/shared/features/playerdata/ProfileStoreName")
local harness = require("../../harness")

return function(suite: harness.Harness)
    suite:test("live servers use the live store, Studio its own", function()
        local data = { profileStore = "Live", studioProfileStore = "Dev" }
        harness.equal(ProfileStoreName.pick(false, data), "Live", "live")
        harness.equal(ProfileStoreName.pick(true, data), "Dev", "studio")
    end)
end
