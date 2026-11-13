--!strict
--[[
    The input scheme a control is shown for: touch, keyboard (keyboard and mouse) or gamepad.
    Pure, so the mapping from the engine enum names is unit tested; the engine side only reads
    `UserInputService.PreferredInput` and calls `fromPreferredInput` (client/presenters/
    InputSchemeWatcher). `fromLastInputType` is the fallback for an engine without PreferredInput.
    Decision: docs/adr/0045-ui-spacing-and-platform-aware-controls.md.
]]

-- Plain strings: the stable solver widens singleton unions in tables.
export type Scheme = string

local InputScheme = {}

InputScheme.TOUCH = "touch"
InputScheme.KEYBOARD = "keyboard"
InputScheme.GAMEPAD = "gamepad"
InputScheme.ALL = { "touch", "keyboard", "gamepad" }

--- True when `name` is one of the three schemes.
function InputScheme.isScheme(name: string): boolean
    return table.find(InputScheme.ALL, name) ~= nil
end

--- Maps an `Enum.PreferredInput` member name. An unknown name falls back to keyboard, the
--- scheme that shows the fewest on-screen controls.
function InputScheme.fromPreferredInput(name: string): Scheme
    if name == "Touch" then
        return InputScheme.TOUCH
    elseif name == "Gamepad" then
        return InputScheme.GAMEPAD
    end
    return InputScheme.KEYBOARD
end

--- Maps an `Enum.UserInputType` member name; nil for types that say nothing about the scheme
--- (Focus, Accelerometer, TextInput, ...), so the caller keeps the current scheme.
function InputScheme.fromLastInputType(name: string): Scheme?
    if name == "Touch" then
        return InputScheme.TOUCH
    elseif string.match(name, "^Gamepad%d+$") ~= nil then
        return InputScheme.GAMEPAD
    elseif name == "Keyboard" or string.sub(name, 1, 5) == "Mouse" then
        return InputScheme.KEYBOARD
    end
    return nil
end

--- Short label of an Enum.KeyCode name for a hint: "LeftShift" -> "Shift", "ButtonL3" -> "L3".
function InputScheme.keyLabel(name: string): string
    local stripped = string.gsub(name, "^Button", "")
    stripped = string.gsub(stripped, "^Left", "")
    stripped = string.gsub(stripped, "^Right", "")
    return if stripped == "" then name else stripped
end

--- The first key name of `keys` for a scheme: gamepad keys start with "Button", keyboard
--- keys do not. nil when the list has none for that scheme.
function InputScheme.firstKeyFor(keys: { string }, scheme: Scheme): string?
    for _, key in keys do
        local isPad = string.sub(key, 1, 6) == "Button"
        if (scheme == InputScheme.GAMEPAD) == isPad then
            return key
        end
    end
    return nil
end

return InputScheme
