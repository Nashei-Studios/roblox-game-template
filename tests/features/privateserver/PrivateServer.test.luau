--!strict
local PrivateServer = require("../../../src/shared/features/privateserver/PrivateServer")
local ServerContext = require("../../../src/shared/ports/ServerContext")
local harness = require("../../harness")

type Fixture = {
    server: PrivateServer.PrivateServer,
    applied: { string },
    delays: { number },
    retries: { number },
    setAllowed: (allowed: boolean) -> (),
}

local function newFixture(enabled: boolean, serverId: string, ownerId: number): Fixture
    local applied: { string } = {}
    local delays: { number } = {}
    local retries: { number } = {}
    local state = { allowed = true }
    local context: ServerContext.ServerContext = {
        privateServerId = function(_self)
            return serverId
        end,
        ownerId = function(_self)
            return ownerId
        end,
        onTeleportFailed = function(_self, _listener)
            return function() end
        end,
    }
    local server = PrivateServer.new({
        config = {
            enabled = enabled,
            expectedMonthlyPrice = 100,
            teleportRetries = 2,
            teleportRetryDelaySeconds = 3,
            settings = { { name = "maxPlayers", min = 2, max = 12, default = 8 } },
        },
        context = context,
        allow = function(_userId: number): boolean
            return state.allowed
        end,
        delay = function(seconds: number, action: () -> ())
            table.insert(delays, seconds)
            action()
        end,
        onSettingChanged = function(setting: string, value: number)
            table.insert(applied, `{setting}={value}`)
        end,
    })
    return {
        server = server,
        applied = applied,
        delays = delays,
        retries = retries,
        setAllowed = function(allowed: boolean)
            state.allowed = allowed
        end,
    }
end

local function failure(fixture: Fixture, result: string): ServerContext.TeleportFailure
    return {
        userId = 7,
        result = result,
        message = "x",
        retry = function()
            table.insert(fixture.retries, 1)
        end,
    }
end

local function reasonOf(result: PrivateServer.SettingResult): string
    if result.ok then
        return "ok"
    end
    return result.reason
end

return function(suite: harness.Harness)
    suite:test("roles: owner, guest and public server", function()
        local privateFixture = newFixture(true, "srv-1", 10)
        harness.equal(privateFixture.server:roleOf(10), "owner", "owner joins")
        harness.equal(privateFixture.server:roleOf(11), "guest", "guest joins")
        harness.isTrue(privateFixture.server:isPrivateServer(), "private")
        local publicFixture = newFixture(true, "", 0)
        harness.equal(publicFixture.server:roleOf(10), "public", "public server")
        harness.isFalse(publicFixture.server:isPrivateServer(), "not private")
    end)

    suite:test("a reserved server with no owner has no owner role", function()
        local fixture = newFixture(true, "srv-2", 0)
        harness.equal(fixture.server:roleOf(0), "guest", "id 0 is never the owner")
    end)

    suite:test("the owner changes a setting inside its bounds", function()
        local fixture = newFixture(true, "srv-1", 10)
        harness.equal(fixture.server:settingValue("maxPlayers"), 8, "default")
        harness.equal(reasonOf(fixture.server:handleSetting(10, "maxPlayers", 12)), "ok", "applied")
        harness.equal(fixture.server:settingValue("maxPlayers"), 12, "stored")
        harness.equal(fixture.applied[1], "maxPlayers=12", "callback")
    end)

    suite:test("guests, bad names and out-of-range values change nothing", function()
        local fixture = newFixture(true, "srv-1", 10)
        harness.equal(
            reasonOf(fixture.server:handleSetting(11, "maxPlayers", 4)),
            "not_owner",
            "guest"
        )
        harness.equal(
            reasonOf(fixture.server:handleSetting(10, "godMode", 1)),
            "not_allowed",
            "name"
        )
        harness.equal(
            reasonOf(fixture.server:handleSetting(10, "maxPlayers", 99)),
            "out_of_range",
            "range"
        )
        harness.equal(
            reasonOf(fixture.server:handleSetting(10, "maxPlayers", 2.5)),
            "not_an_integer",
            "int"
        )
        harness.equal(#fixture.applied, 0, "nothing applied")
        harness.equal(fixture.server:settingValue("maxPlayers"), 8, "unchanged")
    end)

    suite:test("disabled, rate-limited and public-server requests are rejected", function()
        local off = newFixture(false, "srv-1", 10)
        harness.equal(
            reasonOf(off.server:handleSetting(10, "maxPlayers", 4)),
            "disabled",
            "disabled"
        )
        local limited = newFixture(true, "srv-1", 10)
        limited.setAllowed(false)
        harness.equal(
            reasonOf(limited.server:handleSetting(10, "maxPlayers", 4)),
            "rate_limited",
            "limited"
        )
        local public = newFixture(true, "", 0)
        harness.equal(
            reasonOf(public.server:handleSetting(10, "maxPlayers", 4)),
            "not_private_server",
            "public"
        )
    end)

    suite:test("TeleportInitFailed retries transient failures a bounded number of times", function()
        local fixture = newFixture(true, "srv-1", 10)
        harness.equal(
            fixture.server:handleTeleportFailed(failure(fixture, "Flooded")),
            "retrying",
            "1"
        )
        harness.equal(
            fixture.server:handleTeleportFailed(failure(fixture, "Failure")),
            "retrying",
            "2"
        )
        harness.equal(
            fixture.server:handleTeleportFailed(failure(fixture, "Failure")),
            "gave_up",
            "3"
        )
        harness.equal(#fixture.retries, 2, "retries")
        harness.equal(fixture.delays[1], 3, "delay from Config")
    end)

    suite:test("a non-transient teleport failure is not retried", function()
        local fixture = newFixture(true, "srv-1", 10)
        for _, result in
            { "GameNotFound", "GameEnded", "Unauthorized", "GameFull", "IsTeleporting" }
        do
            harness.equal(
                fixture.server:handleTeleportFailed(failure(fixture, result)),
                "not_retryable",
                result
            )
        end
        harness.equal(#fixture.retries, 0, "no retries")
    end)
end
