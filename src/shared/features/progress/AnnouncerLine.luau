--!strict
--[[
    Pure guard for one announcer line. The server sends the text to every client
    (TextChannel:DisplaySystemMessage runs on the client only); this keeps what it sends
    inside the wire limit of the AnnouncerLine remote (1 to 100 UTF-8 characters).
]]

local AnnouncerLine = {}

AnnouncerLine.MAX_CHARACTERS = 100

--- The text to send, trimmed and capped; nil when there is nothing to say.
function AnnouncerLine.prepare(text: string): string?
    local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
    if trimmed == "" then
        return nil
    end
    local length = utf8.len(trimmed)
    if length == nil then
        return nil -- invalid UTF-8 would be rejected by the wire check
    end
    if length <= AnnouncerLine.MAX_CHARACTERS then
        return trimmed
    end
    local cut = utf8.offset(trimmed, AnnouncerLine.MAX_CHARACTERS + 1)
    return string.sub(trimmed, 1, (cut or #trimmed + 1) - 1)
end

return AnnouncerLine
