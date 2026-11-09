--!strict
--[[
    Tests of the UI gate rules (docs/adr/0061): duplicate destinations, scroll overlap and
    containment, modal motion, button limits per screen and scheme, locomotion buttons on touch
    and nested scrollers. Each rule has a fixture with the defect seen in game 1 (+1 Mining Power)
    and a fixed twin that passes.
]]

local harness = require("../../harness")
local ControlRegistry = require("../../../src/shared/features/ui/ControlRegistry")
local GateRules = require("../../../src/shared/features/ui/audit/GateRules")
local UiGates = require("../../../src/shared/features/ui/UiGates")
local LocomotionConfig = require("../../../src/shared/features/locomotion/LocomotionConfig")
local LocomotionControls = require("../../../src/shared/features/locomotion/LocomotionControls")
local Config = require("../../../src/shared/Config")
local ConfigAudit = require("../../../src/shared/features/ui/audit/ConfigAudit")
local Finding = require("../../../src/shared/features/ui/audit/Finding")
local StaticRules = require("../../../src/shared/features/ui/audit/StaticRules")

local gates = UiGates.default()

local function item(y: number, height: number): GateRules.Rect
    return { x = 0, y = y, width = 200, height = height }
end

local MODAL_MOTION: UiGates.MenuMotion = {
    open = "tween",
    close = "spring",
    hover = true,
    press = true,
    reduced = "instant",
}

return function(suite: harness.Harness)
    suite:test("UiGates default validates and a bad limit is reported", function()
        harness.equal(#UiGates.validate(gates), 0)
        local bad = UiGates.default()
        bad.maxNestedScroll = 0
        bad.maxButtons.hud.touch = 0
        harness.equal(#UiGates.validate(bad), 2)
    end)

    suite:test("UI-DUP-DESTINATION fails two visible controls to the same place", function()
        local bug = GateRules.duplicateDestinations("HUD", "touch", {
            { name = "Shop", destination = "menu:shop" },
            { name = "Store", destination = "menu:shop" },
            { name = "Daily", destination = "menu:rewards" },
        })
        harness.equal(#bug, 1)
        harness.equal(bug[1].rule, "UI-DUP-DESTINATION")
        harness.equal(#GateRules.duplicateDestinations("HUD", "touch", {
            { name = "Shop", destination = "menu:shop" },
            { name = "Daily", destination = "menu:rewards" },
        }), 0)
    end)

    suite:test("registry destinations are checked per scheme from the visible controls", function()
        local registry = ControlRegistry.new()
        ControlRegistry.register(registry, {
            id = "ShopA",
            purpose = "open the shop",
            schemes = { "touch", "keyboard" },
            destination = "menu:shop",
        })
        ControlRegistry.register(registry, {
            id = "ShopB",
            purpose = "also open the shop",
            schemes = { "touch" },
            destination = "menu:shop",
        })
        harness.equal(#GateRules.registryDuplicates("HUD", registry, "touch"), 1)
        harness.equal(#GateRules.registryDuplicates("HUD", registry, "keyboard"), 0)
    end)

    suite:test("UI-SCROLL-OVERLAP fails rows that overlap at every scroll position", function()
        local bug = GateRules.scrollLayout("Shop", "List", {
            viewport = { width = 200, height = 100 },
            canvas = { width = 200, height = 300 },
            children = { item(0, 60), item(50, 60), item(130, 60) },
        }, gates)
        harness.equal(#bug, 1)
        harness.equal(bug[1].rule, "UI-SCROLL-OVERLAP")
        local ok = GateRules.scrollLayout("Shop", "List", {
            viewport = { width = 200, height = 100 },
            canvas = { width = 200, height = 300 },
            children = { item(0, 60), item(68, 60), item(136, 60) },
        }, gates)
        harness.equal(#ok, 0)
    end)

    suite:test("UI-SCROLL-OUTSIDE fails a child that leaves the canvas", function()
        local bug = GateRules.scrollLayout("Shop", "List", {
            viewport = { width = 200, height = 100 },
            canvas = { width = 200, height = 150 },
            children = { item(0, 60), item(100, 60) },
        }, gates)
        harness.equal(#bug, 1)
        harness.equal(bug[1].rule, "UI-SCROLL-OUTSIDE")
    end)

    suite:test("scroll positions cover the start, the middle and the end of the canvas", function()
        local positions = GateRules.scrollPositions(
            { width = 200, height = 100 },
            { width = 200, height = 300 }
        )
        harness.equal(#positions, 3)
        harness.equal(positions[1].y, 0)
        harness.equal(positions[3].y, 200)
        harness.equal(
            #GateRules.scrollPositions({ width = 1, height = 9 }, { width = 1, height = 5 }),
            1
        )
    end)

    suite:test("list layout is computed from sizes and padding", function()
        local rects = GateRules.listRects({ 40, 40, 40 }, 8, 200)
        harness.equal(rects[2].y, 48)
        harness.equal(rects[3].y, 96)
        harness.equal(GateRules.listExtent({ 40, 40, 40 }, 8), 136)
    end)

    suite:test("UI-MOTION-MISSING fails a modal menu with no declared motion", function()
        local menus: { UiGates.MotionMenu } = {
            { id = "hud", modal = false },
            { id = "shop", modal = true },
            { id = "settings", modal = true, motion = MODAL_MOTION },
        }
        local bug = GateRules.motion("Config", menus, 0.15)
        harness.equal(#bug, 1)
        harness.equal(bug[1].rule, "UI-MOTION-MISSING")
        harness.equal(bug[1].path, "shop")
    end)

    suite:test("UI-MOTION-MISSING names each missing piece and a zero duration", function()
        local partial: UiGates.MenuMotion = {
            open = "tween",
            close = "none",
            hover = false,
            press = true,
            reduced = "instant",
        }
        local bug =
            GateRules.motion("Config", { { id = "shop", modal = true, motion = partial } }, 0)
        harness.equal(#bug, 3)
    end)

    suite:test("UI-MOTION-MISSING requires a reduced motion fallback", function()
        local noFallback: UiGates.MenuMotion = {
            open = "tween",
            close = "tween",
            hover = true,
            press = true,
            reduced = "none",
        }
        local bug =
            GateRules.motion("Config", { { id = "shop", modal = true, motion = noFallback } }, 0.15)
        harness.equal(#bug, 1)
    end)

    suite:test("the template menus all declare motion", function()
        local ui = Config.default.ui
        assert(ui ~= nil, "default ui config is declared")
        local menus: { UiGates.MotionMenu } = {}
        for _, menu in ui.menus do
            table.insert(menus, { id = menu.id, modal = menu.modal, motion = menu.motion })
        end
        harness.equal(#GateRules.motion("Config", menus, ui.theme.motionSeconds), 0)
    end)

    suite:test("UI-BUTTON-LIMIT fails 50 buttons and passes the limit", function()
        local bug = GateRules.buttonLimit("HUD", "hud", "touch", 50, gates)
        harness.equal(#bug, 1)
        harness.equal(bug[1].rule, "UI-BUTTON-LIMIT")
        local limit = gates.maxButtons.hud.touch
        harness.equal(#GateRules.buttonLimit("HUD", "hud", "touch", limit, gates), 0)
        harness.equal(#GateRules.buttonLimit("HUD", "hud", "touch", limit + 1, gates), 1)
    end)

    suite:test("the button limit is per scheme: touch is stricter than keyboard", function()
        harness.isTrue(gates.maxButtons.hud.touch < gates.maxButtons.hud.keyboard)
        harness.isTrue(gates.maxButtons.menu.touch <= gates.maxButtons.menu.keyboard)
    end)

    suite:test("UI-TOUCH-LOCOMOTION fails a RUN or STOW button on touch", function()
        local registry = ControlRegistry.new()
        LocomotionControls.register(registry, LocomotionConfig.default().keys, true)
        local bug = GateRules.touchLocomotion("HUD", registry, gates)
        harness.equal(#bug, 2)
        harness.equal(bug[1].rule, "UI-TOUCH-LOCOMOTION")
    end)

    suite:test("the template locomotion registry has no touch buttons by default", function()
        local registry = ControlRegistry.new()
        LocomotionControls.register(registry, LocomotionConfig.default().keys)
        harness.equal(#GateRules.touchLocomotion("HUD", registry, gates), 0)
        harness.isFalse(ControlRegistry.visibleOn(registry, "Sprint", "touch"))
        harness.equal(ControlRegistry.hintFor(registry, "Sprint", "keyboard"), "Shift")
    end)

    suite:test("UI-SCROLL-DEPTH fails a scroller nested past the limit", function()
        local bug = GateRules.scrollDepth("Shop", "Outer.Inner", 2, gates)
        harness.equal(#bug, 1)
        harness.equal(bug[1].rule, "UI-SCROLL-DEPTH")
        harness.equal(#GateRules.scrollDepth("Shop", "Outer", 1, gates), 0)
    end)

    suite:test("the template declarations pass every gate rule", function()
        local ui = Config.default.ui
        assert(ui ~= nil, "default ui config is declared")
        harness.equal(#ConfigAudit.audit(ui), 0)
    end)

    suite:test(
        "a registry with 50 buttons and a repeated destination fails the declaration gate",
        function()
            local ui = Config.default.ui
            assert(ui ~= nil, "default ui config is declared")
            local registry = ConfigAudit.templateRegistry()
            for index = 1, 50 do
                ControlRegistry.register(registry, {
                    id = `Extra{index}`,
                    purpose = "a button added by a game",
                    schemes = { "touch", "keyboard", "gamepad" },
                    destination = "menu:shop",
                })
            end
            local counts = Finding.countByRule(ConfigAudit.auditRegistry("game", registry, ui))
            harness.isTrue((counts["UI-BUTTON-LIMIT"] or 0) >= 3, "limit per scheme")
            harness.equal(counts["UI-DUP-DESTINATION"], 3)
        end
    )

    local function loadRoblox(): any
        local ok, roblox = pcall(function()
            return require("@lune/roblox")
        end)
        if ok then
            return roblox
        end
        return nil
    end

    suite:test("static rules fail a nested scroller and rows that overlap in a scroller", function()
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
        local outer = make("ScrollingFrame", root, "Outer")
        outer.AutomaticCanvasSize = roblox.Enum.AutomaticSize.Y
        make("UIPadding", outer, "Pad")
        local inner = make("ScrollingFrame", outer, "Inner")
        inner.AutomaticCanvasSize = roblox.Enum.AutomaticSize.Y
        make("UIPadding", inner, "Pad")
        local counts = Finding.countByRule(StaticRules.auditRoot(root, "synthetic"))
        harness.equal(counts["UI-SCROLL-DEPTH"], 1)

        local shop = make("Frame", nil, "Shop")
        local list = make("ScrollingFrame", shop, "Rows")
        list.Size = roblox.UDim2.fromOffset(300, 100)
        list.CanvasSize = roblox.UDim2.fromOffset(0, 400)
        list.AutomaticCanvasSize = roblox.Enum.AutomaticSize.None
        list:SetAttribute("CanvasUpdater", true)
        make("UIPadding", list, "Pad")
        for index, y in { 0, 40, 200 } do
            local row = make("Frame", list, `Row{index}`)
            row.Position = roblox.UDim2.fromOffset(0, y)
            row.Size = roblox.UDim2.fromOffset(300, 60)
        end
        local shopCounts = Finding.countByRule(StaticRules.auditRoot(shop, "synthetic"))
        harness.equal(shopCounts["UI-SCROLL-OVERLAP"], 1)
        harness.isTrue(shopCounts["UI-SCROLL-OUTSIDE"] == nil)
    end)

    suite:test("static rules fail list rows past a fixed canvas and pass a spaced list", function()
        local roblox = loadRoblox()
        if roblox == nil then
            print("  (skipped: needs the Lune runtime)")
            return
        end
        local function build(canvasHeight: number): any
            local root = roblox.Instance.new("Frame")
            local list = roblox.Instance.new("ScrollingFrame")
            list.Name = "Rows"
            list.Size = roblox.UDim2.fromOffset(300, 100)
            list.AutomaticCanvasSize = roblox.Enum.AutomaticSize.None
            list.CanvasSize = roblox.UDim2.fromOffset(0, canvasHeight)
            list:SetAttribute("CanvasUpdater", true)
            list.Parent = root
            roblox.Instance.new("UIPadding").Parent = list
            local layout = roblox.Instance.new("UIListLayout")
            layout.Padding = roblox.UDim.new(0, 8)
            layout.Parent = list
            for index = 1, 3 do
                local row = roblox.Instance.new("Frame")
                row.Name = `Row{index}`
                row.Size = roblox.UDim2.fromOffset(300, 60)
                row.LayoutOrder = index
                row.Parent = list
            end
            return root
        end
        harness.equal(
            Finding.countByRule(StaticRules.auditRoot(build(100), "s"))["UI-SCROLL-OUTSIDE"],
            1
        )
        harness.isTrue(
            Finding.countByRule(StaticRules.auditRoot(build(196), "s"))["UI-SCROLL-OUTSIDE"] == nil
        )
    end)
end
