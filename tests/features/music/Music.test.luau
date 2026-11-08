--!strict
local MusicConfig = require("../../../src/shared/features/music/MusicConfig")
local MusicDirector = require("../../../src/shared/features/music/MusicDirector")
local SoundConfig = require("../../../src/shared/features/sound/SoundConfig")
local harness = require("../../harness")

local function sound(): SoundConfig.SoundConfig
    return {
        sfx = { { name = "sting_big", assetId = 5, volume = 1 } },
        music = {
            { name = "hub_a", assetId = 1, volume = 1 },
            { name = "hub_b", assetId = 2, volume = 1 },
            { name = "fight", assetId = 3, volume = 1 },
        },
        defaultVolumes = { music = 100, sfx = 100 },
        fadeSeconds = 1,
    }
end

local function config(): MusicConfig.MusicConfig
    local licence = { basis = "cc0", source = "https://example.invalid/cc0", attribution = nil }
    return {
        licences = {
            hub_a = licence,
            hub_b = { basis = "distrokid", source = "contract", attribution = nil },
            fight = { basis = "cc_by", source = "page", attribution = "Artist, CC BY 4.0" },
            sting_big = licence,
        },
        moods = { lobby = { "hub_a", "hub_b" }, action = { "fight" } },
        stings = { big_break = "sting_big" },
        duck = MusicConfig.defaultDuck(),
    }
end

local function has(problems: { string }, needle: string): boolean
    return string.find(table.concat(problems, "|"), needle, 1, true) ~= nil
end

type Fake = {
    music: { string },
    sfx: { string },
    volumes: { { music: number, sfx: number } },
}

local function rig(known: { string }?)
    local fake: Fake = { music = {}, sfx = {}, volumes = {} }
    local director = MusicDirector.new({
        config = config(),
        volumes = { music = 80, sfx = 60 },
        sound = {
            playMusic = function(_self, name: string): boolean
                if known ~= nil and not table.find(known, name) then
                    return false
                end
                table.insert(fake.music, name)
                return true
            end,
            playSfx = function(_self, name: string): boolean
                table.insert(fake.sfx, name)
                return true
            end,
            setVolumes = function(_self, volumes)
                table.insert(fake.volumes, volumes)
            end,
        },
    })
    return { director = director, fake = fake }
end

return function(suite: harness.Harness)
    suite:test("a complete config validates and its manifest is sorted", function()
        harness.equal(#MusicConfig.validate(config(), sound()), 0)
        local rows = MusicConfig.manifest(config())
        harness.equal(#rows, 4)
        harness.equal(rows[1].name, "fight")
        harness.equal(rows[1].attribution, "Artist, CC BY 4.0")
    end)

    suite:test(
        "every used name needs a licence with a basis, a source and cc_by attribution",
        function()
            local bad = config()
            local cc0 = { basis = "cc0", source = "x", attribution = nil }
            bad.licences = {
                fight = { basis = "cc_by", source = "page", attribution = nil },
                hub_b = { basis = "stolen", source = "", attribution = nil },
                ghost = cc0,
                sting_big = cc0,
            }
            local problems = MusicConfig.validate(bad, sound())
            harness.isTrue(has(problems, `"hub_a" has no licence`))
            harness.isTrue(has(problems, "needs an attribution"))
            harness.isTrue(has(problems, "not recognised"))
            harness.isTrue(has(problems, "needs a source"))
            harness.isTrue(has(problems, `"ghost" matches no SoundConfig`))
        end
    )

    suite:test(
        "validate reports unknown tracks, unknown stings, empty moods and a bad duck",
        function()
            local bad = config()
            bad.moods.empty = {}
            bad.moods.lobby = { "nope" }
            bad.stings.big_break = "missing"
            bad.duck = { factor = 1, attackSeconds = -1, releaseSeconds = 0, stingHoldSeconds = 0 }
            local problems = MusicConfig.validate(bad, sound())
            harness.isTrue(has(problems, "has no track"))
            harness.isTrue(has(problems, `unknown track "nope"`))
            harness.isTrue(has(problems, `unknown sfx "missing"`))
            harness.isTrue(has(problems, "duck.factor"))
            harness.isTrue(has(problems, "attack seconds"))
            bad.moods[""] = { "hub_a" }
            harness.isTrue(has(MusicConfig.validate(bad, sound()), "needs a name"))
        end
    )

    suite:test(
        "a mood plays its playlist in order and never repeats the same track back to back",
        function()
            local r = rig()
            harness.isTrue(r.director:setMood("lobby"))
            harness.equal(r.director:currentTrack(), "hub_a")
            harness.isTrue(r.director:setMood("lobby"), "same mood is a no-op")
            harness.equal(#r.fake.music, 1)
            r.director:onTrackEnded()
            harness.equal(r.director:currentTrack(), "hub_b")
            r.director:onTrackEnded()
            harness.equal(r.director:currentTrack(), "hub_a")
            harness.isTrue(r.director:setMood("action"))
            r.director:onTrackEnded()
            harness.equal(r.director:currentTrack(), "fight", "a single-track mood keeps its track")
            harness.equal(r.director:mood(), "action")
        end
    )

    suite:test("an unknown mood or a track the manager refuses reports false", function()
        local r = rig({ "hub_b" })
        harness.isFalse(r.director:setMood("nope"))
        harness.equal(r.director:mood(), nil)
        harness.isFalse(r.director:setMood("lobby"), "hub_a has no asset id yet")
        harness.equal(r.director:currentTrack(), nil)
        r.director:onTrackEnded()
        harness.equal(r.director:currentTrack(), "hub_b")
        local idle = rig()
        idle.director:onTrackEnded()
        harness.equal(#idle.fake.music, 0, "no mood, nothing to advance")
    end)

    suite:test("a sting plays its sfx and holds a duck that releases", function()
        local r = rig()
        harness.isFalse(r.director:sting("unknown"))
        harness.isTrue(r.director:sting("big_break"))
        harness.equal(r.fake.sfx[1], "sting_big")
        r.director:step(0.15)
        harness.isTrue(math.abs(r.director:duckFactor() - 0.35) < 1e-9, "attack finished")
        local last = r.fake.volumes[#r.fake.volumes]
        harness.isTrue(math.abs(last.music - 80 * 0.35) < 1e-6)
        harness.equal(last.sfx, 60)
        r.director:step(1.2)
        r.director:step(0.6)
        harness.equal(r.director:duckFactor(), 1)
        harness.isTrue(math.abs(r.fake.volumes[#r.fake.volumes].music - 80) < 1e-6)
    end)

    suite:test(
        "a menu holds the duck until it lets go, and many holders are independent",
        function()
            local r = rig()
            r.director:duck("menu")
            r.director:duck("dialog")
            r.director:step(1)
            harness.isTrue(r.director:duckFactor() < 1)
            r.director:unduck("menu")
            r.director:step(5)
            harness.isTrue(r.director:duckFactor() < 1, "dialog still holds")
            r.director:unduck("dialog")
            r.director:step(5)
            harness.equal(r.director:duckFactor(), 1)
            local before = #r.fake.volumes
            r.director:step(1)
            harness.equal(#r.fake.volumes, before, "no write when nothing changes")
        end
    )

    suite:test("player volumes win: a change applies at the current duck factor", function()
        local r = rig()
        r.director:duck("menu")
        r.director:step(1)
        r.director:setVolumes({ music = 50, sfx = 40 })
        local last = r.fake.volumes[#r.fake.volumes]
        harness.isTrue(math.abs(last.music - 50 * 0.35) < 1e-6)
        harness.equal(last.sfx, 40)
    end)

    suite:test("zero attack and release jump straight to the target", function()
        local cfg = config()
        cfg.duck = { factor = 0.5, attackSeconds = 0, releaseSeconds = 0, stingHoldSeconds = 0 }
        local volumes: { number } = {}
        local director = MusicDirector.new({
            config = cfg,
            volumes = { music = 100, sfx = 100 },
            sound = {
                playMusic = function(): boolean
                    return true
                end,
                playSfx = function(): boolean
                    return true
                end,
                setVolumes = function(_self, v)
                    table.insert(volumes, v.music)
                end,
            },
        })
        director:duck("ui")
        director:step(0.016)
        director:unduck("ui")
        director:step(0.016)
        harness.equal(table.concat(volumes, ","), "50,100")
    end)
end
