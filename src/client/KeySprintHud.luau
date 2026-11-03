--!strict
--[[
    Client adapter: draws the minimal HUD by code (meter, multiplier, coins, stage, key prompt,
    upgrade button, skip button). It holds no rules: it draws what `HudModel.view()` returns and
    reports button clicks through callbacks. It touches the engine, so the coverage gate excludes
    it (ADR 0017); the look is checked in Studio. Colors and sizes are placeholders for the first
    playtest, not a design system.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudModel = require(ReplicatedStorage.Shared.features.keysprint.HudModel)

export type Callbacks = {
    onUpgrade: () -> (),
    onSkip: () -> (),
}

export type KeySprintHud = {
    render: (self: KeySprintHud, view: HudModel.View) -> (),
}

local KeySprintHudModule = {}

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

function KeySprintHudModule.new(callbacks: Callbacks): KeySprintHud
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    local gui = Instance.new("ScreenGui")
    gui.Name = "KeySprintHud"
    gui.ResetOnSpawn = false
    gui.Parent = playerGui

    local prompt =
        newLabel(gui, "KeyPrompt", UDim2.fromScale(0.3, 0.72), UDim2.fromScale(0.4, 0.08))
    local meterBack = Instance.new("Frame")
    meterBack.Name = "MeterBack"
    meterBack.Position = UDim2.fromScale(0.3, 0.84)
    meterBack.Size = UDim2.fromScale(0.4, 0.04)
    meterBack.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    meterBack.Parent = gui
    local meterFill = Instance.new("Frame")
    meterFill.Name = "MeterFill"
    meterFill.Size = UDim2.fromScale(0, 1)
    meterFill.BackgroundColor3 = Color3.fromRGB(255, 190, 40)
    meterFill.Parent = meterBack
    local multiplier =
        newLabel(gui, "Multiplier", UDim2.fromScale(0.3, 0.89), UDim2.fromScale(0.4, 0.06))
    local coins = newLabel(gui, "Coins", UDim2.fromScale(0.02, 0.02), UDim2.fromScale(0.2, 0.06))
    local stage = newLabel(gui, "Stage", UDim2.fromScale(0.4, 0.02), UDim2.fromScale(0.2, 0.05))
    local upgrade = newButton(
        gui,
        "UpgradeCap",
        UDim2.fromScale(0.78, 0.84),
        UDim2.fromScale(0.2, 0.07),
        callbacks.onUpgrade
    )
    local skip = newButton(
        gui,
        "SkipStage",
        UDim2.fromScale(0.78, 0.74),
        UDim2.fromScale(0.2, 0.07),
        callbacks.onSkip
    )
    skip.Text = "Skip stage"

    local hud: KeySprintHud = {
        render = function(_self: KeySprintHud, view: HudModel.View)
            prompt.Text = view.promptText
            prompt.Visible = view.showKeyPrompt
            meterFill.Size = UDim2.fromScale(view.meterFill, 1)
            multiplier.Text = view.multiplierText
            coins.Text = view.coinsText
            stage.Text = view.stageText
            upgrade.Text = view.upgradeText
            upgrade.Active = view.upgradeEnabled
            upgrade.AutoButtonColor = view.upgradeEnabled
            upgrade.BackgroundTransparency = if view.upgradeEnabled then 0 else 0.6
            skip.Visible = view.showSkip
        end,
    }
    return hud
end

return KeySprintHudModule
