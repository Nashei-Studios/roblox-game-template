--!strict
--[[
    The rarity ladder of the template: tier order, colors and the tier each effect starts at. Pure
    data plus validation, loads under Lune. Tiers are DERIVED for this template (reasons in
    docs/design/DESIGN.md, "Rarity language") and a game overrides them in `Config.default.rarity`.

    Order is the array order: index 1 is the commonest tier. Effects are a rule over that order
    ("from this tier up"), so adding a tier in the middle keeps the rules true.
]]

local Contrast = require("../ui/Contrast")

export type Tier = {
    id: string,
    -- Text shown next to the color; rarity is never carried by color alone.
    label: string,
    -- Frame, label and glow color, "#RRGGBB".
    frameHex: string,
    -- Tint of the top of the card background; the bottom stays the surface color.
    tintHex: string,
}

export type Quality = "high" | "low"

export type Config = {
    tiers: { Tier },
    -- Ids of the first tier that gets each effect (a tier id, so reordering stays safe).
    glowFrom: string,
    shimmerFrom: string,
    particlesFrom: string,
    -- Seconds one shimmer sweep takes at the high quality tier.
    shimmerPeriodSeconds: number,
    -- Particles per second of a world emitter at the high quality tier (capped by PerfBudget).
    particlesPerSecond: number,
    -- Share of the high-tier particle rate kept at the low tier; 0 drops particles entirely.
    lowQualityParticleFactor: number,
    -- Frame color of a locked card (neutral: a locked item reveals no rarity color).
    lockedFrameHex: string,
    -- Auto quality: a touch device with the Roblox graphics slider on "automatic" renders low.
    lowOnTouchWhenAuto: boolean,
    -- Roblox manual graphics levels 1..N (1 = lowest) that count as low; 0 is "automatic".
    lowGraphicsLevelMax: number,
}

local RarityConfig = {}

--- Card surface the default frames are verified against (3:1) when Config validates the ladder.
--- The template draws no UI, so this is the reference dark surface the ladder was derived on; a
--- game whose UI uses another card surface passes its own to `validate`.
RarityConfig.referenceSurfaceHex = "#171C30"

--- The default ladder. Cold to hot, like a metal heating up: slate, moss, steel blue, violet,
--- ember orange, white-hot magenta. Distinct from the UI accent (amber) and status colors.
RarityConfig.default = {
    tiers = {
        { id = "common", label = "Common", frameHex = "#9AA5B8", tintHex = "#3A4359" },
        { id = "uncommon", label = "Uncommon", frameHex = "#4FD18B", tintHex = "#1F4A3A" },
        { id = "rare", label = "Rare", frameHex = "#4D8DFF", tintHex = "#1F3C78" },
        { id = "epic", label = "Epic", frameHex = "#B26BFF", tintHex = "#4A2A78" },
        { id = "legendary", label = "Legendary", frameHex = "#FF8A3D", tintHex = "#7A3A14" },
        { id = "mythic", label = "Mythic", frameHex = "#FF4FB8", tintHex = "#7A1F5A" },
    },
    glowFrom = "uncommon", -- chosen, not sourced
    shimmerFrom = "rare", -- chosen, not sourced
    particlesFrom = "epic", -- chosen, not sourced: the brief says particles only from Epic up
    shimmerPeriodSeconds = 2.4, -- chosen, not measured
    particlesPerSecond = 10, -- chosen, not measured
    lowQualityParticleFactor = 0, -- chosen, not measured: low drops particles until a phone run says otherwise
    lockedFrameHex = "#3A4260",
    lowOnTouchWhenAuto = true, -- chosen: cheap default with a switch (see RarityFx.qualityFor)
    lowGraphicsLevelMax = 4, -- chosen, not sourced
} :: Config

--- Position of a tier in the ladder (1 = commonest), or nil when the id is unknown.
function RarityConfig.rank(config: Config, id: string): number?
    for index, tier in config.tiers do
        if tier.id == id then
            return index
        end
    end
    return nil
end

--- One problem per rule broken (empty when valid). `surfaceHex` is the card surface the frames
--- sit on; each frame color must reach the AA UI ratio against it.
function RarityConfig.validate(
    config: Config,
    surfaceHex: string,
    maxParticlesPerSecond: number
): { string }
    local problems: { string } = {}
    if #config.tiers < 2 then
        table.insert(problems, "at least two tiers are needed")
    end
    local seen: { [string]: boolean } = {}
    for _, tier in config.tiers do
        if tier.id == "" then
            table.insert(problems, "a tier has no id")
        elseif seen[tier.id] then
            table.insert(problems, `tier id "{tier.id}" is repeated`)
        end
        seen[tier.id] = true
        if tier.label == "" then
            table.insert(problems, `tier "{tier.id}" has no label`)
        end
        if not Contrast.isHex(tier.frameHex) then
            table.insert(problems, `tier "{tier.id}" frameHex must be #RRGGBB`)
        end
        if not Contrast.isHex(tier.tintHex) then
            table.insert(problems, `tier "{tier.id}" tintHex must be #RRGGBB`)
        end
        local ratio = Contrast.ratio(tier.frameHex, surfaceHex)
        if ratio ~= nil and ratio < Contrast.AA_UI then
            table.insert(problems, `tier "{tier.id}" frame is under 3:1 on the surface`)
        end
    end
    local effectStarts: { [string]: string } = {
        glowFrom = config.glowFrom,
        shimmerFrom = config.shimmerFrom,
        particlesFrom = config.particlesFrom,
    }
    for key, tierId in effectStarts do
        if RarityConfig.rank(config, tierId) == nil then
            table.insert(problems, `{key} names an unknown tier`)
        end
    end
    -- Rule from the brief: particles only from Epic up, when the ladder has an Epic tier.
    local particlesRank = RarityConfig.rank(config, config.particlesFrom)
    local epicRank = RarityConfig.rank(config, "epic")
    if particlesRank ~= nil and epicRank ~= nil and particlesRank < epicRank then
        table.insert(problems, "particlesFrom is below epic")
    end
    if config.particlesPerSecond > maxParticlesPerSecond then
        table.insert(problems, "particlesPerSecond is over the PerfBudget clientFx cap")
    end
    if config.lowQualityParticleFactor < 0 or config.lowQualityParticleFactor > 1 then
        table.insert(problems, "lowQualityParticleFactor must be between 0 and 1")
    end
    if config.shimmerPeriodSeconds <= 0 then
        table.insert(problems, "shimmerPeriodSeconds must be above 0")
    end
    if not Contrast.isHex(config.lockedFrameHex) then
        table.insert(problems, "lockedFrameHex must be #RRGGBB")
    end
    return problems
end

return RarityConfig
