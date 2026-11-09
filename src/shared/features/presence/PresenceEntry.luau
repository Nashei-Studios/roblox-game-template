--!strict
--[[
    One thing a player did, as it travels through the shared feed (ADR 0053). Pure codec: the
    feed holds text written by other servers, so `decode` trusts nothing and returns nil for
    anything malformed. Format: kind|userId|value|at|name (the name is last and never has "|").
    Whether the kind is declared is the caller's job (the config knows the kinds).
]]

export type Entry = {
    kind: string,
    userId: number,
    value: number,
    -- Unix seconds.
    at: number,
    -- Already passed through the Roblox text filter (never raw).
    name: string,
}

local PresenceEntry = {}

--- Drops separators and control characters, then cuts to `maxLength`.
function PresenceEntry.cleanName(name: string, maxLength: number): string
    local cleaned = string.gsub(name, "[%c|]", "")
    return string.sub(cleaned, 1, maxLength)
end

function PresenceEntry.encode(entry: Entry): string
    local name = PresenceEntry.cleanName(entry.name, 40)
    return `{entry.kind}|{math.floor(entry.userId)}|{math.floor(entry.value)}|{math.floor(entry.at)}|{name}`
end

function PresenceEntry.decode(text: string): Entry?
    local kind, userText, valueText, atText, name =
        string.match(text, "^([%w_]+)|(%d+)|(%d+)|(%d+)|([^|]*)$")
    if kind == nil or name == nil or name == "" then
        return nil
    end
    local userId, value, at = tonumber(userText), tonumber(valueText), tonumber(atText)
    if userId == nil or value == nil or at == nil then
        return nil
    end
    return { kind = kind, userId = userId, value = value, at = at, name = name }
end

return PresenceEntry
