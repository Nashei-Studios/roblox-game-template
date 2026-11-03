--!strict
-- Receipt delivery end to end without the engine: ProductGrants + the bounded ledger +
-- PlayerDataService + the in-memory repository with injectable save failures (ADR 0016).
local InMemoryProfileRepository =
    require("../../../src/shared/features/playerdata/InMemoryProfileRepository")
local Monetization = require("../../../src/shared/features/monetization/Monetization")
local PlayerData = require("../../../src/shared/features/playerdata/PlayerData")
local PlayerDataMigrations = require("../../../src/shared/features/playerdata/PlayerDataMigrations")
local PlayerDataService = require("../../../src/shared/features/playerdata/PlayerDataService")
local ProductGrants = require("../../../src/shared/features/monetization/ProductGrants")
local harness = require("../../harness")

local LEDGER_SIZE = 3
local TIMEOUT_SECONDS = 30
local USER_KEY = "1"

local function clone(data: PlayerData.PlayerData): PlayerData.PlayerData
    return {
        schemaVersion = data.schemaVersion,
        coins = data.coins,
        purchaseIds = table.clone(data.purchaseIds),
        sessionCount = data.sessionCount,
        plots = table.clone(data.plots),
        seeds = table.clone(data.seeds),
        produce = table.clone(data.produce),
        totalHarvests = data.totalHarvests,
    }
end

type Env = {
    service: PlayerDataService.PlayerDataService<
        PlayerData.PlayerData,
        PlayerDataMigrations.MigrationError
    >,
    repository: InMemoryProfileRepository.ProfileRepository<PlayerData.PlayerData>,
    setOutage: (failing: boolean) -> (),
    -- Mirrors Main.server's wiring of ledgers, grant and confirmSaved.
    process: (purchaseId: string) -> Monetization.ReceiptDecision,
}

local function newEnv(): Env
    local outage = false
    local repository = InMemoryProfileRepository.new({
        default = PlayerData.default,
        clone = clone,
        failSaves = function(): boolean
            return outage
        end,
    })
    local service = PlayerDataService.new({
        repository = repository,
        onSessionLost = function() end,
        migrate = PlayerDataMigrations.migrateInPlace,
        startSession = function(data: PlayerData.PlayerData): number
            data.sessionCount += 1
            return data.sessionCount
        end,
    })
    local grants = ProductGrants.new({ Coins100 = { kind = "coins", amount = 100 } })

    local function process(purchaseId: string): Monetization.ReceiptDecision
        local data = service:get(USER_KEY)
        if data == nil then
            return "failed"
        end
        local ledger = Monetization.newListLedger(data.purchaseIds, LEDGER_SIZE)
        local receipt: Monetization.ReceiptInfo =
            { playerId = 1, purchaseId = purchaseId, productId = 10 }
        return Monetization.processReceipt(ledger, receipt, function(): boolean
            return grants:apply(data, "Coins100").ok
        end, function(id: string): boolean
            return service:confirmSaved(USER_KEY, function(saved: PlayerData.PlayerData): boolean
                return table.find(saved.purchaseIds, id) ~= nil
            end, TIMEOUT_SECONDS).ok
        end)
    end

    return {
        service = service,
        repository = repository,
        setOutage = function(failing: boolean)
            outage = failing
        end,
        process = process,
    }
end

local function coins(env: Env): number
    local data = env.service:get(USER_KEY)
    return if data ~= nil then data.coins else -1
end

return function(suite: harness.Harness)
    suite:test("grant plus confirmed save is granted and the coins are stored", function()
        local env = newEnv()
        env.service:join(USER_KEY)
        harness.equal(env.process("p1"), "granted", "decision")
        harness.equal(coins(env), 100, "coins")
        env.service:leave(USER_KEY)
        local rejoined = env.service:join(USER_KEY)
        harness.isTrue(rejoined.ok and rejoined.value.data.coins == 100, "persisted")
    end)

    suite:test("a save that is not confirmed is unconfirmed, never granted", function()
        local env = newEnv()
        env.service:join(USER_KEY)
        env.setOutage(true)
        harness.equal(env.process("p1"), "unconfirmed", "decision")
    end)

    suite:test("the retry after an unconfirmed save does not deliver twice", function()
        local env = newEnv()
        env.service:join(USER_KEY)
        env.setOutage(true)
        env.process("p1")
        harness.equal(coins(env), 100, "delivered once in memory")
        env.setOutage(false)
        -- Roblox retries the same PurchaseId: the entry is still in memory, so only the save is awaited.
        harness.equal(env.process("p1"), "alreadyGranted", "retry decision")
        harness.equal(coins(env), 100, "still delivered once")
        env.service:leave(USER_KEY)
        local rejoined = env.service:join(USER_KEY)
        harness.isTrue(rejoined.ok and rejoined.value.data.coins == 100, "stored once")
    end)

    suite:test("the same PurchaseId twice delivers once", function()
        local env = newEnv()
        env.service:join(USER_KEY)
        harness.equal(env.process("p1"), "granted", "first")
        harness.equal(env.process("p1"), "alreadyGranted", "second")
        harness.equal(coins(env), 100, "coins")
    end)

    suite:test("a player whose data is not loaded is not processed", function()
        local env = newEnv()
        harness.equal(env.process("p1"), "failed", "decision")
    end)

    suite:test("a session that ends before the save lands is not confirmed", function()
        local env = newEnv()
        env.service:join(USER_KEY)
        env.setOutage(true)
        env.process("p1")
        -- The service forgets the handle on leave, so the retry finds no data (NotProcessedYet).
        env.service:leave(USER_KEY)
        harness.equal(env.process("p1"), "failed", "after leave")
    end)

    suite:test("the ledger keeps only the last N PurchaseIds and drops the oldest", function()
        local env = newEnv()
        env.service:join(USER_KEY)
        for _, id in { "p1", "p2", "p3", "p4" } do
            env.process(id)
        end
        local data = env.service:get(USER_KEY)
        harness.isTrue(data ~= nil, "data")
        if data ~= nil then
            harness.equal(#data.purchaseIds, LEDGER_SIZE, "bounded")
            harness.isTrue(table.find(data.purchaseIds, "p1") == nil, "oldest dropped")
            harness.equal(data.purchaseIds[LEDGER_SIZE], "p4", "newest last")
        end
    end)
end
