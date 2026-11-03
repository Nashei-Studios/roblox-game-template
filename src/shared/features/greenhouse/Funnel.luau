--!strict
--[[
    Funnel events of the first 60 seconds (design: games/2026-11-greenhouse). Pure: the analytics
    tracker is injected as a function. Each event is sent at most once per session.

    session_start     : the profile loaded.
    tutorial_start    : a player with no harvest yet joined (the plant prompt is shown).
    first_action      : the first accepted plant of the session.
    tutorial_complete : the first accepted sell of a tutorial player (the HUD then offers the
                        second plot, which is what the design shows at second 55-60).
    A returning player (totalHarvests > 0 at join) gets neither tutorial event.
]]

export type Deps = {
    -- AnalyticsTracker.track; returns false for an unknown event name.
    track: (name: string, userId: number, sessionIndex: number) -> boolean,
}

export type Funnel = {
    onJoin: (self: Funnel, userId: number, sessionIndex: number, totalHarvests: number) -> (),
    onPlantAccepted: (self: Funnel, userId: number) -> (),
    onSellAccepted: (self: Funnel, userId: number) -> (),
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
            totalHarvests: number
        )
            local inTutorial = totalHarvests == 0
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
        onPlantAccepted = function(_self: Funnel, userId: number)
            local state = states[userId]
            if state == nil or state.firstActionSent then
                return
            end
            state.firstActionSent = true
            deps.track("first_action", userId, state.sessionIndex)
        end,
        onSellAccepted = function(_self: Funnel, userId: number)
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
