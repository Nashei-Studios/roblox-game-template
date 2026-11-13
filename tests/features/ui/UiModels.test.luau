--!strict
local ControlRegistry = require("../../../src/shared/features/ui/ControlRegistry")
local InputScheme = require("../../../src/shared/features/ui/InputScheme")
local LocomotionConfig = require("../../../src/shared/features/locomotion/LocomotionConfig")
local LocomotionControls = require("../../../src/shared/features/locomotion/LocomotionControls")
local Contrast = require("../../../src/shared/features/ui/Contrast")
local MenuController = require("../../../src/shared/features/ui/MenuController")
local ShopModel = require("../../../src/shared/features/ui/ShopModel")
local UiPresenter = require("../../../src/shared/ports/UiPresenter")
local harness = require("../../harness")

local MENUS: { MenuController.MenuConfig } = {
    { id = "hud", modal = false },
    { id = "shop", modal = true },
    { id = "rewards", modal = true },
    { id = "settings", modal = true },
}

local function newMenus(): (MenuController.MenuController, { string })
    local log: { string } = {}
    local presenter: UiPresenter.UiPresenter = {
        setVisible = function(_self: UiPresenter.UiPresenter, menuId: string, visible: boolean)
            table.insert(log, `{menuId}={visible}`)
        end,
        setText = function(_self: UiPresenter.UiPresenter, slot: string, text: string)
            table.insert(log, `{slot}:{text}`)
        end,
    }
    return MenuController.new({ menus = MENUS, presenter = presenter }), log
end

return function(suite: harness.Harness)
    suite:test("contrast follows the WCAG formula", function()
        local blackOnWhite = Contrast.ratio("#000000", "#FFFFFF")
        harness.isTrue(blackOnWhite ~= nil and math.abs(blackOnWhite - 21) < 0.01, "21:1")
        local same = Contrast.ratio("#808080", "#808080")
        harness.isTrue(same ~= nil and math.abs(same - 1) < 0.001, "1:1")
        harness.isTrue(Contrast.ratio("red", "#FFFFFF") == nil, "invalid hex")
    end)

    suite:test(
        "locomotion controls are key-only by default and get a touch button on request",
        function()
            local keys = LocomotionConfig.default().keys
            local keyOnly = ControlRegistry.new()
            LocomotionControls.register(keyOnly, keys)
            harness.isFalse(
                ControlRegistry.visibleOn(keyOnly, "Sprint", InputScheme.TOUCH),
                "no touch"
            )
            harness.isTrue(
                ControlRegistry.hintFor(keyOnly, "Sprint", InputScheme.KEYBOARD) ~= nil,
                "keyboard hint"
            )
            harness.isFalse(ControlRegistry.has(keyOnly, "Unknown"), "unregistered")
            local withTouch = ControlRegistry.new()
            LocomotionControls.register(withTouch, keys, true)
            harness.isTrue(
                ControlRegistry.visibleOn(withTouch, "Equip", InputScheme.TOUCH),
                "touch"
            )
            harness.equal(
                #ControlRegistry.onScheme(withTouch, InputScheme.TOUCH),
                2,
                "both buttons"
            )
            harness.equal(
                ControlRegistry.hintFor(withTouch, "Equip", InputScheme.TOUCH),
                nil,
                "shown"
            )
        end
    )

    suite:test("opening a modal menu closes the other modal menus; the HUD stays", function()
        local menus, log = newMenus()
        harness.isTrue(menus:isOpen("hud"), "hud visible")
        harness.isFalse(menus:isOpen("shop"))
        harness.isTrue(menus:open("shop").ok)
        harness.isTrue(menus:isOpen("shop"))
        harness.isTrue(menus:open("rewards").ok)
        harness.isFalse(menus:isOpen("shop"), "shop closed by rewards")
        harness.isTrue(menus:isOpen("rewards"))
        harness.isTrue(table.find(log, "shop=false") ~= nil, "presenter told")
        harness.isTrue(menus:toggle("rewards").ok)
        harness.isFalse(menus:isOpen("rewards"), "toggled closed")
    end)

    suite:test("back closes the open menu and unknown ids are refused", function()
        local menus = newMenus()
        harness.isFalse(menus:back(), "nothing to close")
        menus:open("settings")
        harness.isTrue(menus:back(), "closed")
        harness.isFalse(menus:isOpen("settings"))
        local unknown = menus:open("nope")
        harness.isTrue(not unknown.ok and unknown.error == "unknown_menu", "unknown")
        local hud = menus:toggle("hud")
        harness.isTrue(not hud.ok and hud.error == "not_toggleable", "hud is not a toggle")
        harness.isTrue(not menus:close("hud").ok, "hud cannot close")
        harness.isTrue(not menus:close("nope").ok, "unknown close")
    end)

    suite:test("shop rows show runtime prices and block a purchase without one", function()
        local placeholders = { pending = "...", unavailable = "n/a" }
        local products: { ShopModel.Product } = {
            { name = "A", id = 1 },
            { name = "B", id = 2 },
            { name = "C", id = nil },
            { name = "D", id = 4 },
        }
        local rows = ShopModel.rows(products, {
            A = { status = "ready", quote = ShopModel.quoteFromPrices(90, 100) },
            B = { status = "failed" },
        }, placeholders)
        harness.equal(rows[1].priceText, "90 (was 100, 10% off)", "discount shown")
        harness.isTrue(rows[1].canBuy, "ready")
        harness.equal(rows[2].priceText, "n/a", "failed")
        harness.isFalse(rows[2].canBuy)
        harness.equal(rows[3].priceText, "n/a", "no id")
        harness.equal(rows[4].priceText, "...", "pending")
        harness.isFalse(rows[4].canBuy)
        harness.equal(ShopModel.quoteFromPrices(50, nil).discountPercent, 0, "no base price")
    end)
end
