--!strict
local SoundConfig = require("../../../src/shared/features/sound/SoundConfig")
local SoundRequests = require("../../../src/shared/features/sound/SoundRequests")
local SoundSettings = require("../../../src/shared/features/sound/SoundSettings")
local harness = require("../../harness")

local config: SoundConfig.SoundConfig = {
    sfx = {},
    music = {},
    defaultVolumes = { music = 60, sfx = 80 },
    fadeSeconds = 1,
}

type Pushed = { music: number, sfx: number }

type Fixture = {
    settings: SoundSettings.SoundSettings,
    profile: SoundSettings.SettingsProfile,
    pushed: { Pushed },
    online: (value: boolean) -> (),
}

local function newFixture(): Fixture
    local profile: SoundSettings.SettingsProfile = { settings = {} }
    local pushed: { Pushed } = {}
    local present = true
    local settings = SoundSettings.new({
        config = config,
        profileFor = function(_userId: number): SoundSettings.SettingsProfile?
            if present then
                return profile
            end
            return nil
        end,
        push = function(_userId: number, volumes: { music: number, sfx: number })
            table.insert(pushed, { music = volumes.music, sfx = volumes.sfx })
        end,
    })
    return {
        settings = settings,
        profile = profile,
        pushed = pushed,
        online = function(value: boolean)
            present = value
        end,
    }
end

return function(suite: harness.Harness)
    suite:test("a player with no choice gets the Config defaults", function()
        local fixture = newFixture()
        local volumes = fixture.settings:get(1)
        harness.isTrue(volumes ~= nil and volumes.music == 60 and volumes.sfx == 80, "defaults")
    end)

    suite:test("setVolume persists the choice and pushes both volumes", function()
        local fixture = newFixture()
        harness.isTrue(fixture.settings:setVolume(1, "music", 30) == nil, "accepted")
        harness.equal(fixture.profile.settings.musicVolume, 30)
        harness.equal(fixture.pushed[1].music, 30)
        harness.equal(fixture.pushed[1].sfx, 80, "sfx keeps its default")
        harness.isTrue(fixture.settings:setVolume(1, "sfx", 0) == nil, "zero is valid")
        harness.equal(fixture.profile.settings.sfxVolume, 0)
    end)

    suite:test("out-of-range, fractional and non-numeric volumes are refused", function()
        local fixture = newFixture()
        harness.equal(fixture.settings:setVolume(1, "music", 101), "invalid_volume")
        harness.equal(fixture.settings:setVolume(1, "music", -1), "invalid_volume")
        harness.equal(fixture.settings:setVolume(1, "music", 0.5), "invalid_volume")
        harness.equal(fixture.settings:setVolume(1, "music", "loud"), "invalid_volume")
        harness.equal(fixture.profile.settings.musicVolume, nil, "nothing saved")
    end)

    suite:test("no loaded data is reported and nothing is pushed", function()
        local fixture = newFixture()
        fixture.online(false)
        harness.equal(fixture.settings:setVolume(1, "music", 10), "no_data")
        harness.isTrue(fixture.settings:get(1) == nil, "no volumes")
        fixture.settings:sendCurrent(1)
        harness.equal(#fixture.pushed, 0)
    end)

    suite:test("sendCurrent pushes the saved volumes", function()
        local fixture = newFixture()
        fixture.profile.settings.sfxVolume = 5
        fixture.settings:sendCurrent(1)
        harness.equal(fixture.pushed[1].sfx, 5)
        harness.equal(fixture.pushed[1].music, 60)
    end)

    suite:test("the SetVolume handler rate-limits, validates the group and delegates", function()
        local fixture = newFixture()
        local allowed = true
        local handler = SoundRequests.new({
            settings = fixture.settings,
            allow = function(_userId: number): boolean
                return allowed
            end,
        })
        harness.isTrue(handler:handle(1, "music", 40).ok, "accepted")
        harness.equal(fixture.profile.settings.musicVolume, 40)
        local badGroup = handler:handle(1, "master", 40)
        harness.equal(not badGroup.ok and badGroup.reason or "ok", "not_allowed")
        local badValue = handler:handle(1, "sfx", 400)
        harness.equal(not badValue.ok and badValue.reason or "ok", "invalid_volume")
        allowed = false
        local limited = handler:handle(1, "sfx", 10)
        harness.equal(not limited.ok and limited.reason or "ok", "rate_limited")
        harness.equal(fixture.profile.settings.sfxVolume, nil, "limited request not applied")
    end)
end
