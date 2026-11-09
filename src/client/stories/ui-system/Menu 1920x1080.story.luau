--!strict
-- UI Labs story: Menu at 1920x1080. See StoryHarness and docs/ui-system.md.
local Harness = require(script.Parent.StoryHarness)
local Scenes = require(script.Parent.Scenes)

return Harness.story(4, Scenes.menu)
