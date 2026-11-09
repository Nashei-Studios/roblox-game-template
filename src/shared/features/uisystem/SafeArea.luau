--!strict
--[[
    Safe-area math of the UI system. The engine does the heavy part (ScreenGui.ScreenInsets =
    CoreUISafeInsets keeps content out of the notch, the top bar and the rounded corners); this
    module adds the margin the design wants and tells a rectangle test whether something is
    reachable. Pure: loads under Lune.
]]

export type Insets = { top: number, left: number, bottom: number, right: number }
export type Rect = { x: number, y: number, width: number, height: number }

local SafeArea = {}

--- The rectangle content may use: the viewport minus device insets minus the design margin.
--- Never returns a negative size.
function SafeArea.usable(
    viewportWidth: number,
    viewportHeight: number,
    insets: Insets,
    margin: number
): Rect
    local x = insets.left + margin
    local y = insets.top + margin
    local width = viewportWidth - insets.left - insets.right - 2 * margin
    local height = viewportHeight - insets.top - insets.bottom - 2 * margin
    return { x = x, y = y, width = math.max(width, 0), height = math.max(height, 0) }
end

--- True when `rect` lies fully inside `area` (with `tolerance` px of slack). A control that is
--- not contained is a control the player may not be able to reach.
function SafeArea.contains(area: Rect, rect: Rect, tolerance: number): boolean
    return rect.x >= area.x - tolerance
        and rect.y >= area.y - tolerance
        and rect.x + rect.width <= area.x + area.width + tolerance
        and rect.y + rect.height <= area.y + area.height + tolerance
end

--- Pixels to pull `rect` back inside `area`, per axis (0 when already inside). Used by
--- floating pieces (tooltips, toasts) so they never leave the screen.
function SafeArea.clampOffset(area: Rect, rect: Rect): (number, number)
    local dx, dy = 0, 0
    if rect.x < area.x then
        dx = area.x - rect.x
    elseif rect.x + rect.width > area.x + area.width then
        dx = area.x + area.width - (rect.x + rect.width)
    end
    if rect.y < area.y then
        dy = area.y - rect.y
    elseif rect.y + rect.height > area.y + area.height then
        dy = area.y + area.height - (rect.y + rect.height)
    end
    return dx, dy
end

return SafeArea
