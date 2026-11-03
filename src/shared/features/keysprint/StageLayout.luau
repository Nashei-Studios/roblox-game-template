--!strict
--[[
    Pure geometry of a stage (ADR 0020): turns a StageSpec into boxes in stage space, with no
    engine types (plain numbers, so it loads under Lune and is unit-tested). The stage runs along
    +Z from z = 0; the deck top is at y = 0; x = 0 is the centre line. The server adapter
    `StageBuilder` offsets the boxes and creates the Parts.
]]

local StageSpecs = require("./StageSpecs")

export type PartKind = "start" | "platform" | "mover" | "finish"

export type Part = {
    kind: PartKind,
    -- Centre of the box.
    x: number,
    y: number,
    z: number,
    sizeX: number,
    sizeY: number,
    sizeZ: number,
    -- Movers only: how far it sways each side along X, and seconds per full cycle.
    travel: number?,
    period: number?,
}

export type Point = { x: number, y: number, z: number }

export type Layout = {
    parts: { Part },
    -- Sum of the segment lengths: the distance from the start gate to the finish line.
    pathLength: number,
    -- Where a player stands when the stage begins (the checkpoint).
    spawn: Point,
    -- The finish line: the start of the finish pad.
    finish: Point,
}

local StageLayout = {}

StageLayout.DECK_WIDTH = 12
StageLayout.DECK_THICKNESS = 1
StageLayout.MOVER_WIDTH = 8
StageLayout.PAD_LENGTH = 8
-- Height above the deck where a character is placed (its feet clear the surface).
StageLayout.SPAWN_HEIGHT = 4

local DECK_CENTRE_Y = -StageLayout.DECK_THICKNESS / 2

function StageLayout.compute(spec: StageSpecs.StageSpec): Layout
    local parts: { Part } = {}
    table.insert(parts, {
        kind = "start",
        x = 0,
        y = DECK_CENTRE_Y,
        z = -StageLayout.PAD_LENGTH / 2,
        sizeX = StageLayout.DECK_WIDTH,
        sizeY = StageLayout.DECK_THICKNESS,
        sizeZ = StageLayout.PAD_LENGTH,
    })
    local cursor = 0
    for _, segment in spec.segments do
        if segment.kind == "platform" then
            table.insert(parts, {
                kind = "platform",
                x = 0,
                y = DECK_CENTRE_Y,
                z = cursor + segment.length / 2,
                sizeX = StageLayout.DECK_WIDTH,
                sizeY = StageLayout.DECK_THICKNESS,
                sizeZ = segment.length,
            })
        elseif segment.kind == "mover" then
            table.insert(parts, {
                kind = "mover",
                x = 0,
                y = DECK_CENTRE_Y,
                z = cursor + segment.length / 2,
                sizeX = StageLayout.MOVER_WIDTH,
                sizeY = StageLayout.DECK_THICKNESS,
                sizeZ = segment.length,
                travel = segment.travel,
                period = segment.period,
            })
        end
        cursor += segment.length
    end
    table.insert(parts, {
        kind = "finish",
        x = 0,
        y = DECK_CENTRE_Y,
        z = cursor + StageLayout.PAD_LENGTH / 2,
        sizeX = StageLayout.DECK_WIDTH,
        sizeY = StageLayout.DECK_THICKNESS,
        sizeZ = StageLayout.PAD_LENGTH,
    })
    return {
        parts = parts,
        pathLength = cursor,
        spawn = { x = 0, y = StageLayout.SPAWN_HEIGHT, z = 0 },
        finish = { x = 0, y = 0, z = cursor },
    }
end

return StageLayout
