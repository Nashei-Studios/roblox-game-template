--!strict
--[[
    Config of the UI gate rules (docs/adr/0061): the limits the audit enforces and the motion a
    modal menu must declare. Nothing is hardcoded in the rules; a game overrides these values in
    Config.default.ui.gates and records why in its own ADR. Pure: loads under Lune.
]]

local InputScheme = require("./InputScheme")

-- How a transition is driven: "tween", "spring" or "none". "none" is not valid for a modal menu.
-- Plain strings: the stable solver widens singleton unions in tables.
export type Transition = string

--- The motion a modal menu declares: its open and close transition, whether its buttons react to
--- hover and press, and what happens when the player asked for reduced motion.
export type MenuMotion = {
    open: Transition,
    close: Transition,
    hover: boolean,
    press: boolean,
    -- Under reduced motion the menu swaps instantly or only fades; "none" means no fallback.
    reduced: string,
}

-- The slice of a menu declaration the motion rule reads (UiConfig.MenuConfig satisfies it).
export type MotionMenu = {
    id: string,
    modal: boolean,
    motion: MenuMotion?,
}

export type SchemeLimits = { touch: number, keyboard: number, gamepad: number }

export type Gates = {
    -- Most buttons a screen shows at once, per input scheme. `hud` counts the HUD controls;
    -- `menu` counts the buttons of a modal menu outside its scrolling lists (the chrome: close,
    -- tabs, actions), because the rows of a list are content that the scroll rules govern.
    maxButtons: { hud: SchemeLimits, menu: SchemeLimits },
    -- Scrollers nested inside scrollers.
    maxNestedScroll: number,
    -- Pixels of slack for engine rounding when comparing rectangles.
    tolerancePx: number,
    -- Control categories that never get a button on touch (the joystick and the item slots
    -- cover them).
    touchForbiddenCategories: { string },
}

local UiGates = {}

--- Control categories a registry entry may declare.
UiGates.CATEGORIES = { "locomotion", "menu", "action", "social" } :: { string }

--- The template defaults, justified in docs/adr/0061.
function UiGates.default(): Gates
    return {
        maxButtons = {
            hud = { touch = 6, keyboard = 10, gamepad = 8 },
            menu = { touch = 8, keyboard = 12, gamepad = 10 },
        },
        maxNestedScroll = 1,
        tolerancePx = 1,
        touchForbiddenCategories = { "locomotion" },
    }
end

--- The motion every modal menu of the template declares: a tween in, a tween out, hover and press
--- feedback, and an instant swap under reduced motion.
function UiGates.defaultMotion(): MenuMotion
    return { open = "tween", close = "tween", hover = true, press = true, reduced = "instant" }
end

local function validateLimits(path: string, limits: SchemeLimits, problems: { string })
    for _, scheme in InputScheme.ALL do
        local value = (limits :: any)[scheme]
        if type(value) ~= "number" or value < 1 or value % 1 ~= 0 then
            table.insert(problems, `ui.gates.{path}.{scheme} must be an integer of 1 or more`)
        end
    end
end

--- One human-readable problem per invalid value (empty when valid).
function UiGates.validate(gates: Gates): { string }
    local problems: { string } = {}
    validateLimits("maxButtons.hud", gates.maxButtons.hud, problems)
    validateLimits("maxButtons.menu", gates.maxButtons.menu, problems)
    if gates.maxNestedScroll < 1 or gates.maxNestedScroll % 1 ~= 0 then
        table.insert(problems, "ui.gates.maxNestedScroll must be an integer of 1 or more")
    end
    if gates.tolerancePx < 0 then
        table.insert(problems, "ui.gates.tolerancePx must be zero or positive")
    end
    for _, category in gates.touchForbiddenCategories do
        if table.find(UiGates.CATEGORIES, category) == nil then
            table.insert(problems, `ui.gates.touchForbiddenCategories: unknown "{category}"`)
        end
    end
    return problems
end

return UiGates
