--!strict
local BenefitReconciler = require("../../../src/shared/features/subscriptions/BenefitReconciler")
local Config = require("../../../src/shared/Config")
local SubscriptionPort = require("../../../src/shared/ports/SubscriptionPort")
local harness = require("../../harness")

type Fixture = {
    reconciler: BenefitReconciler.BenefitReconciler,
    applied: { string },
    subscribed: { [string]: boolean },
    ownedPasses: { [number]: boolean },
    failing: { lookups: boolean },
    statusCalls: { number },
}

local ENTRY: BenefitReconciler.Entry = {
    name = "VipPlus",
    subscriptionId = "EXP-1",
    benefits = { "vipLounge" },
    legacyPassId = nil,
}

local function newFixture(entry: BenefitReconciler.Entry): Fixture
    local applied: { string } = {}
    local subscribed: { [string]: boolean } = {}
    local ownedPasses: { [number]: boolean } = {}
    local failing = { lookups = false }
    local statusCalls: { number } = {}
    local port: SubscriptionPort.SubscriptionPort = {
        statusOf = function(_self, userId: number, subscriptionId: string)
            table.insert(statusCalls, userId)
            if failing.lookups then
                return { ok = false, error = { kind = "lookup_failed", message = "boom" } }
            end
            return { ok = true, value = { isSubscribed = subscribed[subscriptionId] == true } }
        end,
        ownsPass = function(_self, _userId: number, passId: number)
            if failing.lookups then
                return { ok = false, error = { kind = "lookup_failed", message = "pass boom" } }
            end
            return { ok = true, value = ownedPasses[passId] == true }
        end,
        onChanged = function(_self, _listener)
            return function() end
        end,
    }
    local reconciler = BenefitReconciler.new({
        entries = { entry },
        port = port,
        apply = function(userId: number, applying: BenefitReconciler.Entry, active: boolean)
            table.insert(applied, `{userId}:{applying.name}:{tostring(active)}`)
        end,
    })
    return {
        reconciler = reconciler,
        applied = applied,
        subscribed = subscribed,
        ownedPasses = ownedPasses,
        failing = failing,
        statusCalls = statusCalls,
    }
end

local LEGACY_ENTRY: BenefitReconciler.Entry = {
    name = "VipPlus",
    subscriptionId = "EXP-1",
    benefits = { "vipLounge" },
    legacyPassId = 77,
}

return function(suite: harness.Harness)
    suite:test("a subscriber gets the benefit on join", function()
        local fixture = newFixture(ENTRY)
        fixture.subscribed["EXP-1"] = true
        harness.equal(#fixture.reconciler:reconcile(1), 0, "failures")
        harness.equal(fixture.applied[1], "1:VipPlus:true", "granted")
        harness.isTrue(fixture.reconciler:isActive(1, "VipPlus"), "active")
    end)

    suite:test(
        "a non-subscriber is revoked on the first read, never trusted from saved data",
        function()
            local fixture = newFixture(ENTRY)
            fixture.reconciler:reconcile(1)
            harness.equal(fixture.applied[1], "1:VipPlus:false", "revoke applied once")
            harness.isFalse(fixture.reconciler:isActive(1, "VipPlus"), "inactive")
        end
    )

    suite:test("the change event grants when the status turns on", function()
        local fixture = newFixture(ENTRY)
        fixture.reconciler:reconcile(1)
        fixture.subscribed["EXP-1"] = true
        fixture.reconciler:onChanged(1, "EXP-1")
        harness.equal(fixture.applied[#fixture.applied], "1:VipPlus:true", "granted")
    end)

    suite:test("revocation: a lapsed subscription removes the benefit", function()
        local fixture = newFixture(ENTRY)
        fixture.subscribed["EXP-1"] = true
        fixture.reconciler:reconcile(1)
        fixture.subscribed["EXP-1"] = false
        fixture.reconciler:onChanged(1, "EXP-1")
        harness.equal(fixture.applied[#fixture.applied], "1:VipPlus:false", "revoked")
        harness.isFalse(fixture.reconciler:isActive(1, "VipPlus"), "inactive")
    end)

    suite:test("a Store tab purchase is found by the next poll without any event", function()
        local fixture = newFixture(ENTRY)
        fixture.reconciler:reconcile(1)
        fixture.subscribed["EXP-1"] = true
        fixture.reconciler:reconcile(1)
        harness.isTrue(fixture.reconciler:isActive(1, "VipPlus"), "active after poll")
    end)

    suite:test("an unchanged state is not applied twice", function()
        local fixture = newFixture(ENTRY)
        fixture.subscribed["EXP-1"] = true
        fixture.reconciler:reconcile(1)
        fixture.reconciler:reconcile(1)
        harness.equal(#fixture.applied, 1, "apply calls")
    end)

    suite:test("a failed lookup keeps the previous state and reports the failure", function()
        local fixture = newFixture(ENTRY)
        fixture.subscribed["EXP-1"] = true
        fixture.reconciler:reconcile(1)
        fixture.failing.lookups = true
        local failures = fixture.reconciler:reconcile(1)
        harness.equal(#failures, 1, "failures")
        harness.equal(failures[1].message, "boom", "message")
        harness.isTrue(fixture.reconciler:isActive(1, "VipPlus"), "still active")
        harness.equal(#fixture.applied, 1, "no revoke on failure")
    end)

    suite:test("a change for another subscription id is ignored", function()
        local fixture = newFixture(ENTRY)
        fixture.reconciler:onChanged(1, "EXP-OTHER")
        harness.equal(#fixture.statusCalls, 0, "no lookups")
    end)

    suite:test("a legacy pass owner keeps the benefit without a subscription lookup", function()
        local fixture = newFixture(LEGACY_ENTRY)
        fixture.ownedPasses[77] = true
        fixture.reconciler:reconcile(1)
        harness.isTrue(fixture.reconciler:isActive(1, "VipPlus"), "active via pass")
        harness.equal(#fixture.statusCalls, 0, "subscription not read")
    end)

    suite:test("a pass lookup failure is reported", function()
        local fixture = newFixture(LEGACY_ENTRY)
        fixture.failing.lookups = true
        local failures = fixture.reconciler:reconcile(1)
        harness.equal(failures[1].message, "pass boom", "message")
    end)

    suite:test("forget drops the player state", function()
        local fixture = newFixture(ENTRY)
        fixture.subscribed["EXP-1"] = true
        fixture.reconciler:reconcile(1)
        fixture.reconciler:forget(1)
        harness.isFalse(fixture.reconciler:isActive(1, "VipPlus"), "forgotten")
    end)

    suite:test(
        "entriesFromConfig skips entries without an id and resolves the legacy pass",
        function()
            local withPass: Config.SubscriptionConfig = {
                name = "A",
                subscriptionId = "EXP-9",
                benefits = { "x" },
                replacesPassName = "VIP",
            }
            local withoutId: Config.SubscriptionConfig = {
                name = "B",
                subscriptionId = nil,
                benefits = { "y" },
                replacesPassName = nil,
            }
            local config: Config.GameConfig = {
                gameName = "T",
                sessionLockTimeoutSeconds = 60,
                autosaveIntervalSeconds = 30,
                purchaseLedgerSize = 50,
                saveConfirmTimeoutSeconds = 30,
                codes = Config.default.codes,
                timeRewards = Config.default.timeRewards,
                notifications = Config.default.notifications,
                sound = Config.default.sound,
                gamePasses = { { name = "VIP", id = 55 } },
                developerProducts = {},
                subscriptions = { withPass, withoutId },
            }
            local entries = BenefitReconciler.entriesFromConfig(config)
            harness.equal(#entries, 1, "entries")
            harness.equal(entries[1].legacyPassId, 55, "legacy pass id")
        end
    )
end
