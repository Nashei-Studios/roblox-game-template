--!strict
local SoundConfig = require("../../../src/shared/features/sound/SoundConfig")
local harness = require("../../harness")

local function base(): SoundConfig.SoundConfig
    return {
        sfx = { { name = "ding", assetId = 1, volume = 1 } },
        music = { { name = "theme", assetId = 2, volume = 0.5 } },
        defaultVolumes = { music = 60, sfx = 80 },
        fadeSeconds = 1,
    }
end

return function(suite: harness.Harness)
    suite:test("a complete config has no problems", function()
        harness.equal(#SoundConfig.validate(base()), 0)
    end)

    suite:test("each unset asset id is reported", function()
        local config = base()
        config.sfx[1].assetId = nil
        config.music[1].assetId = nil
        harness.equal(#SoundConfig.validate(config), 2)
    end)

    suite:test("names, duplicates and volumes are validated", function()
        local config = base()
        config.sfx = {
            { name = "", assetId = 1, volume = 1 },
            { name = "x", assetId = 1, volume = 0 },
            { name = "x", assetId = 1, volume = 2 },
        }
        harness.equal(#SoundConfig.validate(config), 4)
    end)

    suite:test("default volumes and fade are validated", function()
        local config = base()
        config.defaultVolumes = { music = 101, sfx = 0.5 }
        config.fadeSeconds = -1
        harness.equal(#SoundConfig.validate(config), 3)
    end)

    suite:test("sfxNames lists the declared effects", function()
        local names = SoundConfig.sfxNames(base())
        harness.isTrue(names["ding"] == true and names["theme"] == nil, "only sfx")
    end)
end
