--!strict
--[[
    Adapter: FlagSource over Experience Configs (ConfigService, ADR 0011).
    GetConfigAsync returns a point-in-time snapshot; this adapter refreshes it when Roblox
    reports an update so flag reads see the latest staged/rolled-out values.
    Engine-only: not testable under Lune. Pure fallback logic is in features/flags/Flags.luau.
]]

local ConfigService = game:GetService("ConfigService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FlagsPort = require(ReplicatedStorage.Shared.ports.Flags)

local ConfigServiceFlags = {}

--- Returns nil when Experience Configs cannot be loaded; callers then use in-repo defaults.
function ConfigServiceFlags.new(): FlagsPort.FlagSource?
    local loaded, snapshot = pcall(function()
        return ConfigService:GetConfigAsync()
    end)
    if not loaded then
        warn(`Experience Configs unavailable, using in-repo flag defaults: {snapshot}`)
        return nil
    end
    local config: ConfigSnapshot = snapshot
    config.UpdateAvailable:Connect(function()
        config:Refresh()
    end)

    local source: FlagsPort.FlagSource = {
        get = function(_self: FlagsPort.FlagSource, name: string): FlagsPort.FlagValue?
            local value: unknown = config:GetValue(name)
            if type(value) == "boolean" or type(value) == "number" or type(value) == "string" then
                return value
            end
            return nil
        end,
    }
    return source
end

return ConfigServiceFlags
