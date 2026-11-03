--!strict
--[[
    Typed flag access with in-repo defaults as fallback. Pure: loads under Lune.
    A live source value of the wrong type is ignored; the default wins. A flag with no
    default is a programming error and raises.
]]

export type FlagValue = boolean | number | string

export type FlagSource = {
    get: (self: FlagSource, name: string) -> FlagValue?,
}

export type Flags = {
    getBoolean: (self: Flags, name: string) -> boolean,
    getNumber: (self: Flags, name: string) -> number,
}

export type Defaults = {
    booleans: { [string]: boolean },
    numbers: { [string]: number },
}

local FlagsModule = {}

--- `source` may be nil (no live-ops yet, or Experience Configs failed to load).
function FlagsModule.new(source: FlagSource?, defaults: Defaults): Flags
    local flags: Flags = {
        getBoolean = function(_self: Flags, name: string): boolean
            local fallback = defaults.booleans[name]
            if fallback == nil then
                error(`unknown boolean flag "{name}": add a default`, 2)
            end
            if source ~= nil then
                local value = source:get(name)
                if type(value) == "boolean" then
                    return value
                end
            end
            return fallback
        end,
        getNumber = function(_self: Flags, name: string): number
            local fallback = defaults.numbers[name]
            if fallback == nil then
                error(`unknown number flag "{name}": add a default`, 2)
            end
            if source ~= nil then
                local value = source:get(name)
                if type(value) == "number" then
                    return value
                end
            end
            return fallback
        end,
    }
    return flags
end

return FlagsModule
