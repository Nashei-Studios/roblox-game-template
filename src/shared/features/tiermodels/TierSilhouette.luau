--!strict
--[[
    The "black and white threshold capture" as a pure function (bar W16). Rasterizes the parts of a
    model into two occupancy masks, a front view (x over y) and a side view (z over y), on a FIXED
    frame in studs, so a bigger rock differs from a smaller one and a spike differs from a dome.
    `duplicates` lists the pairs of tiers whose masks overlap more than `maxOverlap` in BOTH views
    (the same idea as PickaxeLadder rejecting two pickaxes that look alike).

    Exactness: a cell is filled when any point of any part along the view direction is inside the
    part, tested with TierSurface.contains (exact for blocks, balls, cylinders and wedges at any
    rotation), sampled at half a cell. A thin feature narrower than half a cell can be missed;
    keep the grid fine enough for the thinnest part that must read. The real check is still a
    threshold capture in Studio; this keeps two clones out of the repo.
]]

local TierModelSource = require("../../ports/TierModelSource")
local TierSurface = require("./TierSurface")

export type PartSpec = TierModelSource.PartSpec

export type Frame = {
    -- Cells per side of the square raster.
    grid: number,
    -- Studs from the node origin to each side of the frame (x and z).
    halfWidth: number,
    -- Studs above the base the frame spans (y from 0 to height).
    height: number,
    -- Two tiers whose masks overlap more than this in both views count as the same shape.
    maxOverlap: number,
}

export type Mask = { front: { boolean }, side: { boolean } }

export type Entry = { id: string, parts: { PartSpec } }

export type Clash = { first: string, second: string, overlap: number }

type Box = { minA: number, maxA: number, minY: number, maxY: number }

local TierSilhouette = {}

-- Corners of the part's box after yaw (Y), pitch (X) and roll (Z), plus its offset.
local function corners(spec: PartSpec): { { number } }
    local yaw, pitch, roll = math.rad(spec.yawDeg), math.rad(spec.pitchDeg), math.rad(spec.rollDeg)
    local cy, sy = math.cos(yaw), math.sin(yaw)
    local cp, sp = math.cos(pitch), math.sin(pitch)
    local cr, sr = math.cos(roll), math.sin(roll)
    local result: { { number } } = {}
    for _, sx in { -0.5, 0.5 } do
        for _, sh in { -0.5, 0.5 } do
            for _, sz in { -0.5, 0.5 } do
                local x, y, z = sx * spec.size.x, sh * spec.size.y, sz * spec.size.z
                -- roll about Z
                local x1, y1 = x * cr - y * sr, x * sr + y * cr
                -- pitch about X
                local y2, z2 = y1 * cp - z * sp, y1 * sp + z * cp
                -- yaw about Y
                local x3, z3 = x1 * cy + z2 * sy, -x1 * sy + z2 * cy
                table.insert(result, { x3 + spec.offset.x, y2 + spec.offset.y, z3 + spec.offset.z })
            end
        end
    end
    return result
end

local function boxes(spec: PartSpec): (Box, Box)
    local front = { minA = math.huge, maxA = -math.huge, minY = math.huge, maxY = -math.huge }
    local side = { minA = math.huge, maxA = -math.huge, minY = math.huge, maxY = -math.huge }
    for _, corner in corners(spec) do
        front.minA = math.min(front.minA, corner[1])
        front.maxA = math.max(front.maxA, corner[1])
        front.minY = math.min(front.minY, corner[2])
        front.maxY = math.max(front.maxY, corner[2])
        side.minA = math.min(side.minA, corner[3])
        side.maxA = math.max(side.maxA, corner[3])
        side.minY = math.min(side.minY, corner[2])
        side.maxY = math.max(side.maxY, corner[2])
    end
    return front, side
end

local function emptyGrid(cells: number): { boolean }
    local grid: { boolean } = table.create(cells, false)
    return grid
end

-- Cell indices (1 to grid) whose centers fall inside [low, high], where cell k spans
-- [(k - 1) * width - origin, k * width - origin].
local function cellRange(
    low: number,
    high: number,
    origin: number,
    width: number,
    grid: number
): (number, number)
    local first = math.max(1, math.floor((low + origin) / width) + 1)
    local last = math.min(grid, math.ceil((high + origin) / width))
    return first, last
end

--- Both masks of a model on `frame`. Cell (column, row) is stored at (row - 1) * grid + column,
--- row 1 at the base.
function TierSilhouette.raster(parts: { PartSpec }, frame: Frame): Mask
    local size = frame.grid
    local mask: Mask = { front = emptyGrid(size * size), side = emptyGrid(size * size) }
    local cell = frame.halfWidth * 2 / size
    local rowHeight = frame.height / size
    local step = cell / 2
    for _, spec in parts do
        local front, side = boxes(spec)
        local firstRow, lastRow = cellRange(front.minY, front.maxY, 0, rowHeight, size)
        local firstColumn, lastColumn =
            cellRange(front.minA, front.maxA, frame.halfWidth, cell, size)
        for row = firstRow, lastRow do
            local y = (row - 0.5) * rowHeight
            for column = firstColumn, lastColumn do
                local index = (row - 1) * size + column
                if not mask.front[index] then
                    local x = (column - 0.5) * cell - frame.halfWidth
                    local z = side.minA
                    while z <= side.maxA do
                        if TierSurface.contains(spec, x, y, z) then
                            mask.front[index] = true
                            break
                        end
                        z += step
                    end
                end
            end
        end
        local sideFirst, sideLast = cellRange(side.minA, side.maxA, frame.halfWidth, cell, size)
        for row = firstRow, lastRow do
            local y = (row - 0.5) * rowHeight
            for column = sideFirst, sideLast do
                local index = (row - 1) * size + column
                if not mask.side[index] then
                    local z = (column - 0.5) * cell - frame.halfWidth
                    local x = front.minA
                    while x <= front.maxA do
                        if TierSurface.contains(spec, x, y, z) then
                            mask.side[index] = true
                            break
                        end
                        x += step
                    end
                end
            end
        end
    end
    return mask
end

local function intersectionOverUnion(first: { boolean }, second: { boolean }): number
    local both, either = 0, 0
    for index = 1, #first do
        local inFirst, inSecond = first[index], second[index]
        if inFirst or inSecond then
            either += 1
            if inFirst and inSecond then
                both += 1
            end
        end
    end
    if either == 0 then
        return 1
    end
    return both / either
end

--- How alike two masks are, 0 to 1: the LOWER of the two views, because two shapes only read as
--- one when they match from the front and from the side.
function TierSilhouette.overlap(first: Mask, second: Mask): number
    return math.min(
        intersectionOverUnion(first.front, second.front),
        intersectionOverUnion(first.side, second.side)
    )
end

--- Every pair of entries whose silhouettes overlap more than `frame.maxOverlap`.
function TierSilhouette.duplicates(entries: { Entry }, frame: Frame): { Clash }
    local masks: { Mask } = {}
    for _, entry in entries do
        table.insert(masks, TierSilhouette.raster(entry.parts, frame))
    end
    local clashes: { Clash } = {}
    for first = 1, #entries do
        for second = first + 1, #entries do
            local overlap = TierSilhouette.overlap(masks[first], masks[second])
            if overlap > frame.maxOverlap then
                table.insert(
                    clashes,
                    { first = entries[first].id, second = entries[second].id, overlap = overlap }
                )
            end
        end
    end
    return clashes
end

--- The front view as text ("#" filled, "." empty), top row first. For reviews and the README.
function TierSilhouette.render(mask: Mask, frame: Frame, side: boolean?): string
    local cells = if side == true then mask.side else mask.front
    local lines: { string } = {}
    for row = frame.grid, 1, -1 do
        local line = ""
        for column = 1, frame.grid do
            line ..= if cells[(row - 1) * frame.grid + column] then "#" else "."
        end
        table.insert(lines, line)
    end
    return table.concat(lines, "\n")
end

return TierSilhouette
