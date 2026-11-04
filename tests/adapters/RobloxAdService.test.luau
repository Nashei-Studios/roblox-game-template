--!strict
local RobloxAdService = require("../../src/server/adapters/RobloxAdService")
local harness = require("../harness")

type FakePlayer = { UserId: number }
type FakeReward = { productId: number }
type Call = { player: FakePlayer, reward: FakeReward, placementId: number? }

local function newGateway(resultName: string, throws: boolean, online: boolean)
    local player: FakePlayer = { UserId = 3 }
    local calls: { Call } = {}
    local gateway = RobloxAdService.new({
        adService = {
            CreateAdRewardFromDevProductId = function(
                _self: unknown,
                productId: number
            ): FakeReward
                return { productId = productId }
            end,
            ShowRewardedVideoAdAsync = function(
                _self: unknown,
                who: FakePlayer,
                reward: FakeReward,
                placementId: number?
            ): string
                if throws then
                    error("quota")
                end
                table.insert(calls, { player = who, reward = reward, placementId = placementId })
                return resultName
            end,
        },
        players = {
            GetPlayerByUserId = function(_self: unknown, userId: number): FakePlayer?
                if online and userId == 3 then
                    return player
                end
                return nil
            end,
        },
    })
    return gateway, calls
end

return function(suite: harness.Harness)
    suite:test("maps every ShowAdResult name to an outcome", function()
        local names: { [string]: string } = {
            ShowCompleted = "completed",
            AdNotReady = "notReady",
            AdAlreadyShowing = "alreadyShowing",
            ShowInterrupted = "interrupted",
            InsufficientMemory = "insufficientMemory",
            InternalError = "failed",
            SomethingNew = "failed",
        }
        for resultName, expected in names do
            local gateway = newGateway(resultName, false, true)
            local result = gateway:show(3, { placementId = nil, rewardProductId = 8 })
            harness.isTrue(result.ok and result.value == expected, resultName)
        end
    end)

    suite:test("passes the reward product and placement to the engine", function()
        local gateway, calls = newGateway("ShowCompleted", false, true)
        gateway:show(3, { placementId = 42, rewardProductId = 8 })
        harness.equal(calls[1].reward.productId, 8, "reward product")
        harness.equal(calls[1].placementId, 42, "placement")
    end)

    suite:test("a missing player and an engine error are typed failures", function()
        local gone = newGateway("ShowCompleted", false, false)
        harness.isFalse(gone:show(3, { placementId = nil, rewardProductId = 8 }).ok, "player gone")
        local broken = newGateway("ShowCompleted", true, true)
        local result = broken:show(3, { placementId = nil, rewardProductId = 8 })
        harness.isFalse(result.ok, "engine error")
        if not result.ok then
            harness.isTrue(string.find(result.error.message, "quota", 1, true) ~= nil, "message")
        end
    end)
end
