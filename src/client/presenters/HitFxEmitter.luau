--!strict
--[[
    Client presenter: one invisible anchor part with one ParticleEmitter, reused for every hit, so
    a tap burst never allocates. Kinds are data (`features/hitfx/HitFx`) passed in by the game; the
    color is per call. Purely cosmetic, never read back. Engine code: excluded from the coverage
    gate and kept thin. UNVERIFIED until a person checks it in Studio.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HitFx = require(ReplicatedStorage.Shared.features.hitfx.HitFx)

export type HitFxEmitter = {
    burst: (self: HitFxEmitter, spot: Vector3, kindId: string, colorHex: string) -> (),
}

local HitFxEmitterModule = {}

function HitFxEmitterModule.new(kinds: { [string]: HitFx.HitSpec }, texture: string): HitFxEmitter
    local anchor = Instance.new("Part")
    anchor.Name = "HitFx"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.2, 0.2, 0.2)
    anchor.Parent = Workspace
    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = texture
    emitter.Rate = 0
    emitter.SpreadAngle = Vector2.new(70, 70)
    emitter.Parent = anchor

    local fx: HitFxEmitter = {
        burst = function(_self: HitFxEmitter, spot: Vector3, kindId: string, colorHex: string)
            local settings = HitFx.settings(kinds, kindId)
            if settings == nil then
                return
            end
            anchor.Position = spot
            emitter.Color = ColorSequence.new(Color3.fromHex(colorHex))
            emitter.LightEmission = settings.glow
            emitter.Speed = NumberRange.new(settings.speedMin, settings.speedMax)
            emitter.Lifetime = NumberRange.new(settings.lifetimeMin, settings.lifetimeMax)
            emitter.Size = NumberSequence.new(settings.size, 0)
            emitter:Emit(settings.count)
        end,
    }
    return fx
end

return HitFxEmitterModule
