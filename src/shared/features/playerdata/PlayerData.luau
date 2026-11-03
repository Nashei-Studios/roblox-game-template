--!strict
--[[
    Player data schema and its default. Pure: loads under Lune.
    Everything here must stay JSON-serializable (ProfileStore rule: no Instances,
    userdata, functions, mixed or sparse tables). Bump `CURRENT_SCHEMA_VERSION` and add a
    pure migration (D-30) when a field changes shape.
]]

export type PlayerData = {
    schemaVersion: number,
    coins: number,
    -- PurchaseId -> true, the idempotent receipt ledger (see Monetization.newTableLedger).
    purchases: { [string]: boolean },
}

local PlayerDataModule = {}

PlayerDataModule.CURRENT_SCHEMA_VERSION = 1

--- A fresh table on every call (profiles mutate their data in place).
function PlayerDataModule.default(): PlayerData
    return {
        schemaVersion = PlayerDataModule.CURRENT_SCHEMA_VERSION,
        coins = 0,
        purchases = {},
    }
end

return PlayerDataModule
