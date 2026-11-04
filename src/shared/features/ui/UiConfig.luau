--!strict
--[[
    Typed config of the UI kit (design tokens, menus, texts) and its validation. Pure: loads
    under Lune. The tokens are DERIVED for this template and each value is justified in
    docs/design/DESIGN.md; a game overrides them in Config.default.ui. Presenters read only these
    tokens: no color, size, font or text literal lives in a presenter.

    Units: "points" are design units at UIScale 1. The root UIScale (Layout.scaleFor) turns them
    into pixels for the screen, so a point is not a fixed pixel size.
]]

local Contrast = require("./Contrast")
local RewardConfig = require("../rewards/RewardConfig")

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
}

export type Theme = {
    -- "Studded" variant: square corners and a heavier outline. Differs from Plain by tokens only.
    studs: boolean,
    palette: Palette,
    -- Corner radius and outline thickness, in points.
    radius: number,
    strokeThickness: number,
    -- Gaps, in points.
    spacing: { sm: number, md: number, lg: number },
    -- Text sizes, in points.
    textSize: { caption: number, body: number, title: number },
    -- Name of an Enum.Font member.
    font: string,
    -- Button height in points at UIScale 1; raised by Layout when the screen would make it small.
    buttonHeight: number,
    -- Smallest touch target in screen pixels (44 pt rule).
    touchTargetMin: number,
    -- Design viewport (the small phone) the UIScale is computed against, in pixels.
    reference: { shortSide: number, longSide: number },
    -- Limits of the UIScale factor.
    scale: { min: number, max: number },
    -- Open/close transition length in seconds.
    motionSeconds: number,
    -- Modal panel: share of the screen it takes, and its widest size in points (tablets, 1080p).
    panel: { widthScale: number, heightScale: number, maxWidthPoints: number },
}

export type Input = {
    -- Closes the open menu (Enum.KeyCode member names).
    backKey: string,
    backPad: string,
}

export type Settings = {
    -- Percent added or removed by one press of a volume stepper.
    volumeStep: number,
    -- The client sends the volume once the player stops pressing for this long (budgeted remote).
    sendDebounceSeconds: number,
}

export type MenuConfig = {
    id: string,
    title: string,
    -- A modal menu closes the other modal menus when it opens.
    modal: boolean,
    -- Keyboard key and gamepad button names (Enum.KeyCode members) that toggle the menu.
    toggleKey: string?,
    togglePad: string?,
}

export type Strings = {
    close: string,
    buy: string,
    pricePending: string,
    priceUnavailable: string,
    claimDaily: string,
    giftReady: string,
    volumeMusic: string,
    volumeSfx: string,
    boardEmpty: string,
    joinCommunity: string,
    checkAgain: string,
    coinsLabel: string,
}

export type UiConfig = {
    theme: Theme,
    menus: { MenuConfig },
    strings: Strings,
    input: Input,
    settings: Settings,
}

local UiConfigModule = {}

-- Menus every kit must define: the HUD and the four screens a game configures.
UiConfigModule.REQUIRED_MENUS = { "hud", "shop", "rewards", "settings", "boards" } :: { string }

local PALETTE_KEYS = {
    "background",
    "surface",
    "surfaceRaised",
    "textPrimary",
    "textMuted",
    "accent",
    "onAccent",
    "success",
    "warning",
    "danger",
    "focus",
}

local STRING_KEYS = {
    "close",
    "buy",
    "pricePending",
    "priceUnavailable",
    "claimDaily",
    "giftReady",
    "volumeMusic",
    "volumeSfx",
    "boardEmpty",
    "joinCommunity",
    "checkAgain",
    "coinsLabel",
}

-- Smallest readable text on a phone, in points (chosen, not sourced).
local MIN_BODY_POINTS = 14
local MIN_CAPTION_POINTS = 11
-- The touch target floor from the project rule (~/.claude/rules/luau.md).
local TOUCH_TARGET_FLOOR = 44

local function paletteMap(palette: Palette): { [string]: string }
    return {
        background = palette.background,
        surface = palette.surface,
        surfaceRaised = palette.surfaceRaised,
        textPrimary = palette.textPrimary,
        textMuted = palette.textMuted,
        accent = palette.accent,
        onAccent = palette.onAccent,
        success = palette.success,
        warning = palette.warning,
        danger = palette.danger,
        focus = palette.focus,
    }
end

local function stringsMap(strings: Strings): { [string]: string }
    return {
        close = strings.close,
        buy = strings.buy,
        pricePending = strings.pricePending,
        priceUnavailable = strings.priceUnavailable,
        claimDaily = strings.claimDaily,
        giftReady = strings.giftReady,
        volumeMusic = strings.volumeMusic,
        volumeSfx = strings.volumeSfx,
        boardEmpty = strings.boardEmpty,
        joinCommunity = strings.joinCommunity,
        checkAgain = strings.checkAgain,
        coinsLabel = strings.coinsLabel,
    }
end

local function checkPair(
    palette: { [string]: string },
    foreground: string,
    background: string,
    minimum: number,
    problems: { string }
)
    local fg = palette[foreground]
    local bg = palette[background]
    local ratio = Contrast.ratio(fg, bg)
    if ratio ~= nil and ratio < minimum then
        table.insert(
            problems,
            `ui.theme contrast {foreground} on {background} is {string.format("%.2f", ratio)}, needs {minimum}`
        )
    end
end

local function validatePalette(source: Palette, problems: { string })
    local palette = paletteMap(source)
    local valid = true
    for _, key in PALETTE_KEYS do
        local value = palette[key]
        if type(value) ~= "string" or not Contrast.isHex(value) then
            table.insert(problems, `ui.theme.palette.{key} must be "#RRGGBB"`)
            valid = false
        end
    end
    if not valid then
        return
    end
    checkPair(palette, "textPrimary", "background", Contrast.AA_TEXT, problems)
    checkPair(palette, "textPrimary", "surface", Contrast.AA_TEXT, problems)
    checkPair(palette, "textPrimary", "surfaceRaised", Contrast.AA_TEXT, problems)
    checkPair(palette, "textMuted", "surface", Contrast.AA_TEXT, problems)
    checkPair(palette, "onAccent", "accent", Contrast.AA_TEXT, problems)
    checkPair(palette, "focus", "surface", Contrast.AA_UI, problems)
    checkPair(palette, "accent", "surface", Contrast.AA_UI, problems)
    for _, status in { "success", "warning", "danger" } do
        checkPair(palette, status, "surface", Contrast.AA_UI, problems)
    end
end

local function validateTheme(theme: Theme, problems: { string })
    validatePalette(theme.palette, problems)
    if not RewardConfig.isFinite(theme.radius) or theme.radius < 0 then
        table.insert(problems, "ui.theme.radius must be zero or positive")
    end
    if not RewardConfig.isFinite(theme.strokeThickness) or theme.strokeThickness < 0 then
        table.insert(problems, "ui.theme.strokeThickness must be zero or positive")
    end
    local spacing = theme.spacing
    if not (0 < spacing.sm and spacing.sm < spacing.md and spacing.md < spacing.lg) then
        table.insert(problems, "ui.theme.spacing must grow: 0 < sm < md < lg")
    end
    local text = theme.textSize
    if text.caption < MIN_CAPTION_POINTS or text.body < MIN_BODY_POINTS then
        table.insert(
            problems,
            `ui.theme.textSize needs caption >= {MIN_CAPTION_POINTS} and body >= {MIN_BODY_POINTS}`
        )
    end
    if not (text.caption <= text.body and text.body <= text.title) then
        table.insert(problems, "ui.theme.textSize must satisfy caption <= body <= title")
    end
    if theme.font == "" then
        table.insert(problems, "ui.theme.font is empty")
    end
    if not RewardConfig.isFinite(theme.buttonHeight) or theme.buttonHeight <= 0 then
        table.insert(problems, "ui.theme.buttonHeight must be positive")
    end
    if theme.touchTargetMin < TOUCH_TARGET_FLOOR then
        table.insert(problems, `ui.theme.touchTargetMin must be at least {TOUCH_TARGET_FLOOR}`)
    end
    local reference = theme.reference
    if reference.shortSide <= 0 or reference.longSide < reference.shortSide then
        table.insert(problems, "ui.theme.reference needs 0 < shortSide <= longSide")
    end
    if theme.scale.min <= 0 or theme.scale.max < theme.scale.min then
        table.insert(problems, "ui.theme.scale needs 0 < min <= max")
    end
    if not RewardConfig.isFinite(theme.motionSeconds) or theme.motionSeconds < 0 then
        table.insert(problems, "ui.theme.motionSeconds must be zero or positive")
    end
    local panel = theme.panel
    local fractions = 0 < panel.widthScale
        and panel.widthScale <= 1
        and 0 < panel.heightScale
        and panel.heightScale <= 1
    if not fractions or panel.maxWidthPoints <= 0 then
        table.insert(
            problems,
            "ui.theme.panel needs scales in (0, 1] and a positive maxWidthPoints"
        )
    end
end

--- One human-readable problem per invalid value (empty when valid).
function UiConfigModule.validate(config: UiConfig): { string }
    local problems: { string } = {}
    validateTheme(config.theme, problems)
    local seen: { [string]: boolean } = {}
    local keys: { [string]: string } = {}
    for _, menu in config.menus do
        if seen[menu.id] then
            table.insert(problems, `ui.menus declares "{menu.id}" twice`)
        end
        seen[menu.id] = true
        if menu.title == "" then
            table.insert(problems, `ui menu "{menu.id}" has no title`)
        end
        if menu.id == "hud" and menu.modal then
            table.insert(problems, 'ui menu "hud" cannot be modal')
        end
        for _, binding in { menu.toggleKey, menu.togglePad } do
            if binding ~= nil then
                if binding == "" then
                    table.insert(problems, `ui menu "{menu.id}" has an empty binding`)
                elseif keys[binding] ~= nil then
                    table.insert(
                        problems,
                        `ui menus "{keys[binding]}" and "{menu.id}" share the binding "{binding}"`
                    )
                else
                    keys[binding] = menu.id
                end
            end
        end
    end
    if config.input.backKey == "" or config.input.backPad == "" then
        table.insert(problems, "ui.input needs a backKey and a backPad")
    end
    for _, binding in { config.input.backKey, config.input.backPad } do
        if keys[binding] ~= nil then
            table.insert(
                problems,
                `ui.input back binding "{binding}" is also used by menu "{keys[binding]}"`
            )
        end
    end
    local step = config.settings.volumeStep
    if not RewardConfig.isPositiveInteger(step) or step > 100 then
        table.insert(problems, "ui.settings.volumeStep must be an integer from 1 to 100")
    end
    if
        not RewardConfig.isFinite(config.settings.sendDebounceSeconds)
        or config.settings.sendDebounceSeconds < 0
    then
        table.insert(problems, "ui.settings.sendDebounceSeconds must be zero or positive")
    end
    for _, required in UiConfigModule.REQUIRED_MENUS do
        if not seen[required] then
            table.insert(problems, `ui.menus is missing "{required}"`)
        end
    end
    local strings = stringsMap(config.strings)
    for _, key in STRING_KEYS do
        local value = strings[key]
        if type(value) ~= "string" or value == "" then
            table.insert(problems, `ui.strings.{key} is empty`)
        end
    end
    return problems
end

--- The tokens a presenter applies. The Studded variant squares the corners and thickens the
--- outline; nothing else changes, so Studded and Plain differ only by tokens.
function UiConfigModule.resolve(theme: Theme): Theme
    if not theme.studs then
        return theme
    end
    local resolved = table.clone(theme)
    resolved.radius = 0
    resolved.strokeThickness = math.max(theme.strokeThickness, 2)
    return resolved
end

return UiConfigModule
