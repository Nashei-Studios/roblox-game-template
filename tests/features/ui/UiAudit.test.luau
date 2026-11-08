--!strict
--[[
    Tests of the UI audit rules (docs/ui-audit.md). Geometry and Finding are pure. The static rules
    need the Lune roblox module to build instances, so under the Luau CLI that part is skipped.
]]

local harness = require("../../harness")
local Finding = require("../../../src/shared/features/ui/audit/Finding")
local Geometry = require("../../../src/shared/features/ui/audit/Geometry")
local StaticRules = require("../../../src/shared/features/ui/audit/StaticRules")

local function loadRoblox(): any
    local ok, roblox = pcall(function()
        return require("@lune/roblox")
    end)
    if ok then
        return roblox
    end
    return nil
end

return function(suite: harness.Harness)
    suite:test("overlap, gap, containment and visible fraction of rectangles", function()
        local a: Geometry.Rect = { x = 0, y = 0, width = 100, height = 50 }
        local b: Geometry.Rect = { x = 50, y = 25, width = 100, height = 50 }
        local c: Geometry.Rect = { x = 104, y = 0, width = 10, height = 50 }
        harness.equal(Geometry.overlapArea(a, b), 50 * 25)
        harness.equal(Geometry.overlapArea(a, c), 0)
        harness.equal(Geometry.gap(a, c), 4)
        harness.equal(Geometry.gap(a, b), 0)
        harness.isTrue(Geometry.contains(a, { x = 1, y = 1, width = 10, height = 10 }, 0))
        harness.isFalse(Geometry.contains(a, b, 2))
        harness.equal(Geometry.visibleFraction(a, b), 50 * 25 / (100 * 50))
    end)

    suite:test("contrast of black on white is 21 and of equal colors is 1", function()
        local white = Geometry.luminance(1, 1, 1)
        local black = Geometry.luminance(0, 0, 0)
        harness.isTrue(math.abs(Geometry.contrast(white, black) - 21) < 0.001)
        harness.equal(Geometry.contrast(white, white), 1)
    end)

    suite:test("findings count by rule and format with scope and path", function()
        local one = Finding.new("UI-X", "error", "file.rbxm", "Root.A", "bad")
        local two = Finding.new("UI-X", "warn", "file.rbxm", "Root.B", "bad")
        harness.equal(Finding.countByRule({ one, two })["UI-X"], 2)
        harness.equal(Finding.format(one), "[error] UI-X file.rbxm Root.A: bad")
    end)

    suite:test("static rules flag touching lists, bare scrollers and unfit text", function()
        local roblox = loadRoblox()
        if roblox == nil then
            print("  (skipped: needs the Lune runtime)")
            return
        end
        local function make(className: string, parent: any?, name: string): any
            local instance = roblox.Instance.new(className)
            instance.Name = name
            instance.Parent = parent
            return instance
        end
        local root = make("Frame", nil, "Root")
        local scroller = make("ScrollingFrame", root, "Scroller")
        scroller.AutomaticCanvasSize = roblox.Enum.AutomaticSize.None
        make("UIListLayout", scroller, "List")
        local label = make("TextLabel", scroller, "Label")
        label.Text = "hello"
        local grid = make("UIGridLayout", root, "Grid")
        grid.CellPadding = roblox.UDim2.new(0, 0, 0, 6)
        local counts = Finding.countByRule(StaticRules.auditRoot(root, "synthetic"))
        harness.equal(counts["UI-LIST-PADDING"], 1)
        harness.equal(counts["UI-GRID-PADDING"], 1)
        harness.equal(counts["UI-SCROLL-CANVAS"], 1)
        harness.equal(counts["UI-SCROLL-PADDING"], 1)
        harness.equal(counts["UI-TEXT-FIT"], 1)
    end)

    suite:test("static rules pass a fixed list, scroller, text and button", function()
        local roblox = loadRoblox()
        if roblox == nil then
            print("  (skipped: needs the Lune runtime)")
            return
        end
        local function make(className: string, parent: any?, name: string): any
            local instance = roblox.Instance.new(className)
            instance.Name = name
            instance.Parent = parent
            return instance
        end
        local root = make("Frame", nil, "Root")
        local scroller = make("ScrollingFrame", root, "Scroller")
        scroller.AutomaticCanvasSize = roblox.Enum.AutomaticSize.Y
        make("UIPadding", scroller, "Inset")
        make("UIListLayout", scroller, "List").Padding = roblox.UDim.new(0, 8)
        local label = make("TextLabel", scroller, "Label")
        label.Text = "hello"
        label.TextScaled = true
        make("UITextSizeConstraint", label, "Fit")
        local button = make("TextButton", scroller, "Button")
        button.Text = ""
        button.Size = roblox.UDim2.new(0, 120, 0, 48)
        harness.equal(#StaticRules.auditRoot(root, "synthetic"), 0)
        local small = make("TextButton", scroller, "Small")
        small.Text = ""
        small.Size = roblox.UDim2.new(0, 30, 0, 30)
        local counts = Finding.countByRule(StaticRules.auditRoot(root, "synthetic"))
        harness.equal(counts["UI-TOUCH-44"], 1)
    end)
end
