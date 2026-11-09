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
}

local PodiumLayout = {}

-- Farthest a statue part may sit from its step center. A part beyond it (an accessory that did
-- not weld and stayed at the world origin) is a bug the stage removes and reports.
-- Size of the name tag of a place, in studs (the BillboardGui is scaled in studs, so the gaps
-- between neighbours hold at any resolution). Narrower than the pitch between steps.
PodiumLayout.TAG_WIDTH = 6 -- chosen, not measured
PodiumLayout.TAG_HEIGHT = 2.4 -- chosen, not measured
-- Height of the tag center above the podium base and its distance in front of the step face.
PodiumLayout.TAG_BASE_Y = 1.2 -- chosen, not measured: the center of every tag sits near the ground, in front of its step
PodiumLayout.TAG_OUT = 1.2 -- chosen, not measured: in front of the step

PodiumLayout.MAX_STATUE_RADIUS = 12 -- chosen, not measured: an R15 avatar with large accessories is under 6; scaled by the statue scale
-- How far the feet may sit from the step top before the stage corrects them, studs.
PodiumLayout.FEET_TOLERANCE = 0.2 -- chosen, not measured

--- Podium-local center of the name tag of a slot: above the front edge of its step.
function PodiumLayout.tagAnchor(slot: Slot): Point
    return {
        x = slot.stepCenter.x,
        y = PodiumLayout.TAG_BASE_Y,
        z = slot.stepSize.z / 2 + PodiumLayout.TAG_OUT,
    }
end

--- The stray radius for a statue scaled by `scale` (MAX_STATUE_RADIUS is for scale 1).
function PodiumLayout.strayRadius(scale: number): number
    return PodiumLayout.MAX_STATUE_RADIUS * scale
end

--- World Y of the HumanoidRootPart center that puts the feet on `topY`: step top, the hip height
--- of the humanoid and half the root part height. Never derived from a bounding box.
function PodiumLayout.rootCenterY(topY: number, hipHeight: number, rootHeight: number): number
    return topY + hipHeight + rootHeight / 2
end

--- Studs to move a statue (positive is up) so its lowest foot bottom meets `topY`; 0 when it is
--- already within FEET_TOLERANCE.
function PodiumLayout.feetShift(topY: number, lowestFootBottomY: number): number
    local delta = topY - lowestFootBottomY
    if math.abs(delta) <= PodiumLayout.FEET_TOLERANCE then
        return 0
    end
    return delta
end

--- Indices (into `points`) farther than `radius` from `center` in 3D.
function PodiumLayout.strays(points: { Point }, center: Point, radius: number): { number }
    local found: { number } = {}
    for index, point in points do
        local dx, dy, dz = point.x - center.x, point.y - center.y, point.z - center.z
        if dx * dx + dy * dy + dz * dz > radius * radius then
            table.insert(found, index)
        end
    end
    return found
end

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
