--!strict
--[[
    The three stages as DATA (ADR 0020). Pure: loads under Lune. A stage is a list of segments
    laid end to end along +Z: platforms to run on, gaps to jump, and moving platforms that sway
    sideways. `StageLayout` turns a spec into boxes; `StageBuilder` (server adapter) turns the
    boxes into Parts. Lengths are in studs.

    MAX_GAP is a conservative limit (a default humanoid jumps farther than this at base speed).
    It has not been measured in the engine: confirm it in a playtest.
]]

export type Segment =
    { kind: "platform", length: number }
    | { kind: "gap", length: number }
    | { kind: "mover", length: number, travel: number, period: number }

export type StageSpec = { segments: { Segment } }

local StageSpecs = {}

-- Widest gap a player is expected to clear at the base walk speed.
StageSpecs.MAX_GAP = 8

-- Stage 1 is the tutorial stage: one gap and one moving platform (design, seconds 15-40).
StageSpecs.all = {
    {
        segments = {
            { kind = "platform", length = 24 },
            { kind = "gap", length = 6 },
            { kind = "platform", length = 18 },
            { kind = "mover", length = 14, travel = 5, period = 4 },
            { kind = "platform", length = 18 },
        },
    },
    {
        segments = {
            { kind = "platform", length = 22 },
            { kind = "gap", length = 7 },
            { kind = "platform", length = 14 },
            { kind = "mover", length = 16, travel = 6, period = 3.5 },
            { kind = "gap", length = 7 },
            { kind = "platform", length = 14 },
            { kind = "mover", length = 16, travel = 6, period = 3 },
            { kind = "platform", length = 20 },
        },
    },
    {
        segments = {
            { kind = "platform", length = 20 },
            { kind = "gap", length = 8 },
            { kind = "platform", length = 10 },
            { kind = "gap", length = 8 },
            { kind = "mover", length = 18, travel = 7, period = 3 },
            { kind = "platform", length = 10 },
            { kind = "gap", length = 8 },
            { kind = "mover", length = 18, travel = 7, period = 2.5 },
            { kind = "gap", length = 8 },
            { kind = "platform", length = 12 },
            { kind = "mover", length = 18, travel = 7, period = 2 },
            { kind = "platform", length = 24 },
        },
    },
} :: { StageSpec }

--- One human-readable problem per rule broken (empty when the spec is playable).
function StageSpecs.validate(spec: StageSpec): { string }
    local problems: { string } = {}
    local count = #spec.segments
    if count == 0 then
        table.insert(problems, "a stage needs at least one segment")
        return problems
    end
    if spec.segments[1].kind == "gap" then
        table.insert(problems, "a stage cannot start with a gap")
    end
    if spec.segments[count].kind == "gap" then
        table.insert(problems, "a stage cannot end with a gap")
    end
    for index, segment in spec.segments do
        if segment.length <= 0 then
            table.insert(problems, `segment {index} has a non-positive length`)
        end
        if segment.kind == "gap" then
            if segment.length > StageSpecs.MAX_GAP then
                table.insert(problems, `segment {index} is a gap wider than {StageSpecs.MAX_GAP}`)
            end
            local previous = spec.segments[index - 1]
            if previous ~= nil and previous.kind == "gap" then
                table.insert(problems, `segment {index} is a gap next to another gap`)
            end
        elseif segment.kind == "mover" then
            if segment.travel <= 0 or segment.period <= 0 then
                table.insert(problems, `segment {index} needs a positive travel and period`)
            end
        end
    end
    return problems
end

return StageSpecs
