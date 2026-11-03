--!strict
-- Golden fixture: the exact shape saved by schema version 4. Never edit it.
return {
    schemaVersion = 4,
    coins = 120,
    purchaseIds = { "receipt-a", "receipt-b" },
    sessionCount = 5,
    plots = {
        { cropId = "carrot", readyAt = 1700000060 },
        { cropId = "", readyAt = 0 },
    },
    seeds = { radish = 2, carrot = 0 },
    produce = { radish = 3 },
    totalHarvests = 7,
}
