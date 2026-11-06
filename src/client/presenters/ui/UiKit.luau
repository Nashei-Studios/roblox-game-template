--!strict
--[[
    Client presenter: the UiPresenter port. Builds the HUD, shop, rewards, settings and
    leaderboards screens from Config.default.ui tokens and texts, and the actions each button
    triggers are injected (Main.client passes the remote calls), so no game rule lives here.

    Device rules (~/.claude/rules/luau.md, "UI y dispositivos"):
    - Sizes are UDim2 scale; points (tokens) are scaled by one root UIScale (Layout.scaleFor).
    - The ScreenGui uses CoreUISafeInsets, so notches and the top bar are respected.
    - Buttons are never under the touch floor (Layout.buttonHeight); nothing depends on hover.
    - Menus toggle by touch (HUD buttons), keyboard and gamepad (ContextActionService); a gamepad
      gets a selected button when a menu opens.
    - Prices come from the shop rows (ShopModel), read at runtime; none is written here.
    It touches the engine, so it is excluded from the line-coverage gate and kept thin.
    UNVERIFIED until a person checks it in Studio's Device Emulator (small phone, tablet, 1080p).
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local BoardKey = require(Shared.features.leaderboards.BoardKey)
local Layout = require(Shared.features.ui.Layout)
local MenuController = require(Shared.features.ui.MenuController)
local ShopModel = require(Shared.features.ui.ShopModel)
local UiConfig = require(Shared.features.ui.UiConfig)
local Widgets = require(script.Parent.Widgets)

export type Actions = {
    buy: (productName: string) -> (),
    claimDaily: () -> (),
    claimGift: (giftId: string) -> (),
    joinCommunity: () -> (),
    checkCommunity: () -> (),
    setVolume: (group: "music" | "sfx", percent: number) -> (),
}

export type Content = {
    products: { ShopModel.Product },
    giftIds: { string },
    -- Board ids in display order.
    boardIds: { string },
    -- True when the community card is shown (module enabled, configured, promptJoin).
    showCommunityCard: boolean,
}

export type Deps = {
    playerGui: PlayerGui,
    camera: Camera,
    config: UiConfig.UiConfig,
    content: Content,
    actions: Actions,
    -- Resolves a user id to a display name (may yield); nil falls back to the id text.
    nameOf: (userId: number) -> string?,
}

export type UiKit = {
    -- The UiPresenter port (MenuController drives it).
    presenter: {
        setVisible: (self: unknown, menuId: string, visible: boolean) -> (),
        setText: (self: unknown, slot: string, text: string) -> (),
    },
    menus: MenuController.MenuController,
    gui: ScreenGui,
    -- Fresh shop rows after prices were read.
    setShopRows: (self: UiKit, rows: { ShopModel.Row }) -> (),
    setVolumes: (self: UiKit, music: number, sfx: number) -> (),
    -- Rebuilds one leaderboard from the replicated text (BoardKey.decodePublished).
    setBoard: (self: UiKit, boardId: string, text: string) -> (),
}

local UiKitModule = {}

function UiKitModule.new(deps: Deps): UiKit
    local theme = UiConfig.resolve(deps.config.theme)
    local strings = deps.config.strings
    local gui = Instance.new("ScreenGui")
    gui.Name = "UiKit"
    gui.ResetOnSpawn = false
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local root = Instance.new("Frame")
    root.Name = "Root"
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1, 1)
    root.Parent = gui
    local uiScale = Instance.new("UIScale")
    uiScale.Parent = root

    local function rescale()
        local size = deps.camera.ViewportSize
        local scale = Layout.scaleFor(size.X, size.Y, theme)
        uiScale.Scale = scale
        -- UIScale also scales the root itself: this keeps it exactly the size of the screen.
        root.Size = UDim2.fromScale(1 / scale, 1 / scale)
    end
    rescale()
    deps.camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
    local function buttonHeight(): number
        return Layout.buttonHeight(theme, uiScale.Scale)
    end

    local screens: { [string]: GuiObject? } = {}
    local texts: { [string]: TextLabel? } = {}
    local lists: { [string]: ScrollingFrame? } = {}
    local shopButtons: { [string]: TextButton } = {}
    local volumeLabels: { [string]: TextLabel } = {}
    local volumes: { [string]: number } = { music = 0, sfx = 0 }
    local sendToken = 0

    local function newScreen(menu: UiConfig.MenuConfig): Frame
        local screen = Widgets.panel(root, theme, menu.id, theme.palette.surface)
        screen.AnchorPoint = Vector2.new(0.5, 0.5)
        screen.Position = UDim2.fromScale(0.5, 0.5)
        screen.Size = UDim2.fromScale(theme.panel.widthScale, theme.panel.heightScale)
        local limit = Instance.new("UISizeConstraint")
        limit.MaxSize = Vector2.new(theme.panel.maxWidthPoints, math.huge)
        limit.Parent = screen
        Widgets.pad(screen, theme.spacing.md)
        Widgets.stack(screen, theme.spacing.md)
        local title =
            Widgets.label(screen, theme, "Title", menu.title, "title", theme.palette.textPrimary)
        title.LayoutOrder = 1
        local list = Instance.new("ScrollingFrame")
        list.Name = "List"
        list.BackgroundTransparency = 1
        list.BorderSizePixel = 0
        list.Size = UDim2.fromScale(1, 0.7)
        list.CanvasSize = UDim2.fromScale(0, 0)
        list.AutomaticCanvasSize = Enum.AutomaticSize.Y
        list.ScrollBarThickness = theme.strokeThickness * 4
        list.LayoutOrder = 2
        list.Parent = screen
        Widgets.stack(list, theme.spacing.sm)
        lists[menu.id] = list
        local close = Widgets.button(
            screen,
            theme,
            "Close",
            strings.close,
            buttonHeight(),
            function()
                -- The real handler is connected below, once the MenuController exists.
            end
        )
        close.LayoutOrder = 3
        screens[menu.id] = screen
        return screen
    end

    local function clearList(list: ScrollingFrame)
        for _, child in list:GetChildren() do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
    end

    -- Menus are created first so the controller can be built, then wired to the buttons.
    local menuById: { [string]: UiConfig.MenuConfig } = {}
    for _, menu in deps.config.menus do
        menuById[menu.id] = menu
    end

    local hud = Widgets.panel(root, theme, "hud", theme.palette.background)
    hud.BackgroundTransparency = 1
    hud.AnchorPoint = Vector2.new(0.5, 1)
    hud.Position = UDim2.fromScale(0.5, 1)
    hud.Size = UDim2.fromScale(1, 0)
    hud.AutomaticSize = Enum.AutomaticSize.Y
    Widgets.pad(hud, theme.spacing.sm)
    Widgets.stack(hud, theme.spacing.sm)
    screens.hud = hud
    local coins = Widgets.label(
        hud,
        theme,
        "Coins",
        `{strings.coinsLabel}: 0`,
        "body",
        theme.palette.textPrimary
    )
    coins.LayoutOrder = 1
    texts["hud.coins"] = coins
    local bar = Instance.new("Frame")
    bar.Name = "Bar"
    bar.BackgroundTransparency = 1
    bar.Size = UDim2.fromScale(1, 0)
    bar.AutomaticSize = Enum.AutomaticSize.Y
    bar.LayoutOrder = 2
    bar.Parent = hud
    Widgets.stack(bar, theme.spacing.sm, true)

    for _, menu in deps.config.menus do
        if menu.modal then
            local screen = newScreen(menu)
            screen.Visible = false
        end
    end

    local presenter = {
        setVisible = function(_self: unknown, menuId: string, visible: boolean)
            local screen = screens[menuId]
            if screen == nil then
                warn(`ui: no screen for menu "{menuId}"`)
                return
            end
            screen.Visible = visible
            if visible and menuId ~= "hud" and UserInputService.GamepadEnabled then
                local list = lists[menuId]
                local first = if list ~= nil then list:FindFirstChildWhichIsA("GuiButton") else nil
                GuiService.SelectedObject = first
            end
        end,
        setText = function(_self: unknown, slot: string, text: string)
            local label = texts[slot]
            if label ~= nil then
                label.Text = text
            end
        end,
    }
    local menus = MenuController.new({ menus = deps.config.menus, presenter = presenter })

    -- Close buttons and HUD buttons, now that the controller exists.
    for menuId, screen in screens do
        local close = if screen ~= nil then screen:FindFirstChild("Close") else nil
        if close ~= nil and close:IsA("TextButton") then
            close.Activated:Connect(function()
                menus:close(menuId)
            end)
        end
    end
    for index, menu in deps.config.menus do
        if menu.modal then
            local opener = Widgets.button(
                bar,
                theme,
                `Open{menu.id}`,
                menu.title,
                buttonHeight(),
                function()
                    menus:toggle(menu.id)
                end
            )
            opener.Size = UDim2.fromOffset(0, buttonHeight())
            opener.AutomaticSize = Enum.AutomaticSize.X
            opener.LayoutOrder = index
            Widgets.pad(opener, theme.spacing.md)
        end
    end

    -- Shop: one button per product; text and enabled state come from ShopModel rows.
    local function listOf(menuId: string): ScrollingFrame
        local list = lists[menuId]
        if list == nil then
            error(`ui.menus is missing "{menuId}" (Config.validate reports it)`)
        end
        return list
    end
    local shopList = listOf("shop")
    local rewardsList = listOf("rewards")
    local settingsList = listOf("settings")

    local function setShopRows(rows: { ShopModel.Row })
        clearList(shopList)
        table.clear(shopButtons)
        for index, row in rows do
            local button = Widgets.button(
                shopList,
                theme,
                row.productName,
                `{row.productName}   {row.priceText}`,
                buttonHeight(),
                function()
                    deps.actions.buy(row.productName)
                end
            )
            button.LayoutOrder = index
            Widgets.setEnabled(button, theme, row.canBuy)
            shopButtons[row.productName] = button
        end
    end

    -- Rewards: daily, session gifts and the optional community card.
    Widgets.button(
        rewardsList,
        theme,
        "Daily",
        strings.claimDaily,
        buttonHeight(),
        deps.actions.claimDaily
    )
    for _, giftId in deps.content.giftIds do
        Widgets.button(
            rewardsList,
            theme,
            `Gift{giftId}`,
            `{strings.giftReady}: {giftId}`,
            buttonHeight(),
            function()
                deps.actions.claimGift(giftId)
            end
        )
    end
    if deps.content.showCommunityCard then
        Widgets.button(
            rewardsList,
            theme,
            "Join",
            strings.joinCommunity,
            buttonHeight(),
            deps.actions.joinCommunity
        )
        Widgets.button(
            rewardsList,
            theme,
            "Check",
            strings.checkAgain,
            buttonHeight(),
            deps.actions.checkCommunity
        )
    end

    -- Settings: a stepper per volume group, sent once the player stops pressing.
    local function sendVolume(group: "music" | "sfx")
        sendToken += 1
        local token = sendToken
        task.delay(deps.config.settings.sendDebounceSeconds, function()
            if token == sendToken then
                deps.actions.setVolume(group, volumes[group])
            end
        end)
    end
    local function refreshVolumeLabels()
        volumeLabels.music.Text = `{strings.volumeMusic}: {volumes.music}%`
        volumeLabels.sfx.Text = `{strings.volumeSfx}: {volumes.sfx}%`
    end
    local function stepper(group: "music" | "sfx", caption: string)
        volumeLabels[group] = Widgets.label(
            settingsList,
            theme,
            `{group}Label`,
            caption,
            "body",
            theme.palette.textPrimary
        )
        local step = deps.config.settings.volumeStep
        Widgets.button(settingsList, theme, `{group}Down`, "-", buttonHeight(), function()
            volumes[group] = math.max(0, volumes[group] - step)
            refreshVolumeLabels()
            sendVolume(group)
        end)
        Widgets.button(settingsList, theme, `{group}Up`, "+", buttonHeight(), function()
            volumes[group] = math.min(100, volumes[group] + step)
            refreshVolumeLabels()
            sendVolume(group)
        end)
    end
    stepper("music", strings.volumeMusic)
    stepper("sfx", strings.volumeSfx)

    -- Leaderboards: a heading and ranked rows per board.
    local boardsList = listOf("boards")
    local boardFrames: { [string]: Frame? } = {}
    for index, boardId in deps.content.boardIds do
        local frame = Instance.new("Frame")
        frame.Name = boardId
        frame.BackgroundTransparency = 1
        frame.Size = UDim2.fromScale(1, 0)
        frame.AutomaticSize = Enum.AutomaticSize.Y
        frame.LayoutOrder = index
        frame.Parent = boardsList
        Widgets.stack(frame, theme.spacing.sm)
        Widgets.label(frame, theme, "Heading", boardId, "body", theme.palette.accent)
        Widgets.label(frame, theme, "Empty", strings.boardEmpty, "caption", theme.palette.textMuted)
        boardFrames[boardId] = frame
    end
    local podium = { theme.palette.accent, theme.palette.textPrimary, theme.palette.warning }

    local kit: UiKit
    kit = {
        presenter = presenter,
        menus = menus,
        gui = gui,
        setShopRows = function(_self: UiKit, rows: { ShopModel.Row })
            setShopRows(rows)
        end,
        setVolumes = function(_self: UiKit, music: number, sfx: number)
            volumes.music = music
            volumes.sfx = sfx
            refreshVolumeLabels()
        end,
        setBoard = function(_self: UiKit, boardId: string, text: string)
            local frame = boardFrames[boardId]
            if frame == nil then
                return
            end
            for _, child in frame:GetChildren() do
                if child:IsA("TextLabel") and child.Name ~= "Heading" then
                    child:Destroy()
                end
            end
            local entries = BoardKey.decodePublished(text)
            if #entries == 0 then
                Widgets.label(
                    frame,
                    theme,
                    "Empty",
                    strings.boardEmpty,
                    "caption",
                    theme.palette.textMuted
                )
                return
            end
            for rank, entry in entries do
                local row = Widgets.label(
                    frame,
                    theme,
                    `Rank{rank}`,
                    `{rank}. {deps.nameOf(entry.userId) or tostring(entry.userId)}   {entry.value}`,
                    "body",
                    podium[rank] or theme.palette.textMuted
                )
                row.LayoutOrder = rank
            end
        end,
    }
    setShopRows({})
    refreshVolumeLabels()

    -- Input: keyboard and gamepad toggles, and "back" on Backspace / gamepad B.
    local function find(enumItems: { Enum.KeyCode }, name: string): Enum.KeyCode?
        for _, item in enumItems do
            if item.Name == name then
                return item
            end
        end
        warn(`ui: unknown input name "{name}"`)
        return nil
    end
    for _, menu in deps.config.menus do
        if menu.modal then
            local inputs: { Enum.KeyCode } = {}
            local key = if menu.toggleKey ~= nil
                then find(Enum.KeyCode:GetEnumItems(), menu.toggleKey)
                else nil
            local pad = if menu.togglePad ~= nil
                then find(Enum.KeyCode:GetEnumItems(), menu.togglePad)
                else nil
            if key ~= nil then
                table.insert(inputs, key)
            end
            if pad ~= nil then
                table.insert(inputs, pad)
            end
            if #inputs > 0 then
                ContextActionService:BindAction(`toggle_{menu.id}`, function(_name, state)
                    if state == Enum.UserInputState.Begin then
                        menus:toggle(menu.id)
                    end
                    return Enum.ContextActionResult.Sink
                end, false, table.unpack(inputs))
            end
        end
    end
    local backInputs: { Enum.KeyCode } = {}
    for _, name in { deps.config.input.backKey, deps.config.input.backPad } do
        local item = find(Enum.KeyCode:GetEnumItems(), name)
        if item ~= nil then
            table.insert(backInputs, item)
        end
    end
    if #backInputs > 0 then
        ContextActionService:BindAction("ui_back", function(_name, state)
            if state == Enum.UserInputState.Begin and menus:back() then
                return Enum.ContextActionResult.Sink
            end
            return Enum.ContextActionResult.Pass
        end, false, table.unpack(backInputs))
    end

    gui.Parent = deps.playerGui
    return kit
end

return UiKitModule
