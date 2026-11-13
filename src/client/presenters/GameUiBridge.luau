--!strict
--[[
    The hook point of the game UI system. The template draws nothing (ADR 0071): a game UI reads
    state from a `Listener` and sends intent through `Actions`, and never touches a remote, a
    service or Config directly. Everything here is state, events and remotes; no Instance of UI is
    created.

    How a UI system attaches (see Main.client.luau, "UI HOOK POINT"):
      1. Build your UI. Keep it in the place (Studio) or in your own presenter folder.
      2. Pass `GameUiBridge.attach` a `mount` function: it receives the `Actions` and the `Content`,
         builds your UI and returns a `Listener` with the callbacks it renders from.
      3. Call the `Actions` when the player presses something. Every action carries intent only;
         the server validates and answers with the events the listener already receives.
]]

local GroupService = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local LeaderboardsConfig =
    require(ReplicatedStorage.Shared.features.leaderboards.LeaderboardsConfig)
local NetTypes = require(ReplicatedStorage.Shared.net.generated.types)
local ShopModel = require(ReplicatedStorage.Shared.features.ui.ShopModel)
local net = require(ReplicatedStorage.Shared.net.generated.client)

export type Actions = {
    buy: (productName: string) -> (),
    claimDaily: () -> (),
    claimGift: (giftId: string) -> (),
    joinCommunity: () -> (),
    checkCommunity: () -> (),
    setVolume: (group: "music" | "sfx", percent: number) -> (),
}

-- State the UI renders. Every field is optional: implement what the game shows.
export type Listener = {
    onCoins: ((coins: number) -> ())?,
    onShopRows: ((rows: { ShopModel.Row }) -> ())?,
    -- The encoded text of a leaderboard (a replicated StringValue), by board id.
    onBoard: ((boardId: string, encoded: string) -> ())?,
    onVolumes: ((music: number, sfx: number) -> ())?,
}

export type Content = {
    products: { ShopModel.Product },
    giftIds: { string },
    boardIds: { string },
    showCommunityCard: boolean,
}

export type Options = {
    -- Game copy of a shop row while its price loads or when it cannot be read.
    shopPlaceholders: ShopModel.Placeholders,
}

local GameUiBridge = {}

--- What the game UI can show, read from Config: products, session gifts, boards and whether the
--- community card applies.
function GameUiBridge.content(): Content
    local community = Config.default.communityReward
    local boards = Config.default.leaderboards
    local giftIds: { string } = {}
    for _, gift in Config.default.timeRewards.sessionGifts do
        table.insert(giftIds, gift.id)
    end
    local products: { ShopModel.Product } = {}
    for _, product in Config.default.developerProducts do
        table.insert(products, { name = product.name, id = product.id })
    end
    return {
        products = products,
        giftIds = giftIds,
        boardIds = if boards ~= nil then LeaderboardsConfig.sortedIds(boards) else {},
        showCommunityCard = community ~= nil
            and community.enabled
            and community.promptJoin
            and community.communityId ~= nil,
    }
end

--- The intents a UI can send. Each one wraps a budgeted remote or a Roblox prompt.
function GameUiBridge.actions(): Actions
    return {
        buy = function(productName: string)
            net.RequestPurchase.fire(productName :: NetTypes.ProductName)
        end,
        claimDaily = function()
            net.ClaimDailyReward.fire()
        end,
        claimGift = function(giftId: string)
            net.ClaimSessionGift.fire(giftId)
        end,
        joinCommunity = function()
            local community = Config.default.communityReward
            local communityId = if community ~= nil then community.communityId else nil
            if communityId == nil then
                return
            end
            local prompted, failure = pcall(function()
                GroupService:PromptJoinAsync(communityId)
            end)
            if not prompted then
                warn(`Join prompt failed: {failure}`)
            end
        end,
        checkCommunity = function()
            net.RequestCommunityCheck.fire()
        end,
        setVolume = function(group: "music" | "sfx", percent: number)
            net.SetVolume.fire(group, percent)
        end,
    }
end

--- Resolves a user id to a name for a leaderboard row, cached. Nil when Roblox cannot answer.
function GameUiBridge.nameResolver(): (userId: number) -> string?
    local cache: { [number]: string } = {}
    return function(userId: number): string?
        local cached = cache[userId]
        if cached ~= nil then
            return cached
        end
        local found, name = pcall(function()
            return Players:GetNameFromUserIdAsync(userId)
        end)
        if not found then
            warn(`Could not resolve the name of {userId}: {name}`)
            return nil
        end
        cache[userId] = name
        return name
    end
end

local function bindShop(
    content: Content,
    options: Options,
    onShopRows: (rows: { ShopModel.Row }) -> ()
)
    -- Prices are read at runtime for this player (Plus and regional prices differ).
    local states: { [string]: ShopModel.QuoteState } = {}
    local function refresh()
        onShopRows(ShopModel.rows(content.products, states, options.shopPlaceholders))
    end
    refresh()
    for _, product in content.products do
        local productId = product.id
        if productId ~= nil then
            task.spawn(function()
                local read, info = pcall(function()
                    return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)
                end)
                local robux: number? = if read then info.PriceInRobux else nil
                if robux == nil then
                    states[product.name] = { status = "failed" }
                    warn(`Price of "{product.name}" could not be read`)
                else
                    states[product.name] = {
                        status = "ready",
                        quote = ShopModel.quoteFromPrices(robux, nil),
                    }
                end
                refresh()
            end)
        end
    end
end

local function bindBoards(onBoard: (boardId: string, encoded: string) -> ())
    -- Leaderboards arrive as replicated values (server to client only); no remote is involved.
    local boardsFolder = ReplicatedStorage:WaitForChild("Boards", 10)
    if boardsFolder == nil then
        warn("Boards folder did not replicate; leaderboards stay empty")
        return
    end
    local function bind(value: Instance)
        if value:IsA("StringValue") then
            onBoard(value.Name, value.Value)
            value:GetPropertyChangedSignal("Value"):Connect(function()
                onBoard(value.Name, value.Value)
            end)
        end
    end
    for _, existing in boardsFolder:GetChildren() do
        bind(existing)
    end
    boardsFolder.ChildAdded:Connect(bind)
end

export type Mount = (actions: Actions, content: Content) -> Listener

--- Attaches a game UI: `mount` builds it from the actions and the content and returns the
--- listener it renders from; the bridge then feeds that listener the shop rows and the boards.
--- Coins and volumes arrive through remotes that Main.client owns (a remote takes one callback),
--- so Main.client forwards them to the returned listener.
function GameUiBridge.attach(mount: Mount, options: Options): Listener
    local content = GameUiBridge.content()
    local listener = mount(GameUiBridge.actions(), content)
    local onShopRows = listener.onShopRows
    if onShopRows ~= nil then
        bindShop(content, options, onShopRows)
    end
    local onBoard = listener.onBoard
    if onBoard ~= nil then
        bindBoards(onBoard)
    end
    return listener
end

return GameUiBridge
