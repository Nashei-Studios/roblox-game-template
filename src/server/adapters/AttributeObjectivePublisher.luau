--!strict
--[[
    Adapter: ObjectivePublisher over attributes of one instance (ADR 0049). The engine object is
    injected as a `set` function, so this file loads under Lune and is tested with a fake. The
    attributes are `<prefix>Phase`, `Beat`, `Progress`, `Target`, `ClosesAt`, `NextAt` and
    `Completed`; the client presenter listens to them. Values are only written when they change,
    so a one-second tick does not fire change signals for nothing.
]]

-- Structurally identical to ports/ObjectivePublisher.luau (local so this file loads under Lune).
type View = {
    phase: "waiting" | "open",
    beat: "idle" | "buildup" | "drop" | "fail",
    progress: number,
    target: number,
    closesAt: number,
    nextAt: number,
    completed: number,
}
type ObjectivePublisher = { publish: (self: ObjectivePublisher, view: View) -> () }

export type Deps = {
    -- Instance:SetAttribute bound to the carrier instance (Workspace in production).
    set: (name: string, value: string | number) -> (),
    -- Attribute name prefix, for example "Objective".
    prefix: string,
}

local AttributeObjectivePublisher = {}

function AttributeObjectivePublisher.new(deps: Deps): ObjectivePublisher
    local last: { [string]: string | number } = {}
    local function write(suffix: string, value: string | number)
        if last[suffix] ~= value then
            last[suffix] = value
            deps.set(`{deps.prefix}{suffix}`, value)
        end
    end
    local publisher: ObjectivePublisher = {
        publish = function(_self: ObjectivePublisher, view: View)
            write("Phase", view.phase)
            write("Beat", view.beat)
            write("Progress", view.progress)
            write("Target", view.target)
            write("ClosesAt", view.closesAt)
            write("NextAt", view.nextAt)
            write("Completed", view.completed)
        end,
    }
    return publisher
end

return AttributeObjectivePublisher
