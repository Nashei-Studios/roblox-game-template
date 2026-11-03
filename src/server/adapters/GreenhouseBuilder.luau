--!strict
--[[
    Adapter: builds the greenhouse world in Workspace from PlotLayout at runtime (ADR 0020). No
    logic lives here: the geometry comes from the pure PlotLayout (tested under Lune); this file
    only turns boxes into Parts. It touches the engine, so the coverage gate excludes it
    (ADR 0017): it is checked by a Studio playtest, not by Lune. Nothing is built by hand in Studio.

    Each parcel is named "Plot<N>" and carries the attribute "Plot" = N plus a ClickDetector; the
    client listens to the click and sends an intent. The server decides what the click does.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GreenhouseData = require(ReplicatedStorage.Shared.features.greenhouse.GreenhouseData)
local PlotLayout = require(ReplicatedStorage.Shared.features.greenhouse.PlotLayout)

local FOLDER_NAME = "GreenhouseWorld"
-- Click range in studs; chosen, not measured.
local CLICK_DISTANCE = 24

export type GreenhouseBuilder = {
    -- Creates the world folder and every Part. Call once at server start.
    build: (self: GreenhouseBuilder) -> (),
}

local GreenhouseBuilderModule = {}

local function colorFor(kind: PlotLayout.PartKind): Color3
    if kind == "floor" then
        return Color3.fromRGB(96, 120, 84)
    elseif kind == "spawn" then
        return Color3.fromRGB(70, 140, 255)
    end
    return Color3.fromRGB(150, 110, 70)
end

local function buildPart(folder: Folder, part: PlotLayout.Part)
    local instance: BasePart
    if part.kind == "spawn" then
        local spawn = Instance.new("SpawnLocation")
        spawn.Duration = 0
        spawn.Neutral = true
        instance = spawn
    else
        instance = Instance.new("Part")
    end
    instance.Name = if part.kind == "parcel" then `Plot{part.plot}` else part.kind
    instance.Anchored = true
    instance.Size = Vector3.new(part.sizeX, part.sizeY, part.sizeZ)
    instance.Position = Vector3.new(part.x, part.y, part.z)
    instance.Color = colorFor(part.kind)
    instance.Material = Enum.Material.SmoothPlastic
    if part.kind == "parcel" then
        instance:SetAttribute("Plot", part.plot)
        local detector = Instance.new("ClickDetector")
        detector.MaxActivationDistance = CLICK_DISTANCE
        detector.Parent = instance
    end
    instance.Parent = folder
end

function GreenhouseBuilderModule.new(): GreenhouseBuilder
    local builder: GreenhouseBuilder = {
        build = function(_self: GreenhouseBuilder)
            local previous = Workspace:FindFirstChild(FOLDER_NAME)
            if previous ~= nil then
                previous:Destroy()
            end
            local folder = Instance.new("Folder")
            folder.Name = FOLDER_NAME
            for _, part in PlotLayout.build(GreenhouseData.ABSOLUTE_MAX_PLOTS) do
                buildPart(folder, part)
            end
            folder.Parent = Workspace
        end,
    }
    return builder
end

return GreenhouseBuilderModule
