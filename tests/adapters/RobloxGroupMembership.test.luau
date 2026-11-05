--!strict
local RobloxGroupMembership = require("../../src/server/adapters/RobloxGroupMembership")
local harness = require("../harness")

type FakePlayer = { UserId: number }

local function playersOf(
    online: { [number]: FakePlayer }
): RobloxGroupMembership.PlayersLike<FakePlayer>
    return {
        GetPlayerByUserId = function(_self: unknown, userId: number): FakePlayer?
            return online[userId]
        end,
    }
end

return function(suite: harness.Harness)
    suite:test("a member and a non-member are reported from the engine answer", function()
        local answers: { [number]: boolean } = { [7] = true, [8] = false }
        local checker = RobloxGroupMembership.new({
            players = playersOf({ [7] = { UserId = 7 }, [8] = { UserId = 8 } }),
            isInGroup = function(player: FakePlayer, _communityId: number): boolean
                return answers[player.UserId]
            end,
        })
        local member = checker:isMember(7, 1)
        harness.isTrue(member.ok and member.value, "member")
        local outsider = checker:isMember(8, 1)
        harness.isTrue(outsider.ok and not outsider.value, "non-member")
    end)

    suite:test("a player who left and a failing engine call are typed errors", function()
        local checker = RobloxGroupMembership.new({
            players = playersOf({ [7] = { UserId = 7 } }),
            isInGroup = function(_player: FakePlayer, _communityId: number): boolean
                error("http 429")
            end,
        })
        local gone = checker:isMember(9, 1)
        harness.isTrue(not gone.ok and gone.error.message == "player_gone", "player gone")
        local failed = checker:isMember(7, 1)
        harness.isTrue(not failed.ok and failed.error.kind == "check_failed", "engine error")
        harness.isTrue(
            not failed.ok and string.find(failed.error.message, "429") ~= nil,
            "message kept"
        )
    end)
end
