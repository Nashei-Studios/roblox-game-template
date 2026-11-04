--!strict
local SoundConfig = require("../../../src/shared/features/sound/SoundConfig")
local SoundEngine = require("../../../src/shared/ports/SoundEngine")
local SoundManager = require("../../../src/shared/features/sound/SoundManager")
local harness = require("../../harness")

local function configWith(fadeSeconds: number): SoundConfig.SoundConfig
    return {
        sfx = {
            { name = "ding", assetId = 11, volume = 0.5 },
            { name = "unset", assetId = nil, volume = 1 },
        },
        music = {
            { name = "a", assetId = 21, volume = 1 },
            { name = "b", assetId = 22, volume = 1 },
        },
        defaultVolumes = { music = 100, sfx = 100 },
        fadeSeconds = fadeSeconds,
    }
end

type Fixture = {
    manager: SoundManager.SoundManager,
    started: { { assetId: number, gain: number, looped: boolean } },
    gains: { [number]: number },
    stopped: { number },
}

local function newFixture(fadeSeconds: number): Fixture
    local started: { { assetId: number, gain: number, looped: boolean } } = {}
    local gains: { [number]: number } = {}
    local stopped: { number } = {}
    local engine: SoundEngine.SoundEngine = {
        start = function(
            _self: SoundEngine.SoundEngine,
            assetId: number,
            gain: number,
            looped: boolean
        ): number
            table.insert(started, { assetId = assetId, gain = gain, looped = looped })
            gains[#started] = gain
            return #started
        end,
        setGain = function(_self: SoundEngine.SoundEngine, handle: number, gain: number)
            gains[handle] = gain
        end,
        stop = function(_self: SoundEngine.SoundEngine, handle: number)
            table.insert(stopped, handle)
        end,
    }
    local manager = SoundManager.new({
        config = configWith(fadeSeconds),
        engine = engine,
        volumes = { music = 100, sfx = 50 },
    })
    return { manager = manager, started = started, gains = gains, stopped = stopped }
end

return function(suite: harness.Harness)
    suite:test("an sfx plays with base volume times the sfx group volume", function()
        local fixture = newFixture(1)
        harness.isTrue(fixture.manager:playSfx("ding"), "played")
        harness.equal(fixture.started[1].assetId, 11)
        harness.equal(fixture.started[1].gain, 0.25)
        harness.isFalse(fixture.started[1].looped, "one-shot")
    end)

    suite:test("an unknown name or an unset asset id plays nothing", function()
        local fixture = newFixture(1)
        harness.isFalse(fixture.manager:playSfx("ghost"), "unknown")
        harness.isFalse(fixture.manager:playSfx("unset"), "no asset id")
        harness.isFalse(fixture.manager:playMusic("ghost"), "unknown track")
        harness.equal(#fixture.started, 0)
    end)

    suite:test("music fades in and loops", function()
        local fixture = newFixture(2)
        harness.isTrue(fixture.manager:playMusic("a"), "started")
        harness.isTrue(fixture.started[1].looped, "looped")
        harness.equal(fixture.gains[1], 0, "starts silent")
        fixture.manager:step(1)
        harness.equal(fixture.gains[1], 0.5, "halfway")
        fixture.manager:step(1)
        harness.equal(fixture.gains[1], 1, "full")
    end)

    suite:test("a new track cross-fades and the old one stops when silent", function()
        local fixture = newFixture(2)
        fixture.manager:playMusic("a")
        fixture.manager:step(2)
        fixture.manager:playMusic("b")
        fixture.manager:step(1)
        harness.equal(fixture.gains[1], 0.5, "old fades out")
        harness.equal(fixture.gains[2], 0.5, "new fades in")
        fixture.manager:step(1)
        harness.equal(fixture.stopped[1], 1, "old stopped")
    end)

    suite:test("asking for the playing track again does nothing", function()
        local fixture = newFixture(2)
        fixture.manager:playMusic("a")
        fixture.manager:playMusic("a")
        harness.equal(#fixture.started, 1)
    end)

    suite:test("zero fade cuts straight to the new track", function()
        local fixture = newFixture(0)
        fixture.manager:playMusic("a")
        fixture.manager:playMusic("b")
        harness.equal(fixture.gains[2], 1, "new at full")
        harness.equal(fixture.stopped[1], 1, "old stopped at once")
    end)

    suite:test("changing the music volume re-mixes the playing track", function()
        local fixture = newFixture(0)
        fixture.manager:playMusic("a")
        fixture.manager:setVolumes({ music = 20, sfx = 50 })
        harness.equal(fixture.gains[1], 0.2)
    end)
end
