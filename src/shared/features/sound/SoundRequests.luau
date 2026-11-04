--!strict
--[[
    Server handler for the SetVolume remote (ADR 0012, ADR 0015). Pure: loads under Lune.
    Intent only: "set this group to this percent". Rate limiter first, then Validation of the
    group (allow-list) and the percent (integer 0..100, done by the SoundSettings port).
]]

local SoundSettings = require("../../ports/SoundSettings")
local Validation = require("../../net/Validation")

export type Rejection =
    "rate_limited"
    | Validation.ValidationError
    | SoundSettings.SetVolumeError

export type HandleResult = { ok: true } | { ok: false, reason: Rejection }

export type Deps = {
    settings: SoundSettings.SoundSettings,
    allow: (userId: number) -> boolean,
}

export type SoundRequests = {
    handle: (self: SoundRequests, userId: number, group: unknown, percent: unknown) -> HandleResult,
}

local SoundRequestsModule = {}

function SoundRequestsModule.new(deps: Deps): SoundRequests
    local handler: SoundRequests = {
        handle = function(
            _self: SoundRequests,
            userId: number,
            group: unknown,
            percent: unknown
        ): HandleResult
            if not deps.allow(userId) then
                return { ok = false, reason = "rate_limited" }
            end
            local checked = Validation.oneOf(group, { "music", "sfx" })
            if not checked.ok then
                return { ok = false, reason = checked.error }
            end
            local failure = deps.settings:setVolume(
                userId,
                if checked.value == "music" then "music" else "sfx",
                percent
            )
            if failure ~= nil then
                return { ok = false, reason = failure }
            end
            return { ok = true }
        end,
    }
    return handler
end

return SoundRequestsModule
