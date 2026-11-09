--!strict
--[[
    Adapter: the name filter of the presence feed over TextService:FilterStringAsync (ADR 0053).
    The engine call is injected (ADR 0009): `filter(name, userId)` returns the text safe to show
    every player (GetNonChatStringForBroadcastAsync). A throw, a yield failure or a non-text
    answer comes back as a typed error so the caller drops the entry instead of storing a raw
    name.
]]

export type NameResult = { ok: true, value: string } | { ok: false, error: string }

export type Deps = {
    -- FilterStringAsync(name, userId):GetNonChatStringForBroadcastAsync() wrapped.
    filter: (name: string, userId: number) -> string,
}

local TextServiceNameFilter = {}

function TextServiceNameFilter.new(deps: Deps): (userId: number, name: string) -> NameResult
    return function(userId: number, name: string): NameResult
        local called, answer = pcall(function(): unknown
            return deps.filter(name, userId)
        end)
        if not called then
            return { ok = false, error = tostring(answer) }
        end
        if type(answer) ~= "string" or answer == "" then
            return { ok = false, error = "the filter returned no text" }
        end
        return { ok = true, value = answer }
    end
end

return TextServiceNameFilter
