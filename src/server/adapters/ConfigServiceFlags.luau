--!strict
--[[
    Adapter: FlagSource over Experience Configs (ConfigService, ADR 0011).
    GetConfigAsync returns a point-in-time snapshot; this adapter refreshes it when Roblox
    reports an update so flag reads see the latest staged/rolled-out values.
    ConfigService is injected (ADR 0009) so this file loads under Lune and is tested with a
    fake. Pure fallback logic is in features/flags/Flags.luau.
]]

-- Structurally identical to ports/Flags.luau (kept local so this file loads under Lune).
type FlagValue = boolean | number | string

type FlagSource = {
    get: (self: FlagSource, name: string) -> FlagValue?,
}

-- The slice of ConfigService and its ConfigSnapshot that this adapter uses.
export type ConfigSnapshotLike = {
    UpdateAvailable: {
        Connect: (self: unknown, listener: () -> ()) -> unknown,
    },
    Refresh: (self: unknown) -> (),
    GetValue: (self: unknown, name: string) -> unknown,
}

export type ConfigServiceLike = {
    GetConfigAsync: (self: unknown) -> ConfigSnapshotLike,
}

export type Deps = {
    configService: ConfigServiceLike,
    -- Defaults to the engine `warn`; tests capture it.
    warn: ((message: string) -> ())?,
}

local ConfigServiceFlags = {}

--- Returns nil when Experience Configs cannot be loaded; callers then use in-repo defaults.
function ConfigServiceFlags.new(deps: Deps): FlagSource?
    local report: (message: string) -> () = deps.warn
        or function(message: string)
            warn(message)
        end
    local loaded, snapshot = pcall(function(): ConfigSnapshotLike
        return deps.configService:GetConfigAsync()
    end)
    if not loaded then
        report(`Experience Configs unavailable, using in-repo flag defaults: {snapshot}`)
        return nil
    end
    local config: ConfigSnapshotLike = snapshot
    config.UpdateAvailable:Connect(function()
        config:Refresh()
    end)

    local source: FlagSource = {
        get = function(_self: FlagSource, name: string): FlagValue?
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
