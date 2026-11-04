--!strict
--[[
    Port: a player's persisted volume settings (server side). In-house implementation:
    features/sound/SoundSettings. The client mixes with features/sound/SoundManager over the
    SoundEngine port.
]]

export type VolumeGroup = "music" | "sfx"

export type SetVolumeError = "no_data" | "invalid_volume"

export type Volumes = { music: number, sfx: number }

export type SoundSettings = {
    -- nil when the player's data is not loaded.
    get: (self: SoundSettings, userId: number) -> Volumes?,
    -- Percent 0..100, integer. Persists and pushes the new volumes to the client. nil on success.
    setVolume: (
        self: SoundSettings,
        userId: number,
        group: VolumeGroup,
        percent: unknown
    ) -> SetVolumeError?,
    -- Pushes the current volumes (call after the data loads).
    sendCurrent: (self: SoundSettings, userId: number) -> (),
}

return {}
