--!strict
--[[
    Pure layout math of the UI kit: the UIScale factor and the touch-target floor. Loads under
    Lune. Presenters size panels with UDim2 scale and use these numbers for the root UIScale and
    button heights, so nothing is a fixed pixel size and a button is never under the 44 pt floor.
]]

local UiConfig = require("./UiConfig")

local Layout = {}

--- The UIScale factor for a viewport (pixels). Portrait and landscape give the same factor:
--- the short side is compared with the short side of the design viewport.
function Layout.scaleFor(
    viewportWidth: number,
    viewportHeight: number,
    theme: UiConfig.Theme
): number
    local short = math.min(viewportWidth, viewportHeight)
    local long = math.max(viewportWidth, viewportHeight)
    if short <= 0 then
        return theme.scale.min
    end
    local factor = math.min(short / theme.reference.shortSide, long / theme.reference.longSide)
    return math.clamp(factor, theme.scale.min, theme.scale.max)
end

--- Button height in points for a UIScale factor: the token, raised so that the button is at
--- least `touchTargetMin` pixels tall on screen.
function Layout.buttonHeight(theme: UiConfig.Theme, uiScale: number): number
    if uiScale <= 0 then
        return theme.buttonHeight
    end
    return math.max(theme.buttonHeight, theme.touchTargetMin / uiScale)
end

--- True when a control of `points` design points is a valid touch target at `uiScale`.
function Layout.isTouchTarget(points: number, uiScale: number, theme: UiConfig.Theme): boolean
    return points * uiScale >= theme.touchTargetMin
end

return Layout
