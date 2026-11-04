--!strict
local PlayerData = require("../../../src/shared/features/playerdata/PlayerData")
local PlayerDataMigrations = require("../../../src/shared/features/playerdata/PlayerDataMigrations")
local harness = require("../../harness")
local v1Fixture = require("../../fixtures/playerdata/v1")
local v2Fixture = require("../../fixtures/playerdata/v2")
local v3Fixture = require("../../fixtures/playerdata/v3")
local v4Fixture = require("../../fixtures/playerdata/v4")
local v5Fixture = require("../../fixtures/playerdata/v5")

local function errorKind(result: PlayerDataMigrations.MigrationResult): string
    if result.ok then
        return "none"
    end
    return result.error.kind
end

local function migrateRaw(raw: unknown): string
    return errorKind(PlayerDataMigrations.migrate(raw))
end

return function(suite: harness.Harness)
    suite:test("current schema version is 5 and PlayerData agrees", function()
        harness.equal(PlayerDataMigrations.CURRENT_SCHEMA_VERSION, 5, "migrations")
        harness.equal(PlayerData.CURRENT_SCHEMA_VERSION, 5, "PlayerData")
    end)

    suite:test("step v2 -> v3 turns the ledger map into a sorted list", function()
        local result = PlayerDataMigrations.migrate(v2Fixture)
        harness.isTrue(result.ok, "migrates")
        if result.ok then
            harness.equal(result.value.schemaVersion, 5, "schemaVersion")
            harness.equal(#result.value.purchaseIds, 2, "ledger size")
            harness.equal(result.value.purchaseIds[1], "receipt-a", "first")
            harness.equal(result.value.purchaseIds[2], "receipt-b", "second")
            harness.equal(result.value.sessionCount, 5, "sessionCount kept")
            harness.equal(result.value.coins, 120, "coins kept")
        end
    end)

    suite:test("step v2 -> v3 drops ledger entries that were never processed", function()
        local result = PlayerDataMigrations.migrate({
            schemaVersion = 2,
            coins = 0,
            purchases = { kept = true, dropped = false },
            sessionCount = 1,
        })
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(#result.value.purchaseIds, 1, "ledger size")
            harness.equal(result.value.purchaseIds[1], "kept", "entry")
        end
    end)

    suite:test("full chain v1 -> v3 adds sessionCount 0 and converts the ledger", function()
        local result = PlayerDataMigrations.migrate(v1Fixture)
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(result.value.schemaVersion, 5, "schemaVersion")
            harness.equal(result.value.sessionCount, 0, "sessionCount")
            harness.equal(result.value.coins, 120, "coins")
            harness.equal(#result.value.purchaseIds, 2, "ledger size")
        end
    end)

    suite:test("step v3 -> v4 adds empty engagement state and keeps the rest", function()
        local result = PlayerDataMigrations.migrate(v3Fixture)
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(result.value.schemaVersion, 5, "schemaVersion")
            harness.equal(result.value.coins, 120, "coins kept")
            harness.equal(#result.value.purchaseIds, 2, "ledger kept")
            harness.isTrue(next(result.value.redeemedCodes) == nil, "no codes redeemed")
            harness.equal(result.value.timeRewards.lastDay, 0, "never claimed")
            harness.equal(result.value.timeRewards.streak, 0, "no streak")
            harness.isTrue(result.value.settings.musicVolume == nil, "no volume choice")
        end
    end)

    suite:test("step v4 -> v5 marks the community reward as not claimed", function()
        local result = PlayerDataMigrations.migrate(v4Fixture)
        harness.isTrue(result.ok and result.value.communityRewardClaimed == false, "not claimed")
        harness.isTrue(result.ok and result.value.coins == 120, "coins kept")
    end)

    suite:test("v5 with a non-boolean community flag is refused", function()
        local data = table.clone(v5Fixture) :: { [string]: unknown }
        data.communityRewardClaimed = "yes"
        harness.equal(migrateRaw(data), "invalid_data", "flag not a boolean")
    end)

    suite:test("v5 keeps its engagement state when it passes through", function()
        local result = PlayerDataMigrations.migrate(v5Fixture)
        harness.isTrue(result.ok and result.value.redeemedCodes.WELCOME == 1, "codes")
        harness.isTrue(result.ok and result.value.timeRewards.streak == 3, "streak")
        harness.isTrue(result.ok and result.value.settings.musicVolume == 40, "volume")
    end)

    suite:test("v4 with broken engagement state is refused", function()
        local function withField(field: string, value: unknown): string
            local data: { [string]: unknown } = {
                schemaVersion = 4,
                coins = 1,
                purchaseIds = {},
                sessionCount = 1,
                redeemedCodes = {},
                timeRewards = { lastDay = 0, streak = 0 },
                settings = {},
            }
            data[field] = value
            return migrateRaw(data)
        end
        harness.equal(withField("redeemedCodes", "x"), "invalid_data", "codes not a table")
        harness.equal(withField("redeemedCodes", { A = -1 }), "invalid_data", "negative use")
        harness.equal(withField("timeRewards", { lastDay = 1 }), "invalid_data", "no streak")
        harness.equal(withField("timeRewards", 5), "invalid_data", "not a table")
        harness.equal(withField("settings", { musicVolume = 101 }), "invalid_data", "volume > 100")
        harness.equal(withField("settings", "loud"), "invalid_data", "settings not a table")
    end)

    suite:test("migration does not mutate its input", function()
        local input = table.clone(v1Fixture)
        PlayerDataMigrations.migrate(input)
        harness.equal(input.schemaVersion, 1, "input untouched")
    end)

    suite:test("current version passes through unchanged (idempotent)", function()
        local result = PlayerDataMigrations.migrate(v5Fixture)
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(result.value.sessionCount, 5, "sessionCount")
            harness.isTrue((result.value :: unknown) == (v5Fixture :: unknown), "same table")
            local again = PlayerDataMigrations.migrate(result.value)
            harness.isTrue(again.ok and again.value.sessionCount == 5, "second pass")
        end
    end)

    suite:test("data without schemaVersion is treated as v1", function()
        local result = PlayerDataMigrations.migrate({ coins = 3, purchases = {} })
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(result.value.schemaVersion, 5, "schemaVersion")
            harness.equal(result.value.sessionCount, 0, "sessionCount")
            harness.equal(result.value.coins, 3, "coins")
        end
    end)

    suite:test("future versions are refused with a typed error, never downgraded", function()
        local result = PlayerDataMigrations.migrate({
            schemaVersion = 6,
            coins = 1,
            purchaseIds = {},
            sessionCount = 1,
        })
        harness.equal(errorKind(result), "future_version")
        if not result.ok and result.error.kind == "future_version" then
            harness.equal(result.error.found, 6, "found")
            harness.equal(result.error.supported, 5, "supported")
        end
    end)

    suite:test("invalid shapes return errors instead of throwing", function()
        harness.equal(migrateRaw(nil), "invalid_data", "nil")
        harness.equal(migrateRaw("x"), "invalid_data", "string")
        harness.equal(
            migrateRaw({ schemaVersion = "1", coins = 0, purchases = {} }),
            "invalid_data",
            "version type"
        )
        harness.equal(
            migrateRaw({ schemaVersion = 0, coins = 0, purchases = {} }),
            "invalid_data",
            "version zero"
        )
        harness.equal(
            migrateRaw({ schemaVersion = 1, coins = "9", purchases = {} }),
            "invalid_data",
            "coins type"
        )
        harness.equal(
            migrateRaw({ schemaVersion = 1, coins = 0, purchases = 5 }),
            "invalid_data",
            "purchases type"
        )
        harness.equal(
            migrateRaw({ schemaVersion = 1, coins = 0, purchases = { a = 1 } }),
            "invalid_data",
            "ledger value"
        )
        harness.equal(
            migrateRaw({ schemaVersion = 2, coins = 0, purchases = {}, sessionCount = "5" }),
            "invalid_data",
            "v2 sessionCount type"
        )
        harness.equal(
            migrateRaw({ schemaVersion = 2, coins = 0, purchases = {} }),
            "invalid_data",
            "v2 without sessionCount"
        )
        harness.equal(
            migrateRaw({ schemaVersion = 3, coins = 0, purchaseIds = {}, sessionCount = "1" }),
            "invalid_data",
            "v3 sessionCount type"
        )
        harness.equal(
            migrateRaw({
                schemaVersion = 3,
                coins = 0,
                purchaseIds = { a = true },
                sessionCount = 1,
            }),
            "invalid_data",
            "v3 ledger is not a sequence"
        )
        harness.equal(
            migrateRaw({ schemaVersion = 3, coins = 0, purchaseIds = { 7 }, sessionCount = 1 }),
            "invalid_data",
            "v3 ledger entry type"
        )
        harness.equal(
            migrateRaw({ schemaVersion = 3, coins = 0, sessionCount = 1 }),
            "invalid_data",
            "v3 without ledger"
        )
    end)

    suite:test("migrateInPlace keeps the live table identity (ProfileStore data)", function()
        local live: { [string]: unknown } = {
            schemaVersion = v1Fixture.schemaVersion,
            coins = v1Fixture.coins,
            purchases = v1Fixture.purchases,
            extra = "kept",
        }
        local result = PlayerDataMigrations.migrateInPlace(live)
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.isTrue((result.value :: unknown) == (live :: unknown), "same table")
            harness.equal(live.schemaVersion, 5, "live schemaVersion")
            harness.equal(live.sessionCount, 0, "live sessionCount")
            harness.equal(live.extra, "kept", "unknown field kept")
        end
    end)

    suite:test("migrateInPlace leaves the live table untouched on failure", function()
        local live: { [string]: unknown } = { schemaVersion = 9, coins = 1, purchases = {} }
        local result = PlayerDataMigrations.migrateInPlace(live)
        harness.isFalse(result.ok, "refused")
        harness.equal(live.schemaVersion, 9, "not downgraded")
    end)

    suite:test("PlayerData.default is already current and passes unchanged", function()
        local fresh = PlayerData.default()
        local result = PlayerDataMigrations.migrate(fresh)
        harness.isTrue(result.ok and (result.value :: unknown) == (fresh :: unknown), "unchanged")
    end)
end
