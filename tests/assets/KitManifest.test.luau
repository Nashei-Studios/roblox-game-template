--!strict
local KitManifest = require("../../src/shared/assets/KitManifest")
local harness = require("../harness")
local manifest = require("../../assets/kits.manifest")

type Overrides = {
    slug: string?,
    ships: string?,
    sha256: string?,
    license: string?,
    libraryPath: string?,
    rojoPath: string?,
    noSha: boolean?,
    noRojo: boolean?,
}

local function kit(overrides: Overrides?): KitManifest.Kit
    local o: Overrides = overrides or {}
    return {
        slug = o.slug or "demo-kit",
        version = nil,
        ships = o.ships or "yes",
        sha256 = if o.noSha then nil else o.sha256 or string.rep("a", 64),
        license = o.license or "CC0-1.0",
        libraryPath = o.libraryPath or "demo-kit",
        rojoPath = if o.noRojo then nil else o.rojoPath or "assets/kits/demo-kit",
    }
end

local function failuresFor(overrides: Overrides?): { string }
    return KitManifest.validate({ kit(overrides) })
end

return function(suite: harness.Harness)
    suite:test("accepts a well-formed kit", function()
        harness.equal(#failuresFor(), 0)
    end)

    suite:test("the shipped manifest is valid", function()
        local failures = KitManifest.validate(manifest)
        harness.equal(#failures, 0, table.concat(failures, "; "))
        harness.isTrue(#manifest > 0, "manifest is not empty")
    end)

    suite:test("rejects a bad slug, bad ships value and empty license", function()
        harness.equal(#failuresFor({ slug = "Demo Kit", rojoPath = "assets/kits/Demo Kit" }), 1)
        harness.equal(#failuresFor({ ships = "maybe" }), 1)
        harness.equal(#failuresFor({ license = "" }), 1)
    end)

    suite:test("rejects a malformed sha256 but allows none", function()
        harness.equal(#failuresFor({ sha256 = "XYZ" }), 1)
        harness.equal(#failuresFor({ sha256 = string.rep("A", 64) }), 1)
        harness.equal(#failuresFor({ noSha = true }), 0)
    end)

    suite:test("rejects a library path that is absolute or leaves the kit library", function()
        harness.equal(#failuresFor({ libraryPath = "C:/tmp/demo-kit" }), 1)
        harness.equal(#failuresFor({ libraryPath = "/home/someone/kits/demo-kit" }), 1)
        harness.equal(#failuresFor({ libraryPath = "../demo-kit" }), 1)
        harness.equal(#failuresFor({ libraryPath = "" }), 1)
        harness.equal(#failuresFor({ libraryPath = "packs/demo-kit" }), 0)
    end)

    suite:test("ties rojoPath to ships", function()
        harness.equal(#failuresFor({ noRojo = true }), 1)
        harness.equal(#failuresFor({ ships = "no" }), 1)
        harness.equal(#failuresFor({ ships = "no", noRojo = true }), 0)
        harness.equal(#failuresFor({ rojoPath = "assets/elsewhere/demo-kit" }), 1)
    end)

    suite:test("rejects duplicate slugs", function()
        local failures = KitManifest.validate({ kit(), kit() })
        harness.equal(#failures, 1)
        harness.isTrue(string.find(failures[1], "duplicate", 1, true) ~= nil, "names the problem")
    end)
end
