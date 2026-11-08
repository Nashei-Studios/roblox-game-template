--!strict
--[[
    Decides when a player's counter crosses an announcement milestone. The first sight of a player
    only sets the baseline, so joining with a high value never announces (no spam on join). Pure:
    the server adapter (`server/adapters/Announcer`) delivers the text.
]]

local ProgressRules = require("./ProgressRules")

export type MilestoneTracker = {
    -- The milestone newly reached, or nil (first sight, same band, or below the first step).
    observe: (self: MilestoneTracker, userId: number, value: number) -> number?,
    forget: (self: MilestoneTracker, userId: number) -> (),
}

local MilestoneTrackerModule = {}

function MilestoneTrackerModule.new(step: number): MilestoneTracker
    local announced: { [number]: number } = {}
    local tracker: MilestoneTracker = {
        observe = function(_self: MilestoneTracker, userId: number, value: number): number?
            local previous = announced[userId]
            if previous == nil then
                announced[userId] = value
                return nil
            end
            local reached = ProgressRules.milestoneCrossed(previous, value, step)
            if reached ~= nil then
                announced[userId] = reached
            end
            return reached
        end,
        forget = function(_self: MilestoneTracker, userId: number)
            announced[userId] = nil
        end,
    }
    return tracker
end

return MilestoneTrackerModule
