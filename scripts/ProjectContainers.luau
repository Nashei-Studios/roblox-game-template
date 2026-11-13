--!strict
--[[
    Pure: which instances of a Rojo project are code. Every node of the project tree with a
    "$path" maps a folder or file of the repo; that node is replaced as a whole when the code of a
    branch goes into a local copy of the shared place (scripts/merge-into-copy.luau). Nothing else
    in the copy is touched, so the world the builders made stays. Read by tests/scripts.
]]

export type Path = { string }

local ProjectContainers = {}

local function walk(node: { [string]: any }, path: Path, out: { Path })
    local keys: { string } = {}
    for key, child in node do
        if type(key) == "string" and string.sub(key, 1, 1) ~= "$" and type(child) == "table" then
            table.insert(keys, key)
        end
    end
    table.sort(keys) -- stable order, so two runs print the same report
    for _, key in keys do
        local child = node[key]
        local here = table.clone(path)
        table.insert(here, key)
        if child["$path"] ~= nil then
            table.insert(out, here)
        else
            walk(child, here, out)
        end
    end
end

-- Paths from the DataModel to every code container, or an error a person can act on.
function ProjectContainers.from(tree: { [string]: any }): (boolean, { Path } | string)
    if type(tree) ~= "table" then
        return false, "the project has no tree"
    end
    local out: { Path } = {}
    walk(tree, {}, out)
    for _, path in out do
        if #path < 2 then
            return false,
                `"{path[1]}" maps a whole service with $path; map a child of it so the copy keeps the rest`
        end
    end
    if #out == 0 then
        return false,
            "the project maps no folder or file ($path): there is no code to put in the copy"
    end
    return true, out
end

return ProjectContainers
