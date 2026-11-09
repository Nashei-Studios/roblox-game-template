--!strict
--[[
    Client presenter: draws a TierModelSet `Look` into a FIXED pool of parts (ADR 0057). The pool is
    built once from the set's capacity, per shape; changing tier re-poses, recolors and re-materials
    pooled parts and unparents the leftovers, so a tier swap creates no instance. A kit Package or
    ReplicatedStorage template is cloned once, on its first use, and moved in and out after that.
    The rarity effects come from RarityWorldFx and are re-applied only when the rarity or the
    quality changes.

    Engine code: excluded from the coverage gate, kept thin. UNVERIFIED until a person checks it in
    Studio (checklist in features/tiermodels/README.md).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RarityWorldFx = require(script.Parent.Parent.rarity.RarityWorldFx)
local TierModelConfig = require(Shared.features.tiermodels.TierModelConfig)
local TierModelSet = require(Shared.features.tiermodels.TierModelSet)
local TierModelSources = require(Shared.features.tiermodels.TierModelSources)

export type Options = {
    -- Should the camera and raycasts treat the parts as solid (a rock the camera backs off from)?
    canQuery: boolean,
    castShadow: boolean,
}

export type ShownPart = { part: BasePart, role: string }

export type Stats = { created: number, shown: number, swaps: number, templates: number }

export type TierModelRig = {
    -- Shows `tierId`. A failed look leaves the previous model in place and returns the error.
    show: (
        self: TierModelRig,
        tierId: string,
        quality: TierModelSet.Quality,
        surfaceHex: string
    ) -> TierModelSet.LookResult,
    -- Moves the whole model; parts keep their offsets from this frame.
    setOrigin: (self: TierModelRig, origin: CFrame) -> (),
    -- Unparents every part, template and effect. The pool stays built.
    hide: (self: TierModelRig) -> (),
    -- The part the rarity effects sit on, or nil while hidden.
    root: (self: TierModelRig) -> BasePart?,
    -- The pooled parts currently shown, in recipe order, with the color role of each (empty for a
    -- template). A game recolors them per floor or per roll; the rig never reads them back.
    shownParts: (self: TierModelRig) -> { ShownPart },
    stats: (self: TierModelRig) -> Stats,
    destroy: (self: TierModelRig) -> (),
}

local TierModelRigModule = {}

local function color(hex: string): Color3
    return Color3.fromHex(hex)
end

local function newPooledPart(shape: string, options: Options): BasePart
    local made: BasePart
    if shape == "wedge" then
        made = Instance.new("WedgePart")
    else
        local plain = Instance.new("Part")
        if shape == "ball" then
            plain.Shape = Enum.PartType.Ball
        elseif shape == "cylinder" then
            plain.Shape = Enum.PartType.Cylinder
        else
            plain.Shape = Enum.PartType.Block
        end
        made = plain
    end
    made.Name = `Tier_{shape}`
    made.Anchored = true
    made.CanCollide = false
    made.CanTouch = false
    made.CanQuery = options.canQuery
    made.CastShadow = options.castShadow
    made.TopSurface = Enum.SurfaceType.Smooth
    made.BottomSurface = Enum.SurfaceType.Smooth
    made.Parent = nil
    return made
end

local function poseOf(origin: CFrame, spec: TierModelSet.ResolvedPart): CFrame
    return origin
        * CFrame.new(spec.offset.x, spec.offset.y, spec.offset.z)
        * CFrame.Angles(0, math.rad(spec.yawDeg), 0)
        * CFrame.Angles(math.rad(spec.pitchDeg), 0, 0)
        * CFrame.Angles(0, 0, math.rad(spec.rollDeg))
end

--- A `Finder` over the descendants of `container` (a kit Package folder or a ReplicatedStorage
--- folder): a Model named `name` is found, its parts counted, its triangles estimated. A model may
--- carry a numeric "Triangles" attribute that wins over the estimate.
function TierModelRigModule.finderFrom(
    container: Instance,
    meshPartTriangles: number
): TierModelSources.Finder
    return function(name: string): TierModelSources.TemplateInfo?
        local found = container:FindFirstChild(name, true)
        if found == nil or not found:IsA("Model") then
            return nil
        end
        local parts, triangles = 0, 0
        for _, descendant in found:GetDescendants() do
            if descendant:IsA("MeshPart") then
                parts += 1
                triangles += meshPartTriangles
            elseif descendant:IsA("BasePart") then
                parts += 1
                triangles += TierModelConfig.TRIANGLES.block
            end
        end
        local declared = found:GetAttribute("Triangles")
        if typeof(declared) == "number" then
            triangles = declared
        end
        return { partCount = parts, triangles = triangles }
    end
end

function TierModelRigModule.new(
    parent: Instance,
    set: TierModelSet.TierModelSet,
    container: Instance?,
    options: Options
): TierModelRig
    local folder = Instance.new("Folder")
    folder.Name = "TierModel"
    folder.Parent = parent

    local pool = set:newPool()
    local capacity = pool:capacity()
    local slots: { [string]: { BasePart } } = {}
    for shape, count in capacity do
        local list: { BasePart } = {}
        for _ = 1, count do
            table.insert(list, newPooledPart(shape, options))
        end
        slots[shape] = list
    end

    local templates: { [string]: Model? } = {}
    local templateCount = 0
    local origin = CFrame.identity
    local shownCount = 0
    local current: TierModelSet.Look? = nil
    local state: { template: Model? } = { template = nil }
    local removeFx: (() -> ())? = nil
    local fxKey = ""
    local rootPart: BasePart? = nil
    local shownParts: { ShownPart } = {}

    local function clearFx()
        local remove = removeFx
        if remove ~= nil then
            remove()
        end
        removeFx = nil
        fxKey = ""
    end

    local function unshow(shape: string, from: number)
        local list = slots[shape]
        if list == nil then
            return
        end
        for index = from, #list do
            list[index].Parent = nil
        end
    end

    local function templateFor(name: string): Model?
        local cached = templates[name]
        if cached ~= nil then
            return cached
        end
        local source = if container ~= nil then container:FindFirstChild(name, true) else nil
        if source == nil or not source:IsA("Model") then
            return nil
        end
        local clone = source:Clone()
        for _, descendant in clone:GetDescendants() do
            if descendant:IsA("BasePart") then
                descendant.Anchored = true
                descendant.CanCollide = false
                descendant.CanQuery = options.canQuery
            end
        end
        templates[name] = clone
        templateCount += 1
        return clone
    end

    local function dismissTemplate()
        local active = state.template
        if active ~= nil then
            active.Parent = nil
        end
        state.template = nil
    end

    local function applyFx(look: TierModelSet.Look, quality: TierModelSet.Quality, target: BasePart)
        local fx = look.fx
        local key = if fx == nil then "" else `{fx.id}:{quality}:{target:GetFullName()}`
        if key == fxKey and removeFx ~= nil then
            return
        end
        clearFx()
        if fx ~= nil then
            removeFx = RarityWorldFx.apply(target, fx)
            fxKey = key
        end
    end

    local rig: TierModelRig
    rig = {
        show = function(
            _self: TierModelRig,
            tierId: string,
            quality: TierModelSet.Quality,
            surfaceHex: string
        ): TierModelSet.LookResult
            local answer = set:look(tierId, quality, surfaceHex)
            if not answer.ok then
                return answer
            end
            local look = answer.value
            local template = look.template
            local chosen: { model: Model? } = { model = nil }
            if template ~= nil then
                chosen.model = templateFor(template.name)
                if chosen.model == nil then
                    -- The finder saw it but the clone failed: keep the previous model, report it.
                    return {
                        ok = false,
                        error = {
                            kind = "missing_model",
                            message = `template "{template.name}" could not be cloned`,
                        },
                    }
                end
            end
            local templateModel = chosen.model

            current = look
            local demand = if templateModel ~= nil then {} else look.demand
            local assignment = pool:assign(demand)
            for shape, count in assignment.hide do
                local used = demand[shape] or 0
                local before = used + count
                for index = used + 1, math.min(before, #(slots[shape] or {})) do
                    slots[shape][index].Parent = nil
                end
            end
            for shape in capacity do
                if demand[shape] == nil then
                    unshow(shape, 1)
                end
            end

            dismissTemplate()
            shownCount = 0
            rootPart = nil
            table.clear(shownParts)
            if templateModel ~= nil then
                templateModel:PivotTo(origin)
                templateModel.Parent = folder
                state.template = templateModel
                shownCount = look.partCount
                rootPart = templateModel.PrimaryPart
                    or templateModel:FindFirstChildWhichIsA("BasePart", true)
            else
                local nextIndex: { [string]: number } = {}
                local material = Enum.Material:FromName(look.material) or Enum.Material.Slate
                for _, spec in look.parts do
                    local index = (nextIndex[spec.shape] or 0) + 1
                    nextIndex[spec.shape] = index
                    local list = slots[spec.shape]
                    local pooled = if list ~= nil then list[index] else nil
                    if pooled ~= nil then
                        pooled.Size = Vector3.new(spec.size.x, spec.size.y, spec.size.z)
                        pooled.CFrame = poseOf(origin, spec)
                        pooled.Color = color(spec.colorHex)
                        pooled.Material = if spec.role == "glow"
                            then Enum.Material.Neon
                            else material
                        pooled.Parent = folder
                        shownCount += 1
                        table.insert(shownParts, { part = pooled, role = spec.role })
                        if rootPart == nil then
                            rootPart = pooled
                        end
                    end
                end
            end
            local target = rootPart
            if target ~= nil then
                applyFx(look, quality, target)
            else
                clearFx()
            end
            return answer
        end,
        setOrigin = function(_self: TierModelRig, next: CFrame)
            origin = next
            local look = current
            if look == nil then
                return
            end
            local active = state.template
            if active ~= nil then
                active:PivotTo(origin)
                return
            end
            local nextIndex: { [string]: number } = {}
            for _, spec in look.parts do
                local index = (nextIndex[spec.shape] or 0) + 1
                nextIndex[spec.shape] = index
                local list = slots[spec.shape]
                local pooled = if list ~= nil then list[index] else nil
                if pooled ~= nil and pooled.Parent ~= nil then
                    pooled.CFrame = poseOf(origin, spec)
                end
            end
        end,
        hide = function(_self: TierModelRig)
            for _, list in slots do
                for _, pooled in list do
                    pooled.Parent = nil
                end
            end
            dismissTemplate()
            clearFx()
            pool:assign({})
            shownCount = 0
            rootPart = nil
            table.clear(shownParts)
            current = nil
        end,
        root = function(_self: TierModelRig): BasePart?
            return rootPart
        end,
        shownParts = function(_self: TierModelRig): { ShownPart }
            return shownParts
        end,
        stats = function(_self: TierModelRig): Stats
            return {
                created = pool:created(),
                shown = shownCount,
                swaps = pool:swaps(),
                templates = templateCount,
            }
        end,
        destroy = function(_self: TierModelRig)
            clearFx()
            for _, model in templates do
                if model ~= nil then
                    model:Destroy()
                end
            end
            table.clear(templates)
            folder:Destroy()
        end,
    }
    return rig
end

return TierModelRigModule
