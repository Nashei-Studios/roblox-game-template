--!strict
-- Golden fixture: the exact shape saved by schema version 1. Never edit it; add a new
-- version file when the schema changes (docs/adr/0014-pure-migration-chain.md).
return {
    schemaVersion = 1,
    coins = 120,
    purchases = { ["receipt-a"] = true, ["receipt-b"] = true },
}
