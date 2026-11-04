--!strict
--[[
    WCAG 2.x contrast ratio between two "#RRGGBB" colors. Pure: loads under Lune. The theme
    validation uses it so contrast is verified against AA (4.5 for text, 3 for UI parts), never
    assumed.
]]

local Contrast = {}

local function channel(hex: string, from: number): number?
    local value = tonumber(string.sub(hex, from, from + 1), 16)
    if value == nil then
        return nil
    end
    local unit = value / 255
    if unit <= 0.03928 then
        return unit / 12.92
    end
    return ((unit + 0.055) / 1.055) ^ 2.4
end

--- True for "#RRGGBB".
function Contrast.isHex(hex: string): boolean
    return string.match(hex, "^#%x%x%x%x%x%x$") ~= nil
end

--- Relative luminance 0..1, or nil when `hex` is not "#RRGGBB".
function Contrast.luminance(hex: string): number?
    if not Contrast.isHex(hex) then
        return nil
    end
    local red, green, blue = channel(hex, 2), channel(hex, 4), channel(hex, 6)
    if red == nil or green == nil or blue == nil then
        return nil
    end
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
end

--- Contrast ratio 1..21 between two colors, or nil when either is not "#RRGGBB".
function Contrast.ratio(first: string, second: string): number?
    local a, b = Contrast.luminance(first), Contrast.luminance(second)
    if a == nil or b == nil then
        return nil
    end
    local lighter, darker = math.max(a, b), math.min(a, b)
    return (lighter + 0.05) / (darker + 0.05)
end

--- WCAG AA minimum for normal text.
Contrast.AA_TEXT = 4.5
--- WCAG AA minimum for UI components and large text.
Contrast.AA_UI = 3

return Contrast
