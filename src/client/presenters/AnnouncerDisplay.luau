--!strict
--[[
    Client presenter: shows an announcer line in the system channel of TextChatService.
    DisplaySystemMessage is client-only; the server sends the text through the AnnouncerLine
    remote. Touches the engine, so it is excluded from the line-coverage gate.
]]

local TextChatService = game:GetService("TextChatService")

local AnnouncerDisplay = {}

function AnnouncerDisplay.show(text: string)
    local channels = TextChatService:FindFirstChild("TextChannels")
    local system = if channels ~= nil then channels:FindFirstChild("RBXSystem") else nil
    if system == nil or not system:IsA("TextChannel") then
        return
    end
    local shown, failure = pcall(function()
        system:DisplaySystemMessage(text)
    end)
    if not shown then
        warn(`Announcement display failed: {failure}`)
    end
end

return AnnouncerDisplay
