--!strict
--[[
    Port: gives the InspectView viewer the 3D model of one item. The game implements it over the
    builder it already uses for the item in hand (same parts, same colors), so the viewer shows
    exactly what the player holds. The mold never builds a model and never loads an external mesh.
]]

export type ModelSource = {
    -- A NEW Model for `itemId`, unparented, or nil for an unknown item. The viewer owns it and
    -- destroys it; it may be cloned from a cached template (lazy and pooled on the game side).
    build: (self: ModelSource, itemId: string) -> Model?,
    -- Parts the model for `itemId` has, without building it (for the budget check); nil if unknown.
    partCount: (self: ModelSource, itemId: string) -> number?,
}

return {}
