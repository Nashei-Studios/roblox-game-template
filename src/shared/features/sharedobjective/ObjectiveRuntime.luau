--!strict
--[[
    Drives a SharedObjective from the engine without owning an engine call (ADR 0049): one
    `step()` per second reads the clock and the players present, ticks the state machine, pays
    the completions through an injected sink and publishes the view through the port. Pure:
    loads under Lune; the server script supplies `now`, `present` and the loop.

    A reward that cannot be delivered (the profile is gone) is reported through `onError` with
    its user id; it is never swallowed and never retried here.
]]

local ObjectiveConfig = require("./ObjectiveConfig")
local ObjectivePublisher = require("../../ports/ObjectivePublisher")
local SharedObjective = require("./SharedObjective")

export type Deps = {
    config: ObjectiveConfig.ObjectiveConfig,
    publisher: ObjectivePublisher.ObjectivePublisher,
    -- Server clock in seconds (workspace:GetServerTimeNow in production).
    now: () -> number,
    present: () -> { number },
    -- Pays one participant. Returns false when it could not be delivered.
    reward: (completion: SharedObjective.Completion) -> boolean,
    -- Called once per completed objective with every completion, after the rewards.
    onCompleted: ((completions: { SharedObjective.Completion }) -> ())?,
    onError: (message: string) -> (),
}

export type Runtime = {
    -- Units the game already accepted for a player. A client has no path to call this.
    contribute: (self: Runtime, userId: number, units: number) -> number,
    step: (self: Runtime) -> { SharedObjective.Event },
    view: (self: Runtime) -> SharedObjective.View,
}

local ObjectiveRuntime = {}

function ObjectiveRuntime.new(deps: Deps): Runtime
    local objective = SharedObjective.new(deps.config, deps.now())

    local function publish()
        deps.publisher:publish(objective:view(deps.now()))
    end
    publish()

    local runtime: Runtime = {
        contribute = function(_self: Runtime, userId: number, units: number): number
            return objective:contribute(userId, units, deps.now())
        end,
        step = function(_self: Runtime): { SharedObjective.Event }
            local events = objective:tick(deps.now(), deps.present())
            for _, event in events do
                if event.kind == "completed" then
                    for _, completion in event.completions do
                        if not deps.reward(completion) then
                            deps.onError(`reward for {completion.userId} was not delivered`)
                        end
                    end
                    if deps.onCompleted ~= nil then
                        deps.onCompleted(event.completions)
                    end
                end
            end
            publish()
            return events
        end,
        view = function(_self: Runtime): SharedObjective.View
            return objective:view(deps.now())
        end,
    }
    return runtime
end

return ObjectiveRuntime
