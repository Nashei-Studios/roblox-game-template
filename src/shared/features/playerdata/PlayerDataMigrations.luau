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
    redeemedCodes: { [string]: number },
    timeRewards: { lastDay: number, streak: number },
    settings: { musicVolume: number?, sfxVolume: number? },
}

export type PlayerDataV5 = {
    schemaVersion: number,
    coins: number,
    purchaseIds: { string },
    sessionCount: number,
    redeemedCodes: { [string]: number },
    timeRewards: { lastDay: number, streak: number },
    settings: { musicVolume: number?, sfxVolume: number? },
    -- True once the one-time community join reward was granted (features/community-reward).
    communityRewardClaimed: boolean,
}

export type MigrationError =
    { kind: "future_version", found: number, supported: number }
    | { kind: "invalid_data", reason: string }

export type MigrationResult =
    { ok: true, value: PlayerDataV5 }
    | { ok: false, error: MigrationError }

type V4Result = { ok: true, value: PlayerDataV4 } | { ok: false, error: MigrationError }

type StepResult = { ok: true, value: unknown } | { ok: false, error: MigrationError }

local PlayerDataMigrations = {}

PlayerDataMigrations.CURRENT_SCHEMA_VERSION = 5

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

local function readPositiveRecord(raw: unknown, label: string): ({ [string]: number }?, string?)
    local record = asRecord(raw)
    if record == nil then
        return nil, `{label} must be a table`
    end
    local clone: { [string]: number } = {}
    for key, value in record do
        if type(key) ~= "string" or not isFiniteNumber(value) or (value :: number) < 0 then
            return nil, `{label} must map strings to non-negative numbers`
        end
        clone[key] = value :: number
    end
    return clone, nil
end

local function readV4(raw: unknown): V4Result
    local v3 = readV3(raw)
    if not v3.ok then
        return v3
    end
    local record = raw :: { [string]: unknown }
    local codes, codesProblem = readPositiveRecord(record.redeemedCodes, "redeemedCodes")
    if codes == nil then
        return invalid(codesProblem or "redeemedCodes is invalid")
    end
    -- Only the keys this version knows: a record reconciled with newer template keys (or written by
    -- a newer server) keeps them, and they are ignored here, never validated as old-shape values.
    local timeRecord = asRecord(record.timeRewards)
    if timeRecord == nil then
        return invalid("timeRewards must be a table")
    end
    local time: { lastDay: number, streak: number } = { lastDay = 0, streak = 0 }
    for _, field in { "lastDay", "streak" } do
        local value = timeRecord[field]
        if not isFiniteNumber(value) or (value :: number) < 0 then
            return invalid("timeRewards needs non-negative numbers for lastDay and streak")
        end
        (time :: { [string]: number })[field] = value :: number
    end
    local settingsRecord = asRecord(record.settings)
    if settingsRecord == nil then
        return invalid("settings must be a table")
    end
    for _, field in { "musicVolume", "sfxVolume" } do
        local volume = settingsRecord[field]
        if volume ~= nil and (not isFiniteNumber(volume) or (volume :: number) < 0) then
            return invalid("settings volumes must be non-negative numbers")
        end
        if volume ~= nil and (volume :: number) > 100 then
            return invalid("settings volumes must be percentages from 0 to 100")
        end
    end
    return {
        ok = true,
        value = {
            schemaVersion = 4,
            coins = v3.value.coins,
            purchaseIds = v3.value.purchaseIds,
            sessionCount = v3.value.sessionCount,
            redeemedCodes = codes,
            timeRewards = { lastDay = time.lastDay, streak = time.streak },
            settings = {
                musicVolume = settingsRecord.musicVolume :: number?,
                sfxVolume = settingsRecord.sfxVolume :: number?,
            },
        },
    }
end

local function readV5(raw: unknown): MigrationResult
    local v4 = readV4(raw)
    if not v4.ok then
        return v4
    end
    local claimed = (raw :: { [string]: unknown }).communityRewardClaimed
    if type(claimed) ~= "boolean" then
        return invalid("communityRewardClaimed must be a boolean")
    end
    return {
        ok = true,
        value = {
            schemaVersion = 5,
            coins = v4.value.coins,
            purchaseIds = v4.value.purchaseIds,
            sessionCount = v4.value.sessionCount,
            redeemedCodes = v4.value.redeemedCodes,
            timeRewards = v4.value.timeRewards,
            settings = v4.value.settings,
            communityRewardClaimed = claimed,
        },
    }
end

-- v4 had no community reward: nobody has claimed it yet.
local function v4ToV5(v4: PlayerDataV4): PlayerDataV5
    return {
        schemaVersion = 5,
        coins = v4.coins,
        purchaseIds = v4.purchaseIds,
        sessionCount = v4.sessionCount,
        redeemedCodes = v4.redeemedCodes,
        timeRewards = v4.timeRewards,
        settings = v4.settings,
        communityRewardClaimed = false,
    }
end

-- v3 had no engagement state: nothing redeemed, no streak, no saved volume choice.
local function v3ToV4(v3: PlayerDataV3): PlayerDataV4
    return {
        schemaVersion = 4,
        coins = v3.coins,
        purchaseIds = v3.purchaseIds,
        sessionCount = v3.sessionCount,
        redeemedCodes = {},
        timeRewards = { lastDay = 0, streak = 0 },
        settings = {},
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
    [4] = function(raw: unknown): StepResult
        local v4 = readV4(raw)
        if not v4.ok then
            return v4
        end
        return { ok = true, value = v4ToV5(v4.value) }
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
        local validated = readV5(raw)
        if validated.ok then
            return { ok = true, value = raw :: PlayerDataV5 } -- unchanged: same table
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
    return readV5(working)
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
        return { ok = true, value = result :: PlayerDataV5 }
    end
    return migrated
end

return PlayerDataMigrations
