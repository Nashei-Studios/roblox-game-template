opt server_output = "../src/shared/net/generated/server.luau"
opt client_output = "../src/shared/net/generated/client.luau"
opt types_output = "../src/shared/net/generated/types.luau"
opt casing = "camelCase"
opt write_checks = true

-- Product names mirror Config.default.developerProducts. Keep both in sync (see docs/architecture.md).
type ProductName = enum { "Coins100" }

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

-- Key sprint (ADR 0020). Client -> server events carry INTENT only: the server owns the multiplier,
-- walk speed, prices, rewards and stage progress. Every event needs an entry in PerfBudget (ADR 0019).

-- A batch of key presses since the last batch (1..12 is enforced by the server, ChargeMeter).
event PressBatch = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (presses: u8),
}

-- The client touched the finish line of `stage`. The server checks the active run, the unlock and
-- the minimum plausible time (StageRuns) before paying anything.
event Finish = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (stage: u8),
}

-- Buy the next multiplier cap. No payload: the server derives the price from the saved cap.
event BuyCap = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (),
}

-- Ask to open the Skip stage purchase prompt. No payload: the product is fixed.
event SkipStage = {
	from: Client,
	type: Reliable,
	call: SingleSync,
	data: (),
}

-- Server -> client. The authoritative multiplier and the player's cap, for the meter only.
event MultiplierChanged = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (multiplier: f32, multiplierCap: u8),
}

-- Server -> client. Saved progress: last stage cleared and the multiplier cap.
event ProgressChanged = {
	from: Server,
	type: Reliable,
	call: SingleSync,
	data: (highestStage: u8, multiplierCap: u8),
}
