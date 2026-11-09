--!strict
--[[
    Port: opens the panel of one item (details, upgrade, inspect). The game implements it over its
    own menu; ItemSlots only says WHICH item was tapped and never knows what the panel is.
]]

export type ItemPanel = {
    -- Opens the panel of `itemId`. Must be safe to call while another panel is open.
    open: (self: ItemPanel, itemId: string) -> (),
}

return {}
