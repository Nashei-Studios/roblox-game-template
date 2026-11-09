--!strict
--[[
    Geometry of the 3-step podium as plain numbers (no Vector3, so it loads under Lune). Local
    space of the podium: x to the right, y up, z toward the viewer; the origin is the bottom
    center of the middle step. Place 1 stands in the middle and is the tallest, place 2 on the
    left and place 3 on the right, as on a sports podium.
]]

local PodiumConfig = require("./PodiumConfig")

export type Point = { x: number, y: number, z: number }

export type Slot = {
    rank: number,
    -- Center of the step block.
    stepCenter: Point,
    stepSize: Point,
    -- Where the statue's feet stand (top center of the step).
    standPoint: Point,
    -- Where the name plate hangs: on the front face of the step.
    platePoint: Point,
}

local PodiumLayout = {}

--- The three slots, indexed by rank (1 to 3).
function PodiumLayout.slots(layout: PodiumConfig.Layout): { Slot }
    local pitch = layout.stepWidth + layout.stepGap
    local offsets = { 0, -pitch, pitch }
    local slots: { Slot } = {}
    for rank = 1, PodiumConfig.PLACES do
        local height = layout.stepHeights[rank]
        local x = offsets[rank]
        table.insert(slots, {
            rank = rank,
            stepCenter = { x = x, y = height / 2, z = 0 },
            stepSize = { x = layout.stepWidth, y = height, z = layout.stepDepth },
            standPoint = { x = x, y = height, z = 0 },
            platePoint = { x = x, y = height / 2, z = layout.stepDepth / 2 },
        })
    end
    return slots
end

--- Footprint of the whole podium: total width, height of the tallest step and depth.
function PodiumLayout.footprint(layout: PodiumConfig.Layout): Point
    local width = layout.stepWidth * PodiumConfig.PLACES
        + layout.stepGap * (PodiumConfig.PLACES - 1)
    return { x = width, y = layout.stepHeights[1], z = layout.stepDepth }
end

return PodiumLayout
