--!strict
-- UI Labs story: Components at 667x375. See StoryHarness and docs/ui-system.md.
local Harness = require(script.Parent.StoryHarness)
local Scenes = require(script.Parent.Scenes)

return Harness.story(2, Scenes.components)
