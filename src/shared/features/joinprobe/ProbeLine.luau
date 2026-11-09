--!strict
--[[
    Formats one `[JOINPROBE] {json}` log line from a flat field map. Pure: loads under Lune.
    A tiny deterministic encoder (sorted keys, numbers at millisecond precision) so the same
    fields always give the same text; HttpService is not available outside the engine.
]]

export type Value = number | string | boolean
export type Fields = { [string]: Value }

local ProbeLine = {}

ProbeLine.PREFIX = "[JOINPROBE]"

local ESCAPES: { [string]: string } = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}

local function escape(text: string): string
    local replaced = string.gsub(text, '[%c"\\]', function(char: string): string
        return ESCAPES[char] or string.format("\\u%04x", string.byte(char))
    end)
    return replaced
end

local function number(value: number): string?
    if value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    if value % 1 == 0 and math.abs(value) < 1e15 then
        return string.format("%d", value)
    end
    local text = string.format("%.3f", value)
    -- Trim trailing zeros: "1.500" -> "1.5".
    local trimmed = string.gsub(text, "0+$", "")
    trimmed = string.gsub(trimmed, "%.$", "")
    return trimmed
end

--- `[JOINPROBE] {"a":1,"b":"x"}`; non-finite numbers are dropped, never printed as nan.
function ProbeLine.format(fields: Fields): string
    local keys: { string } = {}
    for key in fields do
        table.insert(keys, key)
    end
    table.sort(keys)
    local parts: { string } = {}
    for _, key in keys do
        local value = fields[key]
        local encoded: string? = nil
        if type(value) == "number" then
            encoded = number(value)
        elseif type(value) == "boolean" then
            encoded = if value then "true" else "false"
        else
            encoded = '"' .. escape(value) .. '"'
        end
        if encoded ~= nil then
            table.insert(parts, '"' .. escape(key) .. '":' .. encoded)
        end
    end
    return ProbeLine.PREFIX .. " {" .. table.concat(parts, ",") .. "}"
end

return ProbeLine
