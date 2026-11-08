--!strict
--[[
    Server adapter: one system line in everyone's chat through TextChatService. A failure is
    reported with `warn` and never reaches the caller, so an announcement cannot block gameplay.
    Pair it with `features/progress/MilestoneTracker` (when) and `ProgressRules.format` (what).
]]

local TextChatService = game:GetService("TextChatService")

local Announcer = {}

function Announcer.say(text: string)
    local channels = TextChatService:FindFirstChild("TextChannels")
    local system = if channels ~= nil then channels:FindFirstChild("RBXSystem") else nil
    if system == nil or not system:IsA("TextChannel") then
        return
    end
    local sent, failure = pcall(function()
        system:DisplaySystemMessage(text)
    end)
    if not sent then
        warn(`Announcement failed: {failure}`)
    end
end

return Announcer
