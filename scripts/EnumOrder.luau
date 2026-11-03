--!strict
--[[
    Deterministic order for the enum aliases Zap emits (issue #10).
    Zap v0.6.29 writes the single-line `export type <Name> = (...)` lines in an order that changes
    between runs, so `git diff --exit-code` in CI gives false reds. `normalize` sorts every
    contiguous block of those lines by type name and touches nothing else.
    Pure and runtime-neutral: loads under Lune and the Luau CLI.
]]

local EnumOrder = {}

local function enumName(line: string): string?
    return string.match(line, "^export type ([%w_]+) = %(.*%)$")
end

--- Sorts each contiguous block of single-line enum aliases by type name; other lines stay put.
function EnumOrder.normalize(text: string): string
    local lines = string.split(text, "\n")
    local output: { string } = {}
    local block: { { name: string, line: string } } = {}

    local function flush()
        table.sort(block, function(a, b)
            return a.name < b.name
        end)
        for _, entry in block do
            table.insert(output, entry.line)
        end
        table.clear(block)
    end

    for _, line in lines do
        local name = enumName(line)
        if name ~= nil then
            table.insert(block, { name = name, line = line })
        else
            flush()
            table.insert(output, line)
        end
    end
    flush()
    return table.concat(output, "\n")
end

return EnumOrder
