--!strict
local AttributeObjectivePublisher =
    require("../../../src/server/adapters/AttributeObjectivePublisher")
local ObjectiveConfig = require("../../../src/shared/features/sharedobjective/ObjectiveConfig")
local ObjectiveRuntime = require("../../../src/shared/features/sharedobjective/ObjectiveRuntime")
local SharedObjective = require("../../../src/shared/features/sharedobjective/SharedObjective")
local harness = require("../../harness")

local config = ObjectiveConfig.default

local function kinds(events: { SharedObjective.Event }): string
    local names: { string } = {}
    for _, event in events do
        table.insert(names, event.kind)
    end
    return table.concat(names, ",")
end

-- Opens an objective for the given players and returns it with the open time.
local function opened(players: { number }): (SharedObjective.SharedObjective, number)
    local objective = SharedObjective.new(config, 1000)
    local at = 1000 + config.intervalSeconds
    harness.equal(kinds(objective:tick(at, players)), "opened")
    return objective, at
end

return function(suite: harness.Harness)
    suite:test("the default config is valid and each rule is checked", function()
        harness.equal(#ObjectiveConfig.problems(config), 0)
        local cases: { { label: string, change: (c: ObjectiveConfig.ObjectiveConfig) -> () } } = {
            {
                label = "duration not shorter",
                change = function(c)
                    c.durationSeconds = c.intervalSeconds
                end,
            },
            {
                label = "interval",
                change = function(c)
                    c.intervalSeconds = 0
                end,
            },
            {
                label = "duration",
                change = function(c)
                    c.durationSeconds = -1
                end,
            },
            {
                label = "first open",
                change = function(c)
                    c.firstOpenSeconds = -1
                end,
            },
            {
                label = "units per player",
                change = function(c)
                    c.unitsPerPlayer = 0
                end,
            },
            {
                label = "rate cap",
                change = function(c)
                    c.maxUnitsPerSecond = 0
                end,
            },
            {
                label = "minimum",
                change = function(c)
                    c.minContribution = -1
                end,
            },
            {
                label = "top count",
                change = function(c)
                    c.topCount = 1.5
                end,
            },
            {
                label = "hold",
                change = function(c)
                    c.resultHoldSeconds = -1
                end,
            },
        }
        for _, case in cases do
            local broken = table.clone(config)
            case.change(broken)
            harness.isTrue(#ObjectiveConfig.problems(broken) > 0, case.label)
        end
    end)

    suite:test(
        "it waits, does not open an empty server and opens on the first present tick",
        function()
            local objective = SharedObjective.new(config, 1000)
            harness.equal(objective:view(1000).phase, "waiting")
            harness.equal(objective:view(1000).beat, "idle")
            harness.equal(objective:view(1000).nextAt, 1000 + config.intervalSeconds)
            harness.equal(kinds(objective:tick(1000 + config.intervalSeconds - 1, { 1 })), "")
            harness.equal(kinds(objective:tick(1000 + config.intervalSeconds, {})), "")
            harness.equal(kinds(objective:tick(1000 + config.intervalSeconds + 5, { 1 })), "opened")
            local view = objective:view(1000 + config.intervalSeconds + 5)
            harness.equal(view.phase, "open")
            harness.equal(view.beat, "buildup")
            harness.equal(view.nextAt, 0)
        end
    )

    suite:test(
        "the first objective counts from the first player, not from the server start",
        function()
            local objective = SharedObjective.new(config, 1000)
            harness.equal(kinds(objective:tick(1010, { 7 })), "")
            harness.equal(kinds(objective:tick(1010 + config.firstOpenSeconds, { 7 })), "opened")
        end
    )

    suite:test("the target scales with the players present and never drops", function()
        harness.equal(SharedObjective.targetFor(config, 0), config.unitsPerPlayer)
        harness.equal(SharedObjective.targetFor(config, 3), config.unitsPerPlayer * 3)
        local objective, at = opened({ 1, 2 })
        harness.equal(objective:view(at).target, config.unitsPerPlayer * 2)
        objective:tick(at + 1, { 1, 2, 3 })
        harness.equal(objective:view(at + 1).target, config.unitsPerPlayer * 3)
        objective:tick(at + 2, { 1 })
        harness.equal(objective:view(at + 2).target, config.unitsPerPlayer * 3)
    end)

    suite:test("contributions count only while open and are rate capped per player", function()
        local objective = SharedObjective.new(config, 1000)
        harness.equal(objective:contribute(1, 5, 1000), 0, "nothing counts while waiting")
        local at = 1000 + config.intervalSeconds
        objective:tick(at, { 1, 2 })
        harness.equal(objective:contribute(1, 1000, at), config.maxUnitsPerSecond)
        harness.equal(objective:contribute(1, 5, at), 0, "bucket empty in the same instant")
        harness.equal(objective:contribute(1, 5, at + 1), 5, "refilled a second later")
        harness.equal(objective:contribute(2, 0, at), 0, "zero units")
        harness.equal(objective:contribute(2, 0 / 0, at), 0, "NaN units")
        harness.equal(objective:contribute(2, 2.9, at), 2, "fractions floor")
        harness.equal(
            objective:contribute(1, 1, at + config.durationSeconds),
            0,
            "nothing after the close time"
        )
    end)

    suite:test("filling the bar completes with a stable ranking and a drop beat", function()
        local objective, at = opened({ 1, 2, 3, 4, 5 })
        local clock = at
        -- 5 players ask for 5 * unitsPerPlayer; players 1..5 push different amounts.
        local pushes: { [number]: number } = { [1] = 90, [2] = 90, [3] = 60, [4] = 40, [5] = 20 }
        for second = 1, 30 do
            clock = at + second
            for userId, total in pushes do
                local counted = objective:contribute(userId, math.min(8, total), clock)
                pushes[userId] = total - counted
            end
        end
        local events = objective:tick(clock, { 1, 2, 3, 4, 5 })
        harness.equal(kinds(events), "completed")
        local event = events[1]
        harness.isTrue(event.kind == "completed", "completed event")
        if event.kind == "completed" then
            local list = event.completions
            harness.equal(#list, 5)
            harness.equal(list[1].userId, 1, "tie broken by the lower id")
            harness.equal(list[2].userId, 2)
            harness.isTrue(list[1].top and list[3].top, "top three flagged")
            harness.isFalse(list[4].top, "fourth is not top")
            harness.equal(list[5].rank, 5)
        end
        local view = objective:view(clock)
        harness.equal(view.beat, "drop")
        harness.equal(view.completed, 1)
        harness.equal(view.progress, 0, "state is reset")
        harness.equal(objective:view(clock + config.resultHoldSeconds).beat, "idle")
        harness.equal(view.nextAt, clock + config.intervalSeconds)
    end)

    suite:test("running out of time fails with a fail beat and no completion", function()
        local objective, at = opened({ 1 })
        objective:contribute(1, 3, at)
        local events = objective:tick(at + config.durationSeconds, { 1 })
        harness.equal(kinds(events), "failed")
        harness.equal(objective:view(at + config.durationSeconds).beat, "fail")
        harness.equal(objective:view(at + config.durationSeconds).completed, 0)
        harness.equal(
            objective:view(at + config.durationSeconds + config.resultHoldSeconds).beat,
            "idle"
        )
        harness.equal(kinds(objective:tick(at + config.durationSeconds + 1, { 1 })), "")
    end)

    suite:test("a player under the minimum contribution is not counted", function()
        local strict = table.clone(config)
        strict.minContribution = 5
        strict.unitsPerPlayer = 6
        local objective = SharedObjective.new(strict, 0)
        local at = strict.intervalSeconds
        objective:tick(at, { 1, 2 })
        objective:contribute(1, 8, at)
        objective:contribute(2, 3, at)
        objective:contribute(2, 1, at + 1)
        local events = objective:tick(at + 1, { 1, 2 })
        local event = events[1]
        harness.isTrue(event ~= nil and event.kind == "completed", "completed")
        if event ~= nil and event.kind == "completed" then
            harness.equal(#event.completions, 1)
            harness.equal(event.completions[1].userId, 1)
        end
    end)

    suite:test(
        "the runtime pays, publishes through the port and reports a missed reward",
        function()
            local clock = 1000
            local players: { number } = { 10, 20 }
            local errors: { string } = {}
            local paid: { number } = {}
            local completedCalls = 0
            local attributes: { [string]: string | number } = {}
            local writes = 0
            local publisher = AttributeObjectivePublisher.new({
                prefix = "Obj",
                set = function(name: string, value: string | number)
                    writes += 1
                    attributes[name] = value
                end,
            })
            local runtime = ObjectiveRuntime.new({
                config = config,
                publisher = publisher,
                now = function()
                    return clock
                end,
                present = function()
                    return players
                end,
                reward = function(completion: SharedObjective.Completion): boolean
                    table.insert(paid, completion.userId)
                    return completion.userId ~= 20
                end,
                onCompleted = function(_completions)
                    completedCalls += 1
                end,
                onError = function(message: string)
                    table.insert(errors, message)
                end,
            })
            harness.equal(attributes.ObjPhase, "waiting")
            harness.equal(attributes.ObjBeat, "idle")
            runtime:step()
            local settled = writes
            runtime:step()
            harness.equal(writes, settled, "unchanged values are not written again")

            clock += config.intervalSeconds
            harness.equal(kinds(runtime:step()), "opened")
            harness.equal(attributes.ObjBeat, "buildup")
            harness.equal(attributes.ObjTarget, config.unitsPerPlayer * 2)

            local counted = 0
            for _ = 1, 60 do
                clock += 1
                counted += runtime:contribute(10, 8) + runtime:contribute(20, 8)
                if counted >= config.unitsPerPlayer * 2 then
                    break
                end
                runtime:step()
            end
            harness.equal(kinds(runtime:step()), "completed")
            harness.equal(#paid, 2)
            harness.equal(#errors, 1)
            harness.isTrue(string.find(errors[1], "20", 1, true) ~= nil, "the error names the user")
            harness.equal(completedCalls, 1)
            harness.equal(attributes.ObjBeat, "drop")
            harness.equal(attributes.ObjCompleted, 1)
            harness.equal(runtime:view().completed, 1)
        end
    )

    suite:test("the runtime works without an onCompleted hook", function()
        local clock = 0
        local published = 0
        local runtime = ObjectiveRuntime.new({
            config = config,
            publisher = {
                publish = function(_self, _view)
                    published += 1
                end,
            },
            now = function()
                return clock
            end,
            present = function()
                return { 1 }
            end,
            reward = function(_completion)
                return true
            end,
            onCompleted = nil,
            onError = function(_message) end,
        })
        clock = config.intervalSeconds
        runtime:step()
        for _ = 1, 20 do
            clock += 1
            runtime:contribute(1, 8)
        end
        harness.equal(kinds(runtime:step()), "completed")
        harness.isTrue(published >= 3, "published on construction and on each step")
    end)
end
