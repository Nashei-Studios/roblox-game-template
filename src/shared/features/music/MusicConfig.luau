--!strict
--[[
    Typed config of the music director and its licence manifest. Pure: loads under Lune.

    The director does not own audio ids. Ids live in SoundConfig (ADR 0006, never hardcoded, never
    invented); this config adds, for every music track and sting NAME of SoundConfig, the licence
    basis the id was cleared under, and the playlists by mood. `validate` fails when a name has no
    licence, a licence has no source, or a playlist points at an unknown track, so a game cannot
    ship an audio id whose right to use is unrecorded.
]]

local SoundConfig = require("../sound/SoundConfig")

export type Licence = {
    -- One of cc0, cc_by, distrokid, original, roblox_library (plain string: stable solver).
    basis: string,
    -- Where the right comes from: a URL, a contract id, a library page. Never empty.
    source: string,
    -- Required for cc_by.
    attribution: string?,
}

export type Duck = {
    -- Music gain multiplier while ducked, in (0, 1).
    factor: number,
    attackSeconds: number,
    releaseSeconds: number,
    -- How long a sting holds the duck before releasing.
    stingHoldSeconds: number,
}

export type MusicConfig = {
    -- Keyed by SoundConfig name (music or sfx).
    licences: { [string]: Licence },
    -- Mood name to the SoundConfig music names that play in it, in order. Moods are free-form
    -- (lobby, action, event, victory are the usual ones).
    moods: { [string]: { string } },
    -- Moment kind (see features/clipmoment) to the SoundConfig sfx name of its sting.
    stings: { [string]: string },
    duck: Duck,
}

local MusicConfigModule = {}

MusicConfigModule.BASES = {
    cc0 = true,
    cc_by = true,
    distrokid = true,
    original = true,
    roblox_library = true,
}

--- A neutral duck: music to 35 % for UI and stings.
function MusicConfigModule.defaultDuck(): Duck
    return { factor = 0.35, attackSeconds = 0.15, releaseSeconds = 0.6, stingHoldSeconds = 1.2 }
end

local function names(entries: { SoundConfig.SoundEntry }): { [string]: boolean }
    local set: { [string]: boolean } = {}
    for _, entry in entries do
        set[entry.name] = true
    end
    return set
end

local function validateLicences(
    config: MusicConfig,
    sound: SoundConfig.SoundConfig,
    problems: { string }
)
    local musicNames = names(sound.music)
    local sfxNames = names(sound.sfx)
    local used: { [string]: boolean } = {}
    for _, track in config.moods do
        for _, name in track do
            used[name] = true
        end
    end
    for _, name in config.stings do
        used[name] = true
    end
    for name in used do
        if config.licences[name] == nil then
            table.insert(problems, `music: "{name}" has no licence entry`)
        end
    end
    for name, licence in config.licences do
        if not musicNames[name] and not sfxNames[name] then
            table.insert(problems, `music: licence for "{name}" matches no SoundConfig entry`)
        end
        if not MusicConfigModule.BASES[licence.basis] then
            table.insert(
                problems,
                `music: "{name}" licence basis "{licence.basis}" is not recognised`
            )
        end
        if licence.source == "" then
            table.insert(problems, `music: "{name}" licence needs a source`)
        end
        if
            licence.basis == "cc_by" and (licence.attribution == nil or licence.attribution == "")
        then
            table.insert(problems, `music: "{name}" is cc_by and needs an attribution line`)
        end
    end
end

--- One human-readable problem per invalid value (empty when valid). `sound` is the game
--- SoundConfig the names resolve against.
function MusicConfigModule.validate(config: MusicConfig, sound: SoundConfig.SoundConfig): { string }
    local problems: { string } = {}
    local musicNames = names(sound.music)
    local sfxNames = names(sound.sfx)
    for mood, playlist in config.moods do
        if mood == "" then
            table.insert(problems, "music: a mood needs a name")
        end
        if #playlist == 0 then
            table.insert(problems, `music: mood "{mood}" has no track`)
        end
        for _, name in playlist do
            if not musicNames[name] then
                table.insert(problems, `music: mood "{mood}" uses unknown track "{name}"`)
            end
        end
    end
    for kind, name in config.stings do
        if not sfxNames[name] then
            table.insert(problems, `music: sting for "{kind}" uses unknown sfx "{name}"`)
        end
    end
    validateLicences(config, sound, problems)
    local duck = config.duck
    if duck.factor ~= duck.factor or duck.factor <= 0 or duck.factor >= 1 then
        table.insert(problems, "music.duck.factor must be between 0 and 1 (exclusive)")
    end
    local timings: { { label: string, value: number } } = {
        { label = "attack", value = duck.attackSeconds },
        { label = "release", value = duck.releaseSeconds },
        { label = "hold", value = duck.stingHoldSeconds },
    }
    for _, timing in timings do
        if timing.value ~= timing.value or timing.value < 0 then
            table.insert(problems, `music.duck.{timing.label} seconds must be zero or positive`)
        end
    end
    return problems
end

export type ManifestRow = { name: string, basis: string, source: string, attribution: string? }

--- The licence manifest as sorted rows, for a credits screen or a release checklist.
function MusicConfigModule.manifest(config: MusicConfig): { ManifestRow }
    local rows: { ManifestRow } = {}
    for name, licence in config.licences do
        table.insert(rows, {
            name = name,
            basis = licence.basis,
            source = licence.source,
            attribution = licence.attribution,
        })
    end
    table.sort(rows, function(a: ManifestRow, b: ManifestRow): boolean
        return a.name < b.name
    end)
    return rows
end

return MusicConfigModule
