--!strict
--[[
    Adapter: builds the stages in Workspace from StageSpecs at runtime (ADR 0020). No logic
    lives here: the geometry comes from the pure StageLayout (tested under Lune); this file only
    turns boxes into Parts. It touches the engine, so the coverage gate excludes it (ADR 0017):
    it is checked by a Studio playtest, not by Lune. Nothing is built by hand in Studio.

    Each stage sits in its own lane, STAGE_SPACING studs apart along X, so stages never overlap.
    The finish pad is named "Finish" and carries the attribute "Stage" so the client can report
    a touch; the server decides whether the finish counts (StageRuns).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local StageLayout = require(ReplicatedStorage.Shared.features.keysprint.StageLayout)
local StageSpecs = require(ReplicatedStorage.Shared.features.keysprint.StageSpecs)

local STAGE_SPACING = 60
local FOLDER_NAME = "KeySprintStages"

export type StageBuilder = {
    -- Creates the stage folder and every Part. Call once at server start.
    build: (self: StageBuilder) -> (),
    -- Where a character stands at the start gate of `stage`.
    spawnPosition: (self: StageBuilder, stage: number) -> Vector3,
    -- Studs from the start gate to the finish line of `stage`.
    pathLength: (self: StageBuilder, stage: number) -> number,
}

local StageBuilderModule = {}

local function laneX(stage: number): number
    return (stage - 1) * STAGE_SPACING
end

local function colorFor(kind: StageLayout.PartKind): Color3
    if kind == "start" then
        return Color3.fromRGB(70, 140, 255)
    elseif kind == "finish" then
        return Color3.fromRGB(80, 200, 120)
    elseif kind == "mover" then
        return Color3.fromRGB(255, 170, 60)
    end
    return Color3.fromRGB(150, 150, 160)
end

local function buildPart(folder: Folder, stage: number, part: StageLayout.Part)
    local instance = Instance.new("Part")
    instance.Name = if part.kind == "finish" then "Finish" else part.kind
    instance.Anchored = true
    instance.Size = Vector3.new(part.sizeX, part.sizeY, part.sizeZ)
    local position = Vector3.new(laneX(stage) + part.x, part.y, part.z)
    instance.Position = position
    instance.Color = colorFor(part.kind)
    instance.Material = Enum.Material.SmoothPlastic
    instance:SetAttribute("Stage", stage)
    instance.Parent = folder
    local travel = part.travel
    local period = part.period
    if travel ~= nil and period ~= nil then
        local tween = TweenService:Create(
            instance,
            TweenInfo.new(period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            { Position = position + Vector3.new(travel, 0, 0) }
        )
        tween:Play()
    end
end

function StageBuilderModule.new(): StageBuilder
    local layouts: { StageLayout.Layout } = {}
    for _, spec in StageSpecs.all do
        table.insert(layouts, StageLayout.compute(spec))
    end

    local builder: StageBuilder = {
        build = function(_self: StageBuilder)
            local folder = Workspace:FindFirstChild(FOLDER_NAME)
            if folder ~= nil then
                folder:Destroy()
            end
            local created = Instance.new("Folder")
            created.Name = FOLDER_NAME
            for stage, layout in layouts do
                for _, part in layout.parts do
                    buildPart(created, stage, part)
                end
            end
            created.Parent = Workspace
        end,
        spawnPosition = function(_self: StageBuilder, stage: number): Vector3
            local layout = layouts[stage] or layouts[1]
            return Vector3.new(laneX(stage) + layout.spawn.x, layout.spawn.y, layout.spawn.z)
        end,
        pathLength = function(_self: StageBuilder, stage: number): number
            local layout = layouts[stage] or layouts[1]
            return layout.pathLength
        end,
    }
    return builder
end

return StageBuilderModule
