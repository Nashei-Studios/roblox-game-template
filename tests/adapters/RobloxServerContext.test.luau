--!strict
local RobloxServerContext = require("../../src/server/adapters/RobloxServerContext")
local ServerContext = require("../../src/shared/ports/ServerContext")
local harness = require("../harness")

type FakePlayer = { UserId: number }
type FakeOptions = { tag: string }
type Listener = (
    player: FakePlayer,
    resultName: string,
    message: string,
    targetPlaceId: number,
    options: FakeOptions
) -> ()

local function newContext(teleportThrows: boolean)
    local listeners: { Listener } = {}
    local teleports: { string } = {}
    local logs: { string } = {}
    local disconnected = { value = false }
    local context = RobloxServerContext.new({
        game = { PrivateServerId = "srv-9", PrivateServerOwnerId = 4 },
        teleport = {
            ConnectInitFailed = function(_self: unknown, listener: Listener): () -> ()
                table.insert(listeners, listener)
                return function()
                    disconnected.value = true
                end
            end,
            TeleportAsync = function(
                _self: unknown,
                placeId: number,
                players: { FakePlayer },
                options: FakeOptions
            )
                if teleportThrows then
                    error("flooded")
                end
                table.insert(teleports, `{placeId}:{#players}:{options.tag}`)
            end,
            UserIdOf = function(_self: unknown, player: FakePlayer): number
                return player.UserId
            end,
        },
        log = function(message: string)
            table.insert(logs, message)
        end,
    })
    return context, listeners, teleports, logs, disconnected
end

return function(suite: harness.Harness)
    suite:test("exposes the private server id and owner", function()
        local context = newContext(false)
        harness.equal(context:privateServerId(), "srv-9", "id")
        harness.equal(context:ownerId(), 4, "owner")
    end)

    suite:test(
        "a failed teleport reaches the listener and retries with the same destination",
        function()
            local context, listeners, teleports = newContext(false)
            local received: { ServerContext.TeleportFailure } = {}
            context:onTeleportFailed(function(failure: ServerContext.TeleportFailure)
                table.insert(received, failure)
            end)
            listeners[1]({ UserId = 8 }, "Flooded", "slow down", 123, { tag = "opts" })
            harness.equal(received[1].userId, 8, "user")
            harness.equal(received[1].result, "Flooded", "result")
            received[1].retry()
            harness.equal(teleports[1], "123:1:opts", "same destination and options")
        end
    )

    suite:test("a retry that throws is logged, not swallowed", function()
        local context, listeners, _teleports, logs = newContext(true)
        local received: { ServerContext.TeleportFailure } = {}
        context:onTeleportFailed(function(failure: ServerContext.TeleportFailure)
            table.insert(received, failure)
        end)
        listeners[1]({ UserId = 8 }, "Failure", "x", 1, { tag = "o" })
        received[1].retry()
        harness.equal(#logs, 1, "logged")
        harness.isTrue(string.find(logs[1], "flooded", 1, true) ~= nil, "message kept")
    end)

    suite:test("the returned function disconnects the listener", function()
        local context, _listeners, _teleports, _logs, disconnected = newContext(false)
        local disconnect = context:onTeleportFailed(
            function(_failure: ServerContext.TeleportFailure) end
        )
        disconnect()
        harness.isTrue(disconnected.value, "disconnected")
    end)
end
