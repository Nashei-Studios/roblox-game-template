--!strict
--[[
    Construction-time rules of the UI system, as pure checks. Each returns the sentence of the
    problem or nil. The engine builders call them through DevGuard and raise on a problem in
    dev mode; tests call them directly. The tree-level rules (list padding, scroller canvas, text
    fit, touch size, kit stroke) are NOT repeated here: they live in ui/audit/StaticRules and the
    builders run that same code over what they built, so there is one rule set.
]]

local Tokens = require("./Tokens")

local Contracts = {}

--- A list or grid needs a positive gap between items.
function Contracts.gap(gapPx: number, owner: string): string?
    if gapPx ~= gapPx or gapPx <= 0 then
        return `UI-LIST-PADDING {owner}: gap must be above 0 (got {gapPx})`
    end
    return nil
end

--- A tappable needs at least the touch floor on both edges, in px at the design scale.
function Contracts.touch(
    widthPx: number,
    heightPx: number,
    owner: string,
    tokens: Tokens.Tokens
): string?
    if widthPx < tokens.touchMin or heightPx < tokens.touchMin then
        return `UI-TOUCH-44 {owner}: {widthPx}x{heightPx} is under {tokens.touchMin} px`
    end
    return nil
end

--- A text size must be inside the allowed bounds.
function Contracts.textSize(sizePx: number, owner: string, tokens: Tokens.Tokens): string?
    if sizePx < tokens.text.min or sizePx > tokens.text.max then
        return `UI-TEXT-SMALL {owner}: {sizePx} px is outside {tokens.text.min}-{tokens.text.max}`
    end
    return nil
end

--- A padding value taken from the scale (never a literal off the grid).
function Contracts.onScale(valuePx: number, owner: string, tokens: Tokens.Tokens): string?
    for _, key in Tokens.SPACING_KEYS do
        if tokens.spacing[key] == valuePx then
            return nil
        end
    end
    return `UI-SPACING-OFF-SCALE {owner}: {valuePx} px is not on the spacing scale`
end

--- Collects the non-nil results into a list.
function Contracts.collect(results: { string? }): { string }
    local out: { string } = {}
    for index = 1, #results do
        local item = results[index]
        if item ~= nil then
            table.insert(out, item)
        end
    end
    return out
end

return Contracts
