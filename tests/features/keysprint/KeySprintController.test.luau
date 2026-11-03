--!strict
local ChargeMeter = require("../../../src/shared/features/keysprint/ChargeMeter")
local Funnel = require("../../../src/shared/features/keysprint/Funnel")
local KeySprintController = require("../../../src/shared/features/keysprint/KeySprintController")
local KeySprintRules = require("../../../src/shared/features/keysprint/KeySprintRules")
local RateLimiter = require("../../../src/shared/net/RateLimiter")
local StageRuns = require("../../../src/shared/features/keysprint/StageRuns")
local harness = require("../../harness")

type Data = KeySprintController.Data

type Env = {
    controller: KeySprintController.KeySprintController,
    data: { [number]: Data },
    log: { string },
    events: { string },
    denied: { [string]: boolean },
    advance: (seconds: number) -> (),
    promptResult: { value: boolean },
}

local function newEnv(): Env
    local now = 0
    local function clock(): number
        return now
    end
    local log: { string } = {}
    local events: { string } = {}
    local denied: { [string]: boolean } = {}
    local data: { [number]: Data } = {}
    local promptResult = { value = true }
    local charge = ChargeMeter.new({
        clock = clock,
        pressLimiter = RateLimiter.new({
            capacity = KeySprintRules.PRESS_BURST,
            refillPerSecond = KeySprintRules.MAX_PRESSES_PER_SECOND,
            clock = clock,
        }),
    })
    local runs = StageRuns.new({
        clock = clock,
        pathLength = function(_stage: number): number
            return 160
        end,
    })
    local funnel = Funnel.new({
        track = function(name: string, _userId: number, _sessionIndex: number): boolean
            table.insert(events, name)
            return true
        end,
    })
    local controller = KeySprintController.new({
        charge = charge,
        runs = runs,
        funnel = funnel,
        dataFor = function(userId: number): Data?
            return data[userId]
        end,
        allow = function(remote: string, _userId: number): boolean
            return not denied[remote]
        end,
        effects = {
            setWalkSpeed = function(_userId: number, speed: number)
                table.insert(log, `speed:{speed}`)
            end,
            sendMultiplier = function(_userId: number, multiplier: number, cap: number)
                table.insert(log, `multiplier:{string.format("%.2f", multiplier)}/{cap}`)
            end,
            sendProgress = function(_userId: number, highestStage: number, cap: number)
                table.insert(log, `progress:{highestStage}/{cap}`)
            end,
            sendCoins = function(_userId: number, coins: number)
                table.insert(log, `coins:{coins}`)
            end,
            teleportToStage = function(_userId: number, stage: number)
                table.insert(log, `teleport:{stage}`)
            end,
            promptSkip = function(_userId: number): boolean
                table.insert(log, "promptSkip")
                return promptResult.value
            end,
        },
    })
    local function advance(seconds: number)
        now += seconds
    end
    return {
        controller = controller,
        data = data,
        log = log,
        events = events,
        denied = denied,
        advance = advance,
        promptResult = promptResult,
    }
end

local function fresh(): Data
    return { coins = 0, highestStage = 0, multiplierCap = KeySprintRules.BASE_CAP }
end

local function reasonOf(outcome: KeySprintController.Outcome): string
    if outcome.ok then
        return "ok"
    end
    return outcome.reason
end

local function has(log: { string }, entry: string): boolean
    return table.find(log, entry) ~= nil
end

return function(suite: harness.Harness)
    suite:test("join sends the state, starts stage 1 and logs the tutorial funnel", function()
        local env = newEnv()
        env.data[1] = fresh()
        harness.isTrue(env.controller:onJoin(1, 1), "joined")
        harness.isTrue(has(env.log, "teleport:1"), "teleport")
        harness.isTrue(has(env.log, "progress:0/5"), "progress")
        harness.isTrue(has(env.log, "coins:0"), "coins")
        harness.equal(table.concat(env.events, ","), "session_start,tutorial_start", "funnel")
    end)

    suite:test("join without loaded data does nothing", function()
        local env = newEnv()
        harness.isFalse(env.controller:onJoin(1, 1), "no data")
        harness.equal(#env.log, 0, "no effects")
    end)

    suite:test("a returning player starts at the next uncleared stage", function()
        local env = newEnv()
        env.data[1] = { coins = 5, highestStage = 2, multiplierCap = 10 }
        env.controller:onJoin(1, 3)
        harness.isTrue(has(env.log, "teleport:3"), "stage 3")
    end)

    suite:test("a press batch raises the speed on the server and tells the client", function()
        local env = newEnv()
        env.data[1] = fresh()
        env.controller:onJoin(1, 1)
        local outcome = env.controller:onPressBatch(1, 10)
        harness.equal(reasonOf(outcome), "ok", "accepted")
        harness.isTrue(has(env.log, "speed:32"), "speed 16 x 2")
        harness.isTrue(has(env.log, "multiplier:2.00/5"), "sent")
        harness.isTrue(has(env.events, "first_action"), "first_action")
    end)

    suite:test(
        "the walk speed never exceeds BASE_WALK_SPEED x cap whatever the client sends",
        function()
            local env = newEnv()
            env.data[1] = fresh()
            env.controller:onJoin(1, 1)
            for _ = 1, 100 do
                env.controller:onPressBatch(1, 12)
                env.advance(0.25)
            end
            local top = 0
            for _, entry in env.log do
                local speed = string.match(entry, "^speed:(.+)$")
                if speed ~= nil then
                    top = math.max(top, tonumber(speed) :: number)
                end
            end
            harness.isTrue(top <= KeySprintRules.BASE_WALK_SPEED * KeySprintRules.BASE_CAP, "cap")
        end
    )

    suite:test("a rate-limited or invalid batch changes nothing", function()
        local env = newEnv()
        env.data[1] = fresh()
        env.controller:onJoin(1, 1)
        local before = #env.log
        env.denied.PressBatch = true
        harness.equal(reasonOf(env.controller:onPressBatch(1, 5)), "rate_limited", "denied")
        env.denied.PressBatch = false
        harness.equal(reasonOf(env.controller:onPressBatch(1, "x")), "not_a_number", "invalid")
        harness.equal(#env.log, before, "no effects")
    end)

    suite:test("a press from a player with no data is dropped", function()
        local env = newEnv()
        harness.equal(reasonOf(env.controller:onPressBatch(7, 3)), "no_data")
    end)

    suite:test("a finish that is too fast is rejected and pays nothing", function()
        local env = newEnv()
        env.data[1] = fresh()
        env.controller:onJoin(1, 1)
        harness.equal(reasonOf(env.controller:onFinish(1, 1)), "too_fast", "teleported finish")
        harness.equal((env.data[1] :: Data).coins, 0, "coins")
        harness.equal((env.data[1] :: Data).highestStage, 0, "stage")
    end)

    suite:test("an honest finish pays, advances the stage and moves the player on", function()
        local env = newEnv()
        env.data[1] = fresh()
        env.controller:onJoin(1, 1)
        env.advance(30)
        harness.equal(reasonOf(env.controller:onFinish(1, 1)), "ok", "accepted")
        local data = env.data[1] :: Data
        harness.equal(data.coins, KeySprintRules.STAGE_REWARDS[1], "coins")
        harness.equal(data.highestStage, 1, "highestStage")
        harness.isTrue(has(env.log, "teleport:2"), "next stage")
        harness.isTrue(has(env.log, `coins:{KeySprintRules.STAGE_REWARDS[1]}`), "coins sent")
        harness.isTrue(has(env.log, "progress:1/5"), "progress sent")
        harness.isTrue(has(env.events, "tutorial_complete"), "tutorial_complete")
    end)

    suite:test("finishing resets the charge so the next stage starts slow", function()
        local env = newEnv()
        env.data[1] = fresh()
        env.controller:onJoin(1, 1)
        env.controller:onPressBatch(1, 10)
        env.advance(30)
        env.controller:onFinish(1, 1)
        local lastSpeed = ""
        for _, entry in env.log do
            if string.sub(entry, 1, 6) == "speed:" then
                lastSpeed = entry
            end
        end
        harness.equal(lastSpeed, "speed:16", "speed back to base")
    end)

    suite:test("the same finish twice pays once", function()
        local env = newEnv()
        env.data[1] = fresh()
        env.controller:onJoin(1, 1)
        env.advance(30)
        env.controller:onFinish(1, 1)
        harness.equal(reasonOf(env.controller:onFinish(1, 1)), "wrong_stage", "second")
        harness.equal((env.data[1] :: Data).coins, KeySprintRules.STAGE_REWARDS[1], "paid once")
    end)

    suite:test("finish is rate limited and ignores players without data", function()
        local env = newEnv()
        env.data[1] = fresh()
        env.controller:onJoin(1, 1)
        env.denied.Finish = true
        harness.equal(reasonOf(env.controller:onFinish(1, 1)), "rate_limited", "denied")
        harness.equal(reasonOf(env.controller:onFinish(9, 1)), "rate_limited", "denied first")
        env.denied.Finish = false
        harness.equal(reasonOf(env.controller:onFinish(9, 1)), "no_data", "no data")
    end)

    suite:test("buy cap charges the server price and tells the client", function()
        local env = newEnv()
        env.data[1] = { coins = 100, highestStage = 1, multiplierCap = 5 }
        env.controller:onJoin(1, 2)
        harness.equal(reasonOf(env.controller:onBuyCap(1)), "ok", "bought")
        harness.equal((env.data[1] :: Data).multiplierCap, 10, "cap")
        harness.equal(
            (env.data[1] :: Data).coins,
            100 - (KeySprintRules.CAP_PRICES[5] :: number),
            "coins"
        )
        harness.isTrue(has(env.log, "progress:1/10"), "progress sent")
    end)

    suite:test("buy cap refusals are typed and change nothing", function()
        local env = newEnv()
        env.data[1] = fresh()
        env.controller:onJoin(1, 1)
        harness.equal(reasonOf(env.controller:onBuyCap(1)), "not_enough_coins", "poor")
        env.denied.BuyCap = true
        harness.equal(reasonOf(env.controller:onBuyCap(1)), "rate_limited", "limited")
        harness.equal(reasonOf(env.controller:onBuyCap(8)), "rate_limited", "limited first")
        env.denied.BuyCap = false
        harness.equal(reasonOf(env.controller:onBuyCap(8)), "no_data", "no data")
        harness.equal((env.data[1] :: Data).multiplierCap, 5, "cap")
    end)

    suite:test("skip stage opens the purchase prompt only while stages remain", function()
        local env = newEnv()
        env.data[1] = fresh()
        env.controller:onJoin(1, 1)
        harness.equal(reasonOf(env.controller:onSkipStageRequest(1)), "ok", "prompt")
        harness.isTrue(has(env.log, "promptSkip"), "prompted")
        env.promptResult.value = false
        harness.equal(reasonOf(env.controller:onSkipStageRequest(1)), "prompt_failed", "failed")
        env.promptResult.value = true
        local data = env.data[1] :: Data
        data.highestStage = KeySprintRules.STAGE_COUNT
        harness.equal(reasonOf(env.controller:onSkipStageRequest(1)), "complete", "all cleared")
        env.denied.SkipStage = true
        harness.equal(reasonOf(env.controller:onSkipStageRequest(1)), "rate_limited", "limited")
        harness.equal(reasonOf(env.controller:onSkipStageRequest(5)), "rate_limited", "no data")
        env.denied.SkipStage = false
        harness.equal(reasonOf(env.controller:onSkipStageRequest(5)), "no_data", "no data")
    end)

    suite:test("after a skip is granted the player moves to the next stage", function()
        local env = newEnv()
        env.data[1] = fresh()
        env.controller:onJoin(1, 1)
        local data = env.data[1] :: Data
        data.highestStage = 1 -- what the skipStage grant does
        env.controller:onProgressGranted(1)
        harness.isTrue(has(env.log, "teleport:2"), "stage 2")
        harness.isTrue(has(env.log, "progress:1/5"), "progress")
        env.controller:onProgressGranted(99)
    end)

    suite:test("tick re-sends the multiplier only when it moved enough", function()
        local env = newEnv()
        env.data[1] = fresh()
        env.controller:onJoin(1, 1)
        env.controller:onPressBatch(1, 10)
        local count = #env.log
        env.controller:tick({ 1 })
        harness.equal(#env.log, count, "unchanged")
        env.advance(2)
        env.controller:tick({ 1, 42 })
        harness.isTrue(#env.log > count, "decay reported")
    end)

    suite:test("the Faster charge pass makes the same presses worth more", function()
        local plain = newEnv()
        local fast = newEnv()
        plain.data[1] = fresh()
        fast.data[1] = fresh()
        plain.controller:onJoin(1, 1)
        fast.controller:onJoin(1, 1)
        fast.controller:setFasterCharge(1, true)
        plain.controller:onPressBatch(1, 4)
        fast.controller:onPressBatch(1, 4)
        harness.isTrue(
            has(plain.log, "multiplier:1.40/5") and has(fast.log, "multiplier:1.60/5"),
            "1.4 against 1.6"
        )
    end)

    suite:test("a respawn returns the player to the checkpoint with base speed", function()
        local env = newEnv()
        env.data[1] = { coins = 0, highestStage = 1, multiplierCap = 5 }
        env.controller:onJoin(1, 2)
        env.controller:onPressBatch(1, 10)
        env.controller:onRespawn(1)
        harness.equal(env.log[#env.log], "speed:16", "speed reset")
        harness.equal(env.log[#env.log - 1], "teleport:2", "checkpoint is the active stage")
        harness.equal(env.controller:onRespawn(77), false, "unknown player")
    end)

    suite:test("leave forgets the player everywhere", function()
        local env = newEnv()
        env.data[1] = fresh()
        env.controller:onJoin(1, 1)
        env.controller:onPressBatch(1, 5)
        env.controller:onLeave(1)
        env.advance(30)
        harness.equal(reasonOf(env.controller:onFinish(1, 1)), "no_active_run", "run gone")
    end)
end
