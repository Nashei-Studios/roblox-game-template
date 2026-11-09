--!strict
--[[
    The rarity language as a pure spec: from a rarity id and a quality tier, the frame color, the
    label text, the background gradient and which effects run (glow, shimmer, particles). One
    source feeds the icon frame (ItemIcon) and the world effect (client/presenters/rarity), so a
    Rare looks the same on a card and on the rock. Loads under Lune; no engine calls.
]]

local RarityConfig = require("./RarityConfig")

export type Quality = RarityConfig.Quality

export type FxSpec = {
    id: string,
    rank: number,
    label: string,
    frameHex: string,
    -- Background gradient, top to bottom, "#RRGGBB".
    backgroundTopHex: string,
    backgroundBottomHex: string,
    glow: boolean,
    shimmer: boolean,
    -- Seconds per shimmer sweep (0 when there is no shimmer).
    shimmerPeriodSeconds: number,
    -- Particles per second for a world emitter (0 below the particles tier or at low quality).
    particlesPerSecond: number,
}

export type QualityInput = {
    -- "auto" follows the device; "high" and "low" are the player's switch and always win.
    setting: "auto" | "high" | "low",
    -- Roblox manual graphics level 1..10, or 0 for automatic.
    graphicsLevel: number,
    touch: boolean,
}

local RarityFx = {}

--- Quality tier to render at. The switch wins; otherwise a low manual graphics level, or a touch
--- device left on automatic (when the config says so), renders low.
function RarityFx.qualityFor(config: RarityConfig.Config, input: QualityInput): Quality
    if input.setting == "high" then
        return "high"
    end
    if input.setting == "low" then
        return "low"
    end
    if input.graphicsLevel >= 1 and input.graphicsLevel <= config.lowGraphicsLevelMax then
        return "low"
    end
    if input.graphicsLevel == 0 and input.touch and config.lowOnTouchWhenAuto then
        return "low"
    end
    return "high"
end

type Rgb = { red: number, green: number, blue: number }

local function channels(hex: string): Rgb?
    if string.match(hex, "^#%x%x%x%x%x%x$") == nil then
        return nil
    end
    local red = tonumber(string.sub(hex, 2, 3), 16)
    local green = tonumber(string.sub(hex, 4, 5), 16)
    local blue = tonumber(string.sub(hex, 6, 7), 16)
    if red == nil or green == nil or blue == nil then
        return nil
    end
    return { red = red, green = green, blue = blue }
end

--- Blend of two "#RRGGBB" colors; `amount` 0 gives `from`, 1 gives `to`. A bad hex gives `from`
--- unchanged (RarityConfig.validate reports it; a panel never crashes on it).
function RarityFx.mix(from: string, to: string, amount: number): string
    local start = channels(from)
    local finish = channels(to)
    if start == nil or finish == nil then
        return from
    end
    local t = math.clamp(amount, 0, 1)
    return string.format(
        "#%02X%02X%02X",
        math.floor(start.red + (finish.red - start.red) * t + 0.5),
        math.floor(start.green + (finish.green - start.green) * t + 0.5),
        math.floor(start.blue + (finish.blue - start.blue) * t + 0.5)
    )
end

--- The spec of a rarity at a quality tier. An unknown id falls back to the commonest tier (the
--- panel still draws; `ItemIcon.validate` reports the typo at load time).
function RarityFx.spec(
    config: RarityConfig.Config,
    rarityId: string,
    quality: Quality,
    surfaceHex: string
): FxSpec
    local rank = RarityConfig.rank(config, rarityId) or 1
    local tier = config.tiers[rank]
    local glowRank = RarityConfig.rank(config, config.glowFrom) or math.huge
    local shimmerRank = RarityConfig.rank(config, config.shimmerFrom) or math.huge
    local particlesRank = RarityConfig.rank(config, config.particlesFrom) or math.huge
    local high = quality == "high"
    local particles = 0
    if rank >= particlesRank then
        particles = if high
            then config.particlesPerSecond
            else math.floor(config.particlesPerSecond * config.lowQualityParticleFactor)
    end
    local shimmer = high and rank >= shimmerRank
    return {
        id = tier.id,
        rank = rank,
        label = tier.label,
        frameHex = tier.frameHex,
        backgroundTopHex = tier.tintHex,
        backgroundBottomHex = surfaceHex,
        glow = rank >= glowRank,
        shimmer = shimmer,
        shimmerPeriodSeconds = if shimmer then config.shimmerPeriodSeconds else 0,
        particlesPerSecond = particles,
    }
end

--- The spec of a locked card: neutral frame, no effects, a dim background. A locked item reveals
--- no rarity color (the silhouette and the lock say "not yet").
function RarityFx.lockedSpec(config: RarityConfig.Config, surfaceHex: string): FxSpec
    return {
        id = "locked",
        rank = 0,
        label = "",
        frameHex = config.lockedFrameHex,
        backgroundTopHex = RarityFx.mix(surfaceHex, "#000000", 0.35),
        backgroundBottomHex = surfaceHex,
        glow = false,
        shimmer = false,
        shimmerPeriodSeconds = 0,
        particlesPerSecond = 0,
    }
end

return RarityFx
