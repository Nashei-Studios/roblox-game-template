--!strict
--[[
    Tests of the UI ecosystem rules (docs/adr/0045). Each audit rule has a fixture that
    reproduces the bug seen in a shipped game (lists glued with 0 gap, text flush to a card edge,
    a Run button on a keyboard, a raw UIListLayout with no Padding) and a fixed twin that passes.
]]

local harness = require("../../harness")
local EcoRules = require("../../../src/shared/features/ui/audit/EcoRules")
local SourceRules = require("../../../src/shared/features/ui/audit/SourceRules")
local ControlRegistry = require("../../../src/shared/features/ui/ControlRegistry")
local InputScheme = require("../../../src/shared/features/ui/InputScheme")
local LocomotionConfig = require("../../../src/shared/features/locomotion/LocomotionConfig")
local LocomotionControls = require("../../../src/shared/features/locomotion/LocomotionControls")

local MIN_GAP = 8

local function column(count: number, gap: number): { EcoRules.Rect }
    local rects: { EcoRules.Rect } = {}
    for index = 0, count - 1 do
        table.insert(rects, { x = 0, y = index * (20 + gap), width = 100, height = 20 })
    end
    return rects
end

local function hudRegistry(): ControlRegistry.Registry
    local registry = ControlRegistry.new()
    ControlRegistry.register(registry, {
        id = "Sprint",
        purpose = "hold to run",
        schemes = { "touch" },
        hints = { keyboard = "Shift", gamepad = "L3" },
    })
    ControlRegistry.register(registry, {
        id = "Top",
        purpose = "open the leaderboard",
        schemes = { "touch", "keyboard", "gamepad" },
    })
    return registry
end

return function(suite: harness.Harness)
    suite:test("UI-LIST-GAP fails rows glued with 0 gap and passes the token gap", function()
        local bug = EcoRules.siblingGaps("Board", "Rows", column(4, 0), MIN_GAP)
        harness.equal(#bug, 1)
        harness.equal(bug[1].rule, "UI-LIST-GAP")
        harness.equal(#EcoRules.siblingGaps("Board", "Rows", column(4, MIN_GAP), MIN_GAP), 0)
    end)

    suite:test("UI-LIST-GAP fails a 4 px gap when the token is 8", function()
        harness.equal(#EcoRules.siblingGaps("Panel", "Rows", column(3, 4), MIN_GAP), 1)
    end)

    suite:test("UI-LIST-OVERLAP fails overlapping items and names the rule", function()
        local rects: { EcoRules.Rect } = {
            { x = 0, y = 0, width = 100, height = 30 },
            { x = 0, y = 20, width = 100, height = 30 },
        }
        local findings = EcoRules.siblingGaps("Panel", "Rows", rects, MIN_GAP)
        harness.equal(#findings, 1)
        harness.equal(findings[1].rule, "UI-LIST-OVERLAP")
    end)

    suite:test("two layers on one box are not neighbours", function()
        local rects: { EcoRules.Rect } = {
            { x = 0, y = 0, width = 100, height = 20 },
            { x = 1, y = 1, width = 98, height = 18 },
        }
        harness.equal(#EcoRules.siblingGaps("Panel", "Text", rects, MIN_GAP), 0)
    end)

    suite:test("UI-CARD-INSET fails text flush to the card edge and passes with padding", function()
        local card: EcoRules.Rect = { x = 0, y = 0, width = 200, height = 60 }
        local flush: EcoRules.Rect = { x = 0, y = 0, width = 200, height = 60 }
        local padded: EcoRules.Rect = { x = 8, y = 8, width = 184, height = 44 }
        local bug = EcoRules.cardInset("Shop", "Row.Name", card, flush, 8)
        harness.equal(#bug, 1)
        harness.equal(bug[1].rule, "UI-CARD-INSET")
        harness.equal(#EcoRules.cardInset("Shop", "Row.Name", card, padded, 8), 0)
    end)

    suite:test("UI-CARD-INSET ignores a text that is outside the card", function()
        local card: EcoRules.Rect = { x = 0, y = 0, width = 50, height = 20 }
        local outside: EcoRules.Rect = { x = 100, y = 100, width = 10, height = 10 }
        harness.equal(#EcoRules.cardInset("Shop", "Row", card, outside, 8), 0)
    end)

    suite:test("UI-TEXT-LOST fails a cut label unless it is marked Truncatable", function()
        local bug = EcoRules.textLost("Hud", "FriendBoostPill.FriendBoost", false, false)
        harness.equal(#bug, 1)
        harness.equal(bug[1].rule, "UI-TEXT-LOST")
        harness.equal(#EcoRules.textLost("Hud", "FriendBoost", true, false), 0)
        harness.equal(#EcoRules.textLost("Hud", "Note", false, true), 0)
    end)

    suite:test("UI-HUD-UNREGISTERED fails a button with no purpose and schemes", function()
        local registry = hudRegistry()
        local bug = EcoRules.hudRegistration("Hud", { "Sprint", "Top", "Mystery" }, registry)
        harness.equal(#bug, 1)
        harness.equal(bug[1].rule, "UI-HUD-UNREGISTERED")
        harness.equal(bug[1].path, "Mystery")
        harness.equal(#EcoRules.hudRegistration("Hud", { "Sprint", "Top" }, registry), 0)
    end)

    suite:test("UI-CONTROL-PLATFORM fails a Run button visible on keyboard and gamepad", function()
        local registry = hudRegistry()
        local keyboard = EcoRules.controlsOnScheme("Hud", "keyboard", { "Sprint", "Top" }, registry)
        harness.equal(#keyboard, 1)
        harness.equal(keyboard[1].rule, "UI-CONTROL-PLATFORM")
        harness.equal(keyboard[1].path, "Sprint")
        harness.equal(#EcoRules.controlsOnScheme("Hud", "gamepad", { "Sprint" }, registry), 1)
        harness.equal(#EcoRules.controlsOnScheme("Hud", "touch", { "Sprint", "Top" }, registry), 0)
        harness.equal(#EcoRules.controlsOnScheme("Hud", "keyboard", { "Top" }, registry), 0)
    end)

    suite:test("SourceRules fails a raw UIListLayout and a literal Padding", function()
        local bug = table.concat({
            'local list = Instance.new("UIListLayout")',
            "list.SortOrder = Enum.SortOrder.LayoutOrder",
            "list.Padding = UDim.new(0, 4)",
        }, "\n")
        local findings = SourceRules.scan("src/client/presenters/mining/RigBoard.luau", bug)
        harness.equal(#findings, 2)
        harness.equal(findings[1].rule, "UI-RAW-LAYOUT")
        harness.equal(findings[1].path, "line 1")
        harness.equal(findings[2].rule, "UI-LITERAL-GAP")
    end)

    suite:test("SourceRules allows the primitive, token gaps and commented code", function()
        local primitive = 'local list = Instance.new("UIGridLayout")'
        harness.equal(
            #SourceRules.scan("src/client/presenters/ui/system/ScrollList.luau", primitive),
            0
        )
        harness.equal(
            #SourceRules.scan("D:\\x\\src\\client\\presenters\\ui\\system\\Atoms.luau", primitive),
            0
        )
        local fixed = table.concat({
            '-- Instance.new("UIListLayout") is forbidden here',
            "Atoms.list(frame, tokens, gapKey, false)",
            "list.Padding = UDim.new(0, Tokens.space(tokens, key))",
        }, "\n")
        harness.equal(#SourceRules.scan("src/client/presenters/mining/RigBoard.luau", fixed), 0)
    end)

    suite:test("InputScheme maps PreferredInput and the last input type", function()
        harness.equal(InputScheme.fromPreferredInput("Touch"), "touch")
        harness.equal(InputScheme.fromPreferredInput("Gamepad"), "gamepad")
        harness.equal(InputScheme.fromPreferredInput("KeyboardAndMouse"), "keyboard")
        harness.equal(InputScheme.fromLastInputType("Gamepad3"), "gamepad")
        harness.equal(InputScheme.fromLastInputType("MouseMovement"), "keyboard")
        harness.equal(InputScheme.fromLastInputType("Touch"), "touch")
        harness.isTrue(InputScheme.fromLastInputType("Focus") == nil)
    end)

    suite:test("key hints come from the configured keys", function()
        harness.equal(InputScheme.keyLabel("LeftShift"), "Shift")
        harness.equal(InputScheme.keyLabel("ButtonL3"), "L3")
        harness.equal(InputScheme.keyLabel("Q"), "Q")
        local keys = { "LeftShift", "ButtonL3" }
        harness.equal(InputScheme.firstKeyFor(keys, "keyboard"), "LeftShift")
        harness.equal(InputScheme.firstKeyFor(keys, "gamepad"), "ButtonL3")
        harness.isTrue(InputScheme.firstKeyFor({ "Q" }, "gamepad") == nil)
    end)

    suite:test(
        "ControlRegistry rejects a control with no purpose, scheme or a duplicate",
        function()
            local registry = hudRegistry()
            local function fails(control: ControlRegistry.Control): boolean
                return not pcall(ControlRegistry.register, registry, control)
            end
            harness.isTrue(fails({ id = "A", purpose = " ", schemes = { "touch" } }))
            harness.isTrue(fails({ id = "B", purpose = "x", schemes = {} }))
            harness.isTrue(fails({ id = "C", purpose = "x", schemes = { "vr" } }))
            harness.isTrue(fails({ id = "Sprint", purpose = "x", schemes = { "touch" } }))
            harness.isTrue(
                fails({ id = "D", purpose = "x", schemes = { "touch" }, hints = { touch = "tap" } })
            )
        end
    )

    suite:test("ControlRegistry shows the button on touch and the hint elsewhere", function()
        local registry = hudRegistry()
        harness.isTrue(ControlRegistry.visibleOn(registry, "Sprint", "touch"))
        harness.isFalse(ControlRegistry.visibleOn(registry, "Sprint", "keyboard"))
        harness.isFalse(ControlRegistry.visibleOn(registry, "Unknown", "touch"))
        harness.equal(ControlRegistry.hintFor(registry, "Sprint", "keyboard"), "Shift")
        harness.equal(ControlRegistry.hintFor(registry, "Sprint", "gamepad"), "L3")
        harness.isTrue(ControlRegistry.hintFor(registry, "Sprint", "touch") == nil)
        harness.isTrue(ControlRegistry.hintFor(registry, "Top", "keyboard") == nil)
    end)

    suite:test("locomotion controls are touch-only with hints from the configured keys", function()
        local registry = ControlRegistry.new()
        LocomotionControls.register(registry, LocomotionConfig.default().keys)
        harness.isTrue(ControlRegistry.visibleOn(registry, "Sprint", "touch"))
        harness.isFalse(ControlRegistry.visibleOn(registry, "Sprint", "keyboard"))
        harness.isFalse(ControlRegistry.visibleOn(registry, "Equip", "gamepad"))
        harness.equal(ControlRegistry.hintFor(registry, "Sprint", "keyboard"), "Shift")
        harness.equal(ControlRegistry.hintFor(registry, "Sprint", "gamepad"), "L3")
        harness.equal(ControlRegistry.hintFor(registry, "Equip", "keyboard"), "Q")
        harness.equal(ControlRegistry.hintFor(registry, "Equip", "gamepad"), "Y")
    end)
end
