--!strict
--[[
    Engine side of InputScheme: tells the HUD which scheme is active and calls back when it
    changes, live. Reads `UserInputService.PreferredInput` (the 2026 API, covers touch,
    keyboard and mouse, gamepad and hybrid devices) and falls back to `LastInputTypeChanged`
    when the property is missing. Excluded from line coverage (engine code); the mapping is
    tested in InputScheme. Decision: docs/adr/0045-ui-spacing-and-platform-aware-controls.md.
]]

local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputScheme = require(ReplicatedStorage.Shared.features.ui.InputScheme)

export type Watcher = {
    get: () -> InputScheme.Scheme,
    -- Calls `callback` now and on every change. Returns the disconnect function.
    subscribe: (callback: (scheme: InputScheme.Scheme) -> ()) -> () -> (),
    destroy: () -> (),
}

local InputSchemeWatcher = {}

local function readPreferred(): InputScheme.Scheme?
    local ok, value = pcall(function(): string
        return (UserInputService :: any).PreferredInput.Name
    end)
    if ok then
        return InputScheme.fromPreferredInput(value)
    end
    return nil
end

function InputSchemeWatcher.new(): Watcher
    local current: InputScheme.Scheme = readPreferred()
        or (if UserInputService.TouchEnabled then InputScheme.TOUCH else InputScheme.KEYBOARD)
    local listeners: { (InputScheme.Scheme) -> () } = {}
    local connections: { RBXScriptConnection } = {}

    local function set(next: InputScheme.Scheme)
        if next == current then
            return
        end
        current = next
        for _, listener in listeners do
            listener(current)
        end
    end

    local hasPreferred = readPreferred() ~= nil
    if hasPreferred then
        table.insert(
            connections,
            UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
                local scheme = readPreferred()
                if scheme ~= nil then
                    set(scheme)
                end
            end)
        )
    end
    -- PreferredInput does not always flip when a pad is merely plugged in, only on a button
    -- press; the last input type covers that gap and the engines that lack the property.
    table.insert(
        connections,
        UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
            local scheme = InputScheme.fromLastInputType(inputType.Name)
            if scheme ~= nil then
                set(scheme)
            end
        end)
    )

    local watcher: Watcher
    watcher = {
        get = function(): InputScheme.Scheme
            return current
        end,
        subscribe = function(callback: (InputScheme.Scheme) -> ()): () -> ()
            table.insert(listeners, callback)
            callback(current)
            return function()
                local index = table.find(listeners, callback)
                if index ~= nil then
                    table.remove(listeners, index)
                end
            end
        end,
        destroy = function()
            for _, connection in connections do
                connection:Disconnect()
            end
            table.clear(listeners)
        end,
    }
    return watcher
end

return InputSchemeWatcher
