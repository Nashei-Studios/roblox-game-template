--!strict
local PlayerData = require("../../../src/shared/features/playerdata/PlayerData")
local PlayerDataMigrations = require("../../../src/shared/features/playerdata/PlayerDataMigrations")
local harness = require("../../harness")
local v1Fixture = require("../../fixtures/playerdata/v1")
local v2Fixture = require("../../fixtures/playerdata/v2")
local v3Fixture = require("../../fixtures/playerdata/v3")
local v4Fixture = require("../../fixtures/playerdata/v4")
local GreenhouseData = require("../../../src/shared/features/greenhouse/GreenhouseData")

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
    suite:test("current schema version is 4 and PlayerData agrees", function()
        harness.equal(PlayerDataMigrations.CURRENT_SCHEMA_VERSION, 4, "migrations")
        harness.equal(PlayerData.CURRENT_SCHEMA_VERSION, 4, "PlayerData")
    end)

    suite:test("step v2 -> v3 turns the ledger map into a sorted list", function()
        local result = PlayerDataMigrations.migrate(v2Fixture)
        harness.isTrue(result.ok, "migrates")
        if result.ok then
            harness.equal(result.value.schemaVersion, 4, "schemaVersion")
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

    suite:test("full chain v1 -> v4 adds sessionCount 0 and converts the ledger", function()
        local result = PlayerDataMigrations.migrate(v1Fixture)
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(result.value.schemaVersion, 4, "schemaVersion")
            harness.equal(result.value.sessionCount, 0, "sessionCount")
            harness.equal(result.value.coins, 120, "coins")
            harness.equal(#result.value.purchaseIds, 2, "ledger size")
        end
    end)

    suite:test("migration does not mutate its input", function()
        local input = table.clone(v1Fixture)
        PlayerDataMigrations.migrate(input)
        harness.equal(input.schemaVersion, 1, "input untouched")
    end)

    suite:test("current version passes through unchanged (idempotent)", function()
        local result = PlayerDataMigrations.migrate(v4Fixture)
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(result.value.sessionCount, 5, "sessionCount")
            harness.isTrue((result.value :: unknown) == (v4Fixture :: unknown), "same table")
            local again = PlayerDataMigrations.migrate(result.value)
            harness.isTrue(again.ok and again.value.sessionCount == 5, "second pass")
        end
    end)

    suite:test("step v3 -> v4 adds one empty plot, the starting seed and no harvests", function()
        local result = PlayerDataMigrations.migrate(v3Fixture)
        harness.isTrue(result.ok, "migrates")
        if result.ok then
            harness.equal(result.value.schemaVersion, 4, "schemaVersion")
            harness.equal(#result.value.plots, GreenhouseData.START_PLOTS, "plots")
            harness.equal(result.value.plots[1].cropId, "", "empty plot")
            harness.equal(result.value.plots[1].readyAt, 0, "no timer")
            harness.equal(
                result.value.seeds[GreenhouseData.START_SEED_CROP],
                GreenhouseData.START_SEED_COUNT,
                "starting seed"
            )
            harness.equal(result.value.totalHarvests, 0, "harvests")
            harness.equal(result.value.coins, 120, "coins kept")
            harness.equal(result.value.sessionCount, 5, "sessionCount kept")
            harness.equal(#result.value.purchaseIds, 2, "ledger kept")
        end
    end)

    suite:test("the migrated greenhouse fields equal a brand new player's default", function()
        local migrated = PlayerDataMigrations.migrate(v3Fixture)
        local fresh = PlayerData.default()
        harness.isTrue(migrated.ok, "migrates")
        if migrated.ok then
            harness.equal(#migrated.value.plots, #fresh.plots, "plots")
            harness.equal(migrated.value.plots[1].cropId, fresh.plots[1].cropId, "plot crop")
            harness.equal(migrated.value.seeds.radish, fresh.seeds.radish, "seed")
            harness.equal(migrated.value.totalHarvests, fresh.totalHarvests, "harvests")
        end
    end)

    suite:test("full chain v1 -> v4 ends with the greenhouse fields", function()
        local result = PlayerDataMigrations.migrate(v1Fixture)
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(#result.value.plots, 1, "plots")
            harness.equal(result.value.totalHarvests, 0, "harvests")
        end
    end)

    suite:test("v4 fields are validated: plots, stock maps and the harvest count", function()
        local function v4(
            plots: unknown,
            seeds: unknown,
            produce: unknown,
            harvests: unknown
        ): unknown
            return {
                schemaVersion = 4,
                coins = 0,
                purchaseIds = {},
                sessionCount = 1,
                plots = plots,
                seeds = seeds,
                produce = produce,
                totalHarvests = harvests,
            }
        end
        local okPlots = { { cropId = "", readyAt = 0 } }
        harness.equal(migrateRaw(v4(okPlots, { radish = 1 }, {}, 0)), "none", "valid")
        harness.equal(migrateRaw(v4({}, {}, {}, 0)), "invalid_data", "needs at least one plot")
        harness.equal(migrateRaw(v4("x", {}, {}, 0)), "invalid_data", "plots type")
        harness.equal(
            migrateRaw(v4({ { cropId = 1, readyAt = 0 } }, {}, {}, 0)),
            "invalid_data",
            "cropId type"
        )
        harness.equal(
            migrateRaw(v4({ { cropId = "", readyAt = -1 } }, {}, {}, 0)),
            "invalid_data",
            "negative readyAt"
        )
        harness.equal(
            migrateRaw(v4({ { cropId = "", readyAt = 0 / 0 } }, {}, {}, 0)),
            "invalid_data",
            "NaN readyAt"
        )
        harness.equal(
            migrateRaw(v4(okPlots, { radish = -1 }, {}, 0)),
            "invalid_data",
            "negative seeds"
        )
        harness.equal(
            migrateRaw(v4(okPlots, { radish = 1.5 }, {}, 0)),
            "invalid_data",
            "fractional seeds"
        )
        harness.equal(
            migrateRaw(v4(okPlots, {}, { radish = "1" }, 0)),
            "invalid_data",
            "produce type"
        )
        harness.equal(migrateRaw(v4(okPlots, nil, {}, 0)), "invalid_data", "missing seeds")
        harness.equal(migrateRaw(v4(okPlots, {}, {}, -1)), "invalid_data", "negative harvests")
        harness.equal(migrateRaw(v4(okPlots, {}, {}, nil)), "invalid_data", "missing harvests")
    end)

    suite:test("data without schemaVersion is treated as v1", function()
        local result = PlayerDataMigrations.migrate({ coins = 3, purchases = {} })
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(result.value.schemaVersion, 4, "schemaVersion")
            harness.equal(result.value.sessionCount, 0, "sessionCount")
            harness.equal(result.value.coins, 3, "coins")
        end
    end)

    suite:test("future versions are refused with a typed error, never downgraded", function()
        local result = PlayerDataMigrations.migrate({
            schemaVersion = 5,
            coins = 1,
            purchaseIds = {},
            sessionCount = 1,
        })
        harness.equal(errorKind(result), "future_version")
        if not result.ok and result.error.kind == "future_version" then
            harness.equal(result.error.found, 5, "found")
            harness.equal(result.error.supported, 4, "supported")
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
            harness.equal(live.schemaVersion, 4, "live schemaVersion")
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
