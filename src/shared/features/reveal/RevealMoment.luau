--!strict
--[[
    Reveal moment: the short, skippable beat that shows an unlocked item large, with its rarity
    color, light beams, name and rarity label (ADR 0054). Pure: loads under Lune. This module owns
    the SPEC (what to draw), the clip moment DEFINITION (so the existing MomentDirector times the
    sting and the share capture) and the SESSION (a small clock that knows when the reveal ends
    and when a tap may dismiss it). The client presenter only paints.

    Rules:
    - The item look comes from ItemIcon.spec and RarityFx.spec, never a second rarity table.
    - Beams and particles scale with the tier and follow the RarityFx quality switch.
    - The reveal lasts `durationSeconds` (1.5 to 2.5) and one tap ends it early; input is blocked
      only while it shows.
    - An item that came from a random source shows its odds; the spec refuses to build without them.
]]

local PerfBudget = require("../../perf/PerfBudget")
local ItemIcon = require("../ui/ItemIcon")
local MomentDirector = require("../clipmoment/MomentDirector")
local RarityConfig = require("../rarity/RarityConfig")
local RarityFx = require("../rarity/RarityFx")
local Result = require("../../Result")

export type Config = {
    -- Seconds the reveal stays up when nobody taps. Bounded by MIN/MAX_DURATION_SECONDS.
    durationSeconds: number,
    -- Taps before this many seconds are ignored, so the tap that caused the unlock does not skip it.
    tapGuardSeconds: number,
    -- First tier id that gets beams (a tier id, so reordering the ladder stays safe).
    beamsFrom: string,
    -- Beams at the first beam tier, and extra beams per tier above it.
    baseBeams: number,
    beamsPerTier: number,
    -- Hard cap on beams at the high quality tier (also capped by PerfBudget.clientFx.maxRevealBeams).
    maxBeams: number,
    -- Share of the beams kept at the low quality tier, 0..1.
    lowQualityBeamFactor: number,
    -- Degrees per second the beam group turns.
    beamSpinDegreesPerSecond: number,
    -- Sting name handed to the music director / sound manager; nil for none.
    sting: string?,
}

export type Request = {
    item: ItemIcon.Item,
    -- Chance in percent (0, 100] when the item came from a random source; nil when it did not.
    oddsPercent: number?,
    -- True when the item came from a random source (the paid random item policy applies).
    random: boolean,
}

export type Beams = {
    count: number,
    -- Angle of each beam around the center, degrees, evenly spaced.
    anglesDegrees: { number },
    spinDegreesPerSecond: number,
}

export type Spec = {
    icon: ItemIcon.Spec,
    name: string,
    rarityLabel: string,
    rarityHex: string,
    rank: number,
    beams: Beams,
    -- Particles per second at the reveal center (from RarityFx, already quality aware).
    particlesPerSecond: number,
    glow: boolean,
    -- "12.5%" style text, nil when the item did not come from a random source.
    oddsText: string?,
    durationSeconds: number,
    tapGuardSeconds: number,
}

export type State = "pending" | "showing" | "done"

export type Session = {
    -- Starts the clock; the reveal is now blocking input.
    start: (self: Session, now: number) -> (),
    -- Advances the clock; ends the session when the duration passed. Returns the state.
    tick: (self: Session, now: number) -> State,
    -- A tap. Returns true when it ended the reveal, false when ignored (guard, not showing).
    dismiss: (self: Session, now: number) -> boolean,
    state: (self: Session) -> State,
    -- True only while the reveal shows: the presenter blocks input exactly this long.
    blocksInput: (self: Session) -> boolean,
    -- 0..1 progress of the reveal, for the presenter's easing.
    progress: (self: Session, now: number) -> number,
}

local RevealMoment = {}

RevealMoment.MIN_DURATION_SECONDS = 1.5
RevealMoment.MAX_DURATION_SECONDS = 2.5

--- Neutral defaults: 2 s, beams from Rare, up to 8 beams, half of them on a low quality device.
function RevealMoment.defaults(): Config
    return {
        durationSeconds = 2, -- chosen, not measured: inside the 1.5 to 2.5 s the brief asks for
        tapGuardSeconds = 0.25, -- chosen, not measured: longer than a double tap
        beamsFrom = "rare", -- chosen, not sourced
        baseBeams = 4, -- chosen, not sourced
        beamsPerTier = 2, -- chosen, not sourced
        maxBeams = 8, -- chosen, not sourced
        lowQualityBeamFactor = 0.5, -- chosen, not measured
        beamSpinDegreesPerSecond = 40, -- chosen, not measured
        sting = nil,
    }
end

--- One human-readable problem per invalid value (empty when valid).
function RevealMoment.validate(config: Config, rarity: RarityConfig.Config): { string }
    local problems: { string } = {}
    if
        config.durationSeconds ~= config.durationSeconds
        or config.durationSeconds < RevealMoment.MIN_DURATION_SECONDS
        or config.durationSeconds > RevealMoment.MAX_DURATION_SECONDS
    then
        table.insert(problems, "reveal.durationSeconds must be between 1.5 and 2.5")
    end
    if config.tapGuardSeconds < 0 or config.tapGuardSeconds >= config.durationSeconds then
        table.insert(problems, "reveal.tapGuardSeconds must be zero or below the duration")
    end
    if RarityConfig.rank(rarity, config.beamsFrom) == nil then
        table.insert(problems, `reveal.beamsFrom "{config.beamsFrom}" is not a rarity tier`)
    end
    if config.baseBeams < 1 or config.baseBeams % 1 ~= 0 then
        table.insert(problems, "reveal.baseBeams must be a positive integer")
    end
    if config.beamsPerTier < 0 or config.beamsPerTier % 1 ~= 0 then
        table.insert(problems, "reveal.beamsPerTier must be a non-negative integer")
    end
    local cap = if PerfBudget.clientFx ~= nil then PerfBudget.clientFx.maxRevealBeams else 0
    if config.maxBeams < 1 or config.maxBeams > cap then
        table.insert(problems, `reveal.maxBeams must be between 1 and the PerfBudget cap {cap}`)
    end
    if config.lowQualityBeamFactor < 0 or config.lowQualityBeamFactor > 1 then
        table.insert(problems, "reveal.lowQualityBeamFactor must be between 0 and 1")
    end
    if config.beamSpinDegreesPerSecond < 0 then
        table.insert(problems, "reveal.beamSpinDegreesPerSecond must be zero or positive")
    end
    return problems
end

--- Beams for a tier rank at a quality: none below `beamsFrom`, `baseBeams` at it, `beamsPerTier`
--- more per tier up, capped, and scaled down at the low quality tier.
function RevealMoment.beamCount(
    config: Config,
    rarity: RarityConfig.Config,
    rank: number,
    quality: RarityFx.Quality
): number
    local first = RarityConfig.rank(rarity, config.beamsFrom)
    if first == nil or rank < first then
        return 0
    end
    local cap = if PerfBudget.clientFx ~= nil then PerfBudget.clientFx.maxRevealBeams else 0
    local count =
        math.min(config.baseBeams + (rank - first) * config.beamsPerTier, config.maxBeams, cap)
    if quality == "low" then
        count = math.floor(count * config.lowQualityBeamFactor)
    end
    return count
end

local function beamAngles(count: number): { number }
    local angles: { number } = {}
    for index = 1, count do
        table.insert(angles, (index - 1) * 360 / count)
    end
    return angles
end

--- "12.5%" for an odds value in (0, 100]; nil outside the range.
function RevealMoment.oddsText(percent: number): string?
    if percent ~= percent or percent <= 0 or percent > 100 then
        return nil
    end
    local text = string.format("%.2f", percent)
    text = string.gsub(text, "0+$", "")
    text = string.gsub(text, "%.$", "")
    return `{text}%`
end

--- Problems with a request (empty when valid): a random source must carry visible odds.
function RevealMoment.problems(request: Request): { string }
    local problems: { string } = {}
    if request.random then
        local odds = request.oddsPercent
        if odds == nil or RevealMoment.oddsText(odds) == nil then
            table.insert(problems, "a random source needs odds in (0, 100]")
        end
    end
    return problems
end

--- The spec of one reveal, or an error string when the request breaks the odds rule.
function RevealMoment.spec(
    config: Config,
    rarity: RarityConfig.Config,
    request: Request,
    quality: RarityFx.Quality,
    surfaceHex: string
): Result.Result<Spec, string>
    local problems = RevealMoment.problems(request)
    if #problems > 0 then
        return Result.err(table.concat(problems, "; "))
    end
    local icon = ItemIcon.spec(request.item, { unlocked = true }, rarity, quality, surfaceHex, "")
    local fx = icon.fx
    local count = RevealMoment.beamCount(config, rarity, fx.rank, quality)
    local odds = request.oddsPercent
    return Result.ok({
        icon = icon,
        name = request.item.name,
        rarityLabel = fx.label,
        rarityHex = fx.frameHex,
        rank = fx.rank,
        beams = {
            count = count,
            anglesDegrees = beamAngles(count),
            spinDegreesPerSecond = config.beamSpinDegreesPerSecond,
        },
        particlesPerSecond = fx.particlesPerSecond,
        glow = fx.glow,
        oddsText = if request.random and odds ~= nil then RevealMoment.oddsText(odds) else nil,
        durationSeconds = config.durationSeconds,
        tapGuardSeconds = config.tapGuardSeconds,
    })
end

--- The clip moment the reveal registers with MomentDirector (ADR 0042): a sting at the peak and a
--- capture right after it, so the existing director times the share prompt and applies its limits.
function RevealMoment.momentDef(id: string, config: Config): MomentDirector.MomentDef
    return {
        id = id,
        kind = "reveal",
        beat = {
            sting = config.sting,
            stingLeadSeconds = 0,
            cameraKick = nil,
            slowMoScale = nil,
            slowMoSeconds = nil,
            captureAfterSeconds = math.min(0.6, config.durationSeconds / 2),
            promptAfterCaptureSeconds = 0.4,
        },
    }
end

--- A reveal session. `now` is a monotonic clock in seconds, passed in so tests control it.
function RevealMoment.session(spec: Spec): Session
    local current: State = "pending"
    local startedAt = 0

    local self = {} :: Session

    function self.start(_: Session, now: number)
        if current ~= "pending" then
            return
        end
        current = "showing"
        startedAt = now
    end

    function self.tick(_: Session, now: number): State
        if current == "showing" and now - startedAt >= spec.durationSeconds then
            current = "done"
        end
        return current
    end

    function self.dismiss(_: Session, now: number): boolean
        if current ~= "showing" or now - startedAt < spec.tapGuardSeconds then
            return false
        end
        current = "done"
        return true
    end

    function self.state(_: Session): State
        return current
    end

    function self.blocksInput(_: Session): boolean
        return current == "showing"
    end

    function self.progress(_: Session, now: number): number
        if current == "pending" then
            return 0
        end
        if current == "done" then
            return 1
        end
        return math.clamp((now - startedAt) / spec.durationSeconds, 0, 1)
    end

    return self
end

return RevealMoment
