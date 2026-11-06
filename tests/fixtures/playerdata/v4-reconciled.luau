--!strict
-- Golden fixture: a schema version 4 record as ProfileStore:Reconcile() leaves it: the v5 key
-- filled in (communityRewardClaimed) and a nested key from a newer template (timeRewards.playSeconds),
-- the shape an old reader must tolerate. Never edit it.
return {
    schemaVersion = 4,
    coins = 120,
    purchaseIds = { "receipt-a", "receipt-b" },
    sessionCount = 5,
    redeemedCodes = { WELCOME = 1 },
    timeRewards = { lastDay = 20000, streak = 3, playSeconds = 0 },
    settings = { musicVolume = 40 },
    communityRewardClaimed = false,
}
