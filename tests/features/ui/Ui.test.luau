--!strict
local Config = require("../../../src/shared/Config")
local Contrast = require("../../../src/shared/features/ui/Contrast")
local Layout = require("../../../src/shared/features/ui/Layout")
local MenuController = require("../../../src/shared/features/ui/MenuController")
local ShopModel = require("../../../src/shared/features/ui/ShopModel")
local UiConfig = require("../../../src/shared/features/ui/UiConfig")
local UiPresenter = require("../../../src/shared/ports/UiPresenter")
local harness = require("../../harness")

local function defaultUi(): UiConfig.UiConfig
    local ui = Config.default.ui
    assert(ui ~= nil, "default ui config is declared")
    return ui
end

local function cloneUi(): UiConfig.UiConfig
    local ui = defaultUi()
    return {
        theme = table.clone(ui.theme),
        menus = table.clone(ui.menus),
        strings = table.clone(ui.strings),
        input = table.clone(ui.input),
        settings = table.clone(ui.settings),
        gates = ui.gates,
    }
end

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
    return MenuController.new({ menus = defaultUi().menus, presenter = presenter }), log
end

return function(suite: harness.Harness)
    suite:test("the default theme passes validation, contrast included", function()
        harness.equal(#UiConfig.validate(defaultUi()), 0, "no problems")
        local palette = defaultUi().theme.palette
        local ratio = Contrast.ratio(palette.textPrimary, palette.surface)
        harness.isTrue(ratio ~= nil and ratio >= Contrast.AA_TEXT, "primary text AA")
    end)

    suite:test("contrast follows the WCAG formula", function()
        local blackOnWhite = Contrast.ratio("#000000", "#FFFFFF")
        harness.isTrue(blackOnWhite ~= nil and math.abs(blackOnWhite - 21) < 0.01, "21:1")
        local same = Contrast.ratio("#808080", "#808080")
        harness.isTrue(same ~= nil and math.abs(same - 1) < 0.001, "1:1")
        harness.isTrue(Contrast.ratio("red", "#FFFFFF") == nil, "invalid hex")
    end)

    suite:test("validate reports low contrast, bad tokens, bindings and missing menus", function()
        local ui = cloneUi()
        ui.theme.palette = table.clone(ui.theme.palette)
        ui.theme.palette.focus = "nothex"
        ui.theme.touchTargetMin = 30
        ui.theme.textSize = { caption = 8, body = 10, title = 9 }
        ui.theme.spacing = { sm = 10, md = 5, lg = 1 }
        ui.menus = {
            { id = "hud", title = "HUD", modal = true },
            { id = "shop", title = "Shop", modal = true, toggleKey = "B" },
            { id = "shop", title = "", modal = true, toggleKey = "B" },
        }
        ui.strings = table.clone(ui.strings)
        ui.strings.buy = ""
        local problems = UiConfig.validate(ui)
        local text = table.concat(problems, "\n")
        local dim = cloneUi()
        dim.theme.palette = table.clone(dim.theme.palette)
        dim.theme.palette.textPrimary = "#2A2F45"
        local dimText = table.concat(UiConfig.validate(dim), " ")
        harness.isTrue(
            string.find(dimText, "contrast textPrimary on surface", 1, true) ~= nil,
            "contrast"
        )
        harness.isTrue(string.find(text, "palette.focus", 1, true) ~= nil, "hex")
        harness.isTrue(string.find(text, "touchTargetMin", 1, true) ~= nil, "touch floor")
        harness.isTrue(string.find(text, "textSize", 1, true) ~= nil, "text size")
        harness.isTrue(string.find(text, "spacing", 1, true) ~= nil, "spacing")
        harness.isTrue(string.find(text, "share the binding", 1, true) ~= nil, "binding")
        harness.isTrue(string.find(text, 'declares "shop" twice', 1, true) ~= nil, "duplicate")
        harness.isTrue(string.find(text, 'missing "rewards"', 1, true) ~= nil, "missing menu")
        harness.isTrue(string.find(text, "cannot be modal", 1, true) ~= nil, "hud modal")
        harness.isTrue(string.find(text, "ui.strings.buy", 1, true) ~= nil, "string")
    end)

    suite:test("scale and reference reject nonsense", function()
        local ui = cloneUi()
        ui.theme.scale = { min = 2, max = 1 }
        ui.theme.reference = { shortSide = 0, longSide = 0 }
        ui.theme.font = ""
        ui.theme.buttonHeight = 0
        ui.theme.panel = { widthScale = 2, heightScale = 0, maxWidthPoints = 0 }
        ui.input = { backKey = "", backPad = "ButtonY" }
        ui.settings = { volumeStep = 0, sendDebounceSeconds = -1 }
        ui.theme.radius = -1
        ui.theme.strokeThickness = -1
        ui.theme.motionSeconds = -1
        harness.isTrue(#UiConfig.validate(ui) >= 11, "each token reported")
    end)

    suite:test("Studded and Plain differ only by tokens", function()
        local plain = defaultUi().theme
        local studded = table.clone(plain)
        studded.studs = true
        local resolved = UiConfig.resolve(studded)
        harness.equal(resolved.radius, 0, "square corners")
        harness.isTrue(resolved.strokeThickness >= 2, "heavier outline")
        harness.equal(resolved.palette.accent, plain.palette.accent, "palette untouched")
        harness.isTrue(UiConfig.resolve(plain) == plain, "plain unchanged")
    end)

    suite:test(
        "UIScale is the same in portrait and landscape and stays inside its limits",
        function()
            local theme = defaultUi().theme
            local portrait = Layout.scaleFor(360, 640, theme)
            local landscape = Layout.scaleFor(640, 360, theme)
            harness.equal(portrait, 1, "reference phone")
            harness.equal(landscape, portrait, "orientation does not matter")
            harness.equal(Layout.scaleFor(1920, 1080, theme), theme.scale.max, "capped on 1080p")
            harness.equal(Layout.scaleFor(100, 100, theme), theme.scale.min, "floored")
            harness.equal(Layout.scaleFor(0, 0, theme), theme.scale.min, "empty viewport")
        end
    )

    suite:test("a button is never under the touch floor, at any scale", function()
        local theme = defaultUi().theme
        for _, scale in { 0.75, 1, 1.5, 2 } do
            local height = Layout.buttonHeight(theme, scale)
            harness.isTrue(Layout.isTouchTarget(height, scale, theme), `scale {scale}`)
        end
        local small = table.clone(theme)
        small.buttonHeight = 20
        harness.isTrue(Layout.buttonHeight(small, 1) >= 44, "raised to the floor")
        harness.equal(Layout.buttonHeight(theme, 0), theme.buttonHeight, "bad scale")
        harness.isFalse(Layout.isTouchTarget(30, 1, theme), "30 pt is too small")
    end)

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
