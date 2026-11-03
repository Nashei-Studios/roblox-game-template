--!strict
local GreenhouseData = require("../../../src/shared/features/greenhouse/GreenhouseData")
local PlotLayout = require("../../../src/shared/features/greenhouse/PlotLayout")
local harness = require("../../harness")

local function overlaps(a: PlotLayout.Part, b: PlotLayout.Part): boolean
    return math.abs(a.x - b.x) < (a.sizeX + b.sizeX) / 2
        and math.abs(a.z - b.z) < (a.sizeZ + b.sizeZ) / 2
end

local function ofKind(parts: { PlotLayout.Part }, kind: PlotLayout.PartKind): { PlotLayout.Part }
    local found: { PlotLayout.Part } = {}
    for _, part in parts do
        if part.kind == kind then
            table.insert(found, part)
        end
    end
    return found
end

return function(suite: harness.Harness)
    suite:test("there is one floor, one spawn and one parcel per possible plot", function()
        local parts = PlotLayout.build(GreenhouseData.ABSOLUTE_MAX_PLOTS)
        harness.equal(#ofKind(parts, "floor"), 1, "floor")
        harness.equal(#ofKind(parts, "spawn"), 1, "spawn")
        harness.equal(#ofKind(parts, "parcel"), GreenhouseData.ABSOLUTE_MAX_PLOTS, "parcels")
    end)

    suite:test("parcels are numbered 1..n exactly once", function()
        local seen: { [number]: boolean } = {}
        for _, parcel in ofKind(PlotLayout.build(10), "parcel") do
            harness.isFalse(seen[parcel.plot], "duplicate plot number")
            seen[parcel.plot] = true
        end
        for plot = 1, 10 do
            harness.isTrue(seen[plot], `plot {plot} exists`)
        end
    end)

    suite:test("no two parcels overlap and none touches the spawn pad", function()
        local parts = PlotLayout.build(10)
        local parcels = ofKind(parts, "parcel")
        for first = 1, #parcels do
            for second = first + 1, #parcels do
                harness.isFalse(overlaps(parcels[first], parcels[second]), "parcel overlap")
            end
        end
        local spawn = ofKind(parts, "spawn")[1]
        for _, parcel in parcels do
            harness.isFalse(overlaps(parcel, spawn), "spawn overlap")
        end
    end)

    suite:test("every parcel and the spawn pad stand inside the floor", function()
        local parts = PlotLayout.build(10)
        local floor = ofKind(parts, "floor")[1]
        for _, part in parts do
            if part.kind ~= "floor" then
                harness.isTrue(
                    math.abs(part.x - floor.x) + part.sizeX / 2 <= floor.sizeX / 2,
                    "inside floor in x"
                )
                harness.isTrue(
                    math.abs(part.z - floor.z) + part.sizeZ / 2 <= floor.sizeZ / 2,
                    "inside floor in z"
                )
            end
        end
    end)

    suite:test("the first parcel is the nearest to the spawn pad", function()
        local parts = PlotLayout.build(10)
        local spawn = ofKind(parts, "spawn")[1]
        local parcels = ofKind(parts, "parcel")
        local first = parcels[1]
        for _, parcel in parcels do
            harness.isTrue(
                math.abs(first.z - spawn.z) <= math.abs(parcel.z - spawn.z),
                "plot 1 is in the front row"
            )
        end
    end)

    suite:test("a single plot still builds a floor wide enough for it", function()
        local parts = PlotLayout.build(1)
        harness.equal(#ofKind(parts, "parcel"), 1, "parcel")
        harness.isTrue(ofKind(parts, "floor")[1].sizeX >= PlotLayout.PARCEL_SIZE, "floor width")
    end)
end
