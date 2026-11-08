--!strict
--[[
    Responsive policy of the UI system: which device class a viewport is, the root UIScale, the
    modal menu box and the column count. Pure math, loads under Lune.

    Lessons baked in (plus-one-mining ADR 0037):
    - UIScale NEVER shrinks the UI (so the 44 px touch floor holds) and NEVER grows it on phones
      (a 1327x496 phone scaled 1.38x made the HUD cover 41 % of the screen). It only grows on
      desktop and console, where px are physically small.
    - Menus are screen fractions capped by an aspect ratio, not point sizes.
]]

local Tokens = require("./Tokens")

export type DeviceClass = Tokens.DeviceClass

export type Viewport = { width: number, height: number }

export type MenuKind = string

export type MenuBox = {
    widthScale: number,
    heightScale: number,
    aspect: number,
    -- Resulting box in px after the aspect fit.
    widthPx: number,
    heightPx: number,
}

local PHONE_SHORT_MAX = 520
local TABLET_SHORT_MAX = 820
-- Reference short side where desktop density starts to grow.
local DESKTOP_REFERENCE = 720
local DESKTOP_SCALE_MAX = 1.5
local CONSOLE_SCALE = 1.25

local Breakpoints = {}

--- The 4 viewports every component is reviewed at (stories and the runtime audit).
Breakpoints.REVIEW_VIEWPORTS = {
    { width = 844, height = 390 },
    { width = 667, height = 375 },
    { width = 1327, height = 496 },
    { width = 1920, height = 1080 },
} :: { Viewport }

--- Device class from the short side of the viewport; a console is declared by the caller
--- (GuiService:IsTenFootInterface). A 1327x496 landscape phone is a phone, 1920x1080 a desktop.
function Breakpoints.classify(viewport: Viewport, isConsole: boolean): DeviceClass
    if isConsole then
        return "console"
    end
    local short = math.min(viewport.width, viewport.height)
    if short < PHONE_SHORT_MAX then
        return "phone"
    elseif short < TABLET_SHORT_MAX then
        return "tablet"
    end
    return "desktop"
end

--- Root UIScale: 1 on phone and tablet, growing with the short side on desktop, fixed on console.
--- Never below 1 and never above DESKTOP_SCALE_MAX.
function Breakpoints.uiScale(deviceClass: DeviceClass, viewport: Viewport): number
    if deviceClass == "console" then
        return CONSOLE_SCALE
    elseif deviceClass == "desktop" then
        local short = math.min(viewport.width, viewport.height)
        return math.clamp(short / DESKTOP_REFERENCE, 1, DESKTOP_SCALE_MAX)
    end
    return 1
end

--- Margin kept from the safe area, in px (before the root UIScale divides it).
function Breakpoints.safeMargin(
    deviceClass: DeviceClass,
    viewport: Viewport,
    tokens: Tokens.Tokens
): number
    if deviceClass == "console" then
        return math.ceil(math.min(viewport.width, viewport.height) * tokens.consoleSafeShare)
    end
    return Tokens.margin(tokens, deviceClass)
end

local ASPECT_MIN: { [string]: number } = { standard = 1.1, wide = 1.0 }
local ASPECT_MAX: { [string]: number } = { standard = 2.0, wide = 3.0 }

--- The modal box: phones up to 90 x 80 %, everything else 45 x 75 % (wide menus 85 x 85 %),
--- capped by an aspect ratio so a wide window never stretches it.
function Breakpoints.menuBox(kind: MenuKind, deviceClass: DeviceClass, viewport: Viewport): MenuBox
    local width = math.max(viewport.width, 1)
    local height = math.max(viewport.height, 1)
    local fractionW, fractionH = 0.45, 0.75
    if kind == "wide" then
        fractionW, fractionH = 0.85, 0.85
    elseif deviceClass == "phone" then
        fractionW, fractionH = 0.9, 0.8
    end
    local boxW, boxH = fractionW * width, fractionH * height
    local aspect = math.clamp(boxW / boxH, ASPECT_MIN[kind], ASPECT_MAX[kind])
    if aspect < boxW / boxH then
        boxW = boxH * aspect
    else
        boxH = boxW / aspect
    end
    return {
        widthScale = fractionW,
        heightScale = fractionH,
        aspect = aspect,
        widthPx = boxW,
        heightPx = boxH,
    }
end

return Breakpoints
