--!strict
--[[
    Port: where the model of a tier comes from (ADR 0057). Implementations live in
    features/tiermodels/TierModelSources: a procedural recipe built from parts, a lookup of kit
    Packages or ReplicatedStorage models by name, and a chain that tries them in order. Pure data
    in, pure data out, so it loads under Lune; the engine only appears in the rig that draws it.
]]

export type PartShape = "block" | "wedge" | "ball" | "cylinder"

-- Which color of the tier a part takes: the body, the veins and trim, or the glowing ore.
export type ColorRole = "primary" | "accent" | "glow"

export type Vec3 = { x: number, y: number, z: number }

-- One part of a model, in studs, relative to the node origin (the center of the base).
export type PartSpec = {
    shape: PartShape,
    size: Vec3,
    offset: Vec3,
    yawDeg: number,
    pitchDeg: number,
    rollDeg: number,
    role: ColorRole,
}

-- An engine model (kit Package or ReplicatedStorage) that the rig clones once and then reuses.
export type TemplateRef = {
    name: string,
    -- Where it was found, for the report: "kit" or "replicated".
    origin: string,
    partCount: number,
    triangles: number,
}

export type Model = {
    -- "recipe", "kit" or "replicated".
    origin: string,
    -- The silhouette of the model as parts. For a template these are bounding proxies that the
    -- validator rasterizes; for a recipe they ARE the model.
    parts: { PartSpec },
    template: TemplateRef?,
}

export type SourceError = {
    kind: "unknown_tier" | "missing_model",
    message: string,
}

export type ResolveResult = { ok: true, value: Model } | { ok: false, error: SourceError }

export type TierModelSource = {
    resolve: (self: TierModelSource, tierId: string) -> ResolveResult,
}

return {}
