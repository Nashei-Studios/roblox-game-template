--!strict
local Breakpoints = require("../../../src/shared/features/uisystem/Breakpoints")
local Contracts = require("../../../src/shared/features/uisystem/Contracts")
local HudRails = require("../../../src/shared/features/uisystem/HudRails")
local KitAdapter = require("../../../src/shared/features/uisystem/KitAdapter")
local Plain = require("../../../src/shared/features/uisystem/adapters/Plain")
local SafeArea = require("../../../src/shared/features/uisystem/SafeArea")
local Studded = require("../../../src/shared/features/uisystem/adapters/Studded")
local Tokens = require("../../../src/shared/features/uisystem/Tokens")
local harness = require("../../harness")

local function noInsets(): SafeArea.Insets
    return { top = 0, left = 0, bottom = 0, right = 0 }
end

return function(suite: harness.Harness)
    suite:test("the default tokens are valid and meet AA", function()
        harness.equal(#Tokens.validate(Tokens.default()), 0, "no problems")
    end)

    suite:test("tokens reject a flat scale, a small touch floor and tiny text", function()
        local tokens = Tokens.default()
        tokens.spacing = { xs = 4, sm = 4, md = 12, lg = 16, xl = 24 }
        tokens.touchMin = 30
        tokens.type = { caption = 9, body = 14, title = 20, display = 28 }
        local problems = Tokens.validate(tokens)
        harness.isTrue(#problems >= 3, "spacing, touch and caption are reported")
        local lowContrast = Tokens.default()
        lowContrast.palette.textPrimary = "#2A303C"
        harness.isTrue(#Tokens.validate(lowContrast) > 0, "low contrast is reported")
    end)

    suite:test("classify by short side, console wins", function()
        harness.equal(Breakpoints.classify({ width = 844, height = 390 }, false), "phone")
        harness.equal(Breakpoints.classify({ width = 667, height = 375 }, false), "phone")
        harness.equal(Breakpoints.classify({ width = 1327, height = 496 }, false), "phone")
        harness.equal(Breakpoints.classify({ width = 1024, height = 768 }, false), "tablet")
        harness.equal(Breakpoints.classify({ width = 1920, height = 1080 }, false), "desktop")
        harness.equal(Breakpoints.classify({ width = 1920, height = 1080 }, true), "console")
    end)

    suite:test("UIScale never shrinks and never grows on a phone", function()
        for _, viewport in Breakpoints.REVIEW_VIEWPORTS do
            local deviceClass = Breakpoints.classify(viewport, false)
            local scale = Breakpoints.uiScale(deviceClass, viewport)
            harness.isTrue(scale >= 1, "never below 1")
            if deviceClass == "phone" then
                harness.equal(scale, 1, "phone stays 1")
            end
        end
        harness.equal(Breakpoints.uiScale("desktop", { width = 3840, height = 2160 }), 1.5, "cap")
    end)

    suite:test("a menu box fits the viewport", function()
        for _, viewport in Breakpoints.REVIEW_VIEWPORTS do
            local deviceClass = Breakpoints.classify(viewport, false)
            for _, kind in { "standard", "wide" } :: { Breakpoints.MenuKind } do
                local box = Breakpoints.menuBox(kind, deviceClass, viewport)
                harness.isTrue(box.widthPx <= viewport.width, "fits the width")
                harness.isTrue(box.heightPx <= viewport.height, "fits the height")
                harness.isTrue(box.heightPx >= 0.4 * viewport.height, "not tiny")
            end
        end
        local phone = Breakpoints.menuBox("standard", "phone", { width = 844, height = 390 })
        harness.isTrue(phone.widthScale == 0.9 and phone.heightScale == 0.8, "phone fractions")
    end)

    suite:test("safe margin is fixed per class and a share of the short side on console", function()
        local tokens = Tokens.default()
        local view = { width = 1920, height = 1080 }
        harness.equal(Breakpoints.safeMargin("phone", view, tokens), 8)
        harness.equal(Breakpoints.safeMargin("console", view, tokens), 54)
    end)

    suite:test("usable area subtracts insets and margin and never goes negative", function()
        local area = SafeArea.usable(844, 390, { top = 36, left = 44, bottom = 21, right = 44 }, 8)
        harness.equal(area.x, 52)
        harness.equal(area.y, 44)
        harness.equal(area.width, 844 - 88 - 16)
        local squeezed =
            SafeArea.usable(10, 10, { top = 20, left = 20, bottom = 20, right = 20 }, 8)
        harness.equal(squeezed.width, 0)
        local inside: SafeArea.Rect = { x = 60, y = 50, width = 44, height = 44 }
        harness.isTrue(SafeArea.contains(area, inside, 0))
        harness.isFalse(SafeArea.contains(area, { x = 0, y = 0, width = 44, height = 44 }, 0))
        local dx, dy = SafeArea.clampOffset(area, { x = 0, y = 0, width = 44, height = 44 })
        harness.equal(dx, 52)
        harness.equal(dy, 44)
        local fx, fy = SafeArea.clampOffset(area, inside)
        harness.isTrue(fx == 0 and fy == 0, "inside needs no move")
        local gx, gy = SafeArea.clampOffset(area, { x = 800, y = 380, width = 44, height = 44 })
        harness.isTrue(gx < 0 and gy < 0, "pulled back from the far edges")
    end)

    suite:test("contracts catch a missing gap, a small target and off-scale padding", function()
        local tokens = Tokens.default()
        harness.isTrue(Contracts.gap(0, "List") ~= nil)
        harness.isTrue(Contracts.gap(8, "List") == nil)
        harness.isTrue(Contracts.touch(40, 44, "Close", tokens) ~= nil)
        harness.isTrue(Contracts.touch(44, 44, "Close", tokens) == nil)
        harness.isTrue(Contracts.textSize(9, "Label", tokens) ~= nil)
        harness.isTrue(Contracts.onScale(7, "Pad", tokens) ~= nil)
        harness.isTrue(Contracts.onScale(8, "Pad", tokens) == nil)
        harness.equal(#Contracts.collect({ "a", "b" }), 2)
    end)

    suite:test("HUD rails never overlap or leave the area on the four review viewports", function()
        local tokens = Tokens.default()
        for _, viewport in Breakpoints.REVIEW_VIEWPORTS do
            local deviceClass = Breakpoints.classify(viewport, false)
            local scale = Breakpoints.uiScale(deviceClass, viewport)
            local margin = Breakpoints.safeMargin(deviceClass, viewport, tokens)
            local area =
                SafeArea.usable(viewport.width / scale, viewport.height / scale, noInsets(), margin)
            local reserve = if deviceClass == "phone" then 0.42 else 0
            local plan = HudRails.plan(area, { left = 4, right = 3, bottom = 4 }, reserve, tokens)
            local label = `{viewport.width}x{viewport.height}: {table.concat(plan.problems, "; ")}`
            harness.equal(#plan.problems, 0, label)
            harness.isTrue(plan.edge >= tokens.touchMin, "tiles are touch sized")
            harness.equal(#plan.tiles, 11, "all tiles placed")
        end
    end)

    suite:test("HUD rails reflow into a second column and report an impossible fit", function()
        local tokens = Tokens.default()
        local area: SafeArea.Rect = { x = 8, y = 8, width = 828, height = 374 }
        local plan = HudRails.plan(area, { left = 9, right = 0, bottom = 0 }, 0.42, tokens)
        local columns: { [number]: boolean } = {}
        for _, tile in plan.tiles do
            columns[tile.rect.x] = true
        end
        local count = 0
        for _ in columns do
            count += 1
        end
        harness.isTrue(count >= 2, "second column")
        harness.equal(#plan.problems, 0)
        local tiny: SafeArea.Rect = { x = 0, y = 0, width = 60, height = 30 }
        local cramped = HudRails.plan(tiny, { left = 1, right = 0, bottom = 3 }, 0, tokens)
        harness.isTrue(#cramped.problems > 0, "reported")
    end)

    suite:test("the Studded adapter is well formed and covers every slot", function()
        harness.equal(#KitAdapter.validate(Studded), 0)
        harness.equal(#KitAdapter.uncovered(Studded), 0)
        harness.equal(#KitAdapter.validate(Plain), 0)
        harness.equal(#KitAdapter.uncovered(Plain), #KitAdapter.SLOTS)
    end)

    suite:test("verify names the missing piece and the missing part", function()
        local present: { [string]: boolean } = { ["Templates/MenuTemplate"] = true }
        local problems = KitAdapter.verify(Studded, function(path: string): boolean
            return present[path] == true
        end)
        harness.isTrue(#problems >= 7, "every slot is reported")
        local joined = table.concat(problems, "\n")
        harness.isTrue(string.find(joined, "Top/Title", 1, true) ~= nil, "part path named")
        harness.isTrue(string.find(joined, "no piece at", 1, true) ~= nil, "piece named")
    end)

    suite:test("validate reports a bad id, a missing licence and an unmapped part", function()
        local bad: KitAdapter.KitAdapter = {
            id = "Bad Id",
            kitSlug = nil,
            license = "",
            slots = { ["menu.shell"] = { path = "/x", parts = { title = "Top.Title" } } },
        }
        harness.isTrue(#KitAdapter.validate(bad) >= 4)
    end)
end
