--!strict
--[[
    Music director on top of the sound manager: a playlist per mood (lobby, action, event,
    victory), a sting on a moment, and ducking under UI and stings. Pure: loads under Lune; the
    sound manager is injected (SoundManager satisfies `Sound`), so crossfades and groups stay in
    one place and this module only decides WHICH track and HOW LOUD the music is.

    - `setMood` crossfades to the next track of the playlist (round robin, never the same track
      twice in a row when the mood has more than one). Asking for the current mood is a no-op.
    - `onTrackEnded` advances the playlist (the presenter calls it when a track finishes; looped
      music never ends, so a game that wants rotation plays unlooped tracks or calls this on a timer).
    - `sting(kind)` plays the sting configured for a moment kind and holds a duck, so the sting is
      heard at or before the moment (checklist criterion 4).
    - `duck(key)` / `unduck(key)`: any number of reasons (a menu open) can hold the duck.
    - `step(dt)` ramps the duck factor and writes the music volume to the sound manager.
      The player volumes come from `setVolumes` and always win: a duck only multiplies them.
]]

local MusicConfig = require("./MusicConfig")

export type Volumes = { music: number, sfx: number }

export type Sound = {
    playMusic: (self: Sound, name: string) -> boolean,
    playSfx: (self: Sound, name: string) -> boolean,
    setVolumes: (self: Sound, volumes: Volumes) -> (),
}

export type Deps = {
    config: MusicConfig.MusicConfig,
    sound: Sound,
    -- Percent volumes at start (the player saved choice).
    volumes: Volumes,
}

export type Director = {
    setMood: (self: Director, mood: string) -> boolean,
    onTrackEnded: (self: Director) -> (),
    sting: (self: Director, momentKind: string) -> boolean,
    duck: (self: Director, key: string) -> (),
    unduck: (self: Director, key: string) -> (),
    setVolumes: (self: Director, volumes: Volumes) -> (),
    step: (self: Director, deltaSeconds: number) -> (),
    mood: (self: Director) -> string?,
    currentTrack: (self: Director) -> string?,
    duckFactor: (self: Director) -> number,
}

local MusicDirector = {}

function MusicDirector.new(deps: Deps): Director
    local config = deps.config
    local base: Volumes = { music = deps.volumes.music, sfx = deps.volumes.sfx }
    local currentMood: string? = nil
    local currentTrack: string? = nil
    local cursor: { [string]: number } = {}
    local holders: { [string]: boolean } = {}
    local stingLeft = 0
    local factor = 1

    local function holding(): boolean
        return stingLeft > 0 or next(holders) ~= nil
    end

    local function push()
        deps.sound:setVolumes({ music = base.music * factor, sfx = base.sfx })
    end

    local function playFrom(mood: string, advance: boolean): boolean
        local playlist = config.moods[mood]
        if playlist == nil or #playlist == 0 then
            return false
        end
        local index = cursor[mood] or 0
        if advance or index == 0 then
            index = index % #playlist + 1
            if #playlist > 1 and playlist[index] == currentTrack then
                index = index % #playlist + 1
            end
        end
        cursor[mood] = index
        local name = playlist[index]
        local played = deps.sound:playMusic(name)
        if played then
            currentTrack = name
        end
        return played
    end

    local director: Director
    director = {
        setMood = function(_self: Director, mood: string): boolean
            if mood == currentMood then
                return true
            end
            if config.moods[mood] == nil then
                return false
            end
            currentMood = mood
            return playFrom(mood, true)
        end,
        onTrackEnded = function(_self: Director)
            local mood = currentMood
            if mood ~= nil then
                playFrom(mood, true)
            end
        end,
        sting = function(_self: Director, momentKind: string): boolean
            local name = config.stings[momentKind]
            if name == nil then
                return false
            end
            stingLeft = config.duck.stingHoldSeconds
            return deps.sound:playSfx(name)
        end,
        duck = function(_self: Director, key: string)
            holders[key] = true
        end,
        unduck = function(_self: Director, key: string)
            holders[key] = nil
        end,
        setVolumes = function(_self: Director, volumes: Volumes)
            base = { music = volumes.music, sfx = volumes.sfx }
            push()
        end,
        step = function(_self: Director, deltaSeconds: number)
            stingLeft = math.max(0, stingLeft - deltaSeconds)
            local duck = config.duck
            local target = if holding() then duck.factor else 1
            local span = 1 - duck.factor
            local seconds = if target < factor then duck.attackSeconds else duck.releaseSeconds
            local previous = factor
            if seconds <= 0 then
                factor = target
            else
                local move = span * deltaSeconds / seconds
                factor = if target < factor
                    then math.max(target, factor - move)
                    else math.min(target, factor + move)
            end
            if factor ~= previous then
                push()
            end
        end,
        mood = function(_self: Director): string?
            return currentMood
        end,
        currentTrack = function(_self: Director): string?
            return currentTrack
        end,
        duckFactor = function(_self: Director): number
            return factor
        end,
    }
    return director
end

return MusicDirector
