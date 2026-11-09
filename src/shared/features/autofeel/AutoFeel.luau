--!strict
--[[
    Feel profiles of one hit pipeline (ADR 0058). An automatic miner paid by the server looks idle
    unless it speaks the same grammar as a manual tap (swing, rock dip, chips, popup, sound) in a
    quieter voice. A profile says which channels play and how loud; `AutoFeelConfig` holds every
    number. Pure data plus `validate` and `profile`: loads under Lune, no engine services.
]]

export type Source = "manual" | "auto"
-- "observer" is how another player's auto miner looks on this client.
export type Role = "manual" | "auto" | "observer"

export type SoundVoice = {
    -- Fraction of the manual volume (0 to 1].
    volumeScale: number,
    -- Playback speed multiplier on top of the manual pitch.
    pitchShift: number,
    -- At most one auto hit sound per this many seconds.
    minGapSeconds: number,
}

export type AutoFeelConfig = {
    -- Seconds between two visible auto swings, whatever the paid rate is.
    cadenceSeconds: number,
    -- Animation weight of an auto swing (1 = the manual swing).
    swingWeight: number,
    -- Seconds the server deltas pile up before one "+N" popup.
    aggregateWindowSeconds: number,
    -- Seconds without manual input before the auto visuals come back.
    overrideSeconds: number,
    -- Studs from the rock beyond which the auto visuals pause.
    radiusStuds: number,
    -- Fractions of the manual rock dip and chip count.
    rockScale: number,
    chipScale: number,
    popupColorHex: string,
    -- Small mark drawn next to the aggregated popup, for example "AUTO".
    popupMark: string,
    sound: SoundVoice,
}

export type Popup = "perHit" | "aggregated" | "none"

export type Profile = {
    -- The character plays the swing.
    swing: boolean,
    swingWeight: number,
    -- World freeze on the animation tracks, and the camera FOV kick.
    hitStop: boolean,
    fovKick: boolean,
    -- Rock dip and chips as a fraction of the manual hit; 0 = none.
    rockScale: number,
    chipScale: number,
    popup: Popup,
    soundEnabled: boolean,
    soundVolumeScale: number,
    soundPitchShift: number,
    soundMinGapSeconds: number,
}

local AutoFeel = {}

-- Bounds of the auto cadence: under 0.5 s the swing blurs and replicates too often to other
-- players; over 0.8 s the miner no longer reads as working. Chosen, not sourced.
AutoFeel.MIN_CADENCE_SECONDS = 0.5
AutoFeel.MAX_CADENCE_SECONDS = 0.8
-- Chosen, not sourced: a popup more often than this stops being "aggregated".
AutoFeel.MIN_WINDOW_SECONDS = 0.8
AutoFeel.MAX_WINDOW_SECONDS = 2

AutoFeel.default = {
    cadenceSeconds = 0.65,
    swingWeight = 0.6,
    aggregateWindowSeconds = 1,
    overrideSeconds = 2.5,
    radiusStuds = 24,
    rockScale = 0.35,
    chipScale = 0.3,
    popupColorHex = "#7AD7FF",
    popupMark = "AUTO",
    sound = { volumeScale = 0.45, pitchShift = 0.85, minGapSeconds = 0.6 },
} :: AutoFeelConfig

local function finite(value: number): boolean
    return value == value and value ~= math.huge and value ~= -math.huge
end

--- One human-readable problem per invalid value (empty when valid).
function AutoFeel.validate(config: AutoFeelConfig): { string }
    local problems: { string } = {}
    local function check(ok: boolean, message: string)
        if not ok then
            table.insert(problems, message)
        end
    end
    check(
        finite(config.cadenceSeconds)
            and config.cadenceSeconds >= AutoFeel.MIN_CADENCE_SECONDS
            and config.cadenceSeconds <= AutoFeel.MAX_CADENCE_SECONDS,
        `autoFeel.cadenceSeconds must be from {AutoFeel.MIN_CADENCE_SECONDS} to {AutoFeel.MAX_CADENCE_SECONDS}`
    )
    check(
        config.swingWeight > 0 and config.swingWeight <= 1,
        "autoFeel.swingWeight must be in (0, 1]"
    )
    check(
        finite(config.aggregateWindowSeconds)
            and config.aggregateWindowSeconds >= AutoFeel.MIN_WINDOW_SECONDS
            and config.aggregateWindowSeconds <= AutoFeel.MAX_WINDOW_SECONDS,
        `autoFeel.aggregateWindowSeconds must be from {AutoFeel.MIN_WINDOW_SECONDS} to {AutoFeel.MAX_WINDOW_SECONDS}`
    )
    check(
        finite(config.overrideSeconds)
            and config.overrideSeconds >= 0.5
            and config.overrideSeconds <= 10,
        "autoFeel.overrideSeconds must be from 0.5 to 10"
    )
    check(
        finite(config.radiusStuds) and config.radiusStuds > 0 and config.radiusStuds <= 80,
        "autoFeel.radiusStuds must be in (0, 80]"
    )
    check(config.rockScale >= 0 and config.rockScale <= 1, "autoFeel.rockScale must be from 0 to 1")
    check(config.chipScale >= 0 and config.chipScale <= 1, "autoFeel.chipScale must be from 0 to 1")
    check(
        string.match(config.popupColorHex, "^#%x%x%x%x%x%x$") ~= nil,
        "autoFeel.popupColorHex is not #RRGGBB"
    )
    check(
        #config.popupMark >= 1 and #config.popupMark <= 6,
        "autoFeel.popupMark must be 1 to 6 characters"
    )
    check(
        config.sound.volumeScale > 0 and config.sound.volumeScale <= 1,
        "autoFeel.sound.volumeScale must be in (0, 1]"
    )
    check(
        config.sound.pitchShift >= 0.5 and config.sound.pitchShift <= 2,
        "autoFeel.sound.pitchShift must be from 0.5 to 2"
    )
    check(
        finite(config.sound.minGapSeconds) and config.sound.minGapSeconds >= 0.3,
        "autoFeel.sound.minGapSeconds must be at least 0.3"
    )
    return problems
end

--- The channels that play for `role`. Manual is the full feel and never reads the config.
function AutoFeel.profile(config: AutoFeelConfig, role: Role): Profile
    if role == "manual" then
        return {
            swing = true,
            swingWeight = 1,
            hitStop = true,
            fovKick = true,
            rockScale = 1,
            chipScale = 1,
            popup = "perHit",
            soundEnabled = true,
            soundVolumeScale = 1,
            soundPitchShift = 1,
            soundMinGapSeconds = 0,
        }
    elseif role == "auto" then
        return {
            swing = true,
            swingWeight = config.swingWeight,
            hitStop = false,
            fovKick = false,
            rockScale = config.rockScale,
            chipScale = config.chipScale,
            popup = "aggregated",
            soundEnabled = true,
            soundVolumeScale = config.sound.volumeScale,
            soundPitchShift = config.sound.pitchShift,
            soundMinGapSeconds = config.sound.minGapSeconds,
        }
    end
    -- Observer (LOD): social proof only. The swing already replicates with the character; no
    -- popup, sound, rock work or camera effect is spent on a player who is not ours.
    return {
        swing = true,
        swingWeight = config.swingWeight,
        hitStop = false,
        fovKick = false,
        rockScale = 0,
        chipScale = 0,
        popup = "none",
        soundEnabled = false,
        soundVolumeScale = 0,
        soundPitchShift = 1,
        soundMinGapSeconds = math.huge,
    }
end

--- Popups per second one auto miner spends (feeds PerfBudget.autoFeel).
function AutoFeel.popupsPerSecond(config: AutoFeelConfig): number
    return 1 / config.aggregateWindowSeconds
end

--- Swings per second one auto miner replicates to other players (one toolanim value each).
function AutoFeel.swingsPerSecond(config: AutoFeelConfig): number
    return 1 / config.cadenceSeconds
end

return AutoFeel
