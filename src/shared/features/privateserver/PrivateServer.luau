--!strict
--[[
    Owner rules for private servers (ADR 0022). Pure: loads under Lune.
    The platform sells paid private servers and sets the price in Creator Hub; this module only
    adds the in-house rules on top: who the owner is, which settings the owner may change (the
    client sends INTENT only through RequestPrivateServerSetting), and what to do when a
    teleport fails to start (TeleportInitFailed). `privateServers.expectedMonthlyPrice` is NOT
    used here: it exists for the release checklist only and is never shown in a UI.
]]

local Config = require("../../Config")
local ServerContext = require("../../ports/ServerContext")
local Validation = require("../../net/Validation")

export type Role = "owner" | "guest" | "public"

export type SettingRejection =
    "disabled"
    | "rate_limited"
    | "not_private_server"
    | "not_owner"
    | Validation.ValidationError

export type SettingResult =
    { ok: true, setting: string, value: number }
    | { ok: false, reason: SettingRejection }

export type TeleportDecision = "retrying" | "gave_up" | "not_retryable"

export type Deps = {
    config: Config.PrivateServersConfig,
    context: ServerContext.ServerContext,
    allow: (userId: number) -> boolean,
    -- Runs `action` after `seconds` (task.delay in production).
    delay: (seconds: number, action: () -> ()) -> (),
    -- Called after the owner changed a setting, so the game can apply it.
    onSettingChanged: (setting: string, value: number) -> (),
}

export type PrivateServer = {
    isPrivateServer: (self: PrivateServer) -> boolean,
    roleOf: (self: PrivateServer, userId: number) -> Role,
    settingValue: (self: PrivateServer, setting: string) -> number?,
    handleSetting: (
        self: PrivateServer,
        userId: number,
        setting: unknown,
        value: unknown
    ) -> SettingResult,
    handleTeleportFailed: (
        self: PrivateServer,
        failure: ServerContext.TeleportFailure
    ) -> TeleportDecision,
}

-- Results worth repeating: transient platform conditions. Anything else (GameNotFound,
-- GameEnded, Unauthorized, GameFull, IsTeleporting) will not fix itself by retrying.
local RETRYABLE_RESULTS: { string } = { "Failure", "Flooded" }

local PrivateServerModule = {}

function PrivateServerModule.new(deps: Deps): PrivateServer
    local values: { [string]: number } = {}
    for _, setting in deps.config.settings do
        values[setting.name] = setting.default
    end
    local attempts: { [number]: number } = {}

    local function settingNames(): { string }
        local names: { string } = {}
        for _, setting in deps.config.settings do
            table.insert(names, setting.name)
        end
        return names
    end

    local server: PrivateServer
    server = {
        isPrivateServer = function(_self: PrivateServer): boolean
            return deps.context:privateServerId() ~= ""
        end,
        roleOf = function(_self: PrivateServer, userId: number): Role
            if deps.context:privateServerId() == "" then
                return "public"
            end
            local ownerId = deps.context:ownerId()
            if ownerId ~= 0 and ownerId == userId then
                return "owner"
            end
            return "guest"
        end,
        settingValue = function(_self: PrivateServer, setting: string): number?
            return values[setting]
        end,
        handleSetting = function(
            _self: PrivateServer,
            userId: number,
            setting: unknown,
            value: unknown
        ): SettingResult
            if not deps.config.enabled then
                return { ok = false, reason = "disabled" }
            end
            if not deps.allow(userId) then
                return { ok = false, reason = "rate_limited" }
            end
            local name = Validation.oneOf(setting, settingNames())
            if not name.ok then
                return { ok = false, reason = name.error }
            end
            local bounds: Config.PrivateServerSettingConfig? = nil
            for _, candidate in deps.config.settings do
                if candidate.name == name.value then
                    bounds = candidate
                end
            end
            if bounds == nil then
                return { ok = false, reason = "not_allowed" }
            end
            local checked = Validation.integerInRange(value, bounds.min, bounds.max)
            if not checked.ok then
                return { ok = false, reason = checked.error }
            end
            if not server:isPrivateServer() then
                return { ok = false, reason = "not_private_server" }
            end
            if server:roleOf(userId) ~= "owner" then
                return { ok = false, reason = "not_owner" }
            end
            values[name.value] = checked.value
            deps.onSettingChanged(name.value, checked.value)
            return { ok = true, setting = name.value, value = checked.value }
        end,
        handleTeleportFailed = function(
            _self: PrivateServer,
            failure: ServerContext.TeleportFailure
        ): TeleportDecision
            if table.find(RETRYABLE_RESULTS, failure.result) == nil then
                return "not_retryable"
            end
            local used = attempts[failure.userId] or 0
            if used >= deps.config.teleportRetries then
                attempts[failure.userId] = nil
                return "gave_up"
            end
            attempts[failure.userId] = used + 1
            deps.delay(deps.config.teleportRetryDelaySeconds, failure.retry)
            return "retrying"
        end,
    }
    return server
end

return PrivateServerModule
