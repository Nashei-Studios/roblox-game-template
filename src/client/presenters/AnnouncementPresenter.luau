--!strict
--[[
    Client presenter: turns an AnnounceMilestone event into one system line in the chat. The text
    lives on the client (Main wires ProgressRules.format); the server only sends the name and the value. The chat
    call is injected so this file loads under Lune and is tested with fakes.
]]

export type Deps = {
    -- Builds the line from a name and a value (ProgressRules.format).
    line: (name: string, value: number) -> string,
    -- Shows one line in the local chat (TextChannel:DisplaySystemMessage on RBXSystem).
    display: (text: string) -> (),
}

export type Presenter = {
    receive: (self: Presenter, name: string, value: number) -> (),
}

local AnnouncementPresenter = {}

function AnnouncementPresenter.new(deps: Deps): Presenter
    local presenter: Presenter = {
        receive = function(_self: Presenter, name: string, value: number)
            deps.display(deps.line(name, value))
        end,
    }
    return presenter
end

return AnnouncementPresenter
