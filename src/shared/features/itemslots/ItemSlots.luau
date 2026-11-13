--!strict
--[[
    ItemSlots mold: the pure model of a small hotbar of equipped items. It decides how many slots
    exist (config), what each one shows (an ItemIcon.Spec: image, rarity frame, level or count
    badge), which key or glyph hint each scheme gets, and what a tap does (open the item panel
    through the ItemPanel port). The game UI only paints
    and places it. Loads under Lune.

    Hints follow ADR 0045: keyboard shows the number key ("1"), gamepad the glyph of the pad button
    ("L1"), touch shows none because the slot itself is the tap target. A slot is visible on every
    scheme (the player must see what they hold), so its registry entry lists all three schemes.
    Decision: docs/adr/0055-item-slots-mold.md. Issue #126.
]]

local InputScheme = require("../ui/InputScheme")
local ControlRegistry = require("../ui/ControlRegistry")
local ItemIcon = require("../ui/ItemIcon")
local RarityConfig = require("../rarity/RarityConfig")
local RarityFx = require("../rarity/RarityFx")
local ItemPanel = require("../../ports/ItemPanel")

export type Config = {
    -- Number of slots, 1..MAX_SLOTS.
    count: number,
    -- Per slot, the Enum.KeyCode names that select it, keyboard and gamepad mixed
    -- (e.g. { "One", "ButtonL1" }). Missing entries mean "no key for that slot".
    keys: { { string } },
}

export type Entry = {
    item: ItemIcon.Item,
    state: ItemIcon.State,
}

export type SlotView = {
    -- Instance name of the slot button; also its ControlRegistry id.
    id: string,
    index: number,
    -- nil for an empty slot.
    itemId: string?,
    spec: ItemIcon.Spec?,
    -- True for the slot of the item in hand.
    selected: boolean,
    hints: { [string]: string },
}

local ItemSlots = {}

ItemSlots.MAX_SLOTS = 9

ItemSlots.default = {
    count = 4,
    keys = {
        { "One", "ButtonL1" },
        { "Two" },
        { "Three" },
        { "Four", "ButtonR1" },
    },
} :: Config

local DIGIT_NAMES: { [string]: string } = {
    One = "1",
    Two = "2",
    Three = "3",
    Four = "4",
    Five = "5",
    Six = "6",
    Seven = "7",
    Eight = "8",
    Nine = "9",
    Zero = "0",
}

--- Id (and instance name) of the slot at `index`.
function ItemSlots.slotId(index: number): string
    return `Slot{index}`
end

--- Problems that make a config invalid; empty when fine.
function ItemSlots.validate(config: Config): { string }
    local problems: { string } = {}
    if
        config.count < 1
        or config.count > ItemSlots.MAX_SLOTS
        or config.count ~= math.floor(config.count)
    then
        table.insert(problems, `itemSlots.count must be an integer 1..{ItemSlots.MAX_SLOTS}`)
    end
    local seen: { [string]: number } = {}
    for index, list in config.keys do
        if index > config.count then
            table.insert(problems, `itemSlots.keys[{index}] has no slot (count {config.count})`)
        end
        for _, key in list do
            if seen[key] ~= nil then
                table.insert(
                    problems,
                    `itemSlots key "{key}" is bound to slots {seen[key]} and {index}`
                )
            end
            seen[key] = index
        end
    end
    return problems
end

--- The hint of a key name: "One" -> "1", "ButtonL1" -> "L1", "F" -> "F".
local function label(key: string): string
    return DIGIT_NAMES[key] or InputScheme.keyLabel(key)
end

--- Hint text of slot `index` for `scheme`, nil when there is none (always nil on touch).
function ItemSlots.hintFor(config: Config, index: number, scheme: InputScheme.Scheme): string?
    local keys = config.keys[index]
    if keys == nil or scheme == InputScheme.TOUCH then
        return nil
    end
    local key = InputScheme.firstKeyFor(keys, scheme)
    return if key ~= nil then label(key) else nil
end

--- Registers every slot in `registry`. Each is visible on every scheme: the slot shows what the
--- player holds, so it is never swapped for a hint, which is drawn inside it instead.
function ItemSlots.register(registry: ControlRegistry.Registry, config: Config)
    for index = 1, config.count do
        ControlRegistry.register(registry, {
            id = ItemSlots.slotId(index),
            purpose = "shows an equipped item; tap or press its key to open its panel",
            schemes = { InputScheme.TOUCH, InputScheme.KEYBOARD, InputScheme.GAMEPAD },
        })
    end
end

--- The `count` slots for the equipped `entries` (in order; fewer entries leave empty slots,
--- extra ones are dropped). `selectedIndex` marks the item in hand.
function ItemSlots.view(
    config: Config,
    entries: { Entry },
    selectedIndex: number?,
    rarity: RarityConfig.Config,
    quality: RarityFx.Quality,
    surfaceHex: string,
    levelPrefix: string
): { SlotView }
    local slots: { SlotView } = {}
    for index = 1, config.count do
        local entry = entries[index]
        local hints: { [string]: string } = {}
        for _, scheme in InputScheme.ALL do
            local text = ItemSlots.hintFor(config, index, scheme)
            if text ~= nil then
                hints[scheme] = text
            end
        end
        table.insert(slots, {
            id = ItemSlots.slotId(index),
            index = index,
            itemId = if entry ~= nil then entry.item.id else nil,
            spec = if entry ~= nil
                then ItemIcon.spec(
                    entry.item,
                    entry.state,
                    rarity,
                    quality,
                    surfaceHex,
                    levelPrefix
                )
                else nil,
            selected = selectedIndex == index and entry ~= nil,
            hints = hints,
        })
    end
    return slots
end

--- A tap on slot `index`: opens the item panel through the port. An empty or unknown slot does
--- nothing and returns false.
function ItemSlots.tap(slots: { SlotView }, index: number, panel: ItemPanel.ItemPanel): boolean
    local slot = slots[index]
    if slot == nil or slot.itemId == nil then
        return false
    end
    panel:open(slot.itemId)
    return true
end

--- Slot index bound to an Enum.KeyCode name, nil when none.
function ItemSlots.indexForKey(config: Config, keyName: string): number?
    for index, list in config.keys do
        if index <= config.count and table.find(list, keyName) ~= nil then
            return index
        end
    end
    return nil
end

return ItemSlots
