--!strict
--[[
    Fuzz of every remote validator and request handler (ADR 0062). A hostile client controls the
    arguments, so each one gets wrong types, nil, NaN, +-inf, 1 MB strings, tables with hostile
    metatables and cyclic tables, plus hundreds of random values. Contract checked on all of
    them: nothing raises, the result is a well-formed Result, and a rejected value never reaches
    the dependency behind the handler.
]]

local CodeRequests = require("../../src/shared/features/codes/CodeRequests")
local PurchaseRequests = require("../../src/shared/features/monetization/PurchaseRequests")
local QuestRequests = require("../../src/shared/features/quests/QuestRequests")
local SoundConfig = require("../../src/shared/features/sound/SoundConfig")
local SoundRequests = require("../../src/shared/features/sound/SoundRequests")
local SoundSettings = require("../../src/shared/features/sound/SoundSettings")
local TimeRewardRequests = require("../../src/shared/features/timerewards/TimeRewardRequests")
local Config = require("../../src/shared/Config")
local Validation = require("../../src/shared/net/Validation")
local Prop = require("../property/Prop")
local harness = require("../harness")

local MEGABYTE = 1048576

-- Values a hostile client could send that random generation would rarely produce.
local function hostileValues(): { unknown }
    local raising = setmetatable({}, {
        __index = function()
            error("hostile __index")
        end,
        __newindex = function()
            error("hostile __newindex")
        end,
        __len = function()
            error("hostile __len")
        end,
        __tostring = function()
            error("hostile __tostring")
        end,
        __eq = function()
            error("hostile __eq")
        end,
        __concat = function()
            error("hostile __concat")
        end,
        __call = function()
            error("hostile __call")
        end,
        __metatable = "locked",
    })
    local cycle: { [string]: unknown } = {}
    cycle.self = cycle
    local deep: { [number]: unknown } = {}
    local cursor = deep
    for _ = 1, 5000 do
        local nextLevel: { [number]: unknown } = {}
        cursor[1] = nextLevel
        cursor = nextLevel
    end
    return {
        true,
        false,
        0,
        -0,
        1,
        -1,
        0.5,
        0 / 0,
        math.huge,
        -math.huge,
        2 ^ 53,
        2 ^ 53 + 2,
        1e300,
        -1e300,
        "",
        " ",
        "Coins100",
        "music",
        "\0",
        "\u{1f600}",
        string.rep("A", MEGABYTE),
        string.rep("\u{1f600}", MEGABYTE // 4),
        string.rep("\0", MEGABYTE),
        {},
        { "Coins100" },
        { [1] = "Coins100", [2] = "Coins100" },
        raising,
        setmetatable({}, { __index = raising }),
        cycle,
        deep,
        function() end,
        print,
        coroutine.create(function() end),
        buffer.create(16),
    }
end

local function isWellFormed(result: unknown): boolean
    if type(result) ~= "table" then
        return false
    end
    local fields = result :: { ok: unknown, reason: unknown, error: unknown }
    if fields.ok == true then
        return true
    end
    return fields.ok == false and type(fields.reason or fields.error) == "string"
end

-- Runs `call` on nil, every hostile value and random ones; `observe` sees each value after.
local function fuzz(name: string, call: (value: unknown) -> unknown, observe: (value: unknown, result: unknown) -> ())
    local function once(value: unknown)
        local ok, result = pcall(call, value)
        harness.isTrue(ok, `{name} raised: {tostring(result)} for {Prop.describe(value, 0)}`)
        harness.isTrue(isWellFormed(result), `{name} returned a malformed result`)
        observe(value, result)
    end
    once(nil)
    for _, value in hostileValues() do
        once(value)
    end
    Prop.check(`fuzz {name}`, Prop.anything(), once, { cases = 300 })
end

local function noObserve(_value: unknown, _result: unknown) end

local function accepted(result: unknown): boolean
    return (result :: { ok: boolean }).ok
end

local function allowAll(_userId: number): boolean
    return true
end

return function(suite: harness.Harness)
    suite:test("Validation.number never raises and accepts only finite numbers", function()
        fuzz("number", function(value: unknown): unknown
            return Validation.number(value)
        end, function(value: unknown, result: unknown)
            local expected = type(value) == "number"
                and value == value
                and value ~= math.huge
                and value ~= -math.huge
            harness.equal(accepted(result), expected, "verdict")
        end)
    end)

    suite:test("Validation.integerInRange never raises and accepts only integers in range", function()
        fuzz("integerInRange", function(value: unknown): unknown
            return Validation.integerInRange(value, 0, 100)
        end, function(value: unknown, result: unknown)
            local expected = type(value) == "number" and value == value and value % 1 == 0 and value >= 0 and value <= 100
            harness.equal(accepted(result), expected, "verdict")
        end)
    end)

    suite:test("Validation.string never raises and enforces type and byte length", function()
        fuzz("string", function(value: unknown): unknown
            return Validation.string(value, 1, 32)
        end, function(value: unknown, result: unknown)
            local expected = type(value) == "string" and #value >= 1 and #value <= 32
            harness.equal(accepted(result), expected, "verdict")
        end)
    end)

    suite:test("Validation.oneOf never raises and is an allow-list", function()
        local allowed = { "Coins100", "Coins500" }
        fuzz("oneOf", function(value: unknown): unknown
            return Validation.oneOf(value, allowed)
        end, function(value: unknown, result: unknown)
            local expected = type(value) == "string" and table.find(allowed, value) ~= nil
            harness.equal(accepted(result), expected, "verdict")
        end)
    end)

    suite:test("Validation.boolean never raises and accepts only booleans", function()
        fuzz("boolean", function(value: unknown): unknown
            return Validation.boolean(value)
        end, function(value: unknown, result: unknown)
            harness.equal(accepted(result), type(value) == "boolean", "verdict")
        end)
    end)

    suite:test("PurchaseRequests rejects every product that is not on the list, cleanly", function()
        local prompted: { string } = {}
        local handler = PurchaseRequests.new({
            productNames = { "Coins100" },
            allow = allowAll,
            prompt = function(_userId: number, productName: string): boolean
                table.insert(prompted, productName)
                return true
            end,
        })
        fuzz("PurchaseRequests", function(value: unknown): unknown
            return handler:handle(1, value)
        end, function(value: unknown, result: unknown)
            harness.equal(accepted(result), value == "Coins100", "only the listed product passes")
        end)
        for _, productName in prompted do
            harness.equal(productName, "Coins100", "the prompt only ever sees a listed product")
        end
    end)

    suite:test("PurchaseRequests tolerates a hostile user id and a failing dependency", function()
        local handler = PurchaseRequests.new({
            productNames = { "Coins100" },
            allow = function(userId: number): boolean
                return userId == userId
            end,
            prompt = function(): boolean
                return false
            end,
        })
        Prop.check("purchase user id", Prop.number(), function(userId: number)
            local result = handler:handle(userId, "Coins100")
            harness.isTrue(isWellFormed(result), "well formed")
            harness.isFalse(accepted(result), "a failed prompt is never ok")
        end)
    end)

    suite:test("SoundRequests never stores a volume outside 0..100", function()
        local profile = { settings = {} :: { musicVolume: number?, sfxVolume: number? } }
        local settings = SoundSettings.new({
            config = Config.default.sound :: SoundConfig.SoundConfig,
            profileFor = function(): SoundSettings.SettingsProfile?
                return profile
            end,
            push = function() end,
        })
        local handler = SoundRequests.new({ settings = settings, allow = allowAll })
        local function checkStored()
            for _, volume in { profile.settings.musicVolume, profile.settings.sfxVolume } do
                harness.isTrue(
                    volume == nil or (volume >= 0 and volume <= 100 and volume % 1 == 0),
                    `stored volume {tostring(volume)}`
                )
            end
        end
        fuzz("SoundRequests percent", function(value: unknown): unknown
            return handler:handle(1, "music", value)
        end, function()
            checkStored()
        end)
        fuzz("SoundRequests group", function(value: unknown): unknown
            return handler:handle(1, value, 50)
        end, function(value: unknown, result: unknown)
            harness.equal(accepted(result), value == "music" or value == "sfx", "group verdict")
            checkStored()
        end)
    end)

    suite:test("CodeRequests only passes a 1..max byte string to the redeem service", function()
        local maxLength = 24
        local redeemed: { string } = {}
        local handler = CodeRequests.new({
            codes = {
                redeem = function(_self, _userId: number, text: string)
                    table.insert(redeemed, text)
                    return { ok = false, error = "invalid_code" :: "invalid_code" }
                end,
                forget = function() end,
            },
            notifier = {
                notify = function(): nil
                    return nil
                end,
            },
            allow = allowAll,
            maxCodeLength = maxLength,
        })
        fuzz("CodeRequests", function(value: unknown): unknown
            return handler:handle(1, value)
        end, noObserve)
        for _, text in redeemed do
            harness.isTrue(#text >= 1 and #text <= maxLength, "redeem saw a bounded string")
        end
    end)

    suite:test("QuestRequests only passes a 1..32 byte string to the quest service", function()
        local claimed: { string } = {}
        local handler = QuestRequests.new({
            quests = {
                record = function()
                    return { ok = false, error = "disabled" :: "disabled" }
                end,
                claim = function(_self, _userId: number, questId: string)
                    table.insert(claimed, questId)
                    return { ok = false, error = "unknown_quest" :: "unknown_quest" }
                end,
                view = function()
                    return {}
                end,
            },
            allow = allowAll,
        })
        fuzz("QuestRequests", function(value: unknown): unknown
            return handler:handleClaim(1, value)
        end, noObserve)
        for _, questId in claimed do
            harness.isTrue(#questId >= 1 and #questId <= 32, "claim saw a bounded string")
        end
    end)

    suite:test("TimeRewardRequests only passes a listed gift id to the service", function()
        local claimed: { string } = {}
        local handler = TimeRewardRequests.new({
            timeRewards = {
                startSession = function() end,
                claimDaily = function()
                    return { ok = false, error = "not_ready" :: "not_ready" }
                end,
                claimSession = function(_self, _userId: number, giftId: string)
                    table.insert(claimed, giftId)
                    return { ok = false, error = "unknown_gift" :: "unknown_gift" }
                end,
                forget = function() end,
            },
            notifier = {
                notify = function(): nil
                    return nil
                end,
            },
            allowDaily = allowAll,
            allowSession = allowAll,
            giftIds = { "welcome", "hour" },
        })
        fuzz("TimeRewardRequests", function(value: unknown): unknown
            return handler:handleSession(1, value)
        end, noObserve)
        for _, giftId in claimed do
            harness.isTrue(giftId == "welcome" or giftId == "hour", "claim saw a listed gift")
        end
    end)
end
