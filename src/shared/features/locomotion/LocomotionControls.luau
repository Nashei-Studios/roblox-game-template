--!strict
--[[
    The locomotion HUD controls as registry entries (ADR 0045). Sprint and Equip are touch-only
    buttons: keyboard and gamepad already have a key, so they get a hint built from the configured
    keys instead of a button. Pure.
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

--- Registers "Sprint" and "Equip" in `registry` from the configured keys.
function LocomotionControls.register(
    registry: ControlRegistry.Registry,
    keys: LocomotionConfig.Keys
)
    ControlRegistry.register(registry, {
        id = "Sprint",
        purpose = "hold to run; keyboard and gamepad use their key",
        schemes = { InputScheme.TOUCH },
        hints = hints(keys.sprint),
    })
    ControlRegistry.register(registry, {
        id = "Equip",
        purpose = "stow or draw the tool; keyboard and gamepad use their key",
        schemes = { InputScheme.TOUCH },
        hints = hints(keys.equip),
    })
end

return LocomotionControls
