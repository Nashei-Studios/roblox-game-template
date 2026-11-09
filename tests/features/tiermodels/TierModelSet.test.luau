--!strict
local Config = require("../../../src/shared/Config")
local PerfBudget = require("../../../src/shared/perf/PerfBudget")
local RarityConfig = require("../../../src/shared/features/rarity/RarityConfig")
local TierModelConfig = require("../../../src/shared/features/tiermodels/TierModelConfig")
local TierModelSet = require("../../../src/shared/features/tiermodels/TierModelSet")
local TierModelSource = require("../../../src/shared/ports/TierModelSource")
local TierModelSources = require("../../../src/shared/features/tiermodels/TierModelSources")
local TierPool = require("../../../src/shared/features/tiermodels/TierPool")
local TierSilhouette = require("../../../src/shared/features/tiermodels/TierSilhouette")
local harness = require("../../harness")

local RARITY = RarityConfig.default
local SURFACE = "#171C30"
local part = TierModelConfig.part

local function budget(): PerfBudget.TierModelBudget
    local found = PerfBudget.tierModels
    assert(found ~= nil, "PerfBudget.tierModels missing")
    return found
end

local function defaultConfig(): TierModelConfig.Config
    local found = Config.default.tierModels
    assert(found ~= nil, "Config.default.tierModels missing")
    return found
end

local function copyConfig(): TierModelConfig.Config
    local source = defaultConfig()
    local tiers: { TierModelConfig.TierSpec } = {}
    for _, tier in source.tiers do
        table.insert(tiers, table.clone(tier))
    end
    return { tiers = tiers, silhouette = table.clone(source.silhouette) }
end

local function newSet(
    config: TierModelConfig.Config,
    source: TierModelSource.TierModelSource?
): TierModelSet.TierModelSet
    return TierModelSet.new(config, RARITY, source or TierModelSources.recipes(config), budget())
end

local function contains(problems: { string }, needle: string): boolean
    for _, problem in problems do
        if string.find(problem, needle, 1, true) ~= nil then
            return true
        end
    end
    return false
end

return function(suite: harness.Harness)
    suite:test("the default config has no problems against the budget", function()
        local problems = TierModelConfig.problems(defaultConfig(), RARITY, budget())
        harness.equal(#problems, 0, table.concat(problems, "; "))
    end)

    suite:test("the three default tiers have distinct silhouettes in both views", function()
        local config = defaultConfig()
        local entries: { TierSilhouette.Entry } = {}
        for _, tier in config.tiers do
            table.insert(entries, { id = tier.tierId, parts = tier.recipe })
        end
        harness.equal(#TierSilhouette.duplicates(entries, config.silhouette), 0)
        -- Every pair is also well under the limit, not just under it by a hair.
        local masks: { TierSilhouette.Mask } = {}
        for _, entry in entries do
            table.insert(masks, TierSilhouette.raster(entry.parts, config.silhouette))
        end
        for first = 1, #masks do
            for second = first + 1, #masks do
                local overlap = TierSilhouette.overlap(masks[first], masks[second])
                harness.isTrue(
                    overlap < config.silhouette.maxOverlap - 0.1,
                    `{entries[first].id} vs {entries[second].id} overlap {overlap}`
                )
            end
        end
    end)

    suite:test("two tiers with the same recipe are rejected as a duplicate silhouette", function()
        local config = copyConfig()
        config.tiers[2].recipe = config.tiers[1].recipe
        local problems = TierModelConfig.problems(config, RARITY, budget())
        harness.isTrue(contains(problems, "share a silhouette"), table.concat(problems, "; "))
    end)

    suite:test("a recolored copy is still a duplicate silhouette", function()
        local config = copyConfig()
        local twin = table.clone(config.tiers[1])
        twin.tierId = "twin"
        twin.primaryHex = "#FF0000"
        table.insert(config.tiers, twin)
        local problems = TierModelConfig.problems(config, RARITY, budget())
        harness.isTrue(contains(problems, '"twin"'), table.concat(problems, "; "))
    end)

    suite:test("a scaled-up copy is distinct when it changes the silhouette enough", function()
        local config = copyConfig()
        local big: { TierModelConfig.PartSpec } = {}
        for _, spec in config.tiers[1].recipe do
            table.insert(big, {
                shape = spec.shape,
                size = { x = spec.size.x * 1.5, y = spec.size.y * 2.2, z = spec.size.z * 1.5 },
                offset = {
                    x = spec.offset.x * 1.5,
                    y = spec.offset.y * 2.2,
                    z = spec.offset.z * 1.5,
                },
                yawDeg = spec.yawDeg,
                pitchDeg = spec.pitchDeg,
                rollDeg = spec.rollDeg,
                role = spec.role,
            })
        end
        local entries: { TierSilhouette.Entry } = {
            { id = "small", parts = config.tiers[1].recipe },
            { id = "big", parts = big },
        }
        local overlap = TierSilhouette.overlap(
            TierSilhouette.raster(entries[1].parts, config.silhouette),
            TierSilhouette.raster(entries[2].parts, config.silhouette)
        )
        harness.isTrue(overlap < 1, "a bigger copy is not identical")
    end)

    suite:test("raster of an empty model is empty and two empties count as equal", function()
        local frame = defaultConfig().silhouette
        local empty = TierSilhouette.raster({}, frame)
        for _, cell in empty.front do
            harness.isFalse(cell)
        end
        harness.equal(TierSilhouette.overlap(empty, empty), 1)
    end)

    suite:test("a ball fills an ellipse, a block fills its box", function()
        local frame: TierSilhouette.Frame =
            { grid = 16, halfWidth = 8, height = 16, maxOverlap = 0.78 }
        local ball =
            TierSilhouette.raster({ part("ball", { 8, 8, 8 }, { 0, 4, 0 }, "primary") }, frame)
        local block =
            TierSilhouette.raster({ part("block", { 8, 8, 8 }, { 0, 4, 0 }, "primary") }, frame)
        local function count(cells: { boolean }): number
            local total = 0
            for _, cell in cells do
                if cell then
                    total += 1
                end
            end
            return total
        end
        harness.isTrue(count(ball.front) < count(block.front), "ellipse covers less than the box")
        harness.isTrue(count(ball.front) > 0)
    end)

    suite:test(
        "an unrotated wedge is a triangle in the side view and a box in the front",
        function()
            local frame: TierSilhouette.Frame =
                { grid = 16, halfWidth = 8, height = 16, maxOverlap = 0.78 }
            local wedge =
                TierSilhouette.raster({ part("wedge", { 8, 8, 8 }, { 0, 4, 0 }, "primary") }, frame)
            local block =
                TierSilhouette.raster({ part("block", { 8, 8, 8 }, { 0, 4, 0 }, "primary") }, frame)
            harness.equal(
                TierSilhouette.render(wedge, frame, false),
                TierSilhouette.render(block, frame, false)
            )
            harness.isTrue(
                TierSilhouette.render(wedge, frame, true)
                    ~= TierSilhouette.render(block, frame, true)
            )
        end
    )

    suite:test("a rolled spike leans: its front silhouette moves sideways", function()
        local frame: TierSilhouette.Frame =
            { grid = 16, halfWidth = 8, height = 16, maxOverlap = 0.78 }
        local straight =
            TierSilhouette.raster({ part("block", { 2, 12, 2 }, { 0, 6, 0 }, "glow") }, frame)
        local leaning = TierSilhouette.raster(
            { part("block", { 2, 12, 2 }, { 0, 6, 0 }, "glow", { 0, 0, 30 }) },
            frame
        )
        harness.isTrue(TierSilhouette.overlap(straight, leaning) < 1)
    end)

    suite:test("leaning thin spikes keep their gaps instead of filling a rectangle", function()
        local frame: TierSilhouette.Frame =
            { grid = 24, halfWidth = 12, height = 16, maxOverlap = 0.78 }
        local spikes: { TierModelConfig.PartSpec } = {}
        for index = -1, 1 do
            table.insert(
                spikes,
                part(
                    "block",
                    { 1.2, 10, 1.2 },
                    { index * 6, 5, 0 },
                    "primary",
                    { 0, 0, index * 25 }
                )
            )
        end
        local mask = TierSilhouette.raster(spikes, frame)
        local filled = 0
        for _, cell in mask.front do
            if cell then
                filled += 1
            end
        end
        -- Three thin spikes cover well under a third of their own bounding rectangle.
        harness.isTrue(filled < 24 * 10 * 0.3, `filled {filled} cells`)
    end)

    suite:test("problems reports bad ids, hex, rarity, sizes and budgets", function()
        local config = copyConfig()
        config.tiers[1].primaryHex = "red"
        config.tiers[2].rarityId = "nope"
        config.tiers[3].recipe = {}
        local first = config.tiers[2]
        first.tierId = config.tiers[1].tierId
        local problems = TierModelConfig.problems(config, RARITY, budget())
        harness.isTrue(contains(problems, 'must be "#RRGGBB"'))
        harness.isTrue(contains(problems, "unknown rarityId"))
        harness.isTrue(contains(problems, "empty recipe"))
        harness.isTrue(contains(problems, "listed twice"))
    end)

    suite:test("problems flags a non positive size and a recipe over the part budget", function()
        local config = copyConfig()
        config.tiers[1].recipe = { part("block", { 0, 1, 1 }, { 0, 0, 0 }, "primary") }
        local many: { TierModelConfig.PartSpec } = {}
        for index = 1, budget().maxPartsPerNode + 1 do
            table.insert(many, part("block", { 1, 1, 1 }, { index, 0, 0 }, "primary"))
        end
        config.tiers[2].recipe = many
        local problems = TierModelConfig.problems(config, RARITY, budget())
        harness.isTrue(contains(problems, "positive finite size"))
        harness.isTrue(contains(problems, "over the budget of"))
    end)

    suite:test("problems flags triangles over budget", function()
        local config = copyConfig()
        local balls: { TierModelConfig.PartSpec } = {}
        for index = 1, 6 do
            table.insert(balls, part("ball", { 2, 2, 2 }, { index * 2, 1, 0 }, "primary"))
        end
        config.tiers[1].recipe = balls
        harness.isTrue(contains(TierModelConfig.problems(config, RARITY, budget()), "triangles"))
    end)

    suite:test("problems flags a bad silhouette frame", function()
        local config = copyConfig()
        config.silhouette = { grid = 2, halfWidth = 0, height = -1, maxOverlap = 2 }
        local problems = TierModelConfig.problems(config, RARITY, budget())
        harness.isTrue(contains(problems, "grid"))
        harness.isTrue(contains(problems, "halfWidth"))
        harness.isTrue(contains(problems, "height"))
        harness.isTrue(contains(problems, "maxOverlap"))
    end)

    suite:test("look returns the recipe parts with colors resolved from the tier", function()
        local config = defaultConfig()
        local set = newSet(config)
        local answer = set:look("rare", "high", SURFACE)
        assert(answer.ok, "look failed")
        local look = answer.value
        harness.equal(look.origin, "recipe")
        harness.equal(look.material, "Glass")
        harness.equal(look.partCount, #config.tiers[2].recipe)
        local spike = look.parts[2]
        harness.equal(spike.role, "glow")
        harness.equal(spike.colorHex, config.tiers[2].glowHex)
        harness.equal(look.parts[1].colorHex, config.tiers[2].accentHex)
        harness.equal(look.demand.block, 4)
    end)

    suite:test("look inherits the rarity effects and drops them at low quality", function()
        local set = newSet(defaultConfig())
        local high = set:look("epic", "high", SURFACE)
        local low = set:look("epic", "low", SURFACE)
        assert(high.ok and low.ok, "look failed")
        local highFx, lowFx = high.value.fx, low.value.fx
        assert(highFx ~= nil and lowFx ~= nil, "epic names a rarity")
        harness.isTrue(highFx.particlesPerSecond > lowFx.particlesPerSecond)
        harness.equal(highFx.id, "epic")
        local common = set:look("common", "high", SURFACE)
        assert(common.ok, "look failed")
        local commonFx = common.value.fx
        assert(commonFx ~= nil, "common names a rarity")
        harness.isFalse(commonFx.glow)
    end)

    suite:test("a tier without a rarityId has no fx", function()
        local config = copyConfig()
        config.tiers[1].rarityId = nil
        local answer = newSet(config):look("common", "high", SURFACE)
        assert(answer.ok, "look failed")
        harness.equal(answer.value.fx, nil)
    end)

    suite:test("an unknown tier is a value, not a throw", function()
        local answer = newSet(defaultConfig()):look("ghost", "high", SURFACE)
        harness.isFalse(answer.ok)
        if not answer.ok then
            harness.equal(answer.error.kind, "unknown_tier")
        end
    end)

    suite:test("the chain prefers a template, then falls back to the recipe", function()
        local config = copyConfig()
        config.tiers[2].templateName = "KitCrystal"
        config.tiers[3].templateName = "MissingCluster"
        local finder =
            TierModelSources.registry({ KitCrystal = { partCount = 3, triangles = 300 } })
        local chain = TierModelSources.chain({
            TierModelSources.templates("kit", config, finder),
            TierModelSources.recipes(config),
        })
        local set = newSet(config, chain)

        local crystal = set:look("rare", "high", SURFACE)
        assert(crystal.ok, "look failed")
        harness.equal(crystal.value.origin, "kit")
        harness.equal(crystal.value.partCount, 3)
        harness.equal(#crystal.value.parts, 0)
        local ref = crystal.value.template
        assert(ref ~= nil, "a template ref")
        harness.equal(ref.name, "KitCrystal")

        local cluster = set:look("epic", "high", SURFACE)
        assert(cluster.ok, "look failed")
        harness.equal(cluster.value.origin, "recipe")
        harness.isTrue(#cluster.value.parts > 0)

        local boulder = set:look("common", "high", SURFACE)
        assert(boulder.ok, "look failed")
        harness.equal(boulder.value.origin, "recipe")
    end)

    suite:test(
        "a template alone reports missing_model; the chain reports the last error",
        function()
            local config = copyConfig()
            config.tiers[1].templateName = "Nope"
            local finder = TierModelSources.registry({})
            local alone = TierModelSources.templates("replicated", config, finder)
            local answer = alone:resolve("common")
            harness.isFalse(answer.ok)
            if not answer.ok then
                harness.equal(answer.error.kind, "missing_model")
            end
            local noTemplate = alone:resolve("rare")
            harness.isFalse(noTemplate.ok)
            harness.isFalse(TierModelSources.chain({}):resolve("common").ok)
            local unknown = alone:resolve("ghost")
            if not unknown.ok then
                harness.equal(unknown.error.kind, "unknown_tier")
            end
        end
    )

    suite:test("a template over the budget is refused", function()
        local config = copyConfig()
        config.tiers[1].templateName = "Heavy"
        local finder = TierModelSources.registry({ Heavy = { partCount = 5, triangles = 99999 } })
        local set = newSet(config, TierModelSources.templates("kit", config, finder))
        local answer = set:look("common", "high", SURFACE)
        harness.isFalse(answer.ok)
        if not answer.ok then
            harness.equal(answer.error.kind, "over_budget")
        end
    end)

    suite:test("tierIds keeps the config order", function()
        local ids = newSet(defaultConfig()):tierIds()
        harness.equal(table.concat(ids, ","), "common,rare,epic")
    end)

    suite:test("the pool is sized by the largest demand per shape", function()
        local set = newSet(defaultConfig())
        local capacity = set:poolCapacity()
        harness.equal(capacity.ball, 3)
        harness.equal(capacity.block, 4)
        harness.equal(capacity.wedge, 1)
    end)

    suite:test("swapping tiers builds nothing new and hides exactly the leftovers", function()
        local set = newSet(defaultConfig())
        local pool = set:newPool()
        local built = pool:created()
        harness.equal(built, 8)
        local ids = set:tierIds()
        for round = 1, 30 do
            local id = ids[(round % #ids) + 1]
            local answer = set:look(id, "high", SURFACE)
            assert(answer.ok, "look failed")
            local assignment = pool:assign(answer.value.demand)
            for _ in assignment.overflow do
                error("a tier recipe overflowed the pool")
            end
        end
        harness.equal(pool:created(), built)
        harness.equal(pool:swaps(), 30)
    end)

    suite:test("assign shows the demand, hides the previous leftovers, reports overflow", function()
        local pool = TierPool.new({ block = 4, ball = 2 })
        local first = pool:assign({ block = 4, ball = 1 })
        harness.equal(first.show.block, 4)
        harness.equal(first.show.ball, 1)
        local second = pool:assign({ block = 1 })
        harness.equal(second.show.block, 1)
        harness.equal(second.hide.block, 3)
        harness.equal(second.hide.ball, 1)
        local third = pool:assign({ block = 6, wedge = 1 })
        harness.equal(third.show.block, 4)
        harness.equal(third.overflow.block, 2)
        harness.equal(third.overflow.wedge, 1)
        harness.equal(pool:created(), 6)
    end)

    suite:test("capacityFor takes the maximum per shape", function()
        local capacity = TierPool.capacityFor({ { block = 2, ball = 5 }, { block = 7 } })
        harness.equal(capacity.block, 7)
        harness.equal(capacity.ball, 5)
    end)

    suite:test("cost counts parts and the triangle upper bound by shape", function()
        local parts, triangles = TierModelConfig.cost({
            part("block", { 1, 1, 1 }, { 0, 0, 0 }, "primary"),
            part("ball", { 1, 1, 1 }, { 0, 0, 0 }, "primary"),
        })
        harness.equal(parts, 2)
        harness.equal(triangles, TierModelConfig.TRIANGLES.block + TierModelConfig.TRIANGLES.ball)
    end)
end
