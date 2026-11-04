--!strict
local RobloxPlusSubscription = require("../../src/server/adapters/RobloxPlusSubscription")
local harness = require("../harness")

type FakePlayer = { UserId: number, plus: boolean }

local function newPort(online: boolean, throws: boolean)
    local player: FakePlayer = { UserId = 6, plus = true }
    local prompted: { number } = {}
    local listeners: { (player: FakePlayer) -> () } = {}
    local disconnected = { value = false }
    local port = RobloxPlusSubscription.new({
        players = {
            GetPlayerByUserId = function(_self: unknown, userId: number): FakePlayer?
                if online and userId == 6 then
                    return player
                end
                return nil
            end,
            HasPlus = function(_self: unknown, who: FakePlayer): boolean
                return who.plus
            end,
            ConnectPlusChanged = function(
                _self: unknown,
                listener: (player: FakePlayer) -> ()
            ): () -> ()
                table.insert(listeners, listener)
                return function()
                    disconnected.value = true
                end
            end,
            UserIdOf = function(_self: unknown, who: FakePlayer): number
                return who.UserId
            end,
        },
        marketplace = {
            PromptRobloxSubscriptionPurchase = function(_self: unknown, who: FakePlayer)
                if throws then
                    error("not allowed")
                end
                table.insert(prompted, who.UserId)
            end,
        },
    })
    return port, player, prompted, listeners, disconnected
end

return function(suite: harness.Harness)
    suite:test("hasPlus reads the server property and is nil for an absent player", function()
        local port = newPort(true, false)
        harness.equal(port:hasPlus(6), true, "plus")
        local absent = newPort(false, false)
        harness.isTrue(absent:hasPlus(6) == nil, "unknown")
    end)

    suite:test("prompt opens the engine prompt for the player", function()
        local port, _player, prompted = newPort(true, false)
        harness.isTrue(port:prompt(6).ok, "ok")
        harness.equal(prompted[1], 6, "prompted")
    end)

    suite:test("prompt failures are typed and keep the engine message", function()
        local gone = newPort(false, false)
        harness.isFalse(gone:prompt(6).ok, "player gone")
        local broken = newPort(true, true)
        local result = broken:prompt(6)
        harness.isFalse(result.ok, "engine error")
        if not result.ok then
            harness.isTrue(
                string.find(result.error.message, "not allowed", 1, true) ~= nil,
                "message"
            )
        end
    end)

    suite:test("onPlusChanged reports the user id and the current status", function()
        local port, player, _prompted, listeners, disconnected = newPort(true, false)
        local seen: { string } = {}
        local disconnect = port:onPlusChanged(function(userId: number, hasPlus: boolean)
            table.insert(seen, `{userId}:{tostring(hasPlus)}`)
        end)
        listeners[1](player)
        harness.equal(seen[1], "6:true", "forwarded")
        disconnect()
        harness.isTrue(disconnected.value, "disconnected")
    end)
end
