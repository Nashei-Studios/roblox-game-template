--!strict
--[[
    Port: the engine side of the client sound manager. The client presenter
    src/client/presenters/SoundEnginePresenter implements it over SoundService; tests use a fake.
]]

export type SoundEngine = {
    -- Starts a sound and returns a handle. `gain` is 0..1 and already mixed.
    start: (self: SoundEngine, assetId: number, gain: number, looped: boolean) -> number,
    setGain: (self: SoundEngine, handle: number, gain: number) -> (),
    stop: (self: SoundEngine, handle: number) -> (),
}

return {}
