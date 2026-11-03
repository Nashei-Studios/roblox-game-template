opt server_output = "../src/shared/net/generated/server.luau"
opt client_output = "../src/shared/net/generated/client.luau"
opt types_output = "../src/shared/net/generated/types.luau"
opt casing = "camelCase"
opt write_checks = true

-- Product names mirror Config.default.developerProducts. Keep both in sync (see docs/architecture.md).
type ProductName = enum { "Coins100", "SeedBundle" }

-- Client -> server. Carries intent only (ADR 0012): the server re-derives price, id and grant.
event RequestPurchase = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (product: ProductName),
}

-- Server -> client. The balance after a grant, clamped to u32 by the sender.
event CoinsChanged = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (coins: u32),
}

-- Greenhouse (ADR 0020). Client -> server events carry INTENT only: the server owns the clock,
-- every timer, price, stock and the coins. Every event needs an entry in PerfBudget (ADR 0019).
-- Crop and pass names mirror GreenhouseData (crop ids, PASS_* names).
type CropName = enum { "radish", "carrot", "pumpkin" }
type PassName = enum { "ExtraPlots", "AutoHarvest" }

-- Plant `crop` in plot number `plot` (1-based). The server stamps readyAt from its own clock.
event Plant = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (plot: u8, crop: CropName),
}

-- Harvest plot number `plot`. The server refuses it until its own clock reaches readyAt.
event Harvest = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (plot: u8),
}

-- Sell all produce. No payload: prices come from the server data table.
event Sell = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (),
}

-- Buy the next plot. No payload: the server derives the price from the saved plot count.
event BuyPlot = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (),
}

-- Buy one seed of `crop` with coins.
event BuySeed = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (crop: CropName),
}

-- Harvest and replant every ready plot. The server checks the AutoHarvest pass itself.
event AutoHarvest = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (),
}

-- Ask to open the purchase prompt of a game pass. The server prompts; ownership is read from Roblox.
event RequestPass = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (pass: PassName),
}

-- Server -> client. State of one plot. crop 0 = empty. readyAt is server time (Unix seconds); the
-- client only draws a countdown from it (workspace:GetServerTimeNow()) and decides nothing.
event PlotChanged = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (plot: u8, crop: u8, readyAt: u32),
}

-- Server -> client. Seeds and unsold produce of one crop (crop = the 1-based wire index).
event StockChanged = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (crop: u8, seeds: u16, produce: u16),
}

-- Server -> client. Which passes the player owns, as the server read them from Roblox.
event PassChanged = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (extraPlots: boolean, autoHarvest: boolean),
}
