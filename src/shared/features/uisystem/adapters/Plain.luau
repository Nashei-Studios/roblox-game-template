--!strict
--[[
    The "plain" adapter: no kit. Every slot is covered by a piece drawn from the Tokens (panels,
    labels and buttons the engine builders create). Used by stories, by a new game before its kit
    is chosen, and as the fallback for a slot a kit does not cover.
]]

local KitAdapter = require("../KitAdapter")

local adapter: KitAdapter.KitAdapter = {
    id = "plain",
    kitSlug = nil,
    license = "own code (MIT, this repository)",
    slots = {},
}

return adapter
