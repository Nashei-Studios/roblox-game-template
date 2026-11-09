--!strict
--[[
    Harness of the UI Labs stories (plugin "UI Labs", docs: a story is a ModuleScript named
    *.story that returns function(target: Frame) -> cleanup). It mounts a fixed-size frame of one
    of the four review viewports inside the story target, builds the real UiEnv and SafeAreaRoot
    layers in it, and hands the scene builder the same content/overlay frames a game gets.

    The skin is Studded when a kit tree named UiKit (the game's ReplicatedStorage.UiKit) exists,
    else Plain, so the same story shows a game's real kit or the template fallback.
    Stories ship with the client scripts but nothing requires them at runtime.
    Engine code; verified by eye in UI Labs, see docs/ui-system.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Breakpoints = require(Shared.features.uisystem.Breakpoints)
local Plain = require(Shared.features.uisystem.adapters.Plain)
local Studded = require(Shared.features.uisystem.adapters.Studded)
local Tokens = require(Shared.features.uisystem.Tokens)
local System = script.Parent.Parent.Parent.presenters.ui.system
local SafeAreaRoot = require(System.SafeAreaRoot)
local Skin = require(System.Skin)
local UiEnv = require(System.UiEnv)

export type Scene = (env: UiEnv.UiEnv, root: SafeAreaRoot.Root) -> ()

local StoryHarness = {}

--- The review viewports by index (1..4), for the story file names.
StoryHarness.VIEWPORTS = Breakpoints.REVIEW_VIEWPORTS

--- Returns the story function for a scene at review viewport `index`.
function StoryHarness.story(index: number, scene: Scene): (target: Frame) -> () -> ()
    local viewport = Breakpoints.REVIEW_VIEWPORTS[index]
    assert(viewport ~= nil, `no review viewport {index}`)
    return function(target: Frame): () -> ()
        local frame = Instance.new("Frame")
        frame.Name = `Viewport_{viewport.width}x{viewport.height}`
        frame.Size = UDim2.fromOffset(viewport.width, viewport.height)
        frame.BackgroundColor3 = Color3.fromHex("#0B0D12")
        frame.BorderSizePixel = 0
        frame.ClipsDescendants = true
        frame.Parent = target

        local tokens = Tokens.default()
        local kitRoot = ReplicatedStorage:FindFirstChild("UiKit")
        local skin = if kitRoot ~= nil
            then Skin.new(Studded, kitRoot, tokens)
            else Skin.new(Plain, nil, tokens)
        local env = UiEnv.new(tokens, skin, viewport, false)
        local root = SafeAreaRoot.layers(frame, env)
        scene(env, root)
        return function()
            frame:Destroy()
        end
    end
end

return StoryHarness
