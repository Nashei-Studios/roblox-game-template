--!strict
local Experiments = require("../../../src/shared/features/experiments/Experiments")
local Config = require("../../../src/shared/Config")
local Prop = require("../../property/Prop")
local harness = require("../../harness")

local FOUR_WAY: { Experiments.Variant } = {
    { id = "control", weight = 1 },
    { id = "a", weight = 1 },
    { id = "b", weight = 1 },
    { id = "c", weight = 1 },
}

local function countVariants(
    experimentId: string,
    variants: { Experiments.Variant },
    total: number,
    userIdOf: (index: number) -> number
): { [string]: number }
    local counts: { [string]: number } = {}
    for _, variant in variants do
        counts[variant.id] = 0
    end
    for index = 1, total do
        local id = Experiments.assign(userIdOf(index), experimentId, variants)
        counts[id] += 1
    end
    return counts
end

local function chiSquare(counts: { [string]: number }, expected: number): number
    local chi = 0
    for _, observed in counts do
        chi += (observed - expected) ^ 2 / expected
    end
    return chi
end

return function(suite: harness.Harness)
    suite:test("assign is deterministic for the same user and experiment", function()
        local first = Experiments.assign(123456, "onboarding", FOUR_WAY)
        for _ = 1, 20 do
            harness.equal(Experiments.assign(123456, "onboarding", FOUR_WAY), first, "same")
        end
    end)

    suite:test("hash32 depends on both the user and the experiment id", function()
        harness.equal(Experiments.hash32("1:onboarding"), Experiments.hash32("1:onboarding"))
        harness.isTrue(
            Experiments.hash32("1:onboarding") ~= Experiments.hash32("2:onboarding"),
            "user matters"
        )
        harness.isTrue(
            Experiments.hash32("1:onboarding") ~= Experiments.hash32("1:onboarding2"),
            "experiment matters"
        )
    end)

    suite:test("the experiment id reshuffles players (assignments are independent)", function()
        local differing = 0
        for userId = 1, 400 do
            if
                Experiments.assign(userId, "week1", FOUR_WAY)
                ~= Experiments.assign(userId, "week2", FOUR_WAY)
            then
                differing += 1
            end
        end
        -- Independent 4-way draws differ 75 % of the time.
        harness.isTrue(differing > 240 and differing < 360, `differing={differing}`)
    end)

    suite:test("equal weights are uniform: chi-square over 10000 scattered ids", function()
        local counts = countVariants("onboarding", FOUR_WAY, 10000, function(index: number)
            return index * 7919 + 1000
        end)
        -- 3 degrees of freedom: 16.27 is the p = 0.001 critical value.
        local chi = chiSquare(counts, 2500)
        harness.isTrue(chi < 16.27, `chi-square {chi}`)
    end)

    suite:test("sequential ids (the common case) are also uniform", function()
        local counts = countVariants("onboarding", FOUR_WAY, 10000, function(index: number)
            return index
        end)
        local chi = chiSquare(counts, 2500)
        harness.isTrue(chi < 16.27, `chi-square {chi}`)
    end)

    suite:test("weights shift the split proportionally", function()
        local weighted: { Experiments.Variant } = {
            { id = "control", weight = 1 },
            { id = "a", weight = 2 },
            { id = "b", weight = 1 },
        }
        local counts = countVariants("weights", weighted, 10000, function(index: number)
            return index
        end)
        harness.isTrue(math.abs(counts.control - 2500) < 250, `control {counts.control}`)
        harness.isTrue(math.abs(counts.a - 5000) < 250, `a {counts.a}`)
        harness.isTrue(math.abs(counts.b - 2500) < 250, `b {counts.b}`)
    end)

    suite:test("an inactive experiment returns the control for everyone", function()
        local experiment: Experiments.Experiment = {
            id = "onboarding",
            active = false,
            variants = FOUR_WAY,
        }
        for userId = 1, 500 do
            harness.equal(Experiments.resolve(userId, experiment), "control", "control")
        end
        experiment.active = true
        local seenOther = false
        for userId = 1, 500 do
            if Experiments.resolve(userId, experiment) ~= "control" then
                seenOther = true
            end
        end
        harness.isTrue(seenOther, "an active experiment spreads players")
    end)

    suite:test("resolveAll covers every declared experiment", function()
        local all = Experiments.resolveAll(42, {
            { id = "one", active = true, variants = FOUR_WAY },
            { id = "two", active = false, variants = FOUR_WAY },
        })
        harness.isTrue(all.one ~= nil, "one")
        harness.equal(all.two, "control", "two inactive")
    end)

    suite:test("the template default config is valid and starts inactive", function()
        local experiments = Config.default.experiments
        harness.isTrue(experiments ~= nil, "declared")
        if experiments ~= nil then
            harness.equal(#Experiments.validate(experiments), 0, "valid")
            for _, experiment in experiments.definitions do
                harness.isFalse(experiment.active, "off until a game enables it")
            end
        end
    end)

    suite:test("labels and attribute names", function()
        harness.equal(Experiments.eventLabel("onboarding", "a"), "onboarding:a")
        harness.equal(Experiments.attributeName("onboarding"), "Experiment_onboarding")
    end)

    suite:test("validate accepts a good config and names every problem in a bad one", function()
        harness.equal(#Experiments.validate({
            funnelExperimentId = "x",
            definitions = { { id = "x", active = true, variants = FOUR_WAY } },
        }), 0, "valid")
        local problems = Experiments.validate({
            funnelExperimentId = "missing",
            definitions = {
                { id = "x", active = true, variants = {} },
                { id = "x", active = true, variants = { { id = "a", weight = 0 } } },
                {
                    id = "y",
                    active = true,
                    variants = { { id = "a", weight = 1 }, { id = "a", weight = 0 / 0 } },
                },
            },
        })
        harness.isTrue(#problems >= 5, `problems={#problems}`)
    end)

    suite:test("property: assign returns a declared variant and repeats", function()
        local gen = Prop.pair(Prop.integer(1, 2 ^ 40), Prop.integer(1, 8))
        Prop.check("assign returns a declared variant", gen, function(input)
            local variants: { Experiments.Variant } = {}
            for index = 1, input.b do
                table.insert(variants, { id = `v{index}`, weight = index })
            end
            local id = Experiments.assign(input.a, "prop", variants)
            local found = false
            for _, variant in variants do
                if variant.id == id then
                    found = true
                end
            end
            harness.isTrue(found, `{id} is declared`)
            harness.equal(Experiments.assign(input.a, "prop", variants), id, "deterministic")
        end)
    end)

    suite:test("property: bucket stays in [0, 1) and a single variant always wins", function()
        Prop.check("bucket range", Prop.integer(0, 2 ^ 50), function(userId: number)
            local bucket = Experiments.bucket(userId, "prop")
            harness.isTrue(bucket >= 0 and bucket < 1, `bucket {bucket}`)
            harness.equal(
                Experiments.assign(userId, "prop", { { id = "only", weight = 3 } }),
                "only",
                "single variant"
            )
        end)
    end)
end
