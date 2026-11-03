--!strict
local ConfigServiceFlags = require("../../src/server/adapters/ConfigServiceFlags")
local harness = require("../harness")

type FakeSnapshot = {
    snapshot: ConfigServiceFlags.ConfigSnapshotLike,
    refreshes: () -> number,
    fireUpdate: () -> (),
}

local function newSnapshot(values: { [string]: unknown }): FakeSnapshot
    local refreshes = 0
    local listeners: { () -> () } = {}
    local snapshot: ConfigServiceFlags.ConfigSnapshotLike = {
        UpdateAvailable = {
            Connect = function(_self: unknown, listener: () -> ()): unknown
                table.insert(listeners, listener)
                return nil
            end,
        },
        Refresh = function(_self: unknown)
            refreshes += 1
        end,
        GetValue = function(_self: unknown, name: string): unknown
            return values[name]
        end,
    }
    return {
        snapshot = snapshot,
        refreshes = function(): number
            return refreshes
        end,
        fireUpdate = function()
            for _, listener in listeners do
                listener()
            end
        end,
    }
end

local function serviceReturning(
    snapshot: ConfigServiceFlags.ConfigSnapshotLike
): ConfigServiceFlags.ConfigServiceLike
    return {
        GetConfigAsync = function(_self: unknown): ConfigServiceFlags.ConfigSnapshotLike
            return snapshot
        end,
    }
end

return function(suite: harness.Harness)
    suite:test("reads boolean, number and string values and ignores other types", function()
        local fake = newSnapshot({ flag = true, count = 4, label = "x", nested = { 1 } })
        local source = ConfigServiceFlags.new({ configService = serviceReturning(fake.snapshot) })
        harness.isTrue(source ~= nil, "source")
        if source ~= nil then
            harness.equal(source:get("flag"), true, "boolean")
            harness.equal(source:get("count"), 4, "number")
            harness.equal(source:get("label"), "x", "string")
            harness.isTrue(source:get("nested") == nil, "table ignored")
            harness.isTrue(source:get("missing") == nil, "missing")
        end
    end)

    suite:test("refreshes the snapshot when Roblox reports an update", function()
        local fake = newSnapshot({})
        ConfigServiceFlags.new({ configService = serviceReturning(fake.snapshot) })
        harness.equal(fake.refreshes(), 0, "before")
        fake.fireUpdate()
        harness.equal(fake.refreshes(), 1, "after")
    end)

    suite:test("returns nil and warns when Experience Configs cannot load", function()
        local warnings: { string } = {}
        local source = ConfigServiceFlags.new({
            configService = {
                GetConfigAsync = function(_self: unknown): ConfigServiceFlags.ConfigSnapshotLike
                    error("HTTP 500")
                end,
            },
            warn = function(message: string)
                table.insert(warnings, message)
            end,
        })
        harness.isTrue(source == nil, "no source")
        harness.equal(#warnings, 1, "warnings")
    end)
end
