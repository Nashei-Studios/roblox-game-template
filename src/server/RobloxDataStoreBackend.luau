--!strict
--[[
    Adapter: Session.Backend<T> over Roblox DataStoreService:UpdateAsync.
    Not unit-testable under Lune (needs the engine); exercise it through the
    Luau Execution API or a dev place. All pure decisions live in Session.luau.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Session = require(ReplicatedStorage.Shared.Session)

local RobloxDataStoreBackend = {}

function RobloxDataStoreBackend.new<T>(storeName: string): Session.Backend<T>
    local store = DataStoreService:GetDataStore(storeName)
    local backend: Session.Backend<T> = {
        update = function(
            key: string,
            transform: (current: Session.SessionRecord<T>?) -> Session.SessionRecord<T>?
        ): Session.Result<Session.SessionRecord<T>?, Session.SessionError>
            local ok, stored = pcall(function(): Session.SessionRecord<T>?
                local value: Session.SessionRecord<T>? = store:UpdateAsync(
                    key,
                    function(old: Session.SessionRecord<T>?): Session.SessionRecord<T>?
                        return transform(old)
                    end
                )
                return value
            end)
            if not ok then
                warn(`DataStore update failed for key {key}: {stored}`)
                return { ok = false, error = "backend_failure" }
            end
            return { ok = true, value = stored }
        end,
    }
    return backend
end

return RobloxDataStoreBackend
