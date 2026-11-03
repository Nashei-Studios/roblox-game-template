--!strict
--[[
    Funnel events of the first 60 seconds (design: games/2026-11-reef). Pure: the analytics
    tracker is injected as a function. Each event is sent at most once per session.

    session_start     : the profile loaded.
    tutorial_start    : a player with no catches joined (the cast prompt is shown).
    first_action      : the first accepted cast of the session.
    tutorial_complete : the first rod purchase of a tutorial player.
]]

export type Deps = {
    -- AnalyticsTracker.track; returns false for an unknown event name.
    track: (name: string, userId: number, sessionIndex: number) -> boolean,
}

export type Funnel = {
    onJoin: (self: Funnel, userId: number, sessionIndex: number, totalCatches: number) -> (),
    onCastAccepted: (self: Funnel, userId: number) -> (),
    onRodBought: (self: Funnel, userId: number) -> (),
    forget: (self: Funnel, userId: number) -> (),
}

type State = {
    sessionIndex: number,
    inTutorial: boolean,
    firstActionSent: boolean,
    tutorialCompleteSent: boolean,
}

local FunnelModule = {}

function FunnelModule.new(deps: Deps): Funnel
    local states: { [number]: State } = {}

    local funnel: Funnel = {
        onJoin = function(
            _self: Funnel,
            userId: number,
            sessionIndex: number,
            totalCatches: number
        )
            local inTutorial = totalCatches == 0
            states[userId] = {
                sessionIndex = sessionIndex,
                inTutorial = inTutorial,
                firstActionSent = false,
                tutorialCompleteSent = false,
            }
            deps.track("session_start", userId, sessionIndex)
            if inTutorial then
                deps.track("tutorial_start", userId, sessionIndex)
            end
        end,
        onCastAccepted = function(_self: Funnel, userId: number)
            local state = states[userId]
            if state == nil or state.firstActionSent then
                return
            end
            state.firstActionSent = true
            deps.track("first_action", userId, state.sessionIndex)
        end,
        onRodBought = function(_self: Funnel, userId: number)
            local state = states[userId]
            if state == nil or not state.inTutorial or state.tutorialCompleteSent then
                return
            end
            state.tutorialCompleteSent = true
            deps.track("tutorial_complete", userId, state.sessionIndex)
        end,
        forget = function(_self: Funnel, userId: number)
            states[userId] = nil
        end,
    }
    return funnel
end

return FunnelModule
