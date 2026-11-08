--!strict
local HelloRetry = require("../../../src/shared/features/mining/HelloRetry")
local JoinCoordinator = require("../../../src/shared/features/join/JoinCoordinator")
local PassOwnership = require("../../../src/shared/features/mining/PassOwnership")
local ProvisionalCredit = require("../../../src/shared/features/mining/ProvisionalCredit")
local harness = require("../../harness")

local USER = 5

type Log = {
    applied: { { names: { string }, late: boolean } },
    topUps: number,
    credited: { number },
    errors: { string },
    passesRead: number,
}

type Env = {
    coordinator: JoinCoordinator.JoinCoordinator,
    log: Log,
    advance: (seconds: number) -> (),
    -- Runs the pass-read task when called (the read itself is the callback below).
    runReads: () -> (),
    setReader: (fn: (onLate: (names: { string }) -> ()) -> { string }) -> (),
    setCredit: (fn: (count: number) -> number) -> (),
}

local function newEnv(): Env
    local now = 0
    local log: Log = { applied = {}, topUps = 0, credited = {}, errors = {}, passesRead = 0 }
    local pending: { () -> () } = {}
    local reader: (onLate: (names: { string }) -> ()) -> { string } = function(_onLate)
        return {}
    end
    local creditor: (count: number) -> number = function(count: number): number
        return count
    end
    local coordinator = JoinCoordinator.new({
        clock = function(): number
            return now
        end,
        maxPerSecond = 12,
        spawn = function(fn: () -> ())
            table.insert(pending, fn)
        end,
        readEntitlements = function(_userId: number, onLate: (names: { string }) -> ()): { string }
            return reader(onLate)
        end,
        applyEntitlements = function(_userId: number, names: { string }, late: boolean)
            table.insert(log.applied, { names = names, late = late })
        end,
        onEntitlementsSettled = function(_userId: number)
            log.topUps += 1
        end,
        creditProvisional = function(_userId: number, count: number): number
            table.insert(log.credited, count)
            return creditor(count)
        end,
        onEntitlementsRead = function(_userId: number)
            log.passesRead += 1
        end,
        onCreditError = function(_userId: number, message: string)
            table.insert(log.errors, message)
        end,
    })
    return {
        coordinator = coordinator,
        log = log,
        advance = function(seconds: number)
            now += seconds
        end,
        runReads = function()
            local tasks = pending
            pending = {}
            for _, fn in tasks do
                fn()
            end
        end,
        setReader = function(fn)
            reader = fn
        end,
        setCredit = function(fn)
            creditor = fn
        end,
    }
end

return function(suite: harness.Harness)
    suite:test("a provisional batch before the hello is refused", function()
        local env = newEnv()
        env.coordinator:begin(USER)
        env.advance(5)
        harness.isTrue(env.coordinator:provisional(USER, 40) == nil, "refused")
        harness.equal(#env.log.credited, 0, "nothing credited")
    end)

    suite:test("the batch is single use: the second one is refused", function()
        local env = newEnv()
        env.coordinator:begin(USER)
        env.advance(5)
        env.coordinator:helloSent(USER)
        local first = env.coordinator:provisional(USER, 40)
        harness.isTrue(first ~= nil and first.credited == 40, "first credited whole")
        harness.isTrue(env.coordinator:provisional(USER, 40) == nil, "second refused")
        harness.equal(#env.log.credited, 1, "credited once")
    end)

    suite:test("the window freezes at the hello: waiting longer buys nothing", function()
        local env = newEnv()
        env.coordinator:begin(USER)
        env.advance(5)
        env.coordinator:helloSent(USER)
        env.advance(600)
        local result = env.coordinator:provisional(USER, 7200)
        harness.isTrue(result ~= nil, "accepted")
        harness.equal(env.log.credited[1], 60, "5 s at 12 a second, not 10 minutes")
        harness.equal(result and result.claimed, 7200, "the claim is reported as made")
    end)

    suite:test("a repeated hello does not move the frozen window", function()
        local env = newEnv()
        env.coordinator:begin(USER)
        env.advance(2)
        env.coordinator:helloSent(USER)
        env.advance(30)
        env.coordinator:helloSent(USER)
        env.coordinator:provisional(USER, 1000)
        harness.equal(env.log.credited[1], 24, "2 s window")
    end)

    suite:test("an honest tapper loses nothing", function()
        local env = newEnv()
        env.coordinator:begin(USER)
        env.advance(8)
        env.coordinator:helloSent(USER)
        local tapped = math.floor(12 * (8 - 0.5))
        local result = env.coordinator:provisional(USER, tapped)
        harness.equal(result and result.credited, tapped, "every tap credited")
    end)

    suite:test("a batch the swing path credits as zero still consumes the batch", function()
        local env = newEnv()
        env.setCredit(function(_count: number): number
            return 0
        end)
        env.coordinator:begin(USER)
        env.advance(5)
        env.coordinator:helloSent(USER)
        local result = env.coordinator:provisional(USER, 30)
        harness.equal(result and result.credited, 0, "out of reach: nothing credited")
        harness.isTrue(env.coordinator:provisional(USER, 30) == nil, "and nothing left to retry")
    end)

    suite:test("claim and commit: a crediting failure gives the reservation back", function()
        local env = newEnv()
        local fail = true
        env.setCredit(function(count: number): number
            if fail then
                error("engine hiccup")
            end
            return count
        end)
        env.coordinator:begin(USER)
        env.advance(5)
        env.coordinator:helloSent(USER)
        harness.isTrue(env.coordinator:provisional(USER, 30) == nil, "failed")
        harness.equal(#env.log.errors, 1, "the failure is reported, never swallowed")
        fail = false
        local retry = env.coordinator:provisional(USER, 30)
        harness.equal(
            retry and retry.credited,
            30,
            "not consumed halfway: it can still be credited"
        )
    end)

    suite:test("a leaving player is credited nothing and nothing is applied", function()
        local env = newEnv()
        env.setReader(function(_onLate)
            return { "x2 Power" }
        end)
        env.coordinator:begin(USER)
        env.advance(5)
        env.coordinator:helloSent(USER)
        env.coordinator:leaving(USER)
        harness.isTrue(env.coordinator:isLeaving(USER), "marked")
        harness.isTrue(env.coordinator:provisional(USER, 30) == nil, "no credit")
        env.runReads()
        harness.equal(#env.log.applied, 0, "no pass applied after the mark")
        harness.equal(env.log.topUps, 0, "no top-up")
        harness.isFalse(env.coordinator:helloSent(USER), "a late hello is refused")
    end)

    suite:test("passes that arrive before the hello ride on it", function()
        local env = newEnv()
        env.setReader(function(_onLate)
            return { "x2 Power" }
        end)
        env.coordinator:begin(USER)
        env.runReads()
        harness.equal(#env.log.applied, 1, "applied")
        harness.isFalse(env.log.applied[1].late, "not late: the hello has not gone out")
        harness.equal(env.log.passesRead, 1, "probe stage")
        env.coordinator:helloSent(USER)
        harness.equal(env.log.topUps, 1, "idempotent top-up check at the hello")
    end)

    suite:test("passes that arrive after the hello are a late change with a top-up", function()
        local env = newEnv()
        env.setReader(function(_onLate)
            return { "Long Sleeper" }
        end)
        env.coordinator:begin(USER)
        env.coordinator:helloSent(USER)
        env.runReads()
        harness.equal(#env.log.applied, 1, "applied")
        harness.isTrue(env.log.applied[1].late, "late")
        harness.equal(env.log.topUps, 1, "the offline cap is topped up")
    end)

    suite:test("a pass that answers after the deadline is applied, not dropped", function()
        local env = newEnv()
        local late: ((names: { string }) -> ())? = nil
        env.setReader(function(onLate)
            late = onLate
            return {}
        end)
        env.coordinator:begin(USER)
        env.coordinator:helloSent(USER)
        env.runReads()
        harness.equal(#env.log.applied, 0, "nothing yet")
        local deliver = late
        harness.isTrue(deliver ~= nil, "the reader got the callback")
        if deliver ~= nil then
            deliver({ "VIP" })
        end
        harness.equal(#env.log.applied, 1, "applied once it arrived")
        harness.isTrue(env.log.applied[1].late, "as a late change")
        harness.equal(env.log.topUps, 1, "and topped up")
    end)

    suite:test("PassOwnership calls onLate for a read that finishes after the deadline", function()
        local clock = 0
        local reader: thread? = nil
        local lateNames: { string } = {}
        local outcome = PassOwnership.readAll(
            { { name = "slow", id = 1 } },
            function(_pass): boolean?
                local answer: any = coroutine.yield()
                return answer :: boolean?
            end,
            {
                clock = function(): number
                    return clock
                end,
                wait = function(seconds: number)
                    clock += seconds
                end,
                spawn = function(fn: () -> ())
                    local co = coroutine.create(fn)
                    reader = co
                    coroutine.resume(co)
                end,
            },
            5,
            function(pass: PassOwnership.Pass)
                table.insert(lateNames, pass.name)
            end
        )
        harness.equal(#outcome.owned, 0, "nothing owned at the deadline")
        harness.equal(outcome.unread[1], "slow", "reported as unread")
        harness.equal(#lateNames, 0, "not late yet")
        local waiting = reader
        if waiting ~= nil then
            coroutine.resume(waiting, true)
        end
        harness.equal(lateNames[1], "slow", "the late answer is delivered, not dropped")
    end)

    suite:test("onLate after leaving applies nothing and tops nothing up", function()
        local env = newEnv()
        local late: ((names: { string }) -> ())? = nil
        env.setReader(function(onLate)
            late = onLate
            return {}
        end)
        env.coordinator:begin(USER)
        env.runReads()
        env.coordinator:leaving(USER)
        local deliver = late
        harness.isTrue(deliver ~= nil, "the reader got the callback")
        if deliver ~= nil then
            deliver({ "VIP" })
        end
        harness.equal(#env.log.applied, 0, "nothing applied")
        harness.equal(env.log.topUps, 0, "no top-up")
    end)

    suite:test("a rejoin gets a fresh window and does not inherit the consumed batch", function()
        local env = newEnv()
        env.coordinator:begin(USER)
        env.advance(5)
        env.coordinator:helloSent(USER)
        local first = env.coordinator:provisional(USER, 1000)
        harness.equal(first and first.credited, 60, "first session, 5 s window")
        harness.isTrue(env.coordinator:provisional(USER, 10) == nil, "consumed")
        env.coordinator:forget(USER)
        env.coordinator:begin(USER)
        env.advance(2)
        env.coordinator:helloSent(USER)
        local second = env.coordinator:provisional(USER, 1000)
        harness.equal(second and second.credited, 24, "new session, its own 2 s window")
    end)

    suite:test(
        "a stale pass delivery from the previous session never touches the new state",
        function()
            local env = newEnv()
            local stale: ((names: { string }) -> ())? = nil
            env.setReader(function(onLate)
                stale = onLate
                return {}
            end)
            env.coordinator:begin(USER)
            env.runReads()
            env.coordinator:forget(USER)
            env.coordinator:begin(USER)
            env.coordinator:helloSent(USER)
            local deliver = stale
            if deliver ~= nil then
                deliver({ "VIP" })
            end
            harness.equal(#env.log.applied, 0, "the old session delivery is dropped")
            harness.equal(env.log.topUps, 0, "no top-up from it")
        end
    )

    suite:test("the leaving mark blocks the pass flow even mid-read", function()
        local env = newEnv()
        env.setReader(function(_onLate)
            env.coordinator:leaving(USER)
            return { "x2 Coins" }
        end)
        env.coordinator:begin(USER)
        env.runReads()
        harness.equal(#env.log.applied, 0, "nothing applied")
        harness.equal(env.log.passesRead, 0, "not even marked as read")
    end)

    suite:test("the slow hello retry keeps asking every 15 s until the hello arrives", function()
        local retry = HelloRetry.new()
        harness.isTrue(retry:due(2), "2 s")
        harness.isTrue(retry:due(5), "5 s")
        harness.isTrue(retry:due(10), "10 s")
        harness.isFalse(retry:due(24), "quiet before the slow moment")
        harness.isTrue(retry:due(25), "slow retry at 25 s")
        harness.isFalse(retry:due(26), "once per moment")
        harness.isTrue(retry:due(40), "and again 15 s later")
        harness.isTrue(retry:due(200), "forever, one request after a long stall")
        harness.isFalse(retry:due(201), "not a burst")
        retry:received()
        harness.isFalse(retry:due(500), "stops with the hello")
    end)

    suite:test("ProvisionalCredit reserves once and commits what was credited", function()
        local now = 0
        local credit = ProvisionalCredit.new({
            clock = function(): number
                return now
            end,
            maxPerSecond = 12,
        })
        credit:begin(USER)
        harness.isTrue(credit:claim(USER, 10) == nil, "refused before the hello")
        now = 3
        credit:markHello(USER)
        now = 1000
        credit:markHello(USER)
        harness.equal(credit:claim(USER, 500), 36, "capped at the frozen window")
        harness.isTrue(credit:claim(USER, 5) == nil, "reserved: no second claim")
        credit:commit(USER, 30)
        harness.isTrue(credit:claim(USER, 5) == nil, "consumed")
        local stats = credit:stats(USER)
        harness.isTrue(stats ~= nil and stats.consumed and stats.credited == 30, "stats")
        harness.isTrue(credit:claim(99, 5) == nil, "unknown player")
        credit:forget(USER)
        harness.isTrue(credit:stats(USER) == nil, "forgotten")
    end)

    suite:test("ProvisionalCredit refuses junk claims", function()
        local credit = ProvisionalCredit.new({
            clock = function(): number
                return 10
            end,
            maxPerSecond = 12,
        })
        credit:begin(USER)
        credit:markHello(USER)
        harness.isTrue(credit:claim(USER, 0) == nil, "zero")
        harness.isTrue(credit:claim(USER, -4) == nil, "negative")
        harness.isTrue(credit:claim(USER, 0 / 0) == nil, "NaN")
    end)
end
