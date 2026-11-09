--!strict
--[[
    The locomotion HUD controls as registry entries (ADR 0045, ADR 0061). Sprint and Equip are
    key-only by default: keyboard and gamepad get a hint built from the configured keys, and touch
    gets no button (run is the joystick pushed to the end, stow is an item slot of the bar).
    `touchButtons` re-adds the touch buttons, which the UI audit then reports as
    UI-TOUCH-LOCOMOTION. Pure.
]]

local ControlRegistry = require("../ui/ControlRegistry")
local InputScheme = require("../ui/InputScheme")
local LocomotionConfig = require("./LocomotionConfig")

local LocomotionControls = {}

local function hints(keys: { string }): { [string]: string }
    local out: { [string]: string } = {}
    local keyboard = InputScheme.firstKeyFor(keys, InputScheme.KEYBOARD)
    local gamepad = InputScheme.firstKeyFor(keys, InputScheme.GAMEPAD)
    if keyboard ~= nil then
        out[InputScheme.KEYBOARD] = InputScheme.keyLabel(keyboard)
    end
    if gamepad ~= nil then
        out[InputScheme.GAMEPAD] = InputScheme.keyLabel(gamepad)
    end
    return out
end

--- Registers "Sprint" and "Equip" in `registry` from the configured keys. `touchButtons` (default
--- false) shows them as buttons on touch.
function LocomotionControls.register(
    registry: ControlRegistry.Registry,
    keys: LocomotionConfig.Keys,
    touchButtons: boolean?
)
    local schemes: { string } = if touchButtons == true then { InputScheme.TOUCH } else {}
    ControlRegistry.register(registry, {
        id = "Sprint",
        purpose = "run; keyboard and gamepad use their key, touch pushes the joystick to the end",
        schemes = schemes,
        category = "locomotion",
        hints = hints(keys.sprint),
    })
    ControlRegistry.register(registry, {
        id = "Equip",
        purpose = "stow or draw the tool; keyboard and gamepad use their key, touch uses an item slot",
        schemes = schemes,
        category = "locomotion",
        hints = hints(keys.equip),
    })
end

return LocomotionControls
