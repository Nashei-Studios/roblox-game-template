--!strict
local ProductGrants = require("../../../src/shared/features/monetization/ProductGrants")
local QuestRequests = require("../../../src/shared/features/quests/QuestRequests")
local Quests = require("../../../src/shared/features/quests/Quests")
local QuestsConfig = require("../../../src/shared/features/quests/QuestsConfig")
local harness = require("../../harness")

local DAY = 86400

local function quest(id: string, counter: string, target: number, amount: number)
    return {
        id = id,
        title = id,
        counter = counter,
        target = target,
        reward = { kind = "coins" :: "coins", amount = amount },
    }
end

local function makeConfig(): QuestsConfig.QuestsConfig
    return {
        enabled = true,
        maxIncrementPerEvent = 100,
        daily = {
            count = 2,
            pool = {
                quest("d1", "hit", 10, 5),
                quest("d2", "sell", 3, 6),
                quest("d3", "hit", 20, 7),
                quest("d4", "open", 1, 8),
            },
        },
        weekly = { count = 1, pool = { quest("w1", "hit", 50, 100), quest("w2", "sell", 9, 120) } },
        chains = {
            {
                id = "intro",
                steps = { quest("c1", "hit", 2, 10), quest("c2", "sell", 1, 20) },
            },
        },
    }
end

type Rig = {
    quests: Quests.Quests,
    profile: Quests.Profile,
    setNow: (value: number) -> (),
    setSaved: (value: boolean) -> (),
}

local function rig(config: QuestsConfig.QuestsConfig?): Rig
    local cfg = config or makeConfig()
    local now = 10 * DAY + 100
    local saved = true
    local profile: Quests.Profile = { coins = 0 }
    local quests = Quests.new({
        config = cfg,
        now = function()
            return now
        end,
        profileFor = function(userId: number)
            if userId == 1 then
                return profile
            end
            return nil
        end,
        grants = ProductGrants.new(Quests.grantTable(cfg)),
        confirmSaved = function()
            return saved
        end,
    })
    return {
        quests = quests,
        profile = profile,
        setNow = function(value: number)
            now = value
        end,
        setSaved = function(value: boolean)
            saved = value
        end,
    }
end

local function activeIds(r: Rig, group: string): { string }
    local ids: { string } = {}
    for _, view in r.quests:view(1) do
        if view.group == group then
            table.insert(ids, view.id)
        end
    end
    return ids
end

local function errorOf(result: Quests.ClaimResult): string
    if result.ok then
        return "ok"
    end
    return result.error
end

return function(suite: harness.Harness)
    suite:test("validate accepts the sample config", function()
        harness.equal(#QuestsConfig.validate(makeConfig()), 0)
    end)

    suite:test("validate reports duplicates, bad targets and oversized counts", function()
        local config = makeConfig()
        config.daily.pool[2].id = "d1"
        config.daily.pool[1].target = 0
        config.weekly.count = 5
        config.maxIncrementPerEvent = 0
        config.chains[1].steps = {}
        harness.equal(#QuestsConfig.validate(config), 5)
    end)

    suite:test("pickIndices is deterministic, distinct and in range", function()
        local first = Quests.pickIndices(6, 3, 77)
        local second = Quests.pickIndices(6, 3, 77)
        harness.equal(#first, 3)
        for position, value in first do
            harness.equal(value, second[position])
            harness.isTrue(value >= 1 and value <= 6, "in range")
        end
        harness.isTrue(first[1] ~= first[2] and first[2] ~= first[3], "distinct")
    end)

    suite:test("a view lists the daily picks, one weekly and the first chain step", function()
        local r = rig()
        harness.equal(#activeIds(r, "daily"), 2)
        harness.equal(#activeIds(r, "weekly"), 1)
        harness.equal(activeIds(r, "chain")[1], "c1")
    end)

    suite:test("record adds progress to matching active quests and caps at the target", function()
        local r = rig()
        local result = r.quests:record(1, "hit", 5)
        harness.isTrue(result.ok, "recorded")
        r.quests:record(1, "hit", 100)
        for _, view in r.quests:view(1) do
            if view.id == "c1" then
                harness.equal(view.progress, 2)
                harness.equal(view.status, "complete")
            end
        end
    end)

    suite:test("record refuses bad counters and amounts", function()
        local r = rig()
        local function reason(result: Quests.RecordResult): string
            if result.ok then
                return "ok"
            end
            return result.error
        end
        harness.equal(reason(r.quests:record(1, "", 1)), "invalid_counter")
        harness.equal(reason(r.quests:record(1, "hit", 0)), "invalid_amount")
        harness.equal(reason(r.quests:record(1, "hit", -3)), "invalid_amount")
        harness.equal(reason(r.quests:record(1, "hit", 0 / 0)), "invalid_amount")
        harness.equal(reason(r.quests:record(1, "hit", 101)), "invalid_amount")
        harness.equal(reason(r.quests:record(2, "hit", 1)), "no_data")
    end)

    suite:test("claim pays once a quest is complete and never twice", function()
        local r = rig()
        r.quests:record(1, "hit", 2)
        harness.equal(errorOf(r.quests:claim(1, "c1")), "ok")
        harness.equal(r.profile.coins, 10)
        harness.equal(errorOf(r.quests:claim(1, "c1")), "already_claimed")
        harness.equal(r.profile.coins, 10)
    end)

    suite:test("claim before completion and for unknown quests is refused", function()
        local r = rig()
        harness.equal(errorOf(r.quests:claim(1, "c1")), "not_complete")
        harness.equal(errorOf(r.quests:claim(1, "nope")), "unknown_quest")
        harness.equal(errorOf(r.quests:claim(1, "c2")), "not_active")
    end)

    suite:test("a chain exposes the next step only after the claim", function()
        local r = rig()
        r.quests:record(1, "hit", 2)
        r.quests:claim(1, "c1")
        harness.equal(activeIds(r, "chain")[1], "c2")
        r.quests:record(1, "sell", 1)
        harness.equal(errorOf(r.quests:claim(1, "c2")), "ok")
        harness.equal(#activeIds(r, "chain"), 0)
        harness.equal(r.profile.coins, 30)
    end)

    suite:test("an unconfirmed save rolls the grant and the chain step back", function()
        local r = rig()
        r.quests:record(1, "hit", 2)
        r.setSaved(false)
        harness.equal(errorOf(r.quests:claim(1, "c1")), "save_failed")
        harness.equal(r.profile.coins, 0)
        harness.equal(activeIds(r, "chain")[1], "c1")
        r.setSaved(true)
        harness.equal(errorOf(r.quests:claim(1, "c1")), "ok")
        harness.equal(r.profile.coins, 10)
    end)

    suite:test("daily progress resets on the next UTC day but chains do not", function()
        local r = rig()
        r.quests:record(1, "hit", 2)
        r.setNow(11 * DAY + 5)
        local views = r.quests:view(1)
        for _, view in views do
            if view.group == "daily" then
                harness.equal(view.progress, 0)
            end
            if view.id == "c1" then
                harness.equal(view.progress, 2)
            end
        end
    end)

    suite:test(
        "the weekly pick holds inside a week and changes the key after seven days",
        function()
            local r = rig()
            local before = activeIds(r, "weekly")[1]
            r.setNow(10 * DAY + 100 + DAY)
            harness.equal(
                Quests.weekKey(10 * DAY + 100),
                Quests.weekKey(10 * DAY + 100 + DAY - 200)
            )
            harness.isTrue(Quests.weekKey(10 * DAY) ~= Quests.weekKey(17 * DAY), "week changes")
            harness.isTrue(before == "w1" or before == "w2", "valid pick")
        end
    )

    suite:test("a disabled config answers disabled everywhere", function()
        local config = makeConfig()
        config.enabled = false
        local r = rig(config)
        harness.equal(errorOf(r.quests:claim(1, "c1")), "disabled")
        harness.equal(#r.quests:view(1), 0)
    end)

    suite:test("the claim handler rate limits, validates and delegates", function()
        local r = rig()
        local allowed = true
        local handler = QuestRequests.new({
            quests = r.quests,
            allow = function()
                return allowed
            end,
        })
        r.quests:record(1, "hit", 2)
        local limited = (function()
            allowed = false
            local result = handler:handleClaim(1, "c1")
            allowed = true
            return result
        end)()
        harness.isFalse(limited.ok, "limited")
        harness.isFalse(handler:handleClaim(1, 42).ok, "not a string")
        harness.isFalse(handler:handleClaim(1, "").ok, "empty")
        harness.isTrue(handler:handleClaim(1, "c1").ok, "claimed")
        harness.isFalse(handler:handleClaim(1, "c1").ok, "second claim refused")
    end)
end
