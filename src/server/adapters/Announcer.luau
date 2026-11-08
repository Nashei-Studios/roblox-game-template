--!strict
--[[
    Server adapter: one system line in everyone's chat. TextChannel:DisplaySystemMessage only
    works on the client ("can only be called on the client"), so the server fires the
    AnnouncerLine remote to every client and `client/presenters/AnnouncerDisplay` shows it.
    A failure is reported with `warn` and never reaches the caller, so an announcement cannot
    block gameplay. Pair it with `features/progress/MilestoneTracker` (when) and
    `ProgressRules.format` (what).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnnouncerLine = require(ReplicatedStorage.Shared.features.progress.AnnouncerLine)

export type FireAll = (text: string) -> ()

local Announcer = {}

--- Builds `say` over the generated remote: `Announcer.bind(function(t) net.AnnouncerLine.fireAll(t) end)`.
function Announcer.bind(fireAll: FireAll): (text: string) -> ()
    return function(text: string)
        local line = AnnouncerLine.prepare(text)
        if line == nil then
            return
        end
        local sent, failure = pcall(function()
            fireAll(line)
        end)
        if not sent then
            warn(`Announcement failed: {failure}`)
        end
    end
end

return Announcer
