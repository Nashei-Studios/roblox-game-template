--!strict
--[[
    Client adapter: draws the minimal HUD by code (status line, coins, bucket, Cast/Reel, Sell and
    next-rod buttons). It holds no rules: it draws what `HudModel.view()` returns and reports button
    clicks through callbacks. It touches the engine, so the coverage gate excludes it (ADR 0017);
    the look is checked in Studio. Colors and sizes are placeholders for the first playtest, not a
    design system.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudModel = require(ReplicatedStorage.Shared.features.reef.HudModel)

export type Callbacks = {
    onCast: () -> (),
    onReel: () -> (),
    onSell: () -> (),
    onBuyRod: () -> (),
}

export type ReefHud = {
    render: (self: ReefHud, view: HudModel.View) -> (),
}

local ReefHudModule = {}

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
    label.Parent = parent
    return label
end

local function newButton(
    parent: Instance,
    name: string,
    text: string,
    position: UDim2,
    onClick: () -> ()
): TextButton
    local button = Instance.new("TextButton")
    button.Name = name
    button.Text = text
    button.Position = position
    button.Size = UDim2.fromScale(0.2, 0.07)
    button.BackgroundColor3 = Color3.fromRGB(30, 110, 180)
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

function ReefHudModule.new(callbacks: Callbacks): ReefHud
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "ReefHud"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui

    local status = newLabel(gui, "Status", UDim2.fromScale(0.3, 0.72), UDim2.fromScale(0.4, 0.08))
    local coins = newLabel(gui, "Coins", UDim2.fromScale(0.02, 0.02), UDim2.fromScale(0.2, 0.06))
    local stock = newLabel(gui, "Stock", UDim2.fromScale(0.4, 0.02), UDim2.fromScale(0.2, 0.05))
    local cast = newButton(gui, "Cast", "Cast", UDim2.fromScale(0.4, 0.84), callbacks.onCast)
    local reel = newButton(gui, "Reel", "Reel", UDim2.fromScale(0.4, 0.84), callbacks.onReel)
    local sell = newButton(gui, "Sell", "Sell fish", UDim2.fromScale(0.78, 0.74), callbacks.onSell)
    local upgrade =
        newButton(gui, "BuyRod", "Next rod", UDim2.fromScale(0.78, 0.84), callbacks.onBuyRod)

    local hud: ReefHud = {
        render = function(_self: ReefHud, view: HudModel.View)
            status.Text = view.statusText
            coins.Text = view.coinsText
            stock.Text = view.stockText
            cast.Visible = view.showCast
            reel.Visible = view.showReel
            -- The reel button lights up when the server says the fish bites.
            reel.BackgroundColor3 = if view.phase == "bite"
                then Color3.fromRGB(230, 150, 30)
                else Color3.fromRGB(30, 110, 180)
            setEnabled(sell, view.sellEnabled)
            upgrade.Text = view.upgradeText
            setEnabled(upgrade, view.upgradeEnabled)
        end,
    }
    return hud
end

return ReefHudModule
