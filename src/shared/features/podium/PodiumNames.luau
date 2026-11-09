--!strict
--[[
    Names for the plates. Pure with injected engine calls (ADR 0009): `lookup` is
    Players:GetNameFromUserIdAsync and `filter` is the TextService adapter
    (server/adapters/TextServiceNameFilter). A raw name never reaches a plate: when the lookup or
    the filter fails the plate shows the config's unknown name, and the failure is not cached so
    the next refresh tries again. Filtered names are cached by user id (a name filter is a web call).
]]

export type NameResult = { ok: true, value: string } | { ok: false, error: string }

export type Deps = {
    -- Players:GetNameFromUserIdAsync wrapped; may throw.
    lookup: (userId: number) -> string,
    filter: (userId: number, name: string) -> NameResult,
    unknownName: string,
    onError: (message: string) -> (),
}

local PodiumNames = {}

--- Returns `nameOf(userId)`, which never throws and never returns a raw or empty name.
function PodiumNames.new(deps: Deps): (userId: number) -> string
    local cache: { [number]: string } = {}
    return function(userId: number): string
        local cached = cache[userId]
        if cached ~= nil then
            return cached
        end
        local looked, name = pcall(function(): string
            return deps.lookup(userId)
        end)
        if not looked or type(name) ~= "string" or name == "" then
            deps.onError(`podium name lookup for {userId} failed`)
            return deps.unknownName
        end
        local filtered = deps.filter(userId, name)
        if not filtered.ok then
            deps.onError(`podium name filter for {userId} failed: {filtered.error}`)
            return deps.unknownName
        end
        cache[userId] = filtered.value
        return filtered.value
    end
end

return PodiumNames
