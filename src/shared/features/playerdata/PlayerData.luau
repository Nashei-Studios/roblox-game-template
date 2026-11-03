--!strict
--[[
    Player data schema and its default. Pure: loads under Lune.
    Everything here must stay JSON-serializable (ProfileStore rule: no Instances,
    userdata, functions, mixed or sparse tables). Bump `CURRENT_SCHEMA_VERSION` and add a
    pure migration step in PlayerDataMigrations (D-30, ADR 0014) when a field changes shape;
    keep `PlayerDataMigrations.CURRENT_SCHEMA_VERSION` in sync (a test enforces it).
]]

local Greenhouse = require("../greenhouse/Greenhouse")

export type Plot = Greenhouse.Plot

export type PlayerData = {
    schemaVersion: number,
    coins: number,
    -- Receipt ledger: the most recent PurchaseIds, oldest first (see Monetization.newListLedger).
    purchaseIds: { string },
    -- Sessions started by this player, counting the current one (see PlayerDataService.join).
    sessionCount: number,
    -- Greenhouse (ADR 0020): plots with their server-time readyAt, seed and produce stock per
    -- crop id, and the lifetime harvest count (a returning player skips the tutorial).
    plots: { Plot },
    seeds: { [string]: number },
    produce: { [string]: number },
    totalHarvests: number,
}

local PlayerDataModule = {}

PlayerDataModule.CURRENT_SCHEMA_VERSION = 4

--- A fresh table on every call (profiles mutate their data in place).
function PlayerDataModule.default(): PlayerData
    local greenhouse = Greenhouse.newState()
    return {
        schemaVersion = PlayerDataModule.CURRENT_SCHEMA_VERSION,
        coins = 0,
        purchaseIds = {},
        sessionCount = 0,
        plots = greenhouse.plots,
        seeds = greenhouse.seeds,
        produce = greenhouse.produce,
        totalHarvests = greenhouse.totalHarvests,
    }
end

return PlayerDataModule
