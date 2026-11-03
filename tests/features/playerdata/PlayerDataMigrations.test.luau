--!strict
local PlayerDataMigrations = require("../../../src/shared/features/playerdata/PlayerDataMigrations")
local PlayerData = require("../../../src/shared/features/playerdata/PlayerData")
local harness = require("../../harness")
local v1Fixture = require("../../fixtures/playerdata/v1")
local v2Fixture = require("../../fixtures/playerdata/v2")

local function errorKind(result: PlayerDataMigrations.MigrationResult): string
    if result.ok then
        return "none"
    end
    return result.error.kind
end

return function(suite: harness.Harness)
    suite:test("step 1 -> 2 adds sessionCount 0 and keeps every other field", function()
        local result = PlayerDataMigrations.migrate(v1Fixture)
        harness.isTrue(result.ok, "migrates")
        if result.ok then
            harness.equal(result.value.schemaVersion, 2, "schemaVersion")
            harness.equal(result.value.sessionCount, 0, "sessionCount")
            harness.equal(result.value.coins, 120, "coins")
            harness.isTrue(result.value.purchases["receipt-a"] == true, "ledger kept")
            harness.isTrue(result.value.purchases["receipt-b"] == true, "ledger kept")
        end
    end)

    suite:test("migration does not mutate its input", function()
        local input = table.clone(v1Fixture)
        PlayerDataMigrations.migrate(input)
        harness.equal(input.schemaVersion, 1, "input untouched")
    end)

    suite:test("current version passes through unchanged (idempotent)", function()
        local result = PlayerDataMigrations.migrate(v2Fixture)
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(result.value.sessionCount, 5, "sessionCount")
            harness.equal(result.value.coins, 120, "coins")
            local again = PlayerDataMigrations.migrate(result.value)
            harness.isTrue(again.ok and again.value.sessionCount == 5, "second pass")
        end
    end)

    suite:test("full chain from v1 equals the v2 shape", function()
        local result = PlayerDataMigrations.migrate(v1Fixture)
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(result.value.schemaVersion, PlayerDataMigrations.CURRENT_SCHEMA_VERSION)
            harness.equal(PlayerDataMigrations.CURRENT_SCHEMA_VERSION, 2, "current version")
        end
    end)

    suite:test("data without schemaVersion is treated as v1", function()
        local result = PlayerDataMigrations.migrate({ coins = 3, purchases = {} })
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(result.value.schemaVersion, 2, "schemaVersion")
            harness.equal(result.value.sessionCount, 0, "sessionCount")
            harness.equal(result.value.coins, 3, "coins")
        end
    end)

    suite:test("future versions are refused with a typed error, never downgraded", function()
        local result = PlayerDataMigrations.migrate({
            schemaVersion = 3,
            coins = 1,
            purchases = {},
            sessionCount = 1,
        })
        harness.equal(errorKind(result), "future_version")
        if not result.ok and result.error.kind == "future_version" then
            harness.equal(result.error.found, 3, "found")
            harness.equal(result.error.supported, 2, "supported")
        end
    end)

    suite:test("invalid shapes return errors instead of throwing", function()
        harness.equal(errorKind(PlayerDataMigrations.migrate(nil)), "invalid_data", "nil")
        harness.equal(errorKind(PlayerDataMigrations.migrate("x")), "invalid_data", "string")
        harness.equal(
            errorKind(
                PlayerDataMigrations.migrate({ schemaVersion = "1", coins = 0, purchases = {} })
            ),
            "invalid_data",
            "version type"
        )
        harness.equal(
            errorKind(
                PlayerDataMigrations.migrate({ schemaVersion = 0, coins = 0, purchases = {} })
            ),
            "invalid_data",
            "version zero"
        )
        harness.equal(
            errorKind(
                PlayerDataMigrations.migrate({ schemaVersion = 1, coins = "9", purchases = {} })
            ),
            "invalid_data",
            "coins type"
        )
        harness.equal(
            errorKind(PlayerDataMigrations.migrate({ schemaVersion = 1, coins = 0, purchases = 5 })),
            "invalid_data",
            "purchases type"
        )
        harness.equal(
            errorKind(
                PlayerDataMigrations.migrate({ schemaVersion = 1, coins = 0, purchases = { a = 1 } })
            ),
            "invalid_data",
            "ledger value"
        )
        harness.equal(
            errorKind(PlayerDataMigrations.migrate({
                schemaVersion = 2,
                coins = 0,
                purchases = {},
                sessionCount = "5",
            })),
            "invalid_data",
            "sessionCount type"
        )
        harness.equal(
            errorKind(PlayerDataMigrations.migrate({
                schemaVersion = 2,
                coins = 0,
                purchases = {},
            })),
            "invalid_data",
            "v2 without sessionCount"
        )
    end)

    suite:test("migrateInPlace keeps the live table identity (ProfileStore data)", function()
        local live: { [string]: unknown } = {
            schemaVersion = v1Fixture.schemaVersion,
            coins = v1Fixture.coins,
            purchases = v1Fixture.purchases,
        }
        local result = PlayerDataMigrations.migrateInPlace(live)
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.isTrue(result.value == (live :: unknown), "same table")
            harness.equal(live.schemaVersion, 2, "live schemaVersion")
            harness.equal(live.sessionCount, 0, "live sessionCount")
        end
    end)

    suite:test("migrateInPlace leaves the live table untouched on failure", function()
        local live: { [string]: unknown } = { schemaVersion = 9, coins = 1, purchases = {} }
        local result = PlayerDataMigrations.migrateInPlace(live)
        harness.isFalse(result.ok, "refused")
        harness.equal(live.schemaVersion, 9, "not downgraded")
    end)

    suite:test(
        "PlayerData.default is already at the current schema and passes unchanged",
        function()
            harness.equal(
                PlayerData.CURRENT_SCHEMA_VERSION,
                PlayerDataMigrations.CURRENT_SCHEMA_VERSION,
                "versions in sync"
            )
            local fresh = PlayerData.default()
            local result = PlayerDataMigrations.migrate(fresh)
            harness.isTrue(
                result.ok and (result.value :: unknown) == (fresh :: unknown),
                "unchanged"
            )
        end
    )
end
