--!strict
--[[
    Client presenter of the CollectionIndex mold (ADR 0046): a counter ("Unlocked 85/126"), a
    progress bar toward the next finite reward, a claim button, optional tabs and a grid of cards.
    An undiscovered card draws the BLACK SILHOUETTE of its icon (the same image tinted black, so
    the shape is the real one) and no name: the snapshot of the server carries none.

    Built only from the UI system (tokens, Stack, ScrollList.grid, Parts.progressBar/tabs, Button).
    It fills the body of a menu shell the game owns; opening, closing in one tap and never covering
    the gameplay is that shell job, not this panel. The icon is a slot: a game passes `renderIcon`
    (an ItemIcon, a ViewportFrame, a model portrait); the default draws `iconRef` as an image.
    Engine code, excluded from the line-coverage gate and kept thin. UNVERIFIED until a person
    checks it in Studio at 1920x1080, 844x390, 667x375 and 568x320.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollectionIndex = require(Shared.features.collectionindex.CollectionIndex)
local Atoms = require(script.Parent.system.Atoms)
local Button = require(script.Parent.system.Button)
local DevGuard = require(script.Parent.system.DevGuard)
local Parts = require(script.Parent.system.Parts)
local ScrollList = require(script.Parent.system.ScrollList)
local UiEnv = require(script.Parent.system.UiEnv)

-- Texts belong to the game (localization, tone); the mold names none of its own.
export type Labels = {
    -- "Unlocked": the panel writes "<counter> found/total".
    counter: string,
    claim: string,
    -- Shown instead of a name while an entry is undiscovered (a game may pass "???" or "").
    undiscovered: string,
    -- "Next reward at": followed by the entries count.
    nextReward: string,
    allRewards: string,
}

-- Draws the icon of one entry inside `slot`. `silhouette` = true means draw it black.
export type IconRenderer = (
    env: UiEnv.UiEnv,
    slot: Frame,
    entry: CollectionIndex.ViewEntry,
    silhouette: boolean
) -> ()

export type Deps = {
    labels: Labels,
    -- Runs when the player presses claim for a milestone. The game sends it to the server.
    onClaim: (milestoneId: string) -> (),
    renderIcon: IconRenderer?,
    -- Second line of a card (a rarity and its odds). Called for found and undiscovered entries.
    captionFor: ((entry: CollectionIndex.ViewEntry) -> string)?,
}

export type Panel = {
    root: Frame,
    setSnapshot: (self: Panel, snapshot: CollectionIndex.Snapshot) -> (),
}

local MIN_CARD_WIDTH = 168
local CARD_HEIGHT = 72

local CollectionIndexPanel = {}

--- The default icon: `iconRef` as an image, tinted black for a silhouette. No ref = a block.
local function defaultIcon(
    env: UiEnv.UiEnv,
    slot: Frame,
    entry: CollectionIndex.ViewEntry,
    silhouette: boolean
)
    local palette = env.tokens.palette
    local ref = entry.iconRef
    if ref == nil then
        slot.BackgroundTransparency = 0
        slot.BackgroundColor3 = if silhouette
            then Color3.new(0, 0, 0)
            else Atoms.color(palette.surfaceRaised)
        return
    end
    local image = Instance.new("ImageLabel")
    image.Name = "Image"
    image.BackgroundTransparency = 1
    image.Size = UDim2.fromScale(1, 1)
    image.ScaleType = Enum.ScaleType.Fit
    image.Image = ref
    -- Tinting a transparent icon black keeps its alpha: the shape stays the real one.
    image.ImageColor3 = if silhouette then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
    image.Parent = slot
end

function CollectionIndexPanel.new(env: UiEnv.UiEnv, parent: Instance, deps: Deps): Panel
    local tokens = env.tokens
    local gapPx = tokens.spacing.sm
    local capH = math.ceil(tokens.type.caption * 1.4)

    local root = Instance.new("Frame")
    root.Name = "CollectionIndex"
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1, 1)
    root.Parent = parent

    -- Header: counter and claim on one row, the bar and its caption under it, tabs last.
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.BackgroundTransparency = 1
    header.Size = UDim2.fromScale(1, 0)
    header.Parent = root

    local topRow = Instance.new("Frame")
    topRow.Name = "TopRow"
    topRow.BackgroundTransparency = 1
    topRow.Size = UDim2.new(1, 0, 0, tokens.touchMin)
    topRow.Parent = header

    local claimWidth = tokens.touchMin * 3
    local counter = Atoms.label(topRow, tokens, "Counter", "", "title", tokens.palette.textPrimary)
    counter.Size = UDim2.new(1, -(claimWidth + gapPx), 1, 0)
    counter.TextYAlignment = Enum.TextYAlignment.Center

    local pendingClaim: string? = nil
    local claim = Button.new(env, topRow, {
        name = "Claim",
        text = deps.labels.claim,
        variant = "primary",
        width = claimWidth,
        onActivated = function()
            local milestoneId = pendingClaim
            if milestoneId ~= nil then
                deps.onClaim(milestoneId)
            end
        end,
    })
    claim.AnchorPoint = Vector2.new(1, 0)
    claim.Position = UDim2.fromScale(1, 0)
    claim.Visible = false

    local barRow = Instance.new("Frame")
    barRow.Name = "BarRow"
    barRow.BackgroundTransparency = 1
    barRow.Size = UDim2.new(1, 0, 0, tokens.spacing.md + gapPx + capH)
    barRow.Position = UDim2.fromOffset(0, tokens.touchMin + gapPx)
    barRow.Parent = header
    local bar = Parts.progressBar(env, barRow, "Progress", "accent")
    local barCaption =
        Atoms.label(barRow, tokens, "BarCaption", "", "caption", tokens.palette.textMuted)
    barCaption.Position = UDim2.fromOffset(0, tokens.spacing.md + gapPx)

    local tabsHost = Instance.new("Frame")
    tabsHost.Name = "TabsHost"
    tabsHost.BackgroundTransparency = 1
    tabsHost.Size = UDim2.new(1, 0, 0, tokens.touchMin)
    tabsHost.Position = UDim2.fromOffset(0, tokens.touchMin + gapPx + barRow.Size.Y.Offset + gapPx)
    tabsHost.Visible = false
    tabsHost.Parent = header

    local grid = ScrollList.grid(env, root, {
        name = "Entries",
        minCardWidth = MIN_CARD_WIDTH,
        cardHeight = CARD_HEIGHT,
    })

    local baseHeader = tokens.touchMin + gapPx + barRow.Size.Y.Offset
    local function layout(showTabs: boolean)
        local headerHeight = baseHeader + (if showTabs then gapPx + tokens.touchMin else 0)
        header.Size = UDim2.new(1, 0, 0, headerHeight)
        grid.Position = UDim2.fromOffset(0, headerHeight + gapPx)
        grid.Size = UDim2.new(1, 0, 1, -(headerHeight + gapPx))
    end
    layout(false)

    type Card = { frame: Frame, name: TextLabel, caption: TextLabel, slot: Frame }
    local cards: { [string]: Card } = {}
    local entryGroup: { [string]: string } = {}
    local activeTab: string? = nil
    local tabs: Parts.Tabs? = nil
    local renderIcon: IconRenderer = if deps.renderIcon ~= nil then deps.renderIcon else defaultIcon

    local function applyTab()
        for id, card in cards do
            card.frame.Visible = activeTab == nil or entryGroup[id] == activeTab
        end
    end

    local function buildCard(order: number, entry: CollectionIndex.ViewEntry): Card
        local frame = ScrollList.item(env, grid, entry.id)
        frame.LayoutOrder = order
        local iconEdge = CARD_HEIGHT - tokens.spacing.sm * 4
        local slot = Instance.new("Frame")
        slot.Name = "Icon"
        slot.BackgroundTransparency = 1
        slot.AnchorPoint = Vector2.new(0, 0.5)
        slot.Position = UDim2.fromScale(0, 0.5)
        slot.Size = UDim2.fromOffset(iconEdge, iconEdge)
        slot.Parent = frame
        local text = Instance.new("Frame")
        text.Name = "Text"
        text.BackgroundTransparency = 1
        text.AnchorPoint = Vector2.new(1, 0.5)
        text.Position = UDim2.fromScale(1, 0.5)
        text.Size = UDim2.new(1, -(iconEdge + tokens.spacing.sm), 1, 0)
        text.Parent = frame
        local list = Atoms.list(text, tokens, "xs", false)
        list.VerticalAlignment = Enum.VerticalAlignment.Center
        local name = Atoms.label(text, tokens, "Name", "", "body", tokens.palette.textPrimary)
        local caption =
            Atoms.label(text, tokens, "Caption", "", "caption", tokens.palette.textMuted)
        return { frame = frame, name = name, caption = caption, slot = slot }
    end

    local function paintCard(card: Card, entry: CollectionIndex.ViewEntry)
        for _, child in card.slot:GetChildren() do
            child:Destroy()
        end
        renderIcon(env, card.slot, entry, not entry.found)
        card.name.Text = entry.name or deps.labels.undiscovered
        card.name.TextColor3 = Atoms.color(
            if entry.found then tokens.palette.textPrimary else tokens.palette.textMuted
        )
        local caption = deps.captionFor
        card.caption.Text = if caption ~= nil then caption(entry) else ""
    end

    local self = {} :: Panel
    self.root = root

    function self.setSnapshot(_self: Panel, snapshot: CollectionIndex.Snapshot)
        counter.Text = `{deps.labels.counter} {snapshot.found}/{snapshot.total}`
        bar:set(snapshot.barFraction)

        local nextAt: number? = nil
        local claimable: string? = nil
        for _, milestone in snapshot.milestones do
            if milestone.id == snapshot.nextMilestoneId then
                nextAt = milestone.atFound
            end
            if claimable == nil and milestone.claimable then
                claimable = milestone.id
            end
        end
        barCaption.Text = if nextAt ~= nil
            then `{deps.labels.nextReward} {nextAt}`
            else deps.labels.allRewards
        pendingClaim = claimable
        claim.Visible = claimable ~= nil

        if next(cards) == nil then
            for order, entry in snapshot.entries do
                cards[entry.id] = buildCard(order, entry)
                entryGroup[entry.id] = entry.group
            end
        end
        for _, entry in snapshot.entries do
            local card = cards[entry.id]
            if card ~= nil then
                paintCard(card, entry)
            end
        end

        if snapshot.showTabs and tabs == nil then
            local list: { Parts.Tab } = {}
            for _, tab in snapshot.tabs do
                table.insert(list, { id = tab.id, label = tab.label })
            end
            activeTab = list[1].id
            tabs = Parts.tabs(env, tabsHost, list, function(id: string)
                activeTab = id
                applyTab()
            end)
        end
        tabsHost.Visible = snapshot.showTabs
        local firstTab = snapshot.tabs[1]
        if not snapshot.showTabs then
            activeTab = nil
        elseif activeTab == nil and firstTab ~= nil then
            activeTab = firstTab.id
            if tabs ~= nil then
                tabs:select(firstTab.id)
            end
        end
        layout(snapshot.showTabs)
        applyTab()
    end

    DevGuard.verify(root, "CollectionIndexPanel")
    return self
end

return CollectionIndexPanel
