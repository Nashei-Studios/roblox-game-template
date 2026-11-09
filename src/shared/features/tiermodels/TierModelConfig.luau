--!strict
--[[
    Typed config of the TierModelSet mold and its validation (ADR 0057). Pure: loads under Lune.
    A tier maps to a model (a part recipe, optionally a kit or ReplicatedStorage template), a
    material, a color set and an optional rarity id whose effects (RarityFx) the node inherits.
    The default ladder is an EXAMPLE of three distinct silhouettes (boulder, crystal, cluster);
    a game replaces it with its own biomes or tiers.
]]

local PerfBudget = require("../../perf/PerfBudget")
local RarityConfig = require("../rarity/RarityConfig")
local TierModelSource = require("../../ports/TierModelSource")
local TierSilhouette = require("./TierSilhouette")

export type PartSpec = TierModelSource.PartSpec
export type PartShape = TierModelSource.PartShape
export type ColorRole = TierModelSource.ColorRole

export type TierSpec = {
    -- Id of the game's own ladder (a biome id, a rock tier, a rarity id). Unique in the config.
    tierId: string,
    label: string,
    -- A RarityConfig tier whose glow, shimmer and particles the node inherits; nil for none.
    rarityId: string?,
    -- Enum.Material name ("Slate", "Glass", "Neon"...). The rig falls back to Slate on a typo.
    material: string,
    primaryHex: string,
    accentHex: string,
    glowHex: string,
    -- The procedural model, always present: it is the fallback of every other source.
    recipe: { PartSpec },
    -- Name of a kit Package or ReplicatedStorage model to prefer over the recipe; nil for none.
    templateName: string?,
}

export type Config = {
    tiers: { TierSpec },
    -- Silhouette check: the raster resolution and the studs it spans (see TierSilhouette).
    silhouette: TierSilhouette.Frame,
}

local TierModelConfig = {}

-- Triangles of one part by shape. Chosen, not measured: Roblox publishes no figure for the
-- primitive meshes, so these are round upper bounds used only to compare against the budget.
TierModelConfig.TRIANGLES = {
    block = 12, -- chosen, not measured
    wedge = 8, -- chosen, not measured
    cylinder = 64, -- chosen, not measured
    ball = 128, -- chosen, not measured
}

--- Readable constructor for recipes: `turn` is { yaw, pitch, roll } in degrees (default none).
function TierModelConfig.part(
    shape: PartShape,
    size: { number },
    offset: { number },
    role: ColorRole,
    turn: { number }?
): PartSpec
    local angles = turn or { 0, 0, 0 }
    return {
        shape = shape,
        size = { x = size[1], y = size[2], z = size[3] },
        offset = { x = offset[1], y = offset[2], z = offset[3] },
        yawDeg = angles[1],
        pitchDeg = angles[2],
        rollDeg = angles[3],
        role = role,
    }
end

local part = TierModelConfig.part

TierModelConfig.default = {
    tiers = {
        {
            -- A wide low dome with two satellite stones: reads as a boulder from any side.
            tierId = "common",
            label = "Boulder",
            rarityId = "common",
            material = "Slate",
            primaryHex = "#8C93A3",
            accentHex = "#5D6577",
            glowHex = "#C9CFDB",
            recipe = {
                part("ball", { 9, 6, 8 }, { 0, 2.6, 0 }, "primary"),
                part("ball", { 5, 4, 5 }, { -4.2, 1.8, 2 }, "primary"),
                part("ball", { 4, 3, 4 }, { 4.2, 1.4, -1.8 }, "accent"),
            },
            templateName = nil,
        },
        {
            -- One tall spike with two leaning crystals on a flat base: a vertical, narrow shape.
            tierId = "rare",
            label = "Crystal",
            rarityId = "rare",
            material = "Glass",
            primaryHex = "#4D8DFF",
            accentHex = "#2B4F9E",
            glowHex = "#9CC2FF",
            recipe = {
                part("block", { 6, 1, 6 }, { 0, 0.5, 0 }, "accent"),
                part("block", { 2.4, 12, 2.4 }, { 0, 6.5, 0 }, "glow", { 0, 0, 5 }),
                part("block", { 1.6, 7, 1.6 }, { 2, 4, 0.6 }, "primary", { 30, 0, -22 }),
                part("block", { 1.4, 5, 1.4 }, { -1.8, 3, 1 }, "primary", { 60, 0, 26 }),
            },
            templateName = nil,
        },
        {
            -- Five stones of different heights side by side: a wide skyline with several peaks.
            tierId = "epic",
            label = "Cluster",
            rarityId = "epic",
            material = "Slate",
            primaryHex = "#B26BFF",
            accentHex = "#6F3FB0",
            glowHex = "#E0C2FF",
            recipe = {
                part("block", { 3, 4, 3 }, { -5.5, 2, 0 }, "primary", { 15, 0, 0 }),
                part("block", { 3, 7, 3 }, { -2, 3.5, 1.2 }, "accent", { -10, 0, 0 }),
                part("block", { 3.6, 10, 3.6 }, { 2, 5, -1 }, "primary", { 25, 0, 0 }),
                part("block", { 2.6, 5.5, 2.6 }, { 5.6, 2.8, 1 }, "accent"),
                part("wedge", { 4, 3, 4 }, { 0, 1.5, -3.6 }, "primary"),
            },
            templateName = nil,
        },
    },
    silhouette = {
        grid = 24, -- chosen, not measured: coarse enough to ignore trim, fine enough to see a spike
        halfWidth = 9, -- chosen, not measured: studs on each side of the node origin
        height = 14, -- chosen, not measured: studs above the base
        maxOverlap = 0.78, -- chosen, not measured: two tiers above this read as one shape
    },
} :: Config

local function isFiniteNumber(value: number): boolean
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function validHex(hex: string): boolean
    return string.match(hex, "^#%x%x%x%x%x%x$") ~= nil
end

--- Parts of a recipe and an upper bound of its triangles.
function TierModelConfig.cost(parts: { PartSpec }): (number, number)
    local triangles = 0
    for _, spec in parts do
        triangles += TierModelConfig.TRIANGLES[spec.shape]
    end
    return #parts, triangles
end

local function partProblems(owner: string, parts: { PartSpec }, found: { string })
    for index, spec in parts do
        local size = spec.size
        if
            not isFiniteNumber(size.x)
            or not isFiniteNumber(size.y)
            or not isFiniteNumber(size.z)
            or size.x <= 0
            or size.y <= 0
            or size.z <= 0
        then
            table.insert(found, `{owner} part {index} needs a positive finite size`)
        end
        local offset = spec.offset
        if
            not isFiniteNumber(offset.x)
            or not isFiniteNumber(offset.y)
            or not isFiniteNumber(offset.z)
        then
            table.insert(found, `{owner} part {index} needs a finite offset`)
        end
        if
            not isFiniteNumber(spec.yawDeg)
            or not isFiniteNumber(spec.pitchDeg)
            or not isFiniteNumber(spec.rollDeg)
        then
            table.insert(found, `{owner} part {index} needs finite angles`)
        end
    end
end

--- One human-readable problem per invalid value (empty when valid). `budget` is
--- PerfBudget.tierModels; `rarity` is the ladder the optional rarity ids must exist in.
function TierModelConfig.problems(
    config: Config,
    rarity: RarityConfig.Config,
    budget: PerfBudget.TierModelBudget
): { string }
    local found: { string } = {}
    if #config.tiers == 0 then
        table.insert(found, "tierModels.tiers is empty")
    end
    local seen: { [string]: boolean } = {}
    for _, tier in config.tiers do
        local owner = `tier "{tier.tierId}"`
        if tier.tierId == "" then
            table.insert(found, "a tier has an empty tierId")
        elseif seen[tier.tierId] then
            table.insert(found, `{owner} is listed twice`)
        end
        seen[tier.tierId] = true
        if tier.label == "" then
            table.insert(found, `{owner} has an empty label`)
        end
        if tier.material == "" then
            table.insert(found, `{owner} has an empty material`)
        end
        local colors: { [string]: string } =
            { primaryHex = tier.primaryHex, accentHex = tier.accentHex, glowHex = tier.glowHex }
        for name, hex in colors do
            if not validHex(hex) then
                table.insert(found, `{owner} {name} must be "#RRGGBB"`)
            end
        end
        local rarityId = tier.rarityId
        if rarityId ~= nil and RarityConfig.rank(rarity, rarityId) == nil then
            table.insert(found, `{owner} has unknown rarityId "{rarityId}"`)
        end
        if tier.templateName ~= nil and tier.templateName == "" then
            table.insert(found, `{owner} has an empty templateName`)
        end
        if #tier.recipe == 0 then
            table.insert(found, `{owner} has an empty recipe`)
        end
        partProblems(owner, tier.recipe, found)
        local parts, triangles = TierModelConfig.cost(tier.recipe)
        if parts > budget.maxPartsPerNode then
            table.insert(
                found,
                `{owner} uses {parts} parts, over the budget of {budget.maxPartsPerNode}`
            )
        end
        if triangles > budget.maxTrianglesPerNode then
            table.insert(
                found,
                `{owner} uses about {triangles} triangles, over the budget of {budget.maxTrianglesPerNode}`
            )
        end
    end
    local frame = config.silhouette
    if frame.grid < 8 or frame.grid > 64 then
        table.insert(found, "tierModels.silhouette.grid must be 8 to 64")
    end
    if not isFiniteNumber(frame.halfWidth) or frame.halfWidth <= 0 then
        table.insert(found, "tierModels.silhouette.halfWidth must be positive")
    end
    if not isFiniteNumber(frame.height) or frame.height <= 0 then
        table.insert(found, "tierModels.silhouette.height must be positive")
    end
    if frame.maxOverlap <= 0 or frame.maxOverlap >= 1 then
        table.insert(found, "tierModels.silhouette.maxOverlap must be between 0 and 1")
    end
    if #found == 0 then
        local entries: { TierSilhouette.Entry } = {}
        for _, tier in config.tiers do
            table.insert(entries, { id = tier.tierId, parts = tier.recipe })
        end
        for _, clash in TierSilhouette.duplicates(entries, frame) do
            table.insert(
                found,
                `tiers "{clash.first}" and "{clash.second}" share a silhouette (overlap {string.format(
                    "%.2f",
                    clash.overlap
                )} over {frame.maxOverlap})`
            )
        end
    end
    return found
end

return TierModelConfig
