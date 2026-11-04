--!strict
--[[
    Typed config of the sound system and its validation. Pure: loads under Lune.
    Asset ids are references (ADR 0006) and stay nil until the game has real ones; `validate`
    reports each missing id so a misconfigured game fails loudly. Never put a plausible fake id.
]]

export type SoundEntry = {
    name: string,
    assetId: number?, -- TODO(victor): set id
    -- Base volume of this sound, 0 to 1 (before the player's group volume).
    volume: number,
}

export type SoundConfig = {
    sfx: { SoundEntry },
    music: { SoundEntry },
    -- Initial volumes in percent (0 to 100) for a player with no saved choice.
    defaultVolumes: { music: number, sfx: number },
    -- Seconds of the fade between two music tracks (0 = cut).
    fadeSeconds: number,
}

local SoundConfigModule = {}

--- Names of the declared sound effects, as a set (Config.validate cross-checks toasts with it).
function SoundConfigModule.sfxNames(config: SoundConfig): { [string]: boolean }
    local names: { [string]: boolean } = {}
    for _, entry in config.sfx do
        names[entry.name] = true
    end
    return names
end

local function listProblems(entries: { SoundEntry }, group: string, problems: { string })
    local seen: { [string]: boolean } = {}
    for _, entry in entries do
        if entry.name == "" then
            table.insert(problems, `a {group} sound has no name`)
        end
        if seen[entry.name] then
            table.insert(problems, `{group} sound "{entry.name}" is declared twice`)
        end
        seen[entry.name] = true
        if entry.assetId == nil then
            table.insert(problems, `{group} sound "{entry.name}" has no asset id`)
        end
        if entry.volume ~= entry.volume or entry.volume <= 0 or entry.volume > 1 then
            table.insert(problems, `{group} sound "{entry.name}" needs a volume above 0 up to 1`)
        end
    end
end

local function percentOk(value: number): boolean
    return value == value and value >= 0 and value <= 100 and value % 1 == 0
end

--- One human-readable problem per invalid or missing value (empty when valid).
function SoundConfigModule.validate(config: SoundConfig): { string }
    local problems: { string } = {}
    listProblems(config.sfx, "sfx", problems)
    listProblems(config.music, "music", problems)
    if not percentOk(config.defaultVolumes.music) then
        table.insert(problems, "sound.defaultVolumes.music must be an integer from 0 to 100")
    end
    if not percentOk(config.defaultVolumes.sfx) then
        table.insert(problems, "sound.defaultVolumes.sfx must be an integer from 0 to 100")
    end
    if config.fadeSeconds ~= config.fadeSeconds or config.fadeSeconds < 0 then
        table.insert(problems, "sound.fadeSeconds must be zero or positive")
    end
    return problems
end

return SoundConfigModule
