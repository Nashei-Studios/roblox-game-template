--!strict
local FriendBoostLabel = require("../../../src/shared/features/social/FriendBoostLabel")
local harness = require("../../harness")

return function(suite: harness.Harness)
    suite:test("friend boost label: hidden at zero or below", function()
        harness.equal(FriendBoostLabel.text(0), nil, "zero")
        harness.equal(FriendBoostLabel.text(0.4), nil, "rounds to zero")
        harness.equal(FriendBoostLabel.text(-3), nil, "negative")
    end)
    suite:test("friend boost label: shows the rounded percent", function()
        harness.equal(FriendBoostLabel.text(10), "Friend +10%", "ten")
        harness.equal(FriendBoostLabel.text(12.6), "Friend +13%", "rounded")
    end)
end
