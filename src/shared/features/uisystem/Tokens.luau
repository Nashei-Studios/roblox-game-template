--!strict
--[[
    Design tokens of the UI system: the ONLY place a UI number lives. Components read keys, never
    literals, so a layout rule (a gap, a padding, the 44 px floor) cannot be forgotten at a call
    site. Units are pixels at UIScale 1 (the root scale only ever grows, see Breakpoints), so the
    touch floor holds on screen.

    A new game overrides values here (docs/ui-system.md). `validate` rejects a theme that breaks a
    rule, so a bad token fails at boot or in the gate, not on a player's phone. Pure: loads under Lune.
]]

local Contrast = require("../ui/Contrast")

export type SpacingKey = "xs" | "sm" | "md" | "lg" | "xl"
export type RadiusKey = "sm" | "md" | "lg"
export type TypeKey = "caption" | "body" | "title" | "display"
export type DeviceClass = "phone" | "tablet" | "desktop" | "console"

export type Palette = {
    background: string,
    surface: string,
    surfaceRaised: string,
    textPrimary: string,
    textMuted: string,
    accent: string,
    onAccent: string,
    success: string,
    warning: string,
    danger: string,
    focus: string,
    scrim: string,
}

export type Tokens = {
    -- Spacing scale in px. Strictly growing: 0 < xs < sm < md < lg < xl.
    spacing: { [SpacingKey]: number },
    -- Corner radii in px (the Studded kit uses its own UICorner; these are for plain pieces).
    radius: { [RadiusKey]: number },
    -- Type scale in px. Growing, caption >= minText.
    type: { [TypeKey]: number },
    -- Text bounds for UITextSizeConstraint on every scaled text.
    text: { min: number, max: number },
    -- Smallest tappable edge in px.
    touchMin: number,
    -- Default token keys, so a call site that says nothing still gets spacing.
    defaults: { gap: SpacingKey, pad: SpacingKey, cardPad: SpacingKey },
    -- Margin from the safe area per device class, in px. Console is a share of the short side.
    safeMargin: { phone: number, tablet: number, desktop: number },
    consoleSafeShare: number,
    -- Menu transition seconds.
    motionSeconds: number,
    palette: Palette,
    -- Name of an Enum.Font member for plain pieces; a kit keeps its own FontFace.
    font: string,
}

local TOUCH_FLOOR = 44
local MIN_TEXT_FLOOR = 12

local TokensModule = {}

TokensModule.TOUCH_FLOOR = TOUCH_FLOOR
TokensModule.MIN_TEXT_FLOOR = MIN_TEXT_FLOOR
TokensModule.SPACING_KEYS = { "xs", "sm", "md", "lg", "xl" } :: { SpacingKey }
TokensModule.TYPE_KEYS = { "caption", "body", "title", "display" } :: { TypeKey }

--- The template defaults. Values are chosen for a 390 px tall landscape phone, then grow:
--- 4 px grid for spacing, 44 px floor, 14 px body (the smallest readable text on a phone).
function TokensModule.default(): Tokens
    return {
        spacing = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 },
        radius = { sm = 4, md = 8, lg = 12 },
        type = { caption = 12, body = 14, title = 20, display = 28 },
        text = { min = 12, max = 40 },
        touchMin = TOUCH_FLOOR,
        defaults = { gap = "sm", pad = "md", cardPad = "sm" },
        safeMargin = { phone = 8, tablet = 12, desktop = 16 },
        consoleSafeShare = 0.05,
        motionSeconds = 0.18,
        palette = {
            background = "#14161C",
            surface = "#1F232C",
            surfaceRaised = "#2A303C",
            textPrimary = "#F4F6FA",
            textMuted = "#B4BCCB",
            accent = "#F2A93B",
            onAccent = "#1A1204",
            success = "#4CC38A",
            warning = "#F2C94C",
            danger = "#EB5757",
            focus = "#7FB6FF",
            scrim = "#000000",
        },
        font = "BuilderSans",
    }
end

--- Pixels of a spacing key.
function TokensModule.space(tokens: Tokens, key: SpacingKey): number
    return tokens.spacing[key]
end

local function checkPair(
    palette: { [string]: string },
    fg: string,
    bg: string,
    minimum: number,
    problems: { string }
)
    local ratio = Contrast.ratio(palette[fg], palette[bg])
    if ratio == nil then
        table.insert(problems, `tokens.palette.{fg}/{bg} must be "#RRGGBB"`)
    elseif ratio < minimum then
        table.insert(
            problems,
            `tokens.palette contrast {fg} on {bg} is {string.format("%.2f", ratio)}, needs {minimum}`
        )
    end
end

--- One sentence per broken rule (empty when the tokens are valid).
function TokensModule.validate(tokens: Tokens): { string }
    local problems: { string } = {}
    local previous = 0
    for _, key in TokensModule.SPACING_KEYS do
        local value = tokens.spacing[key]
        if value == nil or value ~= value or value <= previous then
            table.insert(
                problems,
                `tokens.spacing must grow: 0 < xs < sm < md < lg < xl (at {key})`
            )
            break
        end
        previous = value
    end
    previous = 0
    for _, key in TokensModule.TYPE_KEYS do
        local value = tokens.type[key]
        if value == nil or value < previous then
            table.insert(
                problems,
                `tokens.type must not shrink: caption <= body <= title <= display`
            )
            break
        end
        previous = value
    end
    if tokens.type.caption < tokens.text.min then
        table.insert(problems, "tokens.type.caption must be at least tokens.text.min")
    end
    if tokens.text.min < MIN_TEXT_FLOOR or tokens.text.max < tokens.text.min then
        table.insert(problems, `tokens.text needs {MIN_TEXT_FLOOR} <= min <= max`)
    end
    if tokens.touchMin < TOUCH_FLOOR then
        table.insert(problems, `tokens.touchMin must be at least {TOUCH_FLOOR}`)
    end
    for _, key in { "gap", "pad", "cardPad" } do
        local ref = (tokens.defaults :: { [string]: SpacingKey })[key]
        if tokens.spacing[ref] == nil then
            table.insert(problems, `tokens.defaults.{key} names an unknown spacing key`)
        end
    end
    for deviceClass, margin in tokens.safeMargin :: { [string]: number } do
        if margin <= 0 then
            table.insert(problems, `tokens.safeMargin.{deviceClass} must be positive`)
        end
    end
    if tokens.consoleSafeShare <= 0 or tokens.consoleSafeShare >= 0.2 then
        table.insert(problems, "tokens.consoleSafeShare must be in (0, 0.2)")
    end
    for key, radius in tokens.radius :: { [string]: number } do
        if radius < 0 then
            table.insert(problems, `tokens.radius.{key} must be zero or positive`)
        end
    end
    local palette = tokens.palette :: { [string]: string }
    for _, pair in
        {
            { "textPrimary", "background" },
            { "textPrimary", "surface" },
            { "textMuted", "surface" },
            { "onAccent", "accent" },
        }
    do
        checkPair(palette, pair[1], pair[2], Contrast.AA_TEXT, problems)
    end
    for _, pair in { { "focus", "surface" }, { "accent", "surface" }, { "danger", "surface" } } do
        checkPair(palette, pair[1], pair[2], Contrast.AA_UI, problems)
    end
    return problems
end

return TokensModule
