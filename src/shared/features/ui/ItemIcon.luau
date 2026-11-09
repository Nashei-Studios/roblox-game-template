--!strict
--[[
    Pure spec of one item icon: the image, the rarity frame, the lock state and the count or level
    badge. A menu builds the spec from its catalog item and the player's state; the engine side
    (`client/presenters/ui/ItemIconView`) only paints it. Loads under Lune.

    Image rule (ADR 0048): an item shows ITS OWN image (a pre-rendered portrait uploaded as an
    image asset). With no image id it falls back to the swatch color, never to a hole. A locked
    item shows the same image as a black silhouette. No ViewportFrame is involved.
]]

local RarityConfig = require("../rarity/RarityConfig")
local RarityFx = require("../rarity/RarityFx")

export type Item = {
    id: string,
    name: string,
    -- A tier id of the RarityConfig.
    rarity: string,
    -- Image asset id: digits only or "rbxassetid://<digits>". nil until uploaded.
    imageAssetId: string?,
    -- Fallback fill when there is no image, "#RRGGBB".
    swatchHex: string,
}

export type State = {
    unlocked: boolean,
    -- Stack size; shown as "xN" above 1 and "99+" above 99.
    count: number?,
    -- Level; wins over count when both are given.
    level: number?,
}

export type ImageMode = "image" | "silhouette" | "swatch"

export type Spec = {
    id: string,
    name: string,
    locked: boolean,
    imageMode: ImageMode,
    -- "rbxassetid://<digits>" for image and silhouette; nil for swatch.
    imageUrl: string?,
    -- ImageColor3 for silhouette ("#000000"), nil for a plain image.
    imageTintHex: string?,
    -- Fill when imageMode is swatch.
    swatchHex: string,
    fx: RarityFx.FxSpec,
    -- Text of the corner badge, nil when there is none.
    badge: string?,
}

local ItemIcon = {}

ItemIcon.BADGE_COUNT_CAP = 99
-- Silhouette color: black keeps the alpha of the image, so the shape stays and the detail goes.
ItemIcon.SILHOUETTE_HEX = "#000000"
-- A swatch shown for a locked item with no image: dark, so it never reads as "owned".
ItemIcon.LOCKED_SWATCH_HEX = "#1A1F33"

--- "rbxassetid://<digits>" from digits or the full form; nil for anything else (including "").
function ItemIcon.imageUrl(assetId: string?): string?
    if assetId == nil then
        return nil
    end
    if string.match(assetId, "^%d+$") ~= nil then
        return `rbxassetid://{assetId}`
    end
    if string.match(assetId, "^rbxassetid://%d+$") ~= nil then
        return assetId
    end
    return nil
end

--- Text of the corner badge: level wins ("Lv 3"), then a count above 1 ("x5", "99+").
function ItemIcon.badge(state: State, levelPrefix: string): string?
    if state.level ~= nil and state.level > 0 then
        return `{levelPrefix} {state.level}`
    end
    if state.count ~= nil and state.count > 1 then
        if state.count > ItemIcon.BADGE_COUNT_CAP then
            return `{ItemIcon.BADGE_COUNT_CAP}+`
        end
        return `x{state.count}`
    end
    return nil
end

--- The spec of one icon. `levelPrefix` is the game's word for a level (a string, never a literal
--- in the presenter).
function ItemIcon.spec(
    item: Item,
    state: State,
    config: RarityConfig.Config,
    quality: RarityFx.Quality,
    surfaceHex: string,
    levelPrefix: string
): Spec
    local url = ItemIcon.imageUrl(item.imageAssetId)
    if not state.unlocked then
        local mode: ImageMode = if url ~= nil then "silhouette" else "swatch"
        return {
            id = item.id,
            name = item.name,
            locked = true,
            imageMode = mode,
            imageUrl = url,
            imageTintHex = if url ~= nil then ItemIcon.SILHOUETTE_HEX else nil,
            swatchHex = ItemIcon.LOCKED_SWATCH_HEX,
            fx = RarityFx.lockedSpec(config, surfaceHex),
            badge = nil,
        }
    end
    return {
        id = item.id,
        name = item.name,
        locked = false,
        imageMode = if url ~= nil then "image" else "swatch",
        imageUrl = url,
        imageTintHex = nil,
        swatchHex = item.swatchHex,
        fx = RarityFx.spec(config, item.rarity, quality, surfaceHex),
        badge = ItemIcon.badge(state, levelPrefix),
    }
end

--- One problem per invalid item (empty when valid): ids unique and non-empty, a known rarity,
--- a well-formed image id when one is given, a "#RRGGBB" swatch.
function ItemIcon.validate(items: { Item }, config: RarityConfig.Config): { string }
    local problems: { string } = {}
    local seen: { [string]: boolean } = {}
    for index, item in items do
        if item.id == "" then
            table.insert(problems, `item {index} has no id`)
        elseif seen[item.id] then
            table.insert(problems, `item id "{item.id}" is repeated`)
        end
        seen[item.id] = true
        if RarityConfig.rank(config, item.rarity) == nil then
            table.insert(problems, `item "{item.id}" has unknown rarity "{item.rarity}"`)
        end
        if item.imageAssetId ~= nil and ItemIcon.imageUrl(item.imageAssetId) == nil then
            table.insert(
                problems,
                `item "{item.id}" image id must be digits or rbxassetid://digits`
            )
        end
        if string.match(item.swatchHex, "^#%x%x%x%x%x%x$") == nil then
            table.insert(problems, `item "{item.id}" swatch must be #RRGGBB`)
        end
    end
    return problems
end

--- Share of items that carry an image id (0..1); the Studio check W12 compares it to the
--- ImageLabel count it reads from the panel.
function ItemIcon.imageCoverage(items: { Item }): number
    if #items == 0 then
        return 1
    end
    local withImage = 0
    for _, item in items do
        if ItemIcon.imageUrl(item.imageAssetId) ~= nil then
            withImage += 1
        end
    end
    return withImage / #items
end

return ItemIcon
