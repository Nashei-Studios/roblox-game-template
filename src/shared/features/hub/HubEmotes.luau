--!strict
--[[
    Emote requests of the hub, validated on the server: the id must be allowed and the player
    must be past the cooldown. Pure: the clock is injected. The game owns the remote (ADR 0012
    validation and rate limit) and the animation; this decides whether a request is accepted.
]]

local HubLayout = require("./HubLayout")

export type Verdict = { accepted: boolean, reason: string? }

export type Deps = {
    policy: HubLayout.EmotePolicy,
    -- Server clock, seconds.
    now: () -> number,
}

export type Emotes = {
    request: (self: Emotes, playerId: number, emoteId: string) -> Verdict,
    forget: (self: Emotes, playerId: number) -> (),
}

local HubEmotes = {}

function HubEmotes.new(deps: Deps): Emotes
    local allowed: { [string]: boolean } = {}
    for _, emote in deps.policy.allowed do
        allowed[emote] = true
    end
    local lastAt: { [number]: number } = {}
    return {
        request = function(_self: Emotes, playerId: number, emoteId: string): Verdict
            if not allowed[emoteId] then
                return { accepted = false, reason = "unknown_emote" }
            end
            local now = deps.now()
            local previous = lastAt[playerId]
            if previous ~= nil and now - previous < deps.policy.cooldownSeconds then
                return { accepted = false, reason = "cooldown" }
            end
            lastAt[playerId] = now
            return { accepted = true, reason = nil }
        end,
        forget = function(_self: Emotes, playerId: number)
            lastAt[playerId] = nil
        end,
    }
end

return HubEmotes
