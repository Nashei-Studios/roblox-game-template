--!strict
--[[
    Pure geometry of the greenhouse world (ADR 0020): a floor, a spawn pad and one parcel per
    possible plot, generated from data so nothing is hand-built in Studio. The engine adapter
    `GreenhouseBuilder` turns these boxes into Parts; this file only does the arithmetic and is
    tested under Lune. All coordinates are studs, y up, the origin at the floor center.
]]

export type PartKind = "floor" | "spawn" | "parcel"

export type Part = {
    kind: PartKind,
    -- 1-based plot number for parcels, 0 for the rest.
    plot: number,
    x: number,
    y: number,
    z: number,
    sizeX: number,
    sizeY: number,
    sizeZ: number,
}

local PlotLayout = {}

PlotLayout.COLUMNS = 5
PlotLayout.PARCEL_SIZE = 6
PlotLayout.GAP = 3
-- Extra floor around the parcel grid, and the depth of the spawn strip in front of it.
PlotLayout.MARGIN = 6
PlotLayout.SPAWN_DEPTH = 8
PlotLayout.FLOOR_THICKNESS = 1

--- Boxes for `plotCount` parcels. Parcels fill rows of COLUMNS from the far side; the spawn pad
--- sits in front of the first row.
function PlotLayout.build(plotCount: number): { Part }
    local pitch = PlotLayout.PARCEL_SIZE + PlotLayout.GAP
    local columns = math.min(PlotLayout.COLUMNS, math.max(1, plotCount))
    local rows = math.max(1, math.ceil(plotCount / PlotLayout.COLUMNS))
    local gridWidth = columns * pitch - PlotLayout.GAP
    local gridDepth = rows * pitch - PlotLayout.GAP
    local floorWidth = gridWidth + 2 * PlotLayout.MARGIN
    local floorDepth = gridDepth + 2 * PlotLayout.MARGIN + PlotLayout.SPAWN_DEPTH
    local thickness = PlotLayout.FLOOR_THICKNESS

    local parts: { Part } = {}
    -- Floor top surface is y = 0. The grid occupies z in [-gridDepth/2 - spawn/2 .. ] shifted
    -- so that the spawn strip is on the +z side.
    local floorCenterZ = 0
    table.insert(parts, {
        kind = "floor",
        plot = 0,
        x = 0,
        y = -thickness / 2,
        z = floorCenterZ,
        sizeX = floorWidth,
        sizeY = thickness,
        sizeZ = floorDepth,
    })
    local gridFrontZ = floorDepth / 2 - PlotLayout.SPAWN_DEPTH - PlotLayout.MARGIN
    table.insert(parts, {
        kind = "spawn",
        plot = 0,
        x = 0,
        y = 0.25,
        z = floorDepth / 2 - PlotLayout.SPAWN_DEPTH / 2,
        sizeX = 6,
        sizeY = 0.5,
        sizeZ = 6,
    })
    for plot = 1, plotCount do
        local column = (plot - 1) % PlotLayout.COLUMNS
        local row = (plot - 1) // PlotLayout.COLUMNS
        table.insert(parts, {
            kind = "parcel",
            plot = plot,
            x = -gridWidth / 2 + PlotLayout.PARCEL_SIZE / 2 + column * pitch,
            y = 0.25,
            z = gridFrontZ - PlotLayout.PARCEL_SIZE / 2 - row * pitch,
            sizeX = PlotLayout.PARCEL_SIZE,
            sizeY = 0.5,
            sizeZ = PlotLayout.PARCEL_SIZE,
        })
    end
    return parts
end

return PlotLayout
