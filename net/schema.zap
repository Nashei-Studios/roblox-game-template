opt server_output = "../src/shared/net/generated/server.luau"
opt client_output = "../src/shared/net/generated/client.luau"
opt types_output = "../src/shared/net/generated/types.luau"
opt casing = "camelCase"
opt write_checks = true

-- Product names mirror Config.default.developerProducts. Keep both in sync (see docs/architecture.md).
type ProductName = enum { "Coins100", "BaitPack" }

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

-- Reef (ADR 0021). Client -> server events carry INTENT only: the server owns the catch roll,
-- the bite time, the reel window, prices and coins. Every event needs an entry in PerfBudget (ADR 0019).

-- Fish ids mirror ReefConfig.default zones; FishWire (typed against this enum) and its test keep them in sync.
type FishName = enum { "minnow", "sardine", "perch", "mackerel", "snapper", "grouper", "tuna", "swordfish", "marlin" }

-- Cast into water zone `zone` (1 = shallow). The server refuses a zone the rod does not reach.
event Cast = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (zone: u8),
}

-- Reel in. No payload: the server judges the moment against its own clock.
event Reel = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (),
}

-- Sell the whole bucket. No payload: the server derives every value.
event Sell = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (),
}

-- Buy the next rod. No payload: the server derives the price from the saved level.
event BuyRod = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (),
}

-- Server -> client. The fish is biting: reel now (the window is short).
event Bite = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (),
}

-- Server -> client. The outcome of a reel: the fish landed, or nil when it got away.
event CatchResult = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (fish: FishName?),
}

-- Server -> client. Fish in the bucket and its capacity.
event StockChanged = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (count: u8, capacity: u8),
}

-- Server -> client. The rod level after a purchase or at join.
event RodChanged = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (rodLevel: u8),
}
