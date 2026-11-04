--!strict
local RobloxMarketplaceSubscriptions =
    require("../../src/server/adapters/RobloxMarketplaceSubscriptions")
local harness = require("../harness")

type FakePlayer = { UserId: number }
type Listener = (player: FakePlayer, subscriptionId: string) -> ()

local function newPort(throws: boolean, online: boolean)
    local player: FakePlayer = { UserId = 5 }
    local fired: { Listener } = {}
    local disconnected = { value = false }
    local port = RobloxMarketplaceSubscriptions.new({
        marketplace = {
            GetUserSubscriptionStatusAsync = function(
                _self: unknown,
                _player: FakePlayer,
                subscriptionId: string
            )
                if throws then
                    error("http 500")
                end
                return { IsSubscribed = subscriptionId == "EXP-1" }
            end,
            UserOwnsGamePassAsync = function(
                _self: unknown,
                _userId: number,
                passId: number
            ): boolean
                if throws then
                    error("http 500")
                end
                return passId == 9
            end,
        },
        players = {
            GetPlayerByUserId = function(_self: unknown, userId: number): FakePlayer?
                if online and userId == 5 then
                    return player
                end
                return nil
            end,
            ConnectStatusChanged = function(_self: unknown, listener: Listener): () -> ()
                table.insert(fired, listener)
                return function()
                    disconnected.value = true
                end
            end,
            UserIdOf = function(_self: unknown, who: FakePlayer): number
                return who.UserId
            end,
        },
    })
    return port, fired, player, disconnected
end

return function(suite: harness.Harness)
    suite:test("statusOf maps IsSubscribed", function()
        local port = newPort(false, true)
        local yes = port:statusOf(5, "EXP-1")
        local no = port:statusOf(5, "EXP-2")
        harness.isTrue(yes.ok and yes.value.isSubscribed, "subscribed")
        harness.isTrue(no.ok and not no.value.isSubscribed, "not subscribed")
    end)

    suite:test("statusOf fails typed when the player is gone", function()
        local port = newPort(false, false)
        harness.isFalse(port:statusOf(5, "EXP-1").ok, "failed")
    end)

    suite:test("an engine error keeps its message in the typed failure", function()
        local port = newPort(true, true)
        local result = port:statusOf(5, "EXP-1")
        harness.isFalse(result.ok, "failed")
        if not result.ok then
            harness.isTrue(string.find(result.error.message, "http 500", 1, true) ~= nil, "message")
        end
        harness.isFalse(port:ownsPass(5, 9).ok, "pass failed")
    end)

    suite:test("ownsPass reports ownership", function()
        local port = newPort(false, true)
        local owned = port:ownsPass(5, 9)
        local missing = port:ownsPass(5, 10)
        harness.isTrue(owned.ok and owned.value, "owned")
        harness.isTrue(missing.ok and not missing.value, "missing")
    end)

    suite:test("onChanged forwards user ids and returns the disconnect", function()
        local port, fired, player, disconnected = newPort(false, true)
        local seen: { string } = {}
        local disconnect = port:onChanged(function(userId: number, subscriptionId: string)
            table.insert(seen, `{userId}:{subscriptionId}`)
        end)
        fired[1](player, "EXP-1")
        harness.equal(seen[1], "5:EXP-1", "forwarded")
        disconnect()
        harness.isTrue(disconnected.value, "disconnected")
    end)
end
