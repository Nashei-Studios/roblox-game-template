--!strict
--[[
    Client presenter: the SoundEngine port over Sound instances in SoundService (issue #30).
    Asset ids come from Config through SoundManager; this file only creates, tunes and removes
    Sound instances. It touches the engine, so it is excluded from the line-coverage gate.
]]

local SoundService = game:GetService("SoundService")

-- Structurally identical to ports/SoundEngine.luau (kept local: this file loads in-engine only).
type SoundEngine = {
    start: (self: SoundEngine, assetId: number, gain: number, looped: boolean) -> number,
    setGain: (self: SoundEngine, handle: number, gain: number) -> (),
    stop: (self: SoundEngine, handle: number) -> (),
}

local SoundEnginePresenter = {}

function SoundEnginePresenter.new(): SoundEngine
    local sounds: { [number]: Sound? } = {}
    local nextHandle = 1

    local engine: SoundEngine = {
        start = function(
            _self: SoundEngine,
            assetId: number,
            gain: number,
            looped: boolean
        ): number
            local sound = Instance.new("Sound")
            sound.SoundId = `rbxassetid://{assetId}`
            sound.Volume = gain
            sound.Looped = looped
            sound.Parent = SoundService
            sound:Play()
            local handle = nextHandle
            nextHandle += 1
            sounds[handle] = sound
            if not looped then
                sound.Ended:Once(function()
                    sounds[handle] = nil
                    sound:Destroy()
                end)
            end
            return handle
        end,
        setGain = function(_self: SoundEngine, handle: number, gain: number)
            local sound = sounds[handle]
            if sound ~= nil then
                sound.Volume = gain
            end
        end,
        stop = function(_self: SoundEngine, handle: number)
            local sound = sounds[handle]
            if sound ~= nil then
                sounds[handle] = nil
                sound:Stop()
                sound:Destroy()
            end
        end,
    }
    return engine
end

return SoundEnginePresenter
