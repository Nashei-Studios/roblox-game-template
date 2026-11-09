--!strict
local Breakpoints = require("../../../src/shared/features/uisystem/Breakpoints")
local Config = require("../../../src/shared/Config")
local ControlRegistry = require("../../../src/shared/features/ui/ControlRegistry")
local EcoRules = require("../../../src/shared/features/ui/audit/EcoRules")
local Geometry = require("../../../src/shared/features/ui/audit/Geometry")
local HudRails = require("../../../src/shared/features/uisystem/HudRails")
local InputScheme = require("../../../src/shared/features/ui/InputScheme")
local ItemIcon = require("../../../src/shared/features/ui/ItemIcon")
local ItemPanel = require("../../../src/shared/ports/ItemPanel")
local ItemSlots = require("../../../src/shared/features/itemslots/ItemSlots")
local RarityConfig = require("../../../src/shared/features/rarity/RarityConfig")
local SafeArea = require("../../../src/shared/features/uisystem/SafeArea")
local Tokens = require("../../../src/shared/features/uisystem/Tokens")
local harness = require("../../harness")

local RARITY = RarityConfig.default
local SURFACE = "#171C30"

local function entry(id: string, rarity: string, level: number?): ItemSlots.Entry
    return {
        item = { id = id, name = id, rarity = rarity, imageAssetId = "123", swatchHex = "#445566" },
        state = { unlocked = true, level = level },
    }
end

local function view(entries: { ItemSlots.Entry }, selected: number?): { ItemSlots.SlotView }
    return ItemSlots.view(ItemSlots.default, entries, selected, RARITY, "high", SURFACE, "Lv")
end

local function fakePanel(): (ItemPanel.ItemPanel, { string })
    local opened: { string } = {}
    local panel: ItemPanel.ItemPanel = {
        open = function(_self: ItemPanel.ItemPanel, itemId: string)
            table.insert(opened, itemId)
        end,
    }
    return panel, opened
end

return function(suite: harness.Harness)
    suite:test("the default config is valid and is part of Config.default", function()
        harness.equal(#ItemSlots.validate(ItemSlots.default), 0, "default valid")
        harness.isTrue(Config.default.itemSlots == ItemSlots.default, "wired in Config")
        local broken: Config.GameConfig = table.clone(Config.default)
        broken.itemSlots = { count = 0, keys = {} }
        harness.equal(
            #Config.validate(broken),
            #Config.validate(Config.default) + 1,
            "Config.validate reports an invalid itemSlots"
        )
    end)

    suite:test("validate rejects a bad count, a key past the count and a repeated key", function()
        harness.isTrue(#ItemSlots.validate({ count = 0, keys = {} }) > 0, "zero slots")
        harness.isTrue(#ItemSlots.validate({ count = 10, keys = {} }) > 0, "too many")
        harness.isTrue(#ItemSlots.validate({ count = 2.5, keys = {} }) > 0, "not integer")
        harness.isTrue(
            #ItemSlots.validate({ count = 2, keys = { {}, {}, { "Three" } } }) > 0,
            "key past count"
        )
        harness.isTrue(
            #ItemSlots.validate({ count = 2, keys = { { "One" }, { "One" } } }) > 0,
            "repeated key"
        )
    end)

    suite:test("N slots come from the config; fewer entries leave empty slots", function()
        local slots = view({ entry("a", "common"), entry("b", "rare") }, 2)
        harness.equal(#slots, 5, "slot count")
        harness.equal(slots[1].id, "Slot1", "id")
        harness.equal(slots[2].itemId, "b", "item")
        harness.isTrue(slots[2].selected, "selected")
        harness.isFalse(slots[1].selected, "not selected")
        harness.isTrue(slots[3].spec == nil and slots[3].itemId == nil, "empty slot")
        local two = ItemSlots.view(
            { count = 2, keys = {} },
            { entry("a", "common") },
            nil,
            RARITY,
            "high",
            SURFACE,
            "Lv"
        )
        harness.equal(#two, 2, "count 2")
    end)

    suite:test("a selected index on an empty slot selects nothing", function()
        local slots = view({ entry("a", "common") }, 3)
        harness.isFalse(slots[3].selected, "empty slot cannot be selected")
    end)

    suite:test("each slot reuses the ItemIcon spec: rarity frame, image and level badge", function()
        local slots = view({ entry("a", "epic", 7) }, 1)
        local spec = slots[1].spec :: ItemIcon.Spec
        harness.equal(spec.imageUrl, "rbxassetid://123", "image")
        harness.equal(spec.badge, "Lv 7", "level badge")
        harness.equal(spec.fx.frameHex, RarityConfig.default.tiers[4].frameHex, "epic frame")
        local thumb = ItemIcon.thumb("123", 150)
        local viaThumb = ItemSlots.view(ItemSlots.default, {
            {
                item = {
                    id = "t",
                    name = "t",
                    rarity = "rare",
                    imageAssetId = thumb,
                    swatchHex = "#445566",
                },
                state = { unlocked = true, count = 12 },
            },
        }, 1, RARITY, "low", SURFACE, "Lv")
        local thumbSpec = viaThumb[1].spec :: ItemIcon.Spec
        harness.equal(thumbSpec.imageUrl, thumb, "ItemIcon.thumb id accepted")
        harness.equal(thumbSpec.badge, "x12", "count badge")
    end)

    suite:test("hints: number key on keyboard, pad glyph on gamepad, none on touch", function()
        local config = ItemSlots.default
        harness.equal(ItemSlots.hintFor(config, 1, InputScheme.KEYBOARD), "1", "keyboard 1")
        harness.equal(ItemSlots.hintFor(config, 1, InputScheme.GAMEPAD), "L1", "pad L1")
        harness.equal(ItemSlots.hintFor(config, 1, InputScheme.TOUCH), nil, "touch none")
        harness.equal(
            ItemSlots.hintFor(config, 2, InputScheme.GAMEPAD),
            nil,
            "slot 2 has no pad key"
        )
        harness.equal(ItemSlots.hintFor(config, 9, InputScheme.KEYBOARD), nil, "out of range")
        local slots = view({ entry("a", "common") }, 1)
        harness.equal(slots[5].hints[InputScheme.GAMEPAD], "R1", "hints table")
        harness.isTrue(slots[1].hints[InputScheme.TOUCH] == nil, "no touch hint")
    end)

    suite:test("keys map to slots", function()
        harness.equal(ItemSlots.indexForKey(ItemSlots.default, "Three"), 3, "Three")
        harness.equal(ItemSlots.indexForKey(ItemSlots.default, "ButtonR1"), 5, "R1")
        harness.equal(ItemSlots.indexForKey(ItemSlots.default, "Nine"), nil, "unbound")
    end)

    suite:test(
        "a tap opens the item panel through the port; empty or unknown slots do nothing",
        function()
            local slots = view({ entry("pick", "rare") }, 1)
            local panel, opened = fakePanel()
            harness.isTrue(ItemSlots.tap(slots, 1, panel), "tap on item")
            harness.isFalse(ItemSlots.tap(slots, 2, panel), "tap on empty")
            harness.isFalse(ItemSlots.tap(slots, 99, panel), "tap out of range")
            harness.equal(#opened, 1, "opened once")
            harness.equal(opened[1], "pick", "item id")
        end
    )

    suite:test("every slot is registered for all schemes and passes the Eco rules", function()
        local registry = ControlRegistry.new()
        ItemSlots.register(registry, ItemSlots.default)
        harness.equal(#registry.order, 5, "five controls")
        local names: { string } = {}
        for index = 1, 5 do
            table.insert(names, ItemSlots.slotId(index))
        end
        harness.equal(#EcoRules.hudRegistration("hud", names, registry), 0, "registered")
        for _, scheme in InputScheme.ALL do
            harness.equal(#EcoRules.controlsOnScheme("hud", scheme, names, registry), 0, scheme)
        end
        harness.equal(
            #EcoRules.hudRegistration("hud", { "Slot6" }, registry),
            1,
            "unregistered caught"
        )
        local ok = pcall(function()
            ItemSlots.register(registry, ItemSlots.default)
        end)
        harness.isFalse(ok, "double registration raises")
    end)

    suite:test(
        "UI-TEXT-LOST: a hint that does not fit is an error, a fitting one passes",
        function()
            harness.equal(#EcoRules.textLost("hud", "Slot1.Hint", true, false), 0, "fits")
            harness.equal(#EcoRules.textLost("hud", "Slot1.Hint", false, false), 1, "cut")
        end
    )

    suite:test(
        "the row keeps the gap, the touch floor and the thumbstick zones on the four viewports",
        function()
            local tokens = Tokens.default()
            local gap = Tokens.space(tokens, tokens.defaults.gap)
            for _, viewport in Breakpoints.REVIEW_VIEWPORTS do
                local deviceClass: Tokens.DeviceClass = Breakpoints.classify(viewport, false)
                local scale = Breakpoints.uiScale(deviceClass, viewport)
                local margin = Breakpoints.safeMargin(deviceClass, viewport, tokens)
                local area = SafeArea.usable(
                    viewport.width / scale,
                    viewport.height / scale,
                    { top = 0, left = 0, bottom = 0, right = 0 },
                    margin
                )
                local reserve = if deviceClass == "phone" then 0.42 else 0
                local plan = HudRails.plan(
                    area,
                    { left = 4, right = 3, bottom = ItemSlots.default.count },
                    reserve,
                    tokens
                )
                local label = `{viewport.width}x{viewport.height}`
                harness.equal(#plan.problems, 0, `{label}: {table.concat(plan.problems, "; ")}`)
                local row: { HudRails.Tile } = {}
                for _, tile in plan.tiles do
                    if tile.rail == "bottom" then
                        table.insert(row, tile)
                    end
                end
                harness.equal(#row, 5, `{label}: all slots placed`)
                for index, tile in row do
                    harness.isTrue(tile.rect.width >= tokens.touchMin, `{label}: touch floor`)
                    if index > 1 then
                        harness.isTrue(
                            Geometry.gap(row[index - 1].rect, tile.rect) >= gap,
                            `{label}: gap between slots`
                        )
                    end
                    for _, other in plan.tiles do
                        if other.rail ~= "bottom" then
                            harness.isTrue(
                                Geometry.gap(other.rect, tile.rect) >= gap,
                                `{label}: gap to the side rails`
                            )
                        end
                    end
                end
                if deviceClass == "phone" then
                    -- The middle band: the thumbstick (left) and jump (right) live in the outer thirds.
                    local first = row[1].rect
                    local last = row[#row].rect
                    harness.isTrue(
                        first.x >= area.x + area.width * 0.25,
                        `{label}: clear of the thumbstick`
                    )
                    harness.isTrue(
                        last.x + last.width <= area.x + area.width * 0.75,
                        `{label}: clear of the jump button`
                    )
                end
            end
        end
    )
end
