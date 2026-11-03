--!strict
--[[
    Player data schema and its default. Pure: loads under Lune.
    Everything here must stay JSON-serializable (ProfileStore rule: no Instances,
    userdata, functions, mixed or sparse tables). Bump `CURRENT_SCHEMA_VERSION` and add a
    pure migration step in PlayerDataMigrations (D-30, ADR 0014) when a field changes shape;
    keep `PlayerDataMigrations.CURRENT_SCHEMA_VERSION` in sync (a test enforces it).
]]

export type PlayerData = {
    schemaVersion: number,
    coins: number,
    -- PurchaseId -> true, the idempotent receipt ledger (see Monetization.newTableLedger).
    purchases: { [string]: boolean },
    -- Sessions started by this player, counting the current one (see PlayerDataService.join).
    sessionCount: number,
}

local PlayerDataModule = {}

PlayerDataModule.CURRENT_SCHEMA_VERSION = 2

--- A fresh table on every call (profiles mutate their data in place).
function PlayerDataModule.default(): PlayerData
    return {
        schemaVersion = PlayerDataModule.CURRENT_SCHEMA_VERSION,
        coins = 0,
        purchases = {},
        sessionCount = 0,
    }
end

return PlayerDataModule
