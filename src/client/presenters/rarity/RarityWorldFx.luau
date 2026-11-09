--!strict
--[[
    Client presenter: the rarity language on a world part (a rock, a drop, a pedestal). A soft
    light from Uncommon up and a sparkle emitter from Epic up, both read from the same
    `RarityFx.FxSpec` as the card frames. Emitters are capped by
    `PerfBudget.clientFx.maxLiveEmitters`; over the cap a part keeps its light but no particles.
    At the low quality tier the spec already carries zero particles. Returns a remove function.
    Engine code: excluded from the coverage gate, kept thin. UNVERIFIED until a person checks it
    in Studio's Device Emulator.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local PerfBudget = require(Shared.perf.PerfBudget)
local RarityFx = require(Shared.features.rarity.RarityFx)

local liveEmitters = 0

local RarityWorldFx = {}

local function color(hex: string): Color3
    local red = tonumber(string.sub(hex, 2, 3), 16) or 255
    local green = tonumber(string.sub(hex, 4, 5), 16) or 255
    local blue = tonumber(string.sub(hex, 6, 7), 16) or 255
    return Color3.fromRGB(red, green, blue)
end

--- Applies the effect for `spec` to `part`. Call the returned function to remove it.
function RarityWorldFx.apply(part: BasePart, spec: RarityFx.FxSpec): () -> ()
    local created: { Instance } = {}
    local ownsEmitter = false

    if spec.glow then
        local light = Instance.new("PointLight")
        light.Name = "RarityLight"
        light.Color = color(spec.frameHex)
        light.Range = 8
        light.Brightness = 0.6 + spec.rank * 0.15
        light.Shadows = false
        light.Parent = part
        table.insert(created, light)
    end

    local maxEmitters = if PerfBudget.clientFx ~= nil
        then PerfBudget.clientFx.maxLiveEmitters
        else 0
    if spec.particlesPerSecond > 0 and liveEmitters < maxEmitters then
        local emitter = Instance.new("ParticleEmitter")
        emitter.Name = "RarityParticles"
        emitter.Color = ColorSequence.new(color(spec.frameHex))
        emitter.Rate = spec.particlesPerSecond
        emitter.Lifetime = NumberRange.new(0.6, 1.1)
        emitter.Speed = NumberRange.new(1, 3)
        emitter.SpreadAngle = Vector2.new(180, 180)
        emitter.LightEmission = 0.6
        emitter.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.25),
            NumberSequenceKeypoint.new(1, 0),
        })
        emitter.Parent = part
        table.insert(created, emitter)
        ownsEmitter = true
        liveEmitters += 1
    end

    return function()
        for _, instance in created do
            instance:Destroy()
        end
        table.clear(created)
        if ownsEmitter then
            ownsEmitter = false
            liveEmitters -= 1
        end
    end
end

return RarityWorldFx
