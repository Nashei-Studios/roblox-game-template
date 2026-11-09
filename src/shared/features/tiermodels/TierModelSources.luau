--!strict
--[[
    Implementations of the TierModelSource port (ADR 0057), all pure so they load under Lune:
    - recipes: the procedural fallback, a model built from the tier's own parts. Always answers
      for a known tier, so a missing kit never leaves a node empty.
    - templates: a kit Package or ReplicatedStorage model preferred by name. It asks an injected
      `find` (the engine lookup lives in the rig's finder) and answers `missing_model` when the
      tier names no template or the template is not there.
    - chain: tries sources in order and answers the first success; the last error otherwise.
    - registry: an in-memory `find`, for tests and for a one-client Studio seed.
]]

local TierModelConfig = require("./TierModelConfig")
local TierModelSource = require("../../ports/TierModelSource")

export type TierModelSource = TierModelSource.TierModelSource
export type Model = TierModelSource.Model

-- What `find` answers for a template name: its size, so the budget can be checked without cloning.
export type TemplateInfo = { partCount: number, triangles: number }

export type Finder = (name: string) -> TemplateInfo?

local TierModelSources = {}

local function tierOf(config: TierModelConfig.Config, tierId: string): TierModelConfig.TierSpec?
    for _, tier in config.tiers do
        if tier.tierId == tierId then
            return tier
        end
    end
    return nil
end

local function unknownTier(tierId: string): TierModelSource.ResolveResult
    return {
        ok = false,
        error = { kind = "unknown_tier", message = `no tier "{tierId}" in tierModels` },
    }
end

function TierModelSources.recipes(config: TierModelConfig.Config): TierModelSource
    local source: TierModelSource = {
        resolve = function(_self: TierModelSource, tierId: string): TierModelSource.ResolveResult
            local tier = tierOf(config, tierId)
            if tier == nil then
                return unknownTier(tierId)
            end
            return { ok = true, value = { origin = "recipe", parts = tier.recipe, template = nil } }
        end,
    }
    return source
end

--- `origin` is "kit" or "replicated", reported with the model. The tier's recipe doubles as the
--- bounding proxy the silhouette check rasterizes (a template has no parts the pure core can see).
function TierModelSources.templates(
    origin: string,
    config: TierModelConfig.Config,
    find: Finder
): TierModelSource
    local source: TierModelSource = {
        resolve = function(_self: TierModelSource, tierId: string): TierModelSource.ResolveResult
            local tier = tierOf(config, tierId)
            if tier == nil then
                return unknownTier(tierId)
            end
            local name = tier.templateName
            if name == nil then
                return {
                    ok = false,
                    error = {
                        kind = "missing_model",
                        message = `tier "{tierId}" names no template`,
                    },
                }
            end
            local info = find(name)
            if info == nil then
                return {
                    ok = false,
                    error = {
                        kind = "missing_model",
                        message = `template "{name}" not found in {origin}`,
                    },
                }
            end
            return {
                ok = true,
                value = {
                    origin = origin,
                    parts = tier.recipe,
                    template = {
                        name = name,
                        origin = origin,
                        partCount = info.partCount,
                        triangles = info.triangles,
                    },
                },
            }
        end,
    }
    return source
end

function TierModelSources.chain(sources: { TierModelSource }): TierModelSource
    local source: TierModelSource = {
        resolve = function(_self: TierModelSource, tierId: string): TierModelSource.ResolveResult
            local last: TierModelSource.ResolveResult = {
                ok = false,
                error = { kind = "missing_model", message = "the chain has no sources" },
            }
            for _, candidate in sources do
                local answer = candidate:resolve(tierId)
                if answer.ok then
                    return answer
                end
                last = answer
            end
            return last
        end,
    }
    return source
end

--- A `Finder` over a table of known templates.
function TierModelSources.registry(known: { [string]: TemplateInfo }): Finder
    return function(name: string): TemplateInfo?
        return known[name]
    end
end

return TierModelSources
