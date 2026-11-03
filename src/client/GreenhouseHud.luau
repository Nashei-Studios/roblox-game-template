--!strict
--[[
    Client adapter: draws the minimal greenhouse HUD by code (coins, plot list, crop selector, and
    the sell / buy seed / buy plot / auto harvest / ExtraPlots buttons). It holds no rules: it draws
    what `HudModel.view()` returns and reports clicks through callbacks. It touches the engine, so
    the coverage gate excludes it (ADR 0017); the look is checked in Studio. Colors and sizes are
    placeholders for the first playtest, not a design system.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudModel = require(ReplicatedStorage.Shared.features.greenhouse.HudModel)

export type Callbacks = {
    onSelectCrop: (cropId: string) -> (),
    onSell: () -> (),
    onBuySeed: () -> (),
    onBuyPlot: () -> (),
    onAutoHarvest: () -> (),
    onExtraPlotsPass: () -> (),
}

export type GreenhouseHud = {
    render: (self: GreenhouseHud, view: HudModel.View) -> (),
}

local GreenhouseHudModule = {}

local function newLabel(parent: Instance, name: string, position: UDim2, size: UDim2): TextLabel
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Position = position
    label.Size = size
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.5
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

local function newButton(
    parent: Instance,
    name: string,
    position: UDim2,
    size: UDim2,
    onClick: () -> ()
): TextButton
    local button = Instance.new("TextButton")
    button.Name = name
    button.Position = position
    button.Size = size
    button.BackgroundColor3 = Color3.fromRGB(40, 120, 220)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.GothamBold
    button.TextScaled = true
    button.Parent = parent
    button.Activated:Connect(onClick)
    return button
end

local function setEnabled(button: TextButton, enabled: boolean)
    button.Active = enabled
    button.AutoButtonColor = enabled
    button.BackgroundTransparency = if enabled then 0 else 0.6
end

function GreenhouseHudModule.new(callbacks: Callbacks, cropIds: { string }): GreenhouseHud
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "GreenhouseHud"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui

    local coins = newLabel(gui, "Coins", UDim2.fromScale(0.02, 0.02), UDim2.fromScale(0.2, 0.06))

    local plotList = Instance.new("Frame")
    plotList.Name = "PlotList"
    plotList.Position = UDim2.fromScale(0.02, 0.1)
    plotList.Size = UDim2.fromScale(0.25, 0.4)
    plotList.BackgroundTransparency = 1
    plotList.Parent = gui
    local layout = Instance.new("UIListLayout")
    layout.Parent = plotList
    local plotLabels: { [number]: TextLabel } = {}

    local cropButtons: { [string]: TextButton } = {}
    for index, cropId in cropIds do
        cropButtons[cropId] = newButton(
            gui,
            `Crop_{cropId}`,
            UDim2.fromScale(0.3 + (index - 1) * 0.14, 0.88),
            UDim2.fromScale(0.13, 0.08),
            function()
                callbacks.onSelectCrop(cropId)
            end
        )
    end

    local sell = newButton(
        gui,
        "Sell",
        UDim2.fromScale(0.78, 0.5),
        UDim2.fromScale(0.2, 0.07),
        callbacks.onSell
    )
    local buySeed = newButton(
        gui,
        "BuySeed",
        UDim2.fromScale(0.78, 0.58),
        UDim2.fromScale(0.2, 0.07),
        callbacks.onBuySeed
    )
    local buyPlot = newButton(
        gui,
        "BuyPlot",
        UDim2.fromScale(0.78, 0.66),
        UDim2.fromScale(0.2, 0.07),
        callbacks.onBuyPlot
    )
    local autoHarvest = newButton(
        gui,
        "AutoHarvest",
        UDim2.fromScale(0.78, 0.74),
        UDim2.fromScale(0.2, 0.07),
        callbacks.onAutoHarvest
    )
    local extraPlots = newButton(
        gui,
        "ExtraPlotsPass",
        UDim2.fromScale(0.78, 0.82),
        UDim2.fromScale(0.2, 0.07),
        callbacks.onExtraPlotsPass
    )
    extraPlots.Text = "Get ExtraPlots pass"

    local hud: GreenhouseHud = {
        render = function(_self: GreenhouseHud, view: HudModel.View)
            coins.Text = view.coinsText
            for _, plotView in view.plots do
                local existing: TextLabel? = plotLabels[plotView.plot]
                local label: TextLabel
                if existing ~= nil then
                    label = existing
                else
                    label = newLabel(
                        plotList,
                        `Plot{plotView.plot}`,
                        UDim2.new(),
                        UDim2.fromScale(1, 0.12)
                    )
                    label.LayoutOrder = plotView.plot
                    plotLabels[plotView.plot] = label
                end
                label.Text = plotView.text
                label.TextColor3 = if plotView.ready
                    then Color3.fromRGB(120, 255, 120)
                    else Color3.new(1, 1, 1)
            end
            for _, cropView in view.crops do
                local button: TextButton? = cropButtons[cropView.cropId]
                if button ~= nil then
                    button.Text = cropView.text
                    button.BackgroundColor3 = if cropView.selected
                        then Color3.fromRGB(60, 170, 90)
                        else Color3.fromRGB(40, 120, 220)
                end
            end
            sell.Text = view.sellText
            setEnabled(sell, view.sellEnabled)
            buySeed.Text = view.buySeedText
            setEnabled(buySeed, view.buySeedEnabled)
            buyPlot.Text = view.buyPlotText
            setEnabled(buyPlot, view.buyPlotEnabled)
            autoHarvest.Text = view.autoHarvestText
            extraPlots.Visible = view.showExtraPlotsOffer
        end,
    }
    return hud
end

return GreenhouseHudModule
