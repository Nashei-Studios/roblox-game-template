--!strict
--[[
    Deterministic A/B assignment (ADR 0064, vault decision 0038). Pure: loads under Lune and the
    Luau CLI. The variant is a function of (userId, experimentId) only, so it needs no
    persistence and the same player gets the same variant on every server and every session.

    Hash: 32-bit FNV-1a over "<userId>:<experimentId>", then a murmur3 finalizer so that the
    low bits are uniform (raw FNV-1a is weak there). No math.random anywhere. Luau numbers are
    doubles, so every 32-bit multiply goes through `mul32` to stay below 2^53.
]]

export type Variant = {
    id: string,
    weight: number,
}

export type Experiment = {
    id: string,
    -- Inactive experiments always resolve to the control (the first variant).
    active: boolean,
    variants: { Variant },
}

export type ExperimentsConfig = {
    -- Experiment whose variant is stamped on every funnel event.
    funnelExperimentId: string,
    definitions: { Experiment },
}

local Experiments = {}

local MODULUS = 4294967296
local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619

local function mul32(a: number, b: number): number
    local low = b % 65536
    local high = b // 65536
    return (a * low + ((a * high) % 65536) * 65536) % MODULUS
end

--- 32-bit hash of a string (FNV-1a plus murmur3 finalizer). Deterministic.
function Experiments.hash32(text: string): number
    local hash = FNV_OFFSET
    for index = 1, #text do
        hash = mul32(bit32.bxor(hash, string.byte(text, index)), FNV_PRIME)
    end
    hash = bit32.bxor(hash, bit32.rshift(hash, 16))
    hash = mul32(hash, 2246822507)
    hash = bit32.bxor(hash, bit32.rshift(hash, 13))
    hash = mul32(hash, 3266489909)
    hash = bit32.bxor(hash, bit32.rshift(hash, 16))
    return hash
end

--- Position in [0, 1) of a player inside an experiment.
function Experiments.bucket(userId: number, experimentId: string): number
    return Experiments.hash32(`{userId}:{experimentId}`) / MODULUS
end

--- The control is the first declared variant.
function Experiments.control(variants: { Variant }): string
    return variants[1].id
end

--- Variant of a player: weighted by `weight`, deterministic. `variants` must be non-empty with
--- positive weights (`Experiments.validate` checks the config).
function Experiments.assign(userId: number, experimentId: string, variants: { Variant }): string
    local total = 0
    for _, variant in variants do
        total += variant.weight
    end
    local point = Experiments.bucket(userId, experimentId) * total
    local cumulative = 0
    for _, variant in variants do
        cumulative += variant.weight
        if point < cumulative then
            return variant.id
        end
    end
    return variants[#variants].id
end

--- Variant of one experiment honoring `active`: inactive returns the control.
function Experiments.resolve(userId: number, experiment: Experiment): string
    if not experiment.active then
        return Experiments.control(experiment.variants)
    end
    return Experiments.assign(userId, experiment.id, experiment.variants)
end

--- Variant of a player in every declared experiment, keyed by experiment id.
function Experiments.resolveAll(userId: number, definitions: { Experiment }): { [string]: string }
    local result: { [string]: string } = {}
    for _, experiment in definitions do
        result[experiment.id] = Experiments.resolve(userId, experiment)
    end
    return result
end

--- Value stamped on analytics events: "<experimentId>:<variantId>".
function Experiments.eventLabel(experimentId: string, variantId: string): string
    return `{experimentId}:{variantId}`
end

--- Name of the Player attribute the client reads.
function Experiments.attributeName(experimentId: string): string
    return `Experiment_{experimentId}`
end

--- Problems with an experiments config (empty when valid).
function Experiments.validate(config: ExperimentsConfig): { string }
    local problems: { string } = {}
    local seenExperiments: { [string]: boolean } = {}
    for _, experiment in config.definitions do
        if experiment.id == "" then
            table.insert(problems, "an experiment has an empty id")
        end
        if seenExperiments[experiment.id] then
            table.insert(problems, `experiment "{experiment.id}" is declared twice`)
        end
        seenExperiments[experiment.id] = true
        if #experiment.variants == 0 then
            table.insert(problems, `experiment "{experiment.id}" has no variants`)
        end
        local seenVariants: { [string]: boolean } = {}
        for _, variant in experiment.variants do
            if variant.id == "" then
                table.insert(problems, `experiment "{experiment.id}" has a variant with no id`)
            end
            if seenVariants[variant.id] then
                table.insert(
                    problems,
                    `experiment "{experiment.id}" declares variant "{variant.id}" twice`
                )
            end
            seenVariants[variant.id] = true
            if variant.weight ~= variant.weight or variant.weight <= 0 then
                table.insert(
                    problems,
                    `experiment "{experiment.id}" variant "{variant.id}" needs a positive weight`
                )
            end
        end
    end
    if not seenExperiments[config.funnelExperimentId] then
        table.insert(
            problems,
            `funnelExperimentId "{config.funnelExperimentId}" is not a declared experiment`
        )
    end
    return problems
end

return Experiments
