--!strict
--[[
    The "Friend +N %" HUD segment (ADR 0030/0031), pure so it is testable without a screen.
    `nil` means "nothing to show": the HUD omits the segment when the server reports no boost.
]]

local FriendBoostLabel = {}

-- `pct` is `friendBoostPct` of the last state snapshot the server sent.
function FriendBoostLabel.text(pct: number): string?
    local rounded = math.floor(pct + 0.5)
    if rounded <= 0 then
        return nil
    end
    return `Friend +{rounded}%`
end

return FriendBoostLabel
