--!strict
--[[
    Registry of the HUD controls: every on-screen button declares its purpose and the schemes
    that need it. A control the player cannot need on the current scheme (a Run button on a
    keyboard, where Shift exists) is hidden and its `hints` entry is shown instead ("Shift").
    The game's UI reads it to show only the controls a scheme needs. Pure. Decision:
    docs/adr/0045-ui-spacing-and-platform-aware-controls.md.
]]

local InputScheme = require("./InputScheme")

export type Control = {
    -- Instance name of the button in the HUD.
    id: string,
    -- Why the control exists, in a sentence. Required: a button with no purpose is a bug.
    purpose: string,
    -- Schemes where the BUTTON is shown. The others never see it. May be empty only when `hints`
    -- covers the control (a key-only control, e.g. run on keyboard and gamepad).
    schemes: { InputScheme.Scheme },
    -- The screen the control lives on: "hud" (default) or a menu id. Button limits and duplicate
    -- destinations are checked per screen.
    screen: string?,
    -- What the control opens or does ("menu:shop", "action:emote"). Two visible controls with the
    -- same destination on one scheme fail UI-DUP-DESTINATION. Nil = nothing to compare.
    destination: string?,
    -- ControlRegistry.CATEGORIES. A game UI can keep a category off touch (the joystick covers locomotion).
    category: string?,
    -- Text shown in place of the button on a scheme that is not in `schemes` (e.g. "Shift").
    hints: { [InputScheme.Scheme]: string }?,
}

export type Registry = {
    controls: { [string]: Control },
    order: { string },
}

local ControlRegistry = {}

--- Control categories a registry entry may declare.
ControlRegistry.CATEGORIES = { "locomotion", "menu", "action", "social" } :: { string }

--- An empty registry.
function ControlRegistry.new(): Registry
    return { controls = {}, order = {} }
end

--- Problems that make a control invalid; empty when it is fine.
function ControlRegistry.validate(control: Control): { string }
    local problems: { string } = {}
    if control.id == "" then
        table.insert(problems, "id is empty")
    end
    if string.match(control.purpose, "%S") == nil then
        table.insert(problems, `{control.id}: purpose is empty`)
    end
    if #control.schemes == 0 and (control.hints == nil or next(control.hints) == nil) then
        table.insert(problems, `{control.id}: no scheme shows it and there is no hint`)
    end
    if control.destination ~= nil and string.match(control.destination, "%S") == nil then
        table.insert(problems, `{control.id}: destination is empty`)
    end
    if
        control.category ~= nil
        and table.find(ControlRegistry.CATEGORIES, control.category) == nil
    then
        table.insert(problems, `{control.id}: unknown category "{control.category}"`)
    end
    for _, scheme in control.schemes do
        if not InputScheme.isScheme(scheme) then
            table.insert(problems, `{control.id}: unknown scheme "{scheme}"`)
        end
    end
    if control.hints ~= nil then
        for scheme, text in control.hints do
            if not InputScheme.isScheme(scheme) then
                table.insert(problems, `{control.id}: hint for unknown scheme "{scheme}"`)
            elseif table.find(control.schemes, scheme) ~= nil then
                table.insert(
                    problems,
                    `{control.id}: "{scheme}" shows the button, it needs no hint`
                )
            elseif string.match(text, "%S") == nil then
                table.insert(problems, `{control.id}: hint for "{scheme}" is empty`)
            end
        end
    end
    return problems
end

--- Registers a control; raises on an invalid or duplicate one (a boot-time bug, not a runtime state).
function ControlRegistry.register(registry: Registry, control: Control)
    local problems = ControlRegistry.validate(control)
    if registry.controls[control.id] ~= nil then
        table.insert(problems, `{control.id}: already registered`)
    end
    if #problems > 0 then
        error(`invalid HUD control:\n{table.concat(problems, "\n")}`, 2)
    end
    registry.controls[control.id] = control
    table.insert(registry.order, control.id)
end

--- True when the registry knows `id`.
function ControlRegistry.has(registry: Registry, id: string): boolean
    return registry.controls[id] ~= nil
end

--- True when the BUTTON of `id` belongs on `scheme`. An unknown id is false: unregistered
--- controls are never shown by code that asks the registry.
function ControlRegistry.visibleOn(
    registry: Registry,
    id: string,
    scheme: InputScheme.Scheme
): boolean
    local control = registry.controls[id]
    return control ~= nil and table.find(control.schemes, scheme) ~= nil
end

--- The controls whose BUTTON is shown on `scheme`, in registration order.
function ControlRegistry.onScheme(registry: Registry, scheme: InputScheme.Scheme): { Control }
    local out: { Control } = {}
    for _, id in registry.order do
        local control = registry.controls[id]
        if table.find(control.schemes, scheme) ~= nil then
            table.insert(out, control)
        end
    end
    return out
end

--- The hint text shown instead of the button on `scheme`, nil when the button is shown or
--- there is no hint.
function ControlRegistry.hintFor(
    registry: Registry,
    id: string,
    scheme: InputScheme.Scheme
): string?
    local control = registry.controls[id]
    if control == nil or table.find(control.schemes, scheme) ~= nil or control.hints == nil then
        return nil
    end
    return control.hints[scheme]
end

return ControlRegistry
