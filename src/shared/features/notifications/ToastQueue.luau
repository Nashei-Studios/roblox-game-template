--!strict
--[[
    Pure toast queue (issue #29): bounded, de-duplicated, with stale entries dropped. The clock
    is passed in, so it loads under Lune and tests control time.
]]

export type Pending = {
    kind: string,
    text: string,
    style: string,
    durationSeconds: number,
    sound: string?,
    enqueuedAt: number,
}

export type Options = {
    maxQueue: number,
    dedupeSeconds: number,
    maxWaitSeconds: number,
}

export type PushOutcome = "queued" | "deduped" | "dropped_oldest"

export type ToastQueue = {
    push: (self: ToastQueue, toast: Pending) -> PushOutcome,
    -- The oldest toast that has not gone stale at `now`, or nil.
    pop: (self: ToastQueue, now: number) -> Pending?,
    size: (self: ToastQueue) -> number,
}

local ToastQueueModule = {}

function ToastQueueModule.new(options: Options): ToastQueue
    local items: { Pending } = {}
    -- "kind|text" -> time of the last push, for de-duplication.
    local lastSeen: { [string]: number } = {}

    local queue: ToastQueue = {
        push = function(_self: ToastQueue, toast: Pending): PushOutcome
            local key = `{toast.kind}|{toast.text}`
            local previous = lastSeen[key]
            if previous ~= nil and toast.enqueuedAt - previous < options.dedupeSeconds then
                return "deduped"
            end
            lastSeen[key] = toast.enqueuedAt
            table.insert(items, toast)
            if #items > options.maxQueue then
                table.remove(items, 1)
                return "dropped_oldest"
            end
            return "queued"
        end,
        pop = function(_self: ToastQueue, now: number): Pending?
            while #items > | do
                local first = table.remove(items, 1) :: Pending
                if now - first.enqueuedAt <= options.maxWaitSeconds then
                    return first
                end
            end
            return nil
        end,
        size = function(_self: ToastQueue): number
            return #items
        end,
    }
    return queue
end

return ToastQueueModule
