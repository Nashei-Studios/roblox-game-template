--!strict
--[[
    UiMotion: the motion table of the UI as pure data and pure functions (docs/adr/0063). The
    values come from section 6 of the game 2 UI spec; a game that needs another value overrides a
    preset and records why in its own ADR. Nothing here touches the engine, so it loads under
    Lune; the client driver (UiMotionPlayer) turns a resolved preset into a TweenService tween.

    Rules the table keeps (and the tests check):
    - every duration is at most 300 ms, except the result reveal (320 ms);
    - entry never eases In;
    - under reduced motion every transform becomes an opacity fade of the same duration, and a
      motion with no opacity (press, hover, counter) plays nothing or lands on the value at once.
]]

-- Easing names are Enum.EasingStyle / Enum.EasingDirection members, kept as strings so this
-- module has no engine dependency. Plain strings: the stable solver widens singleton unions.
export type Preset = {
    seconds: number,
    style: string,
    direction: string,
    -- UIScale.Scale at the start and end; nil = the motion does not scale.
    scaleFrom: number?,
    scaleTo: number?,
    -- Transparency (0 opaque, 1 invisible) at the start and end; nil = does not fade.
    fadeFrom: number?,
    fadeTo: number?,
}

local UiMotion = {}

--- Longest allowed UI tween, and the longer limit of the result reveal.
UiMotion.MAX_SECONDS = 0.3
UiMotion.MAX_REVEAL_SECONDS = 0.32

--- Names whose limit is MAX_REVEAL_SECONDS instead of MAX_SECONDS.
local REVEAL_PRESETS: { [string]: boolean } = { resultReveal = true }

--- The table of the spec (section 6). Frozen so a caller cannot change it by accident.
local PRESETS: { [string]: Preset } = {
    modalOpen = {
        seconds = 0.2,
        style = "Quart",
        direction = "Out",
        scaleFrom = 0.92,
        scaleTo = 1,
        fadeFrom = 1,
        fadeTo = 0,
    },
    modalClose = {
        seconds = 0.14,
        style = "Quart",
        direction = "Out",
        scaleFrom = 1,
        scaleTo = 0.96,
        fadeFrom = 0,
        fadeTo = 1,
    },
    scrimOpen = {
        seconds = 0.2,
        style = "Linear",
        direction = "Out",
        fadeFrom = 1,
        fadeTo = 0.6,
    },
    scrimClose = {
        seconds = 0.14,
        style = "Linear",
        direction = "Out",
        fadeFrom = 0.6,
        fadeTo = 1,
    },
    pressDown = {
        seconds = 0.09,
        style = "Quad",
        direction = "Out",
        scaleFrom = 1,
        scaleTo = 0.94,
    },
    pressUp = {
        seconds = 0.14,
        style = "Quad",
        direction = "Out",
        scaleFrom = 0.94,
        scaleTo = 1,
    },
    hoverIn = {
        seconds = 0.12,
        style = "Quad",
        direction = "Out",
        scaleFrom = 1,
        scaleTo = 1.04,
    },
    hoverOut = {
        seconds = 0.12,
        style = "Quad",
        direction = "Out",
        scaleFrom = 1.04,
        scaleTo = 1,
    },
    notificationPop = {
        seconds = 0.16,
        style = "Back",
        direction = "Out",
        scaleFrom = 0,
        scaleTo = 1,
        fadeFrom = 1,
        fadeTo = 0,
    },
    resultReveal = {
        seconds = 0.28,
        style = "Back",
        direction = "Out",
        scaleFrom = 0.7,
        scaleTo = 1,
        fadeFrom = 1,
        fadeTo = 0,
    },
    -- The counter has no transform: see countValue.
    counter = {
        seconds = 0.25,
        style = "Quad",
        direction = "Out",
    },
}
for _, preset in PRESETS do
    table.freeze(preset)
end
UiMotion.PRESETS = table.freeze(PRESETS)

--- A preset by name. Errors on an unknown name so a typo fails in the first test, not as a UI
--- that silently never animates.
function UiMotion.preset(name: string): Preset
    local found = UiMotion.PRESETS[name]
    if found == nil then
        error(`unknown UI motion preset "{name}"`, 2)
    end
    return found
end

--- The preset to play. Under reduced motion the transform is dropped and the fade is kept with
--- the same duration; a preset with no fade returns nil (nothing to play). A scale-only motion
--- such as press has no opacity to stand in, so it plays nothing.
function UiMotion.resolve(name: string, reducedMotion: boolean): Preset?
    local base = UiMotion.preset(name)
    if not reducedMotion then
        return base
    end
    if base.fadeFrom == nil or base.fadeTo == nil then
        return nil
    end
    return {
        seconds = base.seconds,
        style = "Linear",
        direction = base.direction,
        scaleFrom = nil,
        scaleTo = nil,
        fadeFrom = base.fadeFrom,
        fadeTo = base.fadeTo,
    }
end

--- Problems of the table (empty when valid): duration over the limit, entry easing In, a scale
--- without its pair, a fade outside 0..1.
function UiMotion.validate(presets: { [string]: Preset }): { string }
    local problems: { string } = {}
    for name, preset in presets do
        local limit = if REVEAL_PRESETS[name]
            then UiMotion.MAX_REVEAL_SECONDS
            else UiMotion.MAX_SECONDS
        if preset.seconds <= 0 or preset.seconds > limit then
            table.insert(problems, `{name}: seconds must be in (0, {limit}]`)
        end
        if preset.direction == "In" then
            table.insert(problems, `{name}: never ease In on a UI motion`)
        end
        if (preset.scaleFrom == nil) ~= (preset.scaleTo == nil) then
            table.insert(problems, `{name}: scaleFrom and scaleTo go together`)
        end
        if (preset.fadeFrom == nil) ~= (preset.fadeTo == nil) then
            table.insert(problems, `{name}: fadeFrom and fadeTo go together`)
        end
        for _, fade in { preset.fadeFrom, preset.fadeTo } do
            if fade ~= nil and (fade < 0 or fade > 1) then
                table.insert(problems, `{name}: transparency must be in 0..1`)
            end
        end
    end
    return problems
end

--- Quad Out easing of an alpha in 0..1 (the counter easing), clamped.
function UiMotion.easeQuadOut(alpha: number): number
    local clamped = math.clamp(alpha, 0, 1)
    return 1 - (1 - clamped) * (1 - clamped)
end

--- The number a counter shows `elapsed` seconds into a count from `from` to `to`, rounded to an
--- integer. Under reduced motion, or when `seconds` is 0, it lands on `to` at once. A caller that
--- gets a new target mid-count restarts from the value it last showed (coalescing).
function UiMotion.countValue(
    from: number,
    to: number,
    elapsed: number,
    seconds: number,
    reducedMotion: boolean
): number
    if reducedMotion or seconds <= 0 or elapsed >= seconds then
        return to
    end
    local alpha = UiMotion.easeQuadOut(elapsed / seconds)
    return math.round(from + (to - from) * alpha)
end

return UiMotion
