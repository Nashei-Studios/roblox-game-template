--!strict
--[[
    Port: make the view of a shared objective readable by clients (ADR 0049). Server side. The
    adapter src/server/adapters/AttributeObjectivePublisher writes it as attributes of an
    instance; a game with another transport (a remote, a StringValue) implements the same port.
    The client only reads; no client path writes the objective.
]]

export type View = {
    phase: "waiting" | "open",
    beat: "idle" | "buildup" | "drop" | "fail",
    progress: number,
    target: number,
    closesAt: number,
    nextAt: number,
    completed: number,
}

export type ObjectivePublisher = {
    publish: (self: ObjectivePublisher, view: View) -> (),
}

return {}
