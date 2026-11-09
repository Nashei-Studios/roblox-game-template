--!strict
--[[
    Server presenter of the 3D podium (ADR 0056): builds the three steps, the avatar statues
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
    -- The screen-sized tag above the statue (readable from the spawn camera).
    tagHead: TextLabel,
    tagDetail: TextLabel,
    tagStroke: UIStroke,
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
    -- Back is the +Z face of the part: the side the viewers stand on.
    gui.Face = Enum.NormalId.Back
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

-- A BillboardGui sized in pixels, so the name and the value stay legible at any distance up to
-- TAG_MAX_DISTANCE. It costs no part.
local TAG_MAX_DISTANCE = 160 -- chosen, not measured: the far side of the deck from the spawn camera
local TAG_SIZE = UDim2.fromOffset(150, 52)

local function newTag(step: Part, offset: Vector3): (TextLabel, TextLabel, UIStroke)
    local gui = Instance.new("BillboardGui")
    gui.Name = "Tag"
    gui.Adornee = step
    gui.Size = TAG_SIZE
    gui.StudsOffsetWorldSpace = offset
    gui.MaxDistance = TAG_MAX_DISTANCE
    gui.LightInfluence = 0
    gui.AlwaysOnTop = false
    gui.Parent = step
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundColor3 = toColor("#171C30")
    frame.BackgroundTransparency = 0.15
    frame.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 3
    stroke.Parent = frame
    local head = Instance.new("TextLabel")
    head.Name = "Headline"
    head.Size = UDim2.fromScale(1, 0.58)
    head.BackgroundTransparency = 1
    head.TextScaled = true
    head.Font = Enum.Font.GothamBold
    head.TextColor3 = Color3.new(1, 1, 1)
    head.Parent = frame
    local detail = Instance.new("TextLabel")
    detail.Name = "Detail"
    detail.Position = UDim2.fromScale(0, 0.58)
    detail.Size = UDim2.fromScale(1, 0.38)
    detail.BackgroundTransparency = 1
    detail.TextScaled = true
    detail.Font = Enum.Font.Gotham
    detail.TextColor3 = Color3.fromRGB(220, 226, 240)
    detail.Parent = frame
    return head, detail, stroke
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

local FOOT_NAMES = { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }

local function toPoint(vector: Vector3): PodiumLayout.Point
    return { x = vector.X, y = vector.Y, z = vector.Z }
end

-- Strips scripts, turns off name tags and the state machine. Nothing is anchored yet: the
-- accessories must weld to the body first.
local function prepareStatue(model: Model)
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("Script") or descendant:IsA("LocalScript") then
            descendant:Destroy()
        elseif descendant:IsA("BasePart") then
            descendant.CanCollide = false
            descendant.CanQuery = false
        end
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid ~= nil then
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        humanoid.EvaluateStateMachine = false
    end
end

-- Lowest bottom Y among the feet (or legs for R6), or nil when none is found.
local function lowestFootBottom(model: Model): number?
    local lowest: number? = nil
    for _, name in FOOT_NAMES do
        local part = model:FindFirstChild(name)
        if part ~= nil and part:IsA("BasePart") then
            local bottom = part.Position.Y - part.Size.Y / 2
            if lowest == nil or bottom < lowest then
                lowest = bottom
            end
        end
    end
    return lowest
end

local function isWelded(model: Model, handle: BasePart): boolean
    for _, descendant in model:GetDescendants() do
        if
            descendant:IsA("JointInstance")
            and (descendant.Part1 == handle or descendant.Part0 == handle)
        then
            return true
        end
    end
    return false
end

-- Re-welds every accessory whose handle has no joint (AddAccessory welds through attachments),
-- lets physics settle the welded parts, then removes and reports any part still farther than the
-- allowed radius from the step center.
local function attachAccessories(
    model: Model,
    center: Vector3,
    radius: number,
    onError: (string) -> ()
)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid == nil then
        return
    end
    for _, child in model:GetChildren() do
        if child:IsA("Accessory") then
            local handle = child:FindFirstChild("Handle")
            if handle ~= nil and handle:IsA("BasePart") and not isWelded(model, handle) then
                humanoid:AddAccessory(child)
            end
        end
    end
    task.wait(0.1)
    local parts: { BasePart } = {}
    local points: { PodiumLayout.Point } = {}
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("BasePart") then
            table.insert(parts, descendant)
            table.insert(points, toPoint(descendant.Position))
        end
    end
    for _, index in PodiumLayout.strays(points, toPoint(center), radius) do
        local part = parts[index]
        local owner = part:FindFirstAncestorOfClass("Accessory")
        onError(`podium statue part "{part.Name}" is out of place and was removed`)
        if owner ~= nil then
            owner:Destroy()
        else
            part:Destroy()
        end
    end
end

-- Anchors the statue (every part, or only the root when an idle animation will play) and starts
-- the animation.
local function freezeStatue(model: Model, animationId: string?, onError: (string) -> ())
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    local animated = animationId ~= nil and humanoid ~= nil and root ~= nil
    for _, descendant in model:GetDescendants() do
        if descendant:IsA("BasePart") then
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
        -- Floats just above the front edge of the step, at the statue's feet: low, so it stays inside
        -- the spawn camera frame (the camera is about as high as a 1.6x statue).
        local tagHead, tagDetail, tagStroke =
            newTag(step, Vector3.new(0, slot.stepSize.y / 2 + 1.4, slot.stepSize.z / 2 + 1.2))
        table.insert(states, {
            tagHead = tagHead,
            tagDetail = tagDetail,
            tagStroke = tagStroke,
            userId = nil,
            statue = nil,
            plate = headline,
            detail = detail,
            stroke = stroke,
            step = step,
        })
    end
    root.Parent = deps.parent

    -- Places the avatar by its feet: root center = step top + HipHeight + half the root height,
    -- facing the viewers; then welds the accessories, corrects the feet to the step top, anchors.
    local function placeStatue(state: PlaceState, slot: PodiumLayout.Slot, userId: number)
        local built, model = pcall(function(): Model
            return Players:CreateHumanoidModelFromUserId(userId)
        end)
        if not built then
            deps.onError(`podium avatar for {userId} failed: {tostring(model)}`)
            return
        end
        prepareStatue(model)
        local scale = deps.config.layout.statueScale
        if scale ~= 1 then
            model:ScaleTo(scale)
        end
        model.Name = `Statue{slot.rank}`
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        local rootPart = model:FindFirstChild("HumanoidRootPart")
        if humanoid == nil or rootPart == nil or not rootPart:IsA("BasePart") then
            deps.onError(`podium avatar for {userId} has no humanoid root`)
            model:Destroy()
            return
        end
        local stepCenter = deps.origin * CFrame.new(toVector(slot.stepCenter))
        local standAt = deps.origin * CFrame.new(toVector(slot.standPoint))
        local topY = standAt.Y
        local rootY = PodiumLayout.rootCenterY(topY, humanoid.HipHeight, rootPart.Size.Y)
        -- A half turn: an avatar looks down -Z and the viewers stand on the +Z side.
        local facing = (deps.origin - deps.origin.Position) * CFrame.Angles(0, math.pi, 0)
        model:PivotTo(CFrame.new(standAt.X, rootY, standAt.Z) * facing)
        rootPart.Anchored = true
        model.Parent = root
        state.statue = model
        attachAccessories(model, stepCenter.Position, PodiumLayout.strayRadius(scale), deps.onError)
        if state.statue ~= model then
            return
        end
        local bottom = lowestFootBottom(model)
        if bottom ~= nil then
            local shift = PodiumLayout.feetShift(topY, bottom)
            if shift ~= 0 then
                model:PivotTo(model:GetPivot() + Vector3.new(0, shift, 0))
            end
        end
        freezeStatue(model, deps.config.idleAnimationId, deps.onError)
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
                state.tagHead.Text = place.headline
                state.tagDetail.Text = place.detail
                state.tagStroke.Color = toColor(place.frameHex)
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
