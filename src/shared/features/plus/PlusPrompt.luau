--!strict
--[[
    Roblox Plus sign-up prompt (ADR 0022). Pure: loads under Lune.
    Docs: production/monetization/roblox-plus (earn from in-game Plus subscriptions).

    Rules:
    - Opt-in: the prompt opens only when the player asks (a button they press); the server never
      opens it on its own, so it cannot interrupt gameplay.
    - Placement names, the cooldown and the per-session cap come from Config.
    - Already-subscribed players are never prompted.
    - The "became a subscriber" signal comes from the SERVER seeing HasRobloxSubscription change
      after we prompted that player in this session, never from the client or from the prompt
      closing. `onSubscribed` is where a game can attach its own thanks.
    - The sign-up bonus paid to the experience is credited by the platform; nothing here pays it.
]]

local Config = require("../../Config")
local PlusPort = require("../../ports/PlusPort")
local Validation = require("../../net/Validation")

export type Rejection =
    "disabled"
    | "rate_limited"
    | "already_plus"
    | "cooldown"
    | "session_cap_reached"
    | "status_unknown"
    | "prompt_failed"
    | Validation.ValidationError

export type HandleResult = { ok: true } | { ok: false, reason: Rejection }

export type Deps = {
    config: Config.PlusPromptConfig,
    port: PlusPort.PlusPort,
    allow: (userId: number) -> boolean,
    -- Seconds, monotonic (os.clock on the server).
    clock: () -> number,
    -- Called once when a player we prompted in this session becomes a Plus subscriber.
    onSubscribed: (userId: number) -> (),
}

export type PlusPrompt = {
    handle: (self: PlusPrompt, userId: number, placement: unknown) -> HandleResult,
    -- Feed the PlusPort.onPlusChanged signal here.
    onPlusChanged: (self: PlusPrompt, userId: number, hasPlus: boolean) -> (),
    forget: (self: PlusPrompt, userId: number) -> (),
}

type PromptState = { lastAt: number, count: number, awaitingSignUp: boolean }

local PlusPromptModule = {}

function PlusPromptModule.new(deps: Deps): PlusPrompt
    local states: { [number]: PromptState } = {}

    local prompt: PlusPrompt = {
        handle = function(_self: PlusPrompt, userId: number, placement: unknown): HandleResult
            if not deps.config.enabled then
                return { ok = false, reason = "disabled" }
            end
            if not deps.allow(userId) then
                return { ok = false, reason = "rate_limited" }
            end
            local checked = Validation.oneOf(placement, deps.config.placements)
            if not checked.ok then
                return { ok = false, reason = checked.error }
            end
            local current = deps.port:hasPlus(userId)
            if current == nil then
                return { ok = false, reason = "status_unknown" }
            end
            if current then
                return { ok = false, reason = "already_plus" }
            end
            local state = states[userId]
            local now = deps.clock()
            if state ~= nil then
                if state.count >= deps.config.maxPromptsPerSession then
                    return { ok = false, reason = "session_cap_reached" }
                end
                if now - state.lastAt < deps.config.cooldownSeconds then
                    return { ok = false, reason = "cooldown" }
                end
            end
            local opened = deps.port:prompt(userId)
            if not opened.ok then
                return { ok = false, reason = "prompt_failed" }
            end
            states[userId] = {
                lastAt = now,
                count = if state == nil then 1 else state.count + 1,
                awaitingSignUp = true,
            }
            return { ok = true }
        end,
        onPlusChanged = function(_self: PlusPrompt, userId: number, hasPlus: boolean)
            local state = states[userId]
            if hasPlus and state ~= nil and state.awaitingSignUp then
                state.awaitingSignUp = false
                deps.onSubscribed(userId)
            end
        end,
        forget = function(_self: PlusPrompt, userId: number)
            states[userId] = nil
        end,
    }
    return prompt
end

return PlusPromptModule
