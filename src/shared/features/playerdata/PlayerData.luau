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
    -- Receipt ledger: the most recent PurchaseIds, oldest first (see Monetization.newListLedger).
    purchaseIds: { string },
    -- Sessions started by this player, counting the current one (see PlayerDataService.join).
    sessionCount: number,
    -- Promo codes redeemed: normalized code -> times redeemed (features/codes).
    redeemedCodes: { [string]: number },
    -- Daily streak: last claimed UTC day (0 = never) and the streak length (features/timerewards).
    timeRewards: { lastDay: number, streak: number },
    -- Volume choices in percent; nil means "use Config.sound.defaultVolumes" (features/sound).
    settings: { musicVolume: number?, sfxVolume: number? },
    -- True once the one-time community join reward was granted (features/community-reward).
    communityRewardClaimed: boolean,
}

local PlayerDataModule = {}

PlayerDataModule.CURRENT_SCHEMA_VERSION = 5

--- A fresh table on every call (profiles mutate their data in place).
function PlayerDataModule.default(): PlayerData
    return {
        schemaVersion = PlayerDataModule.CURRENT_SCHEMA_VERSION,
        coins = 0,
        purchaseIds = {},
        sessionCount = 0,
        redeemedCodes = {},
        timeRewards = { lastDay = 0, streak = 0 },
        settings = {},
        communityRewardClaimed = false,
    }
end

return PlayerDataModule
