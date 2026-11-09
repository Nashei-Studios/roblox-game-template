--!strict
--[[
    Server presenter of the 3D podium (ADR 0055): builds the three steps, the avatar statues
    and the name plates as ordinary world instances, so they replicate to every client with no
    remote and no client script. It touches Instances, so it is excluded from the line-coverage
    gate; the rules (who stands where, the words, the colors, the geometry) live in
    features/podium and are tested under Lune.

    Statues: Players:CreateHumanoidModelFromUserId, scripts stripped, anchored, name tags off.
    With an idle animation configured only the root is anchored (the Motor6D chain follows it)
    and an Animator plays the loop; without one every part is anchored. A statue that fails to
    load leaves its plate, so the podium degrades to text instead of to an error.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local PodiumConfig = require(Shared.features.podium.PodiumConfig)
local PodiumLayout = require(Shared.features.podium.PodiumLayout)
local PodiumModel = require(Shared.features.podium.PodiumModel)
local RarityFx = require(Shared.features.rarity.RarityFx)

export type Deps = {
    config: PodiumConfig.PodiumConfig,
    -- Where the podium stands; the game keeps this CFrame in its world data, never in Studio.
    origin: CFrame,
    -- Folder (usually Workspace) the Podium3D model is parented to.
    parent: Instance,
    -- Parts allowed for the whole podium (PerfBudget.podium.maxParts).
    maxParts: number,
    onError: (message: string) -> (),
}

export type Stage = {
    -- Rebuilds only the places whose occupant changed; plates are rewritten when the text changed.
    render: (self: Stage, view: PodiumModel.View) -> (),
    destroy: (self: Stage) -> (),
}

type PlaceState = {
    userId: number?,
    statue: Model?,
    plate: TextLabel?,
    detail: TextLabel?,
    stroke: UIStroke?,
    step: Part,
}

local STEP_BASE_HEX = "#2B3148" -- chosen: dark slate the medal color is mixed into
local PLATE_PIXELS_PER_STUD = 40

local PodiumStage = {}

local function toColor(hex: string): Color3
    return Color3.fromHex(hex)
end

local function toVector(point: PodiumLayout.Point): Vector3
    return Vector3.new(point.x, point.y, point.z)
end

local function newPart(name: string, size: Vector3, cframe: CFrame): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = cframe
    part.Anchored = true
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    return part
end

local function newPlate(
    slot: PodiumLayout.Slot,
    root: CFrame,
    parent: Instance
): (Part, TextLabel, TextLabel, UIStroke)
    local face = newPart(
        `Plate{slot.rank}`,
        Vector3.new(slot.stepSize.x - 0.4, 1.4, 0.2),
        root * CFrame.new(slot.platePoint.x, 0.9, slot.platePoint.z + 0.1)
    )
    face.CanCollide = false
    face.CanQuery = false
    face.Material = Enum.Material.SmoothPlastic
    face.Color = toColor("#171C30")
    face.Parent = parent
    local gui = Instance.new("SurfaceGui")
    gui.Face = Enum.NormalId.Front
    gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.PixelsPerStud = PLATE_PIXELS_PER_STUD
    gui.AlwaysOnTop = false
    gui.Parent = face
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 3
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundTransparency = 1
    frame.Parent = gui
    stroke.Parent = frame
    local headline = Instance.new("TextLabel")
    headline.Name = "Headline"
    headline.Size = UDim2.fromScale(1, 0.58)
    headline.BackgroundTransparency = 1
    headline.TextScaled = true
    headline.Font = Enum.Font.GothamBold
    headline.TextColor3 = Color3.new(1, 1, 1)
    headline.Parent = frame
    local detail = Instance.new("TextLabel")
    detail.Name = "Detail"
    detail.Position = UDim2.fromScale(0, 0.58)
    detail.Size = UDim2.fromScale(1, 0.38)
    detail.BackgroundTransparency = 1
    detail.TextScaled = true
    detail.Font = Enum.Font.Gotham
    detail.TextColor3 = Color3.fromRGB(220, 226, 240)
    detail.Parent = frame
    return face, headline, detail, stroke
end

local function countParts(root: Instance): number
    local total = 0
    for _, descendant in root:GetDescendants() do
        if descendant:IsA("BasePart") then
            total += 1
        end
    end
    return total
end

local function prepareStatue(model: Model, animationId: string?, onError: (string) -> ())
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("Script") or descendant:IsA("LocalScript") then
            descendant:Destroy()
        end
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    if humanoid ~= nil then
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        humanoid.EvaluateStateMachine = false
    end
    local animated = animationId ~= nil and humanoid ~= nil and root ~= nil
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
            descendant.CanQuery = false
            descendant.Anchored = not animated
        end
    end
    if animated and root ~= nil and root:IsA("BasePart") then
        root.Anchored = true
    end
    if animated and humanoid ~= nil and animationId ~= nil then
        local animator: Animator = humanoid:FindFirstChildOfClass("Animator")
            or Instance.new("Animator")
        animator.Parent = humanoid
        local animation = Instance.new("Animation")
        animation.AnimationId = animationId
        local loaded, track = pcall(function()
            return animator:LoadAnimation(animation)
        end)
        if loaded then
            track.Looped = true
            track:Play()
        else
            onError(`podium idle animation failed to load: {tostring(track)}`)
        end
    end
end

--- Builds the steps and empty plates at `deps.origin`. Call `render` with each new view.
function PodiumStage.new(deps: Deps): Stage
    local root = Instance.new("Model")
    root.Name = "Podium3D"
    local slots = PodiumLayout.slots(deps.config.layout)
    local states: { PlaceState } = {}
    for _, slot in slots do
        local step = newPart(
            `Step{slot.rank}`,
            toVector(slot.stepSize),
            deps.origin * CFrame.new(toVector(slot.stepCenter))
        )
        step.Material = Enum.Material.Concrete
        step.Color = toColor(STEP_BASE_HEX)
        step.Parent = root
        local _face, headline, detail, stroke = newPlate(slot, deps.origin, root)
        table.insert(states, {
            userId = nil,
            statue = nil,
            plate = headline,
            detail = detail,
            stroke = stroke,
            step = step,
        })
    end
    root.Parent = deps.parent

    local function placeStatue(state: PlaceState, slot: PodiumLayout.Slot, userId: number)
        local built, model = pcall(function(): Model
            return Players:CreateHumanoidModelFromUserId(userId)
        end)
        if not built then
            deps.onError(`podium avatar for {userId} failed: {tostring(model)}`)
            return
        end
        prepareStatue(model, deps.config.idleAnimationId, deps.onError)
        model.Name = `Statue{slot.rank}`
        -- Face the viewer (+Z of the podium); the pivot sits at the feet.
        local feet = deps.origin * CFrame.new(toVector(slot.standPoint))
        local _, size = model:GetBoundingBox()
        model:PivotTo(feet * CFrame.new(0, size.Y / 2, 0))
        model.Parent = root
        state.statue = model
    end

    local stage: Stage = {
        render = function(_self: Stage, view: PodiumModel.View)
            for index, place in view.places do
                local state = states[index]
                local slot = slots[index]
                if state.userId ~= place.userId then
                    if state.statue ~= nil then
                        state.statue:Destroy()
                        state.statue = nil
                    end
                    state.userId = place.userId
                    if place.userId ~= nil then
                        placeStatue(state, slot, place.userId)
                    end
                end
                if state.plate ~= nil then
                    state.plate.Text = place.headline
                end
                if state.detail ~= nil then
                    state.detail.Text = place.detail
                end
                if state.stroke ~= nil then
                    state.stroke.Color = toColor(place.frameHex)
                end
                state.step.Color = toColor(
                    if place.occupied
                        then RarityFx.mix(STEP_BASE_HEX, place.frameHex, 0.35)
                        else STEP_BASE_HEX
                )
            end
            local total = countParts(root)
            if total > deps.maxParts then
                deps.onError(`podium has {total} parts, over the budget of {deps.maxParts}`)
            end
        end,
        destroy = function(_self: Stage)
            root:Destroy()
        end,
    }
    return stage
end

return PodiumStage
