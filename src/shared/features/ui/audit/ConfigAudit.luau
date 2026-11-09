--!strict
--[[
    The declaration-level half of the UI gate (docs/adr/0061): it needs no instances, only what the
    template declares. It builds the control registry from the shipped features (item slots, item
    viewer, locomotion) and checks it, and checks the menu motion declared in the UI config. A game
    that registers more controls passes its own registry to `auditRegistry`.
]]

local ControlRegistry = require("../ControlRegistry")
local Finding = require("./Finding")
local GateRules = require("./GateRules")
local InputScheme = require("../InputScheme")
local InspectView = require("../../inspect/InspectView")
local ItemSlots = require("../../itemslots/ItemSlots")
local LocomotionConfig = require("../../locomotion/LocomotionConfig")
local LocomotionControls = require("../../locomotion/LocomotionControls")
local UiConfig = require("../UiConfig")
local UiGates = require("../UiGates")

export type Finding = Finding.Finding

local ConfigAudit = {}

--- The registry of the controls the template ships, from the default feature configs.
function ConfigAudit.templateRegistry(): ControlRegistry.Registry
    local registry = ControlRegistry.new()
    LocomotionControls.register(registry, LocomotionConfig.default().keys)
    ItemSlots.register(registry, ItemSlots.default)
    InspectView.register(registry, InspectView.default)
    return registry
end

--- Duplicate destinations, touch locomotion and button limits of one registry.
function ConfigAudit.auditRegistry(
    scope: string,
    registry: ControlRegistry.Registry,
    ui: UiConfig.UiConfig
): { Finding }
    local out: { Finding } = {}
    local function add(list: { Finding })
        for _, finding in list do
            table.insert(out, finding)
        end
    end
    for _, scheme in InputScheme.ALL do
        add(GateRules.registryDuplicates(scope, registry, scheme))
    end
    add(GateRules.touchLocomotion(scope, registry, ui.gates))
    add(GateRules.registryButtonLimits(scope, registry, ui.gates))
    return out
end

--- Everything declaration-level: the UI config motion plus the template registry.
function ConfigAudit.audit(ui: UiConfig.UiConfig): { Finding }
    local menus: { UiGates.MotionMenu } = {}
    for _, menu in ui.menus do
        table.insert(menus, { id = menu.id, modal = menu.modal, motion = menu.motion })
    end
    local out = GateRules.motion("ui.menus", menus, ui.theme.motionSeconds)
    for _, finding in ConfigAudit.auditRegistry("template", ConfigAudit.templateRegistry(), ui) do
        table.insert(out, finding)
    end
    return out
end

return ConfigAudit
