--!strict
--[[
    Lune entry point: puts the code of the current branch into a local copy of the shared place,
    keeping the world, so a branch is tested in Studio without connecting Rojo by hand.

        lune run scripts/merge-into-copy <copy.rbxl> <out.rbxl> [project.json]

    Builds the project with `rojo build`, then replaces in the copy every container the project maps
    with $path (scripts/ProjectContainers, pure and tested). Everything else in the copy stays as the
    builders left it. Open <out.rbxl> in Studio and test it through the Studio MCP.
    Procedure: docs/live-vs-branches.md, "Test your branch in Studio".
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local ProjectContainers = require("./ProjectContainers")

local copyPath, outPath = process.args[1], process.args[2]
local projectPath = process.args[3] or "default.project.json"
if copyPath == nil or outPath == nil then
    print("usage: lune run scripts/merge-into-copy <copy.rbxl> <out.rbxl> [project.json]")
    process.exit(2)
end
if not fs.isFile(copyPath) then
    print(`merge-into-copy: no copy at {copyPath}; get it first (docs/live-vs-branches.md)`)
    process.exit(1)
end

local ok, result = ProjectContainers.from(serde.decode("json", fs.readFile(projectPath)).tree)
if not ok then
    print(`merge-into-copy: {result}`)
    process.exit(1)
end
local containers = result :: { ProjectContainers.Path }

local codePath = outPath .. ".code.rbxl"
local build = process.exec("rojo", { "build", projectPath, "-o", codePath })
if not build.ok then
    print(`merge-into-copy: rojo build failed: {build.stderr}`)
    process.exit(1)
end

local copy = roblox.deserializePlace(fs.readFile(copyPath))
local code = roblox.deserializePlace(fs.readFile(codePath))

-- The instance at path[1..depth] of a place; path[1] is a service.
local function at(place: any, path: ProjectContainers.Path, depth: number): any?
    local node = place:GetService(path[1])
    for i = 2, depth do
        if node == nil then
            return nil
        end
        node = node:FindFirstChild(path[i])
    end
    return node
end

for _, path in containers do
    local name = table.concat(path, ".")
    if at(code, path, #path) == nil then
        print(`merge-into-copy: the build has no {name}`)
        process.exit(1)
    end
    -- Deepest ancestor the copy already has (path[1] is a service, so depth 1 always exists).
    -- A folder the copy lacks comes from the build with everything it holds.
    local depth = #path - 1
    while depth > 1 and at(copy, path, depth) == nil do
        depth -= 1
    end
    local parent = assert(at(copy, path, depth), `the copy has no {path[1]}`)
    local incoming = assert(at(code, path, depth + 1), `the build has no {name}`)
    local old = parent:FindFirstChild(path[depth + 1])
    if old ~= nil then
        old:Destroy()
    end
    incoming:Clone().Parent = parent
    print(`code  {name}`)
end

fs.writeFile(outPath, roblox.serializePlace(copy))
fs.removeFile(codePath)
print(`merge-into-copy: wrote {outPath} (world from {copyPath}, code from {projectPath})`)
