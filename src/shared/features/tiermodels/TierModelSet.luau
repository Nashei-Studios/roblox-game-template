--!strict
--[[
    The TierModelSet mold (ADR 0057): from a tier id to everything a node needs to look like that
    tier. The model comes from a TierModelSource (kit Package, ReplicatedStorage model or the
    tier's own part recipe, in the order the game chains them); the material and the color set come
    from the tier's config; the rarity effects come from RarityFx, so a Rare rock glows like a
    Rare card. Pure: the engine only appears in client/presenters/world/TierModelRig, which draws a
    `Look` into a fixed pool of parts.
]]

local PerfBudget = require("../../perf/PerfBudget")
local RarityConfig = require("../rarity/RarityConfig")
local RarityFx = require("../rarity/RarityFx")
local TierModelConfig = require("./TierModelConfig")
local TierModelSource = require("../../ports/TierModelSource")
local TierPool = require("./TierPool")

export type Quality = RarityConfig.Quality
export type TemplateRef = TierModelSource.TemplateRef

-- A part of the model with its color already resolved from the tier's color set.
export type ResolvedPart = {
    shape: TierModelSource.PartShape,
    size: TierModelSource.Vec3,
    offset: TierModelSource.Vec3,
    yawDeg: number,
    pitchDeg: number,
    rollDeg: number,
    role: TierModelSource.ColorRole,
    colorHex: string,
}

export type Look = {
    tierId: string,
    label: string,
    -- "recipe", "kit" or "replicated".
    origin: string,
    -- Set when the model is an engine template the rig clones; the parts are then only its proxy.
    template: TemplateRef?,
    material: string,
    primaryHex: string,
    accentHex: string,
    glowHex: string,
    -- Parts to pose from the pool (empty for a template).
    parts: { ResolvedPart },
    -- Pool demand by shape for `parts`.
    demand: TierPool.Demand,
    -- Parts and triangles this node costs while shown.
    partCount: number,
    triangles: number,
    -- Rarity effects of the tier; nil when the tier names no rarityId.
    fx: RarityFx.FxSpec?,
}

export type LookError = {
    kind: "unknown_tier" | "missing_model" | "over_budget",
    message: string,
}

export type LookResult = { ok: true, value: Look } | { ok: false, error: LookError }

export type TierModelSet = {
    -- The look of `tierId` at a quality tier; `surfaceHex` is the background the FX blends into.
    look: (self: TierModelSet, tierId: string, quality: Quality, surfaceHex: string) -> LookResult,
    -- Tier ids in config order.
    tierIds: (self: TierModelSet) -> { string },
    -- Pool capacity that fits every tier's recipe.
    poolCapacity: (self: TierModelSet) -> TierPool.Demand,
    -- A fresh pool sized for this set.
    newPool: (self: TierModelSet) -> TierPool.TierPool,
}

local TierModelSetModule = {}

local function colorFor(spec: TierModelConfig.TierSpec, role: TierModelSource.ColorRole): string
    if role == "glow" then
        return spec.glowHex
    elseif role == "accent" then
        return spec.accentHex
    end
    return spec.primaryHex
end

local function demandOf(parts: { TierModelSource.PartSpec }): TierPool.Demand
    local demand: TierPool.Demand = {}
    for _, spec in parts do
        demand[spec.shape] = (demand[spec.shape] or 0) + 1
    end
    return demand
end

function TierModelSetModule.new(
    config: TierModelConfig.Config,
    rarity: RarityConfig.Config,
    source: TierModelSource.TierModelSource,
    budget: PerfBudget.TierModelBudget
): TierModelSet
    local byId: { [string]: TierModelConfig.TierSpec } = {}
    local order: { string } = {}
    local demands: { TierPool.Demand } = {}
    for _, tier in config.tiers do
        byId[tier.tierId] = tier
        table.insert(order, tier.tierId)
        table.insert(demands, demandOf(tier.recipe))
    end

    local set: TierModelSet
    set = {
        look = function(
            _self: TierModelSet,
            tierId: string,
            quality: Quality,
            surfaceHex: string
        ): LookResult
            local tier = byId[tierId]
            if tier == nil then
                return {
                    ok = false,
                    error = { kind = "unknown_tier", message = `no tier "{tierId}" in tierModels` },
                }
            end
            local answer = source:resolve(tierId)
            if not answer.ok then
                return { ok = false, error = answer.error }
            end
            local model = answer.value
            local template = model.template
            local parts: { ResolvedPart } = {}
            local partCount, triangles
            if template ~= nil then
                partCount, triangles = template.partCount, template.triangles
            else
                partCount, triangles = TierModelConfig.cost(model.parts)
                for _, spec in model.parts do
                    table.insert(parts, {
                        shape = spec.shape,
                        size = spec.size,
                        offset = spec.offset,
                        yawDeg = spec.yawDeg,
                        pitchDeg = spec.pitchDeg,
                        rollDeg = spec.rollDeg,
                        role = spec.role,
                        colorHex = colorFor(tier, spec.role),
                    })
                end
            end
            if partCount > budget.maxPartsPerNode or triangles > budget.maxTrianglesPerNode then
                return {
                    ok = false,
                    error = {
                        kind = "over_budget",
                        message = `tier "{tierId}" costs {partCount} parts and about {triangles} triangles, over {budget.maxPartsPerNode} and {budget.maxTrianglesPerNode}`,
                    },
                }
            end
            local fx: RarityFx.FxSpec? = nil
            if tier.rarityId ~= nil then
                fx = RarityFx.spec(rarity, tier.rarityId, quality, surfaceHex)
            end
            return {
                ok = true,
                value = {
                    tierId = tier.tierId,
                    label = tier.label,
                    origin = model.origin,
                    template = template,
                    material = tier.material,
                    primaryHex = tier.primaryHex,
                    accentHex = tier.accentHex,
                    glowHex = tier.glowHex,
                    parts = parts,
                    demand = if template ~= nil then {} else demandOf(model.parts),
                    partCount = partCount,
                    triangles = triangles,
                    fx = fx,
                },
            }
        end,
        tierIds = function(_self: TierModelSet): { string }
            return table.clone(order)
        end,
        poolCapacity = function(_self: TierModelSet): TierPool.Demand
            return TierPool.capacityFor(demands)
        end,
        newPool = function(self: TierModelSet): TierPool.TierPool
            return TierPool.new(self:poolCapacity())
        end,
    }
    return set
end

return TierModelSetModule
