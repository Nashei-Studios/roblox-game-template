--!strict
--[[
    The kit adapter contract. A UI kit is data: a tree of Instances shipped as .rbxm. An adapter
    says WHERE each component slot lives in that tree and WHICH named parts the slot must have, so
    the engine builders clone a kit piece, bind it by part name and never hardcode a kit path.
    A new kit = a new adapter file; no component changes.

    Rules (plus-one-mining ADR 0047, kept as the factory law):
    - Kit-native: never re-tint a kit piece, never touch a kit UIStroke Thickness or
      StrokeSizingMode. The adapter exposes parts to BIND (text, icon, visibility), not to restyle.
    - A slot the kit lacks is absent from the adapter and the builder falls back to the "plain"
      piece drawn from the Tokens, so a game works with a kit that covers only part of the slots.
    - `verify` runs at boot and in the gate against the real tree; a missing part is a loud
      error that names the kit, the slot and the part.

    Pure: `verify` takes a finder function instead of an Instance, so it runs under Lune (against
    a deserialized .rbxm or a fake tree) and in the engine alike.
]]

export type Slot = string -- one of KitAdapter.SLOTS; REQUIRED_PARTS rejects the rest

export type Binding = {
    -- Slash separated path from the kit root to the piece.
    path: string,
    -- Part name -> dot path from the piece to the descendant to bind.
    parts: { [string]: string },
    -- Dot paths (from the piece) of containers whose GuiObject children are demo content to drop
    -- after cloning (the kit ships sample rows inside its menu template). Layouts are kept.
    clear: { string }?,
}

export type KitAdapter = {
    -- Adapter id, stable and kebab-case.
    id: string,
    -- Slug of the kit in kits.manifest (assets/kits.manifest.luau). nil for the plain fallback.
    kitSlug: string?,
    -- Licence summary copied from the kit, so a reader sees what ships.
    license: string,
    -- Slots this kit covers. A slot not listed falls back to the plain piece.
    slots: { [string]: Binding },
}

-- The parts each slot MUST expose. Builders bind exactly these names.
local REQUIRED_PARTS: { [string]: { string } } = {
    ["menu.shell"] = { "title", "close", "body" },
    ["menu.rowCard"] = { "name", "description", "action" },
    ["menu.rowToggle"] = { "name", "toggle" },
    ["menu.rowUpgrade"] = { "action" },
    ["hud.button"] = { "icon", "badge" },
    ["tooltip.button"] = { "label" },
    ["effects.strip"] = {},
}

local KitAdapterModule = {}

local SLOT_LIST: { string } = {
    "menu.shell",
    "menu.rowCard",
    "menu.rowToggle",
    "menu.rowUpgrade",
    "hud.button",
    "tooltip.button",
    "effects.strip",
}
KitAdapterModule.SLOTS = SLOT_LIST

--- The part names a slot must expose.
function KitAdapterModule.requiredParts(slot: Slot): { string }
    local parts = REQUIRED_PARTS[slot]
    if parts == nil then
        error(`unknown UI slot "{slot}"`, 2)
    end
    return parts
end

--- Static check of the adapter itself (no tree needed).
function KitAdapterModule.validate(adapter: KitAdapter): { string }
    local problems: { string } = {}
    if string.match(adapter.id, "^[a-z0-9]+[a-z0-9%-]*$") == nil then
        table.insert(problems, `adapter id "{adapter.id}" must be lowercase kebab-case`)
    end
    if adapter.license == "" then
        table.insert(problems, `adapter {adapter.id}: license must state the terms or "unknown"`)
    end
    for slot, binding in adapter.slots do
        local required = REQUIRED_PARTS[slot]
        if required == nil then
            table.insert(problems, `adapter {adapter.id}: unknown slot "{slot}"`)
            continue
        end
        if binding.path == "" or string.find(binding.path, "^/") ~= nil then
            table.insert(problems, `adapter {adapter.id}: slot {slot} needs a relative path`)
        end
        for _, part in required do
            local dotPath = binding.parts[part]
            if dotPath == nil or dotPath == "" then
                table.insert(
                    problems,
                    `adapter {adapter.id}: slot {slot} does not map part "{part}"`
                )
            end
        end
    end
    return problems
end

--- Checks the adapter against a tree. `exists(path)` answers whether the kit root has the
--- descendant at a slash path. Returns one sentence per missing piece or part.
function KitAdapterModule.verify(adapter: KitAdapter, exists: (path: string) -> boolean): { string }
    local problems: { string } = {}
    for slot, binding in adapter.slots do
        if not exists(binding.path) then
            table.insert(problems, `kit {adapter.id}: slot {slot} has no piece at "{binding.path}"`)
            continue
        end
        for part, dotPath in binding.parts do
            local relative = string.gsub(dotPath, "%.", "/")
            local full = binding.path .. "/" .. relative
            if not exists(full) then
                table.insert(
                    problems,
                    `kit {adapter.id}: slot {slot} part "{part}" missing at "{full}"`
                )
            end
        end
        local clearPaths: { string } = binding.clear or {}
        for _, dotPath in clearPaths do
            local full = binding.path .. "/" .. string.gsub(dotPath, "%.", "/")
            if not exists(full) then
                table.insert(
                    problems,
                    `kit {adapter.id}: slot {slot} clear target missing at "{full}"`
                )
            end
        end
    end
    return problems
end

--- Slots a kit does not cover (they use the plain fallback).
function KitAdapterModule.uncovered(adapter: KitAdapter): { Slot }
    local out: { Slot } = {}
    for _, slot in KitAdapterModule.SLOTS do
        if adapter.slots[slot] == nil then
            table.insert(out, slot)
        end
    end
    return out
end

return KitAdapterModule
