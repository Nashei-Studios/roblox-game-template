--!strict
--[[
    Port: live-ops flags (ADR 0011). The production adapter reads Experience Configs
    (ConfigService); in-repo defaults are the fallback (see features/flags/Flags.luau).
]]

export type FlagValue = boolean | number | string

export type FlagSource = {
    -- nil when the source does not define the flag.
    get: (self: FlagSource, name: string) -> FlagValue?,
}

return {}
