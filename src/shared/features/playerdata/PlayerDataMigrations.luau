--!strict
--[[
    Pure schema-migration chain for player data (D-30, ADR 0014). Loads under Lune.

    Rules:
    - One step per version (`steps[n]` upgrades vN to vN+1); the chain runs from the stored
      version to CURRENT_SCHEMA_VERSION.
    - Data already at the current version is validated and returned as is (idempotent).
    - Data from a FUTURE version (written by a newer server) is refused, never downgraded.
    - Data without `schemaVersion` is treated as v1 (the first shipped schema).
    - Invalid shapes return a typed error; nothing here throws.

    Types are local structural aliases (this file cannot `require` PlayerData by instance path
    and still load under Lune). `PlayerDataV2` must stay structurally identical to
    `PlayerData.PlayerData`; the compiler checks it where the two meet in `Main.server`.
]]

export type PlayerDataV1 = {
    schemaVersion: number,
    coins: number,
    purchases: { [string]: boolean },
}

export type PlayerDataV2 = {
    schemaVersion: number,
    coins: number,
    purchases: { [string]: boolean },
    sessionCount: number,
}

export type PlayerDataV3 = {
    schemaVersion: number,
    coins: number,
    -- Oldest first, bounded by Config.purchaseLedgerSize when recording (see Monetization).
    purchaseIds: { string },
    sessionCount: number,
}

export type PlayerDataV4 = {
    schemaVersion: number,
    coins: number,
    purchaseIds: { string },
    sessionCount: number,
    -- Key sprint: last stage cleared (0 = none) and multiplier cap.
    highestStage: number,
    multiplierCap: number,
}

export type MigrationError =
    { kind: "future_version", found: number, supported: number }
    | { kind: "invalid_data", reason: string }

export type MigrationResult =
    { ok: true, value: PlayerDataV4 }
    | { ok: false, error: MigrationError }

type StepResult = { ok: true, value: unknown } | { ok: false, error: MigrationError }

local PlayerDataMigrations = {}

PlayerDataMigrations.CURRENT_SCHEMA_VERSION = 4

-- Multiplier cap given to data written before v4. A test keeps it equal to
-- KeySprintRules.BASE_CAP (this file stays free of game modules).
local DEFAULT_MULTIPLIER_CAP = 5

local function invalid(reason: string): { ok: false, error: MigrationError }
    return { ok = false, error = { kind = "invalid_data", reason = reason } }
end

local function isFiniteNumber(value: unknown): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function asRecord(raw: unknown): { [string]: unknown }?
    if type(raw) ~= "table" then
        return nil
    end
    return raw :: { [string]: unknown }
end

-- Validates the fields shared by every version and returns clones of them.
local function readCommon(
    record: { [string]: unknown },
    schemaVersion: number
): { ok: true, value: PlayerDataV1 } | { ok: false, error: MigrationError }
    local coins = record.coins
    if not isFiniteNumber(coins) then
        return invalid("coins must be a finite number")
    end
    local purchases = asRecord(record.purchases)
    if purchases == nil then
        return invalid("purchases must be a table")
    end
    local ledger: { [string]: boolean } = {}
    for purchaseId, processed in purchases do
        if type(purchaseId) ~= "string" or type(processed) ~= "boolean" then
            return invalid("purchases must map string ids to booleans")
        end
        ledger[purchaseId] = processed
    end
    return {
        ok = true,
        value = { schemaVersion = schemaVersion, coins = coins :: number, purchases = ledger },
    }
end

local function readVersion(record: { [string]: unknown }): { ok: true, value: number } | {
    ok: false,
    error: MigrationError,
}
    local version = record.schemaVersion
    if version == nil then
        return { ok = true, value = 1 }
    end
    if not isFiniteNumber(version) or (version :: number) < 1 or (version :: number) % 1 ~= 0 then
        return invalid("schemaVersion must be a positive integer")
    end
    return { ok = true, value = version :: number }
end

local function readV1(raw: unknown): { ok: true, value: PlayerDataV1 } | {
    ok: false,
    error: MigrationError,
}
    local record = asRecord(raw)
    if record == nil then
        return invalid("player data must be a table")
    end
    return readCommon(record, 1)
end

local function readV2(raw: unknown): { ok: true, value: PlayerDataV2 } | {
    ok: false,
    error: MigrationError,
}
    local record = asRecord(raw)
    if record == nil then
        return invalid("player data must be a table")
    end
    local common = readCommon(record, 2)
    if not common.ok then
        return common
    end
    local sessionCount = record.sessionCount
    if not isFiniteNumber(sessionCount) then
        return invalid("sessionCount must be a finite number")
    end
    return {
        ok = true,
        value = {
            schemaVersion = 2,
            coins = common.value.coins,
            purchases = common.value.purchases,
            sessionCount = sessionCount :: number,
        },
    }
end

local function readV3(raw: unknown): { ok: true, value: PlayerDataV3 } | {
    ok: false,
    error: MigrationError,
}
    local record = asRecord(raw)
    if record == nil then
        return invalid("player data must be a table")
    end
    if not isFiniteNumber(record.coins) then
        return invalid("coins must be a finite number")
    end
    if not isFiniteNumber(record.sessionCount) then
        return invalid("sessionCount must be a finite number")
    end
    local rawIds = record.purchaseIds
    if type(rawIds) ~= "table" then
        return invalid("purchaseIds must be a table")
    end
    local sequence = rawIds :: { unknown }
    local entries = 0
    for _ in rawIds :: { [unknown]: unknown } do
        entries += 1
    end
    local ids: { string } = {}
    for index = 1, entries do
        local id = sequence[index]
        if type(id) ~= "string" then
            return invalid("purchaseIds must be a sequence of strings")
        end
        ids[index] = id
    end
    return {
        ok = true,
        value = {
            schemaVersion = 3,
            coins = record.coins :: number,
            purchaseIds = ids,
            sessionCount = record.sessionCount :: number,
        },
    }
end

local function isNonNegativeInteger(value: unknown): boolean
    return isFiniteNumber(value) and (value :: number) >= 0 and (value :: number) % 1 == 0
end

local function readV4(raw: unknown): MigrationResult
    local base = readV3(raw)
    if not base.ok then
        return base
    end
    local record = raw :: { [string]: unknown }
    if not isNonNegativeInteger(record.highestStage) then
        return invalid("highestStage must be a non-negative integer")
    end
    if not isNonNegativeInteger(record.multiplierCap) or record.multiplierCap == 0 then
        return invalid("multiplierCap must be a positive integer")
    end
    return {
        ok = true,
        value = {
            schemaVersion = 4,
            coins = base.value.coins,
            purchaseIds = base.value.purchaseIds,
            sessionCount = base.value.sessionCount,
            highestStage = record.highestStage :: number,
            multiplierCap = record.multiplierCap :: number,
        },
    }
end

local function v1ToV2(v1: PlayerDataV1): PlayerDataV2
    return {
        schemaVersion = 2,
        coins = v1.coins,
        purchases = v1.purchases,
        sessionCount = 0,
    }
end

-- The v2 ledger was an unordered map, so the true purchase order is lost; sorting by id keeps
-- the result deterministic. Entries marked false were never processed and are dropped.
local function v2ToV3(v2: PlayerDataV2): PlayerDataV3
    local ids: { string } = {}
    for purchaseId, processed in v2.purchases do
        if processed then
            table.insert(ids, purchaseId)
        end
    end
    table.sort(ids)
    return {
        schemaVersion = 3,
        coins = v2.coins,
        purchaseIds = ids,
        sessionCount = v2.sessionCount,
    }
end

local function v3ToV4(v3: PlayerDataV3): PlayerDataV4
    return {
        schemaVersion = 4,
        coins = v3.coins,
        purchaseIds = v3.purchaseIds,
        sessionCount = v3.sessionCount,
        highestStage = 0,
        multiplierCap = DEFAULT_MULTIPLIER_CAP,
    }
end

-- steps[n] validates a vN table and upgrades it to vN+1. Add a new entry per schema change.
local steps: { [number]: (raw: unknown) -> StepResult } = {
    [1] = function(raw: unknown): StepResult
        local v1 = readV1(raw)
        if not v1.ok then
            return v1
        end
        return { ok = true, value = v1ToV2(v1.value) }
    end,
    [2] = function(raw: unknown): StepResult
        local v2 = readV2(raw)
        if not v2.ok then
            return v2
        end
        return { ok = true, value = v2ToV3(v2.value) }
    end,
    [3] = function(raw: unknown): StepResult
        local v3 = readV3(raw)
        if not v3.ok then
            return v3
        end
        return { ok = true, value = v3ToV4(v3.value) }
    end,
}

--- Upgrades `raw` to the current schema. Never mutates `raw`; never throws.
function PlayerDataMigrations.migrate(raw: unknown): MigrationResult
    local record = asRecord(raw)
    if record == nil then
        return invalid("player data must be a table")
    end
    local version = readVersion(record)
    if not version.ok then
        return version
    end
    local current = PlayerDataMigrations.CURRENT_SCHEMA_VERSION
    if version.value > current then
        return {
            ok = false,
            error = { kind = "future_version", found = version.value, supported = current },
        }
    end
    if version.value == current then
        local validated = readV4(raw)
        if validated.ok then
            return { ok = true, value = raw :: PlayerDataV4 } -- unchanged: same table
        end
        return validated
    end

    local working: unknown = raw
    for step = version.value, current - 1 do
        local run = steps[step]
        if run == nil then
            return invalid(`no migration step from version {step}`)
        end
        local stepped = run(working)
        if not stepped.ok then
            return stepped
        end
        working = stepped.value
    end
    return readV4(working)
end

--- Like `migrate`, but writes the result into `raw` (the live ProfileStore table, whose
--- identity must survive) and returns that same table. Fields outside the schema are kept.
--- `raw` is left untouched when the migration fails.
function PlayerDataMigrations.migrateInPlace(raw: unknown): MigrationResult
    local migrated = PlayerDataMigrations.migrate(raw)
    if not migrated.ok then
        return migrated
    end
    local live = asRecord(raw)
    if live ~= nil and (migrated.value :: unknown) ~= raw then
        local source: unknown = migrated.value
        for key, value in source :: { [string]: unknown } do
            live[key] = value
        end
        local result: unknown = live
        return { ok = true, value = result :: PlayerDataV4 }
    end
    return migrated
end

return PlayerDataMigrations
