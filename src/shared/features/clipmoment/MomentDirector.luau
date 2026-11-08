--!strict
--[[
    Clip moments: the game declares which moments are worth a clip (a big break, a rare drop, a
    co-op success) and this module turns a trigger into a timed PLAN of hype beats: a sound
    sting, a camera kick, a slow-motion window and the capture and share prompt at the right
    instant. Pure: loads under Lune; the clock and the player settings are injected, and the
    client presenter executes the plan (CaptureService is client only).

    Rules:
    - A moment is a declaration with its own beats; nothing here names a game.
    - Effects (camera, slow motion) respect the player setting `effects`; the share prompt
      respects `sharePrompt` (opt-out). A disabled part is dropped from the plan, the sting stays.
    - Rate limits: the share prompt shows at most `promptsPerSession` times (default 1) and at
      least `minSecondsBetweenPrompts` apart; effects have their own cooldown so a rapid chain of
      moments does not shake the screen every second.
    - The prompt is always skippable by the player (the native share sheet can be denied).
]]

export type Beat = {
    -- Sound sting name (resolved by the music director / sound manager), nil = none.
    sting: string?,
    -- Seconds the sting starts BEFORE the peak (0 = at the peak). Clip checklist: sound at or before.
    stingLeadSeconds: number,
    -- Camera kick intensity 0..1, nil = none.
    cameraKick: number?,
    -- Slow-motion window: scale in (0, 1) and its length in seconds; nil = none.
    slowMoScale: number?,
    slowMoSeconds: number?,
    -- Seconds after the peak at which the screenshot is taken.
    captureAfterSeconds: number,
    -- Seconds after the capture at which the share prompt opens.
    promptAfterCaptureSeconds: number,
}

export type MomentDef = {
    id: string,
    -- Free-form kind for analytics (big_break, rare_drop, coop_success...).
    kind: string,
    beat: Beat,
}

export type MomentConfig = {
    moments: { MomentDef },
    promptsPerSession: number,
    minSecondsBetweenPrompts: number,
    effectCooldownSeconds: number,
}

export type Settings = { effects: boolean, sharePrompt: boolean }

export type Step = {
    -- Seconds from the start of the plan (the sting). The peak is at `stingLeadSeconds`.
    at: number,
    -- "sting" | "camera_kick" | "slow_mo_start" | "slow_mo_end" | "capture" | "share_prompt"
    action: string,
    name: string?,
    value: number?,
}

export type Plan = {
    momentId: string,
    kind: string,
    steps: { Step },
    -- What the player setting or a rate limit removed, for the log.
    dropped: { string },
}

export type Deps = {
    config: MomentConfig,
    -- Seconds, monotonic.
    now: () -> number,
    settings: () -> Settings,
}

export type Director = {
    trigger: (self: Director, momentId: string) -> Plan?,
    promptsShown: (self: Director) -> number,
}

local MomentDirector = {}

-- Order of simultaneous steps: the sound leads, the prompt closes.
local RANK: { [string]: number } = {
    sting = 1,
    camera_kick = 2,
    slow_mo_start = 3,
    capture = 4,
    slow_mo_end = 5,
    share_prompt = 6,
}
local MAX_SLOW_SECONDS = 3
local MAX_DELAY_SECONDS = 10

--- Neutral defaults: one prompt per session, a minute apart, a short cooldown on effects.
function MomentDirector.defaults(moments: { MomentDef }): MomentConfig
    return {
        moments = moments,
        promptsPerSession = 1,
        minSecondsBetweenPrompts = 60,
        effectCooldownSeconds = 8,
    }
end

local function nonNegative(value: number): boolean
    return value == value and value >= 0
end

--- One human-readable problem per invalid value (empty when valid).
function MomentDirector.validate(config: MomentConfig): { string }
    local problems: { string } = {}
    local seen: { [string]: boolean } = {}
    if config.promptsPerSession < 0 or config.promptsPerSession % 1 ~= 0 then
        table.insert(problems, "clipmoment.promptsPerSession must be a non-negative integer")
    end
    if not nonNegative(config.minSecondsBetweenPrompts) then
        table.insert(problems, "clipmoment.minSecondsBetweenPrompts must be zero or positive")
    end
    if not nonNegative(config.effectCooldownSeconds) then
        table.insert(problems, "clipmoment.effectCooldownSeconds must be zero or positive")
    end
    for _, moment in config.moments do
        local label = `moment "{moment.id}"`
        if moment.id == "" or #moment.id > 32 then
            table.insert(problems, "a moment id must be 1 to 32 characters")
        end
        if seen[moment.id] then
            table.insert(problems, `{label} is declared twice`)
        end
        seen[moment.id] = true
        if moment.kind == "" then
            table.insert(problems, `{label} needs a kind`)
        end
        local beat = moment.beat
        local kick = beat.cameraKick
        if kick ~= nil and (kick ~= kick or kick <= 0 or kick > 1) then
            table.insert(problems, `{label} cameraKick must be above 0 up to 1`)
        end
        local scale, length = beat.slowMoScale, beat.slowMoSeconds
        if (scale == nil) ~= (length == nil) then
            table.insert(problems, `{label} needs slowMoScale and slowMoSeconds together`)
        elseif scale ~= nil and length ~= nil then
            if scale ~= scale or scale <= 0 or scale >= 1 then
                table.insert(problems, `{label} slowMoScale must be between 0 and 1 (exclusive)`)
            end
            if length ~= length or length <= 0 or length > MAX_SLOW_SECONDS then
                table.insert(
                    problems,
                    `{label} slowMoSeconds must be above 0 up to {MAX_SLOW_SECONDS}`
                )
            end
        end
        local delays: { { name: string, value: number } } = {
            { name = "stingLeadSeconds", value = beat.stingLeadSeconds },
            { name = "captureAfterSeconds", value = beat.captureAfterSeconds },
            { name = "promptAfterCaptureSeconds", value = beat.promptAfterCaptureSeconds },
        }
        for _, delay in delays do
            if not nonNegative(delay.value) or delay.value > MAX_DELAY_SECONDS then
                table.insert(problems, `{label} {delay.name} must be 0 to {MAX_DELAY_SECONDS}`)
            end
        end
        if beat.sting ~= nil and beat.sting == "" then
            table.insert(problems, `{label} sting must be a name or nil`)
        end
    end
    return problems
end

--- Moments the checklist would reject: no sting means no sound moment (criterion 4).
function MomentDirector.advise(config: MomentConfig): { string }
    local advice: { string } = {}
    if #config.moments == 0 then
        table.insert(
            advice,
            "no moment is declared: the game has no clip-worthy moment (checklist 2)"
        )
    end
    for _, moment in config.moments do
        if moment.beat.sting == nil then
            table.insert(advice, `moment "{moment.id}" has no sting (checklist criterion 4)`)
        end
    end
    return advice
end

local function find(config: MomentConfig, id: string): MomentDef?
    for _, moment in config.moments do
        if moment.id == id then
            return moment
        end
    end
    return nil
end

function MomentDirector.new(deps: Deps): Director
    local config = deps.config
    local prompts = 0
    local lastPromptAt: number? = nil
    local lastEffectAt: number? = nil

    local director: Director = {
        trigger = function(_self: Director, momentId: string): Plan?
            local moment = find(config, momentId)
            if moment == nil then
                return nil
            end
            local now = deps.now()
            local settings = deps.settings()
            local beat = moment.beat
            local steps: { Step } = {}
            local dropped: { string } = {}

            local sting = beat.sting
            if sting ~= nil then
                -- A lead shifts the whole plan: the sting is at 0 and the peak is `lead` later.
                table.insert(steps, { at = 0, action = "sting", name = sting, value = nil })
            end
            local peak = if sting ~= nil then beat.stingLeadSeconds else 0

            local effectsReady = lastEffectAt == nil
                or now - lastEffectAt >= config.effectCooldownSeconds
            if not settings.effects then
                table.insert(dropped, "effects_off")
            elseif not effectsReady then
                table.insert(dropped, "effect_cooldown")
            else
                local kick = beat.cameraKick
                if kick ~= nil then
                    table.insert(
                        steps,
                        { at = peak, action = "camera_kick", name = nil, value = kick }
                    )
                end
                local scale, length = beat.slowMoScale, beat.slowMoSeconds
                if scale ~= nil and length ~= nil then
                    table.insert(
                        steps,
                        { at = peak, action = "slow_mo_start", name = nil, value = scale }
                    )
                    table.insert(
                        steps,
                        { at = peak + length, action = "slow_mo_end", name = nil, value = nil }
                    )
                end
                if kick ~= nil or scale ~= nil then
                    lastEffectAt = now
                end
            end

            local promptReady = lastPromptAt == nil
                or now - lastPromptAt >= config.minSecondsBetweenPrompts
            if not settings.sharePrompt then
                table.insert(dropped, "prompt_opted_out")
            elseif prompts >= config.promptsPerSession then
                table.insert(dropped, "prompt_session_limit")
            elseif not promptReady then
                table.insert(dropped, "prompt_too_soon")
            else
                local captureAt = peak + beat.captureAfterSeconds
                table.insert(steps, { at = captureAt, action = "capture", name = nil, value = nil })
                table.insert(steps, {
                    at = captureAt + beat.promptAfterCaptureSeconds,
                    action = "share_prompt",
                    name = nil,
                    value = nil,
                })
                prompts += 1
                lastPromptAt = now
            end

            table.sort(steps, function(a: Step, b: Step): boolean
                if a.at ~= b.at then
                    return a.at < b.at
                end
                return (RANK[a.action] or 9) < (RANK[b.action] or 9)
            end)
            return { momentId = moment.id, kind = moment.kind, steps = steps, dropped = dropped }
        end,
        promptsShown = function(_self: Director): number
            return prompts
        end,
    }
    return director
end

return MomentDirector
