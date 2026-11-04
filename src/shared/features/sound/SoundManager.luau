--!strict
--[[
    Client sound manager (issue #30), pure: loads under Lune. It resolves sounds by Config name
    (an unknown name or an unset asset id plays nothing), mixes the base volume with the player's
    group volume, and cross-fades music. The engine is behind the SoundEngine port; the client
    entry point calls `step` every frame with the elapsed seconds.
]]

local Mixer = require("./Mixer")
local SoundConfig = require("./SoundConfig")
local SoundEngine = require("../../ports/SoundEngine")

export type Volumes = { music: number, sfx: number }

export type Deps = {
    config: SoundConfig.SoundConfig,
    engine: SoundEngine.SoundEngine,
    -- Percent volumes at start (the player's saved choice or Config defaults).
    volumes: Volumes,
}

export type SoundManager = {
    -- False when the name is unknown or its asset id is not set.
    playSfx: (self: SoundManager, name: string) -> boolean,
    -- Fades out the current track and fades in `name`. False when unknown / no asset id.
    playMusic: (self: SoundManager, name: string) -> boolean,
    setVolumes: (self: SoundManager, volumes: Volumes) -> (),
    step: (self: SoundManager, deltaSeconds: number) -> (),
}

type Layer = {
    handle: number,
    entry: SoundConfig.SoundEntry,
    from: number,
    to: number,
    level: number,
    elapsed: number,
}

local SoundManagerModule = {}

local function find(entries: { SoundConfig.SoundEntry }, name: string): SoundConfig.SoundEntry?
    for _, entry in entries do
        if entry.name == name then
            return entry
        end
    end
    return nil
end

function SoundManagerModule.new(deps: Deps): SoundManager
    local volumes: Volumes = { music = deps.volumes.music, sfx = deps.volumes.sfx }
    local layers: { Layer } = {}
    local fadeSeconds = deps.config.fadeSeconds

    local function apply(layer: Layer)
        deps.engine:setGain(layer.handle, Mixer.mix(layer.entry.volume, volumes.music) * layer.level)
    end

    local manager: SoundManager = {
        playSfx = function(_self: SoundManager, name: string): boolean
            local entry = find(deps.config.sfx, name)
            if entry == nil or entry.assetId == nil then
                return false
            end
            deps.engine:start(entry.assetId, Mixer.mix(entry.volume, volumes.sfx), false)
            return true
        end,
        playMusic = function(_self: SoundManager, name: string): boolean
            local entry = find(deps.config.music, name)
            if entry == nil or entry.assetId == nil then
                return false
            end
            local current = layers[#layers]
            if current ~= nil and current.entry == entry and current.to == 1 then
                return true -- already the target track
            end
            for _, layer in layers do
                layer.from = layer.level
                layer.to = 0
                layer.elapsed = 0
            end
            local startLevel = if fadeSeconds > 0 then 0 else 1
            local handle = deps.engine:start(entry.assetId, 0, true)
            local fresh: Layer = {
                handle = handle,
                entry = entry,
                from = startLevel,
                to = 1,
                level = startLevel,
                elapsed = 0,
            }
            table.insert(layers, fresh)
            apply(fresh)
            if fadeSeconds <= 0 then
                -- A cut: the older tracks stop at once.
                for index = #layers - 1, 1, -1 do
                    deps.engine:stop(layers[index].handle)
                    table.remove(layers, index)
                end
            end
            return true
        end,
        setVolumes = function(_self: SoundManager, newVolumes: Volumes)
            volumes = { music = newVolumes.music, sfx = newVolumes.sfx }
            for _, layer in layers do
                apply(layer)
            end
        end,
        step = function(_self: SoundManager, deltaSeconds: number)
            for index = #layers, 1, -1 do
                local layer = layers[index]
                if layer.level ~= layer.to then
                    layer.elapsed += deltaSeconds
                    layer.level = Mixer.fade(layer.from, layer.to, layer.elapsed, fadeSeconds)
                    apply(layer)
                end
                if layer.to == 0 and layer.level == 0 then
                    deps.engine:stop(layer.handle)
                    table.remove(layers, index)
                end
            end
        end,
    }
    return manager
end

return SoundManagerModule
