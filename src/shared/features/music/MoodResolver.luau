--!strict
--[[
    Which mood the music is in, from game state read through a port (ADR 0050). Pure: loads
    under Lune; the clock and the signals are injected. The game declares ordered rules in data;
    the first rule that is active wins, and a fallback mood closes the list.

    Rule kinds:
      while    active while the signal is on.
      hold     active for `holdSeconds` after the signal turns on (a one-shot like a result or
               a level up) or, with `onFall`, after it turns off (a drop after a build-up).
      sustain  the signal must stay on for `enterSeconds` to start, and the rule lingers for
               `holdSeconds` after it stops (a run that should not flicker).
    Rules are listed from the highest priority to the lowest. Mood names are free-form and are
    checked against the moods of the music config by `validate`.
]]

local MoodSignals = require("../../ports/MoodSignals")

export type Rule = {
    mood: string,
    signal: string,
    -- "while" | "hold" | "sustain" (plain string: stable solver).
    kind: string,
    holdSeconds: number,
    enterSeconds: number,
    -- hold only: start the hold when the signal turns off instead of on.
    onFall: boolean,
}

export type MoodRules = {
    rules: { Rule },
    fallback: string,
}

export type Deps = {
    rules: MoodRules,
    signals: MoodSignals.MoodSignals,
}

export type Resolver = {
    -- Reads the signals at `now` (seconds, monotonic) and returns the mood to play.
    mood: (self: Resolver, now: number) -> string,
}

local MoodResolver = {}

local KINDS = { ["while"] = true, hold = true, sustain = true }

--- Shorthand constructors so a game config reads as a list of sentences.
function MoodResolver.whileOn(mood: string, signal: string): Rule
    return {
        mood = mood,
        signal = signal,
        kind = "while",
        holdSeconds = 0,
        enterSeconds = 0,
        onFall = false,
    }
end

function MoodResolver.holdAfter(
    mood: string,
    signal: string,
    seconds: number,
    onFall: boolean
): Rule
    return {
        mood = mood,
        signal = signal,
        kind = "hold",
        holdSeconds = seconds,
        enterSeconds = 0,
        onFall = onFall,
    }
end

function MoodResolver.sustained(
    mood: string,
    signal: string,
    enterSeconds: number,
    holdSeconds: number
): Rule
    return {
        mood = mood,
        signal = signal,
        kind = "sustain",
        holdSeconds = holdSeconds,
        enterSeconds = enterSeconds,
        onFall = false,
    }
end

--- One human-readable problem per invalid value (empty when valid). `knownMoods` is the set of
--- mood names of the music config, so a rule cannot point at a mood with no playlist.
function MoodResolver.validate(rules: MoodRules, knownMoods: { [string]: boolean }): { string }
    local problems: { string } = {}
    if rules.fallback == "" or not knownMoods[rules.fallback] then
        table.insert(problems, `mood: fallback "{rules.fallback}" is not a known mood`)
    end
    for index, rule in rules.rules do
        local label = `mood rule {index} ("{rule.mood}")`
        if not knownMoods[rule.mood] then
            table.insert(problems, `{label} uses an unknown mood`)
        end
        if rule.signal == "" then
            table.insert(problems, `{label} needs a signal`)
        end
        if not KINDS[rule.kind] then
            table.insert(problems, `{label} has unknown kind "{rule.kind}"`)
        end
        if rule.holdSeconds ~= rule.holdSeconds or rule.holdSeconds < 0 then
            table.insert(problems, `{label} holdSeconds must be zero or positive`)
        end
        if rule.enterSeconds ~= rule.enterSeconds or rule.enterSeconds < 0 then
            table.insert(problems, `{label} enterSeconds must be zero or positive`)
        end
        if rule.kind == "hold" and rule.holdSeconds <= 0 then
            table.insert(problems, `{label} is a hold and needs holdSeconds above zero`)
        end
    end
    return problems
end

type State = {
    wasOn: boolean,
    activeUntil: number,
    onSince: number?,
    lastSustained: number,
}

function MoodResolver.new(deps: Deps): Resolver
    local states: { State } = {}
    for _ = 1, #deps.rules.rules do
        table.insert(
            states,
            { wasOn = false, activeUntil = -math.huge, onSince = nil, lastSustained = -math.huge }
        )
    end

    local function active(rule: Rule, state: State, now: number): boolean
        local on = deps.signals:isOn(rule.signal)
        if rule.kind == "while" then
            return on
        elseif rule.kind == "hold" then
            local edge = if rule.onFall then (state.wasOn and not on) else (on and not state.wasOn)
            if edge then
                state.activeUntil = now + rule.holdSeconds
            end
            state.wasOn = on
            return now < state.activeUntil
        end
        -- sustain
        if on then
            if state.onSince == nil then
                state.onSince = now
            end
            if now - (state.onSince :: number) >= rule.enterSeconds then
                state.lastSustained = now
                return true
            end
        else
            state.onSince = nil
        end
        return now - state.lastSustained < rule.holdSeconds
    end

    local resolver: Resolver = {
        mood = function(_self: Resolver, now: number): string
            local chosen: string? = nil
            -- Every rule is updated each call so a hold sees its edge even under a higher rule.
            for index, rule in deps.rules.rules do
                if active(rule, states[index], now) and chosen == nil then
                    chosen = rule.mood
                end
            end
            return chosen or deps.rules.fallback
        end,
    }
    return resolver
end

return MoodResolver
