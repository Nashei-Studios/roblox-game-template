--!strict
--[[
    Server adapter: a value milestone for everyone's chat ("Name reached 150!"). TextChannel:
    DisplaySystemMessage only works on the client, so the server sends bounded data over the
    AnnounceMilestone remote and each client builds and shows the line (AnnouncementPresenter).
    The engine call is injected so this file loads under Lune and is tested with fakes.
]]

export type Deps = {
    -- Sends the AnnounceMilestone remote to every client.
    fireAll: (name: string, value: number) -> (),
}

export type Announcer = {
    announce: (self: Announcer, name: string, value: number) -> (),
}

-- Limits of the wire fields in net/schema.zap (name: string.binary(1..40), value: u32).
local MAX_NAME_BYTES = 40
local MAX_WIRE_VALUE = 4294967295
local FALLBACK_NAME = "Miner"

local function boundedName(name: string): string
    if utf8.len(name) == nil or #name == 0 then
        return FALLBACK_NAME
    end
    local bounded = name
    while #bounded > MAX_NAME_BYTES do
        bounded = string.sub(bounded, 1, (utf8.offset(bounded, -1) or 1) - 1)
    end
    return if #bounded == 0 then FALLBACK_NAME else bounded
end

local Announcer = {}

function Announcer.new(deps: Deps): Announcer
    local announcer: Announcer = {
        announce = function(_self: Announcer, name: string, value: number)
            deps.fireAll(boundedName(name), math.clamp(math.floor(value), 0, MAX_WIRE_VALUE))
        end,
    }
    return announcer
end

return Announcer
