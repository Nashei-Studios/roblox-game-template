--!strict
--[[
    Persisted volume settings (issue #30). Implements ports/SoundSettings. Pure: loads under
    Lune. A player with no saved choice gets Config.default.sound.defaultVolumes; the profile
    stores only what the player changed (`settings.musicVolume` / `settings.sfxVolume`).
]]

local SoundConfig = require("./SoundConfig")
local Validation = require("../../net/Validation")

-- Structurally identical to ports/SoundSettings (kept local: this module is the implementation).
type VolumeGroup = "music" | "sfx"
type SetVolumeError = "no_data" | "invalid_volume"
type Volumes = { music: number, sfx: number }

export type SoundSettings = {
    get: (self: SoundSettings, userId: number) -> Volumes?,
    setVolume: (
        self: SoundSettings,
        userId: number,
        group: VolumeGroup,
        percent: unknown
    ) -> SetVolumeError?,
    sendCurrent: (self: SoundSettings, userId: number) -> (),
}

-- The slice of PlayerData that sound settings read and write.
export type SettingsProfile = {
    settings: { musicVolume: number?, sfxVolume: number? },
}

export type Deps = {
    config: SoundConfig.SoundConfig,
    profileFor: (userId: number) -> SettingsProfile?,
    -- Delivers the volumes to the player's client (the adapter fires the remote).
    push: (userId: number, volumes: Volumes) -> (),
}

local SoundSettingsModule = {}

function SoundSettingsModule.new(deps: Deps): SoundSettings
    local function read(userId: number): Volumes?
        local profile = deps.profileFor(userId)
        if profile == nil then
            return nil
        end
        return {
            music = profile.settings.musicVolume or deps.config.defaultVolumes.music,
            sfx = profile.settings.sfxVolume or deps.config.defaultVolumes.sfx,
        }
    end

    local service: SoundSettings = {
        get = function(_self: SoundSettings, userId: number): Volumes?
            return read(userId)
        end,
        setVolume = function(
            _self: SoundSettings,
            userId: number,
            group: VolumeGroup,
            percent: unknown
        ): SetVolumeError?
            local profile = deps.profileFor(userId)
            if profile == nil then
                return "no_data"
            end
            local checked = Validation.integerInRange(percent, 0, 100)
            if not checked.ok then
                return "invalid_volume"
            end
            if group == "music" then
                profile.settings.musicVolume = checked.value
            else
                profile.settings.sfxVolume = checked.value
            end
            local volumes = read(userId)
            if volumes ~= nil then
                deps.push(userId, volumes)
            end
            return nil
        end,
        sendCurrent = function(_self: SoundSettings, userId: number)
            local volumes = read(userId)
            if volumes ~= nil then
                deps.push(userId, volumes)
            end
        end,
    }
    return service
end

return SoundSettingsModule
