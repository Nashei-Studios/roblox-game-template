--!strict
local ItemIcon = require("../../../src/shared/features/ui/ItemIcon")
local RarityConfig = require("../../../src/shared/features/rarity/RarityConfig")
local harness = require("../../harness")

local CONFIG = RarityConfig.default
local SURFACE = "#171C30"

local function item(id: string, rarity: string, image: string?): ItemIcon.Item
    return { id = id, name = id, rarity = rarity, imageAssetId = image, swatchHex = "#445566" }
end

return function(suite: harness.Harness)
    suite:test("image ids: digits and the full form pass, anything else is nil", function()
        harness.equal(ItemIcon.imageUrl("123"), "rbxassetid://123", "digits")
        harness.equal(ItemIcon.imageUrl("rbxassetid://9"), "rbxassetid://9", "full form")
        harness.equal(ItemIcon.imageUrl(""), nil, "empty")
        harness.equal(ItemIcon.imageUrl("12a"), nil, "letters")
        harness.equal(ItemIcon.imageUrl("https://x"), nil, "url")
        harness.equal(ItemIcon.imageUrl(nil), nil, "nil")
    end)

    suite:test("thumb builds the rbxthumb content id and imageUrl accepts it as ready", function()
        local url = ItemIcon.thumb("104425944384081", 420)
        harness.equal(url, "rbxthumb://type=Asset&id=104425944384081&w=420&h=420", "digits")
        harness.equal(
            ItemIcon.thumb("rbxassetid://7", 150),
            "rbxthumb://type=Asset&id=7&w=150&h=150",
            "full form"
        )
        harness.equal(ItemIcon.thumb("7", 100), nil, "size outside the list")
        harness.equal(ItemIcon.thumb("x7", 420), nil, "bad id")
        harness.equal(ItemIcon.imageUrl(url), url, "ready content id passes through")
        harness.equal(ItemIcon.imageUrl("rbxthumb://evil"), nil, "other thumb forms are refused")
        local spec = ItemIcon.spec(
            item("a", "rare", url),
            { unlocked = true },
            CONFIG,
            "high",
            SURFACE,
            "Lv"
        )
        harness.equal(spec.imageUrl, url, "spec keeps the thumb url")
    end)

    suite:test("an unlocked item with an image shows it with its rarity frame", function()
        local spec = ItemIcon.spec(
            item("a", "rare", "5"),
            { unlocked = true },
            CONFIG,
            "high",
            SURFACE,
            "Lv"
        )
        harness.equal(spec.imageMode, "image", "mode")
        harness.equal(spec.imageUrl, "rbxassetid://5", "url")
        harness.equal(spec.imageTintHex, nil, "no tint")
        harness.equal(spec.fx.id, "rare", "rarity")
        harness.isFalse(spec.locked, "not locked")
    end)

    suite:test("no image id falls back to the swatch, never to a hole", function()
        local spec = ItemIcon.spec(
            item("a", "common", nil),
            { unlocked = true },
            CONFIG,
            "high",
            SURFACE,
            "Lv"
        )
        harness.equal(spec.imageMode, "swatch", "mode")
        harness.equal(spec.imageUrl, nil, "no url")
        harness.equal(spec.swatchHex, "#445566", "swatch")
    end)

    suite:test("a locked item is a black silhouette of its image with a neutral frame", function()
        local spec = ItemIcon.spec(
            item("a", "mythic", "5"),
            { unlocked = false, count = 4 },
            CONFIG,
            "high",
            SURFACE,
            "Lv"
        )
        harness.isTrue(spec.locked, "locked")
        harness.equal(spec.imageMode, "silhouette", "mode")
        harness.equal(spec.imageUrl, "rbxassetid://5", "same image")
        harness.equal(spec.imageTintHex, "#000000", "black")
        harness.equal(spec.fx.frameHex, CONFIG.lockedFrameHex, "neutral frame")
        harness.isFalse(spec.fx.glow or spec.fx.shimmer, "no effects")
        harness.equal(spec.badge, nil, "no badge while locked")
    end)

    suite:test("a locked item with no image is a dark swatch", function()
        local spec = ItemIcon.spec(
            item("a", "epic", nil),
            { unlocked = false },
            CONFIG,
            "high",
            SURFACE,
            "Lv"
        )
        harness.equal(spec.imageMode, "swatch", "mode")
        harness.equal(spec.swatchHex, ItemIcon.LOCKED_SWATCH_HEX, "dark")
    end)

    suite:test("badge: level wins, count shows above 1 and caps at 99+", function()
        harness.equal(
            ItemIcon.badge({ unlocked = true, level = 3, count = 9 }, "Lv"),
            "Lv 3",
            "level"
        )
        harness.equal(ItemIcon.badge({ unlocked = true, count = 5 }, "Lv"), "x5", "count")
        harness.equal(
            ItemIcon.badge({ unlocked = true, count = 1 }, "Lv"),
            nil,
            "one shows nothing"
        )
        harness.equal(ItemIcon.badge({ unlocked = true, count = 250 }, "Lv"), "99+", "cap")
        harness.equal(ItemIcon.badge({ unlocked = true, level = 0 }, "Lv"), nil, "level 0")
        harness.equal(ItemIcon.badge({ unlocked = true }, "Lv"), nil, "none")
    end)

    suite:test(
        "validate reports a repeated id, an unknown rarity, a bad image id and a bad swatch",
        function()
            harness.equal(
                #ItemIcon.validate({ item("a", "rare", "1"), item("b", "epic", nil) }, CONFIG),
                0,
                "valid"
            )
            local bad: { ItemIcon.Item } = {
                item("a", "rare", "1"),
                item("a", "nope", "x1"),
                { id = "", name = "n", rarity = "rare", imageAssetId = nil, swatchHex = "red" },
            }
            harness.equal(
                #ItemIcon.validate(bad, CONFIG),
                5,
                "repeat, rarity, image, empty id, swatch"
            )
        end
    )

    suite:test("image coverage is the share of items with an image id", function()
        harness.equal(ItemIcon.imageCoverage({}), 1, "empty list")
        harness.equal(
            ItemIcon.imageCoverage({ item("a", "rare", "1"), item("b", "rare", nil) }),
            0.5,
            "half"
        )
    end)
end
