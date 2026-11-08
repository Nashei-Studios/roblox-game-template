--!strict
--[[
    Pure rectangle and color math for the runtime UI audit. No engine access, so it loads under Lune
    and is unit tested. Rectangles are in screen pixels.
]]

export type Rect = { x: number, y: number, width: number, height: number }

local Geometry = {}

--- Overlap area of two rectangles (0 when they only touch or are apart).
function Geometry.overlapArea(a: Rect, b: Rect): number
    local width = math.min(a.x + a.width, b.x + b.width) - math.max(a.x, b.x)
    local height = math.min(a.y + a.height, b.y + b.height) - math.max(a.y, b.y)
    if width <= 0 or height <= 0 then
        return 0
    end
    return width * height
end

--- True when `inner` is fully inside `outer`, allowing `tolerance` pixels of slack.
function Geometry.contains(outer: Rect, inner: Rect, tolerance: number): boolean
    return inner.x >= outer.x - tolerance
        and inner.y >= outer.y - tolerance
        and inner.x + inner.width <= outer.x + outer.width + tolerance
        and inner.y + inner.height <= outer.y + outer.height + tolerance
end

--- Visible fraction (0..1) of `inner` inside `outer`.
function Geometry.visibleFraction(outer: Rect, inner: Rect): number
    local area = inner.width * inner.height
    if area <= 0 then
        return 1
    end
    return Geometry.overlapArea(outer, inner) / area
end

--- Smallest edge-to-edge gap between two rectangles that do not overlap; 0 when they overlap.
--- Siblings in a list touch when this is under the spacing floor.
function Geometry.gap(a: Rect, b: Rect): number
    local dx = math.max(0, math.max(a.x, b.x) - math.min(a.x + a.width, b.x + b.width))
    local dy = math.max(0, math.max(a.y, b.y) - math.min(a.y + a.height, b.y + b.height))
    if dx > 0 and dy > 0 then
        return math.sqrt(dx * dx + dy * dy)
    end
    return math.max(dx, dy)
end

--- WCAG relative luminance of a 0..1 sRGB color.
function Geometry.luminance(red: number, green: number, blue: number): number
    local function channel(value: number): number
        if value <= 0.03928 then
            return value / 12.92
        end
        return ((value + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
end

--- WCAG contrast ratio between two relative luminances.
function Geometry.contrast(first: number, second: number): number
    local lighter, darker = math.max(first, second), math.min(first, second)
    return (lighter + 0.05) / (darker + 0.05)
end

return Geometry
